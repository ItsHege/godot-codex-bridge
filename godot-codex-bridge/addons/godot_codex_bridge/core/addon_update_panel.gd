@tool
extends VBoxContainer

## Compact Bridge tab updates row: "<build status> [Check] [Update] [Cancel update]".
## Update is only visible when an update is available and Cancel only while one
## is pending; explanations live in tooltips. Renders AddonUpdateModel.view();
## plugin.gd owns the Host RPC and the editor close request.

signal check_pressed
signal update_confirmed
signal cancel_pressed

const TONE_COLORS := {
	"ok": Color(0.42, 0.86, 0.58),
	"warn": Color(0.92, 0.72, 0.34),
	"neutral": Color(0.72, 0.74, 0.78),
}

var status_label: Label
var notice_label: Label
var manual_command_edit: LineEdit
var check_button: Button
var update_button: Button
var cancel_button: Button
var confirm_dialog: ConfirmationDialog


func _init() -> void:
	name = "AddonUpdates"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 2)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(row)
	status_label = _one_line_label()
	row.add_child(status_label)
	check_button = _button("Check", "Check for updates: re-read the local install/channel manifests and, when paired, ask the Codex Host.")
	check_button.pressed.connect(func() -> void: check_pressed.emit())
	row.add_child(check_button)
	update_button = _button("Update", "")
	update_button.visible = false
	update_button.pressed.connect(func() -> void: confirm_dialog.popup_centered(Vector2i(460, 200)))
	row.add_child(update_button)
	cancel_button = _button("Cancel update", "")
	cancel_button.visible = false
	cancel_button.pressed.connect(func() -> void: cancel_pressed.emit())
	row.add_child(cancel_button)

	notice_label = _one_line_label()
	notice_label.visible = false
	add_child(notice_label)

	manual_command_edit = LineEdit.new()
	manual_command_edit.editable = false
	manual_command_edit.selecting_enabled = true
	manual_command_edit.tooltip_text = "Manual update command: close Godot, then run this in PowerShell."
	manual_command_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	manual_command_edit.visible = false
	add_child(manual_command_edit)

	confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.title = "Update Godot Codex Bridge"
	confirm_dialog.ok_button_text = "Update and close Godot"
	confirm_dialog.confirmed.connect(func() -> void: update_confirmed.emit())
	add_child(confirm_dialog)


func apply(view: Dictionary, confirmation_text: String) -> void:
	status_label.text = str(view.get("status_compact", view.get("status_text", "")))
	status_label.tooltip_text = str(view.get("status_tooltip", ""))
	_tint(status_label, str(view.get("status_tone", "neutral")))
	# One short line only when actionable; the full text is in the tooltip.
	var notice := str(view.get("notice", ""))
	var line := notice if notice != "" else str(view.get("pending_text", ""))
	notice_label.text = line
	notice_label.tooltip_text = line
	notice_label.visible = line != ""
	_tint(notice_label, str(view.get("notice_tone", "neutral")) if notice != "" else "warn")
	check_button.disabled = not bool(view.get("check_enabled", true))
	update_button.visible = bool(view.get("update_visible", false))
	update_button.disabled = not bool(view.get("update_enabled", false))
	update_button.tooltip_text = str(view.get("update_tooltip", ""))
	cancel_button.visible = bool(view.get("cancel_visible", false))
	cancel_button.disabled = not bool(view.get("cancel_enabled", false))
	cancel_button.tooltip_text = str(view.get("cancel_tooltip", ""))
	var command := str(view.get("manual_command", ""))
	manual_command_edit.text = command
	manual_command_edit.visible = command != ""
	confirm_dialog.dialog_text = confirmation_text


func _tint(label: Label, tone: String) -> void:
	label.add_theme_color_override("font_color", TONE_COLORS.get(tone, TONE_COLORS["neutral"]))


func _one_line_label() -> Label:
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# Labels ignore the mouse by default; PASS lets the tooltip show.
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	return label


## Buttons keep their text width as minimum size (no clip_text), so they can
## never collapse into empty boxes.
func _button(text: String, tooltip: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	return button
