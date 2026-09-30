extends SceneTree

const AddonUpdateModel := preload("res://addons/godot_codex_bridge/core/addon_update_model.gd")
const AddonUpdatePanel := preload("res://addons/godot_codex_bridge/core/addon_update_panel.gd")

const INSTALLED := {
	"channel": "GC-work",
	"build_id": "sha256:aaaaaaaa11112222",
	"channel_manifest_path": "C:/Source/godot-codex-bridge/GC_WORK_CHANNEL.json",
}
const LOCAL_UPDATE := {"state": "update_available", "label": "GC-work · UPDATE", "tone": "warn", "tooltip": "t"}
const CHECK_AVAILABLE := {
	"state": "update_available",
	"installed_build_id": "sha256:aaaaaaaa11112222",
	"available_build_id": "sha256:bbbbbbbb33334444",
	"available_version": "0.2.0",
	"published_at": "2026-09-30T10:00:00Z",
	"source_matches_channel": true,
	"pending": false,
}

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge addon update model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge addon update model tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	_test_manual_command()
	_test_unpaired()
	_test_check_states()
	_test_schedule_and_cancel()
	_test_disconnect_while_busy()
	_test_result_notice()
	_test_panel_applies_view()


func _model() -> AddonUpdateModel:
	var model := AddonUpdateModel.new()
	model.project_root = "C:/Games/My Project/"
	model.set_local(INSTALLED, LOCAL_UPDATE)
	return model


func _test_manual_command() -> void:
	_eq(AddonUpdateModel.manual_command(INSTALLED, "C:/Games/My Project/"), "pwsh \"C:\\Source\\godot-codex-bridge\\scripts\\gc_work.ps1\" -Action Update -ProjectRoot \"C:\\Games\\My Project\"", "manual command uses channel manifest directory")
	_true(AddonUpdateModel.manual_command({}, "C:/P").contains("<GC-work source>"), "manual command placeholder without provenance")
	_true(AddonUpdateModel.manual_command({"channel_manifest_path": "relative/GC_WORK_CHANNEL.json"}, "C:/P").contains("<GC-work source>"), "relative channel path rejected")


func _test_unpaired() -> void:
	var model := _model()
	_false(model.begin_check(), "unpaired check stays local")
	var view := model.view()
	_false(bool(view.get("update_enabled", true)), "update disabled when unpaired")
	_true(str(view.get("update_tooltip", "")).contains("gc_work.ps1") and str(view.get("update_tooltip", "")).contains("Pair"), "unpaired tooltip explains and gives the manual command")
	_true(str(view.get("manual_command", "")).begins_with("pwsh "), "copyable manual command shown when local manifests see an update")
	_eq(view.get("status_text"), "GC-work · UPDATE", "local status shown without Host")
	_eq(view.get("status_compact"), "GC-work update available", "compact local status")
	_true(bool(view.get("update_visible", false)), "Update visible when local manifests show an update")
	_eq(str(view.get("notice", "")), "", "unpaired check adds no notice line")
	_true(str(view.get("status_tooltip", "")).contains("Pair with the Codex Host"), "pairing hint moved to tooltip")
	var current := AddonUpdateModel.new()
	current.set_local(INSTALLED, {"state": "current", "label": "GC-work · aaaaaaaa", "tone": "ok"})
	_eq(current.view().get("status_compact"), "GC-work aaaaaaaa ✓", "compact current status")
	_false(bool(current.view().get("update_visible", true)), "Update hidden when current")
	_eq(model.begin_schedule(1, "C:/Godot/godot.exe"), {}, "schedule refused when unpaired")


