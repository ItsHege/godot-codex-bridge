import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import type { CodexRuntimeAdapter, RuntimeThreadHandle, RuntimeThreadOptions, RuntimeTurnInput } from "../src/codexRuntime.js";
import { event, MockCodexRuntime } from "../src/codexRuntime.js";
import { loadConfig } from "../src/config.js";
import { HostController } from "../src/hostController.js";
import type { HostEvent } from "../src/types.js";

async function fixtureProject(): Promise<string> {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-background-"));
  await fs.writeFile(path.join(root, "project.godot"), "[application]\n", "utf8");
  return root;
}

test("background.start runs read-only roles and writes task evidence", async () => {
  const projectRoot = await fixtureProject();
  const controller = new HostController(loadConfig(["--runtime", "mock"]), new MockCodexRuntime());
  const events: HostEvent[] = [];
  controller.on("event", (hostEvent) => events.push(hostEvent));

  await controller.handleRequest({ method: "project.attach", params: { project_root: projectRoot } });
  const response = await controller.handleRequest({
    method: "background.start",
    params: {
      prompt: "Review current scene",
      roles: ["scene_agent", "script_agent", "qa_agent"]
    }
  }) as { task_id: string; state: string };

  assert.match(response.task_id, /^background-/);
  await waitFor(() => events.some((hostEvent) => hostEvent.method === "background.updated" && hostEvent.params.state === "completed"));
  assert.equal(controller.status().backgroundTasks, 0);

  const taskDir = path.join(projectRoot, ".godot", "godot_codex_bridge", "codex_host", "background_tasks", response.task_id);
  const taskJson = JSON.parse(await fs.readFile(path.join(taskDir, "task.json"), "utf8")) as { state: string; results: Array<{ role: string; artifact_path: string }> };
  assert.equal(taskJson.state, "completed");
  assert.deepEqual(taskJson.results.map((result) => result.role), ["scene_agent", "script_agent", "qa_agent"]);
  const status = await controller.handleRequest({ method: "background.status", params: {} }) as { active_tasks: number; tasks: Array<{ task_id: string; state: string }> };
  assert.equal(status.active_tasks, 0);
  assert.equal(status.tasks[0].task_id, response.task_id);
  assert.equal(status.tasks[0].state, "completed");
  assert.ok(await exists(path.join(taskDir, "summary.md")));
  for (const result of taskJson.results) {
    assert.ok(await exists(result.artifact_path));
  }
});

test("background work does not block foreground thread.send", async () => {
  const projectRoot = await fixtureProject();
  const controller = new HostController(loadConfig(["--runtime", "mock"]), new ForegroundMockBackgroundSlowRuntime());
  const events: HostEvent[] = [];
  controller.on("event", (hostEvent) => events.push(hostEvent));

  await controller.handleRequest({ method: "project.attach", params: { project_root: projectRoot } });
  const background = await controller.handleRequest({
    method: "background.start",
    params: {
      prompt: "Slow team review",
      roles: ["scene_agent", "script_agent"]
    }
  }) as { task_id: string };

  await waitFor(() => controller.status().backgroundTasks === 1);
  const send = await controller.handleRequest({
    method: "thread.send",
    params: { message: "Foreground should still work" }
  }) as { accepted: boolean };
  assert.equal(send.accepted, true);
  await waitFor(() => events.some((hostEvent) => hostEvent.method === "turn.completed"));

  const cancel = await controller.handleRequest({
    method: "background.cancel",
    params: { task_id: background.task_id }
  }) as { cancelled: boolean };
  assert.equal(cancel.cancelled, true);
  await waitFor(() => events.some((hostEvent) => hostEvent.method === "background.updated" && hostEvent.params.state === "cancelled"));
});

test("background role timeout writes a partial summary instead of hanging", async () => {
  const previousRoleTimeout = process.env.GODOT_CODEX_BACKGROUND_ROLE_TIMEOUT_MS;
  const previousSummaryTimeout = process.env.GODOT_CODEX_BACKGROUND_SUMMARY_TIMEOUT_MS;
  process.env.GODOT_CODEX_BACKGROUND_ROLE_TIMEOUT_MS = "60";
  process.env.GODOT_CODEX_BACKGROUND_SUMMARY_TIMEOUT_MS = "1000";
  try {
    const projectRoot = await fixtureProject();
    const controller = new HostController(loadConfig(["--runtime", "mock"]), new TimeoutThenSummaryRuntime());
    const events: HostEvent[] = [];
    controller.on("event", (hostEvent) => events.push(hostEvent));

    await controller.handleRequest({ method: "project.attach", params: { project_root: projectRoot } });
    const response = await controller.handleRequest({
      method: "background.start",
      params: {
        prompt: "Timeout test",
        roles: ["scene_agent"]
      }
    }) as { task_id: string };

    await waitFor(() => events.some((hostEvent) => hostEvent.method === "background.updated" && hostEvent.params.state === "failed"));
    assert.equal(controller.status().backgroundTasks, 0);

    const taskDir = path.join(projectRoot, ".godot", "godot_codex_bridge", "codex_host", "background_tasks", response.task_id);
    const taskJson = JSON.parse(await fs.readFile(path.join(taskDir, "task.json"), "utf8")) as {
      state: string;
      error: string;
      summary_path: string;
      results: Array<{ state: string; error: string }>;
    };
    assert.equal(taskJson.state, "failed");
    assert.match(taskJson.error, /partial summary written/);
    assert.match(taskJson.results[0].error, /scene_agent_turn_timeout/);
    assert.ok(await exists(taskJson.summary_path));
  } finally {
    restoreEnv("GODOT_CODEX_BACKGROUND_ROLE_TIMEOUT_MS", previousRoleTimeout);
    restoreEnv("GODOT_CODEX_BACKGROUND_SUMMARY_TIMEOUT_MS", previousSummaryTimeout);
  }
});

