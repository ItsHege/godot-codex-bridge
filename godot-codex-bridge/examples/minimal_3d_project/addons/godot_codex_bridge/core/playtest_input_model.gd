@tool
extends RefCounted

const BridgeContext := preload("bridge_context.gd")

const COMMAND_VERSION := "godot-codex-bridge/playtest-input-v1"
const DEFAULT_COMMAND_FILE := "runtime/input_commands.json"
const DEFAULT_SESSION_FILE := "runtime/playtest_session.json"
const DEFAULT_MAX_STEPS := 16
const DEFAULT_MAX_AGE_MS := 10000
const DEFAULT_MAX_BATCH_MS := 5000
const VALID_STEP_TYPES := [
	"action_press",
	"action_release",
	"axis",
	"key",
	"mouse_button",
]

var _context: BridgeContext
var _command_path_abs := ""
var _session_path_abs := ""
var _session_id := ""
var _session_token := ""
var _held_actions := {}


func _init(context: BridgeContext = null, command_path_abs := "", session_path_abs := "") -> void:
	_context = context
	_command_path_abs = command_path_abs
	_session_path_abs = session_path_abs


func held_actions() -> Array:
	var actions := _held_actions.keys()
	actions.sort()
	return actions


func start_bridge_session(scene_path := "") -> Dictionary:
	var now_unix_ms := int(Time.get_unix_time_from_system() * 1000.0)
	_session_id = "playtest_session_" + str(now_unix_ms) + "_" + str(randi() % 1000000)
	_session_token = _safe_command_id(_session_id + "_" + str(Time.get_ticks_usec()))
	var document := {
		"playtest_session_version": COMMAND_VERSION,
		"session_id": _session_id,
		"session_token": _session_token,
		"active": true,
		"scene_path": scene_path,
		"created_at": Time.get_datetime_string_from_system(true) + "Z",
		"created_unix_ms": now_unix_ms,
		"source": "godot_codex_bridge_editor_addon",
		"runtime_delivery": "runtime_state_probe_file_command",
	}
	var write_result := _write_session(document)
	if not bool(write_result.get("ok", false)):
		_session_id = ""
		_session_token = ""
		return write_result
	return _ok(document)


func clear_bridge_session(reason := "cleanup") -> Dictionary:
	var before := current_session_payload()
	var document := {
		"playtest_session_version": COMMAND_VERSION,
		"session_id": _session_id,
		"session_token": _session_token,
		"active": false,
		"closed_at": Time.get_datetime_string_from_system(true) + "Z",
		"reason": reason,
		"source": "godot_codex_bridge_editor_addon",
	}
	var write_result := _write_session(document)
	_session_id = ""
	_session_token = ""
	return _ok({
		"previous_session": before,
		"session_written": bool(write_result.get("ok", false)),
		"reason": reason,
	})


func current_session_payload() -> Dictionary:
	return {
		"session_id": _session_id,
		"session_token": _session_token,
		"session_active": _session_token != "",
		"session_path": _relative_session_path(),
		"session_absolute_path": _session_path_abs,
	}


func submit_input(params: Dictionary, play_session: Dictionary) -> Dictionary:
	if _context != null and not _context.permission_enabled("allow_playtest_input"):
		return _err("permission_denied", "Playtest input permission is disabled in the Codex Bridge dock.")
	if not bool(play_session.get("is_playing", false)):
		return _err("play_session_not_running", "Cannot inject playtest input because no Godot play session is running.")
	if not bool(play_session.get("bridge_owned", false)):
		return _err("play_session_not_bridge_owned", "Cannot inject playtest input because the active play session was not started by Godot Codex Bridge.")
	if _session_token == "":
		return _err("playtest_session_unavailable", "Cannot inject playtest input because the Bridge playtest session token is unavailable.")

	var command_params := params.duplicate(true)
	command_params["play_session_id"] = _session_id
	command_params["session_token"] = _session_token
	var command := build_command_document(command_params)
	if not bool(command.get("ok", false)):
		return command

	var document := command.get("data", {}) as Dictionary
	var write_result := _write_command(document)
	if not bool(write_result.get("ok", false)):
		return write_result

	var before := held_actions()
	_apply_local_held_state(document.get("steps", []) as Array)
	return _ok({
		"command_id": str(document.get("command_id", "")),
		"command_path": _relative_command_path(),
		"command_absolute_path": _command_path_abs,
		"step_count": (document.get("steps", []) as Array).size(),
		"held_actions_before": before,
		"held_actions_after": held_actions(),
		"runtime_delivery": "runtime_state_probe_file_command",
		"bridge_owned_play_session": true,
		"playtest_session_id": _session_id,
		"session_path": _relative_session_path(),
		"non_os_input": true,
	})


