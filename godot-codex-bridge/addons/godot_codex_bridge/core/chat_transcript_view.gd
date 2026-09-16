@tool
extends RefCounted

const ChatTranscriptModel := preload("chat_transcript_model.gd")
const ChatTranscriptBatchModel := preload("chat_transcript_batch_model.gd")
const ChatDiffModel := preload("chat_diff_model.gd")
const ChatDiffView := preload("chat_diff_view.gd")
const ChatThemeModel := preload("chat_theme_model.gd")

const COPY_ICON_TEXT := "⧉"
const COPY_BUTTON_SIZE := Vector2(20, 20)

var _message_list: VBoxContainer
var _bottom_spacer: Control
var _scroll_callback: Callable
var _detail_callback: Callable
var _assistant_streaming := false
var _assistant_label: Label
var _assistant_text := ""
var _assistant_item_id := ""
var _assistant_phase := ""
var _assistant_dirty := false
var _last_assistant_flush_msec := 0
var _last_status_text := ""
var _last_status_label: Label
var _last_status_msec := 0
var _last_status_repeat_count := 0
var _work_panel: PanelContainer
var _work_controls := {}
var _work_state := {}
var _diff_panel: VBoxContainer
var _diff_controls := {}
var _diff_state := {}
var _palette := ChatThemeModel.default_palette()
var _limits := {
	"max_message_chars": 65536,
	"collapse_chars": 1200,
	"collapse_lines": 14,
	"preview_chars": 900,
	"preview_lines": 8,
	"assistant_section_chars": 2200,
	"assistant_flush_interval_msec": 50,
	"work_preview_chars": 220,
	"work_preview_lines": 2,
	"diff_max_files": 24,
	"diff_max_lines_per_file": 360,
	"status_coalesce_msec": 2500,
}


static func empty_control_counts() -> Dictionary:
	return {
		"copy_button_count": 0,
		"copy_icon_button_count": 0,
		"copy_icon_button_max_width": 0.0,
		"copy_icon_button_max_height": 0.0,
		"collapsible_message_count": 0,
		"collapsed_message_count": 0,
		"diff_preview_count": 0,
		"diff_file_section_count": 0,
		"diff_expanded_file_section_count": 0,
		"diff_files_box_visible_count": 0,
		"work_batch_count": 0,
		"work_details_visible_count": 0,
		"bridge_tools_enabled_status_count": 0,
		"refreshing_tools_status_count": 0,
	}


func setup(message_list: VBoxContainer, bottom_spacer: Control, scroll_callback: Callable, detail_callback: Callable, limits: Dictionary = {}) -> void:
	_message_list = message_list
	_bottom_spacer = bottom_spacer
	_scroll_callback = scroll_callback
	_detail_callback = detail_callback
	for key in limits.keys():
		if key == "palette" and limits.get(key) is Dictionary:
			_palette = ChatThemeModel.palette_values(limits.get(key) as Dictionary)
		else:
			_limits[key] = limits.get(key)


func create_copy_button(tooltip: String) -> Button:
	var copy_button := Button.new()
	copy_button.text = COPY_ICON_TEXT
	copy_button.tooltip_text = tooltip
	copy_button.set_meta("chat_copy_tooltip", tooltip)
	copy_button.set_meta("chat_copy_icon_button", true)
	copy_button.focus_mode = Control.FOCUS_ALL
	copy_button.flat = true
	copy_button.custom_minimum_size = COPY_BUTTON_SIZE
	copy_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	copy_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	copy_button.add_theme_font_size_override("font_size", 12)
	return copy_button


func append_user_message(text: String) -> Label:
	_reset_status_coalescing()
	var style := ChatThemeModel.bubble_style("user", _palette)
	return append_bubble(
		"You",
		text,
		style.get("background", Color(0.17, 0.27, 0.42)),
		style.get("accent", Color(0.37, 0.58, 0.92))
	)


func append_user_turn(text: String, now_msec := 0) -> Label:
	flush_assistant_text(now_msec)
	reset_assistant_stream(false, now_msec)
	return append_user_message(text)


func append_status_message(text: String, now_msec := 0) -> Label:
	var trimmed := text.strip_edges()
	if trimmed == "":
		return null
	if now_msec <= 0:
		now_msec = Time.get_ticks_msec()
	var coalesce_window := int(_limits.get("status_coalesce_msec", 2500))
	if (
		_last_status_label != null
		and is_instance_valid(_last_status_label)
		and _last_status_text == trimmed
		and coalesce_window >= 0
		and now_msec - _last_status_msec <= coalesce_window
	):
		_last_status_repeat_count += 1
		var repeated_text := trimmed
		if _last_status_repeat_count > 1:
			repeated_text += "\n(repeated " + str(_last_status_repeat_count) + " times)"
		set_bubble_text(_last_status_label, repeated_text)
		_last_status_msec = now_msec
		return _last_status_label
	var style := ChatThemeModel.bubble_style("status", _palette)
	var label := append_bubble(
		"Status",
		trimmed,
		style.get("background", Color(0.16, 0.16, 0.16)),
		style.get("accent", Color(0.28, 0.28, 0.28))
	)
	_last_status_text = trimmed
	_last_status_label = label
	_last_status_msec = now_msec
	_last_status_repeat_count = 1
	return label


