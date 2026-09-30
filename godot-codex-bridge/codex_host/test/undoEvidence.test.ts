import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { createApprovalUndoSnapshot, verifyApprovalUndoSnapshotCurrent } from "../src/undoEvidence.js";
import type { HostApproval, ProjectSummary } from "../src/types.js";

test("createApprovalUndoSnapshot copies existing safe project files", async () => {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-undo-evidence-"));
  const bridgeDir = path.join(projectRoot, ".godot", "godot_codex_bridge");
  const hostStateDir = path.join(bridgeDir, "codex_host");
  await fs.mkdir(hostStateDir, { recursive: true });
  await fs.writeFile(path.join(projectRoot, "player.gd"), "extends Node\n", "utf8");

  const project: ProjectSummary = {
    projectRoot,
    projectFile: path.join(projectRoot, "project.godot"),
    bridgeDir,
    hostStateDir,
    agentsFiles: []
  };
  const approval: HostApproval = {
    runtime_approval_id: "runtime-undo",
    kind: "file_change",
    file_changes: {
      "res://player.gd": { type: "update", unified_diff: "@@\n-extends Node\n+extends Node3D\n" }
    },
    raw_method: "item/fileChange/requestApproval",
    raw_params: {},
    approval_id: "approval-undo-test",
    nonce: "nonce",
    status: "approved",
    created_at: new Date().toISOString(),
    expires_at: new Date(Date.now() + 1000).toISOString(),
    diff_hash: "hash",
    safe_default: "manual_only",
    approvable_by_chat: true,
    blocked_reason: null,
    required_evidence: ["nonce", "diff_hash", "displayed_diff_matches_hash"],
    approval_policy_label: "Manual diff approval"
  };

  const snapshot = await createApprovalUndoSnapshot(project, approval);
  assert.equal(snapshot.requested_path_count, 1);
  assert.equal(snapshot.copied_count, 1);
  assert.equal(snapshot.files[0].requested_path, "res://player.gd");
  assert.equal(snapshot.files[0].existed, true);
  assert.equal(snapshot.files[0].copied, true);
  assert.match(snapshot.files[0].sha256 ?? "", /^[a-f0-9]{64}$/);
  assert.equal(await fs.readFile(snapshot.files[0].snapshot_path!, "utf8"), "extends Node\n");
});

test("createApprovalUndoSnapshot records a new-file deletion tombstone and detects drift", async () => {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-undo-new-"));
  const project = await makeProjectSummary(projectRoot);
  const approval = makeApproval({ "res://created.gd": { type: "create" } }, "approval-new");

  const snapshot = await createApprovalUndoSnapshot(project, approval);
  assert.equal(snapshot.covered_count, 1);
  assert.equal(snapshot.copied_count, 0);
  assert.equal(snapshot.files[0].rollback_action, "delete_created_file");
  assert.equal(snapshot.files[0].copied, false);
  await verifyApprovalUndoSnapshotCurrent(snapshot);

  await fs.writeFile(path.join(projectRoot, "created.gd"), "extends Node\n", "utf8");
  await assert.rejects(() => verifyApprovalUndoSnapshotCurrent(snapshot), /new_target_changed/);
});

test("createApprovalUndoSnapshot fails closed instead of truncating more than 64 paths", async () => {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-undo-limit-"));
  const project = await makeProjectSummary(projectRoot);
  const changes: Record<string, unknown> = {};
  for (let index = 0; index < 65; index += 1) {
    changes[`res://file-${index}.gd`] = { type: "create" };
  }

  await assert.rejects(
    () => createApprovalUndoSnapshot(project, makeApproval(changes, "approval-limit")),
    /exceed_limit/,
  );
});

test("createApprovalUndoSnapshot rejects a linked project path", async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-undo-link-"));
  const projectRoot = path.join(root, "project");
  const outsideRoot = path.join(root, "outside");
  await fs.mkdir(projectRoot, { recursive: true });
  await fs.mkdir(outsideRoot, { recursive: true });
  await fs.writeFile(path.join(outsideRoot, "outside.gd"), "extends Node\n", "utf8");
  await fs.symlink(outsideRoot, path.join(projectRoot, "linked"), process.platform === "win32" ? "junction" : "dir");
  const project = await makeProjectSummary(projectRoot);

  await assert.rejects(
    () => createApprovalUndoSnapshot(project, makeApproval({ "res://linked/outside.gd": { type: "update" } }, "approval-link")),
    /link|reparse/i,
  );
});

test("createApprovalUndoSnapshot rejects a linked undo output directory", async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-undo-output-link-"));
  const projectRoot = path.join(root, "project");
  const outsideRoot = path.join(root, "outside");
  await fs.mkdir(projectRoot, { recursive: true });
  await fs.mkdir(outsideRoot, { recursive: true });
  await fs.writeFile(path.join(projectRoot, "player.gd"), "extends Node\n", "utf8");
  const project = await makeProjectSummary(projectRoot);
  await fs.symlink(
    outsideRoot,
    path.join(project.hostStateDir, "undo_snapshots"),
    process.platform === "win32" ? "junction" : "dir",
  );

  await assert.rejects(
    () => createApprovalUndoSnapshot(project, makeApproval({ "res://player.gd": { type: "update" } }, "approval-output-link")),
    /link|junction|reparse/i,
  );
  assert.deepEqual(await fs.readdir(outsideRoot), []);
});

async function makeProjectSummary(projectRoot: string): Promise<ProjectSummary> {
  const bridgeDir = path.join(projectRoot, ".godot", "godot_codex_bridge");
  const hostStateDir = path.join(bridgeDir, "codex_host");
  await fs.mkdir(hostStateDir, { recursive: true });
  return {
    projectRoot,
    projectFile: path.join(projectRoot, "project.godot"),
    bridgeDir,
    hostStateDir,
    agentsFiles: [],
  };
}

function makeApproval(fileChanges: Record<string, unknown>, approvalId: string): HostApproval {
  return {
    runtime_approval_id: `runtime-${approvalId}`,
    kind: "file_change",
    file_changes: fileChanges,
    raw_method: "item/fileChange/requestApproval",
    raw_params: {},
    approval_id: approvalId,
    nonce: "nonce",
    status: "approved",
    created_at: new Date().toISOString(),
    expires_at: new Date(Date.now() + 1000).toISOString(),
    diff_hash: "hash",
    safe_default: "manual_only",
    approvable_by_chat: true,
    blocked_reason: null,
    required_evidence: ["nonce", "diff_hash", "displayed_diff_matches_hash"],
    approval_policy_label: "Manual diff approval",
  };
}
