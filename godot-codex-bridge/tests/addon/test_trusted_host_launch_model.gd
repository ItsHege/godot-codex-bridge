extends SceneTree

const Model := preload("res://addons/godot_codex_bridge/core/trusted_host_launch_model.gd")
const PLUGIN_PATH := "res://addons/godot_codex_bridge/plugin.gd"
const FINGERPRINT := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

var _failures := 0


func _init() -> void:
	_test_validation()
	_test_files()
	_test_args()
	_test_launch_state()
	_test_texts()
	_test_plugin_wiring()
	if _failures == 0:
		print("Godot Codex Bridge trusted host launch model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge trusted host launch model tests failed: " + str(_failures))
		quit(1)


func _record(overrides: Dictionary = {}) -> Dictionary:
	var bs := char(92)
	var record := {
		"schema_version": "trusted-host/1",
		"install_root": "C:" + bs + "Tools" + bs + "godot-codex-bridge",
		"start_script": "C:" + bs + "Tools" + bs + "godot-codex-bridge" + bs + "scripts" + bs + "start_codex_host.ps1",
		"powershell_executable": "C:" + bs + "Program Files" + bs + "PowerShell" + bs + "7" + bs + "pwsh.exe",
		"node_executable": "C:/Program Files/nodejs/node.exe",
		"codex_executable": "C:/Users/u/AppData/Roaming/npm/codex.exe",
		"runtime": "app-server",
		"port": 49390,
		"fingerprint": FINGERPRINT,
		"start_script_sha256": FINGERPRINT,
		"trusted_at": "2026-09-30T10:00:00Z",
	}
	for key in overrides.keys():
		record[key] = overrides[key]
	return record


func _code(record: Dictionary, project := "D:/Games/MyGame") -> String:
	var result := Model.validate_record(record, project, false)
	return "ok" if bool(result.get("ok", false)) else str(result.get("error_code", ""))


func _test_validation() -> void:
	var bs := char(92)
	_eq(_code(_record()), "ok", "valid record")
	_eq(_code({}), "missing", "missing record")
	_eq(_code({"_unreadable": true}), "unreadable", "unreadable record")
	_eq(_code(_record({"schema_version": "trusted-host/2"})), "schema", "schema checked")
	_eq(_code(_record({"node_executable": "node.exe"})), "path", "relative executable rejected")
	_eq(_code(_record({"codex_executable": bs + bs + "server" + bs + "share" + bs + "codex.exe"})), "path", "UNC executable rejected")
	_eq(_code(_record({"node_executable": "C:/Tools/../Windows/node.exe"})), "path", "parent segments rejected")
	_eq(_code(_record({"codex_executable": "C:/Tools/codex.cmd"})), "executable", "non-.exe rejected")
	_eq(_code(_record({"powershell_executable": "C:/Tools/cmd.exe"})), "executable", "powershell must be pwsh/powershell")
	_eq(_code(_record({"powershell_executable": "C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"})), "ok", "Windows PowerShell accepted")
	_eq(_code(_record({"start_script": "C:/Other/scripts/start_codex_host.ps1"})), "start_script", "start script outside install root rejected")
	_eq(_code(_record({"start_script": "C:/Tools/godot-codex-bridge/scripts/evil.ps1"})), "start_script", "other script rejected")
	_eq(_code(_record(), "C:/Tools/godot-codex-bridge"), "inside_project", "install root equal to project rejected")
	_eq(_code(_record(), "c:/tools"), "inside_project", "install root inside project rejected (case-insensitive)")
	_eq(_code(_record(), "C:/Tools/godot-codex-bridge/examples/minimal_3d_project"), "project_inside_install", "project inside install root rejected like the launcher does")
	_eq(_code(_record({"runtime": "mock", "codex_executable": ""})), "ok", "mock runtime record without Codex accepted")
	_eq(_code(_record({"runtime": "app-server", "codex_executable": ""})), "path", "app-server record still requires Codex")
	_eq(_code(_record({"runtime": "shell"})), "runtime", "runtime checked")
	_eq(_code(_record({"port": 70000})), "port", "port range checked")
	_eq(_code(_record({"port": "49390"})), "port", "port must be a number")
	_eq(_code(_record({"fingerprint": FINGERPRINT.to_upper()})), "fingerprint", "fingerprint must be lowercase hex")
	var no_hash := _record()
	no_hash.erase("start_script_sha256")
	_eq(_code(no_hash), "script_hash", "start script hash required")
	_eq(_code(_record({"start_script_sha256": "abc"})), "script_hash", "start script hash must be sha256 hex")
	var normalized: Dictionary = Model.validate_record(_record(), "D:/Games/MyGame", false).get("record", {})
	_eq(normalized.get("port"), 49390, "normalized port is int")
	_false(normalized.has("trusted_at"), "only known fields kept")


