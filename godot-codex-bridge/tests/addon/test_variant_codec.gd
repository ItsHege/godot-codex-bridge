extends SceneTree

const VariantCodec := preload("res://addons/godot_codex_bridge/core/variant_codec.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge variant codec tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge variant codec tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var vector_payload: Dictionary = VariantCodec.variant_to_json_value(Vector3(1.0, 2.5, -3.0))
	_assert_eq(vector_payload.get("x"), 1.0, "Vector3 x serializes")
	_assert_eq(vector_payload.get("y"), 2.5, "Vector3 y serializes")
	_assert_eq(vector_payload.get("z"), -3.0, "Vector3 z serializes")

	var color_payload: Dictionary = VariantCodec.variant_to_json_value(Color(0.1, 0.2, 0.3, 0.4))
	_assert_float_near(float(color_payload.get("a")), 0.4, "Color alpha serializes")

	var array_payload: Dictionary = VariantCodec.variant_to_json_value([1, 2, 3], 0, 2, 2, 16)
	_assert_eq(array_payload.get("type"), "Array", "Array summary type")
	_assert_eq(array_payload.get("size"), 3, "Array summary size")
	_assert_eq((array_payload.get("sample") as Array).size(), 2, "Array summary sample limit")
	_assert_eq(array_payload.get("truncated"), true, "Array summary truncation")

	var dict_payload: Dictionary = VariantCodec.variant_to_json_value({"a": 1, "b": 2, "c": 3}, 0, 2, 12, 2)
	_assert_eq(dict_payload.get("type"), "Dictionary", "Dictionary summary type")
	_assert_eq((dict_payload.get("sample") as Dictionary).size(), 2, "Dictionary summary sample limit")
	_assert_eq(dict_payload.get("truncated"), true, "Dictionary summary truncation")

	_assert_eq(VariantCodec.property_value_summary("abcdef", 3), "abc", "String summary truncates")
	_assert_eq(VariantCodec.property_value_summary([1, 2, 3]), "omitted: resource/object contents not expanded", "Array summary redacts")
	_assert_eq(VariantCodec.omitted_reason_for([1, 2, 3]), "large_value", "Array omitted reason")

	var resource := Resource.new()
	resource.resource_name = "CodecTest"
	var resource_ref: Dictionary = VariantCodec.resource_reference(resource)
	_assert_eq(resource_ref.get("type"), "Resource", "Resource reference type")
	_assert_eq(resource_ref.get("resource_name"), "CodecTest", "Resource reference name")

	var bool_coerce := VariantCodec.coerce_editor_property_value(false, true)
	_assert_eq(bool_coerce.get("ok"), true, "Bool coercion ok")
	_assert_eq(VariantCodec.coerced_value(bool_coerce), true, "Bool coercion value")

	var int_coerce := VariantCodec.coerce_editor_property_value(1, 2.9)
	_assert_eq(VariantCodec.coerced_value(int_coerce), 2, "Int coercion truncates numeric input")

	var string_name_coerce := VariantCodec.coerce_editor_property_value(StringName("old"), "new")
	_assert_eq(str(VariantCodec.coerced_value(string_name_coerce)), "new", "StringName coercion")

	var vector2_coerce := VariantCodec.coerce_editor_property_value(Vector2.ZERO, {"x": 4, "y": 5})
	_assert_eq(VariantCodec.coerced_value(vector2_coerce), Vector2(4, 5), "Vector2 object coercion")

	var vector3_coerce := VariantCodec.coerce_editor_property_value(Vector3.ZERO, [1, 2, 3])
	_assert_eq(VariantCodec.coerced_value(vector3_coerce), Vector3(1, 2, 3), "Vector3 array coercion")

	var color_coerce := VariantCodec.coerce_editor_property_value(Color.WHITE, {"r": 0.2, "g": 0.3, "b": 0.4})
	_assert_eq(VariantCodec.coerced_value(color_coerce), Color(0.2, 0.3, 0.4, 1.0), "Color coercion default alpha")

	var relative_move := VariantCodec.coerce_transform_value(Vector3(1, 2, 3), {"x": 3, "y": 2, "z": 1}, "position", "relative")
	_assert_eq(relative_move.get("value"), Vector3(4, 4, 4), "Relative Vector3 position adds")

	var relative_scale := VariantCodec.coerce_transform_value(Vector3(2, 3, 4), {"x": 2, "y": 2, "z": 0.5}, "scale", "relative")
	_assert_eq(relative_scale.get("value"), Vector3(4, 6, 2), "Relative Vector3 scale multiplies")

	var invalid_vector := VariantCodec.coerce_editor_property_value(Vector3.ZERO, {"x": 1, "y": 2})
	_assert_eq(invalid_vector.get("ok"), false, "Invalid Vector3 rejects")
	_assert_eq((invalid_vector.get("error") as Dictionary).get("code"), "invalid_vector3", "Invalid Vector3 error code")


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures += 1
		push_error(label + " expected=" + str(expected) + " actual=" + str(actual))


func _assert_float_near(actual: float, expected: float, label: String) -> void:
	if absf(actual - expected) > 0.0001:
		_failures += 1
		push_error(label + " expected=" + str(expected) + " actual=" + str(actual))
