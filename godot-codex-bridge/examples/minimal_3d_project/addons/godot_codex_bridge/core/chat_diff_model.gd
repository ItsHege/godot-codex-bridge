@tool
extends RefCounted

const DEFAULT_MAX_FILES := 24
const DEFAULT_MAX_LINES_PER_FILE := 360


static func diff_text_from_event_params(params: Dictionary) -> String:
	var diff_payload: Variant = params.get("diff_text", params.get("diff", ""))
	if typeof(diff_payload) == TYPE_STRING:
		var direct := str(diff_payload)
		if direct.strip_edges() != "":
			return direct
	if params.has("file_changes") and params.get("file_changes") != null:
		var from_file_changes := diff_from_file_changes(params.get("file_changes"))
		if from_file_changes.strip_edges() != "":
			return from_file_changes
	if typeof(diff_payload) == TYPE_DICTIONARY:
		var from_dictionary := diff_from_file_changes(diff_payload)
		if from_dictionary.strip_edges() != "":
			return from_dictionary
	return ""


static func parse_diff_files(diff_text: String, max_files := DEFAULT_MAX_FILES, max_lines_per_file := DEFAULT_MAX_LINES_PER_FILE) -> Array[Dictionary]:
	var files: Array[Dictionary] = []
	var current: Dictionary = {}
	for raw_line in diff_text.split("\n"):
		var line := str(raw_line)
		if line.ends_with("\r"):
			line = line.substr(0, line.length() - 1)
		if line.begins_with("diff --git "):
			if not current.is_empty():
				files.append(current)
				if files.size() >= max_files:
					return files
			current = _new_diff_file(_diff_path_from_git_header(line))
			_append_diff_line(current, line, max_lines_per_file)
			continue
		if current.is_empty():
			if line.strip_edges() == "":
				continue
			current = _new_diff_file("unified diff")
		if line.begins_with("+++ ") or line.begins_with("--- "):
			var header_path := normalize_diff_file_path(line.substr(4).strip_edges())
			if header_path != "" and str(current.get("path", "")) in ["", "unknown file", "unified diff"]:
				current["path"] = header_path
		_append_diff_line(current, line, max_lines_per_file)
	if not current.is_empty() and files.size() < max_files:
		files.append(current)
	return files


static func diff_from_file_changes(file_changes: Variant) -> String:
	if typeof(file_changes) != TYPE_DICTIONARY:
		return ""
	var parts := PackedStringArray()
	var changes := file_changes as Dictionary
	for key in changes.keys():
		var path := str(key)
		var change: Variant = changes.get(key)
		var unified_diff := ""
		if typeof(change) == TYPE_DICTIONARY:
			unified_diff = str((change as Dictionary).get("unified_diff", ""))
		else:
			unified_diff = str(change)
		if unified_diff.strip_edges() == "":
			continue
		parts.append("diff --git a/" + path + " b/" + path)
		parts.append("--- a/" + path)
		parts.append("+++ b/" + path)
		parts.append(unified_diff.strip_edges(false, true))
	if parts.is_empty():
		return ""
	return "\n".join(parts)


static func many_file_overflow_fixture(file_count := 32, lines_per_file := 8) -> String:
	var bounded_file_count := clampi(file_count, 1, 64)
	var bounded_lines_per_file := clampi(lines_per_file, 1, 64)
	var parts := PackedStringArray()
	for file_index in range(bounded_file_count):
		var index_text := str(file_index)
		while index_text.length() < 2:
			index_text = "0" + index_text
		var path := "res://diff_overflow/file_" + index_text + ".gd"
		parts.append("diff --git a/" + path + " b/" + path)
		parts.append("--- a/" + path)
		parts.append("+++ b/" + path)
		parts.append("@@")
		for line_index in range(bounded_lines_per_file):
			parts.append("-old_value_" + str(file_index) + "_" + str(line_index))
			parts.append("+new_value_" + str(file_index) + "_" + str(line_index))
	return "\n".join(parts)


