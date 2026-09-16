import type {
  AttachmentFlags,
  HostEvent,
  ResolvedAnnotationAttachment,
  RuntimeModelInventory,
  RuntimeReasoningEffort,
  RuntimeToolInventory
} from "./types.js";
import type { BridgeToolsEnableResult, BridgeToolsRegistrationPlan, ProjectSummary } from "./types.js";
import { buildBridgeToolsRegistrationPlan } from "./bridgeToolsRegistration.js";

export type RuntimeApprovalPolicy = "on-request" | "never";
export type RuntimeSandboxMode = "read-only" | "workspace-write" | "danger-full-access";

export type RuntimeThreadOptions = {
  projectRoot: string;
  model?: string;
  effort?: RuntimeReasoningEffort | null;
  sandbox?: RuntimeSandboxMode;
  approvalPolicy?: RuntimeApprovalPolicy;
  background?: boolean;
};

export type RuntimeTurnInput = {
  threadId: string;
  projectRoot: string;
  message: string;
  attachments?: AttachmentFlags;
  annotation?: ResolvedAnnotationAttachment;
  model?: string | null;
  effort?: RuntimeReasoningEffort | null;
  sandbox?: RuntimeSandboxMode;
  approvalPolicy?: RuntimeApprovalPolicy;
};

export type RuntimeThreadHandle = {
  threadId: string;
  cwd: string;
  instructionSources: string[];
};

export type RuntimeTurnHandle = {
  turnId: string;
};

export interface CodexRuntimeAdapter {
  readonly kind: string;
  createBackgroundRuntime?(index: number): CodexRuntimeAdapter;
  inspectMcpTools?(threadId?: string): Promise<RuntimeToolInventory>;
  listModels?(): Promise<RuntimeModelInventory>;
  previewBridgeTools?(project: ProjectSummary): Promise<BridgeToolsRegistrationPlan>;
  enableBridgeTools?(project: ProjectSummary, evidenceDir: string): Promise<BridgeToolsEnableResult>;
  startThread(options: RuntimeThreadOptions): Promise<RuntimeThreadHandle>;
  runTurn(input: RuntimeTurnInput): AsyncIterable<HostEvent>;
  interruptTurn(threadId: string, turnId: string): Promise<void>;
  respondToApproval(approvalId: string, decision: "approve" | "approve_session" | "reject" | "revise" | "expired", note?: string): Promise<void>;
  shutdown(): Promise<void>;
}

export class MockCodexRuntime implements CodexRuntimeAdapter {
  readonly kind = "mock";
  private nextThread = 1;
  private activeTurn: { threadId: string; turnId: string; interrupted: boolean } | null = null;

  async startThread(options: RuntimeThreadOptions): Promise<RuntimeThreadHandle> {
    return {
      threadId: `mock-thread-${this.nextThread++}`,
      cwd: options.projectRoot,
      instructionSources: []
    };
  }

  createBackgroundRuntime(_index: number): CodexRuntimeAdapter {
    return new MockCodexRuntime();
  }

  async inspectMcpTools(_threadId?: string): Promise<RuntimeToolInventory> {
    const godotTools = [
      "godot.get_project_overview",
      "godot.list_project_files",
      "godot.search_project_files",
      "godot.read_project_file"
    ];
    return {
      available: true,
      serverName: "mock-godot-codex-bridge",
      toolCount: godotTools.length,
      godotToolCount: godotTools.length,
      godotTools,
      checkedAt: new Date().toISOString()
    };
  }