func show_copy_feedback(copy_button: Button) -> void:
	if copy_button == null:
		return
	copy_button.text = COPY_ICON_TEXT
	copy_button.tooltip_text = "Copied to clipboard."
	copy_button.disabled = true
	copy_button.modulate = _palette.get("copy_feedback_modulate", Color(0.62, 0.92, 0.68))
	copy_button.get_tree().create_timer(0.8).timeout.connect(func() -> void:
		if is_instance_valid(copy_button):
			copy_button.text = COPY_ICON_TEXT
			copy_button.tooltip_text = str(copy_button.get_meta("chat_copy_tooltip", "Copy to clipboard."))
			copy_button.disabled = false
			copy_button.modulate = _palette.get("copy_default_modulate", Color(1, 1, 1))
	)


func append_bubble(author: String, text: String, background: Color, accent: Color, force_collapsed: bool = false) -> Label:
	if _message_list == null:
		return null

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = accent
	style.border_width_left = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 4)
	margin.add_child(content)

	var header_row := HBoxContainer.new()
	header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_theme_constant_override("separation", 6)
	content.add_child(header_row)

	var header := Label.new()
	header.text = author
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_color_override("font_color", accent)
	header.add_theme_font_size_override("font_size", 11)
	header_row.add_child(header)

	var collapse_button := Button.new()
	collapse_button.text = "More"
	collapse_button.tooltip_text = "Expand or collapse this message."
	collapse_button.focus_mode = Control.FOCUS_ALL
	collapse_button.visible = false
	collapse_button.custom_minimum_size = Vector2(54, 24)
	header_row.add_child(collapse_button)

	var copy_button := create_copy_button("Copy the full message text to clipboard.")
	header_row.add_child(copy_button)

	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_color_override("font_color", _palette.get("body_font", Color(0.86, 0.86, 0.86)))
	content.add_child(body)

	body.set_meta("chat_author", author)
	body.set_meta("chat_collapse_button", collapse_button)
	body.set_meta("chat_copy_button", copy_button)
	body.set_meta("chat_user_toggled", false)
	body.set_meta("chat_force_collapsed", force_collapsed)
	collapse_button.pressed.connect(func() -> void:
		toggle_message_collapse(body)
	)
	copy_button.pressed.connect(func() -> void:
		copy_message(body, copy_button)
	)
	set_bubble_text(body, text)

	append_panel(panel)
	return body


func append_assistant_delta(text: String, item_id: String = "", phase: String = "", now_msec := 0) -> Dictionary:
	if text == "":
		return assistant_stream_status()
	_reset_status_coalescing()
	var normalized_phase := ChatTranscriptModel.normalize_message_phase(phase)
	var normalized_item_id := item_id.strip_edges()
	if normalized_item_id == "":
		normalized_item_id = _assistant_item_id
	var item_changed := (
		normalized_item_id != ""
		and _assistant_item_id != ""
		and normalized_item_id != _assistant_item_id
	)
	var phase_changed := (
		normalized_phase != ""
		and _assistant_phase != ""
		and normalized_phase != _assistant_phase
	)
	if item_changed or phase_changed:
		flush_assistant_text(now_msec)
		reset_assistant_stream(false)
	if not _assistant_streaming or _assistant_label == null or not is_instance_valid(_assistant_label):
		_assistant_text = ""
		_assistant_item_id = normalized_item_id
		_assistant_phase = normalized_phase
		_assistant_label = _append_assistant_bubble(_assistant_phase)
		_assistant_streaming = _assistant_label != null
	else:
		if normalized_item_id != "":
			_assistant_item_id = normalized_item_id
		if normalized_phase != "":
			_assistant_phase = normalized_phase

	_assistant_text += text
	var section_limit := int(_limits.get("assistant_section_chars", 2200))
	while section_limit > 0 and _assistant_text.length() > section_limit:
		var split_at := ChatTranscriptModel.find_assistant_section_split(_assistant_text, section_limit)
		var chunk := _assistant_text.substr(0, split_at).strip_edges(false, true)
		if _assistant_label != null and is_instance_valid(_assistant_label):
			set_bubble_text(_assistant_label, chunk)
		_assistant_text = _assistant_text.substr(split_at).strip_edges(true, false)
		_assistant_label = _append_assistant_bubble(_assistant_phase)
	_assistant_dirty = true
	var flush_interval := int(_limits.get("assistant_flush_interval_msec", 50))
	if now_msec <= 0 or now_msec - _last_assistant_flush_msec >= flush_interval:
		flush_assistant_text(now_msec)
	return assistant_stream_status()


