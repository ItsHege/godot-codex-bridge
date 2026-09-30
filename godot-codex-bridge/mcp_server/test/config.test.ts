import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { createServerConfig, discoverGodotExecutable, findGodotOnPath } from "../src/config.js";

test("discoverGodotExecutable honors explicit override first", () => {
  const custom = path.resolve("/custom/bin/godot");
  const result = discoverGodotExecutable(custom);
  assert.equal(result, custom);
});

test("discoverGodotExecutable prioritizes GODOT_BIN environment variable", () => {
  const original = process.env.GODOT_BIN;
  try {
    const customBin = path.resolve("/opt/godot/bin/godot");
    process.env.GODOT_BIN = customBin;

    const result = discoverGodotExecutable();
    assert.equal(result, customBin);
  } finally {
    if (original === undefined) {
      delete process.env.GODOT_BIN;
    } else {
      process.env.GODOT_BIN = original;
    }
  }
});

test("discoverGodotExecutable ignores project-controlled .godot_bin", async () => {
  const original = process.env.GODOT_BIN;
  delete process.env.GODOT_BIN;

  try {
    const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-config-test-"));
    const targetBin = path.join(tempDir, "bin", "godot");
    await fs.writeFile(path.join(tempDir, ".godot_bin"), targetBin, "utf8");

    const result = discoverGodotExecutable(undefined, tempDir);
    assert.notEqual(result, path.resolve(targetBin));
  } finally {
    if (original !== undefined) {
      process.env.GODOT_BIN = original;
    }
  }
});

test("findGodotOnPath locates executable in custom PATH string", async () => {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-path-test-"));
  const binaryName = process.platform === "win32" ? "godot.exe" : "godot";
  const binaryPath = path.join(tempDir, binaryName);
  await fs.writeFile(binaryPath, "", "utf8");

  const delimiter = process.platform === "win32" ? ";" : ":";
  const fakePath = `${tempDir}${delimiter}/nonexistent`;

  const result = findGodotOnPath(fakePath);
  assert.equal(result, binaryPath);
});

test("findGodotOnPath ignores relative and attached-project candidates", async () => {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-project-path-test-"));
  const projectBin = path.join(projectRoot, "bin");
  await fs.mkdir(projectBin, { recursive: true });
  const binaryName = process.platform === "win32" ? "godot.exe" : "godot";
  await fs.writeFile(path.join(projectBin, binaryName), "", "utf8");
  const delimiter = process.platform === "win32" ? ";" : ":";

  assert.equal(findGodotOnPath(`.${delimiter}${projectBin}`, projectRoot), null);
});

test("createServerConfig sets godotExecutable via discoverGodotExecutable", () => {
  const original = process.env.GODOT_BIN;
  const custom = path.resolve("/test/bin/godot_custom");
  process.env.GODOT_BIN = custom;

  try {
    const config = createServerConfig();
    assert.equal(config.godotExecutable, custom);
  } finally {
    if (original === undefined) {
      delete process.env.GODOT_BIN;
    } else {
      process.env.GODOT_BIN = original;
    }
  }
});

test("explicit project and bridge CLI paths override inherited environment", () => {
  const originalArgv = process.argv;
  const originalProject = process.env.GODOT_CODEX_BRIDGE_PROJECT_ROOT;
  const originalBridge = process.env.GODOT_CODEX_BRIDGE_DIR;
  const project = path.resolve("/chosen-godot-project");
  const bridge = path.join(project, ".godot", "godot_codex_bridge");
  try {
    process.env.GODOT_CODEX_BRIDGE_PROJECT_ROOT = path.resolve("/wrong-project");
    process.env.GODOT_CODEX_BRIDGE_DIR = path.resolve("/wrong-bridge");
    process.argv = [originalArgv[0]!, originalArgv[1]!, "--project-root", project, "--bridge-dir", bridge];
    const config = createServerConfig();
    assert.equal(config.projectRoot, project);
    assert.equal(config.bridgeDir, bridge);
  } finally {
    process.argv = originalArgv;
    if (originalProject === undefined) delete process.env.GODOT_CODEX_BRIDGE_PROJECT_ROOT;
    else process.env.GODOT_CODEX_BRIDGE_PROJECT_ROOT = originalProject;
    if (originalBridge === undefined) delete process.env.GODOT_CODEX_BRIDGE_DIR;
    else process.env.GODOT_CODEX_BRIDGE_DIR = originalBridge;
  }
});
