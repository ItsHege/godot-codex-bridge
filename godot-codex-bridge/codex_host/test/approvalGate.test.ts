import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { ApprovalGate } from "../src/approvalGate.js";

test("ApprovalGate keeps permission grants blocked", async () => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-approval-"));
  const gate = new ApprovalGate(dir);
  const approval = await gate.create({
    runtime_approval_id: "runtime-1",
    kind: "permissions",
    grant_root: "/",
    raw_method: "item/permissions/requestApproval",
    raw_params: {}
  });

  assert.match(approval.approval_id, /^approval-/);
  assert.equal(approval.safe_default, "reject");
  assert.equal(approval.approvable_by_chat, false);
  assert.match(approval.blocked_reason ?? "", /Permission grants are not reviewable in Godot chat/);
  assert.deepEqual(approval.required_evidence, []);
  assert.equal(approval.approval_policy_label, "Permission grant blocked");
  await assert.rejects(
    () => gate.resolve({ approval_id: approval.approval_id, nonce: approval.nonce, decision: "approve" }),
    /approval_not_approvable_by_chat/
  );
  const originalBlockedReason = approval.blocked_reason;
  const invalidated = await gate.invalidateByRuntimeId("runtime-1", "server_resolved");
  assert.equal(invalidated?.status, "resolved_by_server");
  assert.equal(invalidated?.approvable_by_chat, false);
  assert.equal(invalidated?.blocked_reason, originalBlockedReason);
  assert.equal(invalidated?.invalidation_reason, "server_resolved");
  const saved = JSON.parse(await fs.readFile(path.join(dir, `${approval.approval_id}.json`), "utf8")) as {
    approvable_by_chat: boolean;
    blocked_reason: string;
    invalidation_reason: string;
  };
  assert.equal(saved.approvable_by_chat, false);
  assert.equal(saved.blocked_reason, originalBlockedReason);
  assert.equal(saved.invalidation_reason, "server_resolved");
});

test("ApprovalGate allows one-shot manual command approval without diff evidence", async () => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-approval-"));
  const gate = new ApprovalGate(dir);
  const approval = await gate.create({
    runtime_approval_id: "runtime-command",
    kind: "command_execution",
    command: "New-Item -ItemType Directory scenes/debug",
    cwd: "C:\\Projects\\example_game",
    raw_method: "item/commandExecution/requestApproval",
    raw_params: {}
  });

  assert.equal(approval.safe_default, "manual_only");
  assert.equal(approval.approvable_by_chat, true);
  assert.equal(approval.blocked_reason, null);
  assert.deepEqual(approval.required_evidence, ["nonce", "displayed_command_reviewed"]);
  assert.equal(approval.approval_policy_label, "Manual command approval");
  assert.equal(approval.diff_hash, undefined);

  const resolved = await gate.resolve({
    approval_id: approval.approval_id,
    nonce: approval.nonce,
    decision: "approve"
  });
  assert.equal(resolved.runtimeDecision, "approve");
});

test("ApprovalGate blocks a command with no reviewable text", async () => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-approval-empty-command-"));
  const gate = new ApprovalGate(dir);
  const approval = await gate.create({
    runtime_approval_id: "runtime-empty-command",
    kind: "command_execution",
    command: "   ",
    raw_method: "item/commandExecution/requestApproval",
    raw_params: {},
  });
  assert.equal(approval.approvable_by_chat, false);
  await assert.rejects(
    () => gate.resolve({ approval_id: approval.approval_id, nonce: approval.nonce, decision: "approve" }),
    /approval_not_approvable_by_chat/,
  );
});

test("ApprovalGate stages responses and server invalidation wins without a false approval terminal", async () => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-approval-race-"));
  const gate = new ApprovalGate(dir);
  const approval = await gate.create({
    runtime_approval_id: "runtime-race",
    kind: "command_execution",
    command: "echo race",
    raw_method: "item/commandExecution/requestApproval",
    raw_params: {},
  });
  const begun = await gate.beginResolve({
    approval_id: approval.approval_id,
    nonce: approval.nonce,
    decision: "approve",
  });
  assert.equal(begun.approval.status, "responding");
  const invalidated = await gate.invalidateByRuntimeId("runtime-race", "server_resolved");
  assert.equal(invalidated?.status, "resolved_by_server");
  assert.equal(invalidated?.approvable_by_chat, true);
  assert.equal(invalidated?.blocked_reason, null);
  assert.equal(await gate.invalidateByRuntimeId("runtime-race", "duplicate"), null);
  await assert.rejects(
    gate.completeResolve(approval.approval_id, "approve"),
    /approval_not_responding/,
  );
  await assert.rejects(
    gate.beginResolve({ approval_id: approval.approval_id, nonce: approval.nonce, decision: "approve" }),
    /approval_not_pending/,
  );
  const saved = JSON.parse(await fs.readFile(path.join(dir, `${approval.approval_id}.json`), "utf8")) as { status: string; invalidation_reason: string };
  assert.equal(saved.status, "resolved_by_server");
  assert.equal(saved.invalidation_reason, "server_resolved");
});

