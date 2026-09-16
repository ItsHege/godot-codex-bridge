@tool
extends RefCounted


static func truncate_text(text: String, limit: int) -> String:
	if limit <= 0:
		return ""
	if text.length() <= limit:
		return text
	if limit <= 3:
		return text.substr(0, limit)
	return text.substr(0, limit - 3) + "..."


static func append_detail(
	current_log: Array,
	text: String,
	timestamp: String,
	max_events: int,
	entry_limit: int,
	event_limit: int
) -> Dictionary:
	var entries := current_log.duplicate(true)
	entries.append({
		"at": timestamp,
		"message": truncate_text(text, entry_limit),
	})

	var bounded_max: int = max(max_events, 0)
	if bounded_max == 0:
		entries.clear()
	else:
		while entries.size() > bounded_max:
			entries.pop_front()

	return {
		"entries": entries,
		"log_event_type": "codex_chat_detail",
		"log_event_data": {
			"message": truncate_text(text, event_limit),
		},
	}
