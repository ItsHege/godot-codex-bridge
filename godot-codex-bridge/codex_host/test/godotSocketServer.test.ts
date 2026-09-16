import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import WebSocket from "ws";
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
