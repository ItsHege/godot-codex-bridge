import assert from "node:assert/strict";
import test from "node:test";
import { createHmac } from "node:crypto";
import WebSocket from "ws";
import { loadConfig } from "../src/config.js";
import { MockCodexRuntime } from "../src/codexRuntime.js";
import { GodotSocketServer } from "../src/godotSocketServer.js";
import { HostController } from "../src/hostController.js";
import { projectIdentityHash } from "../src/projectIdentity.js";

const PAIR_SECRET = "c".repeat(64);

test("unpaired notifications and invalid pair proofs cannot gain Host privilege", async () => {
  const controller = new HostController(loadConfig(["--runtime", "mock"]), new MockCodexRuntime());
  const server = new GodotSocketServer("127.0.0.1", 0, controller, "", PAIR_SECRET);
  await server.start();
  const url = `ws://127.0.0.1:${server.addressPort()}`;
  const client = await connect(url);
  try {
    assert.equal((await nextMessage(client)).method, "host.pair_required");
    client.socket.send(JSON.stringify({ jsonrpc: "2.0", method: "session.trust.set", params: { mode: "full_machine" } }));
    client.socket.send(JSON.stringify({ jsonrpc: "2.0", method: "host.shutdown" }));
    client.socket.send(JSON.stringify({ jsonrpc: "2.0", method: "bridge.addon_response", params: { request_id: "forged", response: { status: "succeeded" } } }));
    client.socket.send(JSON.stringify({ jsonrpc: "2.0", id: 1, method: "host.health" }));
    const denied = await nextMessage(client);
    assert.equal(denied.id, 1);
    assert.equal(denied.error.message, "pairing_required");
    assert.equal(controller.status().trustMode, "off");

    const closed = new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error("bad pairing socket remained open")), 2_000);
      client.socket.once("close", () => { clearTimeout(timeout); resolve(); });
    });
    for (let id = 2; id <= 6; id += 1) {
      client.socket.send(JSON.stringify({ jsonrpc: "2.0", id, method: "host.pair", params: { client_nonce: "invalid" } }));
    }
    await closed;
    assert.equal(controller.status().trustMode, "off");
    assert.equal(controller.status().activeProject, undefined);

    const impostor = await connect(url);
    try {
      assert.equal((await nextMessage(impostor)).method, "host.pair_required");
      impostor.socket.send(JSON.stringify({ jsonrpc: "2.0", id: 7, method: "host.pair", params: { client_nonce: "e".repeat(64) } }));
      assert.equal(typeof (await nextMessage(impostor)).result.server_proof, "string");
      const impostorClosed = new Promise<void>((resolve, reject) => {
        const timeout = setTimeout(() => reject(new Error("invalid proof socket remained open")), 2_000);
        impostor.socket.once("close", () => { clearTimeout(timeout); resolve(); });
      });
      impostor.socket.send(JSON.stringify({ jsonrpc: "2.0", id: 8, method: "host.pair_complete", params: { client_proof: "f".repeat(64) } }));
      await impostorClosed;
      assert.equal(controller.status().trustMode, "off");
    } finally {
      impostor.socket.terminate();
    }

    const addon = await connect(url);
    try {
      assert.equal((await nextMessage(addon)).method, "host.pair_required");
      const clientNonce = "1".repeat(64);
      addon.socket.send(JSON.stringify({ jsonrpc: "2.0", id: 9, method: "host.pair", params: { client_nonce: clientNonce } }));
      const challenge = (await nextMessage(addon)).result;
      const proof = (direction: string) => createHmac("sha256", Buffer.from(PAIR_SECRET, "hex"))
        .update(`${direction}:${clientNonce}:${challenge.server_nonce}`).digest("hex");
      assert.equal(challenge.server_proof, proof("host"));
      addon.socket.send(JSON.stringify({ jsonrpc: "2.0", id: 10, method: "host.pair_complete", params: { client_proof: proof("addon") } }));
      assert.equal((await nextMessage(addon)).result.paired, true);
      assert.equal((await nextMessage(addon)).method, "host.status");
      addon.socket.send(JSON.stringify({ jsonrpc: "2.0", id: 11, method: "host.health" }));
      assert.equal((await nextMessage(addon)).result.state, "ready");
    } finally {
      addon.socket.terminate();
    }
  } finally {
    client.socket.terminate();
    await server.stop();
  }
});

