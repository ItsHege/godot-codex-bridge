extends SceneTree

const ChatEventModel := preload("res://addons/godot_codex_bridge/core/chat_event_model.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge chat event model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge chat event model tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var host_status := ChatEventModel.classify_event("host.status", {"state": "turn_running"}, {"runtime_state": "ready"})
	_assert_eq(host_status.get("runtime_state"), "turn_running", "host status runtime")
	_assert_true(bool(host_status.get("update_host_status", false)), "host status updates host")
	_assert_true(bool(host_status.get("update_tool_visibility", false)), "host status updates tools")

	var thread := ChatEventModel.classify_event("thread.started", {"thread_id": "abc"}, {})
	_assert_eq(thread.get("thread_id"), "abc", "thread id")
	_assert_eq(thread.get("detail_message"), "Thread started: abc", "thread detail")

	var turn := ChatEventModel.classify_event("turn.started", {"turn_id": "turn-1"}, {})
	_assert_eq(turn.get("turn_id"), "turn-1", "turn id")
	_assert_true(bool(turn.get("reset_stream_state", false)), "turn resets stream")
	_assert_true(bool(turn.get("reset_diff_batch", false)), "turn resets diff")
	_assert_true(bool(turn.get("reset_work_batch", false)), "turn resets work")

	var interrupted := ChatEventModel.classify_event("turn.interrupted", {}, {})
	_assert_true(bool(interrupted.get("flush_assistant", false)), "interrupted flushes")
	_assert_true(bool(interrupted.get("clear_turn", false)), "interrupted clears turn")
	_assert_eq(interrupted.get("system_message"), "Codex response stopped.", "interrupted message")

	var approval := ChatEventModel.classify_event("approval.requested", {}, {})
	_assert_eq(approval.get("runtime_state"), "waiting_for_approval", "approval runtime")
	_assert_true(bool(approval.get("show_approval", false)), "approval show")

	var resolved := ChatEventModel.classify_event("approval.resolved", {"decision": "approve"}, {})
	_assert_eq(resolved.get("runtime_state"), "ready", "resolved runtime")
	_assert_true(bool(resolved.get("clear_approval", false)), "resolved clears")
	_assert_eq(resolved.get("approval_clear_message"), "Approval resolved: approve", "resolved message")

	var background := ChatEventModel.classify_event("background.updated", {}, {})
	_assert_true(bool(background.get("background_update", false)), "background action")

	var runtime_error := ChatEventModel.classify_event("error", {"message": "boom"}, {})
	_assert_eq(runtime_error.get("runtime_state"), "error_recoverable", "error runtime")
	_assert_eq(runtime_error.get("system_message"), "Codex runtime error: boom", "error message")

	var unsupported := ChatEventModel.classify_event("custom.event", {}, {})
	_assert_false(bool(unsupported.get("known", true)), "unsupported known flag")

	var delta := ChatEventModel.classify_turn_event({"event": "agent_message_delta", "text": "hi", "item_id": "item", "phase": "final"})
	_assert_eq(delta.get("action"), "assistant_delta", "delta action")
	_assert_eq(delta.get("text"), "hi", "delta text")
	_assert_eq(delta.get("item_id"), "item", "delta item")
	_assert_eq(delta.get("phase"), "final", "delta phase")

	var diff := ChatEventModel.classify_turn_event({"event": "diff_updated", "diff_text": "diff --git a/a.gd b/a.gd"})
	_assert_eq(diff.get("action"), "diff_updated", "diff action")
	_assert_true(str(diff.get("diff_text", "")).find("diff --git") >= 0, "diff text")

	var diff_from_changes := ChatEventModel.classify_turn_event({
		"event": "diff_updated",
		"file_changes": {
			"scripts/player.gd": {
				"unified_diff": "@@ -1 +1\n-old\n+new",
			},
		},
	})
	_assert_eq(diff_from_changes.get("action"), "diff_updated", "diff file changes action")
	_assert_true(str(diff_from_changes.get("diff_text", "")).find("scripts/player.gd") >= 0, "diff file changes text")

	var detail := ChatEventModel.classify_turn_event({"event": "other", "x": 1})
	_assert_eq(detail.get("action"), "detail", "detail action")

	var delta_plan := ChatEventModel.turn_event_handler_plan({"event": "agent_message_delta", "text": "hi", "item_id": "item", "phase": "final"})
	var delta_effects := delta_plan.get("effects", []) as Array
	_assert_eq((delta_effects[0] as Dictionary).get("action"), "assistant_delta", "delta plan action")
	_assert_eq((delta_effects[0] as Dictionary).get("text"), "hi", "delta plan text")
	_assert_eq((delta_effects[0] as Dictionary).get("item_id"), "item", "delta plan item")
	_assert_eq((delta_effects[0] as Dictionary).get("phase"), "final", "delta plan phase")

	var diff_plan := ChatEventModel.turn_event_handler_plan({"event": "diff_updated", "diff_text": "diff --git a/a.gd b/a.gd"})
	var diff_effects := diff_plan.get("effects", []) as Array
	_assert_eq((diff_effects[0] as Dictionary).get("action"), "diff_updated", "diff plan action")
	_assert_true(str((diff_effects[0] as Dictionary).get("diff_text", "")).find("diff --git") >= 0, "diff plan text")

	var empty_diff_plan := ChatEventModel.turn_event_handler_plan({"event": "diff_updated", "diff_text": "   "})
	_assert_eq((empty_diff_plan.get("effects", []) as Array).size(), 0, "empty diff plan no effects")

	var detail_plan := ChatEventModel.turn_event_handler_plan({"event": "other", "x": 1})
	var detail_effects := detail_plan.get("effects", []) as Array
	_assert_eq((detail_effects[0] as Dictionary).get("action"), "detail_message", "detail plan action")

	var delta_effect_plan := ChatEventModel.turn_event_handler_effect_plan({"event": "agent_message_delta", "text": "hi", "item_id": "item", "phase": "final"})
	var delta_live_effects := delta_effect_plan.get("effects", []) as Array
	_assert_eq((delta_live_effects[0] as Dictionary).get("action"), "assistant_delta", "delta effect plan action")
	_assert_eq((delta_live_effects[0] as Dictionary).get("text"), "hi", "delta effect plan text")
	_assert_eq((delta_live_effects[0] as Dictionary).get("item_id"), "item", "delta effect plan item")
	_assert_eq((delta_live_effects[0] as Dictionary).get("phase"), "final", "delta effect plan phase")

	var diff_effect_plan := ChatEventModel.turn_event_handler_effect_plan({"event": "diff_updated", "diff_text": "diff --git a/a.gd b/a.gd"})
	var diff_live_effects := diff_effect_plan.get("effects", []) as Array
	_assert_eq((diff_live_effects[0] as Dictionary).get("action"), "diff_updated", "diff effect plan action")
	_assert_true(str((diff_live_effects[0] as Dictionary).get("diff_text", "")).find("diff --git") >= 0, "diff effect plan text")

	var detail_effect_plan := ChatEventModel.turn_event_handler_effect_plan({"event": "other", "x": 1})
	var detail_live_effects := detail_effect_plan.get("effects", []) as Array
	_assert_eq((detail_live_effects[0] as Dictionary).get("action"), "detail_message", "detail effect plan action")

	var state_patch := ChatEventModel.event_state_patch({
		"runtime_state": "waiting_for_approval",
		"thread_id": "thread-1",
		"turn_id": "turn-1",
	})
	_assert_eq(state_patch.get("runtime_state"), "waiting_for_approval", "state patch runtime")
	_assert_eq(state_patch.get("thread_id"), "thread-1", "state patch thread")
	_assert_eq(state_patch.get("turn_id"), "turn-1", "state patch turn")

	var clear_turn_patch := ChatEventModel.event_state_patch({
		"turn_id": "turn-1",
		"clear_turn": true,
	})
	_assert_eq(clear_turn_patch.get("turn_id"), "", "clear turn wins in patch")

	var empty_patch := ChatEventModel.event_state_patch({})
	_assert_true(empty_patch.is_empty(), "empty event state patch")

	var started_plan := ChatEventModel.event_handler_plan("turn.started", {"turn_id": "turn-2"}, {})
	var started_effects := started_plan.get("effects", []) as Array
	_assert_eq((started_plan.get("state_patch", {}) as Dictionary).get("turn_id"), "turn-2", "started plan state patch")
	_assert_eq((started_effects[0] as Dictionary).get("action"), "apply_state_patch", "started plan applies state first")
	_assert_eq((started_effects[1] as Dictionary).get("action"), "reset_stream_state", "started plan resets stream")
	_assert_eq((started_effects[2] as Dictionary).get("action"), "reset_diff_batch", "started plan resets diff")
	_assert_eq((started_effects[3] as Dictionary).get("action"), "reset_work_batch", "started plan resets work")
	_assert_eq((started_effects[4] as Dictionary).get("action"), "detail_message", "started plan detail last")
	_assert_true(bool(started_plan.get("update_ui", false)), "started plan updates ui")

	var approval_plan := ChatEventModel.event_handler_plan("approval.resolved", {"decision": "approve"}, {})
	var approval_effects := approval_plan.get("effects", []) as Array
	_assert_eq((approval_effects[0] as Dictionary).get("action"), "apply_state_patch", "approval plan applies state first")
	_assert_eq((approval_effects[1] as Dictionary).get("action"), "clear_approval", "approval plan clears approval")
	_assert_eq((approval_effects[1] as Dictionary).get("message"), "Approval resolved: approve", "approval plan clear message")

	var status_plan := ChatEventModel.event_handler_plan("host.status", {"state": "ready"}, {})
	var status_effects := status_plan.get("effects", []) as Array
	_assert_eq((status_effects[0] as Dictionary).get("action"), "apply_state_patch", "status plan applies state")
	_assert_eq((status_effects[1] as Dictionary).get("action"), "update_host_status", "status plan host status")
	_assert_eq((status_effects[2] as Dictionary).get("action"), "update_tool_visibility", "status plan tool visibility")

	var status_effect_plan := ChatEventModel.event_handler_effect_plan("host.status", {"state": "ready", "mcp_tools": true}, {})
	var status_live_effects := status_effect_plan.get("effects", []) as Array
	_assert_eq((status_live_effects[0] as Dictionary).get("action"), "apply_state_patch", "status effect plan applies state")
	_assert_eq((status_live_effects[1] as Dictionary).get("action"), "update_host_status", "status effect plan host status")
	_assert_eq(((status_live_effects[1] as Dictionary).get("params", {}) as Dictionary).get("state"), "ready", "status effect plan carries params")
	_assert_eq((status_live_effects[status_live_effects.size() - 1] as Dictionary).get("action"), "update_ui", "status effect plan updates ui last")

	var turn_effect_plan := ChatEventModel.event_handler_effect_plan("turn.event", {"event": "agent_message_delta", "text": "hello"}, {})
	var turn_live_effects := turn_effect_plan.get("effects", []) as Array
	_assert_eq((turn_live_effects[0] as Dictionary).get("action"), "turn_event", "turn event effect plan delegates turn event")
	_assert_eq(((turn_live_effects[0] as Dictionary).get("params", {}) as Dictionary).get("text"), "hello", "turn event effect plan carries params")
	_assert_eq((turn_live_effects[turn_live_effects.size() - 1] as Dictionary).get("action"), "update_ui", "turn event effect plan updates ui")


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
