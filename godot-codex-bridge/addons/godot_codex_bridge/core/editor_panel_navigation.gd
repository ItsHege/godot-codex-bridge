@tool
extends RefCounted

const BridgeContext := preload("bridge_context.gd")

const PANEL_ALIASES := {
	"output": "Output",
	"console": "Output",
	"log": "Output",
	"debugger": "Debugger",
	"errors": "Debugger",
	"error": "Debugger",
	"warnings": "Debugger",
	"warning": "Debugger",
	"stack trace": "Stack Trace",
	"stacktrace": "Stack Trace",
	"audio": "Audio",
	"animation": "Animation",
	"shader": "Shader Editor",
	"shader editor": "Shader Editor",
	"signal visualizer": "Signal Visualizer",
	"signals": "Signal Visualizer",
	"profiler": "Profiler",
	"visual profiler": "Visual Profiler",
	"monitors": "Monitors",
	"video ram": "Video RAM",
	"network profiler": "Network Profiler",
	"inspector": "Inspector",
	"filesystem": "FileSystem",
	"file system": "FileSystem",
	"scene": "Scene",
	"import": "Import",
}

const SUPPORTED_PANELS := [
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
]

var _context: BridgeContext


func _init(context: BridgeContext = null) -> void:
	_context = context


func focus_panel(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_editor_navigation"):
		return _err("permission_denied", "Navigate editor permission is disabled in the Codex Bridge dock.")

	var requested := str(params.get("panel", params.get("panelName", ""))).strip_edges()
	var canonical := canonical_panel_name(requested)
	if canonical == "":
		return _err("invalid_editor_panel", "panel must be one of: " + supported_panel_text())

	var base := EditorInterface.get_base_control()
	if base == null:
		return _err("editor_base_control_unavailable", "Godot editor base control is unavailable.")

	var result := focus_tab_recursive(base, canonical)
	if not bool(result.get("found", false)):
		return _err("editor_panel_not_found", "Could not find a visible Godot editor tab named " + canonical + ".")

	var data := {
		"requested_panel": requested,
		"panel": canonical,
		"matched_title": result.get("matched_title", ""),
		"matched_control_class": result.get("matched_control_class", ""),
		"matched_tab_index": result.get("matched_tab_index", -1),
		"native_clear_supported": false,
		"snapshot_refreshed": false,
		"guidance": "Panel focus is navigation-only. Native Output/Debugger clear is not claimed in V1.",
	}
	_log("editor_panel_focused", data)
	return _ok(data)


static func canonical_panel_name(value: String) -> String:
	var normalized := _normalize(value)
	if normalized == "":
		return ""
	if PANEL_ALIASES.has(normalized):
		return str(PANEL_ALIASES.get(normalized))
	for panel in SUPPORTED_PANELS:
		if _normalize(str(panel)) == normalized:
			return str(panel)
	return ""


static func supported_panels() -> Array:
	return SUPPORTED_PANELS.duplicate()


static func supported_panel_text() -> String:
	var names: PackedStringArray = []
	for panel in SUPPORTED_PANELS:
		names.append(str(panel))
	return ", ".join(names)


static func focus_tab_recursive(root: Node, panel: String) -> Dictionary:
	return _focus_tab_recursive(root, _normalize(panel), {})


static func _focus_tab_recursive(node: Node, normalized_panel: String, visited: Dictionary) -> Dictionary:
	if node == null:
		return {"found": false}
	var id := node.get_instance_id()
	if visited.has(id):
		return {"found": false}
	visited[id] = true

	var tab_result := _try_focus_tab_holder(node, normalized_panel)
	if bool(tab_result.get("found", false)):
		return tab_result

	for child in node.get_children():
		if child is Node:
			var child_result := _focus_tab_recursive(child as Node, normalized_panel, visited)
			if bool(child_result.get("found", false)):
				return child_result

	return {"found": false}


static func _try_focus_tab_holder(node: Node, normalized_panel: String) -> Dictionary:
	if not (node is TabContainer or node is TabBar):
		return {"found": false}
	if not node.has_method("get_tab_count") or not node.has_method("get_tab_title"):
		return {"found": false}

	var tab_count := int(node.call("get_tab_count"))
	for index in range(tab_count):
		var title := str(node.call("get_tab_title", index))
		if _normalize(title) == normalized_panel:
			_set_current_tab(node, index)
			if node is Control and (node as Control).is_inside_tree():
				(node as Control).grab_focus()
			return {
				"found": true,
				"matched_title": title,
				"matched_control_class": node.get_class(),
				"matched_tab_index": index,
			}
	return {"found": false}


static func _set_current_tab(node: Node, index: int) -> void:
	if node is TabContainer:
		(node as TabContainer).current_tab = index
	elif node is TabBar:
		(node as TabBar).current_tab = index
	elif node.has_method("set_current_tab"):
		node.call("set_current_tab", index)
	else:
		node.set("current_tab", index)


static func _normalize(value: String) -> String:
	return value.strip_edges().to_lower().replace("_", " ").replace("-", " ").replace("  ", " ")


func _permission_enabled(key: String) -> bool:
	return _context != null and _context.permission_enabled(key)


func _log(event_name: String, data: Dictionary = {}) -> void:
	if _context != null:
		_context.log(event_name, data)


func _ok(data: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"data": data,
	}


func _err(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"error": _context.err(code, message) if _context != null else {"code": code, "message": message},
	}