func release_all_held(reason := "cleanup") -> Dictionary:
	var before := held_actions()
	if before.is_empty():
		return _ok({
			"auto_released_actions": [],
			"held_actions_after": [],
			"command_written": false,
			"reason": reason,
		})
	var steps := []
	for action in before:
		steps.append({
			"type": "action_release",
			"action": action,
			"reason": reason,
		})
	var command := build_command_document({
		"steps": steps,
		"reason": reason,
		"play_session_id": _session_id,
		"session_token": _session_token,
	})
	if bool(command.get("ok", false)):
		_write_command(command.get("data", {}) as Dictionary)
	_held_actions.clear()
	return _ok({
		"auto_released_actions": before,
		"held_actions_after": held_actions(),
		"command_written": bool(command.get("ok", false)),
		"reason": reason,
	})


static func build_command_document(params: Dictionary, options: Dictionary = {}) -> Dictionary:
	var steps_result := _normalized_steps(params, int(options.get("max_steps", DEFAULT_MAX_STEPS)))
	if not bool(steps_result.get("ok", false)):
		return steps_result
	var now_unix_ms := int(Time.get_unix_time_from_system() * 1000.0)
	var max_age_ms := clampi(int(params.get("max_age_ms", params.get("maxAgeMs", DEFAULT_MAX_AGE_MS))), 1000, 60000)
	var max_batch_ms := clampi(int(params.get("max_batch_ms", params.get("maxBatchMs", DEFAULT_MAX_BATCH_MS))), 100, 30000)
	var command_id := _safe_command_id(str(params.get("command_id", params.get("commandId", ""))))
	if command_id == "":
		command_id = "playtest_input_" + str(now_unix_ms) + "_" + str(randi() % 1000000)
	return _ok_static({
		"playtest_input_version": COMMAND_VERSION,
		"command_id": command_id,
		"created_at": Time.get_datetime_string_from_system(true) + "Z",
		"created_unix_ms": now_unix_ms,
		"expires_unix_ms": now_unix_ms + max_age_ms,
		"max_batch_ms": max_batch_ms,
		"play_session_id": _safe_command_id(str(params.get("play_session_id", params.get("playSessionId", "")))),
		"session_token": _safe_command_id(str(params.get("session_token", params.get("sessionToken", "")))),
		"reason": str(params.get("reason", "playtest_input")),
		"source": "godot_codex_bridge_editor_addon",
		"delivery": "runtime_state_probe_file_command",
		"non_os_input": true,
		"steps": steps_result.get("steps", []),
	})


