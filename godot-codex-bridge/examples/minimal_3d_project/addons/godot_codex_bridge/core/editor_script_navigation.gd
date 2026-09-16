@tool
extends RefCounted

const BridgeContext := preload("bridge_context.gd")
const EditorPathGuard := preload("editor_path_guard.gd")

const SCRIPT_EXTENSIONS := [".gd", ".cs", ".gdshader", ".shader"]

var _context: BridgeContext


func _init(context: BridgeContext = null) -> void:
	_context = context


func open_script(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_editor_navigation"):
		return _err("permission_denied", "Navigate editor permission is disabled in the Codex Bridge dock.")

	var script_path := script_path_from_params(params)
	var path_error := validate_script_path(script_path, true)
	if not path_error.is_empty():
		return {"ok": false, "error": path_error}

	EditorInterface.set_main_screen_editor("Script")
	EditorInterface.select_file(script_path)
	var resource := ResourceLoader.load(script_path)
	var opened := false
	if resource is Script:
		EditorInterface.edit_script(resource)
		opened = true
	elif resource != null and EditorInterface.has_method("edit_resource"):
		EditorInterface.call("edit_resource", resource)
		opened = true

	var line := line_from_params(params)
	if line > 0 and EditorInterface.has_method("get_script_editor"):
		var script_editor: Variant = EditorInterface.call("get_script_editor")
		if script_editor != null and script_editor.has_method("goto_line"):
			script_editor.call("goto_line", line)

	var snapshot := _refresh("editor_control:open_script")
	var data := {
		"opened_script": script_path,
		"line": line if line > 0 else null,
		"opened_in_script_editor": opened,
		"selected_file": script_path,
		"snapshot_refreshed": true,
		"generated_at": snapshot.get("generated_at", ""),
	}
	_log("editor_script_opened", data)
	return _ok(data)


static func script_path_from_params(params: Dictionary) -> String:
	return str(params.get("script_path", params.get("scriptPath", ""))).strip_edges()


static func line_from_params(params: Dictionary) -> int:
	return max(0, int(params.get("line", 0)))


static func validate_script_path(script_path: String, must_exist: bool) -> Dictionary:
	return EditorPathGuard.validate_res_path(script_path, SCRIPT_EXTENSIONS, "script", must_exist)


func _permission_enabled(key: String) -> bool:
	return _context != null and _context.permission_enabled(key)


func _refresh(reason: String) -> Dictionary:
	if _context != null:
		return _context.refresh(reason)
	return {}


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
