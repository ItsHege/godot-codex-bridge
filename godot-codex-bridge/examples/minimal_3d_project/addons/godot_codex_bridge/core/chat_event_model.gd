@tool
extends RefCounted

const ChatDiffModel := preload("chat_diff_model.gd")


static func classify_event(method: String, params: Dictionary, current_state: Dictionary = {}) -> Dictionary:
	var current_runtime := str(current_state.get("runtime_state", "ready"))
	var current_thread := str(current_state.get("thread_id", ""))
	var current_turn := str(current_state.get("turn_id", ""))
	var event := {
		"method": method,
		"known": true,
		"update_ui": true,
		"update_host_status": false,
		"update_tool_visibility": false,
		"flush_assistant": false,
		"reset_stream_state": false,
		"reset_diff_batch": false,
		"reset_work_batch": false,
		"clear_turn": false,
		"turn_event": false,
		"background_update": false,
		"show_approval": false,
		"clear_approval": false,
		"system_message": "",
		"detail_message": "",
		"approval_clear_message": "",
	}

	match method:
		"host.status":
			event["runtime_state"] = str(params.get("state", current_runtime))
			event["update_host_status"] = true
			event["update_tool_visibility"] = true
		"host.reconnected":
			event["system_message"] = "Codex reconnected."
		"thread.started":
			var thread_id := str(params.get("thread_id", current_thread))
			event["thread_id"] = thread_id
			event["detail_message"] = "Thread started: " + thread_id
		"turn.started":
			var turn_id := str(params.get("turn_id", current_turn))
			event["turn_id"] = turn_id
			event["reset_stream_state"] = true
			event["reset_diff_batch"] = true
			event["reset_work_batch"] = true
			event["detail_message"] = "Turn started."
		"turn.event":
			event["turn_event"] = true
		"turn.interrupted":
			event["flush_assistant"] = true
			event["clear_turn"] = true
			event["reset_stream_state"] = true
			event["system_message"] = "Codex response stopped."
		"turn.completed":
			event["flush_assistant"] = true
			event["clear_turn"] = true
			event["reset_stream_state"] = true
			event["detail_message"] = "Turn completed."
		"approval.requested":
			event["flush_assistant"] = true
			event["runtime_state"] = "waiting_for_approval"
			event["show_approval"] = true
		"approval.expired":
			event["runtime_state"] = "ready"
			event["clear_approval"] = true
			event["approval_clear_message"] = "Approval expired; files left unchanged."
		"approval.resolved":
			event["runtime_state"] = "ready"
			event["clear_approval"] = true
			event["approval_clear_message"] = "Approval resolved: " + str(params.get("decision", "unknown"))
		"background.updated":
			event["background_update"] = true
		"runtime.warning":
			event["detail_message"] = "Warning: " + str(params.get("message", "runtime warning"))
		"runtime.backpressure":
			event["detail_message"] = "Backpressure: " + str(params.get("message", params))
		"error":
			event["runtime_state"] = "error_recoverable"
			event["system_message"] = "Codex runtime error: " + str(params.get("message", "unknown error"))
		_:
			event["known"] = false
			event["detail_message"] = "Unsupported Codex event: " + method
	return event


static func classify_turn_event(params: Dictionary) -> Dictionary:
	var event_name := str(params.get("event", ""))
	match event_name:
		"agent_message_delta":
			return {
				"action": "assistant_delta",
				"text": str(params.get("text", "")),
				"item_id": str(params.get("item_id", "")),
				"phase": str(params.get("phase", "")),
			}
		"diff_updated":
			return {
				"action": "diff_updated",
				"diff_text": ChatDiffModel.diff_text_from_event_params(params),
			}
		_:
			return {
				"action": "detail",
				"message": str(params),
			}


