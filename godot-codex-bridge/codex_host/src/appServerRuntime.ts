import { spawn, type ChildProcess } from "node:child_process";
import crypto from "node:crypto";
import { existsSync } from "node:fs";
import fs from "node:fs/promises";
import path from "node:path";
import WebSocket from "ws";
import type { ServerNotification } from "../schemas/ServerNotification.js";
import type { ServerRequest } from "../schemas/ServerRequest.js";
import type { ConfigReadResponse } from "../schemas/v2/ConfigReadResponse.js";
import type { ListMcpServerStatusResponse } from "../schemas/v2/ListMcpServerStatusResponse.js";
import type { ModelListResponse } from "../schemas/v2/ModelListResponse.js";
import type { ThreadStartResponse } from "../schemas/v2/ThreadStartResponse.js";
import type { TurnStartResponse } from "../schemas/v2/TurnStartResponse.js";
import { AsyncQueue } from "./asyncQueue.js";
import { buildBridgeToolsRegistrationPlan } from "./bridgeToolsRegistration.js";
import type { CodexRuntimeAdapter, RuntimeSandboxMode, RuntimeThreadHandle, RuntimeThreadOptions, RuntimeTurnInput } from "./codexRuntime.js";
import { event } from "./codexRuntime.js";
import type {
  BridgeToolsEnableResult,
  BridgeToolsRegistrationPlan,
  HostEvent,
  JsonRpcId,
  ProjectSummary,
  RuntimeApprovalKind,
  RuntimeApprovalRequest,
  RuntimeModelInventory,
  RuntimeReasoningEffort,
  RuntimeReasoningEffortOption,
  RuntimeToolInventory
} from "./types.js";

type PendingRequest = {
  resolve: (value: unknown) => void;
  reject: (error: Error) => void;
  timer: NodeJS.Timeout;
};

type AppServerRuntimeOptions = {
  codexBin: string;
  host: string;
  port: number;
  backpressureLimit: number;
};

type RuntimeNotification =
  | ServerNotification
  | {
      method: "godot/approvalRequested";
      params: RuntimeApprovalRequest;
    };

type PendingServerRequest = {
  requestId: JsonRpcId;
  method: string;
  params: unknown;
};

function normalizeRuntimeReasoningEffort(value: unknown): RuntimeReasoningEffort | undefined {
  if (
    value === "none" ||
    value === "minimal" ||
    value === "low" ||
    value === "medium" ||
    value === "high" ||
    value === "xhigh"
  ) {
    return value;
  }
  return undefined;
}

export class AppServerRuntime implements CodexRuntimeAdapter {
  readonly kind = "app-server";
  private proc: ChildProcess | null = null;
  private socket: WebSocket | null = null;
  private nextId = 1;
  private initialized = false;
  private connectionPromise: Promise<void> | null = null;
  private readonly pending = new Map<JsonRpcId, PendingRequest>();
  private readonly pendingServerRequests = new Map<string, PendingServerRequest>();
  private readonly notifications = new AsyncQueue<RuntimeNotification>();
  private readonly turnDiffs = new Map<string, string>();
  private readonly itemDiffs = new Map<string, unknown>();
  private readonly itemPhases = new Map<string, string>();
  private shuttingDown = false;

  constructor(private readonly options: AppServerRuntimeOptions) {}

  createBackgroundRuntime(index: number): CodexRuntimeAdapter {
    return new AppServerRuntime({
      ...this.options,
      port: this.options.port + index + 1
    });
  }

  async inspectMcpTools(threadId?: string): Promise<RuntimeToolInventory> {
    await this.ensureConnected();
    const response = await this.request<ListMcpServerStatusResponse>("mcpServerStatus/list", {
      cursor: null,
      limit: 100,
      detail: "toolsAndAuthOnly",
      threadId: threadId ?? null
    });
    return summarizeMcpTools(response);
  }

