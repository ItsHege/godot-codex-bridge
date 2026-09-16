@tool
extends RefCounted

const ShaderMaterialModel := preload("shader_material_model.gd")
const VariantCodec := preload("variant_codec.gd")


static func mesh_material_count(mesh_instance: MeshInstance3D) -> int:
	var count := 0
	for surface_index in range(mesh_instance.get_surface_override_material_count()):
		if mesh_instance.get_surface_override_material(surface_index) != null:
			count += 1
	return count


static func collect_candidate_nodes(node: Node, targets: Array, state: Dictionary, max_nodes: int) -> void:
	state["visited"] = int(state.get("visited", 0)) + 1
	if node_can_have_materials(node):
		targets.append(node)
		if targets.size() >= max_nodes:
			state["truncated"] = true
			return
	for child in node.get_children():
		if bool(state.get("truncated", false)):
			return
		if child is Node:
			collect_candidate_nodes(child as Node, targets, state, max_nodes)


static func node_can_have_materials(node: Node) -> bool:
	return node is CanvasItem or node is GeometryInstance3D or node is MeshInstance3D


static func node_materials_payload(
	node: Node,
	scene_root: Node,
	include_shader_params: bool,
	include_empty: bool,
	max_slots: int,
	stats: Dictionary,
	unique_materials: Dictionary,
	suggestions: Array,
	limits: Dictionary
) -> Dictionary:
	var max_materials_per_mesh := int(limits.get("max_materials_per_mesh", 24))
	var slots: Array = []
	var slots_truncated := false
	var node_ref := node_ref_payload(node, scene_root)
	var geometry_override_material: Variant = null

	if node is CanvasItem:
		var canvas_material: Variant = node.get("material")
		if include_empty or canvas_material != null:
			if slots.size() >= max_slots:
				slots_truncated = true
			else:
				slots.append(material_slot_payload(
					"canvas_item_material",
					null,
					canvas_material,
					include_shader_params,
					stats,
					unique_materials,
					suggestions,
					node_ref,
					{},
					limits
				))

	if node is GeometryInstance3D:
		geometry_override_material = node.get("material_override")
		if include_empty or geometry_override_material != null:
			if slots.size() >= max_slots:
				slots_truncated = true
			else:
				slots.append(material_slot_payload(
					"geometry_material_override",
					null,
					geometry_override_material,
					include_shader_params,
					stats,
					unique_materials,
					suggestions,
					node_ref,
					{"applies_to_all_surfaces": geometry_override_material != null},
					limits
				))

	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var mesh_value: Variant = mesh_instance.get("mesh")
		var mesh_resource := mesh_value as Mesh
		if mesh_resource == null:
			suggestions.append({
				"code": "mesh_instance_without_mesh",
				"severity": "warning",
				"node": node_ref,
				"message": "MeshInstance3D has no mesh, so no surface materials can be resolved.",
			})
		else:
			var surface_total := mesh_resource.get_surface_count()
			var surface_limit: int = min(surface_total, max_materials_per_mesh)
			if surface_total > max_materials_per_mesh:
				suggestions.append({
					"code": "mesh_surface_materials_truncated",
					"severity": "info",
					"node": node_ref,
					"surface_count": surface_total,
					"returned_surfaces": surface_limit,
					"message": "Mesh has more surfaces than the material diagnostics V1 limit.",
				})
			for surface_index in range(surface_limit):
				if slots.size() >= max_slots:
					slots_truncated = true
					break
				var active_material := mesh_instance.get_active_material(surface_index)
				var surface_override_material := mesh_instance.get_surface_override_material(surface_index)
				var mesh_surface_material := mesh_resource.surface_get_material(surface_index)
				if include_empty or active_material != null or surface_override_material != null or mesh_surface_material != null:
					var source := "none"
					if geometry_override_material != null:
						source = "geometry_material_override"
					elif surface_override_material != null:
						source = "surface_override"
					elif mesh_surface_material != null:
						source = "mesh_surface"
					slots.append(material_slot_payload(
						"mesh_surface",
						surface_index,
						active_material,
						include_shader_params,
						stats,
						unique_materials,
						suggestions,
						node_ref,
						{
							"source": source,
							"surface_override_material": VariantCodec.resource_reference(surface_override_material),
							"mesh_surface_material": VariantCodec.resource_reference(mesh_surface_material),
							"mesh": VariantCodec.resource_reference(mesh_resource),
						},
						limits
					))

	if slots.is_empty() and node_can_have_materials(node):
		suggestions.append({
			"code": "node_has_no_materials",
			"severity": "info",
			"node": node_ref,
			"message": "Node can expose material slots, but none are currently assigned or effective.",
		})

	return {
		"node": node_ref,
		"class": node.get_class(),
		"material_slots": slots,
		"material_slot_count": slots.size(),
		"slots_truncated": slots_truncated,
	}


