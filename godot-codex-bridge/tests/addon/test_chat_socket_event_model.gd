extends SceneTree

const ChatSocketEventModel := preload("res://addons/godot_codex_bridge/core/chat_socket_event_model.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge chat socket event model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge chat socket event model tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var non_string_gate := ChatSocketEventModel.packet_gate(false, 12, 100)
	_assert_false(bool(non_string_gate.get("handle", true)), "non-string packet ignored")
	_assert_eq(str(non_string_gate.get("reason", "")), "non_string_packet", "non-string packet reason")

	var oversized_gate := ChatSocketEventModel.packet_gate(true, 101, 100)
	_assert_false(bool(oversized_gate.get("handle", true)), "oversized packet ignored")
	_assert_eq(str(oversized_gate.get("reason", "")), "packet_too_large", "oversized packet reason")
	_assert_true(str(oversized_gate.get("message", "")).contains("exceeded"), "oversized packet message")

	var ok_gate := ChatSocketEventModel.packet_gate(true, 100, 100)
	_assert_true(bool(ok_gate.get("handle", false)), "packet at limit accepted")
	var ok_gate_effects := ChatSocketEventModel.packet_gate_effect_plan(ok_gate, "{\"result\":{}}").get("effects", []) as Array
	_assert_eq(ok_gate_effects.size(), 1, "ok packet gate effect count")
	_assert_eq(str((ok_gate_effects[0] as Dictionary).get("action", "")), "handle_packet_text", "ok packet gate handles text")
	_assert_eq(str((ok_gate_effects[0] as Dictionary).get("text", "")), "{\"result\":{}}", "ok packet gate keeps text")

	var oversized_gate_effects := ChatSocketEventModel.packet_gate_effect_plan(oversized_gate, "x".repeat(101)).get("effects", []) as Array
	_assert_eq(oversized_gate_effects.size(), 1, "oversized packet gate effect count")
	_assert_eq(str((oversized_gate_effects[0] as Dictionary).get("action", "")), "detail_message", "oversized packet gate detail")
	_assert_true(str((oversized_gate_effects[0] as Dictionary).get("message", "")).contains("exceeded"), "oversized packet gate message")

	var non_string_effects := ChatSocketEventModel.packet_gate_effect_plan(non_string_gate, "ignored").get("effects", []) as Array
	_assert_eq(non_string_effects.size(), 0, "non-string packet gate has no visible effect")

	var zero_drain := ChatSocketEventModel.packet_drain_frame_plan(0, 48)
	_assert_eq(int(zero_drain.get("read_count", -1)), 0, "zero drain reads zero packets")
	_assert_false(bool(zero_drain.get("limited", true)), "zero drain is not limited")
	_assert_eq(int(zero_drain.get("estimated_remaining_after_reads", -1)), 0, "zero drain has no remaining packets")

	var bounded_drain := ChatSocketEventModel.packet_drain_frame_plan(99, 48)
	_assert_eq(int(bounded_drain.get("read_count", -1)), 48, "bounded drain honors per-frame limit")
	_assert_true(bool(bounded_drain.get("limited", false)), "bounded drain marks limited backlog")
	_assert_eq(int(bounded_drain.get("estimated_remaining_after_reads", -1)), 51, "bounded drain estimates remaining backlog")

	var unlimited_drain := ChatSocketEventModel.packet_drain_frame_plan(7, 0)
	_assert_eq(int(unlimited_drain.get("read_count", -1)), 7, "zero limit means read all available")
	_assert_false(bool(unlimited_drain.get("limited", true)), "zero limit is not limited")

	var negative_drain := ChatSocketEventModel.packet_drain_frame_plan(-4, 48)
	_assert_eq(int(negative_drain.get("read_count", -1)), 0, "negative available packets are clamped")
	_assert_eq(int(negative_drain.get("available_packet_count", -1)), 0, "negative available count is reported as zero")

	var packet_read_effects := ChatSocketEventModel.packet_read_effect_plan(true, "{\"jsonrpc\":\"2.0\"}", 100).get("effects", []) as Array
	_assert_eq(packet_read_effects.size(), 1, "packet read effect accepts valid string packet")
	_assert_eq(str((packet_read_effects[0] as Dictionary).get("action", "")), "handle_packet_text", "packet read effect handles text")

	var first_backpressure := ChatSocketEventModel.backpressure_notice(5, 0, 1000, 0, 250)
	_assert_eq(int(first_backpressure.get("events_since_notice", -1)), 0, "first backpressure resets count after notice")
	_assert_eq(int(first_backpressure.get("last_notice_msec", -1)), 1000, "first backpressure sets notice time")
	_assert_eq((first_backpressure.get("detail_messages", []) as Array).size(), 1, "first backpressure one detail")

	var quiet_backpressure := ChatSocketEventModel.backpressure_notice(4, 0, 1100, 1000, 250)
	_assert_eq(int(quiet_backpressure.get("events_since_notice", -1)), 1, "quiet backpressure count increments")
	_assert_eq(int(quiet_backpressure.get("last_notice_msec", -1)), 1000, "quiet backpressure keeps notice time")
	_assert_eq((quiet_backpressure.get("detail_messages", []) as Array).size(), 0, "quiet backpressure emits no detail")
	var quiet_effects := ChatSocketEventModel.backpressure_effect_plan(quiet_backpressure).get("effects", []) as Array
	_assert_eq(_effect_count(quiet_effects, "detail_message"), 0, "quiet backpressure effect has no detail")
	_assert_eq(_effect_count(quiet_effects, "update_ui"), 1, "quiet backpressure still updates ui")

	var coalesced_backpressure := ChatSocketEventModel.backpressure_notice(3, 2, 1300, 900, 250)
	_assert_eq(int(coalesced_backpressure.get("events_since_notice", -1)), 0, "coalesced backpressure resets count")
	_assert_eq(int(coalesced_backpressure.get("last_notice_msec", -1)), 1300, "coalesced backpressure updates notice time")
	_assert_eq((coalesced_backpressure.get("detail_messages", []) as Array).size(), 2, "coalesced backpressure details")
	_assert_true(str((coalesced_backpressure.get("detail_messages", []) as Array)[1]).contains("Coalesced 3"), "coalesced backpressure text")
	var coalesced_effects := ChatSocketEventModel.backpressure_effect_plan(coalesced_backpressure).get("effects", []) as Array
	_assert_eq(str((coalesced_effects[0] as Dictionary).get("action", "")), "set_backpressure_state", "backpressure state effect first")
	_assert_eq(_effect_count(coalesced_effects, "detail_message"), 2, "coalesced backpressure detail effects")
	_assert_eq(_effect_count(coalesced_effects, "update_ui"), 1, "coalesced backpressure updates ui")

	var no_backlog_effects := ChatSocketEventModel.packet_drain_completion_effect_plan(0, 0, 1400, 1300, 250).get("effects", []) as Array
	_assert_eq(no_backlog_effects.size(), 0, "drain completion without backlog has no effects")

	var backlog_effects := ChatSocketEventModel.packet_drain_completion_effect_plan(2, 0, 1600, 1300, 250).get("effects", []) as Array
	_assert_eq(str((backlog_effects[0] as Dictionary).get("action", "")), "set_backpressure_state", "drain completion stores backpressure state")
	_assert_eq(_effect_count(backlog_effects, "detail_message"), 1, "drain completion emits backpressure detail")
	_assert_eq(_effect_count(backlog_effects, "update_ui"), 1, "drain completion updates ui")

	var invalid := ChatSocketEventModel.classify_packet_text("{not json")
	_assert_eq(str(invalid.get("kind", "")), "invalid_json", "invalid JSON classification")
	var invalid_plan := ChatSocketEventModel.packet_dispatch_plan(invalid)
	_assert_eq(str(invalid_plan.get("action", "")), "detail_message", "invalid dispatch action")
	_assert_true(str(invalid_plan.get("detail_message", "")).contains("invalid JSON"), "invalid dispatch message")
	var invalid_effects := ChatSocketEventModel.packet_effect_plan(invalid).get("effects", []) as Array
	_assert_eq(str((invalid_effects[0] as Dictionary).get("action", "")), "detail_message", "invalid effect detail")
	_assert_eq(str((invalid_effects[1] as Dictionary).get("action", "")), "update_ui", "invalid effect updates ui")

	var host_busy := ChatSocketEventModel.classify_message({
		"jsonrpc": "2.0",
		"id": 1,
		"error": {"message": "host_busy: turn_running"},
	})
	_assert_eq(str(host_busy.get("kind", "")), "host_busy", "host busy classification")
	var host_busy_plan := ChatSocketEventModel.packet_dispatch_plan(host_busy)
	_assert_eq(str(host_busy_plan.get("action", "")), "detail_message", "host busy dispatch action")
	_assert_true(str(host_busy_plan.get("detail_message", "")).begins_with("Codex busy:"), "host busy dispatch message")

	var runtime_error := ChatSocketEventModel.classify_message({
		"jsonrpc": "2.0",
		"id": 2,
		"error": {"message": "boom"},
	})
	_assert_eq(str(runtime_error.get("kind", "")), "error", "runtime error classification")
	_assert_eq(str(runtime_error.get("message", "")), "boom", "runtime error message")
	var runtime_error_plan := ChatSocketEventModel.packet_dispatch_plan(runtime_error)
	_assert_eq(str(runtime_error_plan.get("action", "")), "system_message", "runtime error dispatch action")
	_assert_eq(str(runtime_error_plan.get("runtime_state", "")), "error_recoverable", "runtime error dispatch state")
	var runtime_error_effects := ChatSocketEventModel.packet_effect_plan(runtime_error).get("effects", []) as Array
	_assert_eq(str((runtime_error_effects[0] as Dictionary).get("action", "")), "apply_runtime_state", "runtime error state effect")
	_assert_eq(str((runtime_error_effects[0] as Dictionary).get("runtime_state", "")), "error_recoverable", "runtime error effect state")
	_assert_eq(str((runtime_error_effects[1] as Dictionary).get("action", "")), "system_message", "runtime error message effect")
	_assert_eq(str((runtime_error_effects[2] as Dictionary).get("action", "")), "update_ui", "runtime error ui effect")

	var result := ChatSocketEventModel.classify_message({
		"jsonrpc": "2.0",
		"id": 3,
		"result": {"state": "ready"},
	})
	_assert_eq(str(result.get("kind", "")), "result", "result classification")
	_assert_eq(int(result.get("request_id", -1)), 3, "result classification keeps request id")
	_assert_eq(ChatSocketEventModel.runtime_state_from_result(result.get("result"), "connecting"), "ready", "runtime state from result")
	_assert_eq(ChatSocketEventModel.runtime_state_from_result({"state": "weird"}, "ready"), "ready", "invalid runtime state ignored")
	var result_plan := ChatSocketEventModel.packet_dispatch_plan(result)
	_assert_eq(str(result_plan.get("action", "")), "result", "result dispatch action")
	_assert_eq(int(result_plan.get("request_id", -1)), 3, "result dispatch keeps request id")
	_assert_eq(str((result_plan.get("result", {}) as Dictionary).get("state", "")), "ready", "result dispatch payload")
	var result_effects := ChatSocketEventModel.packet_effect_plan(result).get("effects", []) as Array
	_assert_eq(str((result_effects[0] as Dictionary).get("action", "")), "handle_result", "result effect handler")
	_assert_eq(int((result_effects[0] as Dictionary).get("request_id", -1)), 3, "result effect keeps request id")
	_assert_eq(str(((result_effects[0] as Dictionary).get("result", {}) as Dictionary).get("state", "")), "ready", "result effect payload")
	_assert_eq(str((result_effects[1] as Dictionary).get("action", "")), "stop_processing", "result effect stops")

	var addon_request := ChatSocketEventModel.classify_message({
		"jsonrpc": "2.0",
		"method": "bridge.addon_request",
		"params": {"request_id": "r1"},
	})
	_assert_eq(str(addon_request.get("kind", "")), "addon_request", "addon request classification")
	_assert_eq(str((addon_request.get("params", {}) as Dictionary).get("request_id", "")), "r1", "addon request params retained")
	var addon_request_plan := ChatSocketEventModel.packet_dispatch_plan(addon_request)
	_assert_eq(str(addon_request_plan.get("action", "")), "addon_request", "addon request dispatch action")
	_assert_eq(str((addon_request_plan.get("params", {}) as Dictionary).get("request_id", "")), "r1", "addon request dispatch params")
	var addon_request_effects := ChatSocketEventModel.packet_effect_plan(addon_request).get("effects", []) as Array
	_assert_eq(str((addon_request_effects[0] as Dictionary).get("action", "")), "handle_addon_request", "addon request effect handler")
	_assert_eq(str(((addon_request_effects[0] as Dictionary).get("params", {}) as Dictionary).get("request_id", "")), "r1", "addon request effect params")
	_assert_eq(str((addon_request_effects[1] as Dictionary).get("action", "")), "stop_processing", "addon request effect stops")

	var event := ChatSocketEventModel.classify_message({
		"jsonrpc": "2.0",
		"method": "turn.completed",
		"params": [],
	})
	_assert_eq(str(event.get("kind", "")), "event", "event classification")
	_assert_eq(str(event.get("method", "")), "turn.completed", "event method retained")
	_assert_eq((event.get("params", {}) as Dictionary).size(), 0, "non-dictionary params normalized")
	var event_plan := ChatSocketEventModel.packet_dispatch_plan(event)
	_assert_eq(str(event_plan.get("action", "")), "event", "event dispatch action")
	_assert_eq(str(event_plan.get("method", "")), "turn.completed", "event dispatch method")
	var event_effects := ChatSocketEventModel.packet_effect_plan(event).get("effects", []) as Array
	_assert_eq(str((event_effects[0] as Dictionary).get("action", "")), "handle_event", "event effect handler")
	_assert_eq(str((event_effects[0] as Dictionary).get("method", "")), "turn.completed", "event effect method")
	_assert_eq(str((event_effects[1] as Dictionary).get("action", "")), "stop_processing", "event effect stops")

	var unsupported_plan := ChatSocketEventModel.packet_dispatch_plan({"kind": "sleepy"})
	_assert_eq(str(unsupported_plan.get("action", "")), "detail_message", "unsupported dispatch action")
	_assert_true(str(unsupported_plan.get("detail_message", "")).contains("unsupported"), "unsupported dispatch message")

	_assert_true(ChatSocketEventModel.is_runtime_state("waiting_for_approval"), "known runtime state accepted")
	_assert_false(ChatSocketEventModel.is_runtime_state("sleepy"), "unknown runtime state rejected")


func _effect_count(effects: Array, action: String) -> int:
	var count := 0
	for effect in effects:
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		var effect_dict := effect as Dictionary
		if str(effect_dict.get("action", "")) == action:
			count += 1
	return count


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
