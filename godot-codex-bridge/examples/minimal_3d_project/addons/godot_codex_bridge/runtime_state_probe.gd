extends Node

const RuntimeStateModel := preload("res://addons/godot_codex_bridge/core/runtime_state_model.gd")
const RuntimeEventsModel := preload("res://addons/godot_codex_bridge/core/runtime_events_model.gd")
const PlaytestInputModel := preload("res://addons/godot_codex_bridge/core/playtest_input_model.gd")

@export var enabled := true
@export_range(0.25, 10.0, 0.25) var write_interval_seconds := 1.0
@export_range(10, 500, 1) var max_nodes := 120
@export_range(1, 12, 1) var max_depth := 7
@export_range(10, 2000, 10) var max_events := 200

var _elapsed := 0.0
var _state_path := ""
var _events_path := ""
var _input_commands_path := ""
var _input_session_path := ""
var _events: Array = []
var _last_scene_path := ""
var _last_action_pressed := {}
var _processed_input_command_ids := {}
var _playtest_held_actions := {}


func _ready() -> void:
	_state_path = ProjectSettings.globalize_path("res://.godot/godot_codex_bridge/runtime/state.json")
	_events_path = ProjectSettings.globalize_path("res://.godot/godot_codex_bridge/runtime/events.json")
	_input_commands_path = ProjectSettings.globalize_path("res://.godot/godot_codex_bridge/runtime/input_commands.json")
	_input_session_path = ProjectSettings.globalize_path("res://.godot/godot_codex_bridge/runtime/playtest_session.json")
	_connect_tree_signals()
	_record_event("probe_ready", {
		"node_path": str(get_path()) if is_inside_tree() else str(name),
	})
	_write_state("ready")


func _process(delta: float) -> void:
	if not enabled:
		return
	_consume_playtest_input_commands()
	_elapsed += delta
	if _elapsed < write_interval_seconds:
		return
	_elapsed = 0.0
	_write_state("interval")


func write_now(reason := "manual") -> Dictionary:
	return _write_state(reason)


func record_event(event_type: String, payload: Dictionary = {}) -> Dictionary:
	return _record_event(event_type, payload)


func _consume_playtest_input_commands() -> void:
	if _input_commands_path == "" or not FileAccess.file_exists(_input_commands_path):
		return
	var file := FileAccess.open(_input_commands_path, FileAccess.READ)
	if file == null:
		_record_event("playtest_input_failed", {
			"code": "playtest_input_read_failed",
			"path": _input_commands_path,
			"godot_error": FileAccess.get_open_error(),
		})
		return
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_record_event("playtest_input_failed", {
			"code": "playtest_input_json_invalid",
			"path": _input_commands_path,
		})
		return
	var session := _read_playtest_session()
	var result := PlaytestInputModel.execute_runtime_document(parsed as Dictionary, _processed_input_command_ids, _playtest_held_actions, {
		"require_session_token": true,
		"session_token": str(session.get("session_token", "")) if bool(session.get("active", false)) else "",
	})
	_processed_input_command_ids = result.get("processed_command_ids", {}) as Dictionary
	_playtest_held_actions = result.get("held_actions", {}) as Dictionary
	for event in result.get("events", []) as Array:
		var event_dict := event as Dictionary
		_record_event(str(event_dict.get("type", "")), event_dict.get("payload", {}) as Dictionary)
	if str(result.get("status", "")) == "applied":
		_write_state("playtest_input")


