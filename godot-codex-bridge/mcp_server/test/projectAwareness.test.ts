import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import {
  getAgentsContext,
  getCurrentSourceContext,
  getProjectMap,
  getProjectOverview,
  getProjectSceneGraph,
  getProjectScriptMap,
  getSceneFileTree,
  listProjectFiles,
  readProjectFile,
  searchProjectFiles,
} from "../src/projectAwareness.js";
import type { ToolEnvelope } from "../src/types.js";

test("project overview and file listing expose bounded metadata", async () => {
  const projectRoot = await makeAwarenessFixture();

  const overview = await getProjectOverview(projectRoot);
  assert.equal(overview.status, "ok");
  assert.equal(overview.project_name, "Awareness Fixture");
  assert.equal(overview.main_scene, "res://scenes/main.tscn");
  assert.equal(overview.main_scene_exists, true);

  const summary = overview.file_summary as { by_kind: Record<string, number> };
  assert.equal(summary.by_kind.scene, 2);
  assert.equal(summary.by_kind.script, 3);

  const listed = await listProjectFiles(projectRoot, { kind: "script", limit: 10 });
  assert.equal(listed.status, "ok");
  assert.equal(listed.returned_count, 3);
  const files = listed.files as Array<{ path: string; sha256: string | null }>;
  assert.equal(files.some((file) => file.path === "scripts/player.gd"), true);
  assert.equal(files.every((file) => typeof file.sha256 === "string"), true);

  const allFiles = await listProjectFiles(projectRoot, { limit: 100 });
  const allPaths = (allFiles.files as Array<{ path: string }>).map((file) => file.path);
  assert.ok(!allPaths.some((item) => item.startsWith(".godot/")));
  assert.ok(!allPaths.some((item) => item.startsWith("addons/godot_codex_bridge/")));
});

test("project_get_map aggregates scenes scripts resources autoloads input actions groups and signals", async () => {
  const projectRoot = await makeAwarenessFixture();

  const result = await getProjectMap(projectRoot);

  assert.equal(result.status, "ok");
  assert.equal(result.project_map_version, "godot-codex-bridge/project-map-v1");
  assert.equal(result.project_name, "Awareness Fixture");
  assert.equal(result.main_scene, "res://scenes/main.tscn");
  assert.equal(typeof result.generated_at, "string");

  const scenes = result.scenes as { total: number; items: Array<{ res_path: string; script_paths: string[]; groups: Array<{ name: string }>; node_count: number }> };
  assert.equal(scenes.total, 2);
  assert.equal(scenes.items.some((scene) => scene.res_path === "res://scenes/main.tscn"), true);
  assert.equal(scenes.items.some((scene) => scene.res_path === "res://scenes/enemy.tscn"), true);
  const mainScene = scenes.items.find((scene) => scene.res_path === "res://scenes/main.tscn");
  assert.equal(mainScene?.node_count, 4);
  assert.equal(mainScene?.script_paths.includes("res://scripts/player.gd"), true);
  assert.equal(mainScene?.groups.some((group) => group.name === "players"), true);

  const scripts = result.scripts as { items: Array<{ res_path: string; class_name: string | null; extends: string | null; signals: Array<{ name: string }> }> };
  assert.equal(scripts.items.some((script) => script.res_path === "res://scripts/player.gd" && script.class_name === "PlayerController"), true);
  assert.equal(scripts.items.some((script) => script.res_path === "res://scripts/enemy.gd" && script.class_name === "EnemyController"), true);
  assert.equal(scripts.items.some((script) => script.res_path === "res://scripts/game_state.gd" && script.class_name === "GameState"), true);
  const playerScript = scripts.items.find((script) => script.res_path === "res://scripts/player.gd");
  assert.equal(playerScript?.extends, "CharacterBody3D");
  assert.equal(playerScript?.signals.some((signal) => signal.name === "health_changed"), true);

  const autoloads = result.autoloads as { merged: Array<{ name: string; path?: string }> };
  assert.equal(autoloads.merged.some((autoload) => autoload.name === "GameState" && autoload.path === "res://scripts/game_state.gd"), true);

  const inputActions = result.input_actions as { merged: Array<{ name: string }> };
  assert.equal(inputActions.merged.some((action) => action.name === "jump"), true);
  assert.equal(inputActions.merged.some((action) => action.name === "dash"), true);

  const groups = result.groups as { items: Array<{ name: string }> };
  assert.equal(groups.items.some((group) => group.name === "players"), true);

  const signals = result.signals as { items: Array<{ name: string; script_path: string }> };
  assert.equal(signals.items.some((signal) => signal.name === "health_changed" && signal.script_path === "res://scripts/player.gd"), true);

  const resources = result.resources as { items: Array<{ path: string; is_binary: boolean }> };
  assert.equal(resources.items.some((resource) => resource.path === "textures/icon.png" && resource.is_binary === true), true);

  const allReturnedPaths = JSON.stringify(result);
  assert.equal(allReturnedPaths.includes(".godot/secret.gd"), false);
  assert.equal(allReturnedPaths.includes("addons/godot_codex_bridge/plugin.gd"), false);
  assert.equal(allReturnedPaths.includes("generated/cache.gd"), false);
  assert.equal(allReturnedPaths.includes("icon.png.import"), false);
});

