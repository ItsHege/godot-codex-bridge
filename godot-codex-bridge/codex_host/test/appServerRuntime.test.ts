import assert from "node:assert/strict";
import test from "node:test";
import {
  AppServerRuntime,
  appServerListenUrl,
  codexChildEnvironment,
  appServerThreadStartParams,
  appServerTurnStartParams,
  diffTextFromFileUpdateChanges,
  fileChangesFromFileUpdateChanges,
  normalizeRuntimeReasoningEffort,
  bridgeMcpOverrideArgs,
  responseForApproval,
  terminateProcessTree
} from "../src/appServerRuntime.js";
import type { HostEvent } from "../src/types.js";

test("app-server URLs bracket IPv6 loopback for both listener and client", () => {
  assert.equal(appServerListenUrl("::1", 49391), "ws://[::1]:49391");
  assert.equal(appServerListenUrl("127.0.0.1", 49391), "ws://127.0.0.1:49391");
});

test("Codex child process does not inherit Host pairing or launch secrets", () => {
  const parent = {
    PATH: "trusted-path",
    GODOT_CODEX_HOST_PAIR_SECRET: "a".repeat(64),
    GODOT_CODEX_HOST_LAUNCH_NONCE: "b".repeat(64),
    godot_codex_host_pair_secret: "c".repeat(64),
  };
  const child = codexChildEnvironment(parent);
  assert.equal(child.PATH, "trusted-path");
  assert.equal(child.GODOT_CODEX_HOST_PAIR_SECRET, undefined);
  assert.equal(child.GODOT_CODEX_HOST_LAUNCH_NONCE, undefined);
  assert.equal(child.godot_codex_host_pair_secret, undefined);
  assert.equal(parent.GODOT_CODEX_HOST_PAIR_SECRET, "a".repeat(64));
});

test("reasoning effort identifiers accept bounded server values and reject malformed input", () => {
  for (const effort of ["none", "xhigh", "max", "ultra", "future_mode-2"]) {
    assert.equal(normalizeRuntimeReasoningEffort(effort), effort);
  }
  for (const effort of [undefined, null, "", " high", "high ", "HIGH", "../high", "x.high", "a".repeat(33)]) {
    assert.equal(normalizeRuntimeReasoningEffort(effort), undefined);
  }
  assert.equal(appServerTurnStartParams({
    threadId: "thread", projectRoot: ".", message: "dynamic", effort: "ultra",
  }).effort, "ultra");
  assert.throws(() => appServerTurnStartParams({
    threadId: "thread", projectRoot: ".", message: "unsafe", effort: "../high",
  }), /invalid_reasoning_effort/);
  assert.throws(() => appServerTurnStartParams({
    threadId: "thread", projectRoot: ".", message: "empty", effort: "",
  }), /invalid_reasoning_effort/);
});

test("model inventory preserves safe dynamic efforts and per-model defaults without fallback pollution", async () => {
  const runtime = new AppServerRuntime({ codexBin: "unused", host: "127.0.0.1", port: 0, backpressureLimit: 10 });
  const transport = runtime as unknown as {
    ensureConnected(): Promise<void>;
    request(method: string): Promise<unknown>;
  };
  transport.ensureConnected = async () => {};
  transport.request = async (method) => {
    assert.equal(method, "model/list");
    return { data: [
      {
        id: "dynamic", model: "dynamic-model", displayName: "Dynamic", description: "Dynamic efforts",
        hidden: false, isDefault: true, inputModalities: ["text"], defaultReasoningEffort: "ultra",
        supportedReasoningEfforts: [
          { reasoningEffort: "max", description: "Maximum" },
          { reasoningEffort: "ultra", description: "Ultra" },
          { reasoningEffort: "max", description: "Duplicate" },
          { reasoningEffort: "../unsafe", description: "Unsafe" },
          { reasoningEffort: "a".repeat(33), description: "Oversized" },
        ],
      },
      {
        id: "default-only", model: "default-only", displayName: "Default only", description: "",
        hidden: false, isDefault: false, inputModalities: ["text"], defaultReasoningEffort: "future_mode-2",
        supportedReasoningEfforts: [],
      },
    ] };
  };
  const inventory = await runtime.listModels();
  assert.deepEqual(inventory.reasoningEfforts.map((option) => option.reasoningEffort), ["max", "ultra", "future_mode-2"]);
  assert.deepEqual(inventory.models[0].supportedReasoningEfforts, [
    { reasoningEffort: "max", description: "Maximum" },
    { reasoningEffort: "ultra", description: "Ultra" },
  ]);
  assert.deepEqual(inventory.models[1].supportedReasoningEfforts, [{ reasoningEffort: "future_mode-2" }]);
  assert.equal(inventory.models[1].defaultReasoningEffort, "future_mode-2");
});

