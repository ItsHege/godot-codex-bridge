@tool
extends RefCounted

const ChatPromptTextEdit := preload("chat_prompt_text_edit.gd")

const DEFAULT_PANEL_MIN_WIDTH := 220.0
const DEFAULT_BUTTON_HEIGHT := 26.0
const INPUT_MIN_HEIGHT := 260.0
const INPUT_AUTO_HEIGHT := 260.0
const INPUT_EXPANDED_HEIGHT := 420.0
const INPUT_CONTROLS_HEIGHT := 34.0
const LOG_FRAME_MIN_HEIGHT := 48.0


static func create_panel() -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(DEFAULT_PANEL_MIN_WIDTH, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return panel


static func create_panel_controls(status_color: Color) -> Dictionary:
	var panel := create_panel()

	var status_controls := create_status_header_controls(status_color)
	panel.add_child(status_controls.get("row") as HBoxContainer)

	var advanced_panel := create_advanced_panel()
	panel.add_child(advanced_panel)

	var meta_controls := create_meta_controls()
	advanced_panel.add_child(meta_controls.get("row") as HBoxContainer)

	var working_label := create_working_label()
	panel.add_child(working_label)

	var toolbar_controls := create_toolbar_controls()
	advanced_panel.add_child(toolbar_controls.get("row") as HBoxContainer)

	var runtime_controls := create_runtime_controls()
	advanced_panel.add_child(runtime_controls.get("row") as HBoxContainer)

	var input_controls := create_input_controls()
	var input_row := input_controls.get("row") as VBoxContainer
	panel.add_child(input_row)

	var attachment_controls := create_attachment_controls()
	advanced_panel.add_child(attachment_controls.get("row") as HBoxContainer)

	var annotation_controls := create_annotation_controls()
	var annotation_row := annotation_controls.get("row") as HBoxContainer
	panel.add_child(annotation_row)

	var team_controls := create_team_controls()
	advanced_panel.add_child(team_controls.get("row") as HBoxContainer)
	var team_status := team_controls.get("status_label") as Label
	advanced_panel.add_child(team_status)

	var approval_controls := create_approval_controls()
	var approval_panel := approval_controls.get("panel") as VBoxContainer

	var log_controls := create_log_controls()
	var log_frame := log_controls.get("frame") as Control
	panel.add_child(log_frame)

	arrange_chat_panel_sections(
		panel,
		advanced_panel,
		annotation_row,
		log_frame,
		approval_panel,
		input_row
	)

	return {
		"panel": panel,
		"status": status_controls,
		"advanced_panel": advanced_panel,
		"meta": meta_controls,
		"working_label": working_label,
		"toolbar": toolbar_controls,
		"runtime": runtime_controls,
		"input": input_controls,
		"attachment": attachment_controls,
		"annotation": annotation_controls,
		"team": team_controls,
		"approval": approval_controls,
		"log": log_controls,
	}


static func control_refs(panel_controls: Dictionary) -> Dictionary:
	var status_controls := panel_controls.get("status", {}) as Dictionary
	var meta_controls := panel_controls.get("meta", {}) as Dictionary
	var toolbar_controls := panel_controls.get("toolbar", {}) as Dictionary
	var runtime_controls := panel_controls.get("runtime", {}) as Dictionary
	var input_controls := panel_controls.get("input", {}) as Dictionary
	var attachment_controls := panel_controls.get("attachment", {}) as Dictionary
	var annotation_controls := panel_controls.get("annotation", {}) as Dictionary
	var team_controls := panel_controls.get("team", {}) as Dictionary
	var approval_controls := panel_controls.get("approval", {}) as Dictionary
	var log_controls := panel_controls.get("log", {}) as Dictionary
	return {
		"panel": panel_controls.get("panel"),
		"status_dot": status_controls.get("status_dot"),
		"status_label": status_controls.get("status_label"),
		"advanced_toggle": status_controls.get("advanced_toggle"),
		"advanced_panel": panel_controls.get("advanced_panel"),
		"readiness_label": meta_controls.get("readiness_label"),
		"thread_label": meta_controls.get("thread_label"),
		"new_button": meta_controls.get("new_button"),
		"clear_button": meta_controls.get("clear_button"),
		"working_label": panel_controls.get("working_label"),
		"connect_button": status_controls.get("connect_button"),
		"cancel_button": toolbar_controls.get("cancel_button"),
		"emergency_stop_button": toolbar_controls.get("emergency_stop_button"),
		"enable_tools_button": toolbar_controls.get("enable_tools_button"),
		"model_option": runtime_controls.get("model_option"),
		"reasoning_option": runtime_controls.get("reasoning_option"),
		"trust_button": runtime_controls.get("trust_button"),
		"input_row": input_controls.get("row"),
		"eye_button": input_controls.get("eye_button"),
		"input": input_controls.get("input"),
		"send_button": input_controls.get("send_button"),
		"composer_toggle_button": input_controls.get("composer_toggle_button"),
		"attach_context": attachment_controls.get("context"),
		"attach_selected": attachment_controls.get("selected"),
		"attach_screenshot": attachment_controls.get("screenshot"),
		"pending_annotation_label": annotation_controls.get("pending_label"),
		"clear_annotation_button": annotation_controls.get("clear_button"),
		"team_review_button": team_controls.get("review_button"),
		"team_cancel_button": team_controls.get("cancel_button"),
		"team_status_label": team_controls.get("status_label"),
		"approval_panel": approval_controls.get("panel"),
		"approval_title": approval_controls.get("title"),
		"approval_body": approval_controls.get("body"),
		"approval_note": approval_controls.get("note"),
		"approve_button": approval_controls.get("approve_button"),
		"approve_session_button": approval_controls.get("approve_session_button"),
		"reject_button": approval_controls.get("reject_button"),
		"revise_button": approval_controls.get("revise_button"),
		"log_frame": log_controls.get("frame"),
		"log_view": log_controls.get("scroll"),
		"message_list": log_controls.get("message_list"),
		"bottom_spacer": log_controls.get("bottom_spacer"),
	}


static func create_row(separation: int = 6) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", separation)
	return row


static func create_status_dot(color: Color) -> ColorRect:
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(10, 10)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.color = color
	return dot


static func create_status_header_controls(status_color: Color) -> Dictionary:
	var row := create_row()
	var dot := create_status_dot(status_color)
	row.add_child(dot)

	var status_label := create_clip_label()
	row.add_child(status_label)

	var connect_button := create_button(
		"Connect",
		"Connect Codex Host to this Godot project.",
		72
	)
	row.add_child(connect_button)

	var advanced_toggle := CheckButton.new()
	advanced_toggle.text = "Advanced"
	advanced_toggle.tooltip_text = "Show model, connection, trust, attachment and team controls."
	advanced_toggle.focus_mode = Control.FOCUS_ALL
	row.add_child(advanced_toggle)

	return {
		"row": row,
		"status_dot": dot,
		"status_label": status_label,
		"connect_button": connect_button,
		"advanced_toggle": advanced_toggle,
	}


static func create_meta_controls() -> Dictionary:
	var row := create_row()

	var readiness_label := create_clip_label()
	row.add_child(readiness_label)

	var thread_label := create_clip_label("", false, 76)
	row.add_child(thread_label)

	var new_button := create_button("New", "Start the next prompt in a fresh Codex thread.", 46)
	row.add_child(new_button)

	var clear_button := create_button("Clear", "Clear the visible chat transcript without disconnecting Codex.", 52)
	row.add_child(clear_button)

	return {
		"row": row,
		"readiness_label": readiness_label,
		"thread_label": thread_label,
		"new_button": new_button,
		"clear_button": clear_button,
	}


static func create_toolbar_controls() -> Dictionary:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var cancel_button := create_button(
		"Cancel",
		"Interrupt the active foreground Codex turn."
	)
	cancel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_button.clip_text = true
	row.add_child(cancel_button)

	var emergency_stop_button := create_button(
		"Stop All",
		"Emergency stop: interrupt Codex, cancel team work, clear Trust Session and stop Godot play session."
	)
	emergency_stop_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	emergency_stop_button.clip_text = true
	row.add_child(emergency_stop_button)

	var enable_tools_button := create_button(
		"Enable Tools",
		"Register or refresh Godot Codex Bridge tools for the attached project."
	)
	enable_tools_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enable_tools_button.clip_text = true
	row.add_child(enable_tools_button)

	return {
		"row": row,
		"cancel_button": cancel_button,
		"emergency_stop_button": emergency_stop_button,
		"enable_tools_button": enable_tools_button,
	}


static func create_runtime_controls() -> Dictionary:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var model_option := OptionButton.new()
	model_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	model_option.clip_text = true
	model_option.custom_minimum_size = Vector2(50, 0)
	model_option.tooltip_text = "Codex model for the next message."
	row.add_child(model_option)

	var reasoning_option := OptionButton.new()
	reasoning_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reasoning_option.clip_text = true
	reasoning_option.custom_minimum_size = Vector2(50, 0)
	reasoning_option.tooltip_text = "Reasoning effort. Lower is faster; higher is deeper."
	row.add_child(reasoning_option)

	var trust_button := CheckButton.new()
	trust_button.text = "Trust Session"
	trust_button.tooltip_text = "Use full-machine trust for this Codex Host session until cleared or restarted."
	row.add_child(trust_button)

	return {
		"row": row,
		"model_option": model_option,
		"reasoning_option": reasoning_option,
		"trust_button": trust_button,
	}


static func create_attachment_controls() -> Dictionary:
	var row := HBoxContainer.new()

	var context := CheckBox.new()
	context.text = "Context"
	context.button_pressed = true
	context.tooltip_text = "Attach bounded Godot project, scene and editor context to the next message."
	row.add_child(context)

	var selected := CheckBox.new()
	selected.text = "Selected"
	selected.button_pressed = true
	selected.tooltip_text = "Attach the currently selected Godot nodes to the next message."
	row.add_child(selected)

	var screenshot := CheckBox.new()
	screenshot.text = "Screenshot"
	screenshot.button_pressed = false
	screenshot.tooltip_text = "Attach the latest local Bridge screenshot. A fresh capture still requires screenshot permission."
	row.add_child(screenshot)

	return {
		"row": row,
		"context": context,
		"selected": selected,
		"screenshot": screenshot,
	}


static func create_team_controls() -> Dictionary:
	var row := HBoxContainer.new()

	var review_button := create_button(
		"Team Review",
		"Ask a background Codex agent team to review the current task."
	)
	row.add_child(review_button)

	var cancel_button := create_button(
		"Cancel Team",
		"Cancel the active background Codex team task."
	)
	row.add_child(cancel_button)

	var status_label := create_clip_label("Team: idle")

	return {
		"row": row,
		"review_button": review_button,
		"cancel_button": cancel_button,
		"status_label": status_label,
	}


static func create_input_controls() -> Dictionary:
	var row := VBoxContainer.new()
	row.custom_minimum_size = Vector2(0, INPUT_MIN_HEIGHT + INPUT_CONTROLS_HEIGHT)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_theme_constant_override("separation", 4)

	var input := create_multiline_input()
	row.add_child(input)

	var controls_row := HBoxContainer.new()
	controls_row.custom_minimum_size = Vector2(0, INPUT_CONTROLS_HEIGHT)
	controls_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls_row.add_theme_constant_override("separation", 6)
	row.add_child(controls_row)

	var eye_button := create_button(
		"Eye",
		"Eye Attach: capture Godot editor or viewport, mark it as a user reference, and attach it to the next message. Ctrl+F12 is a plain screenshot; Eye adds AI-safe marker metadata.",
		44
	)
	eye_button.custom_minimum_size = Vector2(44, 32)
	controls_row.add_child(eye_button)

	var composer_toggle := create_composer_toggle_button()
	controls_row.add_child(composer_toggle)

	var controls_spacer := Control.new()
	controls_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls_row.add_child(controls_spacer)

	var send_button := create_button("Send")
	controls_row.add_child(send_button)

	return {
		"row": row,
		"controls_row": controls_row,
		"eye_button": eye_button,
		"input": input,
		"send_button": send_button,
		"composer_toggle_button": composer_toggle,
	}


static func create_annotation_controls() -> Dictionary:
	var row := HBoxContainer.new()

	var pending_label := create_clip_label()
	pending_label.visible = false
	row.add_child(pending_label)

	var clear_button := create_button(
		"x",
		"Remove the AI marker attachment from the next message."
	)
	clear_button.visible = false
	row.add_child(clear_button)

	return {
		"row": row,
		"pending_label": pending_label,
		"clear_button": clear_button,
	}


static func create_working_label() -> Label:
	var label := create_clip_label()
	label.text = "Still working..."
	label.visible = false
	return label


static func create_clip_label(text: String = "", expand: bool = true, min_width: float = 0.0) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.clip_text = true
	if expand:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		label.size_flags_horizontal = Control.SIZE_SHRINK_END
	if min_width > 0.0:
		label.custom_minimum_size = Vector2(min_width, 0)
	return label


static func create_button(text: String, tooltip: String = "", min_width: float = 0.0) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_ALL
	if min_width > 0.0:
		button.custom_minimum_size = Vector2(min_width, DEFAULT_BUTTON_HEIGHT)
	return button


static func apply_button_state(button: Button, state: Dictionary) -> void:
	if button == null:
		return
	button.disabled = bool(state.get("disabled", button.disabled))
	if state.has("text"):
		button.text = str(state.get("text", button.text))
	if state.has("tooltip"):
		button.tooltip_text = str(state.get("tooltip", button.tooltip_text))
	if state.has("visible"):
		button.visible = bool(state.get("visible", button.visible))


static func apply_check_button_state(button: CheckButton, state: Dictionary) -> void:
	apply_button_state(button, state)
	if button == null:
		return
	if state.has("pressed"):
		button.set_pressed_no_signal(bool(state.get("pressed", false)))


static func connect_prompt_input(input: TextEdit, text_changed_callback: Callable, focus_entered_callback: Callable, action_callback: Callable, fallback_key_callback: Callable) -> Dictionary:
	var connected_signals: Array[String] = []
	if input == null:
		return {
			"connected": false,
			"action_path": "unavailable",
			"connected_signals": connected_signals,
		}
	if text_changed_callback.is_valid():
		input.text_changed.connect(text_changed_callback)
		connected_signals.append("text_changed")
	if focus_entered_callback.is_valid():
		input.focus_entered.connect(focus_entered_callback)
		connected_signals.append("focus_entered")
	var action_path := "none"
	if action_callback.is_valid() and input.has_method("set_action_handler"):
		input.call("set_action_handler", action_callback)
		action_path = "direct_handler"
	elif action_callback.is_valid() and input.has_signal("chat_enter_action"):
		input.connect("chat_enter_action", action_callback)
		action_path = "signal"
	elif fallback_key_callback.is_valid():
		input.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventKey:
				if bool(fallback_key_callback.call(event as InputEventKey)):
					input.accept_event()
		)
		action_path = "gui_input_fallback"
	return {
		"connected": true,
		"action_path": action_path,
		"connected_signals": connected_signals,
	}


