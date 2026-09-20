extends SceneTree

const ChatScrollPolicyModel := preload("res://addons/godot_codex_bridge/core/chat_scroll_policy_model.gd")

var _failures := 0


func _init() -> void:
	_assert_true(ChatScrollPolicyModel.is_near_bottom(968, 1000), "bottom tolerance follows latest")
	_assert_false(ChatScrollPolicyModel.is_near_bottom(900, 1000), "history browsing disables follow")

	var browsing := ChatScrollPolicyModel.after_user_scroll(420, 1000)
	_assert_false(bool(browsing.get("follow_latest", true)), "manual history position is retained")
	_assert_true(bool(browsing.get("show_jump_latest", false)), "manual history exposes jump action")

	for terminal_update in ["assistant_stream", "status", "cancelled", "error"]:
		var update := ChatScrollPolicyModel.content_update(false)
		_assert_false(bool(update.get("scroll_to_bottom", true)), terminal_update + " does not steal scroll")
		_assert_true(bool(update.get("show_jump_latest", false)), terminal_update + " keeps jump action visible")

	var resumed := ChatScrollPolicyModel.after_user_scroll(999, 1000)
	_assert_true(bool(resumed.get("follow_latest", false)), "returning to bottom resumes follow")
	var jumped := ChatScrollPolicyModel.jump_to_latest()
	_assert_true(bool(jumped.get("scroll_to_bottom", false)), "jump action reaches latest")
	_assert_false(bool(jumped.get("show_jump_latest", true)), "jump action hides itself")

	if _failures == 0:
		print("Godot Codex Bridge chat scroll policy model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge chat scroll policy model tests failed: " + str(_failures))
		quit(1)


func _assert_true(value: bool, label: String) -> void:
	if not value:
		_failures += 1
		push_error(label)


func _assert_false(value: bool, label: String) -> void:
	if value:
		_failures += 1
		push_error(label)
