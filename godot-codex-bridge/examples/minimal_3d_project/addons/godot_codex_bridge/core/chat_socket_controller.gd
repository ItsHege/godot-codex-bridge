@tool
extends RefCounted

const ChatHostConfigModel := preload("chat_host_config_model.gd")
const ChatSocketEventModel := preload("chat_socket_event_model.gd")


static func lifecycle_state(current: Dictionary, patch: Dictionary) -> Dictionary:
	var result := current.duplicate()
	if patch.has("host_start_in_progress"):
		result["host_start_in_progress"] = bool(patch.get("host_start_in_progress", false))
	if patch.has("host_connect_autostart_allowed"):
		result["host_connect_autostart_allowed"] = bool(patch.get("host_connect_autostart_allowed", false))
	if patch.has("host_launch_attempted"):
		result["host_launch_attempted"] = bool(patch.get("host_launch_attempted", false))
	if patch.has("host_start_process_id"):
		result["host_start_process_id"] = int(patch.get("host_start_process_id", -1))
	if patch.has("host_start_deadline_msec"):
		result["host_start_deadline_msec"] = int(patch.get("host_start_deadline_msec", 0))
	if patch.has("host_start_retry_elapsed"):
		result["host_start_retry_elapsed"] = float(patch.get("host_start_retry_elapsed", 0.0))
	if patch.has("connection_state"):
		result["connection_state"] = str(patch.get("connection_state", "disconnected"))
	if patch.has("runtime_state"):
		result["runtime_state"] = str(patch.get("runtime_state", "disconnected"))
	if patch.has("trust_mode"):
		result["trust_mode"] = str(patch.get("trust_mode", "off"))
	if patch.has("chat_auto_enable_tools_requested"):
		result["chat_auto_enable_tools_requested"] = bool(patch.get("chat_auto_enable_tools_requested", false))
	if patch.has("chat_last_auto_enable_tools_project_root"):
		result["chat_last_auto_enable_tools_project_root"] = str(patch.get("chat_last_auto_enable_tools_project_root", ""))
	return result


static func connect_result(connect_error: int, host_url: String, log_attempt: bool) -> Dictionary:
	if connect_error != OK:
		return {
			"ok": false,
			"connection_state": "disconnected",
			"runtime_state": "error_recoverable",
			"system_message": "Could not connect to Codex: " + error_string(connect_error),
			"detail_message": "",
		}
	return {
		"ok": true,
		"connection_state": "connecting",
		"runtime_state": "connecting",
		"system_message": "",
		"detail_message": "Connecting to " + host_url if log_attempt else "",
	}


static func connect_result_effect_plan(connect_error: int, host_url: String, log_attempt: bool) -> Dictionary:
	var result := connect_result(connect_error, host_url, log_attempt)
	var effects: Array[Dictionary] = [
		{
			"action": "apply_state_patch",
			"patch": {
				"connection_state": str(result.get("connection_state", "disconnected")),
				"runtime_state": str(result.get("runtime_state", "disconnected")),
			},
		},
	]
	var system_message := str(result.get("system_message", ""))
	if system_message != "":
		effects.append({
			"action": "system_message",
			"message": system_message,
		})
	var detail_message := str(result.get("detail_message", ""))
	if detail_message != "":
		effects.append({
			"action": "detail_message",
			"message": detail_message,
		})
	effects.append({
		"action": "update_ui",
	})
	return {
		"ok": bool(result.get("ok", false)),
		"effects": effects,
	}


static func connect_request_plan(chat_allowed: bool, socket_present: bool, socket_state: int) -> Dictionary:
	if not chat_allowed:
		return {
			"action": "blocked",
			"system_message": "Codex chat permission is disabled.",
			"update_ui": true,
		}
	if socket_present and socket_state == WebSocketPeer.STATE_OPEN:
		return {
			"action": "reattach",
			"chat_auto_enable_tools_requested": false,
			"system_message": "Refreshing Codex project attachment...",
		}
	if socket_present and socket_state == WebSocketPeer.STATE_CONNECTING:
		return {
			"action": "noop",
		}
	return {
		"action": "connect",
		"host_connect_autostart_allowed": true,
		"host_launch_attempted": false,
		"chat_auto_enable_tools_requested": false,
		"log_attempt": true,
	}


