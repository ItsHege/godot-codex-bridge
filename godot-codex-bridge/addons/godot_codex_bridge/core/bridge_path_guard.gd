@tool
extends RefCounted


static func validate_project_path(project_root_abs: String, target_abs: String, allow_missing_tail := false) -> Dictionary:
	var root := _normalize(project_root_abs).trim_suffix("/")
	var target := _normalize(target_abs)
	var compare_root := root.to_lower() if OS.get_name() == "Windows" else root
	var compare_target := target.to_lower() if OS.get_name() == "Windows" else target
	if target == "" or (compare_target != compare_root and not compare_target.begins_with(compare_root + "/")):
		return _error("path_outside_project", "Path is outside the Godot project: " + target_abs)
	var root_check := _root_components_check(root)
	if not bool(root_check.get("ok", false)):
		return root_check
	var relative := target.substr(root.length()).trim_prefix("/")
	var current := root
	for part in relative.split("/", false):
		var parent := current
		current = parent.path_join(part)
		var parent_access := DirAccess.open(parent)
		if parent_access == null:
			if allow_missing_tail:
				return {"ok": true, "missing": true}
			return _error("path_parent_unavailable", "Cannot inspect path parent: " + parent)
		if parent_access.is_link(part):
			return _error("reparse_path_rejected", "Symbolic-link and junction path components are not allowed: " + current)
		if not DirAccess.dir_exists_absolute(current) and not FileAccess.file_exists(current):
			if allow_missing_tail:
				return {"ok": true, "missing": true}
			return _error("path_unavailable", "Path does not exist: " + current)
	return {"ok": true, "missing": false}


static func ensure_project_directory(project_root_abs: String, directory_abs: String) -> Dictionary:
	var initial := validate_project_path(project_root_abs, directory_abs, true)
	if not bool(initial.get("ok", false)):
		return initial
	var root := _normalize(project_root_abs).trim_suffix("/")
	var target := _normalize(directory_abs)
	var relative := target.substr(root.length()).trim_prefix("/")
	var current := root
	for part in relative.split("/", false):
		var next := current.path_join(part)
		var checked := validate_project_path(root, next, true)
		if not bool(checked.get("ok", false)):
			return checked
		if not DirAccess.dir_exists_absolute(next):
			var err := DirAccess.make_dir_absolute(next)
			if err != OK and err != ERR_ALREADY_EXISTS:
				return _error("directory_create_failed", "Failed to create Bridge directory: " + next + " (" + error_string(err) + ")")
		checked = validate_project_path(root, next, false)
		if not bool(checked.get("ok", false)):
			return checked
		if not DirAccess.dir_exists_absolute(next):
			return _error("path_not_directory", "Expected a Bridge directory: " + next)
		current = next
	return {"ok": true, "path": target}


static func _component_check(path_value: String) -> Dictionary:
	var parent := path_value.get_base_dir()
	var name := path_value.get_file()
	var access := DirAccess.open(parent)
	if access == null:
		return _error("project_root_unavailable", "Cannot inspect project root: " + path_value)
	if access.is_link(name):
		return _error("reparse_root_rejected", "The project root cannot be a symbolic link or junction: " + path_value)
	if not DirAccess.dir_exists_absolute(path_value):
		return _error("project_root_unavailable", "Project root is unavailable: " + path_value)
	return {"ok": true}


static func _root_components_check(path_value: String) -> Dictionary:
	var components: Array[String] = []
	var current := path_value.trim_suffix("/")
	while current != "":
		if current == "/" or current.ends_with(":"):
			break
		var name := current.get_file()
		var parent := current.get_base_dir().trim_suffix("/")
		if name == "" or parent == current:
			break
		components.push_front(current)
		current = parent
	for component in components:
		var result := _component_check(component)
		if not bool(result.get("ok", false)):
			return result
	return {"ok": true}


static func _normalize(path_value: String) -> String:
	return path_value.replace("\\", "/").simplify_path()


static func _error(code: String, message: String) -> Dictionary:
	return {"ok": false, "error": {"code": code, "message": message}}
