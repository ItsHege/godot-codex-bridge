import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import WebSocket from "ws";
import { request as httpRequest } from "node:http";
import { createHmac } from "node:crypto";
import { loadConfig } from "../src/config.js";
import { MockCodexRuntime } from "../src/codexRuntime.js";
import { GodotSocketServer } from "../src/godotSocketServer.js";
import { HostController } from "../src/hostController.js";

const TEST_PAIR_SECRET = "a".repeat(64);

test("installation launch nonce binds HTTP health without changing ordinary Host status", async () => {
  const controller = new HostController(loadConfig(["--runtime", "mock"]), new MockCodexRuntime());
  const nonce = "a".repeat(64);
  const server = new GodotSocketServer("127.0.0.1", 0, controller, nonce);
  await server.start();
  try {
    const health = await (await fetch(`http://127.0.0.1:${server.addressPort()}/health`)).json() as Record<string, unknown>;
    assert.equal(health.launch_proof, createHmac("sha256", Buffer.from(nonce, "hex")).update("godot-codex-bridge-host-health-v1").digest("hex"));
    assert.equal(Object.hasOwn(health, "launch_nonce"), false);
    assert.equal(health.runtime, "mock");
    assert.equal(Object.hasOwn(controller.status(), "launch_nonce"), false);
  } finally {
    await server.stop();
  }
});

test("Godot socket server accepts health and project attach requests", async () => {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-host-ws-"));
  await fs.writeFile(path.join(projectRoot, "project.godot"), "[application]\n", "utf8");

  const port = 0;
  const config = loadConfig(["--runtime", "mock", "--port", String(port)]);
  const controller = new HostController(config, new MockCodexRuntime());
  const server = new GodotSocketServer("127.0.0.1", port, controller, "", TEST_PAIR_SECRET);
  await server.start();
  const actualPort = server.addressPort();

  const client = await openWebSocket(`ws://127.0.0.1:${actualPort}`);
  try {
    await pairClient(client);
    client.socket.send(JSON.stringify({ jsonrpc: "2.0", id: 1, method: "host.health" }));
    const health = await client.nextResponse(1);
    assert.equal(health.id, 1);
    assert.equal(health.result.state, "ready");

    client.socket.send(JSON.stringify({
      jsonrpc: "2.0",
      id: 2,
      method: "project.attach",
      params: { project_root: projectRoot }
    }));
    const attach = await client.nextResponse(2);
    assert.equal(attach.id, 2);
    assert.equal(attach.result.activeProject.projectRoot, projectRoot);
  } finally {
    client.socket.close();
    await server.stop();
  }
});

test("Godot socket server disables unauthenticated HTTP bridge RPC even with a paired addon", async () => {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-host-bridge-rpc-"));
  await fs.writeFile(path.join(projectRoot, "project.godot"), "[application]\n", "utf8");
  const bridgeDir = path.join(projectRoot, ".godot", "godot_codex_bridge");

  const port = 0;
  const config = loadConfig(["--runtime", "mock", "--port", String(port)]);
  const controller = new HostController(config, new MockCodexRuntime());
  const server = new GodotSocketServer("127.0.0.1", port, controller, "", TEST_PAIR_SECRET);
  await server.start();
  const actualPort = server.addressPort();

  const addon = await openWebSocket(`ws://127.0.0.1:${actualPort}`);
  try {
    await pairClient(addon);
    addon.socket.send(JSON.stringify({
      jsonrpc: "2.0",
      id: 1,
      method: "project.attach",
      params: { project_root: projectRoot, bridge_dir: bridgeDir }
    }));
    await addon.nextResponse(1);

    const pendingHttp = fetch(`http://127.0.0.1:${actualPort}/bridge/request`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        project_root: projectRoot,
        bridge_dir: bridgeDir,
        timeout_ms: 1_000,
        request: {
          protocol_version: "godot-codex-bridge/0.1",
          request_id: "bridge-rpc-test",
          type: "refresh_context",
          created_at: new Date().toISOString(),
          payload: {}
        }
      })
    });

    const httpResponse = await pendingHttp;
    assert.equal(httpResponse.status, 503);
    const result = await httpResponse.json() as any;
    assert.equal(result.error.code, "bridge_rpc_unavailable");
  } finally {
    addon.socket.close();
    await server.stop();
  }
});

