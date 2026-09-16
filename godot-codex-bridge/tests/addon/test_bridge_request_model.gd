extends SceneTree

const BridgeRequestModel := preload("res://addons/godot_codex_bridge/core/bridge_request_model.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge request model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge request model tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var explicit := BridgeRequestModel.request_identity("fallback-1", {
		"request_id": "request-1",
		"id": "legacy-1",
		"type": "refresh_context",
	})
	_assert_eq(explicit.get("request_id"), "request-1", "request_id wins over id")
	_assert_eq(explicit.get("request_type"), "refresh_context", "type preserved")

	var legacy := BridgeRequestModel.request_identity("fallback-2", {
		"id": "legacy-2",
		"type": "open_scene",
	})
	_assert_eq(legacy.get("request_id"), "legacy-2", "legacy id fallback")
	_assert_eq(legacy.get("request_type"), "open_scene", "legacy type preserved")

	var missing := BridgeRequestModel.request_identity("fallback-3", {})
	_assert_eq(missing.get("request_id"), "fallback-3", "missing id uses fallback")
	_assert_eq(missing.get("request_type"), "", "missing type uses empty string")

	var empty := BridgeRequestModel.request_identity("fallback-4", {
		"request_id": "",
		"id": "legacy-4",
		"type": "run_current_scene",
	})
	_assert_eq(empty.get("request_id"), "fallback-4", "empty request_id uses fallback")
	_assert_eq(empty.get("request_type"), "run_current_scene", "empty id keeps type")

	var payload := BridgeRequestModel.request_payload({
		"payload": {"scenePath": "res://scenes/main.tscn"},
	})
	_assert_eq(payload.get("scenePath"), "res://scenes/main.tscn", "dictionary payload preserved")
	_assert_true(BridgeRequestModel.request_payload({}).is_empty(), "missing payload becomes empty dictionary")
	_assert_true(BridgeRequestModel.request_payload({"payload": "bad"}).is_empty(), "non-dictionary payload becomes empty dictionary")

	var success_parts := BridgeRequestModel.result_response_parts({
		"ok": true,
		"data": {"value": 7},
		"error": {"code": "ignored"},
	})
	_assert_eq(success_parts.get("status"), "completed", "success result status")
	_assert_eq((success_parts.get("data", {}) as Dictionary).get("value"), 7, "success result data")
	_assert_true((success_parts.get("error", {}) as Dictionary).is_empty(), "success error empty")

	var failure_parts := BridgeRequestModel.result_response_parts({
		"ok": false,
		"data": {"ignored": true},
		"error": {"code": "bad_request"},
	})
	_assert_eq(failure_parts.get("status"), "error", "failure result status")
	_assert_true((failure_parts.get("data", {}) as Dictionary).is_empty(), "failure data empty")
	_assert_eq((failure_parts.get("error", {}) as Dictionary).get("code"), "bad_request", "failure error")


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures += 1
		push_error(label + " expected=" + str(expected) + " actual=" + str(actual))


func _assert_true(value: bool, label: String) -> void:
	if not value:
		_failures += 1
		push_error(label + " expected=true actual=false")
