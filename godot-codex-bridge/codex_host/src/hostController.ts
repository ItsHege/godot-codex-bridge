import { EventEmitter } from "node:events";
import fs from "node:fs/promises";
import path from "node:path";
import { ApprovalGate } from "./approvalGate.js";
import { BackgroundAgentManager } from "./backgroundAgents.js";
import type { HostConfig } from "./config.js";
import type { CodexRuntimeAdapter } from "./codexRuntime.js";
import { event } from "./codexRuntime.js";
import { buildProjectOrientationBundle } from "./orientationBundle.js";
import { resolveProject } from "./projectRoots.js";
import { SessionStore } from "./sessionStore.js";
import type {
  ApprovalRespondParams,
  BackgroundCancelParams,
  BackgroundStartParams,
  HostEvent,
  HostSession,
  HostStatus,
  JsonRpcRequest,
  ProjectAttachParams,
  ProjectSummary,
  RuntimeModelInventory,
  RuntimeToolInventory,
  RuntimeState,
  ImageDetail,
  ResolvedAnnotationAttachment,
  SessionTrustSetParams,
  ThreadSendParams
} from "./types.js";
import { HOST_PROTOCOL_VERSION } from "./types.js";
import { createApprovalUndoSnapshot, type UndoSnapshotSummary } from "./undoEvidence.js";

export class HostController extends EventEmitter {
  private state: RuntimeState = "disconnected";
  private project: ProjectSummary | null = null;
  private store: SessionStore | null = null;
  private approvalGate: ApprovalGate | null = null;
  private backgroundManager: BackgroundAgentManager | null = null;
  private session: HostSession | null = null;
  private threadId: string | undefined;
  private turnId: string | undefined;
  private recoverableMessage: string | undefined;
  private fatalMessage: string | undefined;
  private toolInventory: RuntimeToolInventory | null = null;
  private modelInventory: RuntimeModelInventory | null = null;
  private trustMode: "off" | "full_machine" = "off";
  private readonly orientationSentThreadIds = new Set<string>();
  private readonly approvalExpiryTimer: NodeJS.Timeout;

  constructor(
    private readonly config: HostConfig,
    private readonly runtime: CodexRuntimeAdapter
  ) {
    super();
    this.state = "ready";
    this.approvalExpiryTimer = setInterval(() => {
      void this.sweepExpiredApprovals();
    }, 5000);
    this.approvalExpiryTimer.unref();
  }

  status(): HostStatus {
    return {
      protocolVersion: HOST_PROTOCOL_VERSION,
      state: this.state,
      runtime: this.runtime.kind,
      port: this.config.port,
      activeProject: this.project ?? undefined,
      threadId: this.threadId,
      turnId: this.turnId,
      pendingApprovals: this.approvalGate?.pendingCount() ?? 0,
      backgroundTasks: this.backgroundManager?.activeCount() ?? 0,
      eventQueueDepth: this.listenerCount("event"),
      updatedAt: new Date().toISOString(),
      recoverableMessage: this.recoverableMessage,
      fatalMessage: this.fatalMessage,
      mcpToolsAvailable: this.toolInventory?.available,
      mcpServerName: this.toolInventory?.serverName,
      mcpToolCount: this.toolInventory?.toolCount,
      mcpGodotToolCount: this.toolInventory?.godotToolCount,
      mcpGodotTools: this.toolInventory?.godotTools,
      lastToolInventoryAt: this.toolInventory?.checkedAt,
      toolVisibilityError: this.toolInventory?.error,
      trustMode: this.trustMode
    };
  }

