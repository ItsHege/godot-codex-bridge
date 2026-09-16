@tool
extends RefCounted

const DEFAULT_MAX_NODES := 80
const DEFAULT_MAX_DEPTH := 6
const DEFAULT_MAX_GROUPS := 8
const DEFAULT_MAX_INPUT_ACTIONS := 80
const DEFAULT_MAX_KEY_POSITIONS := 40
const DEFAULT_MAX_AUTOLOADS := 40
const SCHEMA_VERSION := "godot-codex-bridge/runtime-state-v1"


static func collect_state(tree: SceneTree, options: Dictionary = {}) -> Dictionary:
	var now := Time.get_datetime_string_from_system(true) + "Z"
	var max_nodes := int(options.get("max_nodes", DEFAULT_MAX_NODES))
	var max_depth := int(options.get("max_depth", DEFAULT_MAX_DEPTH))
	var root := tree.current_scene
	if root == null:
		root = tree.root
	var budget := {
		"count": 0,
		"truncated": false,
		"type_counts": {},
		"key_positions": [],
		"max_key_positions": clampi(int(options.get("max_key_positions", DEFAULT_MAX_KEY_POSITIONS)), 1, 200),
	}
	var nodes := []
	if root != null:
		nodes = _collect_nodes(root, 0, max_depth, max_nodes, budget)
	var autoloads := _collect_autoloads(tree, options)
	var input := _collect_input(options)
	var tree_payload := {
		"current_scene": _node_path_or_empty(tree.current_scene),
		"active_scene": _active_scene_summary(tree.current_scene),
		"root": _node_path_or_empty(root),
		"paused": tree.paused,
		"node_count_sampled": int(budget.get("count", 0)),
		"node_type_counts": budget.get("type_counts", {}),
		"key_positions": budget.get("key_positions", []),
		"truncated": bool(budget.get("truncated", false)),
		"max_nodes": max_nodes,
		"max_depth": max_depth,
		"nodes": nodes,
	}
	tree_payload["summary"] = _tree_summary(tree_payload, autoloads)
	return {
		"runtime_state_version": SCHEMA_VERSION,
		"generated_at": now,
		"reason": str(options.get("reason", "runtime_probe")),
		"project": {
			"name": str(ProjectSettings.get_setting("application/config/name", "")),
			"main_scene": str(ProjectSettings.get_setting("application/run/main_scene", "")),
		},
		"tree": tree_payload,
		"autoloads": autoloads,
		"runtime": _collect_runtime(tree),
		"input": input,
		"metrics": _collect_metrics(),
		"observability": {
			"level": "opt_in_runtime_probe",
			"writer": "res://addons/godot_codex_bridge/runtime_state_probe.gd",
			"arbitrary_script_execution": false,
			"scene_mutation": false,
			"scene_save": false,
		},
		"privacy": {
			"classification": "local_sensitive_runtime_evidence",
			"external_upload_allowed": false,
		},
	}


static func _tree_summary(tree_payload: Dictionary, autoloads: Dictionary) -> Dictionary:
	var active_scene := tree_payload.get("active_scene", {}) as Dictionary
	return {
		"active_scene_name": str(active_scene.get("name", "")),
		"active_scene_type": str(active_scene.get("type", "")),
		"active_scene_path": str(active_scene.get("path", "")),
		"current_scene": str(tree_payload.get("current_scene", "")),
		"node_count_sampled": int(tree_payload.get("node_count_sampled", 0)),
		"top_node_types": _top_node_types(tree_payload.get("node_type_counts", {}) as Dictionary),
		"key_position_count": (tree_payload.get("key_positions", []) as Array).size(),
		"autoload_count": int(autoloads.get("total", 0)),
		"truncated": bool(tree_payload.get("truncated", false)),
	}


static func _top_node_types(type_counts: Dictionary, limit := 8) -> Array:
	var names := type_counts.keys()
	names.sort()
	var result := []
	for name in names:
		if result.size() >= limit:
			break
		result.append({
			"type": str(name),
			"count": int(type_counts.get(name, 0)),
		})
	return result