func append_assistant_routed_delta(text: String, item_id: String = "", phase: String = "", now_msec := 0) -> Dictionary:
	var route := ChatTranscriptBatchModel.assistant_delta_route(text, phase, assistant_current_phase())
	var route_name := str(route.get("route", "ignore"))
	match route_name:
		"ignore":
			return {
				"route": "ignore",
				"status": assistant_stream_status(),
			}
		"work":
			var work_state := record_work_update(text, item_id)
			return {
				"route": "work",
				"work_state": work_state,
				"status": assistant_stream_status(),
			}
	var normalized_phase := str(route.get("phase", ""))
	var status := append_assistant_delta(text, item_id, normalized_phase, now_msec)
	status["route"] = "assistant"
	return status


func flush_assistant_text(now_msec := 0) -> void:
	if not _assistant_dirty:
		return
	if _assistant_label != null and is_instance_valid(_assistant_label):
		set_bubble_text(_assistant_label, _assistant_text.strip_edges(false, true))
	if now_msec <= 0:
		now_msec = Time.get_ticks_msec()
	_last_assistant_flush_msec = now_msec
	_assistant_dirty = false
	_request_scroll()


func reset_assistant_stream(flush_first := true, now_msec := 0) -> void:
	if flush_first:
		flush_assistant_text(now_msec)
	_assistant_streaming = false
	_assistant_label = null
	_assistant_text = ""
	_assistant_item_id = ""
	_assistant_phase = ""
	_assistant_dirty = false


func assistant_current_phase() -> String:
	return _assistant_phase


func assistant_current_item_id() -> String:
	return _assistant_item_id


func assistant_stream_status() -> Dictionary:
	return {
		"streaming": _assistant_streaming,
		"dirty": _assistant_dirty,
		"text_length": _assistant_text.length(),
		"item_id": _assistant_item_id,
		"phase": _assistant_phase,
		"has_label": _assistant_label != null and is_instance_valid(_assistant_label),
	}


func work_state_payload() -> Dictionary:
	if _work_state.is_empty():
		return ChatTranscriptBatchModel.empty_work_state()
	return _work_state.duplicate(true)


func diff_state_payload() -> Dictionary:
	if _diff_state.is_empty():
		return ChatTranscriptBatchModel.empty_diff_state()
	return _diff_state.duplicate(true)


func reset_work_batch() -> void:
	_work_panel = null
	_work_controls = {}
	_work_state = ChatTranscriptBatchModel.empty_work_state()


func reset_diff_batch() -> void:
	_diff_panel = null
	_diff_controls = {}
	_diff_state = ChatTranscriptBatchModel.empty_diff_state()


func record_work_update(text: String, item_id: String = "") -> Dictionary:
	var work_plan := ChatTranscriptBatchModel.record_work_update_effect_plan(
		work_state_payload(),
		text,
		item_id,
		_work_panel != null and is_instance_valid(_work_panel)
	)
	_apply_work_update_effects(work_plan.get("effects", []) as Array)
	return work_state_payload()


func record_diff_update(diff_text: String) -> Dictionary:
	var diff_plan := ChatTranscriptBatchModel.record_diff_update_effect_plan(
		diff_state_payload(),
		diff_text,
		_diff_panel != null and is_instance_valid(_diff_panel)
	)
	_apply_diff_update_effects(diff_plan.get("effects", []) as Array)
	return diff_state_payload()


func set_work_visible(visible: bool) -> Dictionary:
	_apply_work_state(ChatTranscriptBatchModel.work_state_visible(work_state_payload(), visible))
	set_work_batch_visible(_work_controls, int(_work_state.get("updates", 0)), visible)
	return work_state_payload()


func set_diff_files_visible(visible: bool) -> Dictionary:
	_apply_diff_state(ChatTranscriptBatchModel.diff_state_visible(diff_state_payload(), visible))
	set_diff_batch_visible(_diff_controls, int(_diff_state.get("file_count", 0)), visible)
	return diff_state_payload()


