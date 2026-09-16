import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { assertInside, resolveProject } from "../src/projectRoots.js";

test("resolveProject requires project.godot and creates host state dir", async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-host-project-"));
  await fs.writeFile(path.join(root, "project.godot"), "[application]\n", "utf8");
  await fs.writeFile(path.join(root, "AGENTS.md"), "# Test\n", "utf8");

  const summary = await resolveProject(root);

  assert.equal(summary.projectRoot, root);
  assert.equal(summary.projectFile, path.join(root, "project.godot"));
  assert.equal(summary.agentsFiles.length, 1);
  assert.match(summary.agentsFiles[0].sha256, /^[a-f0-9]{64}$/);

  const state = await fs.stat(summary.hostStateDir);
  assert.equal(state.isDirectory(), true);
});

test("resolveProject rejects wrong root", async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-host-wrong-"));
  await assert.rejects(() => resolveProject(root), /wrong_root/);
});

test("assertInside rejects traversal outside project root", () => {
  const root = path.resolve("C:/tmp/project");
  assert.equal(assertInside(root, path.join(root, ".godot"), "bridge_dir"), path.join(root, ".godot"));
  assert.throws(() => assertInside(root, path.resolve("C:/tmp/other"), "bridge_dir"), /outside_project_root/);
});
