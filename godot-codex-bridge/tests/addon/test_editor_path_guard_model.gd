extends SceneTree

const EditorPathGuard := preload("res://addons/godot_codex_bridge/core/editor_path_guard.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge editor path guard tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge editor path guard tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	_assert_true(EditorPathGuard.validate_res_dir_path("res://").is_empty(), "res root validates")
	_assert_true(EditorPathGuard.validate_res_dir_path("res://assets/nested").is_empty(), "nested resource root validates")
	_assert_eq(EditorPathGuard.validate_res_dir_path("C:/outside").get("code"), "invalid_resource_root", "absolute root rejected")
	_assert_eq(EditorPathGuard.validate_res_dir_path("res://assets//bad").get("code"), "invalid_resource_root", "empty segment root rejected")
	_assert_eq(EditorPathGuard.validate_res_dir_path("res://../outside").get("code"), "invalid_resource_root", "traversal root rejected")
	_assert_eq(EditorPathGuard.validate_res_dir_path("res://.import/cache").get("code"), "invalid_resource_root", "import root rejected")
	_assert_eq(EditorPathGuard.validate_res_dir_path("res://.godot/cache").get("code"), "invalid_resource_root", "godot cache root rejected")

	_assert_true(EditorPathGuard.validate_res_path("res://assets/tree.png", [".png"], "texture", false).is_empty(), "valid texture path accepted")
	_assert_eq(EditorPathGuard.validate_res_path("C:/tree.png", [".png"], "texture", false).get("code"), "invalid_texture_path", "absolute file rejected")
	_assert_eq(EditorPathGuard.validate_res_path("res://", [".png"], "texture", false).get("code"), "invalid_texture_path", "empty file path rejected")
	_assert_eq(EditorPathGuard.validate_res_path("res://assets/../tree.png", [".png"], "texture", false).get("code"), "invalid_texture_path", "file traversal rejected")
	_assert_eq(EditorPathGuard.validate_res_path("res://assets/tree.txt", [".png"], "texture", false).get("code"), "invalid_texture_extension", "extension rejected")
	_assert_eq(EditorPathGuard.validate_res_path("res://assets/missing.png", [".png"], "texture", true).get("code"), "texture_not_found", "missing file rejected when required")

	_assert_true(EditorPathGuard.validate_scene_path("res://scenes/ghost.tscn", false).is_empty(), "scene path accepted without existence")
	_assert_eq(EditorPathGuard.validate_scene_path("res://scenes/ghost.txt", false).get("code"), "invalid_scene_extension", "scene extension rejected")
	_assert_eq(EditorPathGuard.validate_scene_path("res://.godot/ghost.tscn", false).get("code"), "invalid_scene_path", "generated scene rejected")
	_assert_eq(EditorPathGuard.validate_scene_path("res://scenes/ghost.tscn", true).get("code"), "scene_not_found", "missing scene rejected when required")
	_assert_true(EditorPathGuard.validate_scene_local_node_path("Player/Camera3D").is_empty(), "scene-local node path accepted")
	_assert_true(EditorPathGuard.validate_scene_local_node_path("/root/EditedScene/Player").is_empty(), "absolute Godot node path remains accepted")
	_assert_eq(EditorPathGuard.validate_scene_local_node_path("res://scenes/main.tscn").get("code"), "invalid_node_path", "file path rejected as node path")
	_assert_eq(EditorPathGuard.validate_scene_local_node_path("../Player").get("code"), "invalid_node_path", "node traversal rejected")
	_assert_eq(EditorPathGuard.validate_scene_local_node_path("Player\nCamera").get("code"), "invalid_node_path", "node newline rejected")
	_assert_eq(EditorPathGuard.validate_scene_local_node_path("Player\rCamera").get("code"), "invalid_node_path", "node carriage return rejected")
	_assert_true(EditorPathGuard.extension_allowed("assets/tree.png", [".PNG"]), "extension compare is case-insensitive")
	_assert_false(EditorPathGuard.extension_allowed("assets/tree.jpg", [".png"]), "nonmatching extension rejected")


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