  async handleRequest(request: JsonRpcRequest): Promise<unknown> {
    switch (request.method) {
      case "host.health":
        return this.status();
      case "host.reconnect":
        return this.reconnect();
      case "host.restart_for_project":
        return this.restartForProject(request.params as ProjectAttachParams);
      case "host.shutdown":
        return this.requestShutdown();
      case "project.attach":
        return this.attachProject(request.params as ProjectAttachParams);
      case "thread.start":
        return this.startThread();
      case "thread.resume":
        return this.resumeThread(request.params as { thread_id?: string });
      case "thread.send":
        return this.sendThread(request.params as ThreadSendParams);
      case "turn.interrupt":
        return this.interruptTurn();
      case "context.refresh":
        return this.contextRefresh();
      case "background.start":
        return this.startBackgroundTask(request.params as BackgroundStartParams);
      case "background.status":
        return this.backgroundStatus();
      case "background.cancel":
        return this.cancelBackgroundTask(request.params as BackgroundCancelParams);
      case "approval.respond":
        return this.respondToApproval(request.params as ApprovalRespondParams);
      case "runtime.models.list":
        return this.listRuntimeModels();
      case "bridge.tools.preview":
        return this.previewBridgeTools();
      case "bridge.tools.enable":
        return this.enableBridgeTools();
      case "session.trust.set":
        return this.setTrustSession(request.params as SessionTrustSetParams);
      case "session.trust.clear":
        return this.clearTrustSession();
      default:
        throw new Error(`unknown_method: ${request.method}`);
    }
  }

  async shutdown(): Promise<void> {
    clearInterval(this.approvalExpiryTimer);
    await this.backgroundManager?.shutdown();
    await this.runtime.shutdown();
  }

  private async attachProject(
    params: ProjectAttachParams,
    options: {
      forceSessionReset?: boolean;
      clearTrust?: boolean;
      cleanupReason?: string;
      broadcastReconnect?: boolean;
    } = {}
  ): Promise<HostStatus> {
    const previousState = this.state;
    this.setState("connecting");
    try {
      const nextProject = await resolveProject(params.project_root, params.bridge_dir);
      const previousProjectRoot = this.project?.projectRoot;
      const projectChanged = Boolean(previousProjectRoot && previousProjectRoot !== nextProject.projectRoot);
      const sessionReset = Boolean(options.forceSessionReset || projectChanged);
      if (sessionReset && (previousState === "turn_running" || previousState === "waiting_for_approval" || previousState === "applying_diff")) {
        throw new Error(`host_busy: ${previousState}`);
      }
      let cleanupEvidencePath: string | undefined;
      if (sessionReset) {
        await this.backgroundManager?.shutdown();
        const trustWasEnabled = this.trustMode !== "off";
        if (options.clearTrust || projectChanged) {
          this.trustMode = "off";
        }
        this.threadId = undefined;
        this.turnId = undefined;
        this.toolInventory = null;
        this.modelInventory = null;
        this.orientationSentThreadIds.clear();
        if (options.cleanupReason) {
          cleanupEvidencePath = await this.writeHostCleanupEvidence(nextProject, {
            reason: options.cleanupReason,
            previous_project_root: previousProjectRoot ?? null,
            project_root: nextProject.projectRoot,
            session_reset: true,
            trust_was_enabled: trustWasEnabled,
            trust_cleared: trustWasEnabled && this.trustMode === "off",
            thread_cleared: true,
            turn_cleared: true,
            tool_inventory_cleared: true,
            model_inventory_cleared: true,
            background_shutdown_requested: true,
          });
        }
      }
      this.project = nextProject;
      this.store = new SessionStore(this.project.hostStateDir, this.config.maxReplayEvents);
      await this.store.init();
      this.approvalGate = new ApprovalGate(path.join(this.project.hostStateDir, "approvals"), () => this.trustMode);
      await this.approvalGate.init();
      this.backgroundManager = new BackgroundAgentManager(this.project, this.runtime, (hostEvent) => this.broadcast(hostEvent));
      this.session = {
        id: `session-${Date.now()}`,
        projectRoot: this.project.projectRoot,
        threadId: this.threadId,
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
        state: "ready",
        trustMode: this.trustMode
      };
      await this.store.saveSession(this.session);
      this.recoverableMessage = undefined;
      this.fatalMessage = undefined;
      await this.refreshToolInventory();
      this.setState("ready");
      if (options.broadcastReconnect) {
        await this.broadcast(
          event("host.reconnected", {
            project_root: this.project.projectRoot,
            previous_project_root: previousProjectRoot ?? null,
            trust_cleared: this.trustMode === "off",
            cleanup_evidence_path: cleanupEvidencePath ?? null,
          })
        );
      }
      await this.broadcastStatus();
      return this.status();
    } catch (error) {
      this.recoverableMessage = (error as Error).message;
      this.setState("error_recoverable");
      await this.broadcastStatus();
      throw error;
    }
  }

