import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { createApprovalUndoSnapshot } from "../src/undoEvidence.js";
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
