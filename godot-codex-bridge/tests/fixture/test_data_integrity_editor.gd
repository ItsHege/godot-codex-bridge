extends SceneTree

## DATA-01/DATA-02 editor fixture. Run in the (headless) editor:
##   Godot_console.exe --headless --editor --path examples/minimal_3d_project --script tests/fixture/test_data_integrity_editor.gd
## Uses scratch scenes under res://_bridge_data_integrity_tmp/ and removes them.

const TMP_DIR := "res://_bridge_data_integrity_tmp"
const OWNER_SCENE := TMP_DIR + "/owners.tscn"
const ANIM_SCENE := TMP_DIR + "/anim.tscn"
const MATERIAL := TMP_DIR + "/material.tres"
const SUB_SCENE := TMP_DIR + "/sub.tscn"
const INSTANCE_SCENE := TMP_DIR + "/instances.tscn"
const DIRTY_SCRIPT := TMP_DIR + "/dirty_script.gd"
const EditorUndo := preload("res://addons/godot_codex_bridge/core/editor_undo.gd")
const MOVER_POSITION := Vector3(1, 2, 3)
const MOVER_SCALE := Vector3(0.5, 0.5, 0.5)

var failures := 0
var _plugin: Node
var _request_counter := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await create_timer(2.0).timeout
	_plugin = _find_plugin(get_root())
	_check(_plugin != null, "Bridge plugin loaded")
	if _plugin == null:
		quit(1)
		return
	var permissions: Dictionary = _plugin.get("_permissions")
	permissions["allow_scene_edits"] = true
	permissions["allow_animation_preview"] = true
	permissions["allow_editor_inspect"] = true
	_write_fixture_files()
	EditorInterface.get_resource_filesystem().scan()
	await create_timer(1.0).timeout

	await _test_delete_undo_keeps_descendants()
	await _test_reparent_keeps_descendants()
	await _test_duplicate_keeps_descendants()
	await _test_undo_targets_latest_bridge_history()
	await _test_animation_preview_restores_pose()
	await _test_instance_ownership_guards()
	await _test_undo_ignores_dirty_script_editor()

	await _cleanup()
	print("DATA_INTEGRITY_RESULT=", JSON.stringify({"failures": failures}))
	quit(0 if failures == 0 else 1)


func _test_delete_undo_keeps_descendants() -> void:
	await _open(OWNER_SCENE)
	var result := _action("delete_node", {"node_path": "Parent"})
	_check(bool(result.get("ok", false)), "delete_node succeeded")
	_check(_root().get_node_or_null("Parent") == null, "Parent removed")
	var undone := _action("undo_last_bridge_action", {})
	_check(bool(undone.get("ok", false)), "delete undone by undo_last_bridge_action: " + JSON.stringify(undone.get("error", {})))
	var root := _root()
	for path in ["Parent", "Parent/Child", "Parent/Child/Grandchild"]:
		var node := root.get_node_or_null(path)
		_check(node != null and node.owner == root, "owner restored after delete undo: " + path)
	_check(EditorInterface.save_scene() == OK, "scene saved after delete undo")
	_check_saved_paths(OWNER_SCENE, ["Parent", "Parent/Child", "Parent/Child/Grandchild", "Target", "Box"], "delete undo reload")


func _test_reparent_keeps_descendants() -> void:
	await _open(OWNER_SCENE)
	var result := _action("reparent_node", {"node_path": "Parent", "new_parent_path": "Target"})
	_check(bool(result.get("ok", false)), "reparent_node succeeded")
	var root := _root()
	for path in ["Target/Parent", "Target/Parent/Child", "Target/Parent/Child/Grandchild"]:
		var node := root.get_node_or_null(path)
		_check(node != null and node.owner == root, "owner kept after reparent: " + path)
	_check(EditorInterface.save_scene() == OK, "scene saved after reparent")
	_check_saved_paths(OWNER_SCENE, ["Target/Parent", "Target/Parent/Child", "Target/Parent/Child/Grandchild"], "reparent reload")
	await _open(OWNER_SCENE)
	result = _action("reparent_node", {"node_path": "Target/Parent", "new_parent_path": "."})
	_check(bool(result.get("ok", false)), "reparent back succeeded")
	var undone := _action("undo_last_bridge_action", {})
	_check(bool(undone.get("ok", false)), "reparent undone: " + JSON.stringify(undone.get("error", {})))
	root = _root()
	for path in ["Target/Parent", "Target/Parent/Child", "Target/Parent/Child/Grandchild"]:
		var node := root.get_node_or_null(path)
		_check(node != null and node.owner == root, "owner restored after reparent undo: " + path)
	_check(EditorInterface.save_scene() == OK, "scene saved after reparent undo")
	_check_saved_paths(OWNER_SCENE, ["Target/Parent/Child/Grandchild"], "reparent undo reload")
	# Restore the original layout for the following tests.
	_action("reparent_node", {"node_path": "Target/Parent", "new_parent_path": "."})
	EditorInterface.save_scene()


