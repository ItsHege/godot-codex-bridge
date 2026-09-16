extends SceneTree

const ChatLayoutStatusModel := preload("res://addons/godot_codex_bridge/core/chat_layout_status_model.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge chat layout status model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge chat layout status model tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var panel := Rect2(10, 20, 300, 400)
	var input := Rect2(20, 300, 160, 96)
	var frame := Rect2(20, 80, 260, 180)
	var approval := Rect2(20, 270, 220, 24)
	_assert_true(ChatLayoutStatusModel.rect_contains(panel, input), "panel contains input")
	_assert_false(ChatLayoutStatusModel.rect_contains(panel, Rect2(0, 0, 20, 20)), "panel rejects outside rect")
	_assert_eq(ChatLayoutStatusModel.rect_payload(input).get("height"), 96.0, "rect payload height")
	_assert_true(ChatLayoutStatusModel.window_inside_usable(Vector2i(0, 0), Vector2i(100, 100), Rect2i(0, 0, 200, 200)), "window inside usable")
	_assert_false(ChatLayoutStatusModel.window_inside_usable(Vector2i(150, 150), Vector2i(100, 100), Rect2i(0, 0, 200, 200)), "window outside usable")

	var status := ChatLayoutStatusModel.build_status(
		{
			"panel_rect": panel,
			"input_rect": input,
			"input_row_rect": Rect2(20, 300, 280, 96),
			"eye_rect": Rect2(20, 300, 44, 32),
			"composer_toggle_rect": Rect2(220, 300, 74, 32),
			"connect_button_rect": Rect2(180, 40, 72, 26),
			"frame_rect": frame,
			"log_rect": frame,
			"approval_rect": approval,
			"advanced_toggle_rect": Rect2(20, 40, 90, 26),
		},
		{
			"input_visible": true,
			"input_minimum_size": Vector2(0, 96),
			"input_row_minimum_size": Vector2(0, 96),
			"composer_toggle_visible": true,
			"composer_toggle_text": "Expand",
			"eye_button_visible": true,
			"approval_visible": true,
			"advanced_toggle_visible": true,
			"advanced_toggle_focus_mode": Control.FOCUS_ALL,
			"connect_button_visible": true,
			"connect_button_in_status_header": true,
			"connect_button_focus_mode": Control.FOCUS_ALL,
			"panel_minimum_size": Vector2(220, 0),
			"log_frame_minimum_size": Vector2(0, 48),
			"log_minimum_size": Vector2(),
			"visibility_chain": [{"name": "Codex Chat"}],
			"readiness_label_text": "Launcher: ok",
		},
		{
			"connection_state": "ready",
			"runtime_state": "ready",
			"mcp_tools_available": true,
			"trust_mode": "off",
		},
		{
			"chat_message_count": 3,
			"technical_log_count": 1,
		},
		{
			"pending_annotation": true,
			"pending_annotation_id": "ann-1",
			"annotation_marker_count": 2,
		},
		{
			"window_mode": 2,
			"window_position": Vector2i(0, 0),
			"window_size": Vector2i(200, 200),
			"window_screen": 0,
			"usable_rect": Rect2i(0, 0, 300, 300),
		}
	)
	_assert_true(bool(status.get("input_inside_chat_panel", false)), "status input inside panel")
	_assert_true(bool(status.get("composer_below_log", false)), "status composer below log")
	_assert_true(bool(status.get("approval_above_input", false)), "status approval above input")
	_assert_true(bool(status.get("composer_toggle_inside_chat_panel", false)), "status composer toggle inside")
	_assert_eq(status.get("composer_toggle_text"), "Expand", "status composer toggle text")
	_assert_true(bool(status.get("connect_button_inside_chat_panel", false)), "status connect button inside")
	_assert_true(bool(status.get("connect_button_in_status_header", false)), "status connect button in header")
	_assert_eq(status.get("connect_button_focus_mode"), Control.FOCUS_ALL, "status connect keyboard focus")
	_assert_eq(status.get("advanced_toggle_focus_mode"), Control.FOCUS_ALL, "status advanced keyboard focus")
	_assert_eq(status.get("pending_annotation_id"), "ann-1", "status annotation id")
	_assert_eq(status.get("mcp_tools_available"), true, "runtime field copied")
	_assert_eq(status.get("chat_message_count"), 3, "count field copied")
	_assert_true(bool(status.get("window_inside_usable_screen", false)), "window status inside")


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
