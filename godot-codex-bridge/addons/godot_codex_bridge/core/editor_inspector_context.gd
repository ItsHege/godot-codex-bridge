@tool
extends RefCounted

## Read-only Inspector context for editor_control `get_inspector_context`.
## Reports the edited object, selected property path and a bounded
## property-category summary (names only, never property values).

const BridgeContext := preload("bridge_context.gd")
const BridgeLimits := preload("bridge_limits.gd")
const VariantCodec := preload("variant_codec.gd")

const MAX_CATEGORIES := 32
const MAX_SAMPLE_PROPERTIES := 6
const TRANSFORM_PROPERTIES := ["position", "rotation", "rotation_degrees", "scale", "transform", "global_transform"]

var _context: BridgeContext


func _init(context: BridgeContext = null) -> void:
	_context = context


func get_inspector_context(_params: Dictionary = {}) -> Dictionary:
	if _context == null or not _context.permission_enabled("allow_editor_inspect"):
		return _err("permission_denied", "Inspect/select nodes permission is disabled in the Codex Bridge dock.")
	var inspector := EditorInterface.get_inspector()
	if inspector == null:
		return _err("inspector_unavailable", "Godot editor inspector is unavailable.")
	var selected_nodes := []
	var selection := EditorInterface.get_selection()
	if selection != null:
		selected_nodes = selection.get_selected_nodes()
	return {"ok": true, "data": context_payload(inspector.get_edited_object(), inspector.get_selected_path(), selected_nodes, EditorInterface.get_edited_scene_root())}


static func context_payload(edited_object: Object, selected_path: String, selected_nodes: Array, scene_root: Node) -> Dictionary:
	if edited_object == null and selected_nodes.size() == 1 and selected_nodes[0] is Node:
		edited_object = selected_nodes[0]
	return {
		"inspector": {
			"selected_path": selected_path,
			"visible_categories_supported": false,
			"visible_categories_unavailable_reason": "Godot EditorInspector exposes the edited object and selected property path, but not a stable API for reading current visible/folded Inspector category UI state.",
		},
		"edited_object": object_payload(edited_object, scene_root),
		"selected_nodes": selected_nodes_payload(selected_nodes, scene_root),
		"property_categories": property_categories(edited_object, MAX_CATEGORIES),
		"snapshot_refreshed": false,
	}


static func object_payload(edited_object: Object, scene_root: Node) -> Dictionary:
	if edited_object == null:
		return {"available": false}
	var payload := {
		"available": true,
		"class": edited_object.get_class(),
		"property_count": edited_object.get_property_list().size(),
	}
	if edited_object is Node:
		payload["kind"] = "node"
		payload["node"] = node_ref_payload(edited_object as Node, scene_root)
	elif edited_object is Resource:
		payload["kind"] = "resource"
		payload["resource_path"] = VariantCodec.resource_path_or_null(edited_object)
	else:
		payload["kind"] = "object"
	return payload


static func selected_nodes_payload(selected_nodes: Array, scene_root: Node) -> Array:
	var nodes: Array = []
	for item in selected_nodes.slice(0, BridgeLimits.MAX_SELECTED_NODES):
		if item is Node:
			nodes.append(node_ref_payload(item as Node, scene_root))
	return nodes


static func property_categories(edited_object: Object, limit: int) -> Array:
	if edited_object == null:
		return []
	var categories := {}
	var order: Array[String] = []
	for property_info in edited_object.get_property_list():
		if typeof(property_info) != TYPE_DICTIONARY:
			continue
		var property_name := str((property_info as Dictionary).get("name", "")).strip_edges()
		if property_name == "":
			continue
		var category := "Other"
		var slash_index := property_name.find("/")
		if slash_index > 0:
			category = property_name.substr(0, slash_index).capitalize()
		elif property_name in TRANSFORM_PROPERTIES:
			category = "Transform"
		elif property_name.begins_with("script"):
			category = "Script"
		if not categories.has(category):
			if order.size() >= limit:
				continue
			categories[category] = {"name": category, "property_count": 0, "sample_properties": []}
			order.append(category)
		var entry: Dictionary = categories[category]
		entry["property_count"] = int(entry.get("property_count", 0)) + 1
		var samples: Array = entry.get("sample_properties", [])
		if samples.size() < MAX_SAMPLE_PROPERTIES:
			samples.append(property_name)
	var result: Array = []
	for category_name in order:
		result.append(categories[category_name])
	return result


static func node_ref_payload(node: Node, scene_root: Node) -> Dictionary:
	var path := ""
	if scene_root != null and node == scene_root:
		path = "."
	elif scene_root != null and scene_root.is_ancestor_of(node):
		path = str(scene_root.get_path_to(node))
	elif node.is_inside_tree():
		path = str(node.get_path())
	return {"path": path, "name": str(node.name), "type": node.get_class()}


func _err(code: String, message: String) -> Dictionary:
	return {"ok": false, "error": _context.err(code, message) if _context != null else {"code": code, "message": message}}
