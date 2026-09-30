import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import { ensureDirectoryInsideRootSync, writeFileInsideRootSync } from "./physicalPath.js";
import type { ApprovalRespondParams, HostApproval, RuntimeApprovalRequest, TrustMode } from "./types.js";

const APPROVAL_TTL_MS = 5 * 60 * 1000;
const MAX_APPROVAL_FILES = 24;
const MAX_APPROVAL_DIFF_LINES_PER_FILE = 360;
const MAX_APPROVAL_COMMAND_CHARS = 1000;

export class ApprovalGate {
  private readonly approvals = new Map<string, HostApproval>();
  private readonly approvalIdsByRuntimeId = new Map<string, string>();
  private writeChain: Promise<void> = Promise.resolve();

  constructor(
    private readonly approvalDir: string,
    private readonly trustMode: () => TrustMode = () => "off",
    private readonly physicalRoot: string = path.dirname(approvalDir),
  ) {}

  async init(): Promise<void> {
    ensureDirectoryInsideRootSync(this.physicalRoot, this.approvalDir);
  }

  get(approvalId: string): HostApproval | undefined {
    return this.approvals.get(approvalId);
  }

  async create(runtimeRequest: RuntimeApprovalRequest): Promise<HostApproval> {
    await this.init();
    const createdAt = new Date();
    const diffHash = hashMaybe(runtimeRequest.diff_evidence ?? runtimeRequest.file_changes);
    const policy = approvalPolicyFor(runtimeRequest, diffHash, this.trustMode());
    const approval: HostApproval = {
      ...runtimeRequest,
      approval_id: `approval-${crypto.randomUUID()}`,
      nonce: crypto.randomBytes(16).toString("hex"),
      status: "pending",
      created_at: createdAt.toISOString(),
      expires_at: new Date(createdAt.getTime() + APPROVAL_TTL_MS).toISOString(),
      diff_hash: diffHash,
      ...policy
    };
    this.approvals.set(approval.approval_id, approval);
    this.approvalIdsByRuntimeId.set(approval.runtime_approval_id, approval.approval_id);
    await this.writeApproval(approval);
    return approval;
  }

  async resolve(params: ApprovalRespondParams): Promise<{ approval: HostApproval; runtimeDecision: "approve" | "approve_session" | "reject" | "revise" | "expired" }> {
    const begun = await this.beginResolve(params);
    await this.completeResolve(begun.approval.approval_id, begun.runtimeDecision);
    return begun;
  }

  async beginResolve(params: ApprovalRespondParams): Promise<{ approval: HostApproval; runtimeDecision: "approve" | "approve_session" | "reject" | "revise" }> {
    const approval = this.approvals.get(params.approval_id);
    if (!approval) {
      throw new Error(`unknown_approval: ${params.approval_id}`);
    }
    if (approval.status !== "pending") {
      throw new Error(`approval_not_pending: ${params.approval_id}`);
    }
    if (params.nonce !== approval.nonce) {
      throw new Error(`approval_nonce_mismatch: ${params.approval_id}`);
    }
    if (Date.now() > Date.parse(approval.expires_at)) {
      throw new Error(`approval_expired: ${params.approval_id}`);
    }

    if (params.decision === "approve" || params.decision === "approve_session") {
      if (!approval.approvable_by_chat || approval.safe_default !== "manual_only") {
        throw new Error(`approval_not_approvable_by_chat: ${approval.kind}`);
      }
      if (params.decision === "approve_session" && approval.kind !== "command_execution" && approval.kind !== "exec_command") {
        throw new Error(`approval_session_scope_not_allowed: ${approval.kind}`);
      }
      if (approval.kind === "file_change" || approval.kind === "apply_patch") {
        if (!approval.diff_hash) {
          throw new Error(`approval_diff_hash_required: ${approval.kind}`);
        }
        if (params.diff_hash !== approval.diff_hash) {
          throw new Error(`approval_diff_hash_mismatch: ${approval.kind}`);
        }
      }
      approval.status = "responding";
      await this.writeApproval(approval);
      return { approval, runtimeDecision: params.decision };
    }

    if (params.decision === "revise") {
      approval.status = "responding";
      await this.writeApproval(approval);
      return { approval, runtimeDecision: "revise" };
    }

    approval.status = "responding";
    await this.writeApproval(approval);
    return { approval, runtimeDecision: "reject" };
  }

