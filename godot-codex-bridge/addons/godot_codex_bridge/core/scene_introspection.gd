@tool
extends RefCounted

const BridgeContext := preload("bridge_context.gd")
const L := preload("bridge_limits.gd")
const VariantCodec := preload("variant_codec.gd")
const EditorControlManifest := preload("editor_control_manifest.gd")
const MaterialDiagnosticsModel := preload("material_diagnostics_model.gd")

const PLUGIN_VERSION := L.PLUGIN_VERSION
const PROTOCOL_VERSION := L.PROTOCOL_VERSION
const POLL_SECONDS := L.POLL_SECONDS
const MAX_SCENE_NODES := L.MAX_SCENE_NODES
const MAX_CHILDREN_PER_NODE := L.MAX_CHILDREN_PER_NODE
const MAX_SELECTED_NODES := L.MAX_SELECTED_NODES
const MAX_PROPERTIES_PER_NODE := L.MAX_PROPERTIES_PER_NODE
const MAX_PROPERTY_DEPTH := L.MAX_PROPERTY_DEPTH
const MAX_ARRAY_ITEMS := L.MAX_ARRAY_ITEMS
const MAX_DICTIONARY_ITEMS := L.MAX_DICTIONARY_ITEMS
const MAX_RESOURCES := L.MAX_RESOURCES
const MAX_INPUT_ACTIONS := L.MAX_INPUT_ACTIONS
const MAX_SCRIPT_FILES := L.MAX_SCRIPT_FILES
const MAX_SCRIPT_LINES_PER_FILE := L.MAX_SCRIPT_LINES_PER_FILE
const MAX_SCRIPT_SYMBOLS_PER_FILE := L.MAX_SCRIPT_SYMBOLS_PER_FILE
const MAX_SCREENSHOTS_IN_CONTEXT := L.MAX_SCREENSHOTS_IN_CONTEXT
const MAX_BRIDGE_LOG_EVENTS := L.MAX_BRIDGE_LOG_EVENTS
const MAX_EDITOR_BATCH_ACTIONS := L.MAX_EDITOR_BATCH_ACTIONS
const MAX_EDITOR_PROPERTY_CHANGES := L.MAX_EDITOR_PROPERTY_CHANGES
const MAX_MATERIALS_PER_MESH := L.MAX_MATERIALS_PER_MESH
const MAX_PERFORMANCE_SAMPLES := L.MAX_PERFORMANCE_SAMPLES
const MAX_STRING_LENGTH := L.MAX_STRING_LENGTH
const MAX_DEPTH := L.MAX_DEPTH

var ctx: BridgeContext


func _init(context: BridgeContext) -> void:
	ctx = context


func collect_context_snapshot(reason: String) -> Dictionary:
	return _collect_context_snapshot(reason)
func _collect_context_snapshot(reason: String) -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	var scene_tree_payload := _scene_tree_payload(scene_root)

	return {
		"protocol_version": PROTOCOL_VERSION,
		"generated_at": _iso_now(),
		"bridge": {
			"addon_version": PLUGIN_VERSION,
			"status": "active",
			"local_bridge_dir": ".godot/godot_codex_bridge",
			"snapshot_path": ".godot/godot_codex_bridge/context_snapshot.json",
			"requests_dir": ".godot/godot_codex_bridge/requests",
			"responses_dir": ".godot/godot_codex_bridge/responses",
			"artifacts_dir": ".godot/godot_codex_bridge/artifacts",
		},
		"project": _project_payload(),
		"current_scene": _current_scene_payload(scene_root),
		"editor_state": _editor_state_payload(scene_root),
		"scene_tree": scene_tree_payload,
		"selected_nodes": _selected_nodes_payload(scene_root),
		"resource_status": _resource_status_payload(),
		"editor_output": _editor_output_payload(),
		"gameplay_context": _gameplay_context_payload(),
		"script_inventory": _script_inventory_payload(),
		"performance": _performance_payload(),
		"screenshots": _screenshots_payload(),
	}