func _read_playtest_session() -> Dictionary:
	if _input_session_path == "" or not FileAccess.file_exists(_input_session_path):
		return {}
	var file := FileAccess.open(_input_session_path, FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary


func _write_state(reason: String) -> Dictionary:
	var dir_path := _state_path.get_base_dir()
	var dir_result := DirAccess.make_dir_recursive_absolute(dir_path)
	if dir_result != OK:
		return {
			"ok": false,
			"error": {
				"code": "runtime_state_dir_failed",
				"message": "Failed to create runtime state directory.",
				"godot_error": dir_result,
				"path": dir_path,
			},
		}

	var state := RuntimeStateModel.collect_state(get_tree(), {
		"reason": reason,
		"max_nodes": max_nodes,
		"max_depth": max_depth,
	})
	_record_state_transition_events(state)
	var file := FileAccess.open(_state_path, FileAccess.WRITE)
	if file == null:
		return {
			"ok": false,
			"error": {
				"code": "runtime_state_write_failed",
				"message": "Failed to open runtime state file for writing.",
				"godot_error": FileAccess.get_open_error(),
				"path": _state_path,
			},
		}
	file.store_string(JSON.stringify(state, "\t"))
	file.store_string("\n")
	file.close()
	var events_result := _write_events("state:" + reason)
	return {
		"ok": true,
		"path": _state_path,
		"events_path": _events_path,
		"event_count": int(events_result.get("event_count", _events.size())),
		"node_count_sampled": int((state.get("tree", {}) as Dictionary).get("node_count_sampled", 0)),
		"truncated": bool((state.get("tree", {}) as Dictionary).get("truncated", false)),
	}


func _connect_tree_signals() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var node_added_callable := Callable(self, "_on_tree_node_added")
	var node_removed_callable := Callable(self, "_on_tree_node_removed")
	if not tree.node_added.is_connected(node_added_callable):
		tree.node_added.connect(node_added_callable)
	if not tree.node_removed.is_connected(node_removed_callable):
		tree.node_removed.connect(node_removed_callable)


func _on_tree_node_added(node: Node) -> void:
	_record_event("node_added", RuntimeEventsModel.node_event_payload(node))


func _on_tree_node_removed(node: Node) -> void:
	_record_event("node_removed", RuntimeEventsModel.node_event_payload(node))


func _record_state_transition_events(state: Dictionary) -> void:
	var tree_state := state.get("tree", {}) as Dictionary
	var current_scene_path := str(tree_state.get("current_scene", ""))
	var scene_event := RuntimeEventsModel.scene_change_event(
		_last_scene_path,
		current_scene_path,
		tree_state.get("active_scene", {}) as Dictionary
	)
	if not scene_event.is_empty():
		_record_event(str(scene_event.get("type", "scene_changed")), scene_event.get("payload", {}) as Dictionary)
	_last_scene_path = current_scene_path

	var input_result := RuntimeEventsModel.input_transition_events(_last_action_pressed, state.get("input", {}) as Dictionary)
	_last_action_pressed = input_result.get("pressed", {}) as Dictionary
	for event in input_result.get("events", []) as Array:
		var event_dict := event as Dictionary
		_record_event(str(event_dict.get("type", "")), event_dict.get("payload", {}) as Dictionary)


func _record_event(event_type: String, payload: Dictionary = {}) -> Dictionary:
	if event_type.strip_edges() == "":
		return {"ok": false, "error": {"code": "runtime_event_type_required"}}
	var result := RuntimeEventsModel.append_event(_events, event_type, payload, {
		"max_events": max_events,
	})
	_events = result.get("events", []) as Array
	var write_result := _write_events("event:" + event_type)
	return {
		"ok": bool(write_result.get("ok", false)),
		"event": result.get("event", {}),
		"event_count": _events.size(),
		"path": _events_path,
	}


func _write_events(reason: String) -> Dictionary:
	var dir_path := _events_path.get_base_dir()
	var dir_result := DirAccess.make_dir_recursive_absolute(dir_path)
	if dir_result != OK:
		return {
			"ok": false,
			"error": {
				"code": "runtime_events_dir_failed",
				"message": "Failed to create runtime events directory.",
				"godot_error": dir_result,
				"path": dir_path,
			},
		}
	var document := RuntimeEventsModel.build_document(_events, {
		"max_events": max_events,
		"source": "res://addons/godot_codex_bridge/runtime_state_probe.gd",
		"reason": reason,
	})
	var file := FileAccess.open(_events_path, FileAccess.WRITE)
	if file == null:
		return {
			"ok": false,
			"error": {
				"code": "runtime_events_write_failed",
				"message": "Failed to open runtime events file for writing.",
				"godot_error": FileAccess.get_open_error(),
				"path": _events_path,
			},
		}
	file.store_string(JSON.stringify(document, "\t"))
	file.store_string("\n")
	file.close()
	return {
		"ok": true,
		"path": _events_path,
		"event_count": int(document.get("event_count", 0)),
	}
