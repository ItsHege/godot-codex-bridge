extends SceneTree

const AnnotationArtifactModel := preload("res://addons/godot_codex_bridge/core/annotation_artifact_model.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge annotation artifact model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge annotation artifact model tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	_assert_eq(AnnotationArtifactModel.default_window_size(Vector2i(1920, 1080)), Vector2i(1497, 820), "Default annotation window size")
	_assert_eq(AnnotationArtifactModel.max_window_size(Vector2i(1920, 1080)), Vector2i(1880, 1010), "Max annotation window size")

	var blank := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	blank.fill(Color(0.1, 0.1, 0.1, 1.0))
	_assert_true(AnnotationArtifactModel.image_looks_blank(blank), "Flat dark image looks blank")

	var varied := Image.create_empty(64, 64, false, Image.FORMAT_RGBA8)
	varied.fill(Color(0.1, 0.1, 0.1, 1.0))
	for y in range(0, 64):
		for x in range(32, 64):
			varied.set_pixel(x, y, Color(0.9, 0.9, 0.9, 1.0))
	_assert_true(not AnnotationArtifactModel.image_looks_blank(varied), "High-contrast image is not blank")

	var watermarked := Image.create_empty(64, 40, false, Image.FORMAT_RGBA8)
	watermarked.fill(Color(0.0, 0.0, 0.0, 1.0))
	AnnotationArtifactModel.burn_watermark(watermarked)
	var watermark_pixel := watermarked.get_pixel(8, 8)
	_assert_true(watermark_pixel.g > 0.9 and watermark_pixel.b > 0.9, "Watermark burns cyan guard")

	var payload_path := "user://gcb_annotation_artifact_payload_test.txt"
	var file := FileAccess.open(payload_path, FileAccess.WRITE)
	file.store_string("abc")
	file.close()
	var artifact := AnnotationArtifactModel.artifact_payload("annotation_test", "raw.png", payload_path, 64, 40)
	_assert_eq(artifact.get("project_relative_path"), ".godot/godot_codex_bridge/artifacts/annotations/annotation_test/raw.png", "Artifact project relative path")
	_assert_eq(artifact.get("format"), "png", "Artifact format")
	_assert_eq(artifact.get("byte_size"), 3, "Artifact byte size")
	_assert_eq(artifact.get("width"), 64, "Artifact width")

	var markers := [
		{
			"id": "A",
			"type": "rectangle",
			"pixel_bounds": {"x": 1, "y": 2, "w": 3, "h": 4},
		},
	]
	var manifest := AnnotationArtifactModel.build_manifest(
		"annotation_test",
		"2026-06-21T00:00:00Z",
		{
			"capture_scope": "editor_window",
			"source": "display_server_window_rect",
			"target_window_verified": false,
			"occlusion_sensitive": true,
		},
		Vector2i(64, 40),
		"res://scenes/main.tscn",
		["/root/Main"],
		artifact,
		artifact,
		AnnotationArtifactModel.artifact_payload("annotation_test", "annotation.json", "user://missing_annotation.json", 0, 0),
		markers
	)
	_assert_eq(manifest.get("annotation_version"), AnnotationArtifactModel.ANNOTATION_VERSION, "Manifest version")
	_assert_eq(manifest.get("annotation_role"), "user_reference_marker", "Manifest role")
	_assert_eq(manifest.get("non_game_overlay"), true, "Manifest marks overlay as non-game")
	_assert_eq(manifest.get("do_not_recreate_marker_graphics"), true, "Manifest has anti-recreate guard")
	_assert_eq(manifest.get("primary_marker"), "A", "Manifest primary marker")
	_assert_eq(manifest.get("target_window_verified"), false, "Manifest target-window verification")
	_assert_eq(manifest.get("occlusion_sensitive"), true, "Manifest occlusion classification")
	_assert_eq((manifest.get("image_size") as Dictionary).get("width"), 64, "Manifest image width")
	_assert_eq((manifest.get("privacy") as Dictionary).get("external_upload_allowed"), false, "Manifest local-only privacy")

	var summary := AnnotationArtifactModel.summary_payload("annotation_test", manifest, 1, "manifest.json", "annotated.png")
	_assert_eq(summary.get("primary_marker"), "A", "Summary primary marker")
	_assert_eq(summary.get("marker_count"), 1, "Summary marker count")


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures += 1
		push_error(label + " expected=" + str(expected) + " actual=" + str(actual))


func _assert_true(value: bool, label: String) -> void:
	if not value:
		_failures += 1
		push_error(label)
