extends SceneTree

const ChatTranscriptModel := preload("res://addons/godot_codex_bridge/core/chat_transcript_model.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge chat transcript model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge chat transcript model tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var files_changed := "\n".join([
		"files_changed:",
		"- scripts/save/save_service.gd",
		"- scenes/main/Main.tscn",
		"- scenes/main/GameScreen.tscn",
		"- scenes/board/CultBoard.tscn",
		"- scenes/ui/RightInspector.tscn",
		"- scripts/ui/game_screen.gd",
		"- scripts/ui/cult_board.gd",
	])
	_assert_true(ChatTranscriptModel.should_collapse_text(files_changed, 1200, 14), "files changed summary collapses even when under character limit")
	var preview := ChatTranscriptModel.collapsed_preview(files_changed, 220, 3)
	_assert_true(preview.begins_with("Files changed summary:"), "files changed preview starts with summary")
	_assert_true(preview.find("[collapsed - press More") >= 0, "collapsed preview includes action hint")

	var work_text := "Checking files now.\nRunning validation.\nReading scene data."
	_assert_true(ChatTranscriptModel.looks_like_work_update("Checking files now."), "english work update detected")
	_assert_true(ChatTranscriptModel.looks_like_work_update("Patikrinsiu scenas."), "lithuanian work update detected")
	var compact := ChatTranscriptModel.compact_collapsed_preview(work_text, 48, 2)
	_assert_true(compact.begins_with("Work note - "), "compact work note prefix")
	_assert_true(compact.find("[More]") >= 0, "compact work note has more hint")
	var work_summary := ChatTranscriptModel.work_batch_summary(3, work_text, 64, 2)
	_assert_true(work_summary.begins_with("Work notes: 3 updates."), "work batch summary counts updates")
	_assert_true(work_summary.find("Checking files now.") >= 0, "work batch summary includes compact preview")
	_assert_eq(ChatTranscriptModel.work_batch_toggle_text(false, 3), "Show 3 notes", "work batch collapsed toggle")
	_assert_eq(ChatTranscriptModel.work_batch_toggle_text(true, 3), "Hide notes", "work batch expanded toggle")

	_assert_eq(ChatTranscriptModel.normalize_message_phase(" Commentary "), "commentary", "normalizes commentary phase")
	_assert_eq(ChatTranscriptModel.normalize_message_phase("final_answer"), "final_answer", "normalizes final phase")
	_assert_eq(ChatTranscriptModel.normalize_message_phase("debug"), "", "unknown phase discarded")

	var commentary_style := ChatTranscriptModel.assistant_style("commentary")
	_assert_eq(str(commentary_style.get("author", "")), "Work", "commentary uses Work author")
	_assert_eq(bool(commentary_style.get("force_collapsed", false)), true, "commentary force collapses")
	var final_style := ChatTranscriptModel.assistant_style("final_answer")
	_assert_eq(str(final_style.get("author", "")), "Codex", "final answer uses Codex author")
	_assert_eq(bool(final_style.get("force_collapsed", true)), false, "final answer does not force collapse")

	var section_text := "Intro paragraph.\n\n" + "x".repeat(80) + "\n- bullet\n" + "y".repeat(80)
	var split := ChatTranscriptModel.find_assistant_section_split(section_text, 80)
	_assert_true(split > 0 and split <= 80, "section split stays inside requested limit")

	var truncated := ChatTranscriptModel.truncate_text("abcdef", 3)
	_assert_eq(truncated, "abc\n[truncated]", "truncate appends marker")


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures += 1
		push_error(label + " expected=" + str(expected) + " actual=" + str(actual))


func _assert_true(value: bool, label: String) -> void:
	if not value:
		_failures += 1
		push_error(label)
