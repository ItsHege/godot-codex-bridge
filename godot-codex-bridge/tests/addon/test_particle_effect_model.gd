extends SceneTree

const ParticleEffectModel := preload("res://addons/godot_codex_bridge/core/particle_effect_model.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge particle effect model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge particle effect model tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var draw_mesh_result := ParticleEffectModel.create_draw_mesh({"drawMesh": "quad", "drawSize": 0.5})
	_assert_true(draw_mesh_result.get("ok", false), "Quad draw mesh creates")
	_assert_true(draw_mesh_result.get("mesh") is QuadMesh, "Quad draw mesh type")
	_assert_eq((draw_mesh_result.get("mesh") as QuadMesh).size, Vector2(0.5, 0.5), "Quad draw mesh size")

	var bad_draw_mesh := ParticleEffectModel.create_draw_mesh({"drawMesh": "sphere"})
	_assert_eq(bad_draw_mesh.get("ok"), false, "Invalid draw mesh rejects")
	_assert_eq((bad_draw_mesh.get("error") as Dictionary).get("code"), "unsupported_particle_draw_mesh", "Invalid draw mesh code")

	var particles := GPUParticles3D.new()
	var material := ParticleProcessMaterial.new()
	var create_changes := ParticleEffectModel.prepare_create_node_changes(particles, material, draw_mesh_result.get("mesh"), {
		"amount": 12,
		"lifetime": 2.0,
		"visibilityAabbSize": 4.0,
	})
	_assert_true(create_changes.get("ok", false), "Create node changes ok")
	_assert_has_property(create_changes.get("changes") as Array, "amount", "Create changes include amount")
	_assert_has_property(create_changes.get("changes") as Array, "draw_pass_1", "Create changes include draw pass")

	var update_changes := ParticleEffectModel.prepare_update_node_changes(particles, {
		"amount": 24,
		"emitting": false,
	})
	_assert_true(update_changes.get("ok", false), "Update node changes ok")
	_assert_has_property(update_changes.get("changes") as Array, "amount", "Update changes include amount")
	_assert_has_property(update_changes.get("changes") as Array, "emitting", "Update changes include emitting")
	_assert_not_has_property(update_changes.get("changes") as Array, "lifetime", "Update changes omit absent lifetime")

	var material_changes := ParticleEffectModel.prepare_update_process_material_changes(material, {
		"color": {"r": 0.1, "g": 0.2, "b": 0.3, "a": 0.4},
		"direction": [0, 1, 0],
		"initialVelocityMin": 1.5,
	})
	_assert_true(material_changes.get("ok", false), "Material update changes ok")
	_assert_has_property(material_changes.get("changes") as Array, "color", "Material changes include color")
	_assert_has_property(material_changes.get("changes") as Array, "direction", "Material changes include direction")
	_assert_has_property(material_changes.get("changes") as Array, "initial_velocity_min", "Material changes include initial velocity")

	var bad_material_changes := ParticleEffectModel.prepare_update_process_material_changes(material, {
		"direction": {"x": 1, "y": 2},
	})
	_assert_eq(bad_material_changes.get("ok"), false, "Invalid direction rejects")
	_assert_eq((bad_material_changes.get("error") as Dictionary).get("code"), "invalid_particle_direction", "Invalid direction code")

	var draw_update := ParticleEffectModel.prepare_draw_mesh_update_changes(particles, {
		"drawMesh": "unchanged",
		"drawSize": 0.75,
	})
	_assert_true(draw_update.get("ok", false), "Draw update changes ok")
	_assert_has_property(draw_update.get("changes") as Array, "draw_pass_1", "Draw update changes include draw pass")
	particles.free()


func _assert_has_property(changes: Array, property_name: String, label: String) -> void:
	for change in changes:
		if typeof(change) == TYPE_DICTIONARY and str((change as Dictionary).get("property", "")) == property_name:
			return
	_failures += 1
	push_error(label + " expected property=" + property_name)


func _assert_not_has_property(changes: Array, property_name: String, label: String) -> void:
	for change in changes:
		if typeof(change) == TYPE_DICTIONARY and str((change as Dictionary).get("property", "")) == property_name:
			_failures += 1
			push_error(label + " unexpected property=" + property_name)
			return


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures += 1
		push_error(label + " expected=" + str(expected) + " actual=" + str(actual))


func _assert_true(value: bool, label: String) -> void:
	if not value:
		_failures += 1
		push_error(label)
