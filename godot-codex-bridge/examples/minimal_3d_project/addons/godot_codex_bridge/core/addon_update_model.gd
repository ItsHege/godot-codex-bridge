@tool
extends RefCounted

## State for the Bridge dock "Updates" row (contracts/ADDON_UPDATE_V1.md).
## Pure logic: no nodes, no sockets, no files except the result helpers.

const GcWorkChannelModel := preload("gc_work_channel_model.gd")

const METHOD_CHECK := "addon.update.check"
const METHOD_SCHEDULE := "addon.update.schedule"
const METHOD_CANCEL := "addon.update.cancel"
const RESULT_FILE_NAME := "addon_update_result.json"
## The scheduled update_id is kept in the editor's per-user data directory,
## which the project (and an agent working in it) cannot write. A result file in
## the project's bridge directory is only shown when its update_id matches.
const SCHEDULED_ID_DIR := "godot_codex_bridge/addon_updates"
const MAX_RESULT_BYTES := 65536
const PENDING_TEXT := "Update pending — close Godot to install."
const CLOSE_NOTICE := "Godot will close (it asks about unsaved changes), the update installs, then this project reopens."

const HOST_STATES := ["current", "update_available", "unmanaged", "drifted", "different_channel", "channel_unpublished", "source_unpublished"]

var installed: Dictionary = {}
var local_status: Dictionary = {}
var paired := false
var project_root := ""
## Normalized addon.update.check result; empty until the Host answered.
var host_check: Dictionary = {}
## idle | checking | scheduling | pending | cancelling
var phase := "idle"
var notice := ""
var notice_tone := "neutral"


func set_local(installed_manifest: Dictionary, status: Dictionary) -> void:
	installed = installed_manifest.duplicate(true)
	local_status = status.duplicate(true)


func set_paired(value: bool) -> void:
	if paired and not value and phase in ["checking", "scheduling", "cancelling"]:
		phase = "pending" if bool(host_check.get("pending", false)) else "idle"
	paired = value
	if not paired:
		# A Host answer is only valid for the connection that produced it.
		var was_pending := phase == "pending"
		host_check = {}
		if was_pending:
			host_check = {"pending": true}


## Returns true when an addon.update.check request should be sent.
func begin_check() -> bool:
	if not paired:
		# Local manifests were re-read by the caller; the status tooltip explains
		# that the Host check needs pairing. Not actionable, so no notice line.
		return false
	if phase != "idle" and phase != "pending":
		return false
	if phase == "idle":
		phase = "checking"
	notice = ""
	return true


## Returns the addon.update.schedule params, or {} when updating is not allowed.
func begin_schedule(editor_pid: int, godot_executable: String) -> Dictionary:
	if not bool(update_gate().get("enabled", false)):
		return {}
	phase = "scheduling"
	notice = ""
	return schedule_params(host_check, editor_pid, godot_executable)


func begin_cancel() -> bool:
	if not paired or phase != "pending":
		return false
	phase = "cancelling"
	return true


## Applies a Host response. Returns effects: {"close_editor": bool}.
func apply_response(method: String, result: Variant, error: Dictionary = {}) -> Dictionary:
	var effects := {"close_editor": false}
	var failed := not error.is_empty() or typeof(result) != TYPE_DICTIONARY
	var message := str(error.get("message", "The Host returned an invalid response."))
	match method:
		METHOD_CHECK:
			if failed:
				phase = "pending" if phase == "pending" else "idle"
				notice = "Update check failed: " + message
				notice_tone = "warn"
				return effects
			var was_pending := phase == "pending"
			host_check = normalize_check(result as Dictionary)
			notice = ""
			if bool(host_check.get("pending", false)):
				phase = "pending"
			elif phase in ["checking", "pending"]:
				phase = "idle"
				if was_pending:
					# e.g. the Host gave up waiting for Godot to close.
					notice = "The Host no longer has a pending update."
					notice_tone = "neutral"
		METHOD_SCHEDULE:
			var data: Dictionary = result as Dictionary if not failed else {}
			if failed or data.get("scheduled") != true:
				phase = "idle"
				notice = "Update was not scheduled: " + message
				notice_tone = "warn"
				return effects
			phase = "pending"
			host_check["pending"] = true
			host_check["update_id"] = str(data.get("update_id", ""))
			notice = "Update scheduled. Closing Godot…"
			notice_tone = "neutral"
			effects["close_editor"] = true
		METHOD_CANCEL:
			if failed:
				phase = "pending"
				notice = "Cancel failed: " + message
				notice_tone = "warn"
				return effects
			phase = "idle"
			host_check["pending"] = false
			notice = "Pending update cancelled." if (result as Dictionary).get("cancelled") == true else "No update was pending."
			notice_tone = "neutral"
	return effects


