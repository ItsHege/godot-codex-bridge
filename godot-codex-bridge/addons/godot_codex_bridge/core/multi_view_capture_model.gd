@tool
extends RefCounted

const BridgeContext := preload("bridge_context.gd")
const BridgeLimits := preload("bridge_limits.gd")
const SpatialBoundsModel := preload("spatial_bounds_model.gd")
const VariantCodec := preload("variant_codec.gd")

const MULTI_VIEW_CAPTURE_VERSION := "godot-codex-bridge/multi-view-capture-v1"
const DEFAULT_VIEWS := ["front", "side", "top", "perspective"]
const VIEW_LABELS := {
	"front": "Front orthographic",
	"side": "Side orthographic",
	"top": "Top orthographic",
	"perspective": "Perspective",
}
const MAX_VIEWS := 4
const MIN_CAPTURE_SIZE := 64
const MAX_CAPTURE_SIZE := 2048
const DEFAULT_WIDTH := 1024
const DEFAULT_HEIGHT := 768
const DEFAULT_MAX_NODES := 32
const HARD_MAX_NODES := 256

var _context: BridgeContext


func _init(context: BridgeContext = null) -> void:
	_context = context


func capture_multi_view(params: Dictionary) -> Dictionary:
	if _context != null and not _context.permission_enabled("allow_screenshots"):
		return _err("permission_denied", "Screenshot capture permission is disabled.")
	if DisplayServer.get_name().to_lower() == "headless":
		return _err("multi_view_capture_unavailable", "Multi-view capture requires a visible editor/display; headless display mode cannot render viewport evidence.")

	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return _err("no_current_scene", "No edited scene is available for multi-view capture.")
	if not (scene_root is Node3D):
		return _err("multi_view_capture_unavailable", "Multi-view capture requires a 3D edited scene root.")

	var max_nodes := _bounded_int(params.get("max_nodes", params.get("maxNodes", DEFAULT_MAX_NODES)), DEFAULT_MAX_NODES, 1, HARD_MAX_NODES)
	var selector := _selection_for(scene_root, params, max_nodes)
	if not bool(selector.get("ok", false)):
		return selector

	var bounds := _bounds_for_targets(scene_root, selector.get("targets", []) as Array, max_nodes)
	if not bool(bounds.get("ok", false)):
		return _err("multi_view_bounds_unavailable", "No measurable Node3D bounds were found for the requested multi-view capture target.", {
			"selector": _selector_summary(selector),
		})

	var width := _bounded_int(params.get("width", DEFAULT_WIDTH), DEFAULT_WIDTH, MIN_CAPTURE_SIZE, MAX_CAPTURE_SIZE)
	var height := _bounded_int(params.get("height", DEFAULT_HEIGHT), DEFAULT_HEIGHT, MIN_CAPTURE_SIZE, MAX_CAPTURE_SIZE)
	var views := _requested_views(params)
	var capture_id := "multi_view_" + _file_time()
	var artifact_dir := _artifact_dir(capture_id)
	var dir_result := _ensure_artifact_dir(artifact_dir)
	if not bool(dir_result.get("ok", false)):
		return dir_result

	var frames: Array = []
	var failures: Array = []
	for view in views:
		var frame := _capture_view(scene_root as Node3D, selector.get("targets", []) as Array, bounds.get("aabb", AABB()), str(view), width, height, artifact_dir, capture_id)
		frames.append(frame)
		if str(frame.get("status", "")) != "ok":
			failures.append(frame)

	var manifest := {
		"status": "ok" if failures.is_empty() else ("partial" if failures.size() < frames.size() else "error"),
		"multi_view_capture_version": MULTI_VIEW_CAPTURE_VERSION,
		"capture_id": capture_id,
		"created_at": _timestamp(),
		"capture_scope": "offscreen_scene_world",
		"views_requested": views,
		"view_count": frames.size(),
		"view_count_succeeded": frames.size() - failures.size(),
		"image_size": {"width": width, "height": height},
		"current_scene": {
			"path": _current_scene_path(),
			"root_name": str(scene_root.name),
			"root_type": scene_root.get_class(),
		},
		"selector": _selector_summary(selector),
		"target_bounds": _aabb_payload(bounds.get("aabb", AABB())),
		"bounds_source": bounds.get("source", "unknown"),
		"frames": frames,
		"artifact_dir": artifact_dir,
		"privacy": {
			"classification": "local_sensitive_visual_evidence",
			"external_upload_allowed": false,
			"notes": [
				"Multi-view capture writes PNG evidence and a manifest only under the local bridge artifacts directory.",
				"PNG bytes are not sent through MCP JSON responses.",
			],
		},
		"snapshot_refreshed": false,
	}
	if not failures.is_empty():
		manifest["failures"] = failures

	var manifest_path := artifact_dir.path_join("multi_view.json")
	var write_result := _write_json(manifest_path, manifest)
	if not bool(write_result.get("ok", false)):
		return write_result
	manifest["manifest_path"] = manifest_path
	_log("multi_view_capture_completed", manifest)
	return _ok(manifest)


