@tool
extends RefCounted

const VariantCodec := preload("variant_codec.gd")


static func collect_animation_players(node: Node, scene_root: Node, players: Array, state: Dictionary, limit: int, include_empty: bool, max_animations_per_player: int) -> void:
	state["visited"] = int(state.get("visited", 0)) + 1
	if node is AnimationPlayer:
		var player := node as AnimationPlayer
		var animation_count := _packed_string_array_to_array(player.get_animation_list()).size()
		if include_empty or animation_count > 0:
			state["matched"] = int(state.get("matched", 0)) + 1
			if players.size() < limit:
				players.append(player_payload(player, scene_root, true, max_animations_per_player))
			else:
				state["truncated"] = true
	for child in node.get_children():
		if players.size() >= limit:
			state["truncated"] = true
			return
		if child is Node:
			collect_animation_players(child as Node, scene_root, players, state, limit, include_empty, max_animations_per_player)


static func resolve_player_animation(player: AnimationPlayer, animation_name: String) -> Dictionary:
	if animation_name == "":
		return _err("invalid_animation_name", "animationName is required.")
	if not player.has_animation(StringName(animation_name)):
		return _err("animation_not_found", "AnimationPlayer does not contain animation: " + animation_name)
	var animation: Animation = player.get_animation(StringName(animation_name))
	if animation == null:
		return _err("animation_unavailable", "Animation exists but could not be loaded: " + animation_name)
	return {
		"ok": true,
		"animation": animation,
	}


static func player_payload(player: AnimationPlayer, scene_root: Node, include_animations: bool, max_animations_per_player: int) -> Dictionary:
	var animation_names := _packed_string_array_to_array(player.get_animation_list())
	var libraries: Array = []
	for library_key in player.get_animation_library_list():
		var key := str(library_key)
		var library: AnimationLibrary = player.get_animation_library(StringName(key))
		libraries.append({
			"key": key,
			"animation_count": library.get_animation_list_size() if library != null else 0,
			"resource": VariantCodec.resource_reference(library),
		})
	var current_animation_name := str(player.current_animation)
	var current_position := 0.0
	var current_length := 0.0
	if current_animation_name != "":
		current_position = player.current_animation_position
		current_length = player.current_animation_length
	var payload := {
		"node": node_ref_payload(player, scene_root),
		"root_node": str(player.get_root()),
		"is_playing": player.is_playing(),
		"is_animation_active": player.is_animation_active(),
		"current_animation": current_animation_name,
		"assigned_animation": str(player.assigned_animation),
		"autoplay": str(player.autoplay),
		"current_position": current_position,
		"current_length": current_length,
		"speed_scale": player.speed_scale,
		"animation_count": animation_names.size(),
		"libraries": libraries,
		"animations_truncated": animation_names.size() > max_animations_per_player,
	}
	if include_animations:
		var animations: Array = []
		var count: int = min(animation_names.size(), max_animations_per_player)
		for index in range(count):
			var animation_name := str(animation_names[index])
			var animation: Animation = player.get_animation(StringName(animation_name))
			if animation != null:
				animations.append(animation_summary_payload(animation_name, animation))
		payload["animations"] = animations
	return payload


static func animation_summary_payload(animation_name: String, animation: Animation) -> Dictionary:
	return {
		"name": animation_name,
		"length": animation.length,
		"step": animation.step,
		"loop_mode": int(animation.loop_mode),
		"track_count": animation.get_track_count(),
		"resource": VariantCodec.resource_reference(animation),
	}


static func animation_detail_payload(
	animation_name: String,
	animation: Animation,
	include_keys: bool,
	max_tracks: int,
	max_keys_per_track: int,
	max_string_length: int,
	max_property_depth: int,
	max_array_items: int,
	max_dictionary_items: int
) -> Dictionary:
	var tracks: Array = []
	var track_count := animation.get_track_count()
	var count: int = min(track_count, max_tracks)
	for index in range(count):
		tracks.append(animation_track_payload(animation, index, include_keys, max_keys_per_track, max_property_depth, max_array_items, max_dictionary_items))
	return {
		"name": animation_name,
		"length": animation.length,
		"step": animation.step,
		"loop_mode": int(animation.loop_mode),
		"track_count": track_count,
		"tracks": tracks,
		"tracks_truncated": track_count > max_tracks,
		"limits": {
			"max_tracks": max_tracks,
			"max_keys_per_track": max_keys_per_track,
			"max_string_length": max_string_length,
		},
		"resource": VariantCodec.resource_reference(animation),
	}


