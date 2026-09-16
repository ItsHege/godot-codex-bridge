extends Node3D

const ACTION_JUMP := "gcb_playtest_jump"
const DIAGNOSTICS_VERSION := "godot-codex-bridge/playtest-input-fixture-diagnostics-v1"
const DIAGNOSTICS_PATH := "res://.godot/godot_codex_bridge/runtime/playtest_fixture_diagnostics.json"

@export var jump_distance := 1.0

var jump_press_count := 0
var start_position := Vector3.ZERO
var _jump_was_pressed := false

@onready var marker: MeshInstance3D = $PlaytestMarker


func _ready() -> void:
	print("Godot Codex Bridge playtest input fixture started")
	start_position = marker.position if marker != null else Vector3.ZERO
	if not InputMap.has_action(ACTION_JUMP):
		InputMap.add_action(ACTION_JUMP)
	_write_fixture_diagnostics("fixture_ready", {
		"has_runtime_probe": has_node("RuntimeProbe"),
		"action_registered": InputMap.has_action(ACTION_JUMP),
	})
	call_deferred("_write_probe_ready_state")


func _write_probe_ready_state() -> void:
	var probe_result: Dictionary = {
		"ok": false,
		"error": {
			"code": "runtime_probe_missing",
			"message": "RuntimeProbe node is missing from playtest input fixture.",
		},
	}
	if has_node("RuntimeProbe"):
		probe_result = $RuntimeProbe.write_now("fixture_ready")
		if not bool(probe_result.get("ok", true)):
			print("Godot Codex Bridge playtest input fixture probe write failed: ", probe_result)
	_write_fixture_diagnostics("probe_write_attempted", {
		"has_runtime_probe": has_node("RuntimeProbe"),
		"probe_write_ok": bool(probe_result.get("ok", false)),
		"probe_result": probe_result,
	})


func _process(_delta: float) -> void:
	var jump_pressed := Input.is_action_pressed(ACTION_JUMP)
	if jump_pressed and not _jump_was_pressed:
		jump_press_count += 1
		if marker != null:
			marker.position = start_position + Vector3(0, jump_distance * float(jump_press_count), 0)
		_write_fixture_diagnostics("input_action_pressed", {
			"action": ACTION_JUMP,
			"jump_press_count": jump_press_count,
			"marker_position": _vector3_payload(marker.position if marker != null else Vector3.ZERO),
		})
	_jump_was_pressed = jump_pressed


func _write_fixture_diagnostics(stage: String, details: Dictionary = {}) -> void:
	var path := ProjectSettings.globalize_path(DIAGNOSTICS_PATH)
	var dir_result := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if dir_result != OK:
		print("Godot Codex Bridge playtest input fixture diagnostics dir failed: ", dir_result)
		return
	var document := {
		"diagnostics_version": DIAGNOSTICS_VERSION,
		"stage": stage,
		"scene_path": scene_file_path,
		"node_path": str(get_path()) if is_inside_tree() else str(name),
		"generated_at": Time.get_datetime_string_from_system(true) + "Z",
		"jump_press_count": jump_press_count,
		"details": details,
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		print("Godot Codex Bridge playtest input fixture diagnostics write failed: ", FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(document, "\t"))
	file.store_string("\n")
	file.close()


func _vector3_payload(value: Vector3) -> Dictionary:
	return {
		"x": value.x,
		"y": value.y,
		"z": value.z,
	}