static func execute_runtime_document(document: Dictionary, processed_command_ids: Dictionary, held_actions_ref: Dictionary, options: Dictionary = {}) -> Dictionary:
	var command_id := str(document.get("command_id", "")).strip_edges()
	if command_id == "":
		return _runtime_result("failed", [], processed_command_ids, held_actions_ref, "missing_command_id", "Playtest input command is missing command_id.")
	if processed_command_ids.has(command_id):
		return _runtime_result("ignored", [], processed_command_ids, held_actions_ref, "", "")
	if str(document.get("playtest_input_version", "")) != COMMAND_VERSION:
		processed_command_ids[command_id] = true
		return _runtime_result("failed", [], processed_command_ids, held_actions_ref, "unsupported_playtest_input_version", "Unsupported playtest input command version.")
	var require_session_token := bool(options.get("require_session_token", false))
	var expected_session_token := _safe_command_id(str(options.get("session_token", options.get("sessionToken", ""))))
	var command_session_token := _safe_command_id(str(document.get("session_token", document.get("sessionToken", ""))))
	if require_session_token and expected_session_token == "":
		processed_command_ids[command_id] = true
		return _runtime_result("failed", [_runtime_event("playtest_input_failed", {"command_id": command_id, "code": "playtest_session_unavailable"})], processed_command_ids, held_actions_ref, "playtest_session_unavailable", "Runtime playtest session token is unavailable.")
	if expected_session_token != "" and command_session_token != expected_session_token:
		processed_command_ids[command_id] = true
		return _runtime_result("failed", [_runtime_event("playtest_input_failed", {"command_id": command_id, "code": "playtest_session_mismatch"})], processed_command_ids, held_actions_ref, "playtest_session_mismatch", "Playtest input command token does not match the active runtime session.")
	var now_unix_ms := int(Time.get_unix_time_from_system() * 1000.0)
	if int(document.get("expires_unix_ms", 0)) < now_unix_ms:
		processed_command_ids[command_id] = true
		return _runtime_result("expired", [{
			"type": "playtest_input_expired",
			"payload": {"command_id": command_id},
		}], processed_command_ids, held_actions_ref, "", "")
	var steps := document.get("steps", []) as Array
	var events := []
	var started_msec := Time.get_ticks_msec()
	var max_batch_ms := clampi(int(document.get("max_batch_ms", DEFAULT_MAX_BATCH_MS)), 100, 30000)
	for index in range(min(steps.size(), DEFAULT_MAX_STEPS)):
		if Time.get_ticks_msec() - started_msec > max_batch_ms:
			events.append(_runtime_event("playtest_input_batch_timeout", {
				"command_id": command_id,
				"processed_steps": index,
			}))
			break
		var step := steps[index] as Dictionary
		events.append(_execute_runtime_step(command_id, index, step, held_actions_ref))
	processed_command_ids[command_id] = true
	return _runtime_result("applied", events, processed_command_ids, held_actions_ref, "", "")


