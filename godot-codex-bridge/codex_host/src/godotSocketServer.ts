import { createServer, type IncomingMessage, type Server } from "node:http";
import { WebSocketServer, type WebSocket } from "ws";
import { fail, ok, parseMessage } from "./jsonRpc.js";
import type { HostController } from "./hostController.js";
import type { HostEvent, JsonRpcRequest } from "./types.js";

const MAX_MESSAGE_BYTES = 1024 * 1024;
const DEFAULT_BRIDGE_RPC_TIMEOUT_MS = 5_000;
type JsonObject = Record<string, unknown>;

export class GodotSocketServer {
  private httpServer: Server | null = null;
  private server: WebSocketServer | null = null;
  private readonly clients = new Set<WebSocket>();
  private readonly pendingBridgeRequests = new Map<string, {
    resolve: (value: unknown) => void;
    reject: (error: Error) => void;
    timer: NodeJS.Timeout;
  }>();

  constructor(
    private readonly host: string,
    private readonly port: number,
    private readonly controller: HostController
  ) {}

  async start(): Promise<void> {
    if (this.server) {
      return;
    }
    this.httpServer = createServer((request, response) => {
      void (async () => {
        if (request.url === "/health" && request.method === "GET") {
          response.writeHead(200, { "content-type": "application/json" });
          response.end(JSON.stringify(this.controller.status()));
          return;
        }
        if (request.url === "/bridge/request" && request.method === "POST") {
          const body = await readJsonBody(request);
          const result = await this.forwardBridgeRequest(body);
          response.writeHead(200, { "content-type": "application/json" });
          response.end(JSON.stringify(result));
          return;
        }
        response.writeHead(404, { "content-type": "application/json" });
        response.end(JSON.stringify({ error: "not_found" }));
      })().catch((error) => {
        const statusCode = error instanceof BridgeHttpError ? error.statusCode : 500;
        response.writeHead(statusCode, { "content-type": "application/json" });
        response.end(JSON.stringify({
          status: "error",
          error: {
            code: error instanceof BridgeHttpError ? error.code : "bridge_http_error",
            message: (error as Error).message
          }
        }));
      });
    });
    await new Promise<void>((resolve, reject) => {
      this.httpServer?.once("listening", resolve);
      this.httpServer?.once("error", reject);
      this.httpServer?.listen(this.port, this.host);
    });
    this.server = new WebSocketServer({
      server: this.httpServer
    });
    this.server.on("connection", (socket) => this.onConnection(socket));
    this.controller.on("event", (event: HostEvent) => this.broadcast(event));
  }

  async stop(): Promise<void> {
    for (const pending of this.pendingBridgeRequests.values()) {
      clearTimeout(pending.timer);
      pending.reject(new Error("bridge_rpc_server_stopping"));
    }
    this.pendingBridgeRequests.clear();
    for (const client of this.clients) {
      client.terminate();
    }
    this.clients.clear();
    if (!this.server) {
      return;
    }
    await new Promise<void>((resolve) => this.server?.close(() => resolve()));
    this.server = null;
    if (this.httpServer) {
      await new Promise<void>((resolve) => this.httpServer?.close(() => resolve()));
      this.httpServer = null;
    }
  }

  addressPort(): number {
    const address = this.httpServer?.address();
    if (!address || typeof address === "string") {
      return this.port;
    }
    return address.port;
  }

  private onConnection(socket: WebSocket): void {
    this.clients.add(socket);
    socket.on("close", () => this.clients.delete(socket));
    socket.on("message", (raw) => void this.onMessage(socket, raw));
    socket.send(JSON.stringify({
      jsonrpc: "2.0",
      method: "host.status",
      params: this.controller.status()
    }));
  }

  private async onMessage(socket: WebSocket, raw: Buffer | ArrayBuffer | Buffer[]): Promise<void> {
    const text = Buffer.isBuffer(raw) ? raw.toString("utf8") : String(raw);
    if (Buffer.byteLength(text, "utf8") > MAX_MESSAGE_BYTES) {
      socket.send(JSON.stringify(fail(null, -32001, "message_too_large")));
      return;
    }

    let request: JsonRpcRequest;
    try {
      request = parseMessage(text) as JsonRpcRequest;
      if (!request || typeof request.method !== "string") {
        throw new Error("method_required");
      }
    } catch (error) {
      socket.send(JSON.stringify(fail(null, -32700, (error as Error).message)));
      return;
    }

    if (request.method === "bridge.addon_response") {
      this.handleBridgeResponse(request.params as JsonObject);
      return;
    }

    try {
      const result = await this.controller.handleRequest(request);
      if (request.id !== undefined) {
        socket.send(JSON.stringify(ok(request.id, result)));
      }
    } catch (error) {
      if (request.id !== undefined) {
        socket.send(JSON.stringify(fail(request.id, -32000, (error as Error).message)));
      }
    }
  }

