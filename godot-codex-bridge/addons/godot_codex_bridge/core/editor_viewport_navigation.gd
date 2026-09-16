@tool
extends RefCounted

const BridgeContext := preload("bridge_context.gd")

const VIEWPORT_2D_ALIASES := ["2d", "canvas", "canvas2d", "viewport_2d"]
const VIEWPORT_3D_ALIASES := ["3d", "spatial", "viewport_3d"]
const ACTION_2D_PAN := "pan"
const ACTION_2D_ZOOM := "zoom"
const ACTION_2D_RESET := "reset"
const ACTION_3D_FRAME_SELECTED := "frame_selected"
const ACTION_3D_ORBIT := "orbit"
const ACTION_3D_ZOOM := "zoom"

var _context: BridgeContext


func _init(context: BridgeContext = null) -> void:
	_context = context


func navigate(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_editor_navigation"):
		return _err("permission_denied", "Navigate editor permission is disabled in the Codex Bridge dock.")

	var viewport := canonical_viewport(str(params.get("viewport", params.get("mode", "2D"))))
	if viewport == "":
		return _err("invalid_viewport", "viewport must be 2D or 3D.")

	var action := canonical_action(viewport, str(params.get("action", "")))
	if action == "":
		return _err(
			"invalid_viewport_action",
			"Unsupported viewport action for " + viewport + ".",
			{"supported_actions": supported_actions(viewport)}
		)

	if viewport == "2D":
		return _navigate_2d(action, params)
	return _navigate_3d_unavailable(action, params)


static func canonical_viewport(value: String) -> String:
	var normalized := _normalize(value)
	if VIEWPORT_2D_ALIASES.has(normalized):
		return "2D"
	if VIEWPORT_3D_ALIASES.has(normalized):
		return "3D"
	return ""


static func canonical_action(viewport: String, value: String) -> String:
	var normalized := _normalize(value)
	if viewport == "2D":
		if normalized in [ACTION_2D_PAN, ACTION_2D_ZOOM, ACTION_2D_RESET]:
			return normalized
		return ""
	if viewport == "3D":
		if normalized in [ACTION_3D_FRAME_SELECTED, ACTION_3D_ORBIT, ACTION_3D_ZOOM]:
			return normalized
		return ""
	return ""


static func supported_actions(viewport: String) -> Array:
	if viewport == "2D":
		return [ACTION_2D_PAN, ACTION_2D_ZOOM, ACTION_2D_RESET]
	if viewport == "3D":
		return [ACTION_3D_FRAME_SELECTED, ACTION_3D_ORBIT, ACTION_3D_ZOOM]
	return []


func _navigate_2d(action: String, params: Dictionary) -> Dictionary:
	var viewport := EditorInterface.get_editor_viewport_2d()
	if viewport == null:
		return _err("editor_viewport_unavailable", "The 2D editor viewport is unavailable.")

	EditorInterface.set_main_screen_editor("2D")
	var before: Transform2D = viewport.global_canvas_transform
	var after := before
	if action == ACTION_2D_PAN:
		var delta := Vector2(
			_number_param(params, ["delta_x", "deltaX", "x"], 0.0, -100000.0, 100000.0),
			_number_param(params, ["delta_y", "deltaY", "y"], 0.0, -100000.0, 100000.0)
		)
		after.origin += delta
	elif action == ACTION_2D_ZOOM:
		var zoom_factor := _number_param(params, ["zoom_factor", "zoomFactor", "factor"], 1.0, 0.05, 20.0)
		var center := Vector2(
			_number_param(params, ["center_x", "centerX"], 0.0, -100000.0, 100000.0),
			_number_param(params, ["center_y", "centerY"], 0.0, -100000.0, 100000.0)
		)
		after.x *= zoom_factor
		after.y *= zoom_factor
		after.origin = center + ((after.origin - center) * zoom_factor)
	elif action == ACTION_2D_RESET:
		after = Transform2D()

	viewport.global_canvas_transform = after
	var data := {
		"viewport": "2D",
		"operation": action,
		"status": "succeeded",
		"before": transform_payload(before),
		"after": transform_payload(viewport.global_canvas_transform),
		"screenshot_after_action": "requested_by_mcp_when_captureScreenshot_is_true",
		"snapshot_refreshed": false,
	}
	_log("viewport_navigate_2d", data)
	return _ok(data)


func _navigate_3d_unavailable(action: String, _params: Dictionary) -> Dictionary:
	var camera_available := false
	var viewport_available := false
	return _err(
		"editor_api_unavailable",
		"Godot exposes the active 3D editor viewport/camera for inspection, but this Bridge version has no stable official API for typed 3D editor camera orbit, zoom or frame-selected control. Use editor_focus/select_node plus capture_viewport_screenshot for visual evidence.",
		{
			"viewport": "3D",
			"operation": action,
			"editor_viewport_available": viewport_available,
			"editor_camera_available": camera_available,
			"fallback_tools": ["godot.editor_focus", "godot.select_node", "godot.capture_viewport_screenshot"],
		}
	)


static func transform_payload(transform: Transform2D) -> Dictionary:
	return {
		"x": {"x": transform.x.x, "y": transform.x.y},
		"y": {"x": transform.y.x, "y": transform.y.y},
		"origin": {"x": transform.origin.x, "y": transform.origin.y},
	}


static func _normalize(value: String) -> String:
	return value.strip_edges().to_lower().replace("-", "_").replace(" ", "_")


func _number_param(params: Dictionary, keys: Array, fallback: float, min_value: float, max_value: float) -> float:
	for key in keys:
		if params.has(key):
			var value: Variant = params.get(key)
			if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
				return clampf(float(value), min_value, max_value)
	return fallback


func _permission_enabled(key: String) -> bool:
	return _context != null and _context.permission_enabled(key)


func _log(event_name: String, data: Dictionary = {}) -> void:
	if _context != null:
		_context.log(event_name, data)


func _ok(data: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"data": data,
	}


func _err(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	return {
		"ok": false,
		"error": _context.err(code, message, details) if _context != null else _fallback_error(code, message, details),
	}


func _fallback_error(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	var payload := {
		"code": code,
		"message": message,
	}
	if not details.is_empty():
		payload["details"] = details
	return payload