test("unpaired native clients cannot read status, attach projects, set trust, or answer addon requests", async () => {
  const controller = new HostController(loadConfig(["--runtime", "mock"]), new MockCodexRuntime());
  const server = new GodotSocketServer("127.0.0.1", 0, controller);
  await server.start();
  const client = await openWebSocket(`ws://127.0.0.1:${server.addressPort()}`);
  try {
    const prompt = await client.nextNotification("host.pair_required");
    assert.equal(prompt.params.protocol, "godot-codex-bridge/pair-v2");
    for (const [id, method, params] of [
      [1, "host.health", {}],
      [2, "project.attach", { project_root: os.tmpdir() }],
      [3, "session.trust.set", { mode: "full_machine" }],
      [4, "approval.respond", { approval_id: "x", decision: "approve" }],
      [5, "host.shutdown", {}],
      [6, "bridge.addon_response", { request_id: "x", response: { status: "completed" } }],
    ] as const) {
      client.socket.send(JSON.stringify({ jsonrpc: "2.0", id, method, params }));
      const denied = await client.nextResponse(id);
      assert.equal(denied.error.message, "pairing_required");
    }
    client.socket.send(JSON.stringify({ jsonrpc: "2.0", id: 7, method: "host.pair", params: { client_nonce: "bad" } }));
    assert.equal((await client.nextResponse(7)).error.message, "invalid_pairing_nonce");
    assert.equal(controller.status().activeProject, undefined);
  } finally {
    client.socket.terminate();
    await server.stop();
  }
});

test("only one socket can be paired and a reconnect must pair again", async () => {
  const controller = new HostController(loadConfig(["--runtime", "mock"]), new MockCodexRuntime());
  const server = new GodotSocketServer("127.0.0.1", 0, controller, "", TEST_PAIR_SECRET);
  await server.start();
  const url = `ws://127.0.0.1:${server.addressPort()}`;
  const first = await openWebSocket(url);
  try {
    await pairClient(first);
    const rejected = await openWebSocket(url);
    await new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error("second socket was not closed")), 1_000);
      rejected.socket.once("close", () => { clearTimeout(timer); resolve(); });
    });
    first.socket.close();
    await new Promise<void>((resolve) => first.socket.once("close", resolve));
    const resumed = await openWebSocket(url);
    try {
      await resumed.nextNotification("host.pair_required");
      resumed.socket.send(JSON.stringify({ jsonrpc: "2.0", id: 1, method: "host.health" }));
      assert.equal((await resumed.nextResponse(1)).error.message, "pairing_required");
      await pairClient(resumed, false);
    } finally {
      resumed.socket.terminate();
    }
  } finally {
    first.socket.terminate();
    await server.stop();
  }
});

test("pair challenge binds both proofs to the socket and rejects an incorrect completion", async () => {
  const controller = new HostController(loadConfig(["--runtime", "mock"]), new MockCodexRuntime());
  const server = new GodotSocketServer("127.0.0.1", 0, controller, "", TEST_PAIR_SECRET);
  await server.start();
  const client = await openWebSocket(`ws://127.0.0.1:${server.addressPort()}`);
  try {
    await client.nextNotification("host.pair_required");
    const clientNonce = "b".repeat(64);
    client.socket.send(JSON.stringify({ jsonrpc: "2.0", id: 1, method: "host.pair", params: { client_nonce: clientNonce } }));
    const challenge = (await client.nextResponse(1)).result;
    assert.match(challenge.server_nonce, /^[a-f0-9]{64}$/);
    assert.equal(challenge.server_proof, createHmac("sha256", Buffer.from(TEST_PAIR_SECRET, "hex"))
      .update(`host:${clientNonce}:${challenge.server_nonce}`).digest("hex"));
    assert.equal(Object.hasOwn(challenge, "paired"), false);
    client.socket.send(JSON.stringify({ jsonrpc: "2.0", id: 2, method: "host.health" }));
    assert.equal((await client.nextResponse(2)).error.message, "pairing_required");
    client.socket.send(JSON.stringify({ jsonrpc: "2.0", id: 3, method: "host.pair_complete", params: { client_proof: "0".repeat(64) } }));
    assert.equal((await client.nextResponse(3)).error.message, "pairing_failed");
    await new Promise<void>((resolve) => client.socket.once("close", resolve));
  } finally {
    client.socket.terminate();
    await server.stop();
  }
});