func _project_payload() -> Dictionary:
	var version := Engine.get_version_info()
	return {
		"name": str(ProjectSettings.get_setting("application/config/name", "")),
		"root_path": ProjectSettings.globalize_path("res://"),
		"godot_version": str(version.get("string", "")),
		"project_file": "project.godot",
		"main_scene": str(ProjectSettings.get_setting("application/run/main_scene", "")),
		"features": _packed_string_array_to_array(ProjectSettings.get_setting("application/config/features", PackedStringArray())),
	}



func _current_scene_payload(scene_root: Node) -> Dictionary:
	if scene_root == null:
		return {
			"path": null,
			"name": null,
			"root_node": null,
			"is_dirty": false,
			"open_scenes": _open_scenes_payload(),
		}

	return {
		"path": scene_root.scene_file_path,
		"name": scene_root.name,
		"root_node": _node_ref_payload(scene_root, scene_root),
		"is_dirty": false,
		"open_scenes": _open_scenes_payload(),
	}



func _open_scenes_payload() -> Array:
	var open_scenes: Array = []
	for scene_path in EditorInterface.get_open_scenes():
		open_scenes.append(str(scene_path))
	return open_scenes



func _editor_state_payload(scene_root: Node) -> Dictionary:
	return {
		"captured_at": _iso_now(),
		"current_scene": _current_scene_payload(scene_root),
		"open_scenes": _open_scenes_payload(),
		"selected_nodes": _selected_nodes_payload(scene_root),
		"selected_files": _selected_files_payload(),
		"permissions": ctx.permissions,
		"capabilities": _editor_capabilities_payload(),
		"diagnostics": {
			"bridge_log_entries": ctx.bridge_log.size(),
			"last_cleared_at": null if ctx.diagnostics_cleared_at == "" else ctx.diagnostics_cleared_at,
			"native_output_supported": false,
		},
		"recent_actions": ctx.recent_editor_actions,
		"project_settings_summary": _important_project_settings_payload(),
	}



func _selected_files_payload() -> Array:
	if not EditorInterface.has_method("get_selected_paths"):
		return []
	var selected: Variant = EditorInterface.call("get_selected_paths")
	return _packed_string_array_to_array(selected)



func _editor_capabilities_payload() -> Dictionary:
	return EditorControlManifest.capabilities(MAX_EDITOR_BATCH_ACTIONS, MAX_EDITOR_PROPERTY_CHANGES)



func _scene_tree_payload(scene_root: Node) -> Dictionary:
	var state := {
		"count": 0,
		"truncated": false,
	}

	if scene_root == null:
		return {
			"root": null,
			"node_count": 0,
			"truncated": false,
			"limits": _scene_limits_payload(),
		}

	return {
		"root": _node_tree_payload(scene_root, scene_root, state),
		"node_count": state["count"],
		"truncated": state["truncated"],
		"limits": _scene_limits_payload(),
	}



func _scene_limits_payload() -> Dictionary:
	return _summary_limits_payload()



func _summary_limits_payload() -> Dictionary:
	return {
		"max_nodes": MAX_SCENE_NODES,
		"max_depth": MAX_DEPTH,
		"max_properties_per_node": MAX_PROPERTIES_PER_NODE,
		"max_string_length": MAX_STRING_LENGTH,
	}



func _node_tree_payload(node: Node, scene_root: Node, state: Dictionary) -> Dictionary:
	state["count"] = int(state["count"]) + 1

	var payload := _basic_node_payload(node, scene_root)
	payload["child_count"] = node.get_child_count()
	payload["children"] = []

	var child_limit: int = min(node.get_child_count(), MAX_CHILDREN_PER_NODE)
	for child_index in range(child_limit):
		if int(state["count"]) >= MAX_SCENE_NODES:
			state["truncated"] = true
			break

		var child := node.get_child(child_index)
		payload["children"].append(_node_tree_payload(child, scene_root, state))

	if node.get_child_count() > MAX_CHILDREN_PER_NODE:
		state["truncated"] = true

	return payload



