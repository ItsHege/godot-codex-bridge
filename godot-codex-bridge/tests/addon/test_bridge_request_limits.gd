extends SceneTree

const BridgeLimits := preload("res://addons/godot_codex_bridge/core/bridge_limits.gd")
const BridgeRequestLimits := preload("res://addons/godot_codex_bridge/core/bridge_request_limits.gd")

var _failures := 0


func _init() -> void:
	var valid := BridgeRequestLimits.parse_bounded_request(JSON.stringify({"type": "refresh_context", "payload": {}}).to_utf8_buffer())
	_assert_true(bool(valid.get("ok", false)), "valid request accepted")

	var oversized := PackedByteArray()
	oversized.resize(BridgeLimits.MAX_REQUEST_BYTES + 1)
	var oversized_result := BridgeRequestLimits.parse_bounded_request(oversized)
	_assert_eq(str((oversized_result.get("error", {}) as Dictionary).get("code", "")), "request_too_large", "oversized request rejected")

	var deep: Variant = {"leaf": true}
	for index in range(BridgeLimits.MAX_REQUEST_JSON_DEPTH + 2):
		deep = {"nested": deep}
	var deep_result := BridgeRequestLimits.parse_bounded_request(JSON.stringify(deep).to_utf8_buffer())
	_assert_eq(str((deep_result.get("error", {}) as Dictionary).get("code", "")), "request_json_too_deep", "deep request rejected")

	var many: Array = []
	for index in range(BridgeLimits.MAX_REQUEST_JSON_NODES + 1):
		many.append(index)
	var complex_result := BridgeRequestLimits.parse_bounded_request(JSON.stringify({"items": many}).to_utf8_buffer())
	_assert_eq(str((complex_result.get("error", {}) as Dictionary).get("code", "")), "request_json_too_complex", "complex request rejected")

	if _failures == 0:
		print("Godot Codex Bridge request limit tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge request limit tests failed: " + str(_failures))
		quit(1)


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures += 1
		push_error(label + " expected=" + str(expected) + " actual=" + str(actual))


func _assert_true(value: bool, label: String) -> void:
	if not value:
		_failures += 1
		push_error(label)
