extends SceneTree

const ChatHostCleanupModel := preload("res://addons/godot_codex_bridge/core/chat_host_cleanup_model.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge chat host cleanup model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge chat host cleanup model tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var artifact_dir := ChatHostCleanupModel.cleanup_artifact_dir("C:/project/.godot/godot_codex_bridge")
	_assert_eq(artifact_dir, "C:/project/.godot/godot_codex_bridge/artifacts/codex_host_cleanup", "cleanup artifact dir")
	var artifact_path := ChatHostCleanupModel.cleanup_artifact_path("C:/project/.godot/godot_codex_bridge", 12345)
	_assert_eq(artifact_path, "C:/project/.godot/godot_codex_bridge/artifacts/codex_host_cleanup/owned-host-cleanup-12345.json", "cleanup artifact path")
	_assert_eq(ChatHostCleanupModel.cleanup_artifact_dir(""), "", "empty cleanup dir")
	_assert_eq(ChatHostCleanupModel.cleanup_artifact_path("", 1), "", "empty cleanup path")

	var payload := ChatHostCleanupModel.cleanup_payload(
		"plugin_exit",
		42,
		true,
		true,
		true,
		true,
		OK,
		false,
		"C:/project",
		"C:/project/.godot/godot_codex_bridge",
		"2026-06-24T12:00:00"
	)
	_assert_eq(payload.get("cleanup_version"), "godot-codex-bridge/owned-host-cleanup-v1", "cleanup version")
	_assert_eq(payload.get("reason"), "plugin_exit", "cleanup reason")
	_assert_eq(payload.get("process_id"), 42, "cleanup process id")
	_assert_true(bool(payload.get("owned_by_addon", false)), "cleanup owned flag")
	_assert_true(bool(payload.get("graceful_shutdown_requested", false)), "cleanup graceful flag")
	_assert_true(bool(payload.get("process_was_alive_before_kill", false)), "cleanup alive before")
	_assert_true(bool(payload.get("kill_attempted", false)), "cleanup kill attempted")
	_assert_eq(payload.get("kill_error"), "", "cleanup ok kill error")
	_assert_false(bool(payload.get("process_alive_after", true)), "cleanup alive after")
	_assert_eq(payload.get("project_root"), "C:/project", "cleanup project root")
	_assert_eq(payload.get("bridge_dir"), "C:/project/.godot/godot_codex_bridge", "cleanup bridge dir")
	_assert_eq(payload.get("created_at"), "2026-06-24T12:00:00", "cleanup created at")

	var failed_payload := ChatHostCleanupModel.cleanup_payload(
		"startup_timeout",
		100,
		true,
		false,
		false,
		false,
		ERR_CANT_CREATE,
		false,
		"C:/project",
		"C:/project/.godot/godot_codex_bridge",
		"2026-06-24T12:00:00"
	)
	_assert_true(str(failed_payload.get("kill_error", "")).length() > 0, "cleanup failed kill error string")


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