func _basic_node_payload(node: Node, scene_root: Node) -> Dictionary:
	var owner_path := ""
	if node.owner != null:
		owner_path = _scene_path_for(node.owner, scene_root)

	return {
		"path": _scene_path_for(node, scene_root),
		"name": node.name,
		"type": node.get_class(),
		"parent_path": _parent_scene_path_for(node, scene_root),
		"owner_path": owner_path,
		"groups": _string_array(node.get_groups()),
		"scene_file_path": _null_if_empty(node.scene_file_path),
		"script_path": _resource_path_or_null(node.get_script()),
		"three_d": _node_3d_hints(node),
	}



func _node_ref_payload(node: Node, scene_root: Node) -> Dictionary:
	return {
		"path": _scene_path_for(node, scene_root),
		"name": node.name,
		"type": node.get_class(),
	}



func _node_3d_hints(node: Node) -> Dictionary:
	var hints := {}

	if node is Node3D:
		var node_3d := node as Node3D
		hints["transform"] = _transform_summary(node_3d)
		hints["visible"] = node_3d.visible

	if node is Camera3D:
		hints["camera"] = {
			"current": node.get("current"),
			"projection": _camera_projection_name(int(node.get("projection"))),
			"fov_degrees": node.get("fov"),
			"size": node.get("size") if int(node.get("projection")) != Camera3D.PROJECTION_PERSPECTIVE else null,
			"near": node.get("near"),
			"far": node.get("far"),
		}

	if node is Light3D:
		hints["light"] = {
			"light_type": node.get_class(),
			"energy": node.get("light_energy"),
			"color": _color_to_hex(node.get("light_color")),
			"range": node.get("omni_range") if node is OmniLight3D else null,
			"shadows_enabled": node.get("shadow_enabled"),
		}

	if node is MeshInstance3D:
		var mesh: Variant = node.get("mesh")
		var mesh_resource := mesh as Mesh
		hints["mesh"] = {
			"mesh_resource_path": _resource_path_or_null(mesh),
			"surface_count": mesh_resource.get_surface_count() if mesh_resource != null else 0,
			"material_count": MaterialDiagnosticsModel.mesh_material_count(node as MeshInstance3D),
			"aabb": _variant_to_json_value(mesh_resource.get_aabb()) if mesh_resource != null else null,
		}

	if node is CollisionShape3D:
		var shape: Variant = node.get("shape")
		hints["collision_shape"] = {
			"shape_type": shape.get_class() if shape is Object else null,
			"disabled": node.get("disabled"),
			"shape_resource_path": _resource_path_or_null(shape),
		}

	if node is NavigationRegion3D:
		hints["navigation_region"] = {
			"enabled": node.get("enabled"),
			"navigation_mesh_path": _resource_path_or_null(node.get("navigation_mesh")),
			"bake_status": "unknown",
		}

	return hints



func _transform_summary(node_3d: Node3D) -> Dictionary:
	return {
		"position": _variant_to_json_value(node_3d.position),
		"rotation_degrees": _variant_to_json_value(node_3d.rotation_degrees),
		"scale": _variant_to_json_value(node_3d.scale),
	}



func _camera_projection_name(projection: int) -> String:
	match projection:
		Camera3D.PROJECTION_PERSPECTIVE:
			return "perspective"
		Camera3D.PROJECTION_ORTHOGONAL:
			return "orthogonal"
		Camera3D.PROJECTION_FRUSTUM:
			return "frustum"
		_:
			return "unknown"



func _color_to_hex(value: Variant) -> Variant:
	if value is Color:
		return "#" + (value as Color).to_html(false)
	return null



