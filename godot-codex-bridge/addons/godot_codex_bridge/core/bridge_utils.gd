@tool
extends RefCounted

## Pure helpers shared by service modules while plugin.gd is being split.
## Keep this file side-effect free: no file I/O, no EditorInterface calls and
## no direct access to plugin.gd state.


static func ok(data: Dictionary = {}) -> Dictionary:
	return {
		"ok": true,
		"data": data,
	}


static func err(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"error": error_payload(code, message),
	}


static func error_payload(code: String, message: String) -> Dictionary:
	return {
		"code": code,
		"message": message,
	}


static func response_payload(protocol_version: String, request_id: String, request_type: String, status: String, data: Dictionary = {}, error: Dictionary = {}, created_at := "", completed_at := "") -> Dictionary:
	var response_status := status
	if status == "completed":
		response_status = "succeeded"
	elif status == "error":
		response_status = "failed"

	return {
		"protocol_version": protocol_version,
		"request_id": request_id,
		"type": request_type,
		"status": response_status,
		"created_at": created_at,
		"completed_at": completed_at,
		"data": data,
		"error": null if error.is_empty() else error,
	}


static func truncate_string(value: Variant, limit: int) -> String:
	var text := str(value)
	if limit <= 0 or text.length() <= limit:
		return text
	if limit <= 3:
		return text.substr(0, limit)
	return text.substr(0, limit - 3) + "..."


static func sanitize_identifier(value: String, fallback := "item", max_length := 96) -> String:
	const ALLOWED := "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-."
	var cleaned := ""
	for index in range(value.length()):
		var character := value.substr(index, 1)
		if ALLOWED.find(character) >= 0:
			cleaned += character
		else:
			cleaned += "_"
	cleaned = cleaned.strip_edges()
	while cleaned.find("__") >= 0:
		cleaned = cleaned.replace("__", "_")
	if cleaned == "":
		cleaned = fallback
	if max_length > 0 and cleaned.length() > max_length:
		cleaned = cleaned.substr(0, max_length)
	return cleaned


static func rect2_payload(rect: Rect2) -> Dictionary:
	return {
		"x": rect.position.x,
		"y": rect.position.y,
		"width": rect.size.x,
		"height": rect.size.y,
	}


static func vector2_payload(value: Vector2) -> Dictionary:
	return {
		"x": value.x,
		"y": value.y,
	}
