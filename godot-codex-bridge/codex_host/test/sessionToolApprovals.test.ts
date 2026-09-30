import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import type { ChildProcess } from "node:child_process";
import { AppServerRuntime } from "../src/appServerRuntime.js";
import { loadConfig } from "../src/config.js";
import { HostController } from "../src/hostController.js";
import { SESSION_ALLOWABLE_TOOLS, sessionAllowableTool } from "../src/sessionToolApprovals.js";
import type { HostEvent } from "../src/types.js";

const threadId = "thread-session-allow";

function toolElicitation(tool: string, overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    threadId, turnId: "turn-1", serverName: "godot_codex_bridge", mode: "form",
    _meta: { codex_approval_kind: "mcp_tool_call", persist: ["session", "always"], tool_title: tool },
    message: `Allow the godot_codex_bridge MCP server to run tool "${tool}"?`,
    requestedSchema: { type: "object", properties: {} },
    ...overrides,
  };
}

test("only plain approvals of allowlisted read-only Bridge tools are session-allowable", () => {
  const method = "mcpServer/elicitation/request";
  assert.equal(sessionAllowableTool(method, toolElicitation("godot.bridge_status")), "godot.bridge_status");
  assert.equal(sessionAllowableTool(method, toolElicitation("godot.set_node_properties")), null, "mutations always ask");
  assert.equal(sessionAllowableTool(method, toolElicitation("godot.capture_viewport_screenshot")), null, "screenshots always ask");
  assert.equal(sessionAllowableTool(method, toolElicitation("godot.bridge_status", { serverName: "other_server" })), null);
  assert.equal(sessionAllowableTool(method, toolElicitation("godot.bridge_status", { _meta: { codex_approval_kind: "other" } })), null);
  assert.equal(sessionAllowableTool(method, toolElicitation("godot.bridge_status", {
    requestedSchema: { type: "object", properties: { confirm: { type: "boolean" } } },
  })), null, "questions with form fields always ask");
  assert.equal(sessionAllowableTool(method, toolElicitation("godot.bridge_status", {
    message: 'Allow the godot_codex_bridge MCP server to run tool "godot.bridge_status"? Also delete files.',
  })), null);
  assert.equal(sessionAllowableTool("item/commandExecution/requestApproval", toolElicitation("godot.bridge_status")), null);
});

test("every session-allowable tool is classified read_only in the MCP tool catalog", async () => {
  const catalogPath = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..", "..", "mcp_server", "src", "toolCatalog.ts");
  const catalog = await fs.readFile(catalogPath, "utf8");
  for (const tool of SESSION_ALLOWABLE_TOOLS) {
    const pattern = new RegExp(`entry\\("${tool.replace(".", "\\.")}",\\s*"[^"]+",\\s*"read_only"`);
    assert.match(catalog, pattern, `${tool} must be a read_only catalog tool`);
  }
});

test("allow for session approves once, then auto-approves the same tool without a card", async () => {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-session-allow-"));
  await fs.writeFile(path.join(projectRoot, "project.godot"), "[application]\n", "utf8");
  const runtime = new AppServerRuntime({ codexBin: "unused", host: "127.0.0.1", port: 0, backpressureLimit: 50 });
  const sent: Array<Record<string, unknown>> = [];
  const transport = runtime as unknown as {
    ensureConnected(): Promise<void>;
    request(method: string): Promise<unknown>;
    handleMessage(raw: string): void;
    proc: ChildProcess | null;
    socket: { readyState: number; send(raw: string, callback?: (error?: Error) => void): void; close(): void } | null;
  };
  transport.ensureConnected = async () => {};
  transport.request = async (method) => {
    if (method === "thread/start") return { thread: { id: threadId }, cwd: projectRoot, instructionSources: [] };
    if (method === "turn/start") return { turn: { id: "turn-1" } };
    throw new Error(`unexpected test request: ${method}`);
  };
  (runtime as unknown as { inspectMcpTools(): Promise<unknown> }).inspectMcpTools = async () => ({
    available: false, serverName: null, toolCount: 0, godotToolCount: 0, godotTools: [], checkedAt: new Date().toISOString(),
  });
  transport.socket = {
    readyState: 1,
    send: (raw, callback) => { sent.push(JSON.parse(raw)); callback?.(); },
    close: () => {},
  };
  const controller = new HostController(loadConfig(["--runtime", "mock"]), runtime);
  const events: HostEvent[] = [];
  controller.on("event", (item) => events.push(item));
  try {
    await controller.handleRequest({ method: "project.attach", params: { project_root: projectRoot } });
    // Attach binds the Bridge MCP server; install the fake app-server afterwards.
    transport.proc = Object.assign(new EventEmitter(), { kill: () => true }) as unknown as ChildProcess;
    await controller.handleRequest({ method: "thread.send", params: { message: "look around" } });
    await waitFor(() => events.some((item) => item.method === "turn.started"));

    // A mutation tool question is never remembered.
    transport.handleMessage(JSON.stringify({ id: 80, method: "mcpServer/elicitation/request", params: toolElicitation("godot.set_node_properties") }));
    await waitFor(() => events.filter((item) => item.method === "approval.requested").length === 1);
    const mutation = events.filter((item) => item.method === "approval.requested")[0]!;
    assert.equal(mutation.params.session_allow_tool, undefined);
    await assert.rejects(controller.handleRequest({ method: "approval.respond", params: {
      approval_id: mutation.params.approval_id, nonce: mutation.params.nonce, decision: "approve", remember_for_session: true,
    } }), /session_allow_not_eligible/);
    await controller.handleRequest({ method: "approval.respond", params: {
      approval_id: mutation.params.approval_id, nonce: mutation.params.nonce, decision: "reject",
    } });

    transport.handleMessage(JSON.stringify({ id: 81, method: "mcpServer/elicitation/request", params: toolElicitation("godot.bridge_status") }));
    await waitFor(() => events.filter((item) => item.method === "approval.requested").length === 2);
    const first = events.filter((item) => item.method === "approval.requested")[1]!;
    assert.equal(first.params.session_allow_tool, "godot.bridge_status");
    await controller.handleRequest({ method: "approval.respond", params: {
      approval_id: first.params.approval_id, nonce: first.params.nonce, decision: "approve", remember_for_session: true,
    } });
    assert.deepEqual(controller.status().sessionAllowedTools, ["godot.bridge_status"]);
    assert.equal(sent.filter((message) => message.id === 81).length, 1);

    transport.handleMessage(JSON.stringify({ id: 82, method: "mcpServer/elicitation/request", params: toolElicitation("godot.bridge_status") }));
    await waitFor(() => events.some((item) => item.method === "approval.auto_approved"));
    assert.equal(events.filter((item) => item.method === "approval.requested").length, 2, "no card for a remembered tool");
    const auto = sent.find((message) => message.id === 82) as { result?: { action?: string } } | undefined;
    assert.equal(auto?.result?.action, "accept");

    // A different tool still asks.
    transport.handleMessage(JSON.stringify({ id: 83, method: "mcpServer/elicitation/request", params: toolElicitation("godot.get_scene_tree") }));
    await waitFor(() => events.filter((item) => item.method === "approval.requested").length === 3);

    await controller.handleRequest({ method: "approval.session_allow.clear" });
    assert.deepEqual(controller.status().sessionAllowedTools, []);
  } finally {
    await controller.shutdown();
  }
});

async function waitFor(predicate: () => boolean, timeoutMs = 3_000): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (!predicate()) {
    if (Date.now() > deadline) throw new Error("timed out waiting for condition");
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
}
