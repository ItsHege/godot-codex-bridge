extends SceneTree

const ChatInputModel := preload("res://addons/godot_codex_bridge/core/chat_input_model.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge chat input model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge chat input model tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	_assert_eq(ChatInputModel.key_event_action(_key(KEY_ENTER, true, false)), ChatInputModel.ACTION_SEND, "enter sends")
	_assert_eq(ChatInputModel.key_event_action(_key(KEY_KP_ENTER, true, false)), ChatInputModel.ACTION_SEND, "keypad enter sends")
	_assert_eq(ChatInputModel.key_event_action(_key(KEY_ENTER, true, true)), ChatInputModel.ACTION_NEWLINE, "shift enter newline")
	_assert_eq(ChatInputModel.key_event_action_with_shift_override(_key(KEY_ENTER, true, false), true), ChatInputModel.ACTION_NEWLINE, "shift override enter newline")
	_assert_eq(ChatInputModel.key_event_action(_physical_key(KEY_ENTER, KEY_NONE, true, true)), ChatInputModel.ACTION_NEWLINE, "physical shift enter newline")
	_assert_eq(ChatInputModel.key_event_action(_label_key(KEY_ENTER, true, true)), ChatInputModel.ACTION_NEWLINE, "key label shift enter newline")
	_assert_eq(ChatInputModel.key_event_action(_unicode_key(10, true, true)), ChatInputModel.ACTION_NEWLINE, "unicode shift enter newline")
	_assert_eq(ChatInputModel.key_event_action(_key(KEY_A, true, false)), ChatInputModel.ACTION_IGNORE, "other key ignored")
	_assert_eq(ChatInputModel.key_event_action(_key(KEY_ENTER, false, false)), ChatInputModel.ACTION_IGNORE, "released enter ignored")
	_assert_eq(ChatInputModel.key_event_action(_echo_key(KEY_ENTER)), ChatInputModel.ACTION_IGNORE, "echo enter ignored")
	var newline_plan := ChatInputModel.action_effect_plan(ChatInputModel.ACTION_NEWLINE)
	var newline_effects := newline_plan.get("effects", []) as Array
	_assert_eq(newline_plan.get("handled"), true, "newline action handled")
	_assert_eq(newline_effects.size(), 3, "newline action effect count")
	_assert_eq((newline_effects[0] as Dictionary).get("action"), "set_composer_expanded", "newline expands composer")
	_assert_eq((newline_effects[1] as Dictionary).get("text"), "\n", "newline inserts newline")
	_assert_eq((newline_effects[2] as Dictionary).get("action"), "refresh_composer_height", "newline refreshes height")
	var send_plan := ChatInputModel.action_effect_plan(ChatInputModel.ACTION_SEND)
	var send_effects := send_plan.get("effects", []) as Array
	_assert_eq(send_plan.get("handled"), true, "send action handled")
	_assert_eq(send_effects.size(), 1, "send action effect count")
	_assert_eq((send_effects[0] as Dictionary).get("action"), "send_message", "send action sends")
	_assert_eq(ChatInputModel.action_effect_plan(ChatInputModel.ACTION_IGNORE).get("handled"), false, "ignore action unhandled")
	_assert_eq(ChatInputModel.action_effect_plan(ChatInputModel.ACTION_SEND, false).get("handled"), false, "missing input unhandled")
	_assert_eq(ChatInputModel.explicit_line_count(""), 1, "empty text counts as one line")
	_assert_eq(ChatInputModel.explicit_line_count("one\ntwo"), 2, "explicit line count")
	_assert_eq(ChatInputModel.explicit_line_count("one\n"), 2, "trailing newline counts as a new line")
	_assert_eq(ChatInputModel.longest_line_length("one\nthree"), 5, "longest line length")
	_assert_eq(ChatInputModel.composer_height_for_text("", false, 180, 260, 360), 260.0, "empty composer keeps comfortable multiline height")
	_assert_eq(ChatInputModel.composer_height_for_text("one line", false, 180, 260, 360), 260.0, "typed single line composer keeps comfortable height")
	_assert_eq(ChatInputModel.composer_height_for_text("one\ntwo", false, 180, 260, 360), 260.0, "two line composer height")
	_assert_eq(ChatInputModel.composer_height_for_text("one\ntwo\nthree\nfour", false, 180, 260, 360), 360.0, "four line composer height")
	_assert_eq(ChatInputModel.composer_height_for_text("x".repeat(120), false, 180, 260, 360), 360.0, "long line composer height")
	_assert_eq(ChatInputModel.composer_height_for_text_width("x".repeat(60), false, 180, 260, 360, 360), 260.0, "wrapped line medium composer height")
	_assert_eq(ChatInputModel.composer_height_for_text_width("x".repeat(150), false, 180, 260, 360, 360), 360.0, "wrapped line expanded composer height")
	_assert_eq(ChatInputModel.composer_height_for_text("one", true, 180, 260, 360), 360.0, "manual expand composer height")
	_assert_eq(ChatInputModel.estimated_visual_line_count("x".repeat(60), 360), 2, "estimated visual line count uses width")
	_assert_eq(ChatInputModel.should_auto_expand_composer("one\ntwo", 360), true, "newline makes composer sticky expanded")
	_assert_eq(ChatInputModel.should_auto_expand_composer("x".repeat(120), 360), true, "long line makes composer sticky expanded")
	_assert_eq(ChatInputModel.should_auto_expand_composer("x".repeat(90), 360), true, "wrapped text makes composer sticky expanded")
	_assert_eq(ChatInputModel.should_auto_expand_composer("short prompt", 360), false, "short prompt stays compact")
	_assert_eq(ChatInputModel.should_rescue_collapsed_composer(120.0, 260.0), true, "short rendered input triggers rescue expand")
	_assert_eq(ChatInputModel.should_rescue_collapsed_composer(240.0, 260.0), false, "comfortable rendered input does not rescue expand")
	_assert_eq(ChatInputModel.should_rescue_collapsed_composer(0.0, 260.0), false, "unlaid out input does not rescue expand")


func _key(keycode: Key, pressed: bool, shift_pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	event.shift_pressed = shift_pressed
	return event


func _physical_key(physical_keycode: Key, keycode: Key, pressed: bool, shift_pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = physical_keycode
	event.pressed = pressed
	event.shift_pressed = shift_pressed
	return event


func _label_key(key_label: Key, pressed: bool, shift_pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.key_label = key_label
	event.pressed = pressed
	event.shift_pressed = shift_pressed
	return event


func _unicode_key(unicode: int, pressed: bool, shift_pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.unicode = unicode
	event.pressed = pressed
	event.shift_pressed = shift_pressed
	return event


func _echo_key(keycode: Key) -> InputEventKey:
	var event := _key(keycode, true, false)
	event.echo = true
	return event


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures += 1
		push_error(label + " expected=" + str(expected) + " actual=" + str(actual))
