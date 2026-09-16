extends SceneTree

const ChatPanelView := preload("res://addons/godot_codex_bridge/core/chat_panel_view.gd")
const ChatStatusModel := preload("res://addons/godot_codex_bridge/core/chat_status_model.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge chat panel view tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge chat panel view tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var panel := ChatPanelView.create_panel()
	_assert_true(panel is VBoxContainer, "panel is VBoxContainer")
	_assert_eq(panel.custom_minimum_size.x, 220.0, "panel min width")
	_assert_eq(panel.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "panel expands horizontally")

	var panel_controls := ChatPanelView.create_panel_controls(ChatStatusModel.COLOR_BUSY)
	var assembled_panel := panel_controls.get("panel") as VBoxContainer
	var assembled_status := panel_controls.get("status", {}) as Dictionary
	var assembled_advanced := panel_controls.get("advanced_panel") as VBoxContainer
	var assembled_annotation := panel_controls.get("annotation", {}) as Dictionary
	var assembled_log := panel_controls.get("log", {}) as Dictionary
	var assembled_approval := panel_controls.get("approval", {}) as Dictionary
	var assembled_input := panel_controls.get("input", {}) as Dictionary
	var assembled_team := panel_controls.get("team", {}) as Dictionary
	_assert_true(assembled_panel is VBoxContainer, "assembled panel type")
	_assert_eq((assembled_status.get("status_dot") as ColorRect).color, ChatStatusModel.COLOR_BUSY, "assembled status color")
	_assert_eq((assembled_status.get("row") as HBoxContainer).get_parent(), assembled_panel, "assembled status row parent")
	_assert_eq(assembled_advanced.get_parent(), assembled_panel, "assembled advanced parent")
	_assert_eq(((panel_controls.get("meta", {}) as Dictionary).get("row") as HBoxContainer).get_parent(), assembled_advanced, "assembled meta parent")
	_assert_eq(((panel_controls.get("toolbar", {}) as Dictionary).get("row") as HBoxContainer).get_parent(), assembled_advanced, "assembled toolbar parent")
	_assert_eq(((panel_controls.get("runtime", {}) as Dictionary).get("row") as HBoxContainer).get_parent(), assembled_advanced, "assembled runtime parent")
	_assert_eq(((panel_controls.get("attachment", {}) as Dictionary).get("row") as HBoxContainer).get_parent(), assembled_advanced, "assembled attachment parent")
	_assert_eq(((assembled_team.get("row") as HBoxContainer).get_parent()), assembled_advanced, "assembled team row parent")
	_assert_eq(((assembled_team.get("status_label") as Label).get_parent()), assembled_advanced, "assembled team status parent")
	_assert_eq((assembled_annotation.get("row") as HBoxContainer).get_parent(), assembled_panel, "assembled annotation parent")
	_assert_eq((assembled_log.get("frame") as Control).get_parent(), assembled_panel, "assembled log parent")
	_assert_eq((assembled_approval.get("panel") as VBoxContainer).get_parent(), assembled_panel, "assembled approval parent")
	_assert_eq((assembled_input.get("row") as VBoxContainer).get_parent(), assembled_panel, "assembled input parent")
	_assert_eq(assembled_panel.get_child(2), assembled_annotation.get("row") as HBoxContainer, "assembled annotation order")
	_assert_eq(assembled_panel.get_child(3), assembled_log.get("frame") as Control, "assembled log order")
	_assert_eq(assembled_panel.get_child(4), assembled_approval.get("panel") as VBoxContainer, "assembled approval order")
	_assert_eq(assembled_panel.get_child(5), assembled_input.get("row") as VBoxContainer, "assembled input order")
	var refs := ChatPanelView.control_refs(panel_controls)
	_assert_eq(refs.get("panel"), assembled_panel, "refs panel")
	_assert_eq(refs.get("status_dot"), assembled_status.get("status_dot"), "refs status dot")
	_assert_eq(refs.get("advanced_panel"), assembled_advanced, "refs advanced panel")
	_assert_eq(refs.get("new_button"), (panel_controls.get("meta", {}) as Dictionary).get("new_button"), "refs new button")
	_assert_eq(refs.get("connect_button"), (panel_controls.get("status", {}) as Dictionary).get("connect_button"), "refs connect button")
	_assert_eq(refs.get("emergency_stop_button"), (panel_controls.get("toolbar", {}) as Dictionary).get("emergency_stop_button"), "refs emergency stop button")
	_assert_eq(refs.get("model_option"), (panel_controls.get("runtime", {}) as Dictionary).get("model_option"), "refs model option")
	_assert_eq(refs.get("input"), assembled_input.get("input"), "refs input")
	_assert_eq(refs.get("composer_toggle_button"), assembled_input.get("composer_toggle_button"), "refs composer toggle")
	_assert_eq(refs.get("attach_context"), (panel_controls.get("attachment", {}) as Dictionary).get("context"), "refs attach context")
	_assert_eq(refs.get("pending_annotation_label"), assembled_annotation.get("pending_label"), "refs pending annotation")
	_assert_eq(refs.get("team_status_label"), assembled_team.get("status_label"), "refs team status")
	_assert_eq(refs.get("approve_session_button"), assembled_approval.get("approve_session_button"), "refs approve session")
	_assert_eq(refs.get("log_view"), assembled_log.get("scroll"), "refs log view")
	_assert_eq(refs.get("bottom_spacer"), assembled_log.get("bottom_spacer"), "refs bottom spacer")

	var dot := ChatPanelView.create_status_dot(ChatStatusModel.COLOR_IDLE)
	_assert_eq(dot.custom_minimum_size, Vector2(10, 10), "status dot stable size")
	_assert_eq(dot.color, ChatStatusModel.COLOR_IDLE, "status dot color")

	var header_controls := ChatPanelView.create_status_header_controls(ChatStatusModel.COLOR_OK)
	var header_row := header_controls.get("row") as HBoxContainer
	var header_dot := header_controls.get("status_dot") as ColorRect
	var header_status := header_controls.get("status_label") as Label
	var header_connect := header_controls.get("connect_button") as Button
	var header_advanced := header_controls.get("advanced_toggle") as CheckButton
	_assert_true(header_row is HBoxContainer, "header row type")
	_assert_eq(header_dot.color, ChatStatusModel.COLOR_OK, "header dot color")
	_assert_eq(header_status.get_parent(), header_row, "header status parent")
	_assert_eq(header_connect.get_parent(), header_row, "header connect parent")
	_assert_eq(header_connect.text, "Connect", "header connect text")
	_assert_true(header_connect.visible, "header connect visible")
	_assert_eq(header_connect.focus_mode, Control.FOCUS_ALL, "header connect keyboard focus")
	_assert_eq(header_advanced.text, "Advanced", "header advanced text")
	_assert_eq(header_advanced.focus_mode, Control.FOCUS_ALL, "header advanced keyboard focus")

	var meta_controls := ChatPanelView.create_meta_controls()
	var meta_row := meta_controls.get("row") as HBoxContainer
	var readiness := meta_controls.get("readiness_label") as Label
	var thread := meta_controls.get("thread_label") as Label
	var new_button := meta_controls.get("new_button") as Button
	var clear_button := meta_controls.get("clear_button") as Button
	_assert_eq(readiness.get_parent(), meta_row, "readiness parent")
	_assert_eq(thread.custom_minimum_size.x, 76.0, "thread label min width")
	_assert_eq(new_button.text, "New", "new button text")
	_assert_eq(clear_button.text, "Clear", "clear button text")

	var working := ChatPanelView.create_working_label()
	_assert_eq(working.text, "Still working...", "working label text")
	_assert_false(working.visible, "working label hidden by default")

	var toolbar_controls := ChatPanelView.create_toolbar_controls()
	var toolbar_row := toolbar_controls.get("row") as HBoxContainer
	var cancel_button := toolbar_controls.get("cancel_button") as Button
	var emergency_stop_button := toolbar_controls.get("emergency_stop_button") as Button
	var enable_tools_button := toolbar_controls.get("enable_tools_button") as Button
	_assert_false(toolbar_controls.has("connect_button"), "advanced toolbar does not duplicate primary connect button")
	_assert_eq(cancel_button.get_parent(), toolbar_row, "cancel button parent")
	_assert_eq(cancel_button.text, "Cancel", "cancel button text")
	_assert_eq(emergency_stop_button.text, "Stop All", "emergency stop button text")
	_assert_true(emergency_stop_button.tooltip_text.contains("Emergency stop"), "emergency stop button tooltip")
	_assert_eq(enable_tools_button.text, "Enable Tools", "enable tools button text")

	var runtime_controls := ChatPanelView.create_runtime_controls()
	var runtime_row := runtime_controls.get("row") as HBoxContainer
	var model_option := runtime_controls.get("model_option") as OptionButton
	var reasoning_option := runtime_controls.get("reasoning_option") as OptionButton
	var trust_button := runtime_controls.get("trust_button") as CheckButton
	_assert_eq(model_option.get_parent(), runtime_row, "model option parent")
	_assert_eq(model_option.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "model option expands")
	_assert_eq(reasoning_option.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "reasoning option expands")
	_assert_eq(trust_button.text, "Trust Session", "trust button text")

	var attachment_controls := ChatPanelView.create_attachment_controls()
	var attachment_row := attachment_controls.get("row") as HBoxContainer
	var attach_context := attachment_controls.get("context") as CheckBox
	var attach_selected := attachment_controls.get("selected") as CheckBox
	var attach_screenshot := attachment_controls.get("screenshot") as CheckBox
	_assert_eq(attach_context.get_parent(), attachment_row, "attachment context parent")
	_assert_true(attach_context.button_pressed, "context attachment default on")
	_assert_true(attach_context.tooltip_text.contains("project"), "context attachment tooltip")
	_assert_true(attach_selected.button_pressed, "selected attachment default on")
	_assert_true(attach_selected.tooltip_text.contains("selected"), "selected attachment tooltip")
	_assert_false(attach_screenshot.button_pressed, "screenshot attachment default off")
	_assert_true(attach_screenshot.tooltip_text.contains("permission"), "screenshot attachment tooltip")

	var team_controls := ChatPanelView.create_team_controls()
	var team_row := team_controls.get("row") as HBoxContainer
	var team_review := team_controls.get("review_button") as Button
	var team_cancel := team_controls.get("cancel_button") as Button
	var team_status := team_controls.get("status_label") as Label
	_assert_eq(team_review.get_parent(), team_row, "team review parent")
	_assert_eq(team_review.text, "Team Review", "team review text")
	_assert_true(team_review.tooltip_text.contains("background"), "team review tooltip")
	_assert_eq(team_cancel.text, "Cancel Team", "team cancel text")
	_assert_true(team_cancel.tooltip_text.contains("Cancel"), "team cancel tooltip")
	_assert_eq(team_status.text, "Team: idle", "team status text")

	var input_controls := ChatPanelView.create_input_controls()
	var input_controls_row := input_controls.get("row") as VBoxContainer
	var input_buttons_row := input_controls.get("controls_row") as HBoxContainer
	var eye_button := input_controls.get("eye_button") as Button
	var input_box := input_controls.get("input") as TextEdit
	var send_button := input_controls.get("send_button") as Button
	var input_toggle := input_controls.get("composer_toggle_button") as Button
	_assert_eq(input_controls_row.custom_minimum_size.y, 294.0, "input controls row min height")
	_assert_eq(input_box.get_parent(), input_controls_row, "input box parent")
	_assert_eq(input_buttons_row.get_parent(), input_controls_row, "input buttons row parent")
	_assert_eq(eye_button.get_parent(), input_buttons_row, "eye button parent")
	_assert_eq(eye_button.text, "Eye", "eye button text")
	_assert_eq(eye_button.custom_minimum_size, Vector2(44, 32), "eye button stable size")
	_assert_true(eye_button.tooltip_text.contains("AI-safe marker"), "eye button tooltip")
	_assert_eq(send_button.get_parent(), input_buttons_row, "send button parent")
	_assert_eq(send_button.text, "Send", "send button text")
	_assert_eq(input_toggle.get_parent(), input_buttons_row, "input toggle parent")
	_assert_eq(input_toggle.text, "Expand", "input toggle text")

	var annotation_controls := ChatPanelView.create_annotation_controls()
	var annotation_row := annotation_controls.get("row") as HBoxContainer
	var pending_label := annotation_controls.get("pending_label") as Label
	var clear_annotation := annotation_controls.get("clear_button") as Button
	_assert_eq(pending_label.get_parent(), annotation_row, "pending annotation parent")
	_assert_false(pending_label.visible, "pending annotation hidden")
	_assert_eq(clear_annotation.text, "x", "clear annotation button text")
	_assert_false(clear_annotation.visible, "clear annotation hidden")

	var label := ChatPanelView.create_clip_label("Ready", false, 76)
	_assert_eq(label.text, "Ready", "clip label text")
	_assert_true(label.clip_text, "clip label clips text")
	_assert_eq(label.autowrap_mode, TextServer.AUTOWRAP_OFF, "clip label no wrap")
	_assert_eq(label.custom_minimum_size.x, 76.0, "clip label min width")

	var button := ChatPanelView.create_button("New", "Start fresh.", 46)
	_assert_eq(button.text, "New", "button text")
	_assert_eq(button.tooltip_text, "Start fresh.", "button tooltip")
	_assert_eq(button.focus_mode, Control.FOCUS_ALL, "button keyboard focus")
	_assert_eq(button.custom_minimum_size, Vector2(46, 26), "button stable size")
	var pressed_events: Array[String] = []
	button.pressed.connect(func() -> void:
		pressed_events.append("pressed")
	)
	button.pressed.emit()
	_assert_eq(pressed_events.size(), 1, "button pressed signal reaches connected handler once")
	ChatPanelView.apply_button_state(button, {
		"disabled": true,
		"text": "Retry",
		"tooltip": "Try again.",
		"visible": false,
	})
	_assert_true(button.disabled, "button state disabled")
	_assert_eq(button.text, "Retry", "button state text")
	_assert_eq(button.tooltip_text, "Try again.", "button state tooltip")
	_assert_false(button.visible, "button state visible")
	var check_button := CheckButton.new()
	check_button.text = "Trust Session"
	ChatPanelView.apply_check_button_state(check_button, {
		"disabled": true,
		"pressed": true,
		"text": "Trust: full",
	})
	_assert_true(check_button.disabled, "check button state disabled")
	_assert_true(check_button.button_pressed, "check button pressed")
	_assert_eq(check_button.text, "Trust: full", "check button text")

	var input := ChatPanelView.create_multiline_input()
	_assert_true(input.placeholder_text.contains("Enter to send"), "input placeholder explains enter")
	_assert_true(input.has_signal("chat_enter_action"), "input emits chat enter actions")
	_assert_true(input.has_method("handle_key_event"), "input owns live key handling")
	_assert_eq(input.custom_minimum_size.y, 260.0, "input min height")
	_assert_eq(input.size_flags_vertical, Control.SIZE_EXPAND_FILL, "input keeps multiline vertical allocation")
	_assert_eq(input.wrap_mode, TextEdit.LINE_WRAPPING_BOUNDARY, "input wraps")
	_assert_false(input.scroll_fit_content_height, "input keeps stable multiline height")
	var prompt_actions: Array[String] = []
	var prompt_text_changes: Array[String] = []
	var prompt_focus_events: Array[String] = []
	var prompt_connection := ChatPanelView.connect_prompt_input(
		input,
		func() -> void:
			prompt_text_changes.append("changed"),
		func() -> void:
			prompt_focus_events.append("focus"),
		func(action: String) -> void:
			prompt_actions.append(action),
		func(_event: InputEventKey) -> bool:
			return false
	)
	_assert_true(bool(prompt_connection.get("connected", false)), "prompt input connected")
	_assert_eq(prompt_connection.get("action_path", ""), "direct_handler", "prompt direct action path")
	_assert_eq((prompt_connection.get("connected_signals", []) as Array).size(), 2, "prompt signal connection count")
	input.text_changed.emit()
	input.focus_entered.emit()
	_assert_eq(prompt_text_changes.size(), 1, "prompt text change callback")
	_assert_eq(prompt_focus_events.size(), 1, "prompt focus callback")
	input.call("handle_key_event", _key(KEY_ENTER, true, true), true)
	_assert_eq(prompt_actions.size(), 1, "prompt action callback")
	_assert_eq(prompt_actions[0], "newline", "prompt action newline")
	var legacy_input := TextEdit.new()
	var fallback_events: Array[String] = []
	var legacy_connection := ChatPanelView.connect_prompt_input(
		legacy_input,
		Callable(),
		Callable(),
		Callable(),
		func(_event: InputEventKey) -> bool:
			fallback_events.append("fallback")
			return true
	)
	_assert_eq(legacy_connection.get("action_path", ""), "gui_input_fallback", "legacy fallback action path")
	legacy_input.gui_input.emit(_key(KEY_ENTER, true, false))
	_assert_eq(fallback_events.size(), 1, "legacy fallback callback")

	var input_row := ChatPanelView.create_row()
	var composer_toggle := ChatPanelView.create_composer_toggle_button()
	_assert_eq(composer_toggle.text, "Expand", "composer toggle starts collapsed")
	ChatPanelView.apply_composer_expanded(input_row, input, composer_toggle, true)
	_assert_eq(input.custom_minimum_size.y, 420.0, "expanded input height")
	_assert_eq(input_row.custom_minimum_size.y, 454.0, "expanded row height")
	_assert_eq(composer_toggle.text, "Collapse", "composer toggle expanded text")
	ChatPanelView.apply_composer_expanded(input_row, input, composer_toggle, false)
	_assert_eq(input.custom_minimum_size.y, 260.0, "collapsed input height")
	_assert_eq(input_row.custom_minimum_size.y, 294.0, "collapsed row height")
	_assert_eq(composer_toggle.text, "Expand", "composer toggle collapsed text")
	ChatPanelView.apply_composer_height(input_row, input, composer_toggle, 260, false)
	_assert_eq(input.custom_minimum_size.y, 260.0, "auto input height")
	_assert_eq(input_row.custom_minimum_size.y, 294.0, "auto row height")
	_assert_eq(composer_toggle.text, "Expand", "auto height keeps manual toggle collapsed")
	_assert_true(input.get_combined_minimum_size().y >= 260.0, "auto input combined minimum size refreshes")
	_assert_true(input_row.get_combined_minimum_size().y >= 294.0, "auto row combined minimum size refreshes")

	var advanced := ChatPanelView.create_advanced_panel()
	_assert_false(advanced.visible, "advanced hidden by default")
	_assert_eq(advanced.size_flags_horizontal, Control.SIZE_EXPAND_FILL, "advanced expands")
	var advanced_state := ChatPanelView.advanced_visibility_state(true)
	_assert_true(bool(advanced_state.get("panel_visible", false)), "advanced state panel visible")
	_assert_true(str(advanced_state.get("toggle_tooltip", "")).contains("Hide advanced"), "advanced state tooltip")
	var advanced_toggle := CheckButton.new()
	ChatPanelView.apply_advanced_visibility(advanced, advanced_toggle, true)
	_assert_true(advanced.visible, "advanced apply visible")
	_assert_true(advanced_toggle.button_pressed, "advanced toggle pressed")
	_assert_true(advanced_toggle.tooltip_text.contains("Hide advanced"), "advanced toggle hide tooltip")
	ChatPanelView.apply_advanced_visibility(advanced, advanced_toggle, false)
	_assert_false(advanced.visible, "advanced apply hidden")
	_assert_false(advanced_toggle.button_pressed, "advanced toggle unpressed")
	_assert_true(advanced_toggle.tooltip_text.contains("Show model"), "advanced toggle show tooltip")

	var log_controls := ChatPanelView.create_log_controls()
	var frame := log_controls.get("frame") as Control
	var scroll := log_controls.get("scroll") as ScrollContainer
	var message_list := log_controls.get("message_list") as VBoxContainer
	var bottom_spacer := log_controls.get("bottom_spacer") as Control
	_assert_true(frame.clip_contents, "log frame clips contents")
	_assert_eq(frame.custom_minimum_size.y, 48.0, "log frame min height")
	_assert_eq(scroll.get_parent(), frame, "scroll is inside frame")
	_assert_eq(scroll.horizontal_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED, "horizontal scroll disabled")
	_assert_eq(scroll.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_SHOW_ALWAYS, "vertical scroll always visible")
	_assert_eq(message_list.get_parent(), scroll, "message list inside scroll")
	_assert_eq(bottom_spacer.get_parent(), message_list, "bottom spacer inside message list")

	var approval_controls := ChatPanelView.create_approval_controls()
	var approval_panel := approval_controls.get("panel") as VBoxContainer
	var approval_title := approval_controls.get("title") as Label
	var approval_body := approval_controls.get("body") as TextEdit
	var approval_note := approval_controls.get("note") as LineEdit
	var approval_buttons := approval_controls.get("buttons") as HBoxContainer
	var approve_button := approval_controls.get("approve_button") as Button
	var approve_session_button := approval_controls.get("approve_session_button") as Button
	var reject_button := approval_controls.get("reject_button") as Button
	var revise_button := approval_controls.get("revise_button") as Button
	_assert_false(approval_panel.visible, "approval hidden by default")
	_assert_eq(approval_title.text, "Approval required", "approval title")
	_assert_false(approval_body.editable, "approval body readonly")
	_assert_eq(approval_note.placeholder_text, "Optional note for Codex", "approval note placeholder")
	_assert_eq(approval_buttons.get_parent(), approval_panel, "approval buttons parent")
	_assert_eq(approval_buttons.get_child_count(), 4, "approval button count")
	_assert_eq(approve_button.get_parent(), approval_buttons, "approve button parent")
	_assert_eq(approve_button.text, "Approve", "approve button text")
	_assert_eq(approve_session_button.text, "Approve Session", "approve session button text")
	_assert_true(approve_session_button.tooltip_text.contains("current app-server session"), "approve session tooltip")
	_assert_eq(reject_button.text, "Reject", "reject button text")
	_assert_eq(revise_button.text, "Revise", "revise button text")

	var layout_panel := ChatPanelView.create_panel()
	var layout_header := Label.new()
	layout_header.text = "Header"
	var layout_advanced := ChatPanelView.create_advanced_panel()
	var layout_input := ChatPanelView.create_input_controls().get("row") as VBoxContainer
	var layout_annotation := ChatPanelView.create_annotation_controls().get("row") as HBoxContainer
	var layout_log := ChatPanelView.create_log_controls().get("frame") as Control
	var layout_approval := ChatPanelView.create_approval_controls().get("panel") as VBoxContainer
	layout_panel.add_child(layout_header)
	layout_panel.add_child(layout_advanced)
	layout_panel.add_child(layout_input)
	layout_panel.add_child(layout_annotation)
	layout_panel.add_child(layout_log)
	ChatPanelView.arrange_chat_panel_sections(
		layout_panel,
		layout_advanced,
		layout_annotation,
		layout_log,
		layout_approval,
		layout_input
	)
	_assert_eq(layout_panel.get_child(2), layout_annotation, "annotation follows advanced")
	_assert_eq(layout_panel.get_child(3), layout_log, "log follows annotation")
	_assert_eq(layout_panel.get_child(4), layout_approval, "approval follows log")
	_assert_eq(layout_panel.get_child(5), layout_input, "input follows approval")

	panel.free()
	assembled_panel.free()
	dot.free()
	header_row.free()
	meta_row.free()
	working.free()
	toolbar_row.free()
	runtime_row.free()
	attachment_row.free()
	team_row.free()
	team_status.free()
	input_controls_row.free()
	annotation_row.free()
	label.free()
	button.free()
	check_button.free()
	input.free()
	legacy_input.free()
	input_row.free()
	composer_toggle.free()
	advanced.free()
	advanced_toggle.free()
	frame.free()
	approval_panel.free()
	layout_panel.free()


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures += 1
		push_error(label + " expected=" + str(expected) + " actual=" + str(actual))


func _assert_true(value: bool, label: String) -> void:
	if not value:
		_failures += 1
		push_error(label)


func _assert_false(value: bool, label: String) -> void:
	if value:
		_failures += 1
		push_error(label)


func _key(keycode: Key, pressed: bool, shift_pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	event.shift_pressed = shift_pressed
	return event