test("project_get_map bounds large sections deterministically", async () => {
  const projectRoot = await makeAwarenessFixture();
  await fs.mkdir(path.join(projectRoot, "scripts", "bulk"), { recursive: true });
  await Promise.all(Array.from({ length: 260 }, (_, index) =>
    fs.writeFile(
      path.join(projectRoot, "scripts", "bulk", `bulk_${String(index).padStart(3, "0")}.gd`),
      [`class_name Bulk${index}`, "extends Node", ""].join("\n"),
      "utf8",
    )
  ));

  const result = await getProjectMap(projectRoot);

  assert.equal(result.status, "ok");
  const scripts = result.scripts as { total: number; returned: number; truncated: boolean; items: Array<{ path: string }> };
  assert.equal(scripts.total, 263);
  assert.equal(scripts.returned, 250);
  assert.equal(scripts.truncated, true);
  assert.equal(scripts.items.length, 250);
  assert.deepEqual(
    scripts.items.slice(0, 3).map((script) => script.path),
    ["scripts/bulk/bulk_000.gd", "scripts/bulk/bulk_001.gd", "scripts/bulk/bulk_002.gd"],
  );
});

test("project_scene_graph maps scene instances scripts resources missing resources and sub resources", async () => {
  const projectRoot = await makeAwarenessFixture();

  const result = await getProjectSceneGraph(projectRoot);

  assert.equal(result.status, "ok");
  assert.equal(result.scene_graph_version, "godot-codex-bridge/project-scene-graph-v1");
  assert.deepEqual(result.scope, { mode: "project", scene_path: null, max_depth: 8 });

  const scenes = result.scenes as { total: number; items: Array<{ res_path: string; instance_scene_paths: string[]; script_paths: string[]; sub_resources: Array<{ id: string; type: string }>; missing_resource_count: number }> };
  assert.equal(scenes.total, 2);
  const mainScene = scenes.items.find((scene) => scene.res_path === "res://scenes/main.tscn");
  assert.ok(mainScene);
  assert.equal(mainScene.instance_scene_paths.includes("res://scenes/enemy.tscn"), true);
  assert.equal(mainScene.script_paths.includes("res://scripts/player.gd"), true);
  assert.equal(mainScene.sub_resources.some((resource) => resource.id === "1_shape" && resource.type === "SphereShape3D"), true);
  assert.equal(mainScene.missing_resource_count, 1);

  const edges = result.edges as { items: Array<{ kind: string; from_scene: string; to: string; via_node_path?: string }> };
  assert.equal(edges.items.some((edge) =>
    edge.kind === "scene_instance" &&
    edge.from_scene === "res://scenes/main.tscn" &&
    edge.to === "res://scenes/enemy.tscn" &&
    edge.via_node_path === "Main/Enemy"
  ), true);
  assert.equal(edges.items.some((edge) =>
    edge.kind === "script_attachment" &&
    edge.from_scene === "res://scenes/enemy.tscn" &&
    edge.to === "res://scripts/enemy.gd"
  ), true);

  const missing = result.missing_resources as { items: Array<{ scene_path: string; path: string; code: string }> };
  assert.deepEqual(missing.items, [{
    scene: "res://scenes/main.tscn",
    scene_path: "res://scenes/main.tscn",
    path: "res://textures/missing.png",
    code: "missing_resource",
    severity: "error",
    message: "Scene references missing project resource res://textures/missing.png.",
  }]);

  const graph = result.graph as { nodes: Array<{ id: string; kind: string; exists: boolean | null }> };
  assert.equal(graph.nodes.some((node) => node.id === "res://scenes/main.tscn" && node.kind === "scene" && node.exists === true), true);
  assert.equal(graph.nodes.some((node) => node.id === "res://textures/missing.png" && node.kind === "resource" && node.exists === false), true);
});