func prepare_diff_visual_evidence(scroll_view: ScrollContainer) -> Dictionary:
	var target := _diff_visual_target()
	var scroll_before := scroll_view.scroll_vertical if scroll_view != null else 0
	var target_content_y := _control_content_y_in_scroll(target, scroll_view)
	if target != null and scroll_view != null and target_content_y >= 0.0:
		var scroll_bar := scroll_view.get_v_scroll_bar()
		var max_scroll := int(scroll_bar.max_value) if scroll_bar != null else 0
		scroll_view.scroll_vertical = clampi(int(floor(target_content_y)), 0, max_scroll)
		scroll_view.queue_redraw()
	var status := diff_visual_evidence_status(scroll_view)
	status["scroll_vertical_before"] = scroll_before
	status["scroll_vertical_after"] = scroll_view.scroll_vertical if scroll_view != null else 0
	status["scroll_vertical_max"] = (
		int(scroll_view.get_v_scroll_bar().max_value)
		if scroll_view != null and scroll_view.get_v_scroll_bar() != null
		else 0
	)
	status["target_content_y"] = target_content_y
	return status


func diff_visual_evidence_status(scroll_view: ScrollContainer, capture_root: Control = null) -> Dictionary:
	var files_box := _diff_controls.get("files_box", null) as Control
	var target := _diff_visual_target()
	var log_rect := scroll_view.get_global_rect() if scroll_view != null else Rect2()
	var root_rect := capture_root.get_global_rect() if capture_root != null else Rect2()
	var target_rect := target.get_global_rect() if target != null else Rect2()
	var log_intersection := log_rect.intersection(target_rect)
	var root_intersection := root_rect.intersection(target_rect)
	return {
		"target": "active_diff_first_file",
		"target_available": target != null,
		"target_visible_in_tree": target != null and target.is_visible_in_tree(),
		"files_box_visible_in_tree": files_box != null and files_box.is_visible_in_tree(),
		"target_intersects_log_view": (
			target != null
			and scroll_view != null
			and log_intersection.size.x > 0.0
			and log_intersection.size.y > 0.0
		),
		"target_intersects_capture_root": (
			target != null
			and capture_root != null
			and root_intersection.size.x > 0.0
			and root_intersection.size.y > 0.0
		),
		"target_rect": target_rect,
		"log_view_rect": log_rect,
		"capture_root_rect": root_rect,
		"log_intersection_rect": log_intersection,
		"capture_root_intersection_rect": root_intersection,
	}


func _diff_visual_target() -> Control:
	var files_box := _diff_controls.get("files_box", null) as VBoxContainer
	if files_box == null or not is_instance_valid(files_box):
		return null
	for child in files_box.get_children():
		if child is Control and (child as Control).visible:
			return child as Control
	return null


func _control_content_y_in_scroll(target: Control, scroll_view: ScrollContainer) -> float:
	if target == null or scroll_view == null:
		return -1.0
	var content_y := 0.0
	var current := target
	while current != null and current.get_parent() != scroll_view:
		content_y += current.position.y
		current = current.get_parent() as Control
	if current == null:
		return -1.0
	return content_y


func _apply_work_update_effects(effects: Array) -> void:
	for effect in effects:
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		var effect_dict := effect as Dictionary
		match str(effect_dict.get("action", "")):
			"flush_assistant_text":
				flush_assistant_text()
			"apply_work_state":
				_apply_work_state(effect_dict.get("state", {}) as Dictionary)
			"ensure_work_panel":
				_ensure_work_panel()
			"update_work_batch":
				_update_owned_work_batch()


func _apply_diff_update_effects(effects: Array) -> void:
	for effect in effects:
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		var effect_dict := effect as Dictionary
		match str(effect_dict.get("action", "")):
			"flush_assistant_text":
				flush_assistant_text()
			"apply_diff_state":
				_apply_diff_state(effect_dict.get("state", {}) as Dictionary)
			"ensure_diff_panel":
				_ensure_diff_panel()
			"update_diff_batch":
				_update_owned_diff_batch()


func _apply_work_state(state: Dictionary) -> void:
	_work_state = {
		"text": str(state.get("text", "")),
		"updates": int(state.get("updates", 0)),
		"item_id": str(state.get("item_id", "")),
		"visible": bool(state.get("visible", false)),
	}


func _apply_diff_state(state: Dictionary) -> void:
	_diff_state = {
		"text": str(state.get("text", "")),
		"updates": int(state.get("updates", 0)),
		"files": state.get("files", PackedStringArray()) as PackedStringArray,
		"file_count": int(state.get("file_count", 0)),
		"added_count": int(state.get("added_count", 0)),
		"removed_count": int(state.get("removed_count", 0)),
		"files_visible": bool(state.get("files_visible", false)),
	}


