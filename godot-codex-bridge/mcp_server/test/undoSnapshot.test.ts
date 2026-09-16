import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { createUndoSnapshot } from "../src/undoSnapshot.js";

test("createUndoSnapshot copies explicitly listed project files", async () => {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-undo-"));
  const bridgeDir = path.join(projectRoot, ".godot", "godot_codex_bridge");
  await fs.mkdir(path.join(projectRoot, "scenes"), { recursive: true });
  await fs.writeFile(path.join(projectRoot, "scenes", "main.tscn"), "[gd_scene format=3]\n", "utf8");

  const result = await createUndoSnapshot(projectRoot, bridgeDir, {
    paths: ["scenes/main.tscn"],
    label: "Before camera tweak",
  });

  assert.equal(result.status, "ok");
  assert.equal(result.file_count, 1);
  assert.equal(typeof result.manifest_path, "string");
  await fs.access(String(result.manifest_path));
  const files = result.files as Array<{ snapshot_path: string }>;
  assert.equal(await fs.readFile(files[0].snapshot_path, "utf8"), "[gd_scene format=3]\n");
});

test("createUndoSnapshot rejects path traversal", async () => {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-undo-reject-"));
  const bridgeDir = path.join(projectRoot, ".godot", "godot_codex_bridge");

  const result = await createUndoSnapshot(projectRoot, bridgeDir, {
    paths: ["../outside.tscn"],
  });

  assert.equal(result.status, "invalid_request");
  assert.equal((result.error as { code: string }).code, "path_traversal_rejected");
});