test("project_scene_graph detects scene instance cycles", async () => {
  const projectRoot = await makeAwarenessFixture();
  await fs.writeFile(
    path.join(projectRoot, "scenes", "a.tscn"),
    [
      "[gd_scene format=3]",
      "",
      '[ext_resource type="PackedScene" path="res://scenes/b.tscn" id="1_b"]',
      "",
      '[node name="A" type="Node3D"]',
      "",
      '[node name="B" parent="." instance=ExtResource("1_b")]',
      "",
    ].join("\n"),
    "utf8",
  );
  await fs.writeFile(
    path.join(projectRoot, "scenes", "b.tscn"),
    [
      "[gd_scene format=3]",
      "",
      '[ext_resource type="PackedScene" path="res://scenes/a.tscn" id="1_a"]',
      "",
      '[node name="B" type="Node3D"]',
      "",
      '[node name="A" parent="." instance=ExtResource("1_a")]',
      "",
    ].join("\n"),
    "utf8",
  );

  const result = await getProjectSceneGraph(projectRoot, { scenePath: "res://scenes/a.tscn" });

  assert.equal(result.status, "ok");
  assert.deepEqual(result.scope, { mode: "single_scene", scene_path: "res://scenes/a.tscn", max_depth: 8 });
  const edges = result.edges as { items: Array<{ kind: string; to: string }> };
  assert.equal(edges.items.some((edge) => edge.kind === "scene_instance" && edge.to === "res://scenes/b.tscn"), true);

  const projectResult = await getProjectSceneGraph(projectRoot);
  const cycles = projectResult.cycles as { items: Array<{ kind: string; paths: string[] }> };
  assert.equal(cycles.items.some((cycle) =>
    cycle.kind === "scene_instance_cycle" &&
    cycle.paths.includes("res://scenes/a.tscn") &&
    cycle.paths.includes("res://scenes/b.tscn")
  ), true);
});