  private async restartForProject(params: ProjectAttachParams): Promise<HostStatus & {
    restartForProject: true;
    previousProjectRoot?: string;
    trustCleared: boolean;
  }> {
    const previousProjectRoot = this.project?.projectRoot;
    const status = await this.attachProject(params, {
      forceSessionReset: true,
      clearTrust: true,
      cleanupReason: "host.restart_for_project",
      broadcastReconnect: true,
    });
    return {
      ...status,
      restartForProject: true,
      previousProjectRoot,
      trustCleared: status.trustMode === "off",
    };
  }

  private async reconnect(): Promise<{ status: HostStatus; replay: HostEvent[] }> {
    const replay = this.store?.replayEvents() ?? [];
    await this.broadcast(
      event("host.reconnected", {
        replay_count: replay.length
      })
    );
    await this.broadcastStatus();
    return {
      status: this.status(),
      replay
    };
  }

  private requestShutdown(): { accepted: true; status: HostStatus } {
    setImmediate(() => this.emit("shutdownRequested"));
    return {
      accepted: true,
      status: this.status()
    };
  }

  private async startThread(options: { model?: string | null } = {}): Promise<{ thread_id: string; cwd: string; instruction_sources: string[] }> {
    const project = this.requireProject();
    const handle = await this.runtime.startThread({
      projectRoot: project.projectRoot,
      model: cleanOptionalString(options.model),
      sandbox: this.runtimeSandboxMode(),
      approvalPolicy: this.runtimeApprovalPolicy()
    });
    this.threadId = handle.threadId;
    await this.refreshToolInventory(handle.threadId);
    if (this.session) {
      this.session.threadId = this.threadId;
      this.session.updatedAt = new Date().toISOString();
      await this.store?.saveSession(this.session);
    }
    await this.broadcast(
      event("thread.started", {
        thread_id: handle.threadId,
        cwd: handle.cwd,
        instruction_sources: handle.instructionSources
      })
    );
    return {
      thread_id: handle.threadId,
      cwd: handle.cwd,
      instruction_sources: handle.instructionSources
    };
  }

  private async resumeThread(params: { thread_id?: string }): Promise<HostStatus> {
    if (params.thread_id) {
      this.threadId = params.thread_id;
    }
    await this.broadcastStatus();
    return this.status();
  }

  private async sendThread(params: ThreadSendParams): Promise<{ accepted: true; thread_id: string }> {
    const project = this.requireProject();
    if (this.state === "turn_running" || this.state === "waiting_for_approval" || this.state === "applying_diff") {
      await this.broadcast(
        event("runtime.backpressure", {
          state: this.state,
          message: "foreground_turn_busy"
        })
      );
      throw new Error(`host_busy: ${this.state}`);
    }
    if (!params.message || typeof params.message !== "string") {
      throw new Error("message_required");
    }
    if (params.thread_id) {
      this.threadId = params.thread_id;
    }
    if (!this.threadId) {
      await this.startThread({ model: params.model });
    }
    const threadId = this.threadId!;
    this.setState("turn_running");
    await this.broadcastStatus();
    void this.runForegroundTurn(project, threadId, params);
    return {
      accepted: true,
      thread_id: threadId
    };
  }