test("model inventory uses the known safe fallback only when no valid effort is reported", async () => {
  const runtime = new AppServerRuntime({ codexBin: "unused", host: "127.0.0.1", port: 0, backpressureLimit: 10 });
  const transport = runtime as unknown as {
    ensureConnected(): Promise<void>;
    request(): Promise<unknown>;
  };
  transport.ensureConnected = async () => {};
  transport.request = async () => ({ data: [{
    id: "invalid", model: "invalid", displayName: "Invalid", description: "", hidden: false,
    isDefault: true, inputModalities: ["text"], defaultReasoningEffort: "../unsafe",
    supportedReasoningEfforts: [{ reasoningEffort: "", description: "Empty" }],
  }] });
  const inventory = await runtime.listModels();
  assert.equal(inventory.models[0].defaultReasoningEffort, undefined);
  assert.deepEqual(inventory.models[0].supportedReasoningEfforts, []);
  assert.deepEqual(inventory.reasoningEfforts.map((option) => option.reasoningEffort), ["minimal", "low", "medium", "high", "xhigh"]);
});

function runtimeWithNotifications(notifications: unknown[], responses: unknown[] = []): AppServerRuntime {
  const runtime = new AppServerRuntime({
    codexBin: "unused-test-codex",
    host: "127.0.0.1",
    port: 0,
    backpressureLimit: 500,
  });
  // Stub only the transport boundary; exercise the real wire parser, queue,
  // notification mapping and runTurn lifecycle without a Codex account.
  const transport = runtime as unknown as {
    ensureConnected(): Promise<void>;
    request(method: string): Promise<unknown>;
    handleMessage(raw: string): void;
    socket: { readyState: number; send(raw: string, callback?: (error?: Error) => void): void };
  };
  transport.socket = {
    readyState: 1,
    send: (raw, callback) => {
      responses.push(JSON.parse(raw));
      callback?.();
    },
  };
  transport.ensureConnected = async () => {};
  transport.request = async (method) => {
    assert.equal(method, "turn/start");
    return { turn: { id: "turn-retry" } };
  };
  for (const notification of notifications) {
    transport.handleMessage(JSON.stringify(notification));
  }
  return runtime;
}

async function collectApprovalEvents(messages: unknown[], responses: unknown[] = []): Promise<HostEvent[]> {
  const runtime = runtimeWithNotifications([...messages, {
    method: "turn/completed", params: {
      threadId: "thread-retry", turn: { id: "turn-retry", status: "completed" },
    },
  }], responses);
  const events: HostEvent[] = [];
  for await (const notification of runtime.runTurn({ threadId: "thread-retry", projectRoot: ".", message: "Review approval" })) {
    events.push(notification);
  }
  return events;
}

test("unsupported network, terminal input and environment approvals are declined with visible reasons", async () => {
  for (const [extra, reason] of [
    [{ networkApprovalContext: { host: "example.com", protocol: "https" } }, /managed network access/],
    [{ kind: "writeStdin" }, /terminal input/],
    [{ kind: "futureAction" }, /unknown command action/],
    [{ environmentId: "remote-environment" }, /explicit execution environment/],
  ] as const) {
    const responses: unknown[] = [];
    const events = await collectApprovalEvents([{
      id: 7, method: "item/commandExecution/requestApproval",
      params: { threadId: "thread-retry", turnId: "turn-retry", itemId: "command-1", command: "echo test", ...extra },
    }], responses);
    assert.deepEqual(responses, [{ id: 7, result: { decision: "decline" } }]);
    assert.equal(events.some((notification) => notification.method === "approval.requested"), false);
    const warning = events.find((notification) => notification.method === "runtime.warning");
    assert.match(String(warning?.params.message), reason);
  }
  const responses: unknown[] = [];
  await collectApprovalEvents([{
    id: 8, method: "item/permissions/requestApproval",
    params: { threadId: "thread-retry", turnId: "turn-retry", itemId: "permission-1", environmentId: "remote-environment", permissions: { network: { enabled: true } } },
  }], responses);
  assert.deepEqual(responses, [{ id: 8, result: { permissions: {}, scope: "turn", strictAutoReview: true } }]);
});

