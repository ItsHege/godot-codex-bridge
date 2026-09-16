@tool
extends RefCounted

const AnimationModel := preload("animation_model.gd")
const BridgeContext := preload("bridge_context.gd")
const BridgeLimits := preload("bridge_limits.gd")
const EditorPathGuard := preload("editor_path_guard.gd")

var _context: BridgeContext


func _init(context: BridgeContext = null) -> void:
	_context = context


func list_animation_players(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_editor_inspect"):
		return _err("permission_denied", "Inspect/select nodes permission is disabled in the Codex Bridge dock.")

	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return _err("no_current_scene", "No edited scene is open.")
	var max_players := clampi(int(params.get("max_players", params.get("maxPlayers", BridgeLimits.MAX_ANIMATION_PLAYERS))), 1, BridgeLimits.MAX_ANIMATION_PLAYERS)
	var include_empty := bool(params.get("include_empty", params.get("includeEmpty", true)))
	var players: Array = []
	var state := {
		"visited": 0,
		"matched": 0,
		"truncated": false,
	}
	AnimationModel.collect_animation_players(scene_root, scene_root, players, state, max_players, include_empty, BridgeLimits.MAX_ANIMATIONS_PER_PLAYER)
	return _ok({
		"captured_at": _timestamp(),
		"players": players,
		"returned_count": players.size(),
		"matched_count": int(state.get("matched", 0)),
		"visited_count": int(state.get("visited", 0)),
		"truncated": bool(state.get("truncated", false)),
		"snapshot_refreshed": false,
	})


func inspect_animation(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_editor_inspect"):
		return _err("permission_denied", "Inspect/select nodes permission is disabled in the Codex Bridge dock.")

	var player_result := resolve_animation_player(str(params.get("node_path", params.get("nodePath", ""))).strip_edges())
	if not player_result.get("ok", false):
		return player_result
	var player: AnimationPlayer = player_result.get("player", null)
	var scene_root: Node = player_result.get("scene_root", null)
	var animation_name := str(params.get("animation_name", params.get("animationName", ""))).strip_edges()
	var include_keys := bool(params.get("include_keys", params.get("includeKeys", true)))
	var max_tracks := clampi(int(params.get("max_tracks", params.get("maxTracks", BridgeLimits.MAX_ANIMATION_TRACKS))), 1, BridgeLimits.MAX_ANIMATION_TRACKS)
	var max_keys_per_track := clampi(int(params.get("max_keys_per_track", params.get("maxKeysPerTrack", BridgeLimits.MAX_ANIMATION_KEYS_PER_TRACK))), 0, BridgeLimits.MAX_ANIMATION_KEYS_PER_TRACK)
	if animation_name == "":
		return _ok({
			"player": AnimationModel.player_payload(player, scene_root, true, BridgeLimits.MAX_ANIMATIONS_PER_PLAYER),
			"snapshot_refreshed": false,
		})
	var animation_result := AnimationModel.resolve_player_animation(player, animation_name)
	if not animation_result.get("ok", false):
		return animation_result
	var animation: Animation = animation_result.get("animation", null)
	return _ok({
		"player": AnimationModel.player_payload(player, scene_root, false, BridgeLimits.MAX_ANIMATIONS_PER_PLAYER),
		"animation": AnimationModel.animation_detail_payload(
			animation_name,
			animation,
			include_keys,
			max_tracks,
			max_keys_per_track,
			BridgeLimits.MAX_STRING_LENGTH,
			BridgeLimits.MAX_PROPERTY_DEPTH,
			BridgeLimits.MAX_ARRAY_ITEMS,
			BridgeLimits.MAX_DICTIONARY_ITEMS
		),
		"snapshot_refreshed": false,
	})


func preview_animation(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_animation_preview"):
		return _err("permission_denied", "Animation preview permission is disabled in the Codex Bridge dock.")

	var player_result := resolve_animation_player(str(params.get("node_path", params.get("nodePath", ""))).strip_edges())
	if not player_result.get("ok", false):
		return player_result
	var player: AnimationPlayer = player_result.get("player", null)
	var scene_root: Node = player_result.get("scene_root", null)
	var animation_name := str(params.get("animation_name", params.get("animationName", ""))).strip_edges()
	var animation_result := AnimationModel.resolve_player_animation(player, animation_name)
	if not animation_result.get("ok", false):
		return animation_result
	var animation: Animation = animation_result.get("animation", null)
	var mode := str(params.get("mode", "seek")).strip_edges().to_lower()
	var position := clampf(float(params.get("position", 0.0)), 0.0, max(0.0, float(animation.length)))
	var speed := clampf(float(params.get("speed", 1.0)), -8.0, 8.0)
	if mode == "seek":
		player.play(StringName(animation_name), -1.0, 0.0, false)
		player.seek(position, true, true)
		player.pause()
	elif mode == "play":
		player.play(StringName(animation_name), float(params.get("custom_blend", params.get("customBlend", -1.0))), speed, bool(params.get("from_end", params.get("fromEnd", false))))
		if player.has_method("advance"):
			player.call("advance", 0.0)
	elif mode == "pause":
		player.pause()
	else:
		return _err("invalid_animation_preview_mode", "mode must be seek, play or pause.")
	var snapshot := _refresh("editor_control:preview_animation")
	var data := {
		"changed": false,
		"auto_saved": false,
		"preview_only": true,
		"player": AnimationModel.node_ref_payload(player, scene_root),
		"animation_name": animation_name,
		"mode": mode,
		"position": player.current_animation_position,
		"is_playing": player.is_playing(),
		"snapshot_refreshed": true,
		"generated_at": snapshot.get("generated_at", ""),
	}
	_log("editor_animation_previewed", data)
	return _ok(data)


func stop_animation_preview(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_animation_preview"):
		return _err("permission_denied", "Animation preview permission is disabled in the Codex Bridge dock.")

	var player_result := resolve_animation_player(str(params.get("node_path", params.get("nodePath", ""))).strip_edges())
	if not player_result.get("ok", false):
		return player_result
	var player: AnimationPlayer = player_result.get("player", null)
	var scene_root: Node = player_result.get("scene_root", null)
	var keep_state := bool(params.get("keep_state", params.get("keepState", true)))
	player.stop(keep_state)
	var snapshot := _refresh("editor_control:stop_animation_preview")
	var data := {
		"changed": false,
		"auto_saved": false,
		"preview_only": true,
		"player": AnimationModel.node_ref_payload(player, scene_root),
		"keep_state": keep_state,
		"is_playing": player.is_playing(),
		"snapshot_refreshed": true,
		"generated_at": snapshot.get("generated_at", ""),
	}
	_log("editor_animation_preview_stopped", data)
	return _ok(data)


func create_animation_clip(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_scene_edits"):
		return _err("permission_denied", "Scene edits via UndoRedo permission is disabled in the Codex Bridge dock.")

	var player_result := resolve_animation_player(str(params.get("node_path", params.get("nodePath", ""))).strip_edges())
	if not player_result.get("ok", false):
		return player_result
	var player: AnimationPlayer = player_result.get("player", null)
	var scene_root: Node = player_result.get("scene_root", null)
	var animation_name := AnimationModel.sanitize_animation_key(str(params.get("animation_name", params.get("animationName", ""))).strip_edges())
	if animation_name == "":
		return _err("invalid_animation_name", "animationName is required and must be a simple animation key.")
	var library_key := AnimationModel.sanitize_animation_library_key(str(params.get("library_key", params.get("libraryKey", ""))).strip_edges())
	if library_key.find("/") >= 0:
		return _err("invalid_animation_library", "libraryKey must not contain '/'.")
	var library: AnimationLibrary = player.get_animation_library(StringName(library_key))
	var library_existed := library != null
	if library == null:
		library = AnimationLibrary.new()
	if library.has_animation(StringName(animation_name)):
		return _err("animation_exists", "Animation already exists in library: " + animation_name)

	var animation := Animation.new()
	animation.length = clampf(float(params.get("length", 1.0)), 0.001, 3600.0)
	animation.step = clampf(float(params.get("step", 0.033333335)), 0.001, 10.0)
	animation.loop_mode = clampi(int(params.get("loop_mode", params.get("loopMode", Animation.LOOP_NONE))), 0, 2)
	var tracks_result := AnimationModel.populate_initial_tracks(animation, params.get("tracks", []), BridgeLimits.MAX_ANIMATION_INITIAL_TRACKS, BridgeLimits.MAX_ANIMATION_KEYS_PER_TRACK)
	if not tracks_result.get("ok", false):
		return tracks_result

	var undo := _undo_redo()
	if undo == null:
		return _err("undo_redo_unavailable", "Editor UndoRedo manager is unavailable.")
	undo.create_action("Godot Codex Bridge: create animation clip")
	if not library_existed:
		undo.add_do_method(player, "add_animation_library", StringName(library_key), library)
		undo.add_undo_method(player, "remove_animation_library", StringName(library_key))
	undo.add_do_method(library, "add_animation", StringName(animation_name), animation)
	if library_existed:
		undo.add_undo_method(library, "remove_animation", StringName(animation_name))
	undo.commit_action()

	select_single_node(player)
	var snapshot := _refresh("editor_control:create_animation_clip")
	var data := {
		"changed": true,
		"undo_redo_action": true,
		"auto_saved": false,
		"player": AnimationModel.node_ref_payload(player, scene_root),
		"animation_name": animation_name,
		"library_key": library_key,
		"library_created": not library_existed,
		"animation": AnimationModel.animation_detail_payload(
			animation_name,
			animation,
			true,
			BridgeLimits.MAX_ANIMATION_TRACKS,
			BridgeLimits.MAX_ANIMATION_KEYS_PER_TRACK,
			BridgeLimits.MAX_STRING_LENGTH,
			BridgeLimits.MAX_PROPERTY_DEPTH,
			BridgeLimits.MAX_ARRAY_ITEMS,
			BridgeLimits.MAX_DICTIONARY_ITEMS
		),
		"snapshot_refreshed": true,
		"generated_at": snapshot.get("generated_at", ""),
	}
	_log("editor_animation_clip_created", data)
	return _ok(data)


func resolve_animation_player(node_path: String) -> Dictionary:
	var node_result := _resolve_editor_node(node_path)
	if not node_result.get("ok", false):
		return node_result
	var node: Node = node_result.get("node", null)
	if not (node is AnimationPlayer):
		return _err("not_animation_player", "Node is not an AnimationPlayer: " + node_path)
	return {
		"ok": true,
		"player": node as AnimationPlayer,
		"scene_root": node_result.get("scene_root", null),
	}


static func select_single_node(node: Node) -> void:
	if node == null:
		return
	var selection := EditorInterface.get_selection()
	if selection != null:
		selection.clear()
		selection.add_node(node)
	EditorInterface.edit_node(node)


func _resolve_editor_node(node_path: String) -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return _err("no_current_scene", "No edited scene is open.")
	if node_path == "" or node_path == ".":
		return {
			"ok": true,
			"node": scene_root,
			"scene_root": scene_root,
		}
	var path_error := EditorPathGuard.validate_scene_local_node_path(node_path)
	if not path_error.is_empty():
		return _err(str(path_error.get("code", "invalid_node_path")), str(path_error.get("message", "")))

	var node: Node = null
	if node_path.begins_with("/"):
		var tree := Engine.get_main_loop() as SceneTree
		if tree == null:
			return _err("scene_tree_unavailable", "Godot SceneTree is unavailable.")
		node = tree.root.get_node_or_null(NodePath(node_path))
	else:
		node = scene_root.get_node_or_null(NodePath(node_path))
	if node == null:
		return _err("node_not_found", "Node not found in the edited scene: " + node_path)
	if node != scene_root and not scene_root.is_ancestor_of(node):
		return _err("node_outside_scene", "Resolved node is outside the edited scene.")
	return {
		"ok": true,
		"node": node,
		"scene_root": scene_root,
	}


func _undo_redo() -> EditorUndoRedoManager:
	return _context.undo_redo if _context != null else null


func _permission_enabled(key: String) -> bool:
	return _context.permission_enabled(key) if _context != null else false


func _refresh(reason: String) -> Dictionary:
	return _context.refresh(reason) if _context != null else {}


func _log(event_name: String, data: Dictionary) -> void:
	if _context != null:
		_context.log(event_name, data)


func _timestamp() -> String:
	return _context.timestamp_iso() if _context != null else Time.get_datetime_string_from_system(true, true)


func _ok(data: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"data": data,
	}


func _err(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"error": _error_payload(code, message),
	}


func _error_payload(code: String, message: String) -> Dictionary:
	if _context != null:
		return _context.err(code, message)
	return {
		"code": code,
		"message": message,
	}
