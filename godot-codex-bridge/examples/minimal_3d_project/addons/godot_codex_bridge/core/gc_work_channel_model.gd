@tool
extends RefCounted

const INSTALL_MANIFEST_PATH := "res://addons/godot_codex_bridge/install_manifest.json"
const CHANNEL_FILE_NAME := "GC_WORK_CHANNEL.json"
const MAX_MANIFEST_BYTES := 65536


static func load_manifest(path: String) -> Dictionary:
	var normalized := path.strip_edges()
	if normalized == "" or not FileAccess.file_exists(normalized):
		return {}
	var file := FileAccess.open(normalized, FileAccess.READ)
	if file == null or file.get_length() > MAX_MANIFEST_BYTES:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return (parsed as Dictionary).duplicate(true)


static func channel_manifest_path(installed: Dictionary) -> String:
	var path := str(installed.get("channel_manifest_path", "")).strip_edges()
	if path == "" or not path.is_absolute_path() or path.get_file() != CHANNEL_FILE_NAME:
		return ""
	return path


static func status(installed: Dictionary, available: Dictionary = {}) -> Dictionary:
	if installed.is_empty():
		return {
			"state": "unmanaged",
			"label": "Addon: unmanaged",
			"tone": "warn",
			"tooltip": "This addon copy has no installation provenance. Run the GC-work updater to install one exact reviewed build.",
		}
	var channel := str(installed.get("channel", "stable")).strip_edges()
	var installed_build := str(installed.get("build_id", "")).strip_edges()
	var version := str(installed.get("addon_version", "unknown")).strip_edges()
	if channel != "GC-work":
		return {
			"state": "stable",
			"label": channel + " · " + version,
			"tone": "neutral",
			"tooltip": "Installed addon channel: " + channel + "\nVersion: " + version,
		}
	if available.is_empty():
		return {
			"state": "source_unavailable",
			"label": "GC-work · " + short_build_id(installed_build),
			"tone": "warn",
			"tooltip": "Installed GC-work build: " + installed_build + "\nThe local GC-work channel manifest is unavailable, so update status cannot be checked.",
		}
	var available_build := str(available.get("build_id", "")).strip_edges()
	var current := installed_build != "" and installed_build == available_build
	return {
		"state": "current" if current else "update_available",
		"label": "GC-work · " + (short_build_id(installed_build) if current else "UPDATE"),
		"tone": "ok" if current else "warn",
		"tooltip": (
			"GC-work is current.\nBuild: " + installed_build
			if current
			else "A newer reviewed GC-work build is available.\nInstalled: " + installed_build + "\nAvailable: " + available_build
		),
	}


static func short_build_id(build_id: String) -> String:
	var value := build_id.strip_edges()
	if value.contains(":"):
		value = value.get_slice(":", value.get_slice_count(":") - 1)
	if value == "":
		return "unknown"
	return value.substr(0, mini(8, value.length()))
