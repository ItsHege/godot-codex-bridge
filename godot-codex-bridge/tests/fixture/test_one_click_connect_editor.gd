extends SceneTree

## Headless editor check of the one-click Connect plan without launching a Host:
## LOCALAPPDATA is pointed at a scratch folder for this process only.
##   Godot_console.exe --headless --editor --path examples/minimal_3d_project --script tests/fixture/test_one_click_connect_editor.gd

const Model := preload("res://addons/godot_codex_bridge/core/trusted_host_launch_model.gd")
const FINGERPRINT := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

var failures := 0
var _plugin: Node
var _scratch := ""


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await create_timer(2.0).timeout
	_plugin = _find_plugin(get_root())
	_check(_plugin != null, "Bridge plugin loaded")
	if _plugin == null:
		quit(1)
		return
	(_plugin.get("_permissions") as Dictionary)["allow_codex_chat"] = true
	# Outside the project: a trust record naming files inside it is rejected.
	_scratch = OS.get_user_data_dir().path_join("one_click_" + str(Time.get_ticks_usec()))
	DirAccess.make_dir_recursive_absolute(_scratch)
	var previous_local := OS.get_environment("LOCALAPPDATA")
	OS.set_environment("LOCALAPPDATA", _scratch)

	# 1. No trust record: setup command, manual pairing dialog, nothing launched.
	_plugin.call("_connect_chat_host")
	_check(not bool(_plugin.get("_one_click_waiting")) and int(_plugin.get("_one_click_launcher_pid")) == -1, "no record: nothing launched")
	_check(_chat_text().contains("<Bridge install>") and _chat_text().contains("-Trust"), "no record: fixed setup command shown")
	_check((_plugin.get("_host_pair_dialog") as Window).visible, "no record: manual pairing dialog offered")
	(_plugin.get("_host_pair_dialog") as Window).hide()

	# 2. Valid record but a Host already listens on its port: no launch.
	var server := TCPServer.new()
	var port := 0
	for candidate in range(49600, 49700):
		if server.listen(candidate, "127.0.0.1") == OK:
			port = candidate
			break
	_check(port > 0, "test listener started")
	_write_record(port)
	_plugin.call("_connect_chat_host")
	_check(not bool(_plugin.get("_one_click_waiting")) and _chat_text().contains("already running"), "running Host without secret: paste-code path, no launch")
	(_plugin.get("_host_pair_dialog") as Window).hide()
	server.stop()

	# 3. Launch status handling (the launch itself is simulated).
	var record: Dictionary = Model.validate_record(Model.read_json(Model.record_path(_scratch)), ProjectSettings.globalize_path("res://")).get("record", {})
	_check(not record.is_empty(), "scratch trust record validates")
	_simulate_launch(record)
	_write_status({"status": "starting"})
	_plugin.call("_poll_one_click_launch")
	_check(bool(_plugin.get("_one_click_waiting")), "starting keeps waiting")
	_write_status({"status": "fingerprint_changed", "fingerprint": "f".repeat(64)})
	_plugin.call("_poll_one_click_launch")
	var retrust := _plugin.get("_retrust_dialog") as ConfirmationDialog
	_check(retrust != null and retrust.visible and retrust.dialog_text.contains("changed since you trusted them") and retrust.dialog_text.contains("f".repeat(64)), "fingerprint change asks to re-trust")
	_check(str(_plugin.get("_one_click_secret")) == "", "secret dropped when nothing was started")
	if retrust != null:
		retrust.hide()
	# A changed start script: no in-addon re-trust and no launch.
	var script_path := str(record.get("start_script", ""))
	var original := FileAccess.get_file_as_string(script_path)
	var tamper := FileAccess.open(script_path, FileAccess.WRITE)
	tamper.store_string("changed")
	tamper.close()
	_simulate_launch(record)
	_write_status({"status": "fingerprint_changed", "fingerprint": "e".repeat(64)})
	_plugin.call("_poll_one_click_launch")
	_check(retrust != null and not retrust.visible and _chat_text().contains("start script changed"), "changed start script: re-trust refused")
	_plugin.call("_forget_one_click_session")
	_check(not bool(_plugin.call("_launch_trusted_host", record)) and int(_plugin.get("_one_click_launcher_pid")) == -1, "changed start script: launch refused")
	var restore := FileAccess.open(script_path, FileAccess.WRITE)
	restore.store_string(original)
	restore.close()
	_simulate_launch(record)
	_write_status({"status": "untrusted", "message": "Not trusted."})
	_plugin.call("_poll_one_click_launch")
	_check(not bool(_plugin.get("_one_click_waiting")) and _chat_text().contains("Setup:"), "untrusted explains setup")
	_simulate_launch(record)
	_write_status({"status": "ready", "port": 1, "host_pid": 1234})
	_plugin.call("_poll_one_click_launch")
	_check(str(_plugin.get("_one_click_url")).ends_with(":" + str(port)) and str(_plugin.get("_host_pair_secret")) == "a".repeat(64), "ready connects to the reported port with the launch secret")
	_check(int(_plugin.get("_one_click_host_pid")) == 1234 and bool(_plugin.get("_one_click_owned")), "ready records the owned Host pid")

	_plugin.call("_disconnect_chat_host", false, "fixture")
	_plugin.call("_forget_one_click_session")
	OS.set_environment("LOCALAPPDATA", previous_local)
	_remove_tree(_scratch)
	print("ONE_CLICK_RESULT=", JSON.stringify({"failures": failures}))
	quit(0 if failures == 0 else 1)


