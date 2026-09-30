extends SceneTree

## Repeatable README screenshots from the example fixture project only.
## Opens a VISIBLE editor window (no Host needed), stages sample UI state and
## writes PNGs to <workspace>/docs/images/. Run from godot-codex-bridge/:
##   Godot_console.exe --editor --path examples/minimal_3d_project --script tests/fixture/capture_readme_images.gd
## Staged "connected" button states are visual only; nothing is sent anywhere.

const MAX_BYTES := 600 * 1024
const BUILD_ID := "sha256:7c1e94d2a3b5f60819de2c4a7b3e5f6a9d0c1b2e3f4a5b6c7d8e9f0a1b2c3d4e"

var _plugin: Node
var _out_dir := ""
var _results: Array = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await create_timer(5.0).timeout
	_plugin = _find_plugin(get_root())
	if _plugin == null:
		push_error("Bridge plugin not loaded")
		quit(1)
		return
	_out_dir = ProjectSettings.globalize_path("res://").path_join("../../../docs/images").simplify_path()
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var permissions: Dictionary = _plugin.get("_permissions")
	for key in ["allow_codex_chat", "allow_ai_markers", "allow_screenshots", "allow_editor_inspect", "allow_scene_edits"]:
		permissions[key] = true

	EditorInterface.open_scene_from_path("res://scenes/main_3d.tscn")
	await create_timer(1.0).timeout
	EditorInterface.set_main_screen_editor("3D")
	var root := EditorInterface.get_edited_scene_root()
	var mesh := root.get_node_or_null("MeshInstance3D") if root != null else null
	if mesh != null:
		EditorInterface.get_selection().clear()
		EditorInterface.get_selection().add_node(mesh)
	# Freeze periodic UI refreshes so the staged state stays on screen.
	_plugin.set_process(false)
	_stage_build_label()
	_stage_conversation()
	_stage_models()
	var tabs := _plugin.get("_dock") as TabContainer
	tabs.current_tab = 1
	_stage_connected()
	await _settle(1.0)
	_save(_root_image(), "01_editor_codex_dock.png", 1600)

	_plugin.call("_set_chat_advanced_visible", true)
	_stage_connected()
	await _settle(0.6)
	_save(_region(tabs), "02_chat_controls_dock.png", 560)
	_plugin.call("_set_chat_advanced_visible", false)

	tabs.current_tab = 0
	_stage_updates_current()
	var advanced := tabs.get_child(0).find_child("AdvancedPermissions", true, false)
	if advanced != null and "folded" in advanced:
		advanced.set("folded", false)
	await _settle(0.6)
	_save(_region(tabs), "03_bridge_permissions.png", 560)

	tabs.current_tab = 1
	await _stage_approval_capture()

	await _stage_eye_attach_capture()

	_plugin.call("_clear_chat_approval", "Approval capture finished.")
	print("README_IMAGES=", JSON.stringify(_results))
	quit(0)


func _stage_build_label() -> void:
	_plugin.set("_gc_work_status", {"state": "current", "label": "GC-work · " + BUILD_ID.substr(7, 8), "tone": "ok", "tooltip": "GC-work is current."})
	_plugin.call("_apply_gc_work_status")


func _stage_conversation() -> void:
	_plugin.call("_clear_chat_transcript")
	var view: Object = _plugin.get("_chat_transcript_view")
	view.call("append_status_message", "Scene context attached: main_3d.tscn · 1 node selected.")
	view.call("append_user_message", "The crate in main_3d floats above the floor. Can you snap it to the ground?")
	view.call("record_work_update", "Reading the scene tree with godot.get_scene_tree.", "w1")
	view.call("record_work_update", "Checking placement with godot.spatial_query.", "w2")
	_plugin.call("_record_auto_approved", {"tool": "godot.get_scene_tree", "turn_id": "t1"})
	view.call("append_assistant_delta", "The **MeshInstance3D** sits `0.40 m` above the floor. I snapped it down with an undoable edit:\n\n```gdscript\n$MeshInstance3D.position.y = 0.5\n```\n\nSave the scene when you're happy with it.", "a1", "final_answer")
	view.call("flush_assistant_text")


func _stage_models() -> void:
	var pref_script := load("res://addons/godot_codex_bridge/core/chat_model_preference_model.gd")
	# In-memory store: never touch the real editor settings.
	_plugin.set("_model_preference", pref_script.new({}))
	_plugin.call("_update_runtime_model_options", {"defaultModel": "gpt-5-codex", "models": [
		{"model": "gpt-5-codex", "displayName": "GPT-5 Codex", "isDefault": true, "supportedReasoningEfforts": [{"reasoningEffort": "low"}, {"reasoningEffort": "medium"}, {"reasoningEffort": "high"}]},
		{"model": "gpt-5-codex-mini", "displayName": "GPT-5 Codex Mini", "supportedReasoningEfforts": [{"reasoningEffort": "low"}, {"reasoningEffort": "medium"}]},
	]})
	var reasoning := _plugin.get("_chat_reasoning_option") as OptionButton
	for index in range(reasoning.item_count):
		if str((reasoning.get_item_metadata(index) as Dictionary).get("reasoningEffort", "")) == "medium":
			reasoning.select(index)
	_plugin.call("_apply_chat_host_status_patch", {"session_allowed_tools": ["godot.bridge_status", "godot.get_scene_tree"]})


