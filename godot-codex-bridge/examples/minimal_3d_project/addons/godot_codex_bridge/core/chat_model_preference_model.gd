@tool
extends RefCounted

## Remembers the user's last explicitly chosen Codex model and reasoning effort
## in per-user editor settings (never in a project) and decides what to select
## when the Host's model inventory arrives. Pure selection logic plus a small
## storage wrapper that tests can back with a Dictionary.

const ChatRuntimeOptionsModel := preload("chat_runtime_options_model.gd")

const SETTING_MODEL := "godot_codex_bridge/chat/last_model"
const SETTING_EFFORT := "godot_codex_bridge/chat/last_reasoning_effort"
const MAX_VALUE_CHARS := 128

## Storage backend: an EditorSettings object, or a Dictionary for tests.
var backend: Variant = null


func _init(storage: Variant = null) -> void:
	backend = storage if storage != null else {}


func has_saved_model() -> bool:
	return _has_value(SETTING_MODEL)


func saved_model() -> String:
	return _read_value(SETTING_MODEL)


func saved_effort() -> String:
	return _read_value(SETTING_EFFORT)


## Called only from the pickers' item_selected signals (user actions).
func save_model(model: String) -> void:
	_write_value(SETTING_MODEL, model.strip_edges().left(MAX_VALUE_CHARS))


func save_effort(effort: String) -> void:
	var value := effort.strip_edges()
	if value != "" and not ChatRuntimeOptionsModel.is_safe_reasoning_effort(value):
		return
	_write_value(SETTING_EFFORT, value)


## What to select once the inventory is known.
## Returns {model, effort, notice}; model "" means the "Default" row.
static func initial_selection(models: Array[Dictionary], default_model: String, has_saved: bool, saved_model_id: String, saved_effort_id: String, fallback_efforts: Array[Dictionary] = []) -> Dictionary:
	var effective_default := effective_default_model(models, default_model)
	var model := effective_default
	var notice := ""
	if has_saved:
		var wanted := saved_model_id.strip_edges()
		if wanted == "":
			model = ""
		elif find_model(models, wanted).is_empty():
			notice = "Your last model " + wanted + " isn't available; using " + model_label(find_model(models, effective_default), effective_default) + "."
		else:
			model = str(find_model(models, wanted).get("model", wanted))
	var effort := ""
	var wanted_effort := saved_effort_id.strip_edges()
	if wanted_effort != "":
		var efforts := ChatRuntimeOptionsModel.model_efforts_for_model(find_model(models, model), fallback_efforts if not fallback_efforts.is_empty() else ChatRuntimeOptionsModel.DEFAULT_REASONING_EFFORTS)
		for option in efforts:
			if str(option.get("reasoningEffort", "")) == wanted_effort:
				effort = wanted_effort
				break
	return {"model": model, "effort": effort, "notice": notice}


## The Host's defaultModel, else the inventory's isDefault model, else the first.
static func effective_default_model(models: Array[Dictionary], default_model: String) -> String:
	var value := default_model.strip_edges()
	if value != "" and not find_model(models, value).is_empty():
		return str(find_model(models, value).get("model", value))
	for model_data in models:
		if bool(model_data.get("isDefault", false)):
			return str(model_data.get("model", ""))
	return str(models[0].get("model", "")) if not models.is_empty() else ""


static func find_model(models: Array[Dictionary], model_id: String) -> Dictionary:
	var wanted := model_id.strip_edges()
	if wanted == "":
		return {}
	for model_data in models:
		if str(model_data.get("model", "")) == wanted or str(model_data.get("id", "")) == wanted:
			return model_data
	return {}


static func model_label(model_data: Dictionary, fallback: String) -> String:
	var label := str(model_data.get("displayName", "")).strip_edges()
	return label if label != "" else (fallback if fallback != "" else "the Codex default")


## Compact "model · effort" text for the composer row.
static func badge_text(model_data: Dictionary, effective_default_label: String, effort: String) -> String:
	var name := model_label(model_data, "")
	if model_data.is_empty() or str(model_data.get("model", "")) == "":
		name = "Default" + (" (" + effective_default_label + ")" if effective_default_label != "" else "")
	var effort_text := ChatRuntimeOptionsModel.reasoning_effort_label(effort) if effort != "" else "default effort"
	return name + " · " + effort_text


func _has_value(key: String) -> bool:
	if backend is Dictionary:
		return (backend as Dictionary).has(key)
	return backend != null and backend.has_setting(key)


func _read_value(key: String) -> String:
	if not _has_value(key):
		return ""
	var value: Variant = (backend as Dictionary).get(key) if backend is Dictionary else backend.get_setting(key)
	return str(value).strip_edges().left(MAX_VALUE_CHARS) if typeof(value) == TYPE_STRING else ""


func _write_value(key: String, value: String) -> void:
	if backend is Dictionary:
		(backend as Dictionary)[key] = value
	elif backend != null:
		backend.set_setting(key, value)