func _test_check_states() -> void:
	var model := _model()
	model.set_paired(true)
	_false(bool(model.view().get("update_enabled", true)), "update disabled before a check")
	_true(model.begin_check(), "paired check sends Host request")
	_false(bool(model.view().get("check_enabled", true)), "check disabled while waiting")
	_false(model.begin_check(), "no duplicate check while waiting")
	model.apply_response(AddonUpdateModel.METHOD_CHECK, {"state": "source_unpublished", "installed_build_id": "sha256:aaaaaaaa", "available_build_id": "", "pending": false})
	var view := model.view()
	_false(bool(view.get("update_enabled", true)), "source_unpublished cannot update")
	_true(str(view.get("status_text", "")).contains("unpublished"), "source_unpublished explained")
	_false(bool(view.get("update_visible", true)), "Update hidden for source_unpublished")
	_eq(str(view.get("manual_command", "")), "", "no manual command while paired")
	model.begin_check()
	model.apply_response(AddonUpdateModel.METHOD_CHECK, CHECK_AVAILABLE.duplicate())
	view = model.view()
	_true(bool(view.get("update_enabled", false)), "update_available enables Update now")
	_eq(view.get("status_text"), "Update available: bbbbbbbb (v0.2.0)", "available build short id and version")
	_true(bool(view.get("update_visible", false)) and view.get("status_compact") == "Update available: bbbbbbbb", "Update visible with compact status")
	var text := model.confirmation_text()
	_true(text.contains("aaaaaaaa → bbbbbbbb") and text.contains(AddonUpdateModel.CLOSE_NOTICE), "confirmation lists builds and close notice")
	_false(text.contains("Files:") or text.contains("added"), "confirmation claims no file counts")
	model.begin_check()
	model.apply_response(AddonUpdateModel.METHOD_CHECK, {}, {"message": "boom"})
	_true(str(model.view().get("notice", "")).contains("boom") and model.phase == "idle", "check error reported")
	model.apply_response(AddonUpdateModel.METHOD_CHECK, {"state": "weird"})
	_eq(model.host_check.get("state"), "unknown:weird", "unknown state normalized")


func _test_schedule_and_cancel() -> void:
	var model := _model()
	model.set_paired(true)
	model.begin_check()
	model.apply_response(AddonUpdateModel.METHOD_CHECK, CHECK_AVAILABLE.duplicate())
	var params := model.begin_schedule(4242, "C:/Godot/godot.exe")
	_eq(params, {"build_id": "sha256:bbbbbbbb33334444", "editor_pid": 4242, "godot_executable": "C:/Godot/godot.exe"}, "schedule params")
	_eq(model.begin_schedule(4242, "C:/Godot/godot.exe"), {}, "no double schedule")
	var rejected := model.apply_response(AddonUpdateModel.METHOD_SCHEDULE, null, {"message": "build changed"})
	_false(bool(rejected.get("close_editor", true)), "rejected schedule does not close")
	_true(model.phase == "idle" and str(model.view().get("notice", "")).contains("build changed"), "rejection reported")
	model.begin_schedule(4242, "C:/Godot/godot.exe")
	var effects := model.apply_response(AddonUpdateModel.METHOD_SCHEDULE, {"scheduled": true, "update_id": "u-1"})
	_true(bool(effects.get("close_editor", false)), "scheduled update requests close")
	var view := model.view()
	_eq(view.get("pending_text"), AddonUpdateModel.PENDING_TEXT, "pending text shown")
	_true(bool(view.get("cancel_visible", false)) and bool(view.get("cancel_enabled", false)), "cancel available while pending")
	_false(model.stop_owned_host_on_exit(), "pending update keeps the owned Host alive on editor exit")
	_false(bool(view.get("update_enabled", true)), "update disabled while pending")
	_false(bool(view.get("update_visible", true)), "Update hidden while pending")
	model.set_paired(false)
	_true(model.phase == "pending" and not bool(model.view().get("cancel_enabled", true)), "pending survives disconnect; cancel needs pairing")
	model.set_paired(true)
	_true(model.begin_cancel(), "cancel sends Host request")
	model.apply_response(AddonUpdateModel.METHOD_CANCEL, {"cancelled": null})
	_true(model.phase == "idle" and str(model.view().get("notice", "")).contains("No update"), "null fields from the Host are not truthy")
	model.phase = "pending"
	model.begin_cancel()
	model.apply_response(AddonUpdateModel.METHOD_CANCEL, {"cancelled": true})
	_true(model.phase == "idle" and not bool(model.view().get("cancel_visible", true)), "cancel clears pending")
	model.begin_check()
	model.apply_response(AddonUpdateModel.METHOD_CHECK, {"state": "update_available", "available_build_id": "sha256:c", "pending": true})
	_eq(model.phase, "pending", "Host-reported pending restored after reload")
	_true(model.begin_check(), "check allowed while pending")
	model.apply_response(AddonUpdateModel.METHOD_CHECK, {"state": "update_available", "available_build_id": "sha256:c", "pending": null})
	_true(model.phase == "idle" and model.view().get("pending_text") == "" and not bool(model.view().get("cancel_visible", true)), "pending cleared when Host no longer has it")
	_true(str(model.view().get("notice", "")).contains("no longer"), "cleared pending explained")
	_true(model.stop_owned_host_on_exit(), "idle editor exit stops its owned Host as before")
	model.begin_schedule(1, "C:/Godot/godot.exe")
	_false(model.stop_owned_host_on_exit(), "scheduling in flight keeps the owned Host alive")
	model.apply_response(AddonUpdateModel.METHOD_SCHEDULE, null, {"message": "x"})
	_true(model.stop_owned_host_on_exit(), "rejected schedule: exit stops owned Host again")


