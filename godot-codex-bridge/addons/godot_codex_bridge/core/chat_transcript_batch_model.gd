@tool
extends RefCounted

const ChatDiffModel := preload("chat_diff_model.gd")
const ChatTranscriptModel := preload("chat_transcript_model.gd")


static func empty_work_state() -> Dictionary:
	return {
		"text": "",
		"updates": 0,
		"item_id": "",
		"visible": false,
	}


static func assistant_delta_route(text: String, phase: String = "", active_phase: String = "") -> Dictionary:
	if text == "":
		return {
			"route": "ignore",
			"phase": "",
		}
	var normalized_phase := ChatTranscriptModel.normalize_message_phase(phase)
	if (
		normalized_phase == ""
		and active_phase.strip_edges() == ""
		and ChatTranscriptModel.looks_like_work_update(text)
	):
		normalized_phase = "commentary"
	if normalized_phase == "commentary":
		return {
			"route": "work",
			"phase": normalized_phase,
		}
	return {
		"route": "assistant",
		"phase": normalized_phase,
	}


static func record_work_update(state: Dictionary, text: String, item_id: String = "") -> Dictionary:
	var trimmed := text.strip_edges(false, true)
	if trimmed == "":
		return {
			"changed": false,
			"state": state.duplicate(),
		}

	var next_state := state.duplicate()
	var current_text := str(next_state.get("text", ""))
	var current_item_id := str(next_state.get("item_id", ""))
	var normalized_item_id := item_id.strip_edges()
	var starts_new_note := current_text == ""
	if normalized_item_id != "" and normalized_item_id != current_item_id:
		starts_new_note = true

	if starts_new_note:
		next_state["updates"] = int(next_state.get("updates", 0)) + 1
		if current_text != "":
			current_text += "\n\n"

	if normalized_item_id != "":
		next_state["item_id"] = normalized_item_id

	current_text += text
	next_state["text"] = current_text

	return {
		"changed": true,
		"starts_new_note": starts_new_note,
		"state": next_state,
	}


static func record_work_update_effect_plan(state: Dictionary, text: String, item_id: String = "", has_work_panel := false) -> Dictionary:
	var result := record_work_update(state, text, item_id)
	if not bool(result.get("changed", false)):
		return {
			"changed": false,
			"effects": [],
			"state": result.get("state", state.duplicate()),
		}
	var next_state := result.get("state", {}) as Dictionary
	var effects: Array = [
		{"action": "flush_assistant_text"},
		{"action": "apply_work_state", "state": next_state},
	]
	if not has_work_panel:
		effects.append({"action": "ensure_work_panel"})
	effects.append({"action": "update_work_batch"})
	return {
		"changed": true,
		"starts_new_note": bool(result.get("starts_new_note", false)),
		"effects": effects,
		"state": next_state,
	}


static func work_state_visible(state: Dictionary, visible: bool) -> Dictionary:
	var next_state := state.duplicate()
	next_state["visible"] = visible
	return next_state


static func empty_diff_state() -> Dictionary:
	return {
		"text": "",
		"updates": 0,
		"files": PackedStringArray(),
		"file_count": 0,
		"added_count": 0,
		"removed_count": 0,
		"files_visible": false,
	}


static func record_diff_update(state: Dictionary, diff_text: String) -> Dictionary:
	var next_state := state.duplicate()
	next_state["updates"] = int(next_state.get("updates", 0)) + 1
	next_state["text"] = diff_text
	next_state["files"] = ChatDiffModel.extract_diff_files(diff_text)
	return {
		"changed": true,
		"state": next_state,
	}


static func record_diff_update_effect_plan(state: Dictionary, diff_text: String, has_diff_panel := false) -> Dictionary:
	var result := record_diff_update(state, diff_text)
	var next_state := result.get("state", {}) as Dictionary
	var effects: Array = [
		{"action": "flush_assistant_text"},
		{"action": "apply_diff_state", "state": next_state},
	]
	if not has_diff_panel:
		effects.append({"action": "ensure_diff_panel"})
	effects.append({"action": "update_diff_batch"})
	return {
		"changed": bool(result.get("changed", true)),
		"effects": effects,
		"state": next_state,
	}


static func diff_state_with_counts(state: Dictionary, diff_result: Dictionary) -> Dictionary:
	var next_state := state.duplicate()
	next_state["file_count"] = int(diff_result.get("file_count", 0))
	next_state["added_count"] = int(diff_result.get("added_count", 0))
	next_state["removed_count"] = int(diff_result.get("removed_count", 0))
	return next_state


static func diff_state_visible(state: Dictionary, visible: bool) -> Dictionary:
	var next_state := state.duplicate()
	next_state["files_visible"] = visible
	return next_state
