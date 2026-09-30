import { spawn, spawnSync, type ChildProcess } from "node:child_process";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import crypto from "node:crypto";
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
import { resolveCodexCommand } from "./codexCommand.js";
import { buildBridgeToolsRegistrationPlan } from "./bridgeToolsRegistration.js";
import type { CodexRuntimeAdapter, RuntimeSandboxMode, RuntimeThreadHandle, RuntimeThreadOptions, RuntimeTurnInput } from "./codexRuntime.js";
import { event } from "./codexRuntime.js";
import { ensureDirectoryInsideRootSync, writeFileInsideRootSync } from "./physicalPath.js";
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
    }
  | {
      method: "godot/approvalInvalidated";
      params: {
        runtime_approval_id: string;
        thread_id?: string;
        turn_id?: string;
        request_id: JsonRpcId;
        reason: string;
      };
    }
  | {
      method: "godot/runtimeFailed";
      params: { threadId: string; turnId: string; message: string };
    };

type PendingServerRequest = {
  runtimeApprovalId: string;
  requestKey: string;
  requestId: JsonRpcId;
  method: string;
  params: unknown;
};

export function appServerListenUrl(host: string, port: number): string {
  return `ws://${host.includes(":") ? `[${host}]` : host}:${port}`;
}

export function codexChildEnvironment(parent: NodeJS.ProcessEnv): NodeJS.ProcessEnv {
  const childEnv = { ...parent };
  for (const key of Object.keys(childEnv)) {
    if (["GODOT_CODEX_HOST_PAIR_SECRET", "GODOT_CODEX_HOST_LAUNCH_NONCE"].includes(key.toUpperCase())) {
      delete childEnv[key];
    }
  }
  return childEnv;
}

const FALLBACK_REASONING_EFFORTS = ["minimal", "low", "medium", "high", "xhigh"] as const;
const MAX_REASONING_EFFORT_LENGTH = 32;
const SAFE_REASONING_EFFORT = /^[a-z][a-z0-9_-]*$/;

