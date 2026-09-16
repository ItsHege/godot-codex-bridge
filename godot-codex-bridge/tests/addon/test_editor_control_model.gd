extends SceneTree

const BridgeContext := preload("res://addons/godot_codex_bridge/core/bridge_context.gd")
const EditorControl := preload("res://addons/godot_codex_bridge/core/editor_control.gd")

var _failures := 0
var _recorded_actions: Array = []
var _executed_actions: Array = []


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge editor control tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge editor control tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var ctx := BridgeContext.new()
	ctx.refresh_snapshot = Callable(self, "_fake_refresh")
	ctx.record_editor_action = Callable(self, "_fake_record_action")
	ctx.error_payload = Callable(self, "_legacy_error_payload")

	var controller := EditorControl.new(ctx, Callable(self, "_fake_execute"), 3, "ctx.json")

	var missing_action := controller.handle_request("r0", {"params": {}})
	_assert_false(bool(missing_action.get("ok", true)), "missing action fails")
	_assert_eq((missing_action.get("error", {}) as Dictionary).get("code"), "invalid_request", "missing action error code")

	var bad_params := controller.handle_request("r1", {"action": "ping", "params": []})
	_assert_false(bool(bad_params.get("ok", true)), "non-object params fail")
	_assert_eq((bad_params.get("error", {}) as Dictionary).get("code"), "invalid_request", "bad params error code")

	var ok := controller.handle_request("r2", {"action": "ping", "params": {"value": 7}})
	_assert_true(bool(ok.get("ok", false)), "valid action succeeds")
	var ok_data: Dictionary = ok.get("data", {})
	_assert_eq(ok_data.get("action"), "ping", "action is attached to data")
	_assert_eq(ok_data.get("request_id"), "r2", "request id is attached to data")
	_assert_eq(ok_data.get("snapshot_refreshed"), false, "snapshot defaults false")
	_assert_eq(_recorded_actions[0].get("status"), "succeeded", "success action recorded")

	var failed := controller.handle_request("r3", {"action": "fail", "params": {}})
	_assert_false(bool(failed.get("ok", true)), "failed action returns error")
	_assert_eq(_recorded_actions[1].get("status"), "failed", "failed action recorded")

	var batch := controller.handle_request("r4", {
		"action": "editor_batch",
		"params": {
			"actions": [
				{"action": "ping", "params": {"value": 1}},
				{"action": "fail", "params": {}},
				{"action": "ping", "params": {"value": 2}},
			],
			"stop_on_error": false,
		},
	})
	_assert_true(bool(batch.get("ok", false)), "batch returns ok wrapper")
	var batch_data: Dictionary = batch.get("data", {})
	_assert_eq(batch_data.get("status"), "partial", "batch reports partial")
	_assert_eq((batch_data.get("results", []) as Array).size(), 3, "batch keeps all results when stop_on_error false")
	_assert_true(bool(batch_data.get("snapshot_refreshed", false)), "batch refreshes snapshot")
	_assert_eq(((batch_data.get("final_snapshot", {}) as Dictionary).get("context_snapshot_path")), "ctx.json", "batch uses context snapshot path")

	var nested := controller.handle_request("r5", {
		"action": "editor_batch",
		"params": {"actions": [{"action": "editor_batch"}]},
	})
	_assert_true(bool(nested.get("ok", false)), "nested batch is a structured partial result")
	var nested_result := (((nested.get("data", {}) as Dictionary).get("results", []) as Array)[0] as Dictionary)
	_assert_eq(nested_result.get("status"), "failed", "nested batch result failed")
	_assert_eq(((nested_result.get("error", {}) as Dictionary).get("code")), "nested_batch_rejected", "nested batch error code")


func _fake_execute(action: String, params: Dictionary) -> Dictionary:
	_executed_actions.append({"action": action, "params": params})
	if action == "fail":
		return {"ok": false, "error": {"code": "forced_failure", "message": "Forced failure"}}
	return {"ok": true, "data": {"echo": params.get("value", null)}}


func _fake_refresh(reason: String) -> Dictionary:
	return {
		"generated_at": "2026-06-22T00:00:00Z",
		"current_scene": {"path": "res://Main.tscn"},
		"reason": reason,
	}


func _fake_record_action(action: String, status: String, data: Dictionary) -> void:
	_recorded_actions.append({"action": action, "status": status, "data": data})


func _legacy_error_payload(code: String, message: String) -> Dictionary:
	return {"code": code, "message": message}


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
