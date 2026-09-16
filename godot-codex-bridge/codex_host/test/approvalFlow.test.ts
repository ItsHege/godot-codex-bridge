import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import type { CodexRuntimeAdapter, RuntimeThreadHandle, RuntimeThreadOptions, RuntimeTurnInput } from "../src/codexRuntime.js";
import { event } from "../src/codexRuntime.js";
import { loadConfig } from "../src/config.js";
import { HostController } from "../src/hostController.js";
import type { HostEvent } from "../src/types.js";

class ApprovalRuntime implements CodexRuntimeAdapter {
  readonly kind = "approval-test";
  decisions: Array<{ approvalId: string; decision: string }> = [];

  async startThread(options: RuntimeThreadOptions): Promise<RuntimeThreadHandle> {
    return { threadId: "thread-approval", cwd: options.projectRoot, instructionSources: [] };
  }

  async *runTurn(input: RuntimeTurnInput): AsyncIterable<HostEvent> {
    yield event("turn.started", { thread_id: input.threadId, turn_id: "turn-approval" });
    yield event("approval.requested", {
      runtime_approval_id: "runtime-file-change-1",
      kind: "file_change",
      thread_id: input.threadId,
      turn_id: "turn-approval",
      item_id: "item-1",
      reason: "test file change",
      file_changes: { "res://test.gd": { type: "update", unified_diff: "@@\n-a\n+b\n" } },
      raw_method: "item/fileChange/requestApproval",
      raw_params: {}
    });
  }

  async interruptTurn(): Promise<void> {}

  async respondToApproval(approvalId: string, decision: "approve" | "approve_session" | "reject" | "revise" | "expired"): Promise<void> {
    this.decisions.push({ approvalId, decision });
  }

  async shutdown(): Promise<void> {}
}

class CommandApprovalRuntime implements CodexRuntimeAdapter {
  readonly kind = "command-approval-test";
  decisions: Array<{ approvalId: string; decision: string }> = [];

  async startThread(options: RuntimeThreadOptions): Promise<RuntimeThreadHandle> {
    return { threadId: "thread-command", cwd: options.projectRoot, instructionSources: [] };
  }

  async *runTurn(input: RuntimeTurnInput): AsyncIterable<HostEvent> {
    yield event("turn.started", { thread_id: input.threadId, turn_id: "turn-command" });
    yield event("approval.requested", {
      runtime_approval_id: "runtime-command-1",
      kind: "command_execution",
      thread_id: input.threadId,
      turn_id: "turn-command",
      item_id: "item-command",
      reason: "test command",
      command: "New-Item -ItemType Directory scenes/debug",
      cwd: input.projectRoot,
      raw_method: "item/commandExecution/requestApproval",
      raw_params: {}
    });
  }

  async interruptTurn(): Promise<void> {}

  async respondToApproval(approvalId: string, decision: "approve" | "approve_session" | "reject" | "revise" | "expired"): Promise<void> {
    this.decisions.push({ approvalId, decision });
  }

  async shutdown(): Promise<void> {}
}

test("HostController wraps runtime approval with host nonce and resolves response", async () => {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-approval-flow-"));
  await fs.writeFile(path.join(projectRoot, "project.godot"), "[application]\n", "utf8");
  const runtime = new ApprovalRuntime();
  const controller = new HostController(loadConfig(["--runtime", "mock"]), runtime);
  const events: HostEvent[] = [];
  controller.on("event", (hostEvent) => events.push(hostEvent));

  await controller.handleRequest({ method: "project.attach", params: { project_root: projectRoot } });
  await controller.handleRequest({ method: "thread.send", params: { message: "make a change" } });
  await waitFor(() => events.some((hostEvent) => hostEvent.method === "approval.requested"));

  const approvalEvent = events.find((hostEvent) => hostEvent.method === "approval.requested")!;
  assert.match(String(approvalEvent.params.approval_id), /^approval-/);
  assert.match(String(approvalEvent.params.nonce), /^[a-f0-9]{32}$/);
  assert.match(String(approvalEvent.params.diff_hash), /^[a-f0-9]{64}$/);
  assert.equal(approvalEvent.params.runtime_approval_id, "runtime-file-change-1");
  assert.equal(approvalEvent.params.approvable_by_chat, true);
  assert.equal(approvalEvent.params.blocked_reason, null);
  assert.deepEqual(approvalEvent.params.required_evidence, ["nonce", "diff_hash", "displayed_diff_matches_hash"]);
  assert.equal(approvalEvent.params.approval_policy_label, "Manual diff approval");
  assert.equal(controller.status().state, "waiting_for_approval");

  await controller.handleRequest({
    method: "approval.respond",
    params: {
      approval_id: approvalEvent.params.approval_id,
      nonce: approvalEvent.params.nonce,
      diff_hash: approvalEvent.params.diff_hash,
      decision: "approve"
    }
  });
  assert.deepEqual(runtime.decisions, [{ approvalId: "runtime-file-change-1", decision: "approve" }]);
  assert.equal(controller.status().pendingApprovals, 0);
  const resolvedEvent = events.find((hostEvent) => hostEvent.method === "approval.resolved")!;
  const manifestPath = String(resolvedEvent.params.undo_snapshot_path);
  assert.ok(manifestPath.endsWith(path.join("undo_snapshots", String(approvalEvent.params.approval_id), "manifest.json")));
  const manifest = JSON.parse(await fs.readFile(manifestPath, "utf8")) as { requested_path_count: number; files: Array<{ requested_path: string; existed: boolean; copied: boolean }> };
  assert.equal(manifest.requested_path_count, 1);
  assert.deepEqual(manifest.files[0], {
    requested_path: "res://test.gd",
    absolute_path: path.join(projectRoot, "test.gd"),
    existed: false,
    copied: false
  });
});