  private broadcast(event: HostEvent): void {
    const text = JSON.stringify(event);
    for (const client of this.clients) {
      if (client.readyState === client.OPEN) {
        client.send(text);
      }
    }
  }

  private async forwardBridgeRequest(body: JsonObject): Promise<unknown> {
    const activeProject = this.controller.status().activeProject;
    if (!activeProject) {
      throw new BridgeHttpError(409, "project_not_attached", "No Godot project is attached to Codex Host.");
    }
    if (typeof body.project_root === "string" && body.project_root !== activeProject.projectRoot) {
      throw new BridgeHttpError(409, "project_mismatch", "Requested project root does not match the attached project.");
    }
    if (typeof body.bridge_dir === "string" && body.bridge_dir !== activeProject.bridgeDir) {
      throw new BridgeHttpError(409, "bridge_dir_mismatch", "Requested bridge dir does not match the attached project.");
    }
    const request = body.request;
    if (!isJsonObject(request)) {
      throw new BridgeHttpError(400, "request_required", "Bridge RPC body requires a request object.");
    }
    const requestId = typeof request.request_id === "string" ? request.request_id : "";
    if (!requestId) {
      throw new BridgeHttpError(400, "request_id_required", "Bridge RPC request requires request_id.");
    }
    if (this.pendingBridgeRequests.has(requestId)) {
      throw new BridgeHttpError(409, "request_id_conflict", `Bridge RPC request_id is already pending: ${requestId}`);
    }

    const openClients = [...this.clients].filter((client) => client.readyState === client.OPEN);
    if (openClients.length === 0) {
      throw new BridgeHttpError(409, "addon_not_connected", "No Godot addon WebSocket client is connected.");
    }

    const timeoutMs = boundedTimeout(body.timeout_ms);
    const responsePromise = new Promise<unknown>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pendingBridgeRequests.delete(requestId);
        reject(new BridgeHttpError(504, "bridge_rpc_timeout", `Timed out waiting ${timeoutMs}ms for Godot addon RPC response.`));
      }, timeoutMs);
      timer.unref();
      this.pendingBridgeRequests.set(requestId, { resolve, reject, timer });
    });

    const message = JSON.stringify({
      jsonrpc: "2.0",
      method: "bridge.addon_request",
      params: {
        request_id: requestId,
        request
      }
    });
    for (const client of openClients) {
      client.send(message);
    }

    return responsePromise;
  }

  private handleBridgeResponse(params: JsonObject | undefined): void {
    if (!isJsonObject(params)) {
      return;
    }
    const requestId = typeof params.request_id === "string" ? params.request_id : "";
    const pending = this.pendingBridgeRequests.get(requestId);
    if (!pending) {
      return;
    }
    clearTimeout(pending.timer);
    this.pendingBridgeRequests.delete(requestId);
    pending.resolve({
      status: "ok",
      transport: "websocket_rpc",
      request_id: requestId,
      response: params.response
    });
  }
}

class BridgeHttpError extends Error {
  constructor(
    readonly statusCode: number,
    readonly code: string,
    message: string
  ) {
    super(message);
  }
}

function boundedTimeout(value: unknown): number {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    return DEFAULT_BRIDGE_RPC_TIMEOUT_MS;
  }
  return Math.min(Math.max(Math.trunc(parsed), 250), 30_000);
}

function isJsonObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function readJsonBody(request: IncomingMessage): Promise<JsonObject> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    request.on("data", (chunk: Buffer) => {
      chunks.push(chunk);
      const size = chunks.reduce((sum, item) => sum + item.length, 0);
      if (size > MAX_MESSAGE_BYTES) {
        reject(new BridgeHttpError(413, "message_too_large", "Bridge RPC body exceeded the local message limit."));
        request.destroy();
      }
    });
    request.on("end", () => {
      try {
        const parsed = JSON.parse(Buffer.concat(chunks).toString("utf8")) as unknown;
        if (!isJsonObject(parsed)) {
          throw new BridgeHttpError(400, "invalid_json_body", "Bridge RPC body must be a JSON object.");
        }
        resolve(parsed);
      } catch (error) {
        reject(error);
      }
    });
    request.on("error", reject);
  });
}
