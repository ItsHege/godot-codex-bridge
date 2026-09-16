import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { createGodotCodexBridgeServer } from "../src/server.js";
import { createToolHandlers } from "../src/tools.js";
import type { ServerConfig } from "../src/types.js";

const ONE_BY_ONE_PNG = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=",
  "base64",
);

test("createGodotCodexBridgeServer registers without throwing", async () => {
  const config = await makeConfig();
  const server = createGodotCodexBridgeServer(config);

  assert.equal(server.isConnected(), false);
});

test("tool handlers expose snapshot fields with structured content", async () => {
  const config = await makeConfig();
  await fs.mkdir(config.bridgeDir, { recursive: true });
  await fs.writeFile(
    path.join(config.bridgeDir, "context_snapshot.json"),
    JSON.stringify({
      protocol_version: "0.1",
      generated_at: "2026-06-13T00:00:00.000Z",
      project: { name: "Fixture" },
      current_scene: { path: "res://scenes/main.tscn" },
      gameplay_context: { input_actions: [{ name: "jump" }], autoloads: [] },
      script_inventory: { scripts: [{ path: "res://player.gd", extends: "CharacterBody3D" }] },
    }),
    "utf8",
  );

  const handlers = createToolHandlers(config);
  const result = await handlers["godot.get_current_scene"]();

  assert.equal(result.isError, false);
  assert.equal(result.structuredContent?.status, "ok");
  assert.deepEqual(result.structuredContent?.current_scene, { path: "res://scenes/main.tscn" });

  const gameplay = await handlers["godot.get_gameplay_context"]();
  assert.equal(gameplay.isError, false);
  assert.deepEqual(gameplay.structuredContent?.gameplay_context, { input_actions: [{ name: "jump" }], autoloads: [] });

  const scripts = await handlers["godot.get_script_inventory"]();
  assert.equal(scripts.isError, false);
  assert.deepEqual(scripts.structuredContent?.script_inventory, { scripts: [{ path: "res://player.gd", extends: "CharacterBody3D" }] });
});

test("annotation tools read local marker artifacts and reject traversal", async () => {
  const config = await makeConfig();
  const annotationDir = path.join(config.bridgeDir, "artifacts", "annotations", "annotation_test_001");
  await fs.mkdir(annotationDir, { recursive: true });
  await fs.writeFile(path.join(annotationDir, "raw.png"), Buffer.from([0x89, 0x50, 0x4e, 0x47]));
  await fs.writeFile(path.join(annotationDir, "annotated.png"), Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d]));
  await fs.writeFile(
    path.join(annotationDir, "annotation.json"),
    JSON.stringify({
      annotation_version: "godot-codex-bridge/annotation-v1",
      annotation_id: "annotation_test_001",
      annotation_role: "user_reference_marker",
      non_game_overlay: true,
      do_not_recreate_marker_graphics: true,
      captured_at: "2026-06-18T12:00:00Z",
      capture_scope: "editor_window",
      current_scene: { path: "res://scenes/main.tscn", name: "Main" },
      selected_nodes: [{ path: "Player", name: "Player", type: "CharacterBody3D" }],
      markers: [{ id: "A", type: "rectangle", label: "A", normalized_bounds: { x: 0.1, y: 0.2, w: 0.3, h: 0.4 } }],
    }),
    "utf8",
  );

  const handlers = createToolHandlers(config);
  const listed = await handlers["godot.list_annotations"]({ limit: 5 });
  assert.equal(listed.isError, false);
  assert.equal(listed.structuredContent?.status, "ok");
  assert.equal(listed.structuredContent?.returned_count, 1);

  const latest = await handlers["godot.get_latest_annotation"]();
  assert.equal(latest.isError, false);
  assert.equal(latest.structuredContent?.annotation_id, "annotation_test_001");
  assert.equal(latest.structuredContent?.marker_count, 1);

  const resolved = await handlers["godot.resolve_annotation_target"]({ annotationId: "annotation_test_001", markerId: "A" });
  assert.equal(resolved.isError, false);
  assert.equal(resolved.structuredContent?.target_resolution_version, "godot-codex-bridge/annotation-target-v1");
  assert.equal(resolved.structuredContent?.world_ray_supported, false);
  assert.equal((resolved.structuredContent?.marker as { normalized_center?: { x?: number; y?: number } })?.normalized_center?.x, 0.25);
  const candidates = resolved.structuredContent?.candidates as Array<{ target_kind?: string; node_path?: string; scene_path?: string }> | undefined;
  assert.equal(candidates?.some((candidate) => candidate.target_kind === "selected_node_context" && candidate.node_path === "Player"), true);
  assert.equal(candidates?.some((candidate) => candidate.target_kind === "current_scene_context" && candidate.scene_path === "res://scenes/main.tscn"), true);
  assert.match(String(resolved.structuredContent?.overclaim_guardrail), /does not claim/);

  const traversal = await handlers["godot.get_annotation"]({ annotationId: "../outside" });
  assert.equal(traversal.isError, true);
  assert.equal((traversal.structuredContent?.error as { code?: string })?.code, "invalid_annotation_id");
});

test("tool handlers expose bridge status", async () => {
  const config = await makeConfig();
  const handlers = createToolHandlers(config);

  const result = await handlers["godot.bridge_status"]();

  assert.equal(result.isError, false);
  assert.equal(result.structuredContent?.status, "ok");
  assert.equal(result.structuredContent?.readiness, "wrong_project_root");
  assert.equal(typeof result.structuredContent?.project_root, "string");
});

test("tool handlers expose editor capability limitations", async () => {
  const config = await makeConfig();
  await fs.mkdir(config.bridgeDir, { recursive: true });
  await fs.writeFile(
    path.join(config.bridgeDir, "context_snapshot.json"),
    JSON.stringify({
      protocol_version: "godot-codex-bridge/0.1",
      generated_at: "2026-06-24T13:30:00.000Z",
      editor_state: {
        capabilities: {
          actions: ["focus_panel", "open_scene"],
          focusable_native_panels: ["Output", "Debugger", "FileSystem"],
          screenshot_only_native_panels: ["Output", "Debugger"],
          native_output_read_supported: false,
          native_debugger_read_supported: false,
        },
      },
    }),
    "utf8",
  );
  const handlers = createToolHandlers(config);

  const result = await handlers["godot.editor_capabilities"]();

  assert.equal(result.isError, false);
  assert.equal(result.structuredContent?.status, "ok");
  assert.equal(result.structuredContent?.capabilities_version, "godot-codex-bridge/editor-capabilities-v1");
  assert.equal((result.structuredContent?.screenshot_only as { panels?: string[] }).panels?.includes("Output"), true);
  assert.equal((result.structuredContent?.can_clear as { native_output_panel?: boolean }).native_output_panel, false);
});

test("tool handlers expose bounded performance snapshot", async () => {
  const config = await makeConfig();
  await fs.mkdir(config.bridgeDir, { recursive: true });
  await fs.writeFile(
    path.join(config.bridgeDir, "context_snapshot.json"),
    JSON.stringify({
      protocol_version: "godot-codex-bridge/0.1",
      generated_at: "2026-06-24T14:10:00.000Z",
      current_scene: { path: "res://scenes/main.tscn" },
      scene_tree: { node_count: 9, truncated: false },
      performance: {
        captured_at: "2026-06-24T14:10:00.000Z",
        source: "godot_performance_monitor",
        status: "available",
        sample_interval_seconds: 1,
        monitors: {
          render_total_draw_calls_in_frame: 42,
          render_total_objects_in_frame: 12,
          render_total_primitives_in_frame: 300,
          physics_3d_active_objects: 4,
          physics_3d_collision_pairs: 8,
          physics_3d_island_count: 1,
          navigation_active_maps: 1,
          navigation_region_count: 2,
          navigation_agent_count: 3,
        },
        samples: [
          { captured_at: "2026-06-24T14:09:59.000Z", monitors: { render_total_draw_calls_in_frame: 40 } },
          { captured_at: "2026-06-24T14:10:00.000Z", monitors: { render_total_draw_calls_in_frame: 42 } },
        ],
      },
    }),
    "utf8",
  );
  const handlers = createToolHandlers(config);

  const result = await handlers["godot.performance_get_snapshot"]({ maxSamples: 1 });

  assert.equal(result.isError, false);
  assert.equal(result.structuredContent?.status, "ok");
  assert.equal(result.structuredContent?.performance_snapshot_version, "godot-codex-bridge/performance-snapshot-v1");
  assert.equal(((result.structuredContent?.rendering as Record<string, { value?: number }>).draw_calls).value, 42);
  assert.equal((result.structuredContent?.timeline as { sample_count?: number }).sample_count, 1);
  assert.equal((result.structuredContent?.memory as { status?: string }).status, "unavailable");
});

test("tool handlers expose runtime probe state", async () => {
  const config = await makeConfig();
  const runtimeDir = path.join(config.bridgeDir, "runtime");
  await fs.mkdir(runtimeDir, { recursive: true });
  await fs.writeFile(
    path.join(runtimeDir, "state.json"),
    JSON.stringify({
      runtime_state_version: "godot-codex-bridge/runtime-state-v1",
      generated_at: "2026-06-23T12:00:00.000Z",
      tree: { current_scene: "/root/Main" },
    }),
    "utf8",
  );
  const handlers = createToolHandlers(config);

  const result = await handlers["godot.runtime_get_state"]({ maxAgeMs: 60_000 });

  assert.equal(result.isError, false);
  assert.equal(result.structuredContent?.status, "ok");
  assert.equal(result.structuredContent?.runtime_state_version, "godot-codex-bridge/runtime-state-v1");
  assert.equal((result.structuredContent?.state as { tree?: { current_scene?: string } })?.tree?.current_scene, "/root/Main");
});

test("tool handlers expose runtime probe events", async () => {
  const config = await makeConfig();
  const runtimeDir = path.join(config.bridgeDir, "runtime");
  await fs.mkdir(runtimeDir, { recursive: true });
  await fs.writeFile(
    path.join(runtimeDir, "events.json"),
    JSON.stringify({
      runtime_events_version: "godot-codex-bridge/runtime-events-v1",
      generated_at: "2026-06-24T13:00:00.000Z",
      events: [{ id: "event-1", type: "scene_changed", payload: { current_scene: "/root/Main" } }],
    }),
    "utf8",
  );
  const handlers = createToolHandlers(config);

  const result = await handlers["godot.runtime_get_events"]({ maxAgeMs: 60_000 });

  assert.equal(result.isError, false);
  assert.equal(result.structuredContent?.status, "ok");
  assert.equal(result.structuredContent?.runtime_events_version, "godot-codex-bridge/runtime-events-v1");
  const document = result.structuredContent?.events as { events?: Array<{ type?: string }> };
  assert.equal(document.events?.[0]?.type, "scene_changed");
});

test("tool handlers expose project awareness tools", async () => {
  const previous = process.env.GODOT_CODEX_BRIDGE_DISABLE_RG;
  process.env.GODOT_CODEX_BRIDGE_DISABLE_RG = "1";
  try {
    const config = await makeConfig();
    await fs.mkdir(path.join(config.projectRoot, "scripts"), { recursive: true });
    await fs.mkdir(path.join(config.projectRoot, "scenes"), { recursive: true });
    await fs.writeFile(
      path.join(config.projectRoot, "project.godot"),
      '[application]\nconfig/name="Tools Awareness"\nrun/main_scene="res://scenes/main.tscn"\n',
      "utf8",
    );
    await fs.writeFile(path.join(config.projectRoot, "AGENTS.md"), "# Tools Awareness\n", "utf8");
    await fs.writeFile(path.join(config.projectRoot, "scripts", "player.gd"), "extends Node\nconst action_ids := []\n", "utf8");
    await fs.writeFile(
      path.join(config.projectRoot, "scenes", "main.tscn"),
      '[gd_scene format=3]\n\n[ext_resource type="Script" path="res://scripts/player.gd" id="1_player"]\n\n[node name="Main" type="Node3D"]\nscript = ExtResource("1_player")\n',
      "utf8",
    );
    await fs.mkdir(config.bridgeDir, { recursive: true });
    await fs.writeFile(
      path.join(config.bridgeDir, "context_snapshot.json"),
      JSON.stringify({
        protocol_version: "godot-codex-bridge/0.1",
        generated_at: "2026-06-14T00:00:00.000Z",
        current_scene: { path: "res://scenes/main.tscn" },
        selected_nodes: [{ node: { script_path: "res://scripts/player.gd" } }],
      }),
      "utf8",
    );

    const handlers = createToolHandlers(config);
    const overview = await handlers["godot.get_project_overview"]();
    assert.equal(overview.isError, false);
    assert.equal(overview.structuredContent?.status, "ok");

    const projectMap = await handlers["godot.project_get_map"]();
    assert.equal(projectMap.isError, false);
    assert.equal(projectMap.structuredContent?.status, "ok");
    assert.equal(projectMap.structuredContent?.project_map_version, "godot-codex-bridge/project-map-v1");
    assert.equal((projectMap.structuredContent?.scenes as { total?: number })?.total, 1);

    const scriptMap = await handlers["godot.project_script_map"]();
    assert.equal(scriptMap.isError, false);
    assert.equal(scriptMap.structuredContent?.status, "ok");
    assert.equal(scriptMap.structuredContent?.script_map_version, "godot-codex-bridge/project-script-map-v1");
    assert.equal((scriptMap.structuredContent?.scripts as { total?: number })?.total, 1);

    const listed = await handlers["godot.list_project_files"]({ kind: "script" });
    assert.equal(listed.isError, false);
    assert.equal(listed.structuredContent?.returned_count, 1);

    const searched = await handlers["godot.search_project_files"]({ query: "action_ids", globs: ["*.gd"] });
    assert.equal(searched.isError, false);
    assert.equal(searched.structuredContent?.returned_count, 1);

    const read = await handlers["godot.read_project_file"]({ path: "scripts/player.gd", maxLines: 1 });
    assert.equal(read.isError, false);
    assert.equal(read.structuredContent?.lines_returned, 1);

    const agents = await handlers["godot.get_agents_context"]();
    assert.equal(agents.isError, false);
    assert.equal(agents.structuredContent?.root_agents_present, true);

    const scene = await handlers["godot.get_scene_file_tree"]();
    assert.equal(scene.isError, false);
    assert.equal(scene.structuredContent?.node_count, 1);

    const currentSource = await handlers["godot.get_current_source_context"]();
    assert.equal(currentSource.isError, false);
    assert.deepEqual(currentSource.structuredContent?.script_paths, ["res://scripts/player.gd"]);
  } finally {
    if (previous === undefined) {
      delete process.env.GODOT_CODEX_BRIDGE_DISABLE_RG;
    } else {
      process.env.GODOT_CODEX_BRIDGE_DISABLE_RG = previous;
    }
  }
});

