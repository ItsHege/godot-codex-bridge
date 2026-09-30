@tool
extends RefCounted


static func validate_res_dir_path(res_path: String, code: String = "invalid_resource_root", generated_message: String = "Generated Godot cache/import paths cannot be listed through editor control.") -> Dictionary:
	if not res_path.begins_with("res://"):
		return error_payload(code, "Resource root must start with res://.")
	var resource_path := res_path.trim_prefix("res://")
	if resource_path == "":
		return {}
	var segment_error := validate_resource_segments(resource_path)
	if not segment_error.is_empty():
		return error_payload(code, "Resource root cannot contain empty, current-directory or parent-directory segments.")
	if is_generated_resource_path(resource_path):
		return error_payload(code, generated_message)
	return {}


static func validate_res_path(res_path: String, allowed_extensions: Array, kind: String, must_exist: bool, generated_message: String = "Generated Godot cache/import paths cannot be used through editor control.") -> Dictionary:
	if not res_path.begins_with("res://"):
		return error_payload("invalid_" + kind + "_path", kind.capitalize() + " path must start with res://.")
	var resource_path := res_path.trim_prefix("res://")
	if resource_path == "":
		return error_payload("invalid_" + kind + "_path", kind.capitalize() + " path cannot be empty.")
	var segment_error := validate_resource_segments(resource_path)
	if not segment_error.is_empty():
		return error_payload("invalid_" + kind + "_path", kind.capitalize() + " path cannot contain empty, current-directory or parent-directory segments.")
	if is_generated_resource_path(resource_path):
		return error_payload("invalid_" + kind + "_path", generated_message)
	var lower := resource_path.to_lower()
	if not allowed_extensions.is_empty() and not extension_allowed(lower, allowed_extensions):
		return error_payload("invalid_" + kind + "_extension", kind.capitalize() + " path has an unsupported extension.")
	if must_exist and not FileAccess.file_exists(res_path) and not ResourceLoader.exists(res_path):
		return error_payload(kind + "_not_found", kind.capitalize() + " file does not exist: " + res_path)
	return {}


static func validate_scene_path(scene_path: String, must_exist: bool = true) -> Dictionary:
	var path_error := validate_res_path(scene_path, [".tscn", ".scn"], "scene", false, "Generated Godot cache/import paths cannot be opened through the bridge.")
	if not path_error.is_empty():
		if path_error.get("code") == "invalid_scene_extension":
			return error_payload("invalid_scene_extension", "Scene path must end in .tscn or .scn.")
		return path_error
	if must_exist and not FileAccess.file_exists(scene_path) and not ResourceLoader.exists(scene_path, "PackedScene"):
		return error_payload("scene_not_found", "Scene file does not exist: " + scene_path)
	return {}


static func validate_scene_local_node_path(node_path: String) -> Dictionary:
	if node_path.begins_with("res://") or node_path.find("..") >= 0 or node_path.find("\n") >= 0 or node_path.find("\r") >= 0:
		return error_payload("invalid_node_path", "nodePath must be a scene-local node path, not a file path or traversal.")
	return {}


## Also rejects backslashes and segments ending in "." or " ": Windows strips
## those on open, so "res://.godot./x" or "res://.godot /x" would alias ".godot".
static func validate_resource_segments(resource_path: String) -> Dictionary:
	if resource_path.find("\\") >= 0:
		return error_payload("invalid_resource_path_segment", "Resource paths cannot contain backslashes.")
	var parts := resource_path.split("/")
	for part in parts:
		if part == "" or part == "." or part == "..":
			return error_payload("invalid_resource_path_segment", "Resource paths cannot contain empty, current-directory or parent-directory segments.")
		if part.ends_with(".") or part.ends_with(" "):
			return error_payload("invalid_resource_path_segment", "Resource path segments cannot end with a dot or space.")
	return {}


## Case-insensitive (Windows/macOS filesystems fold case) and tolerant of
## Windows aliases: trailing dots/spaces and NTFS ":stream" suffixes are
## ignored when comparing, and backslashes count as separators.
static func is_generated_resource_path(resource_path: String) -> bool:
	var parts := resource_path.replace("\\", "/").split("/", false)
	for index in range(parts.size()):
		var name := _comparable_segment(parts[index])
		if name == ".import" or (index == 0 and name == ".godot"):
			return true
	return false


static func _comparable_segment(segment: String) -> String:
	var name := segment
	var stream := name.find(":")
	if stream >= 0:
		name = name.substr(0, stream)
	return name.to_lower().rstrip(". ")


static func extension_allowed(lower_resource_path: String, allowed_extensions: Array) -> bool:
	for extension in allowed_extensions:
		if lower_resource_path.ends_with(str(extension).to_lower()):
			return true
	return false


static func error_payload(code: String, message: String) -> Dictionary:
	return {
		"code": code,
		"message": message,
	}