static func turn_event_handler_plan(params: Dictionary) -> Dictionary:
	var turn_event := classify_turn_event(params)
	var effects: Array[Dictionary] = []
	match str(turn_event.get("action", "")):
		"assistant_delta":
			effects.append({
				"action": "assistant_delta",
				"text": str(turn_event.get("text", "")),
				"item_id": str(turn_event.get("item_id", "")),
				"phase": str(turn_event.get("phase", "")),
			})
		"diff_updated":
			var diff_text := str(turn_event.get("diff_text", ""))
			if diff_text.strip_edges() != "":
				effects.append({
					"action": "diff_updated",
					"diff_text": diff_text,
				})
		_:
			effects.append({
				"action": "detail_message",
				"message": str(turn_event.get("message", params)),
			})
	return {
		"turn_event": turn_event,
		"effects": effects,
	}


static func turn_event_handler_effect_plan(params: Dictionary) -> Dictionary:
	var plan := turn_event_handler_plan(params)
	var effects: Array[Dictionary] = []
	for effect in plan.get("effects", []):
		effects.append((effect as Dictionary).duplicate(true))
	return {
		"turn_event": plan.get("turn_event", {}),
		"effects": effects,
	}


static func event_state_patch(event: Dictionary) -> Dictionary:
	var patch := {}
	if event.has("runtime_state"):
		patch["runtime_state"] = str(event.get("runtime_state", ""))
	if event.has("thread_id"):
		patch["thread_id"] = str(event.get("thread_id", ""))
	if event.has("turn_id"):
		patch["turn_id"] = str(event.get("turn_id", ""))
	if bool(event.get("clear_turn", false)):
		patch["turn_id"] = ""
	return patch


static func event_handler_plan(method: String, params: Dictionary, current_state: Dictionary = {}) -> Dictionary:
	var event := classify_event(method, params, current_state)
	var state_patch := event_state_patch(event)
	var effects: Array[Dictionary] = []
	if not state_patch.is_empty():
		effects.append({"action": "apply_state_patch", "patch": state_patch})
	if bool(event.get("update_host_status", false)):
		effects.append({"action": "update_host_status"})
	if bool(event.get("update_tool_visibility", false)):
		effects.append({"action": "update_tool_visibility"})
	if bool(event.get("flush_assistant", false)):
		effects.append({"action": "flush_assistant"})
	if bool(event.get("reset_stream_state", false)):
		effects.append({"action": "reset_stream_state"})
	if bool(event.get("reset_diff_batch", false)):
		effects.append({"action": "reset_diff_batch"})
	if bool(event.get("reset_work_batch", false)):
		effects.append({"action": "reset_work_batch"})
	if bool(event.get("turn_event", false)):
		effects.append({"action": "turn_event"})
	if bool(event.get("show_approval", false)):
		effects.append({"action": "show_approval"})
	if bool(event.get("clear_approval", false)):
		effects.append({
			"action": "clear_approval",
			"message": str(event.get("approval_clear_message", "")),
		})
	if bool(event.get("background_update", false)):
		effects.append({"action": "background_update"})
	var system_message := str(event.get("system_message", ""))
	if system_message != "":
		effects.append({"action": "system_message", "message": system_message})
	var detail_message := str(event.get("detail_message", ""))
	if detail_message != "":
		effects.append({"action": "detail_message", "message": detail_message})
	return {
		"event": event,
		"state_patch": state_patch,
		"effects": effects,
		"update_ui": bool(event.get("update_ui", true)),
	}


static func event_handler_effect_plan(method: String, params: Dictionary, current_state: Dictionary = {}) -> Dictionary:
	var plan := event_handler_plan(method, params, current_state)
	var effects: Array[Dictionary] = []
	for effect in plan.get("effects", []):
		var effect_dict := (effect as Dictionary).duplicate(true)
		match str(effect_dict.get("action", "")):
			"update_host_status", "update_tool_visibility", "turn_event", "show_approval", "background_update":
				effect_dict["params"] = params.duplicate(true)
		effects.append(effect_dict)
	if bool(plan.get("update_ui", true)):
		effects.append({"action": "update_ui"})
	return {
		"event": plan.get("event", {}),
		"state_patch": plan.get("state_patch", {}),
		"effects": effects,
	}
