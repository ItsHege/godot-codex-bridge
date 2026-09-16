import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { loadConfig } from "../src/config.js";
import { MockCodexRuntime } from "../src/codexRuntime.js";
import { HostController } from "../src/hostController.js";
import { RUNTIME_STATES, type RuntimeModelInventory, type RuntimeToolInventory } from "../src/types.js";

async function fixtureProject(): Promise<string> {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-host-protocol-"));
  await fs.writeFile(path.join(root, "project.godot"), "[application]\n", "utf8");
  return root;
}

class CapturingRuntime extends MockCodexRuntime {
  messages: string[] = [];
  threads: Parameters<MockCodexRuntime["startThread"]>[0][] = [];
  turns: Parameters<MockCodexRuntime["runTurn"]>[0][] = [];

  override async startThread(input: Parameters<MockCodexRuntime["startThread"]>[0]) {
    this.threads.push(input);
    return super.startThread(input);
  }

  override async *runTurn(input: Parameters<MockCodexRuntime["runTurn"]>[0]) {
    this.messages.push(input.message);
    this.turns.push(input);
    yield* super.runTurn(input);
  }
}

class TextOnlyRuntime extends CapturingRuntime {
  override async listModels(): Promise<RuntimeModelInventory> {
    return {
      models: [
        {
          id: "text-only",
          model: "text-only",
          displayName: "Text Only",
          inputModalities: ["text"],
          isDefault: true,
          supportedReasoningEfforts: [{ reasoningEffort: "medium" }],
        },
      ],
      defaultModel: "text-only",
      reasoningEfforts: [{ reasoningEffort: "medium" }],
      checkedAt: new Date().toISOString(),
    };
  }
}

test("host exposes canonical runtime states", () => {
  assert.deepEqual([...RUNTIME_STATES], [
    "disconnected",
    "connecting",
    "ready",
    "turn_running",
    "waiting_for_approval",
    "applying_diff",
    "error_recoverable",
    "error_fatal"
  ]);
});

test("host.shutdown accepts cleanup request and emits shutdown signal", async () => {
  const controller = new HostController(loadConfig(["--runtime", "mock"]), new MockCodexRuntime());
  const projectRoot = await fixtureProject();
  let shutdownRequested = false;
  controller.once("shutdownRequested", () => {
    shutdownRequested = true;
  });

  await controller.handleRequest({
    id: 1,
    method: "project.attach",
    params: { project_root: projectRoot }
  });
  const response = await controller.handleRequest({
    id: 2,
    method: "host.shutdown",
    params: { reason: "test" }
  }) as { accepted: boolean; status: { state: string } };

  assert.equal(response.accepted, true);
  assert.equal(response.status.state, "ready");
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(shutdownRequested, true);
});

test("session.trust.set enables full-machine policy for new foreground turns", async () => {
  const runtime = new CapturingRuntime();
  const controller = new HostController(loadConfig(["--runtime", "mock"]), runtime);
  const projectRoot = await fixtureProject();
  const events: string[] = [];
  controller.on("event", (event) => events.push(event.method));

  await controller.handleRequest({
    id: 1,
    method: "project.attach",
    params: { project_root: projectRoot }
  });
  const trust = await controller.handleRequest({
    id: 2,
    method: "session.trust.set",
    params: { mode: "full_machine" }
  }) as { trustMode: string; trustSessionChanged: boolean };
  assert.equal(trust.trustMode, "full_machine");
  assert.equal(trust.trustSessionChanged, true);

  await controller.handleRequest({
    id: 3,
    method: "thread.send",
    params: { message: "Create a scene without repeated approvals" }
  });
  await waitFor(() => events.includes("turn.completed"));

  assert.equal(runtime.threads[0].approvalPolicy, "never");
  assert.equal(runtime.threads[0].sandbox, "danger-full-access");
  assert.equal(runtime.turns[0].approvalPolicy, "never");
  assert.equal(runtime.turns[0].sandbox, "danger-full-access");

  const cleared = await controller.handleRequest({
    id: 4,
    method: "session.trust.clear",
    params: {}
  }) as { trustMode: string; trustSessionChanged: boolean };
  assert.equal(cleared.trustMode, "off");
  assert.equal(cleared.trustSessionChanged, true);
});