test("ordinary command approvals remain available for old and current command schemas", async () => {
  for (const extra of [
    {},
    { kind: "command", environmentId: null, networkApprovalContext: null },
    { kind: "command", environmentId: null, proposedExecpolicyAmendment: ["echo", "test"] },
  ]) {
    const responses: unknown[] = [];
    const events = await collectApprovalEvents([{
      id: 9, method: "item/commandExecution/requestApproval",
      params: { threadId: "thread-retry", turnId: "turn-retry", itemId: "command-1", command: "echo test", ...extra },
    }], responses);
    assert.deepEqual(responses, []);
    assert.equal(events.find((notification) => notification.method === "approval.requested")?.params.command, "echo test");
  }
});

test("serverRequest/resolved invalidates the exact pending approval and late clicks send nothing", async () => {
  const responses: unknown[] = [];
  const runtime = runtimeWithNotifications([
    { id: 41, method: "item/commandExecution/requestApproval", params: {
      threadId: "thread-retry", turnId: "turn-retry", itemId: "command-41", command: "echo test",
    } },
    { method: "serverRequest/resolved", params: { threadId: "thread-retry", requestId: 41 } },
    { method: "serverRequest/resolved", params: { threadId: "thread-retry", requestId: 41 } },
    { method: "turn/completed", params: {
      threadId: "thread-retry", turn: { id: "turn-retry", status: "completed" },
    } },
  ], responses);
  const events: HostEvent[] = [];
  for await (const notification of runtime.runTurn({ threadId: "thread-retry", projectRoot: ".", message: "Resolved approval" })) {
    events.push(notification);
  }
  const requested = events.find((notification) => notification.method === "approval.requested")!;
  const invalidated = events.filter((notification) => notification.method === "approval.invalidated");
  assert.equal(invalidated.length, 1);
  assert.equal(invalidated[0].params.runtime_approval_id, requested.params.runtime_approval_id);
  assert.equal(invalidated[0].params.request_id, 41);
  assert.equal(invalidated[0].params.reason, "server_resolved");
  await assert.rejects(
    runtime.respondToApproval(String(requested.params.runtime_approval_id), "approve"),
    /runtime_approval_not_found/,
  );
  assert.deepEqual(responses, []);
});

test("approval response waits for WebSocket callback and delayed send failure invalidates safely", async () => {
  const runtime = new AppServerRuntime({ codexBin: "unused", host: "127.0.0.1", port: 0, backpressureLimit: 10 });
  let sendCallback: ((error?: Error) => void) | undefined;
  const sent: unknown[] = [];
  const transport = runtime as unknown as {
    ensureConnected(): Promise<void>;
    request(method: string): Promise<unknown>;
    handleMessage(raw: string): void;
    socket: { readyState: number; send(raw: string, callback?: (error?: Error) => void): void };
  };
  transport.ensureConnected = async () => {};
  transport.request = async () => ({ turn: { id: "turn-send-failure" } });
  transport.socket = {
    readyState: 1,
    send: (raw, callback) => {
      sent.push(JSON.parse(raw));
      sendCallback = callback;
    },
  };
  transport.handleMessage(JSON.stringify({
    id: 45,
    method: "item/commandExecution/requestApproval",
    params: { threadId: "thread-send-failure", turnId: "turn-send-failure", itemId: "command-45", command: "echo fail" },
  }));
  const iterator = runtime.runTurn({ threadId: "thread-send-failure", projectRoot: ".", message: "Failure" })[Symbol.asyncIterator]();
  assert.equal((await iterator.next()).value?.method, "turn.started");
  const requested = (await iterator.next()).value!;
  assert.equal(requested.method, "approval.requested");

  let settled = false;
  const response = runtime.respondToApproval(String(requested.params.runtime_approval_id), "approve");
  void response.finally(() => { settled = true; }).catch(() => undefined);
  await Promise.resolve();
  assert.equal(settled, false);
  assert.deepEqual(sent, [{ id: 45, result: { decision: "accept" } }]);
  assert.ok(sendCallback);
  sendCallback!(new Error("deferred send failed"));
  await assert.rejects(response, /deferred send failed/);
  assert.equal(settled, true);
  const invalidated = (await iterator.next()).value!;
  assert.equal(invalidated.method, "approval.invalidated");
  assert.equal(invalidated.params.runtime_approval_id, requested.params.runtime_approval_id);
  assert.equal(invalidated.params.reason, "response_send_failed");
  await assert.rejects(
    runtime.respondToApproval(String(requested.params.runtime_approval_id), "approve"),
    /runtime_approval_not_found/,
  );
});

