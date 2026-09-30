// "Allow for this session" for read-only Godot Bridge MCP tools. The Host
// remembers the user's choice itself; nothing depends on Codex honouring a
// persistence hint. Only the Bridge's own server and only tools that inspect
// without writing files or sending screenshots qualify; mutations, file
// writes, screenshots and runtime input always ask.

export const BRIDGE_MCP_SERVER_NAME = "godot_codex_bridge";

/**
 * Subset of the MCP tool catalog's "read_only" tools (mcp_server/src/toolCatalog.ts)
 * that neither write artifacts nor send screenshots. A test keeps every entry
 * classified read_only in the catalog.
 */
export const SESSION_ALLOWABLE_TOOLS: ReadonlySet<string> = new Set([
  "godot.get_tool_catalog",
  "godot.bridge_status",
  "godot.get_project_overview",
  "godot.project_get_map",
  "godot.project_scene_graph",
  "godot.project_script_map",
  "godot.get_agents_context",
  "godot.get_current_source_context",
  "godot.editor_get_state",
  "godot.editor_capabilities",
  "godot.get_current_scene",
  "godot.get_scene_tree",
  "godot.get_selected_nodes",
  "godot.list_project_files",
  "godot.search_project_files",
  "godot.read_project_file",
  "godot.get_scene_file_tree",
  "godot.get_script_inventory",
  "godot.list_annotations",
  "godot.get_latest_annotation",
  "godot.get_annotation",
  "godot.resolve_annotation_target",
  "godot.inspect_node",
  "godot.get_inspector_context",
  "godot.get_node_deep",
  "godot.get_spatial_bounds",
  "godot.spatial_query",
  "godot.placement_check",
  "godot.list_resources",
  "godot.inspect_imported_assets",
  "godot.get_class_info",
  "godot.get_editor_output",
  "godot.get_resource_status",
  "godot.get_gameplay_context",
  "godot.diagnostics_get",
  "godot.inspect_3d_scene",
  "godot.performance_get_snapshot",
  "godot.check_export_readiness",
  "godot.inspect_materials",
  "godot.inspect_rendering_effects",
  "godot.list_animation_players",
  "godot.inspect_animation",
  "godot.list_signal_connections",
  "godot.preview_scene_diff",
  "godot.runtime_get_state",
  "godot.runtime_get_events",
  "godot.notes_get",
]);

const TOOL_MESSAGE = /^Allow the godot_codex_bridge MCP server to run tool "(godot\.[a-z0-9_]+)"\?$/;

/**
 * The Bridge tool an elicitation asks to run, when it is a plain yes/no tool
 * approval for a session-allowable tool; otherwise null.
 */
export function sessionAllowableTool(rawMethod: unknown, rawParams: unknown): string | null {
  if (rawMethod !== "mcpServer/elicitation/request") return null;
  const params = objectValue(rawParams);
  if (!params || params.serverName !== BRIDGE_MCP_SERVER_NAME || params.mode !== "form") return null;
  if (objectValue(params._meta)?.codex_approval_kind !== "mcp_tool_call") return null;
  // Only a pure confirmation: no form fields whose answers the Host would invent.
  const schema = objectValue(params.requestedSchema);
  const properties = objectValue(schema?.properties);
  if (!schema || (properties && Object.keys(properties).length > 0)) return null;
  const match = typeof params.message === "string" ? TOOL_MESSAGE.exec(params.message) : null;
  const tool = match?.[1] ?? null;
  return tool && SESSION_ALLOWABLE_TOOLS.has(tool) ? tool : null;
}

function objectValue(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : null;
}
