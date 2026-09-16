@tool
extends RefCounted

const ChatDiffModel := preload("chat_diff_model.gd")
const ChatTranscriptModel := preload("chat_transcript_model.gd")


static func can_approve(params: Dictionary) -> bool:
	if params.is_empty():
		return false
	if params.has("approvable_by_chat") and not bool(params.get("approvable_by_chat", false)):
		return false
	if str(params.get("safe_default", "reject")) != "manual_only":
		return false
	if str(params.get("nonce", "")) == "":
		return false
	var kind := str(params.get("kind", "unknown"))
	if kind == "file_change" or kind == "apply_patch":
		return str(params.get("diff_hash", "")) != ""
	if kind == "elicitation" or kind == "command_execution" or kind == "exec_command":
		return true
	if not bool(params.get("approvable_by_chat", false)):
		return false
	return true


static func can_approve_session(params: Dictionary) -> bool:
	if not can_approve(params):
		return false
	var kind := str(params.get("kind", "unknown"))
	return kind == "command_execution" or kind == "exec_command" or kind == "file_change" or kind == "apply_patch"


static func disabled_reason(params: Dictionary) -> String:
	if params.is_empty():
		return "No active approval."
	var blocked_reason := str(params.get("blocked_reason", "")).strip_edges()
	if blocked_reason != "":
		return blocked_reason
	var kind := str(params.get("kind", "unknown"))
	if str(params.get("safe_default", "reject")) != "manual_only":
		return "This approval does not have a manual-only safe policy."
	if str(params.get("nonce", "")) == "":
		return "Approval nonce is missing."
	if (kind == "file_change" or kind == "apply_patch") and str(params.get("diff_hash", "")) == "":
		return "Diff hash is missing, so Codex cannot prove the approved content matches the displayed diff."
	if kind != "elicitation" and kind != "file_change" and kind != "apply_patch" and kind != "command_execution" and kind != "exec_command":
		return "Only file diffs, commands and Codex user questions can be approved from Godot chat. Permission grants stay blocked."
	return "Approval is not available."


static func approval_summary(params: Dictionary, command_limit := 1000, file_path_limit := 12) -> String:
	var lines: Array[String] = []
	lines.append("Approval: " + str(params.get("approval_id", "")))
	lines.append("Kind: " + str(params.get("kind", "unknown")))
	lines.append("Chat approval: " + ("available" if can_approve(params) else "blocked"))
	if can_approve_session(params):
		lines.append("Session approval: available")
	if not can_approve(params):
		lines.append("Blocked reason: " + disabled_reason(params))
	elif str(params.get("approval_policy_label", "")) != "":
		lines.append("Policy: " + str(params.get("approval_policy_label", "")))
	lines.append("Safe default: " + str(params.get("safe_default", "reject")))
	lines.append("Nonce: " + str(params.get("nonce", "")))
	lines.append("Expires: " + str(params.get("expires_at", "")))
	lines.append("Reason: " + str(params.get("reason", "")))
	if str(params.get("cwd", "")) != "":
		lines.append("CWD: " + str(params.get("cwd", "")))
	if params.has("command") and params.get("command") != null:
		lines.append("Command: " + ChatTranscriptModel.truncate_text(str(params.get("command")), command_limit))
	if str(params.get("grant_root", "")) != "":
		lines.append("Grant root: " + str(params.get("grant_root", "")))
	if str(params.get("diff_hash", "")) != "":
		lines.append("Diff hash: " + str(params.get("diff_hash", "")))
	if params.has("file_changes") and params.get("file_changes") != null:
		lines.append("")
		lines.append(ChatDiffModel.file_changes_summary(params.get("file_changes"), file_path_limit))
	return "\n".join(lines)


static func notice_text(params: Dictionary) -> String:
	if not can_approve(params):
		return "Approval requested but Approve is blocked for this request type."
	var kind := str(params.get("kind", ""))
	if kind == "elicitation":
		return "Codex is asking for confirmation."
	if kind == "command_execution" or kind == "exec_command":
		return "Codex requested command approval."
	return "Approval requested; review the card before approving."


static func response_payload(params: Dictionary, decision: String, note: String) -> Dictionary:
	return {
		"approval_id": str(params.get("approval_id", "")),
		"nonce": str(params.get("nonce", "")),
		"diff_hash": str(params.get("diff_hash", "")),
		"decision": decision,
		"note": note,
	}


static func show_plan(params: Dictionary, active_diff_text: String) -> Dictionary:
	var diff_text := ""
	if params.has("file_changes") and params.get("file_changes") != null and active_diff_text.strip_edges() == "":
		diff_text = ChatDiffModel.diff_from_file_changes(params.get("file_changes"))
	return {
		"active_approval": params.duplicate(true),
		"title": "Approval required: " + str(params.get("kind", "unknown")),
		"body": approval_summary(params),
		"note_text": "",
		"note_placeholder": "Optional answer/note for Codex" if str(params.get("kind", "")) == "elicitation" else "Optional note for Codex",
		"diff_text": diff_text,
		"detail_message": notice_text(params),
		"show_panel": true,
		"scroll_to_bottom": true,
		"update_ui": true,
	}