func _selected_nodes_payload(scene_root: Node) -> Array:
	var selected_nodes: Array = []

	var selection := EditorInterface.get_selection()
	if selection != null:
		var raw_selected := selection.get_selected_nodes()
		var selected_count: int = min(raw_selected.size(), MAX_SELECTED_NODES)
		for index in range(selected_count):
			var node: Node = raw_selected[index]
			if node == null:
				continue
			selected_nodes.append(_selected_node_payload(node, scene_root))

	return selected_nodes



func _selected_node_payload(node: Node, scene_root: Node) -> Dictionary:
	var node_payload := _basic_node_payload(node, scene_root)
	node_payload["child_count"] = node.get_child_count()
	node_payload["children"] = []
	return {
		"node": node_payload,
		"properties_summary": _bounded_property_summary(node),
		"summary_limits": _summary_limits_payload(),
	}



func _bounded_property_summary(object: Object) -> Array:
	var properties: Array = []

	for property_info in object.get_property_list():
		if properties.size() >= MAX_PROPERTIES_PER_NODE:
			break

		var property_name := str(property_info.get("name", ""))
		if property_name == "" or property_name.begins_with("_"):
			continue

		var usage := int(property_info.get("usage", 0))
		if ((usage & PROPERTY_USAGE_EDITOR) == 0) and ((usage & PROPERTY_USAGE_STORAGE) == 0):
			continue

		var value: Variant = object.get(property_name)
		properties.append({
			"name": property_name,
			"value_type": type_string(int(property_info.get("type", TYPE_NIL))),
			"value_summary": _property_value_summary(value),
			"source": "inspector",
			"included_reason": "bounded inspector summary",
			"redacted": _is_redacted_value(value),
			"omitted_reason": _omitted_reason_for(value),
		})

	return properties



func _resource_status_payload() -> Dictionary:
	var resource_fs := EditorInterface.get_resource_filesystem()
	if resource_fs == null:
		return {
			"scan_status": "unavailable",
			"resources": [],
			"missing_resources": [],
			"import_errors": [],
			"truncated": false,
			"limits": _summary_limits_payload(),
		}

	var resources: Array = []
	var import_errors: Array = []
	var state := {
		"count": 0,
		"truncated": false,
	}

	var root_dir := resource_fs.get_filesystem()
	if root_dir != null:
		_collect_resource_files(root_dir, resources, import_errors, state)

	return {
		"scan_status": "partial" if resource_fs.is_scanning() else "complete",
		"resources": resources,
		"missing_resources": [],
		"import_errors": import_errors,
		"truncated": state["truncated"],
		"limits": _summary_limits_payload(),
	}



func _collect_resource_files(directory: EditorFileSystemDirectory, resources: Array, invalid_imports: Array, state: Dictionary) -> void:
	for file_index in range(directory.get_file_count()):
		state["count"] = int(state["count"]) + 1
		var resource_payload := {
			"path": directory.get_file_path(file_index),
			"type": str(directory.get_file_type(file_index)),
			"status": "ok" if directory.get_file_import_is_valid(file_index) else "import_error",
			"owner_node_paths": [],
			"message": null,
		}

		if resources.size() < MAX_RESOURCES:
			resources.append(resource_payload)
		else:
			state["truncated"] = true

		if not directory.get_file_import_is_valid(file_index) and invalid_imports.size() < MAX_RESOURCES:
			invalid_imports.append({
				"timestamp": null,
				"level": "error",
				"message": "Invalid import: " + directory.get_file_path(file_index),
				"file": directory.get_file_path(file_index),
				"line": null,
			})

	for subdir_index in range(directory.get_subdir_count()):
		_collect_resource_files(directory.get_subdir(subdir_index), resources, invalid_imports, state)



