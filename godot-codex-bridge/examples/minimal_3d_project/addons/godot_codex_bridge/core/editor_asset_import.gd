@tool
extends RefCounted

const AssetImportModel := preload("asset_import_model.gd")
const BridgeContext := preload("bridge_context.gd")
const BridgeLimits := preload("bridge_limits.gd")
const EditorPathGuard := preload("editor_path_guard.gd")
const VariantCodec := preload("variant_codec.gd")

var _context: BridgeContext


func _init(context: BridgeContext = null) -> void:
	_context = context


func inspect_imported_assets(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_editor_diagnostics"):
		return _err("permission_denied", "Diagnostics capture permission is disabled in the Codex Bridge dock.")

	var root_path := str(params.get("root_path", params.get("rootPath", "res://"))).strip_edges()
	if root_path == "":
		root_path = "res://"
	var root_error := validate_res_dir_path(root_path)
	if not root_error.is_empty():
		return {"ok": false, "error": root_error}
	var extensions := extension_filter_array(params.get("extensions", []))
	if extensions.is_empty():
		extensions = AssetImportModel.default_import_asset_extensions()
	var type_filter := str(params.get("type", params.get("typeFilter", ""))).strip_edges()
	var invalid_only := bool(params.get("invalid_only", params.get("invalidOnly", false)))
	var placeable_only := bool(params.get("placeable_only", params.get("placeableOnly", false)))
	var include_dependencies := bool(params.get("include_dependencies", params.get("includeDependencies", false)))
	var limit := clampi(int(params.get("limit", BridgeLimits.MAX_IMPORTED_ASSETS)), 1, BridgeLimits.MAX_IMPORTED_ASSETS)

	var list_result := list_resources({
		"root_path": root_path,
		"extensions": extensions,
		"type": type_filter,
		"limit": limit,
	})
	if not list_result.get("ok", false):
		return list_result

	var list_data: Dictionary = list_result.get("data", {})
	var resources: Array = list_data.get("resources", [])
	var assets: Array = []
	var matched_count := 0
	var invalid_count := 0
	var placeable_count := 0
	for resource_value in resources:
		if typeof(resource_value) != TYPE_DICTIONARY:
			continue
		var resource := resource_value as Dictionary
		var file_path := str(resource.get("path", ""))
		var file_type := str(resource.get("type", ""))
		var import_valid := bool(resource.get("import_valid", true))
		var placeable_kind := AssetImportModel.placeable_kind(file_path, file_type)
		var placeable := placeable_kind != "unsupported"
		if invalid_only and import_valid:
			continue
		if placeable_only and not placeable:
			continue
		matched_count += 1
		if not import_valid:
			invalid_count += 1
		if placeable:
			placeable_count += 1
		assets.append(AssetImportModel.imported_asset_payload_from_resource(resource, include_dependencies, BridgeLimits.MAX_ASSET_DEPENDENCIES, BridgeLimits.MAX_STRING_LENGTH))

	var scan_status := str(list_data.get("scan_status", "complete"))
	if scan_status == "partial":
		scan_status = "scanning"
	return _ok({
		"captured_at": _now(),
		"scan_status": scan_status,
		"scan_progress": null,
		"root_path": root_path,
		"extensions": extensions,
		"type_filter": type_filter if type_filter != "" else null,
		"invalid_only": invalid_only,
		"placeable_only": placeable_only,
		"include_dependencies": include_dependencies,
		"assets": assets,
		"returned_count": assets.size(),
		"matched_count": matched_count,
		"visited_count": int(list_data.get("visited_count", 0)),
		"invalid_count": invalid_count,
		"placeable_count": placeable_count,
		"truncated": bool(list_data.get("truncated", false)),
		"limit": limit,
		"snapshot_refreshed": false,
	})


func list_resources(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_editor_diagnostics"):
		return _err("permission_denied", "Diagnostics capture permission is disabled in the Codex Bridge dock.")

	var resource_fs := EditorInterface.get_resource_filesystem()
	if resource_fs == null or resource_fs.get_filesystem() == null:
		return _ok({
			"scan_status": "unavailable",
			"resources": [],
			"returned_count": 0,
			"matched_count": 0,
			"truncated": false,
			"snapshot_refreshed": false,
		})

	var root_path := str(params.get("root_path", params.get("rootPath", "res://"))).strip_edges()
	if root_path == "":
		root_path = "res://"
	var root_error := validate_res_dir_path(root_path)
	if not root_error.is_empty():
		return {"ok": false, "error": root_error}
	var extensions := extension_filter_array(params.get("extensions", []))
	var type_filter := str(params.get("type", params.get("typeFilter", ""))).strip_edges()
	var limit := clampi(int(params.get("limit", 120)), 1, BridgeLimits.MAX_RESOURCES)
	var resources: Array = []
	var state := {
		"matched_count": 0,
		"visited_count": 0,
		"truncated": false,
	}
	collect_resource_listing(resource_fs.get_filesystem(), resources, state, root_path, extensions, type_filter, limit)
	return _ok({
		"captured_at": _now(),
		"scan_status": "partial" if resource_fs.is_scanning() else "complete",
		"root_path": root_path,
		"extensions": extensions,
		"type_filter": type_filter if type_filter != "" else null,
		"resources": resources,
		"returned_count": resources.size(),
		"matched_count": int(state.get("matched_count", 0)),
		"visited_count": int(state.get("visited_count", 0)),
		"truncated": bool(state.get("truncated", false)),
		"limit": limit,
		"snapshot_refreshed": false,
	})


func place_asset_in_scene(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_scene_edits"):
		return _err("permission_denied", "Scene edits via UndoRedo permission is disabled in the Codex Bridge dock.")

	var asset_path := str(params.get("asset_path", params.get("assetPath", ""))).strip_edges()
	var path_error := validate_placeable_asset_path(asset_path)
	if not path_error.is_empty():
		return {"ok": false, "error": path_error}
	var parent_result := resolve_editor_node(str(params.get("parent_path", params.get("parentPath", "."))).strip_edges())
	if not parent_result.get("ok", false):
		return parent_result
	var parent: Node = parent_result.get("node", null)
	var scene_root: Node = parent_result.get("scene_root", null)
	var loaded: Variant = ResourceLoader.load(asset_path)
	var placement_result := AssetImportModel.create_node_for_loaded_asset(asset_path, loaded)
	if not placement_result.get("ok", false):
		return placement_result
	var placed_node: Node = placement_result.get("node", null)
	var placement_kind := str(placement_result.get("placement_kind", ""))
	if placed_node == null:
		return _err("asset_place_failed", "Godot failed to create a node for asset: " + asset_path)
	var requested_name := sanitize_node_name(str(params.get("name", "")).strip_edges(), AssetImportModel.default_node_name(asset_path, placement_kind))
	if not is_valid_node_name(requested_name):
		return _err("invalid_node_name", "Placed asset name must not contain path separators.")
	placed_node.name = requested_name
	var index := bounded_child_index(parent, int(params.get("index", -1)))

	var transform_result := prepare_initial_transform_changes(placed_node, params)
	if not transform_result.get("ok", false):
		return transform_result
	var transform_changes: Array = transform_result.get("changes", [])
	var option_result := prepare_placement_options(placed_node, params)
	if not option_result.get("ok", false):
		return option_result
	var option_changes: Array = option_result.get("changes", [])
	var option_nodes: Array = option_result.get("nodes", [])

	var undo := _undo_redo()
	if undo == null:
		return _err("undo_redo_unavailable", "Editor UndoRedo manager is unavailable.")
	undo.create_action("Godot Codex Bridge: place asset in scene")
	undo.add_do_method(parent, "add_child", placed_node)
	undo.add_do_method(parent, "move_child", placed_node, index)
	undo.add_do_method(self, "set_owner_recursive", placed_node, scene_root)
	for option_node in option_nodes:
		if option_node is Node:
			undo.add_do_method(placed_node, "add_child", option_node)
			undo.add_do_method(self, "set_owner_recursive", option_node, scene_root)
	for change in transform_changes:
		var property_name := str((change as Dictionary).get("property", ""))
		undo.add_do_property(placed_node, property_name, (change as Dictionary).get("new_value"))
		undo.add_undo_property(placed_node, property_name, (change as Dictionary).get("old_value"))
	for change in option_changes:
		var target_node := (change as Dictionary).get("node", placed_node) as Object
		var property_name := str((change as Dictionary).get("property", ""))
		undo.add_do_property(target_node, property_name, (change as Dictionary).get("new_value"))
		undo.add_undo_property(target_node, property_name, (change as Dictionary).get("old_value"))
	for option_node in option_nodes:
		if option_node is Node:
			undo.add_undo_method(placed_node, "remove_child", option_node)
	undo.add_undo_method(parent, "remove_child", placed_node)
	undo.commit_action()

	if bool(params.get("select", true)):
		select_single_node(placed_node)
	var snapshot := _refresh("editor_control:place_asset_in_scene")
	var data := {
		"changed": true,
		"undo_redo_action": true,
		"auto_saved": false,
		"asset_path": asset_path,
		"asset": AssetImportModel.asset_metadata_for_loaded(asset_path, loaded),
		"placement_kind": placement_kind,
		"placed_node": node_ref_payload(placed_node, scene_root),
		"parent": node_ref_payload(parent, scene_root),
		"index": index,
		"transform_changes": serialized_property_changes(transform_changes),
		"placement_options": option_result.get("summary", {}),
		"snapshot_refreshed": true,
		"generated_at": snapshot.get("generated_at", ""),
	}
	_log("editor_asset_placed", data)
	return _ok(data)


static func validate_res_dir_path(res_path: String) -> Dictionary:
	return EditorPathGuard.validate_res_dir_path(res_path)


static func extension_filter_array(value: Variant) -> Array:
	var extensions: Array = []
	if typeof(value) != TYPE_ARRAY:
		return extensions
	for item in value as Array:
		var extension := str(item).strip_edges().to_lower()
		if extension == "":
			continue
		if not extension.begins_with("."):
			extension = "." + extension
		if extension.length() > 16 or extension.find("/") >= 0 or extension.find("\\") >= 0:
			continue
		if not extension in extensions:
			extensions.append(extension)
		if extensions.size() >= 24:
			break
	return extensions


static func collect_resource_listing(directory: EditorFileSystemDirectory, resources: Array, state: Dictionary, root_path: String, extensions: Array, type_filter: String, limit: int) -> void:
	for file_index in range(directory.get_file_count()):
		state["visited_count"] = int(state.get("visited_count", 0)) + 1
		var file_path := directory.get_file_path(file_index)
		var file_type := str(directory.get_file_type(file_index))
		if not resource_matches_filters(file_path, file_type, root_path, extensions, type_filter):
			continue
		state["matched_count"] = int(state.get("matched_count", 0)) + 1
		if resources.size() >= limit:
			state["truncated"] = true
			continue
		resources.append({
			"path": file_path,
			"type": file_type,
			"import_valid": directory.get_file_import_is_valid(file_index),
			"status": "ok" if directory.get_file_import_is_valid(file_index) else "import_error",
		})

	for subdir_index in range(directory.get_subdir_count()):
		collect_resource_listing(directory.get_subdir(subdir_index), resources, state, root_path, extensions, type_filter, limit)


static func resource_matches_filters(path_value: String, type_value: String, root_path: String, extensions: Array, type_filter: String) -> bool:
	var normalized_root := root_path
	if normalized_root != "res://" and normalized_root.ends_with("/"):
		normalized_root = normalized_root.substr(0, normalized_root.length() - 1)
	if normalized_root != "res://" and not path_value.begins_with(normalized_root + "/") and path_value != normalized_root:
		return false
	var lower_path := path_value.to_lower()
	if not extensions.is_empty():
		var extension_ok := false
		for extension in extensions:
			if lower_path.ends_with(str(extension)):
				extension_ok = true
				break
		if not extension_ok:
			return false
	if type_filter != "" and type_value.to_lower() != type_filter.to_lower():
		return false
	return true


static func validate_placeable_asset_path(asset_path: String) -> Dictionary:
	return validate_res_path(asset_path, AssetImportModel.placeable_asset_extensions(), "asset", true)


static func validate_res_path(res_path: String, allowed_extensions: Array, kind: String, must_exist: bool) -> Dictionary:
	return EditorPathGuard.validate_res_path(res_path, allowed_extensions, kind, must_exist)


static func sanitize_node_name(value: String, fallback: String) -> String:
	var name := value.strip_edges()
	if name == "":
		name = fallback.strip_edges()
	if name.length() > 96:
		name = name.substr(0, 96)
	return name


static func is_valid_node_name(value: String) -> bool:
	return value != "" and value.find("/") < 0 and value.find("\\") < 0 and value.find("\n") < 0 and value.find("\r") < 0


static func bounded_child_index(parent: Node, requested_index: int) -> int:
	if parent == null:
		return 0
	var child_count := parent.get_child_count()
	if requested_index < 0:
		return child_count
	return clampi(requested_index, 0, child_count)


static func set_owner_recursive(node: Node, owner: Node) -> void:
	if node == null:
		return
	node.owner = owner
	for child in node.get_children():
		if child is Node:
			set_owner_recursive(child, owner)


static func prepare_initial_transform_changes(node: Node, params: Dictionary) -> Dictionary:
	var has_transform := payload_has_any(params, ["position", "rotation_degrees", "rotationDegrees", "scale"])
	if not has_transform:
		return {"ok": true, "changes": []}
	if not (node is Node2D) and not (node is Node3D):
		return {
			"ok": false,
			"error": _error_payload_static("unsupported_node_type", "Initial transform is supported only for Node2D and Node3D placements."),
		}

	var changes: Array = []
	var parse_result: Dictionary
	if payload_has_any(params, ["position"]):
		parse_result = VariantCodec.coerce_transform_value(node.get("position"), params.get("position"), "position", "absolute")
		if not parse_result.get("ok", false):
			return parse_result
		changes.append({"property": "position", "old_value": node.get("position"), "new_value": VariantCodec.coerced_value(parse_result)})
	if payload_has_any(params, ["rotation_degrees", "rotationDegrees"]):
		parse_result = VariantCodec.coerce_transform_value(node.get("rotation_degrees"), payload_get_any(params, ["rotation_degrees", "rotationDegrees"]), "rotation_degrees", "absolute")
		if not parse_result.get("ok", false):
			return parse_result
		changes.append({"property": "rotation_degrees", "old_value": node.get("rotation_degrees"), "new_value": VariantCodec.coerced_value(parse_result)})
	if payload_has_any(params, ["scale"]):
		parse_result = VariantCodec.coerce_transform_value(node.get("scale"), params.get("scale"), "scale", "absolute")
		if not parse_result.get("ok", false):
			return parse_result
		changes.append({"property": "scale", "old_value": node.get("scale"), "new_value": VariantCodec.coerced_value(parse_result)})
	return {"ok": true, "changes": changes}


static func prepare_placement_options(node: Node, params: Dictionary) -> Dictionary:
	var summary := {
		"create_collider": {"requested": bool(params.get("create_collider", params.get("createCollider", false))), "status": "not_requested"},
		"material_color": {"requested": payload_has_any(params, ["material_color", "materialColor"]), "status": "not_requested"},
	}
	var changes: Array = []
	var nodes: Array = []

	if bool((summary.get("create_collider", {}) as Dictionary).get("requested", false)):
		var collider_result := collision_option_node(node)
		summary["create_collider"] = collider_result.get("summary", {})
		if bool(collider_result.get("created", false)):
			nodes.append(collider_result.get("node"))

	if bool((summary.get("material_color", {}) as Dictionary).get("requested", false)):
		var color_result := parse_color_payload(payload_get_any(params, ["material_color", "materialColor"]))
		if not color_result.get("ok", false):
			return color_result
		var material_result := material_color_change(node, color_result.get("color"))
		summary["material_color"] = material_result.get("summary", {})
		if bool(material_result.get("changed", false)):
			changes.append(material_result.get("change"))

	return {
		"ok": true,
		"changes": changes,
		"nodes": nodes,
		"summary": summary,
	}


static func collision_option_node(node: Node) -> Dictionary:
	if not (node is MeshInstance3D):
		return {
			"created": false,
			"summary": {"requested": true, "status": "skipped", "reason": "collider_supported_for_mesh_instance_3d_only"},
		}
	var mesh_instance := node as MeshInstance3D
	if mesh_instance.mesh == null:
		return {
			"created": false,
			"summary": {"requested": true, "status": "skipped", "reason": "mesh_instance_has_no_mesh"},
		}
	var bounds := mesh_instance.mesh.get_aabb()
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(bounds.size.x, 0.001), maxf(bounds.size.y, 0.001), maxf(bounds.size.z, 0.001))
	var body := StaticBody3D.new()
	body.name = "BridgeCollision"
	var collision_shape := CollisionShape3D.new()
	collision_shape.name = "BridgeCollisionShape"
	collision_shape.shape = shape
	collision_shape.position = bounds.position + bounds.size * 0.5
	body.add_child(collision_shape)
	return {
		"created": true,
		"node": body,
		"summary": {
			"requested": true,
			"status": "created",
			"kind": "static_body_box_shape",
			"size": VariantCodec.variant_to_json_value(shape.size, 0, BridgeLimits.MAX_PROPERTY_DEPTH, BridgeLimits.MAX_ARRAY_ITEMS, BridgeLimits.MAX_DICTIONARY_ITEMS),
		},
	}


static func material_color_change(node: Node, color: Color) -> Dictionary:
	if node is MeshInstance3D:
		var material := StandardMaterial3D.new()
		material.resource_name = "BridgePlacedMaterial"
		material.albedo_color = color
		return {
			"changed": true,
			"change": {"node": node, "property": "material_override", "old_value": (node as MeshInstance3D).material_override, "new_value": material},
			"summary": {"requested": true, "status": "applied", "target": "mesh_material_override"},
		}
	if node is CanvasItem:
		return {
			"changed": true,
			"change": {"node": node, "property": "modulate", "old_value": (node as CanvasItem).modulate, "new_value": color},
			"summary": {"requested": true, "status": "applied", "target": "canvas_item_modulate"},
		}
	return {
		"changed": false,
		"summary": {"requested": true, "status": "skipped", "reason": "material_color_supported_for_mesh_instance_3d_or_canvas_item_only"},
	}


static func parse_color_payload(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {
			"ok": false,
			"error": _error_payload_static("invalid_material_color", "materialColor must be an object with r/g/b/a or x/y/z/w numeric fields."),
		}
	var payload := value as Dictionary
	var r := float(payload.get("r", payload.get("x", 1.0)))
	var g := float(payload.get("g", payload.get("y", 1.0)))
	var b := float(payload.get("b", payload.get("z", 1.0)))
	var a := float(payload.get("a", payload.get("w", 1.0)))
	for component in [r, g, b, a]:
		if is_nan(component) or is_inf(component) or component < 0.0 or component > 1.0:
			return {
				"ok": false,
				"error": _error_payload_static("invalid_material_color", "materialColor components must be finite numbers from 0 to 1."),
			}
	return {"ok": true, "color": Color(r, g, b, a)}


static func payload_has_any(payload: Dictionary, keys: Array) -> bool:
	for key in keys:
		if payload.has(str(key)):
			return true
	return false


static func payload_get_any(payload: Dictionary, keys: Array) -> Variant:
	for key in keys:
		if payload.has(str(key)):
			return payload.get(str(key))
	return null


static func select_single_node(node: Node) -> void:
	if node == null:
		return
	var selection := EditorInterface.get_selection()
	if selection != null:
		selection.clear()
		selection.add_node(node)
	EditorInterface.edit_node(node)


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


func resolve_editor_node(node_path: String) -> Dictionary:
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
