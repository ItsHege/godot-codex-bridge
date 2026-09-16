@tool
extends RefCounted

const BridgeContext := preload("bridge_context.gd")
const BridgeLimits := preload("bridge_limits.gd")
const EditorPathGuard := preload("editor_path_guard.gd")
const ResourceLifecycleModel := preload("resource_lifecycle_model.gd")
const VariantCodec := preload("variant_codec.gd")

var _context: BridgeContext


func _init(context: BridgeContext = null) -> void:
	_context = context


func set_node_transform(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_scene_edits"):
		return _err("permission_denied", "Scene edits via UndoRedo permission is disabled in the Codex Bridge dock.")

	var node_result := _resolve_editor_node(str(params.get("node_path", params.get("nodePath", ""))).strip_edges())
	if not node_result.get("ok", false):
		return node_result
	var node: Node = node_result.get("node", null)
	var scene_root: Node = node_result.get("scene_root", null)
	if not (node is Node2D) and not (node is Node3D):
		return _err("unsupported_node_type", "set_node_transform supports only Node2D and Node3D.")

	var mode := str(params.get("mode", "absolute")).strip_edges()
	if mode != "absolute" and mode != "relative":
		return _err("invalid_transform_mode", "mode must be absolute or relative.")
	var space := str(params.get("space", "local")).strip_edges()
	if space != "local":
		return _err("unsupported_transform_space", "V1 supports only local transform edits.")

	var changes: Array = []
	var parse_result: Dictionary
	if payload_has_any(params, ["position"]):
		parse_result = VariantCodec.coerce_transform_value(node.get("position"), params.get("position"), "position", mode)
		if not parse_result.get("ok", false):
			return parse_result
		changes.append({"property": "position", "old_value": node.get("position"), "new_value": VariantCodec.coerced_value(parse_result)})
	if payload_has_any(params, ["rotation_degrees", "rotationDegrees"]):
		parse_result = VariantCodec.coerce_transform_value(node.get("rotation_degrees"), payload_get_any(params, ["rotation_degrees", "rotationDegrees"]), "rotation_degrees", mode)
		if not parse_result.get("ok", false):
			return parse_result
		changes.append({"property": "rotation_degrees", "old_value": node.get("rotation_degrees"), "new_value": VariantCodec.coerced_value(parse_result)})
	if payload_has_any(params, ["scale"]):
		parse_result = VariantCodec.coerce_transform_value(node.get("scale"), params.get("scale"), "scale", mode)
		if not parse_result.get("ok", false):
			return parse_result
		changes.append({"property": "scale", "old_value": node.get("scale"), "new_value": VariantCodec.coerced_value(parse_result)})

	if changes.is_empty():
		return _err("no_transform_changes", "Provide at least one transform field: position, rotationDegrees or scale.")

	var undo := _undo_redo()
	if undo == null:
		return _err("undo_redo_unavailable", "Editor UndoRedo manager is unavailable.")
	undo.create_action("Godot Codex Bridge: set node transform")
	for change in changes:
		var property_name := str(change.get("property", ""))
		undo.add_do_property(node, property_name, change.get("new_value"))
		undo.add_undo_property(node, property_name, change.get("old_value"))
	undo.commit_action()

	var snapshot := _refresh("editor_control:set_node_transform")
	var data := {
		"changed": true,
		"undo_redo_action": true,
		"auto_saved": false,
		"node": node_ref_payload(node, scene_root),
		"changes": serialized_property_changes(changes),
		"snapshot_refreshed": true,
		"generated_at": snapshot.get("generated_at", ""),
	}
	_log("editor_node_transform_changed", data)
	return _ok(data)


func set_node_properties(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_scene_edits"):
		return _err("permission_denied", "Scene edits via UndoRedo permission is disabled in the Codex Bridge dock.")

	var node_result := _resolve_editor_node(str(params.get("node_path", params.get("nodePath", ""))).strip_edges())
	if not node_result.get("ok", false):
		return node_result
	var node: Node = node_result.get("node", null)
	var scene_root: Node = node_result.get("scene_root", null)
	var changes_value: Variant = params.get("changes", [])
	if typeof(changes_value) != TYPE_ARRAY:
		return _err("invalid_property_changes", "changes must be an array.")
	var requested_changes: Array = changes_value
	if requested_changes.is_empty():
		return _err("invalid_property_changes", "changes cannot be empty.")
	if requested_changes.size() > BridgeLimits.MAX_EDITOR_PROPERTY_CHANGES:
		return _err("too_many_property_changes", "set_node_properties supports at most " + str(BridgeLimits.MAX_EDITOR_PROPERTY_CHANGES) + " changes per request.")

	var prepared_changes: Array = []
	for item in requested_changes:
		if typeof(item) != TYPE_DICTIONARY:
			return _err("invalid_property_change", "Each property change must be an object.")
		var change: Dictionary = item
		var property_name := str(change.get("property", "")).strip_edges()
		var property_error := ResourceLifecycleModel.validate_editor_property(node, property_name)
		if not property_error.is_empty():
			return {"ok": false, "error": property_error}
		var old_value: Variant = node.get(property_name)
		var coercion := VariantCodec.coerce_editor_property_value(old_value, change.get("value"))
		if not coercion.get("ok", false):
			return coercion
		prepared_changes.append({
			"property": property_name,
			"old_value": old_value,
			"new_value": VariantCodec.coerced_value(coercion),
		})

	var undo := _undo_redo()
	if undo == null:
		return _err("undo_redo_unavailable", "Editor UndoRedo manager is unavailable.")
	undo.create_action("Godot Codex Bridge: set node properties")
	for change in prepared_changes:
		var property_name := str(change.get("property", ""))
		undo.add_do_property(node, property_name, change.get("new_value"))
		undo.add_undo_property(node, property_name, change.get("old_value"))
	undo.commit_action()

	var snapshot := _refresh("editor_control:set_node_properties")
	var data := {
		"changed": true,
		"undo_redo_action": true,
		"auto_saved": false,
		"node": node_ref_payload(node, scene_root),
		"changes": serialized_property_changes(prepared_changes),
		"snapshot_refreshed": true,
		"generated_at": snapshot.get("generated_at", ""),
	}
	_log("editor_node_properties_changed", data)
	return _ok(data)


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
	return {
		"code": code,
		"message": message,
	}
