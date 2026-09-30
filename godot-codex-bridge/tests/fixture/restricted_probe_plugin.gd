@tool
extends "res://addons/godot_codex_bridge/plugin.gd"

## Installed only in the isolated checkpoint fixture. Production requests still
## pass through the inherited dispatcher without modification.
func _handle_request(fallback_id: String, request: Dictionary, request_file_name: String) -> Dictionary:
	var identity := BridgeRequestModel.request_identity(fallback_id, request)
	var request_id := str(identity.get("request_id", fallback_id))
	var request_type := str(identity.get("request_type", ""))
	if request_type == "fixture_set_screenshot_permission":
		var payload := BridgeRequestModel.request_payload(request)
		_permissions["allow_screenshots"] = bool(payload.get("allowed", false))
		_write_permissions()
		return _response_payload(request_id, request_type, "completed", {
			"allow_screenshots": _permission_enabled("allow_screenshots"),
		}, {}, request_file_name)
	if request_type == "fixture_eye_attach_probe":
		return _response_from_request_result(
			request_id, request_type, _validate_eye_attach_flow_request(), request_file_name
		)
	return super._handle_request(fallback_id, request, request_file_name)
