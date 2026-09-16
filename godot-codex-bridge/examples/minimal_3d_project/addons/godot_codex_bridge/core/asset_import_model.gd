@tool
extends RefCounted

const VariantCodec := preload("variant_codec.gd")


static func default_import_asset_extensions() -> Array:
	return [
		".glb",
		".gltf",
		".obj",
		".fbx",
		".dae",
		".blend",
		".mesh",
		".res",
		".tres",
		".tscn",
		".scn",
		".png",
		".jpg",
		".jpeg",
		".webp",
		".svg",
		".gdshader",
		".wav",
		".ogg",
		".mp3",
	]


static func placeable_asset_extensions() -> Array:
	return [
		".glb",
		".gltf",
		".obj",
		".fbx",
		".dae",
		".blend",
		".mesh",
		".res",
		".tres",
		".tscn",
		".scn",
		".png",
	]


static func imported_asset_payload_from_resource(resource: Dictionary, include_dependencies: bool, max_dependencies: int, max_string_length: int) -> Dictionary:
	var file_path := str(resource.get("path", ""))
	var file_type := str(resource.get("type", ""))
	var import_valid := bool(resource.get("import_valid", true))
	var kind := placeable_kind(file_path, file_type)
	var payload := {
		"path": file_path,
		"file": file_path.get_file(),
		"extension": path_extension(file_path),
		"type": file_type,
		"import_valid": import_valid,
		"status": str(resource.get("status", "ok" if import_valid else "import_error")),
		"loadable": ResourceLoader.exists(file_path),
		"placeable": kind != "unsupported",
		"placeable_kind": kind,
	}
	if include_dependencies:
		payload["dependencies"] = resource_dependencies_payload(file_path, max_dependencies, max_string_length)
	return payload


static func asset_metadata_for_loaded(asset_path: String, loaded: Variant) -> Dictionary:
	var resource := loaded as Resource
	var payload := {
		"path": asset_path,
		"type": resource.get_class() if resource != null else type_string(typeof(loaded)),
		"resource": VariantCodec.resource_reference(loaded),
		"loadable": resource != null,
		"placeable_kind": "unsupported",
	}
	if loaded is PackedScene:
		payload["placeable_kind"] = "packed_scene"
		payload["can_instantiate"] = (loaded as PackedScene).can_instantiate()
	elif loaded is Mesh:
		payload["placeable_kind"] = "mesh"
	elif loaded is Texture2D:
		payload["placeable_kind"] = "texture_2d"
	return payload


static func create_node_for_loaded_asset(asset_path: String, loaded: Variant) -> Dictionary:
	if not (loaded is Resource):
		return _err("asset_load_failed", "Asset did not load as a Godot Resource: " + asset_path)
	if loaded is PackedScene:
		var packed := loaded as PackedScene
		if not packed.can_instantiate():
			return _err("asset_cannot_instantiate", "PackedScene asset cannot instantiate nodes: " + asset_path)
		return {
			"ok": true,
			"node": packed.instantiate(),
			"placement_kind": "packed_scene_instance",
		}
	if loaded is Mesh:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = loaded as Mesh
		return {
			"ok": true,
			"node": mesh_instance,
			"placement_kind": "mesh_instance",
		}
	if loaded is Texture2D:
		var sprite := Sprite2D.new()
		sprite.texture = loaded as Texture2D
		return {
			"ok": true,
			"node": sprite,
			"placement_kind": "sprite_2d",
		}
	return _err("unsupported_asset_type", "V1 can place only PackedScene, Mesh or Texture2D assets. Loaded type: " + (loaded as Resource).get_class())


static func default_node_name(asset_path: String, placement_kind: String) -> String:
	var file_name := asset_path.get_file()
	var dot_index := file_name.rfind(".")
	if dot_index > 0:
		file_name = file_name.substr(0, dot_index)
	file_name = file_name.replace("-", "_").replace(" ", "_")
	if file_name.strip_edges() != "":
		return file_name
	if placement_kind == "mesh_instance":
		return "PlacedMesh"
	return "PlacedAsset"


static func placeable_kind(file_path: String, file_type: String) -> String:
	var lower_path := file_path.to_lower()
	var lower_type := file_type.to_lower()
	if lower_type == "packedscene" or lower_type == "packed_scene" or lower_path.ends_with(".tscn") or lower_path.ends_with(".scn"):
		return "packed_scene"
	if lower_type.find("mesh") >= 0 or lower_path.ends_with(".mesh"):
		return "mesh"
	if lower_type.find("texture2d") >= 0 or lower_type.find("texture") >= 0 or lower_path.ends_with(".png"):
		return "texture_2d"
	if lower_path.ends_with(".glb") or lower_path.ends_with(".gltf") or lower_path.ends_with(".fbx") or lower_path.ends_with(".dae") or lower_path.ends_with(".blend"):
		return "imported_scene_candidate"
	if lower_path.ends_with(".obj"):
		return "imported_mesh_candidate"
	if lower_path.ends_with(".res") or lower_path.ends_with(".tres"):
		return "resource_candidate"
	return "unsupported"


static func resource_dependencies_payload(resource_path: String, max_dependencies: int, max_string_length: int) -> Array:
	var dependencies: Array = []
	if not ResourceLoader.exists(resource_path):
		return dependencies
	var raw_dependencies := ResourceLoader.get_dependencies(resource_path)
	var count: int = min(raw_dependencies.size(), max_dependencies)
	for index in range(count):
		dependencies.append(VariantCodec.truncate_string(str(raw_dependencies[index]), max_string_length))
	return dependencies


static func is_script_resource_path(file_path: String, file_type: String) -> bool:
	var lower_path := file_path.to_lower()
	var lower_type := file_type.to_lower()
	return (
		lower_type.find("script") >= 0
		or lower_path.ends_with(".gd")
		or lower_path.ends_with(".cs")
		or lower_path.ends_with(".gdshader")
		or lower_path.ends_with(".shader")
	)


static func import_is_valid(file_path: String, file_type: String) -> bool:
	var lower_path := file_path.to_lower()
	var lower_type := file_type.to_lower()
	var imported_source := (
		lower_path.ends_with(".glb")
		or lower_path.ends_with(".gltf")
		or lower_path.ends_with(".obj")
		or lower_path.ends_with(".fbx")
		or lower_path.ends_with(".dae")
		or lower_path.ends_with(".blend")
		or lower_path.ends_with(".png")
		or lower_path.ends_with(".jpg")
		or lower_path.ends_with(".jpeg")
		or lower_path.ends_with(".webp")
		or lower_path.ends_with(".svg")
		or lower_path.ends_with(".wav")
		or lower_path.ends_with(".ogg")
		or lower_path.ends_with(".mp3")
	)
	if imported_source:
		return FileAccess.file_exists(ProjectSettings.globalize_path(file_path + ".import"))
	if lower_type == "":
		return FileAccess.file_exists(ProjectSettings.globalize_path(file_path))
	return true


static func path_extension(path_value: String) -> String:
	var file_name := path_value.get_file()
	var dot_index := file_name.rfind(".")
	if dot_index < 0:
		return ""
	return file_name.substr(dot_index).to_lower()


static func _err(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"error": {
			"code": code,
			"message": message,
		},
	}
