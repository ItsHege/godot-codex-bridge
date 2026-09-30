import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import type { ChildProcess } from "node:child_process";
import { WebSocketServer } from "ws";
import { AppServerRuntime } from "../src/appServerRuntime.js";
import { loadConfig } from "../src/config.js";
import { HostController } from "../src/hostController.js";
import type { HostEvent } from "../src/types.js";

const threadId = "thread-qa-child-exit";

test("missing Codex executable reports spawn failure without hanging or crashing Host runtime", async () => {
  const runtime = new AppServerRuntime({
    codexBin: path.join(os.tmpdir(), `missing-codex-${Date.now()}.exe`),
    host: "127.0.0.1", port: 0, backpressureLimit: 10,
  });
  try {
    await assert.rejects(
      runtime.startThread({ projectRoot: os.tmpdir() }),
      /spawn failed|ENOENT|process stopped/i,
    );
  } finally {
    await runtime.shutdown();
  }
});

test("child exit during streamed pending approval terminates turn once and later send runs", async () => {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-qa-child-exit-"));
  await fs.writeFile(path.join(projectRoot, "project.godot"), "[application]\n", "utf8");
  const runtime = new AppServerRuntime({ codexBin: "unused", host: "127.0.0.1", port: 0, backpressureLimit: 50 });
  const transport = runtime as unknown as {
    ensureConnected(): Promise<void>;
    request(method: string): Promise<unknown>;
    handleMessage(raw: string): void;
    handleProcessFailure(proc: ChildProcess, message: string): void;
    proc: ChildProcess | null;
    socket: { readyState: number; send(raw: string): void; close(): void } | null;
  };
  let turnIndex = 0;
  transport.ensureConnected = async () => {};
  transport.request = async (method) => {
    if (method === "thread/start") return { thread: { id: threadId }, cwd: projectRoot, instructionSources: [] };
    if (method === "turn/start") return { turn: { id: `turn-${++turnIndex}` } };
    throw new Error(`unexpected test request: ${method}`);
  };
  (runtime as unknown as { inspectMcpTools(): Promise<unknown> }).inspectMcpTools = async () => ({
    available: false, serverName: null, toolCount: 0, godotToolCount: 0, godotTools: [], checkedAt: new Date().toISOString(),
  });
  const fakeProc = new EventEmitter() as ChildProcess;

  const controller = new HostController(loadConfig(["--runtime", "mock"]), runtime);
  const events: HostEvent[] = [];
  controller.on("event", (item) => events.push(item));
  try {
    await controller.handleRequest({ method: "project.attach", params: { project_root: projectRoot } });
    // Attach binds the Bridge MCP server; install the fake app-server afterwards.
    transport.proc = fakeProc;
    transport.socket = { readyState: 1, send: () => {}, close: () => {} };
    await controller.handleRequest({ method: "thread.send", params: { message: "stream before child exit" } });
    await waitFor(() => events.some((item) => item.method === "turn.started"));
    transport.handleMessage(JSON.stringify({ method: "item/agentMessage/delta", params: {
      threadId, turnId: "turn-1", itemId: "message-1", delta: "partial stream",
    } }));
    transport.handleMessage(JSON.stringify({ id: 71, method: "item/commandExecution/requestApproval", params: {
      threadId, turnId: "turn-1", itemId: "command-1", startedAtMs: Date.now(),
      kind: "command", environmentId: null, command: "echo pending", cwd: projectRoot,
    } }));
    await waitFor(() => events.some((item) => item.method === "approval.requested"));
    const requested = events.find((item) => item.method === "approval.requested")!;
    assert.equal(events.some((item) => item.method === "turn.event" && item.params.text === "partial stream"), true);

    transport.handleProcessFailure(fakeProc, "codex app-server exited with code 17 signal null");
    await waitFor(() => controller.status().state === "error_recoverable");
    assert.equal(controller.status().pendingApprovals, 0);
    assert.match(String(controller.status().recoverableMessage), /exited with code 17/);
    assert.equal(events.filter((item) => item.method === "error").length, 1);
    assert.equal(events.filter((item) => item.method === "turn.completed").length, 0);
    const invalidated = events.find((item) => item.method === "approval.resolved" && item.params.approval_id === requested.params.approval_id);
    assert.equal(invalidated?.params.status, "invalidated");
    await assert.rejects(controller.handleRequest({ method: "approval.respond", params: {
      approval_id: requested.params.approval_id, nonce: requested.params.nonce, decision: "approve",
    } }), /approval_not_pending|stale/i);

    await controller.handleRequest({ method: "thread.send", params: { message: "second turn after recovery" } });
    await waitFor(() => events.filter((item) => item.method === "turn.started").length === 2);
    transport.handleMessage(JSON.stringify({ method: "turn/completed", params: {
      threadId, turn: { id: "turn-2", status: "completed" },
    } }));
    await waitFor(() => controller.status().state === "ready");
    assert.equal(events.filter((item) => item.method === "turn.completed").length, 1);
  } finally {
    await controller.shutdown();
  }
});

test("socket close while streaming yields one recoverable terminal event", async () => {
  const server = new WebSocketServer({ host: "127.0.0.1", port: 0 });
  await new Promise<void>((resolve) => server.once("listening", resolve));
  const address = server.address();
  assert.ok(address && typeof address !== "string");
  const runtime = new AppServerRuntime({ codexBin: "unused", host: "127.0.0.1", port: address.port, backpressureLimit: 10 });
  const transport = runtime as unknown as {
    ensureConnected(): Promise<void>;
    request(method: string): Promise<unknown>;
    connectSocket(): Promise<void>;
    handleMessage(raw: string): void;
    proc: ChildProcess | null;
  };
  let processKilled = false;
  transport.proc = { killed: false, kill: () => { processKilled = true; return true; } } as ChildProcess;
  transport.ensureConnected = async () => {};
  transport.request = async () => ({ turn: { id: "turn-socket-close" } });
  const connected = new Promise<any>((resolve) => server.once("connection", resolve));
  try {
    await transport.connectSocket();
    const peer = await connected;
    const iterator = runtime.runTurn({ threadId, projectRoot: ".", message: "stream" })[Symbol.asyncIterator]();
    assert.equal((await iterator.next()).value?.method, "turn.started");
    transport.handleMessage(JSON.stringify({ method: "item/agentMessage/delta", params: {
      threadId, turnId: "turn-socket-close", itemId: "message-1", delta: "partial",
    } }));
    assert.equal((await iterator.next()).value?.method, "turn.event");
    peer.close();
    const terminal = await iterator.next();
    assert.equal(terminal.value?.method, "error");
    assert.equal(terminal.value?.params.recoverable, true);
    assert.equal((await iterator.next()).done, true);
    assert.equal(processKilled, true);
  } finally {
    await runtime.shutdown();
    await new Promise<void>((resolve) => server.close(() => resolve()));
  }
});

async function waitFor(predicate: () => boolean): Promise<void> {
  const deadline = Date.now() + 2_000;
  while (Date.now() < deadline) {
    if (predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  throw new Error("turn failure test timeout");
}
