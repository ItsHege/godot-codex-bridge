@tool
extends RefCounted

const CUSTOM_PROFILE_ID := "custom"

const PERMISSION_KEYS := [
	"allow_screenshots",
	"allow_ai_markers",
	"allow_open_scene",
	"allow_run_current_scene",
	"allow_playtest_input",
	"allow_fix_selected_node",
	"allow_editor_navigation",
	"allow_editor_inspect",
	"allow_editor_diagnostics",
	"allow_clear_diagnostics",
	"allow_animation_preview",
	"allow_scene_edits",
	"allow_scene_save",
	"allow_bridge_notes",
	"allow_send_context",
	"allow_codex_chat",
	"allow_background_team_review",
	"allow_full_trust_session",
]

const PROFILES := [
	{
		"id": "read_only",
		"label": "Read Only",
		"description": "Read project/editor context and chat. No screenshots, navigation, scene run, edits or saves.",
		"enabled": [
			"allow_editor_inspect",
			"allow_editor_diagnostics",
			"allow_bridge_notes",
			"allow_send_context",
			"allow_codex_chat",
		],
	},
	{
		"id": "navigate",
		"label": "Navigate",
		"description": "Read Only plus safe editor navigation: open scenes, focus panels and select/inspect nodes. No screenshots, runs, edits or saves.",
		"enabled": [
			"allow_open_scene",
			"allow_editor_navigation",
			"allow_editor_inspect",
			"allow_editor_diagnostics",
			"allow_bridge_notes",
			"allow_send_context",
			"allow_codex_chat",
		],
	},
	{
		"id": "diagnose",
		"label": "Diagnose",
		"description": "Navigate plus local screenshots, AI markers and background review. No scene execution, edits, clears or saves.",
		"enabled": [
			"allow_screenshots",
			"allow_ai_markers",
			"allow_open_scene",
			"allow_editor_navigation",
			"allow_editor_inspect",
			"allow_editor_diagnostics",
			"allow_bridge_notes",
			"allow_send_context",
			"allow_codex_chat",
			"allow_background_team_review",
		],
	},
	{
		"id": "scene_edit",
		"label": "Scene Edit",
		"description": "Diagnose plus UndoRedo-backed scene edits, selected-node fixes, animation preview and scene run. No save.",
		"enabled": [
			"allow_screenshots",
			"allow_ai_markers",
			"allow_open_scene",
			"allow_run_current_scene",
			# P11 playtest input remains manual-only until the safety sign-off slice.
			"allow_fix_selected_node",
			"allow_editor_navigation",
			"allow_editor_inspect",
			"allow_editor_diagnostics",
			"allow_animation_preview",
			"allow_scene_edits",
			"allow_bridge_notes",
			"allow_send_context",
			"allow_codex_chat",
			"allow_background_team_review",
		],
	},
	{
		"id": "save",
		"label": "Save",
		"description": "Scene Edit plus clear Bridge diagnostics and explicit scene save. File diff/apply approvals still remain separate.",
		"enabled": [
			"allow_screenshots",
			"allow_ai_markers",
			"allow_open_scene",
			"allow_run_current_scene",
			# P11 playtest input remains manual-only until the safety sign-off slice.
			"allow_fix_selected_node",
			"allow_editor_navigation",
			"allow_editor_inspect",
			"allow_editor_diagnostics",
			"allow_clear_diagnostics",
			"allow_animation_preview",
			"allow_scene_edits",
			"allow_scene_save",
			"allow_bridge_notes",
			"allow_send_context",
			"allow_codex_chat",
			"allow_background_team_review",
		],
	},
	{
		"id": "full_trust",
		"label": "Full Trust",
		"description": "All addon permissions for this project. Codex Host full-machine Trust Session is still controlled by the separate Trust toggle.",
		"enabled": [
			"allow_screenshots",
			"allow_ai_markers",
			"allow_open_scene",
			"allow_run_current_scene",
			# P11 playtest input remains manual-only until the safety sign-off slice.
			"allow_fix_selected_node",
			"allow_editor_navigation",
			"allow_editor_inspect",
			"allow_editor_diagnostics",
			"allow_clear_diagnostics",
			"allow_animation_preview",
			"allow_scene_edits",
			"allow_scene_save",
			"allow_bridge_notes",
			"allow_send_context",
			"allow_codex_chat",
			"allow_background_team_review",
			"allow_full_trust_session",
		],
	},
]


static func permission_keys() -> Array:
	return PERMISSION_KEYS.duplicate()


static func profiles() -> Array:
	return PROFILES.duplicate(true)


static func profile_ids() -> Array[String]:
	var ids: Array[String] = []
	for profile in PROFILES:
		ids.append(str((profile as Dictionary).get("id", "")))
	return ids


static func profile_for_id(profile_id: String) -> Dictionary:
	var normalized := profile_id.strip_edges().to_lower()
	for profile in PROFILES:
		var profile_dict := profile as Dictionary
		if str(profile_dict.get("id", "")) == normalized:
			return profile_dict.duplicate(true)
	return {
		"id": CUSTOM_PROFILE_ID,
		"label": "Custom",
		"description": "Manual permission mix.",
		"enabled": [],
	}


static func permissions_for_profile(profile_id: String) -> Dictionary:
	var profile := profile_for_id(profile_id)
	var enabled := {}
	var enabled_value: Variant = profile.get("enabled", [])
	if typeof(enabled_value) == TYPE_ARRAY:
		for key in enabled_value as Array:
			enabled[str(key)] = true
	var permissions := {}
	for key in PERMISSION_KEYS:
		permissions[key] = bool(enabled.get(key, false))
	return permissions


static func profile_metadata(profile_id: String) -> Dictionary:
	var profile := profile_for_id(profile_id)
	return {
		"profile_id": str(profile.get("id", CUSTOM_PROFILE_ID)),
		"profile_label": str(profile.get("label", "Custom")),
		"profile_description": str(profile.get("description", "Manual permission mix.")),
	}


static func matching_profile_id(permissions: Dictionary) -> String:
	for profile in PROFILES:
		var profile_id := str((profile as Dictionary).get("id", ""))
		if _permissions_match(permissions, permissions_for_profile(profile_id)):
			return profile_id
	return CUSTOM_PROFILE_ID


static func current_profile_metadata(permissions: Dictionary) -> Dictionary:
	return profile_metadata(matching_profile_id(permissions))


static func with_known_keys_only(permissions: Dictionary) -> Dictionary:
	var normalized := {}
	for key in PERMISSION_KEYS:
		normalized[key] = bool(permissions.get(key, false))
	return normalized


static func unknown_permission_keys(permissions: Dictionary) -> Array[String]:
	var known := {}
	for key in PERMISSION_KEYS:
		known[key] = true
	var unknown: Array[String] = []
	for key in permissions.keys():
		var key_string := str(key)
		if not known.has(key_string):
			unknown.append(key_string)
	unknown.sort()
	return unknown


static func _permissions_match(actual: Dictionary, expected: Dictionary) -> bool:
	for key in PERMISSION_KEYS:
		if bool(actual.get(key, false)) != bool(expected.get(key, false)):
			return false
	return true