test("HostController allows manual command approval from chat", async () => {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-command-approval-flow-"));
  await fs.writeFile(path.join(projectRoot, "project.godot"), "[application]\n", "utf8");
  const runtime = new CommandApprovalRuntime();
  const controller = new HostController(loadConfig(["--runtime", "mock"]), runtime);
  const events: HostEvent[] = [];
  controller.on("event", (hostEvent) => events.push(hostEvent));

  await controller.handleRequest({ method: "project.attach", params: { project_root: projectRoot } });
  await controller.handleRequest({ method: "thread.send", params: { message: "create a debug scene" } });
  await waitFor(() => events.some((hostEvent) => hostEvent.method === "approval.requested"));

  const approvalEvent = events.find((hostEvent) => hostEvent.method === "approval.requested")!;
  assert.equal(approvalEvent.params.kind, "command_execution");
  assert.equal(approvalEvent.params.approvable_by_chat, true);
  assert.equal(approvalEvent.params.blocked_reason, null);
  assert.deepEqual(approvalEvent.params.required_evidence, ["nonce", "displayed_command_reviewed"]);
  assert.equal(approvalEvent.params.approval_policy_label, "Manual command approval");
  assert.equal(approvalEvent.params.diff_hash, undefined);

  await controller.handleRequest({
    method: "approval.respond",
    params: {
      approval_id: approvalEvent.params.approval_id,
      nonce: approvalEvent.params.nonce,
      decision: "approve"
    }
  });
  assert.deepEqual(runtime.decisions, [{ approvalId: "runtime-command-1", decision: "approve" }]);
  const resolvedEvent = events.find((hostEvent) => hostEvent.method === "approval.resolved")!;
  assert.equal(resolvedEvent.params.undo_snapshot_path, undefined);
});

test("HostController forwards session command approval", async () => {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-command-session-approval-flow-"));
  await fs.writeFile(path.join(projectRoot, "project.godot"), "[application]\n", "utf8");
  const runtime = new CommandApprovalRuntime();
  const controller = new HostController(loadConfig(["--runtime", "mock"]), runtime);
  const events: HostEvent[] = [];
  controller.on("event", (hostEvent) => events.push(hostEvent));

  await controller.handleRequest({ method: "project.attach", params: { project_root: projectRoot } });
  await controller.handleRequest({ method: "thread.send", params: { message: "create many scene files" } });
  await waitFor(() => events.some((hostEvent) => hostEvent.method === "approval.requested"));

  const approvalEvent = events.find((hostEvent) => hostEvent.method === "approval.requested")!;
  await controller.handleRequest({
    method: "approval.respond",
    params: {
      approval_id: approvalEvent.params.approval_id,
      nonce: approvalEvent.params.nonce,
      decision: "approve_session"
    }
  });

  assert.deepEqual(runtime.decisions, [{ approvalId: "runtime-command-1", decision: "approve_session" }]);
  const resolvedEvent = events.find((hostEvent) => hostEvent.method === "approval.resolved")!;
  assert.equal(resolvedEvent.params.status, "approved_session");
});

async function waitFor(predicate: () => boolean): Promise<void> {
  const deadline = Date.now() + 1000;
  while (Date.now() < deadline) {
    if (predicate()) {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  throw new Error("timeout waiting for condition");
}
