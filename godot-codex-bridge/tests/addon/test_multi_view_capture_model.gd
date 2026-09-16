extends SceneTree

const BridgeContext := preload("res://addons/godot_codex_bridge/core/bridge_context.gd")
const MultiViewCaptureModel := preload("res://addons/godot_codex_bridge/core/multi_view_capture_model.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge multi-view capture model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge multi-view capture model tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var model := MultiViewCaptureModel.new()

	var views := model.call("_requested_views", {"views": ["front", "top", "front", "side"]}) as Array
	_assert_eq(views, ["front", "top", "side"], "requested views dedupe in order")

	var fallback_views := model.call("_requested_views", {"views": ["bad"]}) as Array
	_assert_eq(fallback_views, ["front", "side", "top", "perspective"], "invalid view list falls back to defaults")

	var root := Node3D.new()
	root.name = "Root"
	get_root().add_child(root)

	var target := Node3D.new()
	target.name = "House"
	root.add_child(target)
	target.add_child(_box_shape_node("HouseShape", Vector3(2, 4, 6), Vector3(0, 0, 0)))
	target.add_child(_box_shape_node("ChimneyShape", Vector3(1, 2, 1), Vector3(0, 3, 0)))

	var bounds := model.call("_bounds_for_targets", root, [target], 32) as Dictionary
	_assert_true(bool(bounds.get("ok", false)), "combined target bounds ok")
	var aabb := bounds.get("aabb", AABB()) as AABB
	_assert_eq(aabb.position, Vector3(-1, -2, -3), "combined bounds position")
	_assert_eq(aabb.size, Vector3(2, 6, 6), "combined bounds size includes child")
	_assert_eq(bounds.get("source"), "node3d_descendant_bounds", "combined bounds source")

	var front_plan := model.call("_camera_plan_for_view", aabb, "front", 1.333) as Dictionary
	_assert_true(bool(front_plan.get("orthogonal", false)), "front is orthographic")
	var front_transform := front_plan.get("transform", Transform3D()) as Transform3D
	_assert_true(front_transform.origin.z > aabb.get_center().z, "front camera is in front of bounds")
	_assert_true(float(front_plan.get("size", 0.0)) >= 8.1, "front ortho size covers largest extent")

	var top_plan := model.call("_camera_plan_for_view", aabb, "top", 1.333) as Dictionary
	_assert_true(bool(top_plan.get("orthogonal", false)), "top is orthographic")
	var top_transform := top_plan.get("transform", Transform3D()) as Transform3D
	_assert_true(top_transform.origin.y > aabb.get_center().y, "top camera is above bounds")

	var perspective_plan := model.call("_camera_plan_for_view", aabb, "perspective", 1.333) as Dictionary
	_assert_false(bool(perspective_plan.get("orthogonal", true)), "perspective is perspective")
	_assert_true(float(perspective_plan.get("far", 0.0)) >= 100.0, "perspective far plane bounded")

	var denied_context := BridgeContext.new()
	denied_context.permissions = {"allow_screenshots": false}
	var denied_model := MultiViewCaptureModel.new(denied_context)
	var denied := denied_model.capture_multi_view({})
	_assert_false(bool(denied.get("ok", true)), "permission gate rejects capture")
	_assert_eq((denied.get("error", {}) as Dictionary).get("code"), "permission_denied", "permission denied code")

	root.queue_free()


func _box_node(node_name: String, size: Vector3, position: Vector3) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	node.position = position
	node.add_child(_box_shape_node(node_name + "Shape", size, Vector3.ZERO))
	return node


func _box_shape_node(node_name: String, size: Vector3, position: Vector3) -> CollisionShape3D:
	var collision := CollisionShape3D.new()
	collision.name = node_name
	collision.position = position
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	return collision


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures += 1
		push_error(label + " expected=" + str(expected) + " actual=" + str(actual))


func _assert_true(value: bool, label: String) -> void:
	if not value:
		_failures += 1
		push_error(label)


func _assert_false(value: bool, label: String) -> void:
	if value:
		_failures += 1
		push_error(label)