func capture_multi_view_async(params: Dictionary) -> Dictionary:
	if _context != null and not _context.permission_enabled("allow_screenshots"):
		return _err("permission_denied", "Screenshot capture permission is disabled.")
	if DisplayServer.get_name().to_lower() == "headless":
		return _err("multi_view_capture_unavailable", "Multi-view capture requires a visible editor/display; headless display mode cannot render viewport evidence.")

	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return _err("no_current_scene", "No edited scene is available for multi-view capture.")
	if not (scene_root is Node3D):
		return _err("multi_view_capture_unavailable", "Multi-view capture requires a 3D edited scene root.")

	var max_nodes := _bounded_int(params.get("max_nodes", params.get("maxNodes", DEFAULT_MAX_NODES)), DEFAULT_MAX_NODES, 1, HARD_MAX_NODES)
	var selector := _selection_for(scene_root, params, max_nodes)
	if not bool(selector.get("ok", false)):
		return selector

	var bounds := _bounds_for_targets(scene_root, selector.get("targets", []) as Array, max_nodes)
	if not bool(bounds.get("ok", false)):
		return _err("multi_view_bounds_unavailable", "No measurable Node3D bounds were found for the requested multi-view capture target.", {
			"selector": _selector_summary(selector),
		})

	var width := _bounded_int(params.get("width", DEFAULT_WIDTH), DEFAULT_WIDTH, MIN_CAPTURE_SIZE, MAX_CAPTURE_SIZE)
	var height := _bounded_int(params.get("height", DEFAULT_HEIGHT), DEFAULT_HEIGHT, MIN_CAPTURE_SIZE, MAX_CAPTURE_SIZE)
	var views := _requested_views(params)
	var capture_id := "multi_view_" + _file_time()
	var artifact_dir := _artifact_dir(capture_id)
	var dir_result := _ensure_artifact_dir(artifact_dir)
	if not bool(dir_result.get("ok", false)):
		return dir_result

	var frames: Array = []
	var failures: Array = []
	for view in views:
		var frame := await _capture_view_async(scene_root as Node3D, selector.get("targets", []) as Array, bounds.get("aabb", AABB()), str(view), width, height, artifact_dir, capture_id)
		frames.append(frame)
		if str(frame.get("status", "")) != "ok":
			failures.append(frame)

	var manifest := {
		"status": "ok" if failures.is_empty() else ("partial" if failures.size() < frames.size() else "error"),
		"multi_view_capture_version": MULTI_VIEW_CAPTURE_VERSION,
		"capture_id": capture_id,
		"created_at": _timestamp(),
		"capture_scope": "offscreen_scene_world",
		"views_requested": views,
		"view_count": frames.size(),
		"view_count_succeeded": frames.size() - failures.size(),
		"image_size": {"width": width, "height": height},
		"current_scene": {
			"path": _current_scene_path(),
			"root_name": str(scene_root.name),
			"root_type": scene_root.get_class(),
		},
		"selector": _selector_summary(selector),
		"target_bounds": _aabb_payload(bounds.get("aabb", AABB())),
		"bounds_source": bounds.get("source", "unknown"),
		"frames": frames,
		"artifact_dir": artifact_dir,
		"privacy": {
			"classification": "local_sensitive_visual_evidence",
			"external_upload_allowed": false,
			"notes": [
				"Multi-view capture writes PNG evidence and a manifest only under the local bridge artifacts directory.",
				"PNG bytes are not sent through MCP JSON responses.",
			],
		},
		"snapshot_refreshed": false,
	}
	if not failures.is_empty():
		manifest["failures"] = failures

	var manifest_path := artifact_dir.path_join("multi_view.json")
	var write_result := _write_json(manifest_path, manifest)
	if not bool(write_result.get("ok", false)):
		return write_result
	manifest["manifest_path"] = manifest_path
	_log("multi_view_capture_completed", manifest)
	return _ok(manifest)


