@tool
extends RefCounted

const ChatTeamModel := preload("res://addons/godot_codex_bridge/core/chat_team_model.gd")


static func attachment_flags(include_context: bool, include_selected: bool, include_screenshot: bool, has_pending_annotation: bool) -> Dictionary:
	return {
		"context_snapshot": include_context,
		"selected_nodes": include_selected,
		"latest_screenshot": include_screenshot,
		"latest_annotation": has_pending_annotation,
		"gameplay_context": true,
		"script_inventory": true,
	}


static func attachment_flag_updates(value: Variant, current_context: bool, current_selected: bool, current_screenshot: bool) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var attachments := value as Dictionary
	var updates := {}
	if attachments.has("context_snapshot"):
		updates["context_snapshot"] = bool(attachments.get("context_snapshot", current_context))
	if attachments.has("selected_nodes"):
		updates["selected_nodes"] = bool(attachments.get("selected_nodes", current_selected))
	if attachments.has("latest_screenshot"):
		updates["latest_screenshot"] = bool(attachments.get("latest_screenshot", current_screenshot))
	return updates


static func needs_screenshot_capture(attachments: Dictionary, allow_screenshots: bool) -> bool:
	return allow_screenshots and bool(attachments.get("latest_screenshot", false))


static func needs_context_snapshot(attachments: Dictionary) -> bool:
	return (
		bool(attachments.get("context_snapshot", false))
		or bool(attachments.get("selected_nodes", false))
		or bool(attachments.get("gameplay_context", false))
		or bool(attachments.get("script_inventory", false))
	)


static func annotation_payload(pending_annotation: Dictionary, include_image := true, detail := "high") -> Dictionary:
	var annotation_id := str(pending_annotation.get("annotation_id", "")).strip_edges()
	if annotation_id == "":
		return {}
	return {
		"annotation_id": annotation_id,
		"include_image": include_image,
		"detail": detail,
	}


static func thread_send_payload(message: String, thread_id: String, attachments: Dictionary, pending_annotation: Dictionary, model: String, effort: String) -> Dictionary:
	var payload := {
		"thread_id": thread_id if thread_id != "" else null,
		"message": message,
		"attachments": attachments,
	}
	var annotation := annotation_payload(pending_annotation)
	if not annotation.is_empty():
		payload["annotation"] = annotation
	var selected_model := model.strip_edges()
	if selected_model != "":
		payload["model"] = selected_model
	var selected_effort := effort.strip_edges()
	if selected_effort != "":
		payload["effort"] = selected_effort
	return payload


static func chat_message_preflight(chat_permission_enabled: bool, socket_ready: bool, message: String, project_mismatch := false) -> Dictionary:
	if not chat_permission_enabled:
		return {
			"ok": false,
			"action": "status",
			"code": "permission_denied",
			"message": "Codex chat permission is disabled.",
		}
	if message.strip_edges() == "":
		return {
			"ok": false,
			"action": "ignore",
			"code": "empty_message",
			"message": "",
		}
	if project_mismatch:
		return {
			"ok": false,
			"action": "status",
			"code": "project_mismatch",
			"message": "Reconnect to this project before sending new work.",
		}
	if not socket_ready:
		return {
			"ok": false,
			"action": "connect",
			"code": "chat_host_not_connected",
			"message": "Codex is not connected yet.",
		}
	return {
		"ok": true,
		"message": message.strip_edges(),
	}


static func chat_message_preflight_effect_plan(preflight: Dictionary) -> Dictionary:
	var effects: Array = []
	if bool(preflight.get("ok", false)):
		return {"effects": effects}
	var status_message := str(preflight.get("message", ""))
	if status_message != "":
		effects.append({
			"type": "system_message",
			"message": status_message,
		})
	if str(preflight.get("action", "")) == "connect":
		effects.append({"type": "connect_host"})
	return {"effects": effects}


static func chat_send_plan(
	message: String,
	thread_id: String,
	include_context: bool,
	include_selected: bool,
	include_screenshot: bool,
	has_pending_annotation: bool,
	pending_annotation: Dictionary,
	model: String,
	effort: String,
	allow_screenshots: bool
) -> Dictionary:
	var attachments := attachment_flags(include_context, include_selected, include_screenshot, has_pending_annotation)
	var params := thread_send_payload(message.strip_edges(), thread_id, attachments, pending_annotation, model, effort)
	return {
		"method": "thread.send",
		"params": params,
		"attachments": attachments,
		"capture_screenshot": needs_screenshot_capture(attachments, allow_screenshots),
		"write_context_snapshot": needs_context_snapshot(attachments),
		"clear_pending_annotation": has_pending_annotation,
	}