static func animation_track_payload(
	animation: Animation,
	track_index: int,
	include_keys: bool,
	max_keys: int,
	max_property_depth: int,
	max_array_items: int,
	max_dictionary_items: int
) -> Dictionary:
	var track_type := int(animation.track_get_type(track_index))
	var key_count := animation.track_get_key_count(track_index)
	var payload := {
		"index": track_index,
		"type": track_type,
		"type_name": animation_track_type_name(track_type),
		"path": str(animation.track_get_path(track_index)),
		"enabled": animation.track_is_enabled(track_index),
		"imported": animation.track_is_imported(track_index),
		"compressed": animation.track_is_compressed(track_index),
		"interpolation_type": int(animation.track_get_interpolation_type(track_index)),
		"loop_wrap": animation.track_get_interpolation_loop_wrap(track_index),
		"key_count": key_count,
		"keys_truncated": key_count > max_keys,
	}
	if include_keys:
		var keys: Array = []
		var count: int = min(key_count, max_keys)
		for key_index in range(count):
			keys.append(animation_key_payload(animation, track_index, key_index, max_property_depth, max_array_items, max_dictionary_items))
		payload["keys"] = keys
	return payload


static func animation_key_payload(animation: Animation, track_index: int, key_index: int, max_property_depth: int, max_array_items: int, max_dictionary_items: int) -> Dictionary:
	return {
		"index": key_index,
		"time": animation.track_get_key_time(track_index, key_index),
		"transition": animation.track_get_key_transition(track_index, key_index),
		"value": VariantCodec.variant_to_json_value(animation.track_get_key_value(track_index, key_index), 0, max_property_depth, max_array_items, max_dictionary_items),
	}


static func animation_track_type_name(track_type: int) -> String:
	match track_type:
		Animation.TYPE_VALUE:
			return "value"
		Animation.TYPE_POSITION_3D:
			return "position_3d"
		Animation.TYPE_ROTATION_3D:
			return "rotation_3d"
		Animation.TYPE_SCALE_3D:
			return "scale_3d"
		Animation.TYPE_BLEND_SHAPE:
			return "blend_shape"
		Animation.TYPE_METHOD:
			return "method"
		Animation.TYPE_BEZIER:
			return "bezier"
		Animation.TYPE_AUDIO:
			return "audio"
		Animation.TYPE_ANIMATION:
			return "animation"
		_:
			return "unknown"


static func sanitize_animation_key(value: String) -> String:
	var key := value.strip_edges()
	if key == "" or key.length() > 120 or key.find("\n") >= 0 or key.find("\r") >= 0 or key.find("/") >= 0 or key.find("\\") >= 0:
		return ""
	return key


static func sanitize_animation_library_key(value: String) -> String:
	var key := value.strip_edges()
	if key.length() > 120 or key.find("\n") >= 0 or key.find("\r") >= 0 or key.find("\\") >= 0:
		return ""
	return key


static func validate_animation_track_path(track_path: String) -> Dictionary:
	if track_path == "" or track_path.length() > 400 or track_path.find("\n") >= 0 or track_path.find("\r") >= 0:
		return _error_payload("invalid_animation_track_path", "Track path is required and must not contain newlines.")
	if track_path.begins_with("res://") or track_path.find("..") >= 0:
		return _error_payload("invalid_animation_track_path", "Track path must be scene-local and must not contain traversal.")
	if track_path.find(":") < 0:
		return _error_payload("invalid_animation_track_path", "V1 animation track paths must include a property separator, for example MeshInstance3D:position.")
	return {}


