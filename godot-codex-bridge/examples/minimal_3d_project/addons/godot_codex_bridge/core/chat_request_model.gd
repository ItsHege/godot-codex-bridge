@tool
extends RefCounted

const ALLOWED_APPROVAL_DECISIONS := ["approve", "approve_session", "reject", "revise"]
const CODEX_CHAT_REQUEST_TYPES := [
	"connect_codex_chat_host",
	"enable_codex_bridge_tools",
	"send_codex_chat_message",
	"start_codex_background_team_review",
	"cancel_codex_background_team_review",
	"respond_codex_chat_approval",
]
const CODEX_CHAT_EFFECT_ACTIONS := [
	"connect_host",
	"enable_tools",
	"set_attachment_flags",
	"set_runtime_options",
	"set_chat_input",
	"send_chat_message",
	"run_team_review",
	"cancel_team_review",
	"set_approval_note",
	"respond_to_approval",
]


static func ok(data: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"data": data,
	}


static func error_result(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"error": {
			"code": code,
			"message": message,
		},
	}


static func is_codex_chat_request_type(request_type: String) -> bool:
	return request_type in CODEX_CHAT_REQUEST_TYPES


static func permission_denied(message: String) -> Dictionary:
	return error_result("permission_denied", message)


static func chat_not_connected(message := "Codex Host is not connected yet.") -> Dictionary:
	return error_result("chat_host_not_connected", message)


static func project_attach_pending(message := "Waiting for Codex to attach this Godot project before continuing.") -> Dictionary:
	return error_result("project_attach_pending", message)


static func project_mismatch(message := "Codex Host is attached to a different Godot project. Reconnect to this project before continuing.") -> Dictionary:
	return error_result("project_mismatch", message)


static func _chat_not_connected_plan(message := "Codex Host is not connected yet.", connect_first := false) -> Dictionary:
	var result := chat_not_connected(message)
	result["connect_first"] = connect_first
	return result


static func message_from_payload(payload: Dictionary) -> String:
	return str(payload.get("message", "")).strip_edges()


static func validate_message_payload(payload: Dictionary) -> Dictionary:
	if message_from_payload(payload) == "":
		return error_result("message_required", "A non-empty chat message is required.")
	return ok({
		"message": message_from_payload(payload),
	})


static func validate_approval_decision(payload: Dictionary) -> Dictionary:
	var decision := str(payload.get("decision", "reject"))
	if not decision in ALLOWED_APPROVAL_DECISIONS:
		return error_result("invalid_decision", "Approval decision must be approve, approve_session, reject or revise.")
	return ok({
		"decision": decision,
		"note": str(payload.get("note", "")),
	})


static func connect_host_request_plan(chat_permission_enabled: bool) -> Dictionary:
	if not chat_permission_enabled:
		return permission_denied("Codex chat permission is disabled in the Codex Bridge dock.")
	return ok({})


static func enable_tools_request_plan(chat_permission_enabled: bool, socket_ready: bool, active_project_root := "", project_mismatch_detected := false) -> Dictionary:
	if not chat_permission_enabled:
		return permission_denied("Codex chat permission is disabled in the Codex Bridge dock.")
	if not socket_ready:
		return chat_not_connected()
	if project_mismatch_detected:
		return project_mismatch("Reconnect to this project before enabling tools.")
	if str(active_project_root).strip_edges() == "":
		return project_attach_pending("Waiting for Codex to attach this Godot project before enabling tools.")
	return ok({})


static func send_message_request_plan(chat_permission_enabled: bool, socket_ready: bool, payload: Dictionary, active_project_root := "", project_mismatch_detected := false) -> Dictionary:
	if not chat_permission_enabled:
		return permission_denied("Codex chat permission is disabled in the Codex Bridge dock.")
	if not socket_ready:
		return _chat_not_connected_plan("Codex Host is not connected yet.", true)
	if project_mismatch_detected:
		return project_mismatch("Reconnect to this project before sending new work.")
	if str(active_project_root).strip_edges() == "":
		return project_attach_pending("Waiting for Codex to attach this Godot project before sending the message.")
	var message_result := validate_message_payload(payload)
	if not bool(message_result.get("ok", false)):
		return message_result
	var message_data := message_result.get("data", {}) as Dictionary
	return ok({
		"message": str(message_data.get("message", "")),
		"attachments": payload.get("attachments", {}),
		"runtime_options": payload,
	})


