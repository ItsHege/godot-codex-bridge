extends SceneTree

const BridgeContext := preload("res://addons/godot_codex_bridge/core/bridge_context.gd")
const EditorAssetImport := preload("res://addons/godot_codex_bridge/core/editor_asset_import.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge editor asset/import tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge editor asset/import tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var bad_root := EditorAssetImport.validate_res_dir_path("C:/outside")
	_assert_eq(bad_root.get("code"), "invalid_resource_root", "absolute resource root rejected")
	var bad_generated := EditorAssetImport.validate_res_dir_path("res://.godot/generated")
	_assert_eq(bad_generated.get("code"), "invalid_resource_root", "generated root rejected")
	var ok_root := EditorAssetImport.validate_res_dir_path("res://assets")
	_assert_eq(ok_root.size(), 0, "valid resource root accepted")

	var extensions := EditorAssetImport.extension_filter_array(["png", ".tscn", "../bad", ".veryveryverylongextension"])
	_assert_true(".png" in extensions, "extension normalizes missing dot")
	_assert_true(".tscn" in extensions, "extension keeps dotted value")
	_assert_false("../bad" in extensions, "path-like extension rejected")

	var bad_asset := EditorAssetImport.validate_placeable_asset_path("res://.godot/cache.tscn")
	_assert_eq(bad_asset.get("code"), "invalid_asset_path", "generated asset path rejected")
	var bad_extension := EditorAssetImport.validate_res_path("res://asset.txt", [".tscn"], "asset", false)
	_assert_eq(bad_extension.get("code"), "invalid_asset_extension", "asset extension rejected")
	var ok_asset := EditorAssetImport.validate_res_path("res://asset.tscn", [".tscn"], "asset", false)
	_assert_eq(ok_asset.size(), 0, "valid asset path accepted when existence not required")

	var root := Node3D.new()
	root.name = "Root"
	var child := Node3D.new()
	child.name = "Child"
	root.add_child(child)
	_assert_eq(EditorAssetImport.bounded_child_index(root, -1), 1, "negative child index appends")
	_assert_eq(EditorAssetImport.sanitize_node_name("", "Fallback"), "Fallback", "empty node name gets fallback")
	_assert_false(EditorAssetImport.is_valid_node_name("bad/name"), "path-like node name rejected")
	var transform_result := EditorAssetImport.prepare_initial_transform_changes(child, {"position": [1, 2, 3]})
	_assert_true(bool(transform_result.get("ok", false)), "initial transform accepted for Node3D")
	_assert_eq((transform_result.get("changes", []) as Array).size(), 1, "one transform change prepared")
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = BoxMesh.new()
	var mesh_options := EditorAssetImport.prepare_placement_options(mesh_instance, {
		"create_collider": true,
		"material_color": {"r": 0.2, "g": 0.4, "b": 0.8, "a": 1.0},
	})
	_assert_true(bool(mesh_options.get("ok", false)), "mesh placement options accepted")
	_assert_eq((mesh_options.get("nodes", []) as Array).size(), 1, "mesh collider option creates one node")
	_assert_true(((mesh_options.get("nodes", []) as Array)[0]) is StaticBody3D, "mesh collider option creates StaticBody3D")
	_assert_eq((mesh_options.get("changes", []) as Array).size(), 1, "mesh material color creates one property change")
	_assert_eq((((mesh_options.get("summary", {}) as Dictionary).get("create_collider", {}) as Dictionary).get("status")), "created", "collider summary created")
	_assert_eq((((mesh_options.get("summary", {}) as Dictionary).get("material_color", {}) as Dictionary).get("status")), "applied", "material summary applied")
	((mesh_options.get("nodes", []) as Array)[0] as Node).free()
	mesh_instance.free()
	var sprite := Sprite2D.new()
	var sprite_options := EditorAssetImport.prepare_placement_options(sprite, {"material_color": {"r": 1.0, "g": 0.5, "b": 0.0}})
	_assert_true(bool(sprite_options.get("ok", false)), "sprite material option accepted")
	_assert_eq((((sprite_options.get("summary", {}) as Dictionary).get("material_color", {}) as Dictionary).get("target")), "canvas_item_modulate", "sprite material option targets modulate")
	sprite.free()
	var bad_node := Node3D.new()
	var bad_color := EditorAssetImport.prepare_placement_options(bad_node, {"material_color": {"r": 2.0}})
	_assert_false(bool(bad_color.get("ok", true)), "invalid material color rejected")
	bad_node.free()

	var ctx := BridgeContext.new()
	ctx.permissions = {"allow_editor_diagnostics": false, "allow_scene_edits": false}
	var service := EditorAssetImport.new(ctx)
	var denied_inspect := service.inspect_imported_assets({})
	_assert_false(bool(denied_inspect.get("ok", true)), "inspect imported assets denied when permission disabled")
	_assert_eq(((denied_inspect.get("error", {}) as Dictionary).get("code")), "permission_denied", "inspect permission error code")
	var denied_place := service.place_asset_in_scene({})
	_assert_false(bool(denied_place.get("ok", true)), "place asset denied when permission disabled")
	_assert_eq(((denied_place.get("error", {}) as Dictionary).get("code")), "permission_denied", "place permission error code")
	root.free()


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