func _ensure_work_panel() -> PanelContainer:
	if _work_panel != null and is_instance_valid(_work_panel):
		return _work_panel
	_work_controls = append_work_batch(func() -> void:
		set_work_visible(not bool(_work_state.get("visible", false)))
	)
	_work_panel = _work_controls.get("panel", null) as PanelContainer
	return _work_panel


func _ensure_diff_panel() -> VBoxContainer:
	if _diff_panel != null and is_instance_valid(_diff_panel):
		return _diff_panel
	_diff_controls = append_diff_batch(func() -> void:
		set_diff_files_visible(not bool(_diff_state.get("files_visible", false)))
	)
	_diff_panel = _diff_controls.get("files_box", null) as VBoxContainer
	return _diff_panel


func _update_owned_work_batch() -> void:
	if _work_panel == null or not is_instance_valid(_work_panel):
		return
	update_work_batch(
		_work_controls,
		int(_work_state.get("updates", 0)),
		str(_work_state.get("text", "")),
		bool(_work_state.get("visible", false))
	)


func _update_owned_diff_batch() -> void:
	if _diff_panel == null or not is_instance_valid(_diff_panel):
		return
	var diff_result := update_diff_batch(
		_diff_controls,
		int(_diff_state.get("updates", 0)),
		str(_diff_state.get("text", "")),
		bool(_diff_state.get("files_visible", false))
	)
	_apply_diff_state(ChatTranscriptBatchModel.diff_state_with_counts(diff_state_payload(), diff_result))


func append_work_batch(toggle_callback: Callable = Callable()) -> Dictionary:
	if _message_list == null:
		return {}
	_reset_status_coalescing()

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.set_meta("chat_work_batch", true)

	var style := StyleBoxFlat.new()
	var work_style := ChatThemeModel.bubble_style("work", _palette)
	style.bg_color = work_style.get("background", Color(0.10, 0.10, 0.10))
	style.border_color = work_style.get("accent", Color(0.42, 0.42, 0.42))
	style.border_width_left = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	margin.add_child(content)

	var header_row := HBoxContainer.new()
	header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_theme_constant_override("separation", 6)
	content.add_child(header_row)

	var header := Label.new()
	header.text = "Work notes"
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_color_override("font_color", _palette.get("muted_font", Color(0.62, 0.62, 0.62)))
	header.add_theme_font_size_override("font_size", 11)
	header_row.add_child(header)

	var copy_button := create_copy_button("Copy all work notes to clipboard.")
	header_row.add_child(copy_button)

	var summary_label := Label.new()
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_label.add_theme_color_override("font_color", _palette.get("body_font", Color(0.78, 0.78, 0.78)))
	content.add_child(summary_label)

	var toggle_button := Button.new()
	toggle_button.text = "Show notes"
	toggle_button.tooltip_text = "Show or hide intermediate Codex work/progress notes."
	toggle_button.focus_mode = Control.FOCUS_ALL
	toggle_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(toggle_button)

	var body_label := Label.new()
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_label.visible = false
	body_label.set_meta("chat_work_details", true)
	body_label.add_theme_color_override("font_color", _palette.get("body_font", Color(0.80, 0.80, 0.80)))
	content.add_child(body_label)

	copy_button.pressed.connect(func() -> void:
		var full_text := str(body_label.get_meta("chat_full_text", body_label.text)) if body_label != null and is_instance_valid(body_label) else ""
		DisplayServer.clipboard_set(full_text)
		_log_detail("Copied work notes to clipboard (" + str(full_text.length()) + " chars).")
		show_copy_feedback(copy_button)
	)
	toggle_button.pressed.connect(func() -> void:
		if toggle_callback.is_valid():
			toggle_callback.call()
	)

	append_panel(panel)
	return {
		"panel": panel,
		"summary_label": summary_label,
		"toggle_button": toggle_button,
		"body_label": body_label,
	}


