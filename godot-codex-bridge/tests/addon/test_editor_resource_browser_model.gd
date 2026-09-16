extends SceneTree

const BridgeContext := preload("res://addons/godot_codex_bridge/core/bridge_context.gd")
const EditorResourceBrowser := preload("res://addons/godot_codex_bridge/core/editor_resource_browser.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge editor resource browser tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge editor resource browser tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	_assert_eq(EditorResourceBrowser.root_path_from_params({}), "res://", "default root path")
	_assert_eq(EditorResourceBrowser.root_path_from_params({"rootPath": " res://scenes "}), "res://scenes", "rootPath alias")
	_assert_eq(EditorResourceBrowser.root_path_from_params({"root_path": ""}), "res://", "empty root path fallback")

	_assert_true(EditorResourceBrowser.validate_res_dir_path("res://").is_empty(), "res root validates")
	_assert_true(EditorResourceBrowser.validate_res_dir_path("res://scenes/debug").is_empty(), "nested root validates")
	_assert_eq(EditorResourceBrowser.validate_res_dir_path("C:/game").get("code"), "invalid_resource_root", "absolute root rejected")
	_assert_eq(EditorResourceBrowser.validate_res_dir_path("res://../outside").get("code"), "invalid_resource_root", "traversal root rejected")
	_assert_eq(EditorResourceBrowser.validate_res_dir_path("res://.godot/cache").get("code"), "invalid_resource_root", "generated root rejected")
	_assert_eq(EditorResourceBrowser.validate_res_dir_path("res://assets//bad").get("code"), "invalid_resource_root", "empty root segment rejected")

	var extensions := EditorResourceBrowser.extension_filter_array(["gd", ".TSCN", " ", ".png", ".png", "bad/path", "waytoolongextensionname"])
	_assert_eq(extensions, [".gd", ".tscn", ".png"], "extension filter normalizes and deduplicates")
	_assert_eq(EditorResourceBrowser.extension_filter_array("gd"), [], "non-array extension filter ignored")

	_assert_true(
		EditorResourceBrowser.resource_matches_filters("res://scenes/Main.tscn", "PackedScene", "res://scenes", [".tscn"], ""),
		"matching resource accepted"
	)
	_assert_true(
		EditorResourceBrowser.resource_matches_filters("res://scenes/Main.tscn", "PackedScene", "res://scenes/", [".tscn"], "packedscene"),
		"trailing root slash and case-insensitive type accepted"
	)
	_assert_false(
		EditorResourceBrowser.resource_matches_filters("res://scripts/main.gd", "GDScript", "res://scenes", [".gd"], ""),
		"outside root rejected"
	)
	_assert_false(
		EditorResourceBrowser.resource_matches_filters("res://scenes/Main.tscn", "PackedScene", "res://scenes", [".gd"], ""),
		"wrong extension rejected"
	)
	_assert_false(
		EditorResourceBrowser.resource_matches_filters("res://scenes/Main.tscn", "PackedScene", "res://scenes", [".tscn"], "Texture2D"),
		"wrong type rejected"
	)

	var ctx := BridgeContext.new()
	ctx.permissions = {"allow_editor_diagnostics": false}
	var browser := EditorResourceBrowser.new(ctx)
	var denied := browser.list_resources({})
	_assert_false(bool(denied.get("ok", true)), "list resources denied when diagnostics permission disabled")
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