static func _execute_runtime_step(command_id: String, index: int, step: Dictionary, held_actions_ref: Dictionary) -> Dictionary:
	var step_type := str(step.get("type", "")).strip_edges()
	match step_type:
		"action_press":
			var press_action := str(step.get("action", "")).strip_edges()
			if press_action == "" or not InputMap.has_action(press_action):
				return _runtime_event("playtest_input_failed", {"command_id": command_id, "index": index, "code": "unknown_input_action", "action": press_action})
			var strength := clampf(float(step.get("strength", 1.0)), 0.0, 1.0)
			var press_event := InputEventAction.new()
			press_event.action = StringName(press_action)
			press_event.pressed = true
			press_event.strength = strength
			Input.parse_input_event(press_event)
			Input.action_press(StringName(press_action), strength)
			held_actions_ref[press_action] = true
			return _runtime_event("playtest_input_applied", {"command_id": command_id, "index": index, "type": step_type, "action": press_action, "strength": strength})
		"action_release":
			var release_action := str(step.get("action", "")).strip_edges()
			if release_action == "":
				return _runtime_event("playtest_input_failed", {"command_id": command_id, "index": index, "code": "input_action_required"})
			var release_event := InputEventAction.new()
			release_event.action = StringName(release_action)
			release_event.pressed = false
			Input.parse_input_event(release_event)
			if InputMap.has_action(release_action):
				Input.action_release(StringName(release_action))
			held_actions_ref.erase(release_action)
			return _runtime_event("playtest_input_applied", {"command_id": command_id, "index": index, "type": step_type, "action": release_action})
		"axis":
			var negative_action := str(step.get("negative_action", step.get("negativeAction", ""))).strip_edges()
			var positive_action := str(step.get("positive_action", step.get("positiveAction", ""))).strip_edges()
			if negative_action == "" or positive_action == "":
				return _runtime_event("playtest_input_failed", {"command_id": command_id, "index": index, "code": "axis_actions_required"})
			if not InputMap.has_action(negative_action) or not InputMap.has_action(positive_action):
				return _runtime_event("playtest_input_failed", {"command_id": command_id, "index": index, "code": "unknown_axis_action", "negative_action": negative_action, "positive_action": positive_action})
			var axis_value := clampf(float(step.get("value", 0.0)), -1.0, 1.0)
			_release_runtime_action(negative_action, held_actions_ref)
			_release_runtime_action(positive_action, held_actions_ref)
			if axis_value < 0.0:
				_press_runtime_action(negative_action, absf(axis_value), held_actions_ref)
			elif axis_value > 0.0:
				_press_runtime_action(positive_action, axis_value, held_actions_ref)
			return _runtime_event("playtest_input_applied", {"command_id": command_id, "index": index, "type": step_type, "negative_action": negative_action, "positive_action": positive_action, "value": axis_value})
		"key":
			var keycode := int(step.get("keycode", 0))
			if keycode <= 0:
				return _runtime_event("playtest_input_failed", {"command_id": command_id, "index": index, "code": "keycode_required"})
			var key_event := InputEventKey.new()
			key_event.keycode = keycode as Key
			key_event.physical_keycode = int(step.get("physical_keycode", step.get("physicalKeycode", keycode))) as Key
			key_event.pressed = bool(step.get("pressed", true))
			Input.parse_input_event(key_event)
			return _runtime_event("playtest_input_applied", {"command_id": command_id, "index": index, "type": step_type, "keycode": keycode, "pressed": key_event.pressed})
		"mouse_button":
			var button_index := int(step.get("button_index", step.get("buttonIndex", 0)))
			if button_index <= 0:
				return _runtime_event("playtest_input_failed", {"command_id": command_id, "index": index, "code": "mouse_button_required"})
			var position := _vector2_from_value(step.get("position", {}))
			var mouse_event := InputEventMouseButton.new()
			mouse_event.button_index = button_index as MouseButton
			mouse_event.pressed = bool(step.get("pressed", true))
			mouse_event.position = position
			mouse_event.global_position = position
			Input.parse_input_event(mouse_event)
			return _runtime_event("playtest_input_applied", {"command_id": command_id, "index": index, "type": step_type, "button_index": button_index, "pressed": mouse_event.pressed, "position": {"x": position.x, "y": position.y}})
		_:
			return _runtime_event("playtest_input_failed", {"command_id": command_id, "index": index, "code": "unsupported_step_type", "type": step_type})


