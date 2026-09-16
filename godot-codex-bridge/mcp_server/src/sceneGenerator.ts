import fs from "node:fs/promises";

import { resolvePreviewTarget } from "./diffPreview.js";
import type { JsonObject, ToolEnvelope } from "./types.js";

const GENERATOR_VERSION = "godot-codex-bridge/scene-generator-live-plan-v1";

export interface GenerateSceneOptions {
  prompt: string;
  path: string;
  apply?: boolean;
  approvalToken?: string;
}

interface ScenePlan {
  targetScene: string;
  targetExists: boolean;
  features: string[];
  plannedActions: JsonObject[];
  suggestedToolCalls: JsonObject[];
  recommendedTools: string[];
  notes: string[];
}

export async function generateSceneFromPrompt(
  projectRoot: string,
  _bridgeDir: string,
  options: GenerateSceneOptions,
): Promise<ToolEnvelope> {
  if (!options.prompt || !options.path) {
    return {
      status: "invalid_request",
      error: {
        code: "prompt_and_path_required",
        message: "Provide prompt and project-relative .tscn path.",
      },
    };
  }

  if (options.apply) {
    return {
      status: "invalid_request",
      generator_version: GENERATOR_VERSION,
      error: {
        code: "scene_generator_apply_removed",
        message:
          "generate_scene_from_prompt no longer writes generated .tscn templates. Use the live editor tools, review changes in Godot, then call godot.save_scene when ready.",
      },
      replacement_tools: [
        "godot.open_scene",
        "godot.editor_batch",
        "godot.create_node",
        "godot.create_node_resource",
        "godot.set_node_transform",
        "godot.set_node_properties",
        "godot.save_scene",
      ],
    };
  }

  const target = resolvePreviewTarget(projectRoot, options.path);
  if (!target.relativePath.toLowerCase().endsWith(".tscn")) {
    return {
      status: "invalid_request",
      generator_version: GENERATOR_VERSION,
      error: {
        code: "target_scene_must_be_tscn",
        message: "Scene prompt planning only accepts project-relative .tscn paths.",
        path: target.relativePath,
      },
    };
  }

  const targetExists = await pathExists(target.absolutePath);
  const plan = createLiveEditorPlan(options.prompt, `res://${target.relativePath}`, targetExists);

  return {
    status: "ok",
    generator_version: GENERATOR_VERSION,
    mode: "live_editor_plan",
    deprecated_template_generation: true,
    prompt: options.prompt,
    path: target.relativePath,
    target_scene: plan.targetScene,
    target_exists: plan.targetExists,
    blueprint: {
      root_name: safeNodeName(options.prompt),
      features: plan.features,
      planned_action_count: plan.plannedActions.length,
      suggested_tool_call_count: plan.suggestedToolCalls.length,
      notes: plan.notes,
    },
    planned_actions: plan.plannedActions,
    suggested_tool_calls: plan.suggestedToolCalls,
    recommended_tools: plan.recommendedTools,
    execution_order: "inspect_open_focus_mutate_capture_then_save_when_approved",
    write_behavior: "no_file_write_no_generated_scene_content_no_apply",
    apply_hint:
      "This tool intentionally does not return proposed_content or apply files. Execute the plan with live editor tools, inspect the scene, then save explicitly with godot.save_scene if the bridge permission is enabled.",
  };
}