test("user click wins when its confirmed response precedes server resolution", async () => {
  const responses: unknown[] = [];
  const runtime = runtimeWithNotifications([{
    id: 46,
    method: "item/commandExecution/requestApproval",
    params: { threadId: "thread-retry", turnId: "turn-retry", itemId: "command-46", command: "echo win" },
  }], responses);
  const transport = runtime as unknown as { handleMessage(raw: string): void };
  const iterator = runtime.runTurn({ threadId: "thread-retry", projectRoot: ".", message: "User wins" })[Symbol.asyncIterator]();
  assert.equal((await iterator.next()).value?.method, "turn.started");
  const requested = (await iterator.next()).value!;
  assert.equal(requested.method, "approval.requested");
  await runtime.respondToApproval(String(requested.params.runtime_approval_id), "approve");
  assert.deepEqual(responses, [{ id: 46, result: { decision: "accept" } }]);
  transport.handleMessage(JSON.stringify({
    method: "serverRequest/resolved", params: { threadId: "thread-retry", requestId: 46 },
  }));
  transport.handleMessage(JSON.stringify({ method: "turn/completed", params: {
    threadId: "thread-retry", turn: { id: "turn-retry", status: "completed" },
  } }));
  assert.equal((await iterator.next()).value?.method, "turn.completed");
});

test("server request correlation distinguishes numeric and string JSON-RPC ids", async () => {
  const responses: unknown[] = [];
  const runtime = runtimeWithNotifications([
    { id: 7, method: "item/commandExecution/requestApproval", params: {
      threadId: "thread-retry", turnId: "turn-retry", itemId: "number-id", command: "echo number",
    } },
    { id: "7", method: "item/commandExecution/requestApproval", params: {
      threadId: "thread-retry", turnId: "turn-retry", itemId: "string-id", command: "echo string",
    } },
    { method: "serverRequest/resolved", params: { threadId: "thread-retry", requestId: 7 } },
  ], responses);
  const transport = runtime as unknown as { handleMessage(raw: string): void };
  const iterator = runtime.runTurn({ threadId: "thread-retry", projectRoot: ".", message: "Typed ids" })[Symbol.asyncIterator]();
  const events: HostEvent[] = [];
  for (let index = 0; index < 4; index += 1) {
    events.push((await iterator.next()).value!);
  }
  const approvals = events.filter((notification) => notification.method === "approval.requested");
  assert.equal(approvals.length, 2);
  assert.notEqual(approvals[0].params.runtime_approval_id, approvals[1].params.runtime_approval_id);
  const invalidated = events.find((notification) => notification.method === "approval.invalidated")!;
  assert.equal(invalidated.params.runtime_approval_id, approvals[0].params.runtime_approval_id);
  await runtime.respondToApproval(String(approvals[1].params.runtime_approval_id), "approve");
  assert.deepEqual(responses, [{ id: "7", result: { decision: "accept" } }]);
  transport.handleMessage(JSON.stringify({
    method: "serverRequest/resolved", params: { threadId: "thread-retry", requestId: "7" },
  }));
  transport.handleMessage(JSON.stringify({
    method: "turn/completed", params: {
      threadId: "thread-retry", turn: { id: "turn-retry", status: "completed" },
    },
  }));
  assert.equal((await iterator.next()).value?.method, "turn.completed");
  assert.equal(events.filter((notification) => notification.method === "approval.invalidated").length, 1);
});

test("unknown serverRequest/resolved is a no-op and does not invalidate another pending request", async () => {
  const responses: unknown[] = [];
  const runtime = runtimeWithNotifications([
    { id: 81, method: "item/commandExecution/requestApproval", params: {
      threadId: "thread-retry", turnId: "turn-retry", itemId: "command-81", command: "echo live",
    } },
    { method: "serverRequest/resolved", params: { threadId: "thread-retry", requestId: 999 } },
  ], responses);
  const transport = runtime as unknown as { handleMessage(raw: string): void };
  const iterator = runtime.runTurn({ threadId: "thread-retry", projectRoot: ".", message: "Unknown resolution" })[Symbol.asyncIterator]();
  assert.equal((await iterator.next()).value?.method, "turn.started");
  const requested = (await iterator.next()).value!;
  assert.equal(requested.method, "approval.requested");
  await runtime.respondToApproval(String(requested.params.runtime_approval_id), "approve");
  assert.deepEqual(responses, [{ id: 81, result: { decision: "accept" } }]);
  transport.handleMessage(JSON.stringify({ method: "turn/completed", params: {
    threadId: "thread-retry", turn: { id: "turn-retry", status: "completed" },
  } }));
  assert.equal((await iterator.next()).value?.method, "turn.completed");
});

