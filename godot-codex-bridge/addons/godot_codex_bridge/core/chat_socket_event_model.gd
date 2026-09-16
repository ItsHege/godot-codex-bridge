@tool
extends RefCounted

const RUNTIME_STATES := [
	"disconnected",
	"connecting",
	"ready",
	"turn_running",
	"waiting_for_approval",
	"applying_diff",
	"error_recoverable",
	"error_fatal",
]


static func packet_gate(was_string_packet: bool, text_length: int, max_chars: int) -> Dictionary:
	if not was_string_packet:
		return {
			"handle": false,
			"reason": "non_string_packet",
			"message": "",
		}
	if max_chars > 0 and text_length > max_chars:
		return {
			"handle": false,
			"reason": "packet_too_large",
			"message": "Codex sent a packet that exceeded the local packet limit and was skipped.",
		}
	return {
		"handle": true,
		"reason": "ok",
		"message": "",
	}


static func packet_gate_effect_plan(gate: Dictionary, text: String) -> Dictionary:
	var effects: Array[Dictionary] = []
	if bool(gate.get("handle", false)):
		effects.append({
			"action": "handle_packet_text",
			"text": text,
		})
	else:
		var message := str(gate.get("message", ""))
		if message != "":
			effects.append({
				"action": "detail_message",
				"message": message,
			})
	return {
		"effects": effects,
	}


static func packet_drain_frame_plan(available_packet_count: int, max_packets_per_frame: int) -> Dictionary:
	var safe_available: int = max(available_packet_count, 0)
	var safe_limit: int = max(max_packets_per_frame, 0)
	var read_count := safe_available if safe_limit <= 0 else min(safe_available, safe_limit)
	return {
		"available_packet_count": safe_available,
		"max_packets_per_frame": safe_limit,
		"read_count": read_count,
		"limited": safe_limit > 0 and safe_available > safe_limit,
		"estimated_remaining_after_reads": max(safe_available - read_count, 0),
	}


static func packet_read_effect_plan(was_string_packet: bool, text: String, max_chars: int) -> Dictionary:
	var gate := packet_gate(was_string_packet, text.length(), max_chars)
	return packet_gate_effect_plan(gate, text)


static func packet_drain_completion_effect_plan(
	remaining_count: int,
	events_since_notice: int,
	now_msec: int,
	last_notice_msec: int,
	interval_msec: int
) -> Dictionary:
	if remaining_count <= 0:
		return {
			"effects": [],
		}
	var notice := backpressure_notice(
		remaining_count,
		events_since_notice,
		now_msec,
		last_notice_msec,
		interval_msec
	)
	return backpressure_effect_plan(notice)


static func backpressure_notice(remaining_count: int, events_since_notice: int, now_msec: int, last_notice_msec: int, interval_msec: int) -> Dictionary:
	var next_events := events_since_notice + 1
	var detail_messages: Array[String] = []
	var backlog_text := "Codex render backlog: " + str(remaining_count) + " packet(s) pending."
	var next_last_notice := last_notice_msec
	var should_emit_notice := last_notice_msec <= 0 or now_msec - last_notice_msec >= interval_msec
	var should_update_ui := true
	if should_emit_notice:
		next_last_notice = now_msec
		detail_messages.append(backlog_text)
		if next_events > 1:
			detail_messages.append("Coalesced " + str(next_events) + " render backlog notice(s).")
		next_events = 0
	return {
		"detail_messages": detail_messages,
		"last_backpressure_text": backlog_text,
		"events_since_notice": next_events,
		"last_notice_msec": next_last_notice,
		"update_ui": should_update_ui,
	}


static func backpressure_effect_plan(notice: Dictionary) -> Dictionary:
	var effects: Array[Dictionary] = [
		{
			"action": "set_backpressure_state",
			"events_since_notice": int(notice.get("events_since_notice", 0)),
			"last_notice_msec": int(notice.get("last_notice_msec", 0)),
			"last_backpressure_text": str(notice.get("last_backpressure_text", "")),
		},
	]
	for message in notice.get("detail_messages", []):
		effects.append({
			"action": "detail_message",
			"message": str(message),
		})
	if bool(notice.get("update_ui", false)):
		effects.append({
			"action": "update_ui",
		})
	return {
		"effects": effects,
	}


