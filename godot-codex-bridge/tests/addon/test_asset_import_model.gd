extends SceneTree

const AssetImportModel := preload("res://addons/godot_codex_bridge/core/asset_import_model.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge asset import model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge asset import model tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	_assert_true(".glb" in AssetImportModel.default_import_asset_extensions(), "Default import extensions include glb")
	_assert_true(".tscn" in AssetImportModel.placeable_asset_extensions(), "Placeable extensions include tscn")
	_assert_true(".png" in AssetImportModel.placeable_asset_extensions(), "Placeable extensions include png")

	_assert_eq(AssetImportModel.path_extension("res://assets/Tree.GLTF"), ".gltf", "Path extension lowercases")
	_assert_eq(AssetImportModel.default_node_name("res://assets/oak-tree.glb", "packed_scene_instance"), "oak_tree", "Default node name normalizes")
	_assert_eq(AssetImportModel.default_node_name("res://.mesh", "mesh_instance"), ".mesh", "Default node name preserves dotfile basename")

	_assert_eq(AssetImportModel.placeable_kind("res://scenes/Tree.tscn", "PackedScene"), "packed_scene", "PackedScene kind")
	_assert_eq(AssetImportModel.placeable_kind("res://meshes/rock.mesh", "ArrayMesh"), "mesh", "Mesh kind")
	_assert_eq(AssetImportModel.placeable_kind("res://models/tree.glb", ""), "imported_scene_candidate", "glb candidate kind")
	_assert_eq(AssetImportModel.placeable_kind("res://models/rock.obj", ""), "imported_mesh_candidate", "obj candidate kind")
	_assert_eq(AssetImportModel.placeable_kind("res://textures/tree.png", ""), "texture_2d", "png texture kind")
	_assert_eq(AssetImportModel.placeable_kind("res://materials/rock.tres", ""), "resource_candidate", "tres candidate kind")
	_assert_eq(AssetImportModel.placeable_kind("res://notes/readme.md", ""), "unsupported", "Unsupported kind")

	var resource_payload := AssetImportModel.imported_asset_payload_from_resource({
		"path": "res://models/tree.glb",
		"type": "",
		"import_valid": false,
		"status": "import_error",
	}, false, 4, 128)
	_assert_eq(resource_payload.get("file"), "tree.glb", "Imported payload file")
	_assert_eq(resource_payload.get("placeable_kind"), "imported_scene_candidate", "Imported payload kind")
	_assert_eq(resource_payload.get("placeable"), true, "Imported payload placeable")
	_assert_eq(resource_payload.get("status"), "import_error", "Imported payload status")

	var mesh := BoxMesh.new()
	mesh.resource_name = "TestBox"
	var mesh_node_result := AssetImportModel.create_node_for_loaded_asset("res://meshes/box.mesh", mesh)
	_assert_true(mesh_node_result.get("ok", false), "Mesh asset creates node")
	_assert_true(mesh_node_result.get("node") is MeshInstance3D, "Mesh asset node type")
	_assert_eq(mesh_node_result.get("placement_kind"), "mesh_instance", "Mesh placement kind")
	(mesh_node_result.get("node") as Node).free()

	var image := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 1))
	var texture := ImageTexture.create_from_image(image)
	texture.resource_name = "TestTexture"
	var texture_node_result := AssetImportModel.create_node_for_loaded_asset("res://textures/tree.png", texture)
	_assert_true(texture_node_result.get("ok", false), "Texture2D asset creates node")
	_assert_true(texture_node_result.get("node") is Sprite2D, "Texture2D asset node type")
	_assert_eq(texture_node_result.get("placement_kind"), "sprite_2d", "Texture2D placement kind")
	(texture_node_result.get("node") as Node).free()

	var root := Node3D.new()
	root.name = "PackedRoot"
	var packed := PackedScene.new()
	var pack_result := packed.pack(root)
	_assert_eq(pack_result, OK, "PackedScene packs test root")
	var packed_node_result := AssetImportModel.create_node_for_loaded_asset("res://scenes/PackedRoot.tscn", packed)
	_assert_true(packed_node_result.get("ok", false), "PackedScene asset creates node")
	_assert_true(packed_node_result.get("node") is Node3D, "PackedScene asset node type")
	_assert_eq((packed_node_result.get("node") as Node).name, "PackedRoot", "PackedScene instantiated node name")
	(packed_node_result.get("node") as Node).free()
	root.free()

	var material := StandardMaterial3D.new()
	var unsupported_result := AssetImportModel.create_node_for_loaded_asset("res://materials/mat.tres", material)
	_assert_eq(unsupported_result.get("ok"), false, "Unsupported Resource rejects")
	_assert_eq((unsupported_result.get("error") as Dictionary).get("code"), "unsupported_asset_type", "Unsupported Resource code")

	var mesh_metadata := AssetImportModel.asset_metadata_for_loaded("res://meshes/box.mesh", mesh)
	_assert_eq(mesh_metadata.get("placeable_kind"), "mesh", "Mesh metadata kind")
	_assert_eq((mesh_metadata.get("resource") as Dictionary).get("resource_name"), "TestBox", "Mesh metadata resource reference")

	var texture_metadata := AssetImportModel.asset_metadata_for_loaded("res://textures/tree.png", texture)
	_assert_eq(texture_metadata.get("placeable_kind"), "texture_2d", "Texture2D metadata kind")

	_assert_eq(AssetImportModel.is_script_resource_path("res://scripts/player.gd", ""), true, "Script path detection")
	_assert_eq(AssetImportModel.import_is_valid("res://missing/model.glb", ""), false, "Missing imported source invalid")


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures += 1
		push_error(label + " expected=" + str(expected) + " actual=" + str(actual))


func _assert_true(value: bool, label: String) -> void:
	if not value:
		_failures += 1
		push_error(label)
