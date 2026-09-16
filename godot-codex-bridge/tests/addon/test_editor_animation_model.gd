extends SceneTree

const BridgeContext := preload("res://addons/godot_codex_bridge/core/bridge_context.gd")
const EditorAnimation := preload("res://addons/godot_codex_bridge/core/editor_animation.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge editor animation tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge editor animation tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var ctx := BridgeContext.new()
	ctx.permissions = {
		"allow_editor_inspect": false,
		"allow_animation_preview": false,
		"allow_scene_edits": false,
	}
	var service := EditorAnimation.new(ctx)

	var denied_list := service.list_animation_players({})
	_assert_false(bool(denied_list.get("ok", true)), "list animation players denied when inspect permission disabled")
	_assert_eq(((denied_list.get("error", {}) as Dictionary).get("code")), "permission_denied", "inspect permission error")

	var denied_preview := service.preview_animation({})
	_assert_false(bool(denied_preview.get("ok", true)), "preview animation denied when preview permission disabled")
	_assert_eq(((denied_preview.get("error", {}) as Dictionary).get("code")), "permission_denied", "preview permission error")

	var denied_create := service.create_animation_clip({})
	_assert_false(bool(denied_create.get("ok", true)), "create animation denied when scene edit permission disabled")
	_assert_eq(((denied_create.get("error", {}) as Dictionary).get("code")), "permission_denied", "scene edit permission error")


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures += 1
		push_error(label + " expected=" + str(expected) + " actual=" + str(actual))


func _assert_false(value: bool, label: String) -> void:
	if value:
		_failures += 1
		push_error(label)