test("ApprovalGate aborts an unsent staged response back to pending", async () => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-approval-abort-"));
  const gate = new ApprovalGate(dir);
  const approval = await gate.create({
    runtime_approval_id: "runtime-abort",
    kind: "command_execution",
    command: "echo retry",
    raw_method: "item/commandExecution/requestApproval",
    raw_params: {},
  });
  await gate.beginResolve({ approval_id: approval.approval_id, nonce: approval.nonce, decision: "approve" });
  assert.equal((await gate.abortResolve(approval.approval_id))?.status, "pending");
  const retry = await gate.beginResolve({ approval_id: approval.approval_id, nonce: approval.nonce, decision: "reject" });
  await gate.completeResolve(approval.approval_id, retry.runtimeDecision);
  assert.equal(retry.approval.status, "rejected");
});

test("ApprovalGate allows session command approval", async () => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-approval-"));
  const gate = new ApprovalGate(dir);
  const approval = await gate.create({
    runtime_approval_id: "runtime-command-session",
    kind: "command_execution",
    command: "New-Item -ItemType Directory scenes/debug",
    cwd: "C:\\Projects\\example_game",
    raw_method: "item/commandExecution/requestApproval",
    raw_params: {}
  });

  const resolved = await gate.resolve({
    approval_id: approval.approval_id,
    nonce: approval.nonce,
    decision: "approve_session"
  });
  assert.equal(resolved.runtimeDecision, "approve_session");
  assert.equal(resolved.approval.status, "approved_session");
});

test("ApprovalGate allows manual file-change approval and writes evidence", async () => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-approval-"));
  const gate = new ApprovalGate(dir);
  const approval = await gate.create({
    runtime_approval_id: "runtime-2",
    kind: "file_change",
    file_changes: { "res://player.gd": { type: "update", unified_diff: "@@\n-old\n+new\n" } },
    raw_method: "item/fileChange/requestApproval",
    raw_params: {}
  });

  assert.equal(gate.pendingCount(), 1);
  assert.equal(approval.safe_default, "manual_only");
  assert.equal(approval.approvable_by_chat, true);
  assert.equal(approval.blocked_reason, null);
  assert.deepEqual(approval.required_evidence, ["nonce", "diff_hash", "displayed_diff_matches_hash"]);
  assert.equal(approval.approval_policy_label, "Manual diff approval");
  assert.match(approval.diff_hash ?? "", /^[a-f0-9]{64}$/);

  await assert.rejects(
    () => gate.resolve({
      approval_id: approval.approval_id,
      nonce: approval.nonce,
      diff_hash: approval.diff_hash,
      decision: "approve_session"
    }),
    /approval_session_scope_not_allowed: file_change/
  );

  await assert.rejects(
    () => gate.resolve({
      approval_id: approval.approval_id,
      nonce: "wrong",
      diff_hash: approval.diff_hash,
      decision: "approve"
    }),
    /approval_nonce_mismatch/
  );

  await assert.rejects(
    () => gate.resolve({
      approval_id: approval.approval_id,
      nonce: approval.nonce,
      diff_hash: "wrong",
      decision: "approve"
    }),
    /approval_diff_hash_mismatch/
  );

  const resolved = await gate.resolve({
    approval_id: approval.approval_id,
    nonce: approval.nonce,
    diff_hash: approval.diff_hash,
    decision: "approve"
  });
  assert.equal(resolved.runtimeDecision, "approve");
  assert.equal(gate.pendingCount(), 0);

  const saved = await fs.readFile(path.join(dir, `${approval.approval_id}.json`), "utf8");
  assert.match(saved, /"status": "approved"/);
  assert.match(saved, /"approvable_by_chat": true/);
  assert.match(saved, /"approval_policy_label": "Manual diff approval"/);
});

