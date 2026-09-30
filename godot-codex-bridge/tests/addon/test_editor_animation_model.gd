extends SceneTree

const BridgeContext := preload("res://addons/godot_codex_bridge/core/bridge_context.gd")
const EditorAnimation := preload("res://addons/godot_codex_bridge/core/editor_animation.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge editor animation tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge editor animation tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var ctx := BridgeContext.new()
	ctx.permissions = {
		"allow_editor_inspect": false,
		"allow_animation_preview": false,
		"allow_scene_edits": false,
	}
	var service := EditorAnimation.new(ctx)

	var denied_list := service.list_animation_players({})
	_assert_false(bool(denied_list.get("ok", true)), "list animation players denied when inspect permission disabled")
	_assert_eq(((denied_list.get("error", {}) as Dictionary).get("code")), "permission_denied", "inspect permission error")

	var denied_preview := service.preview_animation({})
	_assert_false(bool(denied_preview.get("ok", true)), "preview animation denied when preview permission disabled")
	_assert_eq(((denied_preview.get("error", {}) as Dictionary).get("code")), "permission_denied", "preview permission error")

	var denied_create := service.create_animation_clip({})
	_assert_false(bool(denied_create.get("ok", true)), "create animation denied when scene edit permission disabled")
	_assert_eq(((denied_create.get("error", {}) as Dictionary).get("code")), "permission_denied", "scene edit permission error")

	# Preview pose backup resolves what each track writes.
	var root := Node3D.new()
	var mover := Node3D.new()
	mover.name = "Mover"
	root.add_child(mover)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.material_override = StandardMaterial3D.new()
	root.add_child(mesh)
	var position_target := EditorAnimation.preview_track_target(root, Animation.TYPE_POSITION_3D, NodePath("Mover"))
	_assert_eq([position_target.get("object"), position_target.get("property")], [mover, "position"], "position track target")
	var rotation_target := EditorAnimation.preview_track_target(root, Animation.TYPE_ROTATION_3D, NodePath("Mover"))
	_assert_eq(rotation_target.get("property"), "quaternion", "rotation track target")
	var value_target := EditorAnimation.preview_track_target(root, Animation.TYPE_VALUE, NodePath("Mover:position:x"))
	_assert_eq([value_target.get("object"), value_target.get("property")], [mover, "position"], "sub-property value track backs up base property")
	var resource_target := EditorAnimation.preview_track_target(root, Animation.TYPE_VALUE, NodePath("Mesh:material_override:albedo_color"))
	_assert_eq([resource_target.get("object"), resource_target.get("property")], [mesh.material_override, "albedo_color"], "resource value track target")
	_assert_eq(EditorAnimation.preview_track_target(root, Animation.TYPE_METHOD, NodePath("Mover")), {}, "method tracks skipped")
	_assert_eq(EditorAnimation.preview_track_target(root, Animation.TYPE_VALUE, NodePath("Missing:position")), {}, "missing node skipped")
	root.free()


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures += 1
		push_error(label + " expected=" + str(expected) + " actual=" + str(actual))


func _assert_false(value: bool, label: String) -> void:
	if value:
		_failures += 1
		push_error(label)