static func show_effect_plan(params: Dictionary, active_diff_text: String) -> Dictionary:
	var plan := show_plan(params, active_diff_text)
	var effects: Array[Dictionary] = [
		{
			"action": "set_active_approval",
			"value": plan.get("active_approval", {}),
		},
		{
			"action": "show_panel",
			"visible": bool(plan.get("show_panel", true)),
		},
		{
			"action": "set_title",
			"text": str(plan.get("title", "")),
		},
		{
			"action": "set_body",
			"text": str(plan.get("body", "")),
		},
		{
			"action": "set_note",
			"text": str(plan.get("note_text", "")),
			"placeholder": str(plan.get("note_placeholder", "Optional note for Codex")),
		},
	]
	var approval_diff := str(plan.get("diff_text", ""))
	if approval_diff != "":
		effects.append({
			"action": "record_diff",
			"diff_text": approval_diff,
		})
	var detail_message := str(plan.get("detail_message", ""))
	if detail_message != "":
		effects.append({
			"action": "detail_message",
			"message": detail_message,
		})
	if bool(plan.get("scroll_to_bottom", true)):
		effects.append({
			"action": "scroll_to_bottom",
		})
	if bool(plan.get("update_ui", true)):
		effects.append({
			"action": "update_ui",
		})
	return {
		"plan": plan,
		"effects": effects,
	}


static func clear_plan(message: String) -> Dictionary:
	return {
		"active_approval": {},
		"panel_visible": false,
		"body": "",
		"note_text": "",
		"detail_message": message,
		"update_ui": true,
	}


static func clear_effect_plan(message: String) -> Dictionary:
	var plan := clear_plan(message)
	var effects: Array[Dictionary] = [
		{
			"action": "set_active_approval",
			"value": plan.get("active_approval", {}),
		},
		{
			"action": "set_panel_visible",
			"visible": bool(plan.get("panel_visible", false)),
		},
		{
			"action": "set_body",
			"text": str(plan.get("body", "")),
		},
		{
			"action": "set_note_text",
			"text": str(plan.get("note_text", "")),
		},
		{
			"action": "detail_message",
			"message": str(plan.get("detail_message", "")),
		},
	]
	if bool(plan.get("update_ui", true)):
		effects.append({
			"action": "update_ui",
		})
	return {
		"plan": plan,
		"effects": effects,
	}


static func response_plan(params: Dictionary, decision: String, note: String, socket_ready: bool) -> Dictionary:
	if params.is_empty():
		return {
			"ok": false,
			"action": "ignore",
		}
	if not socket_ready:
		return {
			"ok": false,
			"action": "status",
			"system_message": "Codex is not connected; approval response was not sent.",
		}
	if decision == "approve" and not can_approve(params):
		return {
			"ok": false,
			"action": "status",
			"system_message": "Approve is blocked: " + disabled_reason(params),
			"update_ui": true,
		}
	if decision == "approve_session" and not can_approve_session(params):
		return {
			"ok": false,
			"action": "status",
			"system_message": "Approve Session is not available for this request type.",
			"update_ui": true,
		}
	if str(params.get("approval_id", "")) == "":
		return {
			"ok": false,
			"action": "status",
			"system_message": "Approval id is missing; response was not sent.",
		}
	if str(params.get("nonce", "")) == "":
		return {
			"ok": false,
			"action": "status",
			"system_message": "Approval nonce is missing; response was not sent.",
		}
	return {
		"ok": true,
		"method": "approval.respond",
		"params": response_payload(params, decision, note),
		"detail_message": "Approval response sent: " + decision,
		"clear_approval": decision != "approve" and decision != "approve_session",
		"clear_message": "Approval " + decision + " sent.",
		"update_ui": decision == "approve" or decision == "approve_session",
	}


static func response_effect_plan(params: Dictionary, decision: String, note: String, socket_ready: bool) -> Dictionary:
	var plan := response_plan(params, decision, note, socket_ready)
	var effects: Array[Dictionary] = []
	if not bool(plan.get("ok", false)):
		var system_message := str(plan.get("system_message", ""))
		if system_message != "":
			effects.append({
				"action": "system_message",
				"message": system_message,
			})
		if bool(plan.get("update_ui", false)):
			effects.append({
				"action": "update_ui",
			})
		return {
			"plan": plan,
			"effects": effects,
		}

	effects.append({
		"action": "send_json",
		"method": str(plan.get("method", "approval.respond")),
		"params": plan.get("params", {}),
	})
	var detail_message := str(plan.get("detail_message", ""))
	if detail_message != "":
		effects.append({
			"action": "detail_message",
			"message": detail_message,
		})
	if bool(plan.get("clear_approval", false)):
		effects.append({
			"action": "clear_approval",
			"message": str(plan.get("clear_message", "")),
		})
	elif bool(plan.get("update_ui", true)):
		effects.append({
			"action": "update_ui",
		})
	return {
		"plan": plan,
		"effects": effects,
	}