func _test_disconnect_while_busy() -> void:
	var model := _model()
	model.set_paired(true)
	model.begin_check()
	model.set_paired(false)
	_eq(model.phase, "idle", "disconnect releases a waiting check")
	_true(bool(model.view().get("check_enabled", false)), "check usable again")


func _test_result_notice() -> void:
	var installed := AddonUpdateModel.startup_notice({"update_id": "u-1", "status": "installed", "to_build_id": "sha256:bbbbbbbb3333"}, "u-1")
	_eq(installed.get("text"), "Updated to bbbbbbbb.", "installed notice for the scheduled id")
	_eq(AddonUpdateModel.startup_notice({"update_id": "u-1", "status": "installed"}, ""), {}, "no scheduled id: result ignored")
	_eq(AddonUpdateModel.startup_notice({"update_id": "forged", "status": "failed", "error": "run evil.ps1"}, "u-1"), {}, "result with another update_id ignored")
	var failed := AddonUpdateModel.startup_notice({"update_id": "u-2", "status": "failed", "error": "installer exit 3", "backup_path": "C:/b/backup"}, "u-2")
	_true(str(failed.get("text", "")).contains("installer exit 3") and str(failed.get("text", "")).contains("Backup: C:/b/backup") and failed.get("tone") == "warn", "failed notice with backup")
	_eq(AddonUpdateModel.startup_notice({"status": "installed"}, ""), {}, "result without update_id ignored")
	var dir := ProjectSettings.globalize_path("res://.godot/godot_codex_bridge/update_test_" + str(Time.get_ticks_usec()))
	DirAccess.make_dir_recursive_absolute(dir)
	var result_path := dir.path_join(AddonUpdateModel.RESULT_FILE_NAME)
	var file := FileAccess.open(result_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"update_id": "u-3", "status": "cancelled"}))
	file.close()
	_eq(AddonUpdateModel.read_json_file(result_path).get("update_id"), "u-3", "result file read")
	var id_path := AddonUpdateModel.scheduled_id_path(dir, "C:\\Games\\My Project\\")
	_eq(id_path, AddonUpdateModel.scheduled_id_path(dir, "c:/games/my project"), "scheduled id key ignores case, separators and trailing slash")
	_true(id_path != AddonUpdateModel.scheduled_id_path(dir, "C:/Games/Other"), "scheduled id key differs per project")
	_eq(AddonUpdateModel.read_scheduled_id(id_path), "", "no scheduled id yet")
	_true(AddonUpdateModel.write_scheduled_id(id_path, "u-3"), "scheduled id persisted")
	_eq(AddonUpdateModel.read_scheduled_id(id_path), "u-3", "scheduled id read back")
	AddonUpdateModel.clear_scheduled_id(id_path)
	_eq(AddonUpdateModel.read_scheduled_id(id_path), "", "scheduled id cleared")
	_eq(AddonUpdateModel.scheduled_id_path("", "C:/P"), "", "no editor data dir: no path")
	DirAccess.remove_absolute(result_path)
	DirAccess.remove_absolute(id_path.get_base_dir())
	DirAccess.remove_absolute(id_path.get_base_dir().get_base_dir())
	DirAccess.remove_absolute(dir)


func _test_panel_applies_view() -> void:
	var model := _model()
	var panel := AddonUpdatePanel.new()
	panel.apply(model.view(), model.confirmation_text())
	_true(panel.update_button.visible and panel.update_button.disabled and panel.update_button.tooltip_text.contains("gc_work.ps1"), "panel shows Update disabled with reason when unpaired")
	_false(panel.notice_label.visible, "no notice line when nothing is actionable")
	for button in [panel.check_button, panel.update_button, panel.cancel_button]:
		_true((button as Button).text != "" and not (button as Button).clip_text, "update buttons keep their label width: " + (button as Button).text)
	_true(panel.manual_command_edit.visible and not panel.manual_command_edit.editable, "panel shows read-only manual command")
	_false(panel.cancel_button.visible, "cancel hidden when nothing pending")
	panel.free()


func _eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures += 1
		push_error(label + " expected=" + str(expected) + " actual=" + str(actual))


func _true(value: bool, label: String) -> void:
	if not value:
		_failures += 1
		push_error(label)


func _false(value: bool, label: String) -> void:
	if value:
		_failures += 1
		push_error(label)