func _editor_output_payload() -> Dictionary:
	var entries: Array = []
	for event in ctx.bridge_log:
		if typeof(event) != TYPE_DICTIONARY:
			continue
		entries.append({
			"timestamp": event.get("at", null),
			"level": "info",
			"message": str(event.get("type", "")),
			"file": null,
			"line": null,
		})

	return {
		"captured_at": _iso_now(),
		"source": "bridge_log",
		"entries": entries,
		"truncated": ctx.bridge_log.size() >= MAX_BRIDGE_LOG_EVENTS,
		"limits": _summary_limits_payload(),
	}



func _gameplay_context_payload() -> Dictionary:
	return {
		"captured_at": _iso_now(),
		"input_actions": _input_actions_payload(),
		"autoloads": _autoloads_payload(),
		"layer_names": _layer_names_payload(),
		"project_settings": _important_project_settings_payload(),
		"limits": {
			"max_input_actions": MAX_INPUT_ACTIONS,
			"max_string_length": MAX_STRING_LENGTH,
		},
	}



func _input_actions_payload() -> Array:
	var actions: Array = []
	var property_list := ProjectSettings.get_property_list()
	for property_info in property_list:
		if actions.size() >= MAX_INPUT_ACTIONS:
			break
		var setting_name := str(property_info.get("name", ""))
		if not setting_name.begins_with("input/"):
			continue
		var action_name := setting_name.trim_prefix("input/")
		var setting: Variant = ProjectSettings.get_setting(setting_name)
		var events: Array = []
		var deadzone: Variant = null
		if typeof(setting) == TYPE_DICTIONARY:
			deadzone = setting.get("deadzone", null)
			for event in setting.get("events", []):
				if events.size() >= MAX_ARRAY_ITEMS:
					break
				events.append(_input_event_summary(event))
		actions.append({
			"name": action_name,
			"setting": setting_name,
			"built_in": action_name.begins_with("ui_"),
			"deadzone": deadzone,
			"events": events,
			"event_count": events.size(),
		})
	return actions



func _input_event_summary(event: Variant) -> Dictionary:
	var payload := {
		"type": type_string(typeof(event)),
		"summary": _truncate_string(str(event), 240),
	}
	if event is InputEvent:
		payload["type"] = event.get_class()
		if event is InputEventKey:
			payload["keycode"] = OS.get_keycode_string((event as InputEventKey).physical_keycode)
		if event is InputEventMouseButton:
			payload["button_index"] = (event as InputEventMouseButton).button_index
		if event is InputEventJoypadButton:
			payload["button_index"] = (event as InputEventJoypadButton).button_index
		if event is InputEventJoypadMotion:
			payload["axis"] = (event as InputEventJoypadMotion).axis
			payload["axis_value"] = (event as InputEventJoypadMotion).axis_value
	return payload



func _autoloads_payload() -> Array:
	var autoloads: Array = []
	for property_info in ProjectSettings.get_property_list():
		var setting_name := str(property_info.get("name", ""))
		if not setting_name.begins_with("autoload/"):
			continue
		var autoload_name := setting_name.trim_prefix("autoload/")
		var raw_value := str(ProjectSettings.get_setting(setting_name))
		autoloads.append({
			"name": autoload_name,
			"path": raw_value.trim_prefix("*"),
			"singleton": raw_value.begins_with("*"),
		})
	return autoloads



func _layer_names_payload() -> Dictionary:
	var groups := {
		"2d_render": "layer_names/2d_render/layer_",
		"2d_physics": "layer_names/2d_physics/layer_",
		"3d_render": "layer_names/3d_render/layer_",
		"3d_physics": "layer_names/3d_physics/layer_",
		"navigation": "layer_names/navigation/layer_",
	}
	var payload := {}
	for group_name in groups.keys():
		var layers: Array = []
		for index in range(1, 33):
			var setting_name: String = str(groups[group_name]) + str(index)
			var layer_name := str(ProjectSettings.get_setting(setting_name, ""))
			if layer_name == "":
				continue
			layers.append({
				"index": index,
				"name": layer_name,
			})
		payload[group_name] = layers
	return payload



