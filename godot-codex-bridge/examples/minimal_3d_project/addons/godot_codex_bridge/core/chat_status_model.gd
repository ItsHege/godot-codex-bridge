@tool
extends RefCounted

## Pure presentation logic for the Codex chat status chip.
## Maps the internal connection/runtime flags to a single human-readable status
## with a severity colour, so the dock can show one clear chip instead of the
## "Host: x | Runtime: y" jargon line. No UI or plugin state lives here.

## Severity -> default colour. Kept here so the chip has sane colours even
## before any editor-theme integration; callers may override per theme.
const COLOR_OK := Color(0.36, 0.78, 0.40)       # green
const COLOR_BUSY := Color(0.36, 0.62, 0.92)      # blue
const COLOR_ATTENTION := Color(0.95, 0.74, 0.25) # amber
const COLOR_WARN := Color(0.92, 0.55, 0.20)      # orange
const COLOR_ERROR := Color(0.90, 0.36, 0.36)     # red
const COLOR_IDLE := Color(0.55, 0.55, 0.55)      # grey

const BUSY_STATES := ["turn_running", "waiting_for_approval", "applying_diff"]


static func status_payload(state: Dictionary) -> Dictionary:
	return {
		"connection_state": str(state.get("connection_state", "disconnected")),
		"runtime_state": str(state.get("runtime_state", "disconnected")),
		"thread_id": str(state.get("thread_id", "")),
		"host_config_status": str(state.get("host_config_status", "unknown")),
		"host_config_message": str(state.get("host_config_message", "")),
		"host_config_path": str(state.get("host_config_path", "")),
		"host_config_runtime": str(state.get("host_config_runtime", "")),
		"host_config_port": int(state.get("host_config_port", 0)),
		"host_config_launcher_path": str(state.get("host_config_launcher_path", "")),
		"host_process_id": int(state.get("host_process_id", 0)),
		"host_process_owned_by_addon": bool(state.get("host_process_owned_by_addon", false)),
		"host_process_running": bool(state.get("host_process_running", false)),
		"host_process_status": host_process_status(state),
		"host_process_status_detail": host_process_status_detail(state),
		"heartbeat_path": str(state.get("heartbeat_path", "")),
		"heartbeat_exists": bool(state.get("heartbeat_exists", false)),
		"heartbeat_age_ms": int(state.get("heartbeat_age_ms", -1)),
		"heartbeat_stale_after_ms": int(state.get("heartbeat_stale_after_ms", 0)),
		"heartbeat_status": heartbeat_status(state),
		"heartbeat_status_detail": heartbeat_status_detail(state),
		"tools_available": bool(state.get("tools_available", false)),
		"mcp_tool_count": int(state.get("mcp_tool_count", 0)),
		"mcp_godot_tool_count": int(state.get("mcp_godot_tool_count", 0)),
		"mcp_server_name": str(state.get("mcp_server_name", "")),
		"last_tool_inventory_at": str(state.get("last_tool_inventory_at", "")),
		"tool_visibility_error": str(state.get("tool_visibility_error", "")),
		"active_project_root": str(state.get("active_project_root", "")),
		"host_project_root": str(state.get("host_project_root", state.get("active_project_root", ""))),
		"editor_project_root": str(state.get("editor_project_root", "")),
		"project_mismatch": _project_mismatch(
			str(state.get("host_project_root", state.get("active_project_root", ""))),
			str(state.get("editor_project_root", "")),
			state.get("project_mismatch", null)
		),
		"agents_count": int(state.get("agents_count", -1)),
		"agents_paths": _string_array(state.get("agents_paths", [])),
		"recoverable_message": str(state.get("recoverable_message", "")),
		"fatal_message": str(state.get("fatal_message", "")),
		"backpressure_text": str(state.get("backpressure_text", "")),
		"trust_mode": str(state.get("trust_mode", "off")),
		"selected_model": str(state.get("selected_model", "")),
		"selected_reasoning": str(state.get("selected_reasoning", "")),
	}


