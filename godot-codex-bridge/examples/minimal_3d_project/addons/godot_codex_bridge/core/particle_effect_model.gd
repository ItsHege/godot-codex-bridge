@tool
extends RefCounted


static func create_draw_mesh(params: Dictionary) -> Dictionary:
	var draw_mesh_kind := str(params.get("draw_mesh", params.get("drawMesh", "quad"))).strip_edges().to_lower()
	if draw_mesh_kind == "none":
		return {"ok": true, "mesh": null, "kind": draw_mesh_kind}
	if draw_mesh_kind != "quad":
		return _error("unsupported_particle_draw_mesh", "create_particle_effect V1 supports drawMesh=quad or none.")
	var quad := QuadMesh.new()
	var draw_size := clampf(float(params.get("draw_size", params.get("drawSize", 0.35))), 0.01, 100.0)
	quad.size = Vector2(draw_size, draw_size)
	return {"ok": true, "mesh": quad, "kind": draw_mesh_kind}


static func prepare_create_node_changes(particle_node: GPUParticles3D, process_material: ParticleProcessMaterial, draw_mesh: Mesh, params: Dictionary) -> Dictionary:
	var changes: Array = []
	_append_property_change(particle_node, "amount", clampi(int(params.get("amount", 64)), 1, 10000), changes)
	_append_property_change(particle_node, "lifetime", clampf(float(params.get("lifetime", 1.5)), 0.05, 60.0), changes)
	_append_property_change(particle_node, "emitting", bool(params.get("emitting", true)), changes)
	_append_property_change(particle_node, "one_shot", bool(params.get("one_shot", params.get("oneShot", false))), changes)
	_append_property_change(particle_node, "explosiveness", clampf(float(params.get("explosiveness", 0.0)), 0.0, 1.0), changes)
	_append_property_change(particle_node, "randomness", clampf(float(params.get("randomness", 0.15)), 0.0, 1.0), changes)
	_append_property_change(particle_node, "speed_scale", clampf(float(params.get("speed_scale", params.get("speedScale", 1.0))), 0.0, 16.0), changes)
	_append_property_change(particle_node, "fixed_fps", clampi(int(params.get("fixed_fps", params.get("fixedFps", 30))), 1, 240), changes)
	_append_property_change(particle_node, "process_material", process_material, changes)
	if draw_mesh != null:
		_append_property_change(particle_node, "draw_passes", 1, changes)
		_append_property_change(particle_node, "draw_pass_1", draw_mesh, changes)
	var visibility_size := clampf(float(params.get("visibility_aabb_size", params.get("visibilityAabbSize", 8.0))), 0.1, 1000.0)
	var visibility_half := visibility_size * 0.5
	_append_property_change(particle_node, "visibility_aabb", AABB(Vector3(-visibility_half, -visibility_half, -visibility_half), Vector3(visibility_size, visibility_size, visibility_size)), changes)
	return {"ok": true, "changes": changes}


static func prepare_update_node_changes(node: GPUParticles3D, params: Dictionary) -> Dictionary:
	var changes: Array = []
	if _payload_has_any(params, ["amount"]):
		_append_property_change(node, "amount", clampi(int(params.get("amount")), 1, 10000), changes)
	if _payload_has_any(params, ["lifetime"]):
		_append_property_change(node, "lifetime", clampf(float(params.get("lifetime")), 0.05, 60.0), changes)
	if _payload_has_any(params, ["emitting"]):
		_append_property_change(node, "emitting", bool(params.get("emitting")), changes)
	if _payload_has_any(params, ["one_shot", "oneShot"]):
		_append_property_change(node, "one_shot", bool(params.get("one_shot", params.get("oneShot"))), changes)
	if _payload_has_any(params, ["explosiveness"]):
		_append_property_change(node, "explosiveness", clampf(float(params.get("explosiveness")), 0.0, 1.0), changes)
	if _payload_has_any(params, ["randomness"]):
		_append_property_change(node, "randomness", clampf(float(params.get("randomness")), 0.0, 1.0), changes)
	if _payload_has_any(params, ["speed_scale", "speedScale"]):
		_append_property_change(node, "speed_scale", clampf(float(params.get("speed_scale", params.get("speedScale"))), 0.0, 16.0), changes)
	if _payload_has_any(params, ["fixed_fps", "fixedFps"]):
		_append_property_change(node, "fixed_fps", clampi(int(params.get("fixed_fps", params.get("fixedFps"))), 1, 240), changes)
	if _payload_has_any(params, ["visibility_aabb_size", "visibilityAabbSize"]):
		var visibility_size := clampf(float(params.get("visibility_aabb_size", params.get("visibilityAabbSize"))), 0.1, 1000.0)
		var visibility_half := visibility_size * 0.5
		_append_property_change(node, "visibility_aabb", AABB(Vector3(-visibility_half, -visibility_half, -visibility_half), Vector3(visibility_size, visibility_size, visibility_size)), changes)
	return {"ok": true, "changes": changes}


