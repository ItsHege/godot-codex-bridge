extends SceneTree

const BridgeContext := preload("res://addons/godot_codex_bridge/core/bridge_context.gd")
const PlaytestInputModel := preload("res://addons/godot_codex_bridge/core/playtest_input_model.gd")

var _failures := 0
var _written_path := ""
var _written_document := {}


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge playtest input model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge playtest input model tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var context := BridgeContext.new()
	context.permissions = {"allow_playtest_input": false}
	context.ensure_bridge_dirs = Callable(self, "_ensure_dirs")
	context.write_json_file = Callable(self, "_write_json_file")
	var model := PlaytestInputModel.new(
		context,
		"user://playtest_input_model/input_commands.json",
		"user://playtest_input_model/playtest_session.json"
	)

	var permission_denied := model.submit_input({"type": "action_press", "action": "jump"}, {
		"is_playing": true,
		"bridge_owned": true,
	})
	_assert_false(bool(permission_denied.get("ok", true)), "permission off rejects")
	_assert_eq((permission_denied.get("error", {}) as Dictionary).get("code"), "permission_denied", "permission error code")

	context.permissions["allow_playtest_input"] = true
	var session := model.start_bridge_session("res://scenes/playtest_input_fixture.tscn")
	_assert_true(bool(session.get("ok", false)), "session starts")
	var session_data := session.get("data", {}) as Dictionary
	_assert_eq(session_data.get("active"), true, "session active")
	_assert_true(str(session_data.get("session_token", "")).length() > 10, "session token generated")
	_assert_eq(_written_path, "user://playtest_input_model/playtest_session.json", "session write path")

	var not_running := model.submit_input({"type": "action_press", "action": "jump"}, {
		"is_playing": false,
		"bridge_owned": true,
	})
	_assert_false(bool(not_running.get("ok", true)), "not running rejects")
	_assert_eq((not_running.get("error", {}) as Dictionary).get("code"), "play_session_not_running", "not running code")

	var not_owned := model.submit_input({"type": "action_press", "action": "jump"}, {
		"is_playing": true,
		"bridge_owned": false,
	})
	_assert_false(bool(not_owned.get("ok", true)), "not bridge-owned rejects")
	_assert_eq((not_owned.get("error", {}) as Dictionary).get("code"), "play_session_not_bridge_owned", "not owned code")

	var valid := model.submit_input({
		"command_id": "cmd.valid-1",
		"type": "action_press",
		"action": "gcb_playtest_jump",
		"strength": 0.75,
	}, {
		"is_playing": true,
		"bridge_owned": true,
		"playing_scene": "res://scenes/playtest_input_fixture.tscn",
	})
	_assert_true(bool(valid.get("ok", false)), "valid input accepted")
	var valid_data := valid.get("data", {}) as Dictionary
	_assert_eq(valid_data.get("command_id"), "cmd.valid-1", "command id preserved")
	_assert_eq(valid_data.get("runtime_delivery"), "runtime_state_probe_file_command", "delivery path")
	_assert_eq((valid_data.get("held_actions_after", []) as Array), ["gcb_playtest_jump"], "local held action tracked")
	_assert_eq(_written_path, "user://playtest_input_model/input_commands.json", "write path")
	_assert_eq(_written_document.get("playtest_input_version"), PlaytestInputModel.COMMAND_VERSION, "written version")
	_assert_eq(_written_document.get("session_token"), session_data.get("session_token"), "written session token")
	_assert_eq((_written_document.get("steps", []) as Array).size(), 1, "written one step")

	var release_result := model.release_all_held("test_cleanup")
	_assert_true(bool(release_result.get("ok", false)), "release all succeeds")
	var release_data := release_result.get("data", {}) as Dictionary
	_assert_eq(release_data.get("auto_released_actions"), ["gcb_playtest_jump"], "auto released action")
	_assert_eq(release_data.get("held_actions_after"), [], "held actions cleared")
	var clear_session := model.clear_bridge_session("test_cleanup")
	_assert_true(bool(clear_session.get("ok", false)), "clear session succeeds")
	_assert_eq(_written_path, "user://playtest_input_model/playtest_session.json", "clear session write path")
	_assert_eq(_written_document.get("active"), false, "session inactive after clear")

	var too_many_steps := []
	for _index in range(PlaytestInputModel.DEFAULT_MAX_STEPS + 1):
		too_many_steps.append({"type": "action_press", "action": "gcb_playtest_jump"})
	var too_many := PlaytestInputModel.build_command_document({"steps": too_many_steps})
	_assert_false(bool(too_many.get("ok", true)), "too many steps rejects")
	_assert_eq((too_many.get("error", {}) as Dictionary).get("code"), "too_many_playtest_input_steps", "too many error code")

	_runtime_roundtrip()