func append_diff_batch(toggle_callback: Callable = Callable()) -> Dictionary:
	if _message_list == null:
		return {}
	_reset_status_coalescing()

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.set_meta("chat_diff_preview", true)

	var style := StyleBoxFlat.new()
	var diff_style := ChatThemeModel.bubble_style("diff", _palette)
	style.bg_color = diff_style.get("background", Color(0.13, 0.13, 0.10))
	style.border_color = diff_style.get("accent", Color(0.70, 0.58, 0.26))
	style.border_width_left = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	panel.add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 6)
	margin.add_child(content)

	var header_row := HBoxContainer.new()
	header_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_theme_constant_override("separation", 6)
	content.add_child(header_row)

	var header := Label.new()
	header.text = "Diff preview"
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_color_override("font_color", _palette.get("diff_font", Color(0.92, 0.78, 0.38)))
	header.add_theme_font_size_override("font_size", 11)
	header_row.add_child(header)

	var copy_button := create_copy_button("Copy the full unified diff to clipboard.")
	header_row.add_child(copy_button)

	var summary_label := Label.new()
	summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_label.add_theme_color_override("font_color", _palette.get("body_font", Color(0.86, 0.82, 0.70)))
	content.add_child(summary_label)

	var toggle_button := Button.new()
	toggle_button.text = "Show files"
	toggle_button.tooltip_text = "Show or hide the changed file list. Each file row can be expanded to inspect the colored diff."
	toggle_button.focus_mode = Control.FOCUS_ALL
	toggle_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(toggle_button)

	var files_box := VBoxContainer.new()
	files_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	files_box.visible = false
	files_box.set_meta("chat_diff_files_box", true)
	files_box.add_theme_constant_override("separation", 4)
	content.add_child(files_box)

	copy_button.pressed.connect(func() -> void:
		var full_text := str(files_box.get_meta("chat_full_diff_text", ""))
		DisplayServer.clipboard_set(full_text)
		_log_detail("Copied diff preview to clipboard (" + str(full_text.length()) + " chars).")
		show_copy_feedback(copy_button)
	)
	toggle_button.pressed.connect(func() -> void:
		if toggle_callback.is_valid():
			toggle_callback.call()
	)

	append_panel(panel)
	return {
		"root_panel": panel,
		"files_box": files_box,
		"summary_label": summary_label,
		"toggle_button": toggle_button,
	}


func update_work_batch(controls: Dictionary, updates: int, text: String, visible: bool) -> String:
	var full_text := ChatTranscriptModel.truncate_text(text.strip_edges(false, true), int(_limits.get("max_message_chars", 65536)))
	var summary_label: Variant = controls.get("summary_label", null)
	if summary_label is Label and is_instance_valid(summary_label):
		(summary_label as Label).text = ChatTranscriptModel.work_batch_summary(
			updates,
			full_text,
			int(_limits.get("work_preview_chars", 220)),
			int(_limits.get("work_preview_lines", 2))
		)
	var toggle_button: Variant = controls.get("toggle_button", null)
	if toggle_button is Button and is_instance_valid(toggle_button):
		(toggle_button as Button).text = ChatTranscriptModel.work_batch_toggle_text(visible, updates)
	var body_label: Variant = controls.get("body_label", null)
	if body_label is Label and is_instance_valid(body_label):
		(body_label as Label).text = full_text
		(body_label as Label).set_meta("chat_full_text", full_text)
		(body_label as Label).visible = visible
	_request_scroll()
	return full_text


func update_diff_batch(controls: Dictionary, updates: int, diff_text: String, files_visible: bool) -> Dictionary:
	var files_box: Variant = controls.get("files_box", null)
	if not (files_box is VBoxContainer) or not is_instance_valid(files_box):
		return {
			"parsed_files": [],
			"file_count": 0,
			"added_count": 0,
			"removed_count": 0,
		}

	var parsed_files := ChatDiffModel.parse_diff_files(
		diff_text,
		int(_limits.get("diff_max_files", 24)),
		int(_limits.get("diff_max_lines_per_file", 360))
	)
	var file_count := parsed_files.size()
	var added_count := 0
	var removed_count := 0
	for file_data in parsed_files:
		added_count += int(file_data.get("added", 0))
		removed_count += int(file_data.get("removed", 0))

	var summary_label: Variant = controls.get("summary_label", null)
	if summary_label is Label and is_instance_valid(summary_label):
		(summary_label as Label).text = ChatDiffModel.batch_summary(updates, parsed_files)

	var toggle_button: Variant = controls.get("toggle_button", null)
	if toggle_button is Button and is_instance_valid(toggle_button):
		(toggle_button as Button).text = ChatDiffModel.batch_toggle_text(files_visible, file_count)
		(toggle_button as Button).disabled = parsed_files.is_empty()

	var files_box_node := files_box as VBoxContainer
	files_box_node.visible = files_visible and not parsed_files.is_empty()
	files_box_node.set_meta("chat_full_diff_text", diff_text)
	ChatDiffView.clear_children(files_box_node)
	if parsed_files.is_empty():
		var empty_label := Label.new()
		empty_label.text = "[diff text was empty]"
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_label.add_theme_color_override("font_color", _palette.get("muted_font", Color(0.74, 0.74, 0.74)))
		files_box_node.add_child(empty_label)
	else:
		for file_data in parsed_files:
			files_box_node.add_child(ChatDiffView.create_file_section(file_data, _scroll_callback, _palette))
	_request_scroll()
	return {
		"parsed_files": parsed_files,
		"file_count": file_count,
		"added_count": added_count,
		"removed_count": removed_count,
	}


