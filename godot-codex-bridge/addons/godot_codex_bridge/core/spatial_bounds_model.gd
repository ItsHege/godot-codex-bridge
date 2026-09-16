@tool
extends RefCounted

const BridgeContext := preload("bridge_context.gd")
const EditorPathGuard := preload("editor_path_guard.gd")
const VariantCodec := preload("variant_codec.gd")

const DEFAULT_MAX_NODES := 24
const HARD_MAX_NODES := 96
const DEFAULT_GROUND_TOLERANCE := 0.05
const DEFAULT_GRID_SIZE := 1.0
const DEFAULT_MAX_ISSUES := 128
const HARD_MAX_ISSUES := 512
const DEFAULT_MAX_PAIRS := 128
const HARD_MAX_PAIRS := 512
const PLACEMENT_CHECKS := ["ground_gap", "overlap", "grid"]

var _context: BridgeContext


func _init(context: BridgeContext = null) -> void:
	_context = context


func get_spatial_bounds(params: Dictionary) -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return _err("no_current_scene", "No edited scene is open.")

	var max_nodes := _bounded_int(params.get("max_nodes", params.get("maxNodes", DEFAULT_MAX_NODES)), DEFAULT_MAX_NODES, 1, HARD_MAX_NODES)
	var ground_y := _bounded_float(params.get("ground_y", params.get("groundY", 0.0)), 0.0, -100000.0, 100000.0)
	var has_explicit_ground_y := params.has("ground_y") or params.has("groundY")
	var node_path := str(params.get("node_path", params.get("nodePath", ""))).strip_edges()
	var group_name := str(params.get("group_name", params.get("groupName", ""))).strip_edges()
	var selected_only := bool(params.get("selected_only", params.get("selectedOnly", node_path == "")))

	var targets_result := _collect_targets(scene_root, node_path, group_name, selected_only, max_nodes)
	if not targets_result.get("ok", false):
		return targets_result

	var targets: Array = targets_result.get("targets", [])
	var ground_reference := _ground_reference(scene_root, targets, ground_y, has_explicit_ground_y)
	var resolved_ground_y := float(ground_reference.get("y", ground_y))
	var nodes: Array = []
	var with_bounds := 0
	for item in targets:
		if item is Node:
			var payload := _node_spatial_payload(item as Node, scene_root, resolved_ground_y)
			if bool(payload.get("has_bounds", false)):
				with_bounds += 1
			nodes.append(payload)

	return _ok({
		"action": "get_spatial_bounds",
		"status": "succeeded",
		"current_scene": _current_scene_payload(scene_root),
		"mode": str(targets_result.get("mode", "unknown")),
		"ground_reference": ground_reference,
		"nodes": nodes,
		"summary": {
			"requested_count": int(targets_result.get("requested_count", targets.size())),
			"returned_count": nodes.size(),
			"nodes_with_bounds": with_bounds,
			"nodes_without_bounds": nodes.size() - with_bounds,
			"max_nodes": max_nodes,
			"truncated": bool(targets_result.get("truncated", false)),
		},
		"snapshot_refreshed": false,
	})


func spatial_query(params: Dictionary) -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return _err("no_current_scene", "No edited scene is open.")
	return _spatial_query_for_scene(scene_root, params)


func placement_check(params: Dictionary) -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return _err("no_current_scene", "No edited scene is open.")
	return _placement_check_for_scene(scene_root, params)


