extends SceneTree

const PermissionProfileModel := preload("res://addons/godot_codex_bridge/core/permission_profile_model.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge permission profile model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge permission profile model tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var ids := PermissionProfileModel.profile_ids()
	_assert_eq(ids, ["read_only", "navigate", "diagnose", "scene_edit", "save", "full_trust"], "profile ids")
	_assert_eq(PermissionProfileModel.permission_keys().size(), 18, "permission key count")

	for profile_id in ids:
		var metadata := PermissionProfileModel.profile_metadata(profile_id)
		_assert_eq(metadata.get("profile_id"), profile_id, "metadata id " + profile_id)
		_assert_true(str(metadata.get("profile_label", "")).strip_edges() != "", "metadata label " + profile_id)
		_assert_true(str(metadata.get("profile_description", "")).strip_edges().length() > 20, "metadata description " + profile_id)
		var permissions := PermissionProfileModel.permissions_for_profile(profile_id)
		_assert_eq(PermissionProfileModel.unknown_permission_keys(permissions), [], "known keys only " + profile_id)
		_assert_eq(permissions.keys().size(), PermissionProfileModel.permission_keys().size(), "permission map size " + profile_id)
		_assert_eq(PermissionProfileModel.matching_profile_id(permissions), profile_id, "matching profile " + profile_id)

	var read_only := PermissionProfileModel.permissions_for_profile("read_only")
	_assert_true(bool(read_only.get("allow_codex_chat", false)), "read only chat allowed")
	_assert_true(bool(read_only.get("allow_send_context", false)), "read only context allowed")
	_assert_false(bool(read_only.get("allow_screenshots", true)), "read only screenshots denied")
	_assert_false(bool(read_only.get("allow_open_scene", true)), "read only open scene denied")
	_assert_false(bool(read_only.get("allow_run_current_scene", true)), "read only run scene denied")
	_assert_false(bool(read_only.get("allow_playtest_input", true)), "read only playtest input denied")
	_assert_false(bool(read_only.get("allow_scene_edits", true)), "read only edits denied")
	_assert_false(bool(read_only.get("allow_scene_save", true)), "read only save denied")

	var navigate := PermissionProfileModel.permissions_for_profile("navigate")
	_assert_true(bool(navigate.get("allow_open_scene", false)), "navigate open scene")
	_assert_true(bool(navigate.get("allow_editor_navigation", false)), "navigate editor navigation")
	_assert_false(bool(navigate.get("allow_screenshots", true)), "navigate screenshots denied")
	_assert_false(bool(navigate.get("allow_run_current_scene", true)), "navigate run scene denied")
	_assert_false(bool(navigate.get("allow_playtest_input", true)), "navigate playtest input denied")
	_assert_false(bool(navigate.get("allow_scene_edits", true)), "navigate edits denied")

	var diagnose := PermissionProfileModel.permissions_for_profile("diagnose")
	_assert_true(bool(diagnose.get("allow_screenshots", false)), "diagnose screenshots")
	_assert_true(bool(diagnose.get("allow_ai_markers", false)), "diagnose markers")
	_assert_true(bool(diagnose.get("allow_background_team_review", false)), "diagnose team")
	_assert_false(bool(diagnose.get("allow_run_current_scene", true)), "diagnose run scene denied")
	_assert_false(bool(diagnose.get("allow_playtest_input", true)), "diagnose playtest input denied")
	_assert_false(bool(diagnose.get("allow_scene_edits", true)), "diagnose edits denied")
	_assert_false(bool(diagnose.get("allow_scene_save", true)), "diagnose save denied")

	var scene_edit := PermissionProfileModel.permissions_for_profile("scene_edit")
	_assert_true(bool(scene_edit.get("allow_run_current_scene", false)), "scene edit run scene")
	_assert_false(bool(scene_edit.get("allow_playtest_input", true)), "scene edit playtest input remains manual-only")
	_assert_true(bool(scene_edit.get("allow_scene_edits", false)), "scene edit edits")
	_assert_false(bool(scene_edit.get("allow_scene_save", true)), "scene edit save denied")

	var save := PermissionProfileModel.permissions_for_profile("save")
	_assert_true(bool(save.get("allow_scene_edits", false)), "save edits")
	_assert_true(bool(save.get("allow_scene_save", false)), "save scene")
	_assert_true(bool(save.get("allow_clear_diagnostics", false)), "save clear diagnostics")
	_assert_false(bool(save.get("allow_playtest_input", true)), "save playtest input remains manual-only")
	_assert_false(bool(save.get("allow_full_trust_session", true)), "save full trust session denied")

	var full_trust := PermissionProfileModel.permissions_for_profile("full_trust")
	for key in PermissionProfileModel.permission_keys():
		if key == "allow_playtest_input":
			_assert_false(bool(full_trust.get(key, true)), "full trust does not enable playtest input before safety sign-off")
		else:
			_assert_true(bool(full_trust.get(key, false)), "full trust enables " + key)

	var custom := PermissionProfileModel.permissions_for_profile("diagnose")
	custom["allow_scene_save"] = true
	_assert_eq(PermissionProfileModel.matching_profile_id(custom), PermissionProfileModel.CUSTOM_PROFILE_ID, "manual drift becomes custom")
	_assert_eq(PermissionProfileModel.current_profile_metadata(custom).get("profile_label"), "Custom", "custom label")
	_assert_eq(PermissionProfileModel.unknown_permission_keys({"allow_codex_chat": true, "bad_key": true}), ["bad_key"], "unknown keys")
	_assert_false(bool(PermissionProfileModel.with_known_keys_only({"allow_codex_chat": true}).get("allow_scene_save", true)), "known keys default false")


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
