import { createServer, type IncomingMessage, type Server } from "node:http";
import { createHmac, randomBytes, timingSafeEqual } from "node:crypto";
import { WebSocketServer, type WebSocket } from "ws";
import { fail, ok, parseMessage } from "./jsonRpc.js";
import { projectIdentityHash } from "./projectIdentity.js";
import type { HostController } from "./hostController.js";
import type { HostEvent, JsonRpcRequest } from "./types.js";

const MAX_MESSAGE_BYTES = 1024 * 1024;
const DEFAULT_BRIDGE_RPC_TIMEOUT_MS = 5_000;
const MAX_UNPAIRED_CLIENTS = 8;
type JsonObject = Record<string, unknown>;

export class GodotSocketServer {
  private httpServer: Server | null = null;
  private server: WebSocketServer | null = null;
  private readonly clients = new Set<WebSocket>();
  private pairedClient: WebSocket | null = null;
  // Godot answers pings only while its editor loop runs, so a paired editor
  // stalled by a long import looks silent too. Never drop it on silence alone
  // (re-pairing needs the secret again); only a new connection may replace a
  // paired socket that has missed pongs. Unpaired sockets must pair promptly.
  heartbeatIntervalMs = 15_000;
  pairingDeadlineMs = 30_000;
  private heartbeatTimer: NodeJS.Timeout | null = null;
  private readonly missedPongs = new Map<WebSocket, number>();
  private readonly connectedAt = new Map<WebSocket, number>();
  private readonly pairingAttempts = new Map<WebSocket, number>();
  private readonly pairingChallenges = new Map<WebSocket, { clientNonce: string; serverNonce: string; expiresAt: number }>();
  private readonly pendingBridgeRequests = new Map<string, {
    resolve: (value: unknown) => void;
    reject: (error: Error) => void;
    timer: NodeJS.Timeout;
    client: WebSocket;
  }>();

  constructor(
    private readonly host: string,
    private readonly port: number,
    private readonly controller: HostController,
    private readonly launchNonce = "",
    private readonly pairingSecret = randomBytes(32).toString("hex")
  ) {
    if (!/^[a-f0-9]{64}$/.test(pairingSecret)) {
      throw new Error("Host pairing secret must be 64 lowercase hex characters.");
    }
  }

