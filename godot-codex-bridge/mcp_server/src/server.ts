import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod/v4";

import { createServerConfig } from "./config.js";
import { createToolHandlers } from "./tools.js";
import type { ServerConfig } from "./types.js";

export function createGodotCodexBridgeServer(config: ServerConfig = createServerConfig()): McpServer {
  const server = new McpServer({
    name: "godot-codex-bridge",
    version: "0.0.1",
  });

  registerTools(server, config);
  return server;
}

export async function startStdioServer(config: ServerConfig = createServerConfig()): Promise<void> {
  const server = createGodotCodexBridgeServer(config);
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

function registerTools(server: McpServer, config: ServerConfig): void {
  const handlers = createToolHandlers(config);

  server.registerTool(
    "godot.get_tool_catalog",
    {
      title: "Get Godot Tool Catalog",
      description: "Return grouped Godot Bridge tool categories, safety levels and recommended workflows to help choose the right tool from the flat godot.* list.",
      inputSchema: {
        category: z.string().optional(),
        intent: z.string().optional(),
        view: z.enum(["full", "compact"]).optional(),
      },
    },
    async (args) => handlers["godot.get_tool_catalog"](args),
  );

  server.registerTool(
    "godot.bridge_status",
    {
      title: "Get Godot Bridge Status",
      description: "Diagnose addon install, plugin enablement, heartbeat freshness, snapshot freshness, and version metadata.",
      inputSchema: {},
    },
    async () => handlers["godot.bridge_status"](),
  );

  server.registerTool(
    "godot.get_project_overview",
    {
      title: "Get Godot Project Overview",
      description: "Read a bounded project summary: project.godot metadata, current scene snapshot when available, file counts, scene/script candidates, and AGENTS status.",
      inputSchema: {},
    },
    async () => handlers["godot.get_project_overview"](),
  );

  server.registerTool(
    "godot.project_get_map",
    {
      title: "Get Godot Project Map",
      description: "Build a bounded read-only project intelligence map: scenes, scripts, resources, autoloads, input actions, groups and declared signals.",
      inputSchema: {},
    },
    async () => handlers["godot.project_get_map"](),
  );

  server.registerTool(
    "godot.project_scene_graph",
    {
      title: "Get Godot Project Scene Graph",
      description: "Parse text .tscn scene dependencies into a bounded graph of scene instances, script attachments, external resources, missing resources and scene-instance cycles.",
      inputSchema: {
        scenePath: z.string().startsWith("res://").optional(),
        includeResources: z.boolean().optional(),
        includeNodes: z.boolean().optional(),
        maxDepth: z.number().int().min(1).max(16).optional(),
      },
    },
    async (args) => handlers["godot.project_scene_graph"](args),
  );

  server.registerTool(
    "godot.project_script_map",
    {
      title: "Get Godot Project Script Map",
      description: "Build a bounded read-only map of scripts, class_name declarations, autoload scripts, scene usage, AGENTS and project docs previews.",
      inputSchema: {
        scriptPath: z.string().startsWith("res://").optional(),
        includeUsages: z.boolean().optional(),
        includeFunctions: z.boolean().optional(),
        includeSignals: z.boolean().optional(),
        includeExports: z.boolean().optional(),
        includeConstants: z.boolean().optional(),
        maxScripts: z.number().int().min(1).max(500).optional(),
      },
    },
    async (args) => handlers["godot.project_script_map"](args),
  );

  server.registerTool(
    "godot.list_project_files",
    {
      title: "List Godot Project Files",
      description: "List safe project-root-bounded file metadata with pagination. Generated/cache dirs are excluded and binary assets are metadata-only.",
      inputSchema: {
        rootPath: z.string().optional(),
        kind: z.enum(["script", "scene", "resource", "image", "audio", "shader", "config", "doc", "addon", "unknown"]).optional(),
        extensions: z.array(z.string().min(1).max(16)).max(25).optional(),
        globs: z.array(z.string().min(1).max(160)).max(25).optional(),
        offset: z.number().int().min(0).optional(),
        limit: z.number().int().min(1).max(500).optional(),
      },
    },
    async (args) => handlers["godot.list_project_files"](args),
  );

  server.registerTool(
    "godot.search_project_files",
    {
      title: "Search Godot Project Files",
      description: "Search safe text files inside the project root using ripgrep when available or a bounded Node fallback. Binary and generated/cache files are skipped.",
      inputSchema: {
        query: z.string().min(1).max(200),
        rootPath: z.string().optional(),
        globs: z.array(z.string().min(1).max(160)).max(25).optional(),
        offset: z.number().int().min(0).optional(),
        limit: z.number().int().min(1).max(200).optional(),
        contextLines: z.number().int().min(0).max(5).optional(),
        caseSensitive: z.boolean().optional(),
      },
    },
    async (args) => handlers["godot.search_project_files"](args),
  );

  server.registerTool(
    "godot.read_project_file",
    {
      title: "Read Godot Project File",
      description: "Read a bounded line range from a safe project text file. Binary assets return metadata only.",
      inputSchema: {
        path: z.string().min(1),
        startLine: z.number().int().min(1).optional(),
        maxLines: z.number().int().min(1).max(1000).optional(),
        maxBytes: z.number().int().min(1).max(256_000).optional(),
      },
    },
    async (args) => handlers["godot.read_project_file"](args),
  );

  server.registerTool(
    "godot.get_agents_context",
    {
      title: "Get Godot Project AGENTS Context",
      description: "Read project-root-bounded AGENTS.md files with precedence, SHA-256 metadata, and bounded previews.",
      inputSchema: {},
    },
    async () => handlers["godot.get_agents_context"](),
  );

  server.registerTool(
    "godot.get_scene_file_tree",
    {
      title: "Get Godot Scene File Tree",
      description: "Parse a safe .tscn scene file into a bounded node/resource tree, using the current or main scene when no scenePath is provided.",
      inputSchema: {
        scenePath: z.string().min(1).optional(),
      },
    },
    async (args) => handlers["godot.get_scene_file_tree"](args),
  );

  server.registerTool(
    "godot.get_current_source_context",
    {
      title: "Get Godot Current Source Context",
      description: "Combine current scene snapshot data, scene file parsing, selected node script paths, and bounded script previews when practical.",
      inputSchema: {},
    },
    async () => handlers["godot.get_current_source_context"](),
  );

  server.registerTool(
    "godot.get_current_scene",
    {
      title: "Get Current Godot Scene",
      description: "Read current scene metadata from the latest Godot bridge context snapshot.",
      inputSchema: {},
    },
    async () => handlers["godot.get_current_scene"](),
  );

  server.registerTool(
    "godot.get_scene_tree",
    {
      title: "Get Godot Scene Tree",
      description: "Read bounded scene tree data from the latest Godot bridge context snapshot.",
      inputSchema: {},
    },
    async () => handlers["godot.get_scene_tree"](),
  );

  server.registerTool(
    "godot.get_selected_nodes",
    {
      title: "Get Selected Godot Nodes",
      description: "Read selected node metadata and bounded inspector summaries from the latest bridge snapshot.",
      inputSchema: {},
    },
    async () => handlers["godot.get_selected_nodes"](),
  );

  server.registerTool(
    "godot.get_editor_output",
    {
      title: "Get Godot Editor Output",
      description: "Read recent editor output/errors captured by the Godot bridge snapshot.",
      inputSchema: {},
    },
    async () => handlers["godot.get_editor_output"](),
  );

  server.registerTool(
    "godot.get_resource_status",
    {
      title: "Get Godot Resource Status",
      description: "Read resource/import status captured by the Godot bridge snapshot.",
      inputSchema: {},
    },
    async () => handlers["godot.get_resource_status"](),
  );

  server.registerTool(
    "godot.get_gameplay_context",
    {
      title: "Get Godot Gameplay Context",
      description: "Read bounded gameplay context from the latest bridge snapshot: input actions, autoloads, layer names and key project settings.",
      inputSchema: {},
    },
    async () => handlers["godot.get_gameplay_context"](),
  );

  server.registerTool(
    "godot.get_script_inventory",
    {
      title: "Get Godot Script Inventory",
      description: "Read bounded GDScript inventory from the latest bridge snapshot: class names, extends, signals, exports, functions and TODO/FIXME markers without full source dumps.",
      inputSchema: {},
    },
    async () => handlers["godot.get_script_inventory"](),
  );

  server.registerTool(
    "godot.list_annotations",
    {
      title: "List Godot AI Marker Annotations",
      description: "List local Eye Attach / AI Marker annotation artifacts created by the Godot editor addon.",
      inputSchema: {
        limit: z.number().int().min(1).max(100).optional(),
      },
    },
    async (args) => handlers["godot.list_annotations"](args),
  );

  server.registerTool(
    "godot.get_latest_annotation",
    {
      title: "Get Latest Godot AI Marker Annotation",
      description: "Read the latest local Eye Attach / AI Marker manifest, marker coordinates and local PNG paths.",
      inputSchema: {},
    },
    async () => handlers["godot.get_latest_annotation"](),
  );

  server.registerTool(
    "godot.get_annotation",
    {
      title: "Get Godot AI Marker Annotation",
      description: "Read one local Eye Attach / AI Marker manifest by annotation id. This is read-only and project bridge-bounded.",
      inputSchema: {
        annotationId: z.string().min(1).max(128),
      },
    },
    async (args) => handlers["godot.get_annotation"](args),
  );

  server.registerTool(
    "godot.resolve_annotation_target",
    {
      title: "Resolve Godot AI Marker Target",
      description: "Resolve an Eye Attach marker into conservative editor target candidates using local annotation metadata and capture-time context. Does not claim viewport ray/world hits.",
      inputSchema: {
        annotationId: z.string().min(1).max(128).optional(),
        markerId: z.string().min(1).max(32).optional(),
      },
    },
    async (args) => handlers["godot.resolve_annotation_target"](args),
  );

  server.registerTool(
    "godot.refresh_editor_context",
    {
      title: "Refresh Godot Editor Context",
      description: "Ask the live addon to refresh context_snapshot.json and return current scene/selection metadata.",
      inputSchema: {
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.refresh_editor_context"](args),
  );

  server.registerTool(
    "godot.editor_get_state",
    {
      title: "Get Live Godot Editor State",
      description: "Ask the live addon for current/open scenes, selected nodes/files, permissions, diagnostics counts and editor-control capabilities.",
      inputSchema: {
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.editor_get_state"](args),
  );

  server.registerTool(
    "godot.editor_capabilities",
    {
      title: "Get Godot Editor Capabilities",
      description: "Explain which Godot editor surfaces can be controlled/read through typed Bridge tools and which native panels are screenshot-only.",
      inputSchema: {},
    },
    async () => handlers["godot.editor_capabilities"](),
  );

  server.registerTool(
    "godot.editor_focus",
    {
      title: "Focus Godot Editor",
      description: "Switch Godot main editor screens and optionally select a project-local file in the FileSystem dock.",
      inputSchema: {
        mainScreen: z.enum(["2D", "3D", "Script", "Game", "AssetLib", "Codex Bridge"]).optional(),
        selectFile: z.string().startsWith("res://").optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.editor_focus"](args),
  );

  server.registerTool(
    "godot.editor_focus_panel",
    {
      title: "Focus Godot Editor Panel",
      description: "Focus a native Godot editor panel/tab such as Output, Debugger, Audio, Animation or Shader Editor. Navigation only; does not clear diagnostics.",
      inputSchema: {
        panel: z.enum([
          "Output",
          "Debugger",
          "Stack Trace",
          "Audio",
          "Animation",
          "Shader Editor",
          "Signal Visualizer",
          "Profiler",
          "Visual Profiler",
          "Monitors",
          "Video RAM",
          "Network Profiler",
          "Inspector",
          "FileSystem",
          "Scene",
          "Import",
        ]),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.editor_focus_panel"](args),
  );

  server.registerTool(
    "godot.get_inspector_context",
    {
      title: "Get Godot Inspector Context",
      description: "Read the current Inspector edited object, selected property path and bounded property-category summary without scraping native Inspector UI state.",
      inputSchema: {
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.get_inspector_context"](args),
  );

  server.registerTool(
    "godot.editor_viewport_navigate",
    {
      title: "Navigate Godot Editor Viewport",
      description: "Navigate the editor viewport through typed Godot API. Supports 2D pan/zoom/reset; returns editor_api_unavailable for 3D orbit/zoom/frame-selected when no stable official API is available.",
      inputSchema: {
        viewport: z.enum(["2D", "3D"]).optional(),
        action: z.enum(["pan", "zoom", "reset", "frame_selected", "orbit"]).optional(),
        deltaX: z.number().min(-100000).max(100000).optional(),
        deltaY: z.number().min(-100000).max(100000).optional(),
        zoomFactor: z.number().min(0.05).max(20).optional(),
        centerX: z.number().min(-100000).max(100000).optional(),
        centerY: z.number().min(-100000).max(100000).optional(),
        orbitYawDegrees: z.number().min(-3600).max(3600).optional(),
        orbitPitchDegrees: z.number().min(-3600).max(3600).optional(),
        zoomDelta: z.number().min(-1000).max(1000).optional(),
        captureScreenshot: z.boolean().optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.editor_viewport_navigate"](args),
  );

  server.registerTool(
    "godot.select_node",
    {
      title: "Select Godot Node",
      description: "Select a scene-local node in the live editor and optionally focus it in the Inspector.",
      inputSchema: {
        nodePath: z.string().min(1).max(400),
        scenePath: z.string().startsWith("res://").optional(),
        focusInspector: z.boolean().optional(),
        additive: z.boolean().optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.select_node"](args),
  );

  server.registerTool(
    "godot.inspect_node",
    {
      title: "Inspect Godot Node",
      description: "Select a scene-local node, focus the Inspector and return bounded property metadata.",
      inputSchema: {
        nodePath: z.string().min(1).max(400),
        scenePath: z.string().startsWith("res://").optional(),
        additive: z.boolean().optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.inspect_node"](args),
  );

  server.registerTool(
    "godot.get_node_deep",
    {
      title: "Get Deep Godot Node Context",
      description: "Read an on-demand bounded node subtree with properties from the live editor, avoiding the global snapshot node/property caps.",
      inputSchema: {
        nodePath: z.string().min(1).max(400),
        depth: z.number().int().min(0).max(8).optional(),
        maxNodes: z.number().int().min(1).max(256).optional(),
        includeProperties: z.boolean().optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.get_node_deep"](args),
  );

  server.registerTool(
    "godot.get_spatial_bounds",
    {
      title: "Get Godot Spatial Bounds",
      description: "Read world-space transforms, AABBs and ground-gap estimates for a node, selection or bounded scene scan.",
      inputSchema: {
        nodePath: z.string().min(1).max(400).optional(),
        groupName: z.string().min(1).max(96).optional(),
        selectedOnly: z.boolean().optional(),
        maxNodes: z.number().int().min(1).max(96).optional(),
        groundY: z.number().min(-100_000).max(100_000).optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.get_spatial_bounds"](args),
  );

  server.registerTool(
    "godot.spatial_query",
    {
      title: "Run Godot Spatial Query",
      description: "Run read-only geometric spatial queries such as ground gap and AABB overlap against the live editor scene.",
      inputSchema: {
        query: z.enum(["ground_gap", "aabb_overlap", "runtime_raycast", "raycast"]).optional(),
        queryType: z.enum(["ground_gap", "aabb_overlap", "runtime_raycast", "raycast"]).optional(),
        nodePath: z.string().min(1).max(400).optional(),
        groupName: z.string().min(1).max(96).optional(),
        selectedOnly: z.boolean().optional(),
        maxNodes: z.number().int().min(1).max(96).optional(),
        maxPairs: z.number().int().min(1).max(512).optional(),
        groundY: z.number().min(-100_000).max(100_000).optional(),
        tolerance: z.number().min(0).max(1000).optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.spatial_query"](args),
  );

  server.registerTool(
    "godot.placement_check",
    {
      title: "Check Godot Placement",
      description: "Run a bounded read-only placement validation for floating, below-ground, clipping and off-grid Node3D objects.",
      inputSchema: {
        nodePath: z.string().min(1).max(400).optional(),
        groupName: z.string().min(1).max(96).optional(),
        selectedOnly: z.boolean().optional(),
        maxNodes: z.number().int().min(1).max(96).optional(),
        maxPairs: z.number().int().min(1).max(512).optional(),
        maxIssues: z.number().int().min(1).max(512).optional(),
        groundY: z.number().min(-100_000).max(100_000).optional(),
        tolerance: z.number().min(0).max(1000).optional(),
        gridSize: z.number().min(0).max(100_000).optional(),
        gridOrigin: z.object({
          x: z.number(),
          y: z.number().optional(),
          z: z.number(),
        }).optional(),
        checks: z.array(z.enum(["ground_gap", "overlap", "grid"])).max(3).optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.placement_check"](args),
  );

  server.registerTool(
    "godot.snap_to_ground",
    {
      title: "Snap Godot Node To Ground",
      description: "Move selected, grouped or single Node3D targets so their measured AABB bottom rests on the ground reference. Uses UndoRedo and does not save.",
      inputSchema: {
        nodePath: z.string().min(1).max(400).optional(),
        groupName: z.string().min(1).max(96).optional(),
        selectedOnly: z.boolean().optional(),
        maxNodes: z.number().int().min(1).max(96).optional(),
        groundY: z.number().min(-100_000).max(100_000).optional(),
        tolerance: z.number().min(0).max(1000).optional(),
        gridSize: z.number().min(0).max(100_000).optional(),
        gridOrigin: z.object({
          x: z.number(),
          y: z.number().optional(),
          z: z.number(),
        }).optional(),
        alignToSurface: z.boolean().optional(),
        captureScreenshot: z.boolean().optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.snap_to_ground"](args),
  );

  server.registerTool(
    "godot.snap_to_grid",
    {
      title: "Snap Godot Node To Grid",
      description: "Move selected, grouped or single Node3D targets to a placement grid on selected axes. Uses UndoRedo and does not save.",
      inputSchema: {
        nodePath: z.string().min(1).max(400).optional(),
        groupName: z.string().min(1).max(96).optional(),
        selectedOnly: z.boolean().optional(),
        maxNodes: z.number().int().min(1).max(96).optional(),
        gridSize: z.number().min(0.000001).max(100_000),
        gridOrigin: z.object({
          x: z.number(),
          y: z.number().optional(),
          z: z.number(),
        }).optional(),
        axes: z.array(z.enum(["x", "y", "z"])).min(1).max(3).optional(),
        tolerance: z.number().min(0).max(1000).optional(),
        captureScreenshot: z.boolean().optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.snap_to_grid"](args),
  );

  server.registerTool(
    "godot.open_script",
    {
      title: "Open Godot Script",
      description: "Open a project-local script/shader in the Godot Script editor and optionally jump to a line.",
      inputSchema: {
        scriptPath: z.string().startsWith("res://"),
        line: z.number().int().min(1).optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.open_script"](args),
  );

  server.registerTool(
    "godot.list_resources",
    {
      title: "List Live Godot Resources",
      description: "Ask the live editor ResourceFilesystem for bounded resource/import metadata under a project-local res:// root.",
      inputSchema: {
        rootPath: z.string().startsWith("res://").optional(),
        extensions: z.array(z.string().min(1).max(16)).max(24).optional(),
        typeFilter: z.string().min(1).max(96).optional(),
        limit: z.number().int().min(1).max(250).optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.list_resources"](args),
  );

  server.registerTool(
    "godot.inspect_imported_assets",
    {
      title: "Inspect Godot Imported Assets",
      description: "Read bounded live ResourceFilesystem import status for model/mesh/scene/texture/audio/shader assets, including placeability hints.",
      inputSchema: {
        rootPath: z.string().startsWith("res://").optional(),
        extensions: z.array(z.string().min(1).max(16)).max(24).optional(),
        typeFilter: z.string().min(1).max(96).optional(),
        invalidOnly: z.boolean().optional(),
        placeableOnly: z.boolean().optional(),
        includeDependencies: z.boolean().optional(),
        limit: z.number().int().min(1).max(250).optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.inspect_imported_assets"](args),
  );

  server.registerTool(
    "godot.plan_blender_asset_import",
    {
      title: "Plan Blender Asset Import",
      description: "Read a project-local Blender/AI import manifest and return safe inspect/place follow-up tool calls without copying, overwriting, placing or saving.",
      inputSchema: {
        manifestPath: z.string().startsWith("res://").optional(),
      },
    },
    async (args) => handlers["godot.plan_blender_asset_import"](args),
  );

  server.registerTool(
    "godot.get_class_info",
    {
      title: "Get Godot ClassDB Info",
      description: "Read bounded Godot ClassDB metadata for an engine/GDExtension class: parent, properties, methods, signals, constants and enums.",
      inputSchema: {
        className: z.string().min(1).max(96),
        noInheritance: z.boolean().optional(),
        limit: z.number().int().min(1).max(200).optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.get_class_info"](args),
  );

  server.registerTool(
    "godot.inspect_materials",
    {
      title: "Inspect Godot Materials And Shaders",
      description: "Read live scene material slots, effective mesh materials, ShaderMaterial uniforms and bounded shader diagnostics without mutating the scene.",
      inputSchema: {
        nodePath: z.string().min(1).max(400).optional(),
        selectedOnly: z.boolean().optional(),
        includeShaderParams: z.boolean().optional(),
        includeEmpty: z.boolean().optional(),
        maxNodes: z.number().int().min(1).max(96).optional(),
        maxSlots: z.number().int().min(1).max(192).optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.inspect_materials"](args),
  );

  server.registerTool(
    "godot.create_shader_material_for_node",
    {
      title: "Create Godot Shader Material For Node",
      description: "Create a live ShaderMaterial, optionally load a project-local Shader resource, set initial uniforms and assign it to a node material slot through Godot UndoRedo without saving the scene.",
      inputSchema: {
        nodePath: z.string().min(1).max(400),
        slotKind: z.enum(["canvas_item_material", "geometry_material_override", "mesh_surface"]).optional(),
        surfaceIndex: z.number().int().min(0).max(1024).optional(),
        shaderPath: z.string().startsWith("res://").optional(),
        localToScene: z.boolean().optional(),
        parameters: z.record(z.string().min(1).max(160), z.any()).optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.create_shader_material_for_node"](args),
  );

  server.registerTool(
    "godot.set_shader_parameter",
    {
      title: "Set Godot Shader Parameter",
      description: "Edit one ShaderMaterial uniform on a live material slot through Godot UndoRedo without saving the scene. Use godot.inspect_materials first to identify slotKind, surfaceIndex and parameter.",
      inputSchema: {
        nodePath: z.string().min(1).max(400),
        slotKind: z.enum(["canvas_item_material", "geometry_material_override", "mesh_surface"]).optional(),
        surfaceIndex: z.number().int().min(0).max(1024).optional(),
        parameter: z.string().min(1).max(160),
        value: z.any(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.set_shader_parameter"](args),
  );

  server.registerTool(
    "godot.set_shader_texture_parameter",
    {
      title: "Set Godot Shader Texture Parameter",
      description: "Assign or clear a project-local Texture2D resource on one ShaderMaterial sampler uniform through Godot UndoRedo without saving the scene.",
      inputSchema: {
        nodePath: z.string().min(1).max(400),
        slotKind: z.enum(["canvas_item_material", "geometry_material_override", "mesh_surface"]).optional(),
        surfaceIndex: z.number().int().min(0).max(1024).optional(),
        parameter: z.string().min(1).max(160),
        texturePath: z.string().startsWith("res://").optional(),
        clear: z.boolean().optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.set_shader_texture_parameter"](args),
  );

  server.registerTool(
    "godot.inspect_rendering_effects",
    {
      title: "Inspect Godot Rendering Effects",
      description: "Read live WorldEnvironment, Camera3D environment overrides, post-processing flags and particle node diagnostics without mutating the scene.",
      inputSchema: {
        selectedOnly: z.boolean().optional(),
        includeEnvironmentProperties: z.boolean().optional(),
        includeParticles: z.boolean().optional(),
        maxNodes: z.number().int().min(1).max(96).optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.inspect_rendering_effects"](args),
  );

  server.registerTool(
    "godot.set_environment_property",
    {
      title: "Set Godot Environment Property",
      description: "Edit one allowlisted Environment/post-processing property on a WorldEnvironment or Camera3D environment override through Godot UndoRedo without saving the scene.",
      inputSchema: {
        nodePath: z.string().min(1).max(400),
        property: z.enum([
          "background_mode",
          "background_color",
          "background_energy_multiplier",
          "sky_custom_fov",
          "ambient_light_source",
          "ambient_light_color",
          "ambient_light_energy",
          "reflected_light_source",
          "tonemap_mode",
          "tonemap_exposure",
          "tonemap_white",
          "glow_enabled",
          "glow_intensity",
          "glow_strength",
          "glow_bloom",
          "fog_enabled",
          "fog_light_color",
          "fog_density",
          "fog_height",
          "fog_height_density",
          "volumetric_fog_enabled",
          "volumetric_fog_density",
          "volumetric_fog_albedo",
          "ssao_enabled",
          "ssao_radius",
          "ssao_intensity",
          "ssil_enabled",
          "sdfgi_enabled",
          "adjustment_enabled",
          "adjustment_brightness",
          "adjustment_contrast",
          "adjustment_saturation",
        ]),
        value: z.any(),
        createIfMissing: z.boolean().optional(),
        localToScene: z.boolean().optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.set_environment_property"](args),
  );

  server.registerTool(
    "godot.create_particle_effect",
    {
      title: "Create Godot 3D Particle Effect",
      description: "Create a GPUParticles3D node with a live ParticleProcessMaterial and optional QuadMesh draw pass through Godot UndoRedo without saving the scene.",
      inputSchema: {
        kind: z.enum(["gpu_particles_3d"]).optional(),
        parentPath: z.string().min(1).max(400).optional(),
        name: z.string().min(1).max(96).optional(),
        index: z.number().int().optional(),
        amount: z.number().int().min(1).max(10_000).optional(),
        lifetime: z.number().min(0.05).max(60).optional(),
        emitting: z.boolean().optional(),
        oneShot: z.boolean().optional(),
        explosiveness: z.number().min(0).max(1).optional(),
        randomness: z.number().min(0).max(1).optional(),
        speedScale: z.number().min(0).max(16).optional(),
        fixedFps: z.number().int().min(1).max(240).optional(),
        visibilityAabbSize: z.number().min(0.1).max(1000).optional(),
        drawMesh: z.enum(["quad", "none"]).optional(),
        drawSize: z.number().min(0.01).max(100).optional(),
        position: z.any().optional(),
        rotationDegrees: z.any().optional(),
        scale: z.any().optional(),
        direction: z.any().optional(),
        gravity: z.any().optional(),
        color: z.any().optional(),
        spread: z.number().min(0).max(180).optional(),
        initialVelocityMin: z.number().min(0).max(10000).optional(),
        initialVelocityMax: z.number().min(0).max(10000).optional(),
        particleScaleMin: z.number().min(0).max(1000).optional(),
        particleScaleMax: z.number().min(0).max(1000).optional(),
        localToScene: z.boolean().optional(),
        restart: z.boolean().optional(),
        select: z.boolean().optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.create_particle_effect"](args),
  );

  server.registerTool(
    "godot.set_particle_effect_properties",
    {
      title: "Set Godot Particle Effect Properties",
      description: "Edit an existing GPUParticles3D node and its ParticleProcessMaterial through Godot UndoRedo without saving the scene.",
      inputSchema: {
        nodePath: z.string().min(1).max(400),
        amount: z.number().int().min(1).max(10_000).optional(),
        lifetime: z.number().min(0.05).max(60).optional(),
        emitting: z.boolean().optional(),
        oneShot: z.boolean().optional(),
        explosiveness: z.number().min(0).max(1).optional(),
        randomness: z.number().min(0).max(1).optional(),
        speedScale: z.number().min(0).max(16).optional(),
        fixedFps: z.number().int().min(1).max(240).optional(),
        visibilityAabbSize: z.number().min(0.1).max(1000).optional(),
        drawMesh: z.enum(["quad", "none", "unchanged"]).optional(),
        drawSize: z.number().min(0.01).max(100).optional(),
        direction: z.any().optional(),
        gravity: z.any().optional(),
        color: z.any().optional(),
        spread: z.number().min(0).max(180).optional(),
        initialVelocityMin: z.number().min(0).max(10000).optional(),
        initialVelocityMax: z.number().min(0).max(10000).optional(),
        particleScaleMin: z.number().min(0).max(1000).optional(),
        particleScaleMax: z.number().min(0).max(1000).optional(),
        createProcessMaterialIfMissing: z.boolean().optional(),
        localToScene: z.boolean().optional(),
        restart: z.boolean().optional(),
        select: z.boolean().optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.set_particle_effect_properties"](args),
  );

  server.registerTool(
    "godot.list_animation_players",
    {
      title: "List Godot Animation Players",
      description: "Read live AnimationPlayer nodes in the current edited scene with bounded animation/library summaries.",
      inputSchema: {
        maxPlayers: z.number().int().min(1).max(64).optional(),
        includeEmpty: z.boolean().optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.list_animation_players"](args),
  );

  server.registerTool(
    "godot.inspect_animation",
    {
      title: "Inspect Godot Animation",
      description: "Inspect one AnimationPlayer and optionally one Animation with bounded tracks and key summaries.",
      inputSchema: {
        nodePath: z.string().min(1).max(400),
        animationName: z.string().min(1).max(120).optional(),
        includeKeys: z.boolean().optional(),
        maxTracks: z.number().int().min(1).max(120).optional(),
        maxKeysPerTrack: z.number().int().min(0).max(16).optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.inspect_animation"](args),
  );

  server.registerTool(
    "godot.preview_animation",
    {
      title: "Preview Godot Animation",
      description: "Preview, seek or pause an AnimationPlayer in the live editor. This is preview-only and does not save the scene.",
      inputSchema: {
        nodePath: z.string().min(1).max(400),
        animationName: z.string().min(1).max(120),
        mode: z.enum(["seek", "play", "pause"]).optional(),
        position: z.number().min(0).optional(),
        speed: z.number().min(-8).max(8).optional(),
        customBlend: z.number().optional(),
        fromEnd: z.boolean().optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.preview_animation"](args),
  );

  server.registerTool(
    "godot.stop_animation_preview",
    {
      title: "Stop Godot Animation Preview",
      description: "Stop an AnimationPlayer preview in the live editor without saving the scene.",
      inputSchema: {
        nodePath: z.string().min(1).max(400),
        keepState: z.boolean().optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.stop_animation_preview"](args),
  );

  server.registerTool(
    "godot.diagnostics_get",
    {
      title: "Get Godot Bridge Diagnostics",
      description: "Read combined live bridge diagnostics. V1 reports bridge-owned logs and declares native Output/Debugger support explicitly.",
      inputSchema: {
        limit: z.number().int().min(1).max(200).optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.diagnostics_get"](args),
  );

  server.registerTool(
    "godot.diagnostics_clear",
    {
      title: "Clear Godot Bridge Diagnostics",
      description: "Clear bridge-owned diagnostics after writing local evidence. Does not claim to clear native Godot Output unless supported.",
      inputSchema: {
        confirm: z.boolean().optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.diagnostics_clear"](args),
  );

  server.registerTool(
    "godot.set_node_transform",
    {
      title: "Set Godot Node Transform",
      description: "Apply an UndoRedo-backed unsaved Node2D/Node3D local transform edit in the live editor.",
      inputSchema: {
        nodePath: z.string().min(1).max(400),
        mode: z.enum(["absolute", "relative"]).optional(),
        position: z.any().optional(),
        rotationDegrees: z.any().optional(),
        scale: z.any().optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.set_node_transform"](args),
  );

  server.registerTool(
    "godot.set_node_properties",
    {
      title: "Set Godot Node Properties",
      description: "Apply up to 20 UndoRedo-backed unsaved safe scalar/vector/color property edits to a live editor node.",
      inputSchema: {
        nodePath: z.string().min(1).max(400),
        changes: z.array(z.object({ property: z.string().min(1).max(160), value: z.any() })).min(1).max(20),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.set_node_properties"](args),
  );

  server.registerTool(
    "godot.undo_last_bridge_action",
    {
      title: "Undo Last Godot Bridge Action",
      description: "Undo the latest current-scene UndoRedo action only when it was created by Godot Codex Bridge. Does not save the scene.",
      inputSchema: {
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.undo_last_bridge_action"](args),
  );

  server.registerTool(
    "godot.assign_resource_to_node",
    {
      title: "Assign Godot Resource To Node",
      description: "Assign or clear an existing project-local Resource on a live node property through Godot UndoRedo without saving the scene.",
      inputSchema: {
        nodePath: z.string().min(1).max(400),
        property: z.string().min(1).max(160),
        resourcePath: z.string().startsWith("res://").optional(),
        clear: z.boolean().optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.assign_resource_to_node"](args),
  );

  server.registerTool(
    "godot.create_node_resource",
    {
      title: "Create Godot Node Resource",
      description: "Create a new local Resource/subresource and assign it to a live node property through Godot UndoRedo without saving the scene.",
      inputSchema: {
        nodePath: z.string().min(1).max(400),
        property: z.string().min(1).max(160),
        resourceClass: z.string().min(1).max(96),
        localToScene: z.boolean().optional(),
        changes: z.array(z.object({ property: z.string().min(1).max(160), value: z.any() })).max(20).optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.create_node_resource"](args),
  );

  server.registerTool(
    "godot.set_resource_properties",
    {
      title: "Set Godot Resource Properties",
      description: "Edit properties on a Resource currently assigned to a live node property through Godot UndoRedo without saving the scene.",
      inputSchema: {
        nodePath: z.string().min(1).max(400),
        property: z.string().min(1).max(160),
        changes: z.array(z.object({ property: z.string().min(1).max(160), value: z.any() })).min(1).max(20),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.set_resource_properties"](args),
  );

  server.registerTool(
    "godot.create_node",
    {
      title: "Create Godot Node",
      description: "Create a Node-derived child in the live edited scene through Godot UndoRedo without saving the scene.",
      inputSchema: {
        parentPath: z.string().min(1).max(400).optional(),
        className: z.string().min(1).max(96).optional(),
        name: z.string().min(1).max(96).optional(),
        index: z.number().int().optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.create_node"](args),
  );

  server.registerTool(
    "godot.delete_node",
    {
      title: "Delete Godot Node",
      description: "Remove a non-root node from the live edited scene through Godot UndoRedo without saving the scene.",
      inputSchema: {
        nodePath: z.string().min(1).max(400),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.delete_node"](args),
  );

  server.registerTool(
    "godot.rename_node",
    {
      title: "Rename Godot Node",
      description: "Rename a node in the live edited scene through Godot UndoRedo without saving the scene.",
      inputSchema: {
        nodePath: z.string().min(1).max(400),
        newName: z.string().min(1).max(96),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.rename_node"](args),
  );

  server.registerTool(
    "godot.reparent_node",
    {
      title: "Reparent Godot Node",
      description: "Move a non-root node under another node through Godot UndoRedo without saving the scene.",
      inputSchema: {
        nodePath: z.string().min(1).max(400),
        newParentPath: z.string().min(1).max(400),
        index: z.number().int().optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.reparent_node"](args),
  );

  server.registerTool(
    "godot.duplicate_node",
    {
      title: "Duplicate Godot Node",
      description: "Duplicate a non-root node in the live edited scene through Godot UndoRedo without saving the scene.",
      inputSchema: {
        nodePath: z.string().min(1).max(400),
        parentPath: z.string().min(1).max(400).optional(),
        name: z.string().min(1).max(96).optional(),
        index: z.number().int().optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.duplicate_node"](args),
  );

  server.registerTool(
    "godot.instance_scene",
    {
      title: "Instance Godot Scene",
      description: "Instance a project-local PackedScene under a node through Godot UndoRedo without saving the edited scene.",
      inputSchema: {
        scenePath: z.string().startsWith("res://"),
        parentPath: z.string().min(1).max(400).optional(),
        name: z.string().min(1).max(96).optional(),
        index: z.number().int().optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.instance_scene"](args),
  );

  server.registerTool(
    "godot.place_asset_in_scene",
    {
      title: "Place Godot Asset In Scene",
      description: "Load a project-local PackedScene, Mesh/imported model or PNG Texture2D asset and place it in the live edited scene through Godot UndoRedo without saving.",
      inputSchema: {
        assetPath: z.string().startsWith("res://"),
        parentPath: z.string().min(1).max(400).optional(),
        name: z.string().min(1).max(96).optional(),
        index: z.number().int().optional(),
        position: z.any().optional(),
        rotationDegrees: z.any().optional(),
        scale: z.any().optional(),
        createCollider: z.boolean().optional(),
        materialColor: z.any().optional(),
        captureScreenshot: z.boolean().optional(),
        select: z.boolean().optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.place_asset_in_scene"](args),
  );

  server.registerTool(
    "godot.list_signal_connections",
    {
      title: "List Godot Signal Connections",
      description: "Read signal connection metadata for a live editor node without mutating the scene.",
      inputSchema: {
        nodePath: z.string().min(1).max(400),
        includeEmpty: z.boolean().optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.list_signal_connections"](args),
  );

  server.registerTool(
    "godot.connect_signal",
    {
      title: "Connect Godot Signal",
      description: "Connect a node signal to a target node method through Godot UndoRedo without saving the scene.",
      inputSchema: {
        sourceNodePath: z.string().min(1).max(400),
        signalName: z.string().min(1).max(160),
        targetNodePath: z.string().min(1).max(400),
        methodName: z.string().min(1).max(160),
        flags: z.number().int().min(0).max(65_535).optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.connect_signal"](args),
  );

  server.registerTool(
    "godot.disconnect_signal",
    {
      title: "Disconnect Godot Signal",
      description: "Disconnect a node signal from a target node method through Godot UndoRedo without saving the scene.",
      inputSchema: {
        sourceNodePath: z.string().min(1).max(400),
        signalName: z.string().min(1).max(160),
        targetNodePath: z.string().min(1).max(400),
        methodName: z.string().min(1).max(160),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.disconnect_signal"](args),
  );

  server.registerTool(
    "godot.create_animation_clip",
    {
      title: "Create Godot Animation Clip",
      description: "Create a new Animation resource in an AnimationPlayer through Godot UndoRedo without saving the scene. V1 supports value tracks.",
      inputSchema: {
        nodePath: z.string().min(1).max(400),
        animationName: z.string().min(1).max(120),
        libraryKey: z.string().max(120).optional(),
        length: z.number().min(0.001).max(3600).optional(),
        step: z.number().min(0.001).max(10).optional(),
        loopMode: z.number().int().min(0).max(2).optional(),
        tracks: z.array(z.object({
          type: z.literal("value").optional(),
          path: z.string().min(1).max(400),
          valueType: z.enum(["variant", "bool", "int", "float", "string", "vector2", "vector3", "color"]).optional(),
          interpolationType: z.number().int().min(0).max(2).optional(),
          keys: z.array(z.object({
            time: z.number().min(0).max(3600).optional(),
            value: z.any(),
            transition: z.number().min(-1024).max(1024).optional(),
          })).min(1).max(16),
        })).max(12).optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.create_animation_clip"](args),
  );

  server.registerTool(
    "godot.editor_batch",
    {
      title: "Run Godot Editor Action Batch",
      description: "Run a bounded batch of typed editor_control actions through one addon request to reduce live editor latency.",
      inputSchema: {
        actions: z.array(z.object({ action: z.string().min(1).max(80), params: z.record(z.string(), z.any()).optional() })).min(1).max(12),
        stopOnError: z.boolean().optional(),
        timeoutMs: z.number().int().min(250).max(60_000).optional(),
      },
    },
    async (args) => handlers["godot.editor_batch"](args),
  );

  server.registerTool(
    "godot.save_scene",
    {
      title: "Save Current Godot Scene",
      description: "Explicitly save the currently edited scene through Godot EditorInterface, then run a bounded Godot --headless --check-only parse check. Requires the Save scenes bridge permission.",
      inputSchema: {
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
        postSaveCheckTimeoutMs: z.number().int().min(1_000).max(60_000).optional(),
      },
    },
    async (args) => handlers["godot.save_scene"](args),
  );

  server.registerTool(
    "godot.save_all_scenes",
    {
      title: "Save All Open Godot Scenes",
      description: "Explicitly save all open Godot editor scenes through Godot EditorInterface. Requires the Save scenes bridge permission.",
      inputSchema: {
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.save_all_scenes"](args),
  );

  server.registerTool(
    "godot.notes_get",
    {
      title: "Get Godot Bridge Notes",
      description: "Read local bridge notes stored under .godot/godot_codex_bridge, not project gameplay files.",
      inputSchema: {
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.notes_get"](args),
  );

  server.registerTool(
    "godot.notes_append",
    {
      title: "Append Godot Bridge Note",
      description: "Append a local bridge note under .godot/godot_codex_bridge without mutating project source files.",
      inputSchema: {
        text: z.string().min(1).max(4_000),
        author: z.string().max(80).optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.notes_append"](args),
  );

  server.registerTool(
    "godot.notes_clear",
    {
      title: "Clear Godot Bridge Notes",
      description: "Clear local bridge notes after writing local evidence under bridge artifacts.",
      inputSchema: {
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.notes_clear"](args),
  );

  server.registerTool(
    "godot.inspect_3d_scene",
    {
      title: "Inspect Godot 3D Scene",
      description: "Read-only 3D diagnostics for cameras, lights, meshes, collision shapes, navigation regions, selected nodes and bounded performance probes.",
      inputSchema: {},
    },
    async () => handlers["godot.inspect_3d_scene"](),
  );

  server.registerTool(
    "godot.performance_get_snapshot",
    {
      title: "Get Godot Performance Snapshot",
      description: "Summarize bounded editor performance monitors from the latest context snapshot, including draw calls, physics, navigation and honest unavailable memory/VRAM fields.",
      inputSchema: {
        maxSamples: z.number().int().min(0).max(120).optional(),
      },
    },
    async (args) => handlers["godot.performance_get_snapshot"](args),
  );

  server.registerTool(
    "godot.create_diagnostic_snapshot",
    {
      title: "Create Godot Diagnostic Snapshot",
      description: "Persist the read-only 3D scene diagnostics as a local bridge artifact for collision/navmesh/debug review.",
      inputSchema: {
        label: z.string().max(80).optional(),
      },
    },
    async (args) => handlers["godot.create_diagnostic_snapshot"](args),
  );

  server.registerTool(
    "godot.create_visual_baseline",
    {
      title: "Create Godot Visual Baseline",
      description: "Copy a local PNG screenshot into bridge visual regression baselines.",
      inputSchema: {
        screenshotPath: z.string().min(1),
        baselineName: z.string().max(80).optional(),
      },
    },
    async (args) => handlers["godot.create_visual_baseline"](args),
  );

  server.registerTool(
    "godot.compare_visual_regression",
    {
      title: "Compare Godot Visual Regression",
      description: "Compare a current local PNG screenshot with a stored baseline by dimensions, byte size and SHA-256.",
      inputSchema: {
        currentScreenshotPath: z.string().min(1),
        baselineName: z.string().max(80).optional(),
        baselinePath: z.string().optional(),
      },
    },
    async (args) => handlers["godot.compare_visual_regression"](args),
  );

  server.registerTool(
    "godot.check_export_readiness",
    {
      title: "Check Godot Export Readiness",
      description: "Read-only desktop/mobile export readiness checks for project.godot and export_presets.cfg.",
      inputSchema: {},
    },
    async () => handlers["godot.check_export_readiness"](),
  );

  server.registerTool(
    "godot.create_undo_snapshot",
    {
      title: "Create Godot Undo Snapshot",
      description: "Copy explicitly listed project-relative text scene/script/resource files into a local bridge undo snapshot artifact.",
      inputSchema: {
        paths: z.array(z.string().min(1)).min(1).max(50),
        label: z.string().max(80).optional(),
      },
    },
    async (args) => handlers["godot.create_undo_snapshot"](args),
  );

  server.registerTool(
    "godot.apply_approved_diff",
    {
      title: "Apply Approved Godot Diff",
      description: "Apply reviewed text content to a safe project-relative path after explicit approval token and optional current hash check.",
      inputSchema: {
        path: z.string().min(1),
        proposedContent: z.string(),
        allowCreate: z.boolean().optional(),
        expectedCurrentSha256: z.string().optional(),
        approvalToken: z.string().min(1),
        label: z.string().max(80).optional(),
      },
    },
    async (args) => handlers["godot.apply_approved_diff"](args),
  );

  server.registerTool(
    "godot.generate_scene_from_prompt",
    {
      title: "Plan Godot Scene From Prompt",
      description: "Return a safe live-editor action plan for building a scene from a prompt. This tool does not generate .tscn content or apply files.",
      inputSchema: {
        prompt: z.string().min(1),
        path: z.string().min(1),
        apply: z.boolean().optional(),
        approvalToken: z.string().optional(),
      },
    },
    async (args) => handlers["godot.generate_scene_from_prompt"](args),
  );

  server.registerTool(
    "godot.fix_selected_node",
    {
      title: "Fix Selected Godot Node",
      description: "Ask the live addon to apply a narrow undoable fix to the currently selected node after dock permission and approval token.",
      inputSchema: {
        fixCode: z.enum([
          "unhide_node",
          "make_camera_current",
          "enable_collision_shape",
          "enable_navigation_region",
          "set_light_energy_default",
          "enable_light_shadows",
        ]),
        approvalToken: z.string().min(1),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.fix_selected_node"](args),
  );

  server.registerTool(
    "godot.capture_viewport_screenshot",
    {
      title: "Capture Godot Viewport Screenshot",
      description: "Ask the active Godot addon to capture a local viewport screenshot artifact.",
      inputSchema: {
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.capture_viewport_screenshot"](args),
  );

  server.registerTool(
    "godot.capture_timeline_screenshots",
    {
      title: "Capture Godot Timeline Screenshots",
      description: "Capture a bounded sequence of local viewport screenshots for animation/shader/runtime feedback and write a local timeline manifest.",
      inputSchema: {
        frameCount: z.number().int().min(2).max(12).optional(),
        intervalMs: z.number().int().min(50).max(5_000).optional(),
        reason: z.string().max(120).optional(),
        baselineName: z.string().max(80).optional(),
        baselinePath: z.string().optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.capture_timeline_screenshots"](args),
  );

  server.registerTool(
    "godot.capture_multi_view_screenshots",
    {
      title: "Capture Godot Multi-View Screenshots",
      description: "Capture front, side, top orthographic and perspective local PNG evidence for a Node3D target, selection or group.",
      inputSchema: {
        nodePath: z.string().max(400).optional(),
        groupName: z.string().max(96).optional(),
        selectedOnly: z.boolean().optional(),
        maxNodes: z.number().int().min(1).max(256).optional(),
        width: z.number().int().min(64).max(2048).optional(),
        height: z.number().int().min(64).max(2048).optional(),
        views: z.array(z.enum(["front", "side", "top", "perspective"])).min(1).max(4).optional(),
        baselineName: z.string().max(80).optional(),
        baselinePath: z.string().optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.capture_multi_view_screenshots"](args),
  );

  server.registerTool(
    "godot.open_scene",
    {
      title: "Open Godot Scene",
      description: "Ask the active Godot addon to open a project-local scene in the editor and optionally focus the 2D/3D/Script main screen.",
      inputSchema: {
        scenePath: z.string().startsWith("res://"),
        makeMainScreen: z.enum(["2D", "3D", "Script"]).optional(),
        selectInFileSystem: z.boolean().optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.open_scene"](args),
  );

  server.registerTool(
    "godot.run_current_scene",
    {
      title: "Run Current Godot Scene",
      description: "Ask the active Godot addon to run the currently open scene, or a specific project-local scene when scenePath is provided.",
      inputSchema: {
        scenePath: z.string().startsWith("res://").optional(),
        timeoutMs: z.number().int().min(1_000).max(60_000).optional(),
      },
    },
    async (args) => handlers["godot.run_current_scene"](args),
  );

  server.registerTool(
    "godot.stop_running_scene",
    {
      title: "Stop Running Godot Scene",
      description: "Ask the active Godot addon to stop the current editor play session if one is running and release Bridge-owned playtest input.",
      inputSchema: {
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.stop_running_scene"](args),
  );

  server.registerTool(
    "godot.emergency_stop",
    {
      title: "Emergency Stop Godot Bridge Runtime",
      description: "Stop any Bridge-owned editor play session, release held playtest input, and close the Bridge playtest session token.",
      inputSchema: {
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.emergency_stop"](args),
  );

  server.registerTool(
    "godot.playtest_input",
    {
      title: "Send Godot Playtest Input",
      description: "Send a bounded typed input batch to a bridge-owned running scene through the opt-in runtime probe. Requires the Playtest input bridge permission.",
      inputSchema: {
        steps: z.array(z.object({
          type: z.enum(["action_press", "action_release", "axis", "key", "mouse_button"]),
          action: z.string().min(1).max(128).optional(),
          negativeAction: z.string().min(1).max(128).optional(),
          positiveAction: z.string().min(1).max(128).optional(),
          strength: z.number().min(0).max(1).optional(),
          value: z.number().min(-1).max(1).optional(),
          keycode: z.number().int().min(1).optional(),
          physicalKeycode: z.number().int().min(1).optional(),
          buttonIndex: z.number().int().min(1).max(16).optional(),
          pressed: z.boolean().optional(),
          position: z.object({ x: z.number(), y: z.number() }).optional(),
        })).min(1).max(16).optional(),
        type: z.enum(["action_press", "action_release", "axis", "key", "mouse_button"]).optional(),
        action: z.string().min(1).max(128).optional(),
        negativeAction: z.string().min(1).max(128).optional(),
        positiveAction: z.string().min(1).max(128).optional(),
        strength: z.number().min(0).max(1).optional(),
        value: z.number().min(-1).max(1).optional(),
        keycode: z.number().int().min(1).optional(),
        physicalKeycode: z.number().int().min(1).optional(),
        buttonIndex: z.number().int().min(1).max(16).optional(),
        pressed: z.boolean().optional(),
        position: z.object({ x: z.number(), y: z.number() }).optional(),
        reason: z.string().max(160).optional(),
        timeoutMs: z.number().int().min(250).max(30_000).optional(),
      },
    },
    async (args) => handlers["godot.playtest_input"](args),
  );

  server.registerTool(
    "godot.run_playtest_scenario",
    {
      title: "Run Godot Playtest Scenario",
      description: "Run a project-local scene through the live addon and execute a bounded playtest scenario contract. The addon must support the run_playtest_scenario editor-control action.",
      inputSchema: {
        scenePath: z.string().startsWith("res://"),
        steps: z.array(z.object({
          type: z.enum(["press_action", "release_action", "wait_seconds", "wait_for_event", "capture", "assert"]),
          action: z.string().min(1).max(128).optional(),
          strength: z.number().min(0).max(1).optional(),
          seconds: z.number().min(0).max(10).optional(),
          event: z.string().min(1).max(160).optional(),
          eventName: z.string().min(1).max(160).optional(),
          event_type: z.string().min(1).max(160).optional(),
          timeoutSeconds: z.number().min(0.05).max(30).optional(),
          source: z.enum(["runtime_state", "runtime_events", "fixture_diagnostics", "viewport_screenshot", "timeline_screenshot"]).optional(),
          frameCount: z.number().int().min(2).max(12).optional(),
          frame_count: z.number().int().min(2).max(12).optional(),
          intervalMs: z.number().int().min(50).max(5_000).optional(),
          interval_ms: z.number().int().min(50).max(5_000).optional(),
          assertion: z.enum([
            "runtime_event_present",
            "runtime_scene_changed",
            "runtime_state_active_scene",
            "runtime_state_node_exists",
            "runtime_state_position_delta",
            "runtime_state_rotation_delta",
          ]).optional(),
          scene_path: z.string().startsWith("res://").optional(),
          nodePath: z.string().min(1).max(400).optional(),
          node_path: z.string().min(1).max(400).optional(),
          nodeName: z.string().min(1).max(128).optional(),
          node_name: z.string().min(1).max(128).optional(),
          nodeType: z.string().min(1).max(128).optional(),
          node_type: z.string().min(1).max(128).optional(),
          axis: z.enum(["x", "y", "z"]).optional(),
          minDelta: z.number().min(0).max(1_000_000).optional(),
          min_delta: z.number().min(0).max(1_000_000).optional(),
          maxDelta: z.number().min(0).max(1_000_000).optional(),
          max_delta: z.number().min(0).max(1_000_000).optional(),
          epsilon: z.number().min(0).max(1000).optional(),
        })).min(1).max(32),
        timeoutMs: z.number().int().min(1_000).max(60_000).optional(),
      },
    },
    async (args) => handlers["godot.run_playtest_scenario"](args),
  );

  server.registerTool(
    "godot.runtime_get_state",
    {
      title: "Get Godot Runtime State",
      description: "Read the local opt-in runtime probe state file without mutating the editor or running arbitrary scripts.",
      inputSchema: {
        maxAgeMs: z.number().int().min(0).max(600_000).optional(),
        maxBytes: z.number().int().min(16 * 1024).max(2 * 1024 * 1024).optional(),
      },
    },
    async (args) => handlers["godot.runtime_get_state"](args),
  );

  server.registerTool(
    "godot.runtime_get_events",
    {
      title: "Get Godot Runtime Events",
      description: "Read the local opt-in runtime probe events buffer without mutating the editor or running arbitrary scripts.",
      inputSchema: {
        maxAgeMs: z.number().int().min(0).max(600_000).optional(),
        maxBytes: z.number().int().min(16 * 1024).max(2 * 1024 * 1024).optional(),
      },
    },
    async (args) => handlers["godot.runtime_get_events"](args),
  );

  server.registerTool(
    "godot.run_test_scene",
    {
      title: "Run Godot Test Scene",
      description: "Run a configured project-local test scene through the fixed Godot executable without shell access.",
      inputSchema: {
        scenePath: z.string().startsWith("res://").optional(),
        timeoutMs: z.number().int().min(1_000).max(60_000).optional(),
      },
    },
    async (args) => handlers["godot.run_test_scene"](args),
  );

  server.registerTool(
    "godot.preview_scene_diff",
    {
      title: "Preview Godot File Diff",
      description: "Create a unified diff for a safe project-relative text scene/script/resource path without applying it.",
      inputSchema: {
        path: z.string().min(1),
        proposedContent: z.string(),
        allowCreate: z.boolean().optional(),
        contextLines: z.number().int().min(0).max(20).optional(),
      },
    },
    async (args) => handlers["godot.preview_scene_diff"](args),
  );
}
