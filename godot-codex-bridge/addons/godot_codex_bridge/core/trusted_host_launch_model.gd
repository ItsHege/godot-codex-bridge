@tool
extends RefCounted

## One-click Connect (contracts/ONE_CLICK_CONNECT_V1.md), pure logic.
## The only executable authority is the per-user trust record written by
## `start_codex_host.ps1 -Trust` under %LOCALAPPDATA%\GodotCodexBridge. Nothing
## from the project (host_config.json included) decides what is launched.

const SCHEMA_VERSION := "trusted-host/1"
const APP_DIR := "GodotCodexBridge"
const RECORD_FILE := "trusted_host.json"
const LAUNCH_DIR := "launch"
const START_SCRIPT_SUFFIX := "/scripts/start_codex_host.ps1"
const POWERSHELL_NAMES := ["pwsh.exe", "powershell.exe"]
const MAX_FILE_BYTES := 65536
const LAUNCH_TIMEOUT_SECONDS := 30.0
## A status file older than the launch (minus clock skew) belongs to an earlier
## process that happened to have the same editor PID.
const STATUS_SKEW_SECONDS := 5.0
const SECRET_ENV := "GODOT_CODEX_HOST_PAIR_SECRET_INPUT"
const RETRUST_TEXT := "The Host installation files changed since you trusted them. Only continue if you changed or rebuilt it yourself."
## Fixed text: never built from project content (host_config.json included).
const SETUP_COMMAND := "pwsh \"<Bridge install>\\scripts\\start_codex_host.ps1\" -Trust"
const SETUP_HINT := "One-time setup: in PowerShell, run the trusted Bridge install's start script with -Trust:"
const MAX_STATUS_MESSAGE_CHARS := 200


static func record_path(local_app_data: String) -> String:
	if local_app_data.strip_edges() == "":
		return ""
	return local_app_data.path_join(APP_DIR).path_join(RECORD_FILE)


static func launch_status_path(local_app_data: String, owner_pid: int) -> String:
	if local_app_data.strip_edges() == "" or owner_pid <= 0:
		return ""
	return local_app_data.path_join(APP_DIR).path_join(LAUNCH_DIR).path_join(str(owner_pid) + ".json")


static func read_json(path: String) -> Dictionary:
	if path == "" or not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_FILE_BYTES:
		return {"_unreadable": true}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {"_unreadable": true}


