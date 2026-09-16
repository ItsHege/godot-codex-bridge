extends SceneTree

const ChatDiffView := preload("res://addons/godot_codex_bridge/core/chat_diff_view.gd")
const ChatThemeModel := preload("res://addons/godot_codex_bridge/core/chat_theme_model.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge chat diff view tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge chat diff view tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var dark_palette := ChatThemeModel.palette_from_values(Color(0.10, 0.10, 0.10), Color(0.40, 0.60, 0.90), Color(0.90, 0.90, 0.90))
	var light_palette := ChatThemeModel.palette_from_values(Color(0.88, 0.88, 0.88), Color(0.10, 0.32, 0.72), Color(0.08, 0.08, 0.08))

	var dark_added := ChatDiffView.line_background("+new", dark_palette)
	var light_added := ChatDiffView.line_background("+new", light_palette)
	_assert_true(_luminance(light_added) > _luminance(dark_added), "diff added background follows light palette")

	var dark_removed := ChatDiffView.line_background("-old", dark_palette)
	var light_removed := ChatDiffView.line_background("-old", light_palette)
	_assert_true(_luminance(light_removed) > _luminance(dark_removed), "diff removed background follows light palette")

	var added_font := ChatDiffView.line_foreground("+new", light_palette)
	var removed_font := ChatDiffView.line_foreground("-old", light_palette)
	_assert_true(added_font != removed_font, "diff line foregrounds distinguish added and removed")

	var section := ChatDiffView.create_file_section({
		"path": "res://scripts/player.gd",
		"added": 1,
		"removed": 1,
		"lines": PackedStringArray(["@@", "-old", "+new"]),
	}, Callable(), light_palette)
	_assert_true(section is VBoxContainer, "diff file section is container")
	_assert_true(section.has_meta("chat_diff_file_section"), "diff file section metadata")
	var toggle := section.get_child(0) as Button
	_assert_true(toggle != null, "diff file section has toggle")
	_assert_true(toggle.focus_mode == Control.FOCUS_ALL, "diff file toggle supports keyboard focus")
	section.free()


func _luminance(color: Color) -> float:
	return 0.2126 * color.r + 0.7152 * color.g + 0.0722 * color.b


func _assert_true(value: bool, label: String) -> void:
	if not value:
		_failures += 1
		push_error(label)
