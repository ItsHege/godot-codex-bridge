extends SceneTree

const Journal := preload("res://addons/godot_codex_bridge/core/bridge_request_journal.gd")


func _initialize() -> void:
	var directory := OS.get_environment("GCB_JOURNAL_RACE_DIR")
	var request: Variant = JSON.parse_string(OS.get_environment("GCB_JOURNAL_RACE_REQUEST_JSON"))
	if directory == "" or typeof(request) != TYPE_DICTIONARY:
		print("CLAIM_RACE_STATE=invalid_setup")
		quit(2)
		return
	var journal := Journal.new(directory, Callable(self, "_validate_path"))
	var result := journal.begin(request as Dictionary)
	print("CLAIM_RACE_STATE=", str(result.get("state", (result.get("error", {}) as Dictionary).get("code", "error"))))
	quit(0)


func _validate_path(_path: String, _allow_missing: bool) -> Dictionary:
	return {"ok": true}
