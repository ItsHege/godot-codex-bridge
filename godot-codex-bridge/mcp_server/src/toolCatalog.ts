import type { JsonObject, ToolEnvelope } from "./types.js";

export interface ToolCatalogEntry {
  name: string;
  category: string;
  safety: "read_only" | "navigation" | "runtime_input" | "undo_redo_mutation" | "persistent_write" | "external_process" | "approval_write" | "safety";
  useWhen: string;
  preferBefore?: string[];
}

interface ToolWorkflow {
  name: string;
  intent: string;
  tools: string[];
  keywords?: string[];
}

export type ToolCatalogView = "full" | "compact";

export const TOOL_CATEGORIES: Record<string, string> = {
  orientation: "Start here: project, bridge, current scene and live editor state.",
  project_files: "Bounded project file, scene and script reading/searching.",
  annotations: "Read local user Eye Attach marker artifacts.",
  editor_navigation: "Navigate Godot editor, open scenes/scripts, select and inspect nodes/resources.",
  diagnostics: "Capture errors, resource state, 3D diagnostics, screenshots and export readiness.",
  materials_rendering: "Inspect and edit materials, shaders, environment and particle effects.",
  animation_signals: "Inspect/edit animation clips and signal connections.",
  scene_mutation: "UndoRedo-backed live scene/node/resource mutation; does not save automatically.",
  persistence_safety: "Explicit save, undo snapshots, diff preview and approval-gated writes.",
  runtime: "Run scenes or test scenes and summarize runtime evidence.",
  planning_batch: "Tool selection, scene planning and multi-action batching.",
  notes: "Project-local bridge notes.",
};

