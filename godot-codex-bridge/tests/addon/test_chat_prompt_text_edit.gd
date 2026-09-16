extends SceneTree

const ChatInputModel := preload("res://addons/godot_codex_bridge/core/chat_input_model.gd")
const ChatPromptTextEdit := preload("res://addons/godot_codex_bridge/core/chat_prompt_text_edit.gd")

var _failures := 0
var _actions: Array[String] = []


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge chat prompt text edit tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge chat prompt text edit tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var input := ChatPromptTextEdit.new()
	input.chat_enter_action.connect(func(action: String) -> void:
		_actions.append(action)
	)

	_assert_true(input.handle_key_event(_key(KEY_ENTER, true, false)), "enter handled")
	_assert_eq(_actions.size(), 1, "enter emits one action")
	_assert_eq(_actions[0], ChatInputModel.ACTION_SEND, "enter emits send")

	_assert_true(input.handle_key_event(_key(KEY_ENTER, true, true)), "shift enter handled")
	_assert_eq(_actions.size(), 2, "shift enter emits second action")
	_assert_eq(_actions[1], ChatInputModel.ACTION_NEWLINE, "shift enter emits newline")

	_assert_true(input.handle_key_event(_key(KEY_ENTER, true, false), true), "shift override handled")
	_assert_eq(_actions.size(), 3, "shift override emits third action")
	_assert_eq(_actions[2], ChatInputModel.ACTION_NEWLINE, "shift override emits newline")

	_assert_false(input.handle_key_event(_key(KEY_A, true, false)), "non-enter ignored")
	_assert_eq(_actions.size(), 3, "ignored event emits nothing")

	input._shortcut_input(_key(KEY_ENTER, true, true))
	_assert_eq(_actions.size(), 4, "shortcut path emits fourth action")
	_assert_eq(_actions[3], ChatInputModel.ACTION_NEWLINE, "shortcut path shift enter emits newline")

	input._unhandled_key_input(_key(KEY_ENTER, true, true))
	_assert_eq(_actions.size(), 4, "unfocused unhandled path emits nothing")

	input.free()

	var callback_input := ChatPromptTextEdit.new()
	var callback_actions: Array[String] = []
	callback_input.set_action_handler(func(action: String) -> void:
		callback_actions.append(action)
	)
	callback_input.chat_enter_action.connect(func(action: String) -> void:
		_actions.append("signal:" + action)
	)
	callback_input._gui_input(_key(KEY_ENTER, true, true))
	_assert_eq(callback_actions.size(), 1, "gui path calls direct action handler")
	_assert_eq(callback_actions[0], ChatInputModel.ACTION_NEWLINE, "gui path direct handler receives newline")
	_assert_eq(_actions.size(), 4, "direct handler does not double-emit signal")
	callback_input.free()


func _key(keycode: Key, pressed: bool, shift_pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	event.shift_pressed = shift_pressed
	return event


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