test("project_script_map builds classes autoloads scene usages docs and graph", async () => {
  const projectRoot = await makeAwarenessFixture();

  const result = await getProjectScriptMap(projectRoot);

  assert.equal(result.status, "ok");
  assert.equal(result.script_map_version, "godot-codex-bridge/project-script-map-v1");
  assert.deepEqual(result.scope, {
    mode: "project",
    script_path: null,
    include_usages: true,
    include_functions: true,
    include_signals: true,
    include_exports: true,
    include_constants: false,
    max_scripts: 300,
  });

  const scripts = result.scripts as { total: number; items: Array<{ res_path: string; class_name: string | null; used_by_scenes: string[]; used_by_scene_count: number; autoload: { name: string } | null; constants: string[]; scene_usage: Array<{ node_type: string }> }> };
  assert.equal(scripts.total, 3);
  const player = scripts.items.find((script) => script.res_path === "res://scripts/player.gd");
  assert.ok(player);
  assert.equal(player.class_name, "PlayerController");
  assert.equal(player.used_by_scenes.includes("res://scenes/main.tscn"), true);
  assert.equal(player.used_by_scene_count, 1);
  assert.equal(player.scene_usage.some((usage) => usage.node_type === "Node3D"), true);
  assert.deepEqual(player.constants, []);

  const gameState = scripts.items.find((script) => script.res_path === "res://scripts/game_state.gd");
  assert.ok(gameState);
  assert.equal(gameState.autoload?.name, "GameState");

  const classes = result.classes as { items: Array<{ class_name: string; script_path: string }> };
  assert.equal(classes.items.some((item) => item.class_name === "PlayerController" && item.script_path === "res://scripts/player.gd"), true);

  const autoloads = result.autoloads as { total: number; items: Array<{ name: string; path: string; exists: boolean; class_name: string | null }>; missing: unknown[] };
  assert.equal(autoloads.total, 1);
  assert.deepEqual(autoloads.items[0], {
    name: "GameState",
    path: "res://scripts/game_state.gd",
    exists: true,
    singleton: true,
    script_found: true,
    class_name: "GameState",
    extends: "Node",
  });
  assert.deepEqual(autoloads.missing, []);

  const usage = result.scene_usage as { items: Array<{ script_path: string; scene_paths: string[] }> };
  assert.equal(usage.items.some((item) => item.script_path === "res://scripts/enemy.gd" && item.scene_paths.includes("res://scenes/enemy.tscn")), true);

  const docs = result.docs as { agents_root_present: boolean; agents_files: Array<{ preview: string }>; project_docs: Array<{ path: string; preview: string }> };
  assert.equal(docs.agents_root_present, true);
  assert.match(docs.agents_files[0].preview, /ROOT_AGENT_MARKER/);
  assert.equal(docs.project_docs.some((doc) => doc.path === "README.md" && /Fixture readme/.test(doc.preview)), true);
});

test("project_script_map supports focused script and include flags", async () => {
  const projectRoot = await makeAwarenessFixture();

  const result = await getProjectScriptMap(projectRoot, {
    scriptPath: "res://scripts/player.gd",
    includeFunctions: false,
    includeSignals: false,
    includeExports: false,
    includeConstants: true,
  });

  assert.equal(result.status, "ok");
  assert.deepEqual(result.scope, {
    mode: "single_script",
    script_path: "res://scripts/player.gd",
    include_usages: true,
    include_functions: false,
    include_signals: false,
    include_exports: false,
    include_constants: true,
    max_scripts: 300,
  });
  const scripts = result.scripts as { total: number; items: Array<{ res_path: string; class_name: string; functions: unknown[]; signals: unknown[]; exports: unknown[]; constants: string[] }> };
  assert.equal(scripts.total, 1);
  assert.equal(scripts.items[0].res_path, "res://scripts/player.gd");
  assert.equal(scripts.items[0].class_name, "PlayerController");
  assert.deepEqual(scripts.items[0].functions, []);
  assert.deepEqual(scripts.items[0].signals, []);
  assert.deepEqual(scripts.items[0].exports, []);
  assert.deepEqual(scripts.items[0].constants, ["action_ids"]);
});

