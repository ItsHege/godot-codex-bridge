@tool
extends RefCounted


static func response_status(status: String) -> String:
	if status == "completed":
		return "succeeded"
	if status == "error":
		return "failed"
	return status


static func response_payload(protocol_version: String, request_id: String, request_type: String, status: String, data: Dictionary, error: Dictionary, created_at: String, completed_at: String) -> Dictionary:
	return {
		"protocol_version": protocol_version,
		"request_id": request_id,
		"type": request_type,
		"status": response_status(status),
		"created_at": created_at,
		"completed_at": completed_at,
		"data": data,
		"error": null if error.is_empty() else error,
	}


static func error_payload(code: String, message: String) -> Dictionary:
	return {
		"code": code,
		"message": message,
	}