func _stage_connected() -> void:
	_plugin.call("_update_chat_ui")
	var status := _plugin.get("_chat_status_label") as Label
	status.text = "Ready"
	(_plugin.get("_chat_status_dot") as ColorRect).color = Color(0.36, 0.78, 0.40)
	(_plugin.get("_chat_connect_button") as Button).text = "Refresh"
	(_plugin.get("_chat_send_button") as Button).disabled = false
	(_plugin.get("_chat_cancel_button") as Button).visible = false
	var readiness := _plugin.get("_chat_readiness_label") as Label
	if readiness != null:
		readiness.text = "Tools: 24 Godot tools · Instructions: AGENTS.md"
	var thread := _plugin.get("_chat_thread_label") as Label
	if thread != null:
		thread.text = "Thread 3f2a"
	for name in ["_chat_approve_button", "_chat_reject_button", "_chat_allow_session_button"]:
		var button := _plugin.get(name) as Button
		if button != null:
			button.disabled = false


func _stage_updates_current() -> void:
	var update: Object = _plugin.get("_addon_update")
	update.call("set_local", {"channel": "GC-work", "build_id": BUILD_ID}, {"state": "current", "label": "GC-work · current", "tone": "ok"})
	_plugin.call("_apply_addon_update_view")


func _stage_approval_capture() -> void:
	_plugin.call("_show_chat_approval", {
		"approval_id": "approval-readme-1",
		"kind": "elicitation",
		"nonce": "readme",
		"safe_default": "manual_only",
		"approvable_by_chat": true,
		"expires_at": "2026-10-01T12:00:00Z",
		"session_allow_tool": "godot.get_scene_tree",
		"raw_params": {"serverName": "godot_codex_bridge", "mode": "form", "message": "Allow the godot_codex_bridge MCP server to run tool \"godot.get_scene_tree\"?"},
	})
	_stage_connected()
	var popup := _plugin.get("_approval_popup") as Window
	for name in ["approve_button", "reject_button", "revise_button", "allow_session_tool_button"]:
		var button := popup.get(name) as Button
		button.disabled = false
	(popup.get("allow_session_tool_button") as Button).visible = true
	await _settle(0.8)
	var editor := _root_image()
	var dialog := popup.get_texture().get_image()
	var position := (editor.get_size() - dialog.get_size()) / 2
	var frame := Image.create(dialog.get_width() + 4, dialog.get_height() + 4, false, editor.get_format())
	frame.fill(Color(0, 0, 0, 1))
	editor.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), position - Vector2i(2, 2))
	dialog.convert(editor.get_format())
	editor.blit_rect(dialog, Rect2i(Vector2i.ZERO, dialog.get_size()), position)
	_save(editor, "06_approval_popup.png", 1600)
	popup.hide()


func _stage_eye_attach_capture() -> void:
	var annotation: Object = _plugin.get("_annotation_controller")
	annotation.call("ensure_dialog")
	(annotation.get("scope_option") as OptionButton).select(1)
	annotation.call("open_eye_attach_dialog")
	await _settle(1.0)
	var canvas: Object = annotation.get("canvas")
	var image := canvas.get("source_image") as Image
	if image == null:
		push_error("Eye Attach capture failed")
		return
	var w := float(image.get_width())
	var h := float(image.get_height())
	var markers: Array = canvas.get("markers")
	# Rectangle around the crate, an arrow to its bottom edge, a pin on the top
	# face and a text label on the right face.
	markers.append({"type": "rectangle", "color": "#ff00ff", "points": [{"x": w * 0.13, "y": h * 0.23}, {"x": w * 0.81, "y": h * 0.87}]})
	markers.append({"type": "arrow", "color": "#ff00ff", "points": [{"x": w * 0.04, "y": h * 0.97}, {"x": w * 0.22, "y": h * 0.76}]})
	markers.append({"type": "pin", "color": "#ff00ff", "points": [{"x": w * 0.46, "y": h * 0.31}]})
	markers.append({"type": "text", "color": "#ff00ff", "points": [{"x": w * 0.70, "y": h * 0.52}]})
	canvas.call("relabel_markers")
	canvas.call("queue_redraw")
	annotation.call("update_status")
	await _settle(0.8)
	var dialog := annotation.get("dialog") as Window
	_save(dialog.get_texture().get_image(), "04_eye_attach_annotation.png", 1600)
	annotation.call("cancel_dialog")


func _settle(seconds: float) -> void:
	for _i in range(4):
		await process_frame
	await create_timer(seconds).timeout


func _root_image() -> Image:
	return get_root().get_texture().get_image()


func _region(control: Control) -> Image:
	var image := _root_image()
	var rect := Rect2i(control.get_global_rect()).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	return image.get_region(rect)


## Downscales to at most `max_width`, then further until the PNG is < 600 KB.
func _save(image: Image, file_name: String, max_width: int) -> void:
	var path := _out_dir.path_join(file_name)
	var working := image.duplicate() as Image
	working.convert(Image.FORMAT_RGB8)
	if working.get_width() > max_width:
		working.resize(max_width, int(round(working.get_height() * float(max_width) / working.get_width())), Image.INTERPOLATE_LANCZOS)
	var buffer := working.save_png_to_buffer()
	while buffer.size() > MAX_BYTES and working.get_width() > 400:
		working.resize(int(working.get_width() * 0.85), int(working.get_height() * 0.85), Image.INTERPOLATE_LANCZOS)
		buffer = working.save_png_to_buffer()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(buffer)
	file.close()
	_results.append({"file": file_name, "size": [working.get_width(), working.get_height()], "bytes": buffer.size()})
	print("SAVED ", file_name, " ", working.get_size(), " ", buffer.size())


func _find_plugin(node: Node) -> Node:
	var script := node.get_script() as Script
	if script != null and "godot_codex_bridge/plugin.gd" in script.resource_path:
		return node
	for child in node.get_children():
		var found := _find_plugin(child)
		if found != null:
			return found
	return null
