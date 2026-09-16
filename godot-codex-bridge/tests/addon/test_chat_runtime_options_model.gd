extends SceneTree

const ChatRuntimeOptionsModel := preload("res://addons/godot_codex_bridge/core/chat_runtime_options_model.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge chat runtime options model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge chat runtime options model tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var models := ChatRuntimeOptionsModel.normalize_models([
		{"model": "gpt-5.5", "displayName": "GPT-5.5", "isDefault": true},
		{"model": ""},
		"bad",
		{"model": "gpt-5.4", "displayName": "GPT-5.4"},
	])
	_assert_eq(models.size(), 2, "normalize models keeps valid models")
	_assert_eq(models[0].get("model"), "gpt-5.5", "normalize models preserves model id")

	var efforts := ChatRuntimeOptionsModel.normalize_reasoning_efforts([
		{"reasoningEffort": "low", "description": "fast"},
		"high",
		{"reasoningEffort": ""},
		"",
	])
	_assert_eq(efforts.size(), 2, "normalize efforts keeps dicts and strings")
	_assert_eq(efforts[1].get("reasoningEffort"), "high", "normalize string effort")

	var fallback := ChatRuntimeOptionsModel.reasoning_efforts_or_default([])
	_assert_true(fallback.size() >= 5, "default reasoning efforts present")
	_assert_eq(ChatRuntimeOptionsModel.reasoning_effort_label("minimal"), "Fast", "minimal label")
	_assert_eq(ChatRuntimeOptionsModel.reasoning_effort_label("xhigh"), "XHigh", "xhigh label")

	var request_ready := ChatRuntimeOptionsModel.request_models_effect_plan(true)
	var request_effects := request_ready.get("effects", []) as Array
	_assert_eq(request_effects.size(), 1, "ready request emits one effect")
	_assert_eq((request_effects[0] as Dictionary).get("type"), "send_json", "ready request sends json")
	_assert_eq((request_effects[0] as Dictionary).get("method"), "runtime.models.list", "ready request method")
	var request_disconnected := ChatRuntimeOptionsModel.request_models_effect_plan(false)
	_assert_eq((request_disconnected.get("effects", []) as Array).size(), 0, "disconnected request emits no effect")

	var update_plan := ChatRuntimeOptionsModel.update_model_options_plan({
		"models": models,
		"reasoningEfforts": ["low", "high"],
		"defaultModel": "gpt-5.5",
	}, [], [])
	_assert_true(bool(update_plan.get("ok", false)), "update plan ok")
	_assert_eq((update_plan.get("models", []) as Array).size(), 2, "update plan normalizes models")
	_assert_eq((update_plan.get("reasoning_efforts", []) as Array).size(), 2, "update plan normalizes efforts")
	_assert_eq(update_plan.get("default_model"), "gpt-5.5", "update plan default model")
	_assert_true(str(update_plan.get("detail_message", "")).contains("2 model"), "update plan detail message")

	var warning_plan := ChatRuntimeOptionsModel.update_model_options_plan({
		"models": [],
		"error": "fallback used",
	}, [], [])
	_assert_true(str(warning_plan.get("detail_message", "")).contains("warning"), "warning plan detail")

	var update_effect_plan := ChatRuntimeOptionsModel.update_model_options_effect_plan({
		"models": models,
		"reasoningEfforts": ["low", "high"],
		"defaultModel": "gpt-5.5",
	}, [], [])
	var update_effects := update_effect_plan.get("effects", []) as Array
	_assert_true(bool(update_effect_plan.get("ok", false)), "update effect plan ok")
	_assert_eq(update_effects.size(), 5, "update effect count")
	_assert_eq((update_effects[0] as Dictionary).get("action"), "apply_runtime_options", "update effect applies options first")
	_assert_eq(((update_effects[0] as Dictionary).get("models", []) as Array).size(), 2, "update effect models")
	_assert_eq((update_effects[1] as Dictionary).get("action"), "rebuild_model_options", "update effect rebuilds models")
	_assert_eq((update_effects[2] as Dictionary).get("action"), "update_reasoning_options_for_selected_model", "update effect refreshes reasoning")
	_assert_eq((update_effects[3] as Dictionary).get("action"), "detail_message", "update effect detail")
	_assert_eq((update_effects[4] as Dictionary).get("action"), "update_ui", "update effect updates ui last")

	var missing_models_effect_plan := ChatRuntimeOptionsModel.update_model_options_effect_plan({}, models, efforts)
	_assert_false(bool(missing_models_effect_plan.get("ok", true)), "missing models effect ignored")
	_assert_eq((missing_models_effect_plan.get("effects", []) as Array).size(), 0, "missing models effect empty")

	var preserve_plan := ChatRuntimeOptionsModel.update_model_options_plan({
		"models": "bad",
		"reasoningEfforts": "bad",
	}, models, efforts)
	_assert_true(bool(preserve_plan.get("ok", false)), "preserve plan ok")
	_assert_eq((preserve_plan.get("models", []) as Array).size(), 2, "preserve plan keeps current models")
	_assert_eq((preserve_plan.get("reasoning_efforts", []) as Array).size(), 2, "preserve plan keeps current efforts")

	var missing_models_plan := ChatRuntimeOptionsModel.update_model_options_plan({}, models, efforts)
	_assert_false(bool(missing_models_plan.get("ok", true)), "missing models ignored")

	var default_rows := ChatRuntimeOptionsModel.model_option_rows(models, "", "")
	var rows := default_rows.get("rows", []) as Array
	_assert_eq(rows.size(), 3, "model rows include default plus models")
	_assert_eq(int(default_rows.get("select_index", -1)), 1, "model rows select isDefault")
	_assert_eq(((rows[0] as Dictionary).get("metadata", {}) as Dictionary).get("model"), "", "default row metadata")

	var selected_rows := ChatRuntimeOptionsModel.model_option_rows(models, "gpt-5.4", "")
	_assert_eq(int(selected_rows.get("select_index", -1)), 2, "model rows preserve selected model")

	var long_label_rows := ChatRuntimeOptionsModel.model_option_rows([
		{"model": "very-long-model", "displayName": "A very long display model name"}
	], "", "", 12)
	var long_rows := long_label_rows.get("rows", []) as Array
	_assert_eq(str((long_rows[1] as Dictionary).get("label", "")), "A very lo...", "model rows truncate long labels")

	var model_efforts := ChatRuntimeOptionsModel.model_efforts_for_model({
		"supportedReasoningEfforts": ["low", {"reasoningEffort": "medium"}]
	}, fallback)
	_assert_eq(model_efforts.size(), 2, "model-specific efforts override fallback")
	_assert_eq(model_efforts[0].get("reasoningEffort"), "low", "model-specific string effort")

	var selection_effect_plan := ChatRuntimeOptionsModel.model_selection_effect_plan({
		"supportedReasoningEfforts": ["low", "medium"]
	}, fallback, "medium")
	var selection_effects := selection_effect_plan.get("effects", []) as Array
	_assert_eq(selection_effects.size(), 2, "selection effect count")
	_assert_eq((selection_effects[0] as Dictionary).get("action"), "rebuild_reasoning_options", "selection rebuilds reasoning")
	_assert_eq(str((selection_effects[0] as Dictionary).get("selected_effort", "")), "medium", "selection keeps effort")
	_assert_eq(((selection_effects[0] as Dictionary).get("efforts", []) as Array).size(), 2, "selection model-specific efforts")
	_assert_eq((selection_effects[1] as Dictionary).get("action"), "update_ui", "selection updates ui")

	var fallback_selection_effects := (ChatRuntimeOptionsModel.model_selection_effect_plan({}, fallback, "").get("effects", []) as Array)
	_assert_true(((fallback_selection_effects[0] as Dictionary).get("efforts", []) as Array).size() >= 5, "selection falls back to default efforts")

	var runtime_selection := ChatRuntimeOptionsModel.runtime_selection_effect_plan(
		{"model": "gpt-5.4", "effort": "high"},
		[
			{"model": ""},
			{"model": "gpt-5.4"},
			{"model": "gpt-5.5"},
		],
		[
			{"reasoningEffort": ""},
			{"reasoningEffort": "low"},
			{"reasoningEffort": "high"},
		]
	)
	var runtime_selection_effects := runtime_selection.get("effects", []) as Array
	_assert_eq(runtime_selection_effects.size(), 2, "runtime selection effect count")
	_assert_eq((runtime_selection_effects[0] as Dictionary).get("action"), "select_model", "runtime selection selects model")
	_assert_eq(int((runtime_selection_effects[0] as Dictionary).get("index", -1)), 1, "runtime selection model index")
	_assert_true(bool((runtime_selection_effects[0] as Dictionary).get("refresh_reasoning", false)), "runtime selection refreshes reasoning")
	_assert_eq((runtime_selection_effects[1] as Dictionary).get("action"), "select_reasoning", "runtime selection selects reasoning")
	_assert_eq(int((runtime_selection_effects[1] as Dictionary).get("index", -1)), 2, "runtime selection reasoning index")
	_assert_eq(str((runtime_selection_effects[1] as Dictionary).get("effort", "")), "high", "runtime selection effort retained")

	var runtime_unknown := ChatRuntimeOptionsModel.runtime_selection_effect_plan(
		{"model": "missing", "effort": ""},
		[{"model": "gpt-5.4"}],
		[{"reasoningEffort": "low"}]
	)
	_assert_eq((runtime_unknown.get("effects", []) as Array).size(), 0, "unknown runtime selection ignored")

	var reasoning_rows := ChatRuntimeOptionsModel.reasoning_option_rows(model_efforts, "medium")
	var effort_rows := reasoning_rows.get("rows", []) as Array
	_assert_eq(effort_rows.size(), 3, "reasoning rows include default plus efforts")
	_assert_eq(int(reasoning_rows.get("select_index", -1)), 2, "reasoning rows preserve selected effort")
	_assert_eq(str((effort_rows[1] as Dictionary).get("label", "")), "Low", "reasoning rows label effort")

	_assert_eq(ChatRuntimeOptionsModel.selected_model_from_metadata({"model": "gpt-5.5"}), "gpt-5.5", "selected model metadata")
	_assert_eq(ChatRuntimeOptionsModel.selected_reasoning_from_metadata({"reasoningEffort": "high"}), "high", "selected reasoning metadata")
	_assert_eq(ChatRuntimeOptionsModel.selected_model_from_metadata("bad"), "", "bad selected model metadata")

	_assert_eq(ChatRuntimeOptionsModel.selected_index_for_model_metadata([
		{"model": ""},
		{"model": "gpt-5.4"},
		"bad",
		{"model": "gpt-5.5"},
	], "gpt-5.5"), 3, "selected model index")
	_assert_eq(ChatRuntimeOptionsModel.selected_index_for_model_metadata([
		{"model": "gpt-5.4"}
	], ""), -1, "blank selected model index")
	_assert_eq(ChatRuntimeOptionsModel.selected_index_for_model_metadata([
		{"model": "gpt-5.4"}
	], "missing"), -1, "missing selected model index")

	_assert_eq(ChatRuntimeOptionsModel.selected_index_for_reasoning_metadata([
		{"reasoningEffort": ""},
		{"reasoningEffort": "low"},
		{"reasoningEffort": "high"},
	], "high"), 2, "selected reasoning index")
	_assert_eq(ChatRuntimeOptionsModel.selected_index_for_reasoning_metadata([
		{"reasoningEffort": "low"}
	], ""), -1, "blank selected reasoning index")


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
