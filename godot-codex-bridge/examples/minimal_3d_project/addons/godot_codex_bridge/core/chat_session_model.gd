@tool
extends RefCounted

const ChatStatusModel := preload("chat_status_model.gd")

const SHORT_THREAD_PREFIX := 8
const SHORT_THREAD_SUFFIX := 4


static func short_thread_id(thread_id: String) -> String:
	var trimmed := thread_id.strip_edges()
	if trimmed == "":
		return "new"
	if trimmed.length() <= SHORT_THREAD_PREFIX + SHORT_THREAD_SUFFIX + 3:
		return trimmed
	return trimmed.substr(0, SHORT_THREAD_PREFIX) + "..." + trimmed.substr(trimmed.length() - SHORT_THREAD_SUFFIX)


static func thread_label(thread_id: String) -> String:
	return "Thread: " + short_thread_id(thread_id)


static func can_start_new_chat(runtime_state: String) -> bool:
	return not ChatStatusModel.is_foreground_busy(runtime_state)


static func new_chat_tooltip(thread_id: String, runtime_state: String) -> String:
	if not can_start_new_chat(runtime_state):
		return "Codex is still working. Cancel or wait before starting a new chat."
	if thread_id.strip_edges() == "":
		return "The next message will already start a new Codex thread."
	return "Clear the current thread id. The next message starts a new Codex thread."


static func can_clear_transcript(message_count: int) -> bool:
	return message_count > 0