  private async runForegroundTurn(project: ProjectSummary, threadId: string, params: ThreadSendParams): Promise<void> {
    try {
      const annotation = await this.resolveAnnotationAttachment(project, params);
      const message = await this.buildForegroundMessage(project, threadId, params, annotation);
      for await (const runtimeEvent of this.runtime.runTurn({
        threadId,
        projectRoot: project.projectRoot,
        message,
        attachments: params.attachments,
        annotation,
        model: cleanOptionalString(params.model),
        effort: params.effort ?? null,
        sandbox: this.runtimeSandboxMode(),
        approvalPolicy: this.runtimeApprovalPolicy()
      })) {
        if (runtimeEvent.method === "turn.started") {
          this.turnId = String(runtimeEvent.params.turn_id ?? "");
          this.setState("turn_running");
        }
        const eventToBroadcast = runtimeEvent.method === "approval.requested"
          ? await this.prepareApprovalEvent(runtimeEvent)
          : runtimeEvent;
        if (eventToBroadcast.method === "approval.requested") {
          this.setState("waiting_for_approval");
        }
        if (runtimeEvent.method === "turn.completed" || runtimeEvent.method === "turn.interrupted") {
          this.turnId = undefined;
          this.setState("ready");
        }
        if (runtimeEvent.method === "error") {
          this.recoverableMessage = String(runtimeEvent.params.message ?? "runtime_error");
          this.setState("error_recoverable");
        }
        await this.broadcast(eventToBroadcast);
        await this.broadcastStatus();
      }
    } catch (error) {
      this.recoverableMessage = (error as Error).message;
      this.setState("error_recoverable");
      await this.broadcast(
        event("error", {
          recoverable: true,
          message: this.recoverableMessage
        })
      );
      await this.broadcastStatus();
    }
  }

  private async buildForegroundMessage(
    project: ProjectSummary,
    threadId: string,
    params: ThreadSendParams,
    annotation?: ResolvedAnnotationAttachment,
  ): Promise<string> {
    const includeOrientation = !this.orientationSentThreadIds.has(threadId);
    const orientation = includeOrientation ? await buildProjectOrientationBundle(project, this.toolInventory) : "";
    if (includeOrientation) {
      this.orientationSentThreadIds.add(threadId);
    }
    return `${params.message}\n\n${annotation ? `${annotation.summaryText}\n\n` : ""}${orientation}`;
  }

  private async interruptTurn(): Promise<{ interrupted: boolean; thread_id?: string; turn_id?: string }> {
    if (!this.threadId || !this.turnId) {
      return { interrupted: false };
    }
    await this.runtime.interruptTurn(this.threadId, this.turnId);
    const previousTurn = this.turnId;
    await this.broadcast(
      event("turn.interrupted", {
        thread_id: this.threadId,
        turn_id: previousTurn
      })
    );
    this.turnId = undefined;
    this.setState("ready");
    await this.broadcastStatus();
    return {
      interrupted: true,
      thread_id: this.threadId,
      turn_id: previousTurn
    };
  }

  private contextRefresh(): { bridge_context: string; available: boolean } {
    const project = this.requireProject();
    return {
      bridge_context: `${project.bridgeDir}\\context_snapshot.json`,
      available: true
    };
  }

  private async startBackgroundTask(params: BackgroundStartParams): Promise<{ task_id: string; state: string }> {
    this.requireProject();
    if (!this.backgroundManager) {
      throw new Error("background_manager_unavailable");
    }
    const summary = await this.backgroundManager.start(params);
    await this.broadcastStatus();
    return {
      task_id: summary.task_id,
      state: summary.state
    };
  }

  private backgroundStatus(): { active_tasks: number; tasks: unknown[] } {
    return {
      active_tasks: this.backgroundManager?.activeCount() ?? 0,
      tasks: this.backgroundManager?.summaries() ?? []
    };
  }

  private async cancelBackgroundTask(params: BackgroundCancelParams): Promise<{ cancelled: boolean; task_id?: string; active_tasks: number }> {
    if (!this.backgroundManager) {
      throw new Error("background_manager_unavailable");
    }
    const result = await this.backgroundManager.cancel(params);
    await this.broadcastStatus();
    return result;
  }