func _important_project_settings_payload() -> Dictionary:
	var setting_names := [
		"application/config/name",
		"application/run/main_scene",
		"display/window/size/viewport_width",
		"display/window/size/viewport_height",
		"display/window/stretch/mode",
		"display/window/stretch/aspect",
		"physics/common/physics_ticks_per_second",
		"rendering/renderer/rendering_method",
		"rendering/renderer/rendering_method.mobile",
	]
	var payload := {}
	for setting_name in setting_names:
		if ProjectSettings.has_setting(setting_name):
			payload[setting_name] = _property_value_summary(ProjectSettings.get_setting(setting_name))
	return payload



func _script_inventory_payload() -> Dictionary:
	var scripts: Array = []
	var state := {
		"count": 0,
		"truncated": false,
	}
	var resource_fs := EditorInterface.get_resource_filesystem()
	if resource_fs != null and resource_fs.get_filesystem() != null:
		_collect_script_inventory(resource_fs.get_filesystem(), scripts, state)
	return {
		"captured_at": _iso_now(),
		"scripts": scripts,
		"script_count": state["count"],
		"truncated": state["truncated"],
		"limits": {
			"max_scripts": MAX_SCRIPT_FILES,
			"max_lines_per_file": MAX_SCRIPT_LINES_PER_FILE,
			"max_symbols_per_file": MAX_SCRIPT_SYMBOLS_PER_FILE,
			"max_string_length": MAX_STRING_LENGTH,
		},
	}



func _collect_script_inventory(directory: EditorFileSystemDirectory, scripts: Array, state: Dictionary) -> void:
	for file_index in range(directory.get_file_count()):
		var file_path := directory.get_file_path(file_index)
		if not file_path.ends_with(".gd"):
			continue
		if file_path.begins_with("res://addons/godot_codex_bridge/"):
			continue
		state["count"] = int(state["count"]) + 1
		if scripts.size() >= MAX_SCRIPT_FILES:
			state["truncated"] = true
			continue
		scripts.append(_script_summary(file_path))

	for subdir_index in range(directory.get_subdir_count()):
		_collect_script_inventory(directory.get_subdir(subdir_index), scripts, state)



func _script_summary(script_path: String) -> Dictionary:
	var summary := {
		"path": script_path,
		"class_name": null,
		"extends": null,
		"is_tool": false,
		"signals": [],
		"exports": [],
		"functions": [],
		"todos": [],
		"line_count_scanned": 0,
		"truncated": false,
	}
	var file := FileAccess.open(script_path, FileAccess.READ)
	if file == null:
		summary["read_error"] = error_string(FileAccess.get_open_error())
		return summary

	var line_index := 0
	while not file.eof_reached() and line_index < MAX_SCRIPT_LINES_PER_FILE:
		var line := file.get_line()
		line_index += 1
		_scan_script_line(line.strip_edges(), line_index, summary)
	summary["line_count_scanned"] = line_index
	summary["truncated"] = not file.eof_reached()
	return summary



func _scan_script_line(line: String, line_number: int, summary: Dictionary) -> void:
	if line == "":
		return
	if line == "@tool":
		summary["is_tool"] = true
	if line.begins_with("class_name "):
		summary["class_name"] = _truncate_string(line.trim_prefix("class_name ").strip_edges(), 160)
	if line.begins_with("extends "):
		summary["extends"] = _truncate_string(line.trim_prefix("extends ").strip_edges(), 160)
	if line.begins_with("signal ") and summary["signals"].size() < MAX_SCRIPT_SYMBOLS_PER_FILE:
		summary["signals"].append(_script_symbol_payload(line, line_number))
	if line.begins_with("@export") and summary["exports"].size() < MAX_SCRIPT_SYMBOLS_PER_FILE:
		summary["exports"].append(_script_symbol_payload(line, line_number))
	if line.begins_with("func ") and summary["functions"].size() < MAX_SCRIPT_SYMBOLS_PER_FILE:
		summary["functions"].append(_script_symbol_payload(line, line_number))
	if ("TODO" in line or "FIXME" in line) and summary["todos"].size() < MAX_ARRAY_ITEMS:
		summary["todos"].append({
			"line": line_number,
			"text": _truncate_string(line, 240),
		})



