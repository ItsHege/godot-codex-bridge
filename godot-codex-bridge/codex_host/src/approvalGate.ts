import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import type { ApprovalRespondParams, HostApproval, RuntimeApprovalRequest, TrustMode } from "./types.js";

const APPROVAL_TTL_MS = 5 * 60 * 1000;

export class ApprovalGate {
  private readonly approvals = new Map<string, HostApproval>();

  constructor(
    private readonly approvalDir: string,
    private readonly trustMode: () => TrustMode = () => "off",
  ) {}

  async init(): Promise<void> {
    await fs.mkdir(this.approvalDir, { recursive: true });
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
    await this.writeApproval(approval);
    return approval;
  }

  async resolve(params: ApprovalRespondParams): Promise<{ approval: HostApproval; runtimeDecision: "approve" | "approve_session" | "reject" | "revise" | "expired" }> {
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
      approval.status = "expired";
      await this.writeApproval(approval);
      return { approval, runtimeDecision: "expired" };
    }

    if (params.decision === "approve" || params.decision === "approve_session") {
      if (!approval.approvable_by_chat || approval.safe_default !== "manual_only") {
        throw new Error(`approval_not_approvable_by_chat: ${approval.kind}`);
      }
      if (approval.kind === "file_change" || approval.kind === "apply_patch") {
        if (!approval.diff_hash) {
          throw new Error(`approval_diff_hash_required: ${approval.kind}`);
        }
        if (params.diff_hash !== approval.diff_hash) {
          throw new Error(`approval_diff_hash_mismatch: ${approval.kind}`);
        }
      }
      approval.status = params.decision === "approve_session" ? "approved_session" : "approved";
      await this.writeApproval(approval);
      return { approval, runtimeDecision: params.decision };
    }

    if (params.decision === "revise") {
      approval.status = "revised";
      await this.writeApproval(approval);
      return { approval, runtimeDecision: "revise" };
    }

    approval.status = "rejected";
    await this.writeApproval(approval);
    return { approval, runtimeDecision: "reject" };
  }

  pendingCount(): number {
    return [...this.approvals.values()].filter((approval) => approval.status === "pending").length;
  }

  pendingApprovals(): HostApproval[] {
    return [...this.approvals.values()].filter((approval) => approval.status === "pending");
  }

  async expireDue(now = Date.now()): Promise<HostApproval[]> {
    const expired: HostApproval[] = [];
    for (const approval of this.approvals.values()) {
      if (approval.status === "pending" && now > Date.parse(approval.expires_at)) {
        approval.status = "expired";
        expired.push(approval);
        await this.writeApproval(approval);
      }
    }
    return expired;
  }

  private async writeApproval(approval: HostApproval): Promise<void> {
    await this.init();
    const filePath = path.join(this.approvalDir, `${safeFileName(approval.approval_id)}.json`);
    await fs.writeFile(filePath, `${JSON.stringify(approval, null, 2)}\n`, "utf8");
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
    if (diffHash) {
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
      blocked_reason: "File or patch approval requires displayed diff evidence and a matching diff hash.",
      required_evidence: [...DIFF_APPROVAL_BLOCKED_EVIDENCE],
      approval_policy_label: "Diff evidence required"
    };
  }

  if (request.kind === "command_execution" || request.kind === "exec_command") {
    return {
      safe_default: "manual_only",
      approvable_by_chat: true,
      blocked_reason: null,
      required_evidence: [...COMMAND_APPROVAL_EVIDENCE],
      approval_policy_label: "Manual command approval"
    };
  }

  if (request.kind === "permissions") {
    if (trustMode === "full_machine") {
      return {
        safe_default: "manual_only",
        approvable_by_chat: true,
        blocked_reason: null,
        required_evidence: ["nonce", "full_machine_trust_session_active"],
        approval_policy_label: "Full trust permission approval"
      };
    }
    return blockedPolicy("Permission grants are not approvable from chat. Use a narrower typed Bridge action or ask Codex to revise.", "Permission grant blocked");
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

function blockedPolicy(blockedReason: string, label: string): ApprovalPolicyFields {
  return {
    safe_default: "reject",
    approvable_by_chat: false,
    blocked_reason: blockedReason,
    required_evidence: [],
    approval_policy_label: label
  };
}