test("background role prompts include bounded Godot editor orientation", async () => {
  const projectRoot = await fixtureProject();
  await writeBackgroundProjectMapFixture(projectRoot);
  const bridgeDir = path.join(projectRoot, ".godot", "godot_codex_bridge");
  await fs.mkdir(bridgeDir, { recursive: true });
  await fs.writeFile(path.join(bridgeDir, "context_snapshot.json"), JSON.stringify({
    protocol_version: "godot-codex-bridge/0.1",
    generated_at: "2026-06-15T12:00:00Z",
    project: {
      name: "Background Fixture",
      godot_version: "4.7.1-stable",
      main_scene: "res://scenes/main.tscn"
    },
    current_scene: {
      path: "res://scenes/main.tscn",
      name: "Main",
      is_dirty: false,
      root_node: { path: ".", name: "Main", type: "Node2D" },
      open_scenes: ["res://scenes/main.tscn"]
    },
    selected_nodes: [
      {
        node: {
          path: "Hero",
          name: "Hero",
          type: "CharacterBody2D",
          script_path: "res://scripts/hero.gd",
          child_count: 0,
          children: []
        },
        properties_summary: []
      }
    ],
    scene_tree: {
      node_count: 2,
      truncated: false,
      root: {
        path: ".",
        name: "Main",
        type: "Node2D",
        child_count: 1,
        children: [
          { path: "Hero", name: "Hero", type: "CharacterBody2D", child_count: 0, children: [], script_path: "res://scripts/hero.gd" }
        ]
      }
    },
    script_inventory: {
      script_count: 1,
      truncated: false,
      scripts: [
        { path: "res://scripts/hero.gd", class_name: "Hero", extends: "CharacterBody2D", functions: [], exports: [] }
      ]
    },
    resource_status: {
      scan_status: "complete",
      resources: [{ path: "res://scripts/hero.gd", type: "GDScript", status: "ok" }],
      missing_resources: [],
      import_errors: [],
      truncated: false
    },
    editor_output: { source: "bridge_log", entries: [] },
    screenshots: []
  }), "utf8");
  const runtime = new CapturingBackgroundRootRuntime();
  const controller = new HostController(loadConfig(["--runtime", "mock"]), runtime);
  const events: HostEvent[] = [];
  controller.on("event", (hostEvent) => events.push(hostEvent));

  await controller.handleRequest({ method: "project.attach", params: { project_root: projectRoot } });
  await controller.handleRequest({
    method: "background.start",
    params: {
      prompt: "Review scene awareness",
      roles: ["scene_agent"]
    }
  });

  await waitFor(() => events.some((hostEvent) => hostEvent.method === "background.updated" && hostEvent.params.state === "completed"));
  assert.ok(runtime.backgroundMessages.some((message) => message.includes("Godot Codex Bridge orientation")));
  assert.ok(runtime.backgroundMessages.some((message) => message.includes("[Project map compact]")));
  assert.ok(runtime.backgroundMessages.some((message) => message.includes("Project name: Background Map Fixture")));
  assert.ok(runtime.backgroundMessages.some((message) => message.includes("res://scenes/main.tscn")));
  assert.ok(runtime.backgroundMessages.some((message) => message.includes("res://scripts/hero.gd (class=Hero extends=CharacterBody2D")));
  assert.ok(runtime.backgroundMessages.some((message) => message.includes("Scene path: res://scenes/main.tscn")));
  assert.ok(runtime.backgroundMessages.some((message) => message.includes("Hero name=Hero type=CharacterBody2D script=res://scripts/hero.gd")));
  assert.ok(runtime.backgroundMessages.every((message) => !message.includes("generated/cache.gd")));
  assert.ok(runtime.backgroundMessages.every((message) => !message.includes("icon.png.import")));
  assert.ok(runtime.backgroundMessages.every((message) => !message.includes("addons/godot_codex_bridge/plugin.gd")));
});

class ForegroundMockBackgroundSlowRuntime extends MockCodexRuntime {
  createBackgroundRuntime(_index: number): CodexRuntimeAdapter {
    return new SlowBackgroundRuntime();
  }
}

class CapturingBackgroundRootRuntime extends MockCodexRuntime {
  readonly backgroundMessages: string[] = [];