static func _collect_nodes(node: Node, depth: int, max_depth: int, max_nodes: int, budget: Dictionary) -> Array:
	if int(budget.get("count", 0)) >= max_nodes:
		budget["truncated"] = true
		return []
	if depth > max_depth:
		budget["truncated"] = true
		return []

	budget["count"] = int(budget.get("count", 0)) + 1
	_count_node_type(node, budget)
	var entry := _node_summary(node, depth)
	_record_key_position(entry, budget)
	var children := []
	var omitted_child_count := 0
	if depth >= max_depth and node.get_child_count() > 0:
		budget["truncated"] = true
		entry["children_truncated"] = true
		entry["omitted_child_count"] = node.get_child_count()
		entry["children"] = children
		return [entry]
	var child_index := 0
	for child in node.get_children():
		if int(budget.get("count", 0)) >= max_nodes:
			budget["truncated"] = true
			omitted_child_count += node.get_child_count() - child_index
			break
		var child_nodes := _collect_nodes(child, depth + 1, max_depth, max_nodes, budget)
		if child_nodes.is_empty():
			omitted_child_count += 1
		for child_entry in child_nodes:
			children.append(child_entry)
		child_index += 1
	if omitted_child_count > 0:
		entry["children_truncated"] = true
		entry["omitted_child_count"] = omitted_child_count
	entry["children"] = children
	return [entry]


static func _active_scene_summary(scene: Node) -> Dictionary:
	if scene == null:
		return {}
	return {
		"path": _node_path_or_empty(scene),
		"name": scene.name,
		"type": scene.get_class(),
		"scene_file_path": _res_path_or_empty(scene.scene_file_path),
		"script_path": _script_path_or_empty(scene),
		"child_count": scene.get_child_count(),
	}


static func _node_summary(node: Node, depth: int) -> Dictionary:
	var summary := {
		"path": _node_path_or_empty(node),
		"name": node.name,
		"type": node.get_class(),
		"depth": depth,
		"child_count": node.get_child_count(),
		"scene_file_path": _res_path_or_empty(node.scene_file_path),
		"script_path": _script_path_or_empty(node),
		"groups": _bounded_groups(node),
		"process": {
			"idle": node.is_processing(),
			"physics": node.is_physics_processing(),
		},
	}
	if node is CanvasItem:
		var canvas_item := node as CanvasItem
		summary["visibility"] = {
			"visible": canvas_item.visible,
			"visible_in_tree": canvas_item.is_visible_in_tree(),
		}
	if node is Node2D:
		var node_2d := node as Node2D
		var global_position_2d := node_2d.global_position if node_2d.is_inside_tree() else node_2d.position
		var global_rotation_degrees_2d := node_2d.global_rotation_degrees if node_2d.is_inside_tree() else node_2d.rotation_degrees
		var global_scale_2d := node_2d.global_scale if node_2d.is_inside_tree() else node_2d.scale
		summary["transform_2d"] = {
			"position": {"x": node_2d.position.x, "y": node_2d.position.y},
			"rotation": node_2d.rotation,
			"scale": {"x": node_2d.scale.x, "y": node_2d.scale.y},
			"global": {
				"position": {"x": global_position_2d.x, "y": global_position_2d.y},
				"rotation_degrees": global_rotation_degrees_2d,
				"scale": {"x": global_scale_2d.x, "y": global_scale_2d.y},
			},
		}
	if node is Node3D:
		var node_3d := node as Node3D
		var global_position_3d := node_3d.global_position if node_3d.is_inside_tree() else node_3d.position
		var global_rotation_degrees_3d := node_3d.global_rotation_degrees if node_3d.is_inside_tree() else node_3d.rotation_degrees
		var global_scale_3d := node_3d.global_basis.get_scale() if node_3d.is_inside_tree() else node_3d.scale
		summary["visibility"] = {
			"visible": node_3d.visible,
			"visible_in_tree": node_3d.is_visible_in_tree(),
		}
		summary["transform_3d"] = {
			"position": {"x": node_3d.position.x, "y": node_3d.position.y, "z": node_3d.position.z},
			"rotation": {"x": node_3d.rotation.x, "y": node_3d.rotation.y, "z": node_3d.rotation.z},
			"scale": {"x": node_3d.scale.x, "y": node_3d.scale.y, "z": node_3d.scale.z},
			"global": {
				"position": {"x": global_position_3d.x, "y": global_position_3d.y, "z": global_position_3d.z},
				"rotation_degrees": {"x": global_rotation_degrees_3d.x, "y": global_rotation_degrees_3d.y, "z": global_rotation_degrees_3d.z},
				"scale": {"x": global_scale_3d.x, "y": global_scale_3d.y, "z": global_scale_3d.z},
			},
		}
	var type_state := _typed_node_state(node)
	if not type_state.is_empty():
		summary["state"] = type_state
	return summary