function createLiveEditorPlan(prompt: string, targetScene: string, targetExists: boolean): ScenePlan {
  const lower = normalizePrompt(prompt);
  const features = detectFeatures(lower);
  const asksForCamera = hasAny(lower, ["camera", "kamera"]);
  const asksForLight = hasAny(lower, ["light", "lighting", "sviesa", "šviesa", "apsviet", "apšviet"]);
  const plannedActions: JsonObject[] = [];
  const suggestedToolCalls: JsonObject[] = [];

  plannedActions.push({
    step: "inspect_editor_state",
    tool: "godot.editor_get_state",
    purpose: "Confirm active scene, permissions and live bridge state before mutating the editor.",
  });
  suggestedToolCalls.push(toolCall("godot.editor_get_state", {}));

  if (targetExists) {
    plannedActions.push({
      step: "open_target_scene",
      tool: "godot.open_scene",
      args: { scenePath: targetScene, makeMainScreen: "3D", selectInFileSystem: true },
    });
    suggestedToolCalls.push(toolCall("godot.open_scene", { scenePath: targetScene, makeMainScreen: "3D", selectInFileSystem: true }));
  } else {
    plannedActions.push({
      step: "choose_scene_creation_path",
      tool: "manual_or_reviewed_diff_required",
      purpose:
        "The live editor tool layer can edit an open scene but does not yet create a brand-new saved scene file at an arbitrary path.",
      targetScene,
    });
  }

  plannedActions.push({
    step: "focus_3d_editor",
    tool: "godot.editor_focus",
    args: { mainScreen: "3D" },
  });
  suggestedToolCalls.push(toolCall("godot.editor_focus", { mainScreen: "3D" }));

  if ((features.length > 0 || asksForCamera) && !hasAny(lower, ["no camera", "be kameros"])) {
    plannedActions.push({
      step: "ensure_camera",
      tool: "godot.create_node, godot.set_node_transform, godot.set_node_properties",
      node: { className: "Camera3D", name: "Camera3D", parentPath: "." },
      properties: [{ property: "current", value: true }],
    });
    suggestedToolCalls.push(
      toolCall("godot.create_node", { parentPath: ".", className: "Camera3D", name: "Camera3D" }),
      toolCall("godot.set_node_transform", { nodePath: "Camera3D", position: [0, 4, 8], rotationDegrees: [-25, 0, 0] }),
      toolCall("godot.set_node_properties", { nodePath: "Camera3D", changes: [{ property: "current", value: true }] }),
    );
  }

  if ((features.length > 0 || asksForLight) && !hasAny(lower, ["no light", "be svies", "be švies", "dark only"])) {
    plannedActions.push({
      step: "ensure_key_light",
      tool: "godot.create_node, godot.set_node_transform, godot.set_node_properties",
      node: { className: "DirectionalLight3D", name: "KeyLight", parentPath: "." },
      properties: [
        { property: "light_energy", value: 1.35 },
        { property: "shadow_enabled", value: true },
      ],
    });
    suggestedToolCalls.push(
      toolCall("godot.create_node", { parentPath: ".", className: "DirectionalLight3D", name: "KeyLight" }),
      toolCall("godot.set_node_transform", { nodePath: "KeyLight", rotationDegrees: [-45, 35, 0] }),
      toolCall("godot.set_node_properties", { nodePath: "KeyLight", changes: [
        { property: "light_energy", value: 1.35 },
        { property: "shadow_enabled", value: true },
      ] }),
    );
  }

  for (const feature of features) {
    const plan = featurePlan(feature);
    plannedActions.push(plan.action);
    suggestedToolCalls.push(...plan.suggestedToolCalls);
  }

  plannedActions.push({
    step: "capture_evidence",
    tool: "godot.editor_batch",
    args: {
      actions: [
        { action: "refresh_context" },
        { action: "capture_viewport_screenshot" },
      ],
    },
  });
  suggestedToolCalls.push(toolCall("godot.editor_batch", {
    actions: [
      { action: "refresh_context" },
      { action: "capture_viewport_screenshot" },
    ],
  }));

  plannedActions.push({
    step: "persist_when_approved",
    tool: "godot.save_scene",
    permission: "allow_scene_save",
    purpose: "Save only after inspecting the live editor result and confirming the scene should persist.",
  });

  return {
    targetScene,
    targetExists,
    features,
    plannedActions,
    suggestedToolCalls,
    recommendedTools: [
      "godot.editor_get_state",
      "godot.open_scene",
      "godot.editor_focus",
      "godot.editor_batch",
      "godot.create_node",
      "godot.create_node_resource",
      "godot.set_resource_properties",
      "godot.set_node_transform",
      "godot.set_node_properties",
      "godot.capture_viewport_screenshot",
      "godot.save_scene",
    ],
    notes: [
      "This is a live-editor plan, not a generated .tscn template.",
      "Use Godot UndoRedo-backed tools for mutations and inspect the result before saving.",
      "If the target scene does not exist yet, create/open a scene first; arbitrary new scene file creation is intentionally not done by this planner.",
    ],
  };
}

