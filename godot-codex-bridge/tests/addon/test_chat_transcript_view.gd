extends SceneTree

const ChatTranscriptView := preload("res://addons/godot_codex_bridge/core/chat_transcript_view.gd")

var _failures := 0
var _detail_messages: Array[String] = []
var _scroll_requests := 0
var _work_toggle_requests := 0
var _diff_toggle_requests := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge chat transcript view tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge chat transcript view tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var message_list := VBoxContainer.new()
	var bottom_spacer := Control.new()
	message_list.add_child(bottom_spacer)

	var view := ChatTranscriptView.new()
	view.setup(
		message_list,
		bottom_spacer,
		Callable(self, "_on_scroll_requested"),
		Callable(self, "_on_detail_message"),
		{
			"max_message_chars": 2000,
			"collapse_chars": 80,
			"collapse_lines": 3,
			"preview_chars": 64,
			"preview_lines": 2,
			"assistant_section_chars": 24,
			"assistant_flush_interval_msec": 50,
			"work_preview_chars": 42,
			"work_preview_lines": 1,
			"palette": {
				"body_font": Color(0.91, 0.88, 0.82),
				"muted_font": Color(0.62, 0.60, 0.56),
				"assistant_background": Color(0.14, 0.15, 0.16),
				"assistant_accent": Color(0.28, 0.30, 0.33),
				"work_background": Color(0.15, 0.15, 0.14),
				"work_accent": Color(0.30, 0.30, 0.28),
				"diff_background": Color(0.17, 0.15, 0.10),
				"diff_accent": Color(0.70, 0.58, 0.26),
				"diff_font": Color(0.94, 0.78, 0.32),
			},
		}
	)

	_assert_eq(view.message_count(), 0, "bottom spacer is not counted as a message")

	var long_text := "First line.\nSecond line.\nThird line.\nFourth line with enough text to collapse."
	var body := view.append_bubble("Codex", long_text, Color(0.12, 0.12, 0.12), Color(0.5, 0.7, 1.0))
	_assert_true(body != null, "append_bubble returns body label")
	_assert_eq(body.get_theme_color("font_color"), Color(0.91, 0.88, 0.82), "bubble body uses palette font")
	var detached_copy_button := view.create_copy_button("Copy")
	_assert_true(detached_copy_button.modulate == Color(1, 1, 1), "partial palette keeps copy defaults")
	_assert_eq(detached_copy_button.focus_mode, Control.FOCUS_ALL, "copy button supports keyboard focus")
	detached_copy_button.free()
	_assert_eq(view.message_count(), 1, "message count increments after append")
	_assert_true(bool(body.get_meta("chat_collapsed", false)), "long text starts collapsed")
	_assert_true(body.text.find("[collapsed") >= 0, "collapsed body includes hint")

	var counts := view.control_counts()
	_assert_eq(int(counts.get("copy_button_count", -1)), 1, "copy button counted")
	_assert_eq(int(counts.get("copy_icon_button_count", -1)), 1, "icon copy button counted")
	_assert_eq(float(counts.get("copy_icon_button_max_width", 0.0)), 20.0, "copy icon width stays compact")
	_assert_eq(float(counts.get("copy_icon_button_max_height", 0.0)), 20.0, "copy icon height stays compact")
	_assert_eq(int(counts.get("collapsible_message_count", -1)), 1, "collapsible message counted")
	_assert_eq(int(counts.get("collapsed_message_count", -1)), 1, "collapsed message counted")

	view.toggle_message_collapse(body)
	_assert_true(not bool(body.get_meta("chat_collapsed", true)), "toggle expands message")
	_assert_eq(body.text, str(body.get_meta("chat_full_text", "")), "expanded body shows full text")
	counts = view.control_counts()
	_assert_eq(int(counts.get("collapsed_message_count", -1)), 0, "expanded message is not counted as collapsed")

	view.set_bubble_text(body, "short")
	_assert_true(not bool(body.get_meta("chat_collapsed", true)), "short text is not collapsed")
	_assert_eq(body.text, "short", "short text displays directly")

	var empty_counts := ChatTranscriptView.empty_control_counts()
	_assert_eq(int(empty_counts.get("work_batch_count", -1)), 0, "empty counts include work batch key")
	_assert_eq(int(empty_counts.get("diff_preview_count", -1)), 0, "empty counts include diff key")

	var user_start_count := view.message_count()
	var user_body := view.append_user_message("hello from user")
	_assert_true(user_body != null, "append_user_message returns body label")
	_assert_eq(str(user_body.get_meta("chat_author", "")), "You", "user message author is stored")
	_assert_eq(str(user_body.get_meta("chat_full_text", "")), "hello from user", "user message full text stored")
	_assert_eq(view.message_count(), user_start_count + 1, "user message count increments")

	var status_start_count := view.message_count()
	var status_body := view.append_status_message("  bridge ready  ", 500)
	_assert_true(status_body != null, "append_status_message returns body label")
	_assert_eq(str(status_body.get_meta("chat_author", "")), "Status", "status message author is stored")
	_assert_eq(str(status_body.get_meta("chat_full_text", "")), "bridge ready", "status message is trimmed")
	_assert_eq(view.message_count(), status_start_count + 1, "status message count increments")
	var repeated_status := view.append_status_message("bridge ready", 1000)
	_assert_true(repeated_status == status_body, "repeated status reuses last status label")
	_assert_eq(view.message_count(), status_start_count + 1, "repeated status does not append")
	_assert_true(str(status_body.get_meta("chat_full_text", "")).contains("repeated 2 times"), "repeated status count shown")
	var late_status := view.append_status_message("bridge ready", 5000)
	_assert_true(late_status != status_body, "late repeated status starts a new bubble")
	_assert_eq(view.message_count(), status_start_count + 2, "late repeated status appends")
	view.append_status_message("Refreshing Godot Bridge tools for this project...", 7000)
	view.append_status_message("Bridge tools enabled. Evidence: C:/bridge-tools/evidence.json", 9000)
	counts = view.control_counts()
	_assert_eq(int(counts.get("refreshing_tools_status_count", -1)), 1, "refreshing tools status counted")
	_assert_eq(int(counts.get("bridge_tools_enabled_status_count", -1)), 1, "bridge tools enabled status counted")
	var blank_status := view.append_status_message("   ")
	_assert_true(blank_status == null, "blank status message is ignored")
	_assert_eq(view.message_count(), status_start_count + 4, "blank status does not append")

	var work_controls := view.append_work_batch(Callable(self, "_on_work_toggle_requested"))
	var work_panel := work_controls.get("panel", null) as PanelContainer
	var work_summary := work_controls.get("summary_label", null) as Label
	var work_toggle := work_controls.get("toggle_button", null) as Button
	var work_body := work_controls.get("body_label", null) as Label
	_assert_true(work_panel != null and work_panel.has_meta("chat_work_batch"), "work batch panel marked")
	_assert_true(work_body != null and work_body.has_meta("chat_work_details"), "work details marked")
	_assert_eq(work_toggle.focus_mode, Control.FOCUS_ALL, "work toggle supports keyboard focus")
	view.update_work_batch(work_controls, 2, "Checking files.\nRunning validation.", false)
	_assert_true(work_summary.text.begins_with("Work notes: 2 updates."), "work summary updated")
	_assert_eq(work_toggle.text, "Show 2 notes", "work toggle collapsed text")
	_assert_false(work_body.visible, "work body hidden while collapsed")
	counts = view.control_counts()
	_assert_eq(int(counts.get("work_batch_count", -1)), 1, "work batch counted")
	_assert_eq(int(counts.get("work_details_visible_count", -1)), 0, "hidden work details not counted")
	view.set_work_batch_visible(work_controls, 2, true)
	_assert_true(work_body.visible, "work body visible after expand")
	_assert_eq(work_toggle.text, "Hide notes", "work toggle expanded text")
	counts = view.control_counts()
	_assert_eq(int(counts.get("work_details_visible_count", -1)), 1, "visible work details counted")
	work_toggle.pressed.emit()
	_assert_eq(_work_toggle_requests, 1, "work toggle callback emitted")

	var diff_text := "\n".join([
		"diff --git a/scripts/player.gd b/scripts/player.gd",
		"--- a/scripts/player.gd",
		"+++ b/scripts/player.gd",
		"@@",
		"-old",
		"+new",
	])
	var diff_controls := view.append_diff_batch(Callable(self, "_on_diff_toggle_requested"))
	var diff_root := diff_controls.get("root_panel", null) as PanelContainer
	var diff_files := diff_controls.get("files_box", null) as VBoxContainer
	var diff_summary := diff_controls.get("summary_label", null) as Label
	var diff_toggle := diff_controls.get("toggle_button", null) as Button
	_assert_true(diff_root != null and diff_root.has_meta("chat_diff_preview"), "diff batch panel marked")
	_assert_true(diff_files != null and diff_files.has_meta("chat_diff_files_box"), "diff files box marked")
	_assert_eq(diff_toggle.focus_mode, Control.FOCUS_ALL, "diff toggle supports keyboard focus")
	var diff_result := view.update_diff_batch(diff_controls, 2, diff_text, false)
	_assert_eq(int(diff_result.get("file_count", -1)), 1, "diff file count")
	_assert_eq(int(diff_result.get("added_count", -1)), 1, "diff added count")
	_assert_eq(int(diff_result.get("removed_count", -1)), 1, "diff removed count")
	_assert_true(diff_summary.text.find("2 update(s), 1 file(s), +1 -1") >= 0, "diff summary updated")
	_assert_eq(diff_toggle.text, "Show 1 file", "diff toggle collapsed text")
	_assert_false(diff_files.visible, "diff files hidden while collapsed")
	view.set_diff_batch_visible(diff_controls, 1, true)
	_assert_true(diff_files.visible, "diff files visible after expand")
	_assert_eq(diff_toggle.text, "Hide files", "diff toggle expanded text")
	counts = view.control_counts()
	_assert_eq(int(counts.get("diff_preview_count", -1)), 1, "diff preview counted")
	_assert_eq(int(counts.get("diff_file_section_count", -1)), 1, "diff file section counted")
	_assert_eq(int(counts.get("diff_files_box_visible_count", -1)), 1, "diff files box visible counted")
	diff_toggle.pressed.emit()
	_assert_eq(_diff_toggle_requests, 1, "diff toggle callback emitted")

	var owned_work_start := view.message_count()
	var owned_work_state := view.record_work_update("Owned work update.", "owned-work-1")
	_assert_eq(int(owned_work_state.get("updates", -1)), 1, "owned work update count")
	_assert_eq(view.message_count(), owned_work_start + 1, "owned work update creates panel")
	owned_work_state = view.set_work_visible(true)
	_assert_true(bool(owned_work_state.get("visible", false)), "owned work visibility state")
	view.reset_work_batch()
	_assert_eq(int(view.work_state_payload().get("updates", -1)), 0, "owned work reset clears state")

	var owned_diff_start := view.message_count()
	var owned_diff_state := view.record_diff_update(diff_text)
	_assert_eq(int(owned_diff_state.get("updates", -1)), 1, "owned diff update count")
	_assert_eq(int(owned_diff_state.get("file_count", -1)), 1, "owned diff file count")
	_assert_eq(view.message_count(), owned_diff_start + 1, "owned diff update creates panel")
	owned_diff_state = view.set_diff_files_visible(true)
	_assert_true(bool(owned_diff_state.get("files_visible", false)), "owned diff visibility state")
	view.reset_diff_batch()
	_assert_eq(int(view.diff_state_payload().get("updates", -1)), 0, "owned diff reset clears state")

	var assistant_start_count := view.message_count()
	var assistant_status := view.append_assistant_delta("Labas, ", "response-1", "final_answer", 1000)
	_assert_true(bool(assistant_status.get("streaming", false)), "assistant stream starts")
	_assert_eq(str(assistant_status.get("phase", "")), "final_answer", "assistant phase stored")
	_assert_eq(view.message_count(), assistant_start_count + 1, "assistant stream creates one bubble")
	assistant_status = view.append_assistant_delta("pasauli", "response-1", "final_answer", 1010)
	_assert_true(bool(assistant_status.get("dirty", false)), "assistant stream stays dirty before flush interval")
	_assert_eq(view.message_count(), assistant_start_count + 1, "same assistant item reuses bubble before split")
	view.flush_assistant_text(1100)
	assistant_status = view.assistant_stream_status()
	_assert_false(bool(assistant_status.get("dirty", true)), "assistant flush clears dirty flag")
	_assert_eq(int(assistant_status.get("text_length", -1)), 14, "assistant text length tracked")

	view.reset_assistant_stream(false)
	var split_start_count := view.message_count()
	view.append_assistant_delta("0123456789 0123456789 0123456789", "response-2", "final_answer", 2000)
	_assert_true(view.message_count() >= split_start_count + 2, "long assistant stream splits into multiple bubbles")
	view.reset_assistant_stream(true, 2100)
	assistant_status = view.assistant_stream_status()
	_assert_false(bool(assistant_status.get("streaming", true)), "assistant reset clears streaming state")
	_assert_eq(str(assistant_status.get("phase", "x")), "", "assistant reset clears phase")

	var routed_start_count := view.message_count()
	var routed_status := view.append_assistant_routed_delta("Patikrinsiu failus.", "work-1", "", 2200)
	_assert_eq(str(routed_status.get("route", "")), "work", "routed thinking delta becomes work route")
	_assert_eq(view.message_count(), routed_start_count + 1, "work route creates work notes panel")
	_assert_eq(int((routed_status.get("work_state", {}) as Dictionary).get("updates", -1)), 1, "work route records work update")
	routed_status = view.append_assistant_routed_delta("Galutinis atsakymas.", "answer-1", "final_answer", 2300)
	_assert_eq(str(routed_status.get("route", "")), "assistant", "routed final delta appends assistant")
	_assert_eq(view.message_count(), routed_start_count + 2, "routed final delta creates assistant bubble")
	view.append_user_turn("next user message", 2400)
	assistant_status = view.assistant_stream_status()
	_assert_false(bool(assistant_status.get("streaming", true)), "user turn resets active assistant stream")
	_assert_eq(str(assistant_status.get("phase", "x")), "", "user turn clears assistant phase")

	message_list.free()


func _on_scroll_requested() -> void:
	_scroll_requests += 1


func _on_detail_message(message: String) -> void:
	_detail_messages.append(message)


func _on_work_toggle_requested() -> void:
	_work_toggle_requests += 1


func _on_diff_toggle_requested() -> void:
	_diff_toggle_requests += 1


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
