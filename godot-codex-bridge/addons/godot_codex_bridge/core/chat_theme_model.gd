@tool
extends RefCounted


static func default_palette() -> Dictionary:
	return palette_from_values(
		Color(0.12, 0.12, 0.12),
		Color(0.37, 0.58, 0.92),
		Color(0.86, 0.86, 0.86)
	)


static func palette_from_control(control: Control) -> Dictionary:
	if control == null:
		return default_palette()
	var base := _theme_color(control, "base_color", "Editor", Color(0.12, 0.12, 0.12))
	var accent := _theme_color(control, "accent_color", "Editor", Color(0.37, 0.58, 0.92))
	var font := _theme_color(control, "font_color", "Label", _readable_text_for(base))
	return palette_from_values(base, accent, font)


static func palette_from_values(base: Color, accent: Color, font: Color) -> Dictionary:
	var light := _is_light(base)
	var surface_delta := -0.08 if light else 0.08
	var subtle_delta := -0.04 if light else 0.04
	var strong_delta := -0.14 if light else 0.14
	var body_font := font if font.a > 0.0 else _readable_text_for(base)
	var muted_font := body_font.lerp(base, 0.42)
	var user_bg := _shift(base.lerp(accent, 0.18), subtle_delta)
	var status_bg := _shift(base, surface_delta)
	var assistant_bg := _shift(base, subtle_delta)
	var work_bg := _shift(base, surface_delta)
	var diff_bg := _shift(base.lerp(Color(0.95, 0.74, 0.25), 0.12), surface_delta)
	var diff_details_bg := _shift(diff_bg, surface_delta)
	return {
		"base": base,
		"accent": accent,
		"body_font": body_font,
		"muted_font": muted_font,
		"user_background": _opaque(user_bg),
		"user_accent": accent,
		"status_background": _opaque(status_bg),
		"status_accent": _shift(base, strong_delta),
		"assistant_background": _opaque(assistant_bg),
		"assistant_accent": _shift(base, strong_delta),
		"work_background": _opaque(work_bg),
		"work_accent": _shift(base, strong_delta),
		"diff_background": _opaque(diff_bg),
		"diff_accent": Color(0.92, 0.72, 0.30).lerp(accent, 0.18),
		"diff_font": Color(0.92, 0.78, 0.38) if not light else Color(0.42, 0.31, 0.05),
		"diff_details_background": _opaque(diff_details_bg),
		"diff_details_accent": _shift(diff_bg, strong_delta),
		"diff_line_default_background": _opaque(_shift(base, surface_delta)),
		"diff_line_default_font": body_font,
		"diff_line_added_background": _opaque(_shift(base.lerp(Color(0.24, 0.72, 0.32), 0.22), surface_delta)),
		"diff_line_added_font": Color(0.07, 0.42, 0.12) if light else Color(0.62, 0.94, 0.66),
		"diff_line_removed_background": _opaque(_shift(base.lerp(Color(0.88, 0.22, 0.22), 0.22), surface_delta)),
		"diff_line_removed_font": Color(0.55, 0.08, 0.08) if light else Color(1.0, 0.62, 0.62),
		"diff_line_hunk_background": _opaque(_shift(base.lerp(accent, 0.18), surface_delta)),
		"diff_line_hunk_font": Color(0.12, 0.24, 0.62) if light else Color(0.62, 0.74, 1.0),
		"diff_line_file_header_background": _opaque(_shift(base.lerp(Color(0.95, 0.74, 0.25), 0.16), surface_delta)),
		"diff_line_file_header_font": Color(0.42, 0.31, 0.05) if light else Color(0.92, 0.78, 0.38),
		"copy_feedback_modulate": Color(0.07, 0.42, 0.12) if light else Color(0.62, 0.92, 0.68),
		"copy_default_modulate": Color(1, 1, 1),
	}


static func palette_values(palette: Dictionary) -> Dictionary:
	var values := default_palette()
	for key in palette.keys():
		values[key] = palette.get(key)
	return values


static func bubble_style(kind: String, palette: Dictionary) -> Dictionary:
	var values := palette_values(palette)
	match kind:
		"user":
			return {"background": values.get("user_background"), "accent": values.get("user_accent")}
		"status":
			return {"background": values.get("status_background"), "accent": values.get("status_accent")}
		"work":
			return {"background": values.get("work_background"), "accent": values.get("work_accent")}
		"diff":
			return {"background": values.get("diff_background"), "accent": values.get("diff_accent")}
		_:
			return {"background": values.get("assistant_background"), "accent": values.get("assistant_accent")}


static func _theme_color(control: Control, name: StringName, theme_type: StringName, fallback: Color) -> Color:
	if control.has_theme_color(name, theme_type):
		return control.get_theme_color(name, theme_type)
	return fallback


static func _shift(color: Color, amount: float) -> Color:
	if amount >= 0.0:
		return color.lerp(Color(1, 1, 1, color.a), amount)
	return color.lerp(Color(0, 0, 0, color.a), -amount)


static func _opaque(color: Color) -> Color:
	return Color(color.r, color.g, color.b, 1.0)


static func _readable_text_for(base: Color) -> Color:
	return Color(0.08, 0.08, 0.08) if _is_light(base) else Color(0.86, 0.86, 0.86)


static func _is_light(color: Color) -> bool:
	var luminance := 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b
	return luminance >= 0.55