static func team_review_request_plan(chat_permission_enabled: bool, background_permission_enabled: bool, socket_ready: bool, payload: Dictionary, active_project_root := "", project_mismatch_detected := false) -> Dictionary:
	if not chat_permission_enabled:
		return permission_denied("Codex chat permission is disabled in the Codex Bridge dock.")
	if not background_permission_enabled:
		return permission_denied("Background team review permission is disabled in the Codex Bridge dock.")
	if not socket_ready:
		return _chat_not_connected_plan("Codex Host is not connected yet.", true)
	if project_mismatch_detected:
		return project_mismatch("Reconnect to this project before starting team review.")
	if str(active_project_root).strip_edges() == "":
		return project_attach_pending("Waiting for Codex to attach this Godot project before starting team review.")
	return ok({
		"attachments": payload.get("attachments", {}),
		"prompt": str(payload.get("prompt", "")).strip_edges(),
	})


static func cancel_team_review_request_plan(socket_ready: bool) -> Dictionary:
	if not socket_ready:
		return chat_not_connected("Codex Host is not connected.")
	return ok({})


static func approval_response_request_plan(has_active_approval: bool, socket_ready: bool, payload: Dictionary) -> Dictionary:
	if not has_active_approval:
		return error_result("approval_unavailable", "No active Codex chat approval is visible in the dock.")
	if not socket_ready:
		return chat_not_connected("Codex Host is not connected.")
	return validate_approval_decision(payload)


static func request_context(raw_context: Dictionary) -> Dictionary:
	return {
		"chat_permission_enabled": bool(raw_context.get("chat_permission_enabled", false)),
		"background_permission_enabled": bool(raw_context.get("background_permission_enabled", false)),
		"socket_ready": bool(raw_context.get("socket_ready", false)),
		"has_active_approval": bool(raw_context.get("has_active_approval", false)),
		"active_project_root": str(raw_context.get("active_project_root", "")),
		"project_mismatch": bool(raw_context.get("project_mismatch", false)),
	}


static func request_dispatch_plan(request_type: String, raw_context: Dictionary, payload: Dictionary = {}) -> Dictionary:
	var context := request_context(raw_context)
	var plan := {}
	var effect_plan := {}
	var success_action := ""
	match request_type:
		"connect_codex_chat_host":
			plan = connect_host_request_plan(bool(context.get("chat_permission_enabled", false)))
			effect_plan = connect_host_request_effect_plan(plan)
			success_action = "host.connect"
		"enable_codex_bridge_tools":
			plan = enable_tools_request_plan(
				bool(context.get("chat_permission_enabled", false)),
				bool(context.get("socket_ready", false)),
				str(context.get("active_project_root", "")),
				bool(context.get("project_mismatch", false))
			)
			effect_plan = enable_tools_request_effect_plan(plan)
			success_action = "bridge.tools.enable"
		"send_codex_chat_message":
			plan = send_message_request_plan(
				bool(context.get("chat_permission_enabled", false)),
				bool(context.get("socket_ready", false)),
				payload,
				str(context.get("active_project_root", "")),
				bool(context.get("project_mismatch", false))
			)
			effect_plan = send_message_request_effect_plan(plan)
			success_action = "thread.send"
		"start_codex_background_team_review":
			plan = team_review_request_plan(
				bool(context.get("chat_permission_enabled", false)),
				bool(context.get("background_permission_enabled", false)),
				bool(context.get("socket_ready", false)),
				payload,
				str(context.get("active_project_root", "")),
				bool(context.get("project_mismatch", false))
			)
			effect_plan = team_review_request_effect_plan(plan)
			success_action = "background.start"
		"cancel_codex_background_team_review":
			plan = cancel_team_review_request_plan(bool(context.get("socket_ready", false)))
			effect_plan = cancel_team_review_request_effect_plan(plan)
			success_action = "background.cancel"
		"respond_codex_chat_approval":
			plan = approval_response_request_plan(
				bool(context.get("has_active_approval", false)),
				bool(context.get("socket_ready", false)),
				payload
			)
			effect_plan = approval_response_request_effect_plan(plan)
			success_action = "approval.respond"
		_:
			plan = error_result("unsupported_chat_request", "Unsupported Codex chat request type: " + request_type)
			effect_plan = request_failure_effect_plan(plan)
	return {
		"request_type": request_type,
		"success_action": success_action,
		"plan": plan,
		"effect_plan": effect_plan,
	}