func _selection_for(scene_root: Node, params: Dictionary, max_nodes: int) -> Dictionary:
	var spatial := SpatialBoundsModel.new(_context)
	var node_path := str(params.get("node_path", params.get("nodePath", ""))).strip_edges()
	var group_name := str(params.get("group_name", params.get("groupName", ""))).strip_edges()
	var selected_only := bool(params.get("selected_only", params.get("selectedOnly", node_path == "" and group_name == "")))
	return spatial.call("_collect_targets", scene_root, node_path, group_name, selected_only, max_nodes)


func _bounds_for_targets(scene_root: Node, targets: Array, max_nodes: int) -> Dictionary:
	var combined := AABB()
	var has_bounds := false
	var measured_nodes := 0
	var visited := 0
	var stack: Array = []
	for target in targets:
		if target is Node:
			stack.append(target)

	while not stack.is_empty() and visited < max_nodes:
		var node := stack.pop_front() as Node
		if node == null:
			continue
		visited += 1
		if node is Node3D:
			var node_3d := node as Node3D
			var bounds := SpatialBoundsModel.local_aabb_for_node3d(node_3d)
			if bool(bounds.get("ok", false)):
				var world_aabb := SpatialBoundsModel.transform_aabb(bounds.get("aabb", AABB()), SpatialBoundsModel.transform_for_node3d(node_3d))
				combined = world_aabb if not has_bounds else combined.merge(world_aabb)
				has_bounds = true
				measured_nodes += 1
		for child in node.get_children():
			if child is Node:
				stack.append(child)

	if not has_bounds:
		for target in targets:
			if target is Node3D:
				var target_3d := target as Node3D
				var origin := SpatialBoundsModel.transform_for_node3d(target_3d).origin
				var fallback := AABB(origin - Vector3.ONE * 0.5, Vector3.ONE)
				combined = fallback if not has_bounds else combined.merge(fallback)
				has_bounds = true
				measured_nodes += 1

	return {
		"ok": has_bounds,
		"aabb": combined,
		"source": "node3d_descendant_bounds" if measured_nodes > 0 else "unavailable",
		"measured_nodes": measured_nodes,
		"visited_nodes": visited,
		"truncated": not stack.is_empty(),
	}


func _capture_view(scene_root: Node3D, targets: Array, bounds: AABB, view: String, width: int, height: int, artifact_dir: String, capture_id: String) -> Dictionary:
	var subviewport := SubViewport.new()
	subviewport.name = "GodotCodexBridgeMultiViewViewport"
	subviewport.size = Vector2i(width, height)
	subviewport.disable_3d = false
	subviewport.own_world_3d = true
	subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	subviewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	subviewport.transparent_bg = false

	var capture_scene := _build_capture_scene(targets, bounds)
	subviewport.add_child(capture_scene.get("root"))

	var camera := Camera3D.new()
	camera.name = "GodotCodexBridgeMultiViewCamera"
	var camera_plan := _camera_plan_for_view(bounds, view, float(width) / maxf(1.0, float(height)))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL if bool(camera_plan.get("orthogonal", true)) else Camera3D.PROJECTION_PERSPECTIVE
	camera.size = float(camera_plan.get("size", 10.0))
	camera.fov = float(camera_plan.get("fov", 60.0))
	camera.near = 0.01
	camera.far = float(camera_plan.get("far", 1000.0))
	camera.global_transform = camera_plan.get("transform", Transform3D())
	camera.current = true

	subviewport.add_child(camera)
	if _context != null and _context.owner_node != null:
		_context.owner_node.add_child(subviewport)
	else:
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			tree.root.add_child(subviewport)

	camera.make_current()
	RenderingServer.force_draw(true)
	RenderingServer.force_draw(true)
	var texture := subviewport.get_texture()
	var image := texture.get_image() if texture != null else null
	var gpu_uniform := image == null or image.is_empty() or _sampled_unique_colors(image) <= 1
	if gpu_uniform:
		image = _software_view_image(bounds, view, width, height)
	var file_name := capture_id + "_" + view + ".png"
	var abs_path := artifact_dir.path_join(file_name)
	var frame: Dictionary
	if image == null or image.is_empty():
		frame = {
			"view": view,
			"label": str(VIEW_LABELS.get(view, view)),
			"status": "error",
			"error": _error_payload("multi_view_image_unavailable", "Offscreen multi-view image was empty for view: " + view),
		}
	else:
		var err := image.save_png(abs_path)
		if err != OK:
			frame = {
				"view": view,
				"label": str(VIEW_LABELS.get(view, view)),
				"status": "error",
				"error": _error_payload("multi_view_save_failed", "Failed to save multi-view PNG: " + error_string(err)),
			}
		else:
			frame = {
				"view": view,
				"label": str(VIEW_LABELS.get(view, view)),
				"status": "ok",
				"artifact": {
					"local_path": abs_path,
					"project_relative_path": _project_relative_artifact_path(abs_path),
					"format": "png",
					"width": image.get_width(),
					"height": image.get_height(),
				},
				"render_source": "software_geometry_fallback" if gpu_uniform else "subviewport_gpu",
				"gpu_uniform_fallback": gpu_uniform,
				"camera": {
					"projection": "orthographic" if bool(camera_plan.get("orthogonal", true)) else "perspective",
					"transform": VariantCodec.variant_to_json_value(camera.global_transform),
					"is_current": camera.is_current(),
					"size": camera.size,
					"fov": camera.fov,
					"near": camera.near,
					"far": camera.far,
					"target": VariantCodec.variant_to_json_value(bounds.get_center()),
				},
				"proxy_scene": capture_scene.get("summary", {}),
			}

	subviewport.queue_free()
	return frame


