import assert from "node:assert/strict";
import { createServer, type Server } from "node:http";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { BridgeClient } from "../src/bridge.js";
import type { ServerConfig } from "../src/types.js";

test("BridgeClient reports bridge_unavailable when no snapshot exists", async () => {
  const config = await makeConfig();
  const bridge = new BridgeClient(config);

  const result = await bridge.readSnapshot();

  assert.equal(result.status, "bridge_unavailable");
});

test("BridgeClient reads the context snapshot and sections", async () => {
  const config = await makeConfig();
  await fs.mkdir(config.bridgeDir, { recursive: true });
  await fs.writeFile(
    path.join(config.bridgeDir, "context_snapshot.json"),
    JSON.stringify({
      protocol_version: "0.1",
      generated_at: "2026-06-13T00:00:00.000Z",
      project: { name: "Fixture" },
      scene_tree: { root: { name: "Root" } },
    }),
    "utf8",
  );

  const bridge = new BridgeClient(config);
  const result = await bridge.readSnapshotSection("scene_tree");

  assert.equal(result.status, "ok");
  assert.deepEqual(result.scene_tree, { root: { name: "Root" } });
});

test("BridgeClient writes addon request and returns timeout when live addon does not answer", async () => {
  const config = await makeConfig();
  await fs.mkdir(config.bridgeDir, { recursive: true });
  await writeLiveHeartbeat(config.bridgeDir);

  const bridge = new BridgeClient(config);
  const result = await bridge.sendAddonRequest("capture_viewport_screenshot", {}, 150);

  assert.equal(result.status, "timeout");
  assert.equal(result.transport, "file_polling");
  assert.equal(result.fallback_reason, "host_rpc_not_configured");
  assert.equal(Array.isArray(result.transport_attempts), true);
  assert.equal((result.transport_attempts as Array<{ transport?: string; status?: string }>)[0]?.status, "skipped");
  assert.equal((result.transport_attempts as Array<{ transport?: string; status?: string }>)[1]?.status, "timeout");
  assert.equal(typeof result.request_path, "string");
  await fs.access(String(result.request_path));
});

test("BridgeClient returns addon response when present", async () => {
  const config = await makeConfig();
  await fs.mkdir(path.join(config.bridgeDir, "responses"), { recursive: true });
  await writeLiveHeartbeat(config.bridgeDir);

  const bridge = new BridgeClient(config);
  const pending = bridge.sendAddonRequest("capture_viewport_screenshot", {}, 1_000);

  const requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
  const request = JSON.parse(await fs.readFile(requestPath, "utf8")) as { request_id: string };
  await fs.writeFile(
    path.join(config.bridgeDir, "responses", `${request.request_id}.json`),
    JSON.stringify({ status: "ok", data: { screenshot_path: "local.png" } }),
    "utf8",
  );

  const result = await pending;
  assert.equal(result.status, "ok");
  assert.equal(result.transport, "file_polling");
  assert.equal(result.fallback_reason, "host_rpc_not_configured");
  assert.equal((result.transport_attempts as Array<{ status?: string }>)[1]?.status, "succeeded");
  assert.equal((result.response as { status: string }).status, "ok");
});

test("BridgeClient uses host websocket RPC endpoint before file polling fallback", async () => {
  const config = await makeConfig();
  await fs.mkdir(config.bridgeDir, { recursive: true });
  await writeLiveHeartbeat(config.bridgeDir);
  const server = createServer((request, response) => {
    if (request.method === "GET" && request.url === "/health") {
      response.writeHead(200, { "content-type": "application/json" });
      response.end(JSON.stringify({
        activeProject: {
          projectRoot: config.projectRoot,
          bridgeDir: config.bridgeDir,
        },
      }));
      return;
    }
    assert.equal(request.method, "POST");
    assert.equal(request.url, "/bridge/request");
    let body = "";
    request.setEncoding("utf8");
    request.on("data", (chunk) => {
      body += chunk;
    });
    request.on("end", () => {
      const parsed = JSON.parse(body) as { request: { request_id: string; type: string } };
      response.writeHead(200, { "content-type": "application/json" });
      response.end(JSON.stringify({
        status: "ok",
        transport: "websocket_rpc",
        request_id: parsed.request.request_id,
        response: {
          request_id: parsed.request.request_id,
          type: parsed.request.type,
          status: "completed",
          data: { transport_marker: "host_rpc" },
        },
      }));
    });
  });
  await listen(server);
  const address = server.address();
  assert.notEqual(address, null);
  assert.notEqual(typeof address, "string");
  config.hostRpcUrl = `http://127.0.0.1:${(address as { port: number }).port}/bridge/request`;

  try {
    const bridge = new BridgeClient(config);
    const result = await bridge.sendAddonRequest("refresh_context", {}, 1_000);

    assert.equal(result.status, "ok");
    assert.equal(result.transport, "websocket_rpc");
    assert.equal((result.transport_attempts as Array<{ transport?: string; status?: string }>)[0]?.transport, "websocket_rpc");
    assert.equal((result.transport_attempts as Array<{ transport?: string; status?: string }>)[0]?.status, "succeeded");
    assert.equal((result.response as { status: string }).status, "completed");
    await assert.rejects(fs.readdir(path.join(config.bridgeDir, "requests")));
  } finally {
    await close(server);
  }
});

