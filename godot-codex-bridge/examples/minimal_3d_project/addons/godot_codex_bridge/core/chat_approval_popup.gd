@tool
extends Window

## Resizable approval review window. It only renders review content and emits
## the decision the user clicked; plugin.gd routes it through the unchanged
## ChatApprovalModel response path (same nonce/evidence, stale handling).
## Closing the window is not a decision.

signal decision_requested(decision: String)

const DockStyle := preload("dock_style.gd")
const ChatDiffModel := preload("chat_diff_model.gd")
const ChatDiffView := preload("chat_diff_view.gd")
const DEFAULT_SIZE := Vector2i(620, 440)

var approval_id := ""
var title_icon: TextureRect
var title_label: Label
var blocked_label: Label
var content_box: VBoxContainer
var note_edit: LineEdit
var approve_button: Button
var approve_session_button: Button
var allow_session_tool_button: Button
var reject_button: Button
var revise_button: Button
var details_label: Label
var _style: Dictionary = DockStyle.resolve(null)
var _palette: Dictionary = {}


func _init() -> void:
	title = "Codex approval"
	size = DEFAULT_SIZE
	min_size = Vector2i(420, 260)
	visible = false
	transient = true
	exclusive = false
	wrap_controls = false
	close_requested.connect(hide)

	var background := PanelContainer.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, DockStyle.SPACE_M)
	background.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", DockStyle.SPACE_M)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", DockStyle.SPACE_M)
	column.add_child(header)
	title_icon = TextureRect.new()
	title_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	title_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(title_icon)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_label)

	blocked_label = Label.new()
	blocked_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blocked_label.visible = false
	column.add_child(blocked_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	content_box = VBoxContainer.new()
	content_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_box.add_theme_constant_override("separation", DockStyle.SPACE_M)
	scroll.add_child(content_box)

	note_edit = LineEdit.new()
	note_edit.placeholder_text = "Note for Codex (optional)"
	column.add_child(note_edit)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", DockStyle.SPACE_S)
	column.add_child(buttons)
	revise_button = _decision_button("Revise", "Send your note back and ask Codex to change its plan.", "revise")
	buttons.add_child(revise_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	reject_button = _decision_button("Reject", "Do not allow this.", "reject")
	buttons.add_child(reject_button)
	approve_session_button = _decision_button("Approve for session", "Approve and let Codex reuse this approval for the current app-server session where supported.", "approve_session")
	approve_session_button.visible = false
	buttons.add_child(approve_session_button)
	allow_session_tool_button = _decision_button("Allow this session", "", "approve_remember")
	allow_session_tool_button.visible = false
	buttons.add_child(allow_session_tool_button)
	approve_button = _decision_button("Approve", "Allow exactly what is shown above.", "approve")
	buttons.add_child(approve_button)

	details_label = Label.new()
	details_label.clip_text = true
	details_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	details_label.mouse_filter = Control.MOUSE_FILTER_PASS
	details_label.add_theme_font_size_override("font_size", 10)
	column.add_child(details_label)


func apply_style(style: Dictionary, palette: Dictionary) -> void:
	_style = style
	_palette = palette
	DockStyle.apply_accent_button(approve_button, style)
	DockStyle.muted_label(style, details_label)
	blocked_label.add_theme_color_override("font_color", DockStyle.tone_color(style, "warn"))


## Replaces the content for approval `id`. Does not show the window.
func set_review(id: String, review: Dictionary) -> void:
	approval_id = id
	title_label.text = str(review.get("title", "Approval"))
	title_icon.texture = DockStyle.icon(_style, str(review.get("icon", "Key")))
	var blocked := str(review.get("blocked_reason", ""))
	blocked_label.text = ("Approve is blocked: " + blocked) if blocked != "" else ""
	blocked_label.visible = blocked != ""
	note_edit.text = ""
	note_edit.placeholder_text = str(review.get("note_placeholder", "Note for Codex (optional)"))
	details_label.text = str(review.get("details", ""))
	details_label.tooltip_text = details_label.text
	ChatDiffView.clear_children(content_box)
	for section in review.get("sections", []):
		_add_section(section as Dictionary)
	var fields: Array = review.get("fields", [])
	if not fields.is_empty():
		_add_fields(fields)
	var diff := str(review.get("diff_text", ""))
	if diff != "":
		for file_data in ChatDiffModel.parse_diff_files(diff):
			content_box.add_child(ChatDiffView.create_file_section(file_data, Callable(), _palette, true))


## Mirrors the dock approval button states (ChatControlStateModel controls).
func apply_button_states(controls: Dictionary) -> void:
	for pair in [[approve_button, "approve"], [approve_session_button, "approve_session"], [allow_session_tool_button, "allow_session_tool"], [reject_button, "reject"], [revise_button, "revise"]]:
		var button := pair[0] as Button
		var state: Dictionary = controls.get(pair[1], {})
		button.disabled = bool(state.get("disabled", button.disabled))
		if state.has("visible"):
			button.visible = bool(state.get("visible"))
		if str(state.get("tooltip", "")) != "":
			button.tooltip_text = str(state.get("tooltip", ""))


func open_centered() -> void:
	if not visible:
		popup_centered(DEFAULT_SIZE)
	grab_focus()


func close_review() -> void:
	approval_id = ""
	hide()


func _decision_button(text: String, tooltip: String, decision: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.pressed.connect(func() -> void: decision_requested.emit(decision))
	return button


func _add_section(section: Dictionary) -> void:
	var label_text := str(section.get("label", ""))
	if label_text != "":
		var heading := Label.new()
		heading.text = label_text
		DockStyle.muted_label(_style, heading, 11)
		content_box.add_child(heading)
	var body := RichTextLabel.new()
	body.bbcode_enabled = false
	body.fit_content = true
	body.scroll_active = false
	body.selection_enabled = true
	body.context_menu_enabled = true
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.text = str(section.get("text", ""))
	body.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	body.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if bool(section.get("code", false)):
		var code_font: Variant = _style.get("code_font")
		if code_font is Font:
			body.add_theme_font_override("normal_font", code_font)
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", DockStyle.code_box(_style))
		panel.add_child(body)
		content_box.add_child(panel)
	else:
		body.add_theme_constant_override("line_separation", 2)
		content_box.add_child(body)


func _add_fields(fields: Array) -> void:
	var heading := Label.new()
	heading.text = "Codex will receive"
	heading.tooltip_text = "The Host fills the answer: the first choice, yes, 0, or your note for text fields."
	heading.mouse_filter = Control.MOUSE_FILTER_PASS
	DockStyle.muted_label(_style, heading, 11)
	content_box.add_child(heading)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", DockStyle.SPACE_M)
	grid.add_theme_constant_override("v_separation", DockStyle.SPACE_S)
	content_box.add_child(grid)
	for field in fields:
		var data := field as Dictionary
		var name_label := Label.new()
		name_label.text = str(data.get("name", "")) + ("*" if bool(data.get("required", false)) else "")
		name_label.tooltip_text = str(data.get("description", ""))
		name_label.mouse_filter = Control.MOUSE_FILTER_PASS
		grid.add_child(name_label)
		var value_label := Label.new()
		var choices: Array = data.get("choices", [])
		value_label.text = str(data.get("answer", "")) + ("   (choices: " + ", ".join(PackedStringArray(choices)) + ")" if choices.size() > 1 else "")
		value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(value_label)