test("project_script_map detects duplicate classes missing autoloads and bounds scripts", async () => {
  const projectRoot = await makeAwarenessFixture();
  await fs.writeFile(
    path.join(projectRoot, "scripts", "duplicate_player.gd"),
    ["class_name PlayerController", "extends Node", ""].join("\n"),
    "utf8",
  );
  await fs.writeFile(
    path.join(projectRoot, "scripts", "extra_service.gd"),
    ["class_name ExtraService", "extends Node", ""].join("\n"),
    "utf8",
  );
  const projectFile = path.join(projectRoot, "project.godot");
  const projectText = await fs.readFile(projectFile, "utf8");
  await fs.writeFile(
    projectFile,
    projectText.replace('[autoload]\nGameState="*res://scripts/game_state.gd"', '[autoload]\nGameState="*res://scripts/game_state.gd"\nMissingService="*res://scripts/missing.gd"'),
    "utf8",
  );

  const result = await getProjectScriptMap(projectRoot, { maxScripts: 2 });

  assert.equal(result.status, "ok");
  const scripts = result.scripts as { returned: number; truncated: boolean };
  assert.equal(scripts.returned, 2);
  assert.equal(scripts.truncated, true);
  const autoloads = result.autoloads as { missing: Array<{ code: string; path: string }> };
  assert.equal(autoloads.missing.some((item) => item.code === "missing_autoload_script" && item.path === "res://scripts/missing.gd"), true);

  const unbounded = await getProjectScriptMap(projectRoot);
  const classes = unbounded.classes as { duplicate_count: number; duplicates: Array<{ class_name: string; script_paths: string[] }> };
  assert.equal(classes.duplicate_count, 1);
  const duplicate = classes.duplicates.find((item) => item.class_name === "PlayerController");
  assert.ok(duplicate);
  assert.equal(duplicate.script_paths.includes("res://scripts/player.gd"), true);
  assert.equal(duplicate.script_paths.includes("res://scripts/duplicate_player.gd"), true);
});

test("project_script_map rejects unsafe focused script paths", async () => {
  const projectRoot = await makeAwarenessFixture();

  assertInvalid(await getProjectScriptMap(projectRoot, { scriptPath: "C:/outside/player.gd" }), "absolute_path_rejected");
  assertInvalid(await getProjectScriptMap(projectRoot, { scriptPath: "res://../outside.gd" }), "path_traversal_rejected");
  assertInvalid(await getProjectScriptMap(projectRoot, { scriptPath: "res://.godot/cache.gd" }), "generated_path_rejected");
  assertInvalid(await getProjectScriptMap(projectRoot, { scriptPath: "res://addons/godot_codex_bridge/plugin.gd" }), "generated_path_rejected");
  assertInvalid(await getProjectScriptMap(projectRoot, { scriptPath: "res://scenes/main.tscn" }), "not_a_gdscript_file");
});

test("readProjectFile bounds text reads and returns metadata only for binary files", async () => {
  const projectRoot = await makeAwarenessFixture();

  const read = await readProjectFile(projectRoot, {
    path: "res://scripts/player.gd",
    startLine: 4,
    maxLines: 2,
    maxBytes: 200,
  });
  assert.equal(read.status, "ok");
  assert.equal(read.metadata_only, false);
  assert.equal(read.start_line, 4);
  assert.equal(read.lines_returned, 2);
  assert.match(String(read.content), /action_ids/);

  const binary = await readProjectFile(projectRoot, { path: "textures/icon.png" });
  assert.equal(binary.status, "ok");
  assert.equal(binary.metadata_only, true);
  assert.equal(binary.content, null);
  assert.equal((binary.file as { is_binary: boolean }).is_binary, true);
});

test("readProjectFile rejects absolute, traversal, and generated paths", async () => {
  const projectRoot = await makeAwarenessFixture();

  const absolute = await readProjectFile(projectRoot, { path: path.join(projectRoot, "scripts", "player.gd") });
  assertInvalid(absolute, "absolute_path_rejected");

  const traversal = await readProjectFile(projectRoot, { path: "../outside.gd" });
  assertInvalid(traversal, "path_traversal_rejected");

  const generated = await readProjectFile(projectRoot, { path: ".godot/secret.gd" });
  assertInvalid(generated, "generated_path_rejected");

  const bridgeAddon = await readProjectFile(projectRoot, { path: "addons/godot_codex_bridge/plugin.gd" });
  assertInvalid(bridgeAddon, "generated_path_rejected");
});

