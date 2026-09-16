@tool
extends RefCounted

const ChatSocketEventModel := preload("res://addons/godot_codex_bridge/core/chat_socket_event_model.gd")


static func host_status_patch(data: Dictionary) -> Dictionary:
	var patch := {}
	if data.has("recoverableMessage"):
		var recoverable: Variant = data.get("recoverableMessage", "")
		patch["recoverable_message"] = "" if recoverable == null else str(recoverable)
	if data.has("fatalMessage"):
		var fatal: Variant = data.get("fatalMessage", "")
		patch["fatal_message"] = "" if fatal == null else str(fatal)
	if data.has("trustMode"):
		var trust: Variant = data.get("trustMode", "off")
		patch["trust_mode"] = "off" if trust == null else str(trust)

	var project: Variant = data.get("activeProject", null)
	if typeof(project) == TYPE_DICTIONARY:
		var project_dict := project as Dictionary
		patch["active_project_root"] = str(project_dict.get("projectRoot", ""))
		var agents: Variant = project_dict.get("agentsFiles", [])
		if typeof(agents) == TYPE_ARRAY:
			var paths: Array[String] = []
			for item in agents:
				if typeof(item) != TYPE_DICTIONARY:
					continue
				var agents_path := str((item as Dictionary).get("path", ""))
				if agents_path != "":
					paths.append(agents_path)
			patch["agents_count"] = (agents as Array).size()
			patch["agents_paths"] = paths
	return patch


static func tool_visibility_patch(data: Dictionary, current: Dictionary = {}) -> Dictionary:
	var patch := {}
	var tools_available := bool(current.get("tools_available", false))
	var last_reported_error := str(current.get("last_reported_error", ""))
	if data.has("mcpToolsAvailable"):
		tools_available = bool(data.get("mcpToolsAvailable", false))
		patch["mcp_tools_available"] = tools_available
	if data.has("mcpToolCount"):
		patch["mcp_tool_count"] = int(data.get("mcpToolCount", 0))
	if data.has("mcpGodotToolCount"):
		patch["mcp_godot_tool_count"] = int(data.get("mcpGodotToolCount", 0))
	if data.has("mcpServerName"):
		var server_name: Variant = data.get("mcpServerName", "")
		patch["mcp_server_name"] = "" if server_name == null else str(server_name)
	if data.has("lastToolInventoryAt"):
		patch["last_tool_inventory_at"] = str(data.get("lastToolInventoryAt", ""))
	if data.has("toolVisibilityError"):
		var error_text: Variant = data.get("toolVisibilityError", "")
		var tool_error := "" if error_text == null else str(error_text)
		patch["tool_visibility_error"] = tool_error
		if tool_error != "" and not tools_available and tool_error != last_reported_error:
			patch["last_reported_tool_visibility_error"] = tool_error
			patch["detail_messages"] = ["Bridge tools unavailable: " + tool_error]
	return patch


static func result_state_patch(data: Dictionary, current: Dictionary = {}) -> Dictionary:
	var patch := {}
	if data.has("thread_id"):
		patch["thread_id"] = str(data.get("thread_id", ""))
	if data.has("task_id"):
		patch["background_task_id"] = str(data.get("task_id", current.get("background_task_id", "")))
		patch["background_state"] = str(data.get("state", current.get("background_state", "")))
	return patch


static func result_messages(data: Dictionary, current: Dictionary = {}) -> Dictionary:
	var system_messages: Array[String] = []
	var detail_messages: Array[String] = []
	var project: Variant = data.get("activeProject", null)
	if typeof(project) == TYPE_DICTIONARY:
		detail_messages.append("Project attached: " + str((project as Dictionary).get("projectRoot", "")))

	if data.has("trustSessionChanged"):
		if str(current.get("trust_mode", "off")) == "full_machine":
			system_messages.append("Trust Session active: full-machine access for new turns.")
		else:
			system_messages.append("Trust Session cleared.")

	if data.has("bridgeToolsEnabled"):
		if bool(data.get("bridgeToolsEnabled", false)):
			var tools_message := "Bridge tools enabled."
			if data.has("bridgeToolsEvidencePath"):
				tools_message += " Evidence: " + str(data.get("bridgeToolsEvidencePath", ""))
			system_messages.append(tools_message)
			if not bool(current.get("mcp_tools_available", false)) and str(current.get("tool_visibility_error", "")) != "":
				system_messages.append("Bridge tools were registered, but Codex has not reported them yet: " + str(current.get("tool_visibility_error", "")))
		else:
			system_messages.append("Bridge tools were not enabled.")

	if data.has("bridgeToolsPreview"):
		detail_messages.append("Bridge tools preview received.")

	return {
		"system_messages": system_messages,
		"detail_messages": detail_messages,
		"has_models": data.has("models"),
		"has_tasks": data.has("tasks") and typeof(data.get("tasks")) == TYPE_ARRAY,
	}