static func create_multiline_input() -> TextEdit:
	var input := ChatPromptTextEdit.new()
	input.placeholder_text = "Ask Codex...  Enter to send, Shift+Enter adds a line"
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.size_flags_vertical = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size = Vector2(0, INPUT_MIN_HEIGHT)
	input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	input.scroll_fit_content_height = false
	input.scroll_smooth = true
	return input


static func create_composer_toggle_button() -> Button:
	var button := create_button("Expand", "Make the Codex prompt box taller for longer instructions. Shift+Enter adds a new line.", 74)
	return button


static func apply_composer_expanded(row: Control, input: TextEdit, toggle_button: Button, expanded: bool) -> void:
	var height := INPUT_EXPANDED_HEIGHT if expanded else INPUT_MIN_HEIGHT
	apply_composer_height(row, input, toggle_button, height, expanded)


static func apply_composer_height(row: Control, input: TextEdit, toggle_button: Button, height: float, expanded: bool) -> void:
	if row != null:
		row.custom_minimum_size = Vector2(0, height + INPUT_CONTROLS_HEIGHT)
		row.update_minimum_size()
	if input != null:
		input.custom_minimum_size = Vector2(0, height)
		input.update_minimum_size()
	if toggle_button != null:
		toggle_button.text = "Collapse" if expanded else "Expand"
		toggle_button.tooltip_text = "Shrink the Codex prompt box." if expanded else "Make the Codex prompt box taller for longer instructions. Shift+Enter adds a new line."
		toggle_button.update_minimum_size()


