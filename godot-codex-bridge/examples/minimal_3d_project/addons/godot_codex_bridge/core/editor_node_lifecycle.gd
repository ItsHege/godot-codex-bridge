@tool
extends RefCounted

const BridgeContext := preload("bridge_context.gd")
const EditorPathGuard := preload("editor_path_guard.gd")

var _context: BridgeContext


func _init(context: BridgeContext = null) -> void:
	_context = context


func create_node(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_scene_edits"):
		return _err("permission_denied", "Scene edits via UndoRedo permission is disabled in the Codex Bridge dock.")

	var parent_result := _resolve_editor_node(str(params.get("parent_path", params.get("parentPath", "."))).strip_edges())
	if not parent_result.get("ok", false):
		return parent_result
	var parent: Node = parent_result.get("node", null)
	var scene_root: Node = parent_result.get("scene_root", null)
	var node_class := sanitize_node_class_name(str(params.get("class_name", params.get("className", "Node"))).strip_edges())
	if node_class == "":
		return _err("invalid_node_class", "className is required.")
	if not ClassDB.class_exists(node_class) or not ClassDB.is_parent_class(node_class, "Node"):
		return _err("unsupported_node_class", "className must be a Godot Node-derived class.")

	var node_name := sanitize_node_name(str(params.get("name", node_class)).strip_edges(), node_class)
	if not is_valid_node_name(node_name):
		return _err("invalid_node_name", "Node name is empty or contains unsupported path separators.")

	var index := bounded_child_index(parent, int(params.get("index", -1)))
	var object: Object = ClassDB.instantiate(node_class)
	var node := object as Node
	if node == null:
		return _err("node_create_failed", "Could not instantiate node class: " + node_class)
	node.name = node_name

	var undo := _undo_redo()
	if undo == null:
		return _err("undo_redo_unavailable", "Editor UndoRedo manager is unavailable.")
	undo.create_action("Godot Codex Bridge: create node")
	undo.add_do_method(parent, "add_child", node)
	undo.add_do_method(parent, "move_child", node, index)
	undo.add_do_property(node, "owner", scene_root)
	undo.add_undo_property(node, "owner", null)
	undo.add_undo_method(parent, "remove_child", node)
	undo.commit_action()

	select_single_node(node)
	var snapshot := _refresh("editor_control:create_node")
	var data := {
		"changed": true,
		"undo_redo_action": true,
		"auto_saved": false,
		"created_node": node_ref_payload(node, scene_root),
		"parent": node_ref_payload(parent, scene_root),
		"class_name": node_class,
		"requested_name": node_name,
		"index": index,
		"snapshot_refreshed": true,
		"generated_at": snapshot.get("generated_at", ""),
	}
	_log("editor_node_created", data)
	return _ok(data)


func delete_node(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_scene_edits"):
		return _err("permission_denied", "Scene edits via UndoRedo permission is disabled in the Codex Bridge dock.")

	var node_result := _resolve_editor_node(str(params.get("node_path", params.get("nodePath", ""))).strip_edges())
	if not node_result.get("ok", false):
		return node_result
	var node: Node = node_result.get("node", null)
	var scene_root: Node = node_result.get("scene_root", null)
	if node == scene_root:
		return _err("unsupported_node_delete", "Deleting the edited scene root is not supported.")
	var parent := node.get_parent()
	if parent == null:
		return _err("node_has_no_parent", "Node has no parent and cannot be removed.")
	var index := node.get_index()
	var owner := node.owner
	var before := node_ref_payload(node, scene_root)

	var undo := _undo_redo()
	if undo == null:
		return _err("undo_redo_unavailable", "Editor UndoRedo manager is unavailable.")
	undo.create_action("Godot Codex Bridge: delete node")
	undo.add_do_property(node, "owner", null)
	undo.add_do_method(parent, "remove_child", node)
	undo.add_undo_method(parent, "add_child", node)
	undo.add_undo_method(parent, "move_child", node, index)
	undo.add_undo_property(node, "owner", owner)
	undo.commit_action()

	var selection := EditorInterface.get_selection()
	if selection != null:
		selection.clear()
	EditorInterface.edit_node(parent)
	var snapshot := _refresh("editor_control:delete_node")
	var data := {
		"changed": true,
		"undo_redo_action": true,
		"auto_saved": false,
		"deleted_node": before,
		"parent": node_ref_payload(parent, scene_root),
		"index": index,
		"snapshot_refreshed": true,
		"generated_at": snapshot.get("generated_at", ""),
	}
	_log("editor_node_deleted", data)
	return _ok(data)


func rename_node(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_scene_edits"):
		return _err("permission_denied", "Scene edits via UndoRedo permission is disabled in the Codex Bridge dock.")

	var node_result := _resolve_editor_node(str(params.get("node_path", params.get("nodePath", ""))).strip_edges())
	if not node_result.get("ok", false):
		return node_result
	var node: Node = node_result.get("node", null)
	var scene_root: Node = node_result.get("scene_root", null)
	var new_name := sanitize_node_name(str(params.get("new_name", params.get("newName", ""))).strip_edges(), "")
	if not is_valid_node_name(new_name):
		return _err("invalid_node_name", "newName is required and must not contain path separators.")
	var before := node_ref_payload(node, scene_root)
	var old_name := str(node.name)
	if old_name == new_name:
		return _ok({
			"changed": false,
			"node": before,
			"old_name": old_name,
			"new_name": new_name,
		})

	var undo := _undo_redo()
	if undo == null:
		return _err("undo_redo_unavailable", "Editor UndoRedo manager is unavailable.")
	undo.create_action("Godot Codex Bridge: rename node")
	undo.add_do_property(node, "name", new_name)
	undo.add_undo_property(node, "name", old_name)
	undo.commit_action()

	var snapshot := _refresh("editor_control:rename_node")
	var data := {
		"changed": true,
		"undo_redo_action": true,
		"auto_saved": false,
		"before": before,
		"after": node_ref_payload(node, scene_root),
		"old_name": old_name,
		"new_name": new_name,
		"snapshot_refreshed": true,
		"generated_at": snapshot.get("generated_at", ""),
	}
	_log("editor_node_renamed", data)
	return _ok(data)


func reparent_node(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_scene_edits"):
		return _err("permission_denied", "Scene edits via UndoRedo permission is disabled in the Codex Bridge dock.")

	var node_result := _resolve_editor_node(str(params.get("node_path", params.get("nodePath", ""))).strip_edges())
	if not node_result.get("ok", false):
		return node_result
	var new_parent_result := _resolve_editor_node(str(params.get("new_parent_path", params.get("newParentPath", ""))).strip_edges())
	if not new_parent_result.get("ok", false):
		return new_parent_result
	var node: Node = node_result.get("node", null)
	var scene_root: Node = node_result.get("scene_root", null)
	var new_parent: Node = new_parent_result.get("node", null)
	if node == scene_root:
		return _err("unsupported_node_reparent", "Reparenting the edited scene root is not supported.")
	if node == new_parent or node.is_ancestor_of(new_parent):
		return _err("invalid_reparent_target", "Cannot reparent a node under itself or one of its descendants.")
	var old_parent := node.get_parent()
	if old_parent == null:
		return _err("node_has_no_parent", "Node has no parent and cannot be reparented.")
	var old_index := node.get_index()
	var new_index := bounded_child_index(new_parent, int(params.get("index", -1)))
	var before := node_ref_payload(node, scene_root)
	var owner := node.owner

	var undo := _undo_redo()
	if undo == null:
		return _err("undo_redo_unavailable", "Editor UndoRedo manager is unavailable.")
	undo.create_action("Godot Codex Bridge: reparent node")
	undo.add_do_method(old_parent, "remove_child", node)
	undo.add_do_method(new_parent, "add_child", node)
	undo.add_do_method(new_parent, "move_child", node, new_index)
	undo.add_do_property(node, "owner", scene_root)
	undo.add_undo_method(new_parent, "remove_child", node)
	undo.add_undo_method(old_parent, "add_child", node)
	undo.add_undo_method(old_parent, "move_child", node, old_index)
	undo.add_undo_property(node, "owner", owner)
	undo.commit_action()

	select_single_node(node)
	var snapshot := _refresh("editor_control:reparent_node")
	var data := {
		"changed": true,
		"undo_redo_action": true,
		"auto_saved": false,
		"before": before,
		"after": node_ref_payload(node, scene_root),
		"old_parent": node_ref_payload(old_parent, scene_root),
		"new_parent": node_ref_payload(new_parent, scene_root),
		"old_index": old_index,
		"new_index": new_index,
		"snapshot_refreshed": true,
		"generated_at": snapshot.get("generated_at", ""),
	}
	_log("editor_node_reparented", data)
	return _ok(data)


func duplicate_node(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_scene_edits"):
		return _err("permission_denied", "Scene edits via UndoRedo permission is disabled in the Codex Bridge dock.")

	var node_result := _resolve_editor_node(str(params.get("node_path", params.get("nodePath", ""))).strip_edges())
	if not node_result.get("ok", false):
		return node_result
	var node: Node = node_result.get("node", null)
	var scene_root: Node = node_result.get("scene_root", null)
	if node == scene_root:
		return _err("unsupported_node_duplicate", "Duplicating the edited scene root is not supported.")
	var parent: Node = node.get_parent()
	var parent_path := str(params.get("parent_path", params.get("parentPath", ""))).strip_edges()
	if parent_path != "":
		var parent_result := _resolve_editor_node(parent_path)
		if not parent_result.get("ok", false):
			return parent_result
		parent = parent_result.get("node", null)
	if parent == null:
		return _err("node_has_no_parent", "Node has no parent and cannot be duplicated.")
	var duplicate: Node = node.duplicate()
	if duplicate == null:
		return _err("node_duplicate_failed", "Godot failed to duplicate node.")
	var requested_name := sanitize_node_name(str(params.get("name", "")).strip_edges(), "")
	if requested_name != "":
		if not is_valid_node_name(requested_name):
			return _err("invalid_node_name", "Duplicate name must not contain path separators.")
		duplicate.name = requested_name
	var index := bounded_child_index(parent, int(params.get("index", -1)))

	var undo := _undo_redo()
	if undo == null:
		return _err("undo_redo_unavailable", "Editor UndoRedo manager is unavailable.")
	undo.create_action("Godot Codex Bridge: duplicate node")
	undo.add_do_method(parent, "add_child", duplicate)
	undo.add_do_method(parent, "move_child", duplicate, index)
	undo.add_do_method(self, "_set_owner_recursive", duplicate, scene_root)
	undo.add_undo_method(parent, "remove_child", duplicate)
	undo.commit_action()

	select_single_node(duplicate)
	var snapshot := _refresh("editor_control:duplicate_node")
	var data := {
		"changed": true,
		"undo_redo_action": true,
		"auto_saved": false,
		"source_node": node_ref_payload(node, scene_root),
		"duplicated_node": node_ref_payload(duplicate, scene_root),
		"parent": node_ref_payload(parent, scene_root),
		"index": index,
		"snapshot_refreshed": true,
		"generated_at": snapshot.get("generated_at", ""),
	}
	_log("editor_node_duplicated", data)
	return _ok(data)


func instance_scene(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_scene_edits"):
		return _err("permission_denied", "Scene edits via UndoRedo permission is disabled in the Codex Bridge dock.")

	var scene_path := str(params.get("scene_path", params.get("scenePath", ""))).strip_edges()
	var path_error := validate_scene_path(scene_path)
	if not path_error.is_empty():
		return {"ok": false, "error": path_error}
	var parent_result := _resolve_editor_node(str(params.get("parent_path", params.get("parentPath", "."))).strip_edges())
	if not parent_result.get("ok", false):
		return parent_result
	var parent: Node = parent_result.get("node", null)
	var scene_root: Node = parent_result.get("scene_root", null)
	var packed: Variant = ResourceLoader.load(scene_path)
	if not (packed is PackedScene):
		return _err("invalid_packed_scene", "Resource is not a PackedScene: " + scene_path)
	var instance: Node = (packed as PackedScene).instantiate()
	if instance == null:
		return _err("scene_instance_failed", "Godot failed to instantiate scene: " + scene_path)
	var requested_name := sanitize_node_name(str(params.get("name", "")).strip_edges(), "")
	if requested_name != "":
		if not is_valid_node_name(requested_name):
			return _err("invalid_node_name", "Instance name must not contain path separators.")
		instance.name = requested_name
	var index := bounded_child_index(parent, int(params.get("index", -1)))

	var undo := _undo_redo()
	if undo == null:
		return _err("undo_redo_unavailable", "Editor UndoRedo manager is unavailable.")
	undo.create_action("Godot Codex Bridge: instance scene")
	undo.add_do_method(parent, "add_child", instance)
	undo.add_do_method(parent, "move_child", instance, index)
	undo.add_do_property(instance, "owner", scene_root)
	undo.add_undo_property(instance, "owner", null)
	undo.add_undo_method(parent, "remove_child", instance)
	undo.commit_action()

	select_single_node(instance)
	var snapshot := _refresh("editor_control:instance_scene")
	var data := {
		"changed": true,
		"undo_redo_action": true,
		"auto_saved": false,
		"instanced_scene": scene_path,
		"instance_node": node_ref_payload(instance, scene_root),
		"parent": node_ref_payload(parent, scene_root),
		"index": index,
		"snapshot_refreshed": true,
		"generated_at": snapshot.get("generated_at", ""),
	}
	_log("editor_scene_instanced", data)
	return _ok(data)


static func sanitize_node_class_name(value: String) -> String:
	var name := value.strip_edges()
	if name.length() > 160 or name.find("\n") >= 0 or name.find("\r") >= 0 or name.find("/") >= 0 or name.find("\\") >= 0:
		return ""
	return name


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


func validate_scene_path(scene_path: String) -> Dictionary:
	return EditorPathGuard.validate_scene_path(scene_path, true)


func select_single_node(node: Node) -> void:
	if node == null:
		return
	var selection := EditorInterface.get_selection()
	if selection != null:
		selection.clear()
		selection.add_node(node)
	EditorInterface.edit_node(node)


func _set_owner_recursive(node: Node, owner: Node) -> void:
	if node == null:
		return
	node.owner = owner
	for child in node.get_children():
		if child is Node:
			_set_owner_recursive(child, owner)


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
