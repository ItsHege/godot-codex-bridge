import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { runDoctor } from "../src/doctor.js";

test("runDoctor returns ok when project, addon, heartbeat and snapshot are ready", async () => {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-doctor-"));
  const bridgeDir = path.join(projectRoot, ".godot", "godot_codex_bridge");
  const addonDir = path.join(projectRoot, "addons", "godot_codex_bridge");
  await fs.mkdir(addonDir, { recursive: true });
  await fs.mkdir(bridgeDir, { recursive: true });
  await fs.writeFile(
    path.join(projectRoot, "project.godot"),
    'config_version=5\n[editor_plugins]\nenabled=PackedStringArray("res://addons/godot_codex_bridge/plugin.cfg")\n',
    "utf8",
  );
  await fs.writeFile(
    path.join(addonDir, "plugin.cfg"),
    '[plugin]\nname="Godot Codex Bridge"\nversion="0.0.1"\nscript="plugin.gd"\n',
    "utf8",
  );
  await fs.writeFile(
    path.join(bridgeDir, "heartbeat.json"),
    JSON.stringify({
      protocol_version: "godot-codex-bridge/0.1",
      addon_active: true,
      updated_at: new Date().toISOString(),
    }),
    "utf8",
  );
  await fs.writeFile(
    path.join(bridgeDir, "context_snapshot.json"),
    JSON.stringify({
      protocol_version: "godot-codex-bridge/0.1",
      generated_at: new Date().toISOString(),
    }),
    "utf8",
  );

  const oldProjectRoot = process.env.GODOT_CODEX_BRIDGE_PROJECT_ROOT;
  const oldBridgeDir = process.env.GODOT_CODEX_BRIDGE_DIR;
  const oldGodotExecutable = process.env.GODOT_CODEX_BRIDGE_GODOT_EXECUTABLE;
  process.env.GODOT_CODEX_BRIDGE_PROJECT_ROOT = projectRoot;
  process.env.GODOT_CODEX_BRIDGE_DIR = bridgeDir;
  process.env.GODOT_CODEX_BRIDGE_GODOT_EXECUTABLE = process.execPath;

  try {
    const result = await runDoctor();
    assert.equal(result.status, "ok");
    assert.equal(result.readiness, "ready");
  } finally {
    restoreEnv("GODOT_CODEX_BRIDGE_PROJECT_ROOT", oldProjectRoot);
    restoreEnv("GODOT_CODEX_BRIDGE_DIR", oldBridgeDir);
    restoreEnv("GODOT_CODEX_BRIDGE_GODOT_EXECUTABLE", oldGodotExecutable);
  }
});

function restoreEnv(name: string, value: string | undefined): void {
  if (value === undefined) {
    delete process.env[name];
  } else {
    process.env[name] = value;
  }
}