func _test_duplicate_keeps_descendants() -> void:
	await _open(OWNER_SCENE)
	var result := _action("duplicate_node", {"node_path": "Parent", "name": "ParentCopy"})
	_check(bool(result.get("ok", false)), "duplicate_node succeeded")
	_check(EditorInterface.save_scene() == OK, "scene saved after duplicate")
	_check_saved_paths(OWNER_SCENE, ["ParentCopy", "ParentCopy/Child", "ParentCopy/Child/Grandchild", "Parent/Child/Grandchild"], "duplicate reload")
	await _open(OWNER_SCENE)
	_action("delete_node", {"node_path": "ParentCopy"})
	EditorInterface.save_scene()


func _test_undo_targets_latest_bridge_history() -> void:
	await _open(OWNER_SCENE)
	var root := _root()
	var target := root.get_node("Target") as Node3D
	var material := (root.get_node("Box") as MeshInstance3D).material_override as StandardMaterial3D
	var manager := EditorInterface.get_editor_undo_redo()
	_check(manager.get_object_history_id(material) == EditorUndoRedoManager.GLOBAL_HISTORY, "external .tres edits use the global history")

	# Bridge scene edit, then Bridge external .tres edit: undo must hit the .tres edit.
	_check(bool(_action("set_node_transform", {"node_path": "Target", "position": {"x": 7, "y": 0, "z": 0}}).get("ok", false)), "bridge scene edit")
	_check(bool(_action("set_resource_properties", {"node_path": "Box", "property": "material_override", "changes": [{"property": "roughness", "value": 0.25}]}).get("ok", false)), "bridge .tres edit")
	_check(is_equal_approx(material.roughness, 0.25) and target.position.x == 7.0, "both bridge edits applied")
	var first := _action("undo_last_bridge_action", {})
	_check(bool(first.get("ok", false)), "undo latest bridge action (.tres): " + JSON.stringify(first.get("error", {})))
	_check(is_equal_approx(material.roughness, 1.0), "external .tres edit undone")
	_check(target.position.x == 7.0, "older bridge scene edit left alone")
	var second := _action("undo_last_bridge_action", {})
	_check(bool(second.get("ok", false)), "next undo reaches bridge scene edit: " + JSON.stringify(second.get("error", {})))
	_check(target.position.x == 0.0, "bridge scene edit undone second")

	# Bridge .tres edit followed by a user scene edit: refuse, touch nothing.
	_check(bool(_action("set_resource_properties", {"node_path": "Box", "property": "material_override", "changes": [{"property": "roughness", "value": 0.5}]}).get("ok", false)), "bridge .tres edit before user edit")
	manager.create_action("User Move Target")
	manager.add_do_property(target, "position", Vector3(0, 9, 0))
	manager.add_undo_property(target, "position", target.position)
	manager.commit_action()
	var refused := _action("undo_last_bridge_action", {})
	_check(not bool(refused.get("ok", true)), "undo refused after user edit")
	_check(str((refused.get("error", {}) as Dictionary).get("code", "")) == "newer_editor_action", "refusal code newer_editor_action")
	_check(target.position.y == 9.0 and is_equal_approx(material.roughness, 0.5), "user edit and bridge edit both kept after refusal")

	# Bridge scene edit followed by a user .tres edit: refuse as well.
	_check(bool(_action("set_node_transform", {"node_path": "Target", "position": {"x": 3, "y": 0, "z": 0}}).get("ok", false)), "bridge scene edit before user .tres edit")
	manager.create_action("User Set Roughness")
	manager.add_do_property(material, "roughness", 0.75)
	manager.add_undo_property(material, "roughness", material.roughness)
	manager.commit_action()
	refused = _action("undo_last_bridge_action", {})
	_check(not bool(refused.get("ok", true)), "undo refused after user .tres edit")
	_check(target.position.x == 3.0 and is_equal_approx(material.roughness, 0.75), "nothing undone after refusal")
	material.roughness = 1.0
	ResourceSaver.save(material, MATERIAL)
	EditorInterface.save_scene()


