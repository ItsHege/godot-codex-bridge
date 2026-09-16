@tool
extends RefCounted


static func rect_contains(container_rect: Rect2, child_rect: Rect2) -> bool:
	return (
		child_rect.position.x >= container_rect.position.x
		and child_rect.position.y >= container_rect.position.y
		and child_rect.position.x + child_rect.size.x <= container_rect.position.x + container_rect.size.x
		and child_rect.position.y + child_rect.size.y <= container_rect.position.y + container_rect.size.y
	)


static func rect_payload(rect: Rect2) -> Dictionary:
	return {
		"x": rect.position.x,
		"y": rect.position.y,
		"width": rect.size.x,
		"height": rect.size.y,
	}


static func variant_payload(value: Variant) -> Variant:
	match typeof(value):
		TYPE_VECTOR2, TYPE_VECTOR2I:
			return {
				"x": value.x,
				"y": value.y,
			}
		TYPE_RECT2, TYPE_RECT2I:
			return {
				"position": variant_payload(value.position),
				"size": variant_payload(value.size),
			}
		_:
			return value


static func window_inside_usable(window_position: Vector2i, window_size: Vector2i, usable_rect: Rect2i) -> bool:
	return (
		window_position.x >= usable_rect.position.x
		and window_position.y >= usable_rect.position.y
		and window_position.x + window_size.x <= usable_rect.position.x + usable_rect.size.x
		and window_position.y + window_size.y <= usable_rect.position.y + usable_rect.size.y
	)


