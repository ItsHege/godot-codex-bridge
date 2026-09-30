@tool
extends RefCounted

const DEFAULT_PORT := 49390
const DEFAULT_RUNTIME := "app-server"


static func missing_state(default_port := DEFAULT_PORT) -> Dictionary:
	return {
		"config": {},
		"status": "missing",
		"message": "Host connection config is missing. Refresh the addon install; no default port was used.",
		"runtime": "",
		"port": default_port,
		"launcher_path": "",
		"host_url": "",
	}


static func invalid_state(default_port := DEFAULT_PORT, reason := "Host connection config is invalid. Refresh the addon install.") -> Dictionary:
	return {
		"config": {},
		"status": "invalid",
		"message": reason,
		"runtime": "",
		"port": default_port,
		"launcher_path": "",
		"host_url": "",
	}


static func normalize_config(data: Dictionary, node_entry_exists: bool, start_script_exists: bool, default_port := DEFAULT_PORT) -> Dictionary:
	if str(data.get("protocol_version", "")) != "godot-codex-bridge/0.1":
		var bad_version := invalid_state(default_port, "Host connection protocol is missing or unsupported. Refresh the addon install.")
		bad_version["config"] = data
		return bad_version
	var port_value: Variant = data.get("port")
	var port := -1
	if typeof(port_value) == TYPE_INT or typeof(port_value) == TYPE_FLOAT:
		var numeric_port := float(port_value)
		if numeric_port >= 1.0 and numeric_port <= 65535.0 and numeric_port == floor(numeric_port):
			port = int(numeric_port)
	if port < 1:
		var bad_port := invalid_state(default_port, "Host connection port is missing or invalid. Refresh the addon install; no default port was used.")
		bad_port["config"] = data
		return bad_port
	var runtime_value: Variant = data.get("runtime")
	if typeof(runtime_value) != TYPE_STRING or not (str(runtime_value) in ["app-server", "mock"]):
		var bad_runtime := invalid_state(default_port, "Host runtime is missing or unsupported. Refresh the addon install; no default runtime was used.")
		bad_runtime["config"] = data
		return bad_runtime
	var runtime := str(runtime_value)
	var node_entry := str(data.get("node_entry", ""))
	var start_script := str(data.get("start_script", ""))
	var configured_launcher_exists := (node_entry != "" and node_entry_exists) or (start_script != "" and start_script_exists)
	var status := "manual_start_required"
	var message := "Automatic launch is disabled because project-local host_config.json is not executable authority. Start the Host from the trusted installation, then connect."
	var launcher_path := node_entry if node_entry != "" and node_entry_exists else start_script if start_script != "" and start_script_exists else ""
	var launcher_kind := "manual_only" if configured_launcher_exists else ""
	return {
		"config": data,
		"status": status,
		"message": message,
		"runtime": runtime,
		"port": port,
		"node_entry": node_entry,
		"start_script": start_script,
		"launcher_path": launcher_path,
		"launcher_kind": launcher_kind,
		"host_url": host_url(port),
	}


static func launch_plan(config: Dictionary, node_entry_exists: bool, start_script_exists: bool, default_port := DEFAULT_PORT) -> Dictionary:
	if config.is_empty():
		return {
			"ok": false,
			"error_code": "missing_config",
			"message": "Codex launcher config is missing. Refresh the addon install.",
		}
	var normalized := normalize_config(config, node_entry_exists, start_script_exists, default_port)
	var port := int(normalized.get("port", default_port))
	var runtime := str(normalized.get("runtime", DEFAULT_RUNTIME))
	return {
		"ok": false,
		"error_code": "automatic_launch_disabled",
		"message": "Automatic Host launch is disabled. Start it from the trusted installation, then connect.",
		"port": port,
		"runtime": runtime,
		"node_entry": str(normalized.get("node_entry", "")),
		"start_script": str(normalized.get("start_script", "")),
	}


static func host_url(port: int) -> String:
	var safe_port := port
	if safe_port <= 0:
		safe_port = DEFAULT_PORT
	return "ws://127.0.0.1:" + str(safe_port)