static func request_application_effects(effects: Array) -> Array:
	var normalized: Array[Dictionary] = []
	for effect: Variant in effects:
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		var source := effect as Dictionary
		var action := str(source.get("action", ""))
		if not action in CODEX_CHAT_EFFECT_ACTIONS:
			continue
		var item := {"action": action}
		match action:
			"set_attachment_flags":
				item["value"] = source.get("value", {})
			"set_runtime_options":
				var options_value: Variant = source.get("value", {})
				item["value"] = options_value if typeof(options_value) == TYPE_DICTIONARY else {}
			"set_chat_input":
				item["text"] = str(source.get("text", ""))
				item["refresh_composer"] = bool(source.get("refresh_composer", false))
			"set_approval_note":
				item["text"] = str(source.get("text", ""))
			"respond_to_approval":
				item["decision"] = str(source.get("decision", "reject"))
		normalized.append(item)
	return normalized


static func request_dispatch_effect_result_plan(request_type: String, raw_context: Dictionary, payload: Dictionary, state: Dictionary) -> Dictionary:
	var dispatch := request_dispatch_plan(request_type, raw_context, payload)
	return request_effect_result_plan(
		dispatch.get("plan", {}) as Dictionary,
		dispatch.get("effect_plan", {}) as Dictionary,
		str(dispatch.get("success_action", "")),
		state
	)


static func addon_rpc_request_plan(params: Dictionary) -> Dictionary:
	var request_value: Variant = params.get("request", {})
	var fallback_request_id := str(params.get("request_id", ""))
	if typeof(request_value) != TYPE_DICTIONARY:
		return {
			"ok": false,
			"request_id": fallback_request_id,
			"request_action": "unknown",
			"error": {
				"code": "invalid_rpc_request",
				"message": "bridge.addon_request params.request must be an object.",
			},
		}
	var request := request_value as Dictionary
	var request_id := str(request.get("request_id", fallback_request_id))
	if request_id == "":
		request_id = "websocket_rpc"
	return {
		"ok": true,
		"request_id": request_id,
		"request": request,
	}


static func addon_rpc_effect_plan(params: Dictionary) -> Dictionary:
	var plan := addon_rpc_request_plan(params)
	var effects: Array[Dictionary] = []
	var request_id := str(plan.get("request_id", ""))
	if not bool(plan.get("ok", false)):
		var error := plan.get("error", {}) as Dictionary
		effects.append({
			"action": "send_addon_error_response",
			"request_id": request_id,
			"request_action": str(plan.get("request_action", "unknown")),
			"error_code": str(error.get("code", "invalid_rpc_request")),
			"error_message": str(error.get("message", "bridge.addon_request params.request must be an object.")),
			"request_source": "websocket_rpc",
		})
	else:
		effects.append({
			"action": "handle_addon_request",
			"request_id": request_id,
			"request": plan.get("request", {}),
			"request_source": "websocket_rpc",
		})
	return {
		"plan": plan,
		"effects": effects,
	}


static func request_state(raw_state: Dictionary) -> Dictionary:
	var host_process_id := int(raw_state.get("host_process_id", -1))
	var host_owned: bool
	if raw_state.has("host_process_owned_by_addon"):
		host_owned = bool(raw_state.get("host_process_owned_by_addon", false))
	else:
		host_owned = host_process_id > 0
	return {
		"chat_request_id": int(raw_state.get("chat_request_id", 0)),
		"connection_state": str(raw_state.get("connection_state", "")),
		"runtime_state": str(raw_state.get("runtime_state", "")),
		"thread_id": str(raw_state.get("thread_id", "")),
		"turn_id": str(raw_state.get("turn_id", "")),
		"background_task_id": str(raw_state.get("background_task_id", "")),
		"background_state": str(raw_state.get("background_state", "")),
		"host_config_loaded": bool(raw_state.get("host_config_loaded", false)),
		"host_url": str(raw_state.get("host_url", "")),
		"host_start_in_progress": bool(raw_state.get("host_start_in_progress", false)),
		"host_process_id": host_process_id,
		"host_process_owned_by_addon": host_owned,
		"trust_mode": str(raw_state.get("trust_mode", "off")),
		"active_project_root": str(raw_state.get("active_project_root", "")),
		"project_mismatch": bool(raw_state.get("project_mismatch", false)),
	}


