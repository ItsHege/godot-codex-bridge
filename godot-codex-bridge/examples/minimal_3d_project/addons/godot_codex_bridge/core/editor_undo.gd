@tool
extends RefCounted

const BridgeContext := preload("bridge_context.gd")

const BRIDGE_ACTION_PREFIX := "Godot Codex Bridge:"

var _context: BridgeContext


func _init(context: BridgeContext = null) -> void:
	_context = context


func undo_last_bridge_action(_params: Dictionary = {}) -> Dictionary:
	if not _permission_enabled("allow_scene_edits"):
		return _err("permission_denied", "Scene edits via UndoRedo permission is disabled in the Codex Bridge dock.")

	var manager := _undo_redo()
	if manager == null:
		return _err("undo_redo_unavailable", "Editor UndoRedo manager is unavailable.")
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return _err("no_current_scene", "No edited scene is open.")

	var history_id := manager.get_object_history_id(scene_root)
	var history := manager.get_history_undo_redo(history_id)
	if history == null:
		return _err("undo_history_unavailable", "Undo history is unavailable for the current edited scene.", {"history_id": history_id})
	if not history.has_undo():
		return _err("no_undo_available", "No undo action is available for the current edited scene.", {"history_id": history_id})

	var action_name := str(history.get_current_action_name())
	if not is_bridge_action_name(action_name):
		return _err(
			"not_bridge_action",
			"The latest undo action is not a Godot Codex Bridge action, so it was not undone.",
			{"action_name": action_name, "history_id": history_id}
		)

	var version_before := history.get_version()
	var undone := history.undo()
	if not undone:
		return _err("undo_failed", "Godot UndoRedo rejected undo for the latest bridge action.", {"action_name": action_name, "history_id": history_id})

	var snapshot := _refresh("editor_control:undo_last_bridge_action")
	var data := undo_state_payload(action_name, history_id, version_before, history.get_version(), snapshot)
	_log("editor_bridge_action_undone", data)
	return _ok(data)


static func is_bridge_action_name(action_name: String) -> bool:
	return action_name.begins_with(BRIDGE_ACTION_PREFIX)


static func undo_state_payload(action_name: String, history_id: int, version_before: int, version_after: int, snapshot: Dictionary) -> Dictionary:
	return {
		"status": "undone",
		"undone": true,
		"action_name": action_name,
		"history_id": history_id,
		"version_before": version_before,
		"version_after": version_after,
		"auto_saved": false,
		"snapshot_refreshed": true,
		"generated_at": snapshot.get("generated_at", ""),
		"current_scene": snapshot.get("current_scene", {}),
		"agent_guidance": "The latest Godot Codex Bridge editor action was undone in the live editor only. Save explicitly if the reverted state should be persisted.",
	}


func _undo_redo() -> EditorUndoRedoManager:
	return _context.undo_redo if _context != null else null


func _permission_enabled(key: String) -> bool:
	return _context.permission_enabled(key) if _context != null else false


func _refresh(reason: String) -> Dictionary:
	return _context.refresh(reason) if _context != null else {}


func _log(event_name: String, data: Dictionary) -> void:
	if _context != null:
		_context.log(event_name, data)


func _ok(data: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"data": data,
	}


func _err(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	return {
		"ok": false,
		"error": _error_payload(code, message, details),
	}


func _error_payload(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	if _context != null:
		return _context.err(code, message, details)
	var payload := {
		"code": code,
		"message": message,
	}
	if not details.is_empty():
		payload["details"] = details
	return payload