static func connect_request_effect_plan(chat_allowed: bool, socket_present: bool, socket_state: int) -> Dictionary:
	var plan := connect_request_plan(chat_allowed, socket_present, socket_state)
	var action := str(plan.get("action", "noop"))
	var effects: Array[Dictionary] = []
	if action == "blocked":
		effects.append({
			"action": "system_message",
			"message": str(plan.get("system_message", "Codex chat permission is disabled.")),
		})
		if bool(plan.get("update_ui", true)):
			effects.append({
				"action": "update_ui",
			})
	elif action == "connect":
		effects.append({
			"action": "apply_connect_request_state",
			"state": {
				"host_connect_autostart_allowed": bool(plan.get("host_connect_autostart_allowed", true)),
				"host_launch_attempted": bool(plan.get("host_launch_attempted", false)),
				"chat_auto_enable_tools_requested": bool(plan.get("chat_auto_enable_tools_requested", false)),
			},
		})
		effects.append({
			"action": "attempt_connect",
			"log_attempt": bool(plan.get("log_attempt", true)),
		})
	elif action == "reattach":
		effects.append({
			"action": "apply_connect_request_state",
			"state": {
				"chat_auto_enable_tools_requested": bool(plan.get("chat_auto_enable_tools_requested", false)),
			},
		})
		var message := str(plan.get("system_message", ""))
		if message != "":
			effects.append({
				"action": "system_message",
				"message": message,
			})
		effects.append({
			"action": "reattach_project",
		})
		effects.append({
			"action": "update_ui",
		})
	return {
		"action": action,
		"effects": effects,
	}


static func ready_transition(project_root: String, bridge_dir: String, attach_method := "project.attach") -> Dictionary:
	return {
		"connection_state": "ready",
		"runtime_state": "ready",
		"trust_mode": "off",
		"host_start_in_progress": false,
		"host_connect_autostart_allowed": false,
		"host_start_retry_elapsed": 0.0,
		"system_message": "Connected to Codex.",
		"requests": [
			{
				"method": attach_method,
				"params": {
					"project_root": project_root,
					"bridge_dir": bridge_dir,
				},
			},
			{
				"method": "host.health",
				"params": {},
			},
			{
				"method": "background.status",
				"params": {},
			},
		],
		"request_models": true,
	}


static func project_reattach_effect_plan(socket_ready: bool, project_mismatch: bool, project_root: String, bridge_dir: String) -> Dictionary:
	if not socket_ready:
		return {
			"action": "noop",
			"effects": [],
		}
	var state := {
		"chat_auto_enable_tools_requested": false,
		"chat_mcp_tools_available": false,
		"chat_mcp_tool_count": 0,
		"chat_mcp_godot_tool_count": 0,
		"chat_last_tool_inventory_at": "",
		"chat_tool_visibility_error": "",
	}
	var attach_method := "project.attach"
	if project_mismatch:
		attach_method = "host.restart_for_project"
		state["chat_last_auto_enable_tools_project_root"] = ""
		state["thread_id"] = ""
		state["turn_id"] = ""
		state["trust_mode"] = "off"
	return {
		"action": "restart_project" if project_mismatch else "attach_project",
		"effects": [
			{
				"action": "apply_project_reattach_state",
				"state": state,
			},
			{
				"action": "send_requests",
				"requests": ready_transition(project_root, bridge_dir, attach_method).get("requests", []),
			},
			{
				"action": "request_models",
			},
			{
				"action": "update_ui",
			},
		],
	}


static func poll_state_decision(peer_state: int) -> Dictionary:
	if peer_state == WebSocketPeer.STATE_OPEN:
		return {
			"action": "open",
		}
	if peer_state == WebSocketPeer.STATE_CONNECTING:
		return {
			"action": "connecting",
			"connection_state": "connecting",
		}
	if peer_state == WebSocketPeer.STATE_CLOSING:
		return {
			"action": "closing",
			"drain_packets": true,
		}
	return {
		"action": "closed",
	}


static func poll_tick_effect_plan(
	chat_allowed: bool,
	socket_present: bool,
	host_start_in_progress: bool,
	now_msec: int,
	deadline_msec: int,
	retry_elapsed: float,
	delta: float,
	retry_seconds: float,
	timeout_seconds := 0.0
) -> Dictionary:
	if not chat_allowed:
		return {
			"action": "blocked",
			"effects": [],
		}
	if not socket_present:
		return {
			"action": "host_start_retry",
			"effects": host_start_retry_effect_plan(
				host_start_in_progress,
				now_msec,
				deadline_msec,
				retry_elapsed,
				delta,
				retry_seconds,
				timeout_seconds
			).get("effects", []),
		}
	return {
		"action": "poll_socket",
		"effects": [
			{
				"action": "poll_live_socket",
			},
		],
	}