test("project.attach and thread.send drive mock runtime events", async () => {
  const controller = new HostController(loadConfig(["--runtime", "mock"]), new MockCodexRuntime());
  const projectRoot = await fixtureProject();
  const events: string[] = [];
  controller.on("event", (event) => events.push(event.method));

  const attach = await controller.handleRequest({
    id: 1,
    method: "project.attach",
    params: { project_root: projectRoot }
  });
  assert.equal((attach as { state: string }).state, "ready");

  const send = await controller.handleRequest({
    id: 2,
    method: "thread.send",
    params: {
      message: "Summarize project",
      attachments: { context_snapshot: true }
    }
  });
  assert.equal((send as { accepted: boolean }).accepted, true);

  await waitFor(() => events.includes("turn.completed"));
  assert.ok(events.includes("thread.started"));
  assert.ok(events.includes("turn.started"));
  assert.ok(events.includes("turn.event"));
  assert.ok(events.includes("turn.completed"));
  assert.equal(controller.status().state, "ready");
});

test("project.attach can switch active project and clear old thread state", async () => {
  const controller = new HostController(loadConfig(["--runtime", "mock"]), new MockCodexRuntime());
  const firstProjectRoot = await fixtureProject();
  const secondProjectRoot = await fixtureProject();
  const events: string[] = [];
  controller.on("event", (event) => events.push(event.method));

  await controller.handleRequest({
    id: 1,
    method: "project.attach",
    params: { project_root: firstProjectRoot }
  });
  await controller.handleRequest({
    id: 2,
    method: "thread.send",
    params: { message: "Start in project A" }
  });
  await waitFor(() => events.includes("turn.completed"));
  assert.ok(controller.status().threadId);

  const switched = await controller.handleRequest({
    id: 3,
    method: "project.attach",
    params: { project_root: secondProjectRoot }
  }) as { activeProject?: { projectRoot: string }; threadId?: string; state: string };

  assert.equal(switched.state, "ready");
  assert.equal(switched.activeProject?.projectRoot, secondProjectRoot);
  assert.equal(switched.threadId, undefined);
  assert.equal(controller.status().activeProject?.projectRoot, secondProjectRoot);
  assert.equal(controller.status().threadId, undefined);
});

test("host.restart_for_project switches project clears session state trust and writes cleanup evidence", async () => {
  const controller = new HostController(loadConfig(["--runtime", "mock"]), new MockCodexRuntime());
  const firstProjectRoot = await fixtureProject();
  const secondProjectRoot = await fixtureProject();
  const events: Array<{ method: string; params: Record<string, unknown> }> = [];
  controller.on("event", (event) => events.push(event));

  await controller.handleRequest({
    id: 1,
    method: "project.attach",
    params: { project_root: firstProjectRoot }
  });
  await controller.handleRequest({
    id: 2,
    method: "session.trust.set",
    params: { mode: "full_machine" }
  });
  await controller.handleRequest({
    id: 3,
    method: "thread.send",
    params: { message: "Start in project A" }
  });
  await waitFor(() => events.some((item) => item.method === "turn.completed"));
  assert.ok(controller.status().threadId);
  assert.equal(controller.status().trustMode, "full_machine");

  const restarted = await controller.handleRequest({
    id: 4,
    method: "host.restart_for_project",
    params: { project_root: secondProjectRoot }
  }) as {
    activeProject?: { projectRoot: string };
    threadId?: string;
    turnId?: string;
    trustMode: string;
    restartForProject: boolean;
    previousProjectRoot?: string;
    trustCleared: boolean;
  };

  assert.equal(restarted.restartForProject, true);
  assert.equal(restarted.previousProjectRoot, firstProjectRoot);
  assert.equal(restarted.activeProject?.projectRoot, secondProjectRoot);
  assert.equal(restarted.threadId, undefined);
  assert.equal(restarted.turnId, undefined);
  assert.equal(restarted.trustMode, "off");
  assert.equal(restarted.trustCleared, true);
  assert.equal(controller.status().activeProject?.projectRoot, secondProjectRoot);
  assert.equal(controller.status().threadId, undefined);
  assert.equal(controller.status().trustMode, "off");

  const reconnectEvent = events.find((item) => item.method === "host.reconnected" && item.params.project_root === secondProjectRoot);
  assert.ok(reconnectEvent);
  assert.equal(reconnectEvent.params.previous_project_root, firstProjectRoot);
  assert.equal(reconnectEvent.params.trust_cleared, true);
  const evidencePath = String(reconnectEvent.params.cleanup_evidence_path ?? "");
  assert.match(evidencePath, /host-cleanup-\d+\.json$/);
  const evidence = JSON.parse(await fs.readFile(evidencePath, "utf8")) as Record<string, unknown>;
  assert.equal(evidence.cleanup_version, "godot-codex-bridge/host-cleanup-v1");
  assert.equal(evidence.reason, "host.restart_for_project");
  assert.equal(evidence.previous_project_root, firstProjectRoot);
  assert.equal(evidence.project_root, secondProjectRoot);
  assert.equal(evidence.trust_cleared, true);
});