func set_work_batch_visible(controls: Dictionary, updates: int, visible: bool) -> void:
	var body_label: Variant = controls.get("body_label", null)
	if body_label is Label and is_instance_valid(body_label):
		(body_label as Label).visible = visible
	var toggle_button: Variant = controls.get("toggle_button", null)
	if toggle_button is Button and is_instance_valid(toggle_button):
		(toggle_button as Button).text = ChatTranscriptModel.work_batch_toggle_text(visible, updates)
	_request_scroll()


func set_diff_batch_visible(controls: Dictionary, file_count: int, visible: bool) -> void:
	var files_box: Variant = controls.get("files_box", null)
	if files_box is Control and is_instance_valid(files_box):
		(files_box as Control).visible = visible and file_count > 0
	var toggle_button: Variant = controls.get("toggle_button", null)
	if toggle_button is Button and is_instance_valid(toggle_button):
		(toggle_button as Button).text = ChatDiffModel.batch_toggle_text(visible, file_count)
	_request_scroll()


func append_panel(panel: Control) -> void:
	if _message_list == null or panel == null:
		return
	_message_list.add_child(panel)
	if _bottom_spacer != null and _bottom_spacer.get_parent() == _message_list:
		_message_list.move_child(_bottom_spacer, _message_list.get_child_count() - 1)
	_reset_status_coalescing()
	_request_scroll()


func _reset_status_coalescing() -> void:
	_last_status_text = ""
	_last_status_label = null
	_last_status_msec = 0
	_last_status_repeat_count = 0


func set_bubble_text(body: Label, text: String) -> void:
	if body == null:
		return
	var full_text := ChatTranscriptModel.truncate_text(text, int(_limits.get("max_message_chars", 65536)))
	body.set_meta("chat_full_text", full_text)
	var force_collapsed := bool(body.get_meta("chat_force_collapsed", false))
	var can_collapse := force_collapsed or ChatTranscriptModel.should_collapse_text(
		full_text,
		int(_limits.get("collapse_chars", 1200)),
		int(_limits.get("collapse_lines", 14))
	)
	var user_toggled := bool(body.get_meta("chat_user_toggled", false))
	var collapsed := bool(body.get_meta("chat_collapsed", false))
	if not can_collapse:
		collapsed = false
	elif not user_toggled:
		collapsed = true
	body.set_meta("chat_collapsed", collapsed)
	var collapse_button: Variant = body.get_meta("chat_collapse_button", null)
	if collapse_button is Button:
		(collapse_button as Button).visible = can_collapse
		(collapse_button as Button).text = "More" if collapsed else "Less"
	body.text = _body_display_text(full_text, collapsed, force_collapsed)


func toggle_message_collapse(body: Label) -> void:
	if body == null:
		return
	var full_text := str(body.get_meta("chat_full_text", body.text))
	var force_collapsed := bool(body.get_meta("chat_force_collapsed", false))
	if not force_collapsed and not ChatTranscriptModel.should_collapse_text(
		full_text,
		int(_limits.get("collapse_chars", 1200)),
		int(_limits.get("collapse_lines", 14))
	):
		return
	var collapsed := not bool(body.get_meta("chat_collapsed", true))
	body.set_meta("chat_user_toggled", true)
	body.set_meta("chat_collapsed", collapsed)
	var collapse_button: Variant = body.get_meta("chat_collapse_button", null)
	if collapse_button is Button:
		(collapse_button as Button).text = "More" if collapsed else "Less"
	body.text = _body_display_text(full_text, collapsed, force_collapsed)
	_request_scroll()


func copy_message(body: Label, copy_button: Button) -> void:
	if body == null:
		return
	var full_text := str(body.get_meta("chat_full_text", body.text))
	DisplayServer.clipboard_set(full_text)
	_log_detail("Copied chat message to clipboard (" + str(full_text.length()) + " chars).")
	show_copy_feedback(copy_button)


func _append_assistant_bubble(phase: String) -> Label:
	var style := ChatTranscriptModel.assistant_style(phase)
	var bubble_kind := "work" if str(style.get("author", "Codex")) == "Work" else "assistant"
	var bubble_style := ChatThemeModel.bubble_style(bubble_kind, _palette)
	return append_bubble(
		str(style.get("author", "Codex")),
		"",
		bubble_style.get("background", style.get("background", Color(0.12, 0.12, 0.12))),
		bubble_style.get("accent", style.get("accent", Color(0.25, 0.25, 0.25))),
		bool(style.get("force_collapsed", false))
	)


func message_count() -> int:
	if _message_list == null:
		return 0
	var count := _message_list.get_child_count()
	if _bottom_spacer != null and _bottom_spacer.get_parent() == _message_list:
		count -= 1
	return max(count, 0)


