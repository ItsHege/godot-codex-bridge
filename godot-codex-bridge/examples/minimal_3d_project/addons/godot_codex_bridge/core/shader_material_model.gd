@tool
extends RefCounted

const VariantCodec := preload("variant_codec.gd")


static func sanitize_parameter_name(value: String) -> String:
	var parameter := value.strip_edges()
	if parameter.length() > 160 or parameter.find("\n") >= 0 or parameter.find("\r") >= 0 or parameter.find("/") >= 0 or parameter.find("\\") >= 0:
		return ""
	return parameter


static func find_uniform_info(shader: Shader, parameter_name: String) -> Dictionary:
	if shader == null:
		return _error("shader_missing", "A Shader is required to inspect uniforms.")
	var uniform_list := shader.get_shader_uniform_list(false)
	for uniform_value in uniform_list:
		if typeof(uniform_value) != TYPE_DICTIONARY:
			continue
		var uniform_info := uniform_value as Dictionary
		if str(uniform_info.get("name", "")) == parameter_name:
			return {
				"ok": true,
				"uniform_info": uniform_info,
			}
	return _error("shader_parameter_not_found", "Shader does not expose uniform parameter: " + parameter_name)


static func prepare_parameter_values(shader_material: ShaderMaterial, shader: Shader, raw_parameters: Variant, max_changes: int) -> Dictionary:
	if raw_parameters == null:
		return {"ok": true, "parameters": []}
	if typeof(raw_parameters) != TYPE_DICTIONARY:
		return _error("invalid_shader_parameters", "parameters must be an object keyed by shader uniform name.")
	if shader == null and not (raw_parameters as Dictionary).is_empty():
		return _error("shader_missing", "A shaderPath is required when initial shader parameters are provided.")
	var prepared: Array = []
	var parameters: Dictionary = raw_parameters
	if parameters.size() > max_changes:
		return _error("too_many_shader_parameters", "create_shader_material_for_node supports at most " + str(max_changes) + " initial parameters.")
	for key in parameters.keys():
		var parameter_name := sanitize_parameter_name(str(key))
		if parameter_name == "":
			return _error("invalid_shader_parameter", "Shader parameter name is invalid.")
		var uniform_result := find_uniform_info(shader, parameter_name)
		if not uniform_result.get("ok", false):
			return uniform_result
		var uniform_info: Dictionary = uniform_result.get("uniform_info", {})
		var old_value: Variant = shader_material.get_shader_parameter(StringName(parameter_name))
		var coercion := coerce_parameter_value(uniform_info, old_value, parameters.get(key))
		if not coercion.get("ok", false):
			return coercion
		prepared.append({
			"parameter": parameter_name,
			"old_value": old_value,
			"new_value": coercion.get("value"),
			"uniform_type": type_string(int(uniform_info.get("type", TYPE_NIL))),
		})
	return {
		"ok": true,
		"parameters": prepared,
	}


static func serialized_parameter_changes(changes: Array, max_property_depth: int, max_array_items: int, max_dictionary_items: int) -> Array:
	var serialized: Array = []
	for change in changes:
		if typeof(change) != TYPE_DICTIONARY:
			continue
		var change_dict := change as Dictionary
		serialized.append({
			"parameter": change_dict.get("parameter", ""),
			"uniform_type": change_dict.get("uniform_type", ""),
			"old_value": uniform_value_payload(change_dict.get("old_value"), max_property_depth, max_array_items, max_dictionary_items),
			"new_value": uniform_value_payload(change_dict.get("new_value"), max_property_depth, max_array_items, max_dictionary_items),
		})
	return serialized


static func uniform_value_payload(value: Variant, max_property_depth: int, max_array_items: int, max_dictionary_items: int) -> Variant:
	if value is Resource:
		return VariantCodec.resource_reference(value)
	if value is Object:
		return {
			"type": value.get_class(),
			"summary": "object value omitted",
		}
	return VariantCodec.variant_to_json_value(value, 0, max_property_depth, max_array_items, max_dictionary_items)


static func texture_uniform_error(uniform_info: Dictionary) -> Dictionary:
	var expected_type := int(uniform_info.get("type", TYPE_NIL))
	if expected_type != TYPE_OBJECT:
		return _error_payload("unsupported_shader_parameter_type", "Shader uniform is not a texture/resource parameter: " + type_string(expected_type))
	var hint_string := str(uniform_info.get("hint_string", "")).to_lower()
	if hint_string == "" or hint_string.find("texture") >= 0 or hint_string.find("sampler") >= 0:
		return {}
	return _error_payload("unsupported_shader_parameter_type", "Shader uniform resource type is not supported by Texture2D V1 assignment: " + str(uniform_info.get("hint_string", "")))