func _test_animation_preview_restores_pose() -> void:
	await _open(ANIM_SCENE)
	var mover := _root().get_node("Mover") as Node3D
	var preview := _action("preview_animation", {"node_path": "AnimationPlayer", "animation_name": "move", "mode": "seek", "position": 1.0})
	_check(bool(preview.get("ok", false)), "preview_animation succeeded: " + JSON.stringify(preview.get("error", {})))
	_check(mover.position.is_equal_approx(Vector3(4, 0, 0)), "preview applied the animated pose: " + str(mover.position))
	# The MCP tool sends keep_state=true by default; the pose must still be restored.
	var stop := _action("stop_animation_preview", {"node_path": "AnimationPlayer", "keep_state": true})
	var stop_data: Dictionary = stop.get("data", {})
	_check(bool(stop.get("ok", false)) and bool(stop_data.get("pose_restored", false)) and not bool(stop_data.get("changed", true)), "stop reports restored pose truthfully: " + JSON.stringify(stop_data))
	_check(mover.position.is_equal_approx(MOVER_POSITION) and mover.scale.is_equal_approx(MOVER_SCALE), "original pose restored: " + str(mover.position) + " " + str(mover.scale))
	_check(EditorInterface.save_scene() == OK, "animation scene saved")
	var reloaded := _instantiate_saved(ANIM_SCENE)
	var saved_mover := reloaded.get_node_or_null("Mover") as Node3D if reloaded != null else null
	_check(saved_mover != null and saved_mover.position.is_equal_approx(MOVER_POSITION) and saved_mover.scale.is_equal_approx(MOVER_SCALE), "saved scene keeps original pose")
	if reloaded != null:
		reloaded.free()

	# A user/UndoRedo edit made during the preview must not be overwritten.
	preview = _action("preview_animation", {"node_path": "AnimationPlayer", "animation_name": "move", "mode": "seek", "position": 1.0})
	_check(bool(preview.get("ok", false)) and mover.scale.is_equal_approx(Vector3(3, 3, 3)), "second preview applied")
	var manager := EditorInterface.get_editor_undo_redo()
	manager.create_action("User Scale Mover")
	manager.add_do_property(mover, "scale", Vector3(2, 2, 2))
	manager.add_undo_property(mover, "scale", mover.scale)
	manager.commit_action()
	stop = _action("stop_animation_preview", {"node_path": "AnimationPlayer", "keep_state": true})
	stop_data = stop.get("data", {})
	_check(int(stop_data.get("restore_conflict_count", -1)) == 1 and int(stop_data.get("restored_property_count", -1)) == 1 and not bool(stop_data.get("pose_restored", true)), "stop reports the conflicting property: " + JSON.stringify(stop_data))
	_check(mover.scale.is_equal_approx(Vector3(2, 2, 2)), "user edit made during preview is kept: " + str(mover.scale))
	_check(mover.position.is_equal_approx(MOVER_POSITION), "untouched preview property still restored")


func _test_instance_ownership_guards() -> void:
	await _open(INSTANCE_SCENE)
	var root := _root()
	_check(root.is_editable_instance(root.get_node("Editable")) and not root.is_editable_instance(root.get_node("Locked")), "instance editable flags loaded")
	var denied := _action("delete_node", {"node_path": "Editable/Inner"})
	_check(_error_code(denied) == "foreign_scene_node", "delete of instance-owned node refused: " + JSON.stringify(denied.get("error", {})))
	denied = _action("reparent_node", {"node_path": "Locked/Inner", "new_parent_path": "."})
	_check(_error_code(denied) == "foreign_scene_node", "reparent of instance-owned node refused")
	denied = _action("reparent_node", {"node_path": "Loose", "new_parent_path": "Locked/Inner"})
	_check(_error_code(denied) == "parent_not_editable", "reparent into non-editable instance refused: " + JSON.stringify(denied.get("error", {})))
	_check(root.get_node_or_null("Editable/Inner/InnerChild") != null and root.get_node_or_null("Loose") != null, "refusals changed nothing")
	var copied := _action("duplicate_node", {"node_path": "Editable/Inner", "name": "InnerCopy"})
	_check(bool(copied.get("ok", false)), "duplicate inside editable instance succeeded: " + JSON.stringify(copied.get("error", {})))
	for path in ["Editable/InnerCopy", "Editable/InnerCopy/InnerChild"]:
		var node := root.get_node_or_null(path)
		_check(node != null and node.owner == root, "duplicated instance-internal node owned by scene: " + path)
	_check(EditorInterface.save_scene() == OK, "instance scene saved")
	_check_saved_paths(INSTANCE_SCENE, ["Editable/InnerCopy", "Editable/InnerCopy/InnerChild", "Loose"], "editable duplicate reload")
	var reloaded := _instantiate_saved(INSTANCE_SCENE)
	_check(reloaded != null and reloaded.get_node_or_null("Editable/Inner/InnerChild") != null and reloaded.get_node_or_null("Locked/Inner/InnerChild") != null, "instance internals intact after reload")
	if reloaded != null:
		reloaded.free()


