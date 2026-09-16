extends SceneTree

const BridgeContext := preload("res://addons/godot_codex_bridge/core/bridge_context.gd")
const EditorDiagnostics := preload("res://addons/godot_codex_bridge/core/editor_diagnostics.gd")

var _failures := 0
var _cleared_at := ""
var _bridge_dir_abs := ""
var _notes_abs := ""
var _ctx: BridgeContext


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge editor diagnostics tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge editor diagnostics tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	_bridge_dir_abs = ProjectSettings.globalize_path("user://editor_diagnostics_test_bridge")
	_notes_abs = ProjectSettings.globalize_path("user://editor_diagnostics_test_notes.json")
	DirAccess.make_dir_recursive_absolute(_bridge_dir_abs.path_join("artifacts"))
	if FileAccess.file_exists(_notes_abs):
		DirAccess.remove_absolute(_notes_abs)

	_ctx = BridgeContext.new()
	_ctx.permissions = {
		"allow_editor_diagnostics": true,
		"allow_clear_diagnostics": true,
		"allow_bridge_notes": true,
	}
	_ctx.bridge_dir_abs = _bridge_dir_abs
	_ctx.bridge_log = [
		{"at": "t0", "type": "first", "data": {"value": 1}},
		{"at": "t1", "type": "second", "data": {"value": 2}},
	]
	_ctx.write_json_file = Callable(self, "_write_json")
	_ctx.iso_now = Callable(self, "_timestamp")
	_ctx.file_timestamp = Callable(self, "_file_timestamp")
	_ctx.diagnostics_cleared_changed = Callable(self, "_set_cleared_at")
	_ctx.log_event = Callable(self, "_log_event")

	var diagnostics := EditorDiagnostics.new(_ctx, _notes_abs)

	var limited := diagnostics.get_diagnostics({"limit": 1})
	_assert_true(bool(limited.get("ok", false)), "diagnostics get succeeds")
	var limited_data: Dictionary = limited.get("data", {})
	_assert_eq(((limited_data.get("diagnostics", []) as Array)[0] as Dictionary).get("message"), "second", "diagnostics limit returns latest entry")

	var append := diagnostics.notes_append({"text": "remember this", "author": "test"})
	_assert_true(bool(append.get("ok", false)), "notes append succeeds")
	_assert_eq(((append.get("data", {}) as Dictionary).get("notes_count")), 1, "notes count after append")

	var notes := diagnostics.notes_get({})
	_assert_true(bool(notes.get("ok", false)), "notes get succeeds")
	_assert_eq(((notes.get("data", {}) as Dictionary).get("notes", []) as Array).size(), 1, "notes get returns one note")

	var cleared_notes := diagnostics.notes_clear({})
	_assert_true(bool(cleared_notes.get("ok", false)), "notes clear succeeds")
	_assert_eq(((cleared_notes.get("data", {}) as Dictionary).get("cleared_count")), 1, "notes clear reports previous count")
	_assert_true(FileAccess.file_exists(_bridge_dir_abs.path_join("artifacts").path_join("notes_before_clear_20260622T000000.json")), "notes clear writes evidence")

	var cleared := diagnostics.clear_diagnostics({})
	_assert_true(bool(cleared.get("ok", false)), "diagnostics clear succeeds")
	_assert_eq(_ctx.bridge_log.size(), 1, "diagnostics clear leaves clear event only")
	_assert_eq(_ctx.diagnostics_cleared_at, "2026-06-22T00:00:00Z", "context clear timestamp updated")
	_assert_eq(_cleared_at, "2026-06-22T00:00:00Z", "plugin callback clear timestamp updated")
	_assert_true(FileAccess.file_exists(_bridge_dir_abs.path_join("artifacts").path_join("diagnostics_before_clear_20260622T000000.json")), "diagnostics clear writes evidence")
	diagnostics = null
	_ctx = null


func _write_json(path: String, data: Dictionary) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": {"code": "write_failed", "message": path}}
	file.store_string(JSON.stringify(data))
	return {"ok": true}


func _timestamp() -> String:
	return "2026-06-22T00:00:00Z"


func _file_timestamp() -> String:
	return "20260622T000000"


func _set_cleared_at(value: String) -> void:
	_cleared_at = value


func _log_event(event_name: String, data: Dictionary) -> void:
	_ctx.bridge_log.append({"at": _timestamp(), "type": event_name, "data": data})


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures += 1
		push_error(label + " expected=" + str(expected) + " actual=" + str(actual))


func _assert_true(value: bool, label: String) -> void:
	if not value:
		_failures += 1
		push_error(label)
