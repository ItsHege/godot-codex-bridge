@tool
extends RefCounted

## Shared runtime context handed to every core/ service module while the
## monolithic plugin.gd is being split up.
##
## Design rule for service modules: never reach into plugin.gd members directly.
## Everything a service needs (undo, permissions, snapshot refresh, logging)
## is exposed here. EditorInterface is a global singleton in Godot 4.2+, so it
## is intentionally NOT carried on the context - call it directly.

## EditorUndoRedoManager from EditorPlugin.get_undo_redo().
var undo_redo: EditorUndoRedoManager

## Reference (not a copy) to plugin.gd's `_permissions` dictionary.
var permissions: Dictionary = {}

## References to read-only runtime buffers used by scene introspection.
var bridge_log: Array = []
var recent_editor_actions: Array = []
var performance_history: Array = []
var diagnostics_cleared_at := ""
var screenshots_dir_abs := ""
var annotations_dir_abs := ""
var bridge_dir_abs := ""
var owner_node: Node

## Callable(reason: String) -> Dictionary. Wraps plugin._write_context_snapshot.
var refresh_snapshot: Callable = Callable()

## Callable(event_name: String, data: Dictionary = {}) -> void. Wraps plugin._log_event.
var log_event: Callable = Callable()

## Callable(action: String, status: String, data: Dictionary) -> void.
## Wraps plugin._record_editor_action.
var record_editor_action: Callable = Callable()

## Callable() -> void. Wraps plugin._ensure_bridge_dirs.
var ensure_bridge_dirs: Callable = Callable()
var append_chat_system: Callable = Callable()
var write_json_file: Callable = Callable()
var current_scene_path: Callable = Callable()
var selected_node_paths: Callable = Callable()
var iso_now: Callable = Callable()
var safe_identifier: Callable = Callable()
var file_timestamp: Callable = Callable()
var error_payload: Callable = Callable()
var diagnostics_cleared_changed: Callable = Callable()


func permission_enabled(key: String) -> bool:
	return bool(permissions.get(key, false))


func refresh(reason: String) -> Dictionary:
	if refresh_snapshot.is_valid():
		var result: Variant = refresh_snapshot.call(reason)
		if typeof(result) == TYPE_DICTIONARY:
			return result
	return {}


func log(event_name: String, data: Dictionary = {}) -> void:
	if log_event.is_valid():
		log_event.call(event_name, data)


func record_action(action: String, status: String, data: Dictionary) -> void:
	if record_editor_action.is_valid():
		record_editor_action.call(action, status, data)


func ensure_dirs() -> void:
	if ensure_bridge_dirs.is_valid():
		ensure_bridge_dirs.call()


func append_status(message: String) -> void:
	if append_chat_system.is_valid():
		append_chat_system.call(message)


func write_json(path: String, data: Dictionary) -> Dictionary:
	if write_json_file.is_valid():
		var result: Variant = write_json_file.call(path, data)
		if typeof(result) == TYPE_DICTIONARY:
			return result
	return err("write_json_unavailable", "Bridge JSON writer is unavailable.")


func current_scene_or_null() -> Variant:
	if current_scene_path.is_valid():
		return current_scene_path.call()
	return null


func selected_nodes() -> Array:
	if selected_node_paths.is_valid():
		var result: Variant = selected_node_paths.call()
		if result is Array:
			return result
	return []


func timestamp_iso() -> String:
	if iso_now.is_valid():
		return str(iso_now.call())
	return Time.get_datetime_string_from_system(true, true)


func file_time() -> String:
	if file_timestamp.is_valid():
		return str(file_timestamp.call())
	return Time.get_datetime_string_from_system(true).replace("-", "").replace(":", "")


func identifier(value: String, fallback := "item") -> String:
	if safe_identifier.is_valid():
		return str(safe_identifier.call(value))
	var cleaned := value.strip_edges().replace(" ", "_")
	return cleaned if cleaned != "" else fallback


func err(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	if error_payload.is_valid():
		var result: Variant = error_payload.call(code, message)
		if typeof(result) == TYPE_DICTIONARY:
			var typed_result: Dictionary = result
			if not details.is_empty():
				typed_result["details"] = details
			return typed_result
	var payload := {
		"code": code,
		"message": message,
	}
	if not details.is_empty():
		payload["details"] = details
	return payload


func set_diagnostics_cleared_at(value: String) -> void:
	diagnostics_cleared_at = value
	if diagnostics_cleared_changed.is_valid():
		diagnostics_cleared_changed.call(value)
