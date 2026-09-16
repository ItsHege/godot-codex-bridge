extends SceneTree

const ChatSocketController := preload("res://addons/godot_codex_bridge/core/chat_socket_controller.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge chat socket controller tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge chat socket controller tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var lifecycle := ChatSocketController.lifecycle_state({
		"connection_state": "ready",
		"runtime_state": "ready",
		"host_start_in_progress": true,
		"host_start_retry_elapsed": 0.5,
		"chat_auto_enable_tools_requested": true,
	}, {
		"connection_state": "disconnected",
		"runtime_state": "error_recoverable",
		"host_start_in_progress": false,
		"host_start_retry_elapsed": 2,
		"chat_auto_enable_tools_requested": false,
		"chat_last_auto_enable_tools_project_root": "C:/project",
	})
	_assert_eq(lifecycle.get("connection_state"), "disconnected", "lifecycle state connection")
	_assert_eq(lifecycle.get("runtime_state"), "error_recoverable", "lifecycle state runtime")
	_assert_false(bool(lifecycle.get("host_start_in_progress", true)), "lifecycle state bool")
	_assert_eq(float(lifecycle.get("host_start_retry_elapsed", 0.0)), 2.0, "lifecycle state float")
	_assert_false(bool(lifecycle.get("chat_auto_enable_tools_requested", true)), "lifecycle state auto enable")
	_assert_eq(lifecycle.get("chat_last_auto_enable_tools_project_root"), "C:/project", "lifecycle state project root")
	var lifecycle_preserve := ChatSocketController.lifecycle_state({"connection_state": "ready"}, {})
	_assert_eq(lifecycle_preserve.get("connection_state"), "ready", "lifecycle state preserves missing")

	var connect_blocked := ChatSocketController.connect_request_plan(false, false, WebSocketPeer.STATE_CLOSED)
	_assert_eq(connect_blocked.get("action"), "blocked", "connect plan blocks permission disabled")
	_assert_true(str(connect_blocked.get("system_message", "")).find("permission") >= 0, "connect blocked message")
	_assert_true(bool(connect_blocked.get("update_ui", false)), "connect blocked updates ui")

	var connect_noop_open := ChatSocketController.connect_request_plan(true, true, WebSocketPeer.STATE_OPEN)
	_assert_eq(connect_noop_open.get("action"), "reattach", "connect plan reattaches open socket")
	_assert_false(bool(connect_noop_open.get("chat_auto_enable_tools_requested", true)), "connect reattach clears auto tools")

	var connect_noop_connecting := ChatSocketController.connect_request_plan(true, true, WebSocketPeer.STATE_CONNECTING)
	_assert_eq(connect_noop_connecting.get("action"), "noop", "connect plan ignores connecting socket")

	var connect_start := ChatSocketController.connect_request_plan(true, false, WebSocketPeer.STATE_CLOSED)
	_assert_eq(connect_start.get("action"), "connect", "connect plan starts closed socket")
	_assert_true(bool(connect_start.get("host_connect_autostart_allowed", false)), "connect plan enables autostart")
	_assert_false(bool(connect_start.get("host_launch_attempted", true)), "connect plan resets launch attempted")
	_assert_false(bool(connect_start.get("chat_auto_enable_tools_requested", true)), "connect plan resets auto tools")
	_assert_true(bool(connect_start.get("log_attempt", false)), "connect plan logs attempt")

	var connect_blocked_effect_plan := ChatSocketController.connect_request_effect_plan(false, false, WebSocketPeer.STATE_CLOSED)
	var connect_blocked_effects := connect_blocked_effect_plan.get("effects", []) as Array
	_assert_eq(connect_blocked_effect_plan.get("action"), "blocked", "connect effect blocks permission disabled")
	_assert_eq(connect_blocked_effects.size(), 2, "connect blocked effect count")
	_assert_eq((connect_blocked_effects[0] as Dictionary).get("action"), "system_message", "connect blocked message effect")
	_assert_eq((connect_blocked_effects[1] as Dictionary).get("action"), "update_ui", "connect blocked update effect")

	var connect_noop_effect_plan := ChatSocketController.connect_request_effect_plan(true, true, WebSocketPeer.STATE_OPEN)
	_assert_eq(connect_noop_effect_plan.get("action"), "reattach", "connect effect reattaches open socket")
	var connect_reattach_effects := connect_noop_effect_plan.get("effects", []) as Array
	_assert_eq(connect_reattach_effects.size(), 4, "connect reattach effect count")
	_assert_eq((connect_reattach_effects[0] as Dictionary).get("action"), "apply_connect_request_state", "connect reattach state effect")
	_assert_eq((connect_reattach_effects[2] as Dictionary).get("action"), "reattach_project", "connect reattach sends project attach")
	_assert_eq((connect_reattach_effects[3] as Dictionary).get("action"), "update_ui", "connect reattach updates ui")

	var connect_start_effect_plan := ChatSocketController.connect_request_effect_plan(true, false, WebSocketPeer.STATE_CLOSED)
	var connect_start_effects := connect_start_effect_plan.get("effects", []) as Array
	_assert_eq(connect_start_effect_plan.get("action"), "connect", "connect effect starts closed socket")
	_assert_eq(connect_start_effects.size(), 2, "connect start effect count")
	_assert_eq((connect_start_effects[0] as Dictionary).get("action"), "apply_connect_request_state", "connect start state effect")
	var connect_start_state := (connect_start_effects[0] as Dictionary).get("state", {}) as Dictionary
	_assert_true(bool(connect_start_state.get("host_connect_autostart_allowed", false)), "connect start effect enables autostart")
	_assert_false(bool(connect_start_state.get("host_launch_attempted", true)), "connect start effect resets launch")
	_assert_false(bool(connect_start_state.get("chat_auto_enable_tools_requested", true)), "connect start effect clears auto tools")
	_assert_eq((connect_start_effects[1] as Dictionary).get("action"), "attempt_connect", "connect start attempts connect")
	_assert_true(bool((connect_start_effects[1] as Dictionary).get("log_attempt", false)), "connect start logs attempt")

	var connected := ChatSocketController.connect_result(OK, "ws://127.0.0.1:49390", true)
	_assert_true(bool(connected.get("ok", false)), "connect ok flag")
	_assert_eq(connected.get("connection_state"), "connecting", "connect state")
	_assert_eq(connected.get("runtime_state"), "connecting", "connect runtime")
	_assert_true(str(connected.get("detail_message", "")).find("49390") >= 0, "connect detail includes host")

	var failed := ChatSocketController.connect_result(ERR_CANT_CONNECT, "ws://127.0.0.1:49390", true)
	_assert_false(bool(failed.get("ok", true)), "connect failure ok flag")
	_assert_eq(failed.get("connection_state"), "disconnected", "connect failure state")
	_assert_eq(failed.get("runtime_state"), "error_recoverable", "connect failure runtime")

	var connected_effect_plan := ChatSocketController.connect_result_effect_plan(OK, "ws://127.0.0.1:49390", true)
	var connected_effects := connected_effect_plan.get("effects", []) as Array
	_assert_true(bool(connected_effect_plan.get("ok", false)), "connect effect ok flag")
	_assert_eq(connected_effects.size(), 3, "connect effect count")
	_assert_eq((connected_effects[0] as Dictionary).get("action"), "apply_state_patch", "connect effect applies state first")
	_assert_eq(((connected_effects[0] as Dictionary).get("patch", {}) as Dictionary).get("connection_state"), "connecting", "connect effect state")
	_assert_eq((connected_effects[1] as Dictionary).get("action"), "detail_message", "connect effect detail second")
	_assert_eq((connected_effects[2] as Dictionary).get("action"), "update_ui", "connect effect updates ui last")

	var quiet_connect_effect_plan := ChatSocketController.connect_result_effect_plan(OK, "ws://127.0.0.1:49390", false)
	_assert_eq((quiet_connect_effect_plan.get("effects", []) as Array).size(), 2, "quiet connect skips detail")

	var failed_effect_plan := ChatSocketController.connect_result_effect_plan(ERR_CANT_CONNECT, "ws://127.0.0.1:49390", true)
	var failed_effects := failed_effect_plan.get("effects", []) as Array
	_assert_false(bool(failed_effect_plan.get("ok", true)), "connect failure effect ok flag")
	_assert_eq(failed_effects.size(), 3, "connect failure effect count")
	_assert_eq((failed_effects[1] as Dictionary).get("action"), "system_message", "connect failure effect message second")
	_assert_eq(((failed_effects[0] as Dictionary).get("patch", {}) as Dictionary).get("runtime_state"), "error_recoverable", "connect failure effect runtime")

	var ready := ChatSocketController.ready_transition("C:/project", "C:/project/.godot/godot_codex_bridge")
	_assert_eq(ready.get("connection_state"), "ready", "ready connection")
	_assert_eq(ready.get("runtime_state"), "ready", "ready runtime")
	_assert_eq((ready.get("requests", []) as Array).size(), 3, "ready sends attach health and background status")
	_assert_eq(((ready.get("requests", []) as Array)[0] as Dictionary).get("method"), "project.attach", "ready default attach method")
	_assert_true(bool(ready.get("request_models", false)), "ready requests models")

	var restart_ready := ChatSocketController.ready_transition("C:/project", "C:/project/.godot/godot_codex_bridge", "host.restart_for_project")
	_assert_eq(((restart_ready.get("requests", []) as Array)[0] as Dictionary).get("method"), "host.restart_for_project", "ready supports restart attach method")

	var reattach_unready := ChatSocketController.project_reattach_effect_plan(false, false, "C:/project", "C:/project/.godot/godot_codex_bridge")
	_assert_eq(reattach_unready.get("action"), "noop", "reattach unready noops")
	_assert_eq((reattach_unready.get("effects", []) as Array).size(), 0, "reattach unready has no effects")

	var reattach_current := ChatSocketController.project_reattach_effect_plan(true, false, "C:/project", "C:/project/.godot/godot_codex_bridge")
	var reattach_current_effects := reattach_current.get("effects", []) as Array
	_assert_eq(reattach_current.get("action"), "attach_project", "reattach current attaches project")
	_assert_eq(reattach_current_effects.size(), 4, "reattach current effect count")
	_assert_eq((reattach_current_effects[0] as Dictionary).get("action"), "apply_project_reattach_state", "reattach current resets state first")
	var reattach_current_state := (reattach_current_effects[0] as Dictionary).get("state", {}) as Dictionary
	_assert_false(bool(reattach_current_state.get("chat_auto_enable_tools_requested", true)), "reattach current clears auto enable")
	_assert_false(bool(reattach_current_state.get("chat_mcp_tools_available", true)), "reattach current clears mcp tools")
	_assert_eq(int(reattach_current_state.get("chat_mcp_tool_count", -1)), 0, "reattach current clears tool count")
	_assert_eq(str(reattach_current_state.get("chat_last_tool_inventory_at", "stale")), "", "reattach current clears inventory time")
	_assert_false(reattach_current_state.has("thread_id"), "reattach current preserves thread id")
	_assert_false(reattach_current_state.has("turn_id"), "reattach current preserves turn id")
	_assert_false(reattach_current_state.has("trust_mode"), "reattach current preserves trust mode")
	_assert_false(reattach_current_state.has("chat_last_auto_enable_tools_project_root"), "reattach current preserves last auto root")
	_assert_eq((reattach_current_effects[1] as Dictionary).get("action"), "send_requests", "reattach current sends requests second")
	_assert_eq((((reattach_current_effects[1] as Dictionary).get("requests", []) as Array)[0] as Dictionary).get("method"), "project.attach", "reattach current sends project attach")
	_assert_eq((reattach_current_effects[2] as Dictionary).get("action"), "request_models", "reattach current requests models")
	_assert_eq((reattach_current_effects[3] as Dictionary).get("action"), "update_ui", "reattach current updates ui")

	var reattach_mismatch := ChatSocketController.project_reattach_effect_plan(true, true, "C:/project", "C:/project/.godot/godot_codex_bridge")
	var reattach_mismatch_effects := reattach_mismatch.get("effects", []) as Array
	_assert_eq(reattach_mismatch.get("action"), "restart_project", "reattach mismatch restarts project")
	var reattach_mismatch_state := (reattach_mismatch_effects[0] as Dictionary).get("state", {}) as Dictionary
	_assert_eq(str(reattach_mismatch_state.get("chat_last_auto_enable_tools_project_root", "stale")), "", "reattach mismatch clears last auto root")
	_assert_eq(str(reattach_mismatch_state.get("thread_id", "stale")), "", "reattach mismatch clears thread")
	_assert_eq(str(reattach_mismatch_state.get("turn_id", "stale")), "", "reattach mismatch clears turn")
	_assert_eq(str(reattach_mismatch_state.get("trust_mode", "")), "off", "reattach mismatch turns trust off")
	_assert_eq((((reattach_mismatch_effects[1] as Dictionary).get("requests", []) as Array)[0] as Dictionary).get("method"), "host.restart_for_project", "reattach mismatch sends restart")

	var poll_tick_blocked := ChatSocketController.poll_tick_effect_plan(false, true, false, 1000, 5000, 0.0, 0.1, 0.75)
	_assert_eq(poll_tick_blocked.get("action"), "blocked", "poll tick blocks disabled chat")
	_assert_eq((poll_tick_blocked.get("effects", []) as Array).size(), 0, "poll tick blocked has no effects")

	var poll_tick_retry := ChatSocketController.poll_tick_effect_plan(true, false, true, 1000, 5000, 0.7, 0.1, 0.75)
	var poll_tick_retry_effects := poll_tick_retry.get("effects", []) as Array
	_assert_eq(poll_tick_retry.get("action"), "host_start_retry", "poll tick retries without socket")
	_assert_eq((poll_tick_retry_effects[0] as Dictionary).get("action"), "set_retry_elapsed", "poll tick retry sets elapsed")
	_assert_eq((poll_tick_retry_effects[1] as Dictionary).get("action"), "attempt_connect", "poll tick retry attempts reconnect")

	var poll_tick_socket := ChatSocketController.poll_tick_effect_plan(true, true, false, 1000, 5000, 0.0, 0.1, 0.75)
	var poll_tick_socket_effects := poll_tick_socket.get("effects", []) as Array
	_assert_eq(poll_tick_socket.get("action"), "poll_socket", "poll tick polls live socket")
	_assert_eq((poll_tick_socket_effects[0] as Dictionary).get("action"), "poll_live_socket", "poll tick live socket effect")

	var poll_open := ChatSocketController.poll_state_decision(WebSocketPeer.STATE_OPEN)
	_assert_eq(poll_open.get("action"), "open", "poll open action")

	var poll_connecting := ChatSocketController.poll_state_decision(WebSocketPeer.STATE_CONNECTING)
	_assert_eq(poll_connecting.get("action"), "connecting", "poll connecting action")
	_assert_eq(poll_connecting.get("connection_state"), "connecting", "poll connecting state")

	var poll_closing := ChatSocketController.poll_state_decision(WebSocketPeer.STATE_CLOSING)
	_assert_eq(poll_closing.get("action"), "closing", "poll closing action")
	_assert_true(bool(poll_closing.get("drain_packets", false)), "poll closing drains packets")

	var poll_closed := ChatSocketController.poll_state_decision(WebSocketPeer.STATE_CLOSED)
	_assert_eq(poll_closed.get("action"), "closed", "poll closed action")

	var poll_socket_open := ChatSocketController.poll_socket_effect_plan(WebSocketPeer.STATE_OPEN, "connecting", "connecting", false, false, false, "C:/project", "C:/project/.godot/godot_codex_bridge")
	var poll_socket_open_effects := poll_socket_open.get("effects", []) as Array
	_assert_eq(poll_socket_open.get("action"), "open", "poll socket open action")
	_assert_eq(poll_socket_open_effects.size(), 1, "poll socket open delegates once")
	_assert_eq((poll_socket_open_effects[0] as Dictionary).get("action"), "apply_open_socket_effects", "poll socket open delegates open effects")
	_assert_true(((poll_socket_open_effects[0] as Dictionary).get("effects", []) as Array).size() >= 1, "poll socket open has nested effects")

	var poll_socket_connecting := ChatSocketController.poll_socket_effect_plan(WebSocketPeer.STATE_CONNECTING, "disconnected", "disconnected", false, false, false, "C:/project", "C:/project/.godot/godot_codex_bridge")
	var poll_socket_connecting_effects := poll_socket_connecting.get("effects", []) as Array
	_assert_eq(poll_socket_connecting.get("action"), "connecting", "poll socket connecting action")
	_assert_eq((poll_socket_connecting_effects[0] as Dictionary).get("action"), "apply_poll_state", "poll socket connecting applies state")
	_assert_eq(((poll_socket_connecting_effects[0] as Dictionary).get("state", {}) as Dictionary).get("connection_state"), "connecting", "poll socket connecting state")

	var poll_socket_closing := ChatSocketController.poll_socket_effect_plan(WebSocketPeer.STATE_CLOSING, "ready", "ready", false, false, false, "C:/project", "C:/project/.godot/godot_codex_bridge")
	var poll_socket_closing_effects := poll_socket_closing.get("effects", []) as Array
	_assert_eq(poll_socket_closing.get("action"), "closing", "poll socket closing action")
	_assert_eq((poll_socket_closing_effects[0] as Dictionary).get("action"), "drain_packets", "poll socket closing drains")

	var poll_socket_closed := ChatSocketController.poll_socket_effect_plan(WebSocketPeer.STATE_CLOSED, "connecting", "connecting", false, false, false, "C:/project", "C:/project/.godot/godot_codex_bridge")
	var poll_socket_closed_effects := poll_socket_closed.get("effects", []) as Array
	_assert_eq(poll_socket_closed.get("action"), "closed", "poll socket closed action")
	_assert_eq((poll_socket_closed_effects[0] as Dictionary).get("action"), "apply_closed_socket_effects", "poll socket closed delegates closed effects")

	var open_ready := ChatSocketController.open_socket_plan("ready", "C:/project", "C:/project/.godot/godot_codex_bridge")
	_assert_false(bool(open_ready.get("ready_transition", true)), "open ready skips transition")
	_assert_true(bool(open_ready.get("drain_packets", false)), "open ready drains packets")
	_assert_false(bool(open_ready.get("request_models", true)), "open ready skips model request")

	var open_connecting := ChatSocketController.open_socket_plan("connecting", "C:/project", "C:/project/.godot/godot_codex_bridge")
	_assert_true(bool(open_connecting.get("ready_transition", false)), "open connecting transitions ready")
	_assert_true(bool(open_connecting.get("request_models", false)), "open connecting requests models")
	_assert_false(bool(open_connecting.get("auto_enable_tools", true)), "open connecting waits for attach before auto-enable")
	_assert_eq((open_connecting.get("requests", []) as Array).size(), 3, "open connecting sends attach health and background status")
	var open_state := open_connecting.get("state", {}) as Dictionary
	_assert_eq(open_state.get("connection_state"), "ready", "open connecting state ready")

	var open_ready_effects := ChatSocketController.open_socket_effect_plan("ready", "C:/project", "C:/project/.godot/godot_codex_bridge")
	var ready_effects := open_ready_effects.get("effects", []) as Array
	_assert_eq(ready_effects.size(), 1, "open ready only drains packets")
	_assert_eq((ready_effects[0] as Dictionary).get("action"), "drain_packets", "open ready drain effect")

	var open_connecting_effects := ChatSocketController.open_socket_effect_plan("connecting", "C:/project", "C:/project/.godot/godot_codex_bridge")
	var connecting_effects := open_connecting_effects.get("effects", []) as Array
	_assert_true(bool(open_connecting_effects.get("ready_transition", false)), "open effect plan ready transition")
	_assert_eq(connecting_effects.size(), 5, "open connecting effect count")
	_assert_eq((connecting_effects[0] as Dictionary).get("action"), "apply_state_patch", "open effect applies state first")
	_assert_eq((connecting_effects[1] as Dictionary).get("action"), "system_message", "open effect appends message")
	_assert_eq((connecting_effects[2] as Dictionary).get("action"), "send_requests", "open effect sends requests")
	_assert_eq(((connecting_effects[2] as Dictionary).get("requests", []) as Array).size(), 3, "open effect sends three requests")
	_assert_eq((connecting_effects[3] as Dictionary).get("action"), "request_models", "open effect requests models")
	_assert_eq((connecting_effects[4] as Dictionary).get("action"), "drain_packets", "open effect drains last")

	var closed_start := ChatSocketController.closed_socket_decision("connecting", "connecting", true, false, false)
	_assert_eq(closed_start.get("action"), "start_host", "closed connecting starts host")

	var closed_wait := ChatSocketController.closed_socket_decision("connecting", "connecting", true, true, true)
	_assert_eq(closed_wait.get("action"), "wait_host", "closed waits for starting host")

	var closed_error := ChatSocketController.closed_socket_decision("connecting", "connecting", false, false, false)
	_assert_eq(closed_error.get("runtime_state"), "error_recoverable", "closed unavailable is recoverable")
	_assert_true(str(closed_error.get("system_message", "")).find("Codex is not available") >= 0, "closed unavailable message")

	var closed_start_effects := ChatSocketController.closed_socket_effect_plan("connecting", "connecting", true, false, false)
	var start_effects := closed_start_effects.get("effects", []) as Array
	_assert_eq(closed_start_effects.get("action"), "start_host", "closed effect start action")
	_assert_eq((start_effects[0] as Dictionary).get("action"), "start_host", "closed effect starts host first")
	_assert_true(((start_effects[0] as Dictionary).get("success_effects", []) as Array).size() >= 4, "closed start success effects")
	_assert_eq((start_effects[1] as Dictionary).get("action"), "clear_socket", "closed start fallback clears socket")
	_assert_eq((start_effects[2] as Dictionary).get("action"), "apply_state_patch", "closed start fallback applies state")
	_assert_eq((start_effects[3] as Dictionary).get("action"), "update_ui", "closed start fallback updates ui")

	var closed_wait_effects := ChatSocketController.closed_socket_effect_plan("connecting", "connecting", true, true, true)
	var wait_effects := closed_wait_effects.get("effects", []) as Array
	_assert_eq(closed_wait_effects.get("action"), "wait_host", "closed effect wait action")
	_assert_eq(wait_effects.size(), 6, "closed wait includes stop then fallback effects")
	_assert_eq((wait_effects[0] as Dictionary).get("action"), "clear_socket", "closed wait clears socket")
	_assert_eq((wait_effects[2] as Dictionary).get("action"), "stop_processing", "closed wait stops processing")

	var closed_error_effects := ChatSocketController.closed_socket_effect_plan("connecting", "connecting", false, false, false)
	var error_effects := closed_error_effects.get("effects", []) as Array
	_assert_eq(closed_error_effects.get("action"), "disconnect", "closed effect disconnect action")
	_assert_eq((error_effects[0] as Dictionary).get("action"), "system_message", "closed error message first")
	_assert_eq((error_effects[1] as Dictionary).get("action"), "clear_socket", "closed error clears socket")
	_assert_eq((error_effects[2] as Dictionary).get("action"), "apply_state_patch", "closed error applies state")
	var error_patch := (error_effects[2] as Dictionary).get("patch", {}) as Dictionary
	_assert_eq(error_patch.get("runtime_state"), "error_recoverable", "closed error patch runtime")

	var retry_wait := ChatSocketController.host_start_retry_decision(true, 1000, 5000, 0.1, 0.2, 0.75)
	_assert_eq(retry_wait.get("action"), "wait", "retry waits before interval")
	_assert_true(float(retry_wait.get("retry_elapsed", 0.0)) > 0.2, "retry accumulates elapsed")

	var retry_reconnect := ChatSocketController.host_start_retry_decision(true, 1000, 5000, 0.7, 0.1, 0.75)
	_assert_eq(retry_reconnect.get("action"), "reconnect", "retry reconnects after interval")
	_assert_eq(float(retry_reconnect.get("retry_elapsed", 1.0)), 0.0, "retry resets elapsed")

	var retry_timeout := ChatSocketController.host_start_retry_decision(true, 6000, 5000, 0.1, 0.1, 0.75, 30.0)
	_assert_eq(retry_timeout.get("action"), "timeout", "retry times out")
	_assert_eq(retry_timeout.get("runtime_state"), "error_recoverable", "timeout runtime")
	_assert_false(bool(retry_timeout.get("host_start_in_progress", true)), "timeout clears host start")
	_assert_false(bool(retry_timeout.get("host_connect_autostart_allowed", true)), "timeout clears autostart")
	_assert_true(str(retry_timeout.get("system_message", "")).find("did not become ready") >= 0, "timeout message")

	var retry_wait_effect_plan := ChatSocketController.host_start_retry_effect_plan(true, 1000, 5000, 0.1, 0.2, 0.75)
	var retry_wait_effects := retry_wait_effect_plan.get("effects", []) as Array
	_assert_eq(retry_wait_effect_plan.get("action"), "wait", "retry effect waits before interval")
	_assert_eq(retry_wait_effects.size(), 1, "retry wait only updates elapsed")
	_assert_eq((retry_wait_effects[0] as Dictionary).get("action"), "set_retry_elapsed", "retry wait elapsed effect")

	var retry_reconnect_effect_plan := ChatSocketController.host_start_retry_effect_plan(true, 1000, 5000, 0.7, 0.1, 0.75)
	var retry_reconnect_effects := retry_reconnect_effect_plan.get("effects", []) as Array
	_assert_eq(retry_reconnect_effect_plan.get("action"), "reconnect", "retry effect reconnects after interval")
	_assert_eq(retry_reconnect_effects.size(), 2, "retry reconnect effect count")
	_assert_eq((retry_reconnect_effects[0] as Dictionary).get("action"), "set_retry_elapsed", "retry reconnect elapsed first")
	_assert_eq((retry_reconnect_effects[1] as Dictionary).get("action"), "attempt_connect", "retry reconnect attempts connect")
	_assert_false(bool((retry_reconnect_effects[1] as Dictionary).get("log_attempt", true)), "retry reconnect is quiet")

	var retry_timeout_effect_plan := ChatSocketController.host_start_retry_effect_plan(true, 6000, 5000, 0.1, 0.1, 0.75, 30.0)
	var retry_timeout_effects := retry_timeout_effect_plan.get("effects", []) as Array
	_assert_eq(retry_timeout_effect_plan.get("action"), "timeout", "retry timeout effect action")
	_assert_eq(retry_timeout_effects.size(), 5, "retry timeout effect count")
	_assert_eq((retry_timeout_effects[0] as Dictionary).get("action"), "set_retry_elapsed", "retry timeout elapsed first")
	_assert_eq((retry_timeout_effects[1] as Dictionary).get("action"), "stop_owned_host", "retry timeout stops host")
	_assert_eq((retry_timeout_effects[2] as Dictionary).get("action"), "apply_state_patch", "retry timeout applies state")
	_assert_eq((retry_timeout_effects[3] as Dictionary).get("action"), "system_message", "retry timeout message")
	_assert_eq((retry_timeout_effects[4] as Dictionary).get("action"), "update_ui", "retry timeout updates ui")
	var retry_timeout_patch := (retry_timeout_effects[2] as Dictionary).get("patch", {}) as Dictionary
	_assert_eq(retry_timeout_patch.get("runtime_state"), "error_recoverable", "retry timeout patch runtime")

	var start_request_in_progress := ChatSocketController.host_start_request_effect_plan(true, {
		"node_entry": "C:/bridge/codex_host/dist/src/index.js",
	}, true, false, 49390)
	_assert_true(bool(start_request_in_progress.get("ok", false)), "start request in progress ok")
	_assert_eq(start_request_in_progress.get("action"), "already_in_progress", "start request in progress action")
	_assert_eq((start_request_in_progress.get("effects", []) as Array).size(), 0, "start request in progress has no effects")

	var start_request_launch := ChatSocketController.host_start_request_effect_plan(false, {
		"port": 49390,
		"runtime": "mock",
		"node_entry": "C:/bridge/codex_host/dist/src/index.js",
		"start_script": "C:/bridge/scripts/start_codex_host.ps1",
	}, true, true, 49390)
	_assert_true(bool(start_request_launch.get("ok", false)), "start request launch ok")
	_assert_eq(start_request_launch.get("action"), "launch", "start request launch action")
	_assert_eq(str(start_request_launch.get("executable", "")), "node", "start request launch executable")
	var start_request_args: PackedStringArray = start_request_launch.get("args", PackedStringArray())
	_assert_eq(start_request_args[0], "C:/bridge/codex_host/dist/src/index.js", "start request launch args")

	var start_request_failure := ChatSocketController.host_start_request_effect_plan(false, {
		"node_entry": "C:/bridge/codex_host/dist/src/index.js",
		"start_script": "C:/bridge/scripts/start_codex_host.ps1",
	}, false, false, 49390)
	var start_request_failure_effects := start_request_failure.get("effects", []) as Array
	_assert_false(bool(start_request_failure.get("ok", true)), "start request failure not ok")
	_assert_eq(start_request_failure.get("action"), "failure", "start request failure action")
	_assert_eq(str((start_request_failure.get("launch_plan", {}) as Dictionary).get("error_code", "")), "launcher_missing", "start request failure code")
	_assert_eq((start_request_failure_effects[0] as Dictionary).get("action"), "system_message", "start request failure message effect")

	var start_state := ChatSocketController.host_start_success_state(123, 1000, 30.0)
	_assert_eq(start_state.get("host_start_process_id"), 123, "start process id")
	_assert_eq(start_state.get("host_start_deadline_msec"), 31000, "start deadline")

	var start_notice := ChatSocketController.host_start_success_notice(123, {
		"port": 49390,
		"runtime": "mock",
		"start_script": "C:/bridge/start.ps1",
		"node_entry": "C:/bridge/index.js",
		"launcher_kind": "node",
	})
	_assert_true(str(start_notice.get("detail_message", "")).find("49390") >= 0, "start notice includes port")
	_assert_eq(start_notice.get("log_event"), "codex_host_start_requested", "start notice event")
	var start_log := start_notice.get("log_payload", {}) as Dictionary
	_assert_eq(start_log.get("process_id"), 123, "start notice process id")
	_assert_eq(start_log.get("runtime"), "mock", "start notice runtime")
	_assert_eq(start_log.get("launcher_kind"), "node", "start notice launcher kind")

	var host_start_effect_plan := ChatSocketController.host_start_success_effect_plan(123, 1000, 30.0, {
		"port": 49390,
		"runtime": "mock",
		"start_script": "C:/bridge/start.ps1",
		"node_entry": "C:/bridge/index.js",
		"launcher_kind": "node",
	})
	var host_start_effects := host_start_effect_plan.get("effects", []) as Array
	_assert_true(bool(host_start_effect_plan.get("ok", false)), "start effect plan ok")
	_assert_eq(host_start_effects.size(), 4, "start success effect count")
	_assert_eq((host_start_effects[0] as Dictionary).get("action"), "apply_start_state", "start success applies state first")
	_assert_eq((host_start_effects[1] as Dictionary).get("action"), "detail_message", "start success detail second")
	_assert_eq((host_start_effects[2] as Dictionary).get("action"), "log_event", "start success logs third")
	_assert_eq((host_start_effects[3] as Dictionary).get("action"), "update_ui", "start success updates ui last")
	var host_start_effect_state := (host_start_effects[0] as Dictionary).get("state", {}) as Dictionary
	_assert_eq(host_start_effect_state.get("host_start_process_id"), 123, "start effect process id")

	var missing_config := ChatSocketController.host_start_failure_state({
		"error_code": "missing_config",
		"message": "no config",
	})
	_assert_false(bool(missing_config.get("ok", true)), "missing config fails")
	_assert_eq(missing_config.get("host_config_status"), "missing", "missing config status")
	_assert_true(str(missing_config.get("host_config_message", "")).find("config") >= 0, "missing config message")
	_assert_eq(missing_config.get("system_message"), "no config", "missing config system message")

	var missing_launcher := ChatSocketController.host_start_failure_state({
		"error_code": "launcher_missing",
	})
	_assert_eq(missing_launcher.get("host_config_status"), "launcher_missing", "missing launcher status")
	_assert_true(str(missing_launcher.get("host_config_message", "")).find("Launcher files") >= 0, "missing launcher message")

	var missing_config_effect_plan := ChatSocketController.host_start_failure_effect_plan({
		"error_code": "missing_config",
		"message": "no config",
	})
	var missing_config_effects := missing_config_effect_plan.get("effects", []) as Array
	_assert_false(bool(missing_config_effect_plan.get("ok", true)), "missing config effect fails")
	_assert_eq(missing_config_effects.size(), 2, "missing config effect count")
	_assert_eq((missing_config_effects[0] as Dictionary).get("action"), "system_message", "missing config message effect")
	_assert_eq((missing_config_effects[1] as Dictionary).get("action"), "apply_host_config_failure", "missing config state effect")
	var missing_config_effect_state := (missing_config_effects[1] as Dictionary).get("state", {}) as Dictionary
	_assert_eq(missing_config_effect_state.get("host_config_status"), "missing", "missing config effect status")

	var process_failure := ChatSocketController.host_process_failure_state()
	_assert_false(bool(process_failure.get("ok", true)), "process failure fails")
	_assert_true(str(process_failure.get("recoverable_message", "")).find("process") >= 0, "process failure recoverable message")

	var process_failure_effect_plan := ChatSocketController.host_process_failure_effect_plan()
	var process_failure_effects := process_failure_effect_plan.get("effects", []) as Array
	_assert_false(bool(process_failure_effect_plan.get("ok", true)), "process failure effect fails")
	_assert_eq(process_failure_effects.size(), 2, "process failure effect count")
	_assert_eq((process_failure_effects[0] as Dictionary).get("action"), "system_message", "process failure message effect")
	_assert_eq((process_failure_effects[1] as Dictionary).get("action"), "apply_recoverable_message", "process failure recoverable effect")

	var disconnect_plain := ChatSocketController.disconnect_request_plan(false, true, "ready")
	_assert_false(bool(disconnect_plain.get("stop_owned_host", true)), "disconnect plain does not stop host")
	_assert_true(bool(disconnect_plain.get("close_socket", false)), "disconnect plain closes socket")
	_assert_true(bool(disconnect_plain.get("clear_socket", false)), "disconnect plain clears socket")
	_assert_eq(disconnect_plain.get("connection_state"), "disconnected", "disconnect plain connection")
	_assert_eq(disconnect_plain.get("runtime_state"), "disconnected", "disconnect plain runtime")
	_assert_false(bool(disconnect_plain.get("chat_auto_enable_tools_requested", true)), "disconnect clears auto tools")

	var disconnect_fatal := ChatSocketController.disconnect_request_plan(true, false, "error_fatal")
	_assert_true(bool(disconnect_fatal.get("stop_owned_host", false)), "disconnect fatal stops owned host")
	_assert_false(bool(disconnect_fatal.get("close_socket", true)), "disconnect no socket skip close")
	_assert_eq(disconnect_fatal.get("runtime_state"), "error_fatal", "disconnect preserves fatal runtime")

	var disconnect_effect_plan := ChatSocketController.disconnect_request_effect_plan(false, true, "ready", "manual")
	var disconnect_effects := disconnect_effect_plan.get("effects", []) as Array
	_assert_eq(disconnect_effects.size(), 4, "disconnect effect count")
	_assert_eq((disconnect_effects[0] as Dictionary).get("action"), "close_socket", "disconnect closes socket first")
	_assert_eq((disconnect_effects[1] as Dictionary).get("action"), "clear_socket", "disconnect clears socket second")
	_assert_eq((disconnect_effects[2] as Dictionary).get("action"), "apply_disconnect_state", "disconnect applies state third")
	_assert_eq((disconnect_effects[3] as Dictionary).get("action"), "update_ui", "disconnect updates ui last")
	var disconnect_effect_state := (disconnect_effects[2] as Dictionary).get("state", {}) as Dictionary
	_assert_eq(disconnect_effect_state.get("connection_state"), "disconnected", "disconnect effect connection state")
	_assert_eq(disconnect_effect_state.get("runtime_state"), "disconnected", "disconnect effect runtime state")
	_assert_false(bool(disconnect_effect_state.get("chat_auto_enable_tools_requested", true)), "disconnect effect clears auto tools")

	var disconnect_owned_effect_plan := ChatSocketController.disconnect_request_effect_plan(true, false, "error_fatal", "plugin_exit")
	var disconnect_owned_effects := disconnect_owned_effect_plan.get("effects", []) as Array
	_assert_eq(disconnect_owned_effects.size(), 3, "owned disconnect effect count")
	_assert_eq((disconnect_owned_effects[0] as Dictionary).get("action"), "stop_owned_host", "owned disconnect stops host first")
	_assert_eq((disconnect_owned_effects[0] as Dictionary).get("reason"), "plugin_exit", "owned disconnect passes reason")
	_assert_eq((disconnect_owned_effects[1] as Dictionary).get("action"), "apply_disconnect_state", "owned disconnect applies state")
	var disconnect_owned_state := (disconnect_owned_effects[1] as Dictionary).get("state", {}) as Dictionary
	_assert_eq(disconnect_owned_state.get("runtime_state"), "error_fatal", "owned disconnect preserves fatal runtime")

	var no_stop := ChatSocketController.owned_host_stop_plan(-1, "plugin_exit", true)
	_assert_eq(no_stop.get("action"), "none", "owned host no process ignored")

	var graceful_stop := ChatSocketController.owned_host_stop_plan(42, "plugin_exit", true)
	_assert_eq(graceful_stop.get("action"), "stop", "owned host stop action")
	_assert_true(bool(graceful_stop.get("send_shutdown", false)), "owned host sends graceful shutdown when socket open")
	_assert_eq(graceful_stop.get("shutdown_method"), "host.shutdown", "owned host shutdown method")
	_assert_eq((graceful_stop.get("shutdown_params", {}) as Dictionary).get("process_id"), 42, "owned host shutdown process id")

	var hard_stop := ChatSocketController.owned_host_stop_plan(42, "plugin_exit", false)
	_assert_false(bool(hard_stop.get("send_shutdown", true)), "owned host skips shutdown without socket")

	var stop_complete := ChatSocketController.owned_host_stop_complete_state(42, "plugin_exit", true, true, OK)
	_assert_eq(stop_complete.get("host_start_process_id"), -1, "owned host reset process id")
	_assert_false(bool(stop_complete.get("host_start_in_progress", true)), "owned host reset in progress")
	var stop_log := stop_complete.get("log_payload", {}) as Dictionary
	_assert_eq(stop_log.get("process_id"), 42, "owned host log process id")
	_assert_eq(stop_log.get("reason"), "plugin_exit", "owned host log reason")
	_assert_eq(stop_log.get("kill_error"), "", "owned host ok kill error empty")

	var request_text := ChatSocketController.rpc_request_text(7, "host.health", {"x": 1})
	var request := JSON.parse_string(request_text) as Dictionary
	_assert_eq(request.get("jsonrpc"), "2.0", "request jsonrpc")
	_assert_eq(request.get("id"), 7, "request id")
	_assert_eq(request.get("method"), "host.health", "request method")

	var notification_text := ChatSocketController.rpc_notification_text("bridge.addon_response", {"ok": true})
	var notification := JSON.parse_string(notification_text) as Dictionary
	_assert_true(not notification.has("id"), "notification has no id")
	_assert_eq(notification.get("method"), "bridge.addon_response", "notification method")

	var request_send_ok := ChatSocketController.request_send_result_effect_plan(OK)
	_assert_true(bool(request_send_ok.get("ok", false)), "request send ok")
	_assert_eq((request_send_ok.get("effects", []) as Array).size(), 0, "request send ok has no effects")

	var request_send_error := ChatSocketController.request_send_result_effect_plan(ERR_CANT_CONNECT)
	var request_send_effects := request_send_error.get("effects", []) as Array
	_assert_false(bool(request_send_error.get("ok", true)), "request send error fails")
	_assert_eq(request_send_effects.size(), 1, "request send error effect count")
	_assert_eq((request_send_effects[0] as Dictionary).get("action"), "system_message", "request send error system effect")
	_assert_true(str((request_send_effects[0] as Dictionary).get("message", "")).find("Failed to send message") >= 0, "request send error message")

	var notification_send_ok := ChatSocketController.notification_send_result_effect_plan(OK)
	_assert_true(bool(notification_send_ok.get("ok", false)), "notification send ok")
	_assert_eq((notification_send_ok.get("effects", []) as Array).size(), 0, "notification send ok has no effects")

	var notification_send_error := ChatSocketController.notification_send_result_effect_plan(ERR_CANT_CONNECT)
	var notification_send_effects := notification_send_error.get("effects", []) as Array
	_assert_false(bool(notification_send_error.get("ok", true)), "notification send error fails")
	_assert_eq(notification_send_effects.size(), 1, "notification send error effect count")
	_assert_eq((notification_send_effects[0] as Dictionary).get("action"), "detail_message", "notification send error detail effect")
	_assert_true(str((notification_send_effects[0] as Dictionary).get("message", "")).find("Failed to send notification") >= 0, "notification send error message")


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