static func poll_socket_effect_plan(peer_state: int, connection_state: String, runtime_state: String, autostart_allowed: bool, launch_attempted: bool, host_start_in_progress: bool, project_root: String, bridge_dir: String) -> Dictionary:
	var decision := poll_state_decision(peer_state)
	var action := str(decision.get("action", "closed"))
	var effects: Array[Dictionary] = []
	if action == "open":
		effects.append({
			"action": "apply_open_socket_effects",
			"effects": open_socket_effect_plan(connection_state, project_root, bridge_dir).get("effects", []),
		})
	elif action == "connecting":
		effects.append({
			"action": "apply_poll_state",
			"state": {
				"connection_state": str(decision.get("connection_state", "connecting")),
			},
		})
	elif action == "closing":
		if bool(decision.get("drain_packets", false)):
			effects.append({
				"action": "drain_packets",
			})
	else:
		effects.append({
			"action": "apply_closed_socket_effects",
			"effects": closed_socket_effect_plan(connection_state, runtime_state, autostart_allowed, launch_attempted, host_start_in_progress).get("effects", []),
		})
	return {
		"action": action,
		"effects": effects,
	}


static func open_socket_plan(connection_state: String, project_root: String, bridge_dir: String) -> Dictionary:
	var result := {
		"action": "open",
		"drain_packets": true,
		"ready_transition": false,
		"request_models": false,
		"auto_enable_tools": false,
		"state": {},
		"requests": [],
		"system_message": "",
	}
	if connection_state == "ready":
		return result
	var ready_state := ready_transition(project_root, bridge_dir)
	result["ready_transition"] = true
	result["request_models"] = bool(ready_state.get("request_models", false))
	result["state"] = ready_state
	result["requests"] = ready_state.get("requests", [])
	result["system_message"] = str(ready_state.get("system_message", ""))
	return result


static func open_socket_effect_plan(connection_state: String, project_root: String, bridge_dir: String) -> Dictionary:
	var plan := open_socket_plan(connection_state, project_root, bridge_dir)
	var effects: Array[Dictionary] = []
	if bool(plan.get("ready_transition", false)):
		effects.append({
			"action": "apply_state_patch",
			"patch": plan.get("state", {}),
		})
		var system_message := str(plan.get("system_message", ""))
		if system_message != "":
			effects.append({
				"action": "system_message",
				"message": system_message,
			})
		effects.append({
			"action": "send_requests",
			"requests": plan.get("requests", []),
		})
		if bool(plan.get("request_models", false)):
			effects.append({
				"action": "request_models",
			})
		if bool(plan.get("auto_enable_tools", false)):
			effects.append({
				"action": "auto_enable_tools",
			})
	if bool(plan.get("drain_packets", true)):
		effects.append({
			"action": "drain_packets",
		})
	return {
		"action": "open",
		"ready_transition": bool(plan.get("ready_transition", false)),
		"effects": effects,
	}


static func closed_socket_decision(connection_state: String, runtime_state: String, autostart_allowed: bool, launch_attempted: bool, host_start_in_progress: bool) -> Dictionary:
	var result := {
		"action": "disconnect",
		"connection_state": "disconnected",
		"runtime_state": "disconnected",
		"trust_mode": "off",
		"clear_socket": true,
		"system_message": "",
	}
	if connection_state == "connecting":
		if autostart_allowed:
			if not launch_attempted:
				result["action"] = "start_host"
				result["connection_state"] = "connecting"
				result["runtime_state"] = runtime_state
				result["clear_socket"] = false
				return result
			if host_start_in_progress:
				result["action"] = "wait_host"
				result["connection_state"] = "connecting"
				result["runtime_state"] = runtime_state
				return result
		result["runtime_state"] = "error_recoverable"
		result["system_message"] = "Codex is not available. Press Connect to try again after refreshing the addon install."
	elif connection_state != "disconnected":
		result["system_message"] = "Codex disconnected. Press Connect to reconnect."
	if result["runtime_state"] != "error_recoverable" and runtime_state == "error_recoverable":
		result["runtime_state"] = "error_recoverable"
	return result