test("ApprovalGate does not allow file-change approval without diff evidence", async () => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-approval-"));
  const gate = new ApprovalGate(dir);
  const approval = await gate.create({
    runtime_approval_id: "runtime-3",
    kind: "file_change",
    raw_method: "item/fileChange/requestApproval",
    raw_params: {}
  });

  assert.equal(approval.safe_default, "reject");
  assert.equal(approval.approvable_by_chat, false);
  assert.match(approval.blocked_reason ?? "", /complete, non-truncated displayed diff/);
  assert.deepEqual(approval.required_evidence, ["diff_hash", "displayed_diff_evidence"]);
  assert.equal(approval.approval_policy_label, "Diff evidence required");
  assert.equal(approval.diff_hash, undefined);
  await assert.rejects(
    () => gate.resolve({
      approval_id: approval.approval_id,
      nonce: approval.nonce,
      decision: "approve"
    }),
    /approval_not_approvable_by_chat/
  );
});

test("ApprovalGate allows apply_patch approval only when diff hash is present", async () => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-approval-"));
  const gate = new ApprovalGate(dir);
  const approval = await gate.create({
    runtime_approval_id: "runtime-4",
    kind: "apply_patch",
    diff_evidence: { "res://enemy.gd": { type: "update", unified_diff: "@@\n-speed = 1\n+speed = 2\n" } },
    raw_method: "applyPatchApproval",
    raw_params: {}
  });

  assert.equal(approval.safe_default, "manual_only");
  assert.equal(approval.approvable_by_chat, true);
  assert.equal(approval.blocked_reason, null);
  assert.deepEqual(approval.required_evidence, ["nonce", "diff_hash", "displayed_diff_matches_hash"]);
  assert.equal(approval.approval_policy_label, "Manual diff approval");
  assert.match(approval.diff_hash ?? "", /^[a-f0-9]{64}$/);

  const missingDiffApproval = await gate.create({
    runtime_approval_id: "runtime-5",
    kind: "apply_patch",
    raw_method: "applyPatchApproval",
    raw_params: {}
  });

  assert.equal(missingDiffApproval.safe_default, "reject");
  assert.equal(missingDiffApproval.approvable_by_chat, false);
  assert.match(missingDiffApproval.blocked_reason ?? "", /complete, non-truncated displayed diff/);
  await assert.rejects(
    () => gate.resolve({
      approval_id: missingDiffApproval.approval_id,
      nonce: missingDiffApproval.nonce,
      decision: "approve"
    }),
    /approval_not_approvable_by_chat/
  );
});

test("ApprovalGate blocks approvals whose complete diff or command cannot be displayed", async () => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-approval-review-bounds-"));
  const gate = new ApprovalGate(dir);
  const changes: Record<string, unknown> = {};
  for (let index = 0; index < 25; index += 1) {
    changes[`res://file-${index}.gd`] = { type: "update", unified_diff: "@@\n-old\n+new\n" };
  }
  const fileApproval = await gate.create({
    runtime_approval_id: "runtime-too-many-files",
    kind: "file_change",
    file_changes: changes,
    raw_method: "item/fileChange/requestApproval",
    raw_params: {}
  });
  assert.equal(fileApproval.approvable_by_chat, false);
  assert.match(fileApproval.blocked_reason ?? "", /complete, non-truncated displayed diff/);

  const commandApproval = await gate.create({
    runtime_approval_id: "runtime-long-command",
    kind: "command_execution",
    command: "x".repeat(1001),
    raw_method: "item/commandExecution/requestApproval",
    raw_params: {}
  });
  assert.equal(commandApproval.approvable_by_chat, false);
  assert.match(commandApproval.blocked_reason ?? "", /full command/);
});

test("ApprovalGate allows user elicitation approval without diff evidence", async () => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-approval-"));
  const gate = new ApprovalGate(dir);
  const approval = await gate.create({
    runtime_approval_id: "runtime-elicitation",
    kind: "elicitation",
    reason: "Codex needs a user answer.",
    raw_method: "mcpServer/elicitation/request",
    raw_params: {
      mode: "form",
      message: "Proceed?",
      requestedSchema: {
        type: "object",
        properties: {
          approved: { type: "boolean" },
          note: { type: "string" }
        }
      }
    }
  });

  assert.equal(approval.safe_default, "manual_only");
  assert.equal(approval.approvable_by_chat, true);
  assert.equal(approval.blocked_reason, null);
  assert.deepEqual(approval.required_evidence, ["nonce", "user_response"]);
  assert.equal(approval.approval_policy_label, "User response approval");
  assert.equal(approval.diff_hash, undefined);

  const resolved = await gate.resolve({
    approval_id: approval.approval_id,
    nonce: approval.nonce,
    decision: "approve",
    note: "Proceed"
  });
  assert.equal(resolved.runtimeDecision, "approve");
});
