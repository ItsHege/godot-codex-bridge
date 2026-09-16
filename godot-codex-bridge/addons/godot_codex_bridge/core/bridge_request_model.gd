@tool
extends RefCounted


static func request_identity(fallback_id: String, request: Dictionary) -> Dictionary:
	var request_id := str(request.get("request_id", request.get("id", fallback_id)))
	if request_id == "":
		request_id = fallback_id

	return {
		"request_id": request_id,
		"request_type": str(request.get("type", "")),
	}


static func request_payload(request: Dictionary) -> Dictionary:
	var payload: Variant = request.get("payload", {})
	if payload is Dictionary:
		return payload as Dictionary
	return {}


static func result_response_parts(result: Dictionary) -> Dictionary:
	if result.get("ok", false):
		return {
			"status": "completed",
			"data": result.get("data", {}),
			"error": {},
		}

	return {
		"status": "error",
		"data": {},
		"error": result.get("error", {}),
	}