test("host.restart_for_project rejects while a foreground turn is busy", async () => {
  const controller = new HostController(loadConfig(["--runtime", "mock"]), new MockCodexRuntime());
  const firstProjectRoot = await fixtureProject();
  const secondProjectRoot = await fixtureProject();

  await controller.handleRequest({
    id: 1,
    method: "project.attach",
    params: { project_root: firstProjectRoot }
  });
  await controller.handleRequest({
    id: 2,
    method: "thread.send",
    params: { message: "Keep this turn busy briefly" }
  });

  await assert.rejects(
    controller.handleRequest({
      id: 3,
      method: "host.restart_for_project",
      params: { project_root: secondProjectRoot }
    }),
    /host_busy: turn_running/
  );
  assert.equal(controller.status().activeProject?.projectRoot, firstProjectRoot);
});

test("thread.send includes bounded project orientation with AGENTS preview", async () => {
  const runtime = new CapturingRuntime();
  const controller = new HostController(loadConfig(["--runtime", "mock"]), runtime);
  const projectRoot = await fixtureProject();
  await fs.writeFile(path.join(projectRoot, "AGENTS.md"), "# Fixture Rules\n\nGCB_FIXTURE_AGENTS_LOADED\n", "utf8");
  const events: string[] = [];
  controller.on("event", (event) => events.push(event.method));

  await controller.handleRequest({
    id: 1,
    method: "project.attach",
    params: { project_root: projectRoot }
  });
  await controller.handleRequest({
    id: 2,
    method: "thread.send",
    params: {
      message: "Visible editor real Codex chat smoke",
      attachments: { context_snapshot: true }
    }
  });

  await waitFor(() => events.includes("turn.completed"));
  assert.equal(runtime.messages.length, 1);
  assert.match(runtime.messages[0], /Godot Codex Bridge orientation/);
  assert.match(runtime.messages[0], /AGENTS files detected: 1/);
  assert.match(runtime.messages[0], /GCB_FIXTURE_AGENTS_LOADED/);
  assert.match(runtime.messages[0], /Bridge tools visible: yes/);
});

test("thread.send includes compact project map and excludes generated paths", async () => {
  const runtime = new CapturingRuntime();
  const controller = new HostController(loadConfig(["--runtime", "mock"]), runtime);
  const projectRoot = await fixtureProject();
  await writeProjectMapFixture(projectRoot);
  const events: string[] = [];
  controller.on("event", (event) => events.push(event.method));

  await controller.handleRequest({
    id: 1,
    method: "project.attach",
    params: { project_root: projectRoot }
  });
  await controller.handleRequest({
    id: 2,
    method: "thread.send",
    params: { message: "Orient before editing" }
  });

  await waitFor(() => events.includes("turn.completed"));
  const message = runtime.messages[0];
  assert.match(message, /\[Project map compact\]/);
  assert.match(message, /Budget: 6000 chars/);
  assert.match(message, /Project name: Map Fixture/);
  assert.match(message, /Main scene: res:\/\/scenes\/main\.tscn/);
  assert.match(message, /Autoloads: GameState->res:\/\/scripts\/game_state\.gd/);
  assert.match(message, /Input actions: jump/);
  assert.match(message, /res:\/\/scenes\/main\.tscn \(nodes=2 root=Node3D scripts=res:\/\/scripts\/player\.gd instances=res:\/\/scenes\/enemy\.tscn\)/);
  assert.match(message, /res:\/\/scripts\/player\.gd \(class=PlayerController extends=CharacterBody3D signals=health_changed\)/);
  assert.match(message, /Resources .*res:\/\/materials\/player_mat\.tres:resource/);
  assert.doesNotMatch(message, /\.godot\/secret\.gd/);
  assert.doesNotMatch(message, /icon\.png\.import/);
  assert.doesNotMatch(message, /addons\/godot_codex_bridge\/plugin\.gd/);
  assert.doesNotMatch(message, /generated\/cache\.gd/);
});