static func token_usage_patch(data: Dictionary) -> Dictionary:
	var usage: Variant = data.get("tokenUsage", data.get("usage", null))
	if typeof(usage) != TYPE_DICTIONARY:
		return {}
	return usage as Dictionary


static func result_plan(data: Dictionary, current: Dictionary = {}) -> Dictionary:
	var source_method := str(current.get("source_method", ""))
	var runtime_state := ChatSocketEventModel.runtime_state_from_result(
		data,
		str(current.get("runtime_state", "ready"))
	)
	var tool_patch := tool_visibility_patch(data, {
		"tools_available": bool(current.get("mcp_tools_available", false)),
		"last_reported_error": str(current.get("last_reported_tool_visibility_error", "")),
	})
	if source_method == "bridge.tools.enable":
		tool_patch["clear_auto_enable_tools_requested"] = true
	var host_patch := host_status_patch(data)
	var state_patch := result_state_patch(data, {
		"background_task_id": str(current.get("background_task_id", "")),
		"background_state": str(current.get("background_state", "")),
	})
	var effective_trust_mode := str(host_patch.get("trust_mode", current.get("trust_mode", "off")))
	var effective_tools_available := bool(tool_patch.get("mcp_tools_available", current.get("mcp_tools_available", false)))
	var effective_tool_error := str(tool_patch.get("tool_visibility_error", current.get("tool_visibility_error", "")))
	var messages := result_messages(data, {
		"trust_mode": effective_trust_mode,
		"mcp_tools_available": effective_tools_available,
		"tool_visibility_error": effective_tool_error,
	})
	return {
		"runtime_state": runtime_state,
		"token_usage": token_usage_patch(data),
		"host_status_patch": host_patch,
		"tool_visibility_patch": tool_patch,
		"result_state_patch": state_patch,
		"auto_enable_tools_after_attach": (source_method == "project.attach" or source_method == "host.restart_for_project") and data.has("activeProject") and typeof(data.get("activeProject")) == TYPE_DICTIONARY,
		"update_background_status_label": data.has("task_id"),
		"restore_background_tasks": bool(messages.get("has_tasks", false)),
		"update_runtime_model_options": bool(messages.get("has_models", false)),
		"system_messages": messages.get("system_messages", []),
		"detail_messages": messages.get("detail_messages", []),
	}


static func result_effect_plan(data: Dictionary, current: Dictionary = {}) -> Dictionary:
	var source_method := str(current.get("source_method", ""))
	var plan := result_plan(data, current)
	var effects: Array[Dictionary] = [
		{
			"action": "apply_runtime_state",
			"runtime_state": str(plan.get("runtime_state", current.get("runtime_state", "ready"))),
		},
		{
			"action": "apply_token_usage_patch",
			"patch": plan.get("token_usage", {}),
		},
		{
			"action": "apply_host_status_patch",
			"patch": plan.get("host_status_patch", {}),
		},
		{
			"action": "apply_tool_visibility_patch",
			"patch": plan.get("tool_visibility_patch", {}),
		},
		{
			"action": "apply_result_state_patch",
			"patch": plan.get("result_state_patch", {}),
		},
	]
	if bool(plan.get("update_background_status_label", false)):
		effects.append({
			"action": "update_background_status_label",
		})
	if bool(plan.get("restore_background_tasks", false)):
		effects.append({
			"action": "restore_background_tasks",
			"tasks": data.get("tasks"),
		})
	if bool(plan.get("auto_enable_tools_after_attach", false)):
		effects.append({
			"action": "auto_enable_tools",
			"force": true,
			"source": source_method,
		})
	for message in plan.get("system_messages", []):
		effects.append({
			"action": "system_message",
			"message": str(message),
		})
	for message in plan.get("detail_messages", []):
		effects.append({
			"action": "detail_message",
			"message": str(message),
		})
	if bool(plan.get("update_runtime_model_options", false)):
		effects.append({
			"action": "update_runtime_model_options",
			"data": data,
		})
	effects.append({
		"action": "update_ui",
	})
	return {
		"effects": effects,
	}
