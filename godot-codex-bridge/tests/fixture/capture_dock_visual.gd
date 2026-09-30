extends SceneTree

## VISIBLE editor capture of the Codex Tools dock for design review (not part of
## validate:addon-core). Opens a real editor window, fills the chat with sample
## messages and one approval, and writes PNGs to <product>/outputs/.
##   Godot_console.exe --editor --path examples/minimal_3d_project --script tests/fixture/capture_dock_visual.gd

const OUTPUT_PREFIX := "2026-09-30-dock-polish"

var failures := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await create_timer(4.0).timeout
	var plugin := _find_plugin(get_root())
	if plugin == null:
		push_error("Bridge plugin not loaded")
		quit(1)
		return
	var out_dir := ProjectSettings.globalize_path("res://").path_join("../../outputs").simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var tabs := plugin.get("_dock") as TabContainer

	tabs.current_tab = 0
	await _settle()
	_save(_region(tabs), out_dir.path_join(OUTPUT_PREFIX + "-bridge.png"))

	(plugin.get("_permissions") as Dictionary)["allow_codex_chat"] = true
	tabs.current_tab = 1
	var view: Object = plugin.get("_chat_transcript_view")
	view.call("append_status_message", "Trust Session cleared.")
	view.call("append_user_message", "Make the crate snap to the ground and check the scene for overlaps.")
	view.call("record_work_update", "Reading the scene tree.", "w1")
	view.call("record_work_update", "Checking placement with spatial_query.", "w1")
	view.call("append_assistant_delta", "I found **two** overlapping nodes. The crate floats `0.4 m` above the floor.\n\n```gdscript\n$Crate.position.y = 0.0\n```", "a1", "final_answer")
	view.call("flush_assistant_text")
	plugin.call("_show_chat_approval", {
		"approval_id": "approval-visual-1",
		"kind": "elicitation",
		"nonce": "n",
		"safe_default": "manual_only",
		"approvable_by_chat": true,
		"expires_at": "2026-09-30T18:00:00Z",
		"session_allow_tool": "godot.get_scene_tree",
		"raw_params": {"serverName": "godot", "mode": "form", "message": "Which scene should I edit? The crate exists in both.",
			"requestedSchema": {"type": "object", "required": ["scene"], "properties": {
				"scene": {"type": "string", "title": "Scene", "enum": ["main_3d.tscn", "test_3d.tscn"]},
				"confirm": {"type": "boolean", "title": "Also fix overlaps"},
			}}},
	})
	await _settle()
	_save(_region(tabs), out_dir.path_join(OUTPUT_PREFIX + "-chat.png"))
	var popup := plugin.get("_approval_popup") as Window
	if popup != null and popup.visible:
		await _settle()
		_save(popup.get_texture().get_image(), out_dir.path_join(OUTPUT_PREFIX + "-approval-popup.png"))
		popup.hide()
	plugin.call("_clear_chat_approval", "Approval capture finished.")
	print("DOCK_VISUAL_OUTPUT=", out_dir)
	quit(0 if failures == 0 else 1)


func _settle() -> void:
	for _i in range(6):
		await process_frame
	await create_timer(0.5).timeout


func _region(control: Control) -> Image:
	var image := get_root().get_texture().get_image()
	var rect := Rect2i(control.get_global_rect())
	rect = rect.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	return image.get_region(rect)


func _save(image: Image, path: String) -> void:
	if image == null or image.is_empty() or image.save_png(path) != OK:
		failures += 1
		push_error("capture failed: " + path)
	else:
		print("SAVED ", path, " ", image.get_size())


func _find_plugin(node: Node) -> Node:
	var script := node.get_script() as Script
	if script != null and "godot_codex_bridge/plugin.gd" in script.resource_path:
		return node
	for child in node.get_children():
		var found := _find_plugin(child)
		if found != null:
			return found
	return null
