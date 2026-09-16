extends SceneTree

const BridgeResponseModel := preload("res://addons/godot_codex_bridge/core/bridge_response_model.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge response model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge response model tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	_assert_eq(BridgeResponseModel.response_status("completed"), "succeeded", "completed maps to succeeded")
	_assert_eq(BridgeResponseModel.response_status("error"), "failed", "error maps to failed")
	_assert_eq(BridgeResponseModel.response_status("pending"), "pending", "custom status preserved")

	var success := BridgeResponseModel.response_payload(
		"godot-codex-bridge/0.1",
		"request-1",
		"refresh_context",
		"completed",
		{"scene_node_count": 3},
		{},
		"2026-06-23T00:00:00Z",
		"2026-06-23T00:00:01Z"
	)
	_assert_eq(success.get("protocol_version"), "godot-codex-bridge/0.1", "success protocol")
	_assert_eq(success.get("request_id"), "request-1", "success request id")
	_assert_eq(success.get("type"), "refresh_context", "success type")
	_assert_eq(success.get("status"), "succeeded", "success status")
	_assert_eq((success.get("data", {}) as Dictionary).get("scene_node_count"), 3, "success data")
	_assert_eq(success.get("error"), null, "success error null")

	var error_payload := BridgeResponseModel.error_payload("permission_denied", "Nope.")
	_assert_eq(error_payload.get("code"), "permission_denied", "error code")
	_assert_eq(error_payload.get("message"), "Nope.", "error message")

	var failure := BridgeResponseModel.response_payload(
		"godot-codex-bridge/0.1",
		"request-2",
		"run_current_scene",
		"error",
		{},
		error_payload,
		"2026-06-23T00:00:02Z",
		"2026-06-23T00:00:03Z"
	)
	_assert_eq(failure.get("status"), "failed", "failure status")
	_assert_eq((failure.get("error", {}) as Dictionary).get("code"), "permission_denied", "failure error")
	_assert_eq(failure.get("created_at"), "2026-06-23T00:00:02Z", "created at preserved")
	_assert_eq(failure.get("completed_at"), "2026-06-23T00:00:03Z", "completed at preserved")


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures += 1
		push_error(label + " expected=" + str(expected) + " actual=" + str(actual))
