@tool
extends RefCounted

const DEFAULT_MAX_STRING_LENGTH := 512
const DEFAULT_MAX_PROPERTY_DEPTH := 2
const DEFAULT_MAX_ARRAY_ITEMS := 12
const DEFAULT_MAX_DICTIONARY_ITEMS := 16


static func resource_reference(value: Variant) -> Variant:
	if value == null:
		return null
	if value is Resource:
		var resource := value as Resource
		return {
			"type": resource.get_class(),
			"resource_path": resource.resource_path,
			"resource_name": resource.resource_name,
		}
	if value is Object:
		return {
			"type": value.get_class(),
			"resource_path": "",
			"resource_name": "",
		}
	return null


static func resource_path_or_null(value: Variant) -> Variant:
	if value is Resource:
		var resource := value as Resource
		if resource.resource_path != "":
			return resource.resource_path
	return null


static func property_value_summary(
	value: Variant,
	max_string_length := DEFAULT_MAX_STRING_LENGTH,
	max_property_depth := DEFAULT_MAX_PROPERTY_DEPTH,
	max_array_items := DEFAULT_MAX_ARRAY_ITEMS,
	max_dictionary_items := DEFAULT_MAX_DICTIONARY_ITEMS
) -> Variant:
	if is_redacted_value(value):
		return "omitted: resource/object contents not expanded"

	match typeof(value):
		TYPE_NIL:
			return null
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT:
			return value
		TYPE_STRING:
			return truncate_string(str(value), max_string_length)
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			return truncate_string(str(value), max_string_length)
		TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_VECTOR3, TYPE_VECTOR3I, TYPE_VECTOR4, TYPE_VECTOR4I, TYPE_COLOR:
			return truncate_string(str(variant_to_json_value(value, 0, max_property_depth, max_array_items, max_dictionary_items)), max_string_length)
		_:
			return truncate_string(type_string(typeof(value)), max_string_length)


static func is_redacted_value(value: Variant) -> bool:
	return value is Object or typeof(value) in [
		TYPE_ARRAY,
		TYPE_DICTIONARY,
		TYPE_PACKED_BYTE_ARRAY,
		TYPE_PACKED_INT32_ARRAY,
		TYPE_PACKED_INT64_ARRAY,
		TYPE_PACKED_FLOAT32_ARRAY,
		TYPE_PACKED_FLOAT64_ARRAY,
		TYPE_PACKED_VECTOR2_ARRAY,
		TYPE_PACKED_VECTOR3_ARRAY,
		TYPE_PACKED_COLOR_ARRAY,
		TYPE_PACKED_STRING_ARRAY,
	]


static func omitted_reason_for(value: Variant) -> Variant:
	if value is Resource:
		return "unsupported_type"
	if value is Object:
		return "unsupported_type"
	match typeof(value):
		TYPE_ARRAY, TYPE_DICTIONARY:
			return "large_value"
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_STRING_ARRAY:
			return "large_value"
		_:
			return null


static func truncate_string(value: String, max_length := DEFAULT_MAX_STRING_LENGTH) -> String:
	if value.length() <= max_length:
		return value
	return value.substr(0, max_length)


