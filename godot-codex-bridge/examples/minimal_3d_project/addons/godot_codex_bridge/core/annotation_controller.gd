@tool
extends RefCounted

const AnnotationCanvas := preload("annotation_canvas.gd")
const AnnotationArtifactModel := preload("annotation_artifact_model.gd")
const BridgeContext := preload("bridge_context.gd")
const AnnotationViewModel := preload("annotation_view_model.gd")
const DockStyle := preload("dock_style.gd")

var ctx: BridgeContext
var dialog: Window
var canvas: AnnotationCanvas
var scope_option: OptionButton
## Marker tool toggle buttons keyed by tool id (one ButtonGroup).
var tool_buttons := {}
var _active_tool := "rectangle"
var attach_button: Button
var marker_list: VBoxContainer
var marker_list_empty: Label
var _selected_marker := -1
## Size/position remembered for this editor session (Rect2i()).
var _remembered_rect := Rect2i()
var _style: Dictionary = {}
var status_label: Label
var zoom_label: Label
var size_toggle_button: Button
var source: Dictionary = {}
var pending_annotation: Dictionary = {}
var window_maximized := false
var pending_label: Label
var clear_button: Button


func _init(context: BridgeContext) -> void:
	ctx = context


func setup_pending_ui(label: Label, button: Button) -> void:
	pending_label = label
	clear_button = button
	update_pending_ui()


func has_pending() -> bool:
	return not pending_annotation.is_empty()


func pending() -> Dictionary:
	return pending_annotation.duplicate(true)


func clear_pending(show_status := false) -> void:
	pending_annotation.clear()
	update_pending_ui()
	if show_status:
		ctx.append_status("Marker attachment removed.")


func invalidate_sensitive_capture(message := "Screenshot permission was revoked; the pending Eye Attach capture was discarded.") -> void:
	source.clear()
	pending_annotation.clear()
	if canvas != null:
		canvas.clear_source_image()
	if dialog != null:
		dialog.hide()
	update_pending_ui()
	if message != "":
		ctx.append_status(message)


func _screenshot_permission_error() -> Dictionary:
	return {
		"ok": false,
		"error": ctx.err("permission_denied", "Screenshot permission is disabled in the Codex Bridge dock."),
	}


func status_payload() -> Dictionary:
	return {
		"pending_annotation": has_pending(),
		"pending_annotation_id": str(pending_annotation.get("annotation_id", "")),
		"annotation_dialog_visible": dialog != null and dialog.visible,
		"annotation_dialog_rect": _window_rect_payload(dialog) if dialog != null else _rect_payload(Rect2()),
		"annotation_canvas_has_image": canvas != null and canvas.source_image != null,
		"annotation_marker_count": canvas.marker_count() if canvas != null else 0,
	}


func open_eye_attach_dialog() -> void:
	if not ctx.permission_enabled("allow_ai_markers"):
		ctx.append_status("Eye Attach permission is disabled.")
		return
	if not ctx.permission_enabled("allow_screenshots"):
		invalidate_sensitive_capture("Screenshot permission is disabled; Eye Attach capture was not opened.")
		return
	ensure_dialog()
	var capture := capture_annotation_source(selected_scope())
	if not bool(capture.get("ok", false)):
		var message := str(capture.get("error", {}).get("message", "Annotation capture failed."))
		ctx.append_status(message)
		if status_label != null:
			status_label.text = message
		popup_dialog()
		return
	source = capture
	canvas.set_source_image(capture.get("image") as Image)
	update_status()
	popup_dialog()


