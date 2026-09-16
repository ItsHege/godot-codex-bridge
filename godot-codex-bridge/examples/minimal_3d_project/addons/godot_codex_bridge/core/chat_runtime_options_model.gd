extends RefCounted

const DEFAULT_REASONING_EFFORTS: Array[Dictionary] = [
	{"reasoningEffort": "minimal", "description": "Fastest lightweight reasoning."},
	{"reasoningEffort": "low", "description": "Fast iteration."},
	{"reasoningEffort": "medium", "description": "Balanced default."},
	{"reasoningEffort": "high", "description": "Deeper reasoning."},
	{"reasoningEffort": "xhigh", "description": "Maximum reasoning."},
]


static func normalize_models(value: Variant) -> Array[Dictionary]:
	var models: Array[Dictionary] = []
	if typeof(value) != TYPE_ARRAY:
		return models
	for item in value:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var item_dict := (item as Dictionary).duplicate(true)
		if str(item_dict.get("model", "")).strip_edges() == "":
			continue
		models.append(item_dict)
	return models


static func normalize_reasoning_efforts(value: Variant) -> Array[Dictionary]:
	var efforts: Array[Dictionary] = []
	if typeof(value) != TYPE_ARRAY:
		return efforts
	for item in value:
		if typeof(item) == TYPE_DICTIONARY:
			var effort_dict := (item as Dictionary).duplicate(true)
			if str(effort_dict.get("reasoningEffort", "")).strip_edges() != "":
				efforts.append(effort_dict)
		elif str(item).strip_edges() != "":
			efforts.append({"reasoningEffort": str(item).strip_edges()})
	return efforts


static func reasoning_efforts_or_default(value: Variant) -> Array[Dictionary]:
	var efforts := normalize_reasoning_efforts(value)
	if efforts.is_empty():
		return DEFAULT_REASONING_EFFORTS.duplicate(true)
	return efforts


static func request_models_effect_plan(socket_ready: bool) -> Dictionary:
	var effects: Array = []
	if socket_ready:
		effects.append({
			"type": "send_json",
			"method": "runtime.models.list",
			"params": {},
		})
	return {"effects": effects}


static func update_model_options_plan(data: Dictionary, current_models: Array[Dictionary], current_efforts: Array[Dictionary]) -> Dictionary:
	if not data.has("models"):
		return {
			"ok": false,
			"reason": "missing_models",
		}
	var models := current_models.duplicate(true)
	var models_value: Variant = data.get("models", [])
	if typeof(models_value) == TYPE_ARRAY:
		models = normalize_models(models_value)

	var efforts := current_efforts.duplicate(true)
	var efforts_value: Variant = data.get("reasoningEfforts", [])
	if typeof(efforts_value) == TYPE_ARRAY:
		efforts = normalize_reasoning_efforts(efforts_value)
	if efforts.is_empty():
		efforts = DEFAULT_REASONING_EFFORTS.duplicate(true)

	var warning := str(data.get("error", ""))
	var detail_message := "Runtime model list warning: " + warning if warning != "" else "Runtime model list loaded: " + str(models.size()) + " model(s)."
	return {
		"ok": true,
		"models": models,
		"reasoning_efforts": efforts,
		"models_loaded": true,
		"default_model": str(data.get("defaultModel", "")),
		"detail_message": detail_message,
		"update_ui": true,
	}


static func update_model_options_effect_plan(data: Dictionary, current_models: Array[Dictionary], current_efforts: Array[Dictionary]) -> Dictionary:
	var plan := update_model_options_plan(data, current_models, current_efforts)
	if not bool(plan.get("ok", false)):
		return {
			"ok": false,
			"reason": str(plan.get("reason", "")),
			"effects": [],
		}
	var effects: Array[Dictionary] = [
		{
			"action": "apply_runtime_options",
			"models": plan.get("models", []),
			"reasoning_efforts": plan.get("reasoning_efforts", []),
			"models_loaded": bool(plan.get("models_loaded", true)),
		},
		{
			"action": "rebuild_model_options",
			"default_model": str(plan.get("default_model", "")),
		},
		{
			"action": "update_reasoning_options_for_selected_model",
		},
	]
	var detail_message := str(plan.get("detail_message", ""))
	if detail_message != "":
		effects.append({
			"action": "detail_message",
			"message": detail_message,
		})
	if bool(plan.get("update_ui", true)):
		effects.append({
			"action": "update_ui",
		})
	return {
		"ok": true,
		"effects": effects,
	}


