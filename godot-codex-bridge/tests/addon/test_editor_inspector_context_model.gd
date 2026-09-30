extends SceneTree

const BridgeContext := preload("res://addons/godot_codex_bridge/core/bridge_context.gd")
const EditorControl := preload("res://addons/godot_codex_bridge/core/editor_control.gd")
const EditorInspectorContext := preload("res://addons/godot_codex_bridge/core/editor_inspector_context.gd")

const PLUGIN_PATH := "res://addons/godot_codex_bridge/plugin.gd"

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge inspector context and emergency stop tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge inspector context and emergency stop tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var denied_context := BridgeContext.new()
	denied_context.permissions = {"allow_editor_inspect": false}
	var denied_model := EditorInspectorContext.new(denied_context)
	var control := EditorControl.new(denied_context)
	control.register_action("get_inspector_context", Callable(denied_model, "get_inspector_context"))
	var denied := control.handle_request("req-inspector", {"action": "get_inspector_context", "params": {}})
	_assert_eq((denied.get("error", {}) as Dictionary).get("code"), "permission_denied", "inspector context honors inspect permission")

	var root := Node3D.new()
	root.name = "Level"
	var child := Node3D.new()
	child.name = "Crate"
	root.add_child(child)
	var payload := EditorInspectorContext.context_payload(null, "transform/position", [child], root)
	var edited: Dictionary = payload.get("edited_object", {})
	_assert_true(bool(edited.get("available", false)), "single selection becomes edited object")
	_assert_eq(edited.get("kind"), "node", "node kind")
	_assert_eq(edited.get("class"), "Node3D", "node class")
	_assert_eq((edited.get("node", {}) as Dictionary).get("path"), "Crate", "scene-relative node path")
	_assert_eq((payload.get("inspector", {}) as Dictionary).get("selected_path"), "transform/position", "selected property path")
	_assert_false(bool((payload.get("inspector", {}) as Dictionary).get("visible_categories_supported", true)), "visible category UI state honestly unsupported")
	_assert_false(bool(payload.get("snapshot_refreshed", true)), "read-only action does not refresh snapshot")
	var categories := payload.get("property_categories", []) as Array
	_assert_true(categories.size() > 0 and categories.size() <= EditorInspectorContext.MAX_CATEGORIES, "bounded property categories")
	var has_transform := false
	for category in categories:
		var entry := category as Dictionary
		_assert_true((entry.get("sample_properties", []) as Array).size() <= EditorInspectorContext.MAX_SAMPLE_PROPERTIES, "bounded samples")
		if entry.get("name") == "Transform":
			has_transform = true
	_assert_true(has_transform, "transform category summarized")
	_assert_false(JSON.stringify(payload).contains("(0, 0, 0)"), "property values are not exported")

	var resource := StandardMaterial3D.new()
	_assert_eq(EditorInspectorContext.object_payload(resource, root).get("kind"), "resource", "resource kind")
	_assert_false(bool(EditorInspectorContext.object_payload(null, root).get("available", true)), "no edited object")
	var many: Array = []
	for index in range(40):
		many.append(child)
	_assert_eq(EditorInspectorContext.selected_nodes_payload(many, root).size(), 16, "selected nodes capped")
	root.free()

	var plugin_source := FileAccess.get_file_as_string(PLUGIN_PATH)
	var start := plugin_source.find("func _emergency_stop_request(")
	_assert_true(start >= 0, "emergency stop handler present")
	var body := plugin_source.substr(start, plugin_source.find("\nfunc ", start + 10) - start)
	_assert_true(body.contains("_bridge_owned_play_session and was_playing"), "emergency stop only stops Bridge-owned sessions")
	for forbidden in ["save_scene", "save_all_scenes", "undo_redo", "create_action", "set_node", "OS.kill", "OS.execute"]:
		_assert_false(body.contains(forbidden), "emergency stop does not " + forbidden)
	_assert_true(plugin_source.contains("EditorInterface.play_current_scene()\n\t_bridge_owned_play_session = true"), "run_current_scene marks ownership")


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
