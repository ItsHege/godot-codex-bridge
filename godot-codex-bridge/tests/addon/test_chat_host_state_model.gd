extends SceneTree

const ChatHostStateModel := preload("res://addons/godot_codex_bridge/core/chat_host_state_model.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge chat host state model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge chat host state model tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var host_patch := ChatHostStateModel.host_status_patch({
		"recoverableMessage": null,
		"fatalMessage": "fatal",
		"trustMode": null,
		"activeProject": {
			"projectRoot": "C:/project",
			"agentsFiles": [
				{"path": "C:/project/AGENTS.md"},
				{"path": ""},
				{"other": true},
			],
		},
	})
	_assert_eq(host_patch.get("recoverable_message"), "", "recoverable null")
	_assert_eq(host_patch.get("fatal_message"), "fatal", "fatal message")
	_assert_eq(host_patch.get("trust_mode"), "off", "trust null")
	_assert_eq(host_patch.get("active_project_root"), "C:/project", "project root")
	_assert_eq(host_patch.get("agents_count"), 3, "agents count preserves host count")
	_assert_eq((host_patch.get("agents_paths", []) as Array).size(), 1, "agents paths filters blanks")

	var tool_patch := ChatHostStateModel.tool_visibility_patch({
		"mcpToolsAvailable": false,
		"mcpToolCount": 7,
		"mcpGodotToolCount": 4,
		"mcpServerName": null,
		"lastToolInventoryAt": "now",
		"toolVisibilityError": "missing tools",
	}, {
		"tools_available": false,
		"last_reported_error": "",
	})
	_assert_false(bool(tool_patch.get("mcp_tools_available", true)), "tools unavailable")
	_assert_eq(tool_patch.get("mcp_tool_count"), 7, "tool count")
	_assert_eq(tool_patch.get("mcp_godot_tool_count"), 4, "godot tool count")
	_assert_eq(tool_patch.get("mcp_server_name"), "", "server null")
	_assert_eq(tool_patch.get("last_tool_inventory_at"), "now", "inventory time")
	_assert_eq(tool_patch.get("tool_visibility_error"), "missing tools", "tool error")
	_assert_eq(tool_patch.get("last_reported_tool_visibility_error"), "missing tools", "last reported")
	_assert_eq((tool_patch.get("detail_messages", []) as Array)[0], "Bridge tools unavailable: missing tools", "tool detail")

	var repeated_tool_patch := ChatHostStateModel.tool_visibility_patch({
		"mcpToolsAvailable": false,
		"toolVisibilityError": "missing tools",
	}, {
		"tools_available": false,
		"last_reported_error": "missing tools",
	})
	_assert_false(repeated_tool_patch.has("detail_messages"), "repeated error no spam")

	var result_patch := ChatHostStateModel.result_state_patch({
		"thread_id": "thread-1",
		"task_id": "task-1",
		"state": "running",
	}, {})
	_assert_eq(result_patch.get("thread_id"), "thread-1", "thread patch")
	_assert_eq(result_patch.get("background_task_id"), "task-1", "task patch")
	_assert_eq(result_patch.get("background_state"), "running", "task state patch")

	var messages := ChatHostStateModel.result_messages({
		"activeProject": {"projectRoot": "C:/project"},
		"trustSessionChanged": true,
		"bridgeToolsEnabled": true,
		"bridgeToolsEvidencePath": "C:/evidence.json",
		"bridgeToolsPreview": true,
		"models": [],
		"tasks": [],
	}, {
		"trust_mode": "full_machine",
		"mcp_tools_available": false,
		"tool_visibility_error": "not visible",
	})
	var system_messages := messages.get("system_messages", []) as Array
	var detail_messages := messages.get("detail_messages", []) as Array
	_assert_eq(system_messages.size(), 3, "system message count")
	_assert_eq(system_messages[0], "Trust Session active: full-machine access for new turns.", "trust message")
	_assert_eq(system_messages[1], "Bridge tools enabled. Evidence: C:/evidence.json", "tools enabled message")
	_assert_eq(system_messages[2], "Bridge tools were registered, but Codex has not reported them yet: not visible", "tools visibility message")
	_assert_eq(detail_messages[0], "Project attached: C:/project", "project detail")
	_assert_eq(detail_messages[1], "Bridge tools preview received.", "preview detail")
	_assert_true(bool(messages.get("has_models", false)), "has models")
	_assert_true(bool(messages.get("has_tasks", false)), "has tasks")

	var token_usage := ChatHostStateModel.token_usage_patch({
		"tokenUsage": {"input": 10, "output": 20},
	})
	_assert_eq(token_usage.get("input"), 10, "token usage input")
	_assert_true(ChatHostStateModel.token_usage_patch({"usage": "bad"}).is_empty(), "bad token usage ignored")

	var plan := ChatHostStateModel.result_plan({
		"state": "turn_running",
		"tokenUsage": {"total": 42},
		"thread_id": "thread-2",
		"task_id": "task-2",
		"mcpToolsAvailable": true,
		"mcpToolCount": 9,
		"trustMode": "full_machine",
		"activeProject": {"projectRoot": "C:/project"},
		"bridgeToolsPreview": true,
		"models": [],
		"tasks": [],
	}, {
		"runtime_state": "ready",
		"background_task_id": "old-task",
		"background_state": "idle",
		"trust_mode": "off",
		"mcp_tools_available": false,
		"tool_visibility_error": "",
		"last_reported_tool_visibility_error": "",
		"source_method": "project.attach",
	})
	_assert_eq(plan.get("runtime_state"), "turn_running", "plan runtime")
	_assert_eq((plan.get("token_usage", {}) as Dictionary).get("total"), 42, "plan token usage")
	_assert_eq((plan.get("host_status_patch", {}) as Dictionary).get("trust_mode"), "full_machine", "plan host trust")
	_assert_true(bool((plan.get("tool_visibility_patch", {}) as Dictionary).get("mcp_tools_available", false)), "plan tools available")
	_assert_false(bool((plan.get("tool_visibility_patch", {}) as Dictionary).get("clear_auto_enable_tools_requested", false)), "project attach does not clear in-flight tool enable")
	_assert_eq((plan.get("result_state_patch", {}) as Dictionary).get("thread_id"), "thread-2", "plan thread")
	_assert_true(bool(plan.get("update_background_status_label", false)), "plan background status")
	_assert_true(bool(plan.get("restore_background_tasks", false)), "plan restore tasks")
	_assert_true(bool(plan.get("update_runtime_model_options", false)), "plan update models")
	_assert_true(bool(plan.get("auto_enable_tools_after_attach", false)), "plan auto enable after attach")
	_assert_eq((plan.get("detail_messages", []) as Array)[0], "Project attached: C:/project", "plan project detail")

	var health_plan := ChatHostStateModel.result_plan({
		"state": "ready",
		"activeProject": {"projectRoot": "C:/project"},
	}, {
		"runtime_state": "ready",
		"source_method": "host.health",
	})
	_assert_false(bool(health_plan.get("auto_enable_tools_after_attach", true)), "host health does not auto refresh tools")

	var restart_plan := ChatHostStateModel.result_plan({
		"state": "ready",
		"activeProject": {"projectRoot": "C:/project"},
	}, {
		"runtime_state": "ready",
		"source_method": "host.restart_for_project",
	})
	_assert_true(bool(restart_plan.get("auto_enable_tools_after_attach", false)), "restart project can auto refresh tools once")

	var bridge_enable_plan := ChatHostStateModel.result_plan({
		"state": "ready",
		"mcpToolsAvailable": true,
		"bridgeToolsEnabled": true,
	}, {
		"runtime_state": "ready",
		"source_method": "bridge.tools.enable",
	})
	_assert_true(bool((bridge_enable_plan.get("tool_visibility_patch", {}) as Dictionary).get("clear_auto_enable_tools_requested", false)), "bridge tools enable result clears in-flight enable")

	var effect_plan := ChatHostStateModel.result_effect_plan({
		"tokenUsage": {"total": 55},
		"thread_id": "thread-3",
		"task_id": "task-3",
		"state": "ready",
		"mcpToolsAvailable": true,
		"trustMode": "full_machine",
		"trustSessionChanged": true,
		"activeProject": {"projectRoot": "C:/project"},
		"bridgeToolsEnabled": true,
		"models": [],
		"tasks": [],
	}, {
		"runtime_state": "turn_running",
		"background_task_id": "old-task",
		"background_state": "running",
		"trust_mode": "off",
		"mcp_tools_available": false,
		"tool_visibility_error": "",
		"last_reported_tool_visibility_error": "",
		"source_method": "project.attach",
	})
	var effects := effect_plan.get("effects", []) as Array
	_assert_true(effects.size() >= 10, "effect plan has ordered effects")
	_assert_eq((effects[0] as Dictionary).get("action"), "apply_runtime_state", "effect runtime first")
	_assert_eq((effects[0] as Dictionary).get("runtime_state"), "ready", "effect runtime value")
	_assert_eq((effects[1] as Dictionary).get("action"), "apply_token_usage_patch", "effect token usage second")
	_assert_eq(((effects[1] as Dictionary).get("patch", {}) as Dictionary).get("total"), 55, "effect token usage patch")
	_assert_eq((effects[2] as Dictionary).get("action"), "apply_host_status_patch", "effect host patch third")
	_assert_eq((effects[3] as Dictionary).get("action"), "apply_tool_visibility_patch", "effect tool patch fourth")
	_assert_eq((effects[4] as Dictionary).get("action"), "apply_result_state_patch", "effect result patch fifth")
	_assert_eq((effects[5] as Dictionary).get("action"), "update_background_status_label", "effect background label")
	_assert_eq((effects[6] as Dictionary).get("action"), "restore_background_tasks", "effect restore tasks")
	_assert_eq((effects[7] as Dictionary).get("action"), "auto_enable_tools", "effect auto enables after attach")
	_assert_true(bool((effects[7] as Dictionary).get("force", false)), "effect force refreshes tools after attach")
	_assert_eq((effects[7] as Dictionary).get("source"), "project.attach", "effect carries auto enable source")
	_assert_eq((effects[8] as Dictionary).get("action"), "system_message", "effect system message")
	_assert_eq((effects[9] as Dictionary).get("action"), "system_message", "effect tools message")
	_assert_eq((effects[10] as Dictionary).get("action"), "detail_message", "effect project detail")
	_assert_eq((effects[effects.size() - 2] as Dictionary).get("action"), "update_runtime_model_options", "effect model update before ui")
	_assert_eq((effects[effects.size() - 1] as Dictionary).get("action"), "update_ui", "effect ui last")


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