function featurePlan(feature: string): { action: JsonObject; suggestedToolCalls: JsonObject[] } {
  switch (feature) {
    case "ground":
      return {
        action: {
          step: "add_ground",
          tool: "godot.create_node, godot.create_node_resource",
          node: { className: "MeshInstance3D", name: "Ground", parentPath: "." },
          resources: [{ property: "mesh", resourceClass: "BoxMesh", changes: [{ property: "size", value: [18, 0.25, 18] }] }],
          follow_up: "Add StaticBody3D/CollisionShape3D when collision is required.",
        },
        suggestedToolCalls: [
          toolCall("godot.create_node", { parentPath: ".", className: "MeshInstance3D", name: "Ground" }),
          toolCall("godot.create_node_resource", {
            nodePath: "Ground",
            property: "mesh",
            resourceClass: "BoxMesh",
            changes: [{ property: "size", value: [18, 0.25, 18] }],
          }),
        ],
      };
    case "wall":
      return {
        action: {
          step: "add_wall",
          tool: "godot.create_node, godot.create_node_resource, godot.set_node_transform",
          node: { className: "MeshInstance3D", name: "NorthWall", parentPath: "." },
          resources: [{ property: "mesh", resourceClass: "BoxMesh", changes: [{ property: "size", value: [10, 2.5, 0.35] }] }],
        },
        suggestedToolCalls: [
          toolCall("godot.create_node", { parentPath: ".", className: "MeshInstance3D", name: "NorthWall" }),
          toolCall("godot.create_node_resource", {
            nodePath: "NorthWall",
            property: "mesh",
            resourceClass: "BoxMesh",
            changes: [{ property: "size", value: [10, 2.5, 0.35] }],
          }),
          toolCall("godot.set_node_transform", { nodePath: "NorthWall", position: [0, 1.25, -5] }),
        ],
      };
    case "trees":
      return {
        action: {
          step: "add_tree_placeholders_or_instance_assets",
          tool: "godot.search_project_files, godot.place_asset_in_scene, godot.create_node",
          purpose: "Prefer existing tree assets or instanced scenes; fallback to simple MeshInstance3D placeholders only if appropriate.",
        },
        suggestedToolCalls: [
          toolCall("godot.search_project_files", { query: "tree", maxResults: 12 }),
          toolCall("godot.create_node", { parentPath: ".", className: "Node3D", name: "TreeA" }),
          toolCall("godot.create_node", { parentPath: "TreeA", className: "MeshInstance3D", name: "Trunk" }),
          toolCall("godot.create_node_resource", {
            nodePath: "TreeA/Trunk",
            property: "mesh",
            resourceClass: "CylinderMesh",
          }),
          toolCall("godot.set_node_transform", { nodePath: "TreeA/Trunk", position: [0, 1.0, 0], scale: [0.25, 1.0, 0.25] }),
          toolCall("godot.create_node", { parentPath: "TreeA", className: "MeshInstance3D", name: "Canopy" }),
          toolCall("godot.create_node_resource", {
            nodePath: "TreeA/Canopy",
            property: "mesh",
            resourceClass: "SphereMesh",
          }),
          toolCall("godot.set_node_transform", { nodePath: "TreeA/Canopy", position: [0, 2.2, 0], scale: [1.2, 0.8, 1.2] }),
          toolCall("godot.set_node_transform", { nodePath: "TreeA", position: [-3, 0, -2] }),
        ],
      };
    case "water":
      return {
        action: {
          step: "add_water_patch",
          tool: "godot.create_node, godot.create_node_resource, godot.set_resource_properties",
          node: { className: "MeshInstance3D", name: "WaterPatch", parentPath: "." },
        },
        suggestedToolCalls: [
          toolCall("godot.create_node", { parentPath: ".", className: "MeshInstance3D", name: "WaterPatch" }),
          toolCall("godot.create_node_resource", {
            nodePath: "WaterPatch",
            property: "mesh",
            resourceClass: "PlaneMesh",
            changes: [{ property: "size", value: [6, 4] }],
          }),
          toolCall("godot.set_node_transform", { nodePath: "WaterPatch", position: [2, 0.04, 2] }),
        ],
      };
    case "rocks":
      return {
        action: {
          step: "add_rocks",
          tool: "godot.search_project_files, godot.place_asset_in_scene, godot.create_node",
          purpose: "Create or instance a few rock meshes, then position them with set_node_transform.",
        },
        suggestedToolCalls: [
          toolCall("godot.search_project_files", { query: "rock", maxResults: 12 }),
          toolCall("godot.create_node", { parentPath: ".", className: "MeshInstance3D", name: "RockA" }),
          toolCall("godot.create_node_resource", { nodePath: "RockA", property: "mesh", resourceClass: "SphereMesh" }),
          toolCall("godot.set_node_transform", { nodePath: "RockA", position: [4, 0.35, -1], scale: [1.2, 0.7, 1.0] }),
        ],
      };
    case "path":
      return {
        action: {
          step: "add_path",
          tool: "godot.create_node, godot.create_node_resource",
          node: { className: "MeshInstance3D", name: "Path", parentPath: "." },
        },
        suggestedToolCalls: [
          toolCall("godot.create_node", { parentPath: ".", className: "MeshInstance3D", name: "Path" }),
          toolCall("godot.create_node_resource", {
            nodePath: "Path",
            property: "mesh",
            resourceClass: "BoxMesh",
            changes: [{ property: "size", value: [2.4, 0.08, 12] }],
          }),
        ],
      };
    case "platforms":
      return {
        action: {
          step: "add_jump_platforms",
          tool: "godot.create_node, godot.create_node_resource, godot.set_node_transform",
          purpose: "Create several platform nodes with collision, then validate camera framing.",
        },
        suggestedToolCalls: [
          toolCall("godot.create_node", { parentPath: ".", className: "MeshInstance3D", name: "JumpPlatformA" }),
          toolCall("godot.create_node_resource", {
            nodePath: "JumpPlatformA",
            property: "mesh",
            resourceClass: "BoxMesh",
            changes: [{ property: "size", value: [2.5, 0.35, 2.5] }],
          }),
          toolCall("godot.set_node_transform", { nodePath: "JumpPlatformA", position: [-2, 1.2, -1] }),
        ],
      };
    default:
      return {
        action: {
          step: `plan_${feature}`,
          tool: "godot.editor_get_state",
          purpose: "Inspect the current scene before choosing a concrete editor action.",
        },
        suggestedToolCalls: [toolCall("godot.editor_get_state", {})],
      };
  }
}