  private async respondToApproval(params: ApprovalRespondParams): Promise<{ accepted: true; decision: string }> {
    if (!this.approvalGate) {
      throw new Error("approval_gate_unavailable");
    }
    const { approval, runtimeDecision } = await this.approvalGate.resolve(params);
    let undoSnapshot: UndoSnapshotSummary | undefined;
    if ((runtimeDecision === "approve" || runtimeDecision === "approve_session") && (approval.kind === "file_change" || approval.kind === "apply_patch")) {
      this.setState("applying_diff");
      await this.broadcastStatus();
      undoSnapshot = await createApprovalUndoSnapshot(this.requireProject(), approval);
    }
    await this.runtime.respondToApproval(approval.runtime_approval_id, runtimeDecision, params.note ?? "");
    await this.broadcast(event(runtimeDecision === "expired" ? "approval.expired" : "approval.resolved", {
      approval_id: approval.approval_id,
      runtime_approval_id: approval.runtime_approval_id,
      decision: runtimeDecision,
      status: approval.status,
      undo_snapshot_path: undoSnapshot?.manifest_path,
      undo_snapshot_file_count: undoSnapshot?.copied_count,
      note: params.note ?? ""
    }));
    this.setState("ready");
    await this.broadcastStatus();
    return {
      accepted: true,
      decision: runtimeDecision
    };
  }

  private async setTrustSession(params: SessionTrustSetParams = {}): Promise<HostStatus & { trustSessionChanged: true }> {
    const mode = params.mode ?? "full_machine";
    if (mode !== "full_machine") {
      throw new Error(`unsupported_trust_mode: ${mode}`);
    }
    if (this.state === "turn_running" || this.state === "waiting_for_approval" || this.state === "applying_diff") {
      throw new Error(`host_busy: ${this.state}`);
    }
    this.trustMode = mode;
    this.threadId = undefined;
    this.turnId = undefined;
    this.orientationSentThreadIds.clear();
    if (this.session) {
      this.session.threadId = undefined;
      this.session.trustMode = this.trustMode;
      this.session.updatedAt = new Date().toISOString();
      await this.store?.saveSession(this.session);
    }
    await this.broadcast(event("runtime.warning", {
      message: "Trust Session enabled: full machine access for new turns until cleared or the host restarts.",
      trustMode: this.trustMode
    }));
    await this.broadcastStatus();
    return {
      ...this.status(),
      trustSessionChanged: true
    };
  }

  private async clearTrustSession(): Promise<HostStatus & { trustSessionChanged: true }> {
    if (this.state === "turn_running" || this.state === "waiting_for_approval" || this.state === "applying_diff") {
      throw new Error(`host_busy: ${this.state}`);
    }
    this.trustMode = "off";
    this.threadId = undefined;
    this.turnId = undefined;
    this.orientationSentThreadIds.clear();
    if (this.session) {
      this.session.threadId = undefined;
      this.session.trustMode = this.trustMode;
      this.session.updatedAt = new Date().toISOString();
      await this.store?.saveSession(this.session);
    }
    await this.broadcastStatus();
    return {
      ...this.status(),
      trustSessionChanged: true
    };
  }

  private async previewBridgeTools(): Promise<unknown> {
    const project = this.requireProject();
    if (!this.runtime.previewBridgeTools) {
      throw new Error("bridge_tools_registration_unavailable");
    }
    return {
      bridgeToolsPreview: true,
      plan: await this.runtime.previewBridgeTools(project),
      status: this.status()
    };
  }

  private async listRuntimeModels(): Promise<RuntimeModelInventory> {
    if (!this.runtime.listModels) {
      return {
        models: [],
        reasoningEfforts: [
          { reasoningEffort: "minimal", description: "Fastest lightweight reasoning." },
          { reasoningEffort: "low", description: "Fast iteration." },
          { reasoningEffort: "medium", description: "Balanced default." },
          { reasoningEffort: "high", description: "Deeper reasoning." },
          { reasoningEffort: "xhigh", description: "Maximum reasoning." }
        ],
        checkedAt: new Date().toISOString(),
        error: "This runtime does not expose model inventory."
      };
    }
    this.modelInventory = await this.runtime.listModels();
    return this.modelInventory;
  }

