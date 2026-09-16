@tool
extends Control

signal markers_changed

var source_image: Image
var source_texture: ImageTexture
var active_tool := "rectangle"
var zoom_factor := 1.0
var pan_offset := Vector2.ZERO
var markers: Array = []
var _dragging := false
var _panning := false
var _draft_marker: Dictionary = {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func set_source_image(image: Image) -> void:
	source_image = image
	source_texture = ImageTexture.create_from_image(image)
	markers.clear()
	_draft_marker.clear()
	_dragging = false
	_panning = false
	zoom_factor = 1.0
	pan_offset = Vector2.ZERO
	queue_redraw()
	markers_changed.emit()


func set_tool(tool: String) -> void:
	active_tool = tool


func zoom_in() -> void:
	set_zoom(zoom_factor * 1.25)


func zoom_out() -> void:
	set_zoom(zoom_factor / 1.25)


func zoom_reset() -> void:
	set_zoom(1.0)
	pan_offset = Vector2.ZERO
	queue_redraw()
	markers_changed.emit()


func zoom_to_actual() -> void:
	if source_image == null:
		return
	var base_scale := _base_fit_scale()
	if base_scale <= 0.0:
		return
	set_zoom(1.0 / base_scale)
	pan_offset = Vector2.ZERO
	queue_redraw()
	markers_changed.emit()


func set_zoom(value: float, anchor := Vector2.INF) -> void:
	if source_image == null:
		return
	var old_rect := _image_rect()
	var old_zoom := zoom_factor
	zoom_factor = clamp(value, 0.25, 8.0)
	if anchor != Vector2.INF and old_rect.size.x > 0.0 and old_rect.size.y > 0.0:
		var old_normalized := (anchor - old_rect.position) / old_rect.size
		var new_rect := _image_rect()
		pan_offset += anchor - (new_rect.position + old_normalized * new_rect.size)
	elif old_zoom != zoom_factor:
		_clamp_pan()
	queue_redraw()
	markers_changed.emit()


func zoom_percent() -> int:
	if source_image == null:
		return 100
	return int(round(_base_fit_scale() * zoom_factor * 100.0))


func undo_marker() -> void:
	if not markers.is_empty():
		markers.pop_back()
		queue_redraw()
		markers_changed.emit()


func clear_markers() -> void:
	markers.clear()
	_draft_marker.clear()
	_dragging = false
	queue_redraw()
	markers_changed.emit()


func marker_count() -> int:
	return markers.size()


func marker_payloads() -> Array:
	var payloads: Array = []
	if source_image == null:
		return payloads
	for index in range(markers.size()):
		var marker: Dictionary = markers[index]
		payloads.append(_marker_payload(marker, index))
	return payloads


func render_annotated_image() -> Image:
	if source_image == null:
		return Image.new()
	var image := source_image.duplicate()
	for marker in markers:
		if typeof(marker) == TYPE_DICTIONARY:
			_draw_marker_on_image(image, marker as Dictionary)
	return image


func _gui_input(event: InputEvent) -> void:
	if source_image == null:
		return
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_button.pressed:
			set_zoom(zoom_factor * 1.15, mouse_button.position)
			accept_event()
			return
		if mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_button.pressed:
			set_zoom(zoom_factor / 1.15, mouse_button.position)
			accept_event()
			return
		if mouse_button.button_index == MOUSE_BUTTON_MIDDLE or mouse_button.button_index == MOUSE_BUTTON_RIGHT:
			_panning = mouse_button.pressed
			accept_event()
			return
		if mouse_button.button_index != MOUSE_BUTTON_LEFT:
			return
		var image_pos := _control_to_image(mouse_button.position)
		if mouse_button.pressed:
			_begin_marker(image_pos)
		else:
			_finish_marker(image_pos)
		accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _panning:
			pan_offset += motion.relative
			_clamp_pan()
			queue_redraw()
			accept_event()
		elif _dragging:
			_update_marker(_control_to_image(motion.position))
			accept_event()


func _draw() -> void:
	if source_texture == null:
		return
	var rect := _image_rect()
	draw_texture_rect(source_texture, rect, false)
	draw_rect(rect, Color(0.35, 0.35, 0.35), false, 1.0)
	for marker in markers:
		if typeof(marker) == TYPE_DICTIONARY:
			_draw_marker(marker as Dictionary, rect)
	if not _draft_marker.is_empty():
		_draw_marker(_draft_marker, rect)


func _begin_marker(point: Vector2) -> void:
	var label := _next_marker_label()
	var marker := {
		"id": label,
		"type": active_tool,
		"label": label,
		"color": "#ff00ff",
		"points": [_point_dict(point)],
	}
	if active_tool == "pin" or active_tool == "text":
		markers.append(marker)
		queue_redraw()
		markers_changed.emit()
		return
	_dragging = true
	_draft_marker = marker


func _update_marker(point: Vector2) -> void:
	if _draft_marker.is_empty():
		return
	var points: Array = _draft_marker.get("points", [])
	if active_tool == "freehand":
		points.append(_point_dict(point))
	elif points.size() == 1:
		points.append(_point_dict(point))
	else:
		points[1] = _point_dict(point)
	_draft_marker["points"] = points
	queue_redraw()


func _finish_marker(point: Vector2) -> void:
	if not _dragging:
		return
	_update_marker(point)
	if _marker_has_size(_draft_marker):
		markers.append(_draft_marker.duplicate(true))
		markers_changed.emit()
	_draft_marker.clear()
	_dragging = false
	queue_redraw()


func _next_marker_label() -> String:
	var index := markers.size()
	if not _draft_marker.is_empty():
		index += 1
	var letter_code := int("A".unicode_at(0)) + (index % 26)
	var suffix := str(int(index / 26)) if index >= 26 else ""
	return String.chr(letter_code) + suffix


func _marker_has_size(marker: Dictionary) -> bool:
	var points: Array = marker.get("points", [])
	if points.size() < 2:
		return marker.get("type", "") == "pin" or marker.get("type", "") == "text"
	var a := _point_from_dict(points[0])
	var b := _point_from_dict(points[points.size() - 1])
	return a.distance_to(b) >= 3.0 or marker.get("type", "") == "freehand"


func _draw_marker(marker: Dictionary, image_rect: Rect2) -> void:
	var color := Color(1.0, 0.0, 1.0, 0.95)
	var points := _scaled_points(marker, image_rect)
	if points.is_empty():
		return
	var marker_type := str(marker.get("type", "rectangle"))
	if marker_type == "pin" or marker_type == "text":
		_draw_pin(points[0], color)
	elif marker_type == "arrow":
		if points.size() >= 2:
			draw_line(points[0], points[1], color, 4.0)
			draw_circle(points[1], 5.0, color)
	elif marker_type == "freehand":
		for index in range(1, points.size()):
			draw_line(points[index - 1], points[index], color, 4.0)
	else:
		var bounds := _bounds_from_points(points)
		draw_rect(bounds, color, false, 4.0)
	var font := get_theme_default_font()
	if font != null:
		draw_string(font, points[0] + Vector2(8, -8), str(marker.get("label", marker.get("id", "A"))), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)


func _draw_pin(point: Vector2, color: Color) -> void:
	draw_circle(point, 8.0, Color(color.r, color.g, color.b, 0.25))
	draw_circle(point, 4.0, color)
	draw_line(point + Vector2(-14, 0), point + Vector2(14, 0), color, 3.0)
	draw_line(point + Vector2(0, -14), point + Vector2(0, 14), color, 3.0)


func _draw_marker_on_image(image: Image, marker: Dictionary) -> void:
	var color := Color(1.0, 0.0, 1.0, 1.0)
	var points: Array = marker.get("points", [])
	if points.is_empty():
		return
	var marker_type := str(marker.get("type", "rectangle"))
	if marker_type == "pin" or marker_type == "text":
		_draw_circle_on_image(image, _point_from_dict(points[0]), 10, color)
		_draw_line_on_image(image, _point_from_dict(points[0]) + Vector2(-16, 0), _point_from_dict(points[0]) + Vector2(16, 0), color, 3)
		_draw_line_on_image(image, _point_from_dict(points[0]) + Vector2(0, -16), _point_from_dict(points[0]) + Vector2(0, 16), color, 3)
	elif marker_type == "arrow":
		if points.size() >= 2:
			_draw_line_on_image(image, _point_from_dict(points[0]), _point_from_dict(points[1]), color, 4)
			_draw_circle_on_image(image, _point_from_dict(points[1]), 6, color)
	elif marker_type == "freehand":
		for index in range(1, points.size()):
			_draw_line_on_image(image, _point_from_dict(points[index - 1]), _point_from_dict(points[index]), color, 4)
	else:
		var bounds := _bounds_from_image_points(points)
		_draw_rect_on_image(image, bounds, color, 4)


func _draw_line_on_image(image: Image, a: Vector2, b: Vector2, color: Color, thickness: int) -> void:
	var steps: int = max(1, int(a.distance_to(b)))
	for step in range(steps + 1):
		var point := a.lerp(b, float(step) / float(steps))
		_draw_circle_on_image(image, point, max(1, thickness), color)


func _draw_rect_on_image(image: Image, rect: Rect2, color: Color, thickness: int) -> void:
	var a := rect.position
	var b := rect.position + Vector2(rect.size.x, 0)
	var c := rect.position + rect.size
	var d := rect.position + Vector2(0, rect.size.y)
	_draw_line_on_image(image, a, b, color, thickness)
	_draw_line_on_image(image, b, c, color, thickness)
	_draw_line_on_image(image, c, d, color, thickness)
	_draw_line_on_image(image, d, a, color, thickness)


func _draw_circle_on_image(image: Image, center: Vector2, radius: int, color: Color) -> void:
	var min_x: int = max(0, int(center.x) - radius)
	var max_x: int = min(image.get_width() - 1, int(center.x) + radius)
	var min_y: int = max(0, int(center.y) - radius)
	var max_y: int = min(image.get_height() - 1, int(center.y) + radius)
	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			if Vector2(x, y).distance_to(center) <= radius:
				image.set_pixel(x, y, color)


func _image_rect() -> Rect2:
	if source_image == null:
		return Rect2()
	var image_size := Vector2(source_image.get_width(), source_image.get_height())
	if image_size.x <= 0.0 or image_size.y <= 0.0:
		return Rect2()
	var scale: float = max(_base_fit_scale() * zoom_factor, 0.001)
	var target_size := image_size * scale
	return Rect2((size - target_size) * 0.5 + pan_offset, target_size)


func _base_fit_scale() -> float:
	if source_image == null:
		return 1.0
	var image_size := Vector2(source_image.get_width(), source_image.get_height())
	if image_size.x <= 0.0 or image_size.y <= 0.0 or size.x <= 0.0 or size.y <= 0.0:
		return 1.0
	return max(min(size.x / image_size.x, size.y / image_size.y), 0.001)


func _clamp_pan() -> void:
	var rect := _image_rect()
	var max_x: float = max(0.0, (rect.size.x - size.x) * 0.5)
	var max_y: float = max(0.0, (rect.size.y - size.y) * 0.5)
	pan_offset.x = clamp(pan_offset.x, -max_x, max_x)
	pan_offset.y = clamp(pan_offset.y, -max_y, max_y)


func _control_to_image(point: Vector2) -> Vector2:
	var rect := _image_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return Vector2.ZERO
	var normalized := (point - rect.position) / rect.size
	normalized.x = clamp(normalized.x, 0.0, 1.0)
	normalized.y = clamp(normalized.y, 0.0, 1.0)
	return Vector2(normalized.x * float(source_image.get_width()), normalized.y * float(source_image.get_height()))


func _scaled_points(marker: Dictionary, image_rect: Rect2) -> Array:
	var result: Array = []
	var image_size := Vector2(source_image.get_width(), source_image.get_height())
	for point_value in marker.get("points", []):
		var point := _point_from_dict(point_value)
		result.append(image_rect.position + Vector2(point.x / image_size.x, point.y / image_size.y) * image_rect.size)
	return result


func _marker_payload(marker: Dictionary, index: int) -> Dictionary:
	var points: Array = marker.get("points", [])
	var bounds := _bounds_from_image_points(points)
	var image_width: float = max(1.0, float(source_image.get_width()))
	var image_height: float = max(1.0, float(source_image.get_height()))
	return {
		"id": str(marker.get("id", String.chr(int("A".unicode_at(0)) + index))),
		"type": str(marker.get("type", "rectangle")),
		"label": str(marker.get("label", marker.get("id", ""))),
		"color": str(marker.get("color", "#ff00ff")),
		"pixel_bounds": _rect_dict(bounds),
		"normalized_bounds": {
			"x": bounds.position.x / image_width,
			"y": bounds.position.y / image_height,
			"w": bounds.size.x / image_width,
			"h": bounds.size.y / image_height,
		},
		"points": points,
	}


func _bounds_from_points(points: Array) -> Rect2:
	var image_points: Array = []
	for point in points:
		image_points.append(point)
	return _bounds_from_vector_points(image_points)


func _bounds_from_image_points(points: Array) -> Rect2:
	var vector_points: Array = []
	for point in points:
		vector_points.append(_point_from_dict(point))
	return _bounds_from_vector_points(vector_points)


func _bounds_from_vector_points(points: Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var min_x := INF
	var min_y := INF
	var max_x := -INF
	var max_y := -INF
	for point_value in points:
		var point: Vector2 = point_value
		min_x = min(min_x, point.x)
		min_y = min(min_y, point.y)
		max_x = max(max_x, point.x)
		max_y = max(max_y, point.y)
	return Rect2(Vector2(min_x, min_y), Vector2(max_x - min_x, max_y - min_y))


func _point_dict(point: Vector2) -> Dictionary:
	return {"x": point.x, "y": point.y}


func _point_from_dict(value: Variant) -> Vector2:
	if typeof(value) == TYPE_DICTIONARY:
		var dict := value as Dictionary
		return Vector2(float(dict.get("x", 0.0)), float(dict.get("y", 0.0)))
	return Vector2.ZERO


func _rect_dict(rect: Rect2) -> Dictionary:
	return {"x": rect.position.x, "y": rect.position.y, "w": rect.size.x, "h": rect.size.y}