test("thread.send injects project orientation only once per thread", async () => {
  const runtime = new CapturingRuntime();
  const controller = new HostController(loadConfig(["--runtime", "mock"]), runtime);
  const projectRoot = await fixtureProject();
  const events: string[] = [];
  controller.on("event", (event) => events.push(event.method));

  await controller.handleRequest({
    id: 1,
    method: "project.attach",
    params: { project_root: projectRoot }
  });
  await controller.handleRequest({
    id: 2,
    method: "thread.send",
    params: { message: "First turn" }
  });
  await waitFor(() => events.includes("turn.completed"));
  events.length = 0;
  await controller.handleRequest({
    id: 3,
    method: "thread.send",
    params: { message: "Second turn same thread" }
  });
  await waitFor(() => events.includes("turn.completed"));

  assert.equal(runtime.messages.length, 2);
  assert.match(runtime.messages[0], /Godot Codex Bridge orientation/);
  assert.doesNotMatch(runtime.messages[1], /Godot Codex Bridge orientation/);
});

test("thread.send forwards selected model and reasoning effort to runtime", async () => {
  const runtime = new CapturingRuntime();
  const controller = new HostController(loadConfig(["--runtime", "mock"]), runtime);
  const projectRoot = await fixtureProject();
  const events: string[] = [];
  controller.on("event", (event) => events.push(event.method));

  await controller.handleRequest({
    id: 1,
    method: "project.attach",
    params: { project_root: projectRoot }
  });
  await controller.handleRequest({
    id: 2,
    method: "thread.send",
    params: {
      message: "Use selected runtime options",
      model: "gpt-5-codex",
      effort: "low"
    }
  });

  await waitFor(() => events.includes("turn.completed"));
  assert.equal(runtime.turns[0].model, "gpt-5-codex");
  assert.equal(runtime.turns[0].effort, "low");
});

test("thread.send resolves AI marker annotation and attaches local image when model supports images", async () => {
  const runtime = new CapturingRuntime();
  const controller = new HostController(loadConfig(["--runtime", "mock"]), runtime);
  const projectRoot = await fixtureProject();
  await writeAnnotationArtifact(projectRoot, "annotation_test_001");
  const events: string[] = [];
  controller.on("event", (event) => events.push(event.method));

  await controller.handleRequest({
    id: 1,
    method: "project.attach",
    params: { project_root: projectRoot }
  });
  await controller.handleRequest({
    id: 2,
    method: "thread.send",
    params: {
      message: "ziurek i marker A",
      attachments: { context_snapshot: true },
      annotation: { annotation_id: "annotation_test_001", include_image: true, detail: "high" }
    }
  });

  await waitFor(() => events.includes("turn.completed"));
  assert.match(runtime.messages[0], /Godot AI Marker attachment/);
  assert.match(runtime.messages[0], /Do not recreate, draw, or implement the marker graphics/);
  assert.equal(runtime.turns[0].annotation?.annotationId, "annotation_test_001");
  assert.equal(runtime.turns[0].annotation?.imageAttached, true);
});

test("thread.send keeps AI marker metadata when selected model lacks image input", async () => {
  const runtime = new TextOnlyRuntime();
  const controller = new HostController(loadConfig(["--runtime", "mock"]), runtime);
  const projectRoot = await fixtureProject();
  await writeAnnotationArtifact(projectRoot, "annotation_text_only");
  const events: string[] = [];
  controller.on("event", (event) => events.push(event.method));

  await controller.handleRequest({
    id: 1,
    method: "project.attach",
    params: { project_root: projectRoot }
  });
  await controller.handleRequest({
    id: 2,
    method: "thread.send",
    params: {
      message: "ziurek i marker A",
      annotation: { annotation_id: "annotation_text_only", include_image: true }
    }
  });

  await waitFor(() => events.includes("turn.completed"));
  assert.match(runtime.messages[0], /selected\/default model did not report image input support/);
  assert.equal(runtime.turns[0].annotation?.annotationId, "annotation_text_only");
  assert.equal(runtime.turns[0].annotation?.imageAttached, false);
});

