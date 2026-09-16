extends SceneTree

const ChatTechnicalLogModel := preload("res://addons/godot_codex_bridge/core/chat_technical_log_model.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge chat technical log model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge chat technical log model tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var current := [
		{"at": "old-1", "message": "first"},
		{"at": "old-2", "message": "second"},
	]
	var result := ChatTechnicalLogModel.append_detail(current, "abcdef", "now", 3, 5, 4)
	var entries: Array = result.get("entries", [])
	_assert_eq(entries.size(), 3, "append keeps bounded entry count")
	_assert_eq(str(entries[0].get("message", "")), "first", "first entry preserved")
	_assert_eq(str(entries[2].get("at", "")), "now", "timestamp applied")
	_assert_eq(str(entries[2].get("message", "")), "ab...", "entry text truncated")
	_assert_eq(str(result.get("log_event_type", "")), "codex_chat_detail", "event type")
	_assert_eq(str(result.get("log_event_data", {}).get("message", "")), "a...", "event text uses event limit")
	_assert_eq(current.size(), 2, "input log not mutated")

	var trimmed := ChatTechnicalLogModel.append_detail(current, "third", "now", 2, 2000, 1000)
	var trimmed_entries: Array = trimmed.get("entries", [])
	_assert_eq(trimmed_entries.size(), 2, "trimmed to max")
	_assert_eq(str(trimmed_entries[0].get("message", "")), "second", "oldest entry dropped")
	_assert_eq(str(trimmed_entries[1].get("message", "")), "third", "newest entry kept")

	var cleared := ChatTechnicalLogModel.append_detail(current, "still logged", "now", 0, 2000, 1000)
	_assert_eq((cleared.get("entries", []) as Array).size(), 0, "zero max clears stored entries")
	_assert_eq(str(cleared.get("log_event_data", {}).get("message", "")), "still logged", "event payload still returned when storage disabled")

	_assert_eq(ChatTechnicalLogModel.truncate_text("abcdef", 3), "abc", "tiny limit truncates without marker")
	_assert_eq(ChatTechnicalLogModel.truncate_text("abcdef", 0), "", "zero limit returns empty")


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures += 1
		push_error(label + " expected=" + str(expected) + " actual=" + str(actual))
