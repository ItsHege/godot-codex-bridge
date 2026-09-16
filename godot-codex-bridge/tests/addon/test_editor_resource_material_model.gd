extends SceneTree

const BridgeContext := preload("res://addons/godot_codex_bridge/core/bridge_context.gd")
const EditorResourceMaterial := preload("res://addons/godot_codex_bridge/core/editor_resource_material.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge editor resource/material tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge editor resource/material tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var bad_absolute := EditorResourceMaterial.validate_res_path("C:/outside.png", [".png"], "texture", false)
	_assert_eq(bad_absolute.get("code"), "invalid_texture_path", "absolute texture path rejected")
	var bad_traversal := EditorResourceMaterial.validate_res_path("res://../outside.png", [".png"], "texture", false)
	_assert_eq(bad_traversal.get("code"), "invalid_texture_path", "traversal texture path rejected")
	var bad_generated := EditorResourceMaterial.validate_res_path("res://.godot/generated.png", [".png"], "texture", false)
	_assert_eq(bad_generated.get("code"), "invalid_texture_path", "generated texture path rejected")
	var bad_extension := EditorResourceMaterial.validate_res_path("res://image.txt", [".png"], "texture", false)
	_assert_eq(bad_extension.get("code"), "invalid_texture_extension", "texture extension rejected")
	var ok_path := EditorResourceMaterial.validate_res_path("res://image.png", [".png"], "texture", false)
	_assert_eq(ok_path.size(), 0, "valid texture path accepted when existence not required")
	_assert_true(".png" in EditorResourceMaterial.texture_resource_extensions(), "png texture extension present")
	_assert_true(".tres" in EditorResourceMaterial.texture_resource_extensions(), "tres texture extension present")

	var root := Node3D.new()
	root.name = "Root"
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = BoxMesh.new()
	root.add_child(mesh_instance)

	var ctx := BridgeContext.new()
	ctx.permissions = {"allow_scene_edits": false}
	var service := EditorResourceMaterial.new(ctx)
	var material_target := service.resolve_material_assignment_target(mesh_instance, "geometry_material_override", -1)
	_assert_true(bool(material_target.get("ok", false)), "geometry material target resolves")
	_assert_eq(material_target.get("property"), "material_override", "geometry target property")
	var mesh_surface_target := service.resolve_material_assignment_target(mesh_instance, "mesh_surface", 0)
	_assert_true(bool(mesh_surface_target.get("ok", false)), "mesh surface target resolves")
	_assert_eq(mesh_surface_target.get("assignment_kind"), "surface_override", "mesh surface assignment kind")
	var shader_target_missing := service.resolve_shader_material_target(mesh_instance, "geometry_material_override", -1)
	_assert_false(bool(shader_target_missing.get("ok", true)), "missing shader material rejects")
	_assert_eq(((shader_target_missing.get("error", {}) as Dictionary).get("code")), "material_missing", "missing shader material error")

	var denied := service.assign_resource_to_node({})
	_assert_false(bool(denied.get("ok", true)), "resource assignment denied when permission disabled")
	_assert_eq(((denied.get("error", {}) as Dictionary).get("code")), "permission_denied", "permission error code")
	root.free()


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