  async completeResolve(approvalId: string, decision: "approve" | "approve_session" | "reject" | "revise" | "expired"): Promise<HostApproval> {
    const approval = this.requireApproval(approvalId);
    const expected = decision === "expired" ? "expiring" : "responding";
    if (approval.status !== expected) {
      throw new Error(`approval_not_${expected}: ${approvalId}`);
    }
    approval.status = decision === "approve_session" ? "approved_session"
      : decision === "approve" ? "approved"
        : decision === "reject" ? "rejected"
          : decision === "revise" ? "revised" : "expired";
    this.approvalIdsByRuntimeId.delete(approval.runtime_approval_id);
    await this.writeApproval(approval);
    return approval;
  }

  async abortResolve(approvalId: string): Promise<HostApproval | null> {
    const approval = this.approvals.get(approvalId);
    if (!approval || (approval.status !== "responding" && approval.status !== "expiring")) {
      return null;
    }
    approval.status = "pending";
    await this.writeApproval(approval);
    return approval;
  }

  async invalidateByRuntimeId(runtimeApprovalId: string, reason: string, status: "resolved_by_server" | "invalidated" = "resolved_by_server"): Promise<HostApproval | null> {
    const approvalId = this.approvalIdsByRuntimeId.get(runtimeApprovalId);
    const approval = approvalId ? this.approvals.get(approvalId) : undefined;
    if (!approval || (approval.status !== "pending" && approval.status !== "responding" && approval.status !== "expiring")) {
      return null;
    }
    approval.status = status;
    approval.invalidated_at = new Date().toISOString();
    approval.invalidation_reason = reason;
    this.approvalIdsByRuntimeId.delete(runtimeApprovalId);
    await this.writeApproval(approval);
    return approval;
  }

  pendingCount(): number {
    return [...this.approvals.values()].filter((approval) => approval.status === "pending").length;
  }

  pendingApprovals(): HostApproval[] {
    return [...this.approvals.values()].filter((approval) => approval.status === "pending");
  }

  async beginExpireDue(now = Date.now()): Promise<HostApproval[]> {
    const expired: HostApproval[] = [];
    for (const approval of this.approvals.values()) {
      if (approval.status === "pending" && now > Date.parse(approval.expires_at)) {
        approval.status = "expiring";
        expired.push(approval);
        await this.writeApproval(approval);
      }
    }
    return expired;
  }

  async expireDue(now = Date.now()): Promise<HostApproval[]> {
    const expired = await this.beginExpireDue(now);
    for (const approval of expired) {
      await this.completeResolve(approval.approval_id, "expired");
    }
    return expired;
  }

  private requireApproval(approvalId: string): HostApproval {
    const approval = this.approvals.get(approvalId);
    if (!approval) {
      throw new Error(`unknown_approval: ${approvalId}`);
    }
    return approval;
  }

  private async writeApproval(approval: HostApproval): Promise<void> {
    const filePath = path.join(this.approvalDir, `${safeFileName(approval.approval_id)}.json`);
    const snapshot = `${JSON.stringify(approval, null, 2)}\n`;
    const write = this.writeChain.then(async () => {
      await this.init();
      writeFileInsideRootSync(this.physicalRoot, filePath, snapshot);
    });
    this.writeChain = write.catch(() => undefined);
    await write;
  }
}

function hashMaybe(value: unknown): string | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }
  return crypto.createHash("sha256").update(JSON.stringify(value)).digest("hex");
}

function safeFileName(value: string): string {
  return value.replace(/[^a-zA-Z0-9._-]/g, "_");
}

type ApprovalPolicyFields = Pick<HostApproval, "safe_default" | "approvable_by_chat" | "blocked_reason" | "required_evidence" | "approval_policy_label">;