test("blender asset import planner returns safe follow-up calls for project-local manifest", async () => {
  const config = await makeConfig();
  const importRoot = path.join(config.projectRoot, "assets", "ai_imports", "blender");
  await fs.mkdir(importRoot, { recursive: true });
  await fs.writeFile(path.join(importRoot, "tree.glb"), "glTF fixture", "utf8");
  await fs.writeFile(path.join(importRoot, "tree_preview.png"), "png fixture", "utf8");
  await fs.writeFile(
    path.join(importRoot, "manifest.json"),
    JSON.stringify({
      manifest_version: "test-v1",
      generated_at: "2026-06-23T12:00:00.000Z",
      source: "Blender MCP",
      assets: [
        {
          asset_path: "res://assets/ai_imports/blender/tree.glb",
          name: "TreeAsset",
          position: { x: 1, y: 0, z: 2 },
          scale: { x: 1.5, y: 1.5, z: 1.5 },
        },
        {
          asset_path: "res://assets/ai_imports/blender/tree_preview.png",
          name: "TreePreview",
        },
        {
          asset_path: "res://assets/ai_imports/blender/missing.glb",
          name: "MissingAsset",
        },
        {
          asset_path: "res://assets/models/outside.glb",
        },
      ],
    }),
    "utf8",
  );
  const handlers = createToolHandlers(config);

  const result = await handlers["godot.plan_blender_asset_import"]({
    manifestPath: "res://assets/ai_imports/blender/manifest.json",
  });

  assert.equal(result.isError, false);
  assert.equal(result.structuredContent?.status, "ok");
  assert.equal(result.structuredContent?.allowlist_root, "res://assets/ai_imports/blender");
  assert.equal(result.structuredContent?.accepted_count, 2);
  assert.equal(result.structuredContent?.rejected_count, 2);
  assert.equal(result.structuredContent?.placeable_count, 1);
  const assets = result.structuredContent?.assets as Array<Record<string, unknown>>;
  assert.equal(assets.some((asset) => Object.hasOwn(asset, "absolute_path")), false);
  assert.equal(assets[0].asset_path, "res://assets/ai_imports/blender/tree.glb");
  assert.equal(assets[0].exists, true);
  assert.equal(assets[1].asset_path, "res://assets/ai_imports/blender/missing.glb");
  assert.equal(assets[1].exists, false);
  const rejected = result.structuredContent?.rejected_assets as Array<Record<string, unknown>>;
  assert.equal(rejected.some((asset) => asset.code === "unsupported_blender_asset_extension" && asset.asset_path === "res://assets/ai_imports/blender/tree_preview.png"), true);
  const workflow = result.structuredContent?.suggested_workflow as Array<{ tool: string; args: Record<string, unknown> }>;
  assert.equal(workflow[0].tool, "godot.inspect_imported_assets");
  assert.equal(workflow[0].args.rootPath, "res://assets/ai_imports/blender");
  assert.deepEqual(workflow.slice(1).map((step) => step.tool), ["godot.place_asset_in_scene"]);
  assert.equal(workflow[1].args.assetPath, "res://assets/ai_imports/blender/tree.glb");
  assert.equal(workflow.some((step) => step.tool === "godot.editor_batch" || step.tool === "godot.save_scene"), false);
});

test("blender asset import planner rejects unsafe manifests and oversized JSON", async () => {
  const config = await makeConfig();
  const importRoot = path.join(config.projectRoot, "assets", "ai_imports", "blender");
  await fs.mkdir(importRoot, { recursive: true });
  const handlers = createToolHandlers(config);

  const outside = await handlers["godot.plan_blender_asset_import"]({
    manifestPath: "res://assets/manifest.json",
  });
  assert.equal(outside.isError, true);
  assert.equal((outside.structuredContent?.error as { code?: string })?.code, "invalid_manifest_path");

  const traversal = await handlers["godot.plan_blender_asset_import"]({
    manifestPath: "res://assets/ai_imports/blender/../manifest.json",
  });
  assert.equal(traversal.isError, true);
  assert.equal((traversal.structuredContent?.error as { code?: string })?.code, "invalid_res_path");

  const missing = await handlers["godot.plan_blender_asset_import"]({
    manifestPath: "res://assets/ai_imports/blender/missing.json",
  });
  assert.equal(missing.isError, true);
  assert.equal(missing.structuredContent?.status, "not_found");
  assert.equal((missing.structuredContent?.error as { code?: string })?.code, "blender_import_manifest_unavailable");

  await fs.writeFile(path.join(importRoot, "bad.json"), "{", "utf8");
  const malformed = await handlers["godot.plan_blender_asset_import"]({
    manifestPath: "res://assets/ai_imports/blender/bad.json",
  });
  assert.equal(malformed.isError, true);
  assert.equal((malformed.structuredContent?.error as { code?: string })?.code, "invalid_blender_import_manifest_json");

  await fs.writeFile(path.join(importRoot, "large.json"), JSON.stringify({ assets: [], pad: "x".repeat(260 * 1024) }), "utf8");
  const large = await handlers["godot.plan_blender_asset_import"]({
    manifestPath: "res://assets/ai_imports/blender/large.json",
  });
  assert.equal(large.isError, true);
  assert.equal((large.structuredContent?.error as { code?: string })?.code, "blender_import_manifest_too_large");

  await fs.writeFile(
    path.join(importRoot, "many.json"),
    JSON.stringify({ assets: Array.from({ length: 51 }, (_, index) => ({ asset_path: `res://assets/ai_imports/blender/${index}.glb` })) }),
    "utf8",
  );
  const many = await handlers["godot.plan_blender_asset_import"]({
    manifestPath: "res://assets/ai_imports/blender/many.json",
  });
  assert.equal(many.isError, true);
  assert.equal((many.structuredContent?.error as { code?: string })?.code, "too_many_blender_assets");

  await fs.writeFile(
    path.join(importRoot, "nested-godot.json"),
    JSON.stringify({ assets: [{ asset_path: "res://assets/ai_imports/blender/.godot/generated.glb" }] }),
    "utf8",
  );
  const nestedGodot = await handlers["godot.plan_blender_asset_import"]({
    manifestPath: "res://assets/ai_imports/blender/nested-godot.json",
  });
  assert.equal(nestedGodot.isError, false);
  assert.equal(nestedGodot.structuredContent?.accepted_count, 0);
  assert.equal(nestedGodot.structuredContent?.rejected_count, 1);
  assert.equal(
    (nestedGodot.structuredContent?.rejected_assets as Array<{ code?: string }> | undefined)?.[0]?.code,
    "invalid_res_path",
  );

  await fs.writeFile(
    path.join(importRoot, "nested-import.json"),
    JSON.stringify({ assets: [{ asset_path: "res://assets/ai_imports/blender/nested/.import/generated.glb" }] }),
    "utf8",
  );
  const nestedImport = await handlers["godot.plan_blender_asset_import"]({
    manifestPath: "res://assets/ai_imports/blender/nested-import.json",
  });
  assert.equal(nestedImport.isError, false);
  assert.equal(nestedImport.structuredContent?.accepted_count, 0);
  assert.equal(nestedImport.structuredContent?.rejected_count, 1);
  assert.equal(
    (nestedImport.structuredContent?.rejected_assets as Array<{ code?: string }> | undefined)?.[0]?.code,
    "invalid_res_path",
  );

  await fs.writeFile(
    path.join(importRoot, "unsupported-extension.json"),
    JSON.stringify({ assets: [{ asset_path: "res://assets/ai_imports/blender/tree.txt" }] }),
    "utf8",
  );
  const unsupportedExtension = await handlers["godot.plan_blender_asset_import"]({
    manifestPath: "res://assets/ai_imports/blender/unsupported-extension.json",
  });
  assert.equal(unsupportedExtension.isError, false);
  assert.equal(unsupportedExtension.structuredContent?.accepted_count, 0);
  assert.equal(unsupportedExtension.structuredContent?.rejected_count, 1);
  assert.equal(
    (unsupportedExtension.structuredContent?.rejected_assets as Array<{ code?: string }> | undefined)?.[0]?.code,
    "unsupported_blender_asset_extension",
  );
});

test("tool handlers expose 3D scene diagnostics", async () => {
  const config = await makeConfig();
  await fs.mkdir(config.bridgeDir, { recursive: true });
  await fs.writeFile(
    path.join(config.bridgeDir, "context_snapshot.json"),
    JSON.stringify({
      protocol_version: "godot-codex-bridge/0.1",
      generated_at: "2026-06-13T00:00:00.000Z",
      scene_tree: {
        root: {
          path: "/root/Main",
          name: "Main",
          type: "Node3D",
          three_d: { visible: true },
          children: [],
        },
        node_count: 1,
        truncated: false,
      },
    }),
    "utf8",
  );
  const handlers = createToolHandlers(config);

  const result = await handlers["godot.inspect_3d_scene"]();

  assert.equal(result.isError, false);
  assert.equal(result.structuredContent?.status, "ok");
  assert.equal(result.structuredContent?.diagnostics_version, "godot-codex-bridge/3d-diagnostics-v1");

  const snapshotResult = await handlers["godot.create_diagnostic_snapshot"]({ label: "tools-test" });
  assert.equal(snapshotResult.isError, false);
  assert.equal(snapshotResult.structuredContent?.status, "ok");
  assert.equal(snapshotResult.structuredContent?.contains_source_mutation, false);
});

test("tool handlers expose export readiness and undo snapshot", async () => {
  const config = await makeConfig();
  await fs.writeFile(path.join(config.projectRoot, "project.godot"), "[application]\nconfig/name=\"Fixture\"\n", "utf8");
  await fs.writeFile(path.join(config.projectRoot, "script.gd"), "extends Node\n", "utf8");
  const handlers = createToolHandlers(config);

  const exportResult = await handlers["godot.check_export_readiness"]();
  assert.equal(exportResult.isError, false);
  assert.equal(exportResult.structuredContent?.status, "ok");
  assert.equal(exportResult.structuredContent?.readiness_version, "godot-codex-bridge/export-readiness-v1");

  const snapshotResult = await handlers["godot.create_undo_snapshot"]({
    paths: ["script.gd"],
    label: "tools-test",
  });
  assert.equal(snapshotResult.isError, false);
  assert.equal(snapshotResult.structuredContent?.status, "ok");
  assert.equal(snapshotResult.structuredContent?.file_count, 1);
});

test("tool handlers expose approved apply and scene generation", async () => {
  const config = await makeConfig();
  await fs.mkdir(path.join(config.projectRoot, "scenes"), { recursive: true });
  await fs.writeFile(path.join(config.projectRoot, "script.gd"), "extends Node\n", "utf8");
  const handlers = createToolHandlers(config);

  const rejectedApply = await handlers["godot.apply_approved_diff"]({
    path: "script.gd",
    proposedContent: "extends Node\nfunc _ready(): pass\n",
  });
  assert.equal(rejectedApply.isError, true);
  assert.equal(rejectedApply.structuredContent?.status, "invalid_request");

  const generated = await handlers["godot.generate_scene_from_prompt"]({
    prompt: "small cube room",
    path: "scenes/generated.tscn",
  });
  assert.equal(generated.isError, false);
  assert.equal(generated.structuredContent?.status, "ok");
});

