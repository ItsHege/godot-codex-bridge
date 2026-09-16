extends SceneTree

const ChatThemeModel := preload("res://addons/godot_codex_bridge/core/chat_theme_model.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge chat theme model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge chat theme model tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var dark_palette := ChatThemeModel.palette_from_values(Color(0.10, 0.10, 0.10), Color(0.40, 0.60, 0.90), Color(0.90, 0.90, 0.90))
	_assert_true(dark_palette.has("user_background"), "dark palette has user background")
	_assert_true(dark_palette.has("body_font"), "dark palette has body font")
	_assert_true(dark_palette.has("diff_line_added_background"), "dark palette has diff line background")
	_assert_true(dark_palette.has("diff_details_background"), "dark palette has diff details background")
	_assert_true(dark_palette.has("copy_feedback_modulate"), "dark palette has copy feedback colour")
	_assert_eq(dark_palette.get("body_font"), Color(0.90, 0.90, 0.90), "dark palette preserves theme font")
	var user_style := ChatThemeModel.bubble_style("user", dark_palette)
	_assert_eq(user_style.get("accent"), dark_palette.get("user_accent"), "user style uses user accent")

	var light_palette := ChatThemeModel.palette_from_values(Color(0.88, 0.88, 0.88), Color(0.10, 0.32, 0.72), Color(0.08, 0.08, 0.08))
	_assert_eq(light_palette.get("body_font"), Color(0.08, 0.08, 0.08), "light palette preserves dark font")
	_assert_true((light_palette.get("diff_line_added_background") as Color).r > (dark_palette.get("diff_line_added_background") as Color).r, "light diff added background follows light theme")
	_assert_true((light_palette.get("copy_feedback_modulate") as Color).r < (dark_palette.get("copy_feedback_modulate") as Color).r, "light copy feedback uses darker readable colour")
	var merged_palette := ChatThemeModel.palette_values({"body_font": Color(0.7, 0.6, 0.5)})
	_assert_eq(merged_palette.get("body_font"), Color(0.7, 0.6, 0.5), "palette merge preserves override")
	_assert_true(merged_palette.has("copy_default_modulate"), "palette merge keeps defaults")
	var status_style := ChatThemeModel.bubble_style("status", light_palette)
	_assert_true((status_style.get("background") as Color).r < 0.88, "light status background darkens from base")
	var assistant_style := ChatThemeModel.bubble_style("assistant", {})
	_assert_true(assistant_style.has("background"), "assistant style falls back with background")

	var fallback_palette := ChatThemeModel.palette_from_control(null)
	_assert_true(fallback_palette.has("accent"), "null control palette has fallback accent")


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures += 1
		push_error(label + " expected=" + str(expected) + " actual=" + str(actual))


func _assert_true(value: bool, label: String) -> void:
	if not value:
		_failures += 1
		push_error(label)
