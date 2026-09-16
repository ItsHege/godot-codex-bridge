import assert from "node:assert/strict";
import fs from "node:fs/promises";
import { createServer, type Server } from "node:http";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { getBridgeStatus } from "../src/status.js";
import type { ServerConfig } from "../src/types.js";

test("getBridgeStatus reports wrong project root", async () => {
  const config = await makeConfig();

  const result = await getBridgeStatus(config);

  assert.equal(result.status, "ok");
  assert.equal(result.readiness, "wrong_project_root");
  assert.equal(result.active_editor_detected, false);
});

test("getBridgeStatus reports live addon metadata", async () => {
  const config = await makeConfig();
  await writeProject(config.projectRoot, true);
  await writeAddon(config.projectRoot, "0.2.0");
  await fs.mkdir(config.bridgeDir, { recursive: true });
  await fs.writeFile(
    path.join(config.bridgeDir, "bridge_state.json"),
    JSON.stringify({
      protocol_version: "godot-codex-bridge/0.1",
      addon_active: true,
      plugin_version: "0.2.0",
      updated_at: new Date().toISOString(),
    }),
    "utf8",
  );
  await fs.writeFile(
    path.join(config.bridgeDir, "heartbeat.json"),
    JSON.stringify({
      protocol_version: "godot-codex-bridge/0.1",
      addon_active: true,
      updated_at: new Date().toISOString(),
    }),
    "utf8",
  );
  await fs.writeFile(
    path.join(config.bridgeDir, "context_snapshot.json"),
    JSON.stringify({
      protocol_version: "godot-codex-bridge/0.1",
      generated_at: new Date().toISOString(),
    }),
    "utf8",
  );

  const result = await getBridgeStatus(config);

  assert.equal(result.readiness, "ready");
  assert.equal(result.plugin_enabled, true);
  assert.equal(result.active_editor_detected, true);
  assert.equal(result.addon_version, "0.2.0");
  assert.equal(result.protocol_version, "godot-codex-bridge/0.1");
  assert.deepEqual(result.project_identity, {
    editorProjectRoot: config.projectRoot,
    hostProjectRoot: null,
    editorBridgeDir: config.bridgeDir,
    hostBridgeDir: null,
    hostStatusAvailable: false,
    matches: null,
    bridgeDirMatches: null,
  });
  assert.deepEqual(result.addon_request_transport, {
    preferred: "file_polling",
    host_rpc_configured: false,
    host_rpc_url: null,
    file_polling_fallback: true,
    file_polling_bridge_dir: config.bridgeDir,
  });
});

test("getBridgeStatus reports matching host and editor project roots", async () => {
  const config = await makeConfig();
  await writeReadyBridge(config);
  await withHostHealth(config.projectRoot, config.bridgeDir, async (hostRpcUrl) => {
    config.hostRpcUrl = hostRpcUrl;

    const result = await getBridgeStatus(config);

    assert.equal(result.readiness, "ready");
    assert.equal(result.project_mismatch, false);
    assert.deepEqual(result.project_identity, {
      editorProjectRoot: config.projectRoot,
      hostProjectRoot: config.projectRoot,
      editorBridgeDir: config.bridgeDir,
      hostBridgeDir: config.bridgeDir,
      hostStatusAvailable: true,
      matches: true,
      bridgeDirMatches: true,
    });
  });
});

test("getBridgeStatus reports project mismatch when host is attached elsewhere", async () => {
  const config = await makeConfig();
  await writeReadyBridge(config);
  const otherProjectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-status-other-"));
  const otherBridgeDir = path.join(otherProjectRoot, ".godot", "godot_codex_bridge");
  await withHostHealth(otherProjectRoot, otherBridgeDir, async (hostRpcUrl) => {
    config.hostRpcUrl = hostRpcUrl;

    const result = await getBridgeStatus(config);

    assert.equal(result.readiness, "project_mismatch");
    assert.equal(result.project_mismatch, true);
    assert.match(String(result.recommended_next_action), /Reconnect Codex Host/);
    assert.deepEqual(result.project_identity, {
      editorProjectRoot: config.projectRoot,
      hostProjectRoot: otherProjectRoot,
      editorBridgeDir: config.bridgeDir,
      hostBridgeDir: otherBridgeDir,
      hostStatusAvailable: true,
      matches: false,
      bridgeDirMatches: false,
    });
  });
});

