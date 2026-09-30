extends SceneTree

const Review := preload("res://addons/godot_codex_bridge/core/chat_approval_review_model.gd")
const ChatApprovalPopup := preload("res://addons/godot_codex_bridge/core/chat_approval_popup.gd")
const DockStyle := preload("res://addons/godot_codex_bridge/core/dock_style.gd")
const ChatControlStateModel := preload("res://addons/godot_codex_bridge/core/chat_control_state_model.gd")

var _failures := 0
var _decisions: Array[String] = []


func _init() -> void:
	_test_kinds()
	_test_elicitation()
	_test_files()
	_test_lifecycle()
	_test_popup()
	_test_dock_style()
	if _failures == 0:
		print("Godot Codex Bridge approval review model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge approval review model tests failed: " + str(_failures))
		quit(1)


func _base(kind: String, extra: Dictionary = {}) -> Dictionary:
	var params := {"approval_id": "approval-8f3e4476-aaaa", "kind": kind, "nonce": "n1", "safe_default": "manual_only", "approvable_by_chat": true, "expires_at": "2026-09-30T12:00:00Z"}
	for key in extra.keys():
		params[key] = extra[key]
	return params


func _test_kinds() -> void:
	var command := _base("command_execution", {"command": ["git", "status"], "cwd": "C:/Game", "reason": "Check the tree"})
	_eq(Review.title(command), "Run command?", "command title")
	var review := Review.review(command)
	var sections: Array = review.get("sections", [])
	_eq((sections[0] as Dictionary).get("text"), "git status", "argv command joined")
	_true(bool((sections[0] as Dictionary).get("code", false)), "command shown as code")
	_eq((sections[1] as Dictionary).get("text"), "C:/Game", "cwd shown")
	_true(str((sections[2] as Dictionary).get("text")) == "Check the tree", "reason shown")
	_true(bool(review.get("can_approve_session", false)), "command allows session approval")
	_eq(Review.title(_base("exec_command", {"command": "ls"})), "Run command?", "legacy exec_command title")
	_eq(Review.title(_base("apply_patch")), "Apply file changes?", "legacy apply_patch title")
	_eq(Review.title(_base("permissions")), "Permission request", "permission title")
	var blocked := Review.review(_base("permissions", {"approvable_by_chat": false, "blocked_reason": "Permission grants are not reviewable in Godot chat."}))
	_false(bool(blocked.get("can_approve", true)), "permission grants stay blocked")
	_true(str(blocked.get("blocked_reason", "")) != "", "blocked reason shown")
	_true(Review.bar_text(command).begins_with("Approval needed — Run command: git status"), "one-line bar text")
	_false(Review.bar_text(command).contains("approval-8f3e"), "bar never shows the raw id")
	_true(str(review.get("details", "")).contains("approval-8f3e4476-aaaa"), "raw id only in details")
	for section in sections:
		_false(str((section as Dictionary).get("text", "")).contains("Nonce"), "no protocol dump in the content")


func _test_elicitation() -> void:
	var params := _base("elicitation", {"raw_params": {
		"serverName": "godot",
		"mode": "form",
		"message": "Which scene should I open?",
		"requestedSchema": {"type": "object", "required": ["scene"], "properties": {
			"scene": {"type": "string", "title": "Scene", "enum": ["main.tscn", "test.tscn"]},
			"confirm": {"type": "boolean", "description": "Really?"},
			"note": {"type": "string"},
		}},
	}})
	_eq(Review.title(params), "Codex asks:", "elicitation title")
	var review := Review.review(params)
	_eq(((review.get("sections", []) as Array)[0] as Dictionary).get("text"), "Which scene should I open?", "elicitation message shown in full")
	var fields: Array = review.get("fields", [])
	_eq(fields.size(), 3, "schema fields summarized")
	_true((fields[0] as Dictionary).get("answer") == "main.tscn" and (fields[0] as Dictionary).get("required") == true, "enum field shows the value the Host sends")
	_eq((fields[1] as Dictionary).get("answer"), "yes", "boolean field answer")
	_eq((fields[2] as Dictionary).get("answer"), "your note", "text field uses the note")
	_true(str(review.get("details", "")).contains("from godot"), "server name in details")
	_true(str(review.get("note_placeholder", "")).begins_with("Answer"), "answer placeholder")
	var legacy := _base("elicitation", {"message": "Proceed with the plan?"})
	_eq(Review.question_message(legacy), "Proceed with the plan?", "legacy top-level message")
	_eq(Review.question_fields(legacy), [], "legacy shape without schema has no fields")
	var url_form := _base("elicitation", {"raw_params": {"mode": "url", "message": "Sign in", "url": "https://example.test/x"}})
	var url_sections: Array = Review.review(url_form).get("sections", [])
	_true(str((url_sections[1] as Dictionary).get("label", "")).contains("not opened"), "URL shown, never opened")


