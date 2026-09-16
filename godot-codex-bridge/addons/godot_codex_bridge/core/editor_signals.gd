@tool
extends RefCounted

const BridgeContext := preload("bridge_context.gd")
const EditorPathGuard := preload("editor_path_guard.gd")
const VariantCodec := preload("variant_codec.gd")

var _context: BridgeContext


func _init(context: BridgeContext = null) -> void:
	_context = context


func list_signal_connections(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_editor_inspect"):
		return _err("permission_denied", "Inspect/select nodes permission is disabled in the Codex Bridge dock.")

	var node_result := _resolve_editor_node(str(params.get("node_path", params.get("nodePath", ""))).strip_edges())
	if not node_result.get("ok", false):
		return node_result
	var node: Node = node_result.get("node", null)
	var scene_root: Node = node_result.get("scene_root", null)
	var include_empty := bool(params.get("include_empty", params.get("includeEmpty", false)))
	var signals: Array = []
	for signal_info in node.get_signal_list():
		if typeof(signal_info) != TYPE_DICTIONARY:
			continue
		var signal_name := str((signal_info as Dictionary).get("name", ""))
		if signal_name == "":
			continue
		var connections := signal_connections_payload(node, signal_name, scene_root)
		if include_empty or not connections.is_empty():
			signals.append({
				"name": signal_name,
				"args": signal_args_payload((signal_info as Dictionary).get("args", [])),
				"connections": connections,
			})
	return _ok({
		"node": node_ref_payload(node, scene_root),
		"signals": signals,
		"snapshot_refreshed": false,
	})


func connect_signal(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_scene_edits"):
		return _err("permission_denied", "Scene edits via UndoRedo permission is disabled in the Codex Bridge dock.")

	var source_result := _resolve_editor_node(str(params.get("source_node_path", params.get("sourceNodePath", params.get("node_path", params.get("nodePath", ""))))).strip_edges())
	if not source_result.get("ok", false):
		return source_result
	var target_result := _resolve_editor_node(str(params.get("target_node_path", params.get("targetNodePath", ""))).strip_edges())
	if not target_result.get("ok", false):
		return target_result
	var source: Node = source_result.get("node", null)
	var target: Node = target_result.get("node", null)
	var scene_root: Node = source_result.get("scene_root", null)
	var signal_name := sanitize_identifier_name(str(params.get("signal_name", params.get("signalName", ""))).strip_edges(), "signal")
	var method_name := sanitize_identifier_name(str(params.get("method_name", params.get("methodName", ""))).strip_edges(), "method")
	if signal_name == "" or not source.has_signal(signal_name):
		return _err("signal_not_found", "Source node does not expose signal: " + signal_name)
	if method_name == "":
		return _err("invalid_method_name", "methodName is required.")
	var callable := Callable(target, method_name)
	if source.is_connected(signal_name, callable):
		return _ok({
			"changed": false,
			"connection": signal_connection_ref_payload(source, signal_name, target, method_name, scene_root),
			"already_connected": true,
		})

	var flags := int(params.get("flags", 0))
	var undo := _undo_redo()
	if undo == null:
		return _err("undo_redo_unavailable", "Editor UndoRedo manager is unavailable.")
	undo.create_action("Godot Codex Bridge: connect signal")
	undo.add_do_method(source, "connect", signal_name, callable, flags)
	undo.add_undo_method(source, "disconnect", signal_name, callable)
	undo.commit_action()

	var snapshot := _refresh("editor_control:connect_signal")
	var data := {
		"changed": true,
		"undo_redo_action": true,
		"auto_saved": false,
		"connection": signal_connection_ref_payload(source, signal_name, target, method_name, scene_root),
		"flags": flags,
		"snapshot_refreshed": true,
		"generated_at": snapshot.get("generated_at", ""),
	}
	_log("editor_signal_connected", data)
	return _ok(data)


func disconnect_signal(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_scene_edits"):
		return _err("permission_denied", "Scene edits via UndoRedo permission is disabled in the Codex Bridge dock.")

	var source_result := _resolve_editor_node(str(params.get("source_node_path", params.get("sourceNodePath", params.get("node_path", params.get("nodePath", ""))))).strip_edges())
	if not source_result.get("ok", false):
		return source_result
	var target_result := _resolve_editor_node(str(params.get("target_node_path", params.get("targetNodePath", ""))).strip_edges())
	if not target_result.get("ok", false):
		return target_result
	var source: Node = source_result.get("node", null)
	var target: Node = target_result.get("node", null)
	var scene_root: Node = source_result.get("scene_root", null)
	var signal_name := sanitize_identifier_name(str(params.get("signal_name", params.get("signalName", ""))).strip_edges(), "signal")
	var method_name := sanitize_identifier_name(str(params.get("method_name", params.get("methodName", ""))).strip_edges(), "method")
	var callable := Callable(target, method_name)
	if signal_name == "" or not source.has_signal(signal_name):
		return _err("signal_not_found", "Source node does not expose signal: " + signal_name)
	if method_name == "":
		return _err("invalid_method_name", "methodName is required.")
	if not source.is_connected(signal_name, callable):
		return _ok({
			"changed": false,
			"connection": signal_connection_ref_payload(source, signal_name, target, method_name, scene_root),
			"already_disconnected": true,
		})
	var flags := find_signal_connection_flags(source, signal_name, callable)

	var undo := _undo_redo()
	if undo == null:
		return _err("undo_redo_unavailable", "Editor UndoRedo manager is unavailable.")
	undo.create_action("Godot Codex Bridge: disconnect signal")
	undo.add_do_method(source, "disconnect", signal_name, callable)
	undo.add_undo_method(source, "connect", signal_name, callable, flags)
	undo.commit_action()

	var snapshot := _refresh("editor_control:disconnect_signal")
	var data := {
		"changed": true,
		"undo_redo_action": true,
		"auto_saved": false,
		"connection": signal_connection_ref_payload(source, signal_name, target, method_name, scene_root),
		"flags": flags,
		"snapshot_refreshed": true,
		"generated_at": snapshot.get("generated_at", ""),
	}
	_log("editor_signal_disconnected", data)
	return _ok(data)


static func sanitize_identifier_name(value: String, _kind: String) -> String:
	var name := value.strip_edges()
	if name.length() > 160 or name.find("\n") >= 0 or name.find("\r") >= 0 or name.find("/") >= 0:
		return ""
	return name


static func signal_args_payload(args_value: Variant) -> Array:
	var args: Array = []
	if typeof(args_value) != TYPE_ARRAY:
		return args
	for item in args_value as Array:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var item_dict := item as Dictionary
		args.append({
			"name": str(item_dict.get("name", "")),
			"type": type_string(int(item_dict.get("type", TYPE_NIL))),
			"default_value": VariantCodec.variant_to_json_value(item_dict.get("default_value", null), 0, 2, 12, 16),
		})
	return args


static func signal_connections_payload(node: Node, signal_name: String, scene_root: Node) -> Array:
	var connections: Array = []
	for item in node.get_signal_connection_list(signal_name):
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var item_dict := item as Dictionary
		var callable: Variant = item_dict.get("callable", null)
		connections.append({
			"signal": signal_name,
			"callable": callable_payload(callable, scene_root),
			"flags": int(item_dict.get("flags", 0)),
		})
	return connections


static func callable_payload(callable: Variant, scene_root: Node) -> Dictionary:
	if not (callable is Callable):
		return {
			"target_node": null,
			"method": "",
		}
	var typed_callable := callable as Callable
	var target := typed_callable.get_object()
	return {
		"target_node": node_ref_payload(target as Node, scene_root) if target is Node else null,
		"target_path": scene_path_for(target as Node, scene_root) if target is Node else null,
		"target_class": target.get_class() if target is Object else "",
		"method": typed_callable.get_method(),
	}


static func signal_connection_ref_payload(source: Node, signal_name: String, target: Node, method_name: String, scene_root: Node) -> Dictionary:
	return {
		"source": node_ref_payload(source, scene_root),
		"signal": signal_name,
		"target": node_ref_payload(target, scene_root),
		"method": method_name,
	}


static func find_signal_connection_flags(source: Node, signal_name: String, callable: Callable) -> int:
	for item in source.get_signal_connection_list(signal_name):
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var item_dict := item as Dictionary
		if item_dict.get("callable", Callable()) == callable:
			return int(item_dict.get("flags", 0))
	return 0


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
