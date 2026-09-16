extends SceneTree

const BridgeContext := preload("res://addons/godot_codex_bridge/core/bridge_context.gd")
const EditorUndo := preload("res://addons/godot_codex_bridge/core/editor_undo.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge editor undo tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge editor undo tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	_assert_true(EditorUndo.is_bridge_action_name("Godot Codex Bridge: set node transform"), "bridge action prefix accepted")
	_assert_false(EditorUndo.is_bridge_action_name("Move Node"), "manual editor action rejected")
	_assert_false(EditorUndo.is_bridge_action_name("Godot Bridge: old action"), "old non-canonical prefix rejected")

	var payload := EditorUndo.undo_state_payload(
		"Godot Codex Bridge: set node transform",
		7,
		3,
		4,
		{
			"generated_at": "2026-06-24T00:00:00Z",
			"current_scene": {"path": "res://scenes/main.tscn"},
		}
	)
	_assert_eq(payload.get("status"), "undone", "payload status")
	_assert_true(bool(payload.get("undone", false)), "payload undone")
	_assert_false(bool(payload.get("auto_saved", true)), "payload does not auto-save")
	_assert_eq(payload.get("history_id"), 7, "payload history id")
	_assert_eq(payload.get("version_before"), 3, "payload version before")
	_assert_eq(payload.get("version_after"), 4, "payload version after")
	_assert_eq((payload.get("current_scene", {}) as Dictionary).get("path"), "res://scenes/main.tscn", "payload current scene")

	var context := BridgeContext.new()
	context.permissions = {"allow_scene_edits": false}
	var undo := EditorUndo.new(context)
	var denied := undo.undo_last_bridge_action({})
	_assert_false(bool(denied.get("ok", true)), "permission denied result is not ok")
	_assert_eq((denied.get("error", {}) as Dictionary).get("code"), "permission_denied", "permission denied code")


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures += 1
		push_error(label + " expected=" + str(expected) + " actual=" + str(actual))


func _assert_true(value: bool, label: String) -> void:
	if not value:
		_failures += 1
		push_error(label)


func _assert_false(value: bool, label: String) -> void:
	if value:
		_failures += 1
		push_error(label)