static func classify_packet_text(text: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return {
			"kind": "invalid_json",
			"message": "Host sent invalid JSON.",
		}
	var parsed: Variant = parser.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return {
			"kind": "invalid_json",
			"message": "Host sent invalid JSON.",
		}
	return classify_message(parsed as Dictionary)


static func classify_message(message: Dictionary) -> Dictionary:
	if message.has("error"):
		var error_value: Variant = message.get("error", {})
		var error := error_value as Dictionary if typeof(error_value) == TYPE_DICTIONARY else {}
		var error_message := str(error.get("message", "unknown error"))
		return {
			"kind": "host_busy" if error_message.begins_with("host_busy:") else "error",
			"message": error_message,
			"error": error,
		}

	if message.has("result"):
		return {
			"kind": "result",
			"result": message.get("result", {}),
			"request_id": int(message.get("id", -1)),
		}

	var method := str(message.get("method", ""))
	var params := normalized_params(message.get("params", {}))
	if method == "bridge.addon_request":
		return {
			"kind": "addon_request",
			"method": method,
			"params": params,
		}
	if method == "":
		return {
			"kind": "unknown",
			"method": method,
			"params": params,
		}
	return {
		"kind": "event",
		"method": method,
		"params": params,
	}


static func packet_dispatch_plan(packet: Dictionary) -> Dictionary:
	var kind := str(packet.get("kind", ""))
	match kind:
		"invalid_json":
			return {
				"action": "detail_message",
				"detail_message": str(packet.get("message", "Host sent invalid JSON.")),
			}
		"host_busy":
			return {
				"action": "detail_message",
				"detail_message": "Codex busy: " + str(packet.get("message", "host_busy")),
			}
		"error":
			return {
				"action": "system_message",
				"runtime_state": "error_recoverable",
				"system_message": "Codex error: " + str(packet.get("message", "unknown error")),
			}
		"result":
			return {
				"action": "result",
				"result": packet.get("result", {}),
				"request_id": int(packet.get("request_id", -1)),
			}
		"addon_request":
			return {
				"action": "addon_request",
				"params": normalized_params(packet.get("params", {})),
			}
		"event":
			return {
				"action": "event",
				"method": str(packet.get("method", "")),
				"params": normalized_params(packet.get("params", {})),
			}
		_:
			return {
				"action": "detail_message",
				"detail_message": "Host sent an unsupported packet.",
			}


static func packet_effect_plan(packet: Dictionary) -> Dictionary:
	var plan := packet_dispatch_plan(packet)
	var effects: Array[Dictionary] = []
	match str(plan.get("action", "")):
		"detail_message":
			effects.append({
				"action": "detail_message",
				"message": str(plan.get("detail_message", "")),
			})
			effects.append({
				"action": "update_ui",
			})
		"system_message":
			if plan.has("runtime_state"):
				effects.append({
					"action": "apply_runtime_state",
					"runtime_state": str(plan.get("runtime_state", "")),
				})
			effects.append({
				"action": "system_message",
				"message": str(plan.get("system_message", "")),
			})
			effects.append({
				"action": "update_ui",
			})
		"result":
			effects.append({
				"action": "handle_result",
				"result": plan.get("result", {}),
				"request_id": int(plan.get("request_id", -1)),
			})
			effects.append({
				"action": "stop_processing",
			})
		"addon_request":
			effects.append({
				"action": "handle_addon_request",
				"params": plan.get("params", {}),
			})
			effects.append({
				"action": "stop_processing",
			})
		"event":
			effects.append({
				"action": "handle_event",
				"method": str(plan.get("method", "")),
				"params": plan.get("params", {}),
			})
			effects.append({
				"action": "stop_processing",
			})
		_:
			effects.append({
				"action": "detail_message",
				"message": "Host sent an unsupported packet.",
			})
			effects.append({
				"action": "update_ui",
			})
	return {
		"effects": effects,
	}


static func normalized_params(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_DICTIONARY:
		return value as Dictionary
	return {}


static func is_runtime_state(value: String) -> bool:
	return value in RUNTIME_STATES


static func runtime_state_from_result(result: Variant, current_state: String) -> String:
	if typeof(result) != TYPE_DICTIONARY:
		return current_state
	var data := result as Dictionary
	var state := str(data.get("state", ""))
	return state if is_runtime_state(state) else current_state
