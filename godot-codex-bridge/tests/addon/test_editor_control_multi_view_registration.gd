extends SceneTree

const BridgeContext := preload("res://addons/godot_codex_bridge/core/bridge_context.gd")
const EditorControl := preload("res://addons/godot_codex_bridge/core/editor_control.gd")
const EditorControlManifest := preload("res://addons/godot_codex_bridge/core/editor_control_manifest.gd")
const MultiViewCaptureModel := preload("res://addons/godot_codex_bridge/core/multi_view_capture_model.gd")

const PLUGIN_PATH := "res://addons/godot_codex_bridge/plugin.gd"

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge editor_control multi-view registration tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge editor_control multi-view registration tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var action: String = EditorControlManifest.capabilities(12, 32).get("multi_view_capture", {}).get("request_action", "")
	_assert_eq(action, "capture_multi_view", "manifest advertises capture_multi_view")

	var plugin_source := FileAccess.get_file_as_string(PLUGIN_PATH)
	_assert_true(plugin_source != "", "plugin.gd source readable")
	_assert_true(plugin_source.contains("MultiViewCaptureModel.new(_context)"), "plugin constructs multi-view model with shared context")
	_assert_true(plugin_source.contains("register_action(\"capture_multi_view\", Callable(_multi_view_capture, \"capture_multi_view\"))"), "plugin registers capture_multi_view action")

	var unregistered := EditorControl.new(BridgeContext.new())
	var missing := unregistered.handle_request("req-missing", {"action": "capture_multi_view", "params": {}})
	_assert_eq((missing.get("error", {}) as Dictionary).get("code"), "unsupported_editor_action", "unregistered dispatcher rejects action")

	var denied_context := BridgeContext.new()
	denied_context.permissions = {"allow_screenshots": false}
	# Callables do not keep RefCounted targets alive; hold the model like plugin.gd does.
	var denied_model := MultiViewCaptureModel.new(denied_context)
	var denied_control := EditorControl.new(denied_context)
	denied_control.register_action(action, Callable(denied_model, "capture_multi_view"))
	var denied := denied_control.handle_request("req-denied", {"action": action, "params": {"views": ["front"]}})
	_assert_false(bool(denied.get("ok", true)), "registered action respects screenshot permission")
	_assert_eq((denied.get("error", {}) as Dictionary).get("code"), "permission_denied", "registered action returns permission_denied")

	var allowed_context := BridgeContext.new()
	allowed_context.permissions = {"allow_screenshots": true}
	var allowed_model := MultiViewCaptureModel.new(allowed_context)
	var allowed_control := EditorControl.new(allowed_context)
	allowed_control.register_action(action, Callable(allowed_model, "capture_multi_view"))
	var headless := allowed_control.handle_request("req-headless", {"action": action, "params": {"width": 640, "height": 480}})
	var headless_code := str((headless.get("error", {}) as Dictionary).get("code", ""))
	_assert_false(bool(headless.get("ok", true)), "headless capture reports structured failure")
	_assert_true(headless_code != "unsupported_editor_action", "registered action reaches multi-view model")
	_assert_eq(headless_code, "multi_view_capture_unavailable", "headless capture uses documented unavailable code")

	var invalid_params := allowed_control.handle_request("req-invalid", {"action": action, "params": "front"})
	_assert_eq((invalid_params.get("error", {}) as Dictionary).get("code"), "invalid_request", "non-object params rejected")

	_assert_true(plugin_source.contains("_async_editor_requests_in_flight.has(str(file_name))"), "request-file poll skips in-flight async requests")
	_assert_true(plugin_source.contains("await _multi_view_capture.capture_multi_view_async(params_value as Dictionary)"), "request-file path awaits live multi-view frames")
	_assert_true(plugin_source.contains("_editor_control.finalize_action_result(request_id, \"capture_multi_view\", result, started_msec)"), "async path reuses editor_control envelope")

	var finalized := allowed_control.finalize_action_result("req-async", action, {"ok": true, "data": {"status": "ok"}}, Time.get_ticks_msec())
	var finalized_data := finalized.get("data", {}) as Dictionary
	_assert_true(bool(finalized.get("ok", false)), "finalized success stays ok")
	_assert_eq(finalized_data.get("action"), action, "finalized envelope includes action")
	_assert_eq(finalized_data.get("request_id"), "req-async", "finalized envelope includes request id")
	_assert_true(finalized_data.has("latency_ms"), "finalized envelope includes latency")
	_assert_eq(finalized_data.get("snapshot_refreshed"), false, "finalized envelope marks snapshot not refreshed")

	var finalized_error := allowed_control.finalize_action_result("req-async-error", action, {"ok": false, "error": {"code": "multi_view_capture_unavailable", "message": "unavailable"}}, Time.get_ticks_msec())
	_assert_eq((finalized_error.get("error", {}) as Dictionary).get("code"), "multi_view_capture_unavailable", "finalized error keeps structured code")


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