func snap_to_ground(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_scene_edits"):
		return _err("permission_denied", "Scene edits via UndoRedo permission is disabled in the Codex Bridge dock.")
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return _err("no_current_scene", "No edited scene is open.")
	return _snap_to_ground_for_scene(scene_root, params)


func snap_to_grid(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_scene_edits"):
		return _err("permission_denied", "Scene edits via UndoRedo permission is disabled in the Codex Bridge dock.")
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return _err("no_current_scene", "No edited scene is open.")
	return _snap_to_grid_for_scene(scene_root, params)


func _spatial_query_for_scene(scene_root: Node, params: Dictionary) -> Dictionary:
	var query := str(params.get("query", params.get("query_type", params.get("queryType", "ground_gap")))).strip_edges().to_lower()
	match query:
		"ground_gap":
			return _ground_gap_query(scene_root, params)
		"aabb_overlap":
			return _aabb_overlap_query(scene_root, params)
		"runtime_raycast", "raycast":
			return _err(
				"spatial_query_unavailable",
				"Runtime physics raycast is not available from the edited scene. Use geometric queries in the editor, or a later runtime playtest/raycast flow."
			)
		_:
			return _err("invalid_spatial_query", "Spatial query must be ground_gap, aabb_overlap or runtime_raycast.")


func _placement_check_for_scene(scene_root: Node, params: Dictionary) -> Dictionary:
	var selection := _spatial_selection(scene_root, params)
	if not bool(selection.get("ok", false)):
		return selection

	var targets: Array = selection.get("targets", [])
	var ground_reference: Dictionary = selection.get("ground_reference", {})
	var ground_y := float(ground_reference.get("y", 0.0))
	var tolerance := _bounded_float(params.get("tolerance", DEFAULT_GROUND_TOLERANCE), DEFAULT_GROUND_TOLERANCE, 0.0, 1000.0)
	var has_grid_size := params.has("grid_size") or params.has("gridSize")
	var grid_size := _bounded_float(params.get("grid_size", params.get("gridSize", 0.0)), 0.0, 0.0, 100000.0)
	var max_issues := _bounded_int(params.get("max_issues", params.get("maxIssues", DEFAULT_MAX_ISSUES)), DEFAULT_MAX_ISSUES, 1, HARD_MAX_ISSUES)
	var max_pairs := _bounded_int(params.get("max_pairs", params.get("maxPairs", DEFAULT_MAX_PAIRS)), DEFAULT_MAX_PAIRS, 1, HARD_MAX_PAIRS)
	var checks := _placement_checks(params.get("checks", PLACEMENT_CHECKS))
	var grid_origin := _grid_origin(params.get("grid_origin", params.get("gridOrigin", {})))

	var items: Array = []
	var issues: Array = []
	var bounded_items: Array = []
	var issue_count := 0
	var ok_count := 0
	var unmeasured_count := 0
	var counts := {
		"floating": 0,
		"below_ground": 0,
		"clipping": 0,
		"off_grid": 0,
		"unmeasured": 0,
	}
	for target in targets:
		if not (target is Node):
			continue
		var spatial := _node_spatial_payload(target as Node, scene_root, ground_y)
		var node_ref := spatial.get("node", {}) as Dictionary
		var item := {
			"node": node_ref,
			"has_bounds": bool(spatial.get("has_bounds", false)),
			"bounds_source": str(spatial.get("bounds_source", "")),
			"world_aabb": spatial.get("world_aabb", null),
			"ground_gap": spatial.get("ground_gap", null),
			"issues": [],
			"status": "ok",
		}
		if bool(item.get("has_bounds", false)):
			var gap := float(item.get("ground_gap", 0.0))
			var ground_status := classify_ground_gap(gap, tolerance)
			if checks.has("ground_gap") and ground_status != "grounded":
				issue_count += _append_issue(item, issues, _ground_issue(ground_status, gap, tolerance), max_issues, counts)
			if checks.has("grid") and has_grid_size:
				var grid_issue := _grid_issue(target as Node, spatial, grid_size, grid_origin, tolerance)
				if not grid_issue.is_empty():
					issue_count += _append_issue(item, issues, grid_issue, max_issues, counts)
			bounded_items.append({
				"node": target,
				"node_ref": node_ref,
				"world_aabb": _aabb_from_payload(spatial.get("world_aabb", {})),
				"item": item,
			})
		else:
			issue_count += _append_issue(item, issues, {
				"type": "unmeasured",
				"severity": "info",
				"message": "Node has no supported MeshInstance3D or CollisionShape3D bounds.",
				"suggested_fix": {
					"kind": "review",
					"action": "inspect_node_bounds",
					"confidence": "medium",
					"requires_mutation_tool": false,
					"reason": "Add or inspect mesh/collision bounds before placement validation.",
				},
			}, max_issues, counts)
		if (item.get("issues", []) as Array).is_empty():
			item["status"] = "ok"
		else:
			item["status"] = "unmeasured" if not bool(item.get("has_bounds", false)) else "has_issues"
		items.append(item)

	var checked_pairs := 0
	var overlap_count := 0
	if checks.has("overlap"):
		for i in range(bounded_items.size()):
			for j in range(i + 1, bounded_items.size()):
				if checked_pairs >= max_pairs:
					break
				checked_pairs += 1
				var first := bounded_items[i] as Dictionary
				var second := bounded_items[j] as Dictionary
				var overlap := aabb_overlap(first.get("world_aabb", AABB()), second.get("world_aabb", AABB()), tolerance)
				if not bool(overlap.get("overlaps", false)):
					continue
				overlap_count += 1
				var issue := {
					"type": "clipping",
					"severity": "warning",
					"message": "AABB overlaps another bounded object.",
					"other": second.get("node_ref", {}),
					"overlap_aabb": aabb_payload(overlap.get("aabb", AABB())),
					"overlap_size": VariantCodec.variant_to_json_value(overlap.get("size", Vector3.ZERO)),
					"overlap_volume": overlap.get("volume", 0.0),
					"suggested_fix": {
						"kind": "review",
						"action": "separate_overlap",
						"confidence": "low",
						"requires_mutation_tool": true,
						"reason": "Review object intent before moving either object; overlap alone does not prove which one should move.",
					},
				}
				issue_count += _append_issue(first.get("item", {}) as Dictionary, issues, issue, max_issues, counts)
				var reverse_issue := issue.duplicate(true)
				reverse_issue["other"] = first.get("node_ref", {})
				issue_count += _append_issue(second.get("item", {}) as Dictionary, issues, reverse_issue, max_issues, counts)
			if checked_pairs >= max_pairs:
				break

	ok_count = 0
	unmeasured_count = 0
	for item in items:
		if not (item.get("issues", []) as Array).is_empty():
			item["status"] = "unmeasured" if not bool(item.get("has_bounds", false)) else "has_issues"
		else:
			item["status"] = "ok"
		if str(item.get("status", "")) == "ok":
			ok_count += 1
		elif str(item.get("status", "")) == "unmeasured":
			unmeasured_count += 1

	return _ok({
		"action": "placement_check",
		"status": "succeeded",
		"current_scene": _current_scene_payload(scene_root),
		"mode": str(selection.get("mode", "unknown")),
		"ground_reference": ground_reference,
		"tolerance": tolerance,
		"grid": {
			"enabled": checks.has("grid") and has_grid_size and grid_size > 0.0,
			"size": grid_size,
			"origin": VariantCodec.variant_to_json_value(grid_origin),
		},
		"checks": checks,
		"items": items,
		"issues": issues,
		"summary": {
			"requested_count": int(selection.get("requested_count", targets.size())),
			"returned_count": items.size(),
			"ok_count": ok_count,
			"unmeasured_count": unmeasured_count,
			"bounded_node_count": bounded_items.size(),
			"checked_pairs": checked_pairs,
			"overlap_count": overlap_count,
			"issue_count": issue_count,
			"counts": counts,
			"max_issues": max_issues,
			"max_pairs": max_pairs,
			"truncated": bool(selection.get("truncated", false)) or checked_pairs >= max_pairs or issue_count >= max_issues,
		},
		"snapshot_refreshed": false,
	})


func _snap_to_ground_for_scene(scene_root: Node, params: Dictionary) -> Dictionary:
	var selector_error := _mutation_selector_error(params)
	if not selector_error.is_empty():
		return {"ok": false, "error": selector_error}
	var selection := _spatial_selection(scene_root, params)
	if not bool(selection.get("ok", false)):
		return selection

	var targets: Array = selection.get("targets", [])
	var ground_reference: Dictionary = selection.get("ground_reference", {})
	var ground_y := float(ground_reference.get("y", 0.0))
	var tolerance := _bounded_float(params.get("tolerance", DEFAULT_GROUND_TOLERANCE), DEFAULT_GROUND_TOLERANCE, 0.0, 1000.0)
	var has_grid_size := params.has("grid_size") or params.has("gridSize")
	var grid_size := _bounded_float(params.get("grid_size", params.get("gridSize", 0.0)), 0.0, 0.0, 100000.0)
	var grid_origin := _grid_origin(params.get("grid_origin", params.get("gridOrigin", {})))
	var align_to_surface := bool(params.get("align_to_surface", params.get("alignToSurface", false)))

	var planned: Array = []
	var skipped: Array = []
	for target in targets:
		if not (target is Node3D):
			if target is Node:
				skipped.append({
					"node": node_ref_payload(target as Node, scene_root),
					"reason": "unsupported_node_type",
				})
			continue
		var plan := _snap_plan_for_node(
			target as Node3D,
			scene_root,
			ground_y,
			tolerance,
			has_grid_size,
			grid_size,
			grid_origin,
			align_to_surface,
			_surface_normal_from_ground_reference(ground_reference),
			bool(ground_reference.get("surface_normal_available", false))
		)
		if bool(plan.get("can_move", false)):
			planned.append(plan)
		else:
			skipped.append(_public_plan_item(plan))

	if planned.is_empty():
		return _ok({
			"action": "snap_to_ground",
			"status": "noop",
			"changed": false,
			"undo_redo_action": false,
			"auto_saved": false,
			"current_scene": _current_scene_payload(scene_root),
			"mode": str(selection.get("mode", "unknown")),
			"ground_reference": ground_reference,
			"grid": {
				"enabled": has_grid_size and grid_size > 0.0,
				"size": grid_size,
				"origin": VariantCodec.variant_to_json_value(grid_origin),
			},
			"align_to_surface": {
				"requested": align_to_surface,
				"applied": false,
				"surface_normal": VariantCodec.variant_to_json_value(_surface_normal_from_ground_reference(ground_reference)),
				"available": bool(ground_reference.get("surface_normal_available", false)),
				"reason": "No movable bounded Node3D target required a transform change.",
			},
			"items": skipped,
			"summary": {
				"requested_count": int(selection.get("requested_count", targets.size())),
				"changed_count": 0,
				"skipped_count": skipped.size(),
				"truncated": bool(selection.get("truncated", false)),
			},
			"snapshot_refreshed": false,
		})

	var undo := _undo_redo()
	if undo == null:
		return _err("undo_redo_unavailable", "Editor UndoRedo manager is unavailable.")
	undo.create_action("Godot Codex Bridge: snap to ground")
	for plan in planned:
		var node := plan.get("node_ref_object", null) as Node3D
		if node == null:
			continue
		undo.add_do_property(node, "global_transform", plan.get("after_global_transform_raw", Transform3D()))
		undo.add_undo_property(node, "global_transform", plan.get("before_global_transform_raw", Transform3D()))
	undo.commit_action()

	var items: Array = []
	for plan in planned:
		items.append(_public_plan_item(plan))
	items.append_array(skipped)
	var snapshot := _refresh("editor_control:snap_to_ground")
	var data := {
		"action": "snap_to_ground",
		"status": "succeeded",
		"changed": true,
		"undo_redo_action": true,
		"auto_saved": false,
		"current_scene": _current_scene_payload(scene_root),
		"mode": str(selection.get("mode", "unknown")),
		"ground_reference": ground_reference,
		"grid": {
			"enabled": has_grid_size and grid_size > 0.0,
			"size": grid_size,
			"origin": VariantCodec.variant_to_json_value(grid_origin),
		},
		"align_to_surface": {
			"requested": align_to_surface,
			"applied": _any_alignment_applied(planned),
			"surface_normal": VariantCodec.variant_to_json_value(_surface_normal_from_ground_reference(ground_reference)),
			"available": bool(ground_reference.get("surface_normal_available", false)),
			"reason": _alignment_summary_reason(align_to_surface, ground_reference, planned),
		},
		"items": items,
		"summary": {
			"requested_count": int(selection.get("requested_count", targets.size())),
			"changed_count": planned.size(),
			"skipped_count": skipped.size(),
			"truncated": bool(selection.get("truncated", false)),
		},
		"snapshot_refreshed": true,
		"generated_at": snapshot.get("generated_at", ""),
	}
	_log("editor_spatial_snap_to_ground", data)
	return _ok(data)


func _snap_to_grid_for_scene(scene_root: Node, params: Dictionary) -> Dictionary:
	var selector_error := _mutation_selector_error(params)
	if not selector_error.is_empty():
		return {"ok": false, "error": selector_error}
	var selection := _spatial_selection(scene_root, params)
	if not bool(selection.get("ok", false)):
		return selection

	var targets: Array = selection.get("targets", [])
	var tolerance := _bounded_float(params.get("tolerance", DEFAULT_GROUND_TOLERANCE), DEFAULT_GROUND_TOLERANCE, 0.0, 1000.0)
	var grid_size := _bounded_float(params.get("grid_size", params.get("gridSize", DEFAULT_GRID_SIZE)), DEFAULT_GRID_SIZE, 0.000001, 100000.0)
	var grid_origin := _grid_origin(params.get("grid_origin", params.get("gridOrigin", {})))
	var axes := _grid_axes(params.get("axes", ["x", "z"]))

	var planned: Array = []
	var skipped: Array = []
	for target in targets:
		if not (target is Node3D):
			if target is Node:
				skipped.append({
					"node": node_ref_payload(target as Node, scene_root),
					"status": "skipped",
					"reason": "unsupported_node_type",
				})
			continue
		var plan := _snap_grid_plan_for_node(target as Node3D, scene_root, tolerance, grid_size, grid_origin, axes)
		if bool(plan.get("can_move", false)):
			planned.append(plan)
		else:
			skipped.append(_public_plan_item(plan))

	if planned.is_empty():
		return _ok({
			"action": "snap_to_grid",
			"status": "noop",
			"changed": false,
			"undo_redo_action": false,
			"auto_saved": false,
			"current_scene": _current_scene_payload(scene_root),
			"mode": str(selection.get("mode", "unknown")),
			"grid": {
				"enabled": true,
				"size": grid_size,
				"origin": VariantCodec.variant_to_json_value(grid_origin),
				"axes": axes,
			},
			"items": skipped,
			"summary": {
				"requested_count": int(selection.get("requested_count", targets.size())),
				"changed_count": 0,
				"skipped_count": skipped.size(),
				"truncated": bool(selection.get("truncated", false)),
			},
			"snapshot_refreshed": false,
		})

	var undo := _undo_redo()
	if undo == null:
		return _err("undo_redo_unavailable", "Editor UndoRedo manager is unavailable.")
	undo.create_action("Godot Codex Bridge: snap to grid")
	for plan in planned:
		var node := plan.get("node_ref_object", null) as Node3D
		if node == null:
			continue
		undo.add_do_property(node, "global_position", plan.get("after_global_position_raw", Vector3.ZERO))
		undo.add_undo_property(node, "global_position", plan.get("before_global_position_raw", Vector3.ZERO))
	undo.commit_action()

	var items: Array = []
	for plan in planned:
		items.append(_public_plan_item(plan))
	items.append_array(skipped)
	var snapshot := _refresh("editor_control:snap_to_grid")
	var data := {
		"action": "snap_to_grid",
		"status": "succeeded",
		"changed": true,
		"undo_redo_action": true,
		"auto_saved": false,
		"current_scene": _current_scene_payload(scene_root),
		"mode": str(selection.get("mode", "unknown")),
		"grid": {
			"enabled": true,
			"size": grid_size,
			"origin": VariantCodec.variant_to_json_value(grid_origin),
			"axes": axes,
		},
		"items": items,
		"summary": {
			"requested_count": int(selection.get("requested_count", targets.size())),
			"changed_count": planned.size(),
			"skipped_count": skipped.size(),
			"truncated": bool(selection.get("truncated", false)),
		},
		"snapshot_refreshed": true,
		"generated_at": snapshot.get("generated_at", ""),
	}
	_log("editor_spatial_snap_to_grid", data)
	return _ok(data)


func _snap_plan_for_node(
	node: Node3D,
	scene_root: Node,
	ground_y: float,
	tolerance: float,
	has_grid_size: bool,
	grid_size: float,
	grid_origin: Vector3,
	align_to_surface: bool = false,
	surface_normal: Vector3 = Vector3.UP,
	surface_normal_available: bool = true
) -> Dictionary:
	var spatial := _node_spatial_payload(node, scene_root, ground_y)
	var node_ref := spatial.get("node", {}) as Dictionary
	if not bool(spatial.get("has_bounds", false)):
		return {
			"node": node_ref,
			"status": "skipped",
			"reason": "no_supported_bounds",
			"has_bounds": false,
		}
	var before_transform := transform_for_node3d(node)
	var before_position := before_transform.origin
	var gap := float(spatial.get("ground_gap", 0.0))
	var after_position := before_position + Vector3(0.0, -gap, 0.0)
	var grid_delta := Vector3.ZERO
	if has_grid_size and grid_size > 0.0:
		var snapped_x := grid_origin.x + roundf((after_position.x - grid_origin.x) / grid_size) * grid_size
		var snapped_z := grid_origin.z + roundf((after_position.z - grid_origin.z) / grid_size) * grid_size
		grid_delta = Vector3(snapped_x - after_position.x, 0.0, snapped_z - after_position.z)
		after_position.x = snapped_x
		after_position.z = snapped_z
	var total_delta := after_position - before_position
	var alignment := _surface_alignment_plan(before_transform.basis, surface_normal, align_to_surface, surface_normal_available, tolerance)
	var after_basis: Basis = alignment.get("after_basis_raw", before_transform.basis)
	var after_transform := Transform3D(after_basis, after_position)
	var position_changed := not (absf(total_delta.x) <= tolerance and absf(total_delta.y) <= tolerance and absf(total_delta.z) <= tolerance)
	var alignment_changed := bool(alignment.get("applied", false))
	if not position_changed and not alignment_changed:
		return {
			"node": node_ref,
			"status": "skipped",
			"reason": "already_snapped",
			"has_bounds": true,
			"ground_gap": gap,
			"before_global_position": VariantCodec.variant_to_json_value(before_position),
			"after_global_position": VariantCodec.variant_to_json_value(after_position),
			"align_to_surface": _public_alignment_plan(alignment),
			"delta": VariantCodec.variant_to_json_value(total_delta),
			"world_aabb": spatial.get("world_aabb", null),
		}
	return {
		"node_ref_object": node,
		"node": node_ref,
		"status": "will_move",
		"can_move": true,
		"has_bounds": true,
		"bounds_source": str(spatial.get("bounds_source", "")),
		"ground_gap": gap,
		"ground_gap_before": gap,
		"ground_gap_after": 0.0,
		"before_global_transform_raw": before_transform,
		"after_global_transform_raw": after_transform,
		"before_global_position_raw": before_position,
		"after_global_position_raw": after_position,
		"before_global_position": VariantCodec.variant_to_json_value(before_position),
		"after_global_position": VariantCodec.variant_to_json_value(after_position),
		"before_global_basis": VariantCodec.variant_to_json_value(before_transform.basis),
		"after_global_basis": VariantCodec.variant_to_json_value(after_basis),
		"align_to_surface": _public_alignment_plan(alignment),
		"before": {
			"global_position": VariantCodec.variant_to_json_value(before_position),
			"global_basis": VariantCodec.variant_to_json_value(before_transform.basis),
			"world_aabb": spatial.get("world_aabb", null),
		},
		"after": {
			"global_position": VariantCodec.variant_to_json_value(after_position),
			"global_basis": VariantCodec.variant_to_json_value(after_basis),
			"ground_gap": 0.0,
		},
		"delta": VariantCodec.variant_to_json_value(total_delta),
		"ground_delta": VariantCodec.variant_to_json_value(Vector3(0.0, -gap, 0.0)),
		"grid_delta": VariantCodec.variant_to_json_value(grid_delta),
	}


func _snap_grid_plan_for_node(node: Node3D, scene_root: Node, tolerance: float, grid_size: float, grid_origin: Vector3, axes: Array) -> Dictionary:
	var before_position := transform_for_node3d(node).origin
	var after_position := before_position
	if axes.has("x"):
		after_position.x = grid_origin.x + roundf((after_position.x - grid_origin.x) / grid_size) * grid_size
	if axes.has("y"):
		after_position.y = grid_origin.y + roundf((after_position.y - grid_origin.y) / grid_size) * grid_size
	if axes.has("z"):
		after_position.z = grid_origin.z + roundf((after_position.z - grid_origin.z) / grid_size) * grid_size
	var total_delta := after_position - before_position
	var node_ref := node_ref_payload(node, scene_root)
	if absf(total_delta.x) <= tolerance and absf(total_delta.y) <= tolerance and absf(total_delta.z) <= tolerance:
		return {
			"node": node_ref,
			"status": "skipped",
			"reason": "already_snapped",
			"before_global_position": VariantCodec.variant_to_json_value(before_position),
			"after_global_position": VariantCodec.variant_to_json_value(after_position),
			"delta": VariantCodec.variant_to_json_value(total_delta),
		}
	return {
		"node_ref_object": node,
		"node": node_ref,
		"status": "will_move",
		"can_move": true,
		"before_global_position_raw": before_position,
		"after_global_position_raw": after_position,
		"before_global_position": VariantCodec.variant_to_json_value(before_position),
		"after_global_position": VariantCodec.variant_to_json_value(after_position),
		"before": {
			"global_position": VariantCodec.variant_to_json_value(before_position),
		},
		"after": {
			"global_position": VariantCodec.variant_to_json_value(after_position),
		},
		"delta": VariantCodec.variant_to_json_value(total_delta),
		"world_delta": VariantCodec.variant_to_json_value(total_delta),
		"local_delta": VariantCodec.variant_to_json_value(total_delta),
	}


func _public_plan_item(plan: Dictionary) -> Dictionary:
	var item := plan.duplicate(false)
	item.erase("node_ref_object")
	item.erase("before_global_transform_raw")
	item.erase("after_global_transform_raw")
	item.erase("before_global_position_raw")
	item.erase("after_global_position_raw")
	return item


func _mutation_selector_error(params: Dictionary) -> Dictionary:
	var node_path := str(params.get("node_path", params.get("nodePath", ""))).strip_edges()
	var group_name := str(params.get("group_name", params.get("groupName", ""))).strip_edges()
	if node_path == "" and group_name == "" and params.has("selected_only") and not bool(params.get("selected_only", true)):
		return _context.err("broad_scene_mutation_rejected", "Spatial mutation requires nodePath, groupName or selectedOnly=true.") if _context != null else {"code": "broad_scene_mutation_rejected", "message": "Spatial mutation requires nodePath, groupName or selectedOnly=true."}
	if node_path == "" and group_name == "" and params.has("selectedOnly") and not bool(params.get("selectedOnly", true)):
		return _context.err("broad_scene_mutation_rejected", "Spatial mutation requires nodePath, groupName or selectedOnly=true.") if _context != null else {"code": "broad_scene_mutation_rejected", "message": "Spatial mutation requires nodePath, groupName or selectedOnly=true."}
	return {}


func _grid_axes(value: Variant) -> Array:
	if not (value is Array):
		return ["x", "z"]
	var result: Array = []
	for item in value as Array:
		var axis := str(item).strip_edges().to_lower()
		if ["x", "y", "z"].has(axis) and not result.has(axis):
			result.append(axis)
	if result.is_empty():
		return ["x", "z"]
	return result


func _placement_checks(value: Variant) -> Array:
	if not (value is Array):
		return PLACEMENT_CHECKS.duplicate()
	var result: Array = []
	for item in value as Array:
		var check := str(item).strip_edges().to_lower()
		if PLACEMENT_CHECKS.has(check) and not result.has(check):
			result.append(check)
	if result.is_empty():
		return PLACEMENT_CHECKS.duplicate()
	return result


func _append_issue(item: Dictionary, all_issues: Array, issue: Dictionary, max_issues: int, counts: Dictionary) -> int:
	if all_issues.size() >= max_issues:
		return 0
	var issues := item.get("issues", []) as Array
	var recorded_issue := issue.duplicate(true)
	recorded_issue["node"] = item.get("node", {})
	issues.append(recorded_issue)
	item["issues"] = issues
	all_issues.append(recorded_issue)
	var issue_type := str(recorded_issue.get("type", "unknown"))
	counts[issue_type] = int(counts.get(issue_type, 0)) + 1
	return 1


func _ground_issue(status: String, gap: float, tolerance: float) -> Dictionary:
	var issue_type := "floating" if status == "floating" else "below_ground"
	var action := "snap_to_ground" if status == "floating" else "raise_to_ground"
	var message := "Object AABB bottom is above the ground reference." if status == "floating" else "Object AABB bottom is below the ground reference."
	return {
		"type": issue_type,
		"severity": "warning",
		"ground_gap": gap,
		"tolerance": tolerance,
		"message": message,
		"suggested_fix": {
			"kind": "translate",
			"action": action,
			"delta": VariantCodec.variant_to_json_value(Vector3(0.0, -gap, 0.0)),
			"confidence": "high",
			"requires_mutation_tool": true,
		},
	}


func _grid_issue(node: Node, spatial: Dictionary, grid_size: float, grid_origin: Vector3, tolerance: float) -> Dictionary:
	if grid_size <= 0.0 or not (node is Node3D):
		return {}
	var position := transform_for_node3d(node as Node3D).origin
	var snapped := Vector3(
		grid_origin.x + roundf((position.x - grid_origin.x) / grid_size) * grid_size,
		position.y,
		grid_origin.z + roundf((position.z - grid_origin.z) / grid_size) * grid_size
	)
	var delta := snapped - position
	if absf(delta.x) <= tolerance and absf(delta.z) <= tolerance:
		return {}
	return {
		"type": "off_grid",
		"severity": "info",
		"grid_size": grid_size,
		"grid_origin": VariantCodec.variant_to_json_value(grid_origin),
		"position": VariantCodec.variant_to_json_value(position),
		"suggested_position": VariantCodec.variant_to_json_value(snapped),
		"delta": VariantCodec.variant_to_json_value(delta),
		"world_aabb": spatial.get("world_aabb", null),
		"message": "Object origin is not aligned to the placement grid on X/Z.",
		"suggested_fix": {
			"kind": "snap_to_grid",
			"action": "move_to_grid",
			"delta": VariantCodec.variant_to_json_value(delta),
			"grid_size": grid_size,
			"confidence": "high",
			"requires_mutation_tool": true,
		},
	}


func _grid_origin(value: Variant) -> Vector3:
	if value is Dictionary:
		var dictionary := value as Dictionary
		return Vector3(
			float(dictionary.get("x", 0.0)),
			float(dictionary.get("y", 0.0)),
			float(dictionary.get("z", 0.0))
		)
	return Vector3.ZERO


func _ground_gap_query(scene_root: Node, params: Dictionary) -> Dictionary:
	var selection := _spatial_selection(scene_root, params)
	if not bool(selection.get("ok", false)):
		return selection
	var targets: Array = selection.get("targets", [])
	var ground_reference: Dictionary = selection.get("ground_reference", {})
	var ground_y := float(ground_reference.get("y", 0.0))
	var tolerance := _bounded_float(params.get("tolerance", DEFAULT_GROUND_TOLERANCE), DEFAULT_GROUND_TOLERANCE, 0.0, 1000.0)

	var items: Array = []
	var counts := {
		"grounded": 0,
		"floating": 0,
		"sunk": 0,
		"no_bounds": 0,
	}
	for target in targets:
		if not (target is Node):
			continue
		var spatial := _node_spatial_payload(target as Node, scene_root, ground_y)
		var item := {
			"node": spatial.get("node", {}),
			"has_bounds": bool(spatial.get("has_bounds", false)),
			"bounds_source": str(spatial.get("bounds_source", "")),
			"ground_gap": spatial.get("ground_gap", null),
			"status": "no_bounds",
			"classification": "unmeasured",
			"world_aabb": spatial.get("world_aabb", null),
		}
		if bool(item.get("has_bounds", false)):
			var gap := float(item.get("ground_gap", 0.0))
			var status := classify_ground_gap(gap, tolerance)
			item["status"] = status
			item["classification"] = status
			counts[status] = int(counts.get(status, 0)) + 1
		else:
			counts["no_bounds"] = int(counts.get("no_bounds", 0)) + 1
		items.append(item)

	return _ok({
		"action": "spatial_query",
		"query": "ground_gap",
		"query_type": "ground_gap",
		"status": "succeeded",
		"current_scene": _current_scene_payload(scene_root),
		"mode": str(selection.get("mode", "unknown")),
		"ground_reference": ground_reference,
		"tolerance": tolerance,
		"items": items,
		"summary": {
			"requested_count": int(selection.get("requested_count", targets.size())),
			"returned_count": items.size(),
			"truncated": bool(selection.get("truncated", false)),
			"counts": counts,
		},
		"snapshot_refreshed": false,
	})


func _aabb_overlap_query(scene_root: Node, params: Dictionary) -> Dictionary:
	var selection := _spatial_selection(scene_root, params)
	if not bool(selection.get("ok", false)):
		return selection
	var targets: Array = selection.get("targets", [])
	var tolerance := _bounded_float(params.get("tolerance", 0.0), 0.0, 0.0, 1000.0)
	var max_pairs := _bounded_int(params.get("max_pairs", params.get("maxPairs", DEFAULT_MAX_PAIRS)), DEFAULT_MAX_PAIRS, 1, HARD_MAX_PAIRS)

	var bounded_nodes: Array = []
	for target in targets:
		if not (target is Node3D):
			continue
		var node_3d := target as Node3D
		var bounds := local_aabb_for_node3d(node_3d)
		if not bool(bounds.get("ok", false)):
			continue
		bounded_nodes.append({
			"node": node_3d,
			"node_ref": node_ref_payload(node_3d, scene_root),
			"bounds_source": str(bounds.get("source", "unknown")),
			"world_aabb": transform_aabb(bounds.get("aabb", AABB()), transform_for_node3d(node_3d)),
		})

	var pairs: Array = []
	var checked_pairs := 0
	var overlapping_pairs := 0
	for i in range(bounded_nodes.size()):
		for j in range(i + 1, bounded_nodes.size()):
			checked_pairs += 1
			var first := bounded_nodes[i] as Dictionary
			var second := bounded_nodes[j] as Dictionary
			var overlap := aabb_overlap(first.get("world_aabb", AABB()), second.get("world_aabb", AABB()), tolerance)
			if bool(overlap.get("overlaps", false)):
				overlapping_pairs += 1
				if pairs.size() < max_pairs:
					pairs.append({
						"first": first.get("node_ref", {}),
						"second": second.get("node_ref", {}),
						"first_bounds_source": first.get("bounds_source", ""),
						"second_bounds_source": second.get("bounds_source", ""),
						"overlap_aabb": aabb_payload(overlap.get("aabb", AABB())),
						"overlap_size": VariantCodec.variant_to_json_value(overlap.get("size", Vector3.ZERO)),
						"overlap_volume": overlap.get("volume", 0.0),
						"status": "overlapping",
					})

	return _ok({
		"action": "spatial_query",
		"query": "aabb_overlap",
		"query_type": "aabb_overlap",
		"status": "succeeded",
		"current_scene": _current_scene_payload(scene_root),
		"mode": str(selection.get("mode", "unknown")),
		"tolerance": tolerance,
		"pairs": pairs,
		"summary": {
			"requested_count": int(selection.get("requested_count", targets.size())),
			"bounded_node_count": bounded_nodes.size(),
			"checked_pairs": checked_pairs,
			"overlapping_pairs": overlapping_pairs,
			"returned_pairs": pairs.size(),
			"max_pairs": max_pairs,
			"truncated": overlapping_pairs > pairs.size() or bool(selection.get("truncated", false)),
		},
		"snapshot_refreshed": false,
	})


func _spatial_selection(scene_root: Node, params: Dictionary) -> Dictionary:
	var max_nodes := _bounded_int(params.get("max_nodes", params.get("maxNodes", DEFAULT_MAX_NODES)), DEFAULT_MAX_NODES, 1, HARD_MAX_NODES)
	var ground_y := _bounded_float(params.get("ground_y", params.get("groundY", 0.0)), 0.0, -100000.0, 100000.0)
	var has_explicit_ground_y := params.has("ground_y") or params.has("groundY")
	var node_path := str(params.get("node_path", params.get("nodePath", ""))).strip_edges()
	var group_name := str(params.get("group_name", params.get("groupName", ""))).strip_edges()
	var selected_only := bool(params.get("selected_only", params.get("selectedOnly", node_path == "" and group_name == "")))

	var targets_result := _collect_targets(scene_root, node_path, group_name, selected_only, max_nodes)
	if not bool(targets_result.get("ok", false)):
		return targets_result
	var targets: Array = targets_result.get("targets", [])
	var ground_reference := _ground_reference(scene_root, targets, ground_y, has_explicit_ground_y)
	targets_result["ground_reference"] = ground_reference
	return targets_result


func _collect_targets(scene_root: Node, node_path: String, group_name: String, selected_only: bool, max_nodes: int) -> Dictionary:
	if node_path != "":
		var resolved := _resolve_scene_node(scene_root, node_path)
		if not resolved.get("ok", false):
			return resolved
		return {"ok": true, "mode": "node_path", "targets": [resolved.get("node")], "requested_count": 1, "truncated": false}

	if group_name != "":
		var grouped := _group_scene_nodes(scene_root, group_name, max_nodes)
		return {"ok": true, "mode": "group", "group_name": group_name, "targets": grouped.get("nodes", []), "requested_count": int(grouped.get("requested_count", 0)), "truncated": bool(grouped.get("truncated", false))}

	if selected_only:
		var selected := _selected_scene_nodes(scene_root, max_nodes)
		return {"ok": true, "mode": "selected", "targets": selected.get("nodes", []), "requested_count": int(selected.get("requested_count", 0)), "truncated": bool(selected.get("truncated", false))}

	var scanned := _walk_node3d(scene_root, max_nodes)
	return {"ok": true, "mode": "scene_scan", "targets": scanned.get("nodes", []), "requested_count": int(scanned.get("requested_count", 0)), "truncated": bool(scanned.get("truncated", false))}


func _resolve_scene_node(scene_root: Node, node_path: String) -> Dictionary:
	if node_path == ".":
		return {"ok": true, "node": scene_root}
	var path_error := EditorPathGuard.validate_scene_local_node_path(node_path)
	if not path_error.is_empty():
		return _err(str(path_error.get("code", "invalid_node_path")), str(path_error.get("message", "Invalid node path.")))
	var node: Node = null
	if node_path.begins_with("/"):
		var tree := Engine.get_main_loop() as SceneTree
		if tree == null:
			return _err("scene_tree_unavailable", "Godot SceneTree is unavailable.")
		node = tree.root.get_node_or_null(NodePath(node_path))
	else:
		node = scene_root.get_node_or_null(NodePath(node_path))
	if node == null:
		return _err("node_not_found", "Node not found in the edited scene: " + node_path)
	if node != scene_root and not scene_root.is_ancestor_of(node):
		return _err("node_outside_scene", "Resolved node is outside the edited scene.")
	return {"ok": true, "node": node}


func _group_scene_nodes(scene_root: Node, group_name: String, max_nodes: int) -> Dictionary:
	var nodes: Array = []
	var requested := 0
	var stack: Array = [scene_root]
	while not stack.is_empty():
		var node := stack.pop_front() as Node
		if node == null:
			continue
		if node.is_in_group(group_name):
			requested += 1
			if nodes.size() < max_nodes:
				nodes.append(node)
		for child in node.get_children():
			if child is Node:
				stack.append(child)
	return {"nodes": nodes, "requested_count": requested, "truncated": requested > nodes.size()}


func _selected_scene_nodes(scene_root: Node, max_nodes: int) -> Dictionary:
	var selection := EditorInterface.get_selection()
	var selected_nodes := selection.get_selected_nodes() if selection != null else []
	var nodes: Array = []
	var requested := 0
	for node in selected_nodes:
		if not (node is Node):
			continue
		if node != scene_root and not scene_root.is_ancestor_of(node):
			continue
		requested += 1
		if nodes.size() < max_nodes:
			nodes.append(node)
	return {"nodes": nodes, "requested_count": requested, "truncated": requested > nodes.size()}


func _ground_reference(scene_root: Node, targets: Array, fallback_y: float, has_explicit_y: bool) -> Dictionary:
	if has_explicit_y:
		return {
			"mode": "explicit_world_y_plane",
			"y": fallback_y,
			"detected": true,
			"source": "request",
			"surface_normal": VariantCodec.variant_to_json_value(Vector3.UP),
			"surface_normal_available": false,
		}

	var target_lookup := {}
	for target in targets:
		if target is Node:
			target_lookup[target] = true

	var stack: Array = [scene_root]
	var best_score := -1
	var best_node: Node3D = null
	var best_aabb := AABB()
	while not stack.is_empty():
		var node := stack.pop_front() as Node
		if node == null:
			continue
		if node is Node3D and not target_lookup.has(node):
			var node_3d := node as Node3D
			var bounds := local_aabb_for_node3d(node_3d)
			if bool(bounds.get("ok", false)):
				var world_aabb := transform_aabb(bounds.get("aabb", AABB()), transform_for_node3d(node_3d))
				var score := _ground_candidate_score(node_3d, world_aabb)
				if score > best_score:
					best_score = score
					best_node = node_3d
					best_aabb = world_aabb
		for child in node.get_children():
			if child is Node:
				stack.append(child)

	if best_node != null and best_score > 0:
		var surface_normal := _top_surface_normal_for(best_node)
		return {
			"mode": "detected_node_top_plane",
			"y": best_aabb.position.y + best_aabb.size.y,
			"detected": true,
			"node": node_ref_payload(best_node, scene_root),
			"world_aabb": aabb_payload(best_aabb),
			"surface_normal": VariantCodec.variant_to_json_value(surface_normal),
			"surface_normal_available": true,
			"score": best_score,
		}

	return {
		"mode": "fallback_world_y_plane",
		"y": fallback_y,
		"detected": false,
		"surface_normal": VariantCodec.variant_to_json_value(Vector3.UP),
		"surface_normal_available": false,
		"note": "No explicit ground/terrain/floor Node3D was detected; using fallback world Y plane.",
	}


func _ground_candidate_score(node_3d: Node3D, world_aabb: AABB) -> int:
	var lower_name := str(node_3d.name).to_lower()
	var score := 0
	if lower_name.contains("ground") or lower_name.contains("terrain") or lower_name.contains("floor"):
		score += 10
	for group in node_3d.get_groups():
		var lower_group := str(group).to_lower()
		if lower_group == "ground" or lower_group == "terrain" or lower_group == "floor":
			score += 10
	if world_aabb.size.x >= 2.0 and world_aabb.size.z >= 2.0 and world_aabb.size.y <= 2.0:
		score += 2
	return score


static func _top_surface_normal_for(node_3d: Node3D) -> Vector3:
	if node_3d == null:
		return Vector3.UP
	var normal := transform_for_node3d(node_3d).basis.y
	if normal.length() <= 0.0001:
		return Vector3.UP
	normal = normal.normalized()
	if normal.dot(Vector3.UP) < 0.0:
		normal = -normal
	return normal


static func _surface_normal_from_ground_reference(ground_reference: Dictionary) -> Vector3:
	var normal := _vector3_from_payload(ground_reference.get("surface_normal", {}))
	if normal.length() <= 0.0001:
		return Vector3.UP
	normal = normal.normalized()
	if normal.dot(Vector3.UP) < 0.0:
		normal = -normal
	return normal


static func _surface_alignment_plan(before_basis: Basis, surface_normal: Vector3, requested: bool, surface_normal_available: bool, tolerance: float) -> Dictionary:
	var target_normal := surface_normal.normalized() if surface_normal.length() > 0.0001 else Vector3.UP
	if target_normal.dot(Vector3.UP) < 0.0:
		target_normal = -target_normal
	if not requested:
		return {
			"requested": false,
			"available": surface_normal_available,
			"applied": false,
			"surface_normal": VariantCodec.variant_to_json_value(target_normal),
			"reason": "Surface alignment was not requested.",
			"after_basis_raw": before_basis,
		}
	if not surface_normal_available:
		return {
			"requested": true,
			"available": false,
			"applied": false,
			"surface_normal": VariantCodec.variant_to_json_value(target_normal),
			"reason": "No detected surface normal was available; alignment requires a detected ground, terrain or floor node.",
			"after_basis_raw": before_basis,
		}
	var scale := before_basis.get_scale()
	var rotation_basis := before_basis.orthonormalized()
	var current_up := rotation_basis.y.normalized() if rotation_basis.y.length() > 0.0001 else Vector3.UP
	var angle := current_up.angle_to(target_normal)
	if angle <= maxf(tolerance, 0.001):
		return {
			"requested": true,
			"available": true,
			"applied": false,
			"surface_normal": VariantCodec.variant_to_json_value(target_normal),
			"angle_radians": angle,
			"reason": "Node up vector already matches the detected surface normal.",
			"after_basis_raw": before_basis,
		}
	var axis := current_up.cross(target_normal)
	if axis.length() <= 0.0001:
		return {
			"requested": true,
			"available": true,
			"applied": false,
			"surface_normal": VariantCodec.variant_to_json_value(target_normal),
			"angle_radians": angle,
			"reason": "Surface normal alignment was ambiguous for opposite up vectors.",
			"after_basis_raw": before_basis,
		}
	var aligned_basis := (Basis(axis.normalized(), angle) * rotation_basis).scaled(scale)
	return {
		"requested": true,
		"available": true,
		"applied": true,
		"surface_normal": VariantCodec.variant_to_json_value(target_normal),
		"angle_radians": angle,
		"rotation_axis": VariantCodec.variant_to_json_value(axis.normalized()),
		"reason": "Node up vector was rotated to match the detected surface normal.",
		"after_basis_raw": aligned_basis,
	}


static func _public_alignment_plan(alignment: Dictionary) -> Dictionary:
	var result := alignment.duplicate(true)
	result.erase("after_basis_raw")
	return result


static func _any_alignment_applied(plans: Array) -> bool:
	for plan in plans:
		if plan is Dictionary:
			var alignment := (plan as Dictionary).get("align_to_surface", {}) as Dictionary
			if bool(alignment.get("applied", false)):
				return true
	return false


static func _alignment_summary_reason(align_to_surface: bool, ground_reference: Dictionary, plans: Array) -> String:
	if not align_to_surface:
		return "Surface alignment was not requested."
	if not bool(ground_reference.get("surface_normal_available", false)):
		return "No detected surface normal was available; only the fallback horizontal plane was known."
	if _any_alignment_applied(plans):
		return "One or more targets were rotated so their local up vectors match the detected surface normal."
	return "Detected surface normal was available, but all moved targets were already aligned."


func _walk_node3d(scene_root: Node, max_nodes: int) -> Dictionary:
	var nodes: Array = []
	var requested := 0
	var stack: Array = [scene_root]
	while not stack.is_empty():
		var node := stack.pop_front() as Node
		if node == null:
			continue
		if node is Node3D:
			requested += 1
			if nodes.size() < max_nodes:
				nodes.append(node)
		for child in node.get_children():
			if child is Node:
				stack.append(child)
	return {"nodes": nodes, "requested_count": requested, "truncated": requested > nodes.size()}


func _node_spatial_payload(node: Node, scene_root: Node, ground_y: float) -> Dictionary:
	var payload := {
		"node": node_ref_payload(node, scene_root),
		"is_node_3d": node is Node3D,
		"has_bounds": false,
		"bounds_source": "not_node_3d",
		"world_aabb": null,
		"ground_gap": null,
	}
	if not (node is Node3D):
		return payload

	var node_3d := node as Node3D
	var global_transform := transform_for_node3d(node_3d)
	payload["global_transform"] = VariantCodec.variant_to_json_value(global_transform)
	payload["global_position"] = VariantCodec.variant_to_json_value(global_transform.origin)
	payload["global_scale"] = VariantCodec.variant_to_json_value(global_transform.basis.get_scale())
	payload["visible"] = node_3d.visible

	var bounds := local_aabb_for_node3d(node_3d)
	if not bounds.get("ok", false):
		payload["bounds_source"] = str(bounds.get("source", "node3d_origin_only"))
		return payload

	var world_aabb := transform_aabb(bounds.get("aabb", AABB()), global_transform)
	payload["has_bounds"] = true
	payload["bounds_source"] = str(bounds.get("source", "unknown"))
	payload["world_aabb"] = aabb_payload(world_aabb)
	payload["ground_gap"] = world_aabb.position.y - ground_y
	return payload


static func local_aabb_for_node3d(node_3d: Node3D) -> Dictionary:
	if node_3d is MeshInstance3D:
		var mesh := (node_3d as MeshInstance3D).mesh
		if mesh != null:
			return {"ok": true, "aabb": mesh.get_aabb(), "source": "mesh_instance_3d_mesh"}
	if node_3d is CollisionShape3D:
		return local_aabb_for_collision_shape((node_3d as CollisionShape3D).shape)
	return {"ok": false, "source": "node3d_origin_only"}


static func local_aabb_for_collision_shape(shape: Shape3D) -> Dictionary:
	if shape == null:
		return {"ok": false, "source": "collision_shape_3d_missing_shape"}
	if shape is BoxShape3D:
		var size := (shape as BoxShape3D).size
		return {"ok": true, "aabb": AABB(size * -0.5, size), "source": "collision_shape_3d_box"}
	if shape is SphereShape3D:
		var radius := (shape as SphereShape3D).radius
		var size := Vector3(radius * 2.0, radius * 2.0, radius * 2.0)
		return {"ok": true, "aabb": AABB(size * -0.5, size), "source": "collision_shape_3d_sphere"}
	return {"ok": false, "source": "collision_shape_3d_unsupported_shape"}


static func transform_for_node3d(node_3d: Node3D) -> Transform3D:
	if node_3d == null:
		return Transform3D()
	if node_3d.is_inside_tree():
		return node_3d.global_transform
	return node_3d.transform


static func transform_aabb(local_aabb: AABB, transform: Transform3D) -> AABB:
	var start := transform * local_aabb.position
	var min_v := start
	var max_v := start
	var end := local_aabb.position + local_aabb.size
	var corners := [
		Vector3(local_aabb.position.x, local_aabb.position.y, local_aabb.position.z),
		Vector3(end.x, local_aabb.position.y, local_aabb.position.z),
		Vector3(local_aabb.position.x, end.y, local_aabb.position.z),
		Vector3(local_aabb.position.x, local_aabb.position.y, end.z),
		Vector3(end.x, end.y, local_aabb.position.z),
		Vector3(end.x, local_aabb.position.y, end.z),
		Vector3(local_aabb.position.x, end.y, end.z),
		Vector3(end.x, end.y, end.z),
	]
	for corner in corners:
		var point: Vector3 = transform * corner
		min_v = Vector3(minf(min_v.x, point.x), minf(min_v.y, point.y), minf(min_v.z, point.z))
		max_v = Vector3(maxf(max_v.x, point.x), maxf(max_v.y, point.y), maxf(max_v.z, point.z))
	return AABB(min_v, max_v - min_v)


static func classify_ground_gap(gap: float, tolerance: float = DEFAULT_GROUND_TOLERANCE) -> String:
	if absf(gap) <= tolerance:
		return "grounded"
	if gap > tolerance:
		return "floating"
	return "sunk"


static func aabb_overlap(first: AABB, second: AABB, tolerance: float = 0.0) -> Dictionary:
	var first_end := first.position + first.size
	var second_end := second.position + second.size
	var min_v := Vector3(
		maxf(first.position.x, second.position.x),
		maxf(first.position.y, second.position.y),
		maxf(first.position.z, second.position.z)
	)
	var max_v := Vector3(
		minf(first_end.x, second_end.x),
		minf(first_end.y, second_end.y),
		minf(first_end.z, second_end.z)
	)
	var size := max_v - min_v
	var overlaps := size.x > tolerance and size.y > tolerance and size.z > tolerance
	if not overlaps:
		return {
			"overlaps": false,
			"size": Vector3.ZERO,
			"volume": 0.0,
			"aabb": AABB(),
		}
	return {
		"overlaps": true,
		"size": size,
		"volume": size.x * size.y * size.z,
		"aabb": AABB(min_v, size),
	}


static func aabb_payload(aabb: AABB) -> Dictionary:
	var end := aabb.position + aabb.size
	return {
		"position": VariantCodec.variant_to_json_value(aabb.position),
		"size": VariantCodec.variant_to_json_value(aabb.size),
		"end": VariantCodec.variant_to_json_value(end),
		"center": VariantCodec.variant_to_json_value(aabb.position + (aabb.size * 0.5)),
		"volume": aabb.size.x * aabb.size.y * aabb.size.z,
	}


static func _aabb_from_payload(value: Variant) -> AABB:
	if not (value is Dictionary):
		return AABB()
	var payload := value as Dictionary
	return AABB(_vector3_from_payload(payload.get("position", {})), _vector3_from_payload(payload.get("size", {})))


static func _vector3_from_payload(value: Variant) -> Vector3:
	if not (value is Dictionary):
		return Vector3.ZERO
	var payload := value as Dictionary
	return Vector3(float(payload.get("x", 0.0)), float(payload.get("y", 0.0)), float(payload.get("z", 0.0)))


static func node_ref_payload(node: Node, scene_root: Node) -> Dictionary:
	return {
		"path": scene_path_for(node, scene_root),
		"name": str(node.name) if node != null else "",
		"type": node.get_class() if node != null else "",
	}


static func scene_path_for(node: Node, scene_root: Node) -> String:
	if node == null:
		return ""
	if scene_root == null:
		return str(node.get_path())
	if node == scene_root:
		return "."
	return str(scene_root.get_path_to(node))


func _current_scene_payload(scene_root: Node) -> Dictionary:
	return {
		"name": str(scene_root.name) if scene_root != null else "",
		"scene_file_path": scene_root.scene_file_path if scene_root != null else "",
		"path": ".",
	}


func _bounded_int(value: Variant, fallback: int, min_value: int, max_value: int) -> int:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return clampi(int(value), min_value, max_value)
	return fallback


func _bounded_float(value: Variant, fallback: float, min_value: float, max_value: float) -> float:
	if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
		return clampf(float(value), min_value, max_value)
	return fallback


func _ok(data: Dictionary) -> Dictionary:
	return {"ok": true, "data": data}


func _err(code: String, message: String) -> Dictionary:
	return {"ok": false, "error": _context.err(code, message) if _context != null else {"code": code, "message": message}}


func _undo_redo() -> EditorUndoRedoManager:
	return _context.undo_redo if _context != null else null


func _permission_enabled(key: String) -> bool:
	return _context.permission_enabled(key) if _context != null else false


func _refresh(reason: String) -> Dictionary:
	return _context.refresh(reason) if _context != null else {}


func _log(event_name: String, data: Dictionary) -> void:
	if _context != null:
		_context.log(event_name, data)