static func has_process_material_update(params: Dictionary) -> bool:
	return _payload_has_any(params, [
		"direction",
		"gravity",
		"color",
		"spread",
		"initial_velocity_min",
		"initialVelocityMin",
		"initial_velocity_max",
		"initialVelocityMax",
		"particle_scale_min",
		"particleScaleMin",
		"particle_scale_max",
		"particleScaleMax",
	])


static func prepare_create_process_material_changes(process_material: ParticleProcessMaterial, params: Dictionary) -> Dictionary:
	var changes: Array = []
	var direction_value: Variant = _payload_get_any(params, ["direction"])
	if direction_value == null:
		direction_value = {"x": 0.0, "y": 1.0, "z": 0.0}
	var vector_result := _vector3_from_payload(direction_value)
	if not vector_result.get("ok", false):
		return _error("invalid_particle_direction", "direction must be a Vector3 payload.")
	_append_property_change(process_material, "direction", vector_result.get("value"), changes)

	var gravity_value: Variant = _payload_get_any(params, ["gravity"])
	if gravity_value == null:
		gravity_value = {"x": 0.0, "y": -2.0, "z": 0.0}
	vector_result = _vector3_from_payload(gravity_value)
	if not vector_result.get("ok", false):
		return _error("invalid_particle_gravity", "gravity must be a Vector3 payload.")
	_append_property_change(process_material, "gravity", vector_result.get("value"), changes)

	var color_value: Variant = _payload_get_any(params, ["color"])
	if color_value == null:
		color_value = {"r": 1.0, "g": 0.75, "b": 0.25, "a": 1.0}
	var color_result := _color_from_payload(color_value)
	if not color_result.get("ok", false):
		return _error("invalid_particle_color", "color must be a Color payload.")
	_append_property_change(process_material, "color", color_result.get("value"), changes)

	_append_property_change(process_material, "spread", clampf(float(params.get("spread", 35.0)), 0.0, 180.0), changes)
	_append_property_change(process_material, "initial_velocity_min", clampf(float(params.get("initial_velocity_min", params.get("initialVelocityMin", 0.8))), 0.0, 10000.0), changes)
	_append_property_change(process_material, "initial_velocity_max", clampf(float(params.get("initial_velocity_max", params.get("initialVelocityMax", 2.4))), 0.0, 10000.0), changes)
	_append_property_change(process_material, "scale_min", clampf(float(params.get("particle_scale_min", params.get("particleScaleMin", 0.15))), 0.0, 1000.0), changes)
	_append_property_change(process_material, "scale_max", clampf(float(params.get("particle_scale_max", params.get("particleScaleMax", 0.35))), 0.0, 1000.0), changes)
	return {"ok": true, "changes": changes}


static func prepare_update_process_material_changes(process_material: ParticleProcessMaterial, params: Dictionary) -> Dictionary:
	var changes: Array = []
	if _payload_has_any(params, ["direction"]):
		var vector_result := _vector3_from_payload(_payload_get_any(params, ["direction"]))
		if not vector_result.get("ok", false):
			return _error("invalid_particle_direction", "direction must be a Vector3 payload.")
		_append_property_change(process_material, "direction", vector_result.get("value"), changes)
	if _payload_has_any(params, ["gravity"]):
		var vector_result := _vector3_from_payload(_payload_get_any(params, ["gravity"]))
		if not vector_result.get("ok", false):
			return _error("invalid_particle_gravity", "gravity must be a Vector3 payload.")
		_append_property_change(process_material, "gravity", vector_result.get("value"), changes)
	if _payload_has_any(params, ["color"]):
		var color_result := _color_from_payload(_payload_get_any(params, ["color"]))
		if not color_result.get("ok", false):
			return _error("invalid_particle_color", "color must be a Color payload.")
		_append_property_change(process_material, "color", color_result.get("value"), changes)
	if _payload_has_any(params, ["spread"]):
		_append_property_change(process_material, "spread", clampf(float(params.get("spread")), 0.0, 180.0), changes)
	if _payload_has_any(params, ["initial_velocity_min", "initialVelocityMin"]):
		_append_property_change(process_material, "initial_velocity_min", clampf(float(params.get("initial_velocity_min", params.get("initialVelocityMin"))), 0.0, 10000.0), changes)
	if _payload_has_any(params, ["initial_velocity_max", "initialVelocityMax"]):
		_append_property_change(process_material, "initial_velocity_max", clampf(float(params.get("initial_velocity_max", params.get("initialVelocityMax"))), 0.0, 10000.0), changes)
	if _payload_has_any(params, ["particle_scale_min", "particleScaleMin"]):
		_append_property_change(process_material, "scale_min", clampf(float(params.get("particle_scale_min", params.get("particleScaleMin"))), 0.0, 1000.0), changes)
	if _payload_has_any(params, ["particle_scale_max", "particleScaleMax"]):
		_append_property_change(process_material, "scale_max", clampf(float(params.get("particle_scale_max", params.get("particleScaleMax"))), 0.0, 1000.0), changes)
	return {"ok": true, "changes": changes}


