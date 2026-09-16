@tool
extends RefCounted

const BridgeContext := preload("bridge_context.gd")
const BridgeLimits := preload("bridge_limits.gd")
const EditorPathGuard := preload("editor_path_guard.gd")

var _context: BridgeContext


func _init(context: BridgeContext = null) -> void:
	_context = context


func list_resources(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_editor_diagnostics"):
		return _err("permission_denied", "Diagnostics capture permission is disabled in the Codex Bridge dock.")

	var resource_fs := EditorInterface.get_resource_filesystem()
	if resource_fs == null or resource_fs.get_filesystem() == null:
		return _ok({
			"scan_status": "unavailable",
			"resources": [],
			"returned_count": 0,
			"matched_count": 0,
			"truncated": false,
			"snapshot_refreshed": false,
		})

	var root_path := root_path_from_params(params)
	var root_error := validate_res_dir_path(root_path)
	if not root_error.is_empty():
		return {"ok": false, "error": root_error}
	var extensions := extension_filter_array(params.get("extensions", []))
	var type_filter := str(params.get("type", params.get("typeFilter", ""))).strip_edges()
	var limit := clampi(int(params.get("limit", 120)), 1, BridgeLimits.MAX_RESOURCES)
	var resources: Array = []
	var state := {
		"matched_count": 0,
		"visited_count": 0,
		"truncated": false,
	}
	collect_resource_listing(resource_fs.get_filesystem(), resources, state, root_path, extensions, type_filter, limit)
	return _ok({
		"captured_at": _timestamp(),
		"scan_status": "partial" if resource_fs.is_scanning() else "complete",
		"root_path": root_path,
		"extensions": extensions,
		"type_filter": type_filter if type_filter != "" else null,
		"resources": resources,
		"returned_count": resources.size(),
		"matched_count": int(state.get("matched_count", 0)),
		"visited_count": int(state.get("visited_count", 0)),
		"truncated": bool(state.get("truncated", false)),
		"limit": limit,
		"snapshot_refreshed": false,
	})


static func root_path_from_params(params: Dictionary) -> String:
	var root_path := str(params.get("root_path", params.get("rootPath", "res://"))).strip_edges()
	if root_path == "":
		return "res://"
	return root_path


static func validate_res_dir_path(res_path: String) -> Dictionary:
	return EditorPathGuard.validate_res_dir_path(res_path)


static func extension_filter_array(value: Variant) -> Array:
	var extensions: Array = []
	if typeof(value) != TYPE_ARRAY:
		return extensions
	for item in value as Array:
		var extension := str(item).strip_edges().to_lower()
		if extension == "":
			continue
		if not extension.begins_with("."):
			extension = "." + extension
		if extension.length() > 16 or extension.find("/") >= 0 or extension.find("\\") >= 0:
			continue
		if not extension in extensions:
			extensions.append(extension)
		if extensions.size() >= 24:
			break
	return extensions


static func resource_matches_filters(path_value: String, type_value: String, root_path: String, extensions: Array, type_filter: String) -> bool:
	var normalized_root := root_path
	if normalized_root != "res://" and normalized_root.ends_with("/"):
		normalized_root = normalized_root.substr(0, normalized_root.length() - 1)
	if normalized_root != "res://" and not path_value.begins_with(normalized_root + "/") and path_value != normalized_root:
		return false
	var lower_path := path_value.to_lower()
	if not extensions.is_empty():
		var extension_ok := false
		for extension in extensions:
			if lower_path.ends_with(str(extension)):
				extension_ok = true
				break
		if not extension_ok:
			return false
	if type_filter != "" and type_value.to_lower() != type_filter.to_lower():
		return false
	return true


static func collect_resource_listing(directory: EditorFileSystemDirectory, resources: Array, state: Dictionary, root_path: String, extensions: Array, type_filter: String, limit: int) -> void:
	for file_index in range(directory.get_file_count()):
		state["visited_count"] = int(state.get("visited_count", 0)) + 1
		var file_path := directory.get_file_path(file_index)
		var file_type := str(directory.get_file_type(file_index))
		if not resource_matches_filters(file_path, file_type, root_path, extensions, type_filter):
			continue
		state["matched_count"] = int(state.get("matched_count", 0)) + 1
		if resources.size() >= limit:
			state["truncated"] = true
			continue
		var import_valid := directory.get_file_import_is_valid(file_index)
		resources.append({
			"path": file_path,
			"type": file_type,
			"import_valid": import_valid,
			"status": "ok" if import_valid else "import_error",
		})

	for subdir_index in range(directory.get_subdir_count()):
		collect_resource_listing(directory.get_subdir(subdir_index), resources, state, root_path, extensions, type_filter, limit)


func _permission_enabled(key: String) -> bool:
	return _context != null and _context.permission_enabled(key)


func _timestamp() -> String:
	if _context != null:
		return _context.timestamp_iso()
	return Time.get_datetime_string_from_system(true, true)


func _ok(data: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"data": data,
	}


func _err(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"error": _context.err(code, message) if _context != null else _static_error_payload(code, message),
	}


static func _static_error_payload(code: String, message: String) -> Dictionary:
	return {
		"code": code,
		"message": message,
	}