test("BridgeClient reports host RPC failure before file polling fallback", async () => {
  const config = await makeConfig();
  await fs.mkdir(path.join(config.bridgeDir, "responses"), { recursive: true });
  await writeLiveHeartbeat(config.bridgeDir);
  const server = createServer((_request, response) => {
    response.writeHead(409, { "content-type": "application/json" });
    response.end(JSON.stringify({
      status: "error",
      error: {
        code: "addon_not_connected",
        message: "No Godot addon WebSocket client is connected.",
      },
    }));
  });
  await listen(server);
  const address = server.address();
  assert.notEqual(address, null);
  assert.notEqual(typeof address, "string");
  config.hostRpcUrl = `http://127.0.0.1:${(address as { port: number }).port}/bridge/request`;

  try {
    const bridge = new BridgeClient(config);
    const pending = bridge.sendAddonRequest("refresh_context", {}, 1_000);
    const requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
    const request = JSON.parse(await fs.readFile(requestPath, "utf8")) as { request_id: string };
    await fs.writeFile(
      path.join(config.bridgeDir, "responses", `${request.request_id}.json`),
      JSON.stringify({ status: "succeeded", data: { transport_marker: "file_fallback" } }),
      "utf8",
    );

    const result = await pending;
    assert.equal(result.status, "ok");
    assert.equal(result.transport, "file_polling");
    assert.equal(result.fallback_reason, "addon_not_connected");
    const attempts = result.transport_attempts as Array<{ transport?: string; status?: string; error?: { code?: string } }>;
    assert.equal(attempts.length, 2);
    assert.equal(attempts[0]?.transport, "websocket_rpc");
    assert.equal(attempts[0]?.status, "failed");
    assert.equal(attempts[0]?.error?.code, "addon_not_connected");
    assert.equal(attempts[1]?.transport, "file_polling");
    assert.equal(attempts[1]?.status, "succeeded");
  } finally {
    await close(server);
  }
});

test("BridgeClient treats contract succeeded addon response as ok", async () => {
  const config = await makeConfig();
  await fs.mkdir(path.join(config.bridgeDir, "responses"), { recursive: true });
  await writeLiveHeartbeat(config.bridgeDir);

  const bridge = new BridgeClient(config);
  const pending = bridge.sendAddonRequest("refresh_context", {}, 1_000);

  const requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
  const request = JSON.parse(await fs.readFile(requestPath, "utf8")) as { request_id: string };
  await fs.writeFile(
    path.join(config.bridgeDir, "responses", `${request.request_id}.json`),
    JSON.stringify({ status: "succeeded", data: { context_snapshot_path: "context_snapshot.json" } }),
    "utf8",
  );

  const result = await pending;
  assert.equal(result.status, "ok");
  assert.equal((result.response as { status: string }).status, "succeeded");
});

test("BridgeClient rejects addon request when heartbeat is stale", async () => {
  const config = await makeConfig();
  await fs.mkdir(config.bridgeDir, { recursive: true });
  await fs.writeFile(
    path.join(config.bridgeDir, "heartbeat.json"),
    JSON.stringify({
      protocol_version: "godot-codex-bridge/0.1",
      addon_active: true,
      updated_at: "2000-01-01T00:00:00.000Z",
    }),
    "utf8",
  );

  const bridge = new BridgeClient(config);
  const result = await bridge.sendAddonRequest("capture_viewport_screenshot", {}, 150);

  assert.equal(result.status, "bridge_unavailable");
  assert.equal((result.bridge_status as { stale_editor?: boolean }).stale_editor, true);
});

async function makeConfig(): Promise<ServerConfig> {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-bridge-"));
  return {
    projectRoot,
    bridgeDir: path.join(projectRoot, ".godot", "godot_codex_bridge"),
    godotExecutable: process.execPath,
    addonRequestTimeoutMs: 250,
    runSceneTimeoutMs: 1_000,
  };
}

async function waitForRequest(requestsDir: string): Promise<string> {
  const deadline = Date.now() + 1_000;
  while (Date.now() <= deadline) {
    try {
      const entries = await fs.readdir(requestsDir);
      const first = entries.find((entry) => entry.endsWith(".json"));
      if (first) {
        return path.join(requestsDir, first);
      }
    } catch {
      // Directory may not exist until the request is created.
    }
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  throw new Error("request not written");
}

async function writeLiveHeartbeat(bridgeDir: string): Promise<void> {
  await fs.mkdir(bridgeDir, { recursive: true });
  await fs.writeFile(
    path.join(bridgeDir, "heartbeat.json"),
    JSON.stringify({
      protocol_version: "godot-codex-bridge/0.1",
      addon_active: true,
      updated_at: new Date().toISOString(),
    }),
    "utf8",
  );
}

function listen(server: Server): Promise<void> {
  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => resolve());
  });
}

function close(server: Server): Promise<void> {
  return new Promise((resolve) => server.close(() => resolve()));
}
