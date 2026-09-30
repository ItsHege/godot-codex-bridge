extends SceneTree

const View := preload("res://addons/godot_codex_bridge/core/annotation_view_model.gd")
const AnnotationCanvas := preload("res://addons/godot_codex_bridge/core/annotation_canvas.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge annotation view model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge annotation view model tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	_eq(View.tool_ids(), ["rectangle", "pin", "arrow", "freehand", "text"], "same marker tools as before")
	_eq(View.tool_label("text"), "Text Label", "tool labels")
	_eq(View.status_text(Vector2i(2560, 1494), 2), "2560×1494 · 2 markers · Wheel: zoom · Right/middle drag: pan", "compact status")
	_eq(View.status_text(Vector2i.ZERO, 1, "root_viewport"), "1 marker · fallback: root_viewport · Wheel: zoom · Right/middle drag: pan", "status without image, with fallback")
	_false(View.attach_enabled(0, true), "no markers: Attach disabled (same rule as attach_current_annotation)")
	_false(View.attach_enabled(2, false), "no image: Attach disabled")
	_true(View.attach_enabled(1, true), "image + marker: Attach enabled")
	_eq(View.attach_text(0), "Attach", "attach text empty")
	_eq(View.attach_text(1), "Attach 1 marker", "attach text singular")
	_eq(View.attach_text(3), "Attach 3 markers", "attach text plural")
	_eq(View.marker_rows([{"label": "A", "type": "pin"}, "junk", {"id": "C", "type": "rectangle"}]), [{"index": 0, "label": "A", "type_label": "Pin"}, {"index": 2, "label": "C", "type_label": "Rectangle"}], "marker rows")

	_eq(View.window_size(Vector2i(2000, 1000)), Vector2i(1600, 800), "default is 80% of the editor window")
	_eq(View.window_size(Vector2i(700, 500)), Vector2i(640, 420), "never below the minimum")
	_eq(View.window_size(Vector2i(2000, 1000), Vector2i(1200, 700)), Vector2i(1200, 700), "remembered size reused")
	_eq(View.window_size(Vector2i(1000, 600), Vector2i(1200, 700)), Vector2i(800, 480), "remembered size ignored when it no longer fits")

	_eq(View.key_action(_key(KEY_ESCAPE)), "cancel", "Esc cancels")
	_eq(View.key_action(_key(KEY_ENTER)), "attach", "Enter attaches")
	_eq(View.key_action(_key(KEY_KP_ENTER)), "attach", "keypad Enter attaches")
	_eq(View.key_action(_key(KEY_Z, true)), "undo", "Ctrl+Z undoes")
	_eq(View.key_action(_key(KEY_Z)), "", "plain Z does nothing")
	_eq(View.key_action(_key(KEY_DELETE)), "delete", "Del removes")
	var released := _key(KEY_ENTER)
	released.pressed = false
	_eq(View.key_action(released), "", "key release ignored")

	# Canvas: removing a marker relabels so labels stay unique and ordered.
	var canvas := AnnotationCanvas.new()
	for index in range(3):
		var label := AnnotationCanvas.label_for_index(index)
		canvas.markers.append({"id": label, "label": label, "type": "pin", "color": "#ff00ff", "points": [{"x": 1, "y": 1}]})
	canvas.remove_marker(1)
	_eq(canvas.markers.map(func(m: Dictionary) -> String: return str(m.get("label"))), ["A", "B"], "relabelled after removing B")
	_eq(str(canvas.markers[1].get("color")), "#ff00ff", "stored marker color unchanged")
	_eq(canvas.call("_next_marker_label"), "C", "next label continues without duplicates")
	canvas.remove_marker(9)
	_eq(canvas.marker_count(), 2, "out-of-range remove ignored")
	_eq(AnnotationCanvas.label_for_index(27), "B1", "label scheme unchanged")
	canvas.free()


func _key(keycode: Key, ctrl := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	event.ctrl_pressed = ctrl
	return event


func _eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures += 1
		push_error(label + " expected=" + str(expected) + " actual=" + str(actual))


func _true(value: bool, label: String) -> void:
	if not value:
		_failures += 1
		push_error(label)


func _false(value: bool, label: String) -> void:
	if value:
		_failures += 1
		push_error(label)
