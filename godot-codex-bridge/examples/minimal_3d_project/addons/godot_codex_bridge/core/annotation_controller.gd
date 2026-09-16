@tool
extends RefCounted

const AnnotationCanvas := preload("annotation_canvas.gd")
const AnnotationArtifactModel := preload("annotation_artifact_model.gd")
const BridgeContext := preload("bridge_context.gd")

var ctx: BridgeContext
var dialog: Window
var canvas: AnnotationCanvas
var scope_option: OptionButton
var tool_option: OptionButton
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
	dialog = Window.new()
	dialog.title = "Eye Attach"
	dialog.unresizable = false
	dialog.min_size = Vector2i(640, 420)
	dialog.close_requested.connect(func() -> void:
		dialog.hide()
	)
	owner.add_child(dialog)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 14
	root.offset_top = 14
	root.offset_right = -14
	root.offset_bottom = -14
	dialog.add_child(root)

	var hint := Label.new()
	hint.text = "Draw user reference markers. Codex will be told these marks are annotations, not game art."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(hint)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	root.add_child(action_row)

	var attach_button := Button.new()
	attach_button.text = "Attach"
	attach_button.tooltip_text = "Attach this AI-safe marker to the next Codex message."
	attach_button.pressed.connect(attach_current_annotation)
	action_row.add_child(attach_button)

	var cancel_button := Button.new()
	cancel_button.text = "Cancel"
	cancel_button.tooltip_text = "Close Eye Attach without attaching a marker."
	cancel_button.pressed.connect(func() -> void:
		if dialog != null:
			dialog.hide()
	)
	action_row.add_child(cancel_button)

	var zoom_out_button := Button.new()
	zoom_out_button.text = "-"
	zoom_out_button.tooltip_text = "Zoom out"
	zoom_out_button.pressed.connect(func() -> void:
		if canvas != null:
			canvas.zoom_out()
			update_status()
	)
	action_row.add_child(zoom_out_button)

	var zoom_in_button := Button.new()
	zoom_in_button.text = "+"
	zoom_in_button.tooltip_text = "Zoom in"
	zoom_in_button.pressed.connect(func() -> void:
		if canvas != null:
			canvas.zoom_in()
			update_status()
	)
	action_row.add_child(zoom_in_button)

	var zoom_fit_button := Button.new()
	zoom_fit_button.text = "Fit"
	zoom_fit_button.tooltip_text = "Fit image"
	zoom_fit_button.pressed.connect(func() -> void:
		if canvas != null:
			canvas.zoom_reset()
			update_status()
	)
	action_row.add_child(zoom_fit_button)

	var zoom_actual_button := Button.new()
	zoom_actual_button.text = "1:1"
	zoom_actual_button.tooltip_text = "Actual size"
	zoom_actual_button.pressed.connect(func() -> void:
		if canvas != null:
			canvas.zoom_to_actual()
			update_status()
	)
	action_row.add_child(zoom_actual_button)

	zoom_label = Label.new()
	zoom_label.text = "Zoom: fit"
	zoom_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_row.add_child(zoom_label)

	size_toggle_button = Button.new()
	size_toggle_button.text = "Max"
	size_toggle_button.tooltip_text = "Toggle a larger Eye Attach window."
	size_toggle_button.pressed.connect(toggle_window_size)
	action_row.add_child(size_toggle_button)

	var capture_row := HBoxContainer.new()
	capture_row.add_theme_constant_override("separation", 8)
	root.add_child(capture_row)

	scope_option = OptionButton.new()
	scope_option.tooltip_text = "Capture scope. Editor Window can mark FileSystem, Inspector, errors and scene UI."
	scope_option.add_item("Editor Window")
	scope_option.set_item_metadata(0, "editor_window")
	scope_option.add_item("3D Viewport")
	scope_option.set_item_metadata(1, "viewport_3d")
	scope_option.add_item("2D Viewport")
	scope_option.set_item_metadata(2, "viewport_2d")
	scope_option.item_selected.connect(func(_index: int) -> void:
		recapture_annotation_source()
	)
	capture_row.add_child(scope_option)

	tool_option = OptionButton.new()
	tool_option.tooltip_text = "Marker tool."
	tool_option.add_item("Rectangle")
	tool_option.set_item_metadata(0, "rectangle")
	tool_option.add_item("Pin")
	tool_option.set_item_metadata(1, "pin")
	tool_option.add_item("Arrow")
	tool_option.set_item_metadata(2, "arrow")
	tool_option.add_item("Freehand")
	tool_option.set_item_metadata(3, "freehand")
	tool_option.add_item("Text Label")
	tool_option.set_item_metadata(4, "text")
	tool_option.item_selected.connect(func(_index: int) -> void:
		if canvas != null:
			canvas.set_tool(selected_tool())
	)
	capture_row.add_child(tool_option)

	var recapture_button := Button.new()
	recapture_button.text = "Recapture"
	recapture_button.tooltip_text = "Capture the selected Godot view again."
	recapture_button.pressed.connect(recapture_annotation_source)
	capture_row.add_child(recapture_button)

	var undo_button := Button.new()
	undo_button.text = "Undo"
	undo_button.pressed.connect(func() -> void:
		if canvas != null:
			canvas.undo_marker()
			update_status()
	)
	capture_row.add_child(undo_button)

	var clear_marker_button := Button.new()
	clear_marker_button.text = "Clear"
	clear_marker_button.pressed.connect(func() -> void:
		if canvas != null:
			canvas.clear_markers()
			update_status()
	)
	capture_row.add_child(clear_marker_button)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(status_label)

	canvas = AnnotationCanvas.new()
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.custom_minimum_size = Vector2(820, 500)
	canvas.set_tool(selected_tool())
	canvas.markers_changed.connect(update_status)
	root.add_child(canvas)