  createBackgroundRuntime(_index: number): CodexRuntimeAdapter {
    return new CapturingBackgroundChildRuntime(this.backgroundMessages);
  }
}

class CapturingBackgroundChildRuntime extends MockCodexRuntime {
  constructor(private readonly messages: string[]) {
    super();
  }

  override async *runTurn(input: RuntimeTurnInput): AsyncIterable<HostEvent> {
    this.messages.push(input.message);
    yield* super.runTurn(input);
  }
}

class SlowBackgroundRuntime implements CodexRuntimeAdapter {
  readonly kind = "slow-background-test";
  private nextThread = 1;
  private interrupted = false;

  createBackgroundRuntime(_index: number): CodexRuntimeAdapter {
    return new SlowBackgroundRuntime();
  }

  async startThread(options: RuntimeThreadOptions): Promise<RuntimeThreadHandle> {
    return {
      threadId: `slow-background-thread-${this.nextThread++}`,
      cwd: options.projectRoot,
      instructionSources: []
    };
  }

  async *runTurn(input: RuntimeTurnInput): AsyncIterable<HostEvent> {
    const turnId = `slow-background-turn-${Date.now()}`;
    yield event("turn.started", {
      thread_id: input.threadId,
      turn_id: turnId
    });
    for (let index = 0; index < 100; index += 1) {
      if (this.interrupted) {
        yield event("turn.interrupted", {
          thread_id: input.threadId,
          turn_id: turnId
        });
        return;
      }
      await delay(20);
    }
    yield event("turn.completed", {
      thread_id: input.threadId,
      turn_id: turnId,
      status: "completed"
    });
  }

  async interruptTurn(_threadId: string, _turnId: string): Promise<void> {
    this.interrupted = true;
  }

  async respondToApproval(): Promise<void> {}

  async shutdown(): Promise<void> {
    this.interrupted = true;
  }
}

class TimeoutThenSummaryRuntime extends MockCodexRuntime {
  createBackgroundRuntime(index: number): CodexRuntimeAdapter {
    return index === 0 ? new NeverCompletesBackgroundRuntime() : new MockCodexRuntime();
  }
}

class NeverCompletesBackgroundRuntime extends SlowBackgroundRuntime {
  override async *runTurn(input: RuntimeTurnInput): AsyncIterable<HostEvent> {
    const turnId = `never-background-turn-${Date.now()}`;
    yield event("turn.started", {
      thread_id: input.threadId,
      turn_id: turnId
    });
    await new Promise(() => undefined);
  }
}

async function exists(filePath: string): Promise<boolean> {
  return (await fs.stat(filePath).catch(() => null))?.isFile() ?? false;
}

async function waitFor(predicate: () => boolean): Promise<void> {
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    if (predicate()) {
      return;
    }
    await delay(20);
  }
  throw new Error("timeout waiting for condition");
}

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function restoreEnv(name: string, previous: string | undefined): void {
  if (previous === undefined) {
    delete process.env[name];
  } else {
    process.env[name] = previous;
  }
}

async function writeBackgroundProjectMapFixture(projectRoot: string): Promise<void> {
  await fs.writeFile(
    path.join(projectRoot, "project.godot"),
    [
      "[application]",
      'config/name="Background Map Fixture"',
      'run/main_scene="res://scenes/main.tscn"',
      "",
      "[input]",
      "jump={}",
      "",
    ].join("\n"),
    "utf8",
  );
  await fs.mkdir(path.join(projectRoot, "scenes"), { recursive: true });
  await fs.mkdir(path.join(projectRoot, "scripts"), { recursive: true });
  await fs.mkdir(path.join(projectRoot, "textures"), { recursive: true });
  await fs.mkdir(path.join(projectRoot, "generated"), { recursive: true });
  await fs.mkdir(path.join(projectRoot, "addons", "godot_codex_bridge"), { recursive: true });
  await fs.writeFile(
    path.join(projectRoot, "scenes", "main.tscn"),
    [
      '[gd_scene load_steps=2 format=3 uid="uid://backgroundmap"]',
      "",
      '[ext_resource type="Script" path="res://scripts/hero.gd" id="1_hero"]',
      "",
      '[node name="Main" type="Node2D"]',
      "",
      '[node name="Hero" type="CharacterBody2D" parent="."]',
      'script = ExtResource("1_hero")',
      "",
    ].join("\n"),
    "utf8",
  );
  await fs.writeFile(
    path.join(projectRoot, "scripts", "hero.gd"),
    ["class_name Hero", "extends CharacterBody2D", "signal jumped", ""].join("\n"),
    "utf8",
  );
  await fs.writeFile(path.join(projectRoot, "textures", "icon.png.import"), "[remap]\n", "utf8");
  await fs.writeFile(path.join(projectRoot, "generated", "cache.gd"), "extends Node\n", "utf8");
  await fs.writeFile(path.join(projectRoot, "addons", "godot_codex_bridge", "plugin.gd"), "extends EditorPlugin\n", "utf8");
}