func _capture_view_async(scene_root: Node3D, targets: Array, bounds: AABB, view: String, width: int, height: int, artifact_dir: String, capture_id: String) -> Dictionary:
	var subviewport := SubViewport.new()
	subviewport.name = "GodotCodexBridgeMultiViewViewport"
	subviewport.size = Vector2i(width, height)
	subviewport.disable_3d = false
	subviewport.own_world_3d = true
	subviewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	subviewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	subviewport.transparent_bg = false

	var capture_scene := _build_capture_scene(targets, bounds)
	subviewport.add_child(capture_scene.get("root"))

	var camera := Camera3D.new()
	camera.name = "GodotCodexBridgeMultiViewCamera"
	var camera_plan := _camera_plan_for_view(bounds, view, float(width) / maxf(1.0, float(height)))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL if bool(camera_plan.get("orthogonal", true)) else Camera3D.PROJECTION_PERSPECTIVE
	camera.size = float(camera_plan.get("size", 10.0))
	camera.fov = float(camera_plan.get("fov", 60.0))
	camera.near = 0.01
	camera.far = float(camera_plan.get("far", 1000.0))
	camera.global_transform = camera_plan.get("transform", Transform3D())
	camera.current = true

	subviewport.add_child(camera)
	if _context != null and _context.owner_node != null:
		_context.owner_node.add_child(subviewport)
	else:
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			tree.root.add_child(subviewport)

	camera.make_current()
	var tree := subviewport.get_tree()
	if tree != null:
		await tree.process_frame
		await tree.process_frame
		await tree.create_timer(0.05).timeout
	RenderingServer.force_draw(true)
	var texture := subviewport.get_texture()
	var image := texture.get_image() if texture != null else null
	var sampled_unique := _sampled_unique_colors(image) if image != null else 0
	var gpu_uniform := image == null or image.is_empty() or sampled_unique <= 1
	if gpu_uniform:
		image = _software_view_image(bounds, view, width, height)
	var file_name := capture_id + "_" + view + ".png"
	var abs_path := artifact_dir.path_join(file_name)
	var frame: Dictionary
	if image == null or image.is_empty():
		frame = {
			"view": view,
			"label": str(VIEW_LABELS.get(view, view)),
			"status": "error",
			"error": _error_payload("multi_view_image_unavailable", "Offscreen multi-view image was empty for view: " + view),
			"render_diagnostics": _render_diagnostics(subviewport, camera, sampled_unique),
		}
	else:
		var err := image.save_png(abs_path)
		if err != OK:
			frame = {
				"view": view,
				"label": str(VIEW_LABELS.get(view, view)),
				"status": "error",
				"error": _error_payload("multi_view_save_failed", "Failed to save multi-view PNG: " + error_string(err)),
				"render_diagnostics": _render_diagnostics(subviewport, camera, sampled_unique),
			}
		else:
			frame = {
				"view": view,
				"label": str(VIEW_LABELS.get(view, view)),
				"status": "ok",
				"artifact": {
					"local_path": abs_path,
					"project_relative_path": _project_relative_artifact_path(abs_path),
					"format": "png",
					"width": image.get_width(),
					"height": image.get_height(),
				},
				"render_source": "software_geometry_fallback" if gpu_uniform else "subviewport_gpu",
				"gpu_uniform_fallback": gpu_uniform,
				"render_diagnostics": _render_diagnostics(subviewport, camera, sampled_unique),
				"camera": {
					"projection": "orthographic" if bool(camera_plan.get("orthogonal", true)) else "perspective",
					"transform": VariantCodec.variant_to_json_value(camera.global_transform),
					"is_current": camera.is_current(),
					"size": camera.size,
					"fov": camera.fov,
					"near": camera.near,
					"far": camera.far,
					"target": VariantCodec.variant_to_json_value(bounds.get_center()),
				},
				"proxy_scene": capture_scene.get("summary", {}),
			}

	subviewport.queue_free()
	return frame