func _test_files() -> void:
	var root := ProjectSettings.globalize_path("res://.godot/godot_codex_bridge/trust_test_" + str(Time.get_ticks_usec()))
	DirAccess.make_dir_recursive_absolute(root.path_join("scripts"))
	for name in ["scripts/start_codex_host.ps1", "pwsh.exe", "node.exe", "codex.exe"]:
		var file := FileAccess.open(root.path_join(name), FileAccess.WRITE)
		file.store_string("x")
		file.close()
	var record := _record({
		"install_root": root,
		"start_script": root.path_join("scripts/start_codex_host.ps1"),
		"powershell_executable": root.path_join("pwsh.exe"),
		"node_executable": root.path_join("node.exe"),
		"codex_executable": root.path_join("codex.exe"),
	})
	record["start_script_sha256"] = FileAccess.get_sha256(root.path_join("scripts/start_codex_host.ps1"))
	var validated: Dictionary = Model.validate_record(record, "D:/Games/MyGame")
	_true(bool(validated.get("ok", false)), "existing files accepted")
	_true(Model.start_script_matches(validated.get("record", {})), "unchanged start script matches its trusted hash")
	var tampered := FileAccess.open(root.path_join("scripts/start_codex_host.ps1"), FileAccess.WRITE)
	tampered.store_string("Write-Host changed")
	tampered.close()
	_false(Model.start_script_matches(validated.get("record", {})), "changed start script refused")
	_false(Model.start_script_matches({"start_script": root.path_join("scripts/start_codex_host.ps1"), "start_script_sha256": ""}), "missing hash refused")
	DirAccess.remove_absolute(root.path_join("codex.exe"))
	_eq(str(Model.validate_record(record, "D:/Games/MyGame").get("error_code", "")), "files_missing", "missing file rejected")
	for name in ["scripts/start_codex_host.ps1", "pwsh.exe", "node.exe"]:
		DirAccess.remove_absolute(root.path_join(name))
	DirAccess.remove_absolute(root.path_join("scripts"))
	DirAccess.remove_absolute(root)


func _test_args() -> void:
	var record: Dictionary = Model.validate_record(_record(), "D:/Games/MyGame", false).get("record", {})
	var bs := char(92)
	var args := Model.launch_args(record, "D:/Games/My Game/", 4242)
	_eq(Array(args), [
		"-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden",
		"-File", "C:" + bs + "Tools" + bs + "godot-codex-bridge" + bs + "scripts" + bs + "start_codex_host.ps1",
		"-ProjectRoot", "D:" + bs + "Games" + bs + "My Game",
		"-NodeExecutable", "C:/Program Files/nodejs/node.exe",
		"-CodexExecutable", "C:/Users/u/AppData/Roaming/npm/codex.exe",
		"-ExpectedFingerprint", FINGERPRINT,
		"-Port", "49390",
		"-Runtime", "app-server",
		"-OwnerProcessId", "4242",
		"-Start",
	], "exact owned launch args")
	var trust := Array(Model.trust_args(record, "e".repeat(64)))
	_true(trust.has("-Trust") and not trust.has("-Start") and trust[trust.find("-NodeExecutable") + 1] == "C:/Program Files/nodejs/node.exe", "re-trust uses the record's executables")
	_true(trust[trust.find("-ExpectedFingerprint") + 1] == "e".repeat(64) and trust[trust.find("-Port") + 1] == "49390" and trust[trust.find("-Runtime") + 1] == "app-server", "re-trust pins the confirmed fingerprint, port and runtime")
	var mock: Dictionary = Model.validate_record(_record({"runtime": "mock", "codex_executable": ""}), "D:/Games/MyGame", false).get("record", {})
	var mock_args := Array(Model.launch_args(mock, "D:/Games/MyGame", 7))
	_false(mock_args.has("-CodexExecutable"), "mock launch passes no empty Codex argument")
	_true(mock_args[mock_args.find("-ExpectedFingerprint") + 1] == FINGERPRINT and mock_args[mock_args.find("-Runtime") + 1] == "mock", "mock launch keeps later flags aligned")
	_false(Array(Model.trust_args(mock, FINGERPRINT)).has("-CodexExecutable"), "mock re-trust passes no empty Codex argument")
	_eq(Model.record_path("C:/Users/u/AppData/Local"), "C:/Users/u/AppData/Local/GodotCodexBridge/trusted_host.json", "record path")
	_eq(Model.launch_status_path("C:/Users/u/AppData/Local", 4242), "C:/Users/u/AppData/Local/GodotCodexBridge/launch/4242.json", "launch status path")
	_eq(Model.record_path(""), "", "no LOCALAPPDATA, no record")


