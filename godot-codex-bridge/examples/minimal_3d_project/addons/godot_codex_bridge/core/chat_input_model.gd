@tool
extends RefCounted

const ACTION_IGNORE := "ignore"
const ACTION_SEND := "send"
const ACTION_NEWLINE := "newline"

const AUTO_MEDIUM_LINE_THRESHOLD := 2
const AUTO_EXPANDED_LINE_THRESHOLD := 4
const AUTO_STICKY_EXPANDED_LINE_THRESHOLD := 3
const LONG_LINE_CHAR_THRESHOLD := 120
const APPROX_CHAR_WIDTH_PX := 8.5
const MIN_VISUAL_CHARS_PER_LINE := 28
const RESCUE_RENDERED_HEIGHT_RATIO := 0.70


static func key_event_action(event: InputEventKey) -> String:
	return key_event_action_with_shift_override(event, false)


static func key_event_action_with_shift_override(event: InputEventKey, shift_down_override: bool) -> String:
	if event == null:
		return ACTION_IGNORE
	if not event.pressed or event.echo:
		return ACTION_IGNORE
	if not _is_enter_key(event):
		return ACTION_IGNORE
	return ACTION_NEWLINE if event.shift_pressed or shift_down_override else ACTION_SEND


static func action_effect_plan(action: String, input_available := true) -> Dictionary:
	var effects: Array[Dictionary] = []
	if not input_available:
		return {
			"handled": false,
			"effects": effects,
		}
	match action:
		ACTION_NEWLINE:
			effects.append({"action": "set_composer_expanded", "expanded": true})
			effects.append({"action": "insert_text_at_caret", "text": "\n"})
			effects.append({"action": "refresh_composer_height", "auto_expand_from_text": true})
		ACTION_SEND:
			effects.append({"action": "send_message"})
		_:
			return {
				"handled": false,
				"effects": effects,
			}
	return {
		"handled": true,
		"effects": effects,
	}


static func _is_enter_key(event: InputEventKey) -> bool:
	return _is_enter_code(event.keycode) or _is_enter_code(event.physical_keycode) or _is_enter_code(event.key_label) or _is_enter_unicode(event.unicode)


static func _is_enter_code(code: Key) -> bool:
	return code == KEY_ENTER or code == KEY_KP_ENTER


static func _is_enter_unicode(code: int) -> bool:
	return code == 10 or code == 13


static func composer_height_for_text(text: String, manually_expanded: bool, collapsed_height: float, medium_height: float, expanded_height: float) -> float:
	return composer_height_for_text_width(text, manually_expanded, collapsed_height, medium_height, expanded_height, 0.0)


static func composer_height_for_text_width(text: String, manually_expanded: bool, collapsed_height: float, medium_height: float, expanded_height: float, input_width: float) -> float:
	if manually_expanded:
		return expanded_height
	var comfortable_height := max(collapsed_height, medium_height)
	var line_count := explicit_line_count(text)
	var longest_line := longest_line_length(text)
	var visual_line_count := max(line_count, estimated_visual_line_count(text, input_width))
	if visual_line_count >= AUTO_EXPANDED_LINE_THRESHOLD or longest_line >= LONG_LINE_CHAR_THRESHOLD:
		return expanded_height
	return comfortable_height


static func should_auto_expand_composer(text: String, input_width: float) -> bool:
	if explicit_line_count(text) >= 2:
		return true
	if longest_line_length(text) >= LONG_LINE_CHAR_THRESHOLD:
		return true
	return estimated_visual_line_count(text, input_width) >= AUTO_STICKY_EXPANDED_LINE_THRESHOLD


static func should_rescue_collapsed_composer(rendered_height: float, comfortable_height: float) -> bool:
	if comfortable_height <= 0.0:
		return false
	if rendered_height <= 0.0:
		return false
	return rendered_height < comfortable_height * RESCUE_RENDERED_HEIGHT_RATIO


static func explicit_line_count(text: String) -> int:
	if text.is_empty():
		return 1
	var count := 1
	for index in text.length():
		if text.unicode_at(index) == 10:
			count += 1
	return count


static func longest_line_length(text: String) -> int:
	var longest := 0
	for line in text.split("\n", false):
		longest = max(longest, line.length())
	return longest


static func estimated_visual_line_count(text: String, input_width: float) -> int:
	if text.is_empty():
		return 1
	var chars_per_line := LONG_LINE_CHAR_THRESHOLD
	if input_width > 0.0:
		chars_per_line = max(MIN_VISUAL_CHARS_PER_LINE, int(floor(input_width / APPROX_CHAR_WIDTH_PX)))
	var count := 0
	for line in text.split("\n", false):
		count += max(1, int(ceil(float(line.length()) / float(chars_per_line))))
	return count