static func _record_key_position(entry: Dictionary, budget: Dictionary) -> void:
	var key_positions := budget.get("key_positions", []) as Array
	var max_key_positions := int(budget.get("max_key_positions", DEFAULT_MAX_KEY_POSITIONS))
	if key_positions.size() >= max_key_positions:
		return
	if entry.has("transform_3d"):
		var transform_3d := entry.get("transform_3d", {}) as Dictionary
		key_positions.append({
			"path": str(entry.get("path", "")),
			"name": str(entry.get("name", "")),
			"type": str(entry.get("type", "")),
			"dimension": "3d",
			"position": transform_3d.get("position", {}),
			"global_position": (transform_3d.get("global", {}) as Dictionary).get("position", {}),
		})
	elif entry.has("transform_2d"):
		var transform_2d := entry.get("transform_2d", {}) as Dictionary
		key_positions.append({
			"path": str(entry.get("path", "")),
			"name": str(entry.get("name", "")),
			"type": str(entry.get("type", "")),
			"dimension": "2d",
			"position": transform_2d.get("position", {}),
			"global_position": (transform_2d.get("global", {}) as Dictionary).get("position", {}),
		})
	budget["key_positions"] = key_positions


static func _bounded_groups(node: Node) -> Array:
	var groups := []
	for group in node.get_groups():
		if groups.size() >= DEFAULT_MAX_GROUPS:
			break
		groups.append(str(group))
	return groups


static func _count_node_type(node: Node, budget: Dictionary) -> void:
	var type_counts := budget.get("type_counts", {}) as Dictionary
	var type_name := node.get_class()
	type_counts[type_name] = int(type_counts.get(type_name, 0)) + 1
	budget["type_counts"] = type_counts


static func _collect_metrics() -> Dictionary:
	return {
		"frames_per_second": Performance.get_monitor(Performance.TIME_FPS),
		"process_time": Performance.get_monitor(Performance.TIME_PROCESS),
		"physics_process_time": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS),
		"object_count": Performance.get_monitor(Performance.OBJECT_COUNT),
		"node_count": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphan_node_count": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
	}


static func _collect_runtime(tree: SceneTree) -> Dictionary:
	return {
		"paused": tree.paused,
		"time_scale": Engine.time_scale,
		"physics_ticks_per_second": Engine.physics_ticks_per_second,
		"max_fps": Engine.max_fps,
		"process_frames": Engine.get_process_frames(),
		"physics_frames": Engine.get_physics_frames(),
		"frames_drawn": Engine.get_frames_drawn(),
	}


static func _collect_autoloads(tree: SceneTree, options: Dictionary) -> Dictionary:
	var max_autoloads := clampi(int(options.get("max_autoloads", DEFAULT_MAX_AUTOLOADS)), 1, 200)
	var entries := []
	var total := 0
	var root := tree.root
	for setting_name in ProjectSettings.get_property_list():
		if typeof(setting_name) != TYPE_DICTIONARY:
			continue
		var property_name := str((setting_name as Dictionary).get("name", ""))
		if not property_name.begins_with("autoload/"):
			continue
		total += 1
		if entries.size() >= max_autoloads:
			continue
		var autoload_name := property_name.trim_prefix("autoload/")
		var raw_value := str(ProjectSettings.get_setting(property_name, ""))
		var singleton := raw_value.begins_with("*")
		var resource_path := raw_value.trim_prefix("*")
		var node := root.get_node_or_null(NodePath(autoload_name)) if root != null else null
		var entry := {
			"name": autoload_name,
			"resource_path": _res_path_or_empty(resource_path),
			"singleton": singleton,
			"node_path": _node_path_or_empty(node),
			"present_in_tree": node != null,
			"type": node.get_class() if node != null else "",
			"script_path": _script_path_or_empty(node) if node != null else "",
			"scene_file_path": _res_path_or_empty(node.scene_file_path) if node != null else "",
		}
		entries.append(entry)
	return {
		"total": total,
		"sampled": entries,
		"truncated": total > max_autoloads,
		"max_autoloads": max_autoloads,
	}


