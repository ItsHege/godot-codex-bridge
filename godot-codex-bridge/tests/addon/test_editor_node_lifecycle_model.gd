extends SceneTree

const BridgeContext := preload("res://addons/godot_codex_bridge/core/bridge_context.gd")
const EditorNodeLifecycle := preload("res://addons/godot_codex_bridge/core/editor_node_lifecycle.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge editor node lifecycle tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge editor node lifecycle tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	_assert_eq(EditorNodeLifecycle.sanitize_node_class_name(" Node3D "), "Node3D", "node class trims")
	_assert_eq(EditorNodeLifecycle.sanitize_node_class_name("Bad/Class"), "", "node class rejects slash")
	_assert_eq(EditorNodeLifecycle.sanitize_node_name("  Hero  ", "Node"), "Hero", "node name trims")
	_assert_eq(EditorNodeLifecycle.sanitize_node_name("", "Node"), "Node", "node name fallback")
	_assert_true(EditorNodeLifecycle.is_valid_node_name("Hero_01"), "valid node name accepted")
	_assert_false(EditorNodeLifecycle.is_valid_node_name("Bad/Name"), "slash node name rejected")

	var root := Node.new()
	root.name = "Root"
	var child := Node.new()
	child.name = "Child"
	root.add_child(child)
	_assert_eq(EditorNodeLifecycle.bounded_child_index(root, -1), 1, "negative index appends")
	_assert_eq(EditorNodeLifecycle.bounded_child_index(root, 99), 1, "large index clamps")
	_assert_eq(EditorNodeLifecycle.scene_path_for(root, root), ".", "root path is dot")
	_assert_eq(EditorNodeLifecycle.scene_path_for(child, root), "Child", "child path is relative")
	var ref := EditorNodeLifecycle.node_ref_payload(child, root)
	_assert_eq(ref.get("name"), "Child", "node ref name")
	_assert_eq(ref.get("path"), "Child", "node ref path")
	root.free()

	var ctx := BridgeContext.new()
	ctx.permissions = {"allow_scene_edits": false}
	var lifecycle := EditorNodeLifecycle.new(ctx)
	var denied := lifecycle.create_node({})
	_assert_false(bool(denied.get("ok", true)), "create node denied when permission disabled")
	_assert_eq(((denied.get("error", {}) as Dictionary).get("code")), "permission_denied", "permission error code")

	var bad_scene := lifecycle.validate_scene_path("C:/outside.tscn")
	_assert_eq(bad_scene.get("code"), "invalid_scene_path", "absolute scene path rejected")
	var generated_scene := lifecycle.validate_scene_path("res://.godot/generated.tscn")
	_assert_eq(generated_scene.get("code"), "invalid_scene_path", "generated scene path rejected")
	var bad_ext := lifecycle.validate_scene_path("res://scene.txt")
	_assert_eq(bad_ext.get("code"), "invalid_scene_extension", "bad scene extension rejected")


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