  async listModels(): Promise<RuntimeModelInventory> {
    await this.ensureConnected();
    const response = await this.request<ModelListResponse>("model/list", {
      cursor: null,
      limit: 100,
      includeHidden: false
    });
    const models = (response.data ?? [])
      .filter((model) => !model.hidden)
      .map((model) => {
        const supportedReasoningEfforts = model.supportedReasoningEfforts
          .map((option): RuntimeReasoningEffortOption | null => {
            const reasoningEffort = normalizeRuntimeReasoningEffort(option.reasoningEffort);
            if (!reasoningEffort) {
              return null;
            }
            return {
              reasoningEffort,
              description: option.description
            };
          })
          .filter((option): option is RuntimeReasoningEffortOption => option !== null);
        return {
          id: model.id,
          model: model.model,
          displayName: model.displayName || model.model,
          description: model.description,
          hidden: model.hidden,
          isDefault: model.isDefault,
          inputModalities: Array.isArray(model.inputModalities) ? model.inputModalities : [],
          defaultReasoningEffort: normalizeRuntimeReasoningEffort(model.defaultReasoningEffort),
          supportedReasoningEfforts
        };
      });
    const reasoningByEffort = new Map<RuntimeReasoningEffort, RuntimeReasoningEffortOption>();
    for (const model of models) {
      for (const option of model.supportedReasoningEfforts) {
        reasoningByEffort.set(option.reasoningEffort, option);
      }
    }
    if (reasoningByEffort.size === 0) {
      for (const effort of ["minimal", "low", "medium", "high", "xhigh"] as RuntimeReasoningEffort[]) {
        reasoningByEffort.set(effort, { reasoningEffort: effort });
      }
    }
    return {
      models,
      defaultModel: models.find((model) => model.isDefault)?.model ?? models[0]?.model,
      reasoningEfforts: [...reasoningByEffort.values()],
      checkedAt: new Date().toISOString()
    };
  }

  async previewBridgeTools(project: ProjectSummary): Promise<BridgeToolsRegistrationPlan> {
    const plan = buildBridgeToolsRegistrationPlan(project);
    try {
      const existing = await this.readExistingBridgeToolsConfig(plan.serverName, project.projectRoot);
      return withExistingConfig(plan, existing);
    } catch (error) {
      return {
        ...plan,
        warnings: [...plan.warnings, `config_read_failed: ${(error as Error).message}`]
      };
    }
  }

  async enableBridgeTools(project: ProjectSummary, evidenceDir: string): Promise<BridgeToolsEnableResult> {
    await this.ensureConnected();
    const plan = await this.previewBridgeTools(project);
    if (!plan.ready) {
      throw new Error(`bridge_tools_not_ready: ${plan.warnings.join("; ")}`);
    }

    const previousConfig = await this.readExistingBridgeToolsConfig(plan.serverName, project.projectRoot).catch(() => null);
    await fs.mkdir(evidenceDir, { recursive: true });
    const evidencePath = path.join(evidenceDir, `enable-bridge-tools-${Date.now()}.json`);
    const beforeEvidence = {
      created_at: new Date().toISOString(),
      server_name: plan.serverName,
      key_path: plan.keyPath,
      project_root: project.projectRoot,
      bridge_dir: project.bridgeDir,
      previous_config: previousConfig ?? null,
      new_config: plan.mcpServerConfig
    };
    await fs.writeFile(evidencePath, `${JSON.stringify(beforeEvidence, null, 2)}\n`, "utf8");

    await this.request("config/value/write", {
      keyPath: plan.keyPath,
      value: plan.mcpServerConfig,
      mergeStrategy: "replace",
      filePath: null,
      expectedVersion: null
    });
    await this.request("config/mcpServer/reload", undefined);

    const inventory = await this.waitForBridgeToolsInventory(project);
    return {
      applied: true,
      reloaded: true,
      evidencePath,
      plan: withExistingConfig(plan, previousConfig),
      inventory,
      checkedAt: new Date().toISOString()
    };
  }

  async startThread(options: RuntimeThreadOptions): Promise<RuntimeThreadHandle> {
    await this.ensureConnected();
    const params = appServerThreadStartParams(options);
    const response = await this.request<ThreadStartResponse>("thread/start", params);
    return {
      threadId: response.thread.id,
      cwd: response.cwd,
      instructionSources: response.instructionSources
    };
  }

  async *runTurn(input: RuntimeTurnInput): AsyncIterable<HostEvent> {
    await this.ensureConnected();
    const params = appServerTurnStartParams(input);
    const response = await this.request<TurnStartResponse>("turn/start", params);

    const turnId = response.turn.id;
    yield event("turn.started", {
      thread_id: input.threadId,
      turn_id: turnId
    });

    for await (const notification of this.notifications) {
      const mapped = mapServerNotification(notification, input.threadId, turnId, this.itemPhases);
      if (!mapped) {
        continue;
      }
      yield mapped;
      if (mapped.method === "turn.completed" || mapped.method === "turn.interrupted" || mapped.method === "error") {
        return;
      }
      if (this.notifications.length > this.options.backpressureLimit) {
        yield event("runtime.backpressure", {
          queue_depth: this.notifications.length,
          limit: this.options.backpressureLimit
        });
      }
    }
  }