static func _collect_input(options: Dictionary) -> Dictionary:
	var max_actions = clampi(int(options.get("max_input_actions", DEFAULT_MAX_INPUT_ACTIONS)), 1, 500)
	var action_names := []
	var action_states := []
	var active_actions := []
	var sampled_action_lookup := {}
	var total_actions := 0
	for action in InputMap.get_actions():
		total_actions += 1
		var action_name := str(action)
		var pressed := Input.is_action_pressed(action)
		if action_names.size() < max_actions:
			action_names.append(action_name)
			sampled_action_lookup[action_name] = true
			action_states.append({
				"name": action_name,
				"pressed": pressed,
				"strength": Input.get_action_strength(action),
			})
		if pressed:
			active_actions.append(action_name)
			if not sampled_action_lookup.has(action_name):
				action_states.append({
					"name": action_name,
					"pressed": true,
					"strength": Input.get_action_strength(action),
				})
	return {
		"total_actions": total_actions,
		"sampled_actions": action_names,
		"action_states": action_states,
		"active_actions": active_actions,
		"truncated": total_actions > max_actions,
		"max_actions": max_actions,
	}


static func _typed_node_state(node: Node) -> Dictionary:
	if node is Timer:
		var timer := node as Timer
		return {
			"kind": "Timer",
			"stopped": timer.is_stopped(),
			"time_left": timer.time_left,
			"wait_time": timer.wait_time,
			"one_shot": timer.one_shot,
			"paused": timer.paused,
		}
	if node is AnimationPlayer:
		var animation_player := node as AnimationPlayer
		return {
			"kind": "AnimationPlayer",
			"playing": animation_player.is_playing(),
			"current_animation": animation_player.current_animation,
			"speed_scale": animation_player.speed_scale,
		}
	if node is AudioStreamPlayer:
		var audio_player := node as AudioStreamPlayer
		return _audio_state("AudioStreamPlayer", audio_player.playing, audio_player.volume_db, audio_player.bus)
	if node is AudioStreamPlayer2D:
		var audio_player_2d := node as AudioStreamPlayer2D
		return _audio_state("AudioStreamPlayer2D", audio_player_2d.playing, audio_player_2d.volume_db, audio_player_2d.bus)
	if node is AudioStreamPlayer3D:
		var audio_player_3d := node as AudioStreamPlayer3D
		return _audio_state("AudioStreamPlayer3D", audio_player_3d.playing, audio_player_3d.volume_db, audio_player_3d.bus)
	if node is Camera2D:
		var camera_2d := node as Camera2D
		return {
			"kind": "Camera2D",
			"enabled": camera_2d.enabled,
			"zoom": {"x": camera_2d.zoom.x, "y": camera_2d.zoom.y},
			"offset": {"x": camera_2d.offset.x, "y": camera_2d.offset.y},
		}
	if node is Camera3D:
		var camera_3d := node as Camera3D
		return {
			"kind": "Camera3D",
			"current": camera_3d.current,
			"fov": camera_3d.fov,
			"near": camera_3d.near,
			"far": camera_3d.far,
		}
	if node is CharacterBody2D:
		var character_2d := node as CharacterBody2D
		return {
			"kind": "CharacterBody2D",
			"velocity": {"x": character_2d.velocity.x, "y": character_2d.velocity.y},
			"floor": character_2d.is_on_floor(),
			"wall": character_2d.is_on_wall(),
			"ceiling": character_2d.is_on_ceiling(),
		}
	if node is CharacterBody3D:
		var character_3d := node as CharacterBody3D
		return {
			"kind": "CharacterBody3D",
			"velocity": {"x": character_3d.velocity.x, "y": character_3d.velocity.y, "z": character_3d.velocity.z},
			"floor": character_3d.is_on_floor(),
			"wall": character_3d.is_on_wall(),
			"ceiling": character_3d.is_on_ceiling(),
		}
	return {}


static func _audio_state(kind: String, playing: bool, volume_db: float, bus: StringName) -> Dictionary:
	return {
		"kind": kind,
		"playing": playing,
		"volume_db": volume_db,
		"bus": str(bus),
	}


static func _script_path_or_empty(node: Node) -> String:
	var script := node.get_script()
	if script == null or not (script is Resource):
		return ""
	return _res_path_or_empty((script as Resource).resource_path)


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
