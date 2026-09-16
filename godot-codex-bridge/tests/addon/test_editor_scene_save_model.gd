extends SceneTree

const BridgeContext := preload("res://addons/godot_codex_bridge/core/bridge_context.gd")
const EditorSceneSave := preload("res://addons/godot_codex_bridge/core/editor_scene_save.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge editor scene save tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge editor scene save tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var root := Node3D.new()
	root.name = "Root"
	root.scene_file_path = "res://scenes/root.tscn"
	var payload := EditorSceneSave.current_scene_payload(root)
	_assert_eq(payload.get("path"), "res://scenes/root.tscn", "current scene path")
	_assert_eq(payload.get("name"), "Root", "current scene name")
	_assert_eq(payload.get("type"), "Node3D", "current scene type")
	root.free()

	var empty := EditorSceneSave.current_scene_payload(null)
	_assert_eq(empty.get("path"), "", "null scene path")

	var open_scenes := PackedStringArray(["res://a.tscn", "res://b.tscn"])
	var open_payload := EditorSceneSave.open_scene_paths_payload(open_scenes)
	_assert_eq(open_payload.size(), 2, "open scene count")
	_assert_eq(open_payload[1], "res://b.tscn", "open scene path")

	var current_scene := {
		"path": "res://scenes/root.tscn",
		"name": "Root",
		"type": "Node3D",
	}
	var snapshot := {"generated_at": "2026-06-23T12:00:00Z"}
	var save_state := EditorSceneSave.save_state_payload(
		"current_scene",
		"res://scenes/root.tscn",
		open_payload,
		current_scene,
		OK,
		"OK",
		snapshot,
		true
	)
	_assert_eq(save_state.get("status"), "saved_to_disk", "save state status")
	_assert_eq(save_state.get("target_scene"), "res://scenes/root.tscn", "save state target scene")
	_assert_eq(save_state.get("generated_at"), "2026-06-23T12:00:00Z", "save state generated_at")
	_assert_true(bool(save_state.get("snapshot_refreshed", false)), "save state snapshot refreshed")
	var dirty_state := save_state.get("dirty_state", {}) as Dictionary
	_assert_eq(dirty_state.get("after"), "saved_scope_persisted", "save state dirty after")
	_assert_eq(dirty_state.get("source"), "EditorInterface.save_scene", "save state dirty source")
	_assert_true(str(save_state.get("agent_guidance", "")).contains("no manual Ctrl+S"), "save state guidance mentions Ctrl+S")

	var save_all_state := EditorSceneSave.save_all_state_payload(open_payload, open_payload, current_scene, snapshot)
	_assert_eq(save_all_state.get("status"), "save_all_requested", "save all state status")
	var save_all_dirty_state := save_all_state.get("dirty_state", {}) as Dictionary
	_assert_eq(save_all_dirty_state.get("source"), "EditorInterface.save_all_scenes", "save all dirty source")
	_assert_true(str(save_all_state.get("agent_guidance", "")).contains("Save-all was requested"), "save all guidance")

	var ctx := BridgeContext.new()
	ctx.permissions = {"allow_scene_save": false}
	var saver := EditorSceneSave.new(ctx)
	var denied_current := saver.save_scene({})
	_assert_false(bool(denied_current.get("ok", true)), "save scene denied when permission disabled")
	_assert_eq(((denied_current.get("error", {}) as Dictionary).get("code")), "permission_denied", "save scene permission error code")
	var denied_all := saver.save_all_scenes({})
	_assert_false(bool(denied_all.get("ok", true)), "save all scenes denied when permission disabled")
	_assert_eq(((denied_all.get("error", {}) as Dictionary).get("code")), "permission_denied", "save all permission error code")


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures += 1
		push_error(label + " expected=" + str(expected) + " actual=" + str(actual))


func _assert_false(value: bool, label: String) -> void:
	if value:
		_failures += 1
		push_error(label)


func _assert_true(value: bool, label: String) -> void:
	if not value:
		_failures += 1
		push_error(label)