function toolCall(tool: string, args: JsonObject): JsonObject {
  return { tool, args };
}

function detectFeatures(lower: string): string[] {
  const features = new Set<string>();
  if (hasAny(lower, [
    "ground",
    "floor",
    "terrain",
    "land",
    "field",
    "map",
    "level",
    "environment",
    "forest",
    "woods",
    "room",
    "arena",
    "zeme",
    "žemė",
    "grindys",
    "reljefas",
    "aplinka",
    "miskas",
    "miškas",
    "kambarys",
  ])) features.add("ground");
  if (hasAny(lower, ["wall", "walls", "siena", "sienos", "fence", "barrier", "room", "kambarys"])) features.add("wall");
  if (hasAny(lower, ["tree", "trees", "forest", "woods", "medis", "medziai", "medžiai", "miskas", "miškas"])) features.add("trees");
  if (hasAny(lower, ["water", "river", "lake", "pond", "vanduo", "upe", "upė", "ezeras", "ežeras"])) features.add("water");
  if (hasAny(lower, ["rock", "rocks", "stone", "akmuo", "akmen", "uola"])) features.add("rocks");
  if (hasAny(lower, ["path", "road", "trail", "kelias", "takas"])) features.add("path");
  if (hasAny(lower, ["platform", "platforms", "jump", "suolis", "šuolis", "floating"])) features.add("platforms");
  return [...features];
}

function normalizePrompt(prompt: string): string {
  return prompt.toLowerCase().normalize("NFC");
}

function hasAny(value: string, needles: string[]): boolean {
  return needles.some((needle) => value.includes(needle));
}

function safeNodeName(prompt: string): string {
  const cleaned = prompt
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^A-Za-z0-9]+/g, " ")
    .trim()
    .split(/\s+/)
    .slice(0, 4)
    .map((part) => part.slice(0, 1).toUpperCase() + part.slice(1))
    .join("");
  return cleaned || "GeneratedScene";
}

async function pathExists(filePath: string): Promise<boolean> {
  try {
    await fs.access(filePath);
    return true;
  } catch {
    return false;
  }
}
