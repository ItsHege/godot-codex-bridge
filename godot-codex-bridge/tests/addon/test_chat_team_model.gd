extends SceneTree

const ChatTeamModel := preload("res://addons/godot_codex_bridge/core/chat_team_model.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge chat team model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge chat team model tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	_assert_true(ChatTeamModel.is_active_state("queued"), "queued active")
	_assert_true(ChatTeamModel.is_active_state("running"), "running active")
	_assert_true(ChatTeamModel.is_active_state("summarizing"), "summarizing active")
	_assert_false(ChatTeamModel.is_active_state("completed"), "completed inactive")

	_assert_eq(ChatTeamModel.prompt_from_input("  "), ChatTeamModel.DEFAULT_PROMPT, "blank prompt default")
	_assert_eq(ChatTeamModel.prompt_from_input(" review scripts "), "review scripts", "prompt trimmed")

	var start := ChatTeamModel.start_payload("check scene")
	_assert_eq(start.get("prompt"), "check scene", "start prompt")
	_assert_eq((start.get("roles", []) as Array).size(), 4, "start roles")

	var cancel_blank := ChatTeamModel.cancel_payload("")
	_assert_false(cancel_blank.has("task_id"), "blank cancel omits task")
	var cancel := ChatTeamModel.cancel_payload(" task-1 ")
	_assert_eq(cancel.get("task_id"), "task-1", "cancel task")

	var update := ChatTeamModel.update_from_params({"task_id": "task-2", "state": "running"}, "old", "queued")
	_assert_eq(update.get("task_id"), "task-2", "update task")
	_assert_eq(update.get("state"), "running", "update state")
	_assert_true(bool(update.get("state_changed", false)), "state changed")

	var restore := ChatTeamModel.restore_from_tasks([
		{"task_id": "done", "state": "completed"},
		{"task_id": "active", "state": "running"},
	], "old", "idle")
	_assert_true(bool(restore.get("has_task", false)), "restore has task")
	_assert_eq(restore.get("task_id"), "active", "restore active task")
	_assert_eq(restore.get("state"), "running", "restore active state")

	var restore_last := ChatTeamModel.restore_from_tasks([
		{"task_id": "done", "state": "completed"},
	], "old", "idle")
	_assert_true(bool(restore_last.get("has_task", false)), "restore completed task")
	_assert_eq(restore_last.get("task_id"), "done", "restore completed id")

	var empty_restore := ChatTeamModel.restore_from_tasks([], "old", "idle")
	_assert_false(bool(empty_restore.get("has_task", true)), "empty restore")
	_assert_eq(empty_restore.get("task_id"), "old", "empty keeps task")

	var status := ChatTeamModel.status_text("completed", {
		"results": [
			{"state": "completed"},
			{"state": "failed"},
			{"state": "cancelled"},
			{"state": "running"},
		],
		"summary_path": "C:/summary.md",
	})
	_assert_eq(status, "Team: completed | roles 1/4 done | 1 failed | 1 cancelled | summary ready", "status text")

	var messages := ChatTeamModel.update_messages({"summary_path": "C:/summary.md"}, "failed", true)
	_assert_eq((messages.get("system_messages", []) as Array).size(), 2, "messages system count")
	_assert_eq(((messages.get("system_messages", []) as Array)[1]), "Background partial summary is ready.", "partial summary message")
	_assert_eq((messages.get("detail_messages", []) as Array)[0], "Background summary: C:/summary.md", "summary detail")

	var update_plan := ChatTeamModel.background_update_plan({
		"state": "summarizing",
		"summary_path": "C:/summary.md",
		"results": [
			{"state": "completed"},
			{"state": "running"},
		],
	}, "task-old", "running")
	_assert_eq(update_plan.get("task_id"), "task-old", "update plan keeps current task when missing")
	_assert_eq(update_plan.get("state"), "summarizing", "update plan state")
	_assert_eq((update_plan.get("status_params", {}) as Dictionary).get("summary_path"), "C:/summary.md", "update plan status params")
	_assert_eq(((update_plan.get("system_messages", []) as Array)[0]), "Background team summarizing.", "update plan state message")
	_assert_eq(((update_plan.get("system_messages", []) as Array)[1]), "Background summary is ready.", "update plan summary message")
	_assert_eq((update_plan.get("detail_messages", []) as Array)[0], "Background summary: C:/summary.md", "update plan detail message")
	_assert_true(bool(update_plan.get("update_ui", false)), "update plan updates ui")
	var update_effects := ChatTeamModel.background_update_effect_plan(update_plan).get("effects", []) as Array
	_assert_eq(update_effects.size(), 7, "update effects count")
	_assert_eq((update_effects[0] as Dictionary).get("type"), "set_background_task_id", "update effect task id")
	_assert_eq((update_effects[0] as Dictionary).get("task_id"), "task-old", "update effect task value")
	_assert_eq((update_effects[1] as Dictionary).get("type"), "set_background_state", "update effect state")
	_assert_eq((update_effects[1] as Dictionary).get("state"), "summarizing", "update effect state value")
	_assert_eq((update_effects[2] as Dictionary).get("type"), "update_background_status_label", "update effect status label")
	_assert_eq((update_effects[3] as Dictionary).get("type"), "system_message", "update effect state message")
	_assert_eq((update_effects[4] as Dictionary).get("type"), "system_message", "update effect summary message")
	_assert_eq((update_effects[5] as Dictionary).get("type"), "detail_message", "update effect detail message")
	_assert_eq((update_effects[6] as Dictionary).get("type"), "update_ui", "update effect ui")

	var unchanged_plan := ChatTeamModel.background_update_plan({"state": "running"}, "task-old", "running")
	_assert_eq((unchanged_plan.get("system_messages", []) as Array).size(), 0, "unchanged update plan has no state message")
	var unchanged_effects := ChatTeamModel.background_update_effect_plan(unchanged_plan).get("effects", []) as Array
	_assert_eq(unchanged_effects.size(), 4, "unchanged update effects count")
	_assert_eq((unchanged_effects[3] as Dictionary).get("type"), "update_ui", "unchanged update still refreshes ui")

	var restore_plan := ChatTeamModel.background_restore_plan([
		{"task_id": "done", "state": "completed"},
		{"task_id": "active", "state": "running", "summary_path": "C:/active.md"},
	], "task-old", "idle")
	_assert_true(bool(restore_plan.get("has_task", false)), "restore plan has task")
	_assert_eq(restore_plan.get("task_id"), "active", "restore plan active task")
	_assert_eq(restore_plan.get("state"), "running", "restore plan active state")
	_assert_eq((restore_plan.get("status_params", {}) as Dictionary).get("summary_path"), "C:/active.md", "restore plan status params")
	_assert_true(bool(restore_plan.get("update_status_label", false)), "restore plan updates label")
	var restore_effects := ChatTeamModel.background_restore_effect_plan(restore_plan).get("effects", []) as Array
	_assert_eq(restore_effects.size(), 3, "restore effects count")
	_assert_eq((restore_effects[0] as Dictionary).get("type"), "set_background_task_id", "restore effect task")
	_assert_eq((restore_effects[1] as Dictionary).get("type"), "set_background_state", "restore effect state")
	_assert_eq((restore_effects[2] as Dictionary).get("type"), "update_background_status_label", "restore effect label")

	var empty_restore_plan := ChatTeamModel.background_restore_plan([], "task-old", "idle")
	_assert_false(bool(empty_restore_plan.get("has_task", true)), "empty restore plan no task")
	_assert_eq(empty_restore_plan.get("task_id"), "task-old", "empty restore plan keeps task")
	_assert_eq(empty_restore_plan.get("state"), "idle", "empty restore plan keeps state")
	_assert_false(bool(empty_restore_plan.get("update_status_label", true)), "empty restore plan skips label")
	_assert_true((ChatTeamModel.background_restore_effect_plan(empty_restore_plan).get("effects", []) as Array).is_empty(), "empty restore effects empty")


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