  async interruptTurn(threadId: string, turnId: string): Promise<void> {
    await this.ensureConnected();
    await this.request("turn/interrupt", {
      threadId,
      turnId
    });
  }

  async respondToApproval(approvalId: string, decision: "approve" | "approve_session" | "reject" | "revise" | "expired", note = ""): Promise<void> {
    const request = this.pendingServerRequests.get(approvalId);
    if (!request) {
      throw new Error(`runtime_approval_not_found: ${approvalId}`);
    }
    this.pendingServerRequests.delete(approvalId);
    this.sendServerResponse(request.requestId, responseForApproval(request.method, decision, request.params, note));
  }

  async shutdown(): Promise<void> {
    this.shuttingDown = true;
    this.socket?.close();
    this.socket = null;
    this.initialized = false;
    this.connectionPromise = null;
    this.failPendingRequests(new Error("app_server_shutdown"));
    this.terminateProcess();
    this.notifications.close();
  }

  private async ensureConnected(): Promise<void> {
    if (this.socket?.readyState === WebSocket.OPEN && this.initialized) {
      return;
    }
    if (this.connectionPromise) {
      await this.connectionPromise;
      return;
    }
    this.connectionPromise = this.connectAndInitialize();
    try {
      await this.connectionPromise;
    } finally {
      this.connectionPromise = null;
    }
  }

  private async connectAndInitialize(): Promise<void> {
    if (this.socket?.readyState === WebSocket.OPEN && this.initialized) {
      return;
    }
    await this.startProcess();
    await this.connectSocket();
    if (!this.initialized) {
      await this.request("initialize", {
        clientInfo: {
          name: "godot-codex-bridge-codex-host",
          title: "Godot Codex Bridge Codex Host",
          version: "0.0.1"
        },
        capabilities: null
      });
      this.socket?.send(JSON.stringify({ method: "initialized" }));
      this.initialized = true;
    }
  }

  private async startProcess(): Promise<void> {
    if (this.proc && !this.proc.killed) {
      return;
    }
    this.shuttingDown = false;
    const listen = `ws://${this.options.host}:${this.options.port}`;
    const command = this.processCommand(listen);
    this.proc = spawn(command.file, command.args, {
      stdio: ["ignore", "pipe", "pipe"],
      windowsHide: true
    });
    this.proc.stderr?.on("data", (chunk) => {
      const text = String(chunk).trim();
      if (text) {
        this.notifications.push({
          method: "warning",
          params: {
            threadId: null,
            message: text
          }
        } as ServerNotification);
      }
    });
    this.proc.on("exit", (code, signal) => {
      this.proc = null;
      this.initialized = false;
      this.socket = null;
      this.failPendingRequests(new Error(`codex app-server exited with code ${code ?? "null"} signal ${signal ?? "null"}`));
      this.notifications.push({
        method: "warning",
        params: {
          threadId: null,
          message: `codex app-server exited with code ${code ?? "null"} signal ${signal ?? "null"}`
        }
      } as ServerNotification);
    });
  }

  private processCommand(listen: string): { file: string; args: string[] } {
    if (process.platform === "win32" && this.options.codexBin === "codex") {
      if (!/^ws:\/\/[0-9.]+:\d+$/.test(listen)) {
        throw new Error(`invalid_app_server_listen_url: ${listen}`);
      }
      const nativeCodex = this.findWindowsNativeCodex();
      if (nativeCodex) {
        return {
          file: nativeCodex,
          args: ["app-server", "--listen", listen]
        };
      }
      return {
        file: process.env.ComSpec ?? "cmd.exe",
        args: ["/d", "/s", "/c", `codex app-server --listen ${listen}`]
      };
    }
    return {
      file: this.options.codexBin,
      args: ["app-server", "--listen", listen]
    };
  }