static func populate_initial_tracks(animation: Animation, tracks_value: Variant, max_initial_tracks: int, max_keys_per_track: int) -> Dictionary:
	if tracks_value == null:
		return _ok({"track_count": 0})
	if typeof(tracks_value) != TYPE_ARRAY:
		return _err("invalid_animation_tracks", "tracks must be an array.")
	var tracks: Array = tracks_value
	if tracks.size() > max_initial_tracks:
		return _err("too_many_animation_tracks", "create_animation_clip supports at most " + str(max_initial_tracks) + " initial tracks.")
	for item in tracks:
		if typeof(item) != TYPE_DICTIONARY:
			return _err("invalid_animation_track", "Each animation track must be an object.")
		var track: Dictionary = item
		var track_type := str(track.get("type", "value")).strip_edges().to_lower()
		if track_type != "value":
			return _err("unsupported_animation_track_type", "V1 create_animation_clip supports only value tracks.")
		var track_path := str(track.get("path", "")).strip_edges()
		var path_error := validate_animation_track_path(track_path)
		if not path_error.is_empty():
			return {"ok": false, "error": path_error}
		var keys_value: Variant = track.get("keys", [])
		if typeof(keys_value) != TYPE_ARRAY:
			return _err("invalid_animation_keys", "Track keys must be an array.")
		var keys: Array = keys_value
		if keys.is_empty():
			return _err("invalid_animation_keys", "Each V1 animation track requires at least one key.")
		if keys.size() > max_keys_per_track:
			return _err("too_many_animation_keys", "Each V1 animation track supports at most " + str(max_keys_per_track) + " keys.")
		var track_index := animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(track_index, NodePath(track_path))
		if track.has("interpolation_type") or track.has("interpolationType"):
			animation.track_set_interpolation_type(track_index, clampi(int(track.get("interpolation_type", track.get("interpolationType", Animation.INTERPOLATION_LINEAR))), 0, 2))
		var value_type := str(track.get("value_type", track.get("valueType", "variant"))).strip_edges().to_lower()
		for key_item in keys:
			if typeof(key_item) != TYPE_DICTIONARY:
				return _err("invalid_animation_key", "Each animation key must be an object.")
			var key: Dictionary = key_item
			var value_result := animation_key_value_from_payload(value_type, key.get("value"))
			if not value_result.get("ok", false):
				return value_result
			var key_time := clampf(float(key.get("time", 0.0)), 0.0, animation.length)
			var transition := clampf(float(key.get("transition", 1.0)), -1024.0, 1024.0)
			animation.track_insert_key(track_index, key_time, VariantCodec.coerced_value(value_result), transition)
	return _ok({"track_count": tracks.size()})


static func animation_key_value_from_payload(value_type: String, raw_value: Variant) -> Dictionary:
	match value_type:
		"bool":
			if typeof(raw_value) != TYPE_BOOL:
				return _err("invalid_animation_key_value", "Expected bool animation key value.")
			return _ok({"value": raw_value})
		"int":
			if typeof(raw_value) != TYPE_INT and typeof(raw_value) != TYPE_FLOAT:
				return _err("invalid_animation_key_value", "Expected numeric animation key value.")
			return _ok({"value": int(raw_value)})
		"float":
			if typeof(raw_value) != TYPE_INT and typeof(raw_value) != TYPE_FLOAT:
				return _err("invalid_animation_key_value", "Expected numeric animation key value.")
			return _ok({"value": float(raw_value)})
		"string":
			if typeof(raw_value) != TYPE_STRING:
				return _err("invalid_animation_key_value", "Expected string animation key value.")
			return _ok({"value": str(raw_value)})
		"vector2":
			return VariantCodec.vector2_from_payload(raw_value)
		"vector3":
			return VariantCodec.vector3_from_payload(raw_value)
		"color":
			return VariantCodec.color_from_payload(raw_value)
		"variant":
			if typeof(raw_value) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
				return _ok({"value": raw_value})
			return _err("invalid_animation_key_value", "V1 variant animation keys support only bool, int, float and string. Use valueType for Vector2, Vector3 or Color.")
		_:
			return _err("unsupported_animation_key_value_type", "Unsupported animation key valueType: " + value_type)


static func node_ref_payload(node: Node, scene_root: Node) -> Dictionary:
	return {
		"path": scene_path_for(node, scene_root),
		"name": node.name,
		"type": node.get_class(),
	}


static func scene_path_for(node: Node, scene_root: Node) -> String:
	if node == null:
		return ""
	if scene_root == null:
		return str(node.get_path())
	if node == scene_root:
		return "."
	if scene_root.is_ancestor_of(node):
		return str(scene_root.get_path_to(node))
	return str(node.get_path())


static func _packed_string_array_to_array(value: Variant) -> Array:
	var result: Array = []
	if value is PackedStringArray:
		for item in value:
			result.append(str(item))
	elif value is Array:
		for item in value:
			result.append(str(item))
	return result


static func _ok(data: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"data": data,
	}


static func _err(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"error": _error_payload(code, message),
	}


static func _error_payload(code: String, message: String) -> Dictionary:
	return {
		"code": code,
		"message": message,
	}