static func chat_send_effect_plan(send_plan: Dictionary, message: String) -> Dictionary:
	var effects: Array = []
	if bool(send_plan.get("capture_screenshot", false)):
		effects.append({
			"type": "capture_screenshot",
			"reason": "codex_chat",
		})
	if bool(send_plan.get("write_context_snapshot", false)):
		effects.append({
			"type": "write_context_snapshot",
			"reason": "codex_chat",
		})
	effects.append({
		"type": "append_user_message",
		"message": message.strip_edges(),
	})
	effects.append({"type": "clear_chat_input"})
	effects.append({"type": "refresh_composer_height"})
	effects.append({
		"type": "send_json",
		"method": str(send_plan.get("method", "thread.send")),
		"params": send_plan.get("params", {}),
	})
	if bool(send_plan.get("clear_pending_annotation", false)):
		effects.append({
			"type": "clear_pending_annotation",
			"notify": false,
		})
	effects.append({"type": "update_ui"})
	return {"effects": effects}


static func team_review_preflight(chat_permission_enabled: bool, team_permission_enabled: bool, socket_ready: bool, project_mismatch := false) -> Dictionary:
	if not chat_permission_enabled:
		return {
			"ok": false,
			"action": "status",
			"code": "permission_denied",
			"message": "Codex chat permission is disabled.",
		}
	if not team_permission_enabled:
		return {
			"ok": false,
			"action": "status",
			"code": "permission_denied",
			"message": "Background team review permission is disabled.",
		}
	if project_mismatch:
		return {
			"ok": false,
			"action": "status",
			"code": "project_mismatch",
			"message": "Reconnect to this project before starting team review.",
		}
	if not socket_ready:
		return {
			"ok": false,
			"action": "connect",
			"code": "chat_host_not_connected",
			"message": "Codex is not connected yet.",
		}
	return {"ok": true}


static func team_review_plan(input_text: String, include_context: bool) -> Dictionary:
	var prompt := ChatTeamModel.prompt_from_input(input_text)
	return {
		"method": "background.start",
		"params": ChatTeamModel.start_payload(prompt),
		"prompt": prompt,
		"input_was_used": input_text.strip_edges() != "",
		"write_context_snapshot": include_context,
		"background_state": "queued",
		"status_message": "Background team review queued.",
	}


static func team_review_preflight_effect_plan(preflight: Dictionary) -> Dictionary:
	var effects: Array = []
	if bool(preflight.get("ok", false)):
		return {"effects": effects}
	var status_message := str(preflight.get("message", ""))
	if status_message != "":
		effects.append({
			"type": "system_message",
			"message": status_message,
		})
	if str(preflight.get("action", "")) == "connect":
		effects.append({"type": "connect_host"})
	return {"effects": effects}


static func team_review_effect_plan(review_plan: Dictionary) -> Dictionary:
	var effects: Array = []
	if bool(review_plan.get("input_was_used", false)):
		effects.append({"type": "clear_chat_input"})
		effects.append({"type": "refresh_composer_height"})
	if bool(review_plan.get("write_context_snapshot", false)):
		effects.append({
			"type": "write_context_snapshot",
			"reason": "codex_background_team",
		})
	effects.append({
		"type": "set_background_state",
		"state": str(review_plan.get("background_state", "queued")),
	})
	effects.append({
		"type": "update_background_status_label",
		"params": {},
	})
	effects.append({
		"type": "send_json",
		"method": str(review_plan.get("method", "background.start")),
		"params": review_plan.get("params", {}),
	})
	effects.append({
		"type": "system_message",
		"message": str(review_plan.get("status_message", "Background team review queued.")),
	})
	effects.append({"type": "update_ui"})
	return {"effects": effects}


static func socket_action_preflight(chat_permission_enabled: bool, socket_ready: bool, require_permission := true, disconnected_message := "Codex is not connected yet.") -> Dictionary:
	if require_permission and not chat_permission_enabled:
		return {
			"ok": false,
			"action": "status",
			"code": "permission_denied",
			"message": "Codex chat permission is disabled.",
		}
	if not socket_ready:
		return {
			"ok": false,
			"action": "connect",
			"code": "chat_host_not_connected",
			"message": disconnected_message,
		}
	return {"ok": true}


