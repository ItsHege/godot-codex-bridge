@tool
extends RefCounted

const ANNOTATION_VERSION := "godot-codex-bridge/annotation-v1"
const ANNOTATION_ROLE := "user_reference_marker"
const NON_GAME_INSTRUCTION := "These marks are user annotations. Do not recreate marker graphics in the game."


static func default_window_size(window_size: Vector2i) -> Vector2i:
	var max_width: int = max(720, window_size.x - 72)
	var max_height: int = max(520, window_size.y - 112)
	var target_width: int = clampi(int(float(window_size.x) * 0.78), 860, max_width)
	var target_height: int = clampi(int(float(window_size.y) * 0.76), 620, max_height)
	return Vector2i(target_width, target_height)


static func max_window_size(window_size: Vector2i) -> Vector2i:
	return Vector2i(max(720, window_size.x - 40), max(520, window_size.y - 70))


static func image_looks_blank(image: Image) -> bool:
	if image == null or image.is_empty():
		return true
	var width := image.get_width()
	var height := image.get_height()
	if width <= 0 or height <= 0:
		return true
	var samples := 0
	var min_luma := 999.0
	var max_luma := -999.0
	var total_luma := 0.0
	var step_x: int = max(1, int(width / 12))
	var step_y: int = max(1, int(height / 8))
	for y in range(0, height, step_y):
		for x in range(0, width, step_x):
			var color := image.get_pixel(x, y)
			var luma := color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
			min_luma = min(min_luma, luma)
			max_luma = max(max_luma, luma)
			total_luma += luma
			samples += 1
	if samples <= 0:
		return true
	var avg_luma := total_luma / float(samples)
	var range_luma := max_luma - min_luma
	return range_luma < 0.035 or (avg_luma < 0.18 and range_luma < 0.08)


static func burn_watermark(image: Image) -> void:
	var color := Color(0.0, 1.0, 1.0, 1.0)
	var margin := 8
	var width: int = min(image.get_width() - margin * 2, 360)
	if width <= 0:
		return
	for x in range(margin, margin + width):
		for y in range(margin, min(margin + 3, image.get_height())):
			image.set_pixel(x, y, color)
	for y in range(margin, min(margin + 18, image.get_height())):
		for x in range(margin, min(margin + 3, image.get_width())):
			image.set_pixel(x, y, color)


static func artifact_payload(annotation_id: String, file_name: String, abs_path: String, width: int, height: int) -> Dictionary:
	var payload := {
		"local_path": abs_path,
		"project_relative_path": ".godot/godot_codex_bridge/artifacts/annotations/" + annotation_id + "/" + file_name,
		"format": file_name.get_extension(),
		"byte_size": FileAccess.get_file_as_bytes(abs_path).size() if FileAccess.file_exists(abs_path) else 0,
	}
	if width > 0 and height > 0:
		payload["width"] = width
		payload["height"] = height
	return payload


static func build_manifest(
	annotation_id: String,
	captured_at: String,
	annotation_source: Dictionary,
	image_size: Vector2i,
	current_scene: Variant,
	selected_nodes: Array,
	raw_artifact: Dictionary,
	annotated_artifact: Dictionary,
	manifest_artifact: Dictionary,
	markers: Array
) -> Dictionary:
	var first_marker: Dictionary = markers[0] if markers.size() > 0 and typeof(markers[0]) == TYPE_DICTIONARY else {}
	return {
		"annotation_version": ANNOTATION_VERSION,
		"annotation_id": annotation_id,
		"annotation_role": ANNOTATION_ROLE,
		"non_game_overlay": true,
		"do_not_recreate_marker_graphics": true,
		"instruction": NON_GAME_INSTRUCTION,
		"captured_at": captured_at,
		"capture_scope": str(annotation_source.get("capture_scope", "editor_window")),
		"capture_source": str(annotation_source.get("source", "unknown")),
		"target_window_verified": bool(annotation_source.get("target_window_verified", false)),
		"occlusion_sensitive": bool(annotation_source.get("occlusion_sensitive", true)),
		"fallback_reason": annotation_source.get("fallback_reason", null),
		"image_size": {
			"width": image_size.x,
			"height": image_size.y,
		},
		"current_scene": current_scene,
		"selected_nodes": selected_nodes,
		"active_screen": "unknown",
		"artifacts": {
			"raw": raw_artifact,
			"annotated": annotated_artifact,
			"manifest": manifest_artifact,
		},
		"markers": markers,
		"primary_marker": str(first_marker.get("id", "A")) if typeof(first_marker) == TYPE_DICTIONARY else "A",
		"privacy": {
			"classification": "local_sensitive_evidence",
			"external_upload_allowed": false,
			"notes": [
				"Whole-editor captures may include private file names or assets.",
				"Artifacts remain local under the project .godot bridge directory.",
			],
		},
	}


static func summary_payload(annotation_id: String, manifest: Dictionary, marker_count: int, manifest_abs: String, annotated_abs: String) -> Dictionary:
	return {
		"annotation_id": annotation_id,
		"primary_marker": manifest.get("primary_marker", "A"),
		"marker_count": marker_count,
		"manifest_path": manifest_abs,
		"annotated_path": annotated_abs,
	}
