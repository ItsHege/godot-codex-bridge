@tool
extends RefCounted

const BridgeContext := preload("bridge_context.gd")
const BridgeLimits := preload("bridge_limits.gd")
const VariantCodec := preload("variant_codec.gd")

var _context: BridgeContext
var _notes_abs := ""


func _init(context: BridgeContext = null, notes_abs := "") -> void:
	_context = context
	_notes_abs = notes_abs


func get_diagnostics(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_editor_diagnostics"):
		return _err("permission_denied", "Diagnostics capture permission is disabled in the Codex Bridge dock.")
	var limit := int(params.get("limit", BridgeLimits.MAX_BRIDGE_LOG_EVENTS))
	return _ok(diagnostics_payload(limit))


func clear_diagnostics(_params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_clear_diagnostics"):
		return _err("permission_denied", "Clear diagnostics permission is disabled in the Codex Bridge dock.")

	var before := diagnostics_payload(BridgeLimits.MAX_BRIDGE_LOG_EVENTS)
	var cleared_at := _timestamp_iso()
	var evidence_name := "diagnostics_before_clear_" + _file_time() + ".json"
	var evidence_relative_path := ".godot/godot_codex_bridge/artifacts/" + evidence_name
	var evidence_path := _bridge_dir_abs().path_join("artifacts").path_join(evidence_name)
	var write_result := _write_json(evidence_path, before)
	if not write_result.get("ok", false):
		return write_result

	if _context != null:
		_context.bridge_log.clear()
		_context.set_diagnostics_cleared_at(cleared_at)
		_context.log("diagnostics_cleared", {
			"cleared_at": cleared_at,
			"evidence_path": evidence_relative_path,
		})

	return _ok({
		"cleared_sources": ["bridge_log"],
		"cleared_at": cleared_at,
		"evidence_path": evidence_relative_path,
		"remaining_counts": {
			"bridge_log": _bridge_log().size(),
		},
		"native_output_supported": false,
		"snapshot_refreshed": false,
	})


func diagnostics_payload(limit: int) -> Dictionary:
	var bounded_limit: int = clampi(limit, 1, BridgeLimits.MAX_BRIDGE_LOG_EVENTS)
	var log := _bridge_log()
	var entries: Array = []
	var start_index: int = max(0, log.size() - bounded_limit)
	for index in range(start_index, log.size()):
		var event: Variant = log[index]
		if typeof(event) != TYPE_DICTIONARY:
			continue
		var event_dict: Dictionary = event
		entries.append({
			"timestamp": event_dict.get("at", null),
			"level": "info",
			"source": "bridge_log",
			"message": str(event_dict.get("type", "")),
			"data": VariantCodec.variant_to_json_value(event_dict.get("data", {}), 0, BridgeLimits.MAX_PROPERTY_DEPTH, BridgeLimits.MAX_ARRAY_ITEMS, BridgeLimits.MAX_DICTIONARY_ITEMS),
		})
	var cleared_at := _diagnostics_cleared_at()
	return {
		"captured_at": _timestamp_iso(),
		"diagnostics": entries,
		"counts": {
			"bridge_log": log.size(),
			"returned": entries.size(),
		},
		"last_cleared_at": null if cleared_at == "" else cleared_at,
		"sources": ["bridge_log"],
		"native_output_supported": false,
		"native_debugger_supported": false,
	}


func notes_get(_params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_bridge_notes"):
		return _err("permission_denied", "Bridge notes permission is disabled in the Codex Bridge dock.")
	return _ok({
		"notes_path": BridgeLimits.NOTES_PATH,
		"notes": _read_bridge_notes(),
	})


func notes_append(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_bridge_notes"):
		return _err("permission_denied", "Bridge notes permission is disabled in the Codex Bridge dock.")
	var text := str(params.get("text", "")).strip_edges()
	if text == "":
		return _err("note_required", "notes_append requires non-empty text.")
	if text.length() > 4000:
		return _err("note_too_large", "notes_append text is limited to 4000 characters.")
	var notes := _read_bridge_notes()
	notes.append({
		"at": _timestamp_iso(),
		"author": str(params.get("author", "codex")),
		"text": text,
	})
	while notes.size() > BridgeLimits.MAX_BRIDGE_NOTES:
		notes.pop_front()
	var write_result := _write_bridge_notes(notes)
	if not write_result.get("ok", false):
		return write_result
	return _ok({
		"notes_path": BridgeLimits.NOTES_PATH,
		"notes_count": notes.size(),
		"latest": notes[notes.size() - 1],
	})


func notes_clear(_params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_bridge_notes"):
		return _err("permission_denied", "Bridge notes permission is disabled in the Codex Bridge dock.")
	var previous := _read_bridge_notes()
	var evidence_name := "notes_before_clear_" + _file_time() + ".json"
	var evidence_relative_path := ".godot/godot_codex_bridge/artifacts/" + evidence_name
	var evidence_path := _bridge_dir_abs().path_join("artifacts").path_join(evidence_name)
	var evidence_result := _write_json(evidence_path, {"notes": previous, "cleared_at": _timestamp_iso()})
	if not evidence_result.get("ok", false):
		return evidence_result
	var write_result := _write_bridge_notes([])
	if not write_result.get("ok", false):
		return write_result
	return _ok({
		"notes_path": BridgeLimits.NOTES_PATH,
		"cleared_count": previous.size(),
		"evidence_path": evidence_relative_path,
	})


func _read_bridge_notes() -> Array:
	if _notes_abs == "" or not FileAccess.file_exists(_notes_abs):
		return []
	var file := FileAccess.open(_notes_abs, FileAccess.READ)
	if file == null:
		return []
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_ARRAY:
		return parsed
	if typeof(parsed) == TYPE_DICTIONARY and (parsed as Dictionary).has("notes") and typeof((parsed as Dictionary).get("notes")) == TYPE_ARRAY:
		return (parsed as Dictionary).get("notes")
	return []


func _write_bridge_notes(notes: Array) -> Dictionary:
	var write_result := _write_json(_notes_abs, {
		"protocol_version": BridgeLimits.PROTOCOL_VERSION,
		"updated_at": _timestamp_iso(),
		"notes": notes,
	})
	if not write_result.get("ok", false):
		return write_result
	return {"ok": true}


func _bridge_log() -> Array:
	if _context != null:
		return _context.bridge_log
	return []


func _diagnostics_cleared_at() -> String:
	if _context != null:
		return _context.diagnostics_cleared_at
	return ""


func _bridge_dir_abs() -> String:
	if _context != null:
		return _context.bridge_dir_abs
	return ""


func _permission_enabled(key: String) -> bool:
	if _context != null:
		return _context.permission_enabled(key)
	return false


func _timestamp_iso() -> String:
	if _context != null:
		return _context.timestamp_iso()
	return Time.get_datetime_string_from_system(true, true)


func _file_time() -> String:
	if _context != null:
		return _context.file_time()
	return Time.get_datetime_string_from_system(true).replace("-", "").replace(":", "")


func _write_json(path: String, data: Dictionary) -> Dictionary:
	if _context != null:
		return _context.write_json(path, data)
	return _err("write_json_unavailable", "Bridge JSON writer is unavailable.")


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


func _error_payload(code: String, message: String) -> Dictionary:
	if _context != null:
		return _context.err(code, message)
	return {
		"code": code,
		"message": message,
	}