static func enable_tools_plan(chat_permission_enabled: bool, socket_ready: bool, active_project_root := "", project_mismatch := false) -> Dictionary:
	var preflight := socket_action_preflight(
		chat_permission_enabled,
		socket_ready,
		true,
		"Codex is not connected yet. Connecting first."
	)
	if not bool(preflight.get("ok", false)):
		return preflight
	if project_mismatch:
		return {
			"ok": false,
			"action": "status",
			"code": "project_mismatch",
			"message": "Reconnect to this project before enabling tools.",
			"update_ui": true,
		}
	if str(active_project_root).strip_edges() == "":
		return {
			"ok": false,
			"action": "wait_for_project_attach",
			"code": "project_attach_pending",
			"message": "Waiting for Codex to attach this Godot project before enabling tools.",
			"update_ui": true,
		}
	return {
		"ok": true,
		"method": "bridge.tools.enable",
		"params": {},
		"mark_requested": true,
		"message": "Enabling Godot Bridge tools for this Codex runtime...",
		"update_ui": true,
	}


static func enable_tools_effect_plan(enable_plan: Dictionary) -> Dictionary:
	var effects: Array = []
	if not bool(enable_plan.get("ok", false)):
		var failure_message := str(enable_plan.get("message", ""))
		if failure_message != "":
			effects.append({
				"type": "system_message",
				"message": failure_message,
			})
		if str(enable_plan.get("action", "")) == "connect":
			effects.append({"type": "connect_host"})
		return {"effects": effects}
	effects.append({
		"type": "set_auto_enable_tools_requested",
		"value": bool(enable_plan.get("mark_requested", true)),
	})
	effects.append({
		"type": "system_message",
		"message": str(enable_plan.get("message", "Enabling Godot Bridge tools for this Codex runtime...")),
	})
	effects.append({
		"type": "send_json",
		"method": str(enable_plan.get("method", "bridge.tools.enable")),
		"params": enable_plan.get("params", {}),
	})
	if bool(enable_plan.get("update_ui", true)):
		effects.append({"type": "update_ui"})
	return {"effects": effects}


static func cancel_turn_plan(socket_ready: bool) -> Dictionary:
	if not socket_ready:
		return {
			"ok": false,
			"action": "ignore",
			"code": "chat_host_not_connected",
			"message": "",
		}
	return {
		"ok": true,
		"method": "turn.interrupt",
		"params": {},
		"message": "Cancel requested.",
	}


static func cancel_turn_effect_plan(cancel_plan: Dictionary) -> Dictionary:
	if not bool(cancel_plan.get("ok", false)):
		return {"effects": []}
	return {
		"effects": [
			{
				"type": "send_json",
				"method": str(cancel_plan.get("method", "turn.interrupt")),
				"params": cancel_plan.get("params", {}),
			},
			{
				"type": "system_message",
				"message": str(cancel_plan.get("message", "Cancel requested.")),
			},
		],
	}


static func cancel_team_review_plan(socket_ready: bool, task_id: String) -> Dictionary:
	if not socket_ready:
		return {
			"ok": false,
			"action": "ignore",
			"code": "chat_host_not_connected",
			"message": "",
		}
	return {
		"ok": true,
		"method": "background.cancel",
		"params": ChatTeamModel.cancel_payload(task_id),
		"message": "Background team cancel requested.",
	}


static func cancel_team_review_effect_plan(cancel_plan: Dictionary) -> Dictionary:
	if not bool(cancel_plan.get("ok", false)):
		return {"effects": []}
	return {
		"effects": [
			{
				"type": "send_json",
				"method": str(cancel_plan.get("method", "background.cancel")),
				"params": cancel_plan.get("params", {}),
			},
			{
				"type": "system_message",
				"message": str(cancel_plan.get("message", "Background team cancel requested.")),
			},
		],
	}


static func trust_session_plan(enabled: bool, socket_ready: bool) -> Dictionary:
	if not socket_ready:
		return {
			"ok": false,
			"action": "status",
			"code": "chat_host_not_connected",
			"local_trust_mode": "off",
			"message": "Connect Codex before enabling Trust Session.",
			"update_ui": true,
		}
	var request := trust_request(enabled)
	request["ok"] = true
	request["update_ui"] = true
	return request


static func trust_session_effect_plan(trust_plan: Dictionary) -> Dictionary:
	var effects: Array = [
		{
			"type": "set_trust_mode",
			"mode": str(trust_plan.get("local_trust_mode", "off")),
		},
	]
	if not bool(trust_plan.get("ok", false)):
		if bool(trust_plan.get("update_ui", false)):
			effects.append({"type": "update_ui"})
		var failure_message := str(trust_plan.get("message", ""))
		if failure_message != "":
			effects.append({
				"type": "system_message",
				"message": failure_message,
			})
		return {"effects": effects}
	var message := str(trust_plan.get("message", ""))
	if message != "":
		effects.append({
			"type": "system_message",
			"message": message,
		})
	effects.append({
		"type": "send_json",
		"method": str(trust_plan.get("method", "")),
		"params": trust_plan.get("params", {}),
	})
	if bool(trust_plan.get("update_ui", true)):
		effects.append({"type": "update_ui"})
	return {"effects": effects}


