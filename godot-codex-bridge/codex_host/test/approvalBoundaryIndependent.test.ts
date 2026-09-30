import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import WebSocket from "ws";
import { AppServerRuntime, responseForApproval } from "../src/appServerRuntime.js";
import type { CodexRuntimeAdapter, RuntimeThreadHandle, RuntimeThreadOptions, RuntimeTurnInput } from "../src/codexRuntime.js";
import { event } from "../src/codexRuntime.js";
import { loadConfig } from "../src/config.js";
import { GodotSocketServer } from "../src/godotSocketServer.js";
import { HostController } from "../src/hostController.js";
import type { HostEvent } from "../src/types.js";

const threadId = "thread-qa-approval";
const turnId = "turn-qa-approval";

test("0.156.1 current and legacy unsupported scopes auto-decline without an approval card", async () => {
  const command = {
    threadId, turnId, itemId: "command-qa", startedAtMs: Date.now(), kind: "command",
    environmentId: null, command: "echo test", cwd: ".",
  };
  const legacy = {
    conversationId: threadId, callId: "legacy-qa", approvalId: null,
    command: ["echo", "test"], cwd: ".", reason: null, parsedCmd: [],
  };
  const cases: Array<{ method: string; params: Record<string, unknown>; result: unknown }> = [
    { method: "item/permissions/requestApproval", params: {
      threadId, turnId, itemId: "permissions-qa", startedAtMs: Date.now(),
      environmentId: null, cwd: ".", reason: null,
      permissions: { network: { enabled: true }, fileSystem: null },
    }, result: { permissions: {}, scope: "turn", strictAutoReview: true } },
    { method: "item/commandExecution/requestApproval", params: { ...command, kind: "writeStdin" }, result: { decision: "decline" } },
    { method: "item/commandExecution/requestApproval", params: { ...command, environmentId: "remote-env" }, result: { decision: "decline" } },
    { method: "item/commandExecution/requestApproval", params: { ...command, networkApprovalContext: { host: "example.com", protocol: "https" } }, result: { decision: "decline" } },
    { method: "item/commandExecution/requestApproval", params: { ...command, proposedNetworkPolicyAmendments: [{ host: "example.com", action: "allow" }] }, result: { decision: "decline" } },
    { method: "item/commandExecution/requestApproval", params: { ...command, command: null }, result: { decision: "decline" } },
    { method: "execCommandApproval", params: { ...legacy, networkApprovalContext: { host: "example.com", protocol: "https" } }, result: { decision: "denied" } },
    { method: "execCommandApproval", params: { ...legacy, permissions: { network: { enabled: true } } }, result: { decision: "denied" } },
    { method: "execCommandApproval", params: { ...legacy, command: [] }, result: { decision: "denied" } },
    { method: "item/fileChange/requestApproval", params: { threadId, turnId, itemId: "file-qa", startedAtMs: Date.now(), grantRoot: "/outside" }, result: { decision: "decline" } },
    { method: "item/fileChange/requestApproval", params: { threadId, turnId, itemId: "file-qa", startedAtMs: Date.now(), futurePrivilege: true }, result: { decision: "decline" } },
    { method: "applyPatchApproval", params: { conversationId: threadId, callId: "patch-qa", reason: null, fileChanges: {}, grantRoot: "/outside" }, result: { decision: "denied" } },
  ];
  for (const [index, entry] of cases.entries()) {
    const { events, responses } = await collectWire([{ id: index + 1, method: entry.method, params: entry.params }]);
    assert.deepEqual(responses, [{ id: index + 1, result: entry.result }], `${entry.method} case ${index} did not fail closed`);
    assert.equal(events.some((item) => item.method === "approval.requested"), false, `${entry.method} case ${index} produced a card`);
    assert.equal(events.some((item) => item.method === "runtime.warning"), true, `${entry.method} case ${index} omitted a warning`);
    assert.throws(
      () => responseForApproval(entry.method, "approve", entry.params),
      /unsupported_approval_scope/,
      `${entry.method} case ${index} could be approved after intake`,
    );
  }
  const malformed = await collectWire([{ id: 89, method: "item/commandExecution/requestApproval", params: null }]);
  assert.deepEqual(malformed.responses, [{ id: 89, result: { decision: "decline" } }]);
  assert.equal(malformed.events.some((item) => item.method === "approval.requested"), false);
  assert.throws(() => responseForApproval("item/commandExecution/requestApproval", "approve"), /unsupported_approval_scope/);
  assert.throws(
    () => responseForApproval("item/commandExecution/requestApproval", "approve_session", {
      ...command, proposedNetworkPolicyAmendments: [{ host: "example.com", action: "allow" }],
    }),
    /unsupported_approval_scope/,
  );

  const validLegacy = await collectWire([{ id: 90, method: "execCommandApproval", params: legacy }]);
  assert.deepEqual(validLegacy.responses, []);
  const legacyCard = validLegacy.events.find((item) => item.method === "approval.requested");
  assert.equal(legacyCard?.params.thread_id, threadId);
  assert.equal(legacyCard?.params.raw_method, "execCommandApproval");
});

