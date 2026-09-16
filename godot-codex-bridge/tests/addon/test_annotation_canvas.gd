extends SceneTree

const AnnotationCanvas := preload("res://addons/godot_codex_bridge/core/annotation_canvas.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge annotation canvas tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge annotation canvas tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var canvas: AnnotationCanvas = AnnotationCanvas.new()
	canvas.size = Vector2(200, 100)

	var image := Image.create_empty(64, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.1, 0.1, 0.1, 1.0))
	canvas.set_source_image(image)
	_assert_eq(canvas.marker_count(), 0, "Initial marker count")
	_assert_eq(canvas.zoom_percent(), 313, "Initial fit zoom percent")

	canvas.markers.append({
		"id": "A",
		"type": "rectangle",
		"label": "A",
		"color": "#ff00ff",
		"points": [
			{"x": 4.0, "y": 5.0},
			{"x": 24.0, "y": 18.0},
		],
	})
	_assert_eq(canvas.marker_count(), 1, "Marker count after manual marker")

	var payloads: Array = canvas.marker_payloads()
	_assert_eq(payloads.size(), 1, "Payload count")
	var payload: Dictionary = payloads[0]
	_assert_eq(payload.get("id"), "A", "Payload id")
	_assert_eq(payload.get("type"), "rectangle", "Payload type")
	var pixel_bounds: Dictionary = payload.get("pixel_bounds", {})
	_assert_eq(pixel_bounds.get("x"), 4.0, "Payload bounds x")
	_assert_eq(pixel_bounds.get("w"), 20.0, "Payload bounds width")
	var normalized_bounds: Dictionary = payload.get("normalized_bounds", {})
	_assert_float_near(float(normalized_bounds.get("x")), 0.0625, "Normalized bounds x")

	var annotated := canvas.render_annotated_image()
	_assert_eq(annotated.get_width(), 64, "Annotated width")
	_assert_eq(annotated.get_height(), 32, "Annotated height")
	_assert_true(annotated.get_pixel(4, 5).r > 0.9, "Annotated rectangle draws magenta")

	canvas.undo_marker()
	_assert_eq(canvas.marker_count(), 0, "Undo removes marker")
	canvas.markers.append({
		"id": "B",
		"type": "pin",
		"label": "B",
		"color": "#ff00ff",
		"points": [{"x": 30.0, "y": 16.0}],
	})
	canvas.clear_markers()
	_assert_eq(canvas.marker_count(), 0, "Clear removes markers")

	canvas.free()


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