test("open scene handler validates paths before sending addon requests", async () => {
  const config = await makeConfig();
  const handlers = createToolHandlers(config);

  const absolute = await handlers["godot.open_scene"]({ scenePath: path.join(config.projectRoot, "scene.tscn") });
  assert.equal(absolute.isError, true);
  assert.equal(absolute.structuredContent?.status, "invalid_request");
  assert.equal((absolute.structuredContent?.error as { code?: string })?.code, "invalid_scene_path");

  const traversal = await handlers["godot.open_scene"]({ scenePath: "res://../outside.tscn" });
  assert.equal(traversal.isError, true);
  assert.equal((traversal.structuredContent?.error as { code?: string })?.code, "invalid_scene_path");

  const missing = await handlers["godot.open_scene"]({ scenePath: "res://scenes/missing.tscn" });
  assert.equal(missing.isError, true);
  assert.equal((missing.structuredContent?.error as { code?: string })?.code, "scene_not_found");
});

test("open scene handler writes addon request for a valid scene", async () => {
  const config = await makeConfig();
  await fs.mkdir(path.join(config.projectRoot, "scenes"), { recursive: true });
  await fs.writeFile(path.join(config.projectRoot, "project.godot"), "[application]\n", "utf8");
  await fs.writeFile(path.join(config.projectRoot, "scenes", "main.tscn"), "[gd_scene format=3]\n", "utf8");
  await writeLiveHeartbeat(config.bridgeDir);

  const handlers = createToolHandlers(config);
  const pending = handlers["godot.open_scene"]({
    scenePath: "res://scenes/main.tscn",
    makeMainScreen: "3D",
    selectInFileSystem: true,
    timeoutMs: 1_000,
  });

  const requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
  const request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: Record<string, unknown>;
  };
  assert.equal(request.type, "open_scene");
  assert.equal(request.payload.scene_path, "res://scenes/main.tscn");
  assert.equal(request.payload.make_main_screen, "3D");
  assert.equal(request.payload.select_in_file_system, true);

  await fs.mkdir(path.join(config.bridgeDir, "responses"), { recursive: true });
  await fs.writeFile(
    path.join(config.bridgeDir, "responses", `${request.request_id}.json`),
    JSON.stringify({ status: "succeeded", data: { opened_scene: "res://scenes/main.tscn" } }),
    "utf8",
  );

  const result = await pending;
  assert.equal(result.isError, false);
  assert.equal(result.structuredContent?.status, "ok");
});

test("run current scene handler accepts an optional explicit scene path", async () => {
  const config = await makeConfig();
  await fs.mkdir(path.join(config.projectRoot, "scenes"), { recursive: true });
  await fs.writeFile(path.join(config.projectRoot, "project.godot"), "[application]\n", "utf8");
  await fs.writeFile(path.join(config.projectRoot, "scenes", "playtest.tscn"), "[gd_scene format=3]\n", "utf8");
  await writeLiveHeartbeat(config.bridgeDir);

  const handlers = createToolHandlers(config);
  const pending = handlers["godot.run_current_scene"]({
    scenePath: "res://scenes/playtest.tscn",
    timeoutMs: 1_000,
  });

  const requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
  const request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: Record<string, unknown>;
  };
  assert.equal(request.type, "run_current_scene");
  assert.equal(request.payload.scene_path, "res://scenes/playtest.tscn");

  await fs.mkdir(path.join(config.bridgeDir, "responses"), { recursive: true });
  await fs.writeFile(
    path.join(config.bridgeDir, "responses", `${request.request_id}.json`),
    JSON.stringify({ status: "succeeded", data: { scene_file_path: "res://scenes/playtest.tscn" } }),
    "utf8",
  );

  const result = await pending;
  assert.equal(result.isError, false);
  assert.equal(result.structuredContent?.status, "ok");
});

test("run current scene handler rejects invalid explicit scene paths", async () => {
  const config = await makeConfig();
  const handlers = createToolHandlers(config);

  const traversal = await handlers["godot.run_current_scene"]({ scenePath: "res://../outside.tscn" });
  assert.equal(traversal.isError, true);
  assert.equal((traversal.structuredContent?.error as { code?: string })?.code, "invalid_scene_path");

  const missing = await handlers["godot.run_current_scene"]({ scenePath: "res://scenes/missing.tscn" });
  assert.equal(missing.isError, true);
  assert.equal((missing.structuredContent?.error as { code?: string })?.code, "scene_not_found");
});

test("timeline screenshot handler captures multiple frames and writes a local manifest", async () => {
  const config = await makeConfig();
  await writeLiveHeartbeat(config.bridgeDir);
  const handlers = createToolHandlers(config);
  const requestsDir = path.join(config.bridgeDir, "requests");

  const pending = handlers["godot.capture_timeline_screenshots"]({
    frameCount: 2,
    intervalMs: 50,
    timeoutMs: 1_000,
    reason: "animation preview",
  });

  const firstRequestPath = await waitForRequest(requestsDir);
  const firstRequest = JSON.parse(await fs.readFile(firstRequestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: Record<string, unknown>;
  };
  assert.equal(firstRequest.type, "capture_viewport_screenshot");
  assert.equal(firstRequest.payload.requested_by, "mcp_server");
  assert.match(String(firstRequest.payload.reason), /^timeline:timeline_/);
  assert.match(String(firstRequest.payload.reason), /:frame:1:animation preview$/);
  await writeAddonResponse(config.bridgeDir, firstRequest.request_id, {
    status: "succeeded",
    data: { screenshot: screenshotFixture(1) },
  });

  const secondRequestPath = await waitForNewestRequest(requestsDir, firstRequest.request_id);
  const secondRequest = JSON.parse(await fs.readFile(secondRequestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: Record<string, unknown>;
  };
  assert.equal(secondRequest.type, "capture_viewport_screenshot");
  assert.match(String(secondRequest.payload.reason), /:frame:2:animation preview$/);
  await writeAddonResponse(config.bridgeDir, secondRequest.request_id, {
    status: "succeeded",
    data: { screenshot: screenshotFixture(2) },
  });

  const result = await pending;
  assert.equal(result.isError, false);
  assert.equal(result.structuredContent?.status, "ok");
  assert.equal(result.structuredContent?.timeline_capture_version, "godot-codex-bridge/timeline-capture-v1");
  assert.equal(result.structuredContent?.capture_status, "completed");
  assert.equal(result.structuredContent?.frame_count_succeeded, 2);
  const manifestPath = String(result.structuredContent?.manifest_path);
  const manifest = JSON.parse(await fs.readFile(manifestPath, "utf8")) as Record<string, unknown>;
  assert.equal(manifest.capture_status, "completed");
  assert.equal(Array.isArray(manifest.frames), true);
});

test("timeline screenshot handler can compare captured frames to a visual baseline", async () => {
  const config = await makeConfig();
  await writeLiveHeartbeat(config.bridgeDir);
  await fs.mkdir(config.bridgeDir, { recursive: true });
  const baselinePath = path.join(config.projectRoot, "baseline.png");
  const frameOnePath = path.join(config.projectRoot, "frame-one.png");
  const frameTwoPath = path.join(config.projectRoot, "frame-two.png");
  await fs.writeFile(baselinePath, ONE_BY_ONE_PNG);
  await fs.writeFile(frameOnePath, ONE_BY_ONE_PNG);
  await fs.writeFile(frameTwoPath, ONE_BY_ONE_PNG);

  const handlers = createToolHandlers(config);
  const baseline = await handlers["godot.create_visual_baseline"]({
    screenshotPath: baselinePath,
    baselineName: "timeline-main",
  });
  assert.equal(baseline.isError, false);

  const requestsDir = path.join(config.bridgeDir, "requests");
  const pending = handlers["godot.capture_timeline_screenshots"]({
    frameCount: 2,
    intervalMs: 50,
    timeoutMs: 1_000,
    baselineName: "timeline-main",
  });

  const firstRequestPath = await waitForRequest(requestsDir);
  const firstRequest = JSON.parse(await fs.readFile(firstRequestPath, "utf8")) as {
    request_id: string;
  };
  await writeAddonResponse(config.bridgeDir, firstRequest.request_id, {
    status: "succeeded",
    data: { screenshot: screenshotFixture(1, frameOnePath) },
  });

  const secondRequestPath = await waitForNewestRequest(requestsDir, firstRequest.request_id);
  const secondRequest = JSON.parse(await fs.readFile(secondRequestPath, "utf8")) as {
    request_id: string;
  };
  await writeAddonResponse(config.bridgeDir, secondRequest.request_id, {
    status: "succeeded",
    data: { screenshot: screenshotFixture(2, frameTwoPath) },
  });

  const result = await pending;
  assert.equal(result.isError, false);
  const comparison = result.structuredContent?.baseline_comparison as {
    status?: string;
    frame_count_compared?: number;
    exact_match_count?: number;
    changed_frame_count?: number;
    comparisons?: Array<{ status?: string; exact_match?: boolean; result_path?: string }>;
  };
  assert.equal(comparison.status, "ok");
  assert.equal(comparison.frame_count_compared, 2);
  assert.equal(comparison.exact_match_count, 2);
  assert.equal(comparison.changed_frame_count, 0);
  assert.equal(comparison.comparisons?.length, 2);
  assert.equal(comparison.comparisons?.every((item) => item.status === "ok" && item.exact_match === true), true);

  const manifestPath = String(result.structuredContent?.manifest_path);
  const manifest = JSON.parse(await fs.readFile(manifestPath, "utf8")) as {
    baseline_comparison?: { status?: string; frame_count_compared?: number };
  };
  assert.equal(manifest.baseline_comparison?.status, "ok");
  assert.equal(manifest.baseline_comparison?.frame_count_compared, 2);
});

test("timeline screenshot handler validates bounds before sending requests", async () => {
  const config = await makeConfig();
  const handlers = createToolHandlers(config);

  const result = await handlers["godot.capture_timeline_screenshots"]({
    frameCount: 1,
  });

  assert.equal(result.isError, true);
  assert.equal((result.structuredContent?.error as { code?: string })?.code, "invalid_timeline_frame_count");
});

test("multi-view screenshot handler writes editor_control request and can compare frames", async () => {
  const config = await makeConfig();
  await writeLiveHeartbeat(config.bridgeDir);
  await fs.mkdir(config.bridgeDir, { recursive: true });
  const baselinePath = path.join(config.projectRoot, "baseline.png");
  const frontPath = path.join(config.projectRoot, "front.png");
  const topPath = path.join(config.projectRoot, "top.png");
  await fs.writeFile(baselinePath, ONE_BY_ONE_PNG);
  await fs.writeFile(frontPath, ONE_BY_ONE_PNG);
  await fs.writeFile(topPath, ONE_BY_ONE_PNG);

  const handlers = createToolHandlers(config);
  const baseline = await handlers["godot.create_visual_baseline"]({
    screenshotPath: baselinePath,
    baselineName: "multi-view-house",
  });
  assert.equal(baseline.isError, false);

  const pending = handlers["godot.capture_multi_view_screenshots"]({
    nodePath: "City/House",
    selectedOnly: true,
    views: ["front", "top", "front"],
    width: 640,
    height: 480,
    maxNodes: 12,
    baselineName: "multi-view-house",
    timeoutMs: 1_000,
  });

  const requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
  const request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.type, "editor_control");
  assert.equal(request.payload.action, "capture_multi_view");
  assert.equal(request.payload.params?.node_path, "City/House");
  assert.equal(request.payload.params?.selected_only, false);
  assert.equal(request.payload.params?.width, 640);
  assert.equal(request.payload.params?.height, 480);
  assert.equal(request.payload.params?.max_nodes, 12);
  assert.deepEqual(request.payload.params?.views, ["front", "top"]);

  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: {
      action: "capture_multi_view",
      status: "ok",
      frames: [
        { view: "front", status: "ok", artifact: { local_path: frontPath, format: "png" } },
        { view: "top", status: "ok", artifact: { local_path: topPath, format: "png" } },
      ],
    },
  });
  await fs.rm(requestPath);

  const result = await pending;
  assert.equal(result.isError, false);
  const transportAttempts = result.structuredContent?.transport_attempts as Array<{ transport?: string; status?: string; reason?: string }>;
  assert.equal(
    transportAttempts?.some((attempt) => attempt.transport === "websocket_rpc" && attempt.status === "skipped" && attempt.reason === "file_polling_required"),
    true,
  );
  const comparison = result.structuredContent?.baseline_comparison as {
    status?: string;
    compared_frames?: number;
    comparisons?: Array<{ result?: { status?: string; exact_match?: boolean } }>;
  };
  assert.equal(comparison.status, "ok");
  assert.equal(comparison.compared_frames, 2);
  assert.equal(comparison.comparisons?.every((item) => item.result?.status === "ok" && item.result?.exact_match === true), true);

  const invalidView = await handlers["godot.capture_multi_view_screenshots"]({ views: ["front", "diagonal"] });
  assert.equal(invalidView.isError, true);
  assert.equal((invalidView.structuredContent?.error as { code?: string })?.code, "invalid_multi_view_views");

  const invalidSelector = await handlers["godot.capture_multi_view_screenshots"]({ nodePath: "House", groupName: "buildings" });
  assert.equal(invalidSelector.isError, true);
  assert.equal((invalidSelector.structuredContent?.error as { code?: string })?.code, "invalid_spatial_selector");
});