test("another unpaired socket cannot complete a different socket's challenge", async () => {
  const controller = new HostController(loadConfig(["--runtime", "mock"]), new MockCodexRuntime());
  const server = new GodotSocketServer("127.0.0.1", 0, controller, "", TEST_PAIR_SECRET);
  await server.start();
  const url = `ws://127.0.0.1:${server.addressPort()}`;
  const first = await openWebSocket(url);
  const second = await openWebSocket(url);
  try {
    await first.nextNotification("host.pair_required");
    await second.nextNotification("host.pair_required");
    const clientNonce = "d".repeat(64);
    first.socket.send(JSON.stringify({ jsonrpc: "2.0", id: 1, method: "host.pair", params: { client_nonce: clientNonce } }));
    const challenge = (await first.nextResponse(1)).result;
    const proof = createHmac("sha256", Buffer.from(TEST_PAIR_SECRET, "hex"))
      .update(`addon:${clientNonce}:${challenge.server_nonce}`).digest("hex");
    second.socket.send(JSON.stringify({ jsonrpc: "2.0", id: 2, method: "host.pair_complete", params: { client_proof: proof } }));
    assert.equal((await second.nextResponse(2)).error.message, "pairing_failed");
    first.socket.send(JSON.stringify({ jsonrpc: "2.0", id: 3, method: "host.pair_complete", params: { client_proof: proof } }));
    assert.equal((await first.nextResponse(3)).result.paired, true);
  } finally {
    first.socket.terminate();
    second.socket.terminate();
    await server.stop();
  }
});

test("native IPC rejects browser and DNS-rebinding requests before RPC dispatch", async () => {
  const controller = new HostController(loadConfig(["--runtime", "mock"]), new MockCodexRuntime());
  const server = new GodotSocketServer("127.0.0.1", 0, controller);
  await server.start();
  const port = server.addressPort();
  try {
    assert.equal((await fetch(`http://127.0.0.1:${port}/health`)).status, 200);
    for (const headers of [
      { origin: "https://attacker.example" },
      { origin: "null" },
      { host: `attacker.example:${port}` },
      { "sec-fetch-site": "cross-site" }
    ]) {
      for (const endpoint of ["/health", "/bridge/request"]) {
        const status = await new Promise<number>((resolve, reject) => {
          const req = httpRequest({ host: "127.0.0.1", port, path: endpoint,
            method: endpoint === "/health" ? "GET" : "POST", headers }, (res) => {
            res.resume();
            resolve(res.statusCode!);
          });
          req.on("error", reject);
          req.end();
        });
        assert.equal(status, 403);
      }
      await assert.rejects(new Promise<void>((resolve, reject) => {
        const socket = new WebSocket(`ws://127.0.0.1:${port}`, { headers });
        socket.once("open", () => { socket.terminate(); resolve(); });
        socket.once("error", reject);
      }), /401/);
    }
    assert.equal(controller.status().activeProject, undefined);
  } finally {
    await server.stop();
  }
});

test("host refuses network binds even when constructed outside loadConfig", async () => {
  const controller = new HostController(loadConfig(["--runtime", "mock"]), new MockCodexRuntime());
  for (const bind of ["0.0.0.0", "::", "192.168.1.10", "attacker.example"]) {
    await assert.rejects(new GodotSocketServer(bind, 0, controller).start(), /loopback/);
  }
});

test("host config rejects nonloopback binds before launching app-server", () => {
  const previous = process.env.GODOT_CODEX_HOST_BIND;
  try {
    for (const bind of ["0.0.0.0", "::", "localhost", "192.168.1.10"]) {
      process.env.GODOT_CODEX_HOST_BIND = bind;
      assert.throws(() => loadConfig([]), /GODOT_CODEX_HOST_BIND/);
    }
    for (const bind of ["127.0.0.1", "::1"]) {
      process.env.GODOT_CODEX_HOST_BIND = bind;
      assert.equal(loadConfig([]).host, bind);
    }
  } finally {
    if (previous === undefined) delete process.env.GODOT_CODEX_HOST_BIND;
    else process.env.GODOT_CODEX_HOST_BIND = previous;
  }
});

