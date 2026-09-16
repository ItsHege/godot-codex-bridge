extends SceneTree

const SpatialBoundsModel := preload("res://addons/godot_codex_bridge/core/spatial_bounds_model.gd")
const BridgeContext := preload("res://addons/godot_codex_bridge/core/bridge_context.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge spatial bounds tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge spatial bounds tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var box_shape := BoxShape3D.new()
	box_shape.size = Vector3(2, 4, 6)
	var local_box := SpatialBoundsModel.local_aabb_for_collision_shape(box_shape)
	_assert_true(bool(local_box.get("ok", false)), "box collision shape produces bounds")
	_assert_eq(local_box.get("source"), "collision_shape_3d_box", "box bounds source")
	_assert_eq((local_box.get("aabb") as AABB).position, Vector3(-1, -2, -3), "box local position")
	_assert_eq((local_box.get("aabb") as AABB).size, Vector3(2, 4, 6), "box local size")

	var transform := Transform3D(Basis().scaled(Vector3(2, 1, 1)), Vector3(10, 1, 0))
	var world_box := SpatialBoundsModel.transform_aabb(local_box.get("aabb") as AABB, transform)
	_assert_eq(world_box.position, Vector3(8, -1, -3), "scaled world position")
	_assert_eq(world_box.size, Vector3(4, 4, 6), "scaled world size")

	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = 1.5
	var local_sphere := SpatialBoundsModel.local_aabb_for_collision_shape(sphere_shape)
	_assert_true(bool(local_sphere.get("ok", false)), "sphere collision shape produces bounds")
	_assert_eq((local_sphere.get("aabb") as AABB).position, Vector3(-1.5, -1.5, -1.5), "sphere local position")
	_assert_eq((local_sphere.get("aabb") as AABB).size, Vector3(3, 3, 3), "sphere local size")

	var node := Node3D.new()
	var root := Node3D.new()
	root.name = "Root"
	get_root().add_child(root)
	root.add_child(node)
	node.name = "House"
	node.add_to_group("buildings")
	_assert_eq(SpatialBoundsModel.scene_path_for(root, root), ".", "root scene path")
	_assert_eq(SpatialBoundsModel.scene_path_for(node, root), "House", "child scene path")

	var ground := CollisionShape3D.new()
	ground.name = "GroundPlane"
	var ground_shape := BoxShape3D.new()
	ground_shape.size = Vector3(20, 1, 20)
	ground.shape = ground_shape
	ground.position = Vector3(0, -0.5, 0)
	root.add_child(ground)

	var model := SpatialBoundsModel.new()
	var grouped: Dictionary = model.call("_group_scene_nodes", root, "buildings", 8)
	_assert_eq(int(grouped.get("requested_count", 0)), 1, "group requested count")
	_assert_eq((grouped.get("nodes", []) as Array).size(), 1, "group returned count")

	var detected_ground: Dictionary = model.call("_ground_reference", root, [node], 0.0, false)
	_assert_true(bool(detected_ground.get("detected", false)), "ground node detected")
	_assert_eq(detected_ground.get("mode"), "detected_node_top_plane", "ground detection mode")
	_assert_eq(detected_ground.get("y"), 0.0, "ground top y")

	var explicit_ground: Dictionary = model.call("_ground_reference", root, [node], -2.0, true)
	_assert_eq(explicit_ground.get("mode"), "explicit_world_y_plane", "explicit ground mode")
	_assert_eq(explicit_ground.get("y"), -2.0, "explicit ground y")

	var tilted_root := Node3D.new()
	tilted_root.name = "TiltedRoot"
	var tilted_ground := _box_node("TiltedGround", Vector3(20, 1, 20), Vector3.ZERO, "tilted_ground")
	tilted_ground.rotation_degrees = Vector3(0, 0, 15)
	tilted_root.add_child(tilted_ground)
	var tilted_target := _box_node("TiltedTarget", Vector3(2, 2, 2), Vector3(0, 3, 0), "tilted_targets")
	tilted_root.add_child(tilted_target)
	var tilted_ground_ref: Dictionary = model.call("_ground_reference", tilted_root, [tilted_target], 0.0, false)
	_assert_true(bool(tilted_ground_ref.get("surface_normal_available", false)), "tilted ground normal available")
	var tilted_normal := SpatialBoundsModel._vector3_from_payload(tilted_ground_ref.get("surface_normal", {}))
	_assert_true(absf(tilted_normal.x) > 0.01, "tilted ground normal has x component")
	_assert_true(tilted_normal.y > 0.9, "tilted ground normal faces up")
	var align_only_target := _box_node(
		"AlignOnlyTarget",
		Vector3(2, 2, 2),
		Vector3(0, float(tilted_ground_ref.get("y", 0.0)) + 1.0, 0),
		"tilted_targets"
	)
	tilted_root.add_child(align_only_target)
	var align_only_plan := model.call(
		"_snap_plan_for_node",
		align_only_target,
		tilted_root,
		float(tilted_ground_ref.get("y", 0.0)),
		0.05,
		false,
		1.0,
		Vector3.ZERO,
		true,
		tilted_normal
	) as Dictionary
	_assert_true(bool(align_only_plan.get("can_move", false)), "surface alignment-only snap plan can move")
	var align_only_surface := align_only_plan.get("align_to_surface", {}) as Dictionary
	_assert_true(bool(align_only_surface.get("applied", false)), "surface alignment applied")
	_assert_approx(float((align_only_plan.get("delta", {}) as Dictionary).get("y", 999.0)), 0.0, 0.001, "alignment-only keeps y delta zero")
	var align_after_basis := align_only_plan.get("after_global_basis", {}) as Dictionary
	var align_after_up := align_after_basis.get("y", {}) as Dictionary
	_assert_approx(float(align_after_up.get("x", 0.0)), tilted_normal.x, 0.001, "aligned basis up x matches surface normal")
	_assert_approx(float(align_after_up.get("y", 0.0)), tilted_normal.y, 0.001, "aligned basis up y matches surface normal")
	var fallback_align_plan := model.call(
		"_snap_plan_for_node",
		align_only_target,
		tilted_root,
		float(tilted_ground_ref.get("y", 0.0)),
		0.05,
		false,
		1.0,
		Vector3.ZERO,
		true,
		Vector3.UP,
		false
	) as Dictionary
	var fallback_align := fallback_align_plan.get("align_to_surface", {}) as Dictionary
	_assert_false(bool(fallback_align.get("available", true)), "fallback surface normal unavailable")
	_assert_false(bool(fallback_align.get("applied", true)), "fallback surface normal does not rotate")
	tilted_root.free()

	var grounded := _box_node("GroundedBox", Vector3(2, 2, 2), Vector3(0, 1, 0), "query_targets")
	var floating := _box_node("FloatingBox", Vector3(2, 2, 2), Vector3(4, 3, 0), "query_targets")
	var sunk := _box_node("SunkBox", Vector3(2, 2, 2), Vector3(8, 0.25, 0), "query_targets")
	var unmeasured := Node3D.new()
	unmeasured.name = "EmptyMarker"
	unmeasured.add_to_group("query_targets")
	root.add_child(grounded)
	root.add_child(floating)
	root.add_child(sunk)
	root.add_child(unmeasured)

	var gap_result: Dictionary = model.call("_ground_gap_query", root, {"group_name": "query_targets", "tolerance": 0.1})
	_assert_true(bool(gap_result.get("ok", false)), "ground gap query succeeds")
	var gap_data := gap_result.get("data", {}) as Dictionary
	var gap_counts := (gap_data.get("summary", {}) as Dictionary).get("counts", {}) as Dictionary
	_assert_eq(gap_counts.get("grounded"), 1, "grounded count")
	_assert_eq(gap_counts.get("floating"), 1, "floating count")
	_assert_eq(gap_counts.get("sunk"), 1, "sunk count")
	_assert_eq(gap_counts.get("no_bounds"), 1, "no-bounds count")

	var first_overlap := SpatialBoundsModel.aabb_overlap(AABB(Vector3.ZERO, Vector3(2, 2, 2)), AABB(Vector3(1, 0, 0), Vector3(2, 2, 2)))
	_assert_true(bool(first_overlap.get("overlaps", false)), "static overlap detects intersection")
	_assert_eq(first_overlap.get("volume"), 4.0, "static overlap volume")
	var no_overlap := SpatialBoundsModel.aabb_overlap(AABB(Vector3.ZERO, Vector3(1, 1, 1)), AABB(Vector3(2, 0, 0), Vector3(1, 1, 1)))
	_assert_false(bool(no_overlap.get("overlaps", true)), "static overlap ignores clear pairs")

	var overlap_a := _box_node("OverlapA", Vector3(2, 2, 2), Vector3(0, 1, 6), "overlap_targets")
	var overlap_b := _box_node("OverlapB", Vector3(2, 2, 2), Vector3(1, 1, 6), "overlap_targets")
	var overlap_clear := _box_node("OverlapClear", Vector3(2, 2, 2), Vector3(8, 1, 6), "overlap_targets")
	root.add_child(overlap_a)
	root.add_child(overlap_b)
	root.add_child(overlap_clear)

	var overlap_result: Dictionary = model.call("_aabb_overlap_query", root, {"group_name": "overlap_targets", "max_pairs": 8})
	_assert_true(bool(overlap_result.get("ok", false)), "aabb overlap query succeeds")
	var overlap_data := overlap_result.get("data", {}) as Dictionary
	var overlap_summary := overlap_data.get("summary", {}) as Dictionary
	_assert_eq(overlap_summary.get("checked_pairs"), 3, "overlap checked pairs")
	_assert_eq(overlap_summary.get("overlapping_pairs"), 1, "overlap pair count")
	_assert_eq((overlap_data.get("pairs", []) as Array).size(), 1, "overlap returned pairs")

	var raycast_result: Dictionary = model.call("_spatial_query_for_scene", root, {"query": "runtime_raycast"})
	_assert_false(bool(raycast_result.get("ok", true)), "runtime raycast unavailable")
	_assert_eq((raycast_result.get("error", {}) as Dictionary).get("code"), "spatial_query_unavailable", "runtime raycast unavailable code")

	var placement_grounded := _box_node("PlacementGrounded", Vector3(2, 2, 2), Vector3(20, 1, 0), "placement_targets")
	var placement_floating := _box_node("PlacementFloating", Vector3(2, 2, 2), Vector3(23.3, 3, 0), "placement_targets")
	var placement_sunk := _box_node("PlacementSunk", Vector3(2, 2, 2), Vector3(27, 0.25, 0), "placement_targets")
	var placement_a := _box_node("PlacementA", Vector3(2, 2, 2), Vector3(31, 1, 0), "placement_targets")
	var placement_b := _box_node("PlacementB", Vector3(2, 2, 2), Vector3(32, 1, 0), "placement_targets")
	var placement_empty := Node3D.new()
	placement_empty.name = "PlacementEmpty"
	placement_empty.add_to_group("placement_targets")
	root.add_child(placement_grounded)
	root.add_child(placement_floating)
	root.add_child(placement_sunk)
	root.add_child(placement_a)
	root.add_child(placement_b)
	root.add_child(placement_empty)

	var placement_result: Dictionary = model.call("_placement_check_for_scene", root, {
		"group_name": "placement_targets",
		"tolerance": 0.1,
		"grid_size": 1.0,
		"max_issues": 64,
	})
	_assert_true(bool(placement_result.get("ok", false)), "placement check succeeds")
	var placement_data := placement_result.get("data", {}) as Dictionary
	var placement_summary := placement_data.get("summary", {}) as Dictionary
	var placement_counts := placement_summary.get("counts", {}) as Dictionary
	_assert_eq(placement_summary.get("returned_count"), 6, "placement returned count")
	_assert_eq(placement_summary.get("bounded_node_count"), 5, "placement bounded count")
	_assert_eq(placement_summary.get("overlap_count"), 1, "placement overlap count")
	_assert_eq(placement_counts.get("floating"), 1, "placement floating count")
	_assert_eq(placement_counts.get("below_ground"), 1, "placement below-ground count")
	_assert_eq(placement_counts.get("clipping"), 2, "placement clipping issue count")
	_assert_eq(placement_counts.get("off_grid"), 1, "placement off-grid count")
	_assert_eq(placement_counts.get("unmeasured"), 1, "placement unmeasured count")
	var placement_items := placement_data.get("items", []) as Array
	_assert_eq(_status_for_item(placement_items, "PlacementGrounded"), "ok", "grounded placement ok")
	_assert_true(_issue_types_for(placement_items, "PlacementFloating").has("floating"), "floating issue present")
	_assert_true(_issue_types_for(placement_items, "PlacementFloating").has("off_grid"), "off-grid issue present")
	_assert_true(_issue_types_for(placement_items, "PlacementSunk").has("below_ground"), "below-ground issue present")
	_assert_true(_issue_types_for(placement_items, "PlacementA").has("clipping"), "clipping issue on first node")
	_assert_true(_issue_types_for(placement_items, "PlacementB").has("clipping"), "clipping issue on second node")
	_assert_eq(_status_for_item(placement_items, "PlacementEmpty"), "unmeasured", "empty placement unmeasured")

	var floating_item := _item_for_name(placement_items, "PlacementFloating")
	var floating_issue := _first_issue_of_type(floating_item, "floating")
	var floating_fix := floating_issue.get("suggested_fix", {}) as Dictionary
	var floating_delta := floating_fix.get("delta", {}) as Dictionary
	_assert_eq(floating_fix.get("action"), "snap_to_ground", "floating fix action")
	_assert_eq(float(floating_delta.get("y", 0.0)), -2.0, "floating fix delta y")

	var truncated_result: Dictionary = model.call("_placement_check_for_scene", root, {
		"group_name": "placement_targets",
		"max_nodes": 2,
	})
	var truncated_summary := ((truncated_result.get("data", {}) as Dictionary).get("summary", {}) as Dictionary)
	_assert_eq(truncated_summary.get("returned_count"), 2, "placement max nodes returned count")
	_assert_true(bool(truncated_summary.get("truncated", false)), "placement max nodes truncated")

	var snap_float := _box_node("SnapFloat", Vector3(2, 2, 2), Vector3(40.3, 3.0, 0.2), "snap_targets")
	var snap_grounded := _box_node("SnapGrounded", Vector3(2, 2, 2), Vector3(42.0, 1.0, 0.0), "snap_targets")
	var snap_sunk := _box_node("SnapSunk", Vector3(2, 2, 2), Vector3(44.0, 0.25, 0.0), "snap_targets")
	var snap_empty := Node3D.new()
	snap_empty.name = "SnapEmpty"
	snap_empty.add_to_group("snap_targets")
	root.add_child(snap_float)
	root.add_child(snap_grounded)
	root.add_child(snap_sunk)
	root.add_child(snap_empty)

	var snap_plan := model.call("_snap_plan_for_node", snap_float, root, 0.0, 0.05, true, 1.0, Vector3.ZERO) as Dictionary
	_assert_true(bool(snap_plan.get("can_move", false)), "floating snap plan can move")
	_assert_eq(snap_plan.get("status"), "will_move", "floating snap plan status")
	_assert_approx(float((snap_plan.get("after_global_position", {}) as Dictionary).get("x", 0.0)), 40.0, 0.001, "floating snap grid x")
	_assert_approx(float((snap_plan.get("after_global_position", {}) as Dictionary).get("y", 0.0)), 1.0, 0.001, "floating snap ground y")
	_assert_approx(float((snap_plan.get("after_global_position", {}) as Dictionary).get("z", 0.0)), 0.0, 0.001, "floating snap grid z")
	_assert_approx(float((snap_plan.get("ground_delta", {}) as Dictionary).get("y", 0.0)), -2.0, 0.001, "floating snap ground delta y")
	_assert_approx(float((snap_plan.get("grid_delta", {}) as Dictionary).get("x", 0.0)), -0.3, 0.001, "floating snap grid delta x")

	var grounded_snap_plan := model.call("_snap_plan_for_node", snap_grounded, root, 0.0, 0.05, false, 1.0, Vector3.ZERO) as Dictionary
	_assert_eq(grounded_snap_plan.get("status"), "skipped", "grounded snap skipped")
	_assert_eq(grounded_snap_plan.get("reason"), "already_snapped", "grounded snap reason")

	var sunk_snap_plan := model.call("_snap_plan_for_node", snap_sunk, root, 0.0, 0.05, false, 1.0, Vector3.ZERO) as Dictionary
	_assert_true(bool(sunk_snap_plan.get("can_move", false)), "sunk snap plan can move")
	_assert_approx(float((sunk_snap_plan.get("after_global_position", {}) as Dictionary).get("y", 0.0)), 1.0, 0.001, "sunk snap raises y")
	_assert_approx(float((sunk_snap_plan.get("ground_delta", {}) as Dictionary).get("y", 0.0)), 0.75, 0.001, "sunk snap ground delta y")

	var empty_snap_plan := model.call("_snap_plan_for_node", snap_empty, root, 0.0, 0.05, false, 1.0, Vector3.ZERO) as Dictionary
	_assert_eq(empty_snap_plan.get("status"), "skipped", "unmeasured snap skipped")
	_assert_eq(empty_snap_plan.get("reason"), "no_supported_bounds", "unmeasured snap reason")

	var grid_plan := model.call("_snap_grid_plan_for_node", snap_float, root, 0.05, 2.0, Vector3.ZERO, ["x", "z"]) as Dictionary
	_assert_true(bool(grid_plan.get("can_move", false)), "grid plan can move")
	_assert_approx(float((grid_plan.get("after_global_position", {}) as Dictionary).get("x", 0.0)), 40.0, 0.001, "grid plan x")
	_assert_approx(float((grid_plan.get("after_global_position", {}) as Dictionary).get("y", 0.0)), 3.0, 0.001, "grid plan keeps y")
	_assert_approx(float((grid_plan.get("after_global_position", {}) as Dictionary).get("z", 0.0)), 0.0, 0.001, "grid plan z")

	var broad_result: Dictionary = model.call("_snap_to_grid_for_scene", root, {"selected_only": false, "grid_size": 1.0})
	_assert_false(bool(broad_result.get("ok", true)), "broad scene snap rejected")
	_assert_eq((broad_result.get("error", {}) as Dictionary).get("code"), "broad_scene_mutation_rejected", "broad snap rejected code")

	var denied_context := BridgeContext.new()
	denied_context.permissions = {"allow_scene_edits": false}
	var denied_model := SpatialBoundsModel.new(denied_context)
	var denied_result := denied_model.snap_to_ground({})
	_assert_false(bool(denied_result.get("ok", true)), "permission disabled snap rejected")
	_assert_eq((denied_result.get("error", {}) as Dictionary).get("code"), "permission_denied", "permission denied code")
	root.free()


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


func _assert_approx(actual: float, expected: float, tolerance: float, label: String) -> void:
	if absf(actual - expected) > tolerance:
		_failures += 1
		push_error(label + " expected~=" + str(expected) + " actual=" + str(actual) + " tolerance=" + str(tolerance))


func _box_node(node_name: String, size: Vector3, position: Vector3, group_name: String) -> CollisionShape3D:
	var node := CollisionShape3D.new()
	node.name = node_name
	var shape := BoxShape3D.new()
	shape.size = size
	node.shape = shape
	node.position = position
	node.add_to_group(group_name)
	return node


func _item_for_name(items: Array, node_name: String) -> Dictionary:
	for item in items:
		var dictionary := item as Dictionary
		var node_ref := dictionary.get("node", {}) as Dictionary
		if str(node_ref.get("name", "")) == node_name:
			return dictionary
	return {}


func _status_for_item(items: Array, node_name: String) -> String:
	return str(_item_for_name(items, node_name).get("status", ""))


func _issue_types_for(items: Array, node_name: String) -> Array:
	var item := _item_for_name(items, node_name)
	var result: Array = []
	for issue in item.get("issues", []) as Array:
		var dictionary := issue as Dictionary
		result.append(str(dictionary.get("type", "")))
	return result


func _first_issue_of_type(item: Dictionary, issue_type: String) -> Dictionary:
	for issue in item.get("issues", []) as Array:
		var dictionary := issue as Dictionary
		if str(dictionary.get("type", "")) == issue_type:
			return dictionary
	return {}
