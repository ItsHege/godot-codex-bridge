extends SceneTree

var failures := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await create_timer(2.0).timeout
	var plugin := _find_plugin(get_root())
	_check(plugin != null, "Bridge plugin loaded")
	if plugin == null:
		quit(1)
		return
	var hex := Crypto.new().generate_random_bytes(16).hex_encode()
	var request_id := hex.substr(0, 8) + "-" + hex.substr(8, 4) + "-" + hex.substr(12, 4) + "-" + hex.substr(16, 4) + "-" + hex.substr(20, 12)
	var note_text := "replay-fixture-" + request_id
	var requests_dir := str(plugin.get("_requests_dir_abs"))
	var responses_dir := str(plugin.get("_responses_dir_abs"))
	var request_path := requests_dir.path_join(request_id + ".json")
	var response_path := responses_dir.path_join(request_id + ".json")
	_check(DirAccess.make_dir_absolute(response_path) == OK, "response path blocked as a directory")
	var now := int(Time.get_unix_time_from_system())
	var request := {
		"protocol_version": "godot-codex-bridge/0.1",
		"request_id": request_id,
		"type": "editor_control",
		"created_at": Time.get_datetime_string_from_unix_time(now),
		"deadline_at": Time.get_datetime_string_from_unix_time(now + 60),
		"payload": {"action": "notes_append", "params": {"text": note_text, "author": "fixture"}},
	}
	var staging := request_path + ".tmp"
	var file := FileAccess.open(staging, FileAccess.WRITE)
	_check(file != null, "request staging file opened")
	if file == null:
		quit(1)
		return
	file.store_string(JSON.stringify(request))
	file.flush()
	file.close()
	_check(DirAccess.rename_absolute(staging, request_path) == OK, "request published")
	plugin.call("_poll_requests")
	_check(_count_notes(plugin, note_text) == 1, "action ran once after response write failed")
	_check(DirAccess.remove_absolute(response_path) == OK, "response blocker removed")
	plugin.call("_poll_requests")
	_check(FileAccess.file_exists(response_path), "stored result published on retry")
	_check(_count_notes(plugin, note_text) == 1, "retry did not repeat action")
	var response := JSON.parse_string(FileAccess.get_file_as_string(response_path)) as Dictionary
	_check(response != null and str(response.get("request_id", "")) == request_id and str(response.get("status", "")) == "succeeded", "response identity and status")
	print("RESPONSE_REPLAY_RESULT=", JSON.stringify({"request_id": request_id, "note_occurrences": _count_notes(plugin, note_text), "response_status": response.get("status", "") if response != null else "invalid"}))
	quit(0 if failures == 0 else 1)


func _count_notes(plugin: Node, text: String) -> int:
	var diagnostics := plugin.get("_editor_diagnostics") as Object
	var result := diagnostics.notes_get({}) as Dictionary
	var data := result.get("data", {}) as Dictionary
	var count := 0
	for note in data.get("notes", []) as Array:
		if typeof(note) == TYPE_DICTIONARY and str((note as Dictionary).get("text", "")) == text:
			count += 1
	return count


func _find_plugin(node: Node) -> Node:
	var script := node.get_script() as Script
	if script != null and "godot_codex_bridge/plugin.gd" in script.resource_path:
		return node
	for child in node.get_children():
		var found := _find_plugin(child)
		if found != null:
			return found
	return null


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