  private findWindowsNativeCodex(): string | null {
    const appData = process.env.APPDATA;
    if (!appData) {
      return null;
    }
    const archDir = process.arch === "arm64" ? "aarch64-pc-windows-msvc" : "x86_64-pc-windows-msvc";
    const candidate = path.join(
      appData,
      "npm",
      "node_modules",
      "@openai",
      "codex",
      "node_modules",
      "@openai",
      process.arch === "arm64" ? "codex-win32-arm64" : "codex-win32-x64",
      "vendor",
      archDir,
      "bin",
      "codex.exe"
    );
    return existsSync(candidate) ? candidate : null;
  }

  private async connectSocket(): Promise<void> {
    if (this.socket?.readyState === WebSocket.OPEN) {
      return;
    }
    const url = `ws://${this.options.host}:${this.options.port}`;
    const deadline = Date.now() + 10_000;
    let lastError: Error | null = null;
    while (Date.now() < deadline) {
      try {
        this.initialized = false;
        this.socket = await openWebSocket(url);
        this.socket.on("message", (raw) => this.handleMessage(String(raw)));
        this.socket.on("close", () => {
          this.initialized = false;
          this.socket = null;
          this.failPendingRequests(new Error("app_server_socket_closed"));
          if (!this.shuttingDown) {
            this.terminateProcess();
          }
        });
        this.socket.on("error", (error) => {
          this.initialized = false;
          this.socket = null;
          this.failPendingRequests(error instanceof Error ? error : new Error(String(error)));
          if (!this.shuttingDown) {
            this.terminateProcess();
          }
        });
        return;
      } catch (error) {
        lastError = error as Error;
        await delay(200);
      }
    }
    this.terminateProcess();
    throw new Error(`app_server_connect_failed: ${lastError?.message ?? url}`);
  }

  private terminateProcess(): void {
    if (this.proc && !this.proc.killed) {
      this.proc.kill();
    }
    this.proc = null;
  }

