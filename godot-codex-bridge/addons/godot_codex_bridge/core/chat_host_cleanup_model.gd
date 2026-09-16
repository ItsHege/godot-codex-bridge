@tool
extends RefCounted


static func cleanup_artifact_dir(bridge_dir_abs: String) -> String:
	if bridge_dir_abs.strip_edges() == "":
		return ""
	return bridge_dir_abs.path_join("artifacts").path_join("codex_host_cleanup")


static func cleanup_artifact_path(bridge_dir_abs: String, timestamp_msec: int) -> String:
	var artifact_dir := cleanup_artifact_dir(bridge_dir_abs)
	if artifact_dir == "":
		return ""
	return artifact_dir.path_join("owned-host-cleanup-" + str(max(timestamp_msec, 0)) + ".json")


static func cleanup_payload(
	reason: String,
	process_id: int,
	owned_by_addon: bool,
	graceful_requested: bool,
	process_was_alive_before_kill: bool,
	kill_attempted: bool,
	kill_error: int,
	process_alive_after: bool,
	project_root: String,
	bridge_dir: String,
	created_at: String
) -> Dictionary:
	return {
		"cleanup_version": "godot-codex-bridge/owned-host-cleanup-v1",
		"reason": reason,
		"process_id": process_id,
		"owned_by_addon": owned_by_addon,
		"graceful_shutdown_requested": graceful_requested,
		"process_was_alive_before_kill": process_was_alive_before_kill,
		"kill_attempted": kill_attempted,
		"kill_error": error_string(kill_error) if kill_error != OK else "",
		"process_alive_after": process_alive_after,
		"project_root": project_root,
		"bridge_dir": bridge_dir,
		"created_at": created_at,
	}