func _runtime_roundtrip() -> void:
	var action := "gcb_playtest_runtime_action"
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	Input.action_release(action)

	var press_doc := (PlaytestInputModel.build_command_document({
		"command_id": "runtime.press",
		"session_token": "runtime-token-1",
		"steps": [{"type": "action_press", "action": action, "strength": 1.0}],
	}).get("data", {}) as Dictionary)
	var processed := {}
	var held := {}
	var mismatch := PlaytestInputModel.execute_runtime_document(press_doc, processed, held, {
		"require_session_token": true,
		"session_token": "other-token",
	})
	_assert_eq(mismatch.get("status"), "failed", "runtime token mismatch status")
	_assert_eq((mismatch.get("error", {}) as Dictionary).get("code"), "playtest_session_mismatch", "runtime token mismatch code")

	processed = {}
	var press_result := PlaytestInputModel.execute_runtime_document(press_doc, processed, held, {
		"require_session_token": true,
		"session_token": "runtime-token-1",
	})
	_assert_eq(press_result.get("status"), "applied", "runtime press status")
	_assert_true(Input.is_action_pressed(action), "runtime action pressed")
	_assert_true(bool((press_result.get("held_actions", {}) as Dictionary).get(action, false)), "runtime held action")
	var press_events := press_result.get("events", []) as Array
	_assert_eq((press_events[0] as Dictionary).get("type"), "playtest_input_applied", "press event applied")

	var duplicate_result := PlaytestInputModel.execute_runtime_document(press_doc, press_result.get("processed_command_ids", {}) as Dictionary, press_result.get("held_actions", {}) as Dictionary)
	_assert_eq(duplicate_result.get("status"), "ignored", "duplicate ignored")

	var release_doc := (PlaytestInputModel.build_command_document({
		"command_id": "runtime.release",
		"session_token": "runtime-token-1",
		"steps": [{"type": "action_release", "action": action}],
	}).get("data", {}) as Dictionary)
	var release_result := PlaytestInputModel.execute_runtime_document(release_doc, duplicate_result.get("processed_command_ids", {}) as Dictionary, duplicate_result.get("held_actions", {}) as Dictionary, {
		"require_session_token": true,
		"session_token": "runtime-token-1",
	})
	_assert_eq(release_result.get("status"), "applied", "runtime release status")
	_assert_false(Input.is_action_pressed(action), "runtime action released")
	_assert_false(bool((release_result.get("held_actions", {}) as Dictionary).get(action, false)), "runtime held action cleared")

	Input.action_release(action)
	InputMap.erase_action(action)

	var negative := "gcb_playtest_axis_left"
	var positive := "gcb_playtest_axis_right"
	for axis_action in [negative, positive]:
		if not InputMap.has_action(axis_action):
			InputMap.add_action(axis_action)
		Input.action_release(axis_action)
	var axis_doc := (PlaytestInputModel.build_command_document({
		"command_id": "runtime.axis",
		"session_token": "runtime-token-1",
		"steps": [{
			"type": "axis",
			"negative_action": negative,
			"positive_action": positive,
			"value": -0.5,
		}],
	}).get("data", {}) as Dictionary)
	var axis_result := PlaytestInputModel.execute_runtime_document(axis_doc, release_result.get("processed_command_ids", {}) as Dictionary, release_result.get("held_actions", {}) as Dictionary, {
		"require_session_token": true,
		"session_token": "runtime-token-1",
	})
	_assert_eq(axis_result.get("status"), "applied", "runtime axis status")
	_assert_true(Input.is_action_pressed(negative), "axis negative pressed")
	_assert_false(Input.is_action_pressed(positive), "axis positive released")
	Input.action_release(negative)
	Input.action_release(positive)
	InputMap.erase_action(negative)
	InputMap.erase_action(positive)


func _ensure_dirs() -> void:
	pass


func _write_json_file(path: String, data: Dictionary) -> Dictionary:
	_written_path = path
	_written_document = data.duplicate(true)
	return {"ok": true, "path": path}


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
