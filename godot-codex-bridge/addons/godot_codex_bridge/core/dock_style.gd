@tool
extends RefCounted

## Theme-derived styling for the Codex Tools dock (Bridge + Codex Chat).
## Colors, icons and fonts come from the editor theme through a Control inside
## the editor tree, so the dock follows light/dark editor themes. Without one
## (headless unit tests) a fixed fallback palette is used and icon helpers keep
## the button text.

const ChatThemeModel := preload("chat_theme_model.gd")

const SPACE_S := 4
const SPACE_M := 8
const RADIUS := 4
const ACCENT_BAR := 3

const FALLBACK := {
	"base": Color(0.13, 0.14, 0.16),
	"accent": Color(0.44, 0.73, 0.98),
	"font": Color(0.85, 0.86, 0.88),
	"muted": Color(0.58, 0.60, 0.63),
	"surface": Color(0.17, 0.18, 0.21),
	"surface_strong": Color(0.21, 0.22, 0.25),
	"success": Color(0.45, 0.85, 0.55),
	"warning": Color(0.95, 0.75, 0.35),
	"error": Color(0.95, 0.42, 0.42),
}


## Returns a style dictionary. `source` should be a Control inside the editor
## tree (e.g. EditorInterface.get_base_control()); null gives the fallback.
static func resolve(source: Control = null) -> Dictionary:
	var style := FALLBACK.duplicate()
	style["source"] = null
	style["code_font"] = null
	style["themed"] = false
	if source == null or not is_instance_valid(source) or not source.has_theme_color("base_color", "Editor"):
		return style
	var base := source.get_theme_color("base_color", "Editor")
	var font := source.get_theme_color("font_color", "Editor")
	var light := _is_light(base)
	style["base"] = base
	style["accent"] = source.get_theme_color("accent_color", "Editor")
	style["font"] = font
	style["muted"] = source.get_theme_color("disabled_font_color", "Editor") if source.has_theme_color("disabled_font_color", "Editor") else font.lerp(base, 0.4)
	style["surface"] = _shift(base, -0.05 if light else 0.05)
	style["surface_strong"] = _shift(base, -0.10 if light else 0.10)
	for key in ["success", "warning", "error"]:
		var name: String = str(key) + "_color"
		if source.has_theme_color(name, "Editor"):
			style[key] = source.get_theme_color(name, "Editor")
	if source.has_theme_font("source", "EditorFonts"):
		style["code_font"] = source.get_theme_font("source", "EditorFonts")
	style["source"] = source
	style["themed"] = true
	return style


static func tone_color(style: Dictionary, tone: String) -> Color:
	match tone:
		"ok", "success":
			return style.get("success", FALLBACK["success"])
		"warn", "warning", "busy":
			return style.get("warning", FALLBACK["warning"])
		"error":
			return style.get("error", FALLBACK["error"])
		"accent":
			return style.get("accent", FALLBACK["accent"])
	return style.get("muted", FALLBACK["muted"])


static func icon(style: Dictionary, icon_name: String) -> Texture2D:
	var source: Variant = style.get("source")
	if source is Control and is_instance_valid(source) and (source as Control).has_theme_icon(icon_name, "EditorIcons"):
		return (source as Control).get_theme_icon(icon_name, "EditorIcons")
	return null


## Gives `button` an editor icon. With `icon_only`, the text is dropped (it
## stays in the tooltip) only when the icon exists, so fallback keeps labels.
static func apply_icon(button: Button, style: Dictionary, icon_name: String, icon_only := false, flat := true) -> void:
	if button == null:
		return
	var texture := icon(style, icon_name)
	if texture == null:
		return
	button.icon = texture
	button.flat = flat
	button.expand_icon = false
	if icon_only:
		if button.tooltip_text == "":
			button.tooltip_text = button.text
		button.set_meta("dock_icon_only", true)
		button.set_meta("dock_label", button.text)
		button.text = ""
		button.custom_minimum_size = Vector2(28, 26)


static func is_icon_only(button: Button) -> bool:
	return button != null and bool(button.get_meta("dock_icon_only", false))


## The control's label: its text, or for icon-only buttons the label it had.
static func button_label(button: Button) -> String:
	if button == null:
		return ""
	if button.text != "":
		return button.text
	return str(button.get_meta("dock_label", ""))


## Rounded panel with an optional left accent bar.
static func card_box(background: Color, accent := Color(0, 0, 0, 0), bar_width := 0, padding := Vector2(6, 4)) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.set_corner_radius_all(RADIUS)
	if bar_width > 0:
		box.border_color = accent
		box.border_width_left = bar_width
	box.content_margin_left = padding.x + bar_width
	box.content_margin_right = padding.x
	box.content_margin_top = padding.y
	box.content_margin_bottom = padding.y
	return box


static func code_box(style: Dictionary) -> StyleBoxFlat:
	return card_box(style.get("surface_strong", FALLBACK["surface_strong"]), Color(0, 0, 0, 0), 0, Vector2(SPACE_M, SPACE_S))


## Accent (primary) button: filled with the editor accent color.
static func apply_accent_button(button: Button, style: Dictionary) -> void:
	if button == null:
		return
	var accent: Color = style.get("accent", FALLBACK["accent"])
	var text := Color(0.05, 0.05, 0.06) if _is_light(accent) else Color(1, 1, 1)
	for state in ["normal", "hover", "pressed", "focus"]:
		var color := accent
		if state == "hover":
			color = accent.lightened(0.12)
		elif state == "pressed":
			color = accent.darkened(0.15)
		var box := card_box(color, Color(0, 0, 0, 0), 0, Vector2(12, 4))
		if state == "focus":
			box.draw_center = false
			box.set_border_width_all(1)
			box.border_color = text
		button.add_theme_stylebox_override(state, box)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(key, text)


## Small muted section header with a thin separator, for the Bridge tab.
static func section_header(style: Dictionary, text: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "Section" + text.replace(" ", "")
	box.add_theme_constant_override("separation", 2)
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", style.get("muted", FALLBACK["muted"]))
	box.add_child(label)
	var line := HSeparator.new()
	line.add_theme_constant_override("separation", 2)
	# Subtle 1 px rule in a faded font color instead of the theme's dark line.
	var rule := StyleBoxLine.new()
	var font_color: Color = style.get("font", FALLBACK["font"])
	rule.color = Color(font_color.r, font_color.g, font_color.b, 0.15)
	rule.thickness = 1
	line.add_theme_stylebox_override("separator", rule)
	box.add_child(line)
	return box


static func muted_label(style: Dictionary, label: Label, font_size := 0) -> void:
	if label == null:
		return
	label.add_theme_color_override("font_color", style.get("muted", FALLBACK["muted"]))
	if font_size > 0:
		label.add_theme_font_size_override("font_size", font_size)


## Chat palette (bubbles, diffs) derived from the same source.
static func chat_palette(source: Control = null) -> Dictionary:
	return ChatThemeModel.palette_from_control(source) if source != null else ChatThemeModel.default_palette()


static func _shift(color: Color, amount: float) -> Color:
	if amount >= 0.0:
		return color.lerp(Color(1, 1, 1, color.a), amount)
	return color.lerp(Color(0, 0, 0, color.a), -amount)


static func _is_light(color: Color) -> bool:
	return 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b >= 0.55