test("editor get state writes editor_control request", async () => {
  const config = await makeConfig();
  await writeLiveHeartbeat(config.bridgeDir);
  const handlers = createToolHandlers(config);

  const pending = handlers["godot.editor_get_state"]({ timeoutMs: 1_000 });
  const requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
  const request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: Record<string, unknown>;
  };
  assert.equal(request.type, "editor_control");
  assert.equal(request.payload.action, "get_state");

  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "get_state", editor_state: { capabilities: { version: "editor-control-v1" } } },
  });

  const result = await pending;
  assert.equal(result.isError, false);
  assert.equal(result.structuredContent?.status, "ok");
});

test("editor focus validates file path and writes editor_control request", async () => {
  const config = await makeConfig();
  await fs.mkdir(path.join(config.projectRoot, "scenes"), { recursive: true });
  await fs.writeFile(path.join(config.projectRoot, "scenes", "main.tscn"), "[gd_scene format=3]\n", "utf8");
  await writeLiveHeartbeat(config.bridgeDir);
  const handlers = createToolHandlers(config);

  const invalidScreen = await handlers["godot.editor_focus"]({ mainScreen: "Output" });
  assert.equal(invalidScreen.isError, true);
  assert.equal((invalidScreen.structuredContent?.error as { code?: string })?.code, "invalid_main_screen");

  const pending = handlers["godot.editor_focus"]({
    mainScreen: "3D",
    selectFile: "res://scenes/main.tscn",
    timeoutMs: 1_000,
  });
  const requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
  const request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.type, "editor_control");
  assert.equal(request.payload.action, "focus_editor");
  assert.equal(request.payload.params?.main_screen, "3D");
  assert.equal(request.payload.params?.select_file, "res://scenes/main.tscn");

  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "focus_editor", main_screen: "3D" },
  });
  const result = await pending;
  assert.equal(result.isError, false);
});

test("get inspector context writes editor_control request", async () => {
  const config = await makeConfig();
  await writeLiveHeartbeat(config.bridgeDir);
  const handlers = createToolHandlers(config);

  const pending = handlers["godot.get_inspector_context"]({ timeoutMs: 1_000 });
  const requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
  const request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.type, "editor_control");
  assert.equal(request.payload.action, "get_inspector_context");
  assert.deepEqual(request.payload.params, {});

  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: {
      action: "get_inspector_context",
      inspector: {
        selected_path: "transform/position",
        visible_categories_supported: false,
      },
      edited_object: { available: true, kind: "node", class: "Node3D" },
      property_categories: [{ name: "Transform", property_count: 3 }],
    },
  });
  const result = await pending;
  assert.equal(result.isError, false);
});

test("editor focus panel validates panel name and writes editor_control request", async () => {
  const config = await makeConfig();
  await writeLiveHeartbeat(config.bridgeDir);
  const handlers = createToolHandlers(config);

  const invalidPanel = await handlers["godot.editor_focus_panel"]({ panel: "Terminal" });
  assert.equal(invalidPanel.isError, true);
  assert.equal((invalidPanel.structuredContent?.error as { code?: string })?.code, "invalid_editor_panel");

  const pending = handlers["godot.editor_focus_panel"]({
    panel: "Debugger",
    timeoutMs: 1_000,
  });
  const requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
  const request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.type, "editor_control");
  assert.equal(request.payload.action, "focus_panel");
  assert.equal(request.payload.params?.panel, "Debugger");

  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "focus_panel", panel: "Debugger" },
  });
  const result = await pending;
  assert.equal(result.isError, false);
});

test("editor viewport navigate validates input, writes editor_control request and captures screenshot", async () => {
  const config = await makeConfig();
  await writeLiveHeartbeat(config.bridgeDir);
  const handlers = createToolHandlers(config);

  const invalidViewport = await handlers["godot.editor_viewport_navigate"]({ viewport: "VR" });
  assert.equal(invalidViewport.isError, true);
  assert.equal((invalidViewport.structuredContent?.error as { code?: string })?.code, "invalid_viewport");

  const invalidAction = await handlers["godot.editor_viewport_navigate"]({ viewport: "2D", action: "orbit" });
  assert.equal(invalidAction.isError, true);
  assert.equal((invalidAction.structuredContent?.error as { code?: string })?.code, "invalid_viewport_action");

  const invalidZoom = await handlers["godot.editor_viewport_navigate"]({ action: "zoom", zoomFactor: 40 });
  assert.equal(invalidZoom.isError, true);
  assert.equal((invalidZoom.structuredContent?.error as { code?: string })?.code, "invalid_viewport_zoom_factor");

  const pending = handlers["godot.editor_viewport_navigate"]({
    viewport: "2D",
    action: "pan",
    deltaX: 12,
    deltaY: -8,
    timeoutMs: 1_000,
  });

  const requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
  const request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.type, "editor_control");
  assert.equal(request.payload.action, "viewport_navigate");
  assert.equal(request.payload.params?.viewport, "2D");
  assert.equal(request.payload.params?.action, "pan");
  assert.equal(request.payload.params?.delta_x, 12);
  assert.equal(request.payload.params?.delta_y, -8);

  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "viewport_navigate", viewport: "2D", operation: "pan" },
  });

  const screenshotRequestPath = await waitForNewestRequest(path.join(config.bridgeDir, "requests"), request.request_id);
  const screenshotRequest = JSON.parse(await fs.readFile(screenshotRequestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: Record<string, unknown>;
  };
  assert.equal(screenshotRequest.type, "capture_viewport_screenshot");
  assert.equal(screenshotRequest.payload.reason, "editor_viewport_navigate");
  await writeAddonResponse(config.bridgeDir, screenshotRequest.request_id, {
    status: "succeeded",
    data: { screenshot: screenshotFixture(1) },
  });

  const result = await pending;
  assert.equal(result.isError, false);
  assert.equal(result.structuredContent?.status, "ok");
  assert.equal(result.structuredContent?.screenshot_after_action !== undefined, true);
});

test("editor control handlers reject unsafe node, script and property inputs", async () => {
  const config = await makeConfig();
  const handlers = createToolHandlers(config);

  const badNode = await handlers["godot.select_node"]({ nodePath: "res://scenes/main.tscn" });
  assert.equal(badNode.isError, true);
  assert.equal((badNode.structuredContent?.error as { code?: string })?.code, "invalid_node_path");

  const missingScript = await handlers["godot.open_script"]({ scriptPath: "res://scripts/missing.gd" });
  assert.equal(missingScript.isError, true);
  assert.equal((missingScript.structuredContent?.error as { code?: string })?.code, "script_not_found");

  const blockedProperty = await handlers["godot.set_node_properties"]({
    nodePath: "Camera3D",
    changes: [{ property: "script", value: "res://malicious.gd" }],
  });
  assert.equal(blockedProperty.isError, true);
  assert.equal((blockedProperty.structuredContent?.error as { code?: string })?.code, "unsupported_property");
});

test("set node transform and editor batch write editor_control requests", async () => {
  const config = await makeConfig();
  await writeLiveHeartbeat(config.bridgeDir);
  const handlers = createToolHandlers(config);

  const transformPending = handlers["godot.set_node_transform"]({
    nodePath: "Camera3D",
    mode: "relative",
    position: { x: 1, y: 0, z: 0 },
    timeoutMs: 1_000,
  });
  let requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
  let request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown>; reason?: unknown };
  };
  assert.equal(request.type, "editor_control");
  assert.equal(request.payload.action, "set_node_transform");
  assert.equal(request.payload.params?.node_path, "Camera3D");
  assert.deepEqual(request.payload.params?.position, { x: 1, y: 0, z: 0 });
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "set_node_transform", changed: true },
  });
  assert.equal((await transformPending).isError, false);

  const batchPending = handlers["godot.editor_batch"]({
    actions: [
      { action: "focus_editor", params: { main_screen: "3D" } },
      { action: "select_node", params: { node_path: "Camera3D" } },
    ],
    timeoutMs: 1_000,
  });
  requestPath = await waitForNewestRequest(path.join(config.bridgeDir, "requests"), request.request_id);
  request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: { actions?: unknown } };
  };
  assert.equal(request.type, "editor_control");
  assert.equal(request.payload.action, "editor_batch");
  assert.equal(Array.isArray(request.payload.params?.actions), true);
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "editor_batch", results: [] },
  });
  assert.equal((await batchPending).isError, false);
});

test("undo last bridge action writes guarded editor_control request", async () => {
  const config = await makeConfig();
  await writeLiveHeartbeat(config.bridgeDir);
  const handlers = createToolHandlers(config);

  const undoPending = handlers["godot.undo_last_bridge_action"]({ timeoutMs: 1_000 });
  const requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
  const request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.type, "editor_control");
  assert.equal(request.payload.action, "undo_last_bridge_action");
  assert.deepEqual(request.payload.params, {});
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: {
      action: "undo_last_bridge_action",
      status: "undone",
      undone: true,
      action_name: "Godot Codex Bridge: set node transform",
    },
  });

  const result = await undoPending;
  assert.equal(result.isError, false);
  assert.equal(result.structuredContent?.status, "ok");
});

test("stop running scene writes editor_control request", async () => {
  const config = await makeConfig();
  await writeLiveHeartbeat(config.bridgeDir);
  const handlers = createToolHandlers(config);

  const stopPending = handlers["godot.stop_running_scene"]({ timeoutMs: 1_000 });
  const requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
  const request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.type, "editor_control");
  assert.equal(request.payload.action, "stop_running_scene");
  assert.deepEqual(request.payload.params, {});
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "stop_running_scene", was_playing: false, stopped: false },
  });
  assert.equal((await stopPending).isError, false);
});

test("emergency stop writes editor_control request", async () => {
  const config = await makeConfig();
  await writeLiveHeartbeat(config.bridgeDir);
  const handlers = createToolHandlers(config);

  const stopPending = handlers["godot.emergency_stop"]({ timeoutMs: 1_000 });
  const requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
  const request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.type, "editor_control");
  assert.equal(request.payload.action, "emergency_stop");
  assert.deepEqual(request.payload.params, { source: "mcp_server" });
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "emergency_stop", was_playing: true, stopped: true, playtest_cleanup_ok: true },
  });
  assert.equal((await stopPending).isError, false);
});

test("playtest input writes gated editor_control request and validates inputs", async () => {
  const config = await makeConfig();
  await writeLiveHeartbeat(config.bridgeDir);
  const handlers = createToolHandlers(config);

  const pending = handlers["godot.playtest_input"]({
    steps: [
      { type: "action_press", action: "jump", strength: 0.75 },
      { type: "axis", negativeAction: "move_left", positiveAction: "move_right", value: -0.5 },
      { type: "mouse_button", buttonIndex: 1, pressed: true, position: { x: 10, y: 20 } },
    ],
    reason: "tools-test",
    timeoutMs: 1_000,
  });
  const requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
  const request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.type, "editor_control");
  assert.equal(request.payload.action, "playtest_input");
  assert.deepEqual(request.payload.params?.steps, [
    { type: "action_press", action: "jump", strength: 0.75 },
    { type: "axis", negative_action: "move_left", positive_action: "move_right", value: -0.5 },
    { type: "mouse_button", button_index: 1, pressed: true, position: { x: 10, y: 20 } },
  ]);
  assert.equal(request.payload.params?.reason, "tools-test");
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "failed",
    error: { code: "permission_denied", message: "Playtest input permission is disabled." },
  });
  await fs.rm(requestPath);
  const result = await pending;
  assert.equal(result.isError, true);
  assert.equal(
    ((result.structuredContent?.response as { error?: { code?: string } } | undefined)?.error)?.code,
    "permission_denied",
  );

  const badAction = await handlers["godot.playtest_input"]({ type: "action_press", action: "../jump" });
  assert.equal(badAction.isError, true);
  assert.equal((badAction.structuredContent?.error as { code?: string })?.code, "invalid_input_action");

  const tooMany = await handlers["godot.playtest_input"]({
    steps: Array.from({ length: 17 }, () => ({ type: "action_press", action: "jump" })),
  });
  assert.equal(tooMany.isError, true);
  assert.equal((tooMany.structuredContent?.error as { code?: string })?.code, "too_many_playtest_input_steps");
});

