@tool
extends RefCounted

## "Allow this session" for read-only Godot Bridge MCP tools (Host contract:
## approval.requested.session_allow_tool, approval.respond.remember_for_session,
## approval.auto_approved, host.status.sessionAllowedTools,
## approval.session_allow.clear). Pure logic.

const CLEAR_METHOD := "approval.session_allow.clear"
const MAX_TOOLS := 64
const MAX_TOOL_CHARS := 96


## A remembered tool name must look like a Godot Bridge tool.
static func valid_tool_name(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var name := value as String
	if not name.begins_with("godot.") or name.length() <= 6 or name.length() > MAX_TOOL_CHARS:
		return false
	for character in name.substr(6):
		if not (character in "abcdefghijklmnopqrstuvwxyz0123456789_"):
			return false
	return true


static func tool_name(params: Dictionary) -> String:
	var value: Variant = params.get("session_allow_tool")
	return value as String if valid_tool_name(value) else ""


static func sanitize_tools(value: Variant) -> Array[String]:
	var tools: Array[String] = []
	if not (value is Array):
		return tools
	for item in value as Array:
		if valid_tool_name(item) and not tools.has(item) and tools.size() < MAX_TOOLS:
			tools.append(item as String)
	return tools


static func allow_tooltip(tool: String) -> String:
	return "Approve now and let Codex use " + tool + " again without asking until the Host restarts. Changes to your project still ask every time."


## Coalesces approval.auto_approved events: consecutive ones in the same turn
## update one transcript line. Returns {state, text, new_line}.
static func coalesce(state: Dictionary, params: Dictionary, line_still_last: bool) -> Dictionary:
	var tool := str(params.get("tool", "")).strip_edges()
	if not valid_tool_name(tool):
		tool = "a remembered Godot tool"
	var turn_id := str(params.get("turn_id", "")).strip_edges()
	var tools: Array = []
	var new_line := true
	if line_still_last and not (state.get("tools", []) as Array).is_empty() and str(state.get("turn_id", "")) == turn_id:
		tools = (state.get("tools", []) as Array).duplicate()
		new_line = false
	if not tools.has(tool) and tools.size() < MAX_TOOLS:
		tools.append(tool)
	return {
		"state": {"turn_id": turn_id, "tools": tools},
		"text": auto_approved_text(tools),
		"new_line": new_line,
	}


static func auto_approved_text(tools: Array) -> String:
	return "Auto-approved: " + ", ".join(PackedStringArray(tools)) + " (allowed this session)"


static func summary_text(tools: Array) -> String:
	return "Allowed this session: " + str(tools.size()) + (" tool" if tools.size() == 1 else " tools")


static func summary_tooltip(tools: Array) -> String:
	if tools.is_empty():
		return "No Godot tools are allowed for this session."
	return "Codex may use these read-only Godot tools without asking until the Host restarts:\n" + "\n".join(PackedStringArray(tools))