static func create_advanced_panel() -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.visible = false
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 4)
	return panel


static func advanced_visibility_state(visible: bool) -> Dictionary:
	return {
		"panel_visible": visible,
		"toggle_pressed": visible,
		"toggle_tooltip": "Hide advanced controls." if visible else "Show model, reasoning, trust, attachment and team controls.",
	}


static func apply_advanced_visibility(panel: Control, toggle: CheckButton, visible: bool) -> void:
	var state := advanced_visibility_state(visible)
	if panel != null:
		panel.visible = bool(state.get("panel_visible", false))
	if toggle != null:
		toggle.set_pressed_no_signal(bool(state.get("toggle_pressed", false)))
		toggle.tooltip_text = str(state.get("toggle_tooltip", ""))


static func create_log_controls() -> Dictionary:
	var frame := Control.new()
	frame.custom_minimum_size = Vector2(0, LOG_FRAME_MIN_HEIGHT)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.clip_contents = true

	var scroll := ScrollContainer.new()
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	scroll.offset_left = 0.0
	scroll.offset_top = 0.0
	scroll.offset_right = 0.0
	scroll.offset_bottom = 0.0
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	frame.add_child(scroll)

	var message_list := VBoxContainer.new()
	message_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message_list.add_theme_constant_override("separation", 8)
	scroll.add_child(message_list)

	var bottom_spacer := Control.new()
	bottom_spacer.custom_minimum_size = Vector2(0, 8)
	message_list.add_child(bottom_spacer)

	return {
		"frame": frame,
		"scroll": scroll,
		"message_list": message_list,
		"bottom_spacer": bottom_spacer,
	}


