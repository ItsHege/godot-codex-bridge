@tool
extends RefCounted

const BridgeContext := preload("bridge_context.gd")

var _context: BridgeContext
var _action_executor: Callable = Callable()
var _handlers: Dictionary = {}
var _max_batch_actions := 12
var _context_snapshot_path := ".godot/godot_codex_bridge/context_snapshot.json"


func _init(
	context: BridgeContext = null,
	action_executor: Callable = Callable(),
	max_batch_actions := 12,
	context_snapshot_path := ".godot/godot_codex_bridge/context_snapshot.json"
) -> void:
	_context = context
	_action_executor = action_executor
	_max_batch_actions = max(1, max_batch_actions)
	_context_snapshot_path = context_snapshot_path


func register_action(action: String, handler: Callable) -> void:
	var clean_action := action.strip_edges()
	if clean_action == "" or not handler.is_valid():
		return
	_handlers[clean_action] = handler


func handle_request(request_id: String, payload: Dictionary) -> Dictionary:
	var started_msec := Time.get_ticks_msec()
	var action := str(payload.get("action", "")).strip_edges()
	if action == "":
		return _err_result("invalid_request", "editor_control payload requires an action.")

	var params_value: Variant = payload.get("params", {})
	if typeof(params_value) != TYPE_DICTIONARY:
		return _err_result("invalid_request", "editor_control params must be an object.")
	var params: Dictionary = params_value

	var result := execute_action(action, params)
	return finalize_action_result(request_id, action, result, started_msec)


# Shared by the synchronous dispatcher and async request-file actions so both
# return the same editor_control response envelope.
func finalize_action_result(request_id: String, action: String, result: Dictionary, started_msec: int) -> Dictionary:
	var latency_ms := Time.get_ticks_msec() - started_msec
	if result.get("ok", false):
		var data: Dictionary = result.get("data", {})
		data["action"] = action
		data["request_id"] = request_id
		data["latency_ms"] = latency_ms
		if not data.has("snapshot_refreshed"):
			data["snapshot_refreshed"] = false
		_record_action(action, "succeeded", data)
		return {
			"ok": true,
			"data": data,
		}

	var raw_error: Variant = result.get("error", {})
	var error: Dictionary = {}
	if typeof(raw_error) == TYPE_DICTIONARY and not (raw_error as Dictionary).is_empty():
		error = raw_error
	else:
		error = _error_payload(
			"editor_control_failed",
			"Editor control action failed without a structured error. Raw result: " + _truncate_string(JSON.stringify(result), 512)
		)
	_record_action(action, "failed", {"error": error, "latency_ms": latency_ms})
	return {
		"ok": false,
		"error": error,
	}


func execute_action(action: String, params: Dictionary) -> Dictionary:
	if action == "editor_batch":
		return _editor_batch_request(params)
	if _handlers.has(action):
		var handler: Callable = _handlers[action]
		var handler_result: Variant = handler.call(params)
		if typeof(handler_result) == TYPE_DICTIONARY:
			return handler_result
		return _err_result("invalid_editor_control_result", "Editor control action returned a non-object result.")
	if not _action_executor.is_valid():
		return _err_result("unsupported_editor_action", "Unsupported editor_control action: " + action)
	var result: Variant = _action_executor.call(action, params)
	if typeof(result) == TYPE_DICTIONARY:
		return result
	return _err_result("invalid_editor_control_result", "Editor control action returned a non-object result.")


func _editor_batch_request(params: Dictionary) -> Dictionary:
	var actions_value: Variant = params.get("actions", [])
	if typeof(actions_value) != TYPE_ARRAY:
		return _err_result("invalid_batch", "editor_batch actions must be an array.")
	var actions: Array = actions_value
	if actions.is_empty():
		return _err_result("invalid_batch", "editor_batch requires at least one action.")
	if actions.size() > _max_batch_actions:
		return _err_result("too_many_batch_actions", "editor_batch supports at most " + str(_max_batch_actions) + " actions.")

	var stop_on_error := bool(params.get("stopOnError", params.get("stop_on_error", true)))
	var results: Array = []
	var any_error := false
	for index in range(actions.size()):
		var item: Variant = actions[index]
		if typeof(item) != TYPE_DICTIONARY:
			any_error = true
			results.append({"index": index, "status": "failed", "error": _error_payload("invalid_batch_action", "Batch action must be an object.")})
			if stop_on_error:
				break
			continue
		var action_item: Dictionary = item
		var action := str(action_item.get("action", "")).strip_edges()
		if action == "editor_batch":
			any_error = true
			results.append({"index": index, "action": action, "status": "failed", "error": _error_payload("nested_batch_rejected", "Nested editor_batch actions are not supported.")})
			if stop_on_error:
				break
			continue
		var action_params_value: Variant = action_item.get("params", {})
		var action_params: Dictionary = {}
		if typeof(action_params_value) == TYPE_DICTIONARY:
			action_params = action_params_value
		var started_msec := Time.get_ticks_msec()
		var result := execute_action(action, action_params)
		var entry := {
			"index": index,
			"action": action,
			"latency_ms": Time.get_ticks_msec() - started_msec,
		}
		if result.get("ok", false):
			entry["status"] = "succeeded"
			entry["data"] = result.get("data", {})
		else:
			any_error = true
			entry["status"] = "failed"
			entry["error"] = result.get("error", {})
		results.append(entry)
		if any_error and stop_on_error:
			break

	var final_snapshot := _refresh("editor_control:editor_batch")
	return _ok({
		"status": "partial" if any_error else "succeeded",
		"results": results,
		"final_snapshot": {
			"context_snapshot_path": _context_snapshot_path,
			"generated_at": final_snapshot.get("generated_at", ""),
			"current_scene": final_snapshot.get("current_scene", {}),
		},
		"snapshot_refreshed": true,
	})


func _refresh(reason: String) -> Dictionary:
	if _context != null:
		return _context.refresh(reason)
	return {}


func _record_action(action: String, status: String, data: Dictionary) -> void:
	if _context != null:
		_context.record_action(action, status, data)


func _ok(data: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"data": data,
	}


func _err_result(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	return {
		"ok": false,
		"error": _error_payload(code, message, details),
	}


func _error_payload(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	if _context != null:
		return _context.err(code, message, details)
	var payload := {
		"code": code,
		"message": message,
	}
	if not details.is_empty():
		payload["details"] = details
	return payload


func _truncate_string(value: String, max_length: int) -> String:
	if value.length() <= max_length:
		return value
	return value.substr(0, max(0, max_length - 3)) + "..."
