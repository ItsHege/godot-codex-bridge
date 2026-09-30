extends SceneTree

const BridgeDockStatusModel := preload("res://addons/godot_codex_bridge/core/bridge_dock_status_model.gd")

var _failures := 0


func _init() -> void:
	var ok := BridgeDockStatusModel.summary("Context snapshot written", "2026-09-30T15:42:47Z", 0, 180)
	_eq(ok.get("text"), "Snapshot 18:42 · 0 pending", "local clock with UTC offset")
	_eq(ok.get("tone"), "ok", "idle bridge is ok")
	_true(str(ok.get("tooltip", "")).contains("Context snapshot written") and str(ok.get("tooltip", "")).contains("2026-09-30T15:42:47Z"), "full status and ISO time in tooltip")
	_eq(BridgeDockStatusModel.summary("Context snapshot written", "2026-09-30T15:42:47Z", 2, 0).get("tone"), "warn", "pending requests warn")
	_eq(BridgeDockStatusModel.summary("Screenshot failed: x", "2026-09-30T15:42:47Z", 0, 0).get("tone"), "error", "failure is an error")
	var none := BridgeDockStatusModel.summary("Starting", "unknown", 0, 0)
	_eq(none.get("text"), "No snapshot yet · 0 pending", "no snapshot yet")
	_eq(BridgeDockStatusModel.local_clock_text("2026-09-30T23:30:00Z", 60), "00:30", "offset wraps past midnight")
	if _failures == 0:
		print("Godot Codex Bridge dock status model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge dock status model tests failed: " + str(_failures))
		quit(1)


func _eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures += 1
		push_error(label + " expected=" + str(expected) + " actual=" + str(actual))


func _true(value: bool, label: String) -> void:
	if not value:
		_failures += 1
		push_error(label)
