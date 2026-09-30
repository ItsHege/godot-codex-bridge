@tool
extends RefCounted

const BridgeContext := preload("bridge_context.gd")

var _context: BridgeContext


func _init(context: BridgeContext = null) -> void:
	_context = context


func save_scene(_params: Dictionary) -> Dictionary:
	return _err("trusted_scene_save_approval_unavailable", "Bridge-request scene saving is disabled until an exact, short-lived, single-use human approval receipt is available. Save from the Godot editor UI.")


func save_all_scenes(_params: Dictionary) -> Dictionary:
	return _err("trusted_scene_save_approval_unavailable", "Bridge-request save-all is disabled until exact, short-lived, single-use human approval receipts are available for every dirty scene. Save from the Godot editor UI.")


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
