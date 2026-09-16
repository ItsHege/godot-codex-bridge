@tool
extends RefCounted

const DEFAULT_PROMPT := "Run a read-only background team review for the current Godot project."
const DEFAULT_ROLES := ["scene_agent", "script_agent", "qa_agent", "safety_agent"]
const ACTIVE_STATES := ["queued", "running", "summarizing"]


static func is_active_state(state: String) -> bool:
	return state in ACTIVE_STATES


static func prompt_from_input(input_text: String) -> String:
	var prompt := input_text.strip_edges()
	return prompt if prompt != "" else DEFAULT_PROMPT


static func start_payload(prompt: String) -> Dictionary:
	return {
		"prompt": prompt_from_input(prompt),
		"roles": DEFAULT_ROLES.duplicate(),
	}


static func cancel_payload(task_id: String) -> Dictionary:
	var payload := {}
	if task_id.strip_edges() != "":
		payload["task_id"] = task_id.strip_edges()
	return payload


static func update_from_params(params: Dictionary, current_task_id: String, current_state: String) -> Dictionary:
	var task_id := str(params.get("task_id", "")).strip_edges()
	var state := str(params.get("state", "unknown")).strip_edges()
	if task_id == "":
		task_id = current_task_id
	if state == "":
		state = current_state
	return {
		"task_id": task_id,
		"state": state,
		"state_changed": state != current_state,
	}


static func restore_from_tasks(tasks: Array, current_task_id: String, current_state: String) -> Dictionary:
	var selected: Dictionary = {}
	for item in tasks:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var task := item as Dictionary
		selected = task
		if is_active_state(str(task.get("state", ""))):
			break
	if selected.is_empty():
		return {
			"has_task": false,
			"task_id": current_task_id,
			"state": current_state,
			"task": {},
		}
	return {
		"has_task": true,
		"task_id": str(selected.get("task_id", current_task_id)),
		"state": str(selected.get("state", current_state)),
		"task": selected,
	}


static func status_text(state: String, params: Dictionary = {}) -> String:
	var parts: Array[String] = []
	parts.append("Team: " + state)
	if not params.is_empty():
		var results_value: Variant = params.get("results", [])
		if typeof(results_value) == TYPE_ARRAY:
			var results := results_value as Array
			var completed := 0
			var failed := 0
			var cancelled := 0
			for item in results:
				if typeof(item) != TYPE_DICTIONARY:
					continue
				var item_state := str((item as Dictionary).get("state", ""))
				if item_state == "completed":
					completed += 1
				elif item_state == "failed":
					failed += 1
				elif item_state == "cancelled":
					cancelled += 1
			parts.append("roles " + str(completed) + "/" + str(results.size()) + " done")
			if failed > 0:
				parts.append(str(failed) + " failed")
			if cancelled > 0:
				parts.append(str(cancelled) + " cancelled")
		if str(params.get("summary_path", "")) != "":
			parts.append("summary ready")
	return " | ".join(parts)


static func update_messages(params: Dictionary, state: String, state_changed: bool) -> Dictionary:
	var system_messages: Array[String] = []
	var detail_messages: Array[String] = []
	if state_changed:
		system_messages.append("Background team " + state + ".")
	var summary_path := str(params.get("summary_path", ""))
	if summary_path != "":
		if state == "failed":
			system_messages.append("Background partial summary is ready.")
		else:
			system_messages.append("Background summary is ready.")
		detail_messages.append("Background summary: " + summary_path)
	return {
		"system_messages": system_messages,
		"detail_messages": detail_messages,
	}


static func background_update_plan(params: Dictionary, current_task_id: String, current_state: String) -> Dictionary:
	var update := update_from_params(params, current_task_id, current_state)
	var next_state := str(update.get("state", current_state))
	var messages := update_messages(params, next_state, bool(update.get("state_changed", false)))
	return {
		"task_id": str(update.get("task_id", current_task_id)),
		"state": next_state,
		"status_params": params,
		"system_messages": messages.get("system_messages", []),
		"detail_messages": messages.get("detail_messages", []),
		"update_ui": true,
	}


static func background_update_effect_plan(plan: Dictionary) -> Dictionary:
	var effects: Array = [
		{
			"type": "set_background_task_id",
			"task_id": str(plan.get("task_id", "")),
		},
		{
			"type": "set_background_state",
			"state": str(plan.get("state", "idle")),
		},
		{
			"type": "update_background_status_label",
			"params": plan.get("status_params", {}),
		},
	]
	for message in plan.get("system_messages", []):
		effects.append({
			"type": "system_message",
			"message": str(message),
		})
	for message in plan.get("detail_messages", []):
		effects.append({
			"type": "detail_message",
			"message": str(message),
		})
	if bool(plan.get("update_ui", true)):
		effects.append({"type": "update_ui"})
	return {"effects": effects}


static func background_restore_plan(tasks: Array, current_task_id: String, current_state: String) -> Dictionary:
	var restored := restore_from_tasks(tasks, current_task_id, current_state)
	var has_task := bool(restored.get("has_task", false))
	return {
		"has_task": has_task,
		"task_id": str(restored.get("task_id", current_task_id)),
		"state": str(restored.get("state", current_state)),
		"status_params": restored.get("task", {}) as Dictionary,
		"update_status_label": has_task,
	}


static func background_restore_effect_plan(plan: Dictionary) -> Dictionary:
	var effects: Array = []
	if not bool(plan.get("has_task", false)):
		return {"effects": effects}
	effects.append({
		"type": "set_background_task_id",
		"task_id": str(plan.get("task_id", "")),
	})
	effects.append({
		"type": "set_background_state",
		"state": str(plan.get("state", "idle")),
	})
	if bool(plan.get("update_status_label", false)):
		effects.append({
			"type": "update_background_status_label",
			"params": plan.get("status_params", {}),
		})
	return {"effects": effects}