test("terminal turn completion invalidates leftover approval before completion", async () => {
  const runtime = runtimeWithNotifications([
    { id: 51, method: "item/commandExecution/requestApproval", params: {
      threadId: "thread-retry", turnId: "turn-retry", itemId: "command-51", command: "echo pending",
    } },
    { method: "turn/completed", params: {
      threadId: "thread-retry", turn: { id: "turn-retry", status: "completed" },
    } },
  ]);
  const events: HostEvent[] = [];
  for await (const notification of runtime.runTurn({ threadId: "thread-retry", projectRoot: ".", message: "Complete" })) {
    events.push(notification);
  }
  assert.deepEqual(events.map((notification) => notification.method), [
    "turn.started", "approval.requested", "approval.invalidated", "turn.completed",
  ]);
  assert.equal(events[2].params.reason, "turn_completed");
});

test("turn interruption invalidates scoped approvals and makes late responses stale", async () => {
  const responses: unknown[] = [];
  const runtime = runtimeWithNotifications([{
    id: 61, method: "item/commandExecution/requestApproval", params: {
      threadId: "thread-retry", turnId: "turn-retry", itemId: "command-61", command: "echo pending",
    },
  }], responses);
  const transport = runtime as unknown as {
    request(method: string): Promise<unknown>;
    handleMessage(raw: string): void;
  };
  transport.request = async (method) => {
    if (method === "turn/start") return { turn: { id: "turn-retry" } };
    if (method === "turn/interrupt") return {};
    throw new Error(`unexpected request: ${method}`);
  };
  await runtime.interruptTurn("thread-retry", "turn-retry");
  transport.handleMessage(JSON.stringify({ method: "turn/completed", params: {
    threadId: "thread-retry", turn: { id: "turn-retry", status: "interrupted" },
  } }));
  const events: HostEvent[] = [];
  for await (const notification of runtime.runTurn({ threadId: "thread-retry", projectRoot: ".", message: "Interrupt" })) {
    events.push(notification);
  }
  const requested = events.find((notification) => notification.method === "approval.requested")!;
  assert.equal(events.find((notification) => notification.method === "approval.invalidated")?.params.reason, "turn_interrupted");
  await assert.rejects(runtime.respondToApproval(String(requested.params.runtime_approval_id), "approve"), /runtime_approval_not_found/);
  assert.deepEqual(responses, []);
});

test("file approvals use their own started-item changes, never another item or whole-turn diff", async () => {
  const changes = [{ path: "scripts/player.gd", kind: "update", diff: "@@\n-old\n+new" }];
  const events = await collectApprovalEvents([
    { method: "item/started", params: {
      threadId: "thread-retry", turnId: "turn-retry", item: { id: "file-1", type: "fileChange", changes },
    } },
    { method: "turn/diff/updated", params: {
      threadId: "thread-retry", turnId: "turn-retry", diff: "diff --git a/unrelated.gd b/unrelated.gd\n@@\n+unrelated",
    } },
    ...["file-1", "file-2"].map((itemId, index) => ({
      id: 10 + index, method: "item/fileChange/requestApproval",
      params: { threadId: "thread-retry", turnId: "turn-retry", itemId },
    })),
  ]);
  const approvals = events.filter((notification) => notification.method === "approval.requested");
  assert.deepEqual(approvals[0].params.diff_evidence, changes);
  assert.deepEqual(approvals[0].params.file_changes, { "scripts/player.gd": { type: "update", unified_diff: changes[0].diff } });
  const preview = events[events.indexOf(approvals[0]) - 1];
  assert.equal(preview.method, "turn.event");
  assert.equal(preview.params.event, "diff_updated");
  assert.match(String(preview.params.diff_text), /scripts\/player\.gd/);
  assert.doesNotMatch(String(preview.params.diff_text), /unrelated/);
  assert.equal(approvals[1].params.diff_evidence, null);
  assert.equal(approvals[1].params.file_changes, null);
});