static func variant_to_json_value(
	value: Variant,
	depth := 0,
	max_property_depth := DEFAULT_MAX_PROPERTY_DEPTH,
	max_array_items := DEFAULT_MAX_ARRAY_ITEMS,
	max_dictionary_items := DEFAULT_MAX_DICTIONARY_ITEMS
) -> Variant:
	match typeof(value):
		TYPE_NIL:
			return null
		TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return value
		TYPE_STRING_NAME, TYPE_NODE_PATH:
			return str(value)
		TYPE_VECTOR2:
			return {"x": value.x, "y": value.y}
		TYPE_VECTOR2I:
			return {"x": value.x, "y": value.y}
		TYPE_RECT2:
			return {"position": variant_to_json_value(value.position, depth + 1, max_property_depth, max_array_items, max_dictionary_items), "size": variant_to_json_value(value.size, depth + 1, max_property_depth, max_array_items, max_dictionary_items)}
		TYPE_RECT2I:
			return {"position": variant_to_json_value(value.position, depth + 1, max_property_depth, max_array_items, max_dictionary_items), "size": variant_to_json_value(value.size, depth + 1, max_property_depth, max_array_items, max_dictionary_items)}
		TYPE_VECTOR3:
			return {"x": value.x, "y": value.y, "z": value.z}
		TYPE_VECTOR3I:
			return {"x": value.x, "y": value.y, "z": value.z}
		TYPE_TRANSFORM2D:
			return {"x": variant_to_json_value(value.x, depth + 1, max_property_depth, max_array_items, max_dictionary_items), "y": variant_to_json_value(value.y, depth + 1, max_property_depth, max_array_items, max_dictionary_items), "origin": variant_to_json_value(value.origin, depth + 1, max_property_depth, max_array_items, max_dictionary_items)}
		TYPE_VECTOR4:
			return {"x": value.x, "y": value.y, "z": value.z, "w": value.w}
		TYPE_VECTOR4I:
			return {"x": value.x, "y": value.y, "z": value.z, "w": value.w}
		TYPE_PLANE:
			return {"normal": variant_to_json_value(value.normal, depth + 1, max_property_depth, max_array_items, max_dictionary_items), "d": value.d}
		TYPE_QUATERNION:
			return {"x": value.x, "y": value.y, "z": value.z, "w": value.w}
		TYPE_AABB:
			return {"position": variant_to_json_value(value.position, depth + 1, max_property_depth, max_array_items, max_dictionary_items), "size": variant_to_json_value(value.size, depth + 1, max_property_depth, max_array_items, max_dictionary_items)}
		TYPE_BASIS:
			return {"x": variant_to_json_value(value.x, depth + 1, max_property_depth, max_array_items, max_dictionary_items), "y": variant_to_json_value(value.y, depth + 1, max_property_depth, max_array_items, max_dictionary_items), "z": variant_to_json_value(value.z, depth + 1, max_property_depth, max_array_items, max_dictionary_items)}
		TYPE_TRANSFORM3D:
			return {"basis": variant_to_json_value(value.basis, depth + 1, max_property_depth, max_array_items, max_dictionary_items), "origin": variant_to_json_value(value.origin, depth + 1, max_property_depth, max_array_items, max_dictionary_items)}
		TYPE_PROJECTION:
			return str(value)
		TYPE_COLOR:
			return {"r": value.r, "g": value.g, "b": value.b, "a": value.a}
		TYPE_ARRAY:
			return array_to_json_summary(value, depth, max_property_depth, max_array_items, max_dictionary_items)
		TYPE_DICTIONARY:
			return dictionary_to_json_summary(value, depth, max_property_depth, max_array_items, max_dictionary_items)
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY:
			return {
				"type": type_string(typeof(value)),
				"size": value.size(),
				"sample": packed_array_sample(value, max_property_depth, max_array_items, max_dictionary_items),
				"truncated": value.size() > max_array_items,
			}
		TYPE_PACKED_STRING_ARRAY:
			return array_to_json_summary(Array(value), depth, max_property_depth, max_array_items, max_dictionary_items)
		TYPE_OBJECT:
			if value is Resource:
				return resource_reference(value)
			if value is Node:
				return {
					"type": value.get_class(),
					"scene_path": str(value.get_path()),
				}
			if value == null:
				return null
			return {
				"type": value.get_class(),
				"omitted": true,
			}
		_:
			return str(value)


static func array_to_json_summary(
	value: Array,
	depth: int,
	max_property_depth := DEFAULT_MAX_PROPERTY_DEPTH,
	max_array_items := DEFAULT_MAX_ARRAY_ITEMS,
	max_dictionary_items := DEFAULT_MAX_DICTIONARY_ITEMS
) -> Dictionary:
	if depth >= max_property_depth:
		return {
			"type": "Array",
			"size": value.size(),
			"truncated": true,
		}

	var sample: Array = []
	var count: int = min(value.size(), max_array_items)
	for index in range(count):
		sample.append(variant_to_json_value(value[index], depth + 1, max_property_depth, max_array_items, max_dictionary_items))

	return {
		"type": "Array",
		"size": value.size(),
		"sample": sample,
		"truncated": value.size() > max_array_items,
	}


static func dictionary_to_json_summary(
	value: Dictionary,
	depth: int,
	max_property_depth := DEFAULT_MAX_PROPERTY_DEPTH,
	max_array_items := DEFAULT_MAX_ARRAY_ITEMS,
	max_dictionary_items := DEFAULT_MAX_DICTIONARY_ITEMS
) -> Dictionary:
	if depth >= max_property_depth:
		return {
			"type": "Dictionary",
			"size": value.size(),
			"truncated": true,
		}

	var sample: Dictionary = {}
	var keys: Array = value.keys()
	var count: int = min(keys.size(), max_dictionary_items)
	for index in range(count):
		var key: Variant = keys[index]
		sample[str(key)] = variant_to_json_value(value[key], depth + 1, max_property_depth, max_array_items, max_dictionary_items)

	return {
		"type": "Dictionary",
		"size": value.size(),
		"sample": sample,
		"truncated": keys.size() > max_dictionary_items,
	}


static func packed_array_sample(
	value: Variant,
	max_property_depth := DEFAULT_MAX_PROPERTY_DEPTH,
	max_array_items := DEFAULT_MAX_ARRAY_ITEMS,
	max_dictionary_items := DEFAULT_MAX_DICTIONARY_ITEMS
) -> Array:
	var sample: Array = []
	var count: int = min(value.size(), max_array_items)
	for index in range(count):
		sample.append(variant_to_json_value(value[index], 0, max_property_depth, max_array_items, max_dictionary_items))
	return sample


