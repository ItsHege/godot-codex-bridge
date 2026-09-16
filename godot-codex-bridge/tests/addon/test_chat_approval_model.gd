extends SceneTree

const ChatApprovalModel := preload("res://addons/godot_codex_bridge/core/chat_approval_model.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge chat approval model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge chat approval model tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var command := {
		"approval_id": "approval-command",
		"kind": "command_execution",
		"safe_default": "manual_only",
		"nonce": "nonce-1",
		"reason": "Run a bounded Godot command",
		"command": "godot --headless --quit",
	}
	_assert_true(ChatApprovalModel.can_approve(command), "command approval is allowed")
	_assert_true(ChatApprovalModel.can_approve_session(command), "command approval can be session-approved")
	_assert_eq(ChatApprovalModel.notice_text(command), "Codex requested command approval.", "command notice text")
	var command_summary := ChatApprovalModel.approval_summary(command, 12)
	_assert_true(command_summary.find("Chat approval: available") >= 0, "command summary says available")
	_assert_true(command_summary.find("Session approval: available") >= 0, "command summary says session available")
	_assert_true(command_summary.find("[truncated]") >= 0, "command summary truncates long command text")

	var elicitation := {
		"approval_id": "approval-question",
		"kind": "elicitation",
		"safe_default": "manual_only",
		"nonce": "nonce-2",
	}
	_assert_true(ChatApprovalModel.can_approve(elicitation), "elicitation approval is allowed")
	_assert_false(ChatApprovalModel.can_approve_session(elicitation), "elicitation cannot be session-approved")
	_assert_eq(ChatApprovalModel.notice_text(elicitation), "Codex is asking for confirmation.", "elicitation notice text")

	var file_without_hash := {
		"approval_id": "approval-file",
		"kind": "file_change",
		"safe_default": "manual_only",
		"nonce": "nonce-3",
	}
	_assert_false(ChatApprovalModel.can_approve(file_without_hash), "file approval without diff hash is blocked")
	_assert_true(ChatApprovalModel.disabled_reason(file_without_hash).find("Diff hash is missing") >= 0, "file without hash explains diff hash")

	var file_with_hash := {
		"approval_id": "approval-file-hash",
		"kind": "file_change",
		"safe_default": "manual_only",
		"nonce": "nonce-4",
		"diff_hash": "abc123",
		"file_changes": {
			"scripts/player.gd": {
				"unified_diff": "@@\n-old\n+new\n",
			},
		},
	}
	_assert_true(ChatApprovalModel.can_approve(file_with_hash), "file approval with diff hash is allowed")
	_assert_true(ChatApprovalModel.can_approve_session(file_with_hash), "file approval with diff hash can be session-approved")
	var file_summary := ChatApprovalModel.approval_summary(file_with_hash)
	_assert_true(file_summary.find("Diff hash: abc123") >= 0, "file summary includes diff hash")
	_assert_true(file_summary.find("File changes: 1 file(s), +1 -1") >= 0, "file summary includes change counts")

	var permission_grant := {
		"approval_id": "approval-permission",
		"kind": "permission_grant",
		"safe_default": "manual_only",
		"nonce": "nonce-5",
		"approvable_by_chat": false,
	}
	_assert_false(ChatApprovalModel.can_approve(permission_grant), "permission grants are blocked")
	_assert_false(ChatApprovalModel.can_approve_session(permission_grant), "permission grants cannot be session-approved")
	_assert_eq(ChatApprovalModel.notice_text(permission_grant), "Approval requested but Approve is blocked for this request type.", "blocked notice text")

	var response := ChatApprovalModel.response_payload(command, "approve_session", "ok")
	_assert_eq(str(response.get("approval_id", "")), "approval-command", "response keeps approval id")
	_assert_eq(str(response.get("nonce", "")), "nonce-1", "response keeps nonce")
	_assert_eq(str(response.get("decision", "")), "approve_session", "response keeps decision")
	_assert_eq(str(response.get("note", "")), "ok", "response keeps note")

	var command_show := ChatApprovalModel.show_plan(command, "")
	_assert_eq(str(command_show.get("title", "")), "Approval required: command_execution", "command show title")
	_assert_true(str(command_show.get("body", "")).find("Approval: approval-command") >= 0, "command show body includes summary")
	_assert_eq(str(command_show.get("note_placeholder", "")), "Optional note for Codex", "command note placeholder")
	_assert_eq(str(command_show.get("detail_message", "")), "Codex requested command approval.", "command show notice")
	_assert_true(bool(command_show.get("show_panel", false)), "command show displays panel")
	_assert_true(bool(command_show.get("scroll_to_bottom", false)), "command show scrolls")
	var active_copy := command_show.get("active_approval", {}) as Dictionary
	active_copy["approval_id"] = "mutated"
	_assert_eq(str(command.get("approval_id", "")), "approval-command", "show active approval is duplicated")

	var elicitation_show := ChatApprovalModel.show_plan(elicitation, "")
	_assert_eq(str(elicitation_show.get("note_placeholder", "")), "Optional answer/note for Codex", "elicitation note placeholder")

	var file_show := ChatApprovalModel.show_plan(file_with_hash, "")
	_assert_true(str(file_show.get("diff_text", "")).find("-old") >= 0, "file show includes removed diff")
	_assert_true(str(file_show.get("diff_text", "")).find("+new") >= 0, "file show includes added diff")

	var file_show_existing_diff := ChatApprovalModel.show_plan(file_with_hash, "existing diff")
	_assert_eq(str(file_show_existing_diff.get("diff_text", "")), "", "existing active diff prevents duplicate approval diff")

	var file_show_effect_plan := ChatApprovalModel.show_effect_plan(file_with_hash, "")
	var file_show_effects := file_show_effect_plan.get("effects", []) as Array
	_assert_eq((file_show_effects[0] as Dictionary).get("action"), "set_active_approval", "show effect sets active approval first")
	_assert_eq((file_show_effects[1] as Dictionary).get("action"), "show_panel", "show effect displays panel")
	_assert_true(_has_action(file_show_effects, "record_diff"), "show effect records approval diff")
	_assert_true(_has_action(file_show_effects, "detail_message"), "show effect appends approval notice")
	_assert_eq((file_show_effects[file_show_effects.size() - 1] as Dictionary).get("action"), "update_ui", "show effect updates ui last")

	var clear_plan := ChatApprovalModel.clear_plan("Approval resolved: approve")
	_assert_true((clear_plan.get("active_approval", {}) as Dictionary).is_empty(), "clear plan resets active approval")
	_assert_false(bool(clear_plan.get("panel_visible", true)), "clear plan hides panel")
	_assert_eq(str(clear_plan.get("body", "not empty")), "", "clear plan clears body")
	_assert_eq(str(clear_plan.get("note_text", "not empty")), "", "clear plan clears note")
	_assert_eq(str(clear_plan.get("detail_message", "")), "Approval resolved: approve", "clear plan keeps detail message")
	_assert_true(bool(clear_plan.get("update_ui", false)), "clear plan updates ui")

	var clear_effect_plan := ChatApprovalModel.clear_effect_plan("Approval resolved: approve")
	var clear_effects := clear_effect_plan.get("effects", []) as Array
	_assert_eq((clear_effects[0] as Dictionary).get("action"), "set_active_approval", "clear effect resets active approval first")
	_assert_eq((clear_effects[1] as Dictionary).get("action"), "set_panel_visible", "clear effect hides panel")
	_assert_true(_has_action(clear_effects, "detail_message"), "clear effect appends detail")
	_assert_eq((clear_effects[clear_effects.size() - 1] as Dictionary).get("action"), "update_ui", "clear effect updates ui last")

	var empty_plan := ChatApprovalModel.response_plan({}, "approve", "", true)
	_assert_false(bool(empty_plan.get("ok", false)), "empty approval response plan is not ok")
	_assert_eq(str(empty_plan.get("action", "")), "ignore", "empty approval response plan ignores")

	var disconnected_plan := ChatApprovalModel.response_plan(command, "approve", "", false)
	_assert_false(bool(disconnected_plan.get("ok", false)), "disconnected approval response plan is not ok")
	_assert_true(str(disconnected_plan.get("system_message", "")).find("not connected") >= 0, "disconnected approval response explains socket")

	var blocked_approve_plan := ChatApprovalModel.response_plan(permission_grant, "approve", "", true)
	_assert_false(bool(blocked_approve_plan.get("ok", false)), "blocked approve response plan is not ok")
	_assert_true(str(blocked_approve_plan.get("system_message", "")).find("Approve is blocked") >= 0, "blocked approve response explains approval")
	_assert_true(bool(blocked_approve_plan.get("update_ui", false)), "blocked approve response updates ui")

	var session_unavailable_plan := ChatApprovalModel.response_plan(elicitation, "approve_session", "", true)
	_assert_false(bool(session_unavailable_plan.get("ok", false)), "elicitation session response plan is not ok")
	_assert_true(str(session_unavailable_plan.get("system_message", "")).find("Approve Session is not available") >= 0, "session unavailable response explains")

	var missing_id_plan := ChatApprovalModel.response_plan({
		"kind": "command_execution",
		"safe_default": "manual_only",
		"nonce": "nonce-missing-id",
	}, "approve", "", true)
	_assert_false(bool(missing_id_plan.get("ok", false)), "missing id response plan is not ok")
	_assert_true(str(missing_id_plan.get("system_message", "")).find("Approval id is missing") >= 0, "missing id response explains")

	var missing_nonce_plan := ChatApprovalModel.response_plan({
		"approval_id": "approval-missing-nonce",
		"kind": "command_execution",
		"safe_default": "manual_only",
	}, "approve", "", true)
	_assert_false(bool(missing_nonce_plan.get("ok", false)), "missing nonce response plan is not ok")
	_assert_true(str(missing_nonce_plan.get("system_message", "")).find("Approval nonce is missing") >= 0, "missing nonce response explains")

	var approve_plan := ChatApprovalModel.response_plan(command, "approve", "ok", true)
	_assert_true(bool(approve_plan.get("ok", false)), "approve response plan ok")
	_assert_eq(str(approve_plan.get("method", "")), "approval.respond", "approve response method")
	_assert_false(bool(approve_plan.get("clear_approval", true)), "approve keeps approval until host resolves")
	_assert_true(bool(approve_plan.get("update_ui", false)), "approve response updates ui")
	var approve_params := approve_plan.get("params", {}) as Dictionary
	_assert_eq(str(approve_params.get("decision", "")), "approve", "approve plan decision")

	var approve_effect_plan := ChatApprovalModel.response_effect_plan(command, "approve", "ok", true)
	var approve_effects := approve_effect_plan.get("effects", []) as Array
	_assert_eq((approve_effects[0] as Dictionary).get("action"), "send_json", "approve effect sends json first")
	_assert_eq((approve_effects[1] as Dictionary).get("action"), "detail_message", "approve effect appends detail")
	_assert_eq((approve_effects[approve_effects.size() - 1] as Dictionary).get("action"), "update_ui", "approve effect updates ui")

	var reject_plan := ChatApprovalModel.response_plan(command, "reject", "no", true)
	_assert_true(bool(reject_plan.get("ok", false)), "reject response plan ok")
	_assert_true(bool(reject_plan.get("clear_approval", false)), "reject clears approval locally")
	_assert_eq(str(reject_plan.get("clear_message", "")), "Approval reject sent.", "reject clear message")

	var reject_effect_plan := ChatApprovalModel.response_effect_plan(command, "reject", "no", true)
	var reject_effects := reject_effect_plan.get("effects", []) as Array
	_assert_eq((reject_effects[0] as Dictionary).get("action"), "send_json", "reject effect sends json first")
	_assert_true(_has_action(reject_effects, "clear_approval"), "reject effect clears approval")

	var blocked_effect_plan := ChatApprovalModel.response_effect_plan(permission_grant, "approve", "", true)
	var blocked_effects := blocked_effect_plan.get("effects", []) as Array
	_assert_eq((blocked_effects[0] as Dictionary).get("action"), "system_message", "blocked effect appends system message")
	_assert_eq((blocked_effects[blocked_effects.size() - 1] as Dictionary).get("action"), "update_ui", "blocked effect updates ui")


func _has_action(effects: Array, action: String) -> bool:
	for effect in effects:
		if typeof(effect) == TYPE_DICTIONARY and str((effect as Dictionary).get("action", "")) == action:
			return true
	return false


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