static func trust_request(enabled: bool) -> Dictionary:
	if enabled:
		return {
			"method": "session.trust.set",
			"params": {"mode": "full_machine"},
			"local_trust_mode": "full_machine",
			"message": "Trust Session requested: full-machine access for new turns.",
		}
	return {
		"method": "session.trust.clear",
		"params": {},
		"local_trust_mode": "off",
		"message": "Trust Session clear requested.",
	}


static func emergency_stop_effect_plan(
	socket_ready: bool,
	trust_mode: String,
	turn_id: String,
	background_task_id: String,
	has_active_approval: bool
) -> Dictionary:
	var effects: Array = [
		{
			"type": "stop_running_scene",
			"reason": "emergency_stop",
		},
	]
	if socket_ready:
		if turn_id.strip_edges() != "":
			effects.append({
				"type": "send_json",
				"method": "turn.interrupt",
				"params": {},
			})
		if background_task_id.strip_edges() != "":
			effects.append({
				"type": "send_json",
				"method": "background.cancel",
				"params": ChatTeamModel.cancel_payload(background_task_id),
			})
		if trust_mode != "off":
			effects.append({
				"type": "send_json",
				"method": "session.trust.clear",
				"params": {},
			})
	if has_active_approval:
		effects.append({
			"type": "clear_approval_local",
			"message": "Emergency stop cleared the pending approval.",
		})
	effects.append({
		"type": "set_trust_mode",
		"mode": "off",
	})
	effects.append({
		"type": "set_background_task_id",
		"task_id": "",
	})
	effects.append({
		"type": "set_background_state",
		"state": "idle",
	})
	effects.append({
		"type": "system_message",
		"message": "Emergency stop requested: Codex turn interrupted, team cancelled, Trust Session cleared, approval cleared and Godot play session stopped if active.",
	})
	effects.append({
		"type": "disconnect_host",
		"stop_owned_host": true,
		"reason": "emergency_stop",
	})
	effects.append({"type": "update_ui"})
	return {"effects": effects}


static func auto_enable_tools_request(connection_state: String, tools_available: bool, already_requested: bool, chat_permission_enabled: bool, active_project_root := "", force := false, project_mismatch := false) -> Dictionary:
	if not chat_permission_enabled:
		return {"send": false, "reason": "permission_disabled"}
	if connection_state != "ready":
		return {"send": false, "reason": "not_ready"}
	if project_mismatch:
		return {"send": false, "reason": "project_mismatch"}
	if str(active_project_root).strip_edges() == "":
		return {"send": false, "reason": "project_attach_pending"}
	if already_requested:
		return {"send": false, "reason": "already_requested"}
	if tools_available and not force:
		return {"send": false, "reason": "tools_available"}
	return {
		"send": true,
		"method": "bridge.tools.enable",
		"params": {},
		"mark_requested": true,
		"message": "Refreshing Godot Bridge tools for this project..." if force else "Enabling Godot Bridge tools for this Codex runtime...",
	}


static func auto_enable_tools_effect_plan(auto_enable: Dictionary) -> Dictionary:
	var effects: Array = []
	if not bool(auto_enable.get("send", false)):
		return {"effects": effects}
	effects.append({
		"type": "set_auto_enable_tools_requested",
		"value": bool(auto_enable.get("mark_requested", true)),
	})
	var message := str(auto_enable.get("message", ""))
	if message != "":
		effects.append({
			"type": "system_message",
			"message": message,
		})
	effects.append({
		"type": "send_json",
		"method": str(auto_enable.get("method", "")),
		"params": auto_enable.get("params", {}),
	})
	effects.append({"type": "update_ui"})
	return {"effects": effects}


static func runtime_options_from_payload(payload: Dictionary) -> Dictionary:
	return {
		"model": str(payload.get("model", "")).strip_edges() if payload.has("model") else "",
		"effort": str(payload.get("effort", "")).strip_edges() if payload.has("effort") else "",
	}


static func selected_metadata_index(metadata_items: Array, key: String, value: String) -> int:
	var expected := value.strip_edges()
	if expected == "":
		return -1
	for index in range(metadata_items.size()):
		var item: Variant = metadata_items[index]
		if typeof(item) != TYPE_DICTIONARY:
			continue
		if str((item as Dictionary).get(key, "")).strip_edges() == expected:
			return index
	return -1