static func coerce_editor_property_value(old_value: Variant, raw_value: Variant) -> Dictionary:
	match typeof(old_value):
		TYPE_BOOL:
			if typeof(raw_value) != TYPE_BOOL:
				return _err("invalid_property_value", "Expected boolean value.")
			return _ok({"value": raw_value})
		TYPE_INT:
			if typeof(raw_value) != TYPE_INT and typeof(raw_value) != TYPE_FLOAT:
				return _err("invalid_property_value", "Expected integer value.")
			return _ok({"value": int(raw_value)})
		TYPE_FLOAT:
			if typeof(raw_value) != TYPE_INT and typeof(raw_value) != TYPE_FLOAT:
				return _err("invalid_property_value", "Expected numeric value.")
			return _ok({"value": float(raw_value)})
		TYPE_STRING:
			if typeof(raw_value) != TYPE_STRING:
				return _err("invalid_property_value", "Expected string value.")
			return _ok({"value": str(raw_value)})
		TYPE_STRING_NAME:
			if typeof(raw_value) != TYPE_STRING:
				return _err("invalid_property_value", "Expected string value.")
			return _ok({"value": StringName(str(raw_value))})
		TYPE_NODE_PATH:
			if typeof(raw_value) != TYPE_STRING:
				return _err("invalid_property_value", "Expected NodePath string value.")
			return _ok({"value": NodePath(str(raw_value))})
		TYPE_VECTOR2:
			return vector2_from_payload(raw_value)
		TYPE_VECTOR3:
			return vector3_from_payload(raw_value)
		TYPE_COLOR:
			return color_from_payload(raw_value)
		_:
			return _err("unsupported_property_type", "Property type is not supported by V1 editor control: " + type_string(typeof(old_value)))


static func coerce_transform_value(old_value: Variant, raw_value: Variant, property_name: String, mode: String) -> Dictionary:
	var coerced := coerce_editor_property_value(old_value, raw_value)
	if not coerced.get("ok", false):
		return coerced
	var value: Variant = coerced_value(coerced)
	if mode == "absolute":
		return {"ok": true, "value": value}
	match typeof(old_value):
		TYPE_FLOAT:
			return {"ok": true, "value": float(old_value) + float(value)}
		TYPE_VECTOR2:
			if property_name == "scale":
				return {"ok": true, "value": Vector2(old_value.x * value.x, old_value.y * value.y)}
			return {"ok": true, "value": old_value + value}
		TYPE_VECTOR3:
			if property_name == "scale":
				return {"ok": true, "value": Vector3(old_value.x * value.x, old_value.y * value.y, old_value.z * value.z)}
			return {"ok": true, "value": old_value + value}
		_:
			return _err("unsupported_relative_transform", "Relative transform is not supported for " + type_string(typeof(old_value)))


static func vector2_from_payload(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		var dict: Dictionary = value
		if dict.has("x") and dict.has("y"):
			return {"ok": true, "value": Vector2(float(dict.get("x")), float(dict.get("y")))}
	if typeof(value) == TYPE_ARRAY and (value as Array).size() >= 2:
		var items: Array = value
		return {"ok": true, "value": Vector2(float(items[0]), float(items[1]))}
	return _err("invalid_vector2", "Expected Vector2 as {x,y} or [x,y].")


static func vector3_from_payload(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		var dict: Dictionary = value
		if dict.has("x") and dict.has("y") and dict.has("z"):
			return {"ok": true, "value": Vector3(float(dict.get("x")), float(dict.get("y")), float(dict.get("z")))}
	if typeof(value) == TYPE_ARRAY and (value as Array).size() >= 3:
		var items: Array = value
		return {"ok": true, "value": Vector3(float(items[0]), float(items[1]), float(items[2]))}
	return _err("invalid_vector3", "Expected Vector3 as {x,y,z} or [x,y,z].")


static func color_from_payload(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		var dict: Dictionary = value
		if dict.has("r") and dict.has("g") and dict.has("b"):
			return {"ok": true, "value": Color(float(dict.get("r")), float(dict.get("g")), float(dict.get("b")), float(dict.get("a", 1.0)))}
	return _err("invalid_color", "Expected Color as {r,g,b,a?}.")


static func coerced_value(result: Dictionary) -> Variant:
	if typeof(result.get("data")) == TYPE_DICTIONARY:
		return (result.get("data") as Dictionary).get("value")
	return result.get("value")


static func _ok(data: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"data": data,
	}


static func _err(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"error": {
			"code": code,
			"message": message,
		},
	}
