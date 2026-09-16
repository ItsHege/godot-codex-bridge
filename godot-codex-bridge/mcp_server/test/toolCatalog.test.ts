import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import test from "node:test";

import { getToolCatalog, TOOL_CATALOG, TOOL_CATEGORIES } from "../src/toolCatalog.js";
import { createToolHandlers } from "../src/tools.js";
import type { ServerConfig } from "../src/types.js";

test("getToolCatalog returns grouped tool selection guidance", () => {
  const result = getToolCatalog(undefined, undefined, "full");

  assert.equal(result.status, "ok");
  assert.equal(result.catalog_version, "godot-tool-catalog-v1");
  assert.equal(result.view, "full");
  assert.equal(result.total_tools, TOOL_CATALOG.length);
  assert.equal((result.tools as unknown[]).length, TOOL_CATALOG.length);
  assert.equal(result.omitted_tool_count, 0);
  assert.equal((result.categories as Array<{ name: string }>).some((category) => category.name === "scene_mutation"), true);
  assert.equal((result.recommended_workflows as Array<{ name: string }>).some((workflow) => workflow.name === "safe_live_scene_edit"), true);
  assert.equal(TOOL_CATALOG.some((tool) => tool.name === "godot.project_get_map"), true);
  assert.equal(TOOL_CATALOG.some((tool) => tool.name === "godot.project_script_map"), true);
  assert.equal(TOOL_CATALOG.some((tool) => tool.name === "godot.editor_capabilities"), true);
  assert.equal(TOOL_CATALOG.some((tool) => tool.name === "godot.editor_viewport_navigate"), true);
  assert.equal(TOOL_CATALOG.some((tool) => tool.name === "godot.placement_check"), true);
  assert.equal(TOOL_CATALOG.some((tool) => tool.name === "godot.snap_to_ground"), true);
  assert.equal(TOOL_CATALOG.some((tool) => tool.name === "godot.snap_to_grid"), true);
  assert.equal(TOOL_CATALOG.some((tool) => tool.name === "godot.undo_last_bridge_action"), true);
  assert.equal(TOOL_CATALOG.some((tool) => tool.name === "godot.runtime_get_events"), true);
  assert.equal(TOOL_CATALOG.some((tool) => tool.name === "godot.emergency_stop"), true);
  assert.equal(TOOL_CATALOG.some((tool) => tool.name === "godot.playtest_input"), true);
  assert.equal(TOOL_CATALOG.some((tool) => tool.name === "godot.run_playtest_scenario"), true);
  assert.equal(TOOL_CATALOG.some((tool) => tool.name === "godot.performance_get_snapshot"), true);
  assert.equal(TOOL_CATALOG.some((tool) => tool.name === "godot.capture_multi_view_screenshots"), true);
});

test("getToolCatalog filters by category and rejects unknown categories", () => {
  const sceneMutation = getToolCatalog("scene_mutation", undefined, "full");
  assert.equal(sceneMutation.status, "ok");
  assert.equal(sceneMutation.filtered_category, "scene_mutation");
  assert.equal((sceneMutation.tools as Array<{ category: string }>).every((tool) => tool.category === "scene_mutation"), true);
  assert.equal((sceneMutation.tools as Array<{ name: string }>).some((tool) => tool.name === "godot.create_node"), true);

  const invalid = getToolCatalog("not_a_category");
  assert.equal(invalid.status, "invalid_request");
  assert.equal((invalid.error as { code?: string }).code, "unknown_tool_category");
  assert.deepEqual((invalid.error as { known_categories?: string[] }).known_categories, Object.keys(TOOL_CATEGORIES));
});

test("getToolCatalog defaults omitted view to compact", () => {
  const result = getToolCatalog();

  assert.equal(result.status, "ok");
  assert.equal(result.view, "compact");
  assert.deepEqual(result.tools, []);
  assert.equal(result.omitted_tool_count, TOOL_CATALOG.length);
});