func _render_diagnostics(subviewport: SubViewport, camera: Camera3D, sampled_unique: int) -> Dictionary:
	var active_camera := subviewport.get_camera_3d() if subviewport != null else null
	return {
		"subviewport_inside_tree": subviewport != null and subviewport.is_inside_tree(),
		"camera_inside_tree": camera != null and camera.is_inside_tree(),
		"camera_is_current": camera != null and camera.is_current(),
		"active_camera_matches": active_camera == camera,
		"sampled_unique_colors": sampled_unique,
	}


func _sampled_unique_colors(image: Image) -> int:
	if image == null or image.is_empty():
		return 0
	var colors := {}
	var step_x: int = maxi(1, int(floor(float(image.get_width()) / 32.0)))
	var step_y: int = maxi(1, int(floor(float(image.get_height()) / 32.0)))
	var xs: Array[int] = []
	var ys: Array[int] = []
	for x in range(0, image.get_width(), step_x):
		xs.append(x)
	if xs.is_empty() or xs[xs.size() - 1] != image.get_width() - 1:
		xs.append(image.get_width() - 1)
	for y in range(0, image.get_height(), step_y):
		ys.append(y)
	if ys.is_empty() or ys[ys.size() - 1] != image.get_height() - 1:
		ys.append(image.get_height() - 1)
	for x in xs:
		for y in ys:
			var color := image.get_pixel(x, y)
			colors[str(color.to_rgba32())] = true
	return colors.size()


func _software_view_image(bounds: AABB, view: String, width: int, height: int) -> Image:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.055, 0.07, 0.105, 1.0))
	_draw_grid(image, Color(0.12, 0.16, 0.22, 1.0))
	var rect := _project_bounds_rect(bounds, view, width, height)
	if view == "perspective":
		_draw_perspective_box(image, rect)
	else:
		_fill_rect(image, rect, Color(0.22, 0.62, 1.0, 1.0))
		_draw_rect(image, rect, Color(0.02, 0.95, 1.0, 1.0), 3)
	_draw_crosshair(image, width, height)
	return image


func _project_bounds_rect(bounds: AABB, view: String, width: int, height: int) -> Rect2i:
	var size_vec := bounds.size.max(Vector3(0.05, 0.05, 0.05))
	var horizontal := size_vec.x
	var vertical := size_vec.y
	match view:
		"side":
			horizontal = size_vec.z
			vertical = size_vec.y
		"top":
			horizontal = size_vec.x
			vertical = size_vec.z
		"perspective":
			horizontal = size_vec.x + size_vec.z * 0.55
			vertical = size_vec.y + size_vec.z * 0.35
	var margin := 0.18
	var usable_w := float(width) * (1.0 - margin * 2.0)
	var usable_h := float(height) * (1.0 - margin * 2.0)
	var scale := minf(usable_w / maxf(horizontal, 0.05), usable_h / maxf(vertical, 0.05))
	var rect_w := maxf(8.0, horizontal * scale)
	var rect_h := maxf(8.0, vertical * scale)
	var left := int(round((float(width) - rect_w) * 0.5))
	var top := int(round((float(height) - rect_h) * 0.5))
	return Rect2i(left, top, int(round(rect_w)), int(round(rect_h)))