test("searchProjectFiles finds text matches with context and skips generated files", async () => {
  const previous = process.env.GODOT_CODEX_BRIDGE_DISABLE_RG;
  process.env.GODOT_CODEX_BRIDGE_DISABLE_RG = "1";
  try {
    const projectRoot = await makeAwarenessFixture();
    const result = await searchProjectFiles(projectRoot, {
      query: "const action_ids",
      globs: ["*.gd"],
      contextLines: 1,
      limit: 5,
    });

    assert.equal(result.status, "ok");
    assert.equal(result.search_engine, "node_fallback");
    assert.equal(result.returned_count, 1);
    const matches = result.matches as Array<{ path: string; line: number; context_before: unknown[] }>;
    assert.equal(matches[0].path, "scripts/player.gd");
    assert.equal(matches[0].line, 5);
    assert.equal(matches[0].context_before.length, 1);
  } finally {
    if (previous === undefined) {
      delete process.env.GODOT_CODEX_BRIDGE_DISABLE_RG;
    } else {
      process.env.GODOT_CODEX_BRIDGE_DISABLE_RG = previous;
    }
  }
});

test("getAgentsContext returns root-bounded AGENTS previews", async () => {
  const projectRoot = await makeAwarenessFixture();

  const result = await getAgentsContext(projectRoot);
  assert.equal(result.status, "ok");
  assert.equal(result.root_agents_present, true);
  assert.equal(result.root_agents_missing, false);
  assert.equal(result.files_count, 2);

  const files = result.files as Array<{ path: string; precedence: number; preview: string; sha256: string }>;
  assert.deepEqual(files.map((file) => file.path), ["AGENTS.md", "scenes/AGENTS.md"]);
  assert.equal(files[0].precedence, 1);
  assert.match(files[0].preview, /ROOT_AGENT_MARKER/);
  assert.equal(typeof files[0].sha256, "string");
});

test("getSceneFileTree parses a text .tscn node/resource tree", async () => {
  const projectRoot = await makeAwarenessFixture();

  const result = await getSceneFileTree(projectRoot, { scenePath: "res://scenes/main.tscn" });

  assert.equal(result.status, "ok");
  assert.equal(result.scene_path, "scenes/main.tscn");
  assert.equal(result.node_count, 4);
  const nodes = result.nodes as Array<{ name: string; scene_path: string; script_path: string | null }>;
  assert.equal(nodes[0].name, "Main");
  assert.equal(nodes[0].script_path, "res://scripts/player.gd");
  assert.equal(nodes[2].scene_path, "Main/Player/Camera3D");
  const resources = result.external_resources as Array<{ path: string }>;
  assert.equal(resources[0].path, "res://scripts/player.gd");
});

test("getCurrentSourceContext combines snapshot, scene, and bounded script preview", async () => {
  const projectRoot = await makeAwarenessFixture();
  const snapshotEnvelope: ToolEnvelope = {
    status: "ok",
    snapshot: {
      current_scene: { path: "res://scenes/main.tscn" },
      selected_nodes: [{ node: { path: "/root/Main/Player", script_path: "res://scripts/player.gd" } }],
      gameplay_context: {
        input_actions: [{ name: "jump" }],
        autoloads: [{ name: "GameState", path: "res://scripts/game_state.gd" }],
      },
    },
  };

  const result = await getCurrentSourceContext(projectRoot, { snapshotEnvelope });

  assert.equal(result.status, "ok");
  assert.equal(result.current_scene_path, "res://scenes/main.tscn");
  assert.deepEqual(result.script_paths, ["res://scripts/player.gd"]);
  const previews = result.script_previews as Array<{ path: string; content: string }>;
  assert.equal(previews[0].path, "res://scripts/player.gd");
  assert.match(previews[0].content, /action_ids/);
});

