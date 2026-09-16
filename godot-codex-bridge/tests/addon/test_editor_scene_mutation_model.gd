extends SceneTree

const BridgeContext := preload("res://addons/godot_codex_bridge/core/bridge_context.gd")
const EditorSceneMutation := preload("res://addons/godot_codex_bridge/core/editor_scene_mutation.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge editor scene mutation tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge editor scene mutation tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	_assert_true(EditorSceneMutation.payload_has_any({"rotationDegrees": 30}, ["rotation_degrees", "rotationDegrees"]), "camelCase transform key detected")
	_assert_false(EditorSceneMutation.payload_has_any({"rotation": 30}, ["rotation_degrees", "rotationDegrees"]), "unlisted transform key ignored")
	_assert_eq(EditorSceneMutation.payload_get_any({"rotationDegrees": 30}, ["rotation_degrees", "rotationDegrees"]), 30, "payload_get_any returns first present key")

	var root := Node3D.new()
	root.name = "Root"
	var child := Node3D.new()
	child.name = "Child"
	root.add_child(child)
	_assert_eq(EditorSceneMutation.scene_path_for(root, root), ".", "root path is dot")
	_assert_eq(EditorSceneMutation.scene_path_for(child, root), "Child", "child path is relative")
	var ref := EditorSceneMutation.node_ref_payload(child, root)
	_assert_eq(ref.get("name"), "Child", "node ref name")
	_assert_eq(ref.get("type"), "Node3D", "node ref type")

	var serialized := EditorSceneMutation.serialized_property_changes([
		{"property": "position", "old_value": Vector3.ZERO, "new_value": Vector3(1, 2, 3)}
	])
	_assert_eq(serialized.size(), 1, "one property change serialized")
	var first_change: Dictionary = serialized[0]
	_assert_eq(first_change.get("property"), "position", "serialized property name")
	_assert_eq((first_change.get("new_value") as Dictionary).get("z"), 3.0, "Vector3 new value serializes")
	root.free()

	var ctx := BridgeContext.new()
	ctx.permissions = {"allow_scene_edits": false}
	var mutation := EditorSceneMutation.new(ctx)
	var denied := mutation.set_node_transform({})
	_assert_false(bool(denied.get("ok", true)), "transform denied when scene edit permission disabled")
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