## A scheduled (or being scheduled) update is installed by the Host after this
## editor exits, so exiting must not shut down or kill an addon-started Host.
func stop_owned_host_on_exit() -> bool:
	return not (phase in ["pending", "scheduling"])


func update_gate() -> Dictionary:
	var command := manual_command(installed, project_root)
	if phase == "pending" or phase == "cancelling":
		return {"enabled": false, "reason": "An update is already pending. Close Godot to install it, or cancel it."}
	if not paired:
		return {"enabled": false, "reason": "Pair with the Codex Host to update from the dock.\nManual update:\n" + command}
	if phase == "checking" or phase == "scheduling":
		return {"enabled": false, "reason": "Waiting for the Codex Host…"}
	if host_check.is_empty():
		return {"enabled": false, "reason": "Press Check for updates first."}
	var state := str(host_check.get("state", ""))
	if state != "update_available" or str(host_check.get("available_build_id", "")) == "":
		return {"enabled": false, "reason": state_text(host_check)}
	return {"enabled": true, "reason": "Install " + GcWorkChannelModel.short_build_id(str(host_check.get("available_build_id", ""))) + ". " + CLOSE_NOTICE}


func view() -> Dictionary:
	var gate := update_gate()
	var status_text := str(local_status.get("label", "Addon: unmanaged"))
	var status_tooltip := str(local_status.get("tooltip", ""))
	var tone := str(local_status.get("tone", "neutral"))
	var has_host_state := not host_check.is_empty() and host_check.has("state")
	if has_host_state:
		status_text = state_text(host_check)
		status_tooltip = status_text + "