static func file_changes_summary(file_changes: Variant, max_paths := 12) -> String:
	if typeof(file_changes) != TYPE_DICTIONARY:
		return "File changes: unavailable"
	var changes := file_changes as Dictionary
	var changed_paths := PackedStringArray()
	var added := 0
	var removed := 0
	for key in changes.keys():
		var path := str(key)
		changed_paths.append(path)
		var change: Variant = changes.get(key)
		if typeof(change) != TYPE_DICTIONARY:
			continue
		var unified_diff := str((change as Dictionary).get("unified_diff", ""))
		for raw_line in unified_diff.split("\n"):
			var line := str(raw_line)
			if line.begins_with("+") and not line.begins_with("+++"):
				added += 1
			elif line.begins_with("-") and not line.begins_with("---"):
				removed += 1
	var lines: Array[String] = []
	lines.append("File changes: " + str(changed_paths.size()) + " file(s), +" + str(added) + " -" + str(removed))
	lines.append("Review the Diff preview card above before approving.")
	for path in changed_paths.slice(0, max_paths):
		lines.append("- " + path)
	if changed_paths.size() > max_paths:
		lines.append("- ... " + str(changed_paths.size() - max_paths) + " more")
	return "\n".join(lines)


static func batch_summary(update_count: int, parsed_files: Array, file_limit := 8) -> String:
	var file_count := parsed_files.size()
	var added := 0
	var removed := 0
	var paths := PackedStringArray()
	for item in parsed_files:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var file_data := item as Dictionary
		added += int(file_data.get("added", 0))
		removed += int(file_data.get("removed", 0))
		var path := str(file_data.get("path", "")).strip_edges()
		if path != "" and path != "unknown file":
			paths.append(path)
	var lines: Array[String] = []
	lines.append("Diff preview batch: " + str(max(update_count, 1)) + " update(s), " + str(file_count) + " file(s), +" + str(added) + " -" + str(removed))
	if paths.is_empty():
		lines.append("Show files to inspect the colored red/green diff.")
	else:
		var visible_paths := paths.slice(0, file_limit)
		lines.append("Files: " + ", ".join(visible_paths))
		if paths.size() > file_limit:
			lines.append("+" + str(paths.size() - file_limit) + " more file(s).")
		lines.append("Show files, then expand a file row to inspect the colored red/green diff.")
	return "\n".join(lines)


static func batch_toggle_text(files_visible: bool, file_count: int) -> String:
	if files_visible:
		return "Hide files"
	return "Show files" if file_count <= 0 else "Show " + str(file_count) + " file" + ("" if file_count == 1 else "s")


static func extract_diff_files(diff_text: String) -> PackedStringArray:
	var files := PackedStringArray()
	for raw_line in diff_text.split("\n"):
		var line := str(raw_line).strip_edges()
		var candidate := ""
		if line.begins_with("diff --git "):
			var parts := line.split(" ")
			if parts.size() >= 4:
				candidate = str(parts[3])
		elif line.begins_with("+++ "):
			candidate = line.substr(4).strip_edges()
		elif line.begins_with("--- "):
			candidate = line.substr(4).strip_edges()
		candidate = normalize_diff_file_path(candidate)
		if candidate != "" and not files.has(candidate):
			files.append(candidate)
	return files


static func normalize_diff_file_path(path_text: String) -> String:
	var value := path_text.strip_edges()
	if value == "" or value == "/dev/null":
		return ""
	if value.begins_with("\"") and value.ends_with("\"") and value.length() >= 2:
		value = value.substr(1, value.length() - 2)
	if value.begins_with("a/") or value.begins_with("b/"):
		value = value.substr(2)
	return value


static func diff_line_kind(line: String) -> String:
	if line.begins_with("+") and not line.begins_with("+++"):
		return "added"
	if line.begins_with("-") and not line.begins_with("---"):
		return "removed"
	if line.begins_with("@@"):
		return "hunk"
	if line.begins_with("diff --git ") or line.begins_with("+++") or line.begins_with("---"):
		return "file_header"
	return "context"


static func _new_diff_file(path_text: String) -> Dictionary:
	var path := path_text.strip_edges()
	if path == "":
		path = "unknown file"
	return {
		"path": path,
		"lines": PackedStringArray(),
		"added": 0,
		"removed": 0,
		"truncated": false,
	}


static func _diff_path_from_git_header(line: String) -> String:
	var parts := line.split(" ")
	if parts.size() >= 4:
		return normalize_diff_file_path(str(parts[3]))
	if parts.size() >= 3:
		return normalize_diff_file_path(str(parts[2]))
	return ""


static func _append_diff_line(file_data: Dictionary, line: String, max_lines_per_file: int) -> void:
	var kind := diff_line_kind(line)
	if kind == "added":
		file_data["added"] = int(file_data.get("added", 0)) + 1
	elif kind == "removed":
		file_data["removed"] = int(file_data.get("removed", 0)) + 1
	var lines: PackedStringArray = file_data.get("lines", PackedStringArray())
	if lines.size() < max_lines_per_file:
		lines.append(line)
	else:
		file_data["truncated"] = true
	file_data["lines"] = lines