test("playtest scenario writes bounded editor_control request and validates contract", async () => {
  const config = await makeConfig();
  await fs.mkdir(path.join(config.projectRoot, "scenes"), { recursive: true });
  await fs.writeFile(path.join(config.projectRoot, "scenes", "playtest.tscn"), "[gd_scene format=3]\n", "utf8");
  await writeLiveHeartbeat(config.bridgeDir);
  const handlers = createToolHandlers(config);

  const pending = handlers["godot.run_playtest_scenario"]({
    scenePath: "res://scenes/playtest.tscn",
    steps: [
      { type: "capture", source: "runtime_state" },
      { type: "assert", assertion: "runtime_state_node_exists", nodePath: "/root/PlaytestInputFixture/PlaytestMarker" },
      { type: "press_action", action: "jump", strength: 0.5 },
      { type: "wait_seconds", seconds: 0.25 },
      { type: "capture", source: "timeline_screenshot", frameCount: 2, intervalMs: 50 },
      { type: "wait_for_event", eventName: "input_action_pressed", timeoutSeconds: 2 },
      { type: "assert", assertion: "runtime_state_position_delta", nodePath: "/root/PlaytestInputFixture/PlaytestMarker", axis: "y", minDelta: 1, epsilon: 0.05 },
      { type: "release_action", action: "jump" },
      { type: "assert", assertion: "runtime_event_present", event_type: "input_action_released", action: "jump" },
    ],
    timeoutMs: 5_000,
  });
  const requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
  const request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.type, "editor_control");
  assert.equal(request.payload.action, "run_playtest_scenario");
  assert.deepEqual(request.payload.params, {
    scene_path: "res://scenes/playtest.tscn",
    steps: [
      { type: "capture", source: "runtime_state" },
      { type: "assert", assertion: "runtime_state_node_exists", node_path: "/root/PlaytestInputFixture/PlaytestMarker" },
      { type: "press_action", action: "jump", strength: 0.5 },
      { type: "wait_seconds", seconds: 0.25 },
      { type: "capture", source: "timeline_screenshot", frame_count: 2, interval_ms: 50 },
      { type: "wait_for_event", event: "input_action_pressed", timeout_seconds: 2 },
      { type: "assert", assertion: "runtime_state_position_delta", node_path: "/root/PlaytestInputFixture/PlaytestMarker", axis: "y", min_delta: 1, epsilon: 0.05 },
      { type: "release_action", action: "jump" },
      { type: "assert", assertion: "runtime_event_present", event_type: "input_action_released", action: "jump" },
    ],
    timeout_ms: 5_000,
  });
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "run_playtest_scenario", scene_path: "res://scenes/playtest.tscn" },
  });
  await fs.rm(requestPath);
  assert.equal((await pending).isError, false);

  const badScene = await handlers["godot.run_playtest_scenario"]({
    scenePath: "res://scenes/playtest.gd",
    steps: [{ type: "wait_seconds", seconds: 0.1 }],
  });
  assert.equal(badScene.isError, true);
  assert.equal((badScene.structuredContent?.error as { code?: string })?.code, "invalid_scene_extension");

  const tooMany = await handlers["godot.run_playtest_scenario"]({
    scenePath: "res://scenes/playtest.tscn",
    steps: Array.from({ length: 33 }, () => ({ type: "wait_seconds", seconds: 0.1 })),
  });
  assert.equal(tooMany.isError, true);
  assert.equal((tooMany.structuredContent?.error as { code?: string })?.code, "too_many_playtest_scenario_steps");

  const badWait = await handlers["godot.run_playtest_scenario"]({
    scenePath: "res://scenes/playtest.tscn",
    steps: [{ type: "wait_seconds", seconds: 11 }],
  });
  assert.equal(badWait.isError, true);
  assert.equal((badWait.structuredContent?.error as { code?: string })?.code, "invalid_playtest_scenario_wait_seconds");

  const badTimeout = await handlers["godot.run_playtest_scenario"]({
    scenePath: "res://scenes/playtest.tscn",
    steps: [{ type: "wait_seconds", seconds: 0.1 }],
    timeoutMs: 60_001,
  });
  assert.equal(badTimeout.isError, true);
  assert.equal((badTimeout.structuredContent?.error as { code?: string })?.code, "invalid_playtest_scenario_timeout");

  const badAssertion = await handlers["godot.run_playtest_scenario"]({
    scenePath: "res://scenes/playtest.tscn",
    steps: [{ type: "assert", assertion: "runtime_state_position_delta", nodePath: "/root/Marker", axis: "w", minDelta: 1 }],
  });
  assert.equal(badAssertion.isError, true);
  assert.equal((badAssertion.structuredContent?.error as { code?: string })?.code, "invalid_playtest_axis");

  const badTimeline = await handlers["godot.run_playtest_scenario"]({
    scenePath: "res://scenes/playtest.tscn",
    steps: [{ type: "capture", source: "timeline_screenshot", frameCount: 1 }],
  });
  assert.equal(badTimeline.isError, true);
  assert.equal((badTimeline.structuredContent?.error as { code?: string })?.code, "invalid_playtest_timeline_frame_count");
});

test("save scene tools write editor_control requests", async () => {
  const config = await makeConfig();
  await writeLiveHeartbeat(config.bridgeDir);
  const handlers = createToolHandlers(config);

  const savePending = handlers["godot.save_scene"]({ timeoutMs: 1_000 });
  let requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
  let request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown>; reason?: unknown };
  };
  assert.equal(request.type, "editor_control");
  assert.equal(request.payload.action, "save_scene");
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: {
      action: "save_scene",
      saved: true,
      save_state: {
        status: "saved_to_disk",
        save_scope: "current_scene",
        target_scene: "res://scenes/main.tscn",
      },
    },
  });
  const saveResult = await savePending;
  assert.equal(saveResult.isError, false);
  const saveResponse = saveResult.structuredContent?.response as {
    data?: {
      save_state?: { status?: string };
      post_save_check?: { check_kind?: string; status?: string; validation_status?: string };
      post_save_check_passed?: boolean;
    };
  } | undefined;
  assert.equal(saveResponse?.data?.save_state?.status, "saved_to_disk");
  assert.equal(saveResponse?.data?.post_save_check?.check_kind, "godot_headless_check_only");
  assert.equal(saveResponse?.data?.post_save_check?.status, "invalid_request");
  assert.equal(saveResponse?.data?.post_save_check?.validation_status, "not_run");
  assert.equal(saveResponse?.data?.post_save_check_passed, false);
  assert.equal(saveResult.structuredContent?.post_save_check_passed, false);

  const saveAllPending = handlers["godot.save_all_scenes"]({ timeoutMs: 1_000 });
  requestPath = await waitForNewestRequest(path.join(config.bridgeDir, "requests"), request.request_id);
  request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.type, "editor_control");
  assert.equal(request.payload.action, "save_all_scenes");
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "save_all_scenes", saved: true },
  });
  assert.equal((await saveAllPending).isError, false);
});