  private async enableBridgeTools(): Promise<unknown> {
    const project = this.requireProject();
    if (!this.runtime.enableBridgeTools) {
      throw new Error("bridge_tools_registration_unavailable");
    }
    const result = await this.runtime.enableBridgeTools(project, path.join(project.hostStateDir, "bridge_tools"));
    this.toolInventory = result.inventory;
    await this.broadcastStatus();
    return {
      ...this.status(),
      bridgeToolsEnabled: result.applied,
      bridgeToolsReloaded: result.reloaded,
      bridgeToolsEvidencePath: result.evidencePath,
      bridgeToolsPlan: result.plan
    };
  }

  private async prepareApprovalEvent(runtimeEvent: HostEvent): Promise<HostEvent> {
    if (!this.approvalGate) {
      throw new Error("approval_gate_unavailable");
    }
    const raw = runtimeEvent.params;
    const approval = await this.approvalGate.create({
      runtime_approval_id: String(raw.runtime_approval_id ?? raw.approval_id ?? ""),
      kind: raw.kind as never,
      thread_id: raw.thread_id ? String(raw.thread_id) : undefined,
      turn_id: raw.turn_id ? String(raw.turn_id) : undefined,
      item_id: raw.item_id ? String(raw.item_id) : undefined,
      reason: raw.reason === undefined ? null : String(raw.reason),
      cwd: raw.cwd === undefined || raw.cwd === null ? null : String(raw.cwd),
      command: raw.command as never,
      grant_root: raw.grant_root === undefined || raw.grant_root === null ? null : String(raw.grant_root),
      diff_evidence: raw.diff_evidence,
      file_changes: raw.file_changes,
      raw_method: String(raw.raw_method ?? "unknown"),
      raw_params: raw.raw_params ?? raw
    });
    return event("approval.requested", approval as unknown as Record<string, unknown>);
  }

  private async resolveAnnotationAttachment(
    project: ProjectSummary,
    params: ThreadSendParams,
  ): Promise<ResolvedAnnotationAttachment | undefined> {
    if (!params.annotation) {
      return undefined;
    }
    const annotationId = cleanAnnotationId(params.annotation.annotation_id ?? params.annotation.annotationId);
    const baseDir = path.join(project.bridgeDir, "artifacts", "annotations");
    const annotationDir = path.resolve(baseDir, annotationId);
    ensureInside(baseDir, annotationDir, "annotation_path_outside_bridge");

    const manifestPath = path.join(annotationDir, "annotation.json");
    const stat = await fs.stat(manifestPath).catch(() => null);
    if (!stat?.isFile()) {
      throw new Error(`annotation_not_found: ${annotationId}`);
    }
    if (stat.size > 256_000) {
      throw new Error(`annotation_manifest_too_large: ${annotationId}`);
    }

    const manifest = parseJsonObject(await fs.readFile(manifestPath, "utf8"), `annotation_manifest_invalid: ${annotationId}`);
    const rawImagePath = path.join(annotationDir, "raw.png");
    const annotatedImagePath = path.join(annotationDir, "annotated.png");
    const includeImage = params.annotation.include_image !== false && params.annotation.includeImage !== false;
    const imageSupported = includeImage ? await this.selectedModelSupportsImage(params.model) : false;
    const annotatedExists = await fileExists(annotatedImagePath);
    const imageAttached = includeImage && imageSupported && annotatedExists;
    const imageAttachmentReason = imageAttached
      ? undefined
      : includeImage
        ? imageSupported
          ? "annotated PNG is missing; passing metadata summary only"
          : "selected/default model did not report image input support; passing metadata summary only"
        : "image attachment was disabled by request";
    const detail = validImageDetail(params.annotation.detail);
    return {
      annotationId,
      manifestPath,
      rawImagePath,
      annotatedImagePath,
      imageAttached,
      imageAttachmentReason,
      detail,
      manifest,
      summaryText: buildAnnotationSummary({
        annotationId,
        manifest,
        manifestPath,
        rawImagePath,
        annotatedImagePath,
        imageAttached,
        imageAttachmentReason,
      }),
    };
  }