func ensure_dialog() -> void:
	if dialog != null and is_instance_valid(dialog):
		return
	var owner := ctx.owner_node
	if owner == null:
		return
	_style = DockStyle.resolve(EditorInterface.get_base_control() if Engine.is_editor_hint() else null)
	dialog = Window.new()
	dialog.title = "Eye Attach"
	dialog.unresizable = false
	dialog.min_size = AnnotationViewModel.MIN_WINDOW
	dialog.close_requested.connect(cancel_dialog)
	dialog.window_input.connect(_on_dialog_input)
	owner.add_child(dialog)

	var background := PanelContainer.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialog.add_child(background)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, DockStyle.SPACE_M)
	background.add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", DockStyle.SPACE_S + 2)
	margin.add_child(root)

	# One toolbar: source + recapture | marker tools | undo, clear | zoom, size, help.
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", DockStyle.SPACE_S)
	root.add_child(toolbar)
	scope_option = OptionButton.new()
	scope_option.tooltip_text = "Capture source. Editor Window can mark FileSystem, Inspector, errors and scene UI."
	scope_option.add_item("Editor Window")
	scope_option.set_item_metadata(0, "editor_window")
	scope_option.add_item("3D Viewport")
	scope_option.set_item_metadata(1, "viewport_3d")
	scope_option.add_item("2D Viewport")
	scope_option.set_item_metadata(2, "viewport_2d")
	scope_option.item_selected.connect(func(_index: int) -> void:
		recapture_annotation_source()
	)
	toolbar.add_child(scope_option)
	toolbar.add_child(_icon_button("Reload", "Recapture", "Capture the selected Godot view again.", recapture_annotation_source))
	toolbar.add_child(VSeparator.new())
	var group := ButtonGroup.new()
	for tool in AnnotationViewModel.TOOLS:
		var tool_id := str(tool.get("id"))
		var button := _icon_button(str(tool.get("icon")), str(tool.get("label")), str(tool.get("tip")), func() -> void:
			set_active_tool(tool_id)
		)
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = tool_id == _active_tool
		tool_buttons[tool_id] = button
		toolbar.add_child(button)
	toolbar.add_child(VSeparator.new())
	toolbar.add_child(_icon_button("UndoRedo", "Undo", "Undo the last marker (Ctrl+Z).", func() -> void:
		if canvas != null:
			canvas.undo_marker()
			update_status()
	))
	toolbar.add_child(_icon_button("Clear", "Clear", "Remove all markers.", func() -> void:
		if canvas != null:
			canvas.clear_markers()
			update_status()
	))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)
	toolbar.add_child(_icon_button("ZoomLess", "-", "Zoom out", func() -> void:
		if canvas != null:
			canvas.zoom_out()
			update_status()
	))
	zoom_label = Label.new()
	zoom_label.text = "fit"
	zoom_label.custom_minimum_size = Vector2(44, 0)
	zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zoom_label.tooltip_text = "Zoom"
	zoom_label.mouse_filter = Control.MOUSE_FILTER_PASS
	toolbar.add_child(zoom_label)
	toolbar.add_child(_icon_button("ZoomMore", "+", "Zoom in", func() -> void:
		if canvas != null:
			canvas.zoom_in()
			update_status()
	))
	toolbar.add_child(_icon_button("CenterView", "Fit", "Fit image", func() -> void:
		if canvas != null:
			canvas.zoom_reset()
			update_status()
	))
	toolbar.add_child(_icon_button("ZoomReset", "1:1", "Actual size", func() -> void:
		if canvas != null:
			canvas.zoom_to_actual()
			update_status()
	))
	size_toggle_button = _icon_button("DistractionFree", "Max", "", toggle_window_size)
	toolbar.add_child(size_toggle_button)
	var help := _icon_button("Info", "?", AnnotationViewModel.HELP_TEXT + "\nShortcuts: Esc cancel · Enter attach · Ctrl+Z undo · Del remove selected marker.", func() -> void: pass)
	help.focus_mode = Control.FOCUS_NONE
	toolbar.add_child(help)

	# Image area (dominant) + marker list.
	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var frame := PanelContainer.new()
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.add_theme_stylebox_override("panel", DockStyle.card_box(Color(0, 0, 0, 0.35), Color(0, 0, 0, 0), 0, Vector2(1, 1)))
	body.add_child(frame)
	canvas = AnnotationCanvas.new()
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.custom_minimum_size = Vector2(420, 280)
	canvas.set_tool(selected_tool())
	canvas.markers_changed.connect(update_status)
	frame.add_child(canvas)

	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(150, 0)
	side.add_theme_constant_override("separation", DockStyle.SPACE_S)
	body.add_child(side)
	var side_title := Label.new()
	side_title.text = "MARKERS"
	DockStyle.muted_label(_style, side_title, 11)
	side.add_child(side_title)
	var list_scroll := ScrollContainer.new()
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	side.add_child(list_scroll)
	marker_list = VBoxContainer.new()
	marker_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(marker_list)
	marker_list_empty = Label.new()
	marker_list_empty.text = "Draw on the image to add markers."
	marker_list_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	DockStyle.muted_label(_style, marker_list_empty)
	side.add_child(marker_list_empty)

	# Bottom bar: muted status left, Cancel + Attach right.
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", DockStyle.SPACE_S)
	root.add_child(bottom)
	status_label = Label.new()
	status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_label.clip_text = true
	status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status_label.mouse_filter = Control.MOUSE_FILTER_PASS
	DockStyle.muted_label(_style, status_label, 12)
	bottom.add_child(status_label)
	var cancel_button := Button.new()
	cancel_button.text = "Cancel"
	cancel_button.tooltip_text = "Close Eye Attach without attaching a marker (Esc)."
	cancel_button.pressed.connect(cancel_dialog)
	bottom.add_child(cancel_button)
	attach_button = Button.new()
	attach_button.text = "Attach"
	attach_button.tooltip_text = "Attach these AI-safe markers to the next Codex message (Enter)."
	attach_button.pressed.connect(attach_current_annotation)
	DockStyle.apply_accent_button(attach_button, _style)
	bottom.add_child(attach_button)
	update_status()


