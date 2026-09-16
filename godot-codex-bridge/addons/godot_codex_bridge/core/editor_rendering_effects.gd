@tool
extends RefCounted

const BridgeContext := preload("bridge_context.gd")
const BridgeLimits := preload("bridge_limits.gd")
const EditorAssetImport := preload("editor_asset_import.gd")
const ParticleEffectModel := preload("particle_effect_model.gd")
const VariantCodec := preload("variant_codec.gd")

var _context: BridgeContext


func _init(context: BridgeContext = null) -> void:
	_context = context


func inspect_rendering_effects(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_editor_inspect"):
		return _err("permission_denied", "Inspect/select nodes permission is disabled in the Codex Bridge dock.")

	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return _err("no_current_scene", "No edited scene is open.")

	var selected_only := bool(params.get("selected_only", params.get("selectedOnly", false)))
	var include_environment_properties := bool(params.get("include_environment_properties", params.get("includeEnvironmentProperties", true)))
	var include_particles := bool(params.get("include_particles", params.get("includeParticles", true)))
	var max_nodes := clampi(int(params.get("max_nodes", params.get("maxNodes", BridgeLimits.MAX_RENDER_EFFECT_NODES))), 1, BridgeLimits.MAX_RENDER_EFFECT_NODES)

	var world_environment_nodes: Array = []
	var camera_nodes: Array = []
	var particle_nodes: Array = []
	var collect_state := {
		"visited": 0,
		"matched": 0,
		"truncated": false,
		"seen": {},
	}
	if selected_only:
		var selection := EditorInterface.get_selection()
		if selection != null:
			for selected in selection.get_selected_nodes():
				if bool(collect_state.get("truncated", false)):
					break
				if selected != null and (selected == scene_root or scene_root.is_ancestor_of(selected)):
					collect_rendering_effect_nodes(selected as Node, scene_root, world_environment_nodes, camera_nodes, particle_nodes, collect_state, max_nodes, include_particles)
	else:
		collect_rendering_effect_nodes(scene_root, scene_root, world_environment_nodes, camera_nodes, particle_nodes, collect_state, max_nodes, include_particles)

	var suggestions: Array = []
	var stats := {
		"world_environment_nodes": 0,
		"camera_environment_overrides": 0,
		"environment_resources": 0,
		"particle_nodes": 0,
		"particles_without_process_material": 0,
		"gpu_particles_without_draw_pass": 0,
	}
	var world_environments: Array = []
	for node in world_environment_nodes:
		if node is Node:
			world_environments.append(world_environment_payload(node as Node, scene_root, include_environment_properties, stats, suggestions))

	var camera_environments: Array = []
	for node in camera_nodes:
		if node is Node:
			camera_environments.append(camera_environment_payload(node as Node, scene_root, include_environment_properties, stats, suggestions))

	var particles: Array = []
	if include_particles:
		for node in particle_nodes:
			if node is Node:
				particles.append(particle_node_payload(node as Node, scene_root, stats, suggestions))

	if world_environments.is_empty() and camera_environments.is_empty():
		suggestions.append({
			"code": "no_environment_nodes_found",
			"severity": "info",
			"message": "No WorldEnvironment nodes or Camera3D environment overrides were found in the inspected scope.",
		})
	if include_particles and particles.is_empty():
		suggestions.append({
			"code": "no_particle_nodes_found",
			"severity": "info",
			"message": "No particle nodes were found in the inspected scope.",
		})

	return _ok({
		"captured_at": _now(),
		"current_scene": current_scene_payload(scene_root),
		"selected_only": selected_only,
		"include_environment_properties": include_environment_properties,
		"include_particles": include_particles,
		"world_environments": world_environments,
		"camera_environments": camera_environments,
		"particles": particles,
		"stats": stats,
		"suggestions": suggestions,
		"visited_node_count": int(collect_state.get("visited", 0)),
		"matched_node_count": int(collect_state.get("matched", 0)),
		"truncated": bool(collect_state.get("truncated", false)),
		"limits": {
			"max_nodes": max_nodes,
			"max_environment_properties": BridgeLimits.MAX_ENVIRONMENT_PROPERTIES,
		},
		"snapshot_refreshed": false,
	})


func set_environment_property(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_scene_edits"):
		return _err("permission_denied", "Scene edits via UndoRedo permission is disabled in the Codex Bridge dock.")

	var node_result := resolve_editor_node(str(params.get("node_path", params.get("nodePath", ""))).strip_edges())
	if not node_result.get("ok", false):
		return node_result
	var node: Node = node_result.get("node", null)
	var scene_root: Node = node_result.get("scene_root", null)
	if not (node is WorldEnvironment) and not (node is Camera3D):
		return _err("unsupported_environment_target", "set_environment_property supports WorldEnvironment and Camera3D nodes only.")
	if find_object_property_info(node, "environment").is_empty():
		return _err("environment_property_missing", "Target node does not expose an environment property.")

	var property_name := str(params.get("property", "")).strip_edges()
	var property_error := validate_environment_mutable_property(property_name)
	if not property_error.is_empty():
		return {"ok": false, "error": property_error}
	if not params.has("value"):
		return _err("invalid_environment_value", "value is required for set_environment_property.")

	var old_environment_value: Variant = node.get("environment")
	var old_environment := old_environment_value as Environment
	var environment := old_environment
	var created_environment := false
	if environment == null:
		if not bool(params.get("create_if_missing", params.get("createIfMissing", false))):
			return _err("environment_missing", "Target node has no Environment resource. Pass createIfMissing=true to create an unsaved live Environment.")
		environment = Environment.new()
		environment.set("resource_local_to_scene", bool(params.get("local_to_scene", params.get("localToScene", true))))
		created_environment = true

	var property_info := find_object_property_info(environment, property_name)
	if property_info.is_empty():
		return _err("property_not_found", "Environment does not expose property: " + property_name)
	if int(property_info.get("type", TYPE_NIL)) == TYPE_OBJECT:
		return _err("unsupported_environment_property", "Environment object/resource properties are not editable through set_environment_property V1.")

	var old_value: Variant = environment.get(property_name)
	var coercion := VariantCodec.coerce_editor_property_value(old_value, params.get("value"))
	if not coercion.get("ok", false):
		return _err("invalid_environment_value", str(coercion.get("error", {}).get("message", "Environment value has an unsupported type.")))
	var new_value: Variant = VariantCodec.coerced_value(coercion)
	var property_changed: bool = old_value != new_value
	var changed: bool = created_environment or property_changed
	if changed:
		var undo := _undo_redo()
		if undo == null:
			return _err("undo_redo_unavailable", "Editor UndoRedo manager is unavailable.")
		undo.create_action("Godot Codex Bridge: set environment property")
		if created_environment:
			undo.add_do_property(node, "environment", environment)
			undo.add_undo_property(node, "environment", old_environment_value)
		if property_changed:
			undo.add_do_property(environment, property_name, new_value)
			undo.add_undo_property(environment, property_name, old_value)
		undo.commit_action()

	var snapshot: Dictionary = _refresh("editor_control:set_environment_property") if changed else {}
	var data := {
		"changed": changed,
		"undo_redo_action": changed,
		"auto_saved": false,
		"node": EditorAssetImport.node_ref_payload(node, scene_root),
		"target_kind": "world_environment" if node is WorldEnvironment else "camera_environment",
		"created_environment": created_environment,
		"old_environment": VariantCodec.resource_reference(old_environment_value),
		"environment": VariantCodec.resource_reference(environment),
		"property": property_name,
		"old_value": json_value(old_value),
		"new_value": json_value(new_value),
		"snapshot_refreshed": changed,
		"generated_at": snapshot.get("generated_at", "") if changed else "",
	}
	_log("editor_environment_property_changed", data)
	return _ok(data)


func create_particle_effect(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_scene_edits"):
		return _err("permission_denied", "Scene edits via UndoRedo permission is disabled in the Codex Bridge dock.")

	var effect_kind := str(params.get("kind", params.get("effectKind", "gpu_particles_3d"))).strip_edges().to_lower()
	if effect_kind != "gpu_particles_3d":
		return _err("unsupported_particle_effect_kind", "create_particle_effect V1 supports only gpu_particles_3d.")

	var parent_result := resolve_editor_node(str(params.get("parent_path", params.get("parentPath", "."))).strip_edges())
	if not parent_result.get("ok", false):
		return parent_result
	var parent: Node = parent_result.get("node", null)
	var scene_root: Node = parent_result.get("scene_root", null)
	if not (parent is Node3D):
		return _err("unsupported_particle_parent", "gpu_particles_3d effects must be parented under a Node3D.")

	var node_name := EditorAssetImport.sanitize_node_name(str(params.get("name", "")).strip_edges(), "CodexParticles3D")
	if not EditorAssetImport.is_valid_node_name(node_name):
		return _err("invalid_node_name", "Particle effect name is empty or contains path separators.")
	var index := EditorAssetImport.bounded_child_index(parent, int(params.get("index", -1)))
	var particle_node := GPUParticles3D.new()
	particle_node.name = node_name

	var process_material := ParticleProcessMaterial.new()
	process_material.set("resource_local_to_scene", bool(params.get("local_to_scene", params.get("localToScene", true))))

	var draw_mesh_result := ParticleEffectModel.create_draw_mesh(params)
	if not draw_mesh_result.get("ok", false):
		return draw_mesh_result
	var draw_mesh: Mesh = draw_mesh_result.get("mesh", null)

	var node_changes_result := ParticleEffectModel.prepare_create_node_changes(particle_node, process_material, draw_mesh, params)
	if not node_changes_result.get("ok", false):
		return node_changes_result
	var node_changes: Array = node_changes_result.get("changes", [])

	var transform_result := EditorAssetImport.prepare_initial_transform_changes(particle_node, params)
	if not transform_result.get("ok", false):
		return transform_result
	var transform_changes: Array = transform_result.get("changes", [])

	var material_changes_result := ParticleEffectModel.prepare_create_process_material_changes(process_material, params)
	if not material_changes_result.get("ok", false):
		return material_changes_result
	var material_changes: Array = material_changes_result.get("changes", [])

	var undo := _undo_redo()
	if undo == null:
		return _err("undo_redo_unavailable", "Editor UndoRedo manager is unavailable.")
	undo.create_action("Godot Codex Bridge: create particle effect")
	undo.add_do_method(parent, "add_child", particle_node)
	undo.add_do_method(parent, "move_child", particle_node, index)
	undo.add_do_property(particle_node, "owner", scene_root)
	undo.add_undo_property(particle_node, "owner", null)
	for change in node_changes:
		add_object_property_change_to_undo(undo, change as Dictionary)
	for change in transform_changes:
		var transform_property := str((change as Dictionary).get("property", ""))
		undo.add_do_property(particle_node, transform_property, (change as Dictionary).get("new_value"))
		undo.add_undo_property(particle_node, transform_property, (change as Dictionary).get("old_value"))
	for change in material_changes:
		add_object_property_change_to_undo(undo, change as Dictionary)
	undo.add_undo_method(parent, "remove_child", particle_node)
	undo.commit_action()

	if bool(params.get("restart", true)) and particle_node.has_method("restart"):
		particle_node.call("restart")
	if bool(params.get("select", true)):
		EditorAssetImport.select_single_node(particle_node)

	var snapshot := _refresh("editor_control:create_particle_effect")
	var data := {
		"changed": true,
		"undo_redo_action": true,
		"auto_saved": false,
		"effect_kind": effect_kind,
		"created_node": EditorAssetImport.node_ref_payload(particle_node, scene_root),
		"parent": EditorAssetImport.node_ref_payload(parent, scene_root),
		"index": index,
		"process_material": VariantCodec.resource_reference(process_material),
		"draw_mesh": VariantCodec.resource_reference(draw_mesh),
		"node_changes": EditorAssetImport.serialized_property_changes(node_changes),
		"transform_changes": EditorAssetImport.serialized_property_changes(transform_changes),
		"process_material_changes": EditorAssetImport.serialized_property_changes(material_changes),
		"snapshot_refreshed": true,
		"generated_at": snapshot.get("generated_at", ""),
	}
	_log("editor_particle_effect_created", data)
	return _ok(data)


func set_particle_effect_properties(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_scene_edits"):
		return _err("permission_denied", "Scene edits via UndoRedo permission is disabled in the Codex Bridge dock.")

	var node_result := resolve_editor_node(str(params.get("node_path", params.get("nodePath", ""))).strip_edges())
	if not node_result.get("ok", false):
		return node_result
	var node: Node = node_result.get("node", null)
	var scene_root: Node = node_result.get("scene_root", null)
	if not (node is GPUParticles3D):
		return _err("unsupported_particle_node", "set_particle_effect_properties V1 supports GPUParticles3D nodes only.")

	var node_changes_result := ParticleEffectModel.prepare_update_node_changes(node as GPUParticles3D, params)
	if not node_changes_result.get("ok", false):
		return node_changes_result
	var node_changes: Array = node_changes_result.get("changes", [])

	var material_changes: Array = []
	var material_created := false
	var process_material: Variant = node.get("process_material") if not find_object_property_info(node, "process_material").is_empty() else null
	if ParticleEffectModel.has_process_material_update(params):
		if not (process_material is ParticleProcessMaterial):
			if process_material == null and bool(params.get("create_process_material_if_missing", params.get("createProcessMaterialIfMissing", true))):
				var new_material := ParticleProcessMaterial.new()
				new_material.set("resource_local_to_scene", bool(params.get("local_to_scene", params.get("localToScene", true))))
				process_material = new_material
				material_created = true
				append_initial_property_change(node, "process_material", process_material, node_changes)
			else:
				return _err("unsupported_particle_process_material", "Particle material edits require an existing ParticleProcessMaterial or an empty process_material slot.")
		var prepared_material_changes := ParticleEffectModel.prepare_update_process_material_changes(process_material as ParticleProcessMaterial, params)
		if not prepared_material_changes.get("ok", false):
			return prepared_material_changes
		material_changes = prepared_material_changes.get("changes", [])

	var draw_changes_result := ParticleEffectModel.prepare_draw_mesh_update_changes(node as GPUParticles3D, params)
	if not draw_changes_result.get("ok", false):
		return draw_changes_result
	var draw_changes: Array = draw_changes_result.get("changes", [])

	var changed := not node_changes.is_empty() or not material_changes.is_empty() or not draw_changes.is_empty()
	if not changed:
		return _ok({
			"changed": false,
			"undo_redo_action": false,
			"auto_saved": false,
			"node": EditorAssetImport.node_ref_payload(node, scene_root),
			"message": "No supported particle properties were provided.",
		})

	var undo := _undo_redo()
	if undo == null:
		return _err("undo_redo_unavailable", "Editor UndoRedo manager is unavailable.")
	undo.create_action("Godot Codex Bridge: set particle effect properties")
	for change in node_changes:
		add_object_property_change_to_undo(undo, change as Dictionary)
	for change in material_changes:
		add_object_property_change_to_undo(undo, change as Dictionary)
	for change in draw_changes:
		add_object_property_change_to_undo(undo, change as Dictionary)
	undo.commit_action()

	if bool(params.get("restart", false)) and node.has_method("restart"):
		node.call("restart")
	if bool(params.get("select", false)):
		EditorAssetImport.select_single_node(node)

	var snapshot := _refresh("editor_control:set_particle_effect_properties")
	var data := {
		"changed": true,
		"undo_redo_action": true,
		"auto_saved": false,
		"node": EditorAssetImport.node_ref_payload(node, scene_root),
		"process_material_created": material_created,
		"process_material": VariantCodec.resource_reference(process_material),
		"node_changes": EditorAssetImport.serialized_property_changes(node_changes),
		"process_material_changes": EditorAssetImport.serialized_property_changes(material_changes),
		"draw_mesh_changes": EditorAssetImport.serialized_property_changes(draw_changes),
		"snapshot_refreshed": true,
		"generated_at": snapshot.get("generated_at", ""),
	}
	_log("editor_particle_effect_properties_set", data)
	return _ok(data)


static func collect_rendering_effect_nodes(node: Node, scene_root: Node, world_environment_nodes: Array, camera_nodes: Array, particle_nodes: Array, state: Dictionary, max_nodes: int, include_particles: bool) -> void:
	if node == null:
		return
	var seen: Dictionary = state.get("seen", {})
	var seen_key := str(node.get_instance_id())
	if seen.has(seen_key):
		return
	seen[seen_key] = true
	state["seen"] = seen
	state["visited"] = int(state.get("visited", 0)) + 1

	if node is WorldEnvironment:
		if not register_rendering_effect_match(state, max_nodes):
			return
		world_environment_nodes.append(node)
	elif node is Camera3D and node_has_non_null_property(node, "environment"):
		if not register_rendering_effect_match(state, max_nodes):
			return
		camera_nodes.append(node)
	elif include_particles and node_is_particle_effect(node):
		if not register_rendering_effect_match(state, max_nodes):
			return
		particle_nodes.append(node)

	for child in node.get_children():
		if bool(state.get("truncated", false)):
			return
		if child is Node:
			collect_rendering_effect_nodes(child as Node, scene_root, world_environment_nodes, camera_nodes, particle_nodes, state, max_nodes, include_particles)


static func register_rendering_effect_match(state: Dictionary, max_nodes: int) -> bool:
	if int(state.get("matched", 0)) >= max_nodes:
		state["truncated"] = true
		return false
	state["matched"] = int(state.get("matched", 0)) + 1
	return true


static func node_is_particle_effect(node: Node) -> bool:
	var node_class_name := node.get_class()
	if node_class_name in ["GPUParticles2D", "GPUParticles3D", "CPUParticles2D", "CPUParticles3D"]:
		return true
	return node_class_name.find("Particles") >= 0 and not find_object_property_info(node, "emitting").is_empty()


static func node_has_non_null_property(node: Node, property_name: String) -> bool:
	if find_object_property_info(node, property_name).is_empty():
		return false
	return node.get(property_name) != null


static func world_environment_payload(node: Node, scene_root: Node, include_environment_properties: bool, stats: Dictionary, suggestions: Array) -> Dictionary:
	stats["world_environment_nodes"] = int(stats.get("world_environment_nodes", 0)) + 1
	var node_ref := EditorAssetImport.node_ref_payload(node, scene_root)
	var environment_value: Variant = node.get("environment") if not find_object_property_info(node, "environment").is_empty() else null
	var environment := environment_value as Environment
	if environment == null:
		suggestions.append({
			"code": "world_environment_without_environment",
			"severity": "warning",
			"node": node_ref,
			"message": "WorldEnvironment node has no Environment resource assigned.",
		})
	return {
		"node": node_ref,
		"environment": environment_payload(environment, include_environment_properties, stats),
		"environment_missing": environment == null,
	}


static func camera_environment_payload(node: Node, scene_root: Node, include_environment_properties: bool, stats: Dictionary, _suggestions: Array) -> Dictionary:
	stats["camera_environment_overrides"] = int(stats.get("camera_environment_overrides", 0)) + 1
	var environment_value: Variant = node.get("environment") if not find_object_property_info(node, "environment").is_empty() else null
	var environment := environment_value as Environment
	return {
		"node": EditorAssetImport.node_ref_payload(node, scene_root),
		"current": bool(node.get("current")) if not find_object_property_info(node, "current").is_empty() else null,
		"environment": environment_payload(environment, include_environment_properties, stats),
		"environment_missing": environment == null,
	}


static func environment_payload(environment: Environment, include_properties: bool, stats: Dictionary) -> Variant:
	if environment == null:
		return null
	stats["environment_resources"] = int(stats.get("environment_resources", 0)) + 1
	var payload := {
		"resource": VariantCodec.resource_reference(environment),
		"enabled_effects": environment_enabled_effects(environment),
		"properties": [],
		"properties_truncated": false,
	}
	if not include_properties:
		return payload
	var properties: Array = []
	for property_name in environment_property_names():
		if properties.size() >= BridgeLimits.MAX_ENVIRONMENT_PROPERTIES:
			payload["properties_truncated"] = true
			break
		var property_info := find_object_property_info(environment, property_name)
		if property_info.is_empty():
			continue
		var value: Variant = environment.get(property_name)
		properties.append({
			"name": property_name,
			"type": type_string(typeof(value)),
			"value": json_value(value),
			"usage": int(property_info.get("usage", 0)),
		})
	payload["properties"] = properties
	return payload


static func environment_enabled_effects(environment: Environment) -> Array:
	var enabled: Array = []
	var flag_names := [
		"glow_enabled",
		"fog_enabled",
		"volumetric_fog_enabled",
		"ssao_enabled",
		"ssil_enabled",
		"sdfgi_enabled",
		"adjustment_enabled",
	]
	for property_name in flag_names:
		if not find_object_property_info(environment, property_name).is_empty() and bool(environment.get(property_name)):
			enabled.append(property_name.trim_suffix("_enabled"))
	return enabled


static func environment_property_names() -> Array:
	return [
		"background_mode",
		"background_color",
		"background_energy_multiplier",
		"sky",
		"sky_custom_fov",
		"ambient_light_source",
		"ambient_light_color",
		"ambient_light_energy",
		"reflected_light_source",
		"tonemap_mode",
		"tonemap_exposure",
		"tonemap_white",
		"glow_enabled",
		"glow_intensity",
		"glow_strength",
		"glow_bloom",
		"fog_enabled",
		"fog_light_color",
		"fog_density",
		"fog_height",
		"fog_height_density",
		"volumetric_fog_enabled",
		"volumetric_fog_density",
		"volumetric_fog_albedo",
		"ssao_enabled",
		"ssao_radius",
		"ssao_intensity",
		"ssil_enabled",
		"sdfgi_enabled",
		"adjustment_enabled",
		"adjustment_brightness",
		"adjustment_contrast",
		"adjustment_saturation",
		"adjustment_color_correction",
	]


static func environment_mutable_property_names() -> Array:
	return [
		"background_mode",
		"background_color",
		"background_energy_multiplier",
		"sky_custom_fov",
		"ambient_light_source",
		"ambient_light_color",
		"ambient_light_energy",
		"reflected_light_source",
		"tonemap_mode",
		"tonemap_exposure",
		"tonemap_white",
		"glow_enabled",
		"glow_intensity",
		"glow_strength",
		"glow_bloom",
		"fog_enabled",
		"fog_light_color",
		"fog_density",
		"fog_height",
		"fog_height_density",
		"volumetric_fog_enabled",
		"volumetric_fog_density",
		"volumetric_fog_albedo",
		"ssao_enabled",
		"ssao_radius",
		"ssao_intensity",
		"ssil_enabled",
		"sdfgi_enabled",
		"adjustment_enabled",
		"adjustment_brightness",
		"adjustment_contrast",
		"adjustment_saturation",
	]


static func validate_environment_mutable_property(property_name: String) -> Dictionary:
	if property_name == "" or property_name.find("\n") >= 0 or property_name.find("/") >= 0 or property_name.find("\\") >= 0:
		return _error_payload_static("invalid_environment_property", "Environment property is required and must be a simple property name.")
	if not property_name in environment_mutable_property_names():
		return _error_payload_static("unsupported_environment_property", "Environment property is not editable through set_environment_property V1: " + property_name)
	return {}


static func particle_node_payload(node: Node, scene_root: Node, stats: Dictionary, suggestions: Array) -> Dictionary:
	stats["particle_nodes"] = int(stats.get("particle_nodes", 0)) + 1
	var node_ref := EditorAssetImport.node_ref_payload(node, scene_root)
	var properties := object_named_properties_payload(node, [
		"visible",
		"emitting",
		"amount",
		"lifetime",
		"one_shot",
		"preprocess",
		"speed_scale",
		"explosiveness",
		"randomness",
		"fixed_fps",
		"fract_delta",
		"interpolate",
		"local_coords",
		"draw_order",
		"visibility_rect",
		"visibility_aabb",
	])
	var process_material: Variant = node.get("process_material") if not find_object_property_info(node, "process_material").is_empty() else null
	if process_material == null:
		stats["particles_without_process_material"] = int(stats.get("particles_without_process_material", 0)) + 1
		suggestions.append({
			"code": "particle_without_process_material",
			"severity": "warning",
			"node": node_ref,
			"message": "Particle node has no process_material assigned, so movement/emission behavior may be default or missing.",
		})
	var draw_passes := particle_draw_passes_payload(node)
	if node.get_class() == "GPUParticles3D" and draw_passes.is_empty():
		stats["gpu_particles_without_draw_pass"] = int(stats.get("gpu_particles_without_draw_pass", 0)) + 1
		suggestions.append({
			"code": "gpu_particles_3d_without_draw_pass",
			"severity": "warning",
			"node": node_ref,
			"message": "GPUParticles3D has no draw pass mesh, so particles may not be visible.",
		})
	return {
		"node": node_ref,
		"class": node.get_class(),
		"properties": properties,
		"process_material": VariantCodec.resource_reference(process_material),
		"draw_passes": draw_passes,
		"draw_pass_count": draw_passes.size(),
	}


static func append_initial_property_change(object: Object, property_name: String, new_value: Variant, changes: Array) -> void:
	if object == null or find_object_property_info(object, property_name).is_empty():
		return
	changes.append({
		"object": object,
		"property": property_name,
		"old_value": object.get(property_name),
		"new_value": new_value,
	})


static func add_object_property_change_to_undo(undo: EditorUndoRedoManager, change: Dictionary) -> void:
	var target := change.get("object") as Object
	if target == null:
		return
	var property_name := str(change.get("property", ""))
	undo.add_do_property(target, property_name, change.get("new_value"))
	undo.add_undo_property(target, property_name, change.get("old_value"))


static func object_named_properties_payload(object: Object, property_names: Array) -> Dictionary:
	var payload := {}
	for property_name_value in property_names:
		var property_name := str(property_name_value)
		if find_object_property_info(object, property_name).is_empty():
			continue
		payload[property_name] = json_value(object.get(property_name))
	return payload


static func particle_draw_passes_payload(node: Node) -> Array:
	var passes: Array = []
	if not node.has_method("get_draw_pass_count") or not node.has_method("get_draw_pass_mesh"):
		return passes
	var draw_pass_count := int(node.call("get_draw_pass_count"))
	var limit: int = min(draw_pass_count, BridgeLimits.MAX_MATERIALS_PER_MESH)
	for index in range(limit):
		var mesh: Variant = node.call("get_draw_pass_mesh", index)
		passes.append({
			"index": index,
			"mesh": VariantCodec.resource_reference(mesh),
			"mesh_missing": mesh == null,
		})
	return passes


static func find_object_property_info(object: Object, property_name: String) -> Dictionary:
	if object == null:
		return {}
	for property_info in object.get_property_list():
		if typeof(property_info) == TYPE_DICTIONARY and str((property_info as Dictionary).get("name", "")) == property_name:
			return property_info as Dictionary
	return {}


static func json_value(value: Variant) -> Variant:
	return VariantCodec.variant_to_json_value(value, 0, BridgeLimits.MAX_PROPERTY_DEPTH, BridgeLimits.MAX_ARRAY_ITEMS, BridgeLimits.MAX_DICTIONARY_ITEMS)


static func current_scene_payload(scene_root: Node) -> Dictionary:
	return {
		"path": scene_root.scene_file_path if scene_root != null else "",
		"root": EditorAssetImport.node_ref_payload(scene_root, scene_root) if scene_root != null else {},
	}


func resolve_editor_node(node_path: String) -> Dictionary:
	return EditorAssetImport.new(_context).resolve_editor_node(node_path)


func _permission_enabled(key: String) -> bool:
	return _context.permission_enabled(key) if _context != null else false


func _undo_redo() -> EditorUndoRedoManager:
	return _context.undo_redo if _context != null else null


func _refresh(reason: String) -> Dictionary:
	return _context.refresh(reason) if _context != null else {}


func _log(event_name: String, data: Dictionary) -> void:
	if _context != null:
		_context.log(event_name, data)


func _now() -> String:
	return _context.timestamp_iso() if _context != null else Time.get_datetime_string_from_system(true, true)


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
	return _error_payload_static(code, message)


static func _error_payload_static(code: String, message: String) -> Dictionary:
	return {
		"code": code,
		"message": message,
	}
