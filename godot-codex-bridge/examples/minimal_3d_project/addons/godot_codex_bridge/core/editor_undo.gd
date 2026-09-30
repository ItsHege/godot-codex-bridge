@tool
extends RefCounted

const BridgeContext := preload("bridge_context.gd")

const BRIDGE_ACTION_PREFIX := "Godot Codex Bridge:"
const MAX_TRACKED_ACTIONS := 32

var _context: BridgeContext
## Bridge commits observed around EditorControl actions, oldest first:
## {history_id, version, action_name, seq_before, seq_after}.
var _records: Array = []
## Counts every commit/undo/redo the editor reports through
## EditorUndoRedoManager (history_changed + version_changed). A record is only
## undoable while this still equals its seq_after, i.e. nothing - including a
## user edit, undo or redo in any history - happened after it.
var _seq := 0
var _observed_manager: EditorUndoRedoManager
## Test seam: Callable() -> bool that performs the editor-level undo.
var editor_undo_trigger := Callable()


func _init(context: BridgeContext = null) -> void:
	_context = context


## Called by EditorControl before a registered action runs.
func begin_tracking() -> Dictionary:
	if _undo_redo() == null:
		return {}
	_observe_manager()
	return {"seq": _seq, "versions": _candidate_versions()}


## Called by EditorControl after the action returns. Records the Bridge action
## the handler committed when exactly one candidate history gained one.
func end_tracking(token: Dictionary) -> void:
	var manager := _undo_redo()
	if manager == null or token.is_empty():
		return
	var before: Dictionary = token.get("versions", {})
	var changed: Array = []
	for history_id in _candidate_versions().keys():
		var history := manager.get_history_undo_redo(int(history_id))
		if history != null and history.get_version() > int(before.get(history_id, history.get_version())):
			changed.append(int(history_id))
	if changed.size() != 1:
		if not changed.is_empty():
			_records.clear()
		return
	var changed_history := manager.get_history_undo_redo(int(changed[0]))
	var action_name := str(changed_history.get_current_action_name())
	if not is_bridge_action_name(action_name):
		return
	_records.append({
		"history_id": int(changed[0]),
		"version": changed_history.get_version(),
		"action_name": action_name,
		"seq_before": int(token.get("seq", -1)),
		"seq_after": _seq,
	})
	while _records.size() > MAX_TRACKED_ACTIONS:
		_records.pop_front()


func tracked_action_count() -> int:
	return _records.size()


## Undoes exactly the latest Bridge action through the editor's own Undo, which
## picks the newest action across the global and current-scene histories and
## keeps EditorUndoRedoManager's bookkeeping consistent. Refuses when anything
## newer exists, so a user action is never undone.
func undo_last_bridge_action(_params: Dictionary = {}) -> Dictionary:
	if not _permission_enabled("allow_scene_edits"):
		return _err("permission_denied", "Scene edits via UndoRedo permission is disabled in the Codex Bridge dock.")

	var manager := _undo_redo()
	if manager == null:
		return _err("undo_redo_unavailable", "Editor UndoRedo manager is unavailable.")
	_observe_manager()
	if _records.is_empty():
		return _err("no_tracked_bridge_action", "No Godot Codex Bridge action from this editor session is available to undo.")
	var record: Dictionary = _records.back()
	var history_id := int(record.get("history_id", EditorUndoRedoManager.INVALID_HISTORY))
	var action_name := str(record.get("action_name", ""))
	var details := {"action_name": action_name, "history_id": history_id}
	if _seq != int(record.get("seq_after", -1)):
		return _err("newer_editor_action", "An editor action, undo or redo happened after the latest Godot Codex Bridge action, so nothing was undone.", details)
	var history := manager.get_history_undo_redo(history_id)
	if history == null or not history.has_undo() or history.get_version() != int(record.get("version", -1)) or str(history.get_current_action_name()) != action_name:
		return _err("not_bridge_action", "The latest undo action in that history is not the tracked Godot Codex Bridge action, so it was not undone.", details)
	var scene_root := EditorInterface.get_edited_scene_root()
	var scene_history := manager.get_object_history_id(scene_root) if scene_root != null else EditorUndoRedoManager.INVALID_HISTORY
	if history_id != EditorUndoRedoManager.GLOBAL_HISTORY and history_id != scene_history:
		return _err("bridge_action_in_other_scene", "The latest Godot Codex Bridge action belongs to another open scene. Switch to that scene tab first.", details)

	var others := _candidate_versions()
	others.erase(history_id)
	var version_before := history.get_version()
	if not _trigger_editor_undo():
		return _err("editor_undo_unavailable", "The editor Undo command could not be located, so nothing was undone.", details)
	var version_after := history.get_version()
	var others_after := _candidate_versions()
	for other_id in others.keys():
		if int(others_after.get(other_id, others[other_id])) != int(others[other_id]):
			_records.clear()
			return _err("undo_mismatch", "The editor undid an action in a different history. Bridge undo tracking was reset; check the editor history.", details)
	if version_after != version_before - 1:
		return _err("undo_failed", "The editor did not undo the latest Godot Codex Bridge action.", details)

	_records.pop_back()
	# The previous record stays undoable only if nothing happened between it and
	# the action just undone.
	if not _records.is_empty() and int((_records.back() as Dictionary).get("seq_after", -1)) == int(record.get("seq_before", -2)):
		(_records.back() as Dictionary)["seq_after"] = _seq
	var snapshot := _refresh("editor_control:undo_last_bridge_action")
	var data := undo_state_payload(action_name, history_id, version_before, version_after, snapshot)
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