export const TOOL_CATALOG: ToolCatalogEntry[] = [
  entry("godot.get_tool_catalog", "planning_batch", "read_only", "Find the right Godot Bridge tool category before choosing from the full flat list."),
  entry("godot.bridge_status", "orientation", "read_only", "Diagnose addon install, heartbeat, snapshot freshness and host/tool state."),
  entry("godot.get_project_overview", "orientation", "read_only", "Get the fastest bounded overview of project metadata, likely scenes/scripts and AGENTS status."),
  entry("godot.project_get_map", "orientation", "read_only", "Build a bounded project intelligence map of scenes, scripts, resources, autoloads, input actions, groups and declared signals."),
  entry("godot.project_scene_graph", "orientation", "read_only", "Build a bounded scene dependency graph of scene instances, script attachments, external resources, missing resources and cycles."),
  entry("godot.project_script_map", "orientation", "read_only", "Build a bounded script/class/autoload map with scene usage and AGENTS/docs previews."),
  entry("godot.get_agents_context", "orientation", "read_only", "Read bounded AGENTS.md instructions before making project-specific decisions."),
  entry("godot.get_current_source_context", "orientation", "read_only", "Combine current snapshot and bounded source previews for the active Godot context."),
  entry("godot.refresh_editor_context", "orientation", "navigation", "Ask the live addon to refresh the editor snapshot."),
  entry("godot.editor_get_state", "orientation", "read_only", "Get current/open scenes, selected nodes, selected file, permissions and capabilities."),
  entry("godot.editor_capabilities", "orientation", "read_only", "Explain which editor surfaces are typed-control/readable and which native panels are screenshot-only."),
  entry("godot.get_current_scene", "orientation", "read_only", "Read current scene metadata from the latest snapshot."),
  entry("godot.get_scene_tree", "orientation", "read_only", "Read the current bounded scene tree from the latest snapshot."),
  entry("godot.get_selected_nodes", "orientation", "read_only", "Read selected node context from the latest snapshot."),

  entry("godot.list_project_files", "project_files", "read_only", "List safe project-root-bounded files with filters and pagination."),
  entry("godot.search_project_files", "project_files", "read_only", "Search safe text files inside the project root."),
  entry("godot.read_project_file", "project_files", "read_only", "Read a bounded safe project text file, or metadata for binary assets."),
  entry("godot.get_scene_file_tree", "project_files", "read_only", "Parse a .tscn file into bounded node/resource metadata."),
  entry("godot.get_script_inventory", "project_files", "read_only", "Read GDScript inventory from the latest bridge snapshot."),

  entry("godot.list_annotations", "annotations", "read_only", "List local Eye Attach annotation artifacts."),
  entry("godot.get_latest_annotation", "annotations", "read_only", "Read the latest local Eye Attach marker metadata."),
  entry("godot.get_annotation", "annotations", "read_only", "Read one local Eye Attach marker artifact by id."),
  entry("godot.resolve_annotation_target", "annotations", "read_only", "Resolve an Eye Attach marker into conservative editor target candidates without claiming ray hits."),

  entry("godot.editor_focus", "editor_navigation", "navigation", "Switch main editor screen and optionally select a project file."),
  entry("godot.editor_focus_panel", "editor_navigation", "navigation", "Focus a native Godot editor panel/tab such as Output, Debugger, Animation or Shader Editor."),
  entry("godot.editor_viewport_navigate", "editor_navigation", "navigation", "Navigate the editor viewport through typed API: 2D pan/zoom/reset, honest unavailable status for unsupported 3D camera controls."),
  entry("godot.open_scene", "editor_navigation", "navigation", "Open an existing project-local scene in the Godot editor."),
  entry("godot.open_script", "editor_navigation", "navigation", "Open a project-local script and optionally focus a line."),
  entry("godot.select_node", "editor_navigation", "navigation", "Select a node in the active scene, optionally focusing Inspector."),
  entry("godot.inspect_node", "editor_navigation", "read_only", "Select and inspect bounded properties for a node."),
  entry("godot.get_inspector_context", "editor_navigation", "read_only", "Read the current Inspector edited object, selected property path and bounded property-category summary."),
  entry("godot.get_node_deep", "editor_navigation", "read_only", "Read deeper bounded node tree/properties for active scene context."),
  entry("godot.get_spatial_bounds", "diagnostics", "read_only", "Read world-space Node3D transforms, AABBs and ground-gap estimates from the live editor."),
  entry("godot.spatial_query", "diagnostics", "read_only", "Measure editor-time ground gap or AABB overlap; runtime raycasts return honest unavailable status until runtime support exists."),
  entry("godot.placement_check", "diagnostics", "read_only", "Scan bounded Node3D targets for floating, below-ground, clipping and off-grid placement issues with measured suggested fixes."),
  entry("godot.list_resources", "editor_navigation", "read_only", "List project resources through the live editor resource model."),
  entry("godot.inspect_imported_assets", "editor_navigation", "read_only", "Inspect imported/placeable assets before instancing or placing them."),
  entry("godot.plan_blender_asset_import", "planning_batch", "read_only", "Validate a project-local Blender/AI import manifest and suggest safe inspect/place follow-up calls."),
  entry("godot.get_class_info", "editor_navigation", "read_only", "Inspect ClassDB metadata for Godot classes, properties, methods and signals."),

  entry("godot.get_editor_output", "diagnostics", "read_only", "Read editor output summary from the latest snapshot."),
  entry("godot.get_resource_status", "diagnostics", "read_only", "Read resource/import status from the latest snapshot."),
  entry("godot.get_gameplay_context", "diagnostics", "read_only", "Read gameplay context captured in the latest snapshot."),
  entry("godot.diagnostics_get", "diagnostics", "read_only", "Get Bridge-owned diagnostics and summaries."),
  entry("godot.diagnostics_clear", "diagnostics", "navigation", "Clear Bridge-owned diagnostics buffer only when permission allows."),
  entry("godot.inspect_3d_scene", "diagnostics", "read_only", "Inspect 3D scene hints, camera/lights/meshes/colliders/nav/performance."),
  entry("godot.performance_get_snapshot", "diagnostics", "read_only", "Read bounded editor performance monitor values and timeline stats from the latest context snapshot."),
  entry("godot.create_diagnostic_snapshot", "diagnostics", "read_only", "Write local diagnostic evidence artifact under the bridge artifact directory."),
  entry("godot.create_visual_baseline", "diagnostics", "read_only", "Create a local visual baseline from a screenshot artifact."),
  entry("godot.compare_visual_regression", "diagnostics", "read_only", "Compare a current screenshot against a local visual baseline."),
  entry("godot.check_export_readiness", "diagnostics", "read_only", "Summarize PC/mobile export readiness without running exports."),
  entry("godot.capture_viewport_screenshot", "diagnostics", "read_only", "Capture a local viewport screenshot through the live addon."),
  entry("godot.capture_timeline_screenshots", "diagnostics", "read_only", "Capture a bounded local sequence of viewport screenshots."),
  entry("godot.capture_multi_view_screenshots", "diagnostics", "read_only", "Capture front/side/top/perspective local PNG evidence for a Node3D selection, node path or group."),

  entry("godot.inspect_materials", "materials_rendering", "read_only", "Inspect scene materials/resources before shader/material edits."),
  entry("godot.create_shader_material_for_node", "materials_rendering", "undo_redo_mutation", "Create and assign a ShaderMaterial to a node through live editor control."),
  entry("godot.set_shader_parameter", "materials_rendering", "undo_redo_mutation", "Set a safe shader parameter on a material."),
  entry("godot.set_shader_texture_parameter", "materials_rendering", "undo_redo_mutation", "Set a safe shader texture parameter on a material."),
  entry("godot.inspect_rendering_effects", "materials_rendering", "read_only", "Inspect environment/rendering/effects state."),
  entry("godot.set_environment_property", "materials_rendering", "undo_redo_mutation", "Set safe environment properties through UndoRedo."),
  entry("godot.create_particle_effect", "materials_rendering", "undo_redo_mutation", "Create a particle effect node/resource through live editor control."),
  entry("godot.set_particle_effect_properties", "materials_rendering", "undo_redo_mutation", "Set safe particle effect properties through UndoRedo."),

  entry("godot.list_animation_players", "animation_signals", "read_only", "List animation players in the current scene."),
  entry("godot.inspect_animation", "animation_signals", "read_only", "Inspect a specific animation clip."),
  entry("godot.preview_animation", "animation_signals", "navigation", "Preview an animation in the editor without saving."),
  entry("godot.stop_animation_preview", "animation_signals", "navigation", "Stop an active editor animation preview."),
  entry("godot.create_animation_clip", "animation_signals", "undo_redo_mutation", "Create an animation clip through live editor control."),
  entry("godot.list_signal_connections", "animation_signals", "read_only", "Inspect signal connections in the scene."),
  entry("godot.connect_signal", "animation_signals", "undo_redo_mutation", "Connect a signal through live editor control."),
  entry("godot.disconnect_signal", "animation_signals", "undo_redo_mutation", "Disconnect a signal through live editor control."),

  entry("godot.set_node_transform", "scene_mutation", "undo_redo_mutation", "Move/rotate/scale Node2D or Node3D through UndoRedo."),
  entry("godot.snap_to_ground", "scene_mutation", "undo_redo_mutation", "Snap measured Node3D targets so their AABB bottoms rest on the ground reference through UndoRedo."),
  entry("godot.snap_to_grid", "scene_mutation", "undo_redo_mutation", "Snap Node3D targets to a placement grid on selected axes through UndoRedo."),
  entry("godot.set_node_properties", "scene_mutation", "undo_redo_mutation", "Set bounded safe node properties through UndoRedo."),
  entry("godot.undo_last_bridge_action", "scene_mutation", "undo_redo_mutation", "Undo the latest live editor UndoRedo action only when it was created by Godot Codex Bridge."),
  entry("godot.assign_resource_to_node", "scene_mutation", "undo_redo_mutation", "Assign a resource to a node property through UndoRedo."),
  entry("godot.create_node_resource", "scene_mutation", "undo_redo_mutation", "Create a safe resource for a node property."),
  entry("godot.set_resource_properties", "scene_mutation", "undo_redo_mutation", "Set bounded safe resource properties."),
  entry("godot.create_node", "scene_mutation", "undo_redo_mutation", "Create a node in the active scene through UndoRedo."),
  entry("godot.delete_node", "scene_mutation", "undo_redo_mutation", "Delete a node through UndoRedo when permission allows."),
  entry("godot.rename_node", "scene_mutation", "undo_redo_mutation", "Rename a node through UndoRedo."),
  entry("godot.reparent_node", "scene_mutation", "undo_redo_mutation", "Reparent a node through UndoRedo."),
  entry("godot.duplicate_node", "scene_mutation", "undo_redo_mutation", "Duplicate a node through UndoRedo."),
  entry("godot.instance_scene", "scene_mutation", "undo_redo_mutation", "Instance a PackedScene into the active scene."),
  entry("godot.place_asset_in_scene", "scene_mutation", "undo_redo_mutation", "Place an imported asset/scene with optional collider/material color and screenshot evidence."),
  entry("godot.fix_selected_node", "scene_mutation", "undo_redo_mutation", "Apply one narrow approved fix to the selected node."),

  entry("godot.save_scene", "persistence_safety", "persistent_write", "Explicitly save the current scene after review and permission."),
  entry("godot.save_all_scenes", "persistence_safety", "persistent_write", "Request save-all after review and permission."),
  entry("godot.create_undo_snapshot", "persistence_safety", "read_only", "Copy explicitly listed safe project files into a local undo snapshot."),
  entry("godot.preview_scene_diff", "persistence_safety", "read_only", "Preview a text file/scene diff without applying it."),
  entry("godot.apply_approved_diff", "persistence_safety", "approval_write", "Apply reviewed text content after approval token and optional hash check."),

  entry("godot.run_current_scene", "runtime", "external_process", "Run the current scene, or an explicit project-local scene path, through the active Godot editor."),
  entry("godot.stop_running_scene", "runtime", "navigation", "Stop the current Godot editor play session if one is active and release Bridge-owned playtest input."),
  entry("godot.emergency_stop", "runtime", "safety", "Stop Bridge-owned runtime work, release held playtest input, and close the playtest session token."),
  entry("godot.playtest_input", "runtime", "runtime_input", "Send a bounded typed input batch only to a bridge-owned running scene through the opt-in runtime probe."),
  entry("godot.run_playtest_scenario", "runtime", "runtime_input", "Run a project-local scene and execute a bounded scenario contract through the addon editor-control path."),
  entry("godot.runtime_get_state", "runtime", "read_only", "Read opt-in runtime probe state from the local bridge runtime folder."),
  entry("godot.runtime_get_events", "runtime", "read_only", "Read opt-in runtime probe signal/input/scene/node events from the local bridge runtime folder."),
  entry("godot.run_test_scene", "runtime", "external_process", "Run a specified test scene and return bounded output/runtime summary."),

  entry("godot.generate_scene_from_prompt", "planning_batch", "read_only", "Convert a scene prompt into a conservative live-editor action plan with suggested tool calls."),
  entry("godot.editor_batch", "planning_batch", "navigation", "Execute multiple editor_control actions in one bridge request."),

  entry("godot.notes_get", "notes", "read_only", "Read project-local bridge notes."),
  entry("godot.notes_append", "notes", "navigation", "Append a project-local bridge note."),
  entry("godot.notes_clear", "notes", "navigation", "Clear project-local bridge notes when permission allows."),
];

