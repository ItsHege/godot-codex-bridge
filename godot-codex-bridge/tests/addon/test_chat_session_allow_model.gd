extends SceneTree

const Allow := preload("res://addons/godot_codex_bridge/core/chat_session_allow_model.gd")
const ChatApprovalModel := preload("res://addons/godot_codex_bridge/core/chat_approval_model.gd")
const ChatControlStateModel := preload("res://addons/godot_codex_bridge/core/chat_control_state_model.gd")
const ChatHostStateModel := preload("res://addons/godot_codex_bridge/core/chat_host_state_model.gd")
const ChatApprovalPopup := preload("res://addons/godot_codex_bridge/core/chat_approval_popup.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge session allow model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge session allow model tests failed: " + str(_failures))
		quit(1)


func _card(extra: Dictionary = {}) -> Dictionary:
	var params := {"approval_id": "approval-1", "kind": "elicitation", "nonce": "n1", "safe_default": "manual_only", "approvable_by_chat": true, "session_allow_tool": "godot.bridge_status"}
	for key in extra.keys():
		params[key] = extra[key]
	return params


func _run() -> void:
	_true(Allow.valid_tool_name("godot.get_scene_tree"), "Godot tool name accepted")
	for bad in ["", "godot.", "fs.read", "godot.Scene", "godot.a b", "godot.[b]x", 5, null]:
		_false(Allow.valid_tool_name(bad), "rejected tool name: " + str(bad))
	_eq(Allow.sanitize_tools(["godot.a", "godot.a", "evil", "godot.b"]), ["godot.a", "godot.b"], "tools sanitized and de-duplicated")
	_eq(Allow.sanitize_tools("godot.a"), [], "non-array ignored")

	# Button visibility and eligibility.
	_true(ChatApprovalModel.can_allow_session_tool(_card()), "marked plain approval is eligible")
	var unmarked := _card()
	unmarked.erase("session_allow_tool")
	_false(ChatApprovalModel.can_allow_session_tool(unmarked), "no session_allow_tool, no button")
	_false(ChatApprovalModel.can_allow_session_tool(_card({"kind": "file_change", "diff_hash": "h"})), "file changes never remembered")
	_false(ChatApprovalModel.can_allow_session_tool(_card({"kind": "command_execution", "command": "ls"})), "commands never remembered")
	_false(ChatApprovalModel.can_allow_session_tool(_card({"session_allow_tool": "shell.exec"})), "non-Godot tool rejected")
	_false(ChatApprovalModel.can_allow_session_tool(_card({"nonce": ""})), "unapprovable card rejected")
	var connected := ChatControlStateModel.controls_state({"chat_enabled": true, "connected": true, "approval": _card()})
	var state: Dictionary = connected.get("allow_session_tool", {})
	_true(bool(state.get("visible", false)) and not bool(state.get("disabled", true)), "button visible and enabled when connected")
	_true(str(state.get("tooltip", "")).contains("godot.bridge_status") and str(state.get("tooltip", "")).contains("Changes to your project still ask"), "tooltip names the tool")
	var other := ChatControlStateModel.controls_state({"chat_enabled": true, "connected": true, "approval": unmarked})
	_false(bool((other.get("allow_session_tool", {}) as Dictionary).get("visible", true)), "hidden for other cards")
	var offline := ChatControlStateModel.controls_state({"chat_enabled": true, "connected": false, "approval": _card()})
	_true(bool((offline.get("allow_session_tool", {}) as Dictionary).get("disabled", false)), "disabled while disconnected")

	# Same response path, approve + flag.
	var plan := ChatApprovalModel.response_plan(_card(), ChatApprovalModel.DECISION_APPROVE_REMEMBER, "ok", true)
	var payload: Dictionary = plan.get("params", {})
	_true(bool(plan.get("ok", false)) and plan.get("method") == "approval.respond", "sent through approval.respond")
	_eq(payload.get("decision"), "approve", "decision stays approve")
	_true(payload.get("remember_for_session") == true and payload.get("nonce") == "n1" and payload.get("approval_id") == "approval-1", "flag added; nonce and id unchanged")
	_false(bool(plan.get("clear_approval", true)), "like Approve, waits for the Host resolution")
	var normal: Dictionary = ChatApprovalModel.response_plan(_card(), "approve", "", true).get("params", {})
	_false(normal.has("remember_for_session"), "plain Approve never sends the flag")
	_false(bool(ChatApprovalModel.response_plan(unmarked, ChatApprovalModel.DECISION_APPROVE_REMEMBER, "", true).get("ok", true)), "ineligible remember refused locally")
	_false(bool(ChatApprovalModel.response_plan({}, ChatApprovalModel.DECISION_APPROVE_REMEMBER, "", true).get("ok", true)), "stale remember sends nothing")

	# Popup button mirrors the state.
	var popup := ChatApprovalPopup.new()
	popup.apply_button_states(connected)
	_true(popup.allow_session_tool_button.visible and not popup.allow_session_tool_button.disabled and popup.allow_session_tool_button.text == "Allow this session", "popup shows Allow this session")
	popup.apply_button_states(other)
	_false(popup.allow_session_tool_button.visible, "popup hides it for other cards")
	popup.free()

	# Auto-approved coalescing.
	var first := Allow.coalesce({}, {"tool": "godot.bridge_status", "turn_id": "t1"}, false)
	_true(bool(first.get("new_line", false)), "first auto-approval adds a line")
	var second := Allow.coalesce(first.get("state", {}), {"tool": "godot.get_scene_tree", "turn_id": "t1"}, true)
	_false(bool(second.get("new_line", true)), "same turn updates the line")
	_eq(second.get("text"), "Auto-approved: godot.bridge_status, godot.get_scene_tree (allowed this session)", "coalesced text")
	var repeat := Allow.coalesce(second.get("state", {}), {"tool": "godot.bridge_status", "turn_id": "t1"}, true)
	_eq(repeat.get("text"), second.get("text"), "repeated tool not duplicated")
	_true(bool(Allow.coalesce(second.get("state", {}), {"tool": "godot.bridge_status", "turn_id": "t2"}, true).get("new_line", false)), "new turn starts a new line")
	_true(bool(Allow.coalesce(second.get("state", {}), {"tool": "godot.bridge_status", "turn_id": "t1"}, false).get("new_line", false)), "a newer message in between starts a new line")
	_true(str(Allow.coalesce({}, {"tool": "[b]x"}, false).get("text", "")).contains("a remembered Godot tool"), "untrusted tool text not echoed")

	# host.status and summary.
	var patch := ChatHostStateModel.host_status_patch({"sessionAllowedTools": ["godot.a", "bad"]})
	_eq(patch.get("session_allowed_tools"), ["godot.a"], "host.status list sanitized")
	_false(ChatHostStateModel.host_status_patch({}).has("session_allowed_tools"), "missing list leaves state alone")
	_eq(Allow.summary_text(["godot.a", "godot.b"]), "Allowed this session: 2 tools", "summary")
	_true(Allow.summary_tooltip(["godot.a"]).contains("godot.a"), "summary tooltip lists tools")


func _eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures += 1
		push_error(label + " expected=" + str(expected) + " actual=" + str(actual))


func _true(value: bool, label: String) -> void:
	if not value:
		_failures += 1
		push_error(label)


func _false(value: bool, label: String) -> void:
	if value:
		_failures += 1
		push_error(label)