func _draw_grid(image: Image, color: Color) -> void:
	var spacing := maxi(24, int(mini(image.get_width(), image.get_height()) / 10))
	for x in range(0, image.get_width(), spacing):
		for y in range(0, image.get_height()):
			image.set_pixel(x, y, color)
	for y in range(0, image.get_height(), spacing):
		for x in range(0, image.get_width()):
			image.set_pixel(x, y, color)


func _draw_crosshair(image: Image, width: int, height: int) -> void:
	var cx := int(width / 2)
	var cy := int(height / 2)
	for x in range(maxi(0, cx - 18), mini(width, cx + 19)):
		image.set_pixel(x, cy, Color(1.0, 0.22, 0.55, 1.0))
	for y in range(maxi(0, cy - 18), mini(height, cy + 19)):
		image.set_pixel(cx, y, Color(1.0, 0.22, 0.55, 1.0))


func _draw_perspective_box(image: Image, rect: Rect2i) -> void:
	var offset := Vector2i(maxi(8, int(rect.size.x * 0.18)), -maxi(8, int(rect.size.y * 0.18)))
	var back := Rect2i(rect.position + offset, rect.size)
	_fill_rect(image, back, Color(0.12, 0.36, 0.74, 1.0))
	_draw_rect(image, back, Color(0.1, 0.75, 1.0, 1.0), 2)
	_fill_rect(image, rect, Color(0.24, 0.68, 1.0, 1.0))
	_draw_rect(image, rect, Color(0.02, 0.95, 1.0, 1.0), 3)
	var corners := [
		rect.position,
		rect.position + Vector2i(rect.size.x, 0),
		rect.position + Vector2i(0, rect.size.y),
		rect.position + rect.size,
	]
	for corner in corners:
		_draw_line(image, corner, corner + offset, Color(0.1, 0.75, 1.0, 1.0), 2)