export const TOOL_WORKFLOWS: ToolWorkflow[] = [
  {
    name: "orient_before_editing",
    intent: "Understand the project and live editor before changing anything.",
    tools: ["godot.bridge_status", "godot.editor_capabilities", "godot.project_get_map", "godot.project_script_map", "godot.get_agents_context", "godot.get_project_overview", "godot.project_scene_graph", "godot.editor_get_state"],
    keywords: ["start", "orient", "overview", "context", "instructions", "state", "before editing", "where am i"],
  },
  {
    name: "inspect_scene_problem",
    intent: "Inspect the active scene, selected node and visual diagnostics.",
    tools: ["godot.refresh_editor_context", "godot.get_scene_tree", "godot.get_selected_nodes", "godot.editor_capabilities", "godot.editor_focus_panel", "godot.inspect_3d_scene", "godot.performance_get_snapshot", "godot.get_spatial_bounds", "godot.spatial_query", "godot.placement_check", "godot.capture_multi_view_screenshots", "godot.capture_viewport_screenshot"],
    keywords: ["inspect", "scene", "selected", "node", "camera", "light", "collider", "screenshot", "visual", "diagnose", "output", "debugger", "errors", "warnings"],
  },
  {
    name: "safe_live_scene_edit",
    intent: "Mutate the live scene safely, inspect evidence, then save explicitly only when requested.",
    tools: ["godot.editor_get_state", "godot.create_undo_snapshot", "godot.placement_check", "godot.snap_to_ground", "godot.undo_last_bridge_action", "godot.save_scene", "godot.snap_to_grid", "godot.get_spatial_bounds", "godot.capture_multi_view_screenshots", "godot.editor_batch", "godot.capture_viewport_screenshot"],
    keywords: ["move", "create", "edit", "node", "scene", "mutation", "transform", "property", "save", "undo", "live edit", "snap", "ground", "grid", "place"],
  },
  {
    name: "blender_asset_import",
    intent: "Review project-local Blender/AI exported assets before inspecting or placing them in the scene.",
    tools: ["godot.plan_blender_asset_import", "godot.inspect_imported_assets", "godot.place_asset_in_scene", "godot.capture_viewport_screenshot"],
    keywords: ["blender", "asset import", "ai import", "imported asset", "glb", "gltf", "model", "mesh", "place asset", "ai_imports"],
  },
  {
    name: "text_diff_edit",
    intent: "Review text scene/script/resource edits before writing files.",
    tools: ["godot.read_project_file", "godot.preview_scene_diff", "godot.create_undo_snapshot", "godot.apply_approved_diff"],
    keywords: ["script", "text", "file", "diff", "patch", "gdscript", "resource", "apply"],
  },
  {
    name: "runtime_smoke",
    intent: "Run a test/current scene and summarize runtime evidence.",
    tools: ["godot.run_test_scene", "godot.run_current_scene", "godot.run_playtest_scenario", "godot.playtest_input", "godot.runtime_get_state", "godot.runtime_get_events", "godot.stop_running_scene", "godot.diagnostics_get", "godot.performance_get_snapshot", "godot.capture_timeline_screenshots"],
    keywords: ["run", "play", "test", "runtime", "smoke", "state", "scene", "crash", "output", "screenshot sequence"],
  },
];

