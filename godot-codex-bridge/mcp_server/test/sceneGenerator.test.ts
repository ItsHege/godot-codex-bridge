import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { generateSceneFromPrompt } from "../src/sceneGenerator.js";

test("generateSceneFromPrompt returns live editor plan without generated content", async () => {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-generate-preview-"));
  const bridgeDir = path.join(projectRoot, ".godot", "godot_codex_bridge");
  await fs.mkdir(path.join(projectRoot, "scenes"), { recursive: true });
  await fs.writeFile(path.join(projectRoot, "scenes", "generated_room.tscn"), "[gd_scene format=3]\n", "utf8");

  const result = await generateSceneFromPrompt(projectRoot, bridgeDir, {
    prompt: "forest test scene with trees, wall, water and jump platforms",
    path: "scenes/generated_room.tscn",
  });

  assert.equal(result.status, "ok");
  assert.equal(result.generator_version, "godot-codex-bridge/scene-generator-live-plan-v1");
  assert.equal(result.mode, "live_editor_plan");
  assert.equal(result.deprecated_template_generation, true);
  assert.equal(result.write_behavior, "no_file_write_no_generated_scene_content_no_apply");
  assert.equal("proposed_content" in result, false);
  assert.equal("preview" in result, false);
  assert.equal(result.target_exists, true);
  assert.deepEqual((result.blueprint as { features?: string[] }).features, ["ground", "wall", "trees", "water", "platforms"]);
  assert.equal((result.blueprint as { planned_action_count?: number }).planned_action_count! > 6, true);
  assert.equal((result.blueprint as { suggested_tool_call_count?: number }).suggested_tool_call_count! > 10, true);
  assert.equal((result.recommended_tools as string[]).includes("godot.create_node"), true);
  const suggestedCalls = result.suggested_tool_calls as Array<{ tool: string; args?: Record<string, unknown> }>;
  assert.equal(suggestedCalls.some((call) => call.tool === "godot.open_scene"), true);
  assert.equal(suggestedCalls.some((call) => call.tool === "godot.create_node" && call.args?.className === "Camera3D"), true);
  assert.equal(suggestedCalls.some((call) => call.tool === "godot.create_node_resource" && call.args?.nodePath === "Ground"), true);
  assert.equal(suggestedCalls.some((call) => call.tool === "godot.editor_batch"), true);
  assert.equal(suggestedCalls.some((call) => call.tool.includes("+")), false);
  assert.equal(JSON.stringify(suggestedCalls).includes("res://path/to"), false);
  assert.equal(await fs.readFile(path.join(projectRoot, "scenes", "generated_room.tscn"), "utf8"), "[gd_scene format=3]\n");
});

test("generateSceneFromPrompt rejects legacy apply mode", async () => {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-generate-apply-"));
  const bridgeDir = path.join(projectRoot, ".godot", "godot_codex_bridge");

  const result = await generateSceneFromPrompt(projectRoot, bridgeDir, {
    prompt: "small cube room",
    path: "scenes/generated_room.tscn",
    apply: true,
    approvalToken: "APPROVE_GODOT_CODEX_BRIDGE_APPLY",
  });

  assert.equal(result.status, "invalid_request");
  assert.equal((result.error as { code?: string }).code, "scene_generator_apply_removed");
  await assert.rejects(fs.access(path.join(projectRoot, "scenes", "generated_room.tscn")));
});

test("generateSceneFromPrompt validates target as a tscn scene path", async () => {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-generate-invalid-path-"));
  const bridgeDir = path.join(projectRoot, ".godot", "godot_codex_bridge");

  const result = await generateSceneFromPrompt(projectRoot, bridgeDir, {
    prompt: "make a script",
    path: "scripts/generated.gd",
  });

  assert.equal(result.status, "invalid_request");
  assert.equal((result.error as { code?: string }).code, "target_scene_must_be_tscn");
});

test("generateSceneFromPrompt does not invent scene features for vague prompts", async () => {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-generate-vague-"));
  const bridgeDir = path.join(projectRoot, ".godot", "godot_codex_bridge");
  await fs.mkdir(path.join(projectRoot, "scenes"), { recursive: true });
  await fs.writeFile(path.join(projectRoot, "scenes", "current.tscn"), "[gd_scene format=3]\n", "utf8");

  const result = await generateSceneFromPrompt(projectRoot, bridgeDir, {
    prompt: "make this feel more dramatic",
    path: "scenes/current.tscn",
  });

  assert.equal(result.status, "ok");
  assert.deepEqual((result.blueprint as { features?: string[] }).features, []);
  assert.equal((result.suggested_tool_calls as Array<{ tool: string }>).some((call) => call.tool === "godot.create_node"), false);
  assert.equal(JSON.stringify(result.planned_actions).includes("add_ground"), false);
  assert.equal(JSON.stringify(result.planned_actions).includes("add_wall"), false);
});

test("generateSceneFromPrompt plans explicit camera and lighting requests", async () => {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-generate-camera-light-"));
  const bridgeDir = path.join(projectRoot, ".godot", "godot_codex_bridge");
  await fs.mkdir(path.join(projectRoot, "scenes"), { recursive: true });
  await fs.writeFile(path.join(projectRoot, "scenes", "current.tscn"), "[gd_scene format=3]\n", "utf8");

  const result = await generateSceneFromPrompt(projectRoot, bridgeDir, {
    prompt: "add camera and dramatic lighting",
    path: "scenes/current.tscn",
  });

  assert.equal(result.status, "ok");
  assert.deepEqual((result.blueprint as { features?: string[] }).features, []);
  const suggestedCalls = result.suggested_tool_calls as Array<{ tool: string; args?: Record<string, unknown> }>;
  assert.equal(suggestedCalls.some((call) => call.tool === "godot.create_node" && call.args?.className === "Camera3D"), true);
  assert.equal(suggestedCalls.some((call) => call.tool === "godot.create_node" && call.args?.className === "DirectionalLight3D"), true);
});