  private request<T = unknown>(method: string, params: unknown): Promise<T> {
    if (!this.socket || this.socket.readyState !== WebSocket.OPEN) {
      return Promise.reject(new Error("app_server_socket_not_open"));
    }
    const id = this.nextId++;
    const payload = { id, method, params };
    const promise = new Promise<T>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`app_server_request_timeout: ${method}`));
      }, 15_000);
      this.pending.set(id, {
        resolve: (value) => resolve(value as T),
        reject,
        timer
      });
    });
    this.socket.send(JSON.stringify(payload));
    return promise;
  }

  private handleMessage(raw: string): void {
    let message: unknown;
    try {
      message = JSON.parse(raw);
    } catch {
      return;
    }
    if (!message || typeof message !== "object") {
      return;
    }
    const record = message as Record<string, unknown>;
    if ("id" in record && typeof record.method === "string") {
      this.handleServerRequest(record as ServerRequest);
      return;
    }
    if ("id" in record) {
      const id = record.id as JsonRpcId;
      const pending = this.pending.get(id);
      if (!pending) {
        return;
      }
      this.pending.delete(id);
      clearTimeout(pending.timer);
      if ("error" in record) {
        const error = record.error as { message?: string };
        if ((error?.message ?? "").toLowerCase().includes("not initialized")) {
          this.initialized = false;
        }
        pending.reject(new Error(error?.message ?? "app_server_request_failed"));
      } else {
        pending.resolve(record.result);
      }
      return;
    }
    if (typeof record.method === "string") {
      const notification = record as ServerNotification;
      this.recordNotificationEvidence(notification);
      this.notifications.push(notification);
    }
  }

  private handleServerRequest(request: ServerRequest): void {
    if (request.method === "account/chatgptAuthTokens/refresh" || request.method === "attestation/generate") {
      this.sendServerError(request.id, "unsupported_server_request", request.method);
      this.notifications.push({
        method: "warning",
        params: {
          threadId: null,
          message: `Unsupported app-server request declined: ${request.method}`
        }
      } as ServerNotification);
      return;
    }

    const runtimeApprovalId = `runtime-approval-${String(request.id)}`;
    this.pendingServerRequests.set(runtimeApprovalId, {
      requestId: request.id,
      method: request.method,
      params: request.params
    });

    const params = request.params as Record<string, unknown>;
    this.notifications.push({
      method: "godot/approvalRequested",
      params: {
        runtime_approval_id: runtimeApprovalId,
        kind: approvalKindFor(request.method),
        thread_id: typeof params.threadId === "string" ? params.threadId : undefined,
        turn_id: typeof params.turnId === "string" ? params.turnId : undefined,
        item_id: typeof (params.itemId ?? params.callId) === "string" ? String(params.itemId ?? params.callId) : undefined,
        reason: params.reason === undefined ? params.message === undefined ? null : String(params.message) : String(params.reason),
        cwd: params.cwd === undefined || params.cwd === null ? null : String(params.cwd),
        command: params.command as never,
        grant_root: params.grantRoot === undefined || params.grantRoot === null ? null : String(params.grantRoot),
        diff_evidence: this.diffEvidenceForRequest(request),
        file_changes: params.fileChanges ?? null,
        raw_method: request.method,
        raw_params: request.params
      }
    });
  }

  private sendServerResponse(id: JsonRpcId, result: unknown): void {
    if (!this.socket || this.socket.readyState !== WebSocket.OPEN) {
      throw new Error("app_server_socket_not_open");
    }
    this.socket.send(JSON.stringify({ id, result }));
  }

  private failPendingRequests(error: Error): void {
    for (const [id, pending] of this.pending.entries()) {
      this.pending.delete(id);
      clearTimeout(pending.timer);
      pending.reject(error);
    }
  }

  private sendServerError(id: JsonRpcId, message: string, method: string): void {
    if (!this.socket || this.socket.readyState !== WebSocket.OPEN) {
      throw new Error("app_server_socket_not_open");
    }
    this.socket.send(JSON.stringify({
      id,
      error: {
        code: -32601,
        message,
        data: { method }
      }
    }));
  }

  private recordNotificationEvidence(notification: ServerNotification): void {
    if (notification.method === "item/started" || notification.method === "item/completed") {
      const params = notification.params as unknown as Record<string, unknown>;
      const item = objectValue(params.item);
      const itemId = typeof item?.id === "string" ? item.id : "";
      const itemType = typeof item?.type === "string" ? item.type : "";
      const phase = typeof item?.phase === "string" ? item.phase : "";
      const threadId = typeof params.threadId === "string" ? params.threadId : "";
      const turnId = typeof params.turnId === "string" ? params.turnId : "";
      if (itemType === "agentMessage" && itemId !== "" && phase !== "") {
        this.itemPhases.set(`${threadId}:${turnId}:${itemId}`, phase);
      }
      return;
    }
    if (notification.method === "turn/diff/updated") {
      this.turnDiffs.set(`${notification.params.threadId}:${notification.params.turnId}`, notification.params.diff);
      return;
    }
    if (notification.method === "item/fileChange/patchUpdated") {
      this.itemDiffs.set(
        `${notification.params.threadId}:${notification.params.turnId}:${notification.params.itemId}`,
        notification.params.changes
      );
    }
  }

  private diffEvidenceForRequest(request: ServerRequest): unknown {
    const params = request.params as Record<string, unknown>;
    if (request.method === "applyPatchApproval") {
      return params.fileChanges ?? null;
    }
    if (request.method !== "item/fileChange/requestApproval") {
      return null;
    }
    const threadId = typeof params.threadId === "string" ? params.threadId : "";
    const turnId = typeof params.turnId === "string" ? params.turnId : "";
    const itemId = typeof params.itemId === "string" ? params.itemId : "";
    return this.itemDiffs.get(`${threadId}:${turnId}:${itemId}`)
      ?? this.turnDiffs.get(`${threadId}:${turnId}`)
      ?? null;
  }

  private async readExistingBridgeToolsConfig(serverName: string, cwd: string): Promise<unknown> {
    await this.ensureConnected();
    const response = await this.request<ConfigReadResponse>("config/read", {
      includeLayers: false,
      cwd
    });
    const config = response.config as Record<string, unknown>;
    const mcpServers = objectValue(config.mcp_servers) ?? objectValue(config.mcpServers);
    return mcpServers?.[serverName] ?? null;
  }

  private async waitForBridgeToolsInventory(project: ProjectSummary): Promise<RuntimeToolInventory> {
    const deadline = Date.now() + 6_000;
    let lastInventory: RuntimeToolInventory | null = null;
    while (Date.now() < deadline) {
      lastInventory = await this.inspectMcpTools();
      if (lastInventory.available) {
        return lastInventory;
      }
      await delay(300);
    }
    return lastInventory ?? {
      available: false,
      serverName: null,
      toolCount: 0,
      godotToolCount: 0,
      godotTools: [],
      checkedAt: new Date().toISOString(),
      error: `Bridge tools were registered for ${project.projectRoot}, but app-server did not report godot.* tools yet.`
    };
  }
}