async function makeAwarenessFixture(): Promise<string> {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-awareness-"));
  await fs.mkdir(path.join(projectRoot, "scripts"), { recursive: true });
  await fs.mkdir(path.join(projectRoot, "scenes"), { recursive: true });
  await fs.mkdir(path.join(projectRoot, "generated"), { recursive: true });
  await fs.mkdir(path.join(projectRoot, "textures"), { recursive: true });
  await fs.mkdir(path.join(projectRoot, ".godot"), { recursive: true });
  await fs.mkdir(path.join(projectRoot, "addons", "godot_codex_bridge"), { recursive: true });

  await fs.writeFile(
    path.join(projectRoot, "project.godot"),
    [
      "[application]",
      'config/name="Awareness Fixture"',
      'run/main_scene="res://scenes/main.tscn"',
      "",
      "[autoload]",
      'GameState="*res://scripts/game_state.gd"',
      "",
      "[input]",
      'jump={"deadzone":0.5,"events":[]}',
      'dash={"deadzone":0.5,"events":[]}',
      "",
    ].join("\n"),
    "utf8",
  );
  await fs.writeFile(path.join(projectRoot, "AGENTS.md"), "# Fixture\nROOT_AGENT_MARKER\n", "utf8");
  await fs.writeFile(path.join(projectRoot, "README.md"), "# Fixture readme\nProject docs preview marker.\n", "utf8");
  await fs.writeFile(path.join(projectRoot, "scenes", "AGENTS.md"), "# Scene Scope\nSCENE_AGENT_MARKER\n", "utf8");
  await fs.writeFile(
    path.join(projectRoot, "scripts", "player.gd"),
    [
      "class_name PlayerController",
      "extends CharacterBody3D",
      "signal health_changed(value: int)",
      "@export var speed := 5.0",
      "const action_ids := [\"jump\", \"dash\"]",
      "",
      "func _ready() -> void:",
      "\tprint(action_ids)",
      "",
    ].join("\n"),
    "utf8",
  );
  await fs.writeFile(
    path.join(projectRoot, "scripts", "enemy.gd"),
    [
      "class_name EnemyController",
      "extends CharacterBody3D",
      "",
      "func patrol() -> void:",
      "\tpass",
      "",
    ].join("\n"),
    "utf8",
  );
  await fs.writeFile(
    path.join(projectRoot, "scripts", "game_state.gd"),
    [
      "class_name GameState",
      "extends Node",
      "",
    ].join("\n"),
    "utf8",
  );
  await fs.writeFile(
    path.join(projectRoot, "scenes", "main.tscn"),
    [
      '[gd_scene load_steps=5 format=3 uid="uid://fixture"]',
      "",
      '[ext_resource type="Script" path="res://scripts/player.gd" id="1_player"]',
      '[ext_resource type="PackedScene" path="res://scenes/enemy.tscn" id="2_enemy"]',
      '[ext_resource type="Texture2D" path="res://textures/missing.png" id="3_missing"]',
      "",
      '[sub_resource type="SphereShape3D" id="1_shape"]',
      "",
      '[node name="Main" type="Node3D"]',
      'script = ExtResource("1_player")',
      "",
      '[node name="Player" type="CharacterBody3D" parent="." groups=["players"]]',
      "",
      '[node name="Camera3D" type="Camera3D" parent="Player"]',
      "current = true",
      "",
      '[node name="Enemy" parent="." instance=ExtResource("2_enemy")]',
      "",
    ].join("\n"),
    "utf8",
  );
  await fs.writeFile(
    path.join(projectRoot, "scenes", "enemy.tscn"),
    [
      '[gd_scene load_steps=2 format=3 uid="uid://enemy"]',
      "",
      '[ext_resource type="Script" path="res://scripts/enemy.gd" id="1_enemy"]',
      "",
      '[node name="Enemy" type="CharacterBody3D"]',
      'script = ExtResource("1_enemy")',
      "",
    ].join("\n"),
    "utf8",
  );
  await fs.writeFile(path.join(projectRoot, "textures", "icon.png"), Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x00]));
  await fs.writeFile(path.join(projectRoot, "textures", "icon.png.import"), "[remap]\n", "utf8");
  await fs.writeFile(path.join(projectRoot, ".godot", "secret.gd"), "extends Node\n", "utf8");
  await fs.writeFile(path.join(projectRoot, "addons", "godot_codex_bridge", "plugin.gd"), "extends EditorPlugin\n", "utf8");
  await fs.writeFile(path.join(projectRoot, "generated", "cache.gd"), "extends Node\n", "utf8");

  return projectRoot;
}

function assertInvalid(result: ToolEnvelope, code: string): void {
  assert.equal(result.status, "invalid_request");
  assert.equal((result.error as { code: string }).code, code);
}