test("wrong-turn approval and unpaired socket cannot approve; exact approval resolves once", async () => {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-qa-approval-"));
  await fs.writeFile(path.join(projectRoot, "project.godot"), "[application]\n", "utf8");
  const wrongRuntime = new SyntheticApprovalRuntime("turn-other");
  const wrong = new HostController(loadConfig(["--runtime", "mock"]), wrongRuntime);
  const wrongEvents: HostEvent[] = [];
  wrong.on("event", (item) => wrongEvents.push(item));
  await wrong.handleRequest({ method: "project.attach", params: { project_root: projectRoot } });
  await wrong.handleRequest({ method: "thread.send", params: { message: "wrong-turn synthetic" } });
  await waitFor(() => wrongRuntime.decisions.length > 0);
  assert.equal(wrongEvents.some((item) => item.method === "approval.requested"), false);
  assert.deepEqual(wrongRuntime.decisions, ["reject"]);
  await assert.rejects(wrong.handleRequest({ method: "approval.respond", params: {
    approval_id: "approval-forged", nonce: "forged", decision: "approve",
  } }), /unknown_approval|not_pending|stale/i);
  assert.deepEqual(wrongRuntime.decisions, ["reject"]);

  const foreignThreadRuntime = new SyntheticApprovalRuntime(turnId, "thread-foreign");
  const foreignThread = new HostController(loadConfig(["--runtime", "mock"]), foreignThreadRuntime);
  const foreignEvents: HostEvent[] = [];
  foreignThread.on("event", (item) => foreignEvents.push(item));
  await foreignThread.handleRequest({ method: "project.attach", params: { project_root: projectRoot } });
  await foreignThread.handleRequest({ method: "thread.send", params: { message: "wrong-thread synthetic" } });
  await waitFor(() => foreignThreadRuntime.decisions.length > 0);
  assert.equal(foreignEvents.some((item) => item.method === "approval.requested"), false);
  assert.deepEqual(foreignThreadRuntime.decisions, ["reject"]);

  const staleRuntime = new SyntheticApprovalRuntime(turnId, threadId, true);
  const stale = new HostController(loadConfig(["--runtime", "mock"]), staleRuntime);
  const staleEvents: HostEvent[] = [];
  stale.on("event", (item) => staleEvents.push(item));
  await stale.handleRequest({ method: "project.attach", params: { project_root: projectRoot } });
  await stale.handleRequest({ method: "thread.send", params: { message: "stale synthetic" } });
  await waitFor(() => staleEvents.some((item) => item.method === "approval.resolved"));
  const staleApproval = staleEvents.find((item) => item.method === "approval.requested")!;
  await assert.rejects(stale.handleRequest({ method: "approval.respond", params: {
    approval_id: staleApproval.params.approval_id, nonce: staleApproval.params.nonce, decision: "approve",
  } }), /approval_not_pending|stale/i);
  assert.deepEqual(staleRuntime.decisions, []);

  const legacyRuntime = new SyntheticApprovalRuntime(undefined, threadId, false, true);
  const legacyController = new HostController(loadConfig(["--runtime", "mock"]), legacyRuntime);
  const legacyEvents: HostEvent[] = [];
  legacyController.on("event", (item) => legacyEvents.push(item));
  await legacyController.handleRequest({ method: "project.attach", params: { project_root: projectRoot } });
  await legacyController.handleRequest({ method: "thread.send", params: { message: "legacy synthetic" } });
  await waitFor(() => legacyEvents.some((item) => item.method === "approval.requested"));
  const legacyApproval = legacyEvents.find((item) => item.method === "approval.requested")!;
  assert.equal(legacyApproval.params.turn_id, turnId);
  await legacyController.handleRequest({ method: "approval.respond", params: {
    approval_id: legacyApproval.params.approval_id, nonce: legacyApproval.params.nonce, decision: "approve",
  } });
  assert.deepEqual(legacyRuntime.decisions, ["approve"]);

  const runtime = new SyntheticApprovalRuntime(turnId);
  const controller = new HostController(loadConfig(["--runtime", "mock"]), runtime);
  const events: HostEvent[] = [];
  controller.on("event", (item) => events.push(item));
  await controller.handleRequest({ method: "project.attach", params: { project_root: projectRoot } });
  await controller.handleRequest({ method: "thread.send", params: { message: "exact synthetic" } });
  await waitFor(() => events.some((item) => item.method === "approval.requested"));
  const approval = events.find((item) => item.method === "approval.requested")!;

  const server = new GodotSocketServer("127.0.0.1", 0, controller);
  await server.start();
  const socket = new WebSocket(`ws://127.0.0.1:${server.addressPort()}`);
  try {
    await new Promise<void>((resolve, reject) => { socket.once("open", resolve); socket.once("error", reject); });
    const denied = new Promise<any>((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error("unpaired response timeout")), 2_000);
      socket.on("message", (raw) => {
        const message = JSON.parse(String(raw));
        if (message.id === 91) { clearTimeout(timeout); resolve(message); }
      });
    });
    socket.send(JSON.stringify({ jsonrpc: "2.0", id: 91, method: "approval.respond", params: {
      approval_id: approval.params.approval_id, nonce: approval.params.nonce, decision: "approve",
    } }));
    assert.equal((await denied).error.message, "pairing_required");
    assert.deepEqual(runtime.decisions, []);
    await controller.handleRequest({ method: "approval.respond", params: {
      approval_id: approval.params.approval_id, nonce: approval.params.nonce, decision: "approve",
    } });
    assert.deepEqual(runtime.decisions, ["approve"]);
    await assert.rejects(controller.handleRequest({ method: "approval.respond", params: {
      approval_id: approval.params.approval_id, nonce: approval.params.nonce, decision: "approve",
    } }), /approval_not_pending/);
    assert.deepEqual(runtime.decisions, ["approve"]);
  } finally {
    socket.terminate();
    await server.stop();
  }
});

