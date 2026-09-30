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

	# Owner bookkeeping for delete/reparent: scene-owned descendants are
	# recorded; nodes owned inside the subtree (instance internals) are not.
	var scene := Node3D.new()
	var parent := _owned(scene, scene, "Parent")
	var grandchild_parent := _owned(parent, scene, "Instance")
	var internal := Node3D.new()
	internal.name = "Internal"
	grandchild_parent.add_child(internal)
	internal.owner = grandchild_parent
	var leaf := _owned(internal, scene, "EditableLeaf")
	var owned := EditorNodeLifecycle.externally_owned_nodes(parent)
	var owned_nodes: Array = owned.map(func(entry: Dictionary) -> Node: return entry.get("node"))
	_assert_eq(owned_nodes, [parent, grandchild_parent, leaf], "externally owned nodes in tree order")
	_assert_false(owned_nodes.has(internal), "instance-internal node keeps its own owner")
	var other := _owned(scene, scene, "Other")
	_assert_eq(EditorNodeLifecycle.owner_after_reparent(scene, other, scene), scene, "scene owner survives reparent")
	_assert_eq(EditorNodeLifecycle.owner_after_reparent(grandchild_parent, other, scene), scene, "non-ancestor owner falls back to scene root")
	_assert_eq(EditorNodeLifecycle.owner_after_reparent(grandchild_parent, internal, scene), grandchild_parent, "ancestor owner kept")
	scene.free()


func _owned(parent: Node, owner: Node, node_name: String) -> Node:
	var node := Node3D.new()
	node.name = node_name
	parent.add_child(node)
	node.owner = owner
	return node


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