static func closed_socket_effect_plan(connection_state: String, runtime_state: String, autostart_allowed: bool, launch_attempted: bool, host_start_in_progress: bool) -> Dictionary:
	var plan := closed_socket_decision(connection_state, runtime_state, autostart_allowed, launch_attempted, host_start_in_progress)
	var action := str(plan.get("action", "disconnect"))
	var effects: Array[Dictionary] = []
	if action == "start_host":
		effects.append({
			"action": "start_host",
			"success_effects": [
				{
					"action": "set_host_launch_attempted",
					"value": true,
				},
				{
					"action": "clear_socket",
				},
				{
					"action": "update_ui",
				},
				{
					"action": "stop_processing",
				},
			],
		})
	elif action == "wait_host":
		effects.append({
			"action": "clear_socket",
		})
		effects.append({
			"action": "update_ui",
		})
		effects.append({
			"action": "stop_processing",
		})

	var message := str(plan.get("system_message", ""))
	if message != "":
		effects.append({
			"action": "system_message",
			"message": message,
		})
	effects.append({
		"action": "clear_socket",
	})
	effects.append({
		"action": "apply_state_patch",
		"patch": {
			"connection_state": str(plan.get("connection_state", "disconnected")),
			"runtime_state": str(plan.get("runtime_state", "disconnected")),
			"trust_mode": str(plan.get("trust_mode", "off")),
		},
	})
	effects.append({
		"action": "update_ui",
	})
	return {
		"action": action,
		"effects": effects,
	}


static func host_start_retry_decision(in_progress: bool, now_msec: int, deadline_msec: int, retry_elapsed: float, delta: float, retry_seconds: float, timeout_seconds := 0.0) -> Dictionary:
	if not in_progress:
		return {
			"action": "none",
			"retry_elapsed": retry_elapsed,
		}
	if now_msec > deadline_msec:
		return {
			"action": "timeout",
			"retry_elapsed": retry_elapsed,
			"host_start_in_progress": false,
			"host_connect_autostart_allowed": false,
			"connection_state": "disconnected",
			"runtime_state": "error_recoverable",
			"system_message": "Codex did not become ready within " + str(int(ceil(max(timeout_seconds, 0.0)))) + " seconds." if timeout_seconds > 0.0 else "Codex did not become ready.",
		}
	var next_elapsed := retry_elapsed + delta
	if next_elapsed >= retry_seconds:
		return {
			"action": "reconnect",
			"retry_elapsed": 0.0,
		}
	return {
		"action": "wait",
		"retry_elapsed": next_elapsed,
	}


static func host_start_retry_effect_plan(in_progress: bool, now_msec: int, deadline_msec: int, retry_elapsed: float, delta: float, retry_seconds: float, timeout_seconds := 0.0) -> Dictionary:
	var plan := host_start_retry_decision(in_progress, now_msec, deadline_msec, retry_elapsed, delta, retry_seconds, timeout_seconds)
	var action := str(plan.get("action", "none"))
	var effects: Array[Dictionary] = [
		{
			"action": "set_retry_elapsed",
			"value": float(plan.get("retry_elapsed", retry_elapsed)),
		},
	]
	if action == "timeout":
		effects.append({
			"action": "stop_owned_host",
			"reason": "startup_timeout",
		})
		effects.append({
			"action": "apply_state_patch",
			"patch": {
				"host_start_in_progress": bool(plan.get("host_start_in_progress", false)),
				"host_connect_autostart_allowed": bool(plan.get("host_connect_autostart_allowed", false)),
				"connection_state": str(plan.get("connection_state", "disconnected")),
				"runtime_state": str(plan.get("runtime_state", "error_recoverable")),
			},
		})
		var timeout_message := str(plan.get("system_message", ""))
		if timeout_message != "":
			effects.append({
				"action": "system_message",
				"message": timeout_message,
			})
		effects.append({
			"action": "update_ui",
		})
	elif action == "reconnect":
		effects.append({
			"action": "attempt_connect",
			"log_attempt": false,
		})
	return {
		"action": action,
		"effects": effects,
	}