class SyntheticApprovalRuntime implements CodexRuntimeAdapter {
  readonly kind = "qa-approval";
  readonly decisions: string[] = [];
  constructor(
    private readonly approvalTurnId: string | undefined,
    private readonly approvalThreadId = threadId,
    private readonly invalidate = false,
    private readonly legacy = false,
  ) {}
  async startThread(options: RuntimeThreadOptions): Promise<RuntimeThreadHandle> {
    return { threadId, cwd: options.projectRoot, instructionSources: [] };
  }
  async *runTurn(input: RuntimeTurnInput): AsyncIterable<HostEvent> {
    yield event("turn.started", { thread_id: input.threadId, turn_id: turnId });
    yield event("approval.requested", {
      runtime_approval_id: `runtime-${this.approvalTurnId}`, kind: "command_execution",
      thread_id: this.approvalThreadId, turn_id: this.approvalTurnId,
      item_id: "command-qa", command: "echo test",
      raw_method: this.legacy ? "execCommandApproval" : "item/commandExecution/requestApproval",
      raw_params: this.legacy ? {
        conversationId: this.approvalThreadId, callId: "legacy-qa", approvalId: null,
        command: ["echo", "test"], cwd: ".", reason: null, parsedCmd: [],
      } : {},
    });
    if (this.invalidate) {
      yield event("approval.invalidated", {
        runtime_approval_id: `runtime-${this.approvalTurnId}`,
        thread_id: input.threadId, turn_id: this.approvalTurnId,
        reason: "server_resolved", request_id: 72,
      });
    }
  }
  async interruptTurn(): Promise<void> {}
  async respondToApproval(_approvalId: string, decision: "approve" | "approve_session" | "reject" | "revise" | "expired"): Promise<void> {
    this.decisions.push(decision);
  }
  async shutdown(): Promise<void> {}
}

async function collectWire(requests: unknown[]): Promise<{ events: HostEvent[]; responses: any[] }> {
  const responses: any[] = [];
  const runtime = new AppServerRuntime({ codexBin: "unused", host: "127.0.0.1", port: 0, backpressureLimit: 500 });
  const transport = runtime as unknown as {
    ensureConnected(): Promise<void>;
    request(method: string): Promise<unknown>;
    handleMessage(raw: string): void;
    socket: { readyState: number; send(raw: string, callback?: (error?: Error) => void): void };
  };
  transport.socket = { readyState: 1, send: (raw, callback) => { responses.push(JSON.parse(raw)); callback?.(); } };
  transport.ensureConnected = async () => {};
  transport.request = async () => ({ turn: { id: turnId } });
  for (const request of requests) transport.handleMessage(JSON.stringify(request));
  transport.handleMessage(JSON.stringify({ method: "turn/completed", params: { threadId, turn: { id: turnId, status: "completed" } } }));
  const events: HostEvent[] = [];
  for await (const item of runtime.runTurn({ threadId, projectRoot: ".", message: "scope check" })) events.push(item);
  return { events, responses };
}

async function waitFor(predicate: () => boolean): Promise<void> {
  const deadline = Date.now() + 2_000;
  while (Date.now() < deadline) {
    if (predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  throw new Error("approval event timeout");
}