  private async selectedModelSupportsImage(model: string | null | undefined): Promise<boolean> {
    if (!this.runtime.listModels) {
      return false;
    }
    try {
      this.modelInventory = await this.runtime.listModels();
    } catch (error) {
      await this.broadcast(event("runtime.warning", {
        message: `annotation_model_inventory_failed: ${(error as Error).message}`,
      }));
      return false;
    }
    const inventory = this.modelInventory;
    const selectedModel = cleanOptionalString(model) ?? inventory.defaultModel;
    const modelInfo = selectedModel
      ? inventory.models.find((item) => item.model === selectedModel || item.id === selectedModel)
      : inventory.models.find((item) => item.isDefault) ?? inventory.models[0];
    return Array.isArray(modelInfo?.inputModalities) && modelInfo.inputModalities.includes("image");
  }

  private requireProject(): ProjectSummary {
    if (!this.project) {
      throw new Error("project_not_attached");
    }
    return this.project;
  }

  private async refreshToolInventory(threadId?: string): Promise<void> {
    if (!this.runtime.inspectMcpTools) {
      this.toolInventory = {
        available: false,
        serverName: null,
        toolCount: 0,
        godotToolCount: 0,
        godotTools: [],
        checkedAt: new Date().toISOString(),
        error: "This runtime does not expose MCP tool inventory."
      };
      return;
    }
    try {
      this.toolInventory = await this.runtime.inspectMcpTools(threadId);
    } catch (error) {
      this.toolInventory = {
        available: false,
        serverName: null,
        toolCount: 0,
        godotToolCount: 0,
        godotTools: [],
        checkedAt: new Date().toISOString(),
        error: `tool_inventory_failed: ${(error as Error).message}`
      };
    }
  }

  private runtimeApprovalPolicy(): "on-request" | "never" {
    return runtimeApprovalPolicyForTrust(this.trustMode);
  }

  private runtimeSandboxMode(): "read-only" | "danger-full-access" {
    return runtimeSandboxForTrust(this.trustMode);
  }

  private setState(state: RuntimeState): void {
    this.state = state;
    if (this.session) {
      this.session.state = state;
      this.session.trustMode = this.trustMode;
      this.session.updatedAt = new Date().toISOString();
    }
  }

  private async sweepExpiredApprovals(): Promise<void> {
    if (!this.approvalGate) {
      return;
    }
    const expired = await this.approvalGate.expireDue();
    if (expired.length === 0) {
      return;
    }
    for (const approval of expired) {
      try {
        await this.runtime.respondToApproval(approval.runtime_approval_id, "expired");
        await this.broadcast(event("approval.expired", {
          approval_id: approval.approval_id,
          runtime_approval_id: approval.runtime_approval_id,
          decision: "expired",
          status: approval.status
        }));
      } catch (error) {
        await this.broadcast(event("runtime.warning", {
          message: `approval_expiry_response_failed: ${(error as Error).message}`,
          approval_id: approval.approval_id
        }));
      }
    }
    this.setState(this.turnId ? "turn_running" : "ready");
    await this.broadcastStatus();
  }

  private async broadcastStatus(): Promise<void> {
    await this.broadcast(event("host.status", this.status() as unknown as Record<string, unknown>));
  }

  private async broadcast(hostEvent: HostEvent): Promise<void> {
    await this.store?.appendEvent(hostEvent);
    this.emit("event", hostEvent);
  }

  private async writeHostCleanupEvidence(project: ProjectSummary, payload: Record<string, unknown>): Promise<string | undefined> {
    try {
      const cleanupDir = path.join(project.bridgeDir, "artifacts", "codex_host_cleanup");
      await fs.mkdir(cleanupDir, { recursive: true });
      const filePath = path.join(cleanupDir, `host-cleanup-${Date.now()}.json`);
      await fs.writeFile(filePath, JSON.stringify({
        cleanup_version: "godot-codex-bridge/host-cleanup-v1",
        created_at: new Date().toISOString(),
        bridge_dir: project.bridgeDir,
        host_state_dir: project.hostStateDir,
        ...payload,
      }, null, 2), "utf8");
      return filePath;
    } catch (error) {
      await this.broadcast(event("runtime.warning", {
        message: `host_cleanup_evidence_failed: ${(error as Error).message}`,
      }));
      return undefined;
    }
  }
}

