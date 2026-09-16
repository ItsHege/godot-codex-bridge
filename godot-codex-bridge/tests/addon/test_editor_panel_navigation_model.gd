extends SceneTree

const EditorPanelNavigation := preload("res://addons/godot_codex_bridge/core/editor_panel_navigation.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge editor panel navigation tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge editor panel navigation tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	_assert_eq(EditorPanelNavigation.canonical_panel_name("errors"), "Debugger", "errors alias")
	_assert_eq(EditorPanelNavigation.canonical_panel_name("shader"), "Shader Editor", "shader alias")
	_assert_eq(EditorPanelNavigation.canonical_panel_name("file_system"), "FileSystem", "filesystem alias")
	_assert_eq(EditorPanelNavigation.canonical_panel_name("Output"), "Output", "canonical output")
	_assert_eq(EditorPanelNavigation.canonical_panel_name("unknown"), "", "unknown panel rejected")
	_assert_true(EditorPanelNavigation.supported_panels().has("Debugger"), "supported panels include debugger")

	var tabs := TabContainer.new()
	var output := Control.new()
	output.name = "Output"
	var debugger := Control.new()
	debugger.name = "Debugger"
	tabs.add_child(output)
	tabs.add_child(debugger)
	root.add_child(tabs)

	var result := EditorPanelNavigation.focus_tab_recursive(tabs, "Debugger")
	_assert_true(bool(result.get("found", false)), "debugger tab found")
	_assert_eq(result.get("matched_title"), "Debugger", "matched debugger title")
	_assert_eq(result.get("matched_tab_index"), 1, "debugger tab index")

	var missing := EditorPanelNavigation.focus_tab_recursive(tabs, "Audio")
	_assert_false(bool(missing.get("found", false)), "missing tab not found")

	tabs.free()


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
