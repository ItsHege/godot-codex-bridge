extends SceneTree

const EditorControlManifest := preload("res://addons/godot_codex_bridge/core/editor_control_manifest.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge editor control manifest tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge editor control manifest tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var capabilities := EditorControlManifest.capabilities(9, 17)
	_assert_eq(capabilities.get("version"), "editor-control-v1", "version")
	_assert_eq(capabilities.get("request_type"), "editor_control", "request type")
	_assert_eq(capabilities.get("mutation_model"), "undo_redo_unsaved_with_explicit_save", "mutation model")
	_assert_false(bool(capabilities.get("auto_save_supported", true)), "auto save unsupported")
	_assert_true(bool(capabilities.get("explicit_save_supported", false)), "explicit save supported")
	_assert_false(bool(capabilities.get("native_output_clear_supported", true)), "native output clear unsupported")
	_assert_false(bool(capabilities.get("native_output_read_supported", true)), "native output read unsupported")
	_assert_false(bool(capabilities.get("native_debugger_read_supported", true)), "native debugger read unsupported")
	_assert_true(str(capabilities.get("native_panel_limitations_tooltip", "")).contains("screenshots"), "native panel tooltip mentions screenshots")
	_assert_eq(capabilities.get("max_batch_actions"), 9, "max batch actions")
	_assert_eq(capabilities.get("max_property_changes"), 17, "max property changes")

	var actions := capabilities.get("actions", []) as Array
	_assert_eq(actions.size(), EditorControlManifest.ACTIONS.size(), "actions copied")
	_assert_true(actions.has("editor_batch"), "editor batch exposed")
	_assert_true(actions.has("focus_panel"), "focus panel exposed")
	_assert_true(actions.has("viewport_navigate"), "viewport navigate exposed")
	_assert_true(actions.has("get_inspector_context"), "inspector context exposed")
	_assert_true(actions.has("save_scene"), "save scene exposed")
	_assert_true(actions.has("save_all_scenes"), "save all scenes exposed")
	_assert_true(actions.has("undo_last_bridge_action"), "undo last bridge action exposed")
	_assert_true(actions.has("stop_running_scene"), "stop running scene exposed")
	_assert_true(actions.has("create_node"), "create node exposed")
	_assert_true(actions.has("set_node_transform"), "set node transform exposed")
	_assert_true(actions.has("open_script"), "open script exposed")
	_assert_true(actions.has("get_spatial_bounds"), "spatial bounds exposed")
	_assert_true(actions.has("spatial_query"), "spatial query exposed")
	_assert_true(actions.has("placement_check"), "placement check exposed")
	_assert_true(actions.has("capture_multi_view"), "multi-view capture exposed")
	_assert_true(actions.has("snap_to_ground"), "snap to ground exposed")
	_assert_true(actions.has("snap_to_grid"), "snap to grid exposed")
	_assert_true(actions.has("notes_append"), "notes append exposed")
	_assert_no_duplicates(actions, "manifest actions")

	var focusable_panels := capabilities.get("focusable_native_panels", []) as Array
	_assert_true(focusable_panels.has("Output"), "output panel focusable")
	_assert_true(focusable_panels.has("Debugger"), "debugger panel focusable")
	_assert_true(focusable_panels.has("FileSystem"), "filesystem panel focusable")
	_assert_no_duplicates(focusable_panels, "focusable native panels")

	var screenshot_only := capabilities.get("screenshot_only_native_panels", []) as Array
	_assert_true(screenshot_only.has("Output"), "output screenshot-only")
	_assert_true(screenshot_only.has("Debugger"), "debugger screenshot-only")
	_assert_false(screenshot_only.has("FileSystem"), "filesystem not screenshot-only")
	_assert_no_duplicates(screenshot_only, "screenshot-only native panels")

	var viewport_navigation := capabilities.get("viewport_navigation", {}) as Dictionary
	_assert_true(bool(viewport_navigation.get("typed_2d_pan_zoom_reset_supported", false)), "typed 2D viewport navigation supported")
	_assert_false(bool(viewport_navigation.get("typed_3d_orbit_zoom_frame_selected_supported", true)), "typed 3D camera navigation unsupported")
	_assert_eq(viewport_navigation.get("typed_3d_unavailable_code"), "editor_api_unavailable", "3D unavailable code")

	var multi_view_capture := capabilities.get("multi_view_capture", {}) as Dictionary
	_assert_true(bool(multi_view_capture.get("supported", false)), "multi-view capture supported")
	_assert_eq(multi_view_capture.get("request_action"), "capture_multi_view", "multi-view request action")
	_assert_eq(multi_view_capture.get("capture_scope"), "offscreen_scene_world", "multi-view capture scope")
	_assert_false(bool(multi_view_capture.get("mutates_scene", true)), "multi-view does not mutate scene")
	_assert_true((multi_view_capture.get("views", []) as Array).has("front"), "multi-view front exposed")
	_assert_true((multi_view_capture.get("views", []) as Array).has("perspective"), "multi-view perspective exposed")

	actions.append("mutated_test_value")
	_assert_false(EditorControlManifest.ACTIONS.has("mutated_test_value"), "capability action list is defensive copy")


func _assert_no_duplicates(values: Array, label: String) -> void:
	var seen := {}
	for value in values:
		if seen.has(value):
			_failures += 1
			push_error(label + " contains duplicate value: " + str(value))
			return
		seen[value] = true


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
