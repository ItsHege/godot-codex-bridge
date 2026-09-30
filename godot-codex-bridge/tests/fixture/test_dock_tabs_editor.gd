extends SceneTree

## Headless editor check: switching the "Codex Tools" dock tabs never changes
## the dock's minimum size, and the Bridge tab has the Updates row.
##   Godot_console.exe --headless --editor --path examples/minimal_3d_project --script tests/fixture/test_dock_tabs_editor.gd

var failures := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await create_timer(2.0).timeout
	var plugin := _find_plugin(get_root())
	_check(plugin != null, "Bridge plugin loaded")
	if plugin == null:
		quit(1)
		return
	var tabs := plugin.get("_dock") as TabContainer
	_check(tabs != null and tabs.use_hidden_tabs_for_min_size, "dock uses hidden tabs for its minimum size")
	var sizes := []
	for tab in [0, 1, 0, 1]:
		tabs.current_tab = tab
		await process_frame
		await process_frame
		sizes.append(tabs.get_combined_minimum_size())
	var child_widths := []
	for child in tabs.get_children():
		if child is Control:
			child_widths.append([str(child.name), (child as Control).get_combined_minimum_size().x])
	print("DOCK_TAB_MIN_SIZES=", sizes, " CHILD_MIN_WIDTHS=", child_widths)
	for size in sizes:
		_check(size == sizes[0], "tab switch keeps dock minimum size: " + str(size) + " vs " + str(sizes[0]))
	_check(sizes[0].x <= 420.0, "dock minimum width stays reasonable: " + str(sizes[0].x))
	var panel := plugin.get("_addon_update_panel") as Control
	_check(panel != null and panel.is_inside_tree(), "Updates row present in the Bridge tab")
	if panel != null:
		var update_button := panel.get("update_button") as Button
		_check(update_button != null and update_button.disabled, "Update now disabled while no Host is paired")
	# Bridge tab: no empty/collapsed buttons, compact top, profile + folded details.
	tabs.current_tab = 0
	await process_frame
	await process_frame
	var bridge_tab := tabs.get_child(0) as Control
	var buttons: Array = []
	_collect_buttons(bridge_tab, buttons)
	_check(buttons.size() >= 4, "bridge tab buttons found: " + str(buttons.size()))
	for button in buttons:
		var b := button as Button
		if not b.is_visible_in_tree():
			continue
		_check(b.text.strip_edges() != "" or b.icon != null, "button has text or icon: " + str(b.get_path()))
		var text_width := b.get_theme_font("font").get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, b.get_theme_font_size("font_size")).x
		_check(b.size.x >= minf(text_width, 40.0), "button wide enough for its label: " + b.text + " " + str(b.size.x))
	_check(plugin.get("_dock_status_label") != null and str((plugin.get("_dock_status_label") as Label).text).contains("pending"), "compact status line shown")
	_check(_find_label_text(bridge_tab, "Godot Codex Bridge") == null, "no duplicate title label in the dock")
	var profile := plugin.get("_permission_profile_option") as OptionButton
	_check(profile != null and profile.is_visible_in_tree() and profile.item_count >= 6, "permission profile dropdown visible")
	var advanced := bridge_tab.find_child("AdvancedPermissions", true, false)
	_check(advanced != null and (bool(advanced.get("folded")) if "folded" in advanced else true), "advanced permissions folded by default")
	var checkboxes: Dictionary = plugin.get("_permission_checkboxes")
	_check(checkboxes.size() == 14, "all permission checkboxes still exist: " + str(checkboxes.size()))
	# Codex Chat tab: themed icons, compact rows, approval popup lifecycle.
	tabs.current_tab = 1
	await process_frame
	await process_frame
	var chat_tab := tabs.get_child(1) as Control
	var chat_buttons: Array = []
	_collect_buttons(chat_tab, chat_buttons)
	for button in chat_buttons:
		var b := button as Button
		if b.is_visible_in_tree():
			_check(b.text.strip_edges() != "" or b.icon != null, "chat button has text or icon: " + b.tooltip_text.left(40))
	var style: Dictionary = plugin.get("_dock_style")
	_check(bool(style.get("themed", false)), "dock style comes from the editor theme")
	_check((plugin.get("_chat_eye_button") as Button).icon != null and (plugin.get("_chat_eye_button") as Button).tooltip_text != "", "Eye is an icon button with a tooltip")
	_check(not (plugin.get("_chat_cancel_button") as Button).visible, "Stop hidden while idle/disconnected")
	var params := {"approval_id": "approval-fixture-1", "kind": "command_execution", "command": "git status", "cwd": "C:/Game", "nonce": "n", "safe_default": "manual_only", "approvable_by_chat": true}
	plugin.call("_show_chat_approval", params)
	await process_frame
	var popup := plugin.get("_approval_popup") as Window
	_check(popup != null and popup.visible, "approval popup opens by itself")
	_check(str(popup.get("title_label").text) == "Run command?", "popup title by kind")
	var bar := plugin.get("_chat_approval_title") as Label
	_check(bar.text.contains("Run command: git status") and not bar.text.contains("approval-fixture"), "dock bar is one readable line without the raw id")
	popup.hide()
	plugin.call("_show_chat_approval", params)
	await process_frame
	_check(not popup.visible, "same approval does not reopen by itself")
	plugin.call("_open_approval_review")
	_check(popup.visible, "Review reopens the popup")
	plugin.call("_clear_chat_approval", "Approval resolved: approved")
	await process_frame
	_check(not popup.visible and str(popup.get("approval_id")) == "", "popup closes when the approval is resolved")
	var request_id_before := int(plugin.get("_chat_request_id"))
	plugin.call("_on_approval_popup_decision", "approve")
	_check(int(plugin.get("_chat_request_id")) == request_id_before, "late popup click after resolution sends nothing")
	# Allow this session: button only for marked cards; auto-approvals coalesce.
	var marked := params.duplicate()
	marked["approval_id"] = "approval-fixture-2"
	marked["kind"] = "elicitation"
	marked["session_allow_tool"] = "godot.bridge_status"
	plugin.call("_show_chat_approval", marked)
	await process_frame
	var allow_dock := plugin.get("_chat_allow_session_button") as Button
	_check(allow_dock.visible and (popup.get("allow_session_tool_button") as Button).visible, "Allow this session shown for a marked card (dock + popup)")
	plugin.call("_clear_chat_approval", "done")
	plugin.call("_show_chat_approval", params.merged({"approval_id": "approval-fixture-3"}, true))
	await process_frame
	_check(not allow_dock.visible, "Allow this session hidden for other cards")
	plugin.call("_clear_chat_approval", "done")
	var view: Object = plugin.get("_chat_transcript_view")
	var before := int(view.call("message_count"))
	plugin.call("_handle_chat_event", "approval.auto_approved", {"tool": "godot.bridge_status", "thread_id": "th", "turn_id": "t1"})
	plugin.call("_handle_chat_event", "approval.auto_approved", {"tool": "godot.get_scene_tree", "thread_id": "th", "turn_id": "t1"})
	_check(int(view.call("message_count")) == before + 1, "consecutive auto-approvals share one line")
	var auto_body := plugin.get("_auto_approved_body") as RichTextLabel
	_check(auto_body != null and str(auto_body.get_meta("chat_full_text", "")).contains("godot.bridge_status, godot.get_scene_tree"), "auto-approved line lists both tools")
	plugin.call("_apply_chat_host_status_patch", {"session_allowed_tools": ["godot.bridge_status"]})
	var allow_row := plugin.get("_session_allow_row") as Control
	_check(allow_row.visible and str((plugin.get("_session_allow_label") as Label).text) == "Allowed this session: 1 tool", "allowed tools shown in Advanced")
	plugin.call("_apply_chat_host_status_patch", {"session_allowed_tools": []})
	_check(not allow_row.visible, "row hides when nothing is allowed")
	# Model preference: in-memory store so the real editor settings are untouched.
	var pref_script := load("res://addons/godot_codex_bridge/core/chat_model_preference_model.gd")
	var store := {}
	plugin.set("_model_preference", pref_script.new(store))
	var inventory := {"defaultModel": "gpt-6-astra", "models": [
		{"model": "gpt-6-astra", "displayName": "GPT 6 Astra", "isDefault": true, "supportedReasoningEfforts": [{"reasoningEffort": "high"}]},
		{"model": "gpt-6-mini", "displayName": "GPT 6 Mini", "supportedReasoningEfforts": [{"reasoningEffort": "low"}, {"reasoningEffort": "medium"}]},
	]}
	plugin.call("_update_runtime_model_options", inventory)
	_check(str(plugin.call("_selected_chat_model")) == "gpt-6-astra" and store.is_empty(), "no saved choice: Codex default selected, nothing saved")
	var model_option := plugin.get("_chat_model_option") as OptionButton
	var mini_index := -1
	for index in range(model_option.item_count):
		if str((model_option.get_item_metadata(index) as Dictionary).get("model", "")) == "gpt-6-mini":
			mini_index = index
	model_option.select(mini_index)
	model_option.item_selected.emit(mini_index)
	var reasoning_option := plugin.get("_chat_reasoning_option") as OptionButton
	for index in range(reasoning_option.item_count):
		if str((reasoning_option.get_item_metadata(index) as Dictionary).get("reasoningEffort", "")) == "low":
			reasoning_option.select(index)
			reasoning_option.item_selected.emit(index)
	_check(str(store.get("godot_codex_bridge/chat/last_model", "")) == "gpt-6-mini" and str(store.get("godot_codex_bridge/chat/last_reasoning_effort", "")) == "low", "explicit picks saved")
	model_option.select(0)
	plugin.call("_update_runtime_model_options", inventory)
	_check(str(plugin.call("_selected_chat_model")) == "gpt-6-mini" and str(plugin.call("_selected_chat_reasoning")) == "low", "saved model and effort restored on inventory")
	var badge := plugin.get("_chat_model_badge") as Button
	_check(badge != null and badge.is_visible_in_tree() and badge.text == "GPT 6 Mini · Low", "model badge visible in the composer row")
	store["godot_codex_bridge/chat/last_model"] = "gpt-5-retired"
	var messages_before := int(view.call("message_count"))
	plugin.call("_update_runtime_model_options", inventory)
	_check(str(plugin.call("_selected_chat_model")) == "gpt-6-astra" and int(view.call("message_count")) == messages_before + 1, "missing saved model: Codex default + one notice")
	plugin.call("_update_runtime_model_options", inventory)
	_check(int(view.call("message_count")) == messages_before + 1, "notice not repeated")
	_check(str(store.get("godot_codex_bridge/chat/last_model", "")) == "gpt-5-retired", "fallback did not overwrite the saved choice")
	# Eye Attach window: one toolbar, marker list, bottom bar, shortcuts.
	var annotation: Object = plugin.get("_annotation_controller")
	annotation.call("ensure_dialog")
	var eye := annotation.get("dialog") as Window
	var eye_canvas := annotation.get("canvas") as Control
	_check(eye != null and eye_canvas != null, "Eye Attach dialog built")
	var image := Image.create(320, 200, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.8, 0.8, 0.8))
	annotation.set("source", {"ok": true, "image": image, "capture_scope": "editor_window"})
	eye_canvas.call("set_source_image", image)
	var attach := annotation.get("attach_button") as Button
	_check(attach.disabled and attach.text == "Attach", "Attach disabled with no markers")
	for index in range(2):
		(eye_canvas.get("markers") as Array).append({"id": "X", "label": "X", "type": "pin", "color": "#ff00ff", "points": [{"x": 10 + index, "y": 10}]})
	eye_canvas.call("relabel_markers")
	annotation.call("update_status")
	_check(not attach.disabled and attach.text == "Attach 2 markers", "Attach shows the marker count")
	_check((annotation.get("marker_list") as Container).get_child_count() == 2, "marker list shows A and B")
	_check(str((annotation.get("status_label") as Label).text).begins_with("320×200 · 2 markers"), "compact status line")
	var tool_buttons: Dictionary = annotation.get("tool_buttons")
	_check(tool_buttons.size() == 5 and (tool_buttons["rectangle"] as Button).button_pressed and (tool_buttons["pin"] as Button).icon != null, "tool toggle group with icons")
	(tool_buttons["arrow"] as Button).pressed.emit()
	_check(str(annotation.call("selected_tool")) == "arrow" and str(eye_canvas.get("active_tool")) == "arrow", "tool toggle selects the canvas tool")
	annotation.set("_selected_marker", 0)
	var del := InputEventKey.new()
	del.keycode = KEY_DELETE
	del.pressed = true
	annotation.call("_on_dialog_input", del)
	_check(int(eye_canvas.call("marker_count")) == 1 and str((eye_canvas.get("markers") as Array)[0].get("label")) == "A", "Del removes the selected marker and relabels")
	print("DOCK_TABS_RESULT=", JSON.stringify({"failures": failures}))
	quit(0 if failures == 0 else 1)


func _collect_buttons(node: Node, result: Array) -> void:
	if node is Button:
		result.append(node)
	for child in node.get_children():
		_collect_buttons(child, result)


func _find_label_text(node: Node, text: String) -> Label:
	if node is Label and (node as Label).text == text:
		return node as Label
	for child in node.get_children():
		var found := _find_label_text(child, text)
		if found != null:
			return found
	return null


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