test("thread.send includes bounded Godot editor snapshot orientation", async () => {
  const runtime = new CapturingRuntime();
  const controller = new HostController(loadConfig(["--runtime", "mock"]), runtime);
  const projectRoot = await fixtureProject();
  const bridgeDir = path.join(projectRoot, ".godot", "godot_codex_bridge");
  await fs.mkdir(bridgeDir, { recursive: true });
  const childNodes = Array.from({ length: 55 }, (_, index) => ({
    path: `Node${index}`,
    name: `Node${index}`,
    type: index === 0 ? "Camera2D" : "Node2D",
    child_count: 0,
    children: [],
    script_path: index === 1 ? "res://scripts/player.gd" : null
  }));
  await fs.writeFile(path.join(bridgeDir, "context_snapshot.json"), JSON.stringify({
    protocol_version: "godot-codex-bridge/0.1",
    generated_at: "2026-06-14T20:00:00Z",
    project: {
      name: "Fixture Game",
      godot_version: "4.7.1-stable",
      main_scene: "res://scenes/combat_main.tscn",
      features: ["4.7", "Forward Plus"]
    },
    current_scene: {
      path: "res://scenes/combat_main.tscn",
      name: "CombatMain",
      is_dirty: false,
      root_node: { path: ".", name: "CombatMain", type: "Node2D" },
      open_scenes: ["res://scenes/combat_main.tscn", "res://scenes/first_map.tscn"]
    },
    selected_nodes: [
      {
        node: {
          path: "Player",
          name: "Player",
          type: "CharacterBody2D",
          script_path: "res://scripts/player.gd",
          child_count: 0,
          children: []
        },
        properties_summary: [
          { name: "position", value_summary: "Vector2(10, 20)" }
        ]
      }
    ],
    scene_tree: {
      node_count: 56,
      truncated: true,
      root: {
        path: ".",
        name: "CombatMain",
        type: "Node2D",
        child_count: childNodes.length,
        children: childNodes
      }
    },
    gameplay_context: {
      autoloads: [{ name: "GameState", path: "res://scripts/game_state.gd", singleton: true }],
      input_actions: [
        { name: "ui_accept", built_in: true, event_count: 2 },
        { name: "move_left", built_in: false, event_count: 1 }
      ]
    },
    script_inventory: {
      script_count: 2,
      truncated: false,
      scripts: [
        { path: "res://scripts/player.gd", class_name: "Player", extends: "CharacterBody2D", functions: [{ line: 1, signature: "func _ready() -> void:" }], exports: [] },
        { path: "res://scripts/game_state.gd", class_name: "GameState", extends: "Node", functions: [], exports: [] }
      ]
    },
    resource_status: {
      scan_status: "complete",
      resources: [
        { path: "res://scenes/combat_main.tscn", type: "PackedScene", status: "ok" },
        { path: "res://scripts/player.gd", type: "GDScript", status: "ok" }
      ],
      missing_resources: ["res://missing.png"],
      import_errors: [],
      truncated: false
    },
    editor_output: {
      source: "bridge_log",
      entries: [
        { level: "info", message: "context_snapshot_written" },
        { level: "error", message: "Missing texture", file: "res://scenes/combat_main.tscn", line: 12 }
      ]
    },
    performance: {
      status: "available",
      monitors: {
        time_fps: 120,
        render_total_draw_calls_in_frame: 33,
        render_total_objects_in_frame: 44
      }
    },
    screenshots: [
      {
        screenshot_id: "viewport_2d_test",
        scene_path: "res://scenes/combat_main.tscn",
        artifact: { width: 1280, height: 720 }
      }
    ],
    private_blob: "SHOULD_NOT_LEAK_IN_ORIENTATION"
  }), "utf8");
  const events: string[] = [];
  controller.on("event", (event) => events.push(event.method));

  await controller.handleRequest({
    id: 1,
    method: "project.attach",
    params: { project_root: projectRoot }
  });
  await controller.handleRequest({
    id: 2,
    method: "thread.send",
    params: {
      message: "What do you see in this Godot project?",
      attachments: { context_snapshot: true, selected_nodes: true }
    }
  });

  await waitFor(() => events.includes("turn.completed"));
  assert.equal(runtime.messages.length, 1);
  const message = runtime.messages[0];
  assert.match(message, /Context snapshot: available/);
  assert.match(message, /Name: Fixture Game/);
  assert.match(message, /Scene path: res:\/\/scenes\/combat_main\.tscn/);
  assert.match(message, /Player name=Player type=CharacterBody2D script=res:\/\/scripts\/player\.gd/);
  assert.match(message, /Scene nodes shown: 40 \(truncated to 40\)/);
  assert.match(message, /Input actions \(2, custom 1\): move_left/);
  assert.match(message, /Script count: 2/);
  assert.match(message, /error: Missing texture/);
  assert.match(message, /fps=120, draw_calls=33, objects=44/);
  assert.doesNotMatch(message, /Node54/);
  assert.doesNotMatch(message, /SHOULD_NOT_LEAK_IN_ORIENTATION/);
});