export function getToolCatalog(category?: string, intent?: string, view: ToolCatalogView = "compact"): ToolEnvelope {
  const normalizedCategory = typeof category === "string" ? category.trim() : "";
  const normalizedIntent = typeof intent === "string" ? intent.trim() : "";
  const normalizedView: ToolCatalogView = view === "full" ? "full" : "compact";
  if (normalizedCategory !== "" && !Object.hasOwn(TOOL_CATEGORIES, normalizedCategory)) {
    return {
      status: "invalid_request",
      error: {
        code: "unknown_tool_category",
        message: `Unknown Godot tool category: ${normalizedCategory}`,
        known_categories: Object.keys(TOOL_CATEGORIES),
      },
    };
  }
  const matchedWorkflows = matchWorkflows(normalizedIntent);
  const recommendedNextTools = matchedWorkflows.length > 0
    ? (matchedWorkflows[0].tools as string[]).slice(0, 6)
    : [];

  const selectedCatalog = normalizedCategory === ""
    ? TOOL_CATALOG
    : TOOL_CATALOG.filter((tool) => tool.category === normalizedCategory);
  const tools = normalizedView === "compact" ? [] : selectedCatalog.map((tool) => ({
    name: tool.name,
    category: tool.category,
    safety: tool.safety,
    use_when: tool.useWhen,
    prefer_before: tool.preferBefore ?? [],
  }));

  return {
    status: "ok",
    catalog_version: "godot-tool-catalog-v1",
    view: normalizedView,
    total_tools: TOOL_CATALOG.length,
    filtered_category: normalizedCategory || null,
    intent: normalizedIntent || null,
    categories: Object.entries(TOOL_CATEGORIES).map(([name, description]) => ({
      name,
      description,
      tool_count: TOOL_CATALOG.filter((tool) => tool.category === name).length,
    })),
    compact_category_summaries: compactCategorySummaries(normalizedCategory),
    tools,
    omitted_tool_count: normalizedView === "compact" ? selectedCatalog.length : 0,
    recommended_workflows: TOOL_WORKFLOWS.map((workflow) => ({ ...workflow })),
    matched_workflows: matchedWorkflows,
    recommended_next_tools: recommendedNextTools,
    guidance: [
      "Use view=compact first when you only need workflow routing; use view=full with a category when you need exact tool metadata.",
      "Prefer orientation tools before mutation tools.",
      "Use editor_batch for multi-step live editor navigation/mutation instead of many separate calls.",
      "UndoRedo-backed scene mutations are not persisted until godot.save_scene or godot.save_all_scenes succeeds.",
      "Use preview_scene_diff/apply_approved_diff for text file edits; use live editor tools for scene/node edits.",
    ],
  };
}

