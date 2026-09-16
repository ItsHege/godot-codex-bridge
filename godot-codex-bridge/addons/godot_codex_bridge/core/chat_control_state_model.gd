@tool
extends RefCounted

const ChatApprovalModel := preload("res://addons/godot_codex_bridge/core/chat_approval_model.gd")
const ChatSessionModel := preload("res://addons/godot_codex_bridge/core/chat_session_model.gd")
const ChatStatusModel := preload("res://addons/godot_codex_bridge/core/chat_status_model.gd")
const ChatTeamModel := preload("res://addons/godot_codex_bridge/core/chat_team_model.gd")

const EYE_ATTACH_TOOLTIP := "Eye Attach: capture Godot editor or viewport, mark it as a user reference, and attach it to the next message. Ctrl+F12 is a plain screenshot; Eye adds AI-safe marker metadata."


static func ui_context(state: Dictionary) -> Dictionary:
	var chat_enabled := bool(state.get("chat_enabled", false))
	var marker_enabled := bool(state.get("marker_enabled", false))
	var team_permission := bool(state.get("team_permission", false))
	var trust_permission := bool(state.get("trust_permission", true))
	var connected := bool(state.get("connected", false))
	var connecting := bool(state.get("connecting", false))
	var runtime_state := str(state.get("runtime_state", "disconnected"))
	var tools_available := bool(state.get("tools_available", false))
	var active_project_root := str(state.get("active_project_root", ""))
	var editor_project_root := str(state.get("editor_project_root", ""))
	var project_mismatch := _project_mismatch(active_project_root, editor_project_root, state.get("project_mismatch", null))
	var approval := _approval_dict(state.get("approval", {}))
	var control := control_context({
		"chat_enabled": chat_enabled,
		"marker_enabled": marker_enabled,
		"team_permission": team_permission,
		"trust_permission": trust_permission,
		"connected": connected,
		"connecting": connecting,
		"runtime_state": runtime_state,
		"thread_id": str(state.get("thread_id", "")),
		"turn_id": str(state.get("turn_id", "")),
		"message_count": int(state.get("message_count", 0)),
		"tools_available": tools_available,
		"active_project_root": active_project_root,
		"editor_project_root": editor_project_root,
		"project_mismatch": project_mismatch,
		"trust_mode": str(state.get("trust_mode", "off")),
		"background_state": str(state.get("background_state", "idle")),
		"host_config_message": str(state.get("host_config_message", "")),
		"approval": approval,
	})
	return {
		"status": ChatStatusModel.compute({
			"chat_enabled": chat_enabled,
			"connected": connected,
			"connecting": connecting,
			"runtime_state": runtime_state,
			"host_config_status": str(state.get("host_config_status", "")),
			"tools_available": tools_available,
			"has_approval": not approval.is_empty(),
			"project_mismatch": project_mismatch,
		}),
		"control_context": control,
		"foreground_busy": bool(control.get("foreground_busy", false)),
		"controls": control.get("controls", {}),
	}


static func control_context(state: Dictionary) -> Dictionary:
	var chat_enabled := bool(state.get("chat_enabled", false))
	var marker_enabled := bool(state.get("marker_enabled", false))
	var team_permission := bool(state.get("team_permission", false))
	var trust_permission := bool(state.get("trust_permission", true))
	var team_enabled := chat_enabled and team_permission
	var connected := bool(state.get("connected", false))
	var connecting := bool(state.get("connecting", false))
	var runtime_state := str(state.get("runtime_state", "disconnected"))
	var foreground_busy := is_foreground_busy(runtime_state)
	var controls := controls_state({
		"chat_enabled": chat_enabled,
		"marker_enabled": marker_enabled,
		"team_enabled": team_enabled,
		"trust_permission": trust_permission,
		"connected": connected,
		"connecting": connecting,
		"foreground_busy": foreground_busy,
		"runtime_state": runtime_state,
		"thread_id": str(state.get("thread_id", "")),
		"turn_id": str(state.get("turn_id", "")),
		"message_count": int(state.get("message_count", 0)),
		"tools_available": bool(state.get("tools_available", false)),
		"active_project_root": str(state.get("active_project_root", "")),
		"editor_project_root": str(state.get("editor_project_root", "")),
		"project_mismatch": bool(state.get("project_mismatch", false)),
		"trust_mode": str(state.get("trust_mode", "off")),
		"background_state": str(state.get("background_state", "idle")),
		"host_config_message": str(state.get("host_config_message", "")),
		"approval": state.get("approval", {}),
	})
	return {
		"chat_enabled": chat_enabled,
		"marker_enabled": marker_enabled,
		"team_enabled": team_enabled,
		"connected": connected,
		"connecting": connecting,
		"foreground_busy": foreground_busy,
		"controls": controls,
	}


