@tool
extends RefCounted

## Human-readable review content for an approval.requested card: title, what
## exactly is being approved, and small muted details. Pure logic; the popup
## and the dock bar render it. Decisions still go through ChatApprovalModel.

const ChatApprovalModel := preload("chat_approval_model.gd")
const ChatDiffModel := preload("chat_diff_model.gd")
const MAX_TEXT_CHARS := 8000
const MAX_FIELDS := 24


static func kind_group(params: Dictionary) -> String:
	match str(params.get("kind", "unknown")):
		"command_execution", "exec_command":
			return "command"
		"file_change", "apply_patch":
			return "files"
		"elicitation", "user_input":
			return "question"
	return "permission"


static func title(params: Dictionary) -> String:
	match kind_group(params):
		"command":
			return "Run command?"
		"files":
			return "Apply file changes?"
		"question":
			return "Codex asks:"
	return "Permission request"


static func icon_name(params: Dictionary) -> String:
	match kind_group(params):
		"command":
			return "Terminal"
		"files":
			return "File"
		"question":
			return "StatusWarning"
	return "Key"


## One line for the compact dock bar.
static func bar_text(params: Dictionary) -> String:
	var summary := title(params).trim_suffix(":").trim_suffix("?")
	match kind_group(params):
		"command":
			summary += ": " + command_text(params).get_slice("\n", 0).left(60)
		"question":
			summary += ": " + question_message(params).get_slice("\n", 0).left(60)
		"files":
			var count := file_paths(params).size()
			if count > 0:
				summary += " (" + str(count) + " file" + ("" if count == 1 else "s") + ")"
	return "Approval needed — " + summary


static func command_text(params: Dictionary) -> String:
	var value: Variant = params.get("command")
	if value is Array:
		var parts: Array[String] = []
		for part in value as Array:
			parts.append(str(part))
		return " ".join(parts)
	return "" if value == null else str(value)


static func raw_params(params: Dictionary) -> Dictionary:
	var raw: Variant = params.get("raw_params")
	return raw as Dictionary if raw is Dictionary else {}


## Elicitation text: app-server `message`, else legacy top-level fields.
static func question_message(params: Dictionary) -> String:
	var raw := raw_params(params)
	for source in [raw, params]:
		for key in ["message", "question", "prompt"]:
			var value: Variant = (source as Dictionary).get(key)
			if value != null and str(value).strip_edges() != "":
				return str(value).strip_edges().left(MAX_TEXT_CHARS)
	return str(params.get("reason", "")).strip_edges().left(MAX_TEXT_CHARS)


## Readable summary of the elicitation form. The Host fills the answer itself
## (first choice, true, 0, or your note for text), so fields are shown, not edited.
static func question_fields(params: Dictionary) -> Array:
	var raw := raw_params(params)
	var schema: Variant = raw.get("requestedSchema", raw.get("requested_schema", params.get("requested_schema")))
	var fields: Array = []
	if not (schema is Dictionary):
		return fields
	var properties: Variant = (schema as Dictionary).get("properties")
	if not (properties is Dictionary):
		return fields
	var required: Array = (schema as Dictionary).get("required", []) if (schema as Dictionary).get("required") is Array else []
	for key in (properties as Dictionary).keys():
		if fields.size() >= MAX_FIELDS:
			break
		var property: Dictionary = (properties as Dictionary)[key] if (properties as Dictionary)[key] is Dictionary else {}
		var type_value: Variant = property.get("type", "string")
		var type := str((type_value as Array)[0]) if type_value is Array and not (type_value as Array).is_empty() else str(type_value)
		var choices: Array[String] = []
		var enum_value: Variant = property.get("enum", property.get("oneOf"))
		if enum_value is Array:
			for option in enum_value as Array:
				choices.append(str((option as Dictionary).get("title", (option as Dictionary).get("const", ""))) if option is Dictionary else str(option))
		var answer := "your note"
		if not choices.is_empty():
			answer = choices[0]
		elif type == "boolean":
			answer = "yes"
		elif type == "number" or type == "integer":
			answer = "0"
		fields.append({
			"name": str(property.get("title", key)).left(120),
			"description": str(property.get("description", "")).left(400),
			"type": type,
			"choices": choices,
			"required": required.has(key),
			"answer": answer,
		})
	return fields