static func result_data(action: String, state: Dictionary) -> Dictionary:
	var normalized := request_state(state)
	return {
		"action": action,
		"sent": true,
		"chat_request_id": int(normalized.get("chat_request_id", 0)),
		"connection_state": str(normalized.get("connection_state", "")),
		"runtime_state": str(normalized.get("runtime_state", "")),
		"thread_id": str(normalized.get("thread_id", "")),
		"turn_id": str(normalized.get("turn_id", "")),
		"background_task_id": str(normalized.get("background_task_id", "")),
		"background_state": str(normalized.get("background_state", "")),
		"host_config_loaded": bool(normalized.get("host_config_loaded", false)),
		"host_url": str(normalized.get("host_url", "")),
		"host_start_in_progress": bool(normalized.get("host_start_in_progress", false)),
		"host_process_id": int(normalized.get("host_process_id", -1)),
		"host_process_owned_by_addon": bool(normalized.get("host_process_owned_by_addon", false)),
		"trust_mode": str(normalized.get("trust_mode", "off")),
		"active_project_root": str(normalized.get("active_project_root", "")),
		"project_mismatch": bool(normalized.get("project_mismatch", false)),
	}


static func request_success_result(action: String, state: Dictionary) -> Dictionary:
	return ok(result_data(action, state))


static func request_effect_result_plan(plan: Dictionary, effect_plan: Dictionary, success_action: String, state: Dictionary) -> Dictionary:
	var result := {}
	if not bool(plan.get("ok", false)):
		result = effect_plan.get("result", plan) as Dictionary
	else:
		result = request_success_result(success_action, state)
	return {
		"effects": effect_plan.get("effects", []) as Array,
		"result": result,
	}


static func request_failure_effect_plan(plan: Dictionary) -> Dictionary:
	var effects: Array[Dictionary] = []
	if bool(plan.get("connect_first", false)):
		effects.append({"action": "connect_host"})
	return {
		"effects": effects,
		"result": plan,
	}


static func connect_host_request_effect_plan(plan: Dictionary) -> Dictionary:
	if not bool(plan.get("ok", false)):
		return request_failure_effect_plan(plan)
	return {
		"effects": [
			{"action": "connect_host"},
		],
	}


static func enable_tools_request_effect_plan(plan: Dictionary) -> Dictionary:
	if not bool(plan.get("ok", false)):
		return request_failure_effect_plan(plan)
	return {
		"effects": [
			{"action": "enable_tools"},
		],
	}


static func send_message_request_effect_plan(plan: Dictionary) -> Dictionary:
	if not bool(plan.get("ok", false)):
		return request_failure_effect_plan(plan)
	var data := plan.get("data", {}) as Dictionary
	return {
		"effects": [
			{
				"action": "set_attachment_flags",
				"value": data.get("attachments", {}),
			},
			{
				"action": "set_runtime_options",
				"value": data.get("runtime_options", {}),
			},
			{
				"action": "set_chat_input",
				"text": str(data.get("message", "")),
				"refresh_composer": true,
			},
			{
				"action": "send_chat_message",
			},
		],
	}


static func team_review_request_effect_plan(plan: Dictionary) -> Dictionary:
	if not bool(plan.get("ok", false)):
		return request_failure_effect_plan(plan)
	var data := plan.get("data", {}) as Dictionary
	var effects: Array[Dictionary] = [
		{
			"action": "set_attachment_flags",
			"value": data.get("attachments", {}),
		},
	]
	var prompt := str(data.get("prompt", ""))
	if prompt != "":
		effects.append({
			"action": "set_chat_input",
			"text": prompt,
			"refresh_composer": true,
		})
	effects.append({
		"action": "run_team_review",
	})
	return {
		"effects": effects,
	}


static func cancel_team_review_request_effect_plan(plan: Dictionary) -> Dictionary:
	if not bool(plan.get("ok", false)):
		return request_failure_effect_plan(plan)
	return {
		"effects": [
			{"action": "cancel_team_review"},
		],
	}


static func approval_response_request_effect_plan(plan: Dictionary) -> Dictionary:
	if not bool(plan.get("ok", false)):
		return request_failure_effect_plan(plan)
	var data := plan.get("data", {}) as Dictionary
	return {
		"effects": [
			{
				"action": "set_approval_note",
				"text": str(data.get("note", "")),
			},
			{
				"action": "respond_to_approval",
				"decision": str(data.get("decision", "reject")),
			},
		],
	}
