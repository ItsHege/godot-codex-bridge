extends SceneTree

const ChatTranscriptBatchModel := preload("res://addons/godot_codex_bridge/core/chat_transcript_batch_model.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge chat transcript batch model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge chat transcript batch model tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var empty_delta := ChatTranscriptBatchModel.assistant_delta_route("")
	_assert_eq(empty_delta.get("route"), "ignore", "empty assistant delta ignored")
	var work_delta := ChatTranscriptBatchModel.assistant_delta_route("Patikrinsiu failus ir testus.")
	_assert_eq(work_delta.get("route"), "work", "progress-like delta routes to work notes")
	_assert_eq(work_delta.get("phase"), "commentary", "progress-like delta becomes commentary")
	var active_answer_delta := ChatTranscriptBatchModel.assistant_delta_route("Patikrinsiu failus ir testus.", "", "final_answer")
	_assert_eq(active_answer_delta.get("route"), "assistant", "active assistant phase keeps ambiguous text in answer")
	var final_delta := ChatTranscriptBatchModel.assistant_delta_route("Galutinis atsakymas.", "final_answer")
	_assert_eq(final_delta.get("route"), "assistant", "final answer routes to assistant")
	_assert_eq(final_delta.get("phase"), "final_answer", "final answer phase normalized")

	var work_state := ChatTranscriptBatchModel.empty_work_state()
	_assert_eq(work_state.get("text"), "", "empty work text")
	_assert_eq(work_state.get("updates"), 0, "empty work updates")
	_assert_false(bool(ChatTranscriptBatchModel.record_work_update(work_state, "   ").get("changed", true)), "blank work update ignored")
	var blank_work_plan := ChatTranscriptBatchModel.record_work_update_effect_plan(work_state, "   ", "", false)
	_assert_false(bool(blank_work_plan.get("changed", true)), "blank work effect plan ignored")
	_assert_eq((blank_work_plan.get("effects", []) as Array).size(), 0, "blank work effect plan has no effects")

	var first_work := ChatTranscriptBatchModel.record_work_update(work_state, "Checking files.", "item-1")
	_assert_true(bool(first_work.get("changed", false)), "first work update changes state")
	work_state = first_work.get("state", {}) as Dictionary
	_assert_eq(work_state.get("updates"), 1, "first work update count")
	_assert_eq(work_state.get("item_id"), "item-1", "first work item id")
	_assert_eq(work_state.get("text"), "Checking files.", "first work text")
	var first_work_plan := ChatTranscriptBatchModel.record_work_update_effect_plan(ChatTranscriptBatchModel.empty_work_state(), "Checking files.", "item-1", false)
	var first_effects := first_work_plan.get("effects", []) as Array
	_assert_eq(first_effects.size(), 4, "first work update has create-panel effect count")
	_assert_eq((first_effects[0] as Dictionary).get("action"), "flush_assistant_text", "first work flushes assistant first")
	_assert_eq((first_effects[1] as Dictionary).get("action"), "apply_work_state", "first work applies state second")
	_assert_eq((first_effects[2] as Dictionary).get("action"), "ensure_work_panel", "first work creates panel third")
	_assert_eq((first_effects[3] as Dictionary).get("action"), "update_work_batch", "first work updates panel last")

	var same_item := ChatTranscriptBatchModel.record_work_update(work_state, " Running tests.", "item-1")
	work_state = same_item.get("state", {}) as Dictionary
	_assert_eq(work_state.get("updates"), 1, "same item appends without new update")
	_assert_eq(work_state.get("text"), "Checking files. Running tests.", "same item text appended")
	var existing_panel_plan := ChatTranscriptBatchModel.record_work_update_effect_plan(work_state, " More checks.", "item-1", true)
	var existing_effects := existing_panel_plan.get("effects", []) as Array
	_assert_eq(existing_effects.size(), 3, "existing work panel skips create effect")
	_assert_eq((existing_effects[2] as Dictionary).get("action"), "update_work_batch", "existing panel still updates batch")

	var next_item := ChatTranscriptBatchModel.record_work_update(work_state, "Reviewing results.", "item-2")
	work_state = next_item.get("state", {}) as Dictionary
	_assert_eq(work_state.get("updates"), 2, "new item increments updates")
	_assert_true(str(work_state.get("text", "")).find("\n\nReviewing results.") >= 0, "new item separated by blank line")
	work_state = ChatTranscriptBatchModel.work_state_visible(work_state, true)
	_assert_true(bool(work_state.get("visible", false)), "work visible state")

	var diff_state := ChatTranscriptBatchModel.empty_diff_state()
	var diff_text := "\n".join([
		"diff --git a/scripts/player.gd b/scripts/player.gd",
		"--- a/scripts/player.gd",
		"+++ b/scripts/player.gd",
		"@@",
		"-old",
		"+new",
	])
	var diff_update := ChatTranscriptBatchModel.record_diff_update(diff_state, diff_text)
	diff_state = diff_update.get("state", {}) as Dictionary
	_assert_eq(diff_state.get("updates"), 1, "diff update count")
	_assert_eq((diff_state.get("files", PackedStringArray()) as PackedStringArray).size(), 1, "diff file extracted")
	var first_diff_plan := ChatTranscriptBatchModel.record_diff_update_effect_plan(ChatTranscriptBatchModel.empty_diff_state(), diff_text, false)
	var first_diff_effects := first_diff_plan.get("effects", []) as Array
	_assert_eq(first_diff_effects.size(), 4, "first diff update has create-panel effect count")
	_assert_eq((first_diff_effects[0] as Dictionary).get("action"), "flush_assistant_text", "first diff flushes assistant first")
	_assert_eq((first_diff_effects[1] as Dictionary).get("action"), "apply_diff_state", "first diff applies state second")
	_assert_eq((first_diff_effects[2] as Dictionary).get("action"), "ensure_diff_panel", "first diff creates panel third")
	_assert_eq((first_diff_effects[3] as Dictionary).get("action"), "update_diff_batch", "first diff updates panel last")
	var existing_diff_plan := ChatTranscriptBatchModel.record_diff_update_effect_plan(diff_state, diff_text, true)
	var existing_diff_effects := existing_diff_plan.get("effects", []) as Array
	_assert_eq(existing_diff_effects.size(), 3, "existing diff panel skips create effect")
	_assert_eq((existing_diff_effects[2] as Dictionary).get("action"), "update_diff_batch", "existing diff panel still updates batch")

	diff_state = ChatTranscriptBatchModel.diff_state_with_counts(diff_state, {
		"file_count": 1,
		"added_count": 1,
		"removed_count": 1,
	})
	_assert_eq(diff_state.get("file_count"), 1, "diff file count stored")
	_assert_eq(diff_state.get("added_count"), 1, "diff added count stored")
	_assert_eq(diff_state.get("removed_count"), 1, "diff removed count stored")
	diff_state = ChatTranscriptBatchModel.diff_state_visible(diff_state, true)
	_assert_true(bool(diff_state.get("files_visible", false)), "diff files visible state")


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