func popup_dialog() -> void:
	if dialog == null:
		return
	window_maximized = false
	var window_size := DisplayServer.window_get_size()
	dialog.popup_centered(AnnotationArtifactModel.default_window_size(window_size))
	update_window_size_button()


func toggle_window_size() -> void:
	if dialog == null:
		return
	window_maximized = not window_maximized
	var window_size := DisplayServer.window_get_size()
	var target_size := AnnotationArtifactModel.max_window_size(window_size) if window_maximized else AnnotationArtifactModel.default_window_size(window_size)
	dialog.size = target_size
	dialog.position = (window_size - target_size) / 2
	update_window_size_button()
	if canvas != null:
		canvas.queue_redraw()
		update_status()


func update_window_size_button() -> void:
	if size_toggle_button == null:
		return
	size_toggle_button.text = "Small" if window_maximized else "Max"
	size_toggle_button.tooltip_text = "Return Eye Attach to normal size." if window_maximized else "Make Eye Attach almost full editor size."


func recapture_annotation_source() -> void:
	if canvas == null:
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
	if tool_option == null:
		return "rectangle"
	var metadata: Variant = tool_option.get_selected_metadata()
	var tool := str(metadata)
	return tool if tool in ["rectangle", "pin", "arrow", "freehand", "text"] else "rectangle"


func capture_annotation_source(scope: String) -> Dictionary:
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
	var image_text := ""
	if image != null:
		image_text = " | " + str(image.get_width()) + "x" + str(image.get_height())
	var zoom_text := ""
	if canvas != null:
		zoom_text = " | Zoom: " + str(canvas.zoom_percent()) + "%"
		if zoom_label != null:
			zoom_label.text = "Zoom: " + str(canvas.zoom_percent()) + "%"
	var fallback_text := ""
	if source.has("fallback_reason") and source.get("fallback_reason") != null:
		fallback_text = " | Fallback: " + str(source.get("fallback_reason"))
	status_label.text = "Scope: " + scope + image_text + zoom_text + fallback_text + " | Markers: " + str(marker_count) + " | Wheel zoom, right/middle drag pan"


func attach_current_annotation() -> void:
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
		dialog.hide()
	ctx.append_status("Marker " + str(pending_annotation.get("primary_marker", "A")) + " attached to the next message.")


func write_annotation_artifact() -> Dictionary:
	ctx.ensure_dirs()
	var annotation_id := ctx.identifier("annotation_" + ctx.file_time() + "_" + str(Time.get_ticks_msec()), "annotation")
	var annotation_dir_abs := ctx.annotations_dir_abs.path_join(annotation_id)
	var err := DirAccess.make_dir_recursive_absolute(annotation_dir_abs)
	if err != OK and err != ERR_ALREADY_EXISTS:
		return {"ok": false, "error": ctx.err("annotation_dir_failed", "Failed to create annotation artifact directory: " + error_string(err))}

	var raw_image: Image = canvas.source_image
	var annotated_image := canvas.render_annotated_image()
	AnnotationArtifactModel.burn_watermark(annotated_image)

	var raw_abs := annotation_dir_abs.path_join("raw.png")
	var annotated_abs := annotation_dir_abs.path_join("annotated.png")
	err = raw_image.save_png(raw_abs)
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
