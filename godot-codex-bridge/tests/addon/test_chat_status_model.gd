extends SceneTree

const ChatStatusModel := preload("res://addons/godot_codex_bridge/core/chat_status_model.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge chat status model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge chat status model tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var disconnected := ChatStatusModel.compute({
		"connected": false,
		"runtime_state": "disconnected",
		"host_config_status": "ok",
	})
	_assert_eq(disconnected.get("label"), "Disconnected - press Connect", "disconnected label")
	_assert_eq(disconnected.get("severity"), "idle", "disconnected severity")

	var busy := ChatStatusModel.compute({
		"connected": true,
		"runtime_state": "turn_running",
		"host_config_status": "ok",
		"tools_available": true,
	})
	_assert_eq(busy.get("label"), "Codex is working...", "busy label")
	_assert_eq(busy.get("severity"), "busy", "busy severity")

	_assert_true(ChatStatusModel.is_foreground_busy("turn_running"), "turn running is busy")
	_assert_true(ChatStatusModel.is_foreground_busy("waiting_for_approval"), "approval is busy")
	_assert_true(ChatStatusModel.is_foreground_busy("applying_diff"), "diff is busy")
	_assert_false(ChatStatusModel.is_foreground_busy("ready"), "ready is not busy")

	_assert_eq(ChatStatusModel.format_elapsed_seconds(0), "", "zero elapsed hidden")
	_assert_eq(ChatStatusModel.format_elapsed_seconds(9), "9s", "seconds elapsed")
	_assert_eq(ChatStatusModel.format_elapsed_seconds(72), "1m 12s", "minutes elapsed")
	_assert_eq(ChatStatusModel.format_elapsed_seconds(3670), "1h 1m", "hours elapsed")

	_assert_eq(ChatStatusModel.working_indicator_text("turn_running", 72), "Still working... 1m 12s", "turn working text")
	_assert_eq(ChatStatusModel.working_indicator_text("waiting_for_approval", 5), "Waiting for approval... 5s", "approval text")
	_assert_eq(ChatStatusModel.working_indicator_text("applying_diff", 0, {"total": 1234}), "Applying approved change... | 1234 tokens", "token text")
	_assert_eq(ChatStatusModel.working_indicator_text("ready", 10), "", "ready text empty")
	_assert_eq(ChatStatusModel.token_usage_text({"inputTokens": 10, "outputTokens": 15}), "25 tokens", "input output token text")
	_assert_eq(ChatStatusModel.tools_state_label({"tools_available": true}), "ok", "tools ok label")
	_assert_eq(ChatStatusModel.tools_state_label({"tools_available": false, "last_tool_inventory_at": ""}), "checking", "tools checking label")
	_assert_eq(ChatStatusModel.tools_state_label({"tools_available": false, "last_tool_inventory_at": "now"}), "missing", "tools missing label")
	_assert_eq(ChatStatusModel.instructions_state_label({"agents_count": 1}), "1 file", "one instructions file")
	_assert_eq(ChatStatusModel.instructions_state_label({"agents_count": 2}), "2 files", "many instructions files")
	_assert_eq(ChatStatusModel.instructions_state_label({"agents_count": 0}), "optional", "missing instructions are optional")
	_assert_eq(ChatStatusModel.instructions_state_label({"agents_count": -1, "active_project_root": "C:/game"}), "checking", "instructions checking")
	_assert_true(ChatStatusModel.instructions_status_detail({"agents_count": 0}).contains("optional"), "missing instructions detail is not fatal")
	var state := {
		"connection_state": "ready",
		"runtime_state": "ready",
		"thread_id": "thread-1",
		"host_config_status": "ok",
		"host_config_message": "Launcher ready.",
		"host_config_path": "res://addons/godot_codex_bridge/host_config.json",
		"host_config_runtime": "app-server",
		"host_config_port": 49390,
		"host_config_launcher_path": "C:/bridge/codex_host/dist/src/index.js",
		"tools_available": true,
		"mcp_tool_count": 70,
		"mcp_godot_tool_count": 70,
		"mcp_server_name": "godot-codex-bridge",
		"last_tool_inventory_at": "now",
		"active_project_root": "C:/game",
		"agents_count": 0,
		"agents_paths": ["C:/game/AGENTS.md"],
		"trust_mode": "full_machine",
		"selected_model": "gpt-5.5",
		"selected_reasoning": "high",
	}
	_assert_eq(ChatStatusModel.readiness_label(state), "Launcher: ok | Tools: ok | Instructions: optional", "readiness label")
	_assert_true(ChatStatusModel.readiness_tooltip(state).contains("This is optional"), "readiness tooltip explains optional instructions")
	_assert_true(ChatStatusModel.status_tooltip(state).contains("Model: gpt-5.5"), "status tooltip model")
	_assert_true(ChatStatusModel.status_tooltip(state).contains("Trust: full_machine"), "status tooltip trust")
	_assert_eq(ChatStatusModel.host_process_status({"connection_state": "ready", "host_process_id": 0}), "external", "ready without owned pid is external")
	_assert_eq(ChatStatusModel.host_process_status({"host_process_id": 42, "host_process_owned_by_addon": true, "host_process_running": true}), "owned", "owned running host status")
	_assert_eq(ChatStatusModel.host_process_status({"host_process_id": 42, "host_process_owned_by_addon": true, "host_process_running": false}), "stale", "owned stale host status")
	_assert_true(ChatStatusModel.host_process_status_detail({"host_process_id": 42, "host_process_owned_by_addon": true, "host_process_running": false}).contains("no longer running"), "stale host detail")
	_assert_true(ChatStatusModel.status_tooltip({"connection_state": "ready", "runtime_state": "ready", "host_process_id": 42, "host_process_owned_by_addon": true, "host_process_running": true}).contains("owned by addon"), "status tooltip host process")
	_assert_eq(ChatStatusModel.heartbeat_status({"heartbeat_exists": true, "heartbeat_age_ms": 1500, "heartbeat_stale_after_ms": 10000}), "fresh", "fresh heartbeat status")
	_assert_eq(ChatStatusModel.heartbeat_status({"heartbeat_exists": true, "heartbeat_age_ms": 12000, "heartbeat_stale_after_ms": 10000}), "stale", "stale heartbeat status")
	_assert_eq(ChatStatusModel.heartbeat_status({"heartbeat_exists": false, "heartbeat_age_ms": -1, "heartbeat_stale_after_ms": 10000}), "missing", "missing heartbeat status")
	_assert_true(ChatStatusModel.heartbeat_status_detail({"heartbeat_exists": true, "heartbeat_age_ms": 12000, "heartbeat_stale_after_ms": 10000}).contains("No fresh bridge heartbeat evidence"), "stale heartbeat detail")
	_assert_true(ChatStatusModel.status_tooltip({"connection_state": "ready", "runtime_state": "ready", "heartbeat_exists": true, "heartbeat_age_ms": 1500, "heartbeat_stale_after_ms": 10000}).contains("Heartbeat: fresh bridge evidence"), "status tooltip heartbeat")
	var stale_heartbeat_context := ChatStatusModel.status_context({
		"chat_enabled": true,
		"connected": true,
		"connecting": false,
		"connection_state": "ready",
		"runtime_state": "ready",
		"host_config_status": "ok",
		"tools_available": true,
		"heartbeat_exists": true,
		"heartbeat_age_ms": 12000,
		"heartbeat_stale_after_ms": 10000,
	})
	_assert_eq((stale_heartbeat_context.get("status", {}) as Dictionary).get("label"), "Bridge heartbeat stale", "stale heartbeat visible label")
	_assert_eq((stale_heartbeat_context.get("status", {}) as Dictionary).get("severity"), "warn", "stale heartbeat visible severity")

	var mismatch_context := ChatStatusModel.status_context({
		"chat_enabled": true,
		"connected": true,
		"connecting": false,
		"connection_state": "ready",
		"runtime_state": "ready",
		"host_config_status": "ok",
		"tools_available": true,
		"active_project_root": "C:/OldProject",
		"editor_project_root": "C:/NewProject/",
		"agents_count": 1,
	})
	var mismatch_status := mismatch_context.get("status", {}) as Dictionary
	var mismatch_payload := mismatch_context.get("payload", {}) as Dictionary
	_assert_eq(mismatch_status.get("label"), "Project mismatch", "mismatch status label")
	_assert_eq(mismatch_status.get("severity"), "warn", "mismatch status severity")
	_assert_true(bool(mismatch_status.get("attention", false)), "mismatch status attention")
	_assert_true(bool(mismatch_payload.get("project_mismatch", false)), "mismatch payload")
	_assert_eq(mismatch_context.get("readiness_label"), "Project mismatch | Tools: ok | Instructions: 1 file", "mismatch readiness label")
	_assert_true(str(mismatch_context.get("readiness_tooltip", "")).contains("Host project root: C:/OldProject"), "mismatch tooltip host root")
	_assert_true(str(mismatch_context.get("readiness_tooltip", "")).contains("Editor project root: C:/NewProject/"), "mismatch tooltip editor root")

	var matching_payload := ChatStatusModel.status_payload({
		"active_project_root": "C:\\Game\\",
		"editor_project_root": "c:/game",
	})
	_assert_false(bool(matching_payload.get("project_mismatch", true)), "matching roots are normalized")

	var context := ChatStatusModel.status_context({
		"chat_enabled": true,
		"connected": true,
		"connecting": false,
		"connection_state": "ready",
		"runtime_state": "ready",
		"thread_id": "thread-2",
		"host_config_status": "ok",
		"host_config_message": "Launcher ready.",
		"host_config_path": "res://addons/godot_codex_bridge/host_config.json",
		"tools_available": true,
		"mcp_tool_count": 82,
		"mcp_godot_tool_count": 82,
		"mcp_server_name": "godot-codex-bridge",
		"last_tool_inventory_at": "now",
		"active_project_root": "C:/game",
		"agents_count": 1,
		"agents_paths": ["C:/game/AGENTS.md"],
		"trust_mode": "full_machine",
		"selected_model": "gpt-5.5",
		"selected_reasoning": "high",
	})
	var context_status := context.get("status", {}) as Dictionary
	var context_payload := context.get("payload", {}) as Dictionary
	_assert_eq(context_status.get("label"), "Ready", "status context ready label")
	_assert_eq(context.get("readiness_label"), "Launcher: ok | Tools: ok | Instructions: 1 file", "status context readiness")
	_assert_eq(context.get("tools_state_label"), "ok", "status context tools")
	_assert_eq(context.get("instructions_state_label"), "1 file", "status context instructions")
	_assert_true(str(context.get("status_tooltip", "")).contains("Thread: thread-2"), "status context tooltip thread")
	_assert_true(str(context.get("readiness_tooltip", "")).contains("AGENTS.md files:"), "status context readiness tooltip agents")
	_assert_eq(context_payload.get("agents_paths"), ["C:/game/AGENTS.md"], "status context payload agents paths")


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