static func coerce_parameter_value(uniform_info: Dictionary, old_value: Variant, raw_value: Variant) -> Dictionary:
	var expected_type := int(uniform_info.get("type", TYPE_NIL))
	if expected_type == TYPE_NIL:
		expected_type = typeof(old_value)
	match expected_type:
		TYPE_BOOL:
			if typeof(raw_value) != TYPE_BOOL:
				return _error("invalid_shader_parameter_value", "Expected boolean shader parameter value.")
			return {"ok": true, "value": raw_value}
		TYPE_INT:
			if typeof(raw_value) != TYPE_INT and typeof(raw_value) != TYPE_FLOAT:
				return _error("invalid_shader_parameter_value", "Expected integer shader parameter value.")
			return {"ok": true, "value": int(raw_value)}
		TYPE_FLOAT:
			if typeof(raw_value) != TYPE_INT and typeof(raw_value) != TYPE_FLOAT:
				return _error("invalid_shader_parameter_value", "Expected numeric shader parameter value.")
			return {"ok": true, "value": float(raw_value)}
		TYPE_STRING, TYPE_STRING_NAME:
			if typeof(raw_value) != TYPE_STRING:
				return _error("invalid_shader_parameter_value", "Expected string shader parameter value.")
			return {"ok": true, "value": str(raw_value)}
		TYPE_VECTOR2:
			return _vector2_from_payload(raw_value)
		TYPE_VECTOR3:
			return _vector3_from_payload(raw_value)
		TYPE_VECTOR4:
			return _vector4_from_payload(raw_value)
		TYPE_COLOR:
			return _color_from_payload(raw_value)
		_:
			return _error("unsupported_shader_parameter_type", "Shader parameter type is not supported by V1 editor control: " + type_string(expected_type))


static func _vector2_from_payload(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		var dict: Dictionary = value
		if dict.has("x") and dict.has("y"):
			return {"ok": true, "value": Vector2(float(dict.get("x")), float(dict.get("y")))}
	if typeof(value) == TYPE_ARRAY and (value as Array).size() >= 2:
		var items: Array = value
		return {"ok": true, "value": Vector2(float(items[0]), float(items[1]))}
	return _error("invalid_vector2", "Expected Vector2 as {x,y} or [x,y].")


static func _vector3_from_payload(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		var dict: Dictionary = value
		if dict.has("x") and dict.has("y") and dict.has("z"):
			return {"ok": true, "value": Vector3(float(dict.get("x")), float(dict.get("y")), float(dict.get("z")))}
	if typeof(value) == TYPE_ARRAY and (value as Array).size() >= 3:
		var items: Array = value
		return {"ok": true, "value": Vector3(float(items[0]), float(items[1]), float(items[2]))}
	return _error("invalid_vector3", "Expected Vector3 as {x,y,z} or [x,y,z].")


static func _vector4_from_payload(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		var dict: Dictionary = value
		if dict.has("x") and dict.has("y") and dict.has("z") and dict.has("w"):
			return {"ok": true, "value": Vector4(float(dict.get("x")), float(dict.get("y")), float(dict.get("z")), float(dict.get("w")))}
	if typeof(value) == TYPE_ARRAY and (value as Array).size() >= 4:
		var items: Array = value
		return {"ok": true, "value": Vector4(float(items[0]), float(items[1]), float(items[2]), float(items[3]))}
	return _error("invalid_vector4", "Expected Vector4 as {x,y,z,w} or [x,y,z,w].")


static func _color_from_payload(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		var dict: Dictionary = value
		if dict.has("r") and dict.has("g") and dict.has("b"):
			return {"ok": true, "value": Color(float(dict.get("r")), float(dict.get("g")), float(dict.get("b")), float(dict.get("a", 1.0)))}
	if typeof(value) == TYPE_ARRAY and (value as Array).size() >= 3:
		var items: Array = value
		var alpha := float(items[3]) if items.size() >= 4 else 1.0
		return {"ok": true, "value": Color(float(items[0]), float(items[1]), float(items[2]), alpha)}
	return _error("invalid_color", "Expected Color as {r,g,b,a?} or [r,g,b,a?].")


static func _error(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"error": _error_payload(code, message),
	}


static func _error_payload(code: String, message: String) -> Dictionary:
	return {
		"code": code,
		"message": message,
	}
