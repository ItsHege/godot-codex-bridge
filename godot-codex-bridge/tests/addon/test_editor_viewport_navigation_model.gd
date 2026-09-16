extends SceneTree

const BridgeContext := preload("res://addons/godot_codex_bridge/core/bridge_context.gd")
const EditorViewportNavigation := preload("res://addons/godot_codex_bridge/core/editor_viewport_navigation.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge editor viewport navigation tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge editor viewport navigation tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	_assert_eq(EditorViewportNavigation.canonical_viewport("2D"), "2D", "2D viewport canonical")
	_assert_eq(EditorViewportNavigation.canonical_viewport("viewport-3d"), "3D", "3D viewport canonical")
	_assert_eq(EditorViewportNavigation.canonical_viewport("unknown"), "", "invalid viewport canonical")
	_assert_eq(EditorViewportNavigation.canonical_action("2D", "pan"), "pan", "2D pan action")
	_assert_eq(EditorViewportNavigation.canonical_action("2D", "frame_selected"), "", "2D rejects 3D action")
	_assert_eq(EditorViewportNavigation.canonical_action("3D", "frame selected"), "frame_selected", "3D frame selected action")
	_assert_true(EditorViewportNavigation.supported_actions("2D").has("zoom"), "2D supported zoom")
	_assert_true(EditorViewportNavigation.supported_actions("3D").has("orbit"), "3D supported orbit")

	var denied := EditorViewportNavigation.new().navigate({"viewport": "2D", "action": "pan"})
	_assert_false(bool(denied.get("ok", true)), "permission denied result")
	_assert_eq((denied.get("error", {}) as Dictionary).get("code"), "permission_denied", "permission denied code")

	var context := BridgeContext.new()
	context.permissions = {"allow_editor_navigation": true}
	var navigator := EditorViewportNavigation.new(context)
	var invalid_viewport := navigator.navigate({"viewport": "VR", "action": "pan"})
	_assert_false(bool(invalid_viewport.get("ok", true)), "invalid viewport result")
	_assert_eq((invalid_viewport.get("error", {}) as Dictionary).get("code"), "invalid_viewport", "invalid viewport code")

	var invalid_action := navigator.navigate({"viewport": "2D", "action": "orbit"})
	_assert_false(bool(invalid_action.get("ok", true)), "invalid action result")
	_assert_eq((invalid_action.get("error", {}) as Dictionary).get("code"), "invalid_viewport_action", "invalid action code")

	var unsupported_3d := navigator.navigate({"viewport": "3D", "action": "orbit"})
	_assert_false(bool(unsupported_3d.get("ok", true)), "3D unavailable result")
	_assert_eq((unsupported_3d.get("error", {}) as Dictionary).get("code"), "editor_api_unavailable", "3D unavailable code")

	var payload := EditorViewportNavigation.transform_payload(Transform2D())
	_assert_true(payload.has("origin"), "transform payload has origin")
	_assert_eq((payload.get("origin", {}) as Dictionary).get("x"), 0.0, "identity origin x")


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