static func host_start_request_effect_plan(in_progress: bool, host_config: Dictionary, node_entry_exists: bool, start_script_exists: bool, default_port: int) -> Dictionary:
	if in_progress:
		return {
			"ok": true,
			"action": "already_in_progress",
			"effects": [],
		}
	var node_entry := str(host_config.get("node_entry", ""))
	var start_script := str(host_config.get("start_script", ""))
	var launch_plan := ChatHostConfigModel.launch_plan(
		host_config,
		node_entry != "" and node_entry_exists,
		start_script != "" and start_script_exists,
		default_port
	)
	if not bool(launch_plan.get("ok", false)):
		var failure := host_start_failure_effect_plan(launch_plan)
		return {
			"ok": false,
			"action": "failure",
			"launch_plan": launch_plan,
			"effects": failure.get("effects", []),
		}
	return {
		"ok": true,
		"action": "launch",
		"launch_plan": launch_plan,
		"executable": str(launch_plan.get("executable", "")),
		"args": launch_plan.get("args", PackedStringArray()),
		"effects": [],
	}


static func host_start_success_state(process_id: int, now_msec: int, timeout_seconds: float) -> Dictionary:
	return {
		"host_start_process_id": process_id,
		"host_start_in_progress": true,
		"host_start_deadline_msec": now_msec + int(timeout_seconds * 1000.0),
		"host_start_retry_elapsed": 0.0,
		"connection_state": "connecting",
		"runtime_state": "connecting",
	}


static func host_start_success_notice(process_id: int, launch_plan: Dictionary) -> Dictionary:
	var port := int(launch_plan.get("port", 0))
	var runtime := str(launch_plan.get("runtime", "app-server"))
	return {
		"detail_message": "Starting Codex Host locally on port " + str(port) + " (" + runtime + ").",
		"log_event": "codex_host_start_requested",
		"log_payload": {
			"process_id": process_id,
			"port": port,
			"runtime": runtime,
			"start_script": str(launch_plan.get("start_script", "")),
			"node_entry": str(launch_plan.get("node_entry", "")),
			"launcher_kind": str(launch_plan.get("launcher_kind", "")),
		},
	}


static func host_start_success_effect_plan(process_id: int, now_msec: int, timeout_seconds: float, launch_plan: Dictionary) -> Dictionary:
	var state := host_start_success_state(process_id, now_msec, timeout_seconds)
	var notice := host_start_success_notice(process_id, launch_plan)
	return {
		"ok": true,
		"effects": [
			{
				"action": "apply_start_state",
				"state": state,
			},
			{
				"action": "detail_message",
				"message": str(notice.get("detail_message", "")),
			},
			{
				"action": "log_event",
				"event": str(notice.get("log_event", "codex_host_start_requested")),
				"payload": notice.get("log_payload", {}),
			},
			{
				"action": "update_ui",
			},
		],
	}


static func host_start_failure_state(launch_plan: Dictionary) -> Dictionary:
	var code := str(launch_plan.get("error_code", "launcher_missing"))
	var status := "launcher_missing"
	var config_message := "Launcher files are missing. Refresh the addon install."
	if code == "missing_config":
		status = "missing"
		config_message = "Launcher config missing. Refresh the addon install."
	return {
		"ok": false,
		"error_code": code,
		"host_config_status": status,
		"host_config_message": config_message,
		"system_message": str(launch_plan.get("message", "Failed to start Codex.")),
	}


static func host_start_failure_effect_plan(launch_plan: Dictionary) -> Dictionary:
	var state := host_start_failure_state(launch_plan)
	return {
		"ok": false,
		"effects": [
			{
				"action": "system_message",
				"message": str(state.get("system_message", "Failed to start Codex.")),
			},
			{
				"action": "apply_host_config_failure",
				"state": {
					"host_config_status": str(state.get("host_config_status", "launcher_missing")),
					"host_config_message": str(state.get("host_config_message", "Launcher files are missing. Refresh the addon install.")),
				},
			},
		],
	}


static func host_process_failure_state() -> Dictionary:
	return {
		"ok": false,
		"system_message": "Failed to start Codex.",
		"recoverable_message": "Failed to start Codex Host process.",
	}


static func host_process_failure_effect_plan() -> Dictionary:
	var state := host_process_failure_state()
	return {
		"ok": false,
		"effects": [
			{
				"action": "system_message",
				"message": str(state.get("system_message", "Failed to start Codex.")),
			},
			{
				"action": "apply_recoverable_message",
				"message": str(state.get("recoverable_message", "Failed to start Codex Host process.")),
			},
		],
	}