static func create_approval_controls() -> Dictionary:
	var panel := VBoxContainer.new()
	panel.visible = false
	panel.size_flags_vertical = Control.SIZE_SHRINK_END
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var title := Label.new()
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.text = "Approval required"
	panel.add_child(title)

	var body := TextEdit.new()
	body.editable = false
	body.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	body.custom_minimum_size = Vector2(0, 56)
	panel.add_child(body)

	var note := LineEdit.new()
	note.placeholder_text = "Optional note for Codex"
	panel.add_child(note)

	var buttons := HBoxContainer.new()
	buttons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(buttons)

	var approve_button := create_button("Approve")
	approve_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	approve_button.clip_text = true
	buttons.add_child(approve_button)

	var approve_session_button := create_button(
		"Approve Session",
		"Approve this request and let Codex reuse this approval for the current app-server session where supported."
	)
	approve_session_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	approve_session_button.clip_text = true
	buttons.add_child(approve_session_button)

	var reject_button := create_button("Reject")
	reject_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reject_button.clip_text = true
	buttons.add_child(reject_button)

	var revise_button := create_button("Revise")
	revise_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	revise_button.clip_text = true
	buttons.add_child(revise_button)

	return {
		"panel": panel,
		"title": title,
		"body": body,
		"note": note,
		"buttons": buttons,
		"approve_button": approve_button,
		"approve_session_button": approve_session_button,
		"reject_button": reject_button,
		"revise_button": revise_button,
	}


static func arrange_chat_panel_sections(panel: VBoxContainer, advanced_panel: Control, annotation_row: Control, log_frame: Control, approval_panel: Control, input_row: Control) -> void:
	if panel == null:
		return
	if approval_panel != null and approval_panel.get_parent() == null:
		panel.add_child(approval_panel)
	_move_after_panel_child(panel, annotation_row, advanced_panel)
	_move_after_panel_child(panel, log_frame, annotation_row)
	_move_after_panel_child(panel, approval_panel, log_frame)
	_move_after_panel_child(panel, input_row, approval_panel)


static func _move_after_panel_child(panel: VBoxContainer, child: Control, previous: Control) -> void:
	if child == null or previous == null:
		return
	if child.get_parent() != panel or previous.get_parent() != panel:
		return
	var target_index := min(previous.get_index() + 1, panel.get_child_count() - 1)
	panel.move_child(child, target_index)