" + check_tooltip(host_check)
		tone = "ok" if str(host_check.get("state", "")) == "current" else "warn"
	elif not paired:
		status_tooltip += ("
" if status_tooltip != "" else "") + "Pair with the Codex Host to check the reviewed build it can install."
	var pending := phase == "pending" or phase == "cancelling"
	var update_available := str(host_check.get("state", "")) == "update_available" if has_host_state else str(local_status.get("state", "")) == "update_available"
	return {
		"status_compact": compact_status(has_host_state),
		"status_text": status_text,
		"status_tooltip": status_tooltip,
		"status_tone": tone,
		"check_enabled": phase == "idle" or phase == "pending",
		# Update is only shown when there is something to install.
		"update_visible": update_available and not pending,
		"update_enabled": bool(gate.get("enabled", false)),
		"update_tooltip": str(gate.get("reason", "")),
		"cancel_visible": phase == "pending" or phase == "cancelling",
		"cancel_enabled": phase == "pending" and paired,
		"cancel_tooltip": "Cancel the pending update." if paired else "Pair with the Codex Host to cancel the pending update.",
		"pending_text": PENDING_TEXT if phase == "pending" or phase == "cancelling" else "",
		"notice": notice,
		"notice_tone": notice_tone,
		# Copyable fallback when the local manifests already show an update but
		# no Host is paired.
		"manual_command": manual_command(installed, project_root) if not paired and str(local_status.get("state", "")) == "update_available" else "",
	}


func compact_status(has_host_state: bool) -> String:
	var installed_short := GcWorkChannelModel.short_build_id(str(host_check.get("installed_build_id", installed.get("build_id", ""))))
	var state := str(host_check.get("state", "")) if has_host_state else str(local_status.get("state", ""))
	match state:
		"current":
			return "GC-work " + installed_short + " ✓"
		"update_available":
			if has_host_state:
				return "Update available: " + GcWorkChannelModel.short_build_id(str(host_check.get("available_build_id", "")))
			return "GC-work update available"
		"source_unavailable":
			return "GC-work " + installed_short
		"stable":
			return str(local_status.get("label", "Addon"))
		"unmanaged":
			return "Addon unmanaged"
		"drifted":
			return "Addon files drifted"
		"different_channel":
			return "Different channel"
		"channel_unpublished":
			return "No published build"
		"source_unpublished":
			return "Unpublished Host source"
	return "Update status unknown"


func confirmation_text() -> String:
	var from_build := str(host_check.get("installed_build_id", installed.get("build_id", "")))
	var to_build := str(host_check.get("available_build_id", ""))
	var lines: Array[String] = [
		"Update the Godot Codex Bridge addon?",
		GcWorkChannelModel.short_build_id(from_build) + " → " + GcWorkChannelModel.short_build_id(to_build) + version_suffix(host_check),
	]
	lines.append("")
	lines.append(CLOSE_NOTICE)
	return "\n".join(lines)


static func normalize_check(result: Dictionary) -> Dictionary:
	var state := str(result.get("state", "")).strip_edges()
	var normalized := {
		"state": state if state in HOST_STATES else "unknown:" + state.left(40),
		"installed_build_id": str(result.get("installed_build_id", "")).left(128),
		"available_build_id": str(result.get("available_build_id", "")).left(128),
		"available_version": str(result.get("available_version", "")).left(40),
		"published_at": str(result.get("published_at", "")).left(40),
		"source_matches_channel": result.get("source_matches_channel") == true,
		"pending": result.get("pending") == true,
	}
	return normalized


static func schedule_params(check: Dictionary, editor_pid: int, godot_executable: String) -> Dictionary:
	return {
		"build_id": str(check.get("available_build_id", "")),
		"editor_pid": editor_pid,
		"godot_executable": godot_executable,
	}


static func state_text(check: Dictionary) -> String:
	var available := GcWorkChannelModel.short_build_id(str(check.get("available_build_id", "")))
	match str(check.get("state", "")):
		"current":
			return "Up to date · " + GcWorkChannelModel.short_build_id(str(check.get("installed_build_id", "")))
		"update_available":
			return "Update available: " + available + version_suffix(check)
		"unmanaged":
			return "Unmanaged addon copy. Install once with gc_work.ps1 to enable updates."
		"drifted":
			return "Installed addon files differ from the recorded build (drifted)."
		"different_channel":
			return "The installed addon comes from a different channel."
		"channel_unpublished":
			return "No GC-work build has been published yet."
		"source_unpublished":
			return "The Host has unpublished addon changes; no reviewed build is installable yet."
	return "Update status: " + str(check.get("state", "unknown"))


static func check_tooltip(check: Dictionary) -> String:
	var lines: Array[String] = ["Installed: " + str(check.get("installed_build_id", "")), "Available: " + str(check.get("available_build_id", ""))]
	if str(check.get("published_at", "")) != "":
		lines.append("Published: " + str(check.get("published_at", "")))
	return "\n".join(lines)


static func version_suffix(check: Dictionary) -> String:
	var version := str(check.get("available_version", "")).strip_edges()
	return "" if version == "" else " (v" + version + ")"


## Manual fallback when no Host is paired. <source> is the directory holding the
## channel manifest recorded by the installer.
static func manual_command(installed_manifest: Dictionary, project_root_abs: String) -> String:
	var channel_path := GcWorkChannelModel.channel_manifest_path(installed_manifest)
	var source := channel_path.get_base_dir() if channel_path != "" else "<GC-work source>"
	var root := project_root_abs if project_root_abs.strip_edges() != "" else "<this project>"
	return "pwsh \"%s\" -Action Update -ProjectRoot \"%s\"" % [_windows_path(source.path_join("scripts").path_join("gc_work.ps1")), _windows_path(root.trim_suffix("/"))]


static func _windows_path(path: String) -> String:
	return path.replace("/", "\\")


## Startup notice for the result of the update this editor scheduled; {} when
## there is no scheduled id or the result is not for it (stale or forged).
static func startup_notice(result: Dictionary, scheduled_update_id: String) -> Dictionary:
	var expected := scheduled_update_id.strip_edges()
	if expected == "" or str(result.get("update_id", "")).strip_edges() != expected:
		return {}
	return result_notice(result)


static func result_notice(result: Dictionary) -> Dictionary:
	var update_id := str(result.get("update_id", "")).strip_edges()
	if update_id == "" or update_id.length() > 128:
		return {}
	match str(result.get("status", "")):
		"installed":
			return {"update_id": update_id, "tone": "ok", "text": "Updated to " + GcWorkChannelModel.short_build_id(str(result.get("to_build_id", ""))) + "."}
		"failed":
			var text := "Addon update failed: " + str(result.get("error", "unknown error")).left(400)
			if str(result.get("backup_path", "")) != "":
				text += "\nBackup: " + str(result.get("backup_path", "")).left(400)
			return {"update_id": update_id, "tone": "warn", "text": text}
		"cancelled":
			return {"update_id": update_id, "tone": "neutral", "text": "The scheduled addon update was cancelled."}
	return {"update_id": update_id, "tone": "warn", "text": "Unrecognized addon update result: " + str(result.get("status", "")).left(40)}


static func read_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_RESULT_BYTES:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}


static func scheduled_id_path(editor_data_dir: String, project_root_abs: String) -> String:
	if editor_data_dir.strip_edges() == "" or project_root_abs.strip_edges() == "":
		return ""
	var key := project_root_abs.strip_edges().replace("\\", "/").trim_suffix("/").to_lower().sha256_text().substr(0, 32)
	return editor_data_dir.path_join(SCHEDULED_ID_DIR).path_join(key + ".id")


static func write_scheduled_id(path: String, update_id: String) -> bool:
	var value := update_id.strip_edges()
	if path == "" or value == "" or value.length() > 128:
		return false
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(value)
	file.close()
	return true


static func clear_scheduled_id(path: String) -> void:
	if path != "" and FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


static func read_scheduled_id(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 256:
		return ""
	return file.get_as_text().strip_edges()