func _simulate_launch(record: Dictionary) -> void:
	_plugin.set("_one_click_record", record)
	_plugin.set("_one_click_secret", "a".repeat(64))
	_plugin.set("_one_click_launcher_pid", OS.get_process_id())
	_plugin.set("_one_click_launched_unix", Time.get_unix_time_from_system())
	_plugin.set("_one_click_deadline_msec", Time.get_ticks_msec() + 30000)
	_plugin.set("_one_click_waiting", true)


func _write_record(port: int) -> void:
	var install := _scratch.path_join("install")
	DirAccess.make_dir_recursive_absolute(install.path_join("scripts"))
	for name in ["scripts/start_codex_host.ps1", "pwsh.exe", "node.exe", "codex.exe"]:
		var file := FileAccess.open(install.path_join(name), FileAccess.WRITE)
		file.store_string("placeholder")
		file.close()
	var record := {
		"schema_version": "trusted-host/1",
		"install_root": install,
		"start_script": install.path_join("scripts/start_codex_host.ps1"),
		"powershell_executable": install.path_join("pwsh.exe"),
		"node_executable": install.path_join("node.exe"),
		"codex_executable": install.path_join("codex.exe"),
		"runtime": "mock",
		"port": port,
		"fingerprint": FINGERPRINT,
		"start_script_sha256": FileAccess.get_sha256(install.path_join("scripts/start_codex_host.ps1")),
	}
	DirAccess.make_dir_recursive_absolute(Model.record_path(_scratch).get_base_dir())
	var out := FileAccess.open(Model.record_path(_scratch), FileAccess.WRITE)
	out.store_string(JSON.stringify(record))
	out.close()


func _write_status(fields: Dictionary) -> void:
	var path := Model.launch_status_path(_scratch, OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var status := fields.duplicate()
	status["updated_at"] = Time.get_datetime_string_from_system(true) + "Z"
	var out := FileAccess.open(path, FileAccess.WRITE)
	out.store_string(JSON.stringify(status))
	out.close()


func _chat_text() -> String:
	var parts: Array[String] = []
	_collect_text(_plugin.get("_chat_dock") as Node, parts)
	return "\n".join(parts)


func _collect_text(node: Node, parts: Array[String]) -> void:
	if node == null:
		return
	if node is RichTextLabel:
		parts.append((node as RichTextLabel).get_parsed_text())
	elif node is Label:
		parts.append((node as Label).text)
	for child in node.get_children():
		_collect_text(child, parts)


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for name in dir.get_files():
		DirAccess.remove_absolute(path.path_join(name))
	for name in dir.get_directories():
		_remove_tree(path.path_join(name))
	DirAccess.remove_absolute(path)


func _find_plugin(node: Node) -> Node:
	var script := node.get_script() as Script
	if script != null and "godot_codex_bridge/plugin.gd" in script.resource_path:
		return node
	for child in node.get_children():
		var found := _find_plugin(child)
		if found != null:
			return found
	return null


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
	else:
		print("PASS ", label)