static func controls_state(state: Dictionary) -> Dictionary:
	var chat_enabled := bool(state.get("chat_enabled", false))
	var marker_enabled := bool(state.get("marker_enabled", false))
	var team_enabled := chat_enabled and bool(state.get("team_enabled", false))
	var trust_permission := bool(state.get("trust_permission", true))
	var connected := bool(state.get("connected", false))
	var connecting := bool(state.get("connecting", false))
	var foreground_busy := bool(state.get("foreground_busy", false))
	var runtime_state := str(state.get("runtime_state", "disconnected"))
	var thread_id := str(state.get("thread_id", ""))
	var turn_id := str(state.get("turn_id", ""))
	var message_count := int(state.get("message_count", 0))
	var tools_available := bool(state.get("tools_available", false))
	var active_project_root := str(state.get("active_project_root", ""))
	var editor_project_root := str(state.get("editor_project_root", ""))
	var project_mismatch := _project_mismatch(active_project_root, editor_project_root, state.get("project_mismatch", null))
	var trust_mode := str(state.get("trust_mode", "off"))
	var background_state := str(state.get("background_state", "idle"))
	var host_config_message := str(state.get("host_config_message", ""))
	var approval := _approval_dict(state.get("approval", {}))
	var has_approval := not approval.is_empty()
	var approval_can_approve := ChatApprovalModel.can_approve(approval)
	var approval_can_approve_session := ChatApprovalModel.can_approve_session(approval)
	var team_active := ChatTeamModel.is_active_state(background_state)

	return {
		"connect": connect_state(chat_enabled, connected, connecting, runtime_state, host_config_message, project_mismatch),
		"send": send_state(chat_enabled, connected, foreground_busy, project_mismatch),
		"eye": eye_state(marker_enabled),
		"new": new_chat_state(chat_enabled, runtime_state, thread_id),
		"clear": {"disabled": not ChatSessionModel.can_clear_transcript(message_count)},
		"cancel": {"disabled": not connected or turn_id == ""},
		"emergency_stop": emergency_stop_state(),
		"enable_tools": enable_tools_state(chat_enabled, connected, tools_available, active_project_root, project_mismatch),
		"trust": trust_state(chat_enabled, trust_permission, connected, foreground_busy or project_mismatch, trust_mode),
		"team_review": {"disabled": not team_enabled or not connected or team_active or project_mismatch},
		"team_cancel": {"disabled": not connected or not team_active},
		"approve": approve_state(connected, has_approval, approval_can_approve, approval),
		"approve_session": approve_session_state(connected, has_approval, approval_can_approve_session),
		"reject": {"disabled": not connected or not has_approval},
		"revise": {"disabled": not connected or not has_approval},
	}


static func is_foreground_busy(runtime_state: String) -> bool:
	return runtime_state == "turn_running" or runtime_state == "waiting_for_approval" or runtime_state == "applying_diff"


