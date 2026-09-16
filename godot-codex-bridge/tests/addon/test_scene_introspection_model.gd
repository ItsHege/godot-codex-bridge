extends SceneTree

const BridgeContext := preload("res://addons/godot_codex_bridge/core/bridge_context.gd")
const SceneIntrospection := preload("res://addons/godot_codex_bridge/core/scene_introspection.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge scene introspection tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge scene introspection tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var ctx := BridgeContext.new()
	ctx.permissions = {"allow_editor_navigation": true}
	var introspection := SceneIntrospection.new(ctx)
	_assert_true(introspection != null, "scene introspection instantiates")
	_assert_true(introspection.has_method("collect_context_snapshot"), "scene introspection exposes snapshot collector")
	var vector_summary: Variant = introspection.call("_property_value_summary", Vector3(1, 2, 3))
	_assert_true(str(vector_summary).find("\"z\": 3.0") >= 0, "scene introspection has variant codec dependency")
	_assert_eq(introspection.call("_camera_projection_name", Camera3D.PROJECTION_PERSPECTIVE), "perspective", "camera projection helper works")


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures += 1
		push_error(label + " expected=" + str(expected) + " actual=" + str(actual))


func _assert_true(value: bool, label: String) -> void:
	if not value:
		_failures += 1
		push_error(label)