static func file_paths(params: Dictionary) -> Array[String]:
	var paths: Array[String] = []
	var changes: Variant = params.get("file_changes", params.get("diff_evidence"))
	if changes is Dictionary:
		for key in (changes as Dictionary).keys():
			var item: Variant = (changes as Dictionary)[key]
			paths.append(str((item as Dictionary).get("path", key)) if item is Dictionary else str(key))
	elif changes is Array:
		for item in changes as Array:
			if item is Dictionary:
				paths.append(str((item as Dictionary).get("path", (item as Dictionary).get("file", "file"))))
	return paths


static func diff_text(params: Dictionary) -> String:
	var changes: Variant = params.get("file_changes", params.get("diff_evidence"))
	return ChatDiffModel.diff_from_file_changes(changes) if changes != null else ""


## Full review content for the popup.
static func review(params: Dictionary) -> Dictionary:
	var sections: Array = []
	var group := kind_group(params)
	match group:
		"command":
			sections.append({"label": "Command", "text": command_text(params).left(MAX_TEXT_CHARS), "code": true})
			if str(params.get("cwd", "")) != "":
				sections.append({"label": "In folder", "text": str(params.get("cwd", "")), "code": true})
		"question":
			sections.append({"label": "", "text": question_message(params), "code": false})
			var raw := raw_params(params)
			if str(raw.get("url", "")) != "":
				sections.append({"label": "Link (not opened automatically)", "text": str(raw.get("url", "")).left(500), "code": true})
		"files":
			var paths := file_paths(params)
			sections.append({"label": str(paths.size()) + " file" + ("" if paths.size() == 1 else "s"), "text": "\n".join(paths.slice(0, 24)), "code": true})
		_:
			sections.append({"label": "Requested", "text": str(params.get("kind", "unknown")) + (" · " + str(params.get("grant_root", "")) if str(params.get("grant_root", "")) != "" else ""), "code": false})
	var reason := str(params.get("reason", "")).strip_edges()
	if reason != "" and group != "question":
		sections.append({"label": "Why", "text": reason.left(2000), "code": false})
	var can_approve := ChatApprovalModel.can_approve(params)
	return {
		"title": title(params),
		"icon": icon_name(params),
		"sections": sections,
		"fields": question_fields(params) if group == "question" else [],
		"diff_text": diff_text(params) if group == "files" else "",
		"blocked_reason": "" if can_approve else ChatApprovalModel.disabled_reason(params),
		"can_approve": can_approve,
		"can_approve_session": ChatApprovalModel.can_approve_session(params),
		"note_placeholder": "Answer / note for Codex (optional)" if group == "question" else "Note for Codex (optional)",
		"details": details_text(params),
	}


## Small muted identity line: ids and expiry, never the main content.
static func details_text(params: Dictionary) -> String:
	var parts: Array[String] = ["Approval " + str(params.get("approval_id", ""))]
	if str(params.get("expires_at", "")) != "":
		parts.append("expires " + str(params.get("expires_at", "")))
	if str(params.get("approval_policy_label", "")) != "":
		parts.append(str(params.get("approval_policy_label", "")))
	var server := str(raw_params(params).get("serverName", ""))
	if server != "":
		parts.append("from " + server)
	return " · ".join(parts)


## The popup opens by itself once per approval id; Review reopens it.
static func should_auto_open(params: Dictionary, opened_ids: Dictionary) -> bool:
	var approval_id := str(params.get("approval_id", "")).strip_edges()
	return approval_id != "" and not opened_ids.has(approval_id)


## True when the popup shows an approval that is no longer the active one.
static func popup_stale(popup_approval_id: String, active: Dictionary) -> bool:
	return popup_approval_id != "" and (active.is_empty() or str(active.get("approval_id", "")) != popup_approval_id)
