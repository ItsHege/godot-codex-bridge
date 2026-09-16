extends SceneTree

const BridgeContext := preload("res://addons/godot_codex_bridge/core/bridge_context.gd")
const EditorScriptNavigation := preload("res://addons/godot_codex_bridge/core/editor_script_navigation.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge editor script navigation tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge editor script navigation tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	_assert_eq(
		EditorScriptNavigation.script_path_from_params({"scriptPath": " res://addons/godot_codex_bridge/plugin.gd "}),
		"res://addons/godot_codex_bridge/plugin.gd",
		"scriptPath alias is normalized"
	)
	_assert_eq(
		EditorScriptNavigation.script_path_from_params({"script_path": "res://addons/godot_codex_bridge/core/editor_script_navigation.gd"}),
		"res://addons/godot_codex_bridge/core/editor_script_navigation.gd",
		"script_path is normalized"
	)
	_assert_eq(EditorScriptNavigation.line_from_params({"line": 12}), 12, "positive line is preserved")
	_assert_eq(EditorScriptNavigation.line_from_params({"line": -3}), 0, "negative line is clamped")

	var valid_path := EditorScriptNavigation.validate_script_path("res://addons/godot_codex_bridge/plugin.gd", true)
	_assert_true(valid_path.is_empty(), "existing plugin script path validates")

	var missing_path := EditorScriptNavigation.validate_script_path("res://missing_script.gd", true)
	_assert_eq(missing_path.get("code"), "script_not_found", "missing script returns not found")

	var absolute_path := EditorScriptNavigation.validate_script_path("C:/tmp/nope.gd", false)
	_assert_eq(absolute_path.get("code"), "invalid_script_path", "absolute path is rejected")

	var traversal_path := EditorScriptNavigation.validate_script_path("res://../nope.gd", false)
	_assert_eq(traversal_path.get("code"), "invalid_script_path", "path traversal is rejected")

	var generated_path := EditorScriptNavigation.validate_script_path("res://.godot/cache/script.gd", false)
	_assert_eq(generated_path.get("code"), "invalid_script_path", "generated .godot path is rejected")

	var unsupported_extension := EditorScriptNavigation.validate_script_path("res://README.md", false)
	_assert_eq(unsupported_extension.get("code"), "invalid_script_extension", "unsupported extension is rejected")

	var ctx := BridgeContext.new()
	ctx.permissions = {"allow_editor_navigation": false}
	var navigation := EditorScriptNavigation.new(ctx)
	var denied := navigation.open_script({"script_path": "res://addons/godot_codex_bridge/plugin.gd"})
	_assert_false(bool(denied.get("ok", true)), "open script denied when permission disabled")
	_assert_eq(((denied.get("error", {}) as Dictionary).get("code")), "permission_denied", "permission error code")


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
