extends SceneTree

const BridgeContext := preload("res://addons/godot_codex_bridge/core/bridge_context.gd")
const BridgeLimits := preload("res://addons/godot_codex_bridge/core/bridge_limits.gd")
const BridgeUtils := preload("res://addons/godot_codex_bridge/core/bridge_utils.gd")

var _failures := 0
var _logged_events: Array[Dictionary] = []
var _recorded_actions: Array[Dictionary] = []


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge phase 0 core tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge phase 0 core tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	_assert_eq(BridgeLimits.PLUGIN_NAME, "Godot Codex Bridge", "plugin name lives in limits")
	_assert_true(BridgeLimits.MAX_SCENE_NODES > 0, "scene node limit is positive")
	_assert_true(BridgeLimits.CONTEXT_SNAPSHOT_PATH.find("context_snapshot.json") >= 0, "snapshot path lives in limits")

	var ok := BridgeUtils.ok({"value": 7})
	_assert_true(bool(ok.get("ok", false)), "ok helper marks success")
	_assert_eq((ok.get("data", {}) as Dictionary).get("value"), 7, "ok helper carries data")

	var error := BridgeUtils.err("bad", "Bad thing")
	_assert_false(bool(error.get("ok", true)), "err helper marks failure")
	_assert_eq(((error.get("error", {}) as Dictionary).get("code")), "bad", "err helper carries code")

	var response := BridgeUtils.response_payload("p/1", "r1", "refresh_context", "completed", {"fresh": true}, {}, "t0", "t1")
	_assert_eq(response.get("status"), "succeeded", "response helper normalizes completed")
	_assert_eq(response.get("error"), null, "response helper emits null error when empty")

	var rect_payload := BridgeUtils.rect2_payload(Rect2(Vector2(1, 2), Vector2(3, 4)))
	_assert_eq(rect_payload.get("width"), 3.0, "rect helper writes width")
	_assert_eq(BridgeUtils.sanitize_identifier("bad name!*", "fallback"), "bad_name_", "identifier helper sanitizes")

	var ctx := BridgeContext.new()
	ctx.permissions = {"allow_chat": true}
	ctx.refresh_snapshot = Callable(self, "_fake_refresh")
	ctx.log_event = Callable(self, "_fake_log")
	ctx.record_editor_action = Callable(self, "_fake_record_action")

	_assert_true(ctx.permission_enabled("allow_chat"), "context permission true")
	_assert_false(ctx.permission_enabled("missing"), "context permission false")
	_assert_eq(ctx.refresh("phase0").get("reason"), "phase0", "context refresh callback")
	ctx.log("phase0_event", {"ok": true})
	ctx.record_action("phase0_action", "ok", {"x": 1})
	_assert_eq(_logged_events.size(), 1, "context log callback called")
	_assert_eq(_recorded_actions.size(), 1, "context record callback called")


func _fake_refresh(reason: String) -> Dictionary:
	return {"reason": reason}


func _fake_log(event_name: String, data: Dictionary = {}) -> void:
	_logged_events.append({"event": event_name, "data": data})


func _fake_record_action(action: String, status: String, data: Dictionary) -> void:
	_recorded_actions.append({"action": action, "status": status, "data": data})


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