test("on-demand introspection tools write editor_control requests and validate inputs", async () => {
  const config = await makeConfig();
  await writeLiveHeartbeat(config.bridgeDir);
  const handlers = createToolHandlers(config);

  const nodePending = handlers["godot.get_node_deep"]({
    nodePath: ".",
    depth: 3,
    maxNodes: 48,
    includeProperties: false,
    timeoutMs: 1_000,
  });
  let requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
  let request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.type, "editor_control");
  assert.equal(request.payload.action, "get_node_deep");
  assert.equal(request.payload.params?.node_path, ".");
  assert.equal(request.payload.params?.depth, 3);
  assert.equal(request.payload.params?.max_nodes, 48);
  assert.equal(request.payload.params?.include_properties, false);
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "get_node_deep", node_count: 3 },
  });
  await fs.rm(requestPath);
  assert.equal((await nodePending).isError, false);

  const boundsPending = handlers["godot.get_spatial_bounds"]({
    nodePath: "House",
    maxNodes: 12,
    groundY: -1.5,
    timeoutMs: 1_000,
  });
  requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
  request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.type, "editor_control");
  assert.equal(request.payload.action, "get_spatial_bounds");
  assert.equal(request.payload.params?.node_path, "House");
  assert.equal(request.payload.params?.selected_only, false);
  assert.equal(request.payload.params?.max_nodes, 12);
  assert.equal(request.payload.params?.ground_y, -1.5);
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "get_spatial_bounds", nodes: [] },
  });
  await fs.rm(requestPath);
  assert.equal((await boundsPending).isError, false);

  const groupBoundsPending = handlers["godot.get_spatial_bounds"]({
    groupName: "buildings",
    selectedOnly: false,
    timeoutMs: 1_000,
  });
  requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
  request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.payload.action, "get_spatial_bounds");
  assert.equal(request.payload.params?.group_name, "buildings");
  assert.equal(request.payload.params?.selected_only, false);
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "get_spatial_bounds", mode: "group", nodes: [] },
  });
  await fs.rm(requestPath);
  assert.equal((await groupBoundsPending).isError, false);

  const spatialQueryPending = handlers["godot.spatial_query"]({
    queryType: "ground_gap",
    groupName: "buildings",
    tolerance: 0.05,
    maxNodes: 12,
    timeoutMs: 1_000,
  });
  requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
  request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.type, "editor_control");
  assert.equal(request.payload.action, "spatial_query");
  assert.equal(request.payload.params?.query, "ground_gap");
  assert.equal(request.payload.params?.group_name, "buildings");
  assert.equal(request.payload.params?.selected_only, false);
  assert.equal(request.payload.params?.max_nodes, 12);
  assert.equal(request.payload.params?.tolerance, 0.05);
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "spatial_query", query_type: "ground_gap", items: [] },
  });
  await fs.rm(requestPath);
  assert.equal((await spatialQueryPending).isError, false);

  const overlapQueryPending = handlers["godot.spatial_query"]({
    query: "aabb_overlap",
    selectedOnly: true,
    maxPairs: 9,
    timeoutMs: 1_000,
  });
  requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
  request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.payload.action, "spatial_query");
  assert.equal(request.payload.params?.query, "aabb_overlap");
  assert.equal(request.payload.params?.selected_only, true);
  assert.equal(request.payload.params?.max_pairs, 9);
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "spatial_query", query_type: "aabb_overlap", pairs: [] },
  });
  await fs.rm(requestPath);
  assert.equal((await overlapQueryPending).isError, false);

  const placementPending = handlers["godot.placement_check"]({
    groupName: "buildings",
    tolerance: 0.05,
    gridSize: 1,
    gridOrigin: { x: 0.5, z: -0.5 },
    checks: ["ground_gap", "overlap", "grid"],
    maxNodes: 12,
    maxPairs: 9,
    maxIssues: 32,
    timeoutMs: 1_000,
  });
  requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
  request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.type, "editor_control");
  assert.equal(request.payload.action, "placement_check");
  assert.equal(request.payload.params?.group_name, "buildings");
  assert.equal(request.payload.params?.selected_only, false);
  assert.equal(request.payload.params?.max_nodes, 12);
  assert.equal(request.payload.params?.max_pairs, 9);
  assert.equal(request.payload.params?.max_issues, 32);
  assert.equal(request.payload.params?.tolerance, 0.05);
  assert.equal(request.payload.params?.grid_size, 1);
  assert.deepEqual(request.payload.params?.grid_origin, { x: 0.5, y: 0, z: -0.5 });
  assert.deepEqual(request.payload.params?.checks, ["ground_gap", "overlap", "grid"]);
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "placement_check", items: [], issues: [] },
  });
  await fs.rm(requestPath);
  assert.equal((await placementPending).isError, false);

  const snapGroundPending = handlers["godot.snap_to_ground"]({
    groupName: "buildings",
    tolerance: 0.05,
    groundY: 0,
    gridSize: 1,
    gridOrigin: { x: 0, z: 0 },
    alignToSurface: true,
    maxNodes: 12,
    timeoutMs: 1_000,
  });
  requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
  request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.type, "editor_control");
  assert.equal(request.payload.action, "snap_to_ground");
  assert.equal(request.payload.params?.group_name, "buildings");
  assert.equal(request.payload.params?.selected_only, false);
  assert.equal(request.payload.params?.max_nodes, 12);
  assert.equal(request.payload.params?.tolerance, 0.05);
  assert.equal(request.payload.params?.ground_y, 0);
  assert.equal(request.payload.params?.grid_size, 1);
  assert.deepEqual(request.payload.params?.grid_origin, { x: 0, y: 0, z: 0 });
  assert.equal(request.payload.params?.align_to_surface, true);
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "snap_to_ground", changed: true },
  });
  await fs.rm(requestPath);
  requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
  request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown>; reason?: unknown };
  };
  assert.equal(request.type, "capture_viewport_screenshot");
  assert.equal((request.payload as Record<string, unknown>).reason, "snap_to_ground");
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { path: "C:/tmp/snap-ground.png" },
  });
  await fs.rm(requestPath);
  const snapGroundResult = await snapGroundPending;
  assert.equal(snapGroundResult.isError, false);
  assert.equal(typeof snapGroundResult.structuredContent?.screenshot_after_action, "object");

  const snapGridPending = handlers["godot.snap_to_grid"]({
    nodePath: "House",
    gridSize: 2,
    gridOrigin: { x: 0, y: 1, z: 0 },
    axes: ["x", "z"],
    captureScreenshot: false,
    timeoutMs: 1_000,
  });
  requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
  request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.type, "editor_control");
  assert.equal(request.payload.action, "snap_to_grid");
  assert.equal(request.payload.params?.node_path, "House");
  assert.equal(request.payload.params?.selected_only, false);
  assert.equal(request.payload.params?.grid_size, 2);
  assert.deepEqual(request.payload.params?.grid_origin, { x: 0, y: 1, z: 0 });
  assert.deepEqual(request.payload.params?.axes, ["x", "z"]);
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "snap_to_grid", changed: true },
  });
  await fs.rm(requestPath);
  assert.equal((await snapGridPending).isError, false);

  const resourcesPending = handlers["godot.list_resources"]({
    rootPath: "res://scenes",
    extensions: ["tscn"],
    typeFilter: "PackedScene",
    limit: 25,
    timeoutMs: 1_000,
  });
  requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
  request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.payload.action, "list_resources");
  assert.equal(request.payload.params?.root_path, "res://scenes");
  assert.deepEqual(request.payload.params?.extensions, [".tscn"]);
  assert.equal(request.payload.params?.type_filter, "PackedScene");
  assert.equal(request.payload.params?.limit, 25);
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "list_resources", returned_count: 1 },
  });
  await fs.rm(requestPath);
  assert.equal((await resourcesPending).isError, false);

  await fs.mkdir(path.join(config.projectRoot, "assets", "models"), { recursive: true });
  await fs.writeFile(path.join(config.projectRoot, "assets", "models", "test.obj"), "o Test\nv 0 0 0\n", "utf8");
  const importedAssetsPending = handlers["godot.inspect_imported_assets"]({
    rootPath: "res://assets",
    extensions: [".obj"],
    placeableOnly: true,
    includeDependencies: true,
    limit: 10,
    timeoutMs: 1_000,
  });
  requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
  request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.payload.action, "inspect_imported_assets");
  assert.equal(request.payload.params?.root_path, "res://assets");
  assert.deepEqual(request.payload.params?.extensions, [".obj"]);
  assert.equal(request.payload.params?.placeable_only, true);
  assert.equal(request.payload.params?.include_dependencies, true);
  assert.equal(request.payload.params?.limit, 10);
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "inspect_imported_assets", returned_count: 1 },
  });
  await fs.rm(requestPath);
  assert.equal((await importedAssetsPending).isError, false);

  const classPending = handlers["godot.get_class_info"]({
    className: "Node3D",
    noInheritance: true,
    limit: 12,
    timeoutMs: 1_000,
  });
  requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
  request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.payload.action, "get_class_info");
  assert.equal(request.payload.params?.class_name, "Node3D");
  assert.equal(request.payload.params?.no_inheritance, true);
  assert.equal(request.payload.params?.limit, 12);
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "get_class_info", class_name: "Node3D" },
  });
  await fs.rm(requestPath);
  assert.equal((await classPending).isError, false);

  const materialsPending = handlers["godot.inspect_materials"]({
    nodePath: "MeshInstance3D",
    includeShaderParams: false,
    includeEmpty: true,
    maxNodes: 10,
    maxSlots: 20,
    timeoutMs: 1_000,
  });
  requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
  request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.payload.action, "inspect_materials");
  assert.equal(request.payload.params?.node_path, "MeshInstance3D");
  assert.equal(request.payload.params?.include_shader_params, false);
  assert.equal(request.payload.params?.include_empty, true);
  assert.equal(request.payload.params?.max_nodes, 10);
  assert.equal(request.payload.params?.max_slots, 20);
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "inspect_materials", material_slot_count: 1 },
  });
  await fs.rm(requestPath);
  assert.equal((await materialsPending).isError, false);

  const effectsPending = handlers["godot.inspect_rendering_effects"]({
    selectedOnly: true,
    includeEnvironmentProperties: false,
    includeParticles: true,
    maxNodes: 12,
    timeoutMs: 1_000,
  });
  requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
  request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.payload.action, "inspect_rendering_effects");
  assert.equal(request.payload.params?.selected_only, true);
  assert.equal(request.payload.params?.include_environment_properties, false);
  assert.equal(request.payload.params?.include_particles, true);
  assert.equal(request.payload.params?.max_nodes, 12);
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "inspect_rendering_effects", stats: { particle_nodes: 1 } },
  });
  await fs.rm(requestPath);
  assert.equal((await effectsPending).isError, false);

  const setEnvironmentPending = handlers["godot.set_environment_property"]({
    nodePath: "WorldEnvironment",
    property: "glow_enabled",
    value: true,
    createIfMissing: true,
    timeoutMs: 1_000,
  });
  requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
  request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.payload.action, "set_environment_property");
  assert.equal(request.payload.params?.node_path, "WorldEnvironment");
  assert.equal(request.payload.params?.property, "glow_enabled");
  assert.equal(request.payload.params?.value, true);
  assert.equal(request.payload.params?.create_if_missing, true);
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "set_environment_property", changed: true },
  });
  await fs.rm(requestPath);
  assert.equal((await setEnvironmentPending).isError, false);

  const createParticlesPending = handlers["godot.create_particle_effect"]({
    parentPath: ".",
    name: "SmokeBurst",
    amount: 32,
    lifetime: 1.25,
    position: { x: 0, y: 1, z: 0 },
    color: { r: 1, g: 0.7, b: 0.25, a: 1 },
    timeoutMs: 1_000,
  });
  requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
  request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.payload.action, "create_particle_effect");
  assert.equal(request.payload.params?.parent_path, ".");
  assert.equal(request.payload.params?.kind, "gpu_particles_3d");
  assert.equal(request.payload.params?.name, "SmokeBurst");
  assert.equal(request.payload.params?.amount, 32);
  assert.equal(request.payload.params?.lifetime, 1.25);
  assert.deepEqual(request.payload.params?.position, { x: 0, y: 1, z: 0 });
  assert.deepEqual(request.payload.params?.color, { r: 1, g: 0.7, b: 0.25, a: 1 });
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "create_particle_effect", changed: true },
  });
  await fs.rm(requestPath);
  assert.equal((await createParticlesPending).isError, false);

  const setParticlesPending = handlers["godot.set_particle_effect_properties"]({
    nodePath: "ValidationParticles",
    amount: 48,
    emitting: false,
    drawMesh: "unchanged",
    drawSize: 0.5,
    color: { r: 0.3, g: 0.8, b: 1, a: 1 },
    timeoutMs: 1_000,
  });
  requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
  request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.payload.action, "set_particle_effect_properties");
  assert.equal(request.payload.params?.node_path, "ValidationParticles");
  assert.equal(request.payload.params?.amount, 48);
  assert.equal(request.payload.params?.emitting, false);
  assert.equal(request.payload.params?.draw_mesh, "unchanged");
  assert.equal(request.payload.params?.draw_size, 0.5);
  assert.deepEqual(request.payload.params?.color, { r: 0.3, g: 0.8, b: 1, a: 1 });
  assert.equal(request.payload.params?.lifetime, undefined);
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "set_particle_effect_properties", changed: true },
  });
  await fs.rm(requestPath);
  assert.equal((await setParticlesPending).isError, false);

  const badNode = await handlers["godot.get_node_deep"]({ nodePath: "res://scenes/main.tscn" });
  assert.equal(badNode.isError, true);
  assert.equal((badNode.structuredContent?.error as { code?: string })?.code, "invalid_node_path");

  const badBoundsNode = await handlers["godot.get_spatial_bounds"]({ nodePath: "../House" });
  assert.equal(badBoundsNode.isError, true);
  assert.equal((badBoundsNode.structuredContent?.error as { code?: string })?.code, "invalid_node_path");

  const badBoundsSelector = await handlers["godot.get_spatial_bounds"]({ nodePath: "House", groupName: "buildings" });
  assert.equal(badBoundsSelector.isError, true);
  assert.equal((badBoundsSelector.structuredContent?.error as { code?: string })?.code, "invalid_spatial_selector");

  const badBoundsGroup = await handlers["godot.get_spatial_bounds"]({ groupName: "../bad" });
  assert.equal(badBoundsGroup.isError, true);
  assert.equal((badBoundsGroup.structuredContent?.error as { code?: string })?.code, "invalid_group_name");

  const badSpatialQuery = await handlers["godot.spatial_query"]({ query: "teleport" });
  assert.equal(badSpatialQuery.isError, true);
  assert.equal((badSpatialQuery.structuredContent?.error as { code?: string })?.code, "invalid_spatial_query");

  const badPlacementSelector = await handlers["godot.placement_check"]({ nodePath: "House", groupName: "buildings" });
  assert.equal(badPlacementSelector.isError, true);
  assert.equal((badPlacementSelector.structuredContent?.error as { code?: string })?.code, "invalid_spatial_selector");

  const badPlacementChecks = await handlers["godot.placement_check"]({ checks: ["teleport"] });
  assert.equal(badPlacementChecks.isError, true);
  assert.equal((badPlacementChecks.structuredContent?.error as { code?: string })?.code, "invalid_placement_checks");

  const badPlacementOrigin = await handlers["godot.placement_check"]({ gridOrigin: { x: 0 } });
  assert.equal(badPlacementOrigin.isError, true);
  assert.equal((badPlacementOrigin.structuredContent?.error as { code?: string })?.code, "invalid_grid_origin");

  const badSnapSelector = await handlers["godot.snap_to_ground"]({ selectedOnly: false });
  assert.equal(badSnapSelector.isError, true);
  assert.equal((badSnapSelector.structuredContent?.error as { code?: string })?.code, "broad_scene_mutation_rejected");

  const badSnapGroundGrid = await handlers["godot.snap_to_ground"]({ nodePath: "House", gridSize: 0 });
  assert.equal(badSnapGroundGrid.isError, true);
  assert.equal((badSnapGroundGrid.structuredContent?.error as { code?: string })?.code, "invalid_grid_size");

  const badSnapGridSize = await handlers["godot.snap_to_grid"]({ nodePath: "House" });
  assert.equal(badSnapGridSize.isError, true);
  assert.equal((badSnapGridSize.structuredContent?.error as { code?: string })?.code, "invalid_grid_size");

  const badSnapGridAxes = await handlers["godot.snap_to_grid"]({ nodePath: "House", gridSize: 1, axes: ["w"] });
  assert.equal(badSnapGridAxes.isError, true);
  assert.equal((badSnapGridAxes.structuredContent?.error as { code?: string })?.code, "invalid_grid_axes");

  const badMaterialNode = await handlers["godot.inspect_materials"]({ nodePath: "../MeshInstance3D" });
  assert.equal(badMaterialNode.isError, true);
  assert.equal((badMaterialNode.structuredContent?.error as { code?: string })?.code, "invalid_node_path");

  const badEffectsLimit = await handlers["godot.inspect_rendering_effects"]({ maxNodes: 999 });
  assert.equal(badEffectsLimit.isError, true);
  assert.equal((badEffectsLimit.structuredContent?.error as { code?: string })?.code, "invalid_max_render_effect_nodes");

  const badEnvironmentProperty = await handlers["godot.set_environment_property"]({
    nodePath: "WorldEnvironment",
    property: "sky",
    value: "res://sky.tres",
  });
  assert.equal(badEnvironmentProperty.isError, true);
  assert.equal((badEnvironmentProperty.structuredContent?.error as { code?: string })?.code, "unsupported_environment_property");

  const badParticleKind = await handlers["godot.create_particle_effect"]({
    kind: "cpu_particles_3d",
    parentPath: ".",
  });
  assert.equal(badParticleKind.isError, true);
  assert.equal((badParticleKind.structuredContent?.error as { code?: string })?.code, "unsupported_particle_effect_kind");

  const badParticleDrawMesh = await handlers["godot.create_particle_effect"]({
    parentPath: ".",
    drawMesh: "sphere",
  });
  assert.equal(badParticleDrawMesh.isError, true);
  assert.equal((badParticleDrawMesh.structuredContent?.error as { code?: string })?.code, "unsupported_particle_draw_mesh");

  const badParticleEditNode = await handlers["godot.set_particle_effect_properties"]({
    nodePath: "../ValidationParticles",
    amount: 8,
  });
  assert.equal(badParticleEditNode.isError, true);
  assert.equal((badParticleEditNode.structuredContent?.error as { code?: string })?.code, "invalid_node_path");

  const badParticleEditDrawMesh = await handlers["godot.set_particle_effect_properties"]({
    nodePath: "ValidationParticles",
    drawMesh: "sphere",
  });
  assert.equal(badParticleEditDrawMesh.isError, true);
  assert.equal((badParticleEditDrawMesh.structuredContent?.error as { code?: string })?.code, "unsupported_particle_draw_mesh");

  const badRoot = await handlers["godot.list_resources"]({ rootPath: "res://../outside" });
  assert.equal(badRoot.isError, true);
  assert.equal((badRoot.structuredContent?.error as { code?: string })?.code, "invalid_resource_root");

  const badImportRoot = await handlers["godot.inspect_imported_assets"]({ rootPath: "res://../outside" });
  assert.equal(badImportRoot.isError, true);
  assert.equal((badImportRoot.structuredContent?.error as { code?: string })?.code, "invalid_resource_root");

  const badClass = await handlers["godot.get_class_info"]({ className: "../Node" });
  assert.equal(badClass.isError, true);
  assert.equal((badClass.structuredContent?.error as { code?: string })?.code, "invalid_node_class");
});