  async start(): Promise<void> {
    if (this.server) {
      return;
    }
    // This is a native local IPC service, not a browser or LAN API.
    if (this.host !== "127.0.0.1" && this.host !== "::1") {
      throw new Error("Codex Host must bind to a numeric loopback address (127.0.0.1 or ::1).");
    }
    this.httpServer = createServer((request, response) => {
      if (!this.isAllowedRequest(request)) {
        response.writeHead(403, { "content-type": "application/json" });
        response.end(JSON.stringify({ error: "local_client_required" }));
        return;
      }
      void (async () => {
        if (request.url === "/health" && request.method === "GET") {
          response.writeHead(200, { "content-type": "application/json" });
          response.end(JSON.stringify({
            ok: true,
            runtime: this.controller.status().runtime,
            port: this.addressPort(),
            ...this.projectIdentity(),
            ...(this.launchNonce ? { launch_proof: createHmac("sha256", Buffer.from(this.launchNonce, "hex")).update("godot-codex-bridge-host-health-v1").digest("hex") } : {})
          }));
          return;
        }
        if (request.url === "/bridge/request" && request.method === "POST") {
          // The MCP process is not an authenticated addon. File polling remains
          // available until a separately authenticated request transport exists.
          response.writeHead(503, { "content-type": "application/json" });
          response.end(JSON.stringify({ status: "error", error: { code: "bridge_rpc_unavailable", message: "Use project-scoped request files." } }));
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
      server: this.httpServer,
      maxPayload: MAX_MESSAGE_BYTES,
      verifyClient: ({ req }: { req: IncomingMessage }) => this.isAllowedRequest(req)
    });
    this.server.on("connection", (socket) => this.onConnection(socket));
    this.controller.on("event", (event: HostEvent) => this.broadcast(event));
    this.heartbeatTimer = setInterval(() => this.checkHeartbeats(), this.heartbeatIntervalMs);
    this.heartbeatTimer.unref();
  }

  private checkHeartbeats(): void {
    const now = Date.now();
    for (const client of this.clients) {
      const missed = this.missedPongs.get(client) ?? 0;
      if (client !== this.pairedClient &&
        (missed >= 1 || now - (this.connectedAt.get(client) ?? now) > this.pairingDeadlineMs)) {
        client.terminate();
        continue;
      }
      this.missedPongs.set(client, missed + 1);
      client.ping();
    }
  }

  async stop(): Promise<void> {
    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = null;
    }
    this.missedPongs.clear();
    this.connectedAt.clear();
    for (const pending of this.pendingBridgeRequests.values()) {
      clearTimeout(pending.timer);
      pending.reject(new Error("bridge_rpc_server_stopping"));
    }
    this.pendingBridgeRequests.clear();
    for (const client of this.clients) {
      client.terminate();
    }
    this.clients.clear();
    this.pairedClient = null;
    this.pairingAttempts.clear();
    this.pairingChallenges.clear();
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

  /** Hashes only: enough for the MCP server to detect a mismatch, not to learn the path. */
  private projectIdentity(): Record<string, unknown> {
    const project = this.controller.status().activeProject;
    if (!project) return {};
    return {
      project_identity: {
        project_root_sha256: projectIdentityHash(project.projectRoot),
        bridge_dir_sha256: projectIdentityHash(project.bridgeDir)
      }
    };
  }

  private isAllowedRequest(request: IncomingMessage): boolean {
    // Reject browser origins (including "null") and DNS-rebinding Host names
    // before exposing status or dispatching any RPC. Native Godot/Node clients
    // send neither Origin nor Fetch Metadata headers.
    if (request.headers.origin !== undefined || request.headers["sec-fetch-site"] !== undefined) {
      return false;
    }
    const port = this.addressPort();
    return [`127.0.0.1:${port}`, `[::1]:${port}`, `localhost:${port}`].includes(request.headers.host ?? "");
  }

  private onConnection(socket: WebSocket): void {
    if (this.controller.isShuttingDown()) {
      socket.close(1013, "host_shutting_down");
      return;
    }
    if (this.pairedClient && this.pairedClient.readyState === this.pairedClient.OPEN) {
      // Two unanswered pings: treat the paired socket as half-open so the
      // reconnecting addon is not locked out until TCP notices.
      if ((this.missedPongs.get(this.pairedClient) ?? 0) < 2) {
        socket.close(1008, "addon_already_paired");
        return;
      }
      this.pairedClient.terminate();
    }
    if (this.clients.size - (this.pairedClient ? 1 : 0) >= MAX_UNPAIRED_CLIENTS) {
      socket.close(1013, "too_many_unpaired_clients");
      return;
    }
    this.clients.add(socket);
    this.connectedAt.set(socket, Date.now());
    // ws emits an error before closing oversized/malformed frames. Handle it
    // locally so an untrusted frame cannot crash the host process.
    socket.on("error", () => socket.terminate());
    socket.on("pong", () => this.missedPongs.delete(socket));
    socket.on("close", () => {
      this.clients.delete(socket);
      this.missedPongs.delete(socket);
      this.connectedAt.delete(socket);
      this.pairingAttempts.delete(socket);
      this.pairingChallenges.delete(socket);
      if (this.pairedClient === socket) {
        this.pairedClient = null;
        for (const [id, pending] of this.pendingBridgeRequests) {
          if (pending.client !== socket) continue;
          clearTimeout(pending.timer);
          this.pendingBridgeRequests.delete(id);
          pending.reject(new BridgeHttpError(503, "addon_disconnected", "Paired addon disconnected."));
        }
      }
    });
    socket.on("message", (raw) => void this.onMessage(socket, raw));
    socket.send(JSON.stringify({
      jsonrpc: "2.0",
      method: "host.pair_required",
      params: { protocol: "godot-codex-bridge/pair-v2" }
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

    if (request.method === "host.pair") {
      if (request.id === undefined) {
        socket.send(JSON.stringify(fail(null, -32600, "pair_request_id_required")));
        return;
      }
      if (this.pairedClient && this.pairedClient !== socket) {
        socket.send(JSON.stringify(fail(request.id, -32003, "addon_already_paired")));
        socket.close(1008, "addon_already_paired");
        return;
      }
      if (this.pairedClient === socket || this.pairingChallenges.has(socket)) {
        socket.send(JSON.stringify(fail(request.id, -32003, "pairing_in_progress")));
        return;
      }
      const clientNonce = isJsonObject(request.params) ? request.params.client_nonce : undefined;
      if (typeof clientNonce !== "string" || !/^[a-f0-9]{64}$/.test(clientNonce)) {
        const attempts = (this.pairingAttempts.get(socket) ?? 0) + 1;
        this.pairingAttempts.set(socket, attempts);
        socket.send(JSON.stringify(fail(request.id, -32003, "invalid_pairing_nonce")));
        if (attempts >= 5) socket.close(1008, "pairing_failed");
        return;
      }
      const serverNonce = randomBytes(32).toString("hex");
      this.pairingChallenges.set(socket, { clientNonce, serverNonce, expiresAt: Date.now() + 30_000 });
      socket.send(JSON.stringify(ok(request.id, {
        server_nonce: serverNonce,
        server_proof: pairProof(this.pairingSecret, `host:${clientNonce}:${serverNonce}`)
      })));
      return;
    }
    if (request.method === "host.pair_complete") {
      if (request.id === undefined) {
        socket.send(JSON.stringify(fail(null, -32600, "pair_request_id_required")));
        return;
      }
      const challenge = this.pairingChallenges.get(socket);
      this.pairingChallenges.delete(socket);
      const rawProof = isJsonObject(request.params) ? request.params.client_proof : undefined;
      const expectedProof = challenge
        ? pairProof(this.pairingSecret, `addon:${challenge.clientNonce}:${challenge.serverNonce}`)
        : "";
      const candidate = typeof rawProof === "string" && /^[a-f0-9]{64}$/.test(rawProof) ? Buffer.from(rawProof, "hex") : Buffer.alloc(0);
      const expected = expectedProof ? Buffer.from(expectedProof, "hex") : Buffer.alloc(0);
      if (this.pairedClient || !challenge || challenge.expiresAt < Date.now() || candidate.length !== expected.length || !timingSafeEqual(candidate, expected)) {
        socket.send(JSON.stringify(fail(request.id, -32003, "pairing_failed")));
        socket.close(1008, "pairing_failed");
        return;
      }
      this.pairedClient = socket;
      this.pairingAttempts.delete(socket);
      socket.send(JSON.stringify(ok(request.id, { paired: true })));
      socket.send(JSON.stringify({ jsonrpc: "2.0", method: "host.status", params: this.controller.status() }));
      return;
    }
    if (socket !== this.pairedClient) {
      if (request.id !== undefined) socket.send(JSON.stringify(fail(request.id, -32003, "pairing_required")));
      return;
    }

    if (request.method === "bridge.addon_response") {
      this.handleBridgeResponse(socket, request.params as JsonObject);
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
    const client = this.pairedClient;
    if (client && client.readyState === client.OPEN) {
      client.send(text);
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

    const client = this.pairedClient;
    if (!client || client.readyState !== client.OPEN) {
      throw new BridgeHttpError(409, "addon_not_connected", "No Godot addon WebSocket client is connected.");
    }

    const timeoutMs = boundedTimeout(body.timeout_ms);
    const responsePromise = new Promise<unknown>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pendingBridgeRequests.delete(requestId);
        reject(new BridgeHttpError(504, "bridge_rpc_timeout", `Timed out waiting ${timeoutMs}ms for Godot addon RPC response.`));
      }, timeoutMs);
      timer.unref();
      this.pendingBridgeRequests.set(requestId, { resolve, reject, timer, client });
    });

    const message = JSON.stringify({
      jsonrpc: "2.0",
      method: "bridge.addon_request",
      params: {
        request_id: requestId,
        request
      }
    });
    client.send(message);

    return responsePromise;
  }

  private handleBridgeResponse(socket: WebSocket, params: JsonObject | undefined): void {
    if (!isJsonObject(params)) {
      return;
    }
    const requestId = typeof params.request_id === "string" ? params.request_id : "";
    const pending = this.pendingBridgeRequests.get(requestId);
    if (!pending || pending.client !== socket || socket !== this.pairedClient) {
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

function pairProof(secret: string, message: string): string {
  return createHmac("sha256", Buffer.from(secret, "hex")).update(message, "utf8").digest("hex");
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