func _test_launch_state() -> void:
	var record := {"port": 49390}
	var launched := float(Time.get_unix_time_from_datetime_string("2026-09-30T12:00:00"))
	_eq(Model.launch_state({}, launched, record).get("state"), "waiting", "no file yet")
	_eq(Model.launch_state({"_unreadable": true}, launched, record).get("state"), "waiting", "partial file")
	_eq(Model.launch_state({"status": "ready", "updated_at": "2026-09-30T11:00:00Z"}, launched, record).get("state"), "waiting", "stale file from an earlier process ignored")
	_eq(Model.launch_state({"status": "starting", "updated_at": "2026-09-30T12:00:01Z"}, launched, record).get("state"), "waiting", "starting")
	var ready := Model.launch_state({"status": "ready", "port": 49391, "updated_at": "2026-09-30T12:00:02.500Z"}, launched, record)
	_true(ready.get("state") == "ready" and ready.get("port") == 49390, "ready always uses the record's port")
	_eq(Model.launch_state({"status": "ready", "updated_at": "2026-09-30T15:00:02+03:00"}, launched, record).get("state"), "ready", "offset timestamp honoured")
	var bad_fp := Model.launch_state({"status": "fingerprint_changed", "fingerprint": "zz", "updated_at": "2026-09-30T12:00:02Z"}, launched, record)
	_eq(bad_fp.get("new_fingerprint"), "", "malformed new fingerprint dropped")
	var changed := Model.launch_state({"status": "fingerprint_changed", "fingerprint": FINGERPRINT, "updated_at": "2026-09-30T12:00:02Z"}, launched, record)
	_true(changed.get("state") == "fingerprint_changed" and changed.get("new_fingerprint") == FINGERPRINT, "fingerprint change")
	_eq(Model.launch_state({"status": "untrusted", "updated_at": "2026-09-30T12:00:02Z"}, launched, record).get("state"), "untrusted", "untrusted")
	_eq(Model.launch_state({"status": "failed", "message": "node missing", "updated_at": "2026-09-30T12:00:02Z"}, launched, record).get("message"), "node missing", "failure message")
	_eq(Model.iso_to_unix("2026-09-30T12:00:00-02:30"), launched + 9000.0, "negative offset")


func _test_texts() -> void:
	var bs := char(92)
	_eq(Model.SETUP_COMMAND, "pwsh \"<Bridge install>" + bs + "scripts" + bs + "start_codex_host.ps1\" -Trust", "fixed setup command")
	_true(Model.setup_text().ends_with(Model.SETUP_COMMAND), "setup text is fixed")
	var text := Model.retrust_dialog_text(_record(), "f".repeat(64))
	_true(text.begins_with("The Host installation files changed since you trusted them. Only continue if you changed or rebuilt it yourself.") and text.contains("godot-codex-bridge") and text.contains(FINGERPRINT) and text.contains("f".repeat(64)), "re-trust dialog shows path and full fingerprints")
	_false(text.contains("for example"), "no reassuring example in the dialog")
	_eq(Model.plain_message("[b]evil[/b]" + char(10) + "line2" + char(7)), "'b'evil'/b' line2", "status message is one plain line")
	_eq(Model.plain_message("x".repeat(500)).length(), Model.MAX_STATUS_MESSAGE_CHARS + 1, "status message truncated")


func _test_plugin_wiring() -> void:
	var source := FileAccess.get_file_as_string(PLUGIN_PATH)
	var start := source.find("func _launch_trusted_host(")
	var body := source.substr(start, source.find("\nfunc ", start + 10) - start)
	var hash_at := body.find("start_script_matches(record)")
	var set_at := body.find("OS.set_environment(TrustedHostLaunchModel.SECRET_ENV")
	_true(hash_at >= 0 and hash_at < set_at, "start script hash checked before launch")
	var create_at := body.find("OS.create_process(str(record.get(\"powershell_executable\"")
	var unset_at := body.find("OS.unset_environment(TrustedHostLaunchModel.SECRET_ENV)")
	_true(start >= 0 and set_at >= 0 and set_at < create_at and create_at < unset_at, "secret env set only around the launch")
	_false(body.contains("_host_config"), "launch never uses host_config.json")
	var try_body := source.substr(source.find("func _try_one_click_launch("), 1400)
	_true(try_body.contains("validate_record(") and try_body.contains("_host_port_listening("), "launch requires a valid trust record and a free port")
	_false(try_body.contains("_host_config"), "setup text never derived from host_config.json")
	var retrust_body := source.substr(source.find("func _retrust_and_connect("), 900)
	_true(retrust_body.find("start_script_matches(record)") >= 0 and retrust_body.find("start_script_matches(record)") < retrust_body.find("OS.execute("), "re-trust checks the script hash before running it")


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
