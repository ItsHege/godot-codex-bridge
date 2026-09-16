extends SceneTree

const ChatActionModel := preload("res://addons/godot_codex_bridge/core/chat_action_model.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge chat action model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge chat action model tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var attachments := ChatActionModel.attachment_flags(true, false, true, true)
	_assert_true(bool(attachments.get("context_snapshot", false)), "context attachment")
	_assert_false(bool(attachments.get("selected_nodes", true)), "selected attachment")
	_assert_true(bool(attachments.get("latest_screenshot", false)), "screenshot attachment")
	_assert_true(bool(attachments.get("latest_annotation", false)), "annotation attachment")
	_assert_true(bool(attachments.get("gameplay_context", false)), "gameplay context default")
	_assert_true(bool(attachments.get("script_inventory", false)), "script inventory default")
	var attachment_updates := ChatActionModel.attachment_flag_updates({
		"context_snapshot": false,
		"latest_screenshot": true,
	}, true, true, false)
	_assert_true(attachment_updates.has("context_snapshot"), "attachment update includes context")
	_assert_false(bool(attachment_updates.get("context_snapshot", true)), "attachment update context false")
	_assert_false(attachment_updates.has("selected_nodes"), "attachment update omits untouched selected")
	_assert_true(bool(attachment_updates.get("latest_screenshot", false)), "attachment update screenshot true")
	_assert_true(ChatActionModel.attachment_flag_updates("bad", true, true, true).is_empty(), "bad attachment update ignored")
	_assert_true(ChatActionModel.needs_screenshot_capture(attachments, true), "screenshot capture allowed")
	_assert_false(ChatActionModel.needs_screenshot_capture(attachments, false), "screenshot capture denied")
	_assert_true(ChatActionModel.needs_context_snapshot(attachments), "context snapshot required")

	var annotation := ChatActionModel.annotation_payload({"annotation_id": " marker-a "})
	_assert_eq(annotation.get("annotation_id"), "marker-a", "annotation id trimmed")
	_assert_true(bool(annotation.get("include_image", false)), "annotation include image")
	_assert_eq(annotation.get("detail"), "high", "annotation detail")
	_assert_true(ChatActionModel.annotation_payload({}).is_empty(), "missing annotation omitted")

	var send_payload := ChatActionModel.thread_send_payload(
		"labas",
		"thread-1",
		attachments,
		{"annotation_id": "ann-1"},
		" gpt-5.5 ",
		" high "
	)
	_assert_eq(send_payload.get("thread_id"), "thread-1", "thread id included")
	_assert_eq(send_payload.get("message"), "labas", "message included")
	_assert_eq(send_payload.get("model"), "gpt-5.5", "model trimmed")
	_assert_eq(send_payload.get("effort"), "high", "effort trimmed")
	_assert_eq((send_payload.get("annotation", {}) as Dictionary).get("annotation_id"), "ann-1", "annotation included")

	var new_thread_payload := ChatActionModel.thread_send_payload("x", "", {}, {}, "", "")
	_assert_eq(new_thread_payload.get("thread_id"), null, "empty thread becomes null")
	_assert_false(new_thread_payload.has("model"), "empty model omitted")
	_assert_false(new_thread_payload.has("effort"), "empty effort omitted")
	_assert_false(new_thread_payload.has("annotation"), "empty annotation omitted")

	var preflight_ok := ChatActionModel.chat_message_preflight(true, true, " labas ")
	_assert_true(bool(preflight_ok.get("ok", false)), "chat preflight ok")
	_assert_eq(preflight_ok.get("message"), "labas", "chat preflight trims message")
	_assert_eq(ChatActionModel.chat_message_preflight(false, true, "x").get("code"), "permission_denied", "chat preflight permission")
	_assert_eq(ChatActionModel.chat_message_preflight(true, true, "  ").get("action"), "ignore", "chat preflight ignores blank")
	_assert_eq(ChatActionModel.chat_message_preflight(true, true, "x", true).get("code"), "project_mismatch", "chat preflight project mismatch")
	_assert_eq(ChatActionModel.chat_message_preflight(true, false, "x").get("action"), "connect", "chat preflight connects")
	var chat_connect_effects := ChatActionModel.chat_message_preflight_effect_plan(
		ChatActionModel.chat_message_preflight(true, false, "x")
	).get("effects", []) as Array
	_assert_eq(chat_connect_effects.size(), 2, "chat preflight connect effects count")
	_assert_eq((chat_connect_effects[0] as Dictionary).get("type"), "system_message", "chat preflight connect message")
	_assert_eq((chat_connect_effects[1] as Dictionary).get("type"), "connect_host", "chat preflight connect host")
	var chat_blank_effects := ChatActionModel.chat_message_preflight_effect_plan(
		ChatActionModel.chat_message_preflight(true, true, "  ")
	).get("effects", []) as Array
	_assert_true(chat_blank_effects.is_empty(), "chat preflight blank has no effects")

	var send_plan := ChatActionModel.chat_send_plan(
		" build it ",
		"thread-2",
		true,
		true,
		true,
		true,
		{"annotation_id": "ann-2"},
		"gpt-5.5",
		"high",
		true
	)
	_assert_eq(send_plan.get("method"), "thread.send", "send plan method")
	_assert_true(bool(send_plan.get("capture_screenshot", false)), "send plan captures screenshot")
	_assert_true(bool(send_plan.get("write_context_snapshot", false)), "send plan writes context")
	_assert_true(bool(send_plan.get("clear_pending_annotation", false)), "send plan clears annotation")
	var send_plan_params := send_plan.get("params", {}) as Dictionary
	_assert_eq(send_plan_params.get("message"), "build it", "send plan trims payload message")
	_assert_eq(send_plan_params.get("thread_id"), "thread-2", "send plan thread id")
	_assert_eq((send_plan_params.get("annotation", {}) as Dictionary).get("annotation_id"), "ann-2", "send plan annotation")

	var send_effect_plan := ChatActionModel.chat_send_effect_plan(send_plan, " build it ")
	var send_effects := send_effect_plan.get("effects", []) as Array
	_assert_eq(send_effects.size(), 8, "send effect count")
	_assert_eq((send_effects[0] as Dictionary).get("type"), "capture_screenshot", "send effect screenshot first")
	_assert_eq((send_effects[0] as Dictionary).get("reason"), "codex_chat", "send effect screenshot reason")
	_assert_eq((send_effects[1] as Dictionary).get("type"), "write_context_snapshot", "send effect context second")
	_assert_eq((send_effects[2] as Dictionary).get("type"), "append_user_message", "send effect append user")
	_assert_eq((send_effects[2] as Dictionary).get("message"), "build it", "send effect trims user message")
	_assert_eq((send_effects[3] as Dictionary).get("type"), "clear_chat_input", "send effect clears input")
	_assert_eq((send_effects[4] as Dictionary).get("type"), "refresh_composer_height", "send effect refreshes composer")
	_assert_eq((send_effects[5] as Dictionary).get("type"), "send_json", "send effect sends json")
	_assert_eq((send_effects[5] as Dictionary).get("method"), "thread.send", "send effect json method")
	_assert_eq((send_effects[5] as Dictionary).get("params"), send_plan.get("params"), "send effect json params")
	_assert_eq((send_effects[6] as Dictionary).get("type"), "clear_pending_annotation", "send effect clears annotation")
	_assert_false(bool((send_effects[6] as Dictionary).get("notify", true)), "send effect clears annotation quietly")
	_assert_eq((send_effects[7] as Dictionary).get("type"), "update_ui", "send effect updates ui")

	var simple_send_plan := ChatActionModel.chat_send_plan(
		"hello",
		"",
		false,
		false,
		false,
		false,
		{},
		"",
		"",
		true
	)
	var simple_effects := ChatActionModel.chat_send_effect_plan(simple_send_plan, "hello").get("effects", []) as Array
	_assert_eq(simple_effects.size(), 6, "simple send effect count")
	_assert_eq((simple_effects[0] as Dictionary).get("type"), "write_context_snapshot", "simple send writes default context")
	_assert_eq((simple_effects[1] as Dictionary).get("type"), "append_user_message", "simple send appends user message")
	_assert_eq((simple_effects[4] as Dictionary).get("type"), "send_json", "simple send still sends json")
	_assert_eq((simple_effects[5] as Dictionary).get("type"), "update_ui", "simple send updates ui")

	var trust_on := ChatActionModel.trust_request(true)
	_assert_eq(trust_on.get("method"), "session.trust.set", "trust set method")
	_assert_eq((trust_on.get("params", {}) as Dictionary).get("mode"), "full_machine", "trust set mode")
	_assert_eq(trust_on.get("local_trust_mode"), "full_machine", "trust local on")

	var trust_off := ChatActionModel.trust_request(false)
	_assert_eq(trust_off.get("method"), "session.trust.clear", "trust clear method")
	_assert_true((trust_off.get("params", {}) as Dictionary).is_empty(), "trust clear params")
	_assert_eq(trust_off.get("local_trust_mode"), "off", "trust local off")

	var blocked_auto_enable := ChatActionModel.auto_enable_tools_request("ready", false, false, true)
	_assert_false(bool(blocked_auto_enable.get("send", true)), "auto enable waits for attached project")
	_assert_eq(blocked_auto_enable.get("reason"), "project_attach_pending", "auto enable attach pending reason")
	var mismatch_auto_enable := ChatActionModel.auto_enable_tools_request("ready", false, false, true, "C:/project", false, true)
	_assert_false(bool(mismatch_auto_enable.get("send", true)), "auto enable blocks project mismatch")
	_assert_eq(mismatch_auto_enable.get("reason"), "project_mismatch", "auto enable mismatch reason")
	var auto_enable := ChatActionModel.auto_enable_tools_request("ready", false, false, true, "C:/project")
	_assert_true(bool(auto_enable.get("send", false)), "auto enable sends when ready")
	_assert_eq(auto_enable.get("method"), "bridge.tools.enable", "auto enable method")
	_assert_true(bool(auto_enable.get("mark_requested", false)), "auto enable marks requested")
	var auto_enable_effects := ChatActionModel.auto_enable_tools_effect_plan(auto_enable).get("effects", []) as Array
	_assert_eq(auto_enable_effects.size(), 4, "auto enable effects count")
	_assert_eq((auto_enable_effects[0] as Dictionary).get("type"), "set_auto_enable_tools_requested", "auto enable marks requested effect")
	_assert_eq((auto_enable_effects[1] as Dictionary).get("type"), "system_message", "auto enable message effect")
	_assert_eq((auto_enable_effects[2] as Dictionary).get("type"), "send_json", "auto enable send effect")
	_assert_eq((auto_enable_effects[2] as Dictionary).get("method"), "bridge.tools.enable", "auto enable send method")
	_assert_eq((auto_enable_effects[3] as Dictionary).get("type"), "update_ui", "auto enable update effect")
	_assert_false(bool(ChatActionModel.auto_enable_tools_request("connecting", false, false, true, "C:/project").get("send", true)), "auto enable waits for ready")
	_assert_false(bool(ChatActionModel.auto_enable_tools_request("ready", true, false, true, "C:/project").get("send", true)), "auto enable skips available tools")
	_assert_false(bool(ChatActionModel.auto_enable_tools_request("ready", false, true, true, "C:/project").get("send", true)), "auto enable skips duplicate")
	var forced_duplicate_auto_enable := ChatActionModel.auto_enable_tools_request("ready", true, true, true, "C:/project", true)
	_assert_false(bool(forced_duplicate_auto_enable.get("send", true)), "forced auto enable still skips in-flight duplicate")
	_assert_eq(forced_duplicate_auto_enable.get("reason"), "already_requested", "forced duplicate reason")
	var forced_auto_enable := ChatActionModel.auto_enable_tools_request("ready", true, false, true, "C:/project", true)
	_assert_true(bool(forced_auto_enable.get("send", false)), "forced auto enable refreshes available tools")
	_assert_true(str(forced_auto_enable.get("message", "")).find("Refreshing") >= 0, "forced auto enable message")
	_assert_false(bool(ChatActionModel.auto_enable_tools_request("ready", false, false, false, "C:/project").get("send", true)), "auto enable respects permission")
	_assert_true((ChatActionModel.auto_enable_tools_effect_plan(ChatActionModel.auto_enable_tools_request("ready", true, false, true, "C:/project")).get("effects", []) as Array).is_empty(), "auto enable no-send has no effects")

	_assert_true(bool(ChatActionModel.team_review_preflight(true, true, true).get("ok", false)), "team preflight ok")
	_assert_eq(ChatActionModel.team_review_preflight(false, true, true).get("code"), "permission_denied", "team preflight chat permission")
	_assert_eq(ChatActionModel.team_review_preflight(true, false, true).get("message"), "Background team review permission is disabled.", "team preflight team permission")
	_assert_eq(ChatActionModel.team_review_preflight(true, true, true, true).get("code"), "project_mismatch", "team preflight project mismatch")
	_assert_eq(ChatActionModel.team_review_preflight(true, true, false).get("action"), "connect", "team preflight connects")
	var team_plan := ChatActionModel.team_review_plan(" inspect scripts ", true)
	_assert_eq(team_plan.get("method"), "background.start", "team plan method")
	_assert_eq(team_plan.get("prompt"), "inspect scripts", "team plan prompt")
	_assert_true(bool(team_plan.get("input_was_used", false)), "team plan input used")
	_assert_true(bool(team_plan.get("write_context_snapshot", false)), "team plan writes context")
	_assert_eq(team_plan.get("background_state"), "queued", "team plan state")
	_assert_true((team_plan.get("params", {}) as Dictionary).has("roles"), "team plan roles")
	var team_effects := ChatActionModel.team_review_effect_plan(team_plan).get("effects", []) as Array
	_assert_eq(team_effects.size(), 8, "team effects count")
	_assert_eq((team_effects[0] as Dictionary).get("type"), "clear_chat_input", "team effects clear input")
	_assert_eq((team_effects[1] as Dictionary).get("type"), "refresh_composer_height", "team effects refresh composer")
	_assert_eq((team_effects[2] as Dictionary).get("type"), "write_context_snapshot", "team effects snapshot")
	_assert_eq((team_effects[2] as Dictionary).get("reason"), "codex_background_team", "team effects snapshot reason")
	_assert_eq((team_effects[3] as Dictionary).get("type"), "set_background_state", "team effects state")
	_assert_eq((team_effects[4] as Dictionary).get("type"), "update_background_status_label", "team effects status label")
	_assert_eq((team_effects[5] as Dictionary).get("type"), "send_json", "team effects send")
	_assert_eq((team_effects[5] as Dictionary).get("method"), "background.start", "team effects send method")
	_assert_eq((team_effects[6] as Dictionary).get("type"), "system_message", "team effects status message")
	_assert_eq((team_effects[7] as Dictionary).get("type"), "update_ui", "team effects update ui")
	var default_team_plan := ChatActionModel.team_review_plan(" ", false)
	_assert_eq(default_team_plan.get("prompt"), "Run a read-only background team review for the current Godot project.", "team plan default prompt")
	_assert_false(bool(default_team_plan.get("input_was_used", true)), "team plan blank input not used")
	var default_team_effects := ChatActionModel.team_review_effect_plan(default_team_plan).get("effects", []) as Array
	_assert_eq(default_team_effects.size(), 5, "default team effects count")
	_assert_eq((default_team_effects[0] as Dictionary).get("type"), "set_background_state", "default team effects no input clear")

	var team_preflight_failure_effects := ChatActionModel.team_review_preflight_effect_plan(
		ChatActionModel.team_review_preflight(true, true, false)
	).get("effects", []) as Array
	_assert_eq(team_preflight_failure_effects.size(), 2, "team preflight failure effect count")
	_assert_eq((team_preflight_failure_effects[0] as Dictionary).get("type"), "system_message", "team preflight failure message")
	_assert_eq((team_preflight_failure_effects[1] as Dictionary).get("type"), "connect_host", "team preflight failure connects")

	var socket_preflight_ok := ChatActionModel.socket_action_preflight(true, true)
	_assert_true(bool(socket_preflight_ok.get("ok", false)), "socket action preflight ok")
	_assert_eq(ChatActionModel.socket_action_preflight(false, true).get("code"), "permission_denied", "socket action permission")
	_assert_eq(ChatActionModel.socket_action_preflight(true, false).get("action"), "connect", "socket action connect")

	var blocked_enable_plan := ChatActionModel.enable_tools_plan(true, true)
	_assert_false(bool(blocked_enable_plan.get("ok", true)), "enable tools waits for attached project")
	_assert_eq(blocked_enable_plan.get("code"), "project_attach_pending", "enable tools attach pending")
	var mismatch_enable_plan := ChatActionModel.enable_tools_plan(true, true, "C:/project", true)
	_assert_false(bool(mismatch_enable_plan.get("ok", true)), "enable tools blocks project mismatch")
	_assert_eq(mismatch_enable_plan.get("code"), "project_mismatch", "enable tools mismatch code")
	var enable_plan := ChatActionModel.enable_tools_plan(true, true, "C:/project")
	_assert_true(bool(enable_plan.get("ok", false)), "enable tools plan ok")
	_assert_eq(enable_plan.get("method"), "bridge.tools.enable", "enable tools method")
	_assert_true(bool(enable_plan.get("mark_requested", false)), "enable tools marks requested")
	var enable_effects := ChatActionModel.enable_tools_effect_plan(enable_plan).get("effects", []) as Array
	_assert_eq(enable_effects.size(), 4, "enable effects count")
	_assert_eq((enable_effects[0] as Dictionary).get("type"), "set_auto_enable_tools_requested", "enable effects mark requested")
	_assert_eq((enable_effects[1] as Dictionary).get("type"), "system_message", "enable effects message")
	_assert_eq((enable_effects[2] as Dictionary).get("type"), "send_json", "enable effects send")
	_assert_eq((enable_effects[3] as Dictionary).get("type"), "update_ui", "enable effects update")
	_assert_eq(ChatActionModel.enable_tools_plan(false, true, "C:/project").get("code"), "permission_denied", "enable tools permission")
	_assert_eq(ChatActionModel.enable_tools_plan(true, false, "C:/project").get("action"), "connect", "enable tools connect")
	var enable_connect_effects := ChatActionModel.enable_tools_effect_plan(ChatActionModel.enable_tools_plan(true, false, "C:/project")).get("effects", []) as Array
	_assert_eq(enable_connect_effects.size(), 2, "enable connect effects count")
	_assert_eq((enable_connect_effects[1] as Dictionary).get("type"), "connect_host", "enable connect effect")

	var cancel_turn := ChatActionModel.cancel_turn_plan(true)
	_assert_eq(cancel_turn.get("method"), "turn.interrupt", "cancel turn method")
	_assert_eq(cancel_turn.get("message"), "Cancel requested.", "cancel turn message")
	var cancel_turn_effects := ChatActionModel.cancel_turn_effect_plan(cancel_turn).get("effects", []) as Array
	_assert_eq(cancel_turn_effects.size(), 2, "cancel turn effects count")
	_assert_eq((cancel_turn_effects[0] as Dictionary).get("type"), "send_json", "cancel turn sends first")
	_assert_eq((cancel_turn_effects[1] as Dictionary).get("type"), "system_message", "cancel turn message second")
	_assert_eq(ChatActionModel.cancel_turn_plan(false).get("action"), "ignore", "cancel turn disconnected ignored")
	_assert_true((ChatActionModel.cancel_turn_effect_plan(ChatActionModel.cancel_turn_plan(false)).get("effects", []) as Array).is_empty(), "cancel turn disconnected no effects")

	var cancel_team := ChatActionModel.cancel_team_review_plan(true, " task-1 ")
	_assert_eq(cancel_team.get("method"), "background.cancel", "cancel team method")
	_assert_eq((cancel_team.get("params", {}) as Dictionary).get("task_id"), "task-1", "cancel team task id")
	var cancel_team_effects := ChatActionModel.cancel_team_review_effect_plan(cancel_team).get("effects", []) as Array
	_assert_eq(cancel_team_effects.size(), 2, "cancel team effects count")
	_assert_eq((cancel_team_effects[0] as Dictionary).get("type"), "send_json", "cancel team sends first")
	_assert_eq((cancel_team_effects[1] as Dictionary).get("type"), "system_message", "cancel team message second")
	_assert_eq(ChatActionModel.cancel_team_review_plan(false, "task-1").get("action"), "ignore", "cancel team disconnected ignored")

	var trust_connected := ChatActionModel.trust_session_plan(true, true)
	_assert_true(bool(trust_connected.get("ok", false)), "trust session connected ok")
	_assert_eq(trust_connected.get("method"), "session.trust.set", "trust session method")
	_assert_eq(trust_connected.get("local_trust_mode"), "full_machine", "trust session local mode")
	var trust_effects := ChatActionModel.trust_session_effect_plan(trust_connected).get("effects", []) as Array
	_assert_eq(trust_effects.size(), 4, "trust effects count")
	_assert_eq((trust_effects[0] as Dictionary).get("type"), "set_trust_mode", "trust effects local first")
	_assert_eq((trust_effects[0] as Dictionary).get("mode"), "full_machine", "trust effects local mode")
	_assert_eq((trust_effects[1] as Dictionary).get("type"), "system_message", "trust effects message")
	_assert_eq((trust_effects[2] as Dictionary).get("type"), "send_json", "trust effects send")
	_assert_eq((trust_effects[3] as Dictionary).get("type"), "update_ui", "trust effects update")
	var trust_disconnected := ChatActionModel.trust_session_plan(true, false)
	_assert_false(bool(trust_disconnected.get("ok", true)), "trust session disconnected blocked")
	_assert_eq(trust_disconnected.get("local_trust_mode"), "off", "trust session disconnected local off")
	_assert_true(bool(trust_disconnected.get("update_ui", false)), "trust session disconnected updates ui")
	var trust_disconnected_effects := ChatActionModel.trust_session_effect_plan(trust_disconnected).get("effects", []) as Array
	_assert_eq(trust_disconnected_effects.size(), 3, "trust disconnected effects count")
	_assert_eq((trust_disconnected_effects[0] as Dictionary).get("type"), "set_trust_mode", "trust disconnected local first")
	_assert_eq((trust_disconnected_effects[1] as Dictionary).get("type"), "update_ui", "trust disconnected updates")
	_assert_eq((trust_disconnected_effects[2] as Dictionary).get("type"), "system_message", "trust disconnected message")

	var emergency := ChatActionModel.emergency_stop_effect_plan(true, "full_machine", "turn-1", "task-1", true)
	var emergency_effects := emergency.get("effects", []) as Array
	_assert_eq((emergency_effects[0] as Dictionary).get("type"), "stop_running_scene", "emergency stops scene first")
	_assert_true(_has_send_method(emergency_effects, "turn.interrupt"), "emergency interrupts turn")
	_assert_true(_has_send_method(emergency_effects, "background.cancel"), "emergency cancels team")
	_assert_true(_has_send_method(emergency_effects, "session.trust.clear"), "emergency clears trust remotely")
	_assert_true(_has_effect_type(emergency_effects, "clear_approval_local"), "emergency clears local approval")
	_assert_true(_has_effect_type(emergency_effects, "disconnect_host"), "emergency disconnects host")
	_assert_true(_has_effect_type(emergency_effects, "update_ui"), "emergency updates ui")
	_assert_eq(_effect_value(emergency_effects, "set_trust_mode", "mode"), "off", "emergency clears local trust")
	_assert_eq(_effect_value(emergency_effects, "set_background_state", "state"), "idle", "emergency clears team state")
	_assert_eq(_effect_value(emergency_effects, "set_background_task_id", "task_id"), "", "emergency clears task id")
	_assert_false(_has_send_method(emergency_effects, "thread.send"), "emergency never sends chat")
	_assert_false(_has_send_method(emergency_effects, "background.start"), "emergency never starts team")
	_assert_false(_has_send_method(emergency_effects, "session.trust.set"), "emergency never enables trust")
	_assert_false(_has_effect_type(emergency_effects, "save_scene"), "emergency never saves scene")
	_assert_false(_has_effect_type(emergency_effects, "save_all_scenes"), "emergency never saves all")

	var emergency_idle := ChatActionModel.emergency_stop_effect_plan(true, "off", "", "", false).get("effects", []) as Array
	_assert_false(_has_send_method(emergency_idle, "turn.interrupt"), "idle emergency skips turn interrupt")
	_assert_false(_has_send_method(emergency_idle, "background.cancel"), "idle emergency skips team cancel")
	_assert_false(_has_send_method(emergency_idle, "session.trust.clear"), "idle emergency skips remote trust clear")
	_assert_false(_has_effect_type(emergency_idle, "clear_approval_local"), "idle emergency skips approval clear")
	_assert_true(_has_effect_type(emergency_idle, "stop_running_scene"), "idle emergency still checks play session")
	_assert_true(_has_effect_type(emergency_idle, "disconnect_host"), "idle emergency still disconnects owned host")

	var emergency_disconnected := ChatActionModel.emergency_stop_effect_plan(false, "full_machine", "turn-1", "task-1", true).get("effects", []) as Array
	_assert_false(_has_send_method(emergency_disconnected, "turn.interrupt"), "disconnected emergency skips remote interrupt")
	_assert_false(_has_send_method(emergency_disconnected, "background.cancel"), "disconnected emergency skips remote cancel")
	_assert_false(_has_send_method(emergency_disconnected, "session.trust.clear"), "disconnected emergency skips remote trust")
	_assert_eq(_effect_value(emergency_disconnected, "set_trust_mode", "mode"), "off", "disconnected emergency clears local trust")

	var options := ChatActionModel.runtime_options_from_payload({"model": " gpt-5 ", "effort": " medium "})
	_assert_eq(options.get("model"), "gpt-5", "runtime model")
	_assert_eq(options.get("effort"), "medium", "runtime effort")

	var selected_index := ChatActionModel.selected_metadata_index([
		{"model": "a"},
		{"model": "b"},
		"bad",
	], "model", " b ")
	_assert_eq(selected_index, 1, "metadata index")
	_assert_eq(ChatActionModel.selected_metadata_index([], "model", "b"), -1, "missing metadata index")


func _has_effect_type(effects: Array, effect_type: String) -> bool:
	for effect in effects:
		if typeof(effect) == TYPE_DICTIONARY and str((effect as Dictionary).get("type", "")) == effect_type:
			return true
	return false


func _has_send_method(effects: Array, method: String) -> bool:
	for effect in effects:
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		var effect_dict := effect as Dictionary
		if str(effect_dict.get("type", "")) == "send_json" and str(effect_dict.get("method", "")) == method:
			return true
	return false


func _effect_value(effects: Array, effect_type: String, key: String) -> Variant:
	for effect in effects:
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		var effect_dict := effect as Dictionary
		if str(effect_dict.get("type", "")) == effect_type:
			return effect_dict.get(key)
	return null


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
