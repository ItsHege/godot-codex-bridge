export const HOST_PROTOCOL_VERSION = "0.1.0";

export const RUNTIME_STATES = [
  "disconnected",
  "connecting",
  "ready",
  "turn_running",
  "waiting_for_approval",
  "applying_diff",
  "error_recoverable",
  "error_fatal"
] as const;

export type RuntimeState = (typeof RUNTIME_STATES)[number];

export type TrustMode = "off" | "full_machine";

export type JsonRpcId = string | number | null;

export type JsonRpcRequest = {
  jsonrpc?: "2.0";
  id?: JsonRpcId;
  method: string;
  params?: unknown;
};

export type JsonRpcResponse = {
  jsonrpc: "2.0";
  id: JsonRpcId;
  result?: unknown;
  error?: {
    code: number;
    message: string;
    data?: unknown;
  };
};

export type HostEventMethod =
  | "host.status"
  | "host.reconnected"
  | "thread.started"
  | "turn.started"
  | "turn.event"
  | "turn.interrupted"
  | "turn.completed"
  | "approval.requested"
  | "approval.resolved"
  | "approval.expired"
  | "background.updated"
  | "runtime.warning"
  | "runtime.backpressure"
  | "error";

export type HostEvent = {
  jsonrpc: "2.0";
  method: HostEventMethod;
  params: Record<string, unknown>;
};

export type AttachmentFlags = {
  context_snapshot?: boolean;
  selected_nodes?: boolean;
  latest_screenshot?: boolean;
  latest_annotation?: boolean;
  gameplay_context?: boolean;
  script_inventory?: boolean;
};

export type ImageDetail = "auto" | "low" | "high" | "original";

export type VisualAnnotationAttachment = {
  annotation_id?: string;
  annotationId?: string;
  include_image?: boolean;
  includeImage?: boolean;
  detail?: ImageDetail;
};

export type ResolvedAnnotationAttachment = {
  annotationId: string;
  manifestPath: string;
  rawImagePath: string;
  annotatedImagePath: string;
  imageAttached: boolean;
  imageAttachmentReason?: string;
  detail: ImageDetail;
  summaryText: string;
  manifest: Record<string, unknown>;
};

export type RuntimeToolInventory = {
  available: boolean;
  serverName: string | null;
  toolCount: number;
  godotToolCount: number;
  godotTools: string[];
  checkedAt: string;
  error?: string;
};

export type RuntimeReasoningEffort = "none" | "minimal" | "low" | "medium" | "high" | "xhigh";

export type RuntimeReasoningEffortOption = {
  reasoningEffort: RuntimeReasoningEffort;
  description?: string;
};

export type RuntimeModelOption = {
  id: string;
  model: string;
  displayName: string;
  description?: string;
  hidden?: boolean;
  isDefault?: boolean;
  inputModalities?: string[];
  defaultReasoningEffort?: RuntimeReasoningEffort;
  supportedReasoningEfforts: RuntimeReasoningEffortOption[];
};

export type RuntimeModelInventory = {
  models: RuntimeModelOption[];
  defaultModel?: string;
  reasoningEfforts: RuntimeReasoningEffortOption[];
  checkedAt: string;
  error?: string;
};

export type BridgeToolsRegistrationPlan = {
  serverName: string;
  keyPath: string;
  projectRoot: string;
  bridgeDir: string;
  productRoot: string;
  mcpServerEntry: string;
  mcpServerConfig: {
    command: string;
    args: string[];
    env: Record<string, string>;
  };
  ready: boolean;
  existingConfigPresent: boolean;
  alreadyConfigured: boolean;
  previousConfigSha256?: string;
  warnings: string[];
};

export type BridgeToolsEnableResult = {
  applied: boolean;
  reloaded: boolean;
  evidencePath?: string;
  plan: BridgeToolsRegistrationPlan;
  inventory: RuntimeToolInventory;
  checkedAt: string;
};

