extends SceneTree

const ChatRequestModel := preload("res://addons/godot_codex_bridge/core/chat_request_model.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge chat request model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge chat request model tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var denied := ChatRequestModel.permission_denied("nope")
	_assert_false(bool(denied.get("ok", true)), "permission denied fails")
	_assert_eq((denied.get("error", {}) as Dictionary).get("code"), "permission_denied", "permission denied code")

	var disconnected := ChatRequestModel.chat_not_connected("offline")
	_assert_false(bool(disconnected.get("ok", true)), "not connected fails")
	_assert_eq((disconnected.get("error", {}) as Dictionary).get("message"), "offline", "not connected message")

	var attach_pending := ChatRequestModel.project_attach_pending("attach first")
	_assert_false(bool(attach_pending.get("ok", true)), "attach pending fails")
	_assert_eq((attach_pending.get("error", {}) as Dictionary).get("code"), "project_attach_pending", "attach pending code")

	_assert_true(ChatRequestModel.is_codex_chat_request_type("connect_codex_chat_host"), "connect request type known")
	_assert_true(ChatRequestModel.is_codex_chat_request_type("enable_codex_bridge_tools"), "enable request type known")
	_assert_true(ChatRequestModel.is_codex_chat_request_type("send_codex_chat_message"), "send request type known")
	_assert_true(ChatRequestModel.is_codex_chat_request_type("start_codex_background_team_review"), "team request type known")
	_assert_true(ChatRequestModel.is_codex_chat_request_type("cancel_codex_background_team_review"), "cancel team request type known")
	_assert_true(ChatRequestModel.is_codex_chat_request_type("respond_codex_chat_approval"), "approval request type known")
	_assert_false(ChatRequestModel.is_codex_chat_request_type("get_codex_chat_layout_status"), "layout request type not chat")
	_assert_false(ChatRequestModel.is_codex_chat_request_type("unsupported_request"), "unsupported request type not chat")

	var empty_message := ChatRequestModel.validate_message_payload({"message": "   "})
	_assert_false(bool(empty_message.get("ok", true)), "empty message rejected")
	_assert_eq((empty_message.get("error", {}) as Dictionary).get("code"), "message_required", "empty message code")

	var message := ChatRequestModel.validate_message_payload({"message": "  labas  "})
	_assert_true(bool(message.get("ok", false)), "message accepted")
	_assert_eq((message.get("data", {}) as Dictionary).get("message"), "labas", "message trimmed")

	var invalid_decision := ChatRequestModel.validate_approval_decision({"decision": "maybe"})
	_assert_false(bool(invalid_decision.get("ok", true)), "invalid decision rejected")
	_assert_eq((invalid_decision.get("error", {}) as Dictionary).get("code"), "invalid_decision", "invalid decision code")

	var decision := ChatRequestModel.validate_approval_decision({"decision": "approve_session", "note": "go"})
	_assert_true(bool(decision.get("ok", false)), "decision accepted")
	_assert_eq((decision.get("data", {}) as Dictionary).get("decision"), "approve_session", "decision value")
	_assert_eq((decision.get("data", {}) as Dictionary).get("note"), "go", "decision note")

	_assert_true(bool(ChatRequestModel.connect_host_request_plan(true).get("ok", false)), "connect host request allowed")
	_assert_eq((ChatRequestModel.connect_host_request_plan(false).get("error", {}) as Dictionary).get("code"), "permission_denied", "connect host permission")

	var enable_pending_attach := ChatRequestModel.enable_tools_request_plan(true, true)
	_assert_false(bool(enable_pending_attach.get("ok", true)), "enable tools waits for attach")
	_assert_eq((enable_pending_attach.get("error", {}) as Dictionary).get("code"), "project_attach_pending", "enable tools attach code")
	var enable_tools := ChatRequestModel.enable_tools_request_plan(true, true, "C:/project")
	_assert_true(bool(enable_tools.get("ok", false)), "enable tools request allowed")
	_assert_eq((ChatRequestModel.enable_tools_request_plan(false, true, "C:/project").get("error", {}) as Dictionary).get("code"), "permission_denied", "enable tools permission")
	_assert_eq((ChatRequestModel.enable_tools_request_plan(true, false, "C:/project").get("error", {}) as Dictionary).get("code"), "chat_host_not_connected", "enable tools socket")
	_assert_eq((ChatRequestModel.enable_tools_request_plan(true, true, "C:/project", true).get("error", {}) as Dictionary).get("code"), "project_mismatch", "enable tools mismatch")

	var send_plan := ChatRequestModel.send_message_request_plan(true, true, {
		"message": "  labas  ",
		"attachments": {"context_snapshot": true},
		"model": "gpt-5",
	}, "C:/project")
	_assert_true(bool(send_plan.get("ok", false)), "send message request allowed")
	_assert_eq((send_plan.get("data", {}) as Dictionary).get("message"), "labas", "send plan message")
	_assert_eq(((send_plan.get("data", {}) as Dictionary).get("attachments", {}) as Dictionary).get("context_snapshot"), true, "send plan attachments")
	var send_pending_attach := ChatRequestModel.send_message_request_plan(true, true, {"message": "labas"})
	_assert_eq((send_pending_attach.get("error", {}) as Dictionary).get("code"), "project_attach_pending", "send message attach code")
	var send_mismatch := ChatRequestModel.send_message_request_plan(true, true, {"message": "labas"}, "C:/project", true)
	_assert_eq((send_mismatch.get("error", {}) as Dictionary).get("code"), "project_mismatch", "send message mismatch")
	var send_disconnected := ChatRequestModel.send_message_request_plan(true, false, {"message": "labas"})
	_assert_false(bool(send_disconnected.get("ok", true)), "send disconnected rejected")
	_assert_true(bool(send_disconnected.get("connect_first", false)), "send disconnected connects first")

	var team_plan := ChatRequestModel.team_review_request_plan(true, true, true, {
		"prompt": "  review  ",
		"attachments": {"selected_nodes": true},
	}, "C:/project")
	_assert_true(bool(team_plan.get("ok", false)), "team request allowed")
	_assert_eq((team_plan.get("data", {}) as Dictionary).get("prompt"), "review", "team prompt")
	_assert_eq(((team_plan.get("data", {}) as Dictionary).get("attachments", {}) as Dictionary).get("selected_nodes"), true, "team attachments")
	_assert_eq((ChatRequestModel.team_review_request_plan(true, false, true, {}, "C:/project").get("error", {}) as Dictionary).get("code"), "permission_denied", "team background permission")
	_assert_eq((ChatRequestModel.team_review_request_plan(true, true, true, {}).get("error", {}) as Dictionary).get("code"), "project_attach_pending", "team attach pending")
	_assert_eq((ChatRequestModel.team_review_request_plan(true, true, true, {}, "C:/project", true).get("error", {}) as Dictionary).get("code"), "project_mismatch", "team mismatch")
	var team_disconnected := ChatRequestModel.team_review_request_plan(true, true, false, {})
	_assert_true(bool(team_disconnected.get("connect_first", false)), "team disconnected connects first")

	_assert_true(bool(ChatRequestModel.cancel_team_review_request_plan(true).get("ok", false)), "cancel team allowed")
	_assert_eq((ChatRequestModel.cancel_team_review_request_plan(false).get("error", {}) as Dictionary).get("code"), "chat_host_not_connected", "cancel team socket")

	var approval_plan := ChatRequestModel.approval_response_request_plan(true, true, {"decision": "revise", "note": "change"})
	_assert_true(bool(approval_plan.get("ok", false)), "approval response allowed")
	_assert_eq((approval_plan.get("data", {}) as Dictionary).get("decision"), "revise", "approval response decision")
	_assert_eq((ChatRequestModel.approval_response_request_plan(false, true, {}).get("error", {}) as Dictionary).get("code"), "approval_unavailable", "approval unavailable")
	_assert_eq((ChatRequestModel.approval_response_request_plan(true, false, {}).get("error", {}) as Dictionary).get("code"), "chat_host_not_connected", "approval socket")

	var invalid_addon_rpc := ChatRequestModel.addon_rpc_request_plan({
		"request_id": "outer-1",
		"request": "bad",
	})
	_assert_false(bool(invalid_addon_rpc.get("ok", true)), "invalid addon rpc rejected")
	_assert_eq(invalid_addon_rpc.get("request_id"), "outer-1", "invalid addon rpc request id")
	_assert_eq((invalid_addon_rpc.get("error", {}) as Dictionary).get("code"), "invalid_rpc_request", "invalid addon rpc code")

	var addon_rpc_outer_id := ChatRequestModel.addon_rpc_request_plan({
		"request_id": "outer-2",
		"request": {"type": "refresh_context"},
	})
	_assert_true(bool(addon_rpc_outer_id.get("ok", false)), "addon rpc outer id accepted")
	_assert_eq(addon_rpc_outer_id.get("request_id"), "outer-2", "addon rpc outer request id")
	_assert_eq((addon_rpc_outer_id.get("request", {}) as Dictionary).get("type"), "refresh_context", "addon rpc request preserved")

	var addon_rpc_default_id := ChatRequestModel.addon_rpc_request_plan({
		"request": {"type": "refresh_context"},
	})
	_assert_true(bool(addon_rpc_default_id.get("ok", false)), "addon rpc default id accepted")
	_assert_eq(addon_rpc_default_id.get("request_id"), "websocket_rpc", "addon rpc default id")

	var invalid_addon_rpc_effects := (ChatRequestModel.addon_rpc_effect_plan({
		"request_id": "outer-3",
		"request": "bad",
	}).get("effects", []) as Array)
	_assert_eq(invalid_addon_rpc_effects.size(), 1, "invalid addon rpc effect count")
	var invalid_addon_rpc_effect := invalid_addon_rpc_effects[0] as Dictionary
	_assert_eq(invalid_addon_rpc_effect.get("action"), "send_addon_error_response", "invalid addon rpc sends error response")
	_assert_eq(invalid_addon_rpc_effect.get("request_id"), "outer-3", "invalid addon rpc effect request id")
	_assert_eq(invalid_addon_rpc_effect.get("error_code"), "invalid_rpc_request", "invalid addon rpc effect code")
	_assert_eq(invalid_addon_rpc_effect.get("request_source"), "websocket_rpc", "invalid addon rpc effect source")

	var valid_addon_rpc_effects := (ChatRequestModel.addon_rpc_effect_plan({
		"request_id": "outer-4",
		"request": {"type": "refresh_context"},
	}).get("effects", []) as Array)
	_assert_eq(valid_addon_rpc_effects.size(), 1, "valid addon rpc effect count")
	var valid_addon_rpc_effect := valid_addon_rpc_effects[0] as Dictionary
	_assert_eq(valid_addon_rpc_effect.get("action"), "handle_addon_request", "valid addon rpc handles request")
	_assert_eq(valid_addon_rpc_effect.get("request_id"), "outer-4", "valid addon rpc effect request id")
	_assert_eq((valid_addon_rpc_effect.get("request", {}) as Dictionary).get("type"), "refresh_context", "valid addon rpc effect request")
	_assert_eq(valid_addon_rpc_effect.get("request_source"), "websocket_rpc", "valid addon rpc effect source")

	var normalized_state := ChatRequestModel.request_state({
		"chat_request_id": "15",
		"connection_state": 123,
		"runtime_state": "ready",
		"host_config_loaded": true,
		"host_process_id": 456,
		"active_project_root": "C:/project",
		"project_mismatch": true,
	})
	_assert_eq(normalized_state.get("chat_request_id"), 15, "request state normalizes id")
	_assert_eq(normalized_state.get("connection_state"), "123", "request state normalizes connection")
	_assert_true(bool(normalized_state.get("host_process_owned_by_addon", false)), "request state infers owned host")
	_assert_eq(normalized_state.get("trust_mode"), "off", "request state default trust")
	_assert_eq(normalized_state.get("active_project_root"), "C:/project", "request state active project")
	_assert_true(bool(normalized_state.get("project_mismatch", false)), "request state project mismatch")

	var explicit_host_owner := ChatRequestModel.request_state({
		"host_process_id": 456,
		"host_process_owned_by_addon": false,
	})
	_assert_false(bool(explicit_host_owner.get("host_process_owned_by_addon", true)), "request state honors explicit host owner")

	var request_context := ChatRequestModel.request_context({
		"chat_permission_enabled": true,
		"background_permission_enabled": true,
		"socket_ready": true,
		"has_active_approval": true,
		"active_project_root": "C:/project",
		"project_mismatch": false,
	})
	_assert_true(bool(request_context.get("chat_permission_enabled", false)), "request context chat permission")
	_assert_true(bool(request_context.get("background_permission_enabled", false)), "request context background permission")
	_assert_true(bool(request_context.get("socket_ready", false)), "request context socket")
	_assert_true(bool(request_context.get("has_active_approval", false)), "request context approval")
	_assert_eq(request_context.get("active_project_root"), "C:/project", "request context active project")
	_assert_false(bool(request_context.get("project_mismatch", true)), "request context project mismatch")

	var mismatch_context := request_context.duplicate()
	mismatch_context["project_mismatch"] = true
	var mismatch_dispatch := ChatRequestModel.request_dispatch_plan(
		"send_codex_chat_message",
		mismatch_context,
		{"message": "dispatch"}
	)
	_assert_eq(((mismatch_dispatch.get("plan", {}) as Dictionary).get("error", {}) as Dictionary).get("code"), "project_mismatch", "send dispatch mismatch")
	_assert_eq((mismatch_dispatch.get("effect_plan", {}) as Dictionary).get("effects", []), [], "send dispatch mismatch no effects")

	var send_dispatch := ChatRequestModel.request_dispatch_plan(
		"send_codex_chat_message",
		request_context,
		{
			"message": "dispatch",
			"attachments": {"context_snapshot": true},
		}
	)
	_assert_eq(send_dispatch.get("success_action"), "thread.send", "send dispatch success action")
	_assert_true(bool((send_dispatch.get("plan", {}) as Dictionary).get("ok", false)), "send dispatch plan ok")
	_assert_eq(_effect_action((send_dispatch.get("effect_plan", {}) as Dictionary).get("effects", []) as Array, 3), "send_chat_message", "send dispatch send effect")

	var enable_dispatch_offline := ChatRequestModel.request_dispatch_plan(
		"enable_codex_bridge_tools",
		{"chat_permission_enabled": true, "socket_ready": false},
		{}
	)
	_assert_eq(((enable_dispatch_offline.get("plan", {}) as Dictionary).get("error", {}) as Dictionary).get("code"), "chat_host_not_connected", "enable dispatch disconnected")

	var approval_dispatch := ChatRequestModel.request_dispatch_plan(
		"respond_codex_chat_approval",
		request_context,
		{"decision": "approve_session", "note": "go"}
	)
	_assert_eq(approval_dispatch.get("success_action"), "approval.respond", "approval dispatch success action")
	_assert_eq(_effect_action((approval_dispatch.get("effect_plan", {}) as Dictionary).get("effects", []) as Array, 1), "respond_to_approval", "approval dispatch response effect")
	_assert_eq((((approval_dispatch.get("effect_plan", {}) as Dictionary).get("effects", []) as Array)[1] as Dictionary).get("decision"), "approve_session", "approval dispatch decision")

	var team_dispatch_denied := ChatRequestModel.request_dispatch_plan(
		"start_codex_background_team_review",
		{
			"chat_permission_enabled": true,
			"background_permission_enabled": false,
			"socket_ready": true,
		},
		{}
	)
	_assert_eq(((team_dispatch_denied.get("plan", {}) as Dictionary).get("error", {}) as Dictionary).get("code"), "permission_denied", "team dispatch background permission")

	var unsupported_dispatch_result := ChatRequestModel.request_dispatch_effect_result_plan(
		"not_a_chat_request",
		request_context,
		{},
		{}
	)
	_assert_false(bool((unsupported_dispatch_result.get("result", {}) as Dictionary).get("ok", true)), "unsupported dispatch result fails")
	_assert_eq((((unsupported_dispatch_result.get("result", {}) as Dictionary).get("error", {}) as Dictionary).get("code")), "unsupported_chat_request", "unsupported dispatch error")

	var result := ChatRequestModel.result_data("thread.send", {
		"chat_request_id": 12,
		"connection_state": "ready",
		"runtime_state": "turn_running",
		"thread_id": "thread-1",
		"turn_id": "turn-1",
		"background_task_id": "background-1",
		"background_state": "running",
		"host_config_loaded": true,
		"host_url": "ws://127.0.0.1:49390",
		"host_start_in_progress": false,
		"host_process_id": 123,
		"host_process_owned_by_addon": true,
		"trust_mode": "full_machine",
		"active_project_root": "C:/project",
		"project_mismatch": true,
	})
	_assert_eq(result.get("action"), "thread.send", "result action")
	_assert_true(bool(result.get("sent", false)), "result sent")
	_assert_eq(result.get("chat_request_id"), 12, "result request id")
	_assert_eq(result.get("trust_mode"), "full_machine", "result trust")
	_assert_eq(result.get("active_project_root"), "C:/project", "result active project")
	_assert_true(bool(result.get("project_mismatch", false)), "result project mismatch")

	var success := ChatRequestModel.request_success_result("thread.send", {
		"chat_request_id": 13,
		"connection_state": "ready",
	})
	_assert_true(bool(success.get("ok", false)), "success wrapper ok")
	_assert_eq((success.get("data", {}) as Dictionary).get("action"), "thread.send", "success wrapper action")
	_assert_eq((success.get("data", {}) as Dictionary).get("chat_request_id"), 13, "success wrapper request id")

	var success_result_plan := ChatRequestModel.request_effect_result_plan(
		send_plan,
		ChatRequestModel.send_message_request_effect_plan(send_plan),
		"thread.send",
		{
			"chat_request_id": 14,
			"connection_state": "ready",
			"trust_mode": "full_machine",
		}
	)
	_assert_eq((success_result_plan.get("effects", []) as Array).size(), 4, "success result plan keeps effects")
	_assert_true(bool((success_result_plan.get("result", {}) as Dictionary).get("ok", false)), "success result plan ok")
	_assert_eq(((success_result_plan.get("result", {}) as Dictionary).get("data", {}) as Dictionary).get("action"), "thread.send", "success result plan action")
	_assert_eq(((success_result_plan.get("result", {}) as Dictionary).get("data", {}) as Dictionary).get("chat_request_id"), 14, "success result plan state")

	var failure_with_connect := ChatRequestModel.request_failure_effect_plan(send_disconnected)
	_assert_eq(((failure_with_connect.get("effects", []) as Array)[0] as Dictionary).get("action"), "connect_host", "failure plan connect effect")
	_assert_eq(((failure_with_connect.get("result", {}) as Dictionary).get("error", {}) as Dictionary).get("code"), "chat_host_not_connected", "failure plan preserves result")

	var failure_without_connect := ChatRequestModel.request_failure_effect_plan(ChatRequestModel.chat_not_connected("offline"))
	_assert_eq((failure_without_connect.get("effects", []) as Array).size(), 0, "failure plan no connect effect")
	_assert_eq(((failure_without_connect.get("result", {}) as Dictionary).get("error", {}) as Dictionary).get("message"), "offline", "failure plan no-connect result")

	var failure_result_plan := ChatRequestModel.request_effect_result_plan(
		send_disconnected,
		ChatRequestModel.send_message_request_effect_plan(send_disconnected),
		"thread.send",
		{}
	)
	_assert_eq((failure_result_plan.get("effects", []) as Array).size(), 1, "failure result plan keeps connect effect")
	_assert_false(bool((failure_result_plan.get("result", {}) as Dictionary).get("ok", true)), "failure result plan fails")
	_assert_eq(((failure_result_plan.get("result", {}) as Dictionary).get("error", {}) as Dictionary).get("code"), "chat_host_not_connected", "failure result plan error")

	var connect_effects := (ChatRequestModel.connect_host_request_effect_plan(ChatRequestModel.connect_host_request_plan(true)).get("effects", []) as Array)
	_assert_eq(connect_effects.size(), 1, "connect request effect count")
	_assert_eq(_effect_action(connect_effects, 0), "connect_host", "connect request effect")

	var enable_effects := (ChatRequestModel.enable_tools_request_effect_plan(enable_tools).get("effects", []) as Array)
	_assert_eq(enable_effects.size(), 1, "enable tools effect count")
	_assert_eq(_effect_action(enable_effects, 0), "enable_tools", "enable tools effect")

	var send_effects := (ChatRequestModel.send_message_request_effect_plan(send_plan).get("effects", []) as Array)
	_assert_eq(send_effects.size(), 4, "send request effect count")
	_assert_eq(_effect_action(send_effects, 0), "set_attachment_flags", "send request attachment effect")
	_assert_eq(_effect_action(send_effects, 1), "set_runtime_options", "send request runtime effect")
	_assert_eq(_effect_action(send_effects, 2), "set_chat_input", "send request input effect")
	_assert_eq((send_effects[2] as Dictionary).get("text"), "labas", "send request input text")
	_assert_eq((send_effects[2] as Dictionary).get("refresh_composer"), true, "send request refreshes composer")
	_assert_eq(_effect_action(send_effects, 3), "send_chat_message", "send request send effect")

	var send_disconnected_effect_plan := ChatRequestModel.send_message_request_effect_plan(send_disconnected)
	var send_disconnected_effects := (send_disconnected_effect_plan.get("effects", []) as Array)
	_assert_eq(send_disconnected_effects.size(), 1, "send disconnected effect count")
	_assert_eq(_effect_action(send_disconnected_effects, 0), "connect_host", "send disconnected connect effect")
	_assert_eq(((send_disconnected_effect_plan.get("result", {}) as Dictionary).get("error", {}) as Dictionary).get("code"), "chat_host_not_connected", "send disconnected effect result")

	var team_effects := (ChatRequestModel.team_review_request_effect_plan(team_plan).get("effects", []) as Array)
	_assert_eq(team_effects.size(), 3, "team request effect count")
	_assert_eq(_effect_action(team_effects, 0), "set_attachment_flags", "team request attachment effect")
	_assert_eq(_effect_action(team_effects, 1), "set_chat_input", "team request input effect")
	_assert_eq((team_effects[1] as Dictionary).get("text"), "review", "team request input text")
	_assert_eq(_effect_action(team_effects, 2), "run_team_review", "team request run effect")

	var team_empty_effects := (ChatRequestModel.team_review_request_effect_plan(ChatRequestModel.team_review_request_plan(true, true, true, {}, "C:/project")).get("effects", []) as Array)
	_assert_eq(team_empty_effects.size(), 2, "team empty prompt effect count")
	_assert_eq(_effect_action(team_empty_effects, 0), "set_attachment_flags", "team empty prompt attachment effect")
	_assert_eq(_effect_action(team_empty_effects, 1), "run_team_review", "team empty prompt run effect")

	var cancel_team_effects := (ChatRequestModel.cancel_team_review_request_effect_plan(ChatRequestModel.cancel_team_review_request_plan(true)).get("effects", []) as Array)
	_assert_eq(cancel_team_effects.size(), 1, "cancel team request effect count")
	_assert_eq(_effect_action(cancel_team_effects, 0), "cancel_team_review", "cancel team request effect")

	var approval_effects := (ChatRequestModel.approval_response_request_effect_plan(approval_plan).get("effects", []) as Array)
	_assert_eq(approval_effects.size(), 2, "approval request effect count")
	_assert_eq(_effect_action(approval_effects, 0), "set_approval_note", "approval request note effect")
	_assert_eq((approval_effects[0] as Dictionary).get("text"), "change", "approval request note text")
	_assert_eq(_effect_action(approval_effects, 1), "respond_to_approval", "approval request response effect")
	_assert_eq((approval_effects[1] as Dictionary).get("decision"), "revise", "approval request decision")

	var app_effects := ChatRequestModel.request_application_effects([
		"bad",
		{"action": "unknown_action", "text": "ignored"},
		{"action": "set_runtime_options", "value": "bad"},
		{"action": "set_chat_input", "text": 123, "refresh_composer": 1},
		{"action": "set_approval_note", "text": 456},
		{"action": "respond_to_approval"},
		{"action": "connect_host", "extra": "ignored"},
	])
	_assert_eq(app_effects.size(), 5, "application effects filter invalid and unknown")
	_assert_eq((app_effects[0] as Dictionary).get("action"), "set_runtime_options", "application runtime action")
	_assert_eq(((app_effects[0] as Dictionary).get("value", {}) as Dictionary).size(), 0, "application runtime value normalized")
	_assert_eq((app_effects[1] as Dictionary).get("text"), "123", "application chat input text normalized")
	_assert_true(bool((app_effects[1] as Dictionary).get("refresh_composer", false)), "application chat input refresh normalized")
	_assert_eq((app_effects[2] as Dictionary).get("text"), "456", "application approval note text normalized")
	_assert_eq((app_effects[3] as Dictionary).get("decision"), "reject", "application approval decision default")
	_assert_eq((app_effects[4] as Dictionary).get("action"), "connect_host", "application simple action preserved")


func _effect_action(effects: Array, index: int) -> String:
	if index < 0 or index >= effects.size():
		return ""
	var effect := effects[index] as Dictionary
	return str(effect.get("action", ""))


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures += 1
		push_error(label + " expected=" + str(expected) + " actual=" + str(actual))


func _assert_true(value: bool, label: String) -> void:
	if not value:
		_failures += 1
		push_error(label)


func _assert_false(value: bool, label: String) -> void:
	if value:
		_failures += 1
		push_error(label)