test("empty or incomplete item updates invalidate previous file approval evidence", async () => {
  for (const changes of [[], [{ path: "scripts/player.gd" }]]) {
    const events = await collectApprovalEvents([
      { method: "item/fileChange/patchUpdated", params: {
        threadId: "thread-retry", turnId: "turn-retry", itemId: "file-1",
        changes: [{ path: "scripts/player.gd", kind: "update", diff: "@@\n-old\n+new" }],
      } },
      { method: "item/started", params: {
        threadId: "thread-retry", turnId: "turn-retry", item: { id: "file-1", type: "fileChange", changes },
      } },
      { id: 12, method: "item/fileChange/requestApproval", params: {
        threadId: "thread-retry", turnId: "turn-retry", itemId: "file-1",
      } },
    ]);
    assert.equal(events.find((notification) => notification.method === "approval.requested")?.params.diff_evidence, null);
  }
});

test("app-server retry warnings preserve the active turn through resumed output and completion", async () => {
  const runtime = runtimeWithNotifications([
    { method: "error", params: {
      threadId: "other-thread", turnId: "turn-retry", willRetry: false,
      error: { message: "Unrelated failure" },
    } },
    { method: "error", params: {
      threadId: "thread-retry", turnId: "turn-retry", willRetry: true,
      error: { message: "Stream interrupted; reconnecting" },
    } },
    { method: "item/agentMessage/delta", params: {
      threadId: "thread-retry", turnId: "turn-retry", itemId: "item-retry", delta: "Recovered output",
    } },
    { method: "turn/completed", params: {
      threadId: "thread-retry", turn: { id: "turn-retry", status: "completed" },
    } },
  ]);
  const events: HostEvent[] = [];
  for await (const notification of runtime.runTurn({ threadId: "thread-retry", projectRoot: ".", message: "Test retry" })) {
    events.push(notification);
  }
  assert.deepEqual(events.map((notification) => notification.method), [
    "turn.started", "runtime.warning", "turn.event", "turn.completed",
  ]);
  assert.equal(events[1].params.recoverable, true);
  assert.equal(events[1].params.message, "Stream interrupted; reconnecting");
  assert.equal(events[2].params.text, "Recovered output");
  assert.equal(events[3].params.status, "completed");
});

test("app-server nonretryable errors still terminate the active turn", async () => {
  const runtime = runtimeWithNotifications([
    { method: "error", params: {
      threadId: "thread-retry", turnId: "turn-retry", willRetry: false,
      error: { message: "Authentication failed" },
    } },
    { method: "item/agentMessage/delta", params: {
      threadId: "thread-retry", turnId: "turn-retry", itemId: "item-retry", delta: "Must not appear",
    } },
  ]);
  const events: HostEvent[] = [];
  for await (const notification of runtime.runTurn({ threadId: "thread-retry", projectRoot: ".", message: "Test failure" })) {
    events.push(notification);
  }
  assert.deepEqual(events.map((notification) => notification.method), ["turn.started", "error"]);
  assert.equal(events[1].params.recoverable, false);
  assert.equal(events[1].params.message, "Authentication failed");
});

test("Codex shutdown stops the whole Windows process tree and falls back to kill", () => {
  const calls: Array<{ file: string; args: string[] }> = [];
  let killed = 0;
  const proc = { pid: 4242, kill: () => { killed += 1; return true; } };
  terminateProcessTree(proc, "win32", (file, args) => { calls.push({ file, args }); return { status: 0 }; });
  assert.equal(killed, 0);
  assert.match(calls[0]!.file, /System32[\\/]taskkill\.exe$/i);
  assert.deepEqual(calls[0]!.args, ["/PID", "4242", "/T", "/F"]);

  terminateProcessTree(proc, "win32", () => ({ status: 128 }));
  assert.equal(killed, 1);
  terminateProcessTree(proc, "linux", () => { throw new Error("taskkill must not run off Windows"); });
  assert.equal(killed, 2);
});

test("app-server command approval maps Godot approve to one-shot accept", () => {
  const params = { threadId: "thread", turnId: "turn", itemId: "item", command: "echo test" };
  assert.deepEqual(
    responseForApproval("item/commandExecution/requestApproval", "approve", params),
    { decision: "accept" }
  );
  // An offered exec-policy amendment is never accepted along with the command.
  for (const decision of ["approve", "approve_session"] as const) {
    assert.deepEqual(
      responseForApproval("item/commandExecution/requestApproval", decision, { ...params, proposedExecpolicyAmendment: ["echo", "test"] }),
      { decision: decision === "approve" ? "accept" : "acceptForSession" }
    );
  }
  assert.deepEqual(
    responseForApproval("item/commandExecution/requestApproval", "reject"),
    { decision: "decline" }
  );
  assert.deepEqual(
    responseForApproval("item/commandExecution/requestApproval", "expired"),
    { decision: "cancel" }
  );
});