test("getToolCatalog recommends workflows from intent", () => {
  const liveEdit = getToolCatalog(undefined, "move a selected node, inspect screenshot, then save the scene");
  assert.equal(liveEdit.status, "ok");
  assert.equal(liveEdit.intent, "move a selected node, inspect screenshot, then save the scene");
  const matched = liveEdit.matched_workflows as Array<{ name: string; score: number; tools: string[] }>;
  assert.equal(matched[0].name, "safe_live_scene_edit");
  assert.equal(matched[0].score > 0, true);
  assert.deepEqual(liveEdit.recommended_next_tools, matched[0].tools.slice(0, 6));
  assert.equal((liveEdit.recommended_next_tools as string[]).includes("godot.undo_last_bridge_action"), true);
  assert.equal((liveEdit.recommended_next_tools as string[]).includes("godot.save_scene"), true);

  const runtime = getToolCatalog(undefined, "run playtest and capture crash output");
  assert.equal(((runtime.matched_workflows as Array<{ name: string }>)[0]).name, "runtime_smoke");
  assert.equal((runtime.recommended_next_tools as string[]).includes("godot.run_test_scene"), true);
  assert.equal((runtime.recommended_next_tools as string[]).includes("godot.playtest_input"), true);
  assert.equal((runtime.recommended_next_tools as string[]).includes("godot.runtime_get_events"), true);
});

test("getToolCatalog compact view routes without returning the flat tool list", () => {
  const result = getToolCatalog(undefined, "open scene, inspect selected node and screenshot", "compact");

  assert.equal(result.status, "ok");
  assert.equal(result.view, "compact");
  assert.equal((result.tools as unknown[]).length, 0);
  assert.equal(result.omitted_tool_count, TOOL_CATALOG.length);
  const summaries = result.compact_category_summaries as Array<{ name: string; primary_tools: string[] }>;
  assert.equal(summaries.some((summary) => summary.name === "editor_navigation"), true);
  assert.equal(summaries.every((summary) => summary.primary_tools.length <= 4), true);
  const matched = result.matched_workflows as Array<{ name: string; tools: string[] }>;
  assert.equal(matched.length > 0, true);
  assert.equal((result.recommended_next_tools as string[]).length > 0, true);
});

test("getToolCatalog compact category view omits only selected category tools", () => {
  const result = getToolCatalog("runtime", "run current scene", "compact");

  assert.equal(result.status, "ok");
  assert.equal(result.filtered_category, "runtime");
  assert.equal((result.tools as unknown[]).length, 0);
  assert.equal(result.omitted_tool_count, TOOL_CATALOG.filter((tool) => tool.category === "runtime").length);
  const summaries = result.compact_category_summaries as Array<{ name: string }>;
  assert.deepEqual(summaries.map((summary) => summary.name), ["runtime"]);
});

test("tool catalog covers every registered godot tool", async () => {
  const serverSource = await fs.readFile(path.resolve("src", "server.ts"), "utf8");
  const registeredTools = [...serverSource.matchAll(/server\.registerTool\(\s*"([^"]+)"/g)]
    .map((match) => match[1])
    .filter((name) => name.startsWith("godot."))
    .sort();

  const catalogTools = TOOL_CATALOG.map((entry) => entry.name).sort();

  assert.deepEqual(catalogTools, registeredTools);
  assert.equal(new Set(catalogTools).size, catalogTools.length);
});

test("tool catalog handler defaults omitted view to compact and preserves explicit full", async () => {
  const config: ServerConfig = {
    projectRoot: path.resolve("test-fixture"),
    bridgeDir: path.resolve("test-fixture", ".godot", "godot_codex_bridge"),
    godotExecutable: "godot",
    addonRequestTimeoutMs: 100,
    runSceneTimeoutMs: 100,
  };
  const handlers = createToolHandlers(config);
  const result = await handlers["godot.get_tool_catalog"]({ category: "orientation", intent: "orient before editing" });

  assert.equal(result.isError, false);
  assert.equal(result.structuredContent?.status, "ok");
  assert.equal(result.structuredContent?.view, "compact");
  assert.equal(result.structuredContent?.intent, "orient before editing");
  assert.deepEqual(result.structuredContent?.tools, []);
  const recommended = result.structuredContent?.recommended_next_tools as string[] | undefined;
  assert.equal(recommended?.includes("godot.bridge_status"), true);
  assert.equal(recommended?.includes("godot.project_get_map"), true);
  assert.equal(recommended?.includes("godot.project_script_map"), true);
  assert.equal(recommended?.includes("godot.editor_capabilities"), true);

  const fullResult = await handlers["godot.get_tool_catalog"]({ category: "orientation", view: "full" });
  const expectedOrientationCount = TOOL_CATALOG.filter((tool) => tool.category === "orientation").length;
  assert.equal(fullResult.isError, false);
  assert.equal(fullResult.structuredContent?.status, "ok");
  assert.equal(fullResult.structuredContent?.view, "full");
  assert.equal((fullResult.structuredContent?.tools as unknown[]).length, expectedOrientationCount);
  assert.equal(fullResult.structuredContent?.omitted_tool_count, 0);
});