static func _normalized_steps(params: Dictionary, max_steps: int) -> Dictionary:
	var raw_steps: Variant = params.get("steps", [])
	var steps: Array = []
	if typeof(raw_steps) == TYPE_ARRAY and not (raw_steps as Array).is_empty():
		steps = raw_steps as Array
	else:
		var shortcut := {
			"type": str(params.get("type", params.get("actionType", ""))),
			"action": str(params.get("action", "")),
			"negative_action": str(params.get("negative_action", params.get("negativeAction", ""))),
			"positive_action": str(params.get("positive_action", params.get("positiveAction", ""))),
			"value": params.get("value", 0.0),
			"strength": params.get("strength", 1.0),
			"keycode": params.get("keycode", 0),
			"physical_keycode": params.get("physical_keycode", params.get("physicalKeycode", 0)),
			"button_index": params.get("button_index", params.get("buttonIndex", 0)),
			"pressed": params.get("pressed", true),
			"position": params.get("position", {}),
		}
		if str(shortcut.get("type", "")).strip_edges() != "":
			steps = [shortcut]
	if steps.is_empty():
		return _err_static("invalid_playtest_input", "Playtest input requires steps or a shortcut type/action.")
	if steps.size() > max_steps:
		return _err_static("too_many_playtest_input_steps", "Playtest input supports at most " + str(max_steps) + " steps.")
	var normalized := []
	for index in range(steps.size()):
		if typeof(steps[index]) != TYPE_DICTIONARY:
			return _err_static("invalid_playtest_input_step", "Playtest input step " + str(index) + " must be an object.")
		var step := steps[index] as Dictionary
		var step_type := str(step.get("type", "")).strip_edges()
		if not VALID_STEP_TYPES.has(step_type):
			return _err_static("unsupported_playtest_input_step", "Unsupported playtest input step type: " + step_type)
		var entry := {"type": step_type}
		match step_type:
			"action_press", "action_release":
				var action := str(step.get("action", "")).strip_edges()
				if action == "":
					return _err_static("input_action_required", "Playtest action steps require action.")
				entry["action"] = action
				if step_type == "action_press":
					entry["strength"] = clampf(float(step.get("strength", 1.0)), 0.0, 1.0)
			"axis":
				var negative_action := str(step.get("negative_action", step.get("negativeAction", ""))).strip_edges()
				var positive_action := str(step.get("positive_action", step.get("positiveAction", ""))).strip_edges()
				if negative_action == "" or positive_action == "":
					return _err_static("axis_actions_required", "Playtest axis steps require negative_action and positive_action.")
				entry["negative_action"] = negative_action
				entry["positive_action"] = positive_action
				entry["value"] = clampf(float(step.get("value", 0.0)), -1.0, 1.0)
			"key":
				entry["keycode"] = int(step.get("keycode", 0))
				entry["physical_keycode"] = int(step.get("physical_keycode", step.get("physicalKeycode", step.get("keycode", 0))))
				entry["pressed"] = bool(step.get("pressed", true))
			"mouse_button":
				entry["button_index"] = int(step.get("button_index", step.get("buttonIndex", 0)))
				entry["pressed"] = bool(step.get("pressed", true))
				entry["position"] = _position_payload(_vector2_from_value(step.get("position", {})))
		normalized.append(entry)
	return {"ok": true, "steps": normalized}


func _write_command(document: Dictionary) -> Dictionary:
	if _command_path_abs == "":
		return _err("playtest_input_path_unavailable", "Playtest input command path is unavailable.")
	if _context != null:
		_context.ensure_dirs()
		var dir_result := DirAccess.make_dir_recursive_absolute(_command_path_abs.get_base_dir())
		if dir_result != OK:
			return _err("playtest_input_dir_failed", "Failed to create playtest input command directory.", {"godot_error": dir_result})
		var write_result := _context.write_json(_command_path_abs, document)
		if bool(write_result.get("ok", false)):
			return write_result
		return write_result
	var file := FileAccess.open(_command_path_abs, FileAccess.WRITE)
	if file == null:
		return _err("playtest_input_write_failed", "Failed to write playtest input command file.")
	file.store_string(JSON.stringify(document, "\t"))
	file.store_string("\n")
	file.close()
	return _ok({"path": _command_path_abs})


func _write_session(document: Dictionary) -> Dictionary:
	if _session_path_abs == "":
		return _err("playtest_session_path_unavailable", "Playtest input session path is unavailable.")
	if _context != null:
		_context.ensure_dirs()
		var dir_result := DirAccess.make_dir_recursive_absolute(_session_path_abs.get_base_dir())
		if dir_result != OK:
			return _err("playtest_session_dir_failed", "Failed to create playtest input session directory.", {"godot_error": dir_result})
		return _context.write_json(_session_path_abs, document)
	var file := FileAccess.open(_session_path_abs, FileAccess.WRITE)
	if file == null:
		return _err("playtest_session_write_failed", "Failed to write playtest input session file.")
	file.store_string(JSON.stringify(document, "\t"))
	file.store_string("\n")
	file.close()
	return _ok({"path": _session_path_abs})