static func status_context(state: Dictionary) -> Dictionary:
	var payload := status_payload(state)
	var status := compute({
		"chat_enabled": bool(state.get("chat_enabled", true)),
		"connected": bool(state.get("connected", false)),
		"connecting": bool(state.get("connecting", false)),
		"runtime_state": str(payload.get("runtime_state", "disconnected")),
		"host_config_status": str(payload.get("host_config_status", "unknown")),
		"tools_available": bool(payload.get("tools_available", false)),
		"has_approval": bool(state.get("has_approval", false)),
		"project_mismatch": bool(payload.get("project_mismatch", false)),
		"heartbeat_status": str(payload.get("heartbeat_status", "unknown")),
	})
	return {
		"payload": payload,
		"status": status,
		"tools_state_label": tools_state_label(payload),
		"instructions_state_label": instructions_state_label(payload),
		"instructions_status_detail": instructions_status_detail(payload),
		"status_tooltip": status_tooltip(payload),
		"readiness_label": readiness_label(payload),
		"readiness_tooltip": readiness_tooltip(payload),
	}


## `state` keys (all optional, default to a safe value):
##   chat_enabled: bool
##   connected: bool
##   connecting: bool
##   runtime_state: String
##   host_config_status: String
##   tools_available: bool
##   has_approval: bool
## Returns: { "label": String, "severity": String, "color": Color, "attention": bool }
static func compute(state: Dictionary) -> Dictionary:
	var chat_enabled := bool(state.get("chat_enabled", true))
	var connected := bool(state.get("connected", false))
	var connecting := bool(state.get("connecting", false))
	var runtime_state := str(state.get("runtime_state", "disconnected"))
	var host_config_status := str(state.get("host_config_status", "ok"))
	var tools_available := bool(state.get("tools_available", false))
	var has_approval := bool(state.get("has_approval", false))
	var project_mismatch := bool(state.get("project_mismatch", false))
	var heartbeat_state := str(state.get("heartbeat_status", "unknown"))

	if not chat_enabled:
		return _result("Chat disabled in Bridge dock", "idle")

	if host_config_status == "missing" or host_config_status == "launcher_missing":
		return _result("Needs setup - check the addon launcher", "error")

	if connecting or runtime_state == "connecting":
		return _result("Starting Codex...", "busy")

	if not connected:
		return _result("Disconnected - press Connect", "idle")

	# Connected from here on.
	if project_mismatch:
		return _result("Project mismatch", "warn", true)

	if heartbeat_state == "stale":
		return _result("Bridge heartbeat stale", "warn", true)
	if heartbeat_state == "missing":
		return _result("Bridge heartbeat missing", "warn", true)

	match runtime_state:
		"error_fatal":
			return _result("Codex error - reconnect to restart", "error")
		"error_recoverable":
			return _result("Connection issue - reconnect", "warn")
		"waiting_for_approval":
			return _result("Needs your approval", "attention", true)
		"applying_diff":
			return _result("Applying approved change...", "busy")
		"turn_running":
			return _result("Codex is working...", "busy")

	if has_approval:
		return _result("Needs your approval", "attention", true)

	if not tools_available:
		return _result("Connected - Godot tools off", "warn")

	return _result("Ready", "ok")


static func _result(label: String, severity: String, attention := false) -> Dictionary:
	return {
		"label": label,
		"severity": severity,
		"color": color_for_severity(severity),
		"attention": attention,
	}


static func color_for_severity(severity: String) -> Color:
	match severity:
		"ok":
			return COLOR_OK
		"busy":
			return COLOR_BUSY
		"attention":
			return COLOR_ATTENTION
		"warn":
			return COLOR_WARN
		"error":
			return COLOR_ERROR
		_:
			return COLOR_IDLE


static func is_foreground_busy(runtime_state: String) -> bool:
	return runtime_state in BUSY_STATES


static func working_indicator_text(runtime_state: String, elapsed_seconds: int = 0, token_usage: Dictionary = {}) -> String:
	var label := ""
	match runtime_state:
		"waiting_for_approval":
			label = "Waiting for approval..."
		"applying_diff":
			label = "Applying approved change..."
		"turn_running":
			label = "Still working..."
		_:
			return ""

	var elapsed := format_elapsed_seconds(elapsed_seconds)
	if elapsed != "":
		label += " " + elapsed

	var token_text := token_usage_text(token_usage)
	if token_text != "":
		label += " | " + token_text
	return label


