import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { PreviewDiffError, previewSceneDiff, resolvePreviewTarget } from "../src/diffPreview.js";

test("previewSceneDiff returns a unified diff without applying changes", async () => {
  const projectRoot = await makeProject();
  const scenePath = path.join(projectRoot, "scenes", "main.tscn");
  await fs.mkdir(path.dirname(scenePath), { recursive: true });
  await fs.writeFile(scenePath, "[node name=\"Root\" type=\"Node3D\"]\n", "utf8");

  const result = await previewSceneDiff({
    projectRoot,
    targetPath: "res://scenes/main.tscn",
    proposedContent: "[node name=\"Root\" type=\"Node3D\"]\n[node name=\"Camera3D\" type=\"Camera3D\"]\n",
  });

  assert.equal(result.status, "ok");
  assert.equal(result.applied, false);
  assert.match(String(result.diff), /Camera3D/);
  assert.equal(await fs.readFile(scenePath, "utf8"), "[node name=\"Root\" type=\"Node3D\"]\n");
});

test("previewSceneDiff rejects unsafe path classes", async () => {
  const projectRoot = await makeProject();

  assertPreviewError(() => resolvePreviewTarget(projectRoot, "C:\\outside\\scene.tscn"), "absolute_path_rejected");
  assertPreviewError(() => resolvePreviewTarget(projectRoot, "../outside.tscn"), "path_traversal_rejected");
  assertPreviewError(() => resolvePreviewTarget(projectRoot, ".godot/state.tscn"), "blocked_path_rejected");
  assertPreviewError(() => resolvePreviewTarget(projectRoot, "generated/state.tscn"), "blocked_path_rejected");
  assertPreviewError(() => resolvePreviewTarget(projectRoot, "textures/albedo.png"), "binary_path_rejected");
  assertPreviewError(() => resolvePreviewTarget(projectRoot, "scenes/main.tscn.import"), "binary_path_rejected");
});

test("previewSceneDiff can preview explicit text file creation", async () => {
  const projectRoot = await makeProject();

  const result = await previewSceneDiff({
    projectRoot,
    targetPath: "scripts/player.gd",
    proposedContent: "extends Node\n",
    allowCreate: true,
  });

  assert.equal(result.status, "ok");
  assert.equal(result.operation, "create");
  assert.match(String(result.diff), /extends Node/);
});

async function makeProject(): Promise<string> {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-diff-"));
  await fs.writeFile(path.join(projectRoot, "project.godot"), "; fixture\n", "utf8");
  return projectRoot;
}

function assertPreviewError(fn: () => unknown, code: string): void {
  assert.throws(
    fn,
    (error) => error instanceof PreviewDiffError && error.code === code,
  );
}