static func material_slot_payload(
	slot_kind: String,
	surface_index: Variant,
	material_value: Variant,
	include_shader_params: bool,
	stats: Dictionary,
	unique_materials: Dictionary,
	suggestions: Array,
	node_ref: Dictionary,
	extra: Dictionary,
	limits: Dictionary
) -> Dictionary:
	stats["material_slots"] = int(stats.get("material_slots", 0)) + 1
	var material_payload: Variant = material_diagnostic_payload(material_value, include_shader_params, stats, unique_materials, suggestions, node_ref, limits)
	var slot: Dictionary = {
		"slot_kind": slot_kind,
		"surface_index": surface_index,
		"material": material_payload,
		"material_missing": material_value == null,
	}
	for key in extra.keys():
		slot[key] = extra[key]
	if material_value == null:
		suggestions.append({
			"code": "material_slot_empty",
			"severity": "info",
			"node": node_ref,
			"slot_kind": slot_kind,
			"surface_index": surface_index,
			"message": "Material slot is empty.",
		})
	return slot


static func material_diagnostic_payload(
	value: Variant,
	include_shader_params: bool,
	stats: Dictionary,
	unique_materials: Dictionary,
	suggestions: Array,
	node_ref: Dictionary,
	limits: Dictionary
) -> Variant:
	if value == null:
		return null
	if not (value is Material):
		return VariantCodec.resource_reference(value)
	var material := value as Material
	var key := material_unique_key(material)
	unique_materials[key] = true
	var payload := {
		"type": material.get_class(),
		"resource_path": material.resource_path,
		"resource_name": material.resource_name,
		"resource_local_to_scene": bool(material.get("resource_local_to_scene")) if property_exists(material, "resource_local_to_scene") else null,
		"common_properties": material_common_properties_payload(material, limits),
		"is_shader_material": material is ShaderMaterial,
	}
	if material.resource_path == "":
		payload["storage"] = "local_or_unsaved_subresource"
	else:
		payload["storage"] = "resource_file"
	if material is ShaderMaterial:
		stats["shader_materials"] = int(stats.get("shader_materials", 0)) + 1
		payload["shader_material"] = shader_material_diagnostics_payload(material as ShaderMaterial, include_shader_params, stats, suggestions, node_ref, limits)
	return payload


static func material_unique_key(material: Material) -> String:
	if material.resource_path != "":
		return "path:" + material.resource_path
	return "instance:" + str(material.get_instance_id())


static func material_common_properties_payload(material: Material, limits: Dictionary) -> Dictionary:
	var payload := {}
	var names := [
		"albedo_color",
		"metallic",
		"roughness",
		"transparency",
		"shading_mode",
		"cull_mode",
		"vertex_color_use_as_albedo",
		"disable_receive_shadows",
	]
	var max_property_depth := int(limits.get("max_property_depth", VariantCodec.DEFAULT_MAX_PROPERTY_DEPTH))
	var max_array_items := int(limits.get("max_array_items", VariantCodec.DEFAULT_MAX_ARRAY_ITEMS))
	var max_dictionary_items := int(limits.get("max_dictionary_items", VariantCodec.DEFAULT_MAX_DICTIONARY_ITEMS))
	for property_name in names:
		if property_exists(material, property_name):
			payload[property_name] = VariantCodec.variant_to_json_value(material.get(property_name), 0, max_property_depth, max_array_items, max_dictionary_items)
	return payload