  async listModels(): Promise<RuntimeModelInventory> {
    return {
      models: [
        {
          id: "mock-gpt-5-codex",
          model: "gpt-5-codex",
          displayName: "GPT-5 Codex",
          description: "Mock local Codex model option.",
          isDefault: true,
          inputModalities: ["text", "image"],
          defaultReasoningEffort: "medium",
          supportedReasoningEfforts: [
            { reasoningEffort: "minimal", description: "Fastest lightweight reasoning." },
            { reasoningEffort: "low", description: "Fast iteration." },
            { reasoningEffort: "medium", description: "Balanced default." },
            { reasoningEffort: "high", description: "Deeper reasoning." },
            { reasoningEffort: "xhigh", description: "Maximum reasoning." }
          ]
        }
      ],
      defaultModel: "gpt-5-codex",
      reasoningEfforts: [
        { reasoningEffort: "minimal", description: "Fastest lightweight reasoning." },
        { reasoningEffort: "low", description: "Fast iteration." },
        { reasoningEffort: "medium", description: "Balanced default." },
        { reasoningEffort: "high", description: "Deeper reasoning." },
        { reasoningEffort: "xhigh", description: "Maximum reasoning." }
      ],
      checkedAt: new Date().toISOString()
    };
  }

  async previewBridgeTools(project: ProjectSummary): Promise<BridgeToolsRegistrationPlan> {
    return buildBridgeToolsRegistrationPlan(project);
  }

  async enableBridgeTools(project: ProjectSummary, evidenceDir: string): Promise<BridgeToolsEnableResult> {
    const plan = await this.previewBridgeTools(project);
    const inventory = await this.inspectMcpTools();
    return {
      applied: true,
      reloaded: true,
      evidencePath: `${evidenceDir}\\mock-enable-bridge-tools.json`,
      plan,
      inventory,
      checkedAt: new Date().toISOString()
    };
  }

  async *runTurn(input: RuntimeTurnInput): AsyncIterable<HostEvent> {
    const turnId = `mock-turn-${Date.now()}`;
    this.activeTurn = { threadId: input.threadId, turnId, interrupted: false };

    yield event("turn.started", {
      thread_id: input.threadId,
      turn_id: turnId
    });

    const attachmentNames = Object.entries(input.attachments ?? {})
      .filter(([, enabled]) => enabled)
      .map(([name]) => name);
    const text = [
      "Mock Codex Host connected.",
      `Project root: ${input.projectRoot}`,
      `Message: ${input.message}`,
      attachmentNames.length > 0 ? `Attachments: ${attachmentNames.join(", ")}` : "Attachments: none"
    ].join("\n");

    for (const line of text.split("\n")) {
      if (this.activeTurn?.interrupted) {
        yield event("turn.interrupted", {
          thread_id: input.threadId,
          turn_id: turnId
        });
        this.activeTurn = null;
        return;
      }
      yield event("turn.event", {
        thread_id: input.threadId,
        turn_id: turnId,
        event: "agent_message_delta",
        text: `${line}\n`
      });
    }

    if (input.message.includes("Validate approval flow")) {
      yield event("approval.requested", {
        runtime_approval_id: `mock-approval-${Date.now()}`,
        kind: "file_change",
        thread_id: input.threadId,
        turn_id: turnId,
        item_id: "mock-file-change",
        reason: "Mock validation file change",
        file_changes: {
          "res://mock_validation.gd": {
            type: "update",
            unified_diff: "@@\n-old\n+new\n"
          }
        },
        raw_method: "item/fileChange/requestApproval",
        raw_params: {}
      });
    }

    yield event("turn.completed", {
      thread_id: input.threadId,
      turn_id: turnId,
      status: "completed"
    });
    this.activeTurn = null;
  }

  async interruptTurn(threadId: string, turnId: string): Promise<void> {
    if (this.activeTurn?.threadId === threadId && this.activeTurn.turnId === turnId) {
      this.activeTurn.interrupted = true;
    }
  }

  async respondToApproval(_approvalId: string, _decision: "approve" | "approve_session" | "reject" | "revise" | "expired", _note?: string): Promise<void> {}

  async shutdown(): Promise<void> {}
}

export function event(method: HostEvent["method"], params: Record<string, unknown>): HostEvent {
  return {
    jsonrpc: "2.0",
    method,
    params
  };
}
