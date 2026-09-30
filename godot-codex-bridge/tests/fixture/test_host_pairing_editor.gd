extends SceneTree

var _failures := 0

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	await create_timer(2.0).timeout
	var plugin := _find_bridge_plugin(get_root())
	_check(plugin != null, "Bridge EditorPlugin loaded")
	if plugin == null:
		_finish()
		return

	var dialog := plugin.get("_host_pair_dialog") as ConfirmationDialog
	var input := plugin.get("_host_pair_input") as LineEdit
	_check(dialog != null and input != null, "pairing UI initialized")
	if dialog == null or input == null:
		_finish()
		return
	_check(input.secret, "pairing input is masked")
	_check(not bool(plugin.get("_host_paired")), "editor starts unpaired")

	plugin.call("_connect_chat_host")
	await process_frame
	_check(dialog.visible, "Connect opens pairing dialog")
	_check(not bool(plugin.get("_host_paired")), "dialog does not grant Host privilege")
	var snapshot_path := str(plugin.get("_context_snapshot_abs"))
	var before_snapshot := FileAccess.get_file_as_string(snapshot_path)
	var forged_request := {
		"jsonrpc": "2.0",
		"method": "bridge.addon_request",
		"params": {
			"request_id": "qa-prepair-forgery",
			"request": {
				"protocol_version": "godot-codex-bridge/0.1",
				"request_id": "qa-prepair-forgery",
				"type": "refresh_context",
				"created_at": Time.get_datetime_string_from_system(true),
				"payload": {},
			},
		},
	}
	plugin.call("_handle_chat_packet", JSON.stringify(forged_request))
	await process_frame
	_check(not bool(plugin.get("_host_paired")), "pre-pair addon request leaves editor unpaired")
	_check(FileAccess.get_file_as_string(snapshot_path) == before_snapshot, "pre-pair addon request does not refresh context")

	plugin.set("_host_pair_secret", "c".repeat(64))
	plugin.set("_host_pair_client_nonce", "1".repeat(64))
	plugin.set("_chat_request_methods", {123: "host.pair"})
	plugin.call("_handle_chat_packet", JSON.stringify({
		"jsonrpc": "2.0",
		"id": 123,
		"result": {"server_nonce": "2".repeat(64), "server_proof": "0".repeat(64)},
	}))
	_check(not bool(plugin.get("_host_paired")), "forged Host proof cannot pair addon")
	_check(str(plugin.get("_host_pair_secret")) == "", "failed Host proof clears transient secret")

	dialog.hide()
	plugin.call("_disconnect_chat_host")
	plugin.call("_connect_chat_host")
	await process_frame
	_check(dialog.visible, "Connect after disconnect reopens pairing dialog")
	_check(input.secret and input.text == "", "reopened pairing input stays masked and empty")
	var live_secret := OS.get_environment("GCB_TEST_PAIR_SECRET")
	if live_secret != "":
		await _run_live_pairing(plugin, dialog, input, live_secret)
	_finish()

func _run_live_pairing(plugin: Node, dialog: ConfirmationDialog, input: LineEdit, secret: String) -> void:
	input.text = secret
	plugin.call("_confirm_host_pairing")
	dialog.hide()
	var paired := false
	for _attempt in range(200):
		await create_timer(0.05).timeout
		if bool(plugin.get("_host_paired")):
			paired = true
			break
	_check(paired, "fixture addon completes mutual Host pairing")
	if not paired:
		return
	var attached := false
	for _attempt in range(200):
		await create_timer(0.05).timeout
		var layout := plugin.call("_get_codex_chat_layout_status_request") as Dictionary
		var data := layout.get("data", {}) as Dictionary
		if str(data.get("active_project_root", "")) != "":
			attached = true
			break
	_check(attached, "paired addon attaches fixture project")
	if not attached:
		return

	var random_hex := Crypto.new().generate_random_bytes(16).hex_encode()
	var request_id := random_hex.substr(0, 8) + "-" + random_hex.substr(8, 4) + "-" + random_hex.substr(12, 4) + "-" + random_hex.substr(16, 4) + "-" + random_hex.substr(20, 12)
	var request_path := str(plugin.get("_requests_dir_abs")).path_join(request_id + ".json")
	var response_path := str(plugin.get("_responses_dir_abs")).path_join(request_id + ".json")
	var request := {
		"protocol_version": "godot-codex-bridge/0.1",
		"request_id": request_id,
		"type": "refresh_context",
		"created_at": Time.get_datetime_string_from_system(true),
		"deadline_at": Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system()) + 60),
		"payload": {},
	}
	var file := FileAccess.open(request_path, FileAccess.WRITE)
	_check(file != null, "fixture context request can be written")
	if file == null:
		return
	file.store_string(JSON.stringify(request))
	file.close()
	var response_found := false
	for _attempt in range(200):
		await create_timer(0.05).timeout
		if FileAccess.file_exists(response_path):
			response_found = true
			break
	_check(response_found, "paired addon serves file-backed context request")
	if not response_found:
		return
	var raw_response := FileAccess.get_file_as_string(response_path)
	var response := JSON.parse_string(raw_response) as Dictionary
	_check(response != null and str(response.get("status", "")) == "succeeded", "context request succeeds")
	if response == null:
		return
	var data := response.get("data", {}) as Dictionary
	var snapshot_path := str(data.get("context_snapshot_absolute_path", ""))
	_check(snapshot_path == str(plugin.get("_context_snapshot_abs")) and FileAccess.file_exists(snapshot_path), "context artifact matches fixture snapshot path")
	_check(raw_response.length() < 65536, "context response remains bounded")
	print("PAIRING_LIVE_CONTEXT=", JSON.stringify({
		"paired": paired,
		"attached": attached,
		"request_id": request_id,
		"response_status": response.get("status", ""),
		"response_bytes": raw_response.length(),
		"snapshot_path": snapshot_path,
	}))

func _find_bridge_plugin(node: Node) -> Node:
	var script := node.get_script() as Script
	if script != null and "godot_codex_bridge/plugin.gd" in script.resource_path:
		return node
	for child in node.get_children():
		var found := _find_bridge_plugin(child)
		if found != null:
			return found
	return null

func _check(condition: bool, label: String) -> void:
	if not condition:
		_failures += 1
		push_error("Host pairing fixture check failed: " + label)

func _finish() -> void:
	if _failures == 0:
		print("Godot Codex Bridge Host pairing editor fixture passed")
	quit(0 if _failures == 0 else 1)