test("app-server approval maps command approve_session and rejects broader session scopes", () => {
  const commandParams = { threadId: "thread", turnId: "turn", itemId: "item", command: "echo test" };
  const legacyParams = { conversationId: "thread", callId: "call", command: ["echo", "test"] };
  assert.deepEqual(
    responseForApproval("item/commandExecution/requestApproval", "approve_session", commandParams),
    { decision: "acceptForSession" }
  );
  assert.throws(
    () => responseForApproval("item/fileChange/requestApproval", "approve_session", { threadId: "thread", turnId: "turn", itemId: "item" }),
    /approval_session_scope_not_allowed/
  );
  assert.deepEqual(
    responseForApproval("execCommandApproval", "approve_session", legacyParams),
    { decision: "approved_for_session" }
  );
  assert.throws(
    () => responseForApproval("applyPatchApproval", "approve_session", { conversationId: "thread", callId: "call" }),
    /approval_session_scope_not_allowed/
  );
});

test("app-server rejects session approval for elicitation", () => {
  assert.throws(
    () => responseForApproval("mcpServer/elicitation/request", "approve_session", {}, ""),
    /approval_session_scope_not_allowed/
  );
});

test("legacy exec command approval maps Godot approve to approved", () => {
  const params = { conversationId: "thread", callId: "call", command: ["echo", "test"] };
  assert.deepEqual(
    responseForApproval("execCommandApproval", "approve", params),
    { decision: "approved" }
  );
  assert.deepEqual(
    responseForApproval("execCommandApproval", "reject"),
    { decision: "denied" }
  );
  assert.deepEqual(
    responseForApproval("execCommandApproval", "expired"),
    { decision: "timed_out" }
  );
});

test("app-server params honor full-machine trust session policy", () => {
  assert.deepEqual(
    appServerThreadStartParams({
      projectRoot: "C:\\Project",
      approvalPolicy: "never",
      sandbox: "danger-full-access",
    }),
    {
      cwd: "C:\\Project",
      approvalPolicy: "never",
      approvalsReviewer: "user",
      sandbox: "danger-full-access",
      threadSource: "user",
      sessionStartSource: "startup",
    },
  );

  const turn = appServerTurnStartParams({
    threadId: "thread-1",
    projectRoot: "C:\\Project",
    message: "Build the scene",
    approvalPolicy: "never",
    sandbox: "danger-full-access",
  });
  assert.equal(turn.approvalPolicy, "never");
  assert.deepEqual(turn.sandboxPolicy, { type: "dangerFullAccess" });
});

test("app-server turn params attach annotation as local image input", () => {
  const turn = appServerTurnStartParams({
    threadId: "thread-annotation",
    projectRoot: "C:\\Project",
    message: "Use marker A",
    attachments: { latest_annotation: true },
    annotation: {
      annotationId: "annotation_test_001",
      manifestPath: "C:\\Project\\.godot\\godot_codex_bridge\\artifacts\\annotations\\annotation_test_001\\annotation.json",
      rawImagePath: "C:\\Project\\.godot\\godot_codex_bridge\\artifacts\\annotations\\annotation_test_001\\raw.png",
      annotatedImagePath: "C:\\Project\\.godot\\godot_codex_bridge\\artifacts\\annotations\\annotation_test_001\\annotated.png",
      imageAttached: true,
      detail: "high",
      summaryText: "[Godot AI Marker attachment]\nAttached marks are user reference annotations.\n[/Godot AI Marker attachment]",
      manifest: {},
    },
  }) as { input: Array<Record<string, unknown>> };

  assert.equal(turn.input.length, 2);
  assert.equal(turn.input[0].type, "text");
  assert.match(String(turn.input[0].text), /latest_annotation/);
  assert.deepEqual(turn.input[1], {
    type: "localImage",
    path: "C:\\Project\\.godot\\godot_codex_bridge\\artifacts\\annotations\\annotation_test_001\\annotated.png",
    detail: "high",
  });
});

