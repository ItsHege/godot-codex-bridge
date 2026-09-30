extends SceneTree

const BridgeContext := preload("res://addons/godot_codex_bridge/core/bridge_context.gd")
const EditorControl := preload("res://addons/godot_codex_bridge/core/editor_control.gd")
const EditorControlManifest := preload("res://addons/godot_codex_bridge/core/editor_control_manifest.gd")
const EditorViewportNavigation := preload("res://addons/godot_codex_bridge/core/editor_viewport_navigation.gd")
const SpatialBoundsModel := preload("res://addons/godot_codex_bridge/core/spatial_bounds_model.gd")

const PLUGIN_PATH := "res://addons/godot_codex_bridge/plugin.gd"
## Dispatched inside editor_control.gd rather than through register_action().
const BUILT_IN_ACTIONS := ["editor_batch"]

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge editor_control manifest parity tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge editor_control manifest parity tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var plugin_source := FileAccess.get_file_as_string(PLUGIN_PATH)
	_assert_true(plugin_source != "", "plugin.gd source readable")
	var pattern := RegEx.new()
	pattern.compile("_editor_control\\.register_action\\(\"([a-z0-9_]+)\"")
	var registered := {}
	for found in pattern.search_all(plugin_source):
		registered[found.get_string(1)] = true
	for action in BUILT_IN_ACTIONS:
		registered[action] = true
	_assert_true(registered.size() > 40, "registered handler set parsed")

	var advertised := {}
	for action in EditorControlManifest.ACTIONS:
		advertised[str(action)] = true
		_assert_true(registered.has(str(action)), "advertised action has a registered handler: " + str(action))
	for action in registered.keys():
		_assert_true(advertised.has(str(action)), "registered action is advertised in manifest: " + str(action))

	for required in ["snap_to_ground", "snap_to_grid", "viewport_navigate", "get_state", "get_inspector_context", "emergency_stop"]:
		_assert_true(registered.has(required), "plugin registers " + required)
		_assert_true(advertised.has(required), "manifest advertises " + required)
	_assert_true(plugin_source.contains("register_action(\"snap_to_ground\", Callable(_spatial_bounds, \"snap_to_ground\"))"), "snap_to_ground routes to spatial bounds model")
	_assert_true(plugin_source.contains("register_action(\"snap_to_grid\", Callable(_spatial_bounds, \"snap_to_grid\"))"), "snap_to_grid routes to spatial bounds model")
	_assert_true(plugin_source.contains("register_action(\"viewport_navigate\", Callable(_editor_viewport_navigation, \"navigate\"))"), "viewport_navigate routes to viewport navigation")
	_assert_true(plugin_source.contains("EditorViewportNavigation.new(_context)"), "viewport navigation shares the plugin context")

	_check_snap_permission_gate()
	_check_viewport_navigation_dispatch()


func _check_snap_permission_gate() -> void:
	var denied_context := BridgeContext.new()
	denied_context.permissions = {"allow_scene_edits": false}
	# Callables do not keep RefCounted targets alive; hold the model like plugin.gd does.
	var model := SpatialBoundsModel.new(denied_context)
	var control := EditorControl.new(denied_context)
	control.register_action("snap_to_ground", Callable(model, "snap_to_ground"))
	control.register_action("snap_to_grid", Callable(model, "snap_to_grid"))
	for action in ["snap_to_ground", "snap_to_grid"]:
		var result := control.handle_request("req-" + action, {"action": action, "params": {"grid_size": 1.0}})
		_assert_false(bool(result.get("ok", true)), action + " rejected without scene-edit permission")
		_assert_eq((result.get("error", {}) as Dictionary).get("code"), "permission_denied", action + " permission code")


func _check_viewport_navigation_dispatch() -> void:
	var denied_context := BridgeContext.new()
	denied_context.permissions = {"allow_editor_navigation": false}
	var denied_model := EditorViewportNavigation.new(denied_context)
	var denied_control := EditorControl.new(denied_context)
	denied_control.register_action("viewport_navigate", Callable(denied_model, "navigate"))
	var denied := denied_control.handle_request("req-nav-denied", {"action": "viewport_navigate", "params": {"viewport": "2D", "action": "reset"}})
	_assert_eq((denied.get("error", {}) as Dictionary).get("code"), "permission_denied", "viewport_navigate honors navigation permission")

	var allowed_context := BridgeContext.new()
	allowed_context.permissions = {"allow_editor_navigation": true}
	var allowed_model := EditorViewportNavigation.new(allowed_context)
	var allowed_control := EditorControl.new(allowed_context)
	allowed_control.register_action("viewport_navigate", Callable(allowed_model, "navigate"))
	var three_d := allowed_control.handle_request("req-nav-3d", {"action": "viewport_navigate", "params": {"viewport": "3D", "action": "orbit"}})
	_assert_eq((three_d.get("error", {}) as Dictionary).get("code"), "editor_api_unavailable", "3D navigation reports honest unavailable code")
	var bad_action := allowed_control.handle_request("req-nav-bad", {"action": "viewport_navigate", "params": {"viewport": "2D", "action": "spin"}})
	_assert_eq((bad_action.get("error", {}) as Dictionary).get("code"), "invalid_viewport_action", "unknown 2D action rejected")
	var navigation := EditorControlManifest.capabilities(12, 32).get("viewport_navigation", {}) as Dictionary
	_assert_true(bool(navigation.get("typed_2d_pan_zoom_reset_supported", false)), "2D pan/zoom/reset advertised because it is wired")
	_assert_eq(EditorViewportNavigation.supported_actions("2D"), ["pan", "zoom", "reset"], "2D actions")


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