func clear_messages() -> void:
	if _message_list == null:
		return
	for child in _message_list.get_children():
		if child == _bottom_spacer:
			continue
		_message_list.remove_child(child)
		child.queue_free()
	if _bottom_spacer != null and _bottom_spacer.get_parent() == null:
		_message_list.add_child(_bottom_spacer)
	if _bottom_spacer != null and _bottom_spacer.get_parent() == _message_list:
		_message_list.move_child(_bottom_spacer, _message_list.get_child_count() - 1)
	_request_scroll()


func control_counts() -> Dictionary:
	var counts := empty_control_counts()
	if _message_list == null:
		return counts
	_collect_control_counts(_message_list, counts)
	return counts


func _body_display_text(full_text: String, collapsed: bool, force_collapsed: bool) -> String:
	if collapsed and force_collapsed:
		return ChatTranscriptModel.compact_collapsed_preview(
			full_text,
			int(_limits.get("work_preview_chars", 220)),
			int(_limits.get("work_preview_lines", 2))
		)
	if collapsed:
		return ChatTranscriptModel.collapsed_preview(
			full_text,
			int(_limits.get("preview_chars", 900)),
			int(_limits.get("preview_lines", 8))
		)
	return full_text


func _collect_control_counts(node: Node, counts: Dictionary) -> void:
	if node.has_meta("chat_diff_preview"):
		counts["diff_preview_count"] = int(counts.get("diff_preview_count", 0)) + 1
	if node.has_meta("chat_diff_file_section"):
		counts["diff_file_section_count"] = int(counts.get("diff_file_section_count", 0)) + 1
	if node.has_meta("chat_diff_files_box") and node is Control and (node as Control).visible:
		counts["diff_files_box_visible_count"] = int(counts.get("diff_files_box_visible_count", 0)) + 1
	if node.has_meta("chat_diff_file_details") and node is Control and (node as Control).visible:
		counts["diff_expanded_file_section_count"] = int(counts.get("diff_expanded_file_section_count", 0)) + 1
	if node.has_meta("chat_work_batch"):
		counts["work_batch_count"] = int(counts.get("work_batch_count", 0)) + 1
	if node.has_meta("chat_work_details") and node is Control and (node as Control).visible:
		counts["work_details_visible_count"] = int(counts.get("work_details_visible_count", 0)) + 1
	if node.has_meta("chat_copy_icon_button") and node is Button:
		var copy_button := node as Button
		counts["copy_icon_button_count"] = int(counts.get("copy_icon_button_count", 0)) + 1
		counts["copy_button_count"] = int(counts.get("copy_button_count", 0)) + 1
		counts["copy_icon_button_max_width"] = max(float(counts.get("copy_icon_button_max_width", 0.0)), copy_button.custom_minimum_size.x)
		counts["copy_icon_button_max_height"] = max(float(counts.get("copy_icon_button_max_height", 0.0)), copy_button.custom_minimum_size.y)
	if node is Label:
		var label := node as Label
		var author := str(label.get_meta("chat_author", ""))
		var full_text := str(label.get_meta("chat_full_text", label.text))
		if author == "Status":
			if full_text.begins_with("Bridge tools enabled."):
				counts["bridge_tools_enabled_status_count"] = int(counts.get("bridge_tools_enabled_status_count", 0)) + 1
			if full_text == "Refreshing Godot Bridge tools for this project...":
				counts["refreshing_tools_status_count"] = int(counts.get("refreshing_tools_status_count", 0)) + 1
		if label.has_meta("chat_copy_button"):
			var label_copy_button: Variant = label.get_meta("chat_copy_button", null)
			if not (label_copy_button is Button) or not (label_copy_button as Button).has_meta("chat_copy_icon_button"):
				counts["copy_button_count"] = int(counts.get("copy_button_count", 0)) + 1
		if label.has_meta("chat_collapse_button"):
			var collapse_full_text := str(label.get_meta("chat_full_text", label.text))
			if ChatTranscriptModel.should_collapse_text(
				collapse_full_text,
				int(_limits.get("collapse_chars", 1200)),
				int(_limits.get("collapse_lines", 14))
			):
				counts["collapsible_message_count"] = int(counts.get("collapsible_message_count", 0)) + 1
				if bool(label.get_meta("chat_collapsed", false)):
					counts["collapsed_message_count"] = int(counts.get("collapsed_message_count", 0)) + 1
	for child in node.get_children():
		_collect_control_counts(child, counts)


func _request_scroll() -> void:
	if _scroll_callback.is_valid():
		_scroll_callback.call_deferred()


func _log_detail(message: String) -> void:
	if _detail_callback.is_valid():
		_detail_callback.call(message)