test("project.attach exposes MCP tool inventory in host status", async () => {
  const controller = new HostController(loadConfig(["--runtime", "mock"]), new MockCodexRuntime());
  const projectRoot = await fixtureProject();
  const status = await controller.handleRequest({
    id: 1,
    method: "project.attach",
    params: { project_root: projectRoot }
  });

  assert.equal((status as { mcpToolsAvailable?: boolean }).mcpToolsAvailable, true);
  assert.equal((status as { mcpGodotToolCount?: number }).mcpGodotToolCount, 4);
  assert.match(String((status as { mcpServerName?: string }).mcpServerName), /godot-codex-bridge/);
});

test("project.attach keeps running when MCP tool inventory check fails", async () => {
  class FailingInventoryRuntime extends MockCodexRuntime {
    async inspectMcpTools(_threadId?: string): Promise<RuntimeToolInventory> {
      throw new Error("inventory unavailable");
    }
  }
  const controller = new HostController(loadConfig(["--runtime", "mock"]), new FailingInventoryRuntime());
  const projectRoot = await fixtureProject();
  const status = await controller.handleRequest({
    id: 1,
    method: "project.attach",
    params: { project_root: projectRoot }
  });

  assert.equal((status as { state: string }).state, "ready");
  assert.equal((status as { mcpToolsAvailable?: boolean }).mcpToolsAvailable, false);
  assert.match(String((status as { toolVisibilityError?: string }).toolVisibilityError), /tool_inventory_failed/);
});

test("bridge.tools.preview and bridge.tools.enable expose registration flow", async () => {
  const controller = new HostController(loadConfig(["--runtime", "mock"]), new MockCodexRuntime());
  const projectRoot = await fixtureProject();
  await controller.handleRequest({
    id: 1,
    method: "project.attach",
    params: { project_root: projectRoot }
  });

  const preview = await controller.handleRequest({
    id: 2,
    method: "bridge.tools.preview",
    params: {}
  }) as { bridgeToolsPreview: boolean; plan: { serverName: string; keyPath: string } };
  assert.equal(preview.bridgeToolsPreview, true);
  assert.equal(preview.plan.serverName, "godot_codex_bridge");
  assert.equal(preview.plan.keyPath, "mcp_servers.godot_codex_bridge");

  const enable = await controller.handleRequest({
    id: 3,
    method: "bridge.tools.enable",
    params: {}
  }) as {
    bridgeToolsEnabled: boolean;
    bridgeToolsReloaded: boolean;
    mcpToolsAvailable: boolean;
    mcpGodotToolCount: number;
  };
  assert.equal(enable.bridgeToolsEnabled, true);
  assert.equal(enable.bridgeToolsReloaded, true);
  assert.equal(enable.mcpToolsAvailable, true);
  assert.equal(enable.mcpGodotToolCount, 4);
});

