@tool
extends RefCounted

const DEFAULT_PORT := 49390
const DEFAULT_RUNTIME := "app-server"


static func missing_state(default_port := DEFAULT_PORT) -> Dictionary:
	return {
		"config": {},
		"status": "missing",
		"message": "Launcher config missing. Refresh the addon install.",
		"runtime": "",
		"port": default_port,
		"launcher_path": "",
		"host_url": host_url(default_port),
	}


static func invalid_state(default_port := DEFAULT_PORT) -> Dictionary:
	return {
		"config": {},
		"status": "invalid",
		"message": "Launcher config is invalid JSON.",
		"runtime": "",
		"port": default_port,
		"launcher_path": "",
		"host_url": host_url(default_port),
	}


static func normalize_config(data: Dictionary, node_entry_exists: bool, start_script_exists: bool, default_port := DEFAULT_PORT) -> Dictionary:
	var port := int(data.get("port", default_port))
	if port <= 0:
		port = default_port
	var runtime := str(data.get("runtime", DEFAULT_RUNTIME))
	if runtime.strip_edges() == "":
		runtime = DEFAULT_RUNTIME
	var node_entry := str(data.get("node_entry", ""))
	var start_script := str(data.get("start_script", ""))
	var status := "launcher_missing"
	var message := "Launcher files are missing. Refresh the addon install."
	var launcher_path := ""
	var launcher_kind := ""
	if node_entry != "" and node_entry_exists:
		status = "ok"
		message = "Launcher ready via node entry."
		launcher_path = node_entry
		launcher_kind = "node_entry"
	elif start_script != "" and start_script_exists:
		status = "ok"
		message = "Launcher ready via start script."
		launcher_path = start_script
		launcher_kind = "start_script"
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
	var launcher_kind := str(normalized.get("launcher_kind", ""))
	if launcher_kind == "node_entry":
		return {
			"ok": true,
			"launcher_kind": launcher_kind,
			"executable": "node",
			"args": PackedStringArray([
				str(normalized.get("node_entry", "")),
				"--port",
				str(port),
				"--runtime",
				runtime,
			]),
			"port": port,
			"runtime": runtime,
			"node_entry": str(normalized.get("node_entry", "")),
			"start_script": str(normalized.get("start_script", "")),
		}
	if launcher_kind == "start_script":
		return {
			"ok": true,
			"launcher_kind": launcher_kind,
			"executable": "powershell.exe",
			"args": PackedStringArray([
				"-NoProfile",
				"-ExecutionPolicy",
				"Bypass",
				"-File",
				str(normalized.get("start_script", "")),
				"-Port",
				str(port),
				"-Runtime",
				runtime,
			]),
			"port": port,
			"runtime": runtime,
			"node_entry": str(normalized.get("node_entry", "")),
			"start_script": str(normalized.get("start_script", "")),
		}
	return {
		"ok": false,
		"error_code": "launcher_missing",
		"message": "Codex launcher files were not found. Refresh the addon install.",
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
