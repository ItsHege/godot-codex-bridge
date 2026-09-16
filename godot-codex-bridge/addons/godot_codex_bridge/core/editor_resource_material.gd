@tool
extends RefCounted

const BridgeContext := preload("bridge_context.gd")
const BridgeLimits := preload("bridge_limits.gd")
const EditorPathGuard := preload("editor_path_guard.gd")
const ResourceLifecycleModel := preload("resource_lifecycle_model.gd")
const ShaderMaterialModel := preload("shader_material_model.gd")
const VariantCodec := preload("variant_codec.gd")

var _context: BridgeContext


func _init(context: BridgeContext = null) -> void:
	_context = context


func assign_resource_to_node(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_scene_edits"):
		return _err("permission_denied", "Scene edits via UndoRedo permission is disabled in the Codex Bridge dock.")

	var node_result := _resolve_editor_node(str(params.get("node_path", params.get("nodePath", ""))).strip_edges())
	if not node_result.get("ok", false):
		return node_result
	var node: Node = node_result.get("node", null)
	var scene_root: Node = node_result.get("scene_root", null)
	var property_name := str(params.get("property", "")).strip_edges()
	var property_result := ResourceLifecycleModel.validate_assignment_property(node, property_name)
	if not property_result.get("ok", false):
		return property_result

	var old_value: Variant = node.get(property_name)
	var new_value: Variant = null
	var clear_resource := bool(params.get("clear", false))
	var resource_path := ""
	if not clear_resource:
		resource_path = str(params.get("resource_path", params.get("resourcePath", ""))).strip_edges()
		var path_error := validate_res_path(resource_path, [], "resource", true)
		if not path_error.is_empty():
			return {"ok": false, "error": path_error}
		var loaded: Variant = ResourceLoader.load(resource_path)
		if not (loaded is Resource):
			return _err("invalid_resource", "Path did not load as a Resource: " + resource_path)
		new_value = loaded
		var compatibility_error := ResourceLifecycleModel.validate_matches_property(property_result.get("property_info", {}), old_value, new_value)
		if not compatibility_error.is_empty():
			return {"ok": false, "error": compatibility_error}

	var undo := _undo_redo()
	if undo == null:
		return _err("undo_redo_unavailable", "Editor UndoRedo manager is unavailable.")
	undo.create_action("Godot Codex Bridge: assign resource to node")
	undo.add_do_property(node, property_name, new_value)
	undo.add_undo_property(node, property_name, old_value)
	undo.commit_action()

	var snapshot := _refresh("editor_control:assign_resource_to_node")
	var data := {
		"changed": true,
		"undo_redo_action": true,
		"auto_saved": false,
		"node": node_ref_payload(node, scene_root),
		"property": property_name,
		"old_resource": resource_reference(old_value),
		"new_resource": resource_reference(new_value),
		"resource_path": resource_path if resource_path != "" else null,
		"cleared": clear_resource,
		"snapshot_refreshed": true,
		"generated_at": snapshot.get("generated_at", ""),
	}
	_log("editor_node_resource_assigned", data)
	return _ok(data)


func create_node_resource(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_scene_edits"):
		return _err("permission_denied", "Scene edits via UndoRedo permission is disabled in the Codex Bridge dock.")

	var node_result := _resolve_editor_node(str(params.get("node_path", params.get("nodePath", ""))).strip_edges())
	if not node_result.get("ok", false):
		return node_result
	var node: Node = node_result.get("node", null)
	var scene_root: Node = node_result.get("scene_root", null)
	var property_name := str(params.get("property", "")).strip_edges()
	var property_result := ResourceLifecycleModel.validate_assignment_property(node, property_name)
	if not property_result.get("ok", false):
		return property_result

	var resource_class := ResourceLifecycleModel.sanitize_resource_class_name(str(params.get("resource_class", params.get("resourceClass", ""))).strip_edges())
	if resource_class == "":
		return _err("invalid_resource_class", "resourceClass is required.")
	if not ClassDB.class_exists(resource_class) or not ClassDB.is_parent_class(resource_class, "Resource") or not ClassDB.can_instantiate(resource_class):
		return _err("unsupported_resource_class", "resourceClass must be an instantiable Godot Resource-derived class.")

	var resource_object: Object = ClassDB.instantiate(resource_class)
	if not (resource_object is Resource):
		return _err("resource_create_failed", "Could not instantiate resource class: " + resource_class)
	var resource := resource_object as Resource
	if resource.has_method("set"):
		resource.set("resource_local_to_scene", bool(params.get("local_to_scene", params.get("localToScene", true))))

	var old_value: Variant = node.get(property_name)
	var compatibility_error := ResourceLifecycleModel.validate_matches_property(property_result.get("property_info", {}), old_value, resource)
	if not compatibility_error.is_empty():
		return {"ok": false, "error": compatibility_error}

	var changes_result := ResourceLifecycleModel.prepare_property_changes(resource, params.get("changes", []), BridgeLimits.MAX_EDITOR_PROPERTY_CHANGES)
	if not changes_result.get("ok", false):
		return changes_result
	var prepared_changes: Array = changes_result.get("changes", [])

	var undo := _undo_redo()
	if undo == null:
		return _err("undo_redo_unavailable", "Editor UndoRedo manager is unavailable.")
	undo.create_action("Godot Codex Bridge: create node resource")
	for change in prepared_changes:
		var resource_property := str((change as Dictionary).get("property", ""))
		undo.add_do_property(resource, resource_property, (change as Dictionary).get("new_value"))
		undo.add_undo_property(resource, resource_property, (change as Dictionary).get("old_value"))
	undo.add_do_property(node, property_name, resource)
	undo.add_undo_property(node, property_name, old_value)
	undo.commit_action()

	var snapshot := _refresh("editor_control:create_node_resource")
	var data := {
		"changed": true,
		"undo_redo_action": true,
		"auto_saved": false,
		"node": node_ref_payload(node, scene_root),
		"property": property_name,
		"old_resource": resource_reference(old_value),
		"created_resource": resource_reference(resource),
		"resource_class": resource_class,
		"resource_changes": serialized_property_changes(prepared_changes),
		"snapshot_refreshed": true,
		"generated_at": snapshot.get("generated_at", ""),
	}
	_log("editor_node_resource_created", data)
	return _ok(data)


func set_resource_properties(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_scene_edits"):
		return _err("permission_denied", "Scene edits via UndoRedo permission is disabled in the Codex Bridge dock.")

	var node_result := _resolve_editor_node(str(params.get("node_path", params.get("nodePath", ""))).strip_edges())
	if not node_result.get("ok", false):
		return node_result
	var node: Node = node_result.get("node", null)
	var scene_root: Node = node_result.get("scene_root", null)
	var property_name := str(params.get("property", "")).strip_edges()
	var property_result := ResourceLifecycleModel.validate_assignment_property(node, property_name)
	if not property_result.get("ok", false):
		return property_result

	var resource_value: Variant = node.get(property_name)
	if not (resource_value is Resource):
		return _err("resource_missing", "Node property does not currently contain a Resource: " + property_name)
	var resource := resource_value as Resource
	var changes_result := ResourceLifecycleModel.prepare_property_changes(resource, params.get("changes", []), BridgeLimits.MAX_EDITOR_PROPERTY_CHANGES)
	if not changes_result.get("ok", false):
		return changes_result
	var prepared_changes: Array = changes_result.get("changes", [])
	if prepared_changes.is_empty():
		return _err("invalid_property_changes", "set_resource_properties requires at least one change.")

	var undo := _undo_redo()
	if undo == null:
		return _err("undo_redo_unavailable", "Editor UndoRedo manager is unavailable.")
	undo.create_action("Godot Codex Bridge: set resource properties")
	for change in prepared_changes:
		var resource_property := str((change as Dictionary).get("property", ""))
		undo.add_do_property(resource, resource_property, (change as Dictionary).get("new_value"))
		undo.add_undo_property(resource, resource_property, (change as Dictionary).get("old_value"))
	undo.commit_action()

	var snapshot := _refresh("editor_control:set_resource_properties")
	var data := {
		"changed": true,
		"undo_redo_action": true,
		"auto_saved": false,
		"node": node_ref_payload(node, scene_root),
		"property": property_name,
		"resource": resource_reference(resource),
		"resource_changes": serialized_property_changes(prepared_changes),
		"snapshot_refreshed": true,
		"generated_at": snapshot.get("generated_at", ""),
	}
	_log("editor_resource_properties_changed", data)
	return _ok(data)


func create_shader_material_for_node(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_scene_edits"):
		return _err("permission_denied", "Scene edits via UndoRedo permission is disabled in the Codex Bridge dock.")

	var node_result := _resolve_editor_node(str(params.get("node_path", params.get("nodePath", ""))).strip_edges())
	if not node_result.get("ok", false):
		return node_result
	var node: Node = node_result.get("node", null)
	var scene_root: Node = node_result.get("scene_root", null)
	var slot_kind := str(params.get("slot_kind", params.get("slotKind", "geometry_material_override"))).strip_edges()
	var surface_index := int(params.get("surface_index", params.get("surfaceIndex", -1)))
	var target_result := resolve_material_assignment_target(node, slot_kind, surface_index)
	if not target_result.get("ok", false):
		return target_result

	var shader_path := str(params.get("shader_path", params.get("shaderPath", ""))).strip_edges()
	var shader: Shader = null
	if shader_path != "":
		var path_error := validate_res_path(shader_path, [".gdshader", ".shader", ".tres", ".res"], "shader", true)
		if not path_error.is_empty():
			return {"ok": false, "error": path_error}
		var loaded: Variant = ResourceLoader.load(shader_path)
		if not (loaded is Shader):
			return _err("invalid_shader_resource", "shaderPath did not load as a Shader: " + shader_path)
		shader = loaded as Shader

	var shader_material := ShaderMaterial.new()
	shader_material.set("resource_local_to_scene", bool(params.get("local_to_scene", params.get("localToScene", true))))
	if shader != null:
		shader_material.shader = shader

	var prepared_parameters_result := ShaderMaterialModel.prepare_parameter_values(shader_material, shader, params.get("parameters", {}), BridgeLimits.MAX_EDITOR_PROPERTY_CHANGES)
	if not prepared_parameters_result.get("ok", false):
		return prepared_parameters_result
	var prepared_parameters: Array = prepared_parameters_result.get("parameters", [])
	for parameter_change in prepared_parameters:
		var parameter_dict := parameter_change as Dictionary
		shader_material.set_shader_parameter(StringName(str(parameter_dict.get("parameter", ""))), parameter_dict.get("new_value"))

	var old_material: Variant = target_result.get("old_material")
	var undo := _undo_redo()
	if undo == null:
		return _err("undo_redo_unavailable", "Editor UndoRedo manager is unavailable.")
	undo.create_action("Godot Codex Bridge: create shader material")
	add_material_assignment_undo(undo, node, target_result, shader_material, old_material)
	undo.commit_action()

	var snapshot := _refresh("editor_control:create_shader_material_for_node")
	var data := {
		"changed": true,
		"undo_redo_action": true,
		"auto_saved": false,
		"node": node_ref_payload(node, scene_root),
		"slot_kind": slot_kind,
		"surface_index": null if surface_index < 0 else surface_index,
		"slot_source": target_result.get("slot_source", ""),
		"old_material": resource_reference(old_material),
		"created_material": resource_reference(shader_material),
		"shader": resource_reference(shader),
		"shader_path": shader_path if shader_path != "" else null,
		"parameters": ShaderMaterialModel.serialized_parameter_changes(prepared_parameters, BridgeLimits.MAX_PROPERTY_DEPTH, BridgeLimits.MAX_ARRAY_ITEMS, BridgeLimits.MAX_DICTIONARY_ITEMS),
		"snapshot_refreshed": true,
		"generated_at": snapshot.get("generated_at", ""),
	}
	_log("editor_shader_material_created", data)
	return _ok(data)


func set_shader_parameter(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_scene_edits"):
		return _err("permission_denied", "Scene edits via UndoRedo permission is disabled in the Codex Bridge dock.")

	var node_result := _resolve_editor_node(str(params.get("node_path", params.get("nodePath", ""))).strip_edges())
	if not node_result.get("ok", false):
		return node_result
	var node: Node = node_result.get("node", null)
	var scene_root: Node = node_result.get("scene_root", null)
	var slot_kind := str(params.get("slot_kind", params.get("slotKind", "geometry_material_override"))).strip_edges()
	var surface_index := int(params.get("surface_index", params.get("surfaceIndex", -1)))
	var parameter_name := ShaderMaterialModel.sanitize_parameter_name(str(params.get("parameter", "")).strip_edges())
	if parameter_name == "":
		return _err("invalid_shader_parameter", "Shader parameter name is required and must not contain path separators or newlines.")
	if not params.has("value"):
		return _err("invalid_shader_parameter_value", "Shader parameter value is required.")

	var target_result := resolve_shader_material_target(node, slot_kind, surface_index)
	if not target_result.get("ok", false):
		return target_result
	var shader_material: ShaderMaterial = target_result.get("shader_material", null)
	var shader_value: Variant = shader_material.get("shader")
	var shader := shader_value as Shader
	if shader == null:
		return _err("shader_missing", "Target ShaderMaterial has no Shader assigned.")
	var uniform_result := ShaderMaterialModel.find_uniform_info(shader, parameter_name)
	if not uniform_result.get("ok", false):
		return uniform_result
	var uniform_info: Dictionary = uniform_result.get("uniform_info", {})
	var old_value: Variant = shader_material.get_shader_parameter(StringName(parameter_name))
	var coercion := ShaderMaterialModel.coerce_parameter_value(uniform_info, old_value, params.get("value"))
	if not coercion.get("ok", false):
		return coercion
	var new_value: Variant = coercion.get("value")
	var changed: bool = old_value != new_value
	if changed:
		var undo := _undo_redo()
		if undo == null:
			return _err("undo_redo_unavailable", "Editor UndoRedo manager is unavailable.")
		undo.create_action("Godot Codex Bridge: set shader parameter")
		undo.add_do_method(shader_material, "set_shader_parameter", StringName(parameter_name), new_value)
		undo.add_undo_method(shader_material, "set_shader_parameter", StringName(parameter_name), old_value)
		undo.commit_action()

	var snapshot: Dictionary = _refresh("editor_control:set_shader_parameter") if changed else {}
	var data := {
		"changed": changed,
		"undo_redo_action": changed,
		"auto_saved": false,
		"node": node_ref_payload(node, scene_root),
		"slot_kind": slot_kind,
		"surface_index": null if surface_index < 0 else surface_index,
		"slot_source": target_result.get("slot_source", ""),
		"material": resource_reference(shader_material),
		"shader": resource_reference(shader),
		"parameter": parameter_name,
		"uniform_type": type_string(int(uniform_info.get("type", TYPE_NIL))),
		"old_value": ShaderMaterialModel.uniform_value_payload(old_value, BridgeLimits.MAX_PROPERTY_DEPTH, BridgeLimits.MAX_ARRAY_ITEMS, BridgeLimits.MAX_DICTIONARY_ITEMS),
		"new_value": ShaderMaterialModel.uniform_value_payload(new_value, BridgeLimits.MAX_PROPERTY_DEPTH, BridgeLimits.MAX_ARRAY_ITEMS, BridgeLimits.MAX_DICTIONARY_ITEMS),
		"snapshot_refreshed": changed,
		"generated_at": snapshot.get("generated_at", "") if changed else "",
	}
	_log("editor_shader_parameter_changed", data)
	return _ok(data)


func set_shader_texture_parameter(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_scene_edits"):
		return _err("permission_denied", "Scene edits via UndoRedo permission is disabled in the Codex Bridge dock.")

	var node_result := _resolve_editor_node(str(params.get("node_path", params.get("nodePath", ""))).strip_edges())
	if not node_result.get("ok", false):
		return node_result
	var node: Node = node_result.get("node", null)
	var scene_root: Node = node_result.get("scene_root", null)
	var slot_kind := str(params.get("slot_kind", params.get("slotKind", "geometry_material_override"))).strip_edges()
	var surface_index := int(params.get("surface_index", params.get("surfaceIndex", -1)))
	var parameter_name := ShaderMaterialModel.sanitize_parameter_name(str(params.get("parameter", "")).strip_edges())
	if parameter_name == "":
		return _err("invalid_shader_parameter", "Shader texture parameter name is required and must not contain path separators or newlines.")

	var target_result := resolve_shader_material_target(node, slot_kind, surface_index)
	if not target_result.get("ok", false):
		return target_result
	var shader_material: ShaderMaterial = target_result.get("shader_material", null)
	var shader_value: Variant = shader_material.get("shader")
	var shader := shader_value as Shader
	if shader == null:
		return _err("shader_missing", "Target ShaderMaterial has no Shader assigned.")
	var uniform_result := ShaderMaterialModel.find_uniform_info(shader, parameter_name)
	if not uniform_result.get("ok", false):
		return uniform_result
	var uniform_info: Dictionary = uniform_result.get("uniform_info", {})
	var compatibility_error := ShaderMaterialModel.texture_uniform_error(uniform_info)
	if not compatibility_error.is_empty():
		return {"ok": false, "error": compatibility_error}

	var clear_texture := bool(params.get("clear", false))
	var texture_path := ""
	var new_value: Variant = null
	if not clear_texture:
		texture_path = str(params.get("texture_path", params.get("texturePath", ""))).strip_edges()
		var path_error := validate_res_path(texture_path, texture_resource_extensions(), "texture", true)
		if not path_error.is_empty():
			return {"ok": false, "error": path_error}
		var loaded: Variant = ResourceLoader.load(texture_path)
		if not (loaded is Texture2D):
			return _err("invalid_texture_resource", "texturePath did not load as a Texture2D: " + texture_path)
		new_value = loaded

	var old_value: Variant = shader_material.get_shader_parameter(StringName(parameter_name))
	var changed: bool = old_value != new_value
	if changed:
		var undo := _undo_redo()
		if undo == null:
			return _err("undo_redo_unavailable", "Editor UndoRedo manager is unavailable.")
		undo.create_action("Godot Codex Bridge: set shader texture parameter")
		undo.add_do_method(shader_material, "set_shader_parameter", StringName(parameter_name), new_value)
		undo.add_undo_method(shader_material, "set_shader_parameter", StringName(parameter_name), old_value)
		undo.commit_action()

	var snapshot: Dictionary = _refresh("editor_control:set_shader_texture_parameter") if changed else {}
	var data := {
		"changed": changed,
		"undo_redo_action": changed,
		"auto_saved": false,
		"node": node_ref_payload(node, scene_root),
		"slot_kind": slot_kind,
		"surface_index": null if surface_index < 0 else surface_index,
		"slot_source": target_result.get("slot_source", ""),
		"material": resource_reference(shader_material),
		"shader": resource_reference(shader),
		"parameter": parameter_name,
		"uniform_type": type_string(int(uniform_info.get("type", TYPE_NIL))),
		"old_texture": resource_reference(old_value),
		"new_texture": resource_reference(new_value),
		"texture_path": texture_path if texture_path != "" else null,
		"cleared": clear_texture,
		"snapshot_refreshed": changed,
		"generated_at": snapshot.get("generated_at", "") if changed else "",
	}
	_log("editor_shader_texture_parameter_changed", data)
	return _ok(data)


func resolve_shader_material_target(node: Node, slot_kind: String, surface_index: int) -> Dictionary:
	var material_value: Variant = null
	var slot_source := ""
	match slot_kind:
		"canvas_item_material":
			if not (node is CanvasItem):
				return _err("unsupported_material_slot", "canvas_item_material requires a CanvasItem node.")
			material_value = node.get("material")
			slot_source = "node.material"
		"geometry_material_override":
			if not (node is GeometryInstance3D):
				return _err("unsupported_material_slot", "geometry_material_override requires a GeometryInstance3D node.")
			material_value = node.get("material_override")
			slot_source = "node.material_override"
		"mesh_surface":
			if not (node is MeshInstance3D):
				return _err("unsupported_material_slot", "mesh_surface requires a MeshInstance3D node.")
			if surface_index < 0:
				return _err("invalid_surface_index", "surfaceIndex is required for mesh_surface shader parameters.")
			var mesh_instance := node as MeshInstance3D
			var mesh_value: Variant = mesh_instance.get("mesh")
			var mesh_resource := mesh_value as Mesh
			if mesh_resource == null:
				return _err("mesh_missing", "MeshInstance3D has no mesh, so surface materials cannot be resolved.")
			if surface_index >= mesh_resource.get_surface_count():
				return _err("invalid_surface_index", "surfaceIndex is outside the Mesh surface range.")
			var geometry_override: Variant = mesh_instance.get("material_override")
			var surface_override := mesh_instance.get_surface_override_material(surface_index)
			var mesh_surface := mesh_resource.surface_get_material(surface_index)
			material_value = mesh_instance.get_active_material(surface_index)
			if geometry_override != null:
				slot_source = "geometry_material_override"
			elif surface_override != null:
				slot_source = "surface_override"
			elif mesh_surface != null:
				slot_source = "mesh_surface"
			else:
				slot_source = "none"
		_:
			return _err("invalid_material_slot", "slotKind must be canvas_item_material, geometry_material_override or mesh_surface.")

	if material_value == null:
		return _err("material_missing", "Target material slot is empty.")
	if not (material_value is ShaderMaterial):
		var material_type := type_string(typeof(material_value))
		if material_value is Object:
			material_type = (material_value as Object).get_class()
		return _err("not_shader_material", "Target material is " + material_type + ", not ShaderMaterial.")
	return {
		"ok": true,
		"shader_material": material_value as ShaderMaterial,
		"slot_source": slot_source,
	}


func resolve_material_assignment_target(node: Node, slot_kind: String, surface_index: int) -> Dictionary:
	match slot_kind:
		"canvas_item_material":
			if not (node is CanvasItem):
				return _err("unsupported_material_slot", "canvas_item_material requires a CanvasItem node.")
			return {
				"ok": true,
				"slot_source": "node.material",
				"assignment_kind": "property",
				"property": "material",
				"old_material": node.get("material"),
			}
		"geometry_material_override":
			if not (node is GeometryInstance3D):
				return _err("unsupported_material_slot", "geometry_material_override requires a GeometryInstance3D node.")
			return {
				"ok": true,
				"slot_source": "node.material_override",
				"assignment_kind": "property",
				"property": "material_override",
				"old_material": node.get("material_override"),
			}
		"mesh_surface":
			if not (node is MeshInstance3D):
				return _err("unsupported_material_slot", "mesh_surface requires a MeshInstance3D node.")
			if surface_index < 0:
				return _err("invalid_surface_index", "surfaceIndex is required for mesh_surface material assignment.")
			var mesh_instance := node as MeshInstance3D
			var mesh_value: Variant = mesh_instance.get("mesh")
			var mesh_resource := mesh_value as Mesh
			if mesh_resource == null:
				return _err("mesh_missing", "MeshInstance3D has no mesh, so surface material override cannot be assigned.")
			if surface_index >= mesh_resource.get_surface_count():
				return _err("invalid_surface_index", "surfaceIndex is outside the Mesh surface range.")
			return {
				"ok": true,
				"slot_source": "surface_override",
				"assignment_kind": "surface_override",
				"surface_index": surface_index,
				"old_material": mesh_instance.get_surface_override_material(surface_index),
			}
		_:
			return _err("invalid_material_slot", "slotKind must be canvas_item_material, geometry_material_override or mesh_surface.")


static func add_material_assignment_undo(undo: EditorUndoRedoManager, node: Node, target: Dictionary, new_material: Material, old_material: Variant) -> void:
	var assignment_kind := str(target.get("assignment_kind", ""))
	if assignment_kind == "surface_override":
		var surface_index := int(target.get("surface_index", -1))
		undo.add_do_method(node, "set_surface_override_material", surface_index, new_material)
		undo.add_undo_method(node, "set_surface_override_material", surface_index, old_material)
	else:
		var property_name := str(target.get("property", ""))
		undo.add_do_property(node, property_name, new_material)
		undo.add_undo_property(node, property_name, old_material)


static func texture_resource_extensions() -> Array:
	return [
		".png",
		".jpg",
		".jpeg",
		".webp",
		".svg",
		".bmp",
		".tga",
		".exr",
		".hdr",
		".dds",
		".ktx",
		".ktx2",
		".tres",
		".res",
	]


static func validate_res_path(res_path: String, allowed_extensions: Array, kind: String, must_exist: bool) -> Dictionary:
	return EditorPathGuard.validate_res_path(res_path, allowed_extensions, kind, must_exist)


static func node_ref_payload(node: Node, scene_root: Node) -> Dictionary:
	return {
		"path": scene_path_for(node, scene_root),
		"name": node.name if node != null else "",
		"type": node.get_class() if node != null else "",
	}


static func scene_path_for(node: Node, scene_root: Node) -> String:
	if node == null:
		return ""
	if scene_root == null:
		return str(node.get_path())
	if node == scene_root:
		return "."
	return str(scene_root.get_path_to(node))


static func resource_reference(value: Variant) -> Variant:
	return VariantCodec.resource_reference(value)


static func serialized_property_changes(changes: Array) -> Array:
	var serialized: Array = []
	for change in changes:
		if typeof(change) != TYPE_DICTIONARY:
			continue
		var change_dict := change as Dictionary
		serialized.append({
			"property": change_dict.get("property", ""),
			"old_value": VariantCodec.variant_to_json_value(change_dict.get("old_value"), 0, BridgeLimits.MAX_PROPERTY_DEPTH, BridgeLimits.MAX_ARRAY_ITEMS, BridgeLimits.MAX_DICTIONARY_ITEMS),
			"new_value": VariantCodec.variant_to_json_value(change_dict.get("new_value"), 0, BridgeLimits.MAX_PROPERTY_DEPTH, BridgeLimits.MAX_ARRAY_ITEMS, BridgeLimits.MAX_DICTIONARY_ITEMS),
		})
	return serialized


func _resolve_editor_node(node_path: String) -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return _err("no_current_scene", "No edited scene is open.")
	if node_path == "" or node_path == ".":
		return {
			"ok": true,
			"node": scene_root,
			"scene_root": scene_root,
		}
	var path_error := EditorPathGuard.validate_scene_local_node_path(node_path)
	if not path_error.is_empty():
		return _err(str(path_error.get("code", "invalid_node_path")), str(path_error.get("message", "")))

	var node: Node = null
	if node_path.begins_with("/"):
		var tree := Engine.get_main_loop() as SceneTree
		if tree == null:
			return _err("scene_tree_unavailable", "Godot SceneTree is unavailable.")
		node = tree.root.get_node_or_null(NodePath(node_path))
	else:
		node = scene_root.get_node_or_null(NodePath(node_path))
	if node == null:
		return _err("node_not_found", "Node not found in the edited scene: " + node_path)
	if node != scene_root and not scene_root.is_ancestor_of(node):
		return _err("node_outside_scene", "Resolved node is outside the edited scene.")
	return {
		"ok": true,
		"node": node,
		"scene_root": scene_root,
	}


func _undo_redo() -> EditorUndoRedoManager:
	return _context.undo_redo if _context != null else null


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


func _error_payload(code: String, message: String) -> Dictionary:
	if _context != null:
		return _context.err(code, message)
	return _static_error_payload(code, message)


static func _static_error_payload(code: String, message: String) -> Dictionary:
	return {
		"code": code,
		"message": message,
	}