static func build_status(geometry: Dictionary, ui: Dictionary, runtime: Dictionary, counts: Dictionary, annotation: Dictionary, window: Dictionary) -> Dictionary:
	var panel_rect := geometry.get("panel_rect", Rect2()) as Rect2
	var input_rect := geometry.get("input_rect", Rect2()) as Rect2
	var input_row_rect := geometry.get("input_row_rect", Rect2()) as Rect2
	var eye_rect := geometry.get("eye_rect", Rect2()) as Rect2
	var composer_toggle_rect := geometry.get("composer_toggle_rect", Rect2()) as Rect2
	var connect_button_rect := geometry.get("connect_button_rect", Rect2()) as Rect2
	var frame_rect := geometry.get("frame_rect", Rect2()) as Rect2
	var log_rect := geometry.get("log_rect", Rect2()) as Rect2
	var approval_rect := geometry.get("approval_rect", Rect2()) as Rect2
	var advanced_toggle_rect := geometry.get("advanced_toggle_rect", Rect2()) as Rect2
	var approval_visible := bool(ui.get("approval_visible", false))
	var window_position := window.get("window_position", Vector2i()) as Vector2i
	var window_size := window.get("window_size", Vector2i()) as Vector2i
	var usable_rect := window.get("usable_rect", Rect2i()) as Rect2i

	var data := {
		"input_visible_in_tree": bool(ui.get("input_visible", false)),
		"input_inside_chat_panel": rect_contains(panel_rect, input_rect),
		"log_inside_chat_panel": rect_contains(panel_rect, frame_rect),
		"composer_below_log": input_rect.position.y >= frame_rect.position.y + frame_rect.size.y,
		"approval_above_input": true,
		"panel_rect": rect_payload(panel_rect),
		"input_rect": rect_payload(input_rect),
		"input_row_rect": rect_payload(input_row_rect),
		"input_minimum_size": variant_payload(ui.get("input_minimum_size", Vector2())),
		"input_row_minimum_size": variant_payload(ui.get("input_row_minimum_size", Vector2())),
		"input_scroll_fit_content_height": bool(ui.get("input_scroll_fit_content_height", false)),
		"composer_expanded": bool(ui.get("composer_expanded", false)),
		"composer_toggle_visible_in_tree": bool(ui.get("composer_toggle_visible", false)),
		"composer_toggle_inside_chat_panel": rect_contains(panel_rect, composer_toggle_rect),
		"composer_toggle_text": str(ui.get("composer_toggle_text", "")),
		"composer_toggle_rect": rect_payload(composer_toggle_rect),
		"eye_button_visible_in_tree": bool(ui.get("eye_button_visible", false)),
		"eye_button_inside_chat_panel": rect_contains(panel_rect, eye_rect),
		"eye_button_rect": rect_payload(eye_rect),
		"pending_annotation": bool(annotation.get("pending_annotation", false)),
		"pending_annotation_id": str(annotation.get("pending_annotation_id", "")),
		"annotation_dialog_visible": bool(annotation.get("annotation_dialog_visible", false)),
		"annotation_dialog_rect": annotation.get("annotation_dialog_rect", rect_payload(Rect2())),
		"annotation_canvas_has_image": bool(annotation.get("annotation_canvas_has_image", false)),
		"annotation_marker_count": int(annotation.get("annotation_marker_count", 0)),
		"approval_rect": rect_payload(approval_rect),
		"log_frame_rect": rect_payload(frame_rect),
		"log_rect": rect_payload(log_rect),
		"panel_minimum_size": variant_payload(ui.get("panel_minimum_size", Vector2())),
		"log_frame_minimum_size": variant_payload(ui.get("log_frame_minimum_size", Vector2())),
		"log_minimum_size": variant_payload(ui.get("log_minimum_size", Vector2())),
		"visibility_chain": ui.get("visibility_chain", []),
		"connection_state": str(runtime.get("connection_state", "")),
		"runtime_state": str(runtime.get("runtime_state", "")),
		"readiness_label_text": str(ui.get("readiness_label_text", "")),
		"readiness_label_tooltip": str(ui.get("readiness_label_tooltip", "")),
		"advanced_visible": bool(ui.get("advanced_visible", false)),
		"advanced_toggle_visible": bool(ui.get("advanced_toggle_visible", false)),
		"advanced_toggle_inside_chat_panel": rect_contains(panel_rect, advanced_toggle_rect),
		"advanced_toggle_focus_mode": int(ui.get("advanced_toggle_focus_mode", -1)),
		"connect_button_visible": bool(ui.get("connect_button_visible", false)),
		"connect_button_inside_chat_panel": rect_contains(panel_rect, connect_button_rect),
		"connect_button_rect": rect_payload(connect_button_rect),
		"connect_button_in_status_header": bool(ui.get("connect_button_in_status_header", false)),
		"connect_button_focus_mode": int(ui.get("connect_button_focus_mode", -1)),
		"enable_tools_button_visible": bool(ui.get("enable_tools_button_visible", false)),
		"model_option_visible": bool(ui.get("model_option_visible", false)),
		"reasoning_option_visible": bool(ui.get("reasoning_option_visible", false)),
		"trust_button_visible": bool(ui.get("trust_button_visible", false)),
		"attach_context_visible": bool(ui.get("attach_context_visible", false)),
		"attach_selected_visible": bool(ui.get("attach_selected_visible", false)),
		"attach_screenshot_visible": bool(ui.get("attach_screenshot_visible", false)),
		"team_review_button_visible": bool(ui.get("team_review_button_visible", false)),
		"team_status_visible": bool(ui.get("team_status_visible", false)),
		"main_screen_registered": bool(ui.get("main_screen_registered", false)),
		"dock_registered": bool(ui.get("dock_registered", false)),
		"bottom_panel_registered": bool(ui.get("bottom_panel_registered", false)),
	}
	if approval_visible:
		data["approval_above_input"] = approval_rect.position.y + approval_rect.size.y <= input_rect.position.y

	for key in runtime.keys():
		if not data.has(key):
			data[key] = runtime[key]
	for key in counts.keys():
		data[key] = counts[key]

	data["window_mode"] = int(window.get("window_mode", 0))
	data["window_position"] = variant_payload(window_position)
	data["window_size"] = variant_payload(window_size)
	data["window_screen"] = int(window.get("window_screen", 0))
	data["usable_screen_rect"] = variant_payload(usable_rect)
	data["window_inside_usable_screen"] = window_inside_usable(window_position, window_size, usable_rect)
	return data