func _script_symbol_payload(line: String, line_number: int) -> Dictionary:
	return {
		"line": line_number,
		"signature": _truncate_string(line, 240),
	}



func _performance_payload() -> Dictionary:
	var sample := _record_performance_sample()
	return {
		"captured_at": _iso_now(),
		"source": "godot_performance_monitor",
		"status": "available",
		"sample_interval_seconds": POLL_SECONDS,
		"sample_count": ctx.performance_history.size(),
		"monitors": sample.get("monitors", {}),
		"samples": ctx.performance_history.duplicate(true),
		"limits": _summary_limits_payload(),
	}



func _record_performance_sample() -> Dictionary:
	var sample := {
		"captured_at": _iso_now(),
		"monitors": _performance_monitors_payload(),
	}
	ctx.performance_history.append(sample)
	while ctx.performance_history.size() > MAX_PERFORMANCE_SAMPLES:
		ctx.performance_history.pop_front()
	return sample



func _performance_monitors_payload() -> Dictionary:
	return {
		"time_fps": Performance.get_monitor(Performance.TIME_FPS),
		"render_total_objects_in_frame": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"render_total_primitives_in_frame": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"render_total_draw_calls_in_frame": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"physics_3d_active_objects": Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		"physics_3d_collision_pairs": Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS),
		"physics_3d_island_count": Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT),
		"navigation_active_maps": Performance.get_monitor(Performance.NAVIGATION_ACTIVE_MAPS),
		"navigation_region_count": Performance.get_monitor(Performance.NAVIGATION_REGION_COUNT),
		"navigation_agent_count": Performance.get_monitor(Performance.NAVIGATION_AGENT_COUNT),
	}



func _screenshots_payload() -> Array:
	ctx.ensure_dirs()

	var screenshots: Array = []
	var file_names := _list_files_with_extension(ctx.screenshots_dir_abs, ".png")
	file_names.sort()
	file_names.reverse()

	var count: int = min(file_names.size(), MAX_SCREENSHOTS_IN_CONTEXT)
	for index in range(count):
		var file_name := str(file_names[index])
		var abs_path := ctx.screenshots_dir_abs.path_join(file_name)
		screenshots.append(_screenshot_metadata(file_name, abs_path, 0, 0, "unknown", null))

	return screenshots



func _camera_payload(camera: Camera3D) -> Variant:
	if camera == null:
		return null

	return {
		"name": camera.name,
		"type": camera.get_class(),
		"absolute_node_path": str(camera.get_path()),
		"global_transform": _variant_to_json_value(camera.global_transform),
		"projection": camera.projection,
		"fov": camera.fov,
		"size": camera.size,
		"near": camera.near,
		"far": camera.far,
	}



func _screenshot_metadata(file_name: String, abs_path: String, width: int, height: int, reason: String, camera: Camera3D) -> Dictionary:
	return {
		"protocol_version": PROTOCOL_VERSION,
		"screenshot_id": _safe_identifier(file_name.get_basename()),
		"captured_at": _iso_now(),
		"scene_path": _current_scene_path_or_null(),
		"selected_node_paths": _selected_node_paths(),
		"artifact": {
			"local_path": abs_path,
			"project_relative_path": ".godot/godot_codex_bridge/artifacts/screenshots/" + file_name,
			"format": "png",
			"width": max(width, 1),
			"height": max(height, 1),
			"byte_size": FileAccess.get_file_as_bytes(abs_path).size() if FileAccess.file_exists(abs_path) else 0,
		},
		"viewport": {
			"source": "editor_3d_viewport",
			"mode": "unknown",
			"camera_node_path": str(camera.get_path()) if camera != null else null,
		},
		"privacy": {
			"classification": "local_sensitive_evidence",
			"external_upload_allowed": false,
			"notes": ["Local editor screenshot evidence only."],
		},
	}



