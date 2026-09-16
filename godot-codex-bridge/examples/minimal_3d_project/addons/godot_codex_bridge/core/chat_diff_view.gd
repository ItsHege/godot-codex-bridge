@tool
extends RefCounted

## Stateless diff-row rendering for the Codex chat transcript.
## These build Godot Control nodes from already-parsed diff data and hold no
## chat/plugin state. Extracted from plugin.gd as the first (lowest-risk) slice
## of the chat view layer. Colour/line classification stays in ChatDiffModel.

const ChatDiffModel := preload("chat_diff_model.gd")
const ChatThemeModel := preload("chat_theme_model.gd")
const BridgeLimits := preload("bridge_limits.gd")


## Builds a collapsible per-file diff section. `scroll_callback` is invoked
## (deferred) when the section is toggled so the transcript can re-scroll.
static func create_file_section(file_data: Dictionary, scroll_callback: Callable, palette: Dictionary = {}) -> Control:
	var colors := _palette_values(palette)
	var section := VBoxContainer.new()
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.set_meta("chat_diff_file_section", true)

	var path := str(file_data.get("path", "unknown file"))
	var added := int(file_data.get("added", 0))
	var removed := int(file_data.get("removed", 0))
	var header_text := path + "  +" + str(added) + " -" + str(removed)

	var toggle := Button.new()
	toggle.text = "+ " + header_text
	toggle.tooltip_text = "Expand or collapse this file diff."
	toggle.focus_mode = Control.FOCUS_ALL
	toggle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_child(toggle)

	var details := PanelContainer.new()
	details.visible = false
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.set_meta("chat_diff_file_details", true)
	var details_style := StyleBoxFlat.new()
	details_style.bg_color = colors.get("diff_details_background", Color(0.08, 0.08, 0.08))
	details_style.border_color = colors.get("diff_details_accent", Color(0.23, 0.23, 0.20))
	details_style.border_width_left = 1
	details_style.border_width_top = 1
	details_style.border_width_right = 1
	details_style.border_width_bottom = 1
	details_style.corner_radius_top_left = 4
	details_style.corner_radius_top_right = 4
	details_style.corner_radius_bottom_left = 4
	details_style.corner_radius_bottom_right = 4
	details.add_theme_stylebox_override("panel", details_style)
	section.add_child(details)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	details.add_child(margin)

	var lines_box := VBoxContainer.new()
	lines_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lines_box.add_theme_constant_override("separation", 1)
	margin.add_child(lines_box)

	var lines: PackedStringArray = file_data.get("lines", PackedStringArray())
	for line in lines:
		lines_box.add_child(create_line(str(line), colors))
	if bool(file_data.get("truncated", false)):
		var truncated := Label.new()
		truncated.text = "[diff truncated in Godot UI after " + str(BridgeLimits.CHAT_DIFF_MAX_LINES_PER_FILE) + " lines; use copy for full diff]"
		truncated.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		truncated.add_theme_color_override("font_color", colors.get("diff_font", Color(0.92, 0.72, 0.40)))
		lines_box.add_child(truncated)

	toggle.pressed.connect(func() -> void:
		details.visible = not details.visible
		toggle.text = ("- " if details.visible else "+ ") + header_text
		if scroll_callback.is_valid():
			scroll_callback.call_deferred()
	)
	return section


static func create_line(line: String, palette: Dictionary = {}) -> Control:
	var colors := _palette_values(palette)
	var row := PanelContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = line_background(line, colors)
	style.content_margin_left = 4
	style.content_margin_right = 4
	style.content_margin_top = 1
	style.content_margin_bottom = 1
	row.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = line
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", line_foreground(line, colors))
	label.add_theme_font_size_override("font_size", 11)
	row.add_child(label)
	return row


static func line_background(line: String, palette: Dictionary = {}) -> Color:
	var colors := _palette_values(palette)
	match ChatDiffModel.diff_line_kind(line):
		"added":
			return colors.get("diff_line_added_background", Color(0.04, 0.18, 0.07))
		"removed":
			return colors.get("diff_line_removed_background", Color(0.22, 0.06, 0.06))
		"hunk":
			return colors.get("diff_line_hunk_background", Color(0.08, 0.12, 0.20))
		"file_header":
			return colors.get("diff_line_file_header_background", Color(0.14, 0.13, 0.09))
		_:
			return colors.get("diff_line_default_background", Color(0.08, 0.08, 0.08))


static func line_foreground(line: String, palette: Dictionary = {}) -> Color:
	var colors := _palette_values(palette)
	match ChatDiffModel.diff_line_kind(line):
		"added":
			return colors.get("diff_line_added_font", Color(0.62, 0.94, 0.66))
		"removed":
			return colors.get("diff_line_removed_font", Color(1.0, 0.62, 0.62))
		"hunk":
			return colors.get("diff_line_hunk_font", Color(0.62, 0.74, 1.0))
		"file_header":
			return colors.get("diff_line_file_header_font", Color(0.92, 0.78, 0.38))
		_:
			return colors.get("diff_line_default_font", Color(0.82, 0.82, 0.82))


static func clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


static func _palette_values(palette: Dictionary) -> Dictionary:
	return ChatThemeModel.palette_values(palette)
