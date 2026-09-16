@tool
extends RefCounted

const DEFAULT_MAX_MESSAGE_CHARS := 65536
const DEFAULT_ASSISTANT_SECTION_CHARS := 2200
const DEFAULT_COLLAPSE_CHARS := 1200
const DEFAULT_COLLAPSE_LINES := 14
const DEFAULT_PREVIEW_CHARS := 900
const DEFAULT_PREVIEW_LINES := 8
const DEFAULT_WORK_PREVIEW_CHARS := 220
const DEFAULT_WORK_PREVIEW_LINES := 2


static func truncate_text(text: String, limit := DEFAULT_MAX_MESSAGE_CHARS) -> String:
	if text.length() <= limit:
		return text
	return text.substr(0, limit) + "\n[truncated]"


static func should_collapse_text(text: String, collapse_chars := DEFAULT_COLLAPSE_CHARS, collapse_lines := DEFAULT_COLLAPSE_LINES) -> bool:
	if text.length() > collapse_chars:
		return true
	var lines := text.split("\n")
	if lines.size() > collapse_lines:
		return true
	var lower := text.to_lower()
	if lower.find("diff preview batch") >= 0 or lower.find("latest diff:") >= 0:
		return true
	if lower.find("files_changed:") >= 0 or lower.find("files changed:") >= 0:
		return text.length() > 400 or lines.size() > 6
	if lower.find("validation:") >= 0 or lower.find("validation") >= 0:
		return text.length() > 700 or lines.size() > 8
	return false


static func collapsed_preview(text: String, preview_chars := DEFAULT_PREVIEW_CHARS, preview_lines := DEFAULT_PREVIEW_LINES) -> String:
	var lines := text.split("\n")
	var summary := summary_line(text, lines)
	var preview_lines_array := PackedStringArray()
	var preview_chars_used := 0
	for line in lines:
		if preview_lines_array.size() >= preview_lines:
			break
		var line_text := str(line)
		if preview_chars_used + line_text.length() > preview_chars:
			var remaining: int = max(preview_chars - preview_chars_used, 0)
			if remaining > 0:
				preview_lines_array.append(line_text.substr(0, remaining))
			break
		preview_lines_array.append(line_text)
		preview_chars_used += line_text.length() + 1
	var preview := "\n".join(preview_lines_array).strip_edges(false, true)
	if preview == "":
		preview = "[empty message]"
	return summary + "\n\n" + preview + "\n\n[collapsed - press More to expand, Copy to copy full text]"


static func compact_collapsed_preview(text: String, preview_chars := DEFAULT_WORK_PREVIEW_CHARS, preview_lines := DEFAULT_WORK_PREVIEW_LINES) -> String:
	return "Work note - " + compact_work_preview(text, preview_chars, preview_lines) + "\n[More]"


static func compact_work_preview(text: String, preview_chars := DEFAULT_WORK_PREVIEW_CHARS, preview_lines := DEFAULT_WORK_PREVIEW_LINES) -> String:
	var lines := text.split("\n")
	var compact_lines := PackedStringArray()
	var preview_chars_used := 0
	for line in lines:
		var line_text := str(line).strip_edges()
		if line_text == "":
			continue
		if compact_lines.size() >= preview_lines:
			break
		if preview_chars_used + line_text.length() > preview_chars:
			var remaining: int = max(preview_chars - preview_chars_used, 0)
			if remaining > 0:
				compact_lines.append(line_text.substr(0, remaining))
			break
		compact_lines.append(line_text)
		preview_chars_used += line_text.length() + 1
	var preview := " ".join(compact_lines).strip_edges()
	if preview == "":
		preview = "Working update"
	return preview


static func work_batch_summary(update_count: int, text: String, preview_chars := DEFAULT_WORK_PREVIEW_CHARS, preview_lines := DEFAULT_WORK_PREVIEW_LINES) -> String:
	var count: int = max(update_count, 1)
	var suffix := "update" if count == 1 else "updates"
	return "Work notes: " + str(count) + " " + suffix + ". " + compact_work_preview(text, preview_chars, preview_lines)


static func work_batch_toggle_text(visible: bool, update_count: int) -> String:
	if visible:
		return "Hide notes"
	var count: int = max(update_count, 1)
	return "Show " + str(count) + (" note" if count == 1 else " notes")


static func summary_line(text: String, lines: PackedStringArray) -> String:
	var path_count := path_like_line_count(lines)
	var lower := text.to_lower()
	if lower.find("diff preview batch") >= 0 or lower.find("latest diff:") >= 0:
		return "Diff preview: " + str(path_count) + " file(s), " + str(lines.size()) + " lines. Press More to inspect."
	if lower.find("files_changed:") >= 0 or lower.find("files changed:") >= 0:
		return "Files changed summary: " + str(path_count) + " path-like line(s), " + str(lines.size()) + " lines."
	if lower.find("validation") >= 0:
		return "Validation/work summary: " + str(lines.size()) + " lines, " + str(text.length()) + " chars."
	if path_count >= 6:
		return "Project/work summary: " + str(path_count) + " path-like line(s), " + str(lines.size()) + " lines."
	return "Long Codex message: " + str(lines.size()) + " lines, " + str(text.length()) + " chars."


static func path_like_line_count(lines: PackedStringArray) -> int:
	var count := 0
	var extensions := [".gd", ".tscn", ".tres", ".res", ".cfg", ".json", ".uid", ".md", ".png", ".svg", ".shader"]
	for line in lines:
		var lower := str(line).to_lower()
		for extension in extensions:
			if lower.find(extension) >= 0:
				count += 1
				break
	return count


static func normalize_message_phase(phase: String) -> String:
	var value := phase.strip_edges().to_lower()
	if value == "commentary" or value == "final_answer":
		return value
	return ""


static func looks_like_work_update(text: String) -> bool:
	var value := text.strip_edges().to_lower()
	if value == "":
		return false
	var prefixes := [
		"patikrinsiu",
		"pradėsiu",
		"pradesiu",
		"toliau",
		"dabar ",
		"skaitau",
		"skaitysiu",
		"perbėgsiu",
		"perbegsiu",
		"paleisiu",
		"pažiūrėsiu",
		"paziuresiu",
		"radau ",
		"matau ",
		"einu ",
		"kol kas",
		"i'll ",
		"i will ",
		"i’m ",
		"i'm ",
		"checking ",
		"now ",
		"next ",
	]
	for prefix in prefixes:
		if value.begins_with(str(prefix)):
			return true
	return false


static func assistant_style(phase: String) -> Dictionary:
	if phase == "commentary":
		return {
			"author": "Work",
			"background": Color(0.11, 0.11, 0.11),
			"accent": Color(0.38, 0.38, 0.38),
			"force_collapsed": true,
		}
	return {
		"author": "Codex",
		"background": Color(0.12, 0.12, 0.12),
		"accent": Color(0.25, 0.25, 0.25),
		"force_collapsed": false,
	}


static func find_assistant_section_split(text: String, section_chars := DEFAULT_ASSISTANT_SECTION_CHARS) -> int:
	var max_split: int = min(text.length(), section_chars)
	var min_split: int = min(text.length(), int(section_chars / 2))
	var search_text := text.substr(0, max_split)
	var split := search_text.rfind("\n\n")
	if split >= min_split:
		return split + 2
	split = search_text.rfind("\n- ")
	if split >= min_split:
		return split + 1
	split = search_text.rfind("\n")
	if split >= min_split:
		return split + 1
	split = search_text.rfind(". ")
	if split >= min_split:
		return split + 2
	return max_split
