extends SceneTree

const ResourceLifecycleModel := preload("res://addons/godot_codex_bridge/core/resource_lifecycle_model.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge resource lifecycle model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge resource lifecycle model tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	_assert_eq(ResourceLifecycleModel.sanitize_resource_class_name(" BoxMesh "), "BoxMesh", "Resource class trims")
	_assert_eq(ResourceLifecycleModel.sanitize_resource_class_name("Bad\nClass"), "", "Resource class rejects newline")

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "MeshInstance3D"
	get_root().add_child(mesh_instance)

	var mesh_property := ResourceLifecycleModel.validate_assignment_property(mesh_instance, "mesh")
	_assert_true(mesh_property.get("ok", false), "Mesh property validates")
	_assert_eq(mesh_property.get("expected_class"), "Mesh", "Mesh property expected class")

	var box_mesh := BoxMesh.new()
	var compatibility_ok := ResourceLifecycleModel.validate_matches_property(mesh_property.get("property_info", {}), mesh_instance.mesh, box_mesh)
	_assert_eq(compatibility_ok.size(), 0, "BoxMesh compatible with mesh property")

	var material := StandardMaterial3D.new()
	var compatibility_bad := ResourceLifecycleModel.validate_matches_property(mesh_property.get("property_info", {}), mesh_instance.mesh, material)
	_assert_eq(compatibility_bad.get("code"), "resource_type_mismatch", "Material rejected for mesh property")

	var mesh_changes := ResourceLifecycleModel.prepare_property_changes(box_mesh, [
		{
			"property": "size",
			"value": {"x": 1.5, "y": 0.75, "z": 2.25},
		},
	], 4)
	_assert_true(mesh_changes.get("ok", false), "Mesh property changes prepare")
	var mesh_change: Dictionary = (mesh_changes.get("changes") as Array)[0]
	_assert_eq(mesh_change.get("new_value"), Vector3(1.5, 0.75, 2.25), "Mesh size coerces to Vector3")

	var material_property := ResourceLifecycleModel.validate_assignment_property(mesh_instance, "material_override")
	_assert_true(material_property.get("ok", false), "Material override validates")
	var material_candidates := ResourceLifecycleModel.expected_resource_class_candidates(material_property.get("property_info", {}), mesh_instance.material_override)
	_assert_true("BaseMaterial3D" in material_candidates or "Material" in material_candidates, "Material override has compatible expected class")
	var material_compatibility := ResourceLifecycleModel.validate_matches_property(material_property.get("property_info", {}), mesh_instance.material_override, material)
	_assert_eq(material_compatibility.size(), 0, "StandardMaterial3D compatible with material override")

	var material_changes := ResourceLifecycleModel.prepare_property_changes(material, [
		{
			"property": "albedo_color",
			"value": {"r": 0.2, "g": 0.3, "b": 0.4, "a": 0.5},
		},
		{
			"property": "roughness",
			"value": 0.75,
		},
	], 4)
	_assert_true(material_changes.get("ok", false), "Material property changes prepare")
	_assert_eq((material_changes.get("changes") as Array).size(), 2, "Material change count")

	var unsupported_property := ResourceLifecycleModel.validate_resource_property(material, "resource_path")
	_assert_eq(unsupported_property.get("code"), "unsupported_property", "Resource path edits rejected")

	var invalid_changes := ResourceLifecycleModel.prepare_property_changes(material, [
		{"property": "albedo_color", "value": "blue"},
	], 4)
	_assert_eq(invalid_changes.get("ok"), false, "Invalid material color rejects")

	var too_many_changes := ResourceLifecycleModel.prepare_property_changes(material, [
		{"property": "roughness", "value": 0.1},
		{"property": "metallic", "value": 0.2},
	], 1)
	_assert_eq((too_many_changes.get("error") as Dictionary).get("code"), "too_many_property_changes", "Too many changes rejected")

	mesh_instance.free()


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures += 1
		push_error(label + " expected=" + str(expected) + " actual=" + str(actual))


func _assert_true(value: bool, label: String) -> void:
	if not value:
		_failures += 1
		push_error(label)