func _scene_path_for(node: Node, scene_root: Node) -> String:
	if node == null:
		return ""
	if scene_root == null:
		return str(node.get_path())
	if node == scene_root:
		return "."
	if scene_root.is_ancestor_of(node):
		return str(scene_root.get_path_to(node))
	return str(node.get_path())



func _parent_scene_path_for(node: Node, scene_root: Node) -> Variant:
	var parent := node.get_parent()
	if parent == null:
		return null
	return _scene_path_for(parent, scene_root)



func _current_scene_path_or_null() -> Variant:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null or scene_root.scene_file_path == "":
		return null
	return scene_root.scene_file_path



func _selected_node_paths() -> Array:
	var paths: Array = []
	var selection := EditorInterface.get_selection()
	if selection == null:
		return paths

	for node in selection.get_selected_nodes():
		if node != null:
			paths.append(str(node.get_path()))
	return paths



func _resource_reference(value: Variant) -> Variant:
	return VariantCodec.resource_reference(value)



func _resource_path_or_null(value: Variant) -> Variant:
	return VariantCodec.resource_path_or_null(value)



func _null_if_empty(value: String) -> Variant:
	return null if value == "" else value



func _packed_string_array_to_array(value: Variant) -> Array:
	var result: Array = []
	if value is PackedStringArray:
		for item in value:
			result.append(str(item))
	elif value is Array:
		for item in value:
			result.append(str(item))
	return result



func _property_value_summary(value: Variant) -> Variant:
	return VariantCodec.property_value_summary(value, MAX_STRING_LENGTH, MAX_PROPERTY_DEPTH, MAX_ARRAY_ITEMS, MAX_DICTIONARY_ITEMS)



func _is_redacted_value(value: Variant) -> bool:
	return VariantCodec.is_redacted_value(value)



func _omitted_reason_for(value: Variant) -> Variant:
	return VariantCodec.omitted_reason_for(value)



func _truncate_string(value: String, max_length: int = MAX_STRING_LENGTH) -> String:
	if value.length() <= max_length:
		return value
	return value.substr(0, max_length)



func _variant_to_json_value(value: Variant, depth: int = 0) -> Variant:
	return VariantCodec.variant_to_json_value(value, depth, MAX_PROPERTY_DEPTH, MAX_ARRAY_ITEMS, MAX_DICTIONARY_ITEMS)



func _array_to_json_summary(value: Array, depth: int) -> Dictionary:
	return VariantCodec.array_to_json_summary(value, depth, MAX_PROPERTY_DEPTH, MAX_ARRAY_ITEMS, MAX_DICTIONARY_ITEMS)



func _dictionary_to_json_summary(value: Dictionary, depth: int) -> Dictionary:
	return VariantCodec.dictionary_to_json_summary(value, depth, MAX_PROPERTY_DEPTH, MAX_ARRAY_ITEMS, MAX_DICTIONARY_ITEMS)



func _string_array(values: Array) -> Array:
	var strings: Array = []
	for value in values:
		strings.append(str(value))
	return strings



func _list_files_with_extension(dir_path: String, extension: String) -> Array:
	var files: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return files

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(extension):
			files.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()

	return files



func _iso_now() -> String:
	return Time.get_datetime_string_from_system(true, false) + "Z"



func _safe_identifier(value: String) -> String:
	var safe := ""
	for index in range(value.length()):
		var character := value.substr(index, 1)
		if character.is_valid_identifier() or character.is_valid_int() or character == "-" or character == ".":
			safe += character
		else:
			safe += "_"
	return safe.strip_edges().substr(0, 128) if safe.strip_edges() != "" else "artifact"

