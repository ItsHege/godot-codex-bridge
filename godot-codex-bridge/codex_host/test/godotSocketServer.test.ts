import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import WebSocket from "ws";
import { request as httpRequest } from "node:http";
import { loadConfig } from "../src/config.js";
import { MockCodexRuntime } from "../src/codexRuntime.js";
import { GodotSocketServer } from "../src/godotSocketServer.js";
import { HostController } from "../src/hostController.js";

test("Godot socket server accepts health and project attach requests", async () => {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-host-ws-"));
  await fs.writeFile(path.join(projectRoot, "project.godot"), "[application]\n", "utf8");

  const port = 0;
  const config = loadConfig(["--runtime", "mock", "--port", String(port)]);
  const controller = new HostController(config, new MockCodexRuntime());
  const server = new GodotSocketServer("127.0.0.1", port, controller);
  await server.start();
  const actualPort = server.addressPort();

  const client = await openWebSocket(`ws://127.0.0.1:${actualPort}`);
  try {
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

test("Godot socket server relays bridge RPC requests to the connected addon", async () => {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-host-bridge-rpc-"));
  await fs.writeFile(path.join(projectRoot, "project.godot"), "[application]\n", "utf8");
  const bridgeDir = path.join(projectRoot, ".godot", "godot_codex_bridge");

  const port = 0;
  const config = loadConfig(["--runtime", "mock", "--port", String(port)]);
  const controller = new HostController(config, new MockCodexRuntime());
  const server = new GodotSocketServer("127.0.0.1", port, controller);
  await server.start();
  const actualPort = server.addressPort();

  const addon = await openWebSocket(`ws://127.0.0.1:${actualPort}`);
  try {
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

    const relay = await addon.nextNotification("bridge.addon_request");
    assert.equal(relay.params.request_id, "bridge-rpc-test");
    addon.socket.send(JSON.stringify({
      jsonrpc: "2.0",
      method: "bridge.addon_response",
      params: {
        request_id: "bridge-rpc-test",
        response: {
          request_id: "bridge-rpc-test",
          type: "refresh_context",
          status: "completed",
          data: { generated_at: "now" }
        }
      }
    }));

    const httpResponse = await pendingHttp;
    assert.equal(httpResponse.status, 200);
    const result = await httpResponse.json() as any;
    assert.equal(result.status, "ok");
    assert.equal(result.transport, "websocket_rpc");
    assert.equal(result.response.status, "completed");
  } finally {
    addon.socket.close();
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