function entry(
  name: string,
  category: string,
  safety: ToolCatalogEntry["safety"],
  useWhen: string,
  preferBefore: string[] = [],
): ToolCatalogEntry {
  return { name, category, safety, useWhen, preferBefore };
}

function compactCategorySummaries(category?: string): JsonObject[] {
  const names = category ? [category] : Object.keys(TOOL_CATEGORIES);
  return names.map((name) => {
    const categoryTools = TOOL_CATALOG.filter((tool) => tool.category === name);
    return {
      name,
      description: TOOL_CATEGORIES[name] ?? "",
      tool_count: categoryTools.length,
      primary_tools: categoryTools.slice(0, 4).map((tool) => tool.name),
      safety_levels: [...new Set(categoryTools.map((tool) => tool.safety))],
    };
  });
}

function matchWorkflows(intent: string): JsonObject[] {
  if (intent === "") {
    return [];
  }
  const normalizedIntent = normalizeSearchText(intent);
  const intentTokens = tokenize(normalizedIntent);
  return TOOL_WORKFLOWS
    .map((workflow) => {
      const haystack = normalizeSearchText([
        workflow.name,
        workflow.intent,
        ...(workflow.keywords ?? []),
        ...workflow.tools,
      ].join(" "));
      const matchedTerms = [
        ...(workflow.keywords ?? []).filter((keyword) => normalizedIntent.includes(normalizeSearchText(keyword))),
        ...intentTokens.filter((token) => haystack.includes(token)),
      ];
      const uniqueMatchedTerms = [...new Set(matchedTerms)].slice(0, 8);
      const score = uniqueMatchedTerms.length;
      return {
        name: workflow.name,
        intent: workflow.intent,
        tools: workflow.tools,
        score,
        matched_terms: uniqueMatchedTerms,
      };
    })
    .filter((workflow) => workflow.score > 0)
    .sort((a, b) => b.score - a.score || a.name.localeCompare(b.name))
    .slice(0, 3);
}

function normalizeSearchText(value: string): string {
  return value.toLowerCase().normalize("NFKD").replace(/[\u0300-\u036f]/g, "");
}

function tokenize(value: string): string[] {
  return [...new Set(normalizeSearchText(value).split(/[^a-z0-9_]+/).filter((token) => token.length >= 3))];
}