func _observe_manager() -> void:
	var manager := _undo_redo()
	if manager == null or manager == _observed_manager:
		return
	_observed_manager = manager
	manager.history_changed.connect(_bump_sequence)
	manager.version_changed.connect(_bump_sequence)


func _bump_sequence() -> void:
	_seq += 1


## Versions of the histories the editor's Undo chooses between.
func _candidate_versions() -> Dictionary:
	var manager := _undo_redo()
	var versions := {}
	if manager == null:
		return versions
	var ids := [EditorUndoRedoManager.GLOBAL_HISTORY]
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root != null:
		ids.append(manager.get_object_history_id(scene_root))
	for history_id in ids:
		var history := manager.get_history_undo_redo(int(history_id))
		if history != null:
			versions[int(history_id)] = history.get_version()
	return versions


## EditorUndoRedoManager.undo() is not exposed to scripts in Godot 4.7, and
## calling UndoRedo.undo() on one history directly desynchronizes the
## manager's own undo/redo stacks. Run the editor's main Undo menu command
## instead. The "ui_undo" Shortcut object is shared with the script and shader
## editors' text Undo items, so only an item in a PopupMenu directly under the
## editor title bar's MenuBar qualifies, and it must be unique.
func _trigger_editor_undo() -> bool:
	if editor_undo_trigger.is_valid():
		return bool(editor_undo_trigger.call())
	var settings := EditorInterface.get_editor_settings()
	if settings == null or not settings.has_shortcut("ui_undo"):
		return false
	var found := find_menu_item(EditorInterface.get_base_control(), settings.get_shortcut("ui_undo"))
	if found.is_empty():
		return false
	(found.get("menu") as PopupMenu).id_pressed.emit(int(found.get("id")))
	return true


## Returns {menu, id} for the single main-menu item using `shortcut`, or {} when
## there is no such item or more than one.
static func find_menu_item(root: Node, shortcut: Shortcut) -> Dictionary:
	if root == null or shortcut == null:
		return {}
	var matches: Array = []
	_collect_main_menu_items(root, shortcut, matches)
	return matches[0] if matches.size() == 1 else {}


static func is_main_menu_popup(menu: PopupMenu) -> bool:
	var bar := menu.get_parent()
	return bar is MenuBar and bar.get_parent() != null and bar.get_parent().get_class() == "EditorTitleBar"


static func _collect_main_menu_items(node: Node, shortcut: Shortcut, matches: Array) -> void:
	if node is PopupMenu and is_main_menu_popup(node as PopupMenu):
		var menu := node as PopupMenu
		for index in range(menu.item_count):
			if menu.get_item_shortcut(index) == shortcut:
				matches.append({"menu": menu, "id": menu.get_item_id(index)})
	for child in node.get_children(true):
		_collect_main_menu_items(child, shortcut, matches)


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