export type ProjectSummary = {
  projectRoot: string;
  projectFile: string;
  bridgeDir: string;
  hostStateDir: string;
  agentsFiles: Array<{
    path: string;
    sha256: string;
    bytes: number;
  }>;
};

export type HostStatus = {
  protocolVersion: string;
  state: RuntimeState;
  runtime: string;
  port: number;
  activeProject?: ProjectSummary;
  threadId?: string;
  turnId?: string;
  pendingApprovals: number;
  backgroundTasks: number;
  eventQueueDepth: number;
  updatedAt: string;
  recoverableMessage?: string;
  fatalMessage?: string;
  mcpToolsAvailable?: boolean;
  mcpServerName?: string | null;
  mcpToolCount?: number;
  mcpGodotToolCount?: number;
  mcpGodotTools?: string[];
  lastToolInventoryAt?: string;
  toolVisibilityError?: string;
  trustMode: TrustMode;
};

export type ProjectAttachParams = {
  project_root: string;
  bridge_dir?: string;
};

export type ThreadSendParams = {
  thread_id?: string;
  message: string;
  attachments?: AttachmentFlags;
  annotation?: VisualAnnotationAttachment | null;
  model?: string | null;
  effort?: RuntimeReasoningEffort | null;
};

export type SessionTrustSetParams = {
  mode?: TrustMode;
};

export type BackgroundStartParams = {
  prompt: string;
  roles?: string[];
};

export type BackgroundCancelParams = {
  task_id?: string;
};

export type BackgroundTaskState =
  | "queued"
  | "running"
  | "summarizing"
  | "completed"
  | "failed"
  | "cancelled";

export type BackgroundRoleState =
  | "queued"
  | "running"
  | "completed"
  | "failed"
  | "cancelled";

export type BackgroundRoleResult = {
  role: string;
  state: BackgroundRoleState;
  thread_id?: string;
  turn_id?: string;
  started_at?: string;
  completed_at?: string;
  output?: string;
  warnings?: string[];
  error?: string;
  artifact_path?: string;
};

export type BackgroundTaskSummary = {
  task_id: string;
  state: BackgroundTaskState;
  prompt: string;
  roles: string[];
  sandbox: "read-only";
  project_root: string;
  task_dir: string;
  created_at: string;
  updated_at: string;
  completed_at?: string;
  summary?: string;
  summary_path?: string;
  results: BackgroundRoleResult[];
  error?: string;
};

export type ApprovalRespondParams = {
  approval_id: string;
  nonce: string;
  diff_hash?: string;
  decision: "approve" | "approve_session" | "reject" | "revise";
  note?: string;
};

export type RuntimeApprovalKind =
  | "file_change"
  | "command_execution"
  | "permissions"
  | "apply_patch"
  | "exec_command"
  | "user_input"
  | "tool_call"
  | "elicitation"
  | "unknown";

export type RuntimeApprovalRequest = {
  runtime_approval_id: string;
  kind: RuntimeApprovalKind;
  thread_id?: string;
  turn_id?: string;
  item_id?: string;
  reason?: string | null;
  cwd?: string | null;
  command?: string | string[] | null;
  grant_root?: string | null;
  diff_evidence?: unknown;
  file_changes?: unknown;
  raw_method: string;
  raw_params: unknown;
};

export type HostApproval = RuntimeApprovalRequest & {
  approval_id: string;
  nonce: string;
  status: "pending" | "approved" | "approved_session" | "rejected" | "revised" | "expired";
  created_at: string;
  expires_at: string;
  diff_hash?: string;
  safe_default: "reject" | "manual_only";
  approvable_by_chat: boolean;
  blocked_reason: string | null;
  required_evidence: string[];
  approval_policy_label: string;
};

export type HostSession = {
  id: string;
  projectRoot: string;
  threadId?: string;
  createdAt: string;
  updatedAt: string;
  state: RuntimeState;
  trustMode: TrustMode;
};