test("oversized WebSocket frames close the client and leave the host healthy", async () => {
  const controller = new HostController(loadConfig(["--runtime", "mock"]), new MockCodexRuntime());
  const server = new GodotSocketServer("127.0.0.1", 0, controller);
  await server.start();
  const port = server.addressPort();
  const client = await openWebSocket(`ws://127.0.0.1:${port}`);
  try {
    const closed = new Promise<void>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error("oversized client not closed")), 2000);
      client.socket.once("close", () => { clearTimeout(timer); resolve(); });
    });
    client.socket.send("x".repeat(1024 * 1024 + 1));
    await closed;
    assert.equal((await fetch(`http://127.0.0.1:${port}/health`)).status, 200);
  } finally {
    client.socket.terminate();
    await server.stop();
  }
});

type TestClient = {
  socket: WebSocket;
  nextResponse: (id: number) => Promise<any>;
  nextNotification: (method: string) => Promise<any>;
};

async function pairClient(client: TestClient, awaitPrompt = true): Promise<void> {
  if (awaitPrompt) await client.nextNotification("host.pair_required");
  const clientNonce = "c".repeat(64);
  client.socket.send(JSON.stringify({ jsonrpc: "2.0", id: 100, method: "host.pair", params: { client_nonce: clientNonce } }));
  const challenge = (await client.nextResponse(100)).result;
  assert.match(challenge.server_nonce, /^[a-f0-9]{64}$/);
  assert.equal(challenge.server_proof, createHmac("sha256", Buffer.from(TEST_PAIR_SECRET, "hex"))
    .update(`host:${clientNonce}:${challenge.server_nonce}`).digest("hex"));
  const clientProof = createHmac("sha256", Buffer.from(TEST_PAIR_SECRET, "hex"))
    .update(`addon:${clientNonce}:${challenge.server_nonce}`).digest("hex");
  client.socket.send(JSON.stringify({ jsonrpc: "2.0", id: 101, method: "host.pair_complete", params: { client_proof: clientProof } }));
  assert.equal((await client.nextResponse(101)).result.paired, true);
  assert.equal((await client.nextNotification("host.status")).params.state, "ready");
}

function openWebSocket(url: string): Promise<TestClient> {
  const queue: any[] = [];
  const waiters: Array<(message: any) => void> = [];
  return new Promise((resolve, reject) => {
    const socket = new WebSocket(url);
    socket.on("message", (raw) => {
      const message = JSON.parse(String(raw));
      const waiter = waiters.shift();
      if (waiter) {
        waiter(message);
      } else {
        queue.push(message);
      }
    });
    socket.once("open", () => resolve({
      socket,
      nextResponse: (id) => nextResponse(queue, waiters, id),
      nextNotification: (method) => nextNotification(queue, waiters, method)
    }));
    socket.once("error", reject);
  });
}

function nextMessage(queue: any[], waiters: Array<(message: any) => void>): Promise<any> {
  const queued = queue.shift();
  if (queued) {
    return Promise.resolve(queued);
  }
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("timeout waiting for websocket message")), 1000);
    waiters.push((message) => {
      clearTimeout(timeout);
      resolve(message);
    });
  });
}

async function nextResponse(queue: any[], waiters: Array<(message: any) => void>, id: number): Promise<any> {
  const deadline = Date.now() + 1000;
  while (Date.now() < deadline) {
    const message = await nextMessage(queue, waiters);
    if (message.id === id) {
      return message;
    }
  }
  throw new Error(`timeout waiting for response ${id}`);
}

async function nextNotification(queue: any[], waiters: Array<(message: any) => void>, method: string): Promise<any> {
  const deadline = Date.now() + 1000;
  while (Date.now() < deadline) {
    const message = await nextMessage(queue, waiters);
    if (message.method === method) {
      return message;
    }
  }
  throw new Error(`timeout waiting for notification ${method}`);
}
