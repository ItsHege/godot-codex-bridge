extends SceneTree

const ChatSessionModel := preload("res://addons/godot_codex_bridge/core/chat_session_model.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge chat session model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge chat session model tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	_assert_eq(ChatSessionModel.short_thread_id(""), "new", "empty thread id")
	_assert_eq(ChatSessionModel.thread_label(""), "Thread: new", "new thread label")
	_assert_eq(ChatSessionModel.short_thread_id("abc123"), "abc123", "short thread id")
	_assert_eq(ChatSessionModel.short_thread_id("019ec691-132a-7242-9713-c63056b8aa75"), "019ec691...aa75", "long thread id")
	_assert_true(ChatSessionModel.can_start_new_chat("ready"), "ready can start new chat")
	_assert_false(ChatSessionModel.can_start_new_chat("turn_running"), "turn running cannot start new chat")
	_assert_false(ChatSessionModel.can_start_new_chat("waiting_for_approval"), "approval cannot start new chat")
	_assert_true(ChatSessionModel.can_clear_transcript(1), "can clear messages")
	_assert_false(ChatSessionModel.can_clear_transcript(0), "cannot clear empty transcript")
	_assert_true(ChatSessionModel.new_chat_tooltip("", "ready").contains("already start"), "new empty tooltip")
	_assert_true(ChatSessionModel.new_chat_tooltip("abc", "ready").contains("starts a new"), "new existing tooltip")
	_assert_true(ChatSessionModel.new_chat_tooltip("abc", "turn_running").contains("still working"), "busy tooltip")


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