async function waitFor(predicate: () => boolean): Promise<void> {
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    if (predicate()) {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
  throw new Error("timeout waiting for condition");
}

async function writeAnnotationArtifact(projectRoot: string, annotationId: string): Promise<void> {
  const annotationDir = path.join(projectRoot, ".godot", "godot_codex_bridge", "artifacts", "annotations", annotationId);
  await fs.mkdir(annotationDir, { recursive: true });
  await fs.writeFile(path.join(annotationDir, "raw.png"), Buffer.from([0x89, 0x50, 0x4e, 0x47]));
  await fs.writeFile(path.join(annotationDir, "annotated.png"), Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d]));
  await fs.writeFile(
    path.join(annotationDir, "annotation.json"),
    JSON.stringify({
      annotation_version: "godot-codex-bridge/annotation-v1",
      annotation_id: annotationId,
      annotation_role: "user_reference_marker",
      non_game_overlay: true,
      do_not_recreate_marker_graphics: true,
      instruction: "These marks are user annotations. Do not recreate marker graphics in the game.",
      captured_at: "2026-06-18T12:00:00Z",
      capture_scope: "editor_window",
      current_scene: "res://scenes/main.tscn",
      markers: [
        {
          id: "A",
          type: "rectangle",
          label: "A",
          normalized_bounds: { x: 0.1, y: 0.2, w: 0.3, h: 0.4 },
          pixel_bounds: { x: 10, y: 20, w: 30, h: 40 },
        }
      ],
    }),
    "utf8",
  );
}

async function writeProjectMapFixture(projectRoot: string): Promise<void> {
  await fs.writeFile(
    path.join(projectRoot, "project.godot"),
    [
      "[application]",
      'config/name="Map Fixture"',
      'run/main_scene="res://scenes/main.tscn"',
      "",
      "[autoload]",
      'GameState="*res://scripts/game_state.gd"',
      "",
      "[input]",
      "jump={}",
      "",
    ].join("\n"),
    "utf8",
  );
  await fs.mkdir(path.join(projectRoot, "scenes"), { recursive: true });
  await fs.mkdir(path.join(projectRoot, "scripts"), { recursive: true });
  await fs.mkdir(path.join(projectRoot, "materials"), { recursive: true });
  await fs.mkdir(path.join(projectRoot, "textures"), { recursive: true });
  await fs.mkdir(path.join(projectRoot, "generated"), { recursive: true });
  await fs.mkdir(path.join(projectRoot, "addons", "godot_codex_bridge"), { recursive: true });
  await fs.mkdir(path.join(projectRoot, ".godot"), { recursive: true });
  await fs.writeFile(
    path.join(projectRoot, "scenes", "main.tscn"),
    [
      '[gd_scene load_steps=4 format=3 uid="uid://mapfixture"]',
      "",
      '[ext_resource type="Script" path="res://scripts/player.gd" id="1_player"]',
      '[ext_resource type="PackedScene" path="res://scenes/enemy.tscn" id="2_enemy"]',
      '[ext_resource type="Material" path="res://materials/player_mat.tres" id="3_mat"]',
      "",
      '[node name="Main" type="Node3D"]',
      'script = ExtResource("1_player")',
      "",
      '[node name="Enemy" parent="." instance=ExtResource("2_enemy")]',
      "",
    ].join("\n"),
    "utf8",
  );
  await fs.writeFile(path.join(projectRoot, "scenes", "enemy.tscn"), '[gd_scene]\n[node name="Enemy" type="Node3D"]\n', "utf8");
  await fs.writeFile(
    path.join(projectRoot, "scripts", "player.gd"),
    ["class_name PlayerController", "extends CharacterBody3D", "signal health_changed(value: int)", ""].join("\n"),
    "utf8",
  );
  await fs.writeFile(path.join(projectRoot, "scripts", "game_state.gd"), "class_name GameState\nextends Node\n", "utf8");
  await fs.writeFile(path.join(projectRoot, "materials", "player_mat.tres"), "[gd_resource type=\"StandardMaterial3D\"]\n", "utf8");
  await fs.writeFile(path.join(projectRoot, "textures", "icon.png"), Buffer.from([0x89, 0x50, 0x4e, 0x47]));
  await fs.writeFile(path.join(projectRoot, "textures", "icon.png.import"), "[remap]\n", "utf8");
  await fs.writeFile(path.join(projectRoot, "generated", "cache.gd"), "extends Node\n", "utf8");
  await fs.writeFile(path.join(projectRoot, "addons", "godot_codex_bridge", "plugin.gd"), "extends EditorPlugin\n", "utf8");
  await fs.writeFile(path.join(projectRoot, ".godot", "secret.gd"), "extends Node\n", "utf8");
}