## Validates a trust record. Returns {ok, record} or {ok: false, error_code, message}.
## `check_files` is only false in unit tests of the shape rules.
static func validate_record(record: Dictionary, project_root_abs: String, check_files := true) -> Dictionary:
	if record.is_empty():
		return _invalid("missing", "No trusted Codex Host is set up for this user yet.")
	if record.has("_unreadable"):
		return _invalid("unreadable", "The trusted Host record could not be read.")
	if str(record.get("schema_version", "")) != SCHEMA_VERSION:
		return _invalid("schema", "The trusted Host record has an unsupported schema.")
	var runtime := str(record.get("runtime", ""))
	if not (runtime in ["app-server", "mock"]):
		return _invalid("runtime", "The trusted Host record has an unsupported runtime.")
	# The mock runtime never launches Codex, so its record has no Codex executable.
	var executable_keys := ["powershell_executable", "node_executable", "codex_executable"] if runtime == "app-server" else ["powershell_executable", "node_executable"]
	var paths := {"codex_executable": ""}
	for key in ["install_root", "start_script"] + executable_keys:
		var value := str(record.get(key, "")).strip_edges()
		if not is_local_absolute_path(value):
			return _invalid("path", "The trusted Host record field " + key + " is not a local absolute path.")
		paths[key] = value
	for key in executable_keys:
		if not str(paths[key]).to_lower().ends_with(".exe"):
			return _invalid("executable", "The trusted Host record field " + key + " is not an .exe.")
	if not (str(paths["powershell_executable"]).get_file().to_lower() in POWERSHELL_NAMES):
		return _invalid("executable", "The trusted Host record does not name PowerShell (pwsh.exe or powershell.exe).")
	var install_root := comparable_path(paths["install_root"])
	var start_script := comparable_path(paths["start_script"])
	if not start_script.ends_with(START_SCRIPT_SUFFIX) or not start_script.begins_with(install_root + "/"):
		return _invalid("start_script", "The trusted start script must be scripts\\start_codex_host.ps1 inside the trusted install root.")
	var project := comparable_path(project_root_abs)
	if project != "" and (install_root == project or install_root.begins_with(project + "/")):
		return _invalid("inside_project", "The trusted Host install is inside this project, so the project could change what runs. Trust an install outside the project.")
	# The launcher also refuses a project inside the install; say so now instead
	# of failing later during the launch.
	if project != "" and project.begins_with(install_root + "/"):
		return _invalid("project_inside_install", "This project is inside the trusted Host install. Open a project stored outside it to use one-click Connect.")
	var port_value: Variant = record.get("port")
	if not (typeof(port_value) == TYPE_INT or typeof(port_value) == TYPE_FLOAT) or float(port_value) != floorf(float(port_value)) or int(port_value) < 1 or int(port_value) > 65535:
		return _invalid("port", "The trusted Host record has an invalid port.")
	var fingerprint := str(record.get("fingerprint", ""))
	if not is_sha256_hex(fingerprint):
		return _invalid("fingerprint", "The trusted Host record has an invalid fingerprint.")
	var script_sha256 := str(record.get("start_script_sha256", ""))
	if not is_sha256_hex(script_sha256):
		return _invalid("script_hash", "The trusted Host record has no start script hash. Re-run the one-time setup.")
	if check_files:
		if not DirAccess.dir_exists_absolute(paths["install_root"]):
			return _invalid("files_missing", "The trusted Host install folder no longer exists: " + str(paths["install_root"]))
		for key in ["start_script"] + executable_keys:
			if not FileAccess.file_exists(paths[key]):
				return _invalid("files_missing", "A trusted Host file no longer exists: " + str(paths[key]))
	var normalized := paths.duplicate()
	normalized["runtime"] = runtime
	normalized["port"] = int(port_value)
	normalized["fingerprint"] = fingerprint
	normalized["start_script_sha256"] = script_sha256
	return {"ok": true, "record": normalized}


## The start script performs every other check, so its bytes must still be the
## ones the user trusted before the addon runs it (launch or re-trust).
static func start_script_matches(record: Dictionary) -> bool:
	var path := str(record.get("start_script", ""))
	var expected := str(record.get("start_script_sha256", ""))
	if path == "" or not is_sha256_hex(expected) or not FileAccess.file_exists(path):
		return false
	return FileAccess.get_sha256(path).to_lower() == expected


static func script_changed_message() -> String:
	return "The trusted Host start script changed since it was trusted, so the addon will not run it. If you changed it yourself, repeat the one-time setup:\n" + SETUP_COMMAND


## Arguments for PowerShell `-File start_codex_host.ps1 -Start` as an owned,
## non-interactive launch for this editor process.
static func launch_args(record: Dictionary, project_root_abs: String, owner_pid: int) -> PackedStringArray:
	var args := PackedStringArray([
		"-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden",
		"-File", str(record.get("start_script", "")),
		"-ProjectRoot", windows_path(project_root_abs.trim_suffix("/").trim_suffix("\\")),
		"-NodeExecutable", str(record.get("node_executable", "")),
	])
	args.append_array(_codex_args(record))
	args.append_array(PackedStringArray([
		"-ExpectedFingerprint", str(record.get("fingerprint", "")),
		"-Port", str(int(record.get("port", 0))),
		"-Runtime", str(record.get("runtime", "")),
		"-OwnerProcessId", str(owner_pid),
		"-Start",
	]))
	return args


## An empty argument value can be dropped on the way to PowerShell, shifting the
## following flags, so the mock runtime passes no Codex argument at all.
static func _codex_args(record: Dictionary) -> PackedStringArray:
	var codex := str(record.get("codex_executable", ""))
	return PackedStringArray(["-CodexExecutable", codex]) if codex != "" else PackedStringArray()


## Arguments for re-trusting the same installation after the user confirmed
## the fingerprint the dialog showed; -Trust refuses if it differs.
static func trust_args(record: Dictionary, expected_fingerprint: String) -> PackedStringArray:
	return PackedStringArray([
		"-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass",
		"-File", str(record.get("start_script", "")),
		"-Trust",
		"-NodeExecutable", str(record.get("node_executable", "")),
	] + Array(_codex_args(record)) + [
		"-ExpectedFingerprint", expected_fingerprint,
		"-Port", str(int(record.get("port", 0))),
		"-Runtime", str(record.get("runtime", "")),
	])


