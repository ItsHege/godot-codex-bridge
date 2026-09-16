extends SceneTree

const ShaderMaterialModel := preload("res://addons/godot_codex_bridge/core/shader_material_model.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge shader material model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge shader material model tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	_assert_eq(ShaderMaterialModel.sanitize_parameter_name(" glow_strength "), "glow_strength", "Parameter names trim")
	_assert_eq(ShaderMaterialModel.sanitize_parameter_name("bad/name"), "", "Parameter names reject slashes")
	_assert_eq(ShaderMaterialModel.sanitize_parameter_name("bad\nname"), "", "Parameter names reject newlines")

	var float_value := ShaderMaterialModel.coerce_parameter_value({"type": TYPE_FLOAT}, 0.0, 1.25)
	_assert_true(float_value.get("ok", false), "Float coercion ok")
	_assert_float_near(float(float_value.get("value")), 1.25, "Float coercion value")

	var int_value := ShaderMaterialModel.coerce_parameter_value({"type": TYPE_INT}, 0, 4.9)
	_assert_true(int_value.get("ok", false), "Int coercion ok")
	_assert_eq(int_value.get("value"), 4, "Int coercion truncates")

	var vector4_value := ShaderMaterialModel.coerce_parameter_value({"type": TYPE_VECTOR4}, Vector4.ZERO, {"x": 1, "y": 2, "z": 3, "w": 4})
	_assert_true(vector4_value.get("ok", false), "Vector4 coercion ok")
	_assert_eq(vector4_value.get("value"), Vector4(1, 2, 3, 4), "Vector4 coercion value")

	var color_value := ShaderMaterialModel.coerce_parameter_value({"type": TYPE_COLOR}, Color.WHITE, [0.1, 0.2, 0.3])
	_assert_true(color_value.get("ok", false), "Color coercion ok")
	_assert_eq(color_value.get("value"), Color(0.1, 0.2, 0.3, 1.0), "Color coercion default alpha")

	var bad_bool := ShaderMaterialModel.coerce_parameter_value({"type": TYPE_BOOL}, false, "yes")
	_assert_eq(bad_bool.get("ok"), false, "Invalid bool rejects")
	_assert_eq((bad_bool.get("error") as Dictionary).get("code"), "invalid_shader_parameter_value", "Invalid bool code")

	var texture_ok := ShaderMaterialModel.texture_uniform_error({"type": TYPE_OBJECT, "hint_string": "sampler2D"})
	_assert_eq(texture_ok.size(), 0, "Sampler texture accepted")

	var texture_bad := ShaderMaterialModel.texture_uniform_error({"type": TYPE_FLOAT})
	_assert_eq(texture_bad.get("code"), "unsupported_shader_parameter_type", "Non-texture uniform rejected")

	var serialized := ShaderMaterialModel.serialized_parameter_changes([
		{
			"parameter": "clip_rect",
			"uniform_type": "Vector4",
			"old_value": Vector4.ZERO,
			"new_value": Vector4(1, 2, 3, 4),
		},
		{
			"parameter": "albedo_color",
			"uniform_type": "Color",
			"old_value": Color.WHITE,
			"new_value": Color(0.2, 0.3, 0.4, 0.5),
		},
	], 2, 8, 8)
	_assert_eq(serialized.size(), 2, "Serialized changes count")
	var first_change: Dictionary = serialized[0]
	_assert_eq((first_change.get("new_value") as Dictionary).get("x"), 1.0, "Serialized Vector4 x")
	var second_change: Dictionary = serialized[1]
	_assert_float_near(float((second_change.get("new_value") as Dictionary).get("a")), 0.5, "Serialized Color alpha")


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures += 1
		push_error(label + " expected=" + str(expected) + " actual=" + str(actual))


func _assert_float_near(actual: float, expected: float, label: String) -> void:
	if absf(actual - expected) > 0.0001:
		_failures += 1
		push_error(label + " expected=" + str(expected) + " actual=" + str(actual))


func _assert_true(value: bool, label: String) -> void:
	if not value:
		_failures += 1
		push_error(label)