static func shader_material_diagnostics_payload(
	shader_material: ShaderMaterial,
	include_shader_params: bool,
	stats: Dictionary,
	suggestions: Array,
	node_ref: Dictionary,
	limits: Dictionary
) -> Dictionary:
	var shader_value: Variant = shader_material.get("shader")
	var shader := shader_value as Shader
	if shader == null:
		suggestions.append({
			"code": "shader_material_without_shader",
			"severity": "warning",
			"node": node_ref,
			"material": VariantCodec.resource_reference(shader_material),
			"message": "ShaderMaterial has no Shader assigned.",
		})
		return {
			"shader": null,
			"shader_missing": true,
			"uniforms": [],
			"uniforms_truncated": false,
		}

	var max_shader_uniforms := int(limits.get("max_shader_uniforms", 32))
	var max_string_length := int(limits.get("max_string_length", VariantCodec.DEFAULT_MAX_STRING_LENGTH))
	var max_property_depth := int(limits.get("max_property_depth", VariantCodec.DEFAULT_MAX_PROPERTY_DEPTH))
	var max_array_items := int(limits.get("max_array_items", VariantCodec.DEFAULT_MAX_ARRAY_ITEMS))
	var max_dictionary_items := int(limits.get("max_dictionary_items", VariantCodec.DEFAULT_MAX_DICTIONARY_ITEMS))
	var code := str(shader.get("code"))
	if code.strip_edges() == "":
		suggestions.append({
			"code": "shader_code_empty",
			"severity": "warning",
			"node": node_ref,
			"shader": VariantCodec.resource_reference(shader),
			"message": "Shader has empty code.",
		})
	var uniforms: Array = []
	var uniforms_truncated := false
	if include_shader_params:
		var uniform_list := shader.get_shader_uniform_list(false)
		var count: int = min(uniform_list.size(), max_shader_uniforms)
		for index in range(count):
			var uniform_info: Dictionary = uniform_list[index] as Dictionary
			var uniform_name := str(uniform_info.get("name", ""))
			if uniform_name == "":
				continue
			var value: Variant = shader_material.get_shader_parameter(StringName(uniform_name))
			uniforms.append({
				"name": uniform_name,
				"type": type_string(int(uniform_info.get("type", TYPE_NIL))),
				"hint": int(uniform_info.get("hint", 0)),
				"usage": int(uniform_info.get("usage", 0)),
				"hint_string": VariantCodec.truncate_string(str(uniform_info.get("hint_string", "")), max_string_length),
				"value": ShaderMaterialModel.uniform_value_payload(value, max_property_depth, max_array_items, max_dictionary_items),
				"value_type": type_string(typeof(value)),
			})
			stats["shader_uniforms"] = int(stats.get("shader_uniforms", 0)) + 1
		uniforms_truncated = uniform_list.size() > max_shader_uniforms
		if uniforms_truncated:
			suggestions.append({
				"code": "shader_uniforms_truncated",
				"severity": "info",
				"node": node_ref,
				"shader": VariantCodec.resource_reference(shader),
				"uniform_count": uniform_list.size(),
				"returned_uniforms": max_shader_uniforms,
				"message": "Shader has more uniforms than the diagnostics V1 limit.",
			})

	return {
		"shader": VariantCodec.resource_reference(shader),
		"shader_missing": false,
		"shader_mode": shader_mode_name(shader.get_mode()),
		"code_length": code.length(),
		"code_preview": VariantCodec.truncate_string(code.strip_edges(), 300),
		"uniforms": uniforms,
		"uniform_count": uniforms.size(),
		"uniforms_truncated": uniforms_truncated,
	}


static func node_ref_payload(node: Node, scene_root: Node) -> Dictionary:
	return {
		"path": scene_path_for(node, scene_root),
		"name": node.name,
		"type": node.get_class(),
	}


static func scene_path_for(node: Node, scene_root: Node) -> String:
	if node == null:
		return ""
	if scene_root == null:
		return str(node.get_path())
	if node == scene_root:
		return "."
	if scene_root.is_ancestor_of(node):
		return str(scene_root.get_path_to(node))
	return str(node.get_path())


static func shader_mode_name(mode: int) -> String:
	match mode:
		Shader.MODE_SPATIAL:
			return "spatial"
		Shader.MODE_CANVAS_ITEM:
			return "canvas_item"
		Shader.MODE_PARTICLES:
			return "particles"
		Shader.MODE_SKY:
			return "sky"
		Shader.MODE_FOG:
			return "fog"
		5:
			return "texture_blit"
		_:
			return "unknown"


static func property_exists(object: Object, property_name: String) -> bool:
	for property_info in object.get_property_list():
		if typeof(property_info) == TYPE_DICTIONARY and str((property_info as Dictionary).get("name", "")) == property_name:
			return true
	return false
