extends SceneTree

const ChatControlStateModel := preload("res://addons/godot_codex_bridge/core/chat_control_state_model.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge chat control state model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge chat control state model tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var ui_context := ChatControlStateModel.ui_context({
		"chat_enabled": true,
		"marker_enabled": true,
		"team_permission": true,
		"connected": true,
		"connecting": false,
		"runtime_state": "waiting_for_approval",
		"host_config_status": "ok",
		"thread_id": "thread-1",
		"turn_id": "turn-1",
		"message_count": 5,
		"tools_available": true,
		"trust_mode": "full_machine",
		"background_state": "idle",
		"approval": {
			"approval_id": "approval-1",
			"kind": "command_execution",
			"safe_default": "manual_only",
			"nonce": "nonce-1",
			"approvable_by_chat": true,
		},
	})
	var ui_status := ui_context.get("status", {}) as Dictionary
	var ui_controls := ui_context.get("controls", {}) as Dictionary
	_assert_eq(ui_status.get("label"), "Needs your approval", "ui context status label")
	_assert_true(bool(ui_context.get("foreground_busy", false)), "ui context foreground busy")
	_assert_true(bool((ui_controls.get("send", {}) as Dictionary).get("disabled", false)), "ui context disables send")
	_assert_true(bool((ui_controls.get("enable_tools", {}) as Dictionary).get("disabled", false)), "ui context disables already available tools")
	_assert_eq((ui_controls.get("trust", {}) as Dictionary).get("text"), "Trust: full", "ui context trust text")
	_assert_false(bool((ui_controls.get("emergency_stop", {}) as Dictionary).get("disabled", true)), "ui context emergency stop enabled")

	var disconnected := ChatControlStateModel.controls_state({
		"chat_enabled": true,
		"marker_enabled": true,
		"team_enabled": true,
		"connected": false,
		"connecting": false,
		"foreground_busy": false,
		"runtime_state": "disconnected",
		"message_count": 0,
	})
	_assert_eq((disconnected.get("connect", {}) as Dictionary).get("text"), "Connect", "connect text")
	_assert_false(bool((disconnected.get("connect", {}) as Dictionary).get("disabled", true)), "connect enabled while disconnected")
	_assert_true(bool((disconnected.get("send", {}) as Dictionary).get("disabled", false)), "send disabled while disconnected")
	_assert_true(bool((disconnected.get("enable_tools", {}) as Dictionary).get("disabled", false)), "enable tools disabled while disconnected")
	_assert_true(bool((disconnected.get("clear", {}) as Dictionary).get("disabled", false)), "clear disabled when transcript empty")
	_assert_false(bool((disconnected.get("emergency_stop", {}) as Dictionary).get("disabled", true)), "emergency stop enabled while disconnected")

	var connected := ChatControlStateModel.controls_state({
		"chat_enabled": true,
		"marker_enabled": true,
		"team_enabled": true,
		"connected": true,
		"connecting": false,
		"foreground_busy": false,
		"runtime_state": "ready",
		"thread_id": "thread-1",
		"turn_id": "turn-1",
		"message_count": 3,
		"tools_available": false,
		"active_project_root": "C:/project",
		"trust_mode": "off",
		"background_state": "idle",
	})
	_assert_eq((connected.get("connect", {}) as Dictionary).get("text"), "Refresh", "connected refresh text")
	_assert_false(bool((connected.get("connect", {}) as Dictionary).get("disabled", true)), "connect refresh enabled")
	_assert_false(bool((connected.get("send", {}) as Dictionary).get("disabled", true)), "send enabled")
	_assert_false(bool((connected.get("enable_tools", {}) as Dictionary).get("disabled", true)), "enable tools enabled")
	_assert_eq((connected.get("trust", {}) as Dictionary).get("text"), "Trust Session", "trust off text")
	_assert_false(bool((connected.get("trust", {}) as Dictionary).get("pressed", true)), "trust off not pressed")
	_assert_false(bool((connected.get("team_review", {}) as Dictionary).get("disabled", true)), "team review enabled")
	_assert_false(bool((connected.get("cancel", {}) as Dictionary).get("disabled", true)), "cancel enabled with turn")
	_assert_eq((connected.get("emergency_stop", {}) as Dictionary).get("text"), "Stop All", "emergency stop text")
	_assert_true(str((connected.get("emergency_stop", {}) as Dictionary).get("tooltip", "")).contains("Emergency stop"), "emergency stop tooltip")
	_assert_false(bool((connected.get("clear", {}) as Dictionary).get("disabled", true)), "clear enabled with messages")

	var mismatched := ChatControlStateModel.controls_state({
		"chat_enabled": true,
		"marker_enabled": true,
		"team_enabled": true,
		"connected": true,
		"connecting": false,
		"foreground_busy": false,
		"runtime_state": "ready",
		"thread_id": "thread-1",
		"turn_id": "",
		"message_count": 3,
		"tools_available": true,
		"active_project_root": "C:/OldProject",
		"editor_project_root": "C:/NewProject",
		"trust_mode": "off",
		"background_state": "idle",
	})
	_assert_eq((mismatched.get("connect", {}) as Dictionary).get("text"), "Reconnect", "mismatch reconnect text")
	_assert_true(str((mismatched.get("connect", {}) as Dictionary).get("tooltip", "")).contains("different Godot project"), "mismatch reconnect tooltip")
	_assert_false(bool((mismatched.get("connect", {}) as Dictionary).get("disabled", true)), "mismatch reconnect enabled")
	_assert_true(bool((mismatched.get("send", {}) as Dictionary).get("disabled", false)), "mismatch disables send")
	_assert_true(bool((mismatched.get("enable_tools", {}) as Dictionary).get("disabled", false)), "mismatch disables tools")
	_assert_true(bool((mismatched.get("team_review", {}) as Dictionary).get("disabled", false)), "mismatch disables team")
	_assert_true(str((mismatched.get("send", {}) as Dictionary).get("tooltip", "")).contains("Reconnect"), "mismatch send tooltip")
	_assert_false(bool((mismatched.get("emergency_stop", {}) as Dictionary).get("disabled", true)), "mismatch keeps emergency stop enabled")

	var pending_attach := ChatControlStateModel.controls_state({
		"chat_enabled": true,
		"connected": true,
		"tools_available": false,
		"active_project_root": "",
	})
	_assert_true(bool((pending_attach.get("enable_tools", {}) as Dictionary).get("disabled", false)), "enable tools disabled while project attach pending")
	_assert_true(str((pending_attach.get("enable_tools", {}) as Dictionary).get("tooltip", "")).contains("attach"), "enable tools attach pending tooltip")

	var tools_available := ChatControlStateModel.controls_state({
		"chat_enabled": true,
		"connected": true,
		"tools_available": true,
		"active_project_root": "C:/project",
	})
	_assert_false(bool((tools_available.get("enable_tools", {}) as Dictionary).get("disabled", true)), "refresh tools enabled when tools already visible")
	_assert_eq((tools_available.get("enable_tools", {}) as Dictionary).get("text"), "Refresh Tools", "refresh tools text")

	var busy := ChatControlStateModel.controls_state({
		"chat_enabled": true,
		"marker_enabled": false,
		"team_enabled": true,
		"connected": true,
		"foreground_busy": true,
		"runtime_state": "turn_running",
		"tools_available": true,
		"active_project_root": "C:/project",
		"trust_mode": "full_machine",
		"background_state": "running",
		"approval": {"blocked_reason": "blocked by test"},
	})
	_assert_true(bool((busy.get("send", {}) as Dictionary).get("disabled", false)), "send disabled while busy")
	_assert_true(str((busy.get("send", {}) as Dictionary).get("tooltip", "")).contains("still working"), "send busy tooltip")
	_assert_true(bool((busy.get("eye", {}) as Dictionary).get("disabled", false)), "eye disabled by permission")
	_assert_eq((busy.get("trust", {}) as Dictionary).get("text"), "Trust: full", "trust full text")
	_assert_true(bool((busy.get("trust", {}) as Dictionary).get("pressed", false)), "trust full pressed")
	_assert_true(bool((busy.get("team_cancel", {}) as Dictionary).get("disabled", false)) == false, "team cancel enabled")
	_assert_true(bool((busy.get("approve", {}) as Dictionary).get("disabled", false)), "approve disabled when blocked")
	_assert_eq((busy.get("approve", {}) as Dictionary).get("tooltip"), "blocked by test", "approve disabled reason")
	_assert_false(bool((busy.get("approve_session", {}) as Dictionary).get("visible", true)), "approve session hidden when unsupported")
	_assert_false(bool((busy.get("emergency_stop", {}) as Dictionary).get("disabled", true)), "busy keeps emergency stop enabled")

	var session_approval := ChatControlStateModel.controls_state({
		"chat_enabled": true,
		"connected": true,
		"approval": {
			"approval_id": "approval-1",
			"kind": "command_execution",
			"safe_default": "manual_only",
			"nonce": "nonce-1",
			"approvable_by_chat": true,
		},
	})
	_assert_false(bool((session_approval.get("approve", {}) as Dictionary).get("disabled", true)), "approve enabled")
	_assert_true(bool((session_approval.get("approve_session", {}) as Dictionary).get("visible", false)), "approve session visible")

	var context := ChatControlStateModel.control_context({
		"chat_enabled": true,
		"marker_enabled": true,
		"team_permission": true,
		"connected": true,
		"connecting": false,
		"runtime_state": "waiting_for_approval",
		"thread_id": "thread-1",
		"turn_id": "turn-1",
		"message_count": 2,
		"tools_available": true,
		"active_project_root": "C:/project",
		"trust_mode": "full_machine",
		"background_state": "idle",
	})
	_assert_true(bool(context.get("foreground_busy", false)), "context detects foreground busy")
	_assert_true(bool(context.get("team_enabled", false)), "context combines chat and team permissions")
	var context_controls: Dictionary = context.get("controls", {})
	_assert_true(bool((context_controls.get("send", {}) as Dictionary).get("disabled", false)), "context disables send while approval is pending")
	_assert_true(bool((context_controls.get("trust", {}) as Dictionary).get("disabled", false)), "context disables trust while foreground busy")

	var disabled_context := ChatControlStateModel.control_context({
		"chat_enabled": false,
		"team_permission": true,
		"connected": true,
		"runtime_state": "ready",
	})
	_assert_false(bool(disabled_context.get("team_enabled", true)), "team disabled when chat disabled")
	var disabled_controls := disabled_context.get("controls", {}) as Dictionary
	_assert_false(bool((disabled_controls.get("emergency_stop", {}) as Dictionary).get("disabled", true)), "chat disabled keeps emergency stop enabled")
	_assert_false(ChatControlStateModel.is_foreground_busy("ready"), "ready is not foreground busy")
	_assert_true(ChatControlStateModel.is_foreground_busy("applying_diff"), "applying diff is foreground busy")


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