func _icon_button(icon_name: String, fallback_text: String, tooltip: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = fallback_text
	button.tooltip_text = tooltip if tooltip != "" else fallback_text
	button.pressed.connect(callback)
	DockStyle.apply_icon(button, _style, icon_name, true)
	return button


func set_active_tool(tool_id: String) -> void:
	if not tool_id in AnnotationViewModel.tool_ids():
		return
	_active_tool = tool_id
	if tool_buttons.has(tool_id):
		(tool_buttons[tool_id] as Button).set_pressed_no_signal(true)
	if canvas != null:
		canvas.set_tool(tool_id)


func cancel_dialog() -> void:
	if dialog == null:
		return
	_remember_window_rect()
	dialog.hide()


func _remember_window_rect() -> void:
	if dialog != null and dialog.visible and not window_maximized:
		_remembered_rect = Rect2i(dialog.position, dialog.size)


func _on_dialog_input(event: InputEvent) -> void:
	match AnnotationViewModel.key_action(event):
		"cancel":
			cancel_dialog()
		"attach":
			attach_current_annotation()
		"undo":
			if canvas != null:
				canvas.undo_marker()
				update_status()
		"delete":
			if canvas != null and _selected_marker >= 0:
				canvas.remove_marker(_selected_marker)
				_selected_marker = -1
				update_status()
		_:
			return
	dialog.set_input_as_handled()


func _rebuild_marker_list() -> void:
	if marker_list == null or canvas == null:
		return
	for child in marker_list.get_children():
		marker_list.remove_child(child)
		child.queue_free()
	var rows := AnnotationViewModel.marker_rows(canvas.markers)
	if _selected_marker >= rows.size():
		_selected_marker = -1
	canvas.highlight_index = _selected_marker
	for row in rows:
		var index := int(row.get("index", 0))
		var line := HBoxContainer.new()
		var select := Button.new()
		select.flat = true
		select.toggle_mode = true
		select.button_pressed = index == _selected_marker
		select.alignment = HORIZONTAL_ALIGNMENT_LEFT
		select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		select.text = str(row.get("label", "")) + "  " + str(row.get("type_label", ""))
		select.tooltip_text = "Select marker " + str(row.get("label", "")) + " (Del removes it)."
		select.pressed.connect(func() -> void:
			_selected_marker = -1 if _selected_marker == index else index
			_rebuild_marker_list()
			canvas.queue_redraw()
		)
		line.add_child(select)
		var remove := _icon_button("Remove", "x", "Remove marker " + str(row.get("label", "")), func() -> void:
			canvas.remove_marker(index)
			_selected_marker = -1
			update_status()
		)
		remove.flat = true
		line.add_child(remove)
		marker_list.add_child(line)
	if marker_list_empty != null:
		marker_list_empty.visible = rows.is_empty()


func popup_dialog() -> void:
	if dialog == null:
		return
	window_maximized = false
	var window_size := AnnotationViewModel.window_size(DisplayServer.window_get_size(), _remembered_rect.size)
	if _remembered_rect.size == window_size:
		dialog.popup(Rect2i(_remembered_rect.position, window_size))
	else:
		dialog.popup_centered(window_size)
	update_window_size_button()


func toggle_window_size() -> void:
	if dialog == null:
		return
	if not window_maximized:
		_remember_window_rect()
	window_maximized = not window_maximized
	var editor_size := DisplayServer.window_get_size()
	if window_maximized:
		dialog.size = AnnotationArtifactModel.max_window_size(editor_size)
		dialog.move_to_center()
	elif _remembered_rect.size == AnnotationViewModel.window_size(editor_size, _remembered_rect.size):
		dialog.size = _remembered_rect.size
		dialog.position = _remembered_rect.position
	else:
		dialog.size = AnnotationViewModel.window_size(editor_size, Vector2i.ZERO)
		dialog.move_to_center()
	update_window_size_button()
	if canvas != null:
		canvas.queue_redraw()
		update_status()


func update_window_size_button() -> void:
	if size_toggle_button == null:
		return
	if not DockStyle.is_icon_only(size_toggle_button):
		size_toggle_button.text = "Small" if window_maximized else "Max"
	size_toggle_button.tooltip_text = "Return Eye Attach to normal size." if window_maximized else "Make Eye Attach almost full editor size."


func recapture_annotation_source() -> void:
	if canvas == null:
		return
	if not ctx.permission_enabled("allow_screenshots"):
		invalidate_sensitive_capture()
		return
	var was_visible := dialog != null and dialog.visible
	var previous_position := Vector2i.ZERO
	var previous_size := Vector2i.ZERO
	var previous_maximized := window_maximized
	if was_visible:
		previous_position = dialog.position
		previous_size = dialog.size
		if status_label != null:
			status_label.text = "Recapturing..."
		dialog.hide()
		await ctx.owner_node.get_tree().process_frame
		await ctx.owner_node.get_tree().process_frame
		await ctx.owner_node.get_tree().create_timer(0.12).timeout
	var capture := capture_annotation_source(selected_scope())
	if bool(capture.get("ok", false)) and AnnotationArtifactModel.image_looks_blank(capture.get("image") as Image):
		await ctx.owner_node.get_tree().create_timer(0.20).timeout
		capture = capture_annotation_source(selected_scope())
	if was_visible:
		dialog.position = previous_position
		dialog.size = previous_size
		window_maximized = previous_maximized
		dialog.show()
		update_window_size_button()
	if not bool(capture.get("ok", false)):
		status_label.text = str(capture.get("error", {}).get("message", "Annotation capture failed."))
		return
	source = capture
	canvas.set_source_image(capture.get("image") as Image)
	update_status()


func selected_scope() -> String:
	if scope_option == null:
		return "editor_window"
	var metadata: Variant = scope_option.get_selected_metadata()
	var scope := str(metadata)
	return scope if scope in ["editor_window", "viewport_3d", "viewport_2d"] else "editor_window"


func selected_tool() -> String:
	return _active_tool if _active_tool in AnnotationViewModel.tool_ids() else "rectangle"


func capture_annotation_source(scope: String) -> Dictionary:
	if not ctx.permission_enabled("allow_screenshots"):
		return _screenshot_permission_error()
	ctx.ensure_dirs()
	if DisplayServer.get_name().to_lower() == "headless":
		return {
			"ok": false,
			"error": ctx.err("annotation_capture_unavailable", "Eye Attach capture is unavailable in headless display mode."),
		}

	var capture: Dictionary
	if scope == "viewport_3d":
		capture = capture_editor_viewport_image("viewport_3d")
	elif scope == "viewport_2d":
		capture = capture_editor_viewport_image("viewport_2d")
	else:
		capture = capture_editor_window_image()

	if bool(capture.get("ok", false)):
		var image: Image = capture.get("image") as Image
		if scope != "editor_window" and AnnotationArtifactModel.image_looks_blank(image):
			var editor_capture := capture_editor_window_image()
			if bool(editor_capture.get("ok", false)):
				editor_capture["capture_scope"] = scope
				editor_capture["fallback_reason"] = "viewport_capture_looked_blank"
				return editor_capture
		return capture
	if scope == "editor_window":
		var fallback := capture_editor_viewport_image("viewport_3d")
		if bool(fallback.get("ok", false)):
			fallback["fallback_reason"] = str(capture.get("error", {}).get("code", "editor_window_capture_failed"))
			return fallback
	return capture


func capture_editor_window_image() -> Dictionary:
	if not ctx.permission_enabled("allow_screenshots"):
		return _screenshot_permission_error()
	var window_position := DisplayServer.window_get_position()
	var window_size := DisplayServer.window_get_size()
	if window_size.x <= 0 or window_size.y <= 0:
		return {
			"ok": false,
			"error": ctx.err("annotation_window_unavailable", "Godot editor window size is unavailable."),
		}
	var root_viewport_capture := _capture_editor_root_viewport_image()
	if bool(root_viewport_capture.get("ok", false)):
		root_viewport_capture["window_position"] = {"x": window_position.x, "y": window_position.y}
		root_viewport_capture["window_size"] = {"x": window_size.x, "y": window_size.y}
		return root_viewport_capture
	var image := DisplayServer.screen_get_image_rect(Rect2i(window_position, window_size))
	if image == null or image.is_empty():
		return {
			"ok": false,
			"error": ctx.err("annotation_window_image_unavailable", "Godot editor window capture returned an empty image."),
		}
	return {
		"ok": true,
		"image": image,
		"capture_scope": "editor_window",
		"source": "display_server_window_rect",
		"target_window_verified": false,
		"occlusion_sensitive": true,
		"fallback_reason": str(root_viewport_capture.get("error", {}).get("code", "editor_root_viewport_unavailable")),
		"window_position": {"x": window_position.x, "y": window_position.y},
		"window_size": {"x": window_size.x, "y": window_size.y},
	}


func _capture_editor_root_viewport_image() -> Dictionary:
	if not ctx.permission_enabled("allow_screenshots"):
		return _screenshot_permission_error()
	var base_control := EditorInterface.get_base_control()
	if base_control == null:
		return {
			"ok": false,
			"error": ctx.err("annotation_editor_root_unavailable", "Godot editor base control is unavailable."),
		}
	var root_viewport := base_control.get_viewport()
	if root_viewport == null:
		return {
			"ok": false,
			"error": ctx.err("annotation_editor_root_viewport_unavailable", "Godot editor root viewport is unavailable."),
		}
	var texture := root_viewport.get_texture()
	if texture == null:
		return {
			"ok": false,
			"error": ctx.err("annotation_editor_root_texture_unavailable", "Godot editor root viewport texture is unavailable."),
		}
	var image := texture.get_image()
	if image == null or image.is_empty() or AnnotationArtifactModel.image_looks_blank(image):
		return {
			"ok": false,
			"error": ctx.err("annotation_editor_root_image_unavailable", "Godot editor root viewport image is empty or blank."),
		}
	return {
		"ok": true,
		"image": image,
		"capture_scope": "editor_window",
		"source": "editor_root_viewport",
		"target_window_verified": true,
		"occlusion_sensitive": false,
	}


func capture_editor_viewport_image(scope: String) -> Dictionary:
	if not ctx.permission_enabled("allow_screenshots"):
		return _screenshot_permission_error()
	var viewport: SubViewport = null
	var source_name := "editor_3d_viewport"
	if scope == "viewport_2d":
		viewport = EditorInterface.get_editor_viewport_2d()
		source_name = "editor_2d_viewport"
	else:
		viewport = EditorInterface.get_editor_viewport_3d(0)
	if viewport == null:
		return {
			"ok": false,
			"error": ctx.err("annotation_viewport_unavailable", "Requested editor viewport is unavailable: " + scope),
		}
	var texture := viewport.get_texture()
	if texture == null:
		return {
			"ok": false,
			"error": ctx.err("annotation_viewport_texture_unavailable", "Requested editor viewport texture is unavailable: " + scope),
		}
	var image := texture.get_image()
	if image == null or image.is_empty():
		return {
			"ok": false,
			"error": ctx.err("annotation_viewport_image_unavailable", "Requested editor viewport image is empty: " + scope),
		}
	var camera: Camera3D = null
	if scope == "viewport_3d":
		camera = viewport.get_camera_3d()
	return {
		"ok": true,
		"image": image,
		"capture_scope": scope,
		"source": source_name,
		"target_window_verified": true,
		"occlusion_sensitive": false,
		"camera": camera,
	}


func update_status() -> void:
	if status_label == null:
		return
	var scope := str(source.get("capture_scope", selected_scope()))
	var marker_count := canvas.marker_count() if canvas != null else 0
	var image: Image = source.get("image") as Image
	var image_size := Vector2i(image.get_width(), image.get_height()) if image != null else Vector2i.ZERO
	if canvas != null and zoom_label != null:
		zoom_label.text = str(canvas.zoom_percent()) + "%"
	var fallback := str(source.get("fallback_reason", "")) if source.get("fallback_reason") != null else ""
	status_label.text = AnnotationViewModel.status_text(image_size, marker_count, fallback)
	status_label.tooltip_text = "Scope: " + scope + "\n" + status_label.text
	if attach_button != null:
		attach_button.text = AnnotationViewModel.attach_text(marker_count)
		attach_button.disabled = not AnnotationViewModel.attach_enabled(marker_count, canvas != null and canvas.source_image != null)
	_rebuild_marker_list()


func attach_current_annotation() -> void:
	if not ctx.permission_enabled("allow_screenshots"):
		invalidate_sensitive_capture()
		return
	if canvas == null or canvas.source_image == null:
		ctx.append_status("Eye Attach has no captured image.")
		return
	if canvas.marker_count() <= 0:
		ctx.append_status("Add at least one marker before attaching.")
		return
	var result := write_annotation_artifact()
	if not bool(result.get("ok", false)):
		ctx.append_status("Failed to attach marker: " + str(result.get("error", {}).get("message", "unknown error")))
		return
	pending_annotation = result.get("annotation", {})
	update_pending_ui()
	if dialog != null:
		_remember_window_rect()
		dialog.hide()
	ctx.append_status("Marker " + str(pending_annotation.get("primary_marker", "A")) + " attached to the next message.")


func write_annotation_artifact() -> Dictionary:
	if not ctx.permission_enabled("allow_screenshots"):
		invalidate_sensitive_capture()
		return _screenshot_permission_error()
	ctx.ensure_dirs()
	var annotation_id := ctx.identifier("annotation_" + ctx.file_time() + "_" + str(Time.get_ticks_msec()), "annotation")
	var annotation_dir_abs := ctx.annotations_dir_abs.path_join(annotation_id)
	var dir_result := ctx.ensure_safe_dir(annotation_dir_abs)
	if not bool(dir_result.get("ok", false)):
		return {"ok": false, "error": dir_result.get("error", ctx.err("annotation_dir_failed", "Failed to create a safe annotation artifact directory."))}

	var raw_image: Image = canvas.source_image
	var annotated_image := canvas.render_annotated_image()
	AnnotationArtifactModel.burn_watermark(annotated_image)

	var raw_abs := annotation_dir_abs.path_join("raw.png")
	var annotated_abs := annotation_dir_abs.path_join("annotated.png")
	var raw_guard := ctx.validate_path(raw_abs, true)
	var annotated_guard := ctx.validate_path(annotated_abs, true)
	if not bool(raw_guard.get("ok", false)) or not bool(annotated_guard.get("ok", false)):
		return {"ok": false, "error": raw_guard.get("error", annotated_guard.get("error", ctx.err("annotation_path_rejected", "Annotation artifact path is unsafe.")))}
	var err := raw_image.save_png(raw_abs)
	if err != OK:
		return {"ok": false, "error": ctx.err("annotation_raw_save_failed", "Failed to save raw marker image: " + error_string(err))}
	err = annotated_image.save_png(annotated_abs)
	if err != OK:
		return {"ok": false, "error": ctx.err("annotation_save_failed", "Failed to save annotated marker image: " + error_string(err))}

	var manifest_abs := annotation_dir_abs.path_join("annotation.json")
	var markers := canvas.marker_payloads()
	var manifest := AnnotationArtifactModel.build_manifest(
		annotation_id,
		ctx.timestamp_iso(),
		source,
		Vector2i(annotated_image.get_width(), annotated_image.get_height()),
		ctx.current_scene_or_null(),
		ctx.selected_nodes(),
		AnnotationArtifactModel.artifact_payload(annotation_id, "raw.png", raw_abs, annotated_image.get_width(), annotated_image.get_height()),
		AnnotationArtifactModel.artifact_payload(annotation_id, "annotated.png", annotated_abs, annotated_image.get_width(), annotated_image.get_height()),
		AnnotationArtifactModel.artifact_payload(annotation_id, "annotation.json", manifest_abs, 0, 0),
		markers
	)
	var write_result := ctx.write_json(manifest_abs, manifest)
	if not bool(write_result.get("ok", false)):
		return write_result
	ctx.log("annotation_attached", {
		"annotation_id": annotation_id,
		"capture_scope": manifest.get("capture_scope"),
		"marker_count": markers.size(),
	})
	return {
		"ok": true,
		"annotation": AnnotationArtifactModel.summary_payload(annotation_id, manifest, markers.size(), manifest_abs, annotated_abs),
	}


func update_pending_ui() -> void:
	if pending_label == null or clear_button == null:
		return
	var has_marker := has_pending()
	pending_label.visible = has_marker
	clear_button.visible = has_marker
	if has_marker:
		pending_label.text = "Marker " + str(pending_annotation.get("primary_marker", "A")) + " attached"
	else:
		pending_label.text = ""


func _rect_payload(rect: Rect2) -> Dictionary:
	return {
		"x": rect.position.x,
		"y": rect.position.y,
		"width": rect.size.x,
		"height": rect.size.y,
	}


func _window_rect_payload(window: Window) -> Dictionary:
	return {
		"x": window.position.x,
		"y": window.position.y,
		"width": window.size.x,
		"height": window.size.y,
	}