function cleanOptionalString(value: string | null | undefined): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function runtimeApprovalPolicyForTrust(trustMode: "off" | "full_machine"): "on-request" | "never" {
  return trustMode === "full_machine" ? "never" : "on-request";
}

function runtimeSandboxForTrust(trustMode: "off" | "full_machine"): "read-only" | "danger-full-access" {
  return trustMode === "full_machine" ? "danger-full-access" : "read-only";
}

function cleanAnnotationId(value: unknown): string {
  if (typeof value !== "string") {
    throw new Error("annotation_id_required");
  }
  const annotationId = value.trim();
  if (!/^[A-Za-z0-9_.-]{1,128}$/.test(annotationId) || annotationId.includes("..")) {
    throw new Error("invalid_annotation_id");
  }
  return annotationId;
}

function validImageDetail(value: unknown): ImageDetail {
  return value === "auto" || value === "low" || value === "original" || value === "high" ? value : "high";
}

function parseJsonObject(raw: string, errorPrefix: string): Record<string, unknown> {
  try {
    const parsed = JSON.parse(raw) as unknown;
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new Error("root is not an object");
    }
    return parsed as Record<string, unknown>;
  } catch (error) {
    throw new Error(`${errorPrefix}: ${(error as Error).message}`);
  }
}

async function fileExists(filePath: string): Promise<boolean> {
  const stat = await fs.stat(filePath).catch(() => null);
  return stat?.isFile() === true;
}

function ensureInside(baseDir: string, candidate: string, code: string): void {
  const relative = path.relative(path.resolve(baseDir), path.resolve(candidate));
  if (relative.startsWith("..") || path.isAbsolute(relative)) {
    throw new Error(code);
  }
}

function buildAnnotationSummary(input: {
  annotationId: string;
  manifest: Record<string, unknown>;
  manifestPath: string;
  rawImagePath: string;
  annotatedImagePath: string;
  imageAttached: boolean;
  imageAttachmentReason?: string;
}): string {
  const markers = Array.isArray(input.manifest.markers) ? input.manifest.markers : [];
  const markerSummary = markers
    .slice(0, 12)
    .map((marker) => {
      if (!marker || typeof marker !== "object" || Array.isArray(marker)) {
        return null;
      }
      const record = marker as Record<string, unknown>;
      const id = typeof record.id === "string" ? record.id : "?";
      const type = typeof record.type === "string" ? record.type : "unknown";
      const label = typeof record.label === "string" && record.label.trim() ? ` label=${singleLine(record.label, 80)}` : "";
      const bounds = record.normalized_bounds && typeof record.normalized_bounds === "object"
        ? ` bounds=${JSON.stringify(record.normalized_bounds)}`
        : "";
      return `${id}:${type}${label}${bounds}`;
    })
    .filter((item): item is string => Boolean(item));
  return [
    "[Godot AI Marker attachment]",
    "Attached marks are user reference annotations. Do not recreate, draw, or implement the marker graphics in the game.",
    "Use marker labels like A/B/C only to identify the user's referenced area.",
    `Annotation id: ${input.annotationId}`,
    `Role: ${String(input.manifest.annotation_role ?? "user_reference_marker")}`,
    `Capture scope: ${String(input.manifest.capture_scope ?? "unknown")}`,
    `Current scene: ${String(input.manifest.current_scene ?? "unknown")}`,
    `Markers (${markers.length}): ${markerSummary.join("; ") || "none"}`,
    `Manifest path: ${input.manifestPath}`,
    `Annotated image path: ${input.annotatedImagePath}`,
    `Raw image path: ${input.rawImagePath}`,
    `Image attached to turn: ${input.imageAttached ? "yes" : "no"}${input.imageAttachmentReason ? ` (${input.imageAttachmentReason})` : ""}`,
    "[/Godot AI Marker attachment]",
  ].join("\n");
}

function singleLine(value: string, maxLength: number): string {
  const compact = value.replace(/\s+/g, " ").trim();
  return compact.length <= maxLength ? compact : `${compact.slice(0, Math.max(0, maxLength - 15))}... [truncated]`;
}
