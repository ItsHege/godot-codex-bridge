@tool
extends RefCounted

const BridgeLimits := preload("bridge_limits.gd")


static func parse_bounded_request(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() > BridgeLimits.MAX_REQUEST_BYTES:
		return _error("request_too_large", "Bridge request exceeds the bounded request size.", {"max_bytes": BridgeLimits.MAX_REQUEST_BYTES})
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return _error("invalid_json", "Expected a JSON object bridge request.")
	var state := {"nodes": 0}
	var limit_result := validate_json_limits(parsed, 0, state)
	if not bool(limit_result.get("ok", false)):
		return limit_result
	return {"ok": true, "data": parsed}


static func validate_json_limits(value: Variant, depth: int, state: Dictionary) -> Dictionary:
	if depth > BridgeLimits.MAX_REQUEST_JSON_DEPTH:
		return _error("request_json_too_deep", "Bridge request JSON exceeds the depth limit.", {"max_depth": BridgeLimits.MAX_REQUEST_JSON_DEPTH})
	state["nodes"] = int(state.get("nodes", 0)) + 1
	if int(state.get("nodes", 0)) > BridgeLimits.MAX_REQUEST_JSON_NODES:
		return _error("request_json_too_complex", "Bridge request JSON exceeds the node limit.", {"max_nodes": BridgeLimits.MAX_REQUEST_JSON_NODES})
	if typeof(value) == TYPE_DICTIONARY:
		for key in (value as Dictionary).keys():
			var nested_result := validate_json_limits((value as Dictionary).get(key), depth + 1, state)
			if not bool(nested_result.get("ok", false)):
				return nested_result
	elif typeof(value) == TYPE_ARRAY:
		for item in (value as Array):
			var nested_result := validate_json_limits(item, depth + 1, state)
			if not bool(nested_result.get("ok", false)):
				return nested_result
	return {"ok": true}


static func _error(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	var payload := {"code": code, "message": message}
	if not details.is_empty():
		payload["details"] = details
	return {"ok": false, "error": payload}
