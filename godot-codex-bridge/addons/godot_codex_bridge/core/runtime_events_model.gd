@tool
extends RefCounted

const EVENTS_VERSION := "godot-codex-bridge/runtime-events-v1"
const DEFAULT_MAX_EVENTS := 200
const DEFAULT_MAX_PAYLOAD_CHARS := 2000


static func append_event(current_events: Array, event_type: String, payload: Dictionary = {}, options: Dictionary = {}) -> Dictionary:
	var max_events := clampi(int(options.get("max_events", DEFAULT_MAX_EVENTS)), 1, 2000)
	var now := str(options.get("generated_at", Time.get_datetime_string_from_system(true) + "Z"))
	var event := {
		"id": str(options.get("id", now + ":" + event_type)),
		"at": now,
		"type": _truncate_text(event_type, 120),
		"payload": _sanitize_payload(payload, int(options.get("max_payload_chars", DEFAULT_MAX_PAYLOAD_CHARS))),
	}
	var events := current_events.duplicate(true)
	events.append(event)
	var truncated := false
	while events.size() > max_events:
		events.pop_front()
		truncated = true
	return {
		"events": events,
		"event": event,
		"truncated": truncated,
	}


static func build_document(events: Array, options: Dictionary = {}) -> Dictionary:
	var max_events := clampi(int(options.get("max_events", DEFAULT_MAX_EVENTS)), 1, 2000)
	var trimmed := events.duplicate(true)
	var truncated := false
	while trimmed.size() > max_events:
		trimmed.pop_front()
		truncated = true
	return {
		"runtime_events_version": EVENTS_VERSION,
		"generated_at": str(options.get("generated_at", Time.get_datetime_string_from_system(true) + "Z")),
		"source": str(options.get("source", "res://addons/godot_codex_bridge/runtime_state_probe.gd")),
		"event_count": trimmed.size(),
		"max_events": max_events,
		"truncated": truncated or bool(options.get("truncated", false)),
		"events": trimmed,
		"observability": {
			"level": "opt_in_runtime_probe",
			"arbitrary_script_execution": false,
			"scene_mutation": false,
			"scene_save": false,
			"input_injection": "gated_playtest_commands_only",
		},
		"privacy": {
			"classification": "local_sensitive_runtime_evidence",
			"external_upload_allowed": false,
		},
	}


static func input_transition_events(previous_pressed: Dictionary, input_state: Dictionary) -> Dictionary:
	var next_pressed := {}
	var events := []
	for action in input_state.get("action_states", []) as Array:
		var action_state := action as Dictionary
		var name := str(action_state.get("name", ""))
		if name == "":
			continue
		var pressed := bool(action_state.get("pressed", false))
		next_pressed[name] = pressed
		var was_pressed := bool(previous_pressed.get(name, false))
		if pressed and not was_pressed:
			events.append({
				"type": "input_action_pressed",
				"payload": {
					"name": name,
					"strength": float(action_state.get("strength", 0.0)),
				},
			})
		elif was_pressed and not pressed:
			events.append({
				"type": "input_action_released",
				"payload": {
					"name": name,
					"strength": float(action_state.get("strength", 0.0)),
				},
			})
	for previous_name in previous_pressed.keys():
		if next_pressed.has(previous_name) or not bool(previous_pressed.get(previous_name, false)):
			continue
		events.append({
			"type": "input_action_released",
			"payload": {
				"name": str(previous_name),
				"strength": 0.0,
			},
		})
	return {
		"pressed": next_pressed,
		"events": events,
	}


static func scene_change_event(previous_scene_path: String, current_scene_path: String, active_scene: Dictionary) -> Dictionary:
	if previous_scene_path == current_scene_path:
		return {}
	return {
		"type": "scene_changed",
		"payload": {
			"previous_scene": previous_scene_path,
			"current_scene": current_scene_path,
			"active_scene": active_scene,
		},
	}


static func node_event_payload(node: Node) -> Dictionary:
	if node == null:
		return {}
	var payload := {
		"path": _node_path_or_empty(node),
		"name": str(node.name),
		"type": node.get_class(),
		"scene_file_path": _res_path_or_empty(node.scene_file_path),
	}
	if node is Node2D:
		var node_2d := node as Node2D
		var position_2d := node_2d.global_position if node_2d.is_inside_tree() else node_2d.position
		payload["dimension"] = "2d"
		payload["global_position"] = {
			"x": position_2d.x,
			"y": position_2d.y,
		}
	elif node is Node3D:
		var node_3d := node as Node3D
		var position_3d := node_3d.global_position if node_3d.is_inside_tree() else node_3d.position
		payload["dimension"] = "3d"
		payload["global_position"] = {
			"x": position_3d.x,
			"y": position_3d.y,
			"z": position_3d.z,
		}
	return payload


static func _sanitize_payload(payload: Dictionary, max_chars: int) -> Dictionary:
	var sanitized := {}
	for key in payload.keys():
		var key_text := _truncate_text(str(key), 120)
		sanitized[key_text] = _sanitize_value(payload.get(key), max_chars, 0)
	return sanitized


static func _sanitize_value(value: Variant, max_chars: int, depth: int) -> Variant:
	if depth >= 4:
		return "[truncated:max_depth]"
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT:
			return value
		TYPE_STRING, TYPE_STRING_NAME, TYPE_NODE_PATH:
			return _truncate_text(str(value), max_chars)
		TYPE_VECTOR2:
			var vector_2 := value as Vector2
			return {"x": vector_2.x, "y": vector_2.y}
		TYPE_VECTOR3:
			var vector_3 := value as Vector3
			return {"x": vector_3.x, "y": vector_3.y, "z": vector_3.z}
		TYPE_DICTIONARY:
			var result := {}
			var count := 0
			for key in (value as Dictionary).keys():
				if count >= 40:
					result["__truncated_keys"] = (value as Dictionary).size() - count
					break
				result[_truncate_text(str(key), 120)] = _sanitize_value((value as Dictionary).get(key), max_chars, depth + 1)
				count += 1
			return result
		TYPE_ARRAY:
			var result_array := []
			var array := value as Array
			for index in range(min(array.size(), 40)):
				result_array.append(_sanitize_value(array[index], max_chars, depth + 1))
			if array.size() > 40:
				result_array.append("[truncated:%d_items]" % (array.size() - 40))
			return result_array
		_:
			return _truncate_text(str(value), max_chars)


static func _truncate_text(value: String, limit: int) -> String:
	if limit <= 0:
		return ""
	if value.length() <= limit:
		return value
	return value.substr(0, max(0, limit - 3)) + "..."


static func _res_path_or_empty(value: String) -> String:
	if value.begins_with("res://"):
		return value
	return ""


static func _node_path_or_empty(node: Node) -> String:
	if node == null:
		return ""
	if not node.is_inside_tree():
		return str(node.name)
	return str(node.get_path())
