extends SceneTree

const Pref := preload("res://addons/godot_codex_bridge/core/chat_model_preference_model.gd")

var _failures := 0

var MODELS: Array[Dictionary] = [
	{"model": "gpt-6-astra", "displayName": "GPT 6 Astra", "isDefault": true, "supportedReasoningEfforts": [{"reasoningEffort": "medium"}, {"reasoningEffort": "high"}, {"reasoningEffort": "xhigh"}]},
	{"model": "gpt-6-mini", "id": "mini-id", "displayName": "GPT 6 Mini", "supportedReasoningEfforts": [{"reasoningEffort": "low"}, {"reasoningEffort": "medium"}]},
]


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge model preference tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge model preference tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	# No saved choice: unchanged default behaviour (Host default / isDefault).
	var none := Pref.initial_selection(MODELS, "", false, "", "")
	_eq(none, {"model": "gpt-6-astra", "effort": "", "notice": ""}, "no saved value keeps the Codex default")
	_eq(Pref.effective_default_model(MODELS, "gpt-6-mini"), "gpt-6-mini", "Host defaultModel wins")
	_eq(Pref.effective_default_model(MODELS, "gone"), "gpt-6-astra", "unknown defaultModel falls back to isDefault")

	# Saved model present, effort supported / unsupported.
	_eq(Pref.initial_selection(MODELS, "", true, "gpt-6-mini", "low"), {"model": "gpt-6-mini", "effort": "low", "notice": ""}, "saved model and effort restored")
	_eq(Pref.initial_selection(MODELS, "", true, "gpt-6-mini", "xhigh"), {"model": "gpt-6-mini", "effort": "", "notice": ""}, "unsupported effort falls back to the model default")
	_eq(Pref.initial_selection(MODELS, "", true, "mini-id", "")["model"], "gpt-6-mini", "saved id matches model")
	_eq(Pref.initial_selection(MODELS, "", true, "", "high"), {"model": "", "effort": "high", "notice": ""}, "saved explicit Default row")

	# Saved model missing: Codex default + one short notice, never the priciest guess.
	var missing := Pref.initial_selection(MODELS, "", true, "gpt-5-old", "high")
	_eq(missing.get("model"), "gpt-6-astra", "missing model falls back to the Codex default")
	_eq(missing.get("notice"), "Your last model gpt-5-old isn't available; using GPT 6 Astra.", "fallback notice")
	_eq(missing.get("effort"), "high", "saved effort kept when the default supports it")
	_eq(Pref.initial_selection([], "", true, "x", "")["notice"], "Your last model x isn't available; using the Codex default.", "empty inventory notice")

	# Storage: only explicit saves write; values are bounded and safe.
	var store := {}
	var pref := Pref.new(store)
	_false(pref.has_saved_model(), "nothing saved initially")
	var selection := Pref.initial_selection(MODELS, "", pref.has_saved_model(), pref.saved_model(), pref.saved_effort())
	_eq(store, {}, "computing/applying a default selection saves nothing")
	pref.save_model("gpt-6-mini")
	pref.save_effort("low")
	_true(pref.has_saved_model() and pref.saved_model() == "gpt-6-mini" and pref.saved_effort() == "low", "explicit change saved")
	_eq(store.keys(), [Pref.SETTING_MODEL, Pref.SETTING_EFFORT], "namespaced per-user keys")
	pref.save_effort("bad effort!")
	_eq(pref.saved_effort(), "low", "unsafe effort ignored")
	pref.save_model("x".repeat(500))
	_eq(pref.saved_model().length(), Pref.MAX_VALUE_CHARS, "saved model bounded")
	store[Pref.SETTING_MODEL] = 42
	_eq(pref.saved_model(), "", "non-string setting ignored")

	# Composer badge text.
	_eq(Pref.badge_text(MODELS[1], "GPT 6 Astra", "low"), "GPT 6 Mini · Low", "badge shows model and effort")
	_eq(Pref.badge_text({"model": ""}, "GPT 6 Astra", ""), "Default (GPT 6 Astra) · default effort", "badge explains the Default row")
	_eq(selection.get("model"), "gpt-6-astra", "selection unaffected by storage")


func _eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures += 1
		push_error(label + " expected=" + str(expected) + " actual=" + str(actual))


func _true(value: bool, label: String) -> void:
	if not value:
		_failures += 1
		push_error(label)


func _false(value: bool, label: String) -> void:
	if value:
		_failures += 1
		push_error(label)
