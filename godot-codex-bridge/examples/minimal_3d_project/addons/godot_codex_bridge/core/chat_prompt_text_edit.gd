@tool
extends TextEdit

signal chat_enter_action(action: String)

const ChatInputModel := preload("chat_input_model.gd")

var _action_handler: Callable


func set_action_handler(handler: Callable) -> void:
	_action_handler = handler


func handle_key_event(event: InputEventKey, shift_down_override: bool = false) -> bool:
	var action := ChatInputModel.key_event_action_with_shift_override(event, shift_down_override)
	if action == ChatInputModel.ACTION_IGNORE:
		return false
	accept_event()
	if _action_handler.is_valid():
		_action_handler.call(action)
	else:
		chat_enter_action.emit(action)
	return true


func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		handle_key_event(key_event, key_event.shift_pressed or Input.is_key_pressed(KEY_SHIFT))


func _shortcut_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		handle_key_event(key_event, key_event.shift_pressed or Input.is_key_pressed(KEY_SHIFT))


func _unhandled_key_input(event: InputEvent) -> void:
	if not has_focus():
		return
	if event is InputEventKey:
		var key_event := event as InputEventKey
		handle_key_event(key_event, key_event.shift_pressed or Input.is_key_pressed(KEY_SHIFT))
