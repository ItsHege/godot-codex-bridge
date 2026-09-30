@tool
extends RefCounted

const AnimationModel := preload("animation_model.gd")
const BridgeContext := preload("bridge_context.gd")
const BridgeLimits := preload("bridge_limits.gd")
const EditorPathGuard := preload("editor_path_guard.gd")

const MAX_PREVIEW_BACKUP_ENTRIES := 512

var _context: BridgeContext
## Original property values captured before an animation preview touched them,
## keyed by AnimationPlayer instance id: {player, entries: [{object, property,
## value}], keys: {}}. Previews run outside UndoRedo, so stop restores these.
var _preview_backups := {}


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
	if not mode in ["seek", "play", "pause"]:
		return _err("invalid_animation_preview_mode", "mode must be seek, play or pause.")
	var backup := _capture_preview_backup(player, animation)
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
	_record_previewed_values(backup, mode)
	var snapshot := _refresh("editor_control:preview_animation")
	var data := {
		"changed": false,
		"auto_saved": false,
		"preview_only": true,
		"undo_redo_action": false,
		"pose_backup_entries": (backup.get("entries", []) as Array).size(),
		"pose_backup_truncated": bool(backup.get("truncated", false)),
		"agent_guidance": "The preview pose is applied outside UndoRedo. Call stop_animation_preview before saving; it restores the original pose.",
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
	# keep_state only controls the player's own stop(); the edited pose is
	# restored unless keep_pose is explicitly requested.
	var keep_pose := bool(params.get("keep_pose", params.get("keepPose", false)))
	_purge_stale_backups()
	var had_backup := _preview_backups.has(player.get_instance_id())
	var playback_unverifiable := had_backup and str((_preview_backups[player.get_instance_id()] as Dictionary).get("last_mode", "")) == "play"
	if playback_unverifiable:
		# Playback kept writing the pose, so the current values are what the
		# animation wrote last; edits made during playback cannot be told apart.
		_record_previewed_values(_preview_backups[player.get_instance_id()], "play", true)
	player.stop(keep_state)
	var restore := {"restored": 0, "failed": 0, "conflicts": 0, "had_backup": had_backup}
	if keep_pose:
		_preview_backups.erase(player.get_instance_id())
	else:
		restore = _restore_preview_backup(player)
	var snapshot := _refresh("editor_control:stop_animation_preview")
	var data := {
		# A kept preview pose is an unsaved scene change made outside UndoRedo.
		"changed": keep_pose and had_backup,
		"auto_saved": false,
		"preview_only": true,
		"undo_redo_action": false,
		"player": AnimationModel.node_ref_payload(player, scene_root),
		"keep_state": keep_state,
		"keep_pose": keep_pose,
		"pose_restored": not keep_pose and bool(restore.get("had_backup", false)) and int(restore.get("failed", 0)) == 0 and int(restore.get("conflicts", 0)) == 0,
		"restored_property_count": int(restore.get("restored", 0)),
		"restore_failed_count": int(restore.get("failed", 0)),
		# Properties changed after the preview wrote them (user or UndoRedo edit)
		# are left alone rather than overwritten outside UndoRedo.
		"restore_conflict_count": int(restore.get("conflicts", 0)),
		"conflict_detection": "playback_unverifiable" if playback_unverifiable else "exact",
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


func _capture_preview_backup(player: AnimationPlayer, animation: Animation) -> Dictionary:
	_purge_stale_backups()
	var key := player.get_instance_id()
	var backup: Dictionary = _preview_backups.get(key, {"player": weakref(player), "entries": [], "keys": {}, "truncated": false})
	_preview_backups[key] = backup
	var touched: Array = []
	backup["touched"] = touched
	var root := player.get_node_or_null(player.root_node)
	if root == null or animation == null:
		return backup
	var entries: Array = backup.get("entries", [])
	var keys: Dictionary = backup.get("keys", {})
	for track in range(animation.get_track_count()):
		var target := preview_track_target(root, animation.track_get_type(track), animation.track_get_path(track))
		if target.is_empty():
			continue
		var object: Object = target.get("object")
		var property := str(target.get("property", ""))
		var entry_key := str(object.get_instance_id()) + ":" + property
		if keys.has(entry_key):
			if not touched.has(keys[entry_key]):
				touched.append(keys[entry_key])
			continue
		if entries.size() >= MAX_PREVIEW_BACKUP_ENTRIES:
			backup["truncated"] = true
			break
		keys[entry_key] = entries.size()
		touched.append(entries.size())
		entries.append({"object": weakref(object), "property": property, "value": _copy_value(object.get_indexed(NodePath(property)))})
	return backup


## Remembers what the preview wrote to the properties this animation touched,
## so stop can tell a later user/UndoRedo edit apart from the preview pose.
func _record_previewed_values(backup: Dictionary, mode: String, all_entries := false) -> void:
	backup["last_mode"] = mode
	var entries: Array = backup.get("entries", [])
	var indices: Array = range(entries.size()) if all_entries else backup.get("touched", [])
	for index in indices:
		var entry: Dictionary = entries[int(index)]
		var object: Object = (entry.get("object") as WeakRef).get_ref()
		if object != null:
			entry["previewed"] = _copy_value(object.get_indexed(NodePath(str(entry.get("property")))))
			entry["has_previewed"] = true


func _purge_stale_backups() -> void:
	for key in _preview_backups.keys():
		var backup: Dictionary = _preview_backups[key]
		if (backup.get("player") as WeakRef).get_ref() == null:
			_preview_backups.erase(key)


static func _copy_value(value: Variant) -> Variant:
	if typeof(value) == TYPE_ARRAY or typeof(value) == TYPE_DICTIONARY:
		return value.duplicate(true)
	return value


static func same_value(a: Variant, b: Variant) -> bool:
	return typeof(a) == typeof(b) and a == b


func _restore_preview_backup(player: AnimationPlayer) -> Dictionary:
	var key := player.get_instance_id()
	if not _preview_backups.has(key):
		return {"restored": 0, "failed": 0, "had_backup": false}
	var backup: Dictionary = _preview_backups[key]
	_preview_backups.erase(key)
	var restored := 0
	var failed := 0
	var conflicts := 0
	var entries: Array = backup.get("entries", [])
	# Restore in reverse capture order so the earliest original value wins.
	for index in range(entries.size() - 1, -1, -1):
		var entry: Dictionary = entries[index]
		var object: Object = (entry.get("object") as WeakRef).get_ref()
		if object == null:
			failed += 1
			continue
		var property := NodePath(str(entry.get("property")))
		if bool(entry.get("has_previewed", false)) and not same_value(object.get_indexed(property), entry.get("previewed")):
			conflicts += 1
			continue
		object.set_indexed(property, entry.get("value"))
		restored += 1
	return {"restored": restored, "failed": failed, "conflicts": conflicts, "had_backup": true}


## Resolves the object/property an animation track writes, relative to the
## player's root node. Method, audio and nested-animation tracks are skipped.
static func preview_track_target(root: Node, track_type: int, track_path: NodePath) -> Dictionary:
	if root.get_node_or_null(NodePath(track_path.get_concatenated_names())) == null:
		return {}
	var resolved: Array = root.get_node_and_resource(track_path)
	if resolved.size() < 3 or resolved[0] == null:
		return {}
	var node: Node = resolved[0]
	var resource: Resource = resolved[1]
	var remaining: NodePath = resolved[2]
	match track_type:
		Animation.TYPE_POSITION_3D:
			return {"object": node, "property": "position"}
		Animation.TYPE_ROTATION_3D:
			return {"object": node, "property": "quaternion"}
		Animation.TYPE_SCALE_3D:
			return {"object": node, "property": "scale"}
		Animation.TYPE_BLEND_SHAPE:
			if track_path.get_subname_count() == 0:
				return {}
			return {"object": node, "property": "blend_shapes/" + str(track_path.get_subname(track_path.get_subname_count() - 1))}
		Animation.TYPE_VALUE, Animation.TYPE_BEZIER:
			if resource != null and remaining.get_subname_count() > 0:
				return {"object": resource, "property": str(remaining.get_subname(0))}
			if track_path.get_subname_count() == 0:
				return {}
			if resource == null:
				# Back up the whole base property (position, not position:x).
				return {"object": node, "property": str(track_path.get_subname(0))}
			return {"object": node, "property": track_path.get_concatenated_subnames()}
	return {}


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