func _test_undo_ignores_dirty_script_editor() -> void:
	await _open(OWNER_SCENE)
	var shortcut := EditorInterface.get_editor_settings().get_shortcut("ui_undo")
	var all_matches := []
	_collect_shortcut_items(EditorInterface.get_base_control(), shortcut, all_matches)
	var script := load(DIRTY_SCRIPT) as Script
	EditorInterface.edit_script(script)
	await create_timer(0.3).timeout
	var script_editor := EditorInterface.get_script_editor()
	var current := script_editor.get_current_editor() if script_editor != null else null
	var code_edit := current.get_base_editor() as CodeEdit if current != null else null
	_check(code_edit != null, "script editor CodeEdit available")
	if code_edit == null:
		return
	all_matches.clear()
	_collect_shortcut_items(EditorInterface.get_base_control(), shortcut, all_matches)
	_check(all_matches.size() >= 2, "ui_undo shortcut is shared by several menus: " + str(all_matches.size()))
	var main_item := EditorUndo.find_menu_item(EditorInterface.get_base_control(), shortcut)
	_check(not main_item.is_empty() and EditorUndo.is_main_menu_popup(main_item.get("menu")), "exactly one main-menu Undo item selected")
	var original_text := code_edit.text
	code_edit.set_caret_line(0)
	code_edit.set_caret_column(0)
	code_edit.insert_text_at_caret("# dirty-marker\n")
	_check(code_edit.text.begins_with("# dirty-marker"), "script text made dirty")
	var target := _root().get_node("Target") as Node3D
	var before := target.position
	_check(bool(_action("set_node_transform", {"node_path": "Target", "position": {"x": 11, "y": 0, "z": 0}}).get("ok", false)), "bridge edit with dirty script open")
	var undone := _action("undo_last_bridge_action", {})
	_check(bool(undone.get("ok", false)), "bridge edit undone with dirty script open: " + JSON.stringify(undone.get("error", {})))
	_check(target.position == before, "bridge edit reverted")
	_check(code_edit.text.begins_with("# dirty-marker"), "dirty script text survived Bridge undo")
	code_edit.text = original_text
	code_edit.tag_saved_version()


func _collect_shortcut_items(node: Node, shortcut: Shortcut, matches: Array) -> void:
	if node is PopupMenu:
		for index in range((node as PopupMenu).item_count):
			if (node as PopupMenu).get_item_shortcut(index) == shortcut:
				matches.append(str(node.get_path()))
	for child in node.get_children(true):
		_collect_shortcut_items(child, shortcut, matches)


func _error_code(result: Dictionary) -> String:
	return str((result.get("error", {}) as Dictionary).get("code", ""))