test("app-server annotation turn params do not embed PNG bytes in JSON", () => {
  const turn = appServerTurnStartParams({
    threadId: "thread-annotation",
    projectRoot: "C:\\Project",
    message: "Use marker A",
    annotation: {
      annotationId: "annotation_test_001",
      manifestPath: "C:\\Project\\.godot\\godot_codex_bridge\\artifacts\\annotations\\annotation_test_001\\annotation.json",
      rawImagePath: "C:\\Project\\.godot\\godot_codex_bridge\\artifacts\\annotations\\annotation_test_001\\raw.png",
      annotatedImagePath: "C:\\Project\\.godot\\godot_codex_bridge\\artifacts\\annotations\\annotation_test_001\\annotated.png",
      imageAttached: true,
      detail: "high",
      summaryText: "[Godot AI Marker attachment]\nAttached marks are user reference annotations.\n[/Godot AI Marker attachment]",
      manifest: {},
    },
  });

  const serialized = JSON.stringify(turn);
  assert.match(serialized, /"type":"localImage"/);
  assert.match(serialized, /annotated\.png/);
  assert.doesNotMatch(serialized, /data:image\/png/i);
  assert.doesNotMatch(serialized, /iVBOR/);
  assert.doesNotMatch(serialized, /rawImageBytes|annotatedImageBytes|bytesBase64|image_bytes/i);
});

test("app-server permission approval never grants requested permissions", () => {
  const rawParams = {
    permissions: {
      fileSystem: { writableRoots: ["C:\\Project"] },
      network: null,
    },
  };
  assert.throws(
    () => responseForApproval("item/permissions/requestApproval", "approve", rawParams),
    /unsupported_approval_scope/,
  );
  assert.throws(
    () => responseForApproval("item/permissions/requestApproval", "approve_session", rawParams),
    /unsupported_approval_scope/,
  );
  assert.deepEqual(
    responseForApproval("item/permissions/requestApproval", "reject", rawParams),
    { permissions: {}, scope: "turn", strictAutoReview: true },
  );
});

test("app-server normalizes file change patch updates for Godot chat diff cards", () => {
  const changes = [
    { path: "res://scripts/player.gd", kind: "update", diff: "@@\n-old\n+new\n" },
    { path: "scenes\\Main.tscn", kind: "add", diff: "@@\n+[node name=\"Main\" type=\"Node3D\"]\n" },
  ];

  const diffText = diffTextFromFileUpdateChanges(changes);
  assert.match(diffText, /diff --git a\/res:\/\/scripts\/player\.gd b\/res:\/\/scripts\/player\.gd/);
  assert.match(diffText, /\n-old\n\+new/);
  assert.match(diffText, /diff --git a\/scenes\/Main\.tscn b\/scenes\/Main\.tscn/);

  const fileChanges = fileChangesFromFileUpdateChanges(changes);
  assert.deepEqual(fileChanges["res://scripts/player.gd"], {
    type: "update",
    unified_diff: "@@\n-old\n+new",
  });
  assert.deepEqual(fileChanges["scenes/Main.tscn"], {
    type: "add",
    unified_diff: "@@\n+[node name=\"Main\" type=\"Node3D\"]",
  });
});

test("Codex launch binds the godot_codex_bridge MCP server to the attached project", () => {
  const args = bridgeMcpOverrideArgs(
    { projectRoot: "C:\\Games\\Cult \"A\"", bridgeDir: "C:\\Games\\Cult \"A\"\\.godot\\godot_codex_bridge" },
    "C:\\Bridge\\mcp_server\\dist\\src\\index.js",
    "C:\\Program Files\\nodejs\\node.exe",
    () => true,
  );
  assert.equal(args[0], "-c");
  assert.equal(
    args[1],
    'mcp_servers.godot_codex_bridge={command="C:\\\\Program Files\\\\nodejs\\\\node.exe",args=["C:\\\\Bridge\\\\mcp_server\\\\dist\\\\src\\\\index.js"],env={GODOT_CODEX_BRIDGE_PROJECT_ROOT="C:\\\\Games\\\\Cult \\"A\\"",GODOT_CODEX_BRIDGE_DIR="C:\\\\Games\\\\Cult \\"A\\"\\\\.godot\\\\godot_codex_bridge"}}',
  );
  assert.deepEqual(bridgeMcpOverrideArgs(null), []);
  assert.deepEqual(bridgeMcpOverrideArgs({ projectRoot: "C:\\p", bridgeDir: "C:\\p\\b" }, "C:\\missing.js", "node.exe", () => false), []);
});
