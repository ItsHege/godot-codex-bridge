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
	_assert_eq(str(missing.get("host_url", "")), "ws://127.0.0.1:49390", "missing host url")

	var invalid := ChatHostConfigModel.invalid_state(49390)
	_assert_eq(str(invalid.get("status", "")), "invalid", "invalid status")

	var data := {
		"port": -1,
		"runtime": "",
		"node_entry": "C:/bridge/codex_host/dist/src/index.js",
		"start_script": "C:/bridge/scripts/start_codex_host.ps1",
	}
	var normalized_node := ChatHostConfigModel.normalize_config(data, true, true, 49390)
	_assert_eq(str(normalized_node.get("status", "")), "ok", "node status ok")
	_assert_eq(str(normalized_node.get("launcher_kind", "")), "node_entry", "node entry preferred")
	_assert_eq(int(normalized_node.get("port", 0)), 49390, "bad port falls back")
	_assert_eq(str(normalized_node.get("runtime", "")), "app-server", "blank runtime falls back")
	_assert_eq(str(normalized_node.get("host_url", "")), "ws://127.0.0.1:49390", "host url from fallback port")

	var node_plan := ChatHostConfigModel.launch_plan(data, true, true, 49390)
	_assert_true(bool(node_plan.get("ok", false)), "node launch plan ok")
	_assert_eq(str(node_plan.get("executable", "")), "node", "node executable")
	var node_args: PackedStringArray = node_plan.get("args", PackedStringArray())
	_assert_eq(node_args[0], "C:/bridge/codex_host/dist/src/index.js", "node arg entry path")
	_assert_eq(node_args[1], "--port", "node arg port flag")

	var normalized_script := ChatHostConfigModel.normalize_config(data, false, true, 49390)
	_assert_eq(str(normalized_script.get("launcher_kind", "")), "start_script", "start script fallback")
	var script_plan := ChatHostConfigModel.launch_plan(data, false, true, 49390)
	_assert_true(bool(script_plan.get("ok", false)), "script launch plan ok")
	_assert_eq(str(script_plan.get("executable", "")), "powershell.exe", "script executable")
	var script_args: PackedStringArray = script_plan.get("args", PackedStringArray())
	_assert_true(script_args.has("-ExecutionPolicy"), "script args include execution policy")
	_assert_true(script_args.has("-Runtime"), "script args include runtime flag")

	var missing_launcher := ChatHostConfigModel.launch_plan(data, false, false, 49390)
	_assert_false(bool(missing_launcher.get("ok", true)), "missing launcher plan fails")
	_assert_eq(str(missing_launcher.get("error_code", "")), "launcher_missing", "missing launcher code")

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