static func prepare_draw_mesh_update_changes(node: GPUParticles3D, params: Dictionary) -> Dictionary:
	var changes: Array = []
	var draw_mesh_requested := _payload_has_any(params, ["draw_mesh", "drawMesh"])
	var draw_size_requested := _payload_has_any(params, ["draw_size", "drawSize"])
	if not draw_mesh_requested and not draw_size_requested:
		return {"ok": true, "changes": changes}

	var draw_mesh_kind := str(params.get("draw_mesh", params.get("drawMesh", "quad"))).strip_edges().to_lower()
	if draw_mesh_kind == "unchanged":
		draw_mesh_kind = "quad" if draw_size_requested else ""
	if draw_mesh_kind == "none":
		_append_property_change(node, "draw_passes", 0, changes)
		return {"ok": true, "changes": changes}
	if draw_mesh_kind != "" and draw_mesh_kind != "quad":
		return _error("unsupported_particle_draw_mesh", "set_particle_effect_properties V1 supports drawMesh=quad, none or unchanged.")

	var draw_size := clampf(float(params.get("draw_size", params.get("drawSize", 0.35))), 0.01, 100.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(draw_size, draw_size)
	_append_property_change(node, "draw_passes", 1, changes)
	_append_property_change(node, "draw_pass_1", quad, changes)
	return {"ok": true, "changes": changes}


static func _append_property_change(object: Object, property_name: String, new_value: Variant, changes: Array) -> void:
	if object == null or _find_object_property_info(object, property_name).is_empty():
		return
	changes.append({
		"object": object,
		"property": property_name,
		"old_value": object.get(property_name),
		"new_value": new_value,
	})


static func _find_object_property_info(object: Object, property_name: String) -> Dictionary:
	if object == null:
		return {}
	for info in object.get_property_list():
		if typeof(info) != TYPE_DICTIONARY:
			continue
		var property_info := info as Dictionary
		if str(property_info.get("name", "")) == property_name:
			return property_info
	return {}


static func _payload_has_any(payload: Dictionary, keys: Array) -> bool:
	for key in keys:
		if payload.has(str(key)):
			return true
	return false


static func _payload_get_any(payload: Dictionary, keys: Array) -> Variant:
	for key in keys:
		if payload.has(str(key)):
			return payload.get(str(key))
	return null


static func _vector3_from_payload(value: Variant) -> Dictionary:
	if value is Vector3:
		return {"ok": true, "value": value}
	if value is Dictionary:
		var dict := value as Dictionary
		if dict.has("x") and dict.has("y") and dict.has("z"):
			return {"ok": true, "value": Vector3(float(dict.get("x")), float(dict.get("y")), float(dict.get("z")))}
	if value is Array and (value as Array).size() >= 3:
		var array := value as Array
		return {"ok": true, "value": Vector3(float(array[0]), float(array[1]), float(array[2]))}
	return _error("invalid_vector3", "Expected Vector3 as {x,y,z} or [x,y,z].")


static func _color_from_payload(value: Variant) -> Dictionary:
	if value is Color:
		return {"ok": true, "value": value}
	if value is Dictionary:
		var dict := value as Dictionary
		if dict.has("r") and dict.has("g") and dict.has("b"):
			return {"ok": true, "value": Color(float(dict.get("r")), float(dict.get("g")), float(dict.get("b")), float(dict.get("a", 1.0)))}
	if value is Array and (value as Array).size() >= 3:
		var array := value as Array
		var alpha := float(array[3]) if array.size() >= 4 else 1.0
		return {"ok": true, "value": Color(float(array[0]), float(array[1]), float(array[2]), alpha)}
	return _error("invalid_color", "Expected Color as {r,g,b,a?} or [r,g,b,a?].")


static func _error(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"error": {
			"code": code,
			"message": message,
		},
	}