static func connect_state(chat_enabled: bool, connected: bool, connecting: bool, runtime_state: String, host_config_message: String, project_mismatch := false) -> Dictionary:
	var text := "Connect"
	if connected and project_mismatch:
		text = "Reconnect"
	elif connected:
		text = "Refresh"
	elif connecting:
		text = "Connecting"
	elif runtime_state == "error_recoverable":
		text = "Reconnect"
	return {
		"disabled": not chat_enabled or connecting,
		"text": text,
		"tooltip": "Host is attached to a different Godot project. Reconnect will attach this editor project and refresh tools." if connected and project_mismatch else ("Re-attach this Godot project and refresh Codex Bridge tools." if connected else host_config_message),
	}


static func send_state(chat_enabled: bool, connected: bool, foreground_busy: bool, project_mismatch := false) -> Dictionary:
	return {
		"disabled": not chat_enabled or not connected or foreground_busy or project_mismatch,
		"tooltip": "Reconnect to this project before sending new work." if project_mismatch else ("Codex is still working. Wait, cancel, or answer the approval card." if foreground_busy else ""),
	}


static func eye_state(marker_enabled: bool) -> Dictionary:
	return {
		"disabled": not marker_enabled,
		"tooltip": "AI marker attachments are disabled in the Codex Bridge dock." if not marker_enabled else EYE_ATTACH_TOOLTIP,
	}


static func new_chat_state(chat_enabled: bool, runtime_state: String, thread_id: String) -> Dictionary:
	return {
		"disabled": not chat_enabled or not ChatSessionModel.can_start_new_chat(runtime_state),
		"tooltip": ChatSessionModel.new_chat_tooltip(thread_id, runtime_state),
	}


static func enable_tools_state(chat_enabled: bool, connected: bool, tools_available: bool, active_project_root := "", project_mismatch := false) -> Dictionary:
	var tooltip := "Connect Codex first."
	if tools_available:
		tooltip = "Refresh the local Godot Codex Bridge MCP tools for this attached project."
	if connected and project_mismatch:
		tooltip = "Reconnect to this project before enabling or refreshing tools."
	elif connected and str(active_project_root).strip_edges() == "":
		tooltip = "Waiting for Codex to attach this Godot project before enabling tools."
	elif connected:
		tooltip = "Register and reload the local Godot Codex Bridge MCP tools for this Codex runtime."
	return {
		"disabled": not chat_enabled or not connected or str(active_project_root).strip_edges() == "" or project_mismatch,
		"text": "Refresh Tools" if tools_available else "Enable Tools",
		"tooltip": tooltip,
	}


static func trust_state(chat_enabled: bool, trust_permission: bool, connected: bool, foreground_busy: bool, trust_mode: String) -> Dictionary:
	var full_trust := trust_mode == "full_machine"
	var tooltip := "Full-machine Trust Session is active for new turns until cleared or the host restarts." if full_trust else "Enable full-machine trust for this Codex Host session."
	if not trust_permission:
		tooltip = "Enable the Full Trust permission profile before using full-machine Trust Session."
	return {
		"disabled": not chat_enabled or not trust_permission or not connected or foreground_busy,
		"pressed": full_trust,
		"text": "Trust: full" if full_trust else "Trust Session",
		"tooltip": tooltip,
	}


static func approve_state(connected: bool, has_approval: bool, can_approve: bool, approval: Dictionary) -> Dictionary:
	return {
		"disabled": not connected or not has_approval or not can_approve,
		"tooltip": ChatApprovalModel.disabled_reason(approval) if has_approval and not can_approve else "",
	}


static func approve_session_state(connected: bool, has_approval: bool, can_approve_session: bool) -> Dictionary:
	return {
		"disabled": not connected or not has_approval or not can_approve_session,
		"visible": has_approval and can_approve_session,
		"tooltip": "Session approval is available for commands and file changes only." if has_approval and not can_approve_session else "Approve this request for the current app-server session where supported.",
	}


static func emergency_stop_state() -> Dictionary:
	return {
		"disabled": false,
		"text": "Stop All",
		"tooltip": "Emergency stop: interrupt Codex, cancel team work, clear approval/trust, stop Godot play session, and disconnect owned host.",
	}


static func _approval_dict(value: Variant) -> Dictionary:
	return value if typeof(value) == TYPE_DICTIONARY else {}


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