test("resource lifecycle tools write editor_control requests and validate inputs", async () => {
  const config = await makeConfig();
  await fs.mkdir(path.join(config.projectRoot, "materials"), { recursive: true });
  await fs.writeFile(path.join(config.projectRoot, "materials", "test_material.tres"), "[gd_resource type=\"StandardMaterial3D\" format=3]\n", "utf8");
  await fs.mkdir(path.join(config.projectRoot, "shaders"), { recursive: true });
  await fs.writeFile(path.join(config.projectRoot, "shaders", "glow.gdshader"), "shader_type spatial;\nuniform float glow_strength = 0.25;\n", "utf8");
  await fs.mkdir(path.join(config.projectRoot, "textures"), { recursive: true });
  await fs.writeFile(path.join(config.projectRoot, "textures", "checker.svg"), "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"8\" height=\"8\"></svg>\n", "utf8");
  await writeLiveHeartbeat(config.bridgeDir);
  const handlers = createToolHandlers(config);

  const assignPending = handlers["godot.assign_resource_to_node"]({
    nodePath: "MeshInstance3D",
    property: "material_override",
    resourcePath: "res://materials/test_material.tres",
    timeoutMs: 1_000,
  });
  let requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
  let request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.type, "editor_control");
  assert.equal(request.payload.action, "assign_resource_to_node");
  assert.equal(request.payload.params?.node_path, "MeshInstance3D");
  assert.equal(request.payload.params?.property, "material_override");
  assert.equal(request.payload.params?.resource_path, "res://materials/test_material.tres");
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "assign_resource_to_node", changed: true },
  });
  await fs.rm(requestPath);
  assert.equal((await assignPending).isError, false);

  const createPending = handlers["godot.create_node_resource"]({
    nodePath: "MeshInstance3D",
    property: "mesh",
    resourceClass: "BoxMesh",
    changes: [{ property: "size", value: { x: 1, y: 2, z: 3 } }],
    timeoutMs: 1_000,
  });
  requestPath = await waitForNewestRequest(path.join(config.bridgeDir, "requests"), request.request_id);
  request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.payload.action, "create_node_resource");
  assert.equal(request.payload.params?.node_path, "MeshInstance3D");
  assert.equal(request.payload.params?.property, "mesh");
  assert.equal(request.payload.params?.resource_class, "BoxMesh");
  assert.deepEqual(request.payload.params?.changes, [{ property: "size", value: { x: 1, y: 2, z: 3 } }]);
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "create_node_resource", changed: true },
  });
  await fs.rm(requestPath);
  assert.equal((await createPending).isError, false);

  const setPending = handlers["godot.set_resource_properties"]({
    nodePath: "MeshInstance3D",
    property: "material_override",
    changes: [{ property: "albedo_color", value: { r: 0.2, g: 0.8, b: 1, a: 1 } }],
    timeoutMs: 1_000,
  });
  requestPath = await waitForNewestRequest(path.join(config.bridgeDir, "requests"), request.request_id);
  request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.payload.action, "set_resource_properties");
  assert.equal(request.payload.params?.node_path, "MeshInstance3D");
  assert.equal(request.payload.params?.property, "material_override");
  assert.deepEqual(request.payload.params?.changes, [{ property: "albedo_color", value: { r: 0.2, g: 0.8, b: 1, a: 1 } }]);
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "set_resource_properties", changed: true },
  });
  await fs.rm(requestPath);
  assert.equal((await setPending).isError, false);

  const shaderPending = handlers["godot.set_shader_parameter"]({
    nodePath: "MeshInstance3D",
    slotKind: "geometry_material_override",
    parameter: "glow_strength",
    value: 0.75,
    timeoutMs: 1_000,
  });
  requestPath = await waitForNewestRequest(path.join(config.bridgeDir, "requests"), request.request_id);
  request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.payload.action, "set_shader_parameter");
  assert.equal(request.payload.params?.node_path, "MeshInstance3D");
  assert.equal(request.payload.params?.slot_kind, "geometry_material_override");
  assert.equal(request.payload.params?.parameter, "glow_strength");
  assert.equal(request.payload.params?.value, 0.75);
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "set_shader_parameter", changed: true },
  });
  await fs.rm(requestPath);
  assert.equal((await shaderPending).isError, false);

  const createShaderPending = handlers["godot.create_shader_material_for_node"]({
    nodePath: "MeshInstance3D",
    slotKind: "geometry_material_override",
    shaderPath: "res://shaders/glow.gdshader",
    parameters: { glow_strength: 0.5 },
    timeoutMs: 1_000,
  });
  requestPath = await waitForNewestRequest(path.join(config.bridgeDir, "requests"), request.request_id);
  request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.payload.action, "create_shader_material_for_node");
  assert.equal(request.payload.params?.node_path, "MeshInstance3D");
  assert.equal(request.payload.params?.slot_kind, "geometry_material_override");
  assert.equal(request.payload.params?.shader_path, "res://shaders/glow.gdshader");
  assert.deepEqual(request.payload.params?.parameters, { glow_strength: 0.5 });
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "create_shader_material_for_node", changed: true },
  });
  await fs.rm(requestPath);
  assert.equal((await createShaderPending).isError, false);

  const texturePending = handlers["godot.set_shader_texture_parameter"]({
    nodePath: "MeshInstance3D",
    slotKind: "geometry_material_override",
    parameter: "detail_texture",
    texturePath: "res://textures/checker.svg",
    timeoutMs: 1_000,
  });
  requestPath = await waitForNewestRequest(path.join(config.bridgeDir, "requests"), request.request_id);
  request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.payload.action, "set_shader_texture_parameter");
  assert.equal(request.payload.params?.node_path, "MeshInstance3D");
  assert.equal(request.payload.params?.slot_kind, "geometry_material_override");
  assert.equal(request.payload.params?.parameter, "detail_texture");
  assert.equal(request.payload.params?.texture_path, "res://textures/checker.svg");
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "set_shader_texture_parameter", changed: true },
  });
  await fs.rm(requestPath);
  assert.equal((await texturePending).isError, false);

  const clearPending = handlers["godot.assign_resource_to_node"]({
    nodePath: "MeshInstance3D",
    property: "material_override",
    clear: true,
    timeoutMs: 1_000,
  });
  requestPath = await waitForNewestRequest(path.join(config.bridgeDir, "requests"), request.request_id);
  request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.payload.action, "assign_resource_to_node");
  assert.equal(request.payload.params?.clear, true);
  assert.equal(request.payload.params?.resource_path, undefined);
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "assign_resource_to_node", changed: true },
  });
  await fs.rm(requestPath);
  assert.equal((await clearPending).isError, false);

  const badResourcePath = await handlers["godot.assign_resource_to_node"]({
    nodePath: "MeshInstance3D",
    property: "material_override",
    resourcePath: "C:/outside/material.tres",
  });
  assert.equal(badResourcePath.isError, true);
  assert.equal((badResourcePath.structuredContent?.error as { code?: string })?.code, "invalid_resource_path");

  const badResourceClass = await handlers["godot.create_node_resource"]({
    nodePath: "MeshInstance3D",
    property: "mesh",
    resourceClass: "../BoxMesh",
  });
  assert.equal(badResourceClass.isError, true);
  assert.equal((badResourceClass.structuredContent?.error as { code?: string })?.code, "invalid_resource_class");

  const badProperty = await handlers["godot.set_resource_properties"]({
    nodePath: "MeshInstance3D",
    property: "script",
    changes: [{ property: "albedo_color", value: { r: 1, g: 1, b: 1, a: 1 } }],
  });
  assert.equal(badProperty.isError, true);
  assert.equal((badProperty.structuredContent?.error as { code?: string })?.code, "unsupported_property");

  const badShaderSlot = await handlers["godot.set_shader_parameter"]({
    nodePath: "MeshInstance3D",
    slotKind: "material_override",
    parameter: "glow_strength",
    value: 1,
  });
  assert.equal(badShaderSlot.isError, true);
  assert.equal((badShaderSlot.structuredContent?.error as { code?: string })?.code, "invalid_material_slot");

  const badShaderParameter = await handlers["godot.set_shader_parameter"]({
    nodePath: "MeshInstance3D",
    slotKind: "geometry_material_override",
    parameter: "../glow_strength",
    value: 1,
  });
  assert.equal(badShaderParameter.isError, true);
  assert.equal((badShaderParameter.structuredContent?.error as { code?: string })?.code, "invalid_shader_parameter");

  const badShaderValue = await handlers["godot.set_shader_parameter"]({
    nodePath: "MeshInstance3D",
    slotKind: "geometry_material_override",
    parameter: "glow_strength",
    value: Number.NaN,
  });
  assert.equal(badShaderValue.isError, true);
  assert.equal((badShaderValue.structuredContent?.error as { code?: string })?.code, "invalid_shader_parameter_value");

  const badShaderPath = await handlers["godot.create_shader_material_for_node"]({
    nodePath: "MeshInstance3D",
    slotKind: "geometry_material_override",
    shaderPath: "res://../outside.gdshader",
  });
  assert.equal(badShaderPath.isError, true);
  assert.equal((badShaderPath.structuredContent?.error as { code?: string })?.code, "invalid_shader_path");

  const badShaderParameters = await handlers["godot.create_shader_material_for_node"]({
    nodePath: "MeshInstance3D",
    slotKind: "geometry_material_override",
    parameters: { "../glow": 1 },
  });
  assert.equal(badShaderParameters.isError, true);
  assert.equal((badShaderParameters.structuredContent?.error as { code?: string })?.code, "invalid_shader_parameter");

  const badTexturePath = await handlers["godot.set_shader_texture_parameter"]({
    nodePath: "MeshInstance3D",
    slotKind: "geometry_material_override",
    parameter: "detail_texture",
    texturePath: "C:/outside/checker.png",
  });
  assert.equal(badTexturePath.isError, true);
  assert.equal((badTexturePath.structuredContent?.error as { code?: string })?.code, "invalid_texture_path");

  const clearTexture = handlers["godot.set_shader_texture_parameter"]({
    nodePath: "MeshInstance3D",
    slotKind: "geometry_material_override",
    parameter: "detail_texture",
    clear: true,
    timeoutMs: 1_000,
  });
  requestPath = await waitForNewestRequest(path.join(config.bridgeDir, "requests"), request.request_id);
  request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.payload.action, "set_shader_texture_parameter");
  assert.equal(request.payload.params?.clear, true);
  assert.equal(request.payload.params?.texture_path, undefined);
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "set_shader_texture_parameter", changed: true },
  });
  await fs.rm(requestPath);
  assert.equal((await clearTexture).isError, false);
});

test("animation tools write editor_control requests and validate inputs", async () => {
  const config = await makeConfig();
  await writeLiveHeartbeat(config.bridgeDir);
  const handlers = createToolHandlers(config);

  const listPending = handlers["godot.list_animation_players"]({
    maxPlayers: 12,
    includeEmpty: false,
    timeoutMs: 1_000,
  });
  let requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
  let request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.type, "editor_control");
  assert.equal(request.payload.action, "list_animation_players");
  assert.equal(request.payload.params?.max_players, 12);
  assert.equal(request.payload.params?.include_empty, false);
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "list_animation_players", returned_count: 1 },
  });
  await fs.rm(requestPath);
  assert.equal((await listPending).isError, false);

  const inspectPending = handlers["godot.inspect_animation"]({
    nodePath: "AnimationPlayer",
    animationName: "float",
    includeKeys: true,
    maxTracks: 8,
    maxKeysPerTrack: 4,
    timeoutMs: 1_000,
  });
  requestPath = await waitForNewestRequest(path.join(config.bridgeDir, "requests"), request.request_id);
  request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.payload.action, "inspect_animation");
  assert.equal(request.payload.params?.node_path, "AnimationPlayer");
  assert.equal(request.payload.params?.animation_name, "float");
  assert.equal(request.payload.params?.max_tracks, 8);
  assert.equal(request.payload.params?.max_keys_per_track, 4);
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "inspect_animation", animation: { name: "float" } },
  });
  await fs.rm(requestPath);
  assert.equal((await inspectPending).isError, false);

  const previewPending = handlers["godot.preview_animation"]({
    nodePath: "AnimationPlayer",
    animationName: "float",
    mode: "seek",
    position: 0.5,
    timeoutMs: 1_000,
  });
  requestPath = await waitForNewestRequest(path.join(config.bridgeDir, "requests"), request.request_id);
  request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.payload.action, "preview_animation");
  assert.equal(request.payload.params?.node_path, "AnimationPlayer");
  assert.equal(request.payload.params?.animation_name, "float");
  assert.equal(request.payload.params?.mode, "seek");
  assert.equal(request.payload.params?.position, 0.5);
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "preview_animation", preview_only: true },
  });
  await fs.rm(requestPath);
  assert.equal((await previewPending).isError, false);

  const stopPending = handlers["godot.stop_animation_preview"]({
    nodePath: "AnimationPlayer",
    keepState: false,
    timeoutMs: 1_000,
  });
  requestPath = await waitForNewestRequest(path.join(config.bridgeDir, "requests"), request.request_id);
  request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.payload.action, "stop_animation_preview");
  assert.equal(request.payload.params?.node_path, "AnimationPlayer");
  assert.equal(request.payload.params?.keep_state, false);
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "stop_animation_preview", preview_only: true },
  });
  await fs.rm(requestPath);
  assert.equal((await stopPending).isError, false);

  const createPending = handlers["godot.create_animation_clip"]({
    nodePath: "AnimationPlayer",
    animationName: "float",
    length: 1,
    tracks: [
      {
        type: "value",
        path: "MeshInstance3D:position",
        valueType: "vector3",
        keys: [
          { time: 0, value: { x: 0, y: 0, z: 0 } },
          { time: 1, value: { x: 0, y: 1, z: 0 } },
        ],
      },
    ],
    timeoutMs: 1_000,
  });
  requestPath = await waitForNewestRequest(path.join(config.bridgeDir, "requests"), request.request_id);
  request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.payload.action, "create_animation_clip");
  assert.equal(request.payload.params?.node_path, "AnimationPlayer");
  assert.equal(request.payload.params?.animation_name, "float");
  assert.equal(request.payload.params?.length, 1);
  assert.deepEqual(request.payload.params?.tracks, [
    {
      type: "value",
      path: "MeshInstance3D:position",
      value_type: "vector3",
      interpolation_type: 1,
      keys: [
        { time: 0, transition: 1, value: { x: 0, y: 0, z: 0 } },
        { time: 1, transition: 1, value: { x: 0, y: 1, z: 0 } },
      ],
    },
  ]);
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "create_animation_clip", changed: true },
  });
  await fs.rm(requestPath);
  assert.equal((await createPending).isError, false);

  const badAnimationName = await handlers["godot.preview_animation"]({
    nodePath: "AnimationPlayer",
    animationName: "movement/run",
  });
  assert.equal(badAnimationName.isError, true);
  assert.equal((badAnimationName.structuredContent?.error as { code?: string })?.code, "invalid_animation_name");

  const badTrackPath = await handlers["godot.create_animation_clip"]({
    nodePath: "AnimationPlayer",
    animationName: "bad",
    tracks: [{ type: "value", path: "res://bad", keys: [{ time: 0, value: 1 }] }],
  });
  assert.equal(badTrackPath.isError, true);
  assert.equal((badTrackPath.structuredContent?.error as { code?: string })?.code, "invalid_animation_track_path");
});