export function normalizeRuntimeReasoningEffort(value: unknown): RuntimeReasoningEffort | undefined {
  if (typeof value !== "string" || value.length === 0 || value.length > MAX_REASONING_EFFORT_LENGTH) {
    return undefined;
  }
  if (value.trim() !== value || !SAFE_REASONING_EFFORT.test(value)) {
    return undefined;
  }
  return value;
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
  private readonly pendingServerRequestIds = new Map<string, string>();
  private readonly notifications = new AsyncQueue<RuntimeNotification>();
  private readonly itemDiffs = new Map<string, unknown>();
  private readonly itemPhases = new Map<string, string>();
  private shuttingDown = false;
  private activeTurn: { threadId: string; turnId: string } | null = null;
  private lastProcessFailure: string | null = null;

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
        const supportedByEffort = new Map<RuntimeReasoningEffort, RuntimeReasoningEffortOption>();
        for (const option of Array.isArray(model.supportedReasoningEfforts) ? model.supportedReasoningEfforts : []) {
          const reasoningEffort = normalizeRuntimeReasoningEffort(option.reasoningEffort);
          if (reasoningEffort && !supportedByEffort.has(reasoningEffort)) {
            supportedByEffort.set(reasoningEffort, { reasoningEffort, description: option.description });
          }
        }
        const defaultReasoningEffort = normalizeRuntimeReasoningEffort(model.defaultReasoningEffort);
        if (defaultReasoningEffort && !supportedByEffort.has(defaultReasoningEffort)) {
          supportedByEffort.set(defaultReasoningEffort, { reasoningEffort: defaultReasoningEffort });
        }
        return {
          id: model.id,
          model: model.model,
          displayName: model.displayName || model.model,
          description: model.description,
          hidden: model.hidden,
          isDefault: model.isDefault,
          inputModalities: Array.isArray(model.inputModalities) ? model.inputModalities : [],
          defaultReasoningEffort,
          supportedReasoningEfforts: [...supportedByEffort.values()]
        };
      });
    const reasoningByEffort = new Map<RuntimeReasoningEffort, RuntimeReasoningEffortOption>();
    for (const model of models) {
      for (const option of model.supportedReasoningEfforts) {
        reasoningByEffort.set(option.reasoningEffort, option);
      }
    }
    if (reasoningByEffort.size === 0) {
      for (const effort of FALLBACK_REASONING_EFFORTS) {
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
    ensureDirectoryInsideRootSync(project.projectRoot, evidenceDir);
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
    if (bridgeMcpOverrideArgs(this.bridgeProject).length > 0 && this.bridgeProject?.projectRoot === project.projectRoot) {
      // Already bound to this project by the launch-time override. Writing the
      // user's global Codex config would repoint every other Codex session
      // (and other games) at this project, so leave it untouched.
      writeFileInsideRootSync(project.projectRoot, evidencePath, `${JSON.stringify({ ...beforeEvidence, binding: "launch_override", global_config_written: false }, null, 2)}\n`);
      return {
        applied: true,
        reloaded: false,
        evidencePath,
        plan: withExistingConfig(plan, previousConfig),
        inventory: await this.waitForBridgeToolsInventory(project),
        checkedAt: new Date().toISOString()
      };
    }
    writeFileInsideRootSync(project.projectRoot, evidencePath, `${JSON.stringify(beforeEvidence, null, 2)}\n`);

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
    this.activeTurn = { threadId: input.threadId, turnId };
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
        if (this.activeTurn?.threadId === input.threadId && this.activeTurn.turnId === turnId) {
          this.activeTurn = null;
        }
        return;
      }
      if (this.notifications.length > this.options.backpressureLimit) {
        yield event("runtime.backpressure", {
          queue_depth: this.notifications.length,
          limit: this.options.backpressureLimit
        });
      }
    }
    if (this.activeTurn?.threadId === input.threadId && this.activeTurn.turnId === turnId) {
      this.activeTurn = null;
      yield event("error", {
        thread_id: input.threadId, turn_id: turnId, recoverable: true,
        message: "codex app-server notification stream ended before the turn completed",
      });
    }
  }

  async interruptTurn(threadId: string, turnId: string): Promise<void> {
    await this.ensureConnected();
    await this.request("turn/interrupt", {
      threadId,
      turnId
    });
    this.invalidateServerRequests((request) => requestThreadId(request) === threadId && requestTurnId(request) === turnId, "turn_interrupted");
  }

  async respondToApproval(approvalId: string, decision: "approve" | "approve_session" | "reject" | "revise" | "expired", note = ""): Promise<void> {
    const request = this.pendingServerRequests.get(approvalId);
    if (!request) {
      throw new Error(`runtime_approval_not_found: ${approvalId}`);
    }
    this.removePendingServerRequest(request);
    try {
      await this.sendServerResponseAndWait(request.requestId, responseForApproval(request.method, decision, request.params, note));
    } catch (error) {
      this.notifications.push(approvalInvalidatedNotification(request, "response_send_failed"));
      throw error;
    }
  }

  async shutdown(): Promise<void> {
    this.shuttingDown = true;
    this.failActiveTurn("codex app-server shut down");
    this.socket?.close();
    this.socket = null;
    this.initialized = false;
    this.connectionPromise = null;
    this.failPendingRequests(new Error("app_server_shutdown"));
    this.invalidateServerRequests(() => true, "runtime_shutdown");
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

  private bridgeProject: { projectRoot: string; bridgeDir: string } | null = null;

  /**
   * Bind Codex's godot_codex_bridge MCP server to the attached project. A
   * global Codex config may point it at another game; this launch-time
   * override always wins. A running app-server for another project is
   * restarted on next use so it picks up the new binding.
   */
  setBridgeProject(projectRoot: string, bridgeDir: string): void {
    if (this.bridgeProject?.projectRoot === projectRoot && this.bridgeProject.bridgeDir === bridgeDir) return;
    this.bridgeProject = { projectRoot, bridgeDir };
    if (!this.proc) return;
    this.shuttingDown = true;
    this.socket?.close();
    this.socket = null;
    this.initialized = false;
    this.connectionPromise = null;
    this.failPendingRequests(new Error("app_server_rebinding_project"));
    this.invalidateServerRequests(() => true, "runtime_rebinding_project");
    this.terminateProcess();
  }

  private async startProcess(): Promise<void> {
    if (this.proc && !this.proc.killed) {
      return;
    }
    this.shuttingDown = false;
    this.lastProcessFailure = null;
    const listen = appServerListenUrl(this.options.host, this.options.port);
    const override = bridgeMcpOverrideArgs(this.bridgeProject);
    let command;
    try {
      command = resolveCodexCommand(this.options.codexBin, [...override, "app-server", "--listen", listen]);
    } catch (error) {
      if (override.length === 0) throw error;
      // The npm cmd.exe fallback cannot carry a config override safely.
      command = resolveCodexCommand(this.options.codexBin, ["app-server", "--listen", listen]);
      this.notifications.push({
        method: "warning",
        params: { threadId: null, message: "Godot Bridge tools could not be bound to this project (Codex npm fallback). Set GODOT_CODEX_HOST_CODEX_BIN to codex.exe." }
      } as ServerNotification);
    }
    const proc = spawn(command.file, command.args, {
      stdio: ["ignore", "pipe", "pipe"],
      windowsHide: true,
      env: codexChildEnvironment(process.env)
    });
    this.proc = proc;
    proc.stderr?.on("data", (chunk) => {
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
    proc.on("error", (error) => {
      this.handleProcessFailure(proc, `codex app-server spawn failed: ${error.message}`);
    });
    proc.on("exit", (code, signal) => {
      this.handleProcessFailure(proc, `codex app-server exited with code ${code ?? "null"} signal ${signal ?? "null"}`);
    });
  }

  private handleProcessFailure(proc: ChildProcess, message: string): void {
    if (this.proc !== proc) return;
    this.proc = null;
    this.lastProcessFailure = message;
    this.initialized = false;
    this.socket?.close();
    this.socket = null;
    this.failPendingRequests(new Error(message));
    this.invalidateServerRequests(() => true, "process_exited");
    this.failActiveTurn(message);
    this.notifications.push({ method: "warning", params: { threadId: null, message } } as ServerNotification);
  }

  private async connectSocket(): Promise<void> {
    if (this.socket?.readyState === WebSocket.OPEN) {
      return;
    }
    const url = appServerListenUrl(this.options.host, this.options.port);
    const deadline = Date.now() + 10_000;
    let lastError: Error | null = null;
    while (Date.now() < deadline) {
      if (!this.proc) {
        throw new Error(this.lastProcessFailure ?? "codex app-server process stopped before connecting");
      }
      try {
        this.initialized = false;
        const socket = await openWebSocket(url);
        this.socket = socket;
        socket.on("message", (raw) => this.handleMessage(String(raw)));
        socket.on("close", () => {
          if (this.socket !== socket) return;
          this.initialized = false;
          this.socket = null;
          this.failPendingRequests(new Error("app_server_socket_closed"));
          this.invalidateServerRequests(() => true, "transport_closed");
          this.failActiveTurn("codex app-server transport closed");
          if (!this.shuttingDown) {
            this.terminateProcess();
          }
        });
        socket.on("error", (error) => {
          if (this.socket !== socket) return;
          this.initialized = false;
          this.socket = null;
          this.failPendingRequests(error instanceof Error ? error : new Error(String(error)));
          this.invalidateServerRequests(() => true, "transport_error");
          this.failActiveTurn(`codex app-server transport error: ${error instanceof Error ? error.message : String(error)}`);
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
      terminateProcessTree(this.proc);
    }
    this.proc = null;
  }

  private failActiveTurn(message: string): void {
    const active = this.activeTurn;
    if (!active) return;
    this.activeTurn = null;
    this.notifications.push({ method: "godot/runtimeFailed", params: { ...active, message } });
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
      if (notification.method === "serverRequest/resolved") {
        this.handleServerRequestResolved(notification.params.requestId);
        return;
      }
      if (notification.method === "turn/completed") {
        this.invalidateServerRequests(
          (request) => requestThreadId(request) === notification.params.threadId && requestTurnId(request) === notification.params.turn.id,
          "turn_completed",
        );
      } else if (notification.method === "error" && !notification.params.willRetry) {
        this.invalidateServerRequests(
          (request) => requestThreadId(request) === notification.params.threadId && requestTurnId(request) === notification.params.turnId,
          "turn_failed",
        );
      }
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

    const params = objectValue(request.params);
    const unsupportedScope = unsupportedApprovalScope(request.method, params);
    if (unsupportedScope) {
      this.sendServerResponse(request.id, responseForApproval(request.method, "reject", params));
      this.notifications.push({
        method: "warning",
        params: {
          threadId: typeof params?.threadId === "string" ? params.threadId : typeof params?.conversationId === "string" ? params.conversationId : null,
          message: `Approval declined: ${unsupportedScope}. Use a Codex client that supports this approval scope.`,
        },
      } as ServerNotification);
      return;
    }

    if (!params) {
      this.sendServerError(request.id, "invalid_server_request_params", request.method);
      return;
    }
    const requestKey = serverRequestKey(request.id);
    if (this.pendingServerRequestIds.has(requestKey)) {
      this.sendServerError(request.id, "duplicate_server_request_id", request.method);
      return;
    }
    const runtimeApprovalId = `runtime-approval-${crypto.randomUUID()}`;
    const pendingRequest: PendingServerRequest = {
      runtimeApprovalId,
      requestKey,
      requestId: request.id,
      method: request.method,
      params: request.params
    };
    this.pendingServerRequests.set(runtimeApprovalId, pendingRequest);
    this.pendingServerRequestIds.set(requestKey, runtimeApprovalId);

    const diffEvidence = this.diffEvidenceForRequest(request);
    if (request.method === "item/fileChange/requestApproval" && Array.isArray(diffEvidence)) {
      // Refresh the existing diff card immediately before the approval card;
      // a more recent turn-wide update may otherwise show unrelated changes.
      this.notifications.push({
        method: "item/fileChange/patchUpdated",
        params: { threadId: params.threadId, turnId: params.turnId, itemId: params.itemId, changes: diffEvidence },
      } as ServerNotification);
    }
    this.notifications.push({
      method: "godot/approvalRequested",
      params: {
        runtime_approval_id: runtimeApprovalId,
        kind: approvalKindFor(request.method),
        thread_id: typeof params.threadId === "string" ? params.threadId : typeof params.conversationId === "string" ? params.conversationId : undefined,
        turn_id: typeof params.turnId === "string" ? params.turnId : undefined,
        item_id: typeof (params.itemId ?? params.callId) === "string" ? String(params.itemId ?? params.callId) : undefined,
        reason: params.reason === undefined ? params.message === undefined ? null : String(params.message) : String(params.reason),
        cwd: params.cwd === undefined || params.cwd === null ? null : String(params.cwd),
        command: params.command as never,
        grant_root: params.grantRoot === undefined || params.grantRoot === null ? null : String(params.grantRoot),
        diff_evidence: diffEvidence,
        file_changes: params.fileChanges ?? (Array.isArray(diffEvidence) ? fileChangesFromFileUpdateChanges(diffEvidence) : null),
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

  private sendServerResponseAndWait(id: JsonRpcId, result: unknown): Promise<void> {
    const socket = this.socket;
    if (!socket || socket.readyState !== WebSocket.OPEN) {
      return Promise.reject(new Error("app_server_socket_not_open"));
    }
    const payload = JSON.stringify({ id, result });
    return new Promise<void>((resolve, reject) => {
      socket.send(payload, (error) => {
        if (error) {
          reject(error);
        } else {
          resolve();
        }
      });
    });
  }

  private handleServerRequestResolved(requestId: JsonRpcId): void {
    const runtimeApprovalId = this.pendingServerRequestIds.get(serverRequestKey(requestId));
    const request = runtimeApprovalId ? this.pendingServerRequests.get(runtimeApprovalId) : undefined;
    if (!request) {
      return;
    }
    this.removePendingServerRequest(request);
    this.notifications.push(approvalInvalidatedNotification(request, "server_resolved"));
  }

  private invalidateServerRequests(predicate: (request: PendingServerRequest) => boolean, reason: string): void {
    for (const request of [...this.pendingServerRequests.values()]) {
      if (!predicate(request)) {
        continue;
      }
      this.removePendingServerRequest(request);
      this.notifications.push(approvalInvalidatedNotification(request, reason));
    }
  }

  private removePendingServerRequest(request: PendingServerRequest): void {
    this.pendingServerRequests.delete(request.runtimeApprovalId);
    this.pendingServerRequestIds.delete(request.requestKey);
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
      if (notification.method === "item/started" && itemType === "fileChange" && threadId && turnId && itemId) {
        this.recordItemDiff(`${threadId}:${turnId}:${itemId}`, item?.changes);
      }
      return;
    }
    if (notification.method === "item/fileChange/patchUpdated") {
      this.recordItemDiff(
        `${notification.params.threadId}:${notification.params.turnId}:${notification.params.itemId}`,
        notification.params.changes
      );
    }
  }

  private recordItemDiff(key: string, changes: unknown): void {
    // Empty or incomplete changes cannot justify a file-write approval.
    if (Array.isArray(changes) && changes.length > 0 && changes.every((change) => {
      const entry = objectValue(change);
      return typeof entry?.path === "string" && entry.path.trim() !== ""
        && typeof entry.diff === "string" && entry.diff.trim() !== "";
    })) {
      this.itemDiffs.set(key, changes);
    } else {
      this.itemDiffs.delete(key);
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
    // A turn-wide diff can describe a different item; never use it to grant
    // approval to a request that has no matching item-specific evidence.
    return threadId && turnId && itemId ? this.itemDiffs.get(`${threadId}:${turnId}:${itemId}`) ?? null : null;
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

function serverRequestKey(id: JsonRpcId): string {
  return JSON.stringify([typeof id, id]);
}

function requestThreadId(request: PendingServerRequest): string | undefined {
  const params = objectValue(request.params);
  return typeof params?.threadId === "string" ? params.threadId : undefined;
}

function requestTurnId(request: PendingServerRequest): string | undefined {
  const params = objectValue(request.params);
  return typeof params?.turnId === "string" ? params.turnId : undefined;
}

function approvalInvalidatedNotification(request: PendingServerRequest, reason: string): RuntimeNotification {
  return {
    method: "godot/approvalInvalidated",
    params: {
      runtime_approval_id: request.runtimeApprovalId,
      thread_id: requestThreadId(request),
      turn_id: requestTurnId(request),
      request_id: request.requestId,
      reason,
    },
  };
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
    case "godot/runtimeFailed":
      if (notification.params.threadId !== threadId || notification.params.turnId !== turnId) return null;
      return event("error", { thread_id: threadId, turn_id: turnId, recoverable: true, message: notification.params.message });
    case "godot/approvalRequested":
      return event("approval.requested", notification.params as unknown as Record<string, unknown>);
    case "godot/approvalInvalidated":
      return event("approval.invalidated", notification.params as unknown as Record<string, unknown>);
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
      // A retry is progress within the active turn, not a terminal host error.
      // Keep consuming notifications and keep the controller's busy state.
      return event(notification.params.willRetry ? "runtime.warning" : "error", {
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

/**
 * Stop the Codex child and its descendants. On Windows the npm fallback runs
 * Codex under cmd.exe, and ChildProcess.kill() would stop only that shim.
 */
/** `-c` override that defines godot_codex_bridge for the attached project. */
export function bridgeMcpOverrideArgs(
  project: { projectRoot: string; bridgeDir: string } | null,
  mcpEntry: string = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..", "..", "mcp_server", "dist", "src", "index.js"),
  nodeExecutable: string = process.execPath,
  exists: (file: string) => boolean = existsSync,
): string[] {
  if (!project || !exists(mcpEntry)) return [];
  // JSON string literals are valid TOML basic strings.
  const q = (value: string) => JSON.stringify(value);
  const table = `{command=${q(nodeExecutable)},args=[${q(mcpEntry)}],env={GODOT_CODEX_BRIDGE_PROJECT_ROOT=${q(project.projectRoot)},GODOT_CODEX_BRIDGE_DIR=${q(project.bridgeDir)}}}`;
  return ["-c", `mcp_servers.godot_codex_bridge=${table}`];
}

export function terminateProcessTree(
  proc: Pick<ChildProcess, "pid" | "kill">,
  platform: NodeJS.Platform = process.platform,
  runTaskkill: (file: string, args: string[]) => { status: number | null } = (file, args) =>
    spawnSync(file, args, { stdio: "ignore", windowsHide: true, timeout: 5_000 }),
): void {
  if (platform === "win32" && proc.pid) {
    // Absolute System32 path: never resolve taskkill through PATH.
    const taskkill = path.win32.join(process.env.SystemRoot ?? "C:\\Windows", "System32", "taskkill.exe");
    const result = runTaskkill(taskkill, ["/PID", String(proc.pid), "/T", "/F"]);
    if (result.status === 0) {
      return;
    }
  }
  proc.kill();
}

const CURRENT_COMMAND_FIELDS = new Set([
  "kind", "threadId", "turnId", "itemId", "startedAtMs", "approvalId", "environmentId",
  "reason", "networkApprovalContext", "command", "cwd", "commandActions",
  "proposedExecpolicyAmendment", "proposedNetworkPolicyAmendments",
]);
const LEGACY_COMMAND_FIELDS = new Set(["conversationId", "callId", "approvalId", "command", "cwd", "reason", "parsedCmd"]);
const CURRENT_FILE_FIELDS = new Set(["threadId", "turnId", "itemId", "startedAtMs", "reason", "grantRoot"]);
const LEGACY_PATCH_FIELDS = new Set(["conversationId", "callId", "fileChanges", "reason", "grantRoot"]);

/** One fail-closed scope check for intake and final response construction. */
export function unsupportedApprovalScope(method: string, rawParams: unknown): string | null {
  if (method === "item/permissions/requestApproval") {
    return "permission grants are not reviewable in Godot chat";
  }
  const params = objectValue(rawParams);
  if (!params) return "approval parameters are required";
  if (method.startsWith("item/") && method.endsWith("/requestApproval")) {
    if (!["threadId", "turnId", "itemId"].every((key) => typeof params[key] === "string" && String(params[key]).length > 0)) {
      return "approval thread, turn, and item identifiers are required";
    }
  }
  if (method === "item/commandExecution/requestApproval" || method === "execCommandApproval") {
    if (method === "execCommandApproval") {
      if (typeof params.conversationId !== "string" || !params.conversationId || typeof params.callId !== "string" || !params.callId) {
        return "legacy approval conversation and callback identifiers are required";
      }
      const extra = Object.keys(params).find((key) => !LEGACY_COMMAND_FIELDS.has(key));
      if (extra) return `unsupported legacy command approval field: ${extra}`;
    } else {
      const extra = Object.keys(params).find((key) => !CURRENT_COMMAND_FIELDS.has(key));
      if (extra) return `unsupported command approval field: ${extra}`;
    }
    if (params.kind != null && params.kind !== "command") return "terminal input or an unknown command action";
    if (params.networkApprovalContext != null || params.proposedNetworkPolicyAmendments != null) return "managed network access";
    // A proposed exec-policy amendment is only an offer: this Host never answers
    // with acceptWithExecpolicyAmendment, so approving accepts this one command.
    if (params.environmentId != null) return "an explicit execution environment";
    if (params.writeStdin != null) return "terminal input";
    if (method === "execCommandApproval") {
      if (!Array.isArray(params.command) || params.command.length === 0 ||
        !params.command.every((part) => typeof part === "string" && part.trim().length > 0)) {
        return "a reviewable command is required";
      }
    } else if (typeof params.command !== "string" || params.command.trim().length === 0) {
      return "a reviewable command is required";
    }
  }
  if (method === "item/fileChange/requestApproval" || method === "applyPatchApproval") {
    if (method === "applyPatchApproval" &&
      (typeof params.conversationId !== "string" || !params.conversationId || typeof params.callId !== "string" || !params.callId)) {
      return "legacy patch conversation and callback identifiers are required";
    }
    const allowed = method === "applyPatchApproval" ? LEGACY_PATCH_FIELDS : CURRENT_FILE_FIELDS;
    const extra = Object.keys(params).find((key) => !allowed.has(key));
    if (extra) return `unsupported file approval field: ${extra}`;
    if (params.grantRoot != null) return "a persistent write root grant";
  }
  return null;
}

export function responseForApproval(method: string, decision: "approve" | "approve_session" | "reject" | "revise" | "expired", rawParams?: unknown, note = ""): unknown {
  if (decision === "approve" || decision === "approve_session") {
    const unsupported = unsupportedApprovalScope(method, rawParams);
    if (unsupported) throw new Error(`unsupported_approval_scope: ${unsupported}`);
  }
  if (decision === "approve_session" && method !== "item/commandExecution/requestApproval" && method !== "execCommandApproval") {
    throw new Error(`approval_session_scope_not_allowed: ${method}`);
  }
  const accepted = decision === "approve" || decision === "approve_session";
  const acceptedForSession = decision === "approve_session";
  switch (method) {
    case "item/fileChange/requestApproval":
      return { decision: accepted ? acceptedForSession ? "acceptForSession" : "accept" : decision === "expired" ? "cancel" : "decline" };
    case "item/commandExecution/requestApproval":
      return { decision: accepted ? acceptedForSession ? "acceptForSession" : "accept" : decision === "expired" ? "cancel" : "decline" };
    case "item/permissions/requestApproval":
      return { permissions: {}, scope: "turn", strictAutoReview: true };
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
  if (input.effort !== undefined && input.effort !== null) {
    const effort = normalizeRuntimeReasoningEffort(input.effort);
    if (!effort) {
      throw new Error("invalid_reasoning_effort");
    }
    params.effort = effort;
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