func _apply_local_held_state(steps: Array) -> void:
	for raw_step in steps:
		var step := raw_step as Dictionary
		var step_type := str(step.get("type", ""))
		var action := str(step.get("action", "")).strip_edges()
		if action == "":
			if step_type == "axis":
				var negative_action := str(step.get("negative_action", "")).strip_edges()
				var positive_action := str(step.get("positive_action", "")).strip_edges()
				var axis_value := float(step.get("value", 0.0))
				_held_actions.erase(negative_action)
				_held_actions.erase(positive_action)
				if axis_value < 0.0 and negative_action != "":
					_held_actions[negative_action] = true
				elif axis_value > 0.0 and positive_action != "":
					_held_actions[positive_action] = true
			continue
		if step_type == "action_press":
			_held_actions[action] = true
		elif step_type == "action_release":
			_held_actions.erase(action)


func _relative_command_path() -> String:
	return ".godot/godot_codex_bridge/" + DEFAULT_COMMAND_FILE


func _relative_session_path() -> String:
	return ".godot/godot_codex_bridge/" + DEFAULT_SESSION_FILE


func _ok(data: Dictionary) -> Dictionary:
	return _ok_static(data)


func _err(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	if _context != null:
		return {"ok": false, "error": _context.err(code, message, details)}
	return _err_static(code, message, details)


static func _ok_static(data: Dictionary) -> Dictionary:
	return {"ok": true, "data": data}


static func _err_static(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	var error := {"code": code, "message": message}
	if not details.is_empty():
		error["details"] = details
	return {"ok": false, "error": error}


static func _runtime_result(status: String, events: Array, processed_command_ids: Dictionary, held_actions_ref: Dictionary, code: String, message: String) -> Dictionary:
	var result := {
		"status": status,
		"events": events,
		"processed_command_ids": processed_command_ids,
		"held_actions": held_actions_ref,
	}
	if code != "":
		result["error"] = {"code": code, "message": message}
	return result


static func _runtime_event(event_type: String, payload: Dictionary) -> Dictionary:
	return {"type": event_type, "payload": payload}


static func _press_runtime_action(action: String, strength: float, held_actions_ref: Dictionary) -> void:
	var event := InputEventAction.new()
	event.action = StringName(action)
	event.pressed = true
	event.strength = clampf(strength, 0.0, 1.0)
	Input.parse_input_event(event)
	Input.action_press(StringName(action), event.strength)
	held_actions_ref[action] = true


static func _release_runtime_action(action: String, held_actions_ref: Dictionary) -> void:
	var event := InputEventAction.new()
	event.action = StringName(action)
	event.pressed = false
	Input.parse_input_event(event)
	if InputMap.has_action(action):
		Input.action_release(StringName(action))
	held_actions_ref.erase(action)


static func _safe_command_id(value: String) -> String:
	var cleaned := value.strip_edges()
	if cleaned == "":
		return ""
	var result := ""
	for index in range(cleaned.length()):
		var ch := cleaned.substr(index, 1)
		var code := cleaned.unicode_at(index)
		var is_ascii_letter := (code >= 65 and code <= 90) or (code >= 97 and code <= 122)
		var is_ascii_digit := code >= 48 and code <= 57
		if is_ascii_letter or is_ascii_digit or ch == "_" or ch == "-" or ch == ".":
			result += ch
	if result.length() > 96:
		result = result.substr(0, 96)
	return result


static func _vector2_from_value(value: Variant) -> Vector2:
	if value is Vector2:
		return value as Vector2
	if typeof(value) == TYPE_DICTIONARY:
		var dict := value as Dictionary
		return Vector2(float(dict.get("x", 0.0)), float(dict.get("y", 0.0)))
	return Vector2.ZERO


static func _position_payload(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}