static func disconnect_request_plan(stop_owned_host: bool, socket_present: bool, runtime_state: String) -> Dictionary:
	var next_state := disconnect_state(runtime_state)
	next_state["stop_owned_host"] = stop_owned_host
	next_state["close_socket"] = socket_present
	next_state["clear_socket"] = socket_present
	next_state["chat_auto_enable_tools_requested"] = false
	next_state["update_ui"] = true
	return next_state


static func disconnect_request_effect_plan(stop_owned_host: bool, socket_present: bool, runtime_state: String, reason := "disconnect") -> Dictionary:
	var plan := disconnect_request_plan(stop_owned_host, socket_present, runtime_state)
	var effects: Array[Dictionary] = []
	if bool(plan.get("stop_owned_host", false)):
		effects.append({
			"action": "stop_owned_host",
			"reason": reason,
		})
	if bool(plan.get("close_socket", false)):
		effects.append({
			"action": "close_socket",
		})
	if bool(plan.get("clear_socket", false)):
		effects.append({
			"action": "clear_socket",
		})
	effects.append({
		"action": "apply_disconnect_state",
		"state": {
			"host_start_in_progress": bool(plan.get("host_start_in_progress", false)),
			"host_connect_autostart_allowed": bool(plan.get("host_connect_autostart_allowed", false)),
			"host_launch_attempted": bool(plan.get("host_launch_attempted", false)),
			"connection_state": str(plan.get("connection_state", "disconnected")),
			"runtime_state": str(plan.get("runtime_state", "disconnected")),
			"trust_mode": str(plan.get("trust_mode", "off")),
			"chat_auto_enable_tools_requested": bool(plan.get("chat_auto_enable_tools_requested", false)),
		},
	})
	if bool(plan.get("update_ui", true)):
		effects.append({
			"action": "update_ui",
		})
	return {
		"effects": effects,
	}


static func owned_host_stop_plan(process_id: int, reason: String, socket_open: bool) -> Dictionary:
	if process_id <= 0:
		return {
			"action": "none",
		}
	var params := {
		"reason": reason,
		"owner": "godot_addon",
		"process_id": process_id,
	}
	return {
		"action": "stop",
		"process_id": process_id,
		"send_shutdown": socket_open,
		"shutdown_method": "host.shutdown",
		"shutdown_params": params,
	}


static func owned_host_stop_complete_state(process_id: int, reason: String, graceful_requested: bool, process_was_alive: bool, kill_error: int) -> Dictionary:
	return {
		"host_start_process_id": -1,
		"host_start_in_progress": false,
		"host_start_retry_elapsed": 0.0,
		"host_start_deadline_msec": 0,
		"log_event": "codex_host_stop_requested",
		"log_payload": {
			"process_id": process_id,
			"reason": reason,
			"graceful_requested": graceful_requested,
			"process_was_alive": process_was_alive,
			"kill_error": error_string(kill_error) if kill_error != OK else "",
		},
	}


static func disconnect_state(runtime_state: String) -> Dictionary:
	return {
		"host_start_in_progress": false,
		"host_connect_autostart_allowed": false,
		"host_launch_attempted": false,
		"connection_state": "disconnected",
		"runtime_state": "error_fatal" if runtime_state == "error_fatal" else "disconnected",
		"trust_mode": "off",
	}


static func runtime_state_from_result(result: Variant, current_state: String) -> String:
	return ChatSocketEventModel.runtime_state_from_result(result, current_state)


static func rpc_request_text(request_id: int, method: String, params: Dictionary) -> String:
	return JSON.stringify({
		"jsonrpc": "2.0",
		"id": request_id,
		"method": method,
		"params": params,
	})


static func rpc_notification_text(method: String, params: Dictionary) -> String:
	return JSON.stringify({
		"jsonrpc": "2.0",
		"method": method,
		"params": params,
	})


static func request_send_result_effect_plan(send_error: int) -> Dictionary:
	var effects: Array[Dictionary] = []
	if send_error != OK:
		effects.append({
			"action": "system_message",
			"message": "Failed to send message to Codex: " + error_string(send_error),
		})
	return {
		"ok": send_error == OK,
		"effects": effects,
	}


static func notification_send_result_effect_plan(send_error: int) -> Dictionary:
	var effects: Array[Dictionary] = []
	if send_error != OK:
		effects.append({
			"action": "detail_message",
			"message": "Failed to send notification to Codex Host: " + error_string(send_error),
		})
	return {
		"ok": send_error == OK,
		"effects": effects,
	}
