import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { applyApprovedDiff, APPLY_APPROVAL_TOKEN } from "../src/applyApprovedDiff.js";

test("applyApprovedDiff requires approval token", async () => {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-apply-token-"));
  const bridgeDir = path.join(projectRoot, ".godot", "godot_codex_bridge");
  await fs.writeFile(path.join(projectRoot, "script.gd"), "extends Node\n", "utf8");

  const result = await applyApprovedDiff(projectRoot, bridgeDir, {
    path: "script.gd",
    proposedContent: "extends Node\nfunc _ready(): pass\n",
  });

  assert.equal(result.status, "invalid_request");
  assert.equal((result.error as { code: string }).code, "approval_token_required");
});

test("applyApprovedDiff writes approved content and creates undo snapshot", async () => {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-apply-"));
  const bridgeDir = path.join(projectRoot, ".godot", "godot_codex_bridge");
  const filePath = path.join(projectRoot, "script.gd");
  await fs.writeFile(filePath, "extends Node\n", "utf8");

  const result = await applyApprovedDiff(projectRoot, bridgeDir, {
    path: "script.gd",
    proposedContent: "extends Node\nfunc _ready(): pass\n",
    approvalToken: APPLY_APPROVAL_TOKEN,
  });

  assert.equal(result.status, "ok");
  assert.equal(result.applied, true);
  assert.equal(await fs.readFile(filePath, "utf8"), "extends Node\nfunc _ready(): pass\n");
  assert.equal((result.undo_snapshot as { status: string }).status, "ok");
});
