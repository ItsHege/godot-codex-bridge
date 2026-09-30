@tool
extends RefCounted

## Presentation logic for the Eye Attach window. The annotation artifact and
## marker payload contract (annotation_artifact_model.gd, annotation_canvas.gd)
## is unchanged; this only decides labels, layout sizes and shortcuts.

const HELP_TEXT := "Draw user reference markers. Codex will be told these marks are annotations, not game art."
const MIN_WINDOW := Vector2i(640, 420)
const DEFAULT_FRACTION := 0.8

const TOOLS := [
	{"id": "rectangle", "label": "Rectangle", "icon": "Rectangle", "tip": "Rectangle: drag to frame an area."},
	{"id": "pin", "label": "Pin", "icon": "Pin", "tip": "Pin: click to mark a point."},
	{"id": "arrow", "label": "Arrow", "icon": "ArrowRight", "tip": "Arrow: drag from tail to head."},
	{"id": "freehand", "label": "Freehand", "icon": "Edit", "tip": "Freehand: drag to draw."},
	{"id": "text", "label": "Text Label", "icon": "Label", "tip": "Text label: click to place a labelled point."},
]


static func tool_ids() -> Array[String]:
	var ids: Array[String] = []
	for tool in TOOLS:
		ids.append(str(tool.get("id")))
	return ids


static func tool_label(tool_id: String) -> String:
	for tool in TOOLS:
		if str(tool.get("id")) == tool_id:
			return str(tool.get("label"))
	return tool_id.capitalize()


static func status_text(image_size: Vector2i, marker_count: int, fallback_reason: String = "") -> String:
	var parts: Array[String] = []
	if image_size.x > 0 and image_size.y > 0:
		parts.append(str(image_size.x) + "×" + str(image_size.y))
	parts.append(str(marker_count) + (" marker" if marker_count == 1 else " markers"))
	if fallback_reason != "":
		parts.append("fallback: " + fallback_reason)
	parts.append("Wheel: zoom · Right/middle drag: pan")
	return " · ".join(parts)


## Same rule as attach_current_annotation(): an image and at least one marker.
static func attach_enabled(marker_count: int, has_image: bool) -> bool:
	return has_image and marker_count > 0


static func attach_text(marker_count: int) -> String:
	if marker_count <= 0:
		return "Attach"
	return "Attach " + str(marker_count) + (" marker" if marker_count == 1 else " markers")


static func marker_rows(markers: Array) -> Array:
	var rows: Array = []
	for index in range(markers.size()):
		var marker: Variant = markers[index]
		if typeof(marker) != TYPE_DICTIONARY:
			continue
		var data := marker as Dictionary
		rows.append({
			"index": index,
			"label": str(data.get("label", data.get("id", ""))),
			"type_label": tool_label(str(data.get("type", "rectangle"))),
		})
	return rows


## 80% of the editor window; a size remembered from this editor session wins
## while it is at least the minimum and still fits the editor window.
static func window_size(editor_size: Vector2i, remembered_size: Vector2i = Vector2i.ZERO) -> Vector2i:
	if remembered_size.x >= MIN_WINDOW.x and remembered_size.y >= MIN_WINDOW.y and remembered_size.x <= editor_size.x and remembered_size.y <= editor_size.y:
		return remembered_size
	var size := Vector2i(int(editor_size.x * DEFAULT_FRACTION), int(editor_size.y * DEFAULT_FRACTION))
	return Vector2i(maxi(size.x, MIN_WINDOW.x), maxi(size.y, MIN_WINDOW.y))


## Window shortcuts: Esc cancel, Enter attach, Ctrl+Z undo, Del remove selected.
static func key_action(event: InputEvent) -> String:
	if not (event is InputEventKey):
		return ""
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return ""
	match key.keycode:
		KEY_ESCAPE:
			return "cancel"
		KEY_ENTER, KEY_KP_ENTER:
			return "attach"
		KEY_DELETE:
			return "delete"
		KEY_Z:
			if (key.ctrl_pressed or key.meta_pressed) and not key.shift_pressed:
				return "undo"
	return ""
