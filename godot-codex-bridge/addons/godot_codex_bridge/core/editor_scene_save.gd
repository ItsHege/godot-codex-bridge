@tool
extends RefCounted

const BridgeContext := preload("bridge_context.gd")

var _context: BridgeContext


func _init(context: BridgeContext = null) -> void:
	_context = context


func save_scene(_params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_scene_save"):
		return _err("permission_denied", "Scene save permission is disabled in the Codex Bridge dock.")

	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return _err("no_current_scene", "No edited scene is open.")

	var scene_path := scene_root.scene_file_path
	var result_code := EditorInterface.save_scene()
	var result_name := error_string(result_code)
	if result_code != OK:
		return {
			"ok": false,
			"error": _error_payload("scene_save_failed", "Godot failed to save the current scene: " + result_name, {
				"result_code": result_code,
				"result_name": result_name,
				"scene_path": scene_path,
			}),
		}

	var snapshot := _refresh("editor_control:save_scene")
	var current_scene := current_scene_payload(EditorInterface.get_edited_scene_root())
	var open_scenes := open_scene_paths_payload(EditorInterface.get_open_scenes())
	var save_state := save_state_payload(
		"current_scene",
		scene_path,
		open_scenes,
		current_scene,
		result_code,
		result_name,
		snapshot,
		true
	)
	var data := {
		"saved": true,
		"changed": true,
		"save_scope": "current_scene",
		"scene_path": scene_path,
		"current_scene": current_scene,
		"open_scenes": open_scenes,
		"save_state": save_state,
		"result_code": result_code,
		"result_name": result_name,
		"snapshot_refreshed": true,
		"generated_at": snapshot.get("generated_at", ""),
	}
	_log("editor_scene_saved", data)
	return _ok(data)


func save_all_scenes(_params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_scene_save"):
		return _err("permission_denied", "Scene save permission is disabled in the Codex Bridge dock.")

	var before_open_scenes := open_scene_paths_payload(EditorInterface.get_open_scenes())
	EditorInterface.save_all_scenes()
	var snapshot := _refresh("editor_control:save_all_scenes")
	var current_scene := current_scene_payload(EditorInterface.get_edited_scene_root())
	var open_scenes := open_scene_paths_payload(EditorInterface.get_open_scenes())
	var save_state := save_all_state_payload(before_open_scenes, open_scenes, current_scene, snapshot)
	var data := {
		"saved": true,
		"changed": true,
		"save_scope": "all_open_scenes",
		"open_scenes_before": before_open_scenes,
		"open_scenes": open_scenes,
		"current_scene": current_scene,
		"save_state": save_state,
		"snapshot_refreshed": true,
		"generated_at": snapshot.get("generated_at", ""),
	}
	_log("editor_all_scenes_saved", data)
	return _ok(data)


static func current_scene_payload(scene_root: Node) -> Dictionary:
	if scene_root == null:
		return {
			"path": "",
			"name": "",
			"type": "",
		}
	return {
		"path": scene_root.scene_file_path,
		"name": scene_root.name,
		"type": scene_root.get_class(),
	}


static func open_scene_paths_payload(open_scenes: PackedStringArray) -> Array:
	var result: Array = []
	for scene_path in open_scenes:
		result.append(str(scene_path))
	return result


static func save_state_payload(save_scope: String, scene_path: String, open_scenes: Array, current_scene: Dictionary, result_code: int, result_name: String, snapshot: Dictionary, saved_to_disk: bool) -> Dictionary:
	var status := "saved_to_disk" if saved_to_disk else "save_failed"
	return {
		"status": status,
		"save_scope": save_scope,
		"target_scene": scene_path,
		"current_scene": current_scene,
		"open_scenes": open_scenes,
		"result_code": result_code,
		"result_name": result_name,
		"snapshot_refreshed": not snapshot.is_empty(),
		"generated_at": snapshot.get("generated_at", ""),
		"dirty_state": {
			"before": "unknown",
			"after": "saved_scope_persisted" if saved_to_disk else "unknown",
			"source": "EditorInterface.save_scene",
			"note": "Godot does not expose a direct stable dirty-scene query here; this state is derived from the save result.",
		},
		"agent_guidance": "Current scene was saved to disk; no manual Ctrl+S is expected for this scene." if saved_to_disk else "Save failed; do not assume scene edits persisted.",
	}


static func save_all_state_payload(open_scenes_before: Array, open_scenes_after: Array, current_scene: Dictionary, snapshot: Dictionary) -> Dictionary:
	return {
		"status": "save_all_requested",
		"save_scope": "all_open_scenes",
		"target_scene": null,
		"current_scene": current_scene,
		"open_scenes_before": open_scenes_before,
		"open_scenes": open_scenes_after,
		"snapshot_refreshed": not snapshot.is_empty(),
		"generated_at": snapshot.get("generated_at", ""),
		"dirty_state": {
			"before": "unknown",
			"after": "save_all_requested",
			"source": "EditorInterface.save_all_scenes",
			"note": "Godot save_all_scenes does not return per-scene result codes through this bridge path.",
		},
		"agent_guidance": "Save-all was requested and the bridge refreshed context afterward; inspect logs if a specific scene still appears unsaved in the editor.",
	}


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


func _err(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"error": _error_payload(code, message),
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
