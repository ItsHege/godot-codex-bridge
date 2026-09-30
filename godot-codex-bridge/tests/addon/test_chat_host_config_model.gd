extends SceneTree

const ChatHostConfigModel := preload("res://addons/godot_codex_bridge/core/chat_host_config_model.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge chat host config model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge chat host config model tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var missing := ChatHostConfigModel.missing_state(49390)
	_assert_eq(str(missing.get("status", "")), "missing", "missing status")
	_assert_eq(str(missing.get("host_url", "")), "", "missing config has no connection target")

	var invalid := ChatHostConfigModel.invalid_state(49390)
	_assert_eq(str(invalid.get("status", "")), "invalid", "invalid status")

	var bad_data := {
		"protocol_version": "godot-codex-bridge/0.1",
		"port": -1,
		"runtime": "",
		"node_entry": "C:/bridge/codex_host/dist/src/index.js",
		"start_script": "C:/bridge/scripts/start_codex_host.ps1",
	}
	var rejected := ChatHostConfigModel.normalize_config(bad_data, true, true, 49390)
	_assert_eq(str(rejected.get("status", "")), "invalid", "bad connection config is rejected")
	_assert_eq(str(rejected.get("host_url", "x")), "", "bad connection config has no target")
	_assert_true(str(rejected.get("message", "")).contains("port"), "bad port is actionable")
	var data := bad_data.duplicate()
	data["port"] = 49390
	data["runtime"] = "app-server"
	var normalized_node := ChatHostConfigModel.normalize_config(data, true, true, 49390)
	_assert_eq(str(normalized_node.get("status", "")), "manual_start_required", "node config requires manual start")
	_assert_eq(str(normalized_node.get("launcher_kind", "")), "manual_only", "project launcher is not executable authority")
	_assert_eq(int(normalized_node.get("port", 0)), 49390, "valid port retained")
	_assert_eq(str(normalized_node.get("runtime", "")), "app-server", "valid runtime retained")
	_assert_eq(str(normalized_node.get("host_url", "")), "ws://127.0.0.1:49390", "host url from reviewed config port")
	var json_data: Dictionary = JSON.parse_string('{"protocol_version":"godot-codex-bridge/0.1","port":49390,"runtime":"mock"}')
	_assert_eq(str(ChatHostConfigModel.normalize_config(json_data, false, false).get("status", "")), "manual_start_required", "JSON numeric port is accepted without launcher path")
	var bad_runtime := data.duplicate()
	bad_runtime["runtime"] = "unknown"
	_assert_eq(str(ChatHostConfigModel.normalize_config(bad_runtime, true, true).get("status", "")), "invalid", "unsupported runtime rejected")
	var bad_version := data.duplicate()
	bad_version["protocol_version"] = "unsupported"
	_assert_eq(str(ChatHostConfigModel.normalize_config(bad_version, true, true).get("status", "")), "invalid", "unsupported protocol rejected")

	var node_plan := ChatHostConfigModel.launch_plan(data, true, true, 49390)
	_assert_false(bool(node_plan.get("ok", true)), "node launch plan is disabled")
	_assert_eq(str(node_plan.get("error_code", "")), "automatic_launch_disabled", "node launch disabled code")

	var normalized_script := ChatHostConfigModel.normalize_config(data, false, true, 49390)
	_assert_eq(str(normalized_script.get("launcher_kind", "")), "manual_only", "start script is manual only")
	var script_plan := ChatHostConfigModel.launch_plan(data, false, true, 49390)
	_assert_false(bool(script_plan.get("ok", true)), "script launch plan is disabled")
	_assert_eq(str(script_plan.get("error_code", "")), "automatic_launch_disabled", "script launch disabled code")

	var missing_launcher := ChatHostConfigModel.launch_plan(data, false, false, 49390)
	_assert_false(bool(missing_launcher.get("ok", true)), "missing launcher plan fails")
	_assert_eq(str(missing_launcher.get("error_code", "")), "automatic_launch_disabled", "missing launcher remains non-executable")

	var no_config := ChatHostConfigModel.launch_plan({}, false, false, 49390)
	_assert_false(bool(no_config.get("ok", true)), "empty config plan fails")
	_assert_eq(str(no_config.get("error_code", "")), "missing_config", "missing config code")

	_assert_eq(ChatHostConfigModel.host_url(0), "ws://127.0.0.1:49390", "host url protects invalid port")


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