func _test_files() -> void:
	var diff := "--- a/a.gd\n+++ b/a.gd\n@@ -1 +1 @@\n-old\n+new\n"
	var params := _base("file_change", {"diff_hash": "h", "file_changes": {"a.gd": {"path": "res://a.gd", "unified_diff": diff}}})
	var review := Review.review(params)
	_eq(Review.title(params), "Apply file changes?", "file title")
	_true(str(review.get("diff_text", "")).contains("+new"), "diff text for the diff view")
	_true(Review.bar_text(params).ends_with("(1 file)"), "bar counts files")


func _test_lifecycle() -> void:
	var opened := {}
	var params := _base("command_execution", {"command": "ls"})
	_true(Review.should_auto_open(params, opened), "first appearance opens the popup")
	opened[params.approval_id] = true
	_false(Review.should_auto_open(params, opened), "same approval does not steal focus again")
	_true(Review.should_auto_open(_base("command_execution", {"approval_id": "approval-2"}), opened), "a new approval opens once")
	_false(Review.should_auto_open({}, opened), "no id, no popup")
	_true(Review.popup_stale("approval-8f3e4476-aaaa", {}), "resolved/invalidated approval closes the popup")
	_true(Review.popup_stale("approval-8f3e4476-aaaa", _base("command_execution", {"approval_id": "approval-2"})), "replaced approval closes the popup")
	_false(Review.popup_stale("approval-8f3e4476-aaaa", params), "active approval keeps the popup")
	_false(Review.popup_stale("", {}), "closed popup is not stale")


func _test_popup() -> void:
	var popup := ChatApprovalPopup.new()
	popup.decision_requested.connect(func(decision: String) -> void: _decisions.append(decision))
	popup.apply_style(DockStyle.resolve(null), {})
	popup.set_review("approval-1", Review.review(_base("command_execution", {"command": "git status", "cwd": "C:/Game"})))
	_eq(popup.approval_id, "approval-1", "popup tracks its approval")
	_eq(popup.title_label.text, "Run command?", "popup title")
	_true(popup.content_box.get_child_count() >= 3, "popup shows command, folder and headings")
	_eq(popup.size, Vector2i(620, 440), "default popup size")
	popup.apply_button_states({"approve": {"disabled": true, "tooltip": "blocked"}, "approve_session": {"visible": true, "disabled": false}})
	_true(popup.approve_button.disabled and popup.approve_session_button.visible, "popup mirrors approval button states")
	# Same enablement source as the old inline buttons: ChatControlStateModel.
	var approval := _base("command_execution", {"command": "ls"})
	var connected := ChatControlStateModel.controls_state({"chat_enabled": true, "connected": true, "approval": approval})
	popup.apply_button_states(connected)
	_true(not popup.approve_button.disabled and not popup.reject_button.disabled and not popup.revise_button.disabled and popup.approve_session_button.visible, "connected: popup decisions enabled exactly like the inline buttons")
	var offline := ChatControlStateModel.controls_state({"chat_enabled": true, "connected": false, "approval": approval})
	popup.apply_button_states(offline)
	_true(popup.approve_button.disabled and popup.reject_button.disabled and popup.revise_button.disabled, "disconnected: disabled, as before")
	popup.reject_button.disabled = false
	popup.reject_button.pressed.emit()
	_eq(_decisions, ["reject"], "decision emitted, routed by plugin")
	popup.close_requested.emit()
	_false(popup.visible, "closing hides without deciding")
	_eq(_decisions.size(), 1, "closing is not a decision")
	popup.close_review()
	_eq(popup.approval_id, "", "close_review forgets the approval")
	popup.free()


func _test_dock_style() -> void:
	var style := DockStyle.resolve(null)
	_false(bool(style.get("themed", true)), "headless fallback palette")
	_eq(DockStyle.icon(style, "ActionCopy"), null, "no icons without the editor theme")
	var button := Button.new()
	button.text = "Eye"
	DockStyle.apply_icon(button, style, "GuiVisibilityVisible", true)
	_eq(button.text, "Eye", "fallback keeps the label when no icon exists")
	var box := DockStyle.card_box(Color.BLACK, Color.WHITE, DockStyle.ACCENT_BAR)
	_true(box.border_width_left == 3 and box.corner_radius_top_left == DockStyle.RADIUS, "one radius and accent bar")
	_true(DockStyle.tone_color(style, "error") != DockStyle.tone_color(style, "ok"), "tones differ")
	var header := DockStyle.section_header(style, "Updates")
	_eq((header.get_child(0) as Label).text, "UPDATES", "section header label")
	var rule := (header.get_child(1) as HSeparator).get_theme_stylebox("separator") as StyleBoxLine
	_true(rule != null and rule.thickness == 1 and rule.color.a < 0.3, "section rule is a subtle 1px line")
	header.free()
	button.free()


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