test("heartbeat drops silent unpaired sockets but keeps a responsive one", async () => {
  const controller = new HostController(loadConfig(["--runtime", "mock"]), new MockCodexRuntime());
  const server = new GodotSocketServer("127.0.0.1", 0, controller, "", PAIR_SECRET);
  server.heartbeatIntervalMs = 50;
  await server.start();
  const url = `ws://127.0.0.1:${server.addressPort()}`;
  const responsive = await connect(url);
  const silent = await connect(url, { autoPong: false });
  try {
    await closedWithin(silent, 2_000, "silent socket was not dropped");
    await sleep(80);
    assert.equal(responsive.socket.readyState, WebSocket.OPEN);
    server.pairingDeadlineMs = 100;
    await closedWithin(responsive, 2_000, "unpaired socket outlived the pairing deadline");
  } finally {
    silent.socket.terminate();
    responsive.socket.terminate();
    await server.stop();
  }
});

test("a silent paired addon stays until a reconnecting client replaces it", async () => {
  const controller = new HostController(loadConfig(["--runtime", "mock"]), new MockCodexRuntime());
  const server = new GodotSocketServer("127.0.0.1", 0, controller, "", PAIR_SECRET);
  server.heartbeatIntervalMs = 50;
  await server.start();
  const url = `ws://127.0.0.1:${server.addressPort()}`;
  const stalled = await connect(url, { autoPong: false });
  let replacement: Client | undefined;
  try {
    await pair(stalled, "2".repeat(64));
    await sleep(300);
    assert.equal(stalled.socket.readyState, WebSocket.OPEN, "a stalled but paired editor must not be dropped on silence alone");
    replacement = await connect(url);
    await closedWithin(stalled, 2_000, "unresponsive paired socket was not replaced");
    await pair(replacement, "3".repeat(64));
  } finally {
    stalled.socket.terminate();
    replacement?.socket.terminate();
    await server.stop();
  }
});

async function pair(client: Client, clientNonce: string): Promise<void> {
  assert.equal((await nextMessage(client)).method, "host.pair_required");
  client.socket.send(JSON.stringify({ jsonrpc: "2.0", id: 1, method: "host.pair", params: { client_nonce: clientNonce } }));
  const challenge = (await nextMessage(client)).result;
  const proof = createHmac("sha256", Buffer.from(PAIR_SECRET, "hex"))
    .update(`addon:${clientNonce}:${challenge.server_nonce}`).digest("hex");
  client.socket.send(JSON.stringify({ jsonrpc: "2.0", id: 2, method: "host.pair_complete", params: { client_proof: proof } }));
  assert.equal((await nextMessage(client)).result.paired, true);
}

function closedWithin(client: Client, ms: number, message: string): Promise<void> {
  if (client.socket.readyState === WebSocket.CLOSED) return Promise.resolve();
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error(message)), ms);
    client.socket.once("close", () => { clearTimeout(timeout); resolve(); });
  });
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

type Client = { socket: WebSocket; queue: any[]; waiters: Array<(value: any) => void> };

function connect(url: string, options: WebSocket.ClientOptions = {}): Promise<Client> {
  return new Promise((resolve, reject) => {
    const client: Client = { socket: new WebSocket(url, options), queue: [], waiters: [] };
    client.socket.on("message", (raw) => {
      const message = JSON.parse(String(raw));
      const waiter = client.waiters.shift();
      if (waiter) waiter(message);
      else client.queue.push(message);
    });
    client.socket.once("open", () => resolve(client));
    client.socket.once("error", reject);
  });
}

function nextMessage(client: Client): Promise<any> {
  const queued = client.queue.shift();
  if (queued) return Promise.resolve(queued);
  return new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error("timed out waiting for Host message")), 2_000);
    client.waiters.push((value) => { clearTimeout(timeout); resolve(value); });
  });
}

test("health publishes only a hash of the attached project, and the hash matches the MCP algorithm", async () => {
  const controller = new HostController(loadConfig(["--runtime", "mock"]), new MockCodexRuntime());
  const server = new GodotSocketServer("127.0.0.1", 0, controller, "", PAIR_SECRET);
  const projectRoot = await import("node:fs/promises").then((fs) => fs.mkdtemp(`${process.env.TEMP ?? "/tmp"}/gcb-health-identity-`));
  await import("node:fs/promises").then((fs) => fs.writeFile(`${projectRoot}/project.godot`, "[application]\n"));
  await controller.handleRequest({ jsonrpc: "2.0", id: 1, method: "project.attach", params: { project_root: projectRoot } });
  await server.start();
  try {
    const health = await (await fetch(`http://127.0.0.1:${server.addressPort()}/health`)).json() as Record<string, any>;
    assert.equal(health.activeProject, undefined, "no project path in unauthenticated health");
    assert.equal(JSON.stringify(health).includes("gcb-health-identity"), false);
    assert.equal(health.project_identity.project_root_sha256, projectIdentityHash(projectRoot));
    assert.equal(projectIdentityHash("C:\\Games\\My Game\\", "win32"), projectIdentityHash("c:/games/my game", "win32"));
  } finally {
    await server.stop();
    await controller.shutdown();
  }
});
