extends SceneTree

const MaterialDiagnosticsModel := preload("res://addons/godot_codex_bridge/core/material_diagnostics_model.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge material diagnostics model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge material diagnostics model tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var limits := {
		"max_materials_per_mesh": 8,
		"max_shader_uniforms": 8,
		"max_property_depth": 2,
		"max_array_items": 8,
		"max_dictionary_items": 8,
		"max_string_length": 256,
	}

	var root := Node3D.new()
	root.name = "Root"
	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "MeshNode"
	mesh_node.mesh = BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.2, 0.4, 0.6, 1.0)
	mesh_node.set_surface_override_material(0, material)
	root.add_child(mesh_node)

	_assert_eq(MaterialDiagnosticsModel.mesh_material_count(mesh_node), 1, "Mesh material override count")
	_assert_true(MaterialDiagnosticsModel.node_can_have_materials(mesh_node), "MeshInstance3D supports material diagnostics")
	_assert_eq(MaterialDiagnosticsModel.scene_path_for(mesh_node, root), "MeshNode", "Relative scene path")

	var targets: Array = []
	var collect_state := {"visited": 0, "truncated": false}
	MaterialDiagnosticsModel.collect_candidate_nodes(root, targets, collect_state, 8)
	_assert_true(mesh_node in targets, "Candidate traversal finds mesh node")
	_assert_true(int(collect_state.get("visited", 0)) >= 2, "Traversal records visited nodes")

	var stats := {"material_slots": 0, "shader_materials": 0, "shader_uniforms": 0}
	var unique_materials := {}
	var suggestions: Array = []
	var payload := MaterialDiagnosticsModel.node_materials_payload(mesh_node, root, true, false, 8, stats, unique_materials, suggestions, limits)
	_assert_eq(payload.get("material_slot_count"), 1, "Material payload slot count")
	_assert_eq(stats.get("material_slots"), 1, "Stats material slots")
	_assert_eq(unique_materials.size(), 1, "Unique material count")
	var slots: Array = payload.get("material_slots", [])
	_assert_eq((slots[0] as Dictionary).get("slot_kind"), "mesh_surface", "Slot kind")
	var material_payload: Dictionary = (slots[0] as Dictionary).get("material", {})
	_assert_eq(material_payload.get("type"), "StandardMaterial3D", "Material type payload")
	_assert_true((material_payload.get("common_properties") as Dictionary).has("albedo_color"), "Common material properties include albedo")

	var empty_node := MeshInstance3D.new()
	empty_node.name = "EmptyMesh"
	root.add_child(empty_node)
	var empty_suggestions: Array = []
	var empty_stats := {"material_slots": 0, "shader_materials": 0, "shader_uniforms": 0}
	var empty_payload := MaterialDiagnosticsModel.node_materials_payload(empty_node, root, false, false, 8, empty_stats, {}, empty_suggestions, limits)
	_assert_eq(empty_payload.get("material_slot_count"), 0, "Empty mesh has no returned slots")
	_assert_has_suggestion(empty_suggestions, "mesh_instance_without_mesh")

	var shader := Shader.new()
	shader.code = "shader_type spatial;\nuniform float glow_strength = 1.0;\nuniform vec4 tint = vec4(1.0);"
	var shader_material := ShaderMaterial.new()
	shader_material.shader = shader
	shader_material.set_shader_parameter(&"glow_strength", 2.5)
	var shader_stats := {"material_slots": 0, "shader_materials": 0, "shader_uniforms": 0}
	var shader_payload: Dictionary = MaterialDiagnosticsModel.material_diagnostic_payload(shader_material, true, shader_stats, {}, [], MaterialDiagnosticsModel.node_ref_payload(mesh_node, root), limits)
	_assert_eq(shader_payload.get("is_shader_material"), true, "Shader material flag")
	_assert_eq(shader_stats.get("shader_materials"), 1, "Shader material stats")
	var shader_details: Dictionary = shader_payload.get("shader_material", {})
	_assert_eq(shader_details.get("shader_missing"), false, "Shader present")
	_assert_true(int(shader_details.get("uniform_count", 0)) >= 1, "Shader uniforms captured")
	_assert_eq(shader_details.get("shader_mode"), "spatial", "Shader mode payload")

	root.free()


func _assert_has_suggestion(suggestions: Array, code: String) -> void:
	for item in suggestions:
		if typeof(item) == TYPE_DICTIONARY and str((item as Dictionary).get("code", "")) == code:
			return
	_failures += 1
	push_error("Expected suggestion code: " + code)


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures += 1
		push_error(label + " expected=" + str(expected) + " actual=" + str(actual))


func _assert_true(value: bool, label: String) -> void:
	if not value:
		_failures += 1
		push_error(label)