func _write_fixture_files() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))
	var material := StandardMaterial3D.new()
	material.roughness = 1.0
	ResourceSaver.save(material, MATERIAL)
	var root := Node3D.new()
	root.name = "OwnersRoot"
	var parent := _add(root, root, Node3D.new(), "Parent")
	var child := _add(parent, root, Node3D.new(), "Child")
	_add(child, root, Node3D.new(), "Grandchild")
	_add(root, root, Node3D.new(), "Target")
	var box := _add(root, root, MeshInstance3D.new(), "Box") as MeshInstance3D
	box.mesh = BoxMesh.new()
	box.material_override = load(MATERIAL)
	_save_scene(root, OWNER_SCENE)

	var anim_root := Node3D.new()
	anim_root.name = "AnimRoot"
	var mover := _add(anim_root, anim_root, Node3D.new(), "Mover") as Node3D
	mover.position = MOVER_POSITION
	mover.scale = MOVER_SCALE
	var player := _add(anim_root, anim_root, AnimationPlayer.new(), "AnimationPlayer") as AnimationPlayer
	var animation := Animation.new()
	animation.length = 1.0
	var position_track := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(position_track, NodePath("Mover"))
	animation.position_track_insert_key(position_track, 0.0, Vector3.ZERO)
	animation.position_track_insert_key(position_track, 1.0, Vector3(4, 0, 0))
	var scale_track := animation.add_track(Animation.TYPE_VALUE)
	animation.track_set_path(scale_track, NodePath("Mover:scale"))
	animation.track_insert_key(scale_track, 0.0, Vector3.ONE)
	animation.track_insert_key(scale_track, 1.0, Vector3(3, 3, 3))
	var library := AnimationLibrary.new()
	library.add_animation("move", animation)
	player.add_animation_library("", library)
	_save_scene(anim_root, ANIM_SCENE)

	var sub_root := Node3D.new()
	sub_root.name = "SubRoot"
	var inner := _add(sub_root, sub_root, Node3D.new(), "Inner")
	_add(inner, sub_root, Node3D.new(), "InnerChild")
	_save_scene(sub_root, SUB_SCENE)
	var sub := load(SUB_SCENE) as PackedScene
	var instances_root := Node3D.new()
	instances_root.name = "InstancesRoot"
	var editable := _add(instances_root, instances_root, sub.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE), "Editable")
	instances_root.set_editable_instance(editable, true)
	_add(instances_root, instances_root, sub.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE), "Locked")
	_add(instances_root, instances_root, Node3D.new(), "Loose")
	_save_scene(instances_root, INSTANCE_SCENE)

	var file := FileAccess.open(DIRTY_SCRIPT, FileAccess.WRITE)
	file.store_string("extends Node\n\nvar value := 1\n")
	file.close()


func _add(parent: Node, owner: Node, node: Node, node_name: String) -> Node:
	node.name = node_name
	parent.add_child(node)
	node.owner = owner
	return node


func _save_scene(root: Node, path: String) -> void:
	var packed := PackedScene.new()
	_check(packed.pack(root) == OK, "fixture scene packed: " + path)
	_check(ResourceSaver.save(packed, path) == OK, "fixture scene saved: " + path)
	root.free()


func _open(path: String) -> void:
	# Every test saves before reopening, so the open scene already matches disk.
	EditorInterface.open_scene_from_path(path)
	await create_timer(0.3).timeout
	var root := _root()
	_check(root != null and root.scene_file_path == path, "edited scene is " + path)


func _root() -> Node:
	return EditorInterface.get_edited_scene_root()


func _action(action: String, params: Dictionary) -> Dictionary:
	_request_counter += 1
	var control := _plugin.get("_editor_control") as Object
	return control.call("handle_request", "data-integrity-" + str(_request_counter), {"action": action, "params": params}) as Dictionary


func _instantiate_saved(path: String) -> Node:
	var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	return packed.instantiate() if packed != null else null


func _check_saved_paths(path: String, node_paths: Array, label: String) -> void:
	var reloaded := _instantiate_saved(path)
	_check(reloaded != null, label + ": saved scene loads")
	if reloaded == null:
		return
	for node_path in node_paths:
		var node := reloaded.get_node_or_null(str(node_path))
		_check(node != null and (node == reloaded or node.owner == reloaded), label + ": saved node present and owned: " + str(node_path))
	reloaded.free()


func _cleanup() -> void:
	# Close scratch scenes one at a time and let the Scene dock settle before
	# the next close and before files are removed.
	for scene_path in EditorInterface.get_open_scenes():
		if str(scene_path).begins_with(TMP_DIR):
			EditorInterface.open_scene_from_path(scene_path)
			await create_timer(0.2).timeout
			EditorInterface.close_scene()
			await create_timer(0.2).timeout
	for file_path in [OWNER_SCENE, ANIM_SCENE, INSTANCE_SCENE, SUB_SCENE, MATERIAL, DIRTY_SCRIPT]:
		for suffix in ["", ".uid"]:
			var absolute := ProjectSettings.globalize_path(file_path + suffix)
			if FileAccess.file_exists(absolute):
				DirAccess.remove_absolute(absolute)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_DIR))


func _find_plugin(node: Node) -> Node:
	var script := node.get_script() as Script
	if script != null and "godot_codex_bridge/plugin.gd" in script.resource_path:
		return node
	for child in node.get_children():
		var found := _find_plugin(child)
		if found != null:
			return found
	return null


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
	else:
		print("PASS ", label)
