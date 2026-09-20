extends SceneTree

const GcWorkChannelModel := preload("res://addons/godot_codex_bridge/core/gc_work_channel_model.gd")

var _failures := 0


func _init() -> void:
	var unmanaged := GcWorkChannelModel.status({})
	_assert_eq(str(unmanaged.get("state", "")), "unmanaged", "missing provenance is visible")

	var installed := {
		"channel": "GC-work",
		"addon_version": "0.1.0",
		"build_id": "sha256:1234567890abcdef",
		"channel_manifest_path": "C:/bridge/GC_WORK_CHANNEL.json",
	}
	_assert_eq(
		GcWorkChannelModel.channel_manifest_path(installed),
		"C:/bridge/GC_WORK_CHANNEL.json",
		"bounded channel manifest path accepted"
	)
	var current := GcWorkChannelModel.status(installed, {"build_id": "sha256:1234567890abcdef"})
	_assert_eq(str(current.get("state", "")), "current", "matching build is current")
	_assert_true(str(current.get("label", "")).contains("12345678"), "current build is visible")

	var update := GcWorkChannelModel.status(installed, {"build_id": "sha256:abcdef1234567890"})
	_assert_eq(str(update.get("state", "")), "update_available", "different build reports update")
	_assert_true(str(update.get("label", "")).contains("UPDATE"), "update is visible")

	var unsafe := installed.duplicate(true)
	unsafe["channel_manifest_path"] = "C:/bridge/other.json"
	_assert_eq(GcWorkChannelModel.channel_manifest_path(unsafe), "", "unexpected manifest file is rejected")

	if _failures == 0:
		print("Godot Codex Bridge GC-work channel model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge GC-work channel model tests failed: " + str(_failures))
		quit(1)


func _assert_true(value: bool, message: String) -> void:
	if not value:
		_failures += 1
		push_error(message)


func _assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures += 1
		push_error(message + ": expected=" + str(expected) + " actual=" + str(actual))