func _fill_rect(image: Image, rect: Rect2i, color: Color) -> void:
	var x0 := clampi(rect.position.x, 0, image.get_width() - 1)
	var y0 := clampi(rect.position.y, 0, image.get_height() - 1)
	var x1 := clampi(rect.position.x + rect.size.x, 0, image.get_width() - 1)
	var y1 := clampi(rect.position.y + rect.size.y, 0, image.get_height() - 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			image.set_pixel(x, y, color)


func _draw_rect(image: Image, rect: Rect2i, color: Color, thickness: int) -> void:
	for offset in range(thickness):
		var inset := Rect2i(rect.position + Vector2i(offset, offset), rect.size - Vector2i(offset * 2, offset * 2))
		_draw_line(image, inset.position, inset.position + Vector2i(inset.size.x, 0), color, 1)
		_draw_line(image, inset.position, inset.position + Vector2i(0, inset.size.y), color, 1)
		_draw_line(image, inset.position + Vector2i(0, inset.size.y), inset.position + inset.size, color, 1)
		_draw_line(image, inset.position + Vector2i(inset.size.x, 0), inset.position + inset.size, color, 1)


func _draw_line(image: Image, from_point: Vector2i, to_point: Vector2i, color: Color, thickness: int) -> void:
	var delta := to_point - from_point
	var steps := maxi(abs(delta.x), abs(delta.y))
	if steps <= 0:
		_set_pixel_thick(image, from_point, color, thickness)
		return
	for step in range(steps + 1):
		var t := float(step) / float(steps)
		var point := Vector2i(int(round(lerpf(float(from_point.x), float(to_point.x), t))), int(round(lerpf(float(from_point.y), float(to_point.y), t))))
		_set_pixel_thick(image, point, color, thickness)


func _set_pixel_thick(image: Image, point: Vector2i, color: Color, thickness: int) -> void:
	var radius := maxi(0, thickness - 1)
	for y in range(point.y - radius, point.y + radius + 1):
		for x in range(point.x - radius, point.x + radius + 1):
			if x >= 0 and y >= 0 and x < image.get_width() and y < image.get_height():
				image.set_pixel(x, y, color)


func _build_capture_scene(targets: Array, bounds: AABB) -> Dictionary:
	var root := Node3D.new()
	root.name = "GodotCodexBridgeMultiViewScene"

	var environment := WorldEnvironment.new()
	environment.name = "GodotCodexBridgeMultiViewEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.06, 0.08, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.62, 0.72)
	env.ambient_light_energy = 0.85
	environment.environment = env
	root.add_child(environment)

	var light := DirectionalLight3D.new()
	light.name = "GodotCodexBridgeMultiViewLight"
	light.light_energy = 2.0
	light.global_transform = Transform3D(Basis(), bounds.get_center() + Vector3(4, 6, 4)).looking_at(bounds.get_center(), Vector3.UP)
	root.add_child(light)

	var summary := {
		"mesh_proxy_count": 0,
		"collision_proxy_count": 0,
		"fallback_bounds_proxy": false,
	}
	var visited := {}
	for target in targets:
		if target is Node:
			_add_visual_proxies(root, target as Node, summary, visited)

	if int(summary.get("mesh_proxy_count", 0)) == 0 and int(summary.get("collision_proxy_count", 0)) == 0:
		_add_bounds_proxy(root, bounds, summary)

	return {
		"root": root,
		"summary": summary,
	}


func _add_visual_proxies(root: Node3D, node: Node, summary: Dictionary, visited: Dictionary) -> void:
	if node == null or visited.has(node.get_instance_id()):
		return
	visited[node.get_instance_id()] = true
	if node is MeshInstance3D:
		var source_mesh := node as MeshInstance3D
		if source_mesh.mesh != null:
			var proxy := MeshInstance3D.new()
			proxy.name = "Proxy_" + str(source_mesh.name)
			proxy.mesh = source_mesh.mesh
			proxy.material_override = _proxy_material(Color(0.28, 0.72, 1.0, 1.0), false)
			for surface_index in range(source_mesh.mesh.get_surface_count()):
				var material := source_mesh.get_surface_override_material(surface_index)
				if material != null:
					proxy.set_surface_override_material(surface_index, material)
			root.add_child(proxy)
			proxy.global_transform = SpatialBoundsModel.transform_for_node3d(source_mesh)
			summary["mesh_proxy_count"] = int(summary.get("mesh_proxy_count", 0)) + 1
	elif node is CollisionShape3D:
		var collision := node as CollisionShape3D
		var collision_mesh := _mesh_for_collision_shape(collision.shape)
		if collision_mesh != null:
			var collision_proxy := MeshInstance3D.new()
			collision_proxy.name = "Proxy_" + str(collision.name)
			collision_proxy.mesh = collision_mesh
			collision_proxy.material_override = _proxy_material(Color(0.1, 0.75, 1.0, 0.42))
			root.add_child(collision_proxy)
			collision_proxy.global_transform = SpatialBoundsModel.transform_for_node3d(collision)
			summary["collision_proxy_count"] = int(summary.get("collision_proxy_count", 0)) + 1

	for child in node.get_children():
		if child is Node:
			_add_visual_proxies(root, child as Node, summary, visited)


func _mesh_for_collision_shape(shape: Shape3D) -> Mesh:
	if shape == null:
		return null
	if shape is BoxShape3D:
		var box := BoxMesh.new()
		box.size = (shape as BoxShape3D).size
		return box
	if shape is SphereShape3D:
		var sphere := SphereMesh.new()
		sphere.radius = (shape as SphereShape3D).radius
		sphere.height = (shape as SphereShape3D).radius * 2.0
		return sphere
	return null


func _add_bounds_proxy(root: Node3D, bounds: AABB, summary: Dictionary) -> void:
	var proxy := MeshInstance3D.new()
	proxy.name = "Proxy_TargetBounds"
	var mesh := BoxMesh.new()
	mesh.size = bounds.size.max(Vector3(0.1, 0.1, 0.1))
	proxy.mesh = mesh
	proxy.material_override = _proxy_material(Color(1.0, 0.45, 0.05, 0.55))
	root.add_child(proxy)
	proxy.global_position = bounds.get_center()
	summary["fallback_bounds_proxy"] = true


func _proxy_material(color: Color, transparent: bool = true) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if transparent else BaseMaterial3D.TRANSPARENCY_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = false
	return material


func _camera_plan_for_view(bounds: AABB, view: String, aspect: float) -> Dictionary:
	var center := bounds.get_center()
	var size_vec := bounds.size
	var radius := maxf(maxf(size_vec.x, size_vec.y), size_vec.z) * 0.5
	radius = maxf(radius, 1.0)
	var distance := radius * 3.0 + 2.0
	var direction := Vector3(0, 0, 1)
	var up := Vector3.UP
	var orthogonal := true
	match view:
		"front":
			direction = Vector3(0, 0, 1)
		"side":
			direction = Vector3(1, 0, 0)
		"top":
			direction = Vector3(0, 1, 0)
			up = Vector3(0, 0, -1)
		"perspective":
			direction = Vector3(1, 0.75, 1).normalized()
			orthogonal = false
	var camera_position := center + direction.normalized() * distance
	var transform := Transform3D(Basis(), camera_position).looking_at(center, up)
	var view_size := maxf(maxf(size_vec.x, size_vec.y), size_vec.z)
	view_size = maxf(view_size * 1.35, 2.0)
	if aspect > 1.0:
		view_size = maxf(view_size, size_vec.y * 1.35)
	return {
		"orthogonal": orthogonal,
		"size": view_size,
		"fov": 55.0,
		"far": maxf(distance + radius * 4.0, 100.0),
		"transform": transform,
	}


func _requested_views(params: Dictionary) -> Array:
	var requested := params.get("views", DEFAULT_VIEWS)
	var result: Array = []
	if requested is Array:
		for item in requested:
			var view := str(item).strip_edges().to_lower()
			if VIEW_LABELS.has(view) and not result.has(view):
				result.append(view)
			if result.size() >= MAX_VIEWS:
				break
	if result.is_empty():
		return DEFAULT_VIEWS.duplicate()
	return result


func _selector_summary(selector: Dictionary) -> Dictionary:
	return {
		"mode": selector.get("mode", "unknown"),
		"group_name": selector.get("group_name", ""),
		"requested_count": int(selector.get("requested_count", 0)),
		"returned_count": (selector.get("targets", []) as Array).size(),
		"truncated": bool(selector.get("truncated", false)),
	}


func _project_relative_artifact_path(abs_path: String) -> String:
	var bridge_dir := _bridge_dir()
	if bridge_dir != "" and abs_path.begins_with(bridge_dir):
		return ".godot/godot_codex_bridge/" + abs_path.substr(bridge_dir.length()).trim_prefix("\\").trim_prefix("/").replace("\\", "/")
	return abs_path


func _artifact_dir(capture_id: String) -> String:
	var root := _bridge_dir()
	if root == "":
		return ""
	return root.path_join("artifacts").path_join("multi_view_captures").path_join(capture_id)


func _ensure_artifact_dir(path: String) -> Dictionary:
	if path == "":
		return _err("bridge_dir_unavailable", "Bridge artifact directory is unavailable.")
	if _context != null:
		_context.ensure_dirs()
	var err := DirAccess.make_dir_recursive_absolute(path)
	if err != OK:
		return _err("multi_view_artifact_dir_failed", "Failed to create multi-view artifact directory: " + error_string(err))
	return _ok({"path": path})


func _write_json(path: String, data: Dictionary) -> Dictionary:
	if _context != null:
		return _context.write_json(path, data)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _err("write_json_failed", "Failed to write JSON file: " + path)
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return _ok({"path": path})


func _bridge_dir() -> String:
	return _context.bridge_dir_abs if _context != null else ProjectSettings.globalize_path(BridgeLimits.BRIDGE_DIR)


func _current_scene_path() -> Variant:
	return _context.current_scene_or_null() if _context != null else null


func _timestamp() -> String:
	return _context.timestamp_iso() if _context != null else Time.get_datetime_string_from_system(true, true)


func _file_time() -> String:
	return _context.file_time() if _context != null else Time.get_datetime_string_from_system(true).replace("-", "").replace(":", "")


func _log(event_name: String, data: Dictionary) -> void:
	if _context != null:
		_context.log(event_name, data)


func _aabb_payload(aabb: AABB) -> Dictionary:
	return {
		"position": VariantCodec.variant_to_json_value(aabb.position),
		"size": VariantCodec.variant_to_json_value(aabb.size),
		"center": VariantCodec.variant_to_json_value(aabb.get_center()),
		"end": VariantCodec.variant_to_json_value(aabb.end),
	}


func _bounded_int(value: Variant, fallback: int, min_value: int, max_value: int) -> int:
	if typeof(value) not in [TYPE_INT, TYPE_FLOAT]:
		return fallback
	return clampi(int(value), min_value, max_value)


func _ok(data: Dictionary) -> Dictionary:
	return {"ok": true, "data": data}


func _err(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	return {"ok": false, "error": _error_payload(code, message, details)}


func _error_payload(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	if _context != null:
		return _context.err(code, message, details)
	var payload := {"code": code, "message": message}
	if not details.is_empty():
		payload["details"] = details
	return payload