static func format_elapsed_seconds(total_seconds: int) -> String:
	var seconds: int = max(total_seconds, 0)
	if seconds <= 0:
		return ""
	var hours := int(seconds / 3600)
	var minutes := int((seconds % 3600) / 60)
	var remaining_seconds := seconds % 60
	if hours > 0:
		return str(hours) + "h " + str(minutes) + "m"
	if minutes > 0:
		return str(minutes) + "m " + str(remaining_seconds) + "s"
	return str(remaining_seconds) + "s"


static func token_usage_text(token_usage: Dictionary) -> String:
	var total := int(token_usage.get("total", token_usage.get("totalTokens", 0)))
	if total <= 0:
		var input := int(token_usage.get("input", token_usage.get("inputTokens", 0)))
		var output := int(token_usage.get("output", token_usage.get("outputTokens", 0)))
		total = input + output
	if total <= 0:
		return ""
	return str(total) + " tokens"


static func tools_state_label(state: Dictionary) -> String:
	if bool(state.get("tools_available", false)):
		return "ok"
	if str(state.get("last_tool_inventory_at", "")) == "":
		return "checking"
	return "missing"


static func instructions_state_label(state: Dictionary) -> String:
	var count := int(state.get("agents_count", -1))
	if count > 0:
		return str(count) + (" file" if count == 1 else " files")
	if count == 0:
		return "optional"
	if str(state.get("active_project_root", "")) != "":
		return "checking"
	return "not attached"


static func instructions_status_detail(state: Dictionary) -> String:
	var count := int(state.get("agents_count", -1))
	if count > 0:
		return "Project instructions loaded from " + str(count) + " AGENTS.md " + ("file." if count == 1 else "files.")
	if count == 0:
		return "No project AGENTS.md instructions were found. This is optional; Codex will still use your prompt and live Godot context."
	if str(state.get("active_project_root", "")) != "":
		return "Checking the attached project for AGENTS.md instructions."
	return "No project is attached yet, so project instructions have not been checked."


static func readiness_label(state: Dictionary) -> String:
	if bool(state.get("project_mismatch", false)):
		return "Project mismatch | Tools: " + tools_state_label(state) + " | Instructions: " + instructions_state_label(state)
	return "Launcher: " + str(state.get("host_config_status", "unknown")) + " | Tools: " + tools_state_label(state) + " | Instructions: " + instructions_state_label(state)


