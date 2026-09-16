extends SceneTree

const AnimationModel := preload("res://addons/godot_codex_bridge/core/animation_model.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge animation model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge animation model tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	_assert_eq(AnimationModel.sanitize_animation_key(" idle "), "idle", "Animation key trims")
	_assert_eq(AnimationModel.sanitize_animation_key("bad/name"), "", "Animation key rejects slash")
	_assert_eq(AnimationModel.sanitize_animation_library_key("library/key"), "library/key", "Library key preserves slash for caller error")

	var bad_path := AnimationModel.validate_animation_track_path("res://scene.tscn:position")
	_assert_eq(bad_path.get("code"), "invalid_animation_track_path", "Track path rejects res path")
	var missing_property := AnimationModel.validate_animation_track_path("MeshInstance3D")
	_assert_eq(missing_property.get("code"), "invalid_animation_track_path", "Track path requires property separator")

	var vector_value := AnimationModel.animation_key_value_from_payload("vector3", {"x": 1, "y": 2, "z": 3})
	_assert_true(vector_value.get("ok", false), "Vector3 key coercion ok")
	_assert_eq(vector_value.get("value"), Vector3(1, 2, 3), "Vector3 key coercion value")
	var invalid_variant := AnimationModel.animation_key_value_from_payload("variant", {"nested": true})
	_assert_eq(invalid_variant.get("ok"), false, "Variant key rejects complex payloads")
	_assert_eq((invalid_variant.get("error") as Dictionary).get("code"), "invalid_animation_key_value", "Variant key reject code")

	var animation := Animation.new()
	animation.length = 2.0
	animation.step = 0.1
	var populate_result := AnimationModel.populate_initial_tracks(animation, [
		{
			"path": "MeshInstance3D:position",
			"valueType": "vector3",
			"interpolationType": Animation.INTERPOLATION_LINEAR,
			"keys": [
				{"time": 0.0, "value": {"x": 0, "y": 0, "z": 0}},
				{"time": 3.0, "value": {"x": 1, "y": 2, "z": 3}, "transition": 1.5},
			],
		},
	], 12, 16)
	_assert_true(populate_result.get("ok", false), "Initial tracks populate")
	_assert_eq(animation.get_track_count(), 1, "Initial track count")
	_assert_eq(str(animation.track_get_path(0)), "MeshInstance3D:position", "Initial track path")
	_assert_eq(animation.track_get_key_count(0), 2, "Initial key count")
	_assert_eq(animation.track_get_key_time(0, 1), 2.0, "Initial key time clamps to animation length")
	_assert_eq(animation.track_get_key_value(0, 1), Vector3(1, 2, 3), "Initial key Vector3 value")

	var detail := AnimationModel.animation_detail_payload("move", animation, true, 4, 8, 512, 2, 12, 16)
	_assert_eq(detail.get("name"), "move", "Detail name")
	_assert_eq(detail.get("track_count"), 1, "Detail track count")
	var track_payload: Dictionary = (detail.get("tracks") as Array)[0]
	_assert_eq(track_payload.get("type_name"), "value", "Track type name")
	var key_payload: Dictionary = (track_payload.get("keys") as Array)[1]
	_assert_eq((key_payload.get("value") as Dictionary).get("z"), 3.0, "Key payload serializes Vector3")

	var root := Node3D.new()
	root.name = "Root"
	get_root().add_child(root)
	var player := AnimationPlayer.new()
	player.name = "AnimPlayer"
	root.add_child(player)
	var library := AnimationLibrary.new()
	library.add_animation(StringName("move"), animation)
	player.add_animation_library(StringName(""), library)

	var resolved := AnimationModel.resolve_player_animation(player, "move")
	_assert_true(resolved.get("ok", false), "Resolve player animation")
	_assert_eq(resolved.get("animation"), animation, "Resolved animation instance")

	var player_payload := AnimationModel.player_payload(player, root, true, 8)
	_assert_eq((player_payload.get("node") as Dictionary).get("path"), "AnimPlayer", "Player payload scene path")
	_assert_eq(player_payload.get("animation_count"), 1, "Player payload animation count")
	_assert_eq((player_payload.get("animations") as Array).size(), 1, "Player payload includes animation")

	var players: Array = []
	var state := {"visited": 0, "matched": 0, "truncated": false}
	AnimationModel.collect_animation_players(root, root, players, state, 4, false, 8)
	_assert_eq(players.size(), 1, "Collect animation players")
	_assert_eq(state.get("matched"), 1, "Collect matched count")
	root.free()


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures += 1
		push_error(label + " expected=" + str(expected) + " actual=" + str(actual))


func _assert_true(value: bool, label: String) -> void:
	if not value:
		_failures += 1
		push_error(label)