static func model_selection_effect_plan(model_data: Dictionary, fallback_efforts: Array[Dictionary], selected_effort: String) -> Dictionary:
	var effects: Array[Dictionary] = [
		{
			"action": "rebuild_reasoning_options",
			"selected_effort": selected_effort.strip_edges(),
			"efforts": model_efforts_for_model(model_data, fallback_efforts),
		},
		{
			"action": "update_ui",
		},
	]
	return {
		"effects": effects,
	}


static func runtime_selection_effect_plan(runtime_options: Dictionary, model_metadata_items: Array, reasoning_metadata_items: Array) -> Dictionary:
	var effects: Array[Dictionary] = []
	var model := str(runtime_options.get("model", "")).strip_edges()
	if model != "":
		var model_index := selected_index_for_model_metadata(model_metadata_items, model)
		if model_index >= 0:
			effects.append({
				"action": "select_model",
				"index": model_index,
				"refresh_reasoning": true,
			})

	var effort := str(runtime_options.get("effort", "")).strip_edges()
	if effort != "":
		var effort_index := selected_index_for_reasoning_metadata(reasoning_metadata_items, effort)
		effects.append({
			"action": "select_reasoning",
			"effort": effort,
			"index": effort_index,
		})
	return {
		"effects": effects,
	}


static func model_efforts_for_model(model_data: Dictionary, fallback_efforts: Array[Dictionary]) -> Array[Dictionary]:
	var efforts := normalize_reasoning_efforts(model_data.get("supportedReasoningEfforts", []))
	if efforts.is_empty():
		return fallback_efforts.duplicate(true)
	return efforts


static func model_option_rows(models: Array[Dictionary], selected_model: String, default_model: String, max_label_length := 22) -> Dictionary:
	var rows: Array[Dictionary] = [
		{"label": "Default", "metadata": {"model": "", "displayName": "Default"}},
	]
	var select_index := 0
	var effective_default := default_model.strip_edges()
	var selected := selected_model.strip_edges()
	for model_data in models:
		var model_id := str(model_data.get("model", "")).strip_edges()
		if model_id == "":
			continue
		var label := str(model_data.get("displayName", model_id))
		if label == "":
			label = model_id
		if bool(model_data.get("isDefault", false)) and effective_default == "":
			effective_default = model_id
		if max_label_length > 3 and label.length() > max_label_length:
			label = label.substr(0, max_label_length - 3) + "..."
		rows.append({"label": label, "metadata": model_data})
		var index := rows.size() - 1
		if model_id == selected or (selected == "" and effective_default != "" and model_id == effective_default):
			select_index = index
	return {
		"rows": rows,
		"select_index": select_index,
		"default_model": effective_default,
	}


static func reasoning_option_rows(efforts: Array[Dictionary], selected_effort: String) -> Dictionary:
	var rows: Array[Dictionary] = [
		{"label": "Default", "metadata": {"reasoningEffort": ""}},
	]
	var select_index := 0
	var selected := selected_effort.strip_edges()
	var source_efforts := efforts
	if source_efforts.is_empty():
		source_efforts = DEFAULT_REASONING_EFFORTS.duplicate(true)
	for effort_data in source_efforts:
		var effort := str(effort_data.get("reasoningEffort", "")).strip_edges()
		if effort == "":
			continue
		rows.append({"label": reasoning_effort_label(effort), "metadata": effort_data})
		var index := rows.size() - 1
		if effort == selected:
			select_index = index
	return {
		"rows": rows,
		"select_index": select_index,
	}


static func selected_model_from_metadata(metadata: Variant) -> String:
	if typeof(metadata) != TYPE_DICTIONARY:
		return ""
	return str((metadata as Dictionary).get("model", "")).strip_edges()


static func selected_reasoning_from_metadata(metadata: Variant) -> String:
	if typeof(metadata) != TYPE_DICTIONARY:
		return ""
	return str((metadata as Dictionary).get("reasoningEffort", "")).strip_edges()


static func selected_index_for_model_metadata(metadata_items: Array, model: String) -> int:
	var expected := model.strip_edges()
	if expected == "":
		return -1
	for index in range(metadata_items.size()):
		if selected_model_from_metadata(metadata_items[index]) == expected:
			return index
	return -1


static func selected_index_for_reasoning_metadata(metadata_items: Array, effort: String) -> int:
	var expected := effort.strip_edges()
	if expected == "":
		return -1
	for index in range(metadata_items.size()):
		if selected_reasoning_from_metadata(metadata_items[index]) == expected:
			return index
	return -1


static func reasoning_effort_label(effort: String) -> String:
	match effort.strip_edges():
		"none":
			return "None"
		"minimal":
			return "Fast"
		"low":
			return "Low"
		"medium":
			return "Medium"
		"high":
			return "High"
		"xhigh":
			return "XHigh"
		_:
			return effort.strip_edges().capitalize()