static func status_tooltip(state: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("Host: " + str(state.get("connection_state", "disconnected")) + " | Runtime: " + str(state.get("runtime_state", "disconnected")))
	lines.append("Host process: " + host_process_status_label(state))
	lines.append("Heartbeat: " + heartbeat_status_label(state))
	lines.append("Thread: " + _value_or_default(str(state.get("thread_id", "")), "none"))
	lines.append("Bridge tools: " + tools_state_label(state))
	if str(state.get("mcp_server_name", "")) != "":
		lines.append("MCP server: " + str(state.get("mcp_server_name", "")))
	if str(state.get("last_tool_inventory_at", "")) != "":
		lines.append("Tool inventory: " + str(state.get("last_tool_inventory_at", "")))
	lines.append("Godot tools: " + str(int(state.get("mcp_godot_tool_count", 0))) + " / " + str(int(state.get("mcp_tool_count", 0))))
	lines.append("Model: " + _value_or_default(str(state.get("selected_model", "")), "default"))
	lines.append("Reasoning: " + _value_or_default(str(state.get("selected_reasoning", "")), "default"))
	lines.append("Trust: " + str(state.get("trust_mode", "off")))
	if bool(state.get("project_mismatch", false)):
		lines.append("Project mismatch: reconnect this Godot project before sending new work.")
		lines.append("Host project root: " + _value_or_default(str(state.get("host_project_root", "")), "unknown"))
		lines.append("Editor project root: " + _value_or_default(str(state.get("editor_project_root", "")), "unknown"))
	if str(state.get("tool_visibility_error", "")) != "":
		lines.append("Tool warning: " + str(state.get("tool_visibility_error", "")))
	var heartbeat_detail := heartbeat_status_detail(state)
	if heartbeat_detail != "":
		lines.append(heartbeat_detail)
	if str(state.get("backpressure_text", "")) != "":
		lines.append(str(state.get("backpressure_text", "")))
	return "\n".join(lines)


static func readiness_tooltip(state: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("Launcher: " + str(state.get("host_config_status", "unknown")))
	lines.append("Launcher message: " + str(state.get("host_config_message", "")))
	lines.append("Host config: " + str(state.get("host_config_path", "")))
	if str(state.get("host_config_runtime", "")) != "":
		lines.append("Runtime: " + str(state.get("host_config_runtime", "")))
	var port := int(state.get("host_config_port", 0))
	if port > 0:
		lines.append("Port: " + str(port))
	if str(state.get("host_config_launcher_path", "")) != "":
		lines.append("Launcher path: " + str(state.get("host_config_launcher_path", "")))
	lines.append("Host process: " + host_process_status_label(state))
	lines.append(host_process_status_detail(state))
	lines.append("Heartbeat: " + heartbeat_status_label(state))
	var heartbeat_detail := heartbeat_status_detail(state)
	if heartbeat_detail != "":
		lines.append(heartbeat_detail)
	lines.append("Bridge tools: " + tools_state_label(state))
	if str(state.get("mcp_server_name", "")) != "":
		lines.append("MCP server: " + str(state.get("mcp_server_name", "")))
	if str(state.get("last_tool_inventory_at", "")) != "":
		lines.append("Tool inventory: " + str(state.get("last_tool_inventory_at", "")))
	lines.append("Godot tools: " + str(int(state.get("mcp_godot_tool_count", 0))) + " / " + str(int(state.get("mcp_tool_count", 0))))
	if str(state.get("tool_visibility_error", "")) != "":
		lines.append("Tool warning: " + str(state.get("tool_visibility_error", "")))
	lines.append("Project instructions: " + instructions_state_label(state))
	lines.append(instructions_status_detail(state))
	if str(state.get("active_project_root", "")) != "":
		lines.append("Project root: " + str(state.get("active_project_root", "")))
	if bool(state.get("project_mismatch", false)):
		lines.append("Project mismatch: Codex Host is attached to a different project.")
		lines.append("Host project root: " + _value_or_default(str(state.get("host_project_root", "")), "unknown"))
		lines.append("Editor project root: " + _value_or_default(str(state.get("editor_project_root", "")), "unknown"))
		lines.append("Use Reconnect to this project before sending new work or refreshing tools.")
	var agents_paths := _string_array(state.get("agents_paths", []))
	if agents_paths.size() > 0:
		lines.append("AGENTS.md files:")
		for agents_path in agents_paths.slice(0, 5):
			lines.append("- " + agents_path)
	if str(state.get("recoverable_message", "")) != "":
		lines.append("Recoverable: " + str(state.get("recoverable_message", "")))
	if str(state.get("fatal_message", "")) != "":
		lines.append("Fatal: " + str(state.get("fatal_message", "")))
	if str(state.get("backpressure_text", "")) != "":
		lines.append(str(state.get("backpressure_text", "")))
	lines.append("Trust: " + str(state.get("trust_mode", "off")))
	lines.append("Selected model: " + _value_or_default(str(state.get("selected_model", "")), "default"))
	lines.append("Reasoning: " + _value_or_default(str(state.get("selected_reasoning", "")), "default"))
	return "\n".join(lines)


static func host_process_status(state: Dictionary) -> String:
	var process_id := int(state.get("host_process_id", 0))
	var owned := bool(state.get("host_process_owned_by_addon", false))
	var running := bool(state.get("host_process_running", false))
	var connection_state := str(state.get("connection_state", "disconnected"))
	if process_id <= 0:
		if connection_state == "ready" or connection_state == "connecting":
			return "external"
		return "stopped"
	if owned and running:
		return "owned"
	if owned and not running:
		return "stale"
	if running:
		return "external"
	return "unknown"


static func host_process_status_label(state: Dictionary) -> String:
	var status := host_process_status(state)
	match status:
		"owned":
			return "owned by addon, running"
		"external":
			return "external or already running"
		"stale":
			return "stale owned process"
		"stopped":
			return "not running"
		_:
			return "unknown"


static func host_process_status_detail(state: Dictionary) -> String:
	var process_id := int(state.get("host_process_id", 0))
	var status := host_process_status(state)
	match status:
		"owned":
			return "This Codex Host was started by the addon and can be stopped safely on disconnect/reconnect. PID: " + str(process_id)
		"external":
			return "Codex Host appears external or was already running; the addon will not kill it."
		"stale":
			return "The addon remembers an owned Codex Host PID, but that process is no longer running. Reconnect will start a fresh host. PID: " + str(process_id)
		"stopped":
			return "No addon-owned Codex Host process is currently tracked."
		_:
			return "Codex Host process ownership is unknown."


static func heartbeat_status(state: Dictionary) -> String:
	if not state.has("heartbeat_exists") and not state.has("heartbeat_age_ms"):
		return "unknown"
	if not bool(state.get("heartbeat_exists", false)):
		return "missing"
	var age_ms := int(state.get("heartbeat_age_ms", -1))
	var stale_after_ms := int(state.get("heartbeat_stale_after_ms", 0))
	if age_ms < 0:
		return "unknown"
	if stale_after_ms > 0 and age_ms > stale_after_ms:
		return "stale"
	return "fresh"


static func heartbeat_status_label(state: Dictionary) -> String:
	var status := heartbeat_status(state)
	match status:
		"fresh":
			return "fresh bridge evidence"
		"stale":
			return "stale bridge evidence"
		"missing":
			return "missing heartbeat file"
		_:
			return "unknown"


static func heartbeat_status_detail(state: Dictionary) -> String:
	var status := heartbeat_status(state)
	var age_ms := int(state.get("heartbeat_age_ms", -1))
	var stale_after_ms := int(state.get("heartbeat_stale_after_ms", 0))
	match status:
		"fresh":
			if age_ms >= 0:
				return "The addon wrote fresh bridge heartbeat evidence " + _format_ms(age_ms) + " ago."
			return "The addon has fresh bridge heartbeat evidence."
		"stale":
			var stale_text := _format_ms(stale_after_ms) if stale_after_ms > 0 else "the freshness limit"
			return "No fresh bridge heartbeat evidence has been written for " + _format_ms(age_ms) + "; expected within " + stale_text + ". Reconnect or reload the editor if this does not recover."
		"missing":
			return "The bridge heartbeat file is missing. The addon may not have finished startup, or the editor bridge is not active."
		_:
			return ""


static func _value_or_default(value: String, fallback: String) -> String:
	return value if value != "" else fallback


static func _format_ms(value_ms: int) -> String:
	var safe_ms: int = max(value_ms, 0)
	if safe_ms < 1000:
		return str(safe_ms) + "ms"
	var seconds := int(safe_ms / 1000)
	if seconds < 60:
		return str(seconds) + "s"
	var minutes := int(seconds / 60)
	var remaining_seconds := seconds % 60
	if remaining_seconds == 0:
		return str(minutes) + "m"
	return str(minutes) + "m " + str(remaining_seconds) + "s"


static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return result
	for item in value as Array:
		var text := str(item)
		if text != "":
			result.append(text)
	return result


static func _project_mismatch(host_root: String, editor_root: String, explicit_value: Variant = null) -> bool:
	if typeof(explicit_value) == TYPE_BOOL:
		return bool(explicit_value)
	var normalized_host := _normalize_path(host_root)
	var normalized_editor := _normalize_path(editor_root)
	if normalized_host == "" or normalized_editor == "":
		return false
	return normalized_host != normalized_editor


static func _normalize_path(value: String) -> String:
	var normalized := value.strip_edges().replace("\\", "/")
	while normalized.ends_with("/"):
		normalized = normalized.substr(0, normalized.length() - 1)
	return normalized.to_lower()