function withExistingConfig(plan: BridgeToolsRegistrationPlan, existing: unknown): BridgeToolsRegistrationPlan {
  const existingConfigPresent = existing !== null && existing !== undefined;
  return {
    ...plan,
    existingConfigPresent,
    alreadyConfigured: existingConfigPresent && stableJson(existing) === stableJson(plan.mcpServerConfig),
    previousConfigSha256: existingConfigPresent ? sha256(stableJson(existing)) : undefined
  };
}

function objectValue(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function stableJson(value: unknown): string {
  return JSON.stringify(sortJson(value));
}

function sortJson(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map(sortJson);
  }
  if (value !== null && typeof value === "object") {
    const record = value as Record<string, unknown>;
    return Object.fromEntries(Object.keys(record).sort().map((key) => [key, sortJson(record[key])]));
  }
  return value;
}

function sha256(value: string): string {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function mapServerNotification(
  notification: RuntimeNotification,
  threadId: string,
  turnId: string,
  itemPhases: Map<string, string>
): HostEvent | null {
  switch (notification.method) {
    case "godot/approvalRequested":
      return event("approval.requested", notification.params as unknown as Record<string, unknown>);
    case "turn/started":
      return null;
    case "item/agentMessage/delta":
      if (notification.params.threadId !== threadId || notification.params.turnId !== turnId) {
        return null;
      }
      return event("turn.event", {
        thread_id: threadId,
        turn_id: turnId,
        event: "agent_message_delta",
        item_id: notification.params.itemId,
        phase: itemPhases.get(`${threadId}:${turnId}:${notification.params.itemId}`) ?? null,
        text: notification.params.delta
      });
    case "turn/diff/updated":
      if (notification.params.threadId !== threadId || notification.params.turnId !== turnId) {
        return null;
      }
      return event("turn.event", {
        thread_id: threadId,
        turn_id: turnId,
        event: "diff_updated",
        diff: notification.params.diff,
        diff_text: notification.params.diff
      });
    case "item/fileChange/patchUpdated": {
      const params = notification.params as unknown as Record<string, unknown>;
      if (params.threadId !== threadId || params.turnId !== turnId) {
        return null;
      }
      const diffText = diffTextFromFileUpdateChanges(params.changes);
      if (diffText === "") {
        return null;
      }
      return event("turn.event", {
        thread_id: threadId,
        turn_id: turnId,
        item_id: typeof params.itemId === "string" ? params.itemId : null,
        event: "diff_updated",
        diff: diffText,
        diff_text: diffText,
        file_changes: fileChangesFromFileUpdateChanges(params.changes)
      });
    }
    case "turn/completed":
      if (notification.params.threadId !== threadId || notification.params.turn.id !== turnId) {
        return null;
      }
      return event("turn.completed", {
        thread_id: threadId,
        turn_id: turnId,
        status: notification.params.turn.status
      });
    case "warning":
      return event("runtime.warning", {
        thread_id: notification.params.threadId,
        message: notification.params.message
      });
    case "error":
      if (notification.params.threadId !== threadId || notification.params.turnId !== turnId) {
        return null;
      }
      return event("error", {
        thread_id: threadId,
        turn_id: turnId,
        recoverable: notification.params.willRetry,
        message: notification.params.error.message
      });
    default:
      return null;
  }
}

export function diffTextFromFileUpdateChanges(changes: unknown): string {
  if (!Array.isArray(changes)) {
    return "";
  }
  const parts: string[] = [];
  for (const change of changes) {
    const item = objectValue(change);
    const rawPath = typeof item?.path === "string" ? item.path : "";
    const diff = typeof item?.diff === "string" ? item.diff.trimEnd() : "";
    if (!rawPath || !diff) {
      continue;
    }
    const normalizedPath = rawPath.replace(/\\/g, "/");
    if (diff.startsWith("diff --git ")) {
      parts.push(diff);
      continue;
    }
    parts.push(`diff --git a/${normalizedPath} b/${normalizedPath}`);
    parts.push(`--- a/${normalizedPath}`);
    parts.push(`+++ b/${normalizedPath}`);
    parts.push(diff);
  }
  return parts.join("\n");
}

export function fileChangesFromFileUpdateChanges(changes: unknown): Record<string, { type: string; unified_diff: string }> {
  const result: Record<string, { type: string; unified_diff: string }> = {};
  if (!Array.isArray(changes)) {
    return result;
  }
  for (const change of changes) {
    const item = objectValue(change);
    const rawPath = typeof item?.path === "string" ? item.path : "";
    const diff = typeof item?.diff === "string" ? item.diff.trimEnd() : "";
    if (!rawPath || !diff) {
      continue;
    }
    result[rawPath.replace(/\\/g, "/")] = {
      type: typeof item?.kind === "string" ? item.kind : "update",
      unified_diff: diff
    };
  }
  return result;
}

function approvalKindFor(method: string): RuntimeApprovalKind {
  switch (method) {
    case "item/fileChange/requestApproval":
      return "file_change";
    case "item/commandExecution/requestApproval":
      return "command_execution";
    case "item/permissions/requestApproval":
      return "permissions";
    case "applyPatchApproval":
      return "apply_patch";
    case "execCommandApproval":
      return "exec_command";
    case "item/tool/requestUserInput":
      return "user_input";
    case "item/tool/call":
      return "tool_call";
    case "mcpServer/elicitation/request":
      return "elicitation";
    default:
      return "unknown";
  }
}

export function responseForApproval(method: string, decision: "approve" | "approve_session" | "reject" | "revise" | "expired", rawParams?: unknown, note = ""): unknown {
  const accepted = decision === "approve" || decision === "approve_session";
  const acceptedForSession = decision === "approve_session";
  switch (method) {
    case "item/fileChange/requestApproval":
      return { decision: accepted ? acceptedForSession ? "acceptForSession" : "accept" : decision === "expired" ? "cancel" : "decline" };
    case "item/commandExecution/requestApproval":
      return { decision: accepted ? acceptedForSession ? "acceptForSession" : "accept" : decision === "expired" ? "cancel" : "decline" };
    case "item/permissions/requestApproval":
      return accepted
        ? { permissions: grantedPermissionsFromRequest(rawParams), scope: acceptedForSession ? "session" : "turn", strictAutoReview: false }
        : { permissions: {}, scope: "turn", strictAutoReview: true };
    case "applyPatchApproval":
      return { decision: accepted ? acceptedForSession ? "approved_for_session" : "approved" : decision === "expired" ? "timed_out" : "denied" };
    case "execCommandApproval":
      return { decision: accepted ? acceptedForSession ? "approved_for_session" : "approved" : decision === "expired" ? "timed_out" : "denied" };
    case "item/tool/requestUserInput":
      return { answers: {} };
    case "item/tool/call":
      return { contentItems: [{ type: "inputText", text: "Denied by Godot Codex Host approval policy." }], success: false };
    case "mcpServer/elicitation/request":
      return accepted
        ? { action: "accept", content: elicitationContent(rawParams, note), _meta: null }
        : { action: decision === "expired" ? "cancel" : "decline", content: null, _meta: null };
    default:
      return {};
  }
}

export function appServerThreadStartParams(options: RuntimeThreadOptions): Record<string, unknown> {
  const params: Record<string, unknown> = {
    cwd: options.projectRoot,
    approvalPolicy: options.approvalPolicy ?? "on-request",
    approvalsReviewer: "user",
    sandbox: options.sandbox ?? "read-only",
    threadSource: options.background ? "subagent" : "user",
    sessionStartSource: "startup"
  };
  if (options.model) {
    params.model = options.model;
  }
  return params;
}

export function appServerTurnStartParams(input: RuntimeTurnInput): Record<string, unknown> {
  const userInput: Record<string, unknown>[] = [
    {
      type: "text",
      text: decorateMessage(input.message, input.attachments, input.annotation),
      text_elements: []
    }
  ];
  if (input.annotation?.imageAttached && input.annotation.annotatedImagePath) {
    userInput.push({
      type: "localImage",
      path: input.annotation.annotatedImagePath,
      detail: input.annotation.detail
    });
  }

  const params: Record<string, unknown> = {
    threadId: input.threadId,
    input: userInput,
    cwd: input.projectRoot,
    approvalPolicy: input.approvalPolicy ?? "on-request",
    approvalsReviewer: "user",
    sandboxPolicy: sandboxPolicyFor(input.sandbox ?? "read-only", input.projectRoot)
  };
  if (input.model) {
    params.model = input.model;
  }
  if (input.effort) {
    params.effort = input.effort;
  }
  return params;
}

function sandboxPolicyFor(sandbox: RuntimeSandboxMode, projectRoot: string): Record<string, unknown> {
  if (sandbox === "danger-full-access") {
    return { type: "dangerFullAccess" };
  }
  if (sandbox === "workspace-write") {
    return {
      type: "workspaceWrite",
      writableRoots: [projectRoot],
      networkAccess: false,
      excludeTmpdirEnvVar: false,
      excludeSlashTmp: false
    };
  }
  return {
    type: "readOnly",
    networkAccess: false
  };
}

function grantedPermissionsFromRequest(rawParams: unknown): Record<string, unknown> {
  const params = objectValue(rawParams);
  const requested = objectValue(params?.permissions);
  const granted: Record<string, unknown> = {};
  if (!requested) {
    return granted;
  }
  if (requested.fileSystem !== undefined && requested.fileSystem !== null) {
    granted.fileSystem = requested.fileSystem;
  }
  if (requested.network !== undefined && requested.network !== null) {
    granted.network = requested.network;
  }
  return granted;
}

function elicitationContent(rawParams: unknown, note: string): Record<string, unknown> {
  const params = objectValue(rawParams);
  const schema = objectValue(params?.requestedSchema);
  const properties = objectValue(schema?.properties);
  const trimmedNote = note.trim();
  if (!properties) {
    return trimmedNote ? { response: trimmedNote } : {};
  }

  const content: Record<string, unknown> = {};
  let noteAssigned = false;
  for (const [key, propertyValue] of Object.entries(properties)) {
    const property = objectValue(propertyValue);
    const enumValues = Array.isArray(property?.enum) ? property.enum : [];
    if (enumValues.length > 0) {
      content[key] = enumValues[0];
      continue;
    }

    const typeValue = property?.type;
    const type = Array.isArray(typeValue) ? String(typeValue[0] ?? "string") : String(typeValue ?? "string");
    if (type === "boolean") {
      content[key] = true;
    } else if (type === "number" || type === "integer") {
      content[key] = 0;
    } else {
      content[key] = trimmedNote;
      noteAssigned = true;
    }
  }
  if (trimmedNote && !noteAssigned) {
    content.note = trimmedNote;
  }
  return content;
}

function summarizeMcpTools(response: ListMcpServerStatusResponse): RuntimeToolInventory {
  const servers = response.data ?? [];
  let bestServerName: string | null = null;
  let bestToolCount = 0;
  let bestGodotTools: string[] = [];

  for (const server of servers) {
    const toolNames = Object.entries(server.tools ?? {})
      .map(([key, tool]) => typeof tool?.name === "string" && tool.name.length > 0 ? tool.name : key)
      .filter((name) => typeof name === "string" && name.length > 0)
      .sort();
    const godotTools = toolNames.filter((name) => name.startsWith("godot."));
    const looksLikeBridge = server.name.toLowerCase().includes("godot")
      || server.name.toLowerCase().includes("bridge")
      || godotTools.length > 0;
    if (godotTools.length > bestGodotTools.length || (bestServerName === null && looksLikeBridge)) {
      bestServerName = server.name;
      bestToolCount = toolNames.length;
      bestGodotTools = godotTools;
    }
  }

  return {
    available: bestGodotTools.length > 0,
    serverName: bestServerName,
    toolCount: bestToolCount,
    godotToolCount: bestGodotTools.length,
    godotTools: bestGodotTools.slice(0, 24),
    checkedAt: new Date().toISOString(),
    error: bestGodotTools.length > 0
      ? undefined
      : "Godot Codex Bridge MCP tools are not visible to this Codex runtime."
  };
}

function decorateMessage(message: string, attachments = {}, annotation?: RuntimeTurnInput["annotation"]): string {
  const enabled = Object.entries(attachments)
    .filter(([, value]) => value)
    .map(([key]) => key);
  if (annotation && !enabled.includes("latest_annotation")) {
    enabled.push("latest_annotation");
  }
  if (enabled.length === 0) {
    return message;
  }
  return `${message}\n\nGodot context attachments requested: ${enabled.join(", ")}. Use the Godot Codex Bridge MCP tools to fetch current data when needed.`;
}

function openWebSocket(url: string): Promise<WebSocket> {
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(url);
    socket.once("open", () => resolve(socket));
    socket.once("error", (error) => reject(error));
  });
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