test("getBridgeStatus reports host websocket RPC transport when configured", async () => {
  const config = await makeConfig();
  config.hostRpcUrl = "http://127.0.0.1:49390/bridge/request";
  await writeProject(config.projectRoot, true);
  await writeAddon(config.projectRoot, "0.2.0");

  const result = await getBridgeStatus(config);

  assert.equal((result.addon_request_transport as { preferred?: string }).preferred, "host_websocket_rpc");
  assert.equal((result.addon_request_transport as { host_rpc_configured?: boolean }).host_rpc_configured, true);
  assert.equal((result.addon_request_transport as { host_rpc_url?: string }).host_rpc_url, config.hostRpcUrl);
  assert.equal((result.addon_request_transport as { file_polling_fallback?: boolean }).file_polling_fallback, true);
});

test("getBridgeStatus reports stale editor", async () => {
  const config = await makeConfig();
  await writeProject(config.projectRoot, true);
  await writeAddon(config.projectRoot, "0.2.0");
  await fs.mkdir(config.bridgeDir, { recursive: true });
  await fs.writeFile(
    path.join(config.bridgeDir, "heartbeat.json"),
    JSON.stringify({
      protocol_version: "godot-codex-bridge/0.1",
      addon_active: true,
      updated_at: "2026-06-13T00:00:00.000Z",
    }),
    "utf8",
  );

  const result = await getBridgeStatus(config, { now: new Date("2026-06-13T00:00:10.000Z") });

  assert.equal(result.readiness, "stale_editor");
  assert.equal(result.stale_editor, true);
  assert.equal(result.active_editor_detected, false);
});

async function makeConfig(): Promise<ServerConfig> {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-status-"));
  return {
    projectRoot,
    bridgeDir: path.join(projectRoot, ".godot", "godot_codex_bridge"),
    godotExecutable: process.execPath,
    addonRequestTimeoutMs: 250,
    runSceneTimeoutMs: 1_000,
  };
}

async function writeProject(projectRoot: string, pluginEnabled: boolean): Promise<void> {
  const enabledLine = pluginEnabled
    ? '\n[editor_plugins]\nenabled=PackedStringArray("res://addons/godot_codex_bridge/plugin.cfg")\n'
    : "";
  await fs.writeFile(path.join(projectRoot, "project.godot"), `config_version=5\n${enabledLine}`, "utf8");
}

async function writeAddon(projectRoot: string, version: string): Promise<void> {
  const addonPath = path.join(projectRoot, "addons", "godot_codex_bridge");
  await fs.mkdir(addonPath, { recursive: true });
  await fs.writeFile(
    path.join(addonPath, "plugin.cfg"),
    `[plugin]\nname="Godot Codex Bridge"\nversion="${version}"\nscript="plugin.gd"\n`,
    "utf8",
  );
}

async function writeReadyBridge(config: ServerConfig): Promise<void> {
  await writeProject(config.projectRoot, true);
  await writeAddon(config.projectRoot, "0.2.0");
  await fs.mkdir(config.bridgeDir, { recursive: true });
  await fs.writeFile(
    path.join(config.bridgeDir, "bridge_state.json"),
    JSON.stringify({
      protocol_version: "godot-codex-bridge/0.1",
      addon_active: true,
      plugin_version: "0.2.0",
      updated_at: new Date().toISOString(),
    }),
    "utf8",
  );
  await fs.writeFile(
    path.join(config.bridgeDir, "heartbeat.json"),
    JSON.stringify({
      protocol_version: "godot-codex-bridge/0.1",
      addon_active: true,
      updated_at: new Date().toISOString(),
    }),
    "utf8",
  );
  await fs.writeFile(
    path.join(config.bridgeDir, "context_snapshot.json"),
    JSON.stringify({
      protocol_version: "godot-codex-bridge/0.1",
      generated_at: new Date().toISOString(),
    }),
    "utf8",
  );
}

async function withHostHealth(
  projectRoot: string,
  bridgeDir: string,
  callback: (hostRpcUrl: string) => Promise<void>,
): Promise<void> {
  let server!: Server;
  await new Promise<void>((resolve, reject) => {
    server = createServer((request, response) => {
      if (request.url === "/health") {
        response.writeHead(200, { "content-type": "application/json" });
        response.end(JSON.stringify({
          activeProject: {
            projectRoot,
            bridgeDir,
          },
        }));
        return;
      }
      response.writeHead(404, { "content-type": "application/json" });
      response.end(JSON.stringify({ error: "not_found" }));
    });
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => resolve());
  });
  try {
    const address = server.address();
    assert.ok(address && typeof address !== "string");
    await callback(`http://127.0.0.1:${address.port}/bridge/request`);
  } finally {
    await new Promise<void>((resolve) => server?.close(() => resolve()));
  }
}