test("node lifecycle and signal tools write editor_control requests", async () => {
  const config = await makeConfig();
  await fs.mkdir(path.join(config.projectRoot, "scenes"), { recursive: true });
  await fs.writeFile(path.join(config.projectRoot, "scenes", "tree.tscn"), "[gd_scene format=3]\n[node name=\"Tree\" type=\"Node3D\"]\n", "utf8");
  await writeLiveHeartbeat(config.bridgeDir);
  const handlers = createToolHandlers(config);

  const createPending = handlers["godot.create_node"]({
    parentPath: ".",
    className: "Node3D",
    name: "Marker",
    timeoutMs: 1_000,
  });
  let requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
  let request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.type, "editor_control");
  assert.equal(request.payload.action, "create_node");
  assert.equal(request.payload.params?.parent_path, ".");
  assert.equal(request.payload.params?.class_name, "Node3D");
  assert.equal(request.payload.params?.name, "Marker");
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "create_node", changed: true },
  });
  await fs.rm(requestPath);
  assert.equal((await createPending).isError, false);

  const renamePending = handlers["godot.rename_node"]({
    nodePath: "Marker",
    newName: "MarkerRenamed",
    timeoutMs: 1_000,
  });
  requestPath = await waitForNewestRequest(path.join(config.bridgeDir, "requests"), request.request_id);
  request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.payload.action, "rename_node");
  assert.equal(request.payload.params?.node_path, "Marker");
  assert.equal(request.payload.params?.new_name, "MarkerRenamed");
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "rename_node", changed: true },
  });
  await fs.rm(requestPath);
  assert.equal((await renamePending).isError, false);

  const instancePending = handlers["godot.instance_scene"]({
    scenePath: "res://scenes/tree.tscn",
    parentPath: ".",
    name: "TreeInstance",
    timeoutMs: 1_000,
  });
  requestPath = await waitForNewestRequest(path.join(config.bridgeDir, "requests"), request.request_id);
  request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.payload.action, "instance_scene");
  assert.equal(request.payload.params?.scene_path, "res://scenes/tree.tscn");
  assert.equal(request.payload.params?.name, "TreeInstance");
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "instance_scene", changed: true },
  });
  await fs.rm(requestPath);
  assert.equal((await instancePending).isError, false);

  await fs.mkdir(path.join(config.projectRoot, "assets", "models"), { recursive: true });
  await fs.writeFile(path.join(config.projectRoot, "assets", "models", "tree.obj"), "o Tree\nv 0 0 0\n", "utf8");
  const placeAssetPending = handlers["godot.place_asset_in_scene"]({
    assetPath: "res://assets/models/tree.obj",
    parentPath: ".",
    name: "PlacedTree",
    position: { x: 1, y: 2, z: 3 },
    scale: { x: 1, y: 1, z: 1 },
    createCollider: true,
    materialColor: { r: 0.2, g: 0.4, b: 0.8, a: 1 },
    timeoutMs: 1_000,
  });
  requestPath = await waitForEditorControlAction(path.join(config.bridgeDir, "requests"), "place_asset_in_scene", request.request_id);
  request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.payload.action, "place_asset_in_scene");
  assert.equal(request.payload.params?.asset_path, "res://assets/models/tree.obj");
  assert.equal(request.payload.params?.parent_path, ".");
  assert.equal(request.payload.params?.name, "PlacedTree");
  assert.deepEqual(request.payload.params?.position, { x: 1, y: 2, z: 3 });
  assert.equal(request.payload.params?.create_collider, true);
  assert.deepEqual(request.payload.params?.material_color, { r: 0.2, g: 0.4, b: 0.8, a: 1 });
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: {
      action: "place_asset_in_scene",
      changed: true,
      placement_options: {
        create_collider: { requested: true, status: "created" },
        material_color: { requested: true, status: "applied" },
      },
    },
  });
  await fs.rm(requestPath);
  requestPath = await waitForNewestRequest(path.join(config.bridgeDir, "requests"), request.request_id);
  request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown>; reason?: unknown };
  };
  assert.equal(request.type, "capture_viewport_screenshot");
  assert.equal((request.payload as Record<string, unknown>).reason, "place_asset_in_scene");
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { path: "C:/tmp/place-asset.png" },
  });
  await fs.rm(requestPath);
  const placeAssetResult = await placeAssetPending;
  assert.equal(placeAssetResult.isError, false);
  assert.equal(typeof placeAssetResult.structuredContent?.screenshot_after_action, "object");

  await fs.writeFile(path.join(config.projectRoot, "assets", "models", "tree_preview.png"), "png fixture", "utf8");
  const placePngPending = handlers["godot.place_asset_in_scene"]({
    assetPath: "res://assets/models/tree_preview.png",
    parentPath: ".",
    name: "TreePreview",
    captureScreenshot: false,
    timeoutMs: 1_000,
  });
  requestPath = await waitForEditorControlAction(path.join(config.bridgeDir, "requests"), "place_asset_in_scene", request.request_id);
  request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.payload.action, "place_asset_in_scene");
  assert.equal(request.payload.params?.asset_path, "res://assets/models/tree_preview.png");
  assert.equal(request.payload.params?.name, "TreePreview");
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "place_asset_in_scene", changed: true, placement_kind: "sprite_2d" },
  });
  await fs.rm(requestPath);
  assert.equal((await placePngPending).isError, false);

  const signalPending = handlers["godot.connect_signal"]({
    sourceNodePath: "Button",
    signalName: "pressed",
    targetNodePath: ".",
    methodName: "_on_button_pressed",
    timeoutMs: 1_000,
  });
  requestPath = await waitForEditorControlAction(path.join(config.bridgeDir, "requests"), "connect_signal", request.request_id);
  request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.payload.action, "connect_signal");
  assert.equal(request.payload.params?.source_node_path, "Button");
  assert.equal(request.payload.params?.signal_name, "pressed");
  assert.equal(request.payload.params?.target_node_path, ".");
  assert.equal(request.payload.params?.method_name, "_on_button_pressed");
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "connect_signal", changed: true },
  });
  assert.equal((await signalPending).isError, false);

  const badName = await handlers["godot.rename_node"]({ nodePath: "Marker", newName: "../bad" });
  assert.equal(badName.isError, true);
  assert.equal((badName.structuredContent?.error as { code?: string })?.code, "invalid_node_name");

  const badScene = await handlers["godot.instance_scene"]({ scenePath: "res://../outside.tscn" });
  assert.equal(badScene.isError, true);
  assert.equal((badScene.structuredContent?.error as { code?: string })?.code, "invalid_scene_path");

  const badAsset = await handlers["godot.place_asset_in_scene"]({ assetPath: "res://../outside.obj" });
  assert.equal(badAsset.isError, true);
  assert.equal((badAsset.structuredContent?.error as { code?: string })?.code, "invalid_asset_path");
});

test("bridge notes append writes editor_control request", async () => {
  const config = await makeConfig();
  await writeLiveHeartbeat(config.bridgeDir);
  const handlers = createToolHandlers(config);

  const pending = handlers["godot.notes_append"]({ text: "Remember current camera framing.", timeoutMs: 1_000 });
  const requestPath = await waitForRequest(path.join(config.bridgeDir, "requests"));
  const request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
    request_id: string;
    type: string;
    payload: { action?: unknown; params?: Record<string, unknown> };
  };
  assert.equal(request.type, "editor_control");
  assert.equal(request.payload.action, "notes_append");
  assert.equal(request.payload.params?.text, "Remember current camera framing.");
  await writeAddonResponse(config.bridgeDir, request.request_id, {
    status: "succeeded",
    data: { action: "notes_append", notes_count: 1 },
  });
  assert.equal((await pending).isError, false);
});

test("preview diff handler returns invalid_request instead of throwing", async () => {
  const config = await makeConfig();
  const handlers = createToolHandlers(config);

  const result = await handlers["godot.preview_scene_diff"]({
    path: "../outside.tscn",
    proposedContent: "",
  });

  assert.equal(result.isError, true);
  assert.equal(result.structuredContent?.status, "invalid_request");
});

async function makeConfig(): Promise<ServerConfig> {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-tools-"));
  return {
    projectRoot,
    bridgeDir: path.join(projectRoot, ".godot", "godot_codex_bridge"),
    godotExecutable: process.execPath,
    addonRequestTimeoutMs: 250,
    runSceneTimeoutMs: 1_000,
  };
}

async function waitForRequest(requestsDir: string): Promise<string> {
  const deadline = Date.now() + 1_000;
  while (Date.now() <= deadline) {
    try {
      const entries = await fs.readdir(requestsDir);
      const first = entries.find((entry) => entry.endsWith(".json"));
      if (first) {
        return path.join(requestsDir, first);
      }
    } catch {
      // Directory may not exist until the request is created.
    }
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  throw new Error("request not written");
}

async function waitForNewestRequest(requestsDir: string, previousRequestId: string): Promise<string> {
  const deadline = Date.now() + 1_000;
  while (Date.now() <= deadline) {
    try {
      const entries = await fs.readdir(requestsDir);
      const next = entries.find((entry) => entry.endsWith(".json") && !entry.startsWith(previousRequestId));
      if (next) {
        return path.join(requestsDir, next);
      }
    } catch {
      // Directory may not exist until the request is created.
    }
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  throw new Error("new request not written");
}

async function waitForEditorControlAction(requestsDir: string, action: string, previousRequestId?: string): Promise<string> {
  const deadline = Date.now() + 1_000;
  while (Date.now() <= deadline) {
    try {
      const entries = (await fs.readdir(requestsDir)).filter((entry) => entry.endsWith(".json")).sort();
      for (const entry of entries) {
        const requestPath = path.join(requestsDir, entry);
        const request = JSON.parse(await fs.readFile(requestPath, "utf8")) as {
          request_id?: string;
          type?: string;
          payload?: { action?: unknown };
        };
        if (previousRequestId !== undefined && request.request_id === previousRequestId) {
          continue;
        }
        if (request.type === "editor_control" && request.payload?.action === action) {
          return requestPath;
        }
      }
    } catch {
      // Directory may not exist until the request is created, or a file may be mid-write.
    }
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  throw new Error(`editor_control request not written for action: ${action}`);
}

async function writeAddonResponse(bridgeDir: string, requestId: string, response: Record<string, unknown>): Promise<void> {
  await fs.mkdir(path.join(bridgeDir, "responses"), { recursive: true });
  await fs.writeFile(path.join(bridgeDir, "responses", `${requestId}.json`), JSON.stringify(response), "utf8");
}

async function writeLiveHeartbeat(bridgeDir: string): Promise<void> {
  await fs.mkdir(bridgeDir, { recursive: true });
  await fs.writeFile(
    path.join(bridgeDir, "heartbeat.json"),
    JSON.stringify({
      protocol_version: "godot-codex-bridge/0.1",
      addon_active: true,
      updated_at: new Date().toISOString(),
    }),
    "utf8",
  );
}

function screenshotFixture(index: number, localPath?: string): Record<string, unknown> {
  return {
    protocol_version: "godot-codex-bridge/0.1",
    screenshot_id: `viewport_3d_test_${index}`,
    captured_at: `2026-06-21T12:00:0${index}.000Z`,
    scene_path: "res://scenes/main.tscn",
    selected_node_paths: [],
    artifact: {
      local_path: localPath ?? `C:\\temp\\viewport_3d_test_${index}.png`,
      project_relative_path: `.godot/godot_codex_bridge/artifacts/screenshots/viewport_3d_test_${index}.png`,
      format: "png",
      width: 1280,
      height: 720,
      byte_size: 1024 + index,
    },
    viewport: {
      source: "editor_3d_viewport",
      mode: "unknown",
      camera_node_path: null,
    },
    privacy: {
      classification: "local_sensitive_evidence",
      external_upload_allowed: false,
    },
  };
}