const DIFF_APPROVAL_EVIDENCE = ["nonce", "diff_hash", "displayed_diff_matches_hash"];
const DIFF_APPROVAL_BLOCKED_EVIDENCE = ["diff_hash", "displayed_diff_evidence"];
const ELICITATION_APPROVAL_EVIDENCE = ["nonce", "user_response"];
const COMMAND_APPROVAL_EVIDENCE = ["nonce", "displayed_command_reviewed"];

function approvalPolicyFor(request: RuntimeApprovalRequest, diffHash: string | undefined, trustMode: TrustMode): ApprovalPolicyFields {
  if (request.kind === "file_change" || request.kind === "apply_patch") {
    if (diffHash && diffIsFullyReviewable(request.diff_evidence ?? request.file_changes)) {
      return {
        safe_default: "manual_only",
        approvable_by_chat: true,
        blocked_reason: null,
        required_evidence: [...DIFF_APPROVAL_EVIDENCE],
        approval_policy_label: "Manual diff approval"
      };
    }
    return {
      safe_default: "reject",
      approvable_by_chat: false,
      blocked_reason: "File or patch approval requires a complete, non-truncated displayed diff and a matching diff hash. Split oversized changes before approval.",
      required_evidence: [...DIFF_APPROVAL_BLOCKED_EVIDENCE],
      approval_policy_label: "Diff evidence required"
    };
  }

  if (request.kind === "command_execution" || request.kind === "exec_command") {
    if (!commandIsReviewable(request.command)) {
      return blockedPolicy("Command approval requires the complete command text for review.", "Command review unavailable");
    }
    if (commandReviewText(request.command).length > MAX_APPROVAL_COMMAND_CHARS) {
      return blockedPolicy("Command approval is blocked because the full command does not fit the review surface. Split or shorten it first.", "Command review too large");
    }
    return {
      safe_default: "manual_only",
      approvable_by_chat: true,
      blocked_reason: null,
      required_evidence: [...COMMAND_APPROVAL_EVIDENCE],
      approval_policy_label: "Manual command approval"
    };
  }

  if (request.kind === "permissions") {
    return blockedPolicy("Permission grants are not reviewable in Godot chat, including full-machine sessions. Use a Codex client that supports this approval scope.", "Permission grant blocked");
  }

  if (request.kind === "elicitation") {
    return {
      safe_default: "manual_only",
      approvable_by_chat: true,
      blocked_reason: null,
      required_evidence: [...ELICITATION_APPROVAL_EVIDENCE],
      approval_policy_label: "User response approval"
    };
  }

  if (request.kind === "tool_call" || request.kind === "user_input") {
    return blockedPolicy("Generic tool approval is not approvable from chat. Use typed Bridge tools or ask Codex to revise.", "Generic tool approval blocked");
  }

  return blockedPolicy("This approval type is not approvable from chat.", "Approval blocked");
}

function diffIsFullyReviewable(value: unknown): boolean {
  const items = Array.isArray(value)
    ? value
    : value && typeof value === "object"
      ? Object.values(value as Record<string, unknown>)
      : [];
  if (items.length === 0 || items.length > MAX_APPROVAL_FILES) {
    return false;
  }
  return items.every((item) => {
    if (!item || typeof item !== "object") {
      return false;
    }
    const record = item as Record<string, unknown>;
    const diff = typeof record.unified_diff === "string"
      ? record.unified_diff
      : typeof record.diff === "string"
        ? record.diff
        : "";
    return diff.length > 0 && diff.split("\n").length <= MAX_APPROVAL_DIFF_LINES_PER_FILE;
  });
}

function commandReviewText(command: unknown): string {
  if (typeof command === "string") {
    return command;
  }
  if (command === undefined || command === null) {
    return "";
  }
  return JSON.stringify(command);
}

function commandIsReviewable(command: unknown): boolean {
  return typeof command === "string"
    ? command.trim().length > 0
    : Array.isArray(command) && command.length > 0 &&
      command.every((part) => typeof part === "string" && part.trim().length > 0);
}

function blockedPolicy(blockedReason: string, label: string): ApprovalPolicyFields {
  return {
    safe_default: "reject",
    approvable_by_chat: false,
    blocked_reason: blockedReason,
    required_evidence: [],
    approval_policy_label: label
  };
}