## Interprets the launch status file for the launch that started at
## `launched_unix`: waiting | ready | fingerprint_changed | untrusted | failed.
static func launch_state(status: Dictionary, launched_unix: float, record: Dictionary) -> Dictionary:
	if status.is_empty() or status.has("_unreadable"):
		return {"state": "waiting"}
	var updated := iso_to_unix(str(status.get("updated_at", "")))
	if updated <= 0 or updated < launched_unix - STATUS_SKEW_SECONDS:
		return {"state": "waiting"}
	var message := plain_message(str(status.get("message", "")))
	match str(status.get("status", "")):
		"starting":
			return {"state": "waiting"}
		"ready":
			# Always the trusted record's port; the status file cannot redirect us.
			return {"state": "ready", "port": int(record.get("port", 0))}
		"fingerprint_changed":
			var new_fingerprint := str(status.get("fingerprint", ""))
			return {"state": "fingerprint_changed", "message": message, "new_fingerprint": new_fingerprint if is_sha256_hex(new_fingerprint) else ""}
		"untrusted":
			return {"state": "untrusted", "message": message if message != "" else "The Host installation is not trusted. Run the -Trust setup command."}
		"failed":
			return {"state": "failed", "message": message if message != "" else "The Codex Host failed to start."}
	return {"state": "waiting"}


static func retrust_dialog_text(record: Dictionary, new_fingerprint: String) -> String:
	return RETRUST_TEXT + "\n\nInstall: " + str(record.get("install_root", "")) + "\nTrusted fingerprint: " + str(record.get("fingerprint", "")) + "\nNew fingerprint: " + new_fingerprint


static func setup_text() -> String:
	return SETUP_HINT + "\n" + SETUP_COMMAND


## Launcher status text is untrusted: one line, no control characters, no
## markup brackets, bounded length.
static func plain_message(text: String) -> String:
	var cleaned := ""
	for character in text:
		var code := character.unicode_at(0)
		if code < 32 or code == 127:
			cleaned += " "
		elif character == "[" or character == "]":
			cleaned += "'"
		else:
			cleaned += character
	cleaned = cleaned.strip_edges()
	if cleaned.length() > MAX_STATUS_MESSAGE_CHARS:
		cleaned = cleaned.left(MAX_STATUS_MESSAGE_CHARS) + "…"
	return cleaned


## ISO-8601 to unix seconds, honouring a Z or ±HH:MM suffix; -1 if invalid.
static func iso_to_unix(value: String) -> float:
	var text := value.strip_edges()
	if text.length() < 19 or text[10] != "T":
		return -1.0
	var base := float(Time.get_unix_time_from_datetime_string(text.substr(0, 19)))
	if base <= 0.0:
		return -1.0
	var tail := text.substr(19)
	var sign_index := maxi(tail.rfind("+"), tail.rfind("-"))
	if sign_index >= 0 and tail.length() - sign_index == 6 and tail[sign_index + 3] == ":":
		var hours := tail.substr(sign_index + 1, 2).to_int()
		var minutes := tail.substr(sign_index + 4, 2).to_int()
		var offset := float(hours * 3600 + minutes * 60)
		return base - offset if tail[sign_index] == "+" else base + offset
	return base


static func is_local_absolute_path(path: String) -> bool:
	if path.length() < 4 or path.find("..") >= 0:
		return false
	var drive := path.substr(0, 1).to_lower()
	return drive >= "a" and drive <= "z" and path[1] == ":" and (path[2] == "/" or path[2] == "\\")


static func comparable_path(path: String) -> String:
	return path.strip_edges().replace("\\", "/").trim_suffix("/").to_lower()


static func windows_path(path: String) -> String:
	return path.replace("/", "\\")


static func is_sha256_hex(value: String) -> bool:
	if value.length() != 64:
		return false
	for character in value:
		if not character in "0123456789abcdef":
			return false
	return true


static func _invalid(code: String, message: String) -> Dictionary:
	return {"ok": false, "error_code": code, "message": message}
