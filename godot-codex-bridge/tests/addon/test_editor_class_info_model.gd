extends SceneTree

const BridgeContext := preload("res://addons/godot_codex_bridge/core/bridge_context.gd")
const EditorClassInfo := preload("res://addons/godot_codex_bridge/core/editor_class_info.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge editor class info tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge editor class info tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	_assert_eq(EditorClassInfo.sanitize_class_name(" Node3D "), "Node3D", "class name trims")
	_assert_eq(EditorClassInfo.sanitize_class_name("Node\n3D"), "", "class name rejects newline")
	_assert_eq(EditorClassInfo.sanitize_class_name("X".repeat(97)), "", "class name rejects long value")

	var limited: Dictionary = EditorClassInfo.packed_string_array_to_limited_array(PackedStringArray(["A", "B", "C"]), 2)
	_assert_eq(limited.get("items"), ["A", "B"], "packed string array is limited")
	_assert_eq(limited.get("count"), 3, "packed string array count")
	_assert_eq(limited.get("returned"), 2, "packed string array returned")
	_assert_true(bool(limited.get("truncated", false)), "packed string array truncated")

	var property_payload: Dictionary = EditorClassInfo.class_property_list_payload([
		{"name": "position", "type": TYPE_VECTOR3, "class_name": "", "hint": 0, "hint_string": "long".repeat(100), "usage": 7},
		"ignored",
	], 2)
	_assert_eq(property_payload.get("count"), 2, "property payload source count")
	_assert_eq(property_payload.get("returned"), 1, "property payload skips non-dictionaries")
	var property_item := ((property_payload.get("items", []) as Array)[0] as Dictionary)
	_assert_eq(property_item.get("name"), "position", "property payload name")
	_assert_eq(property_item.get("type"), "Vector3", "property payload type")
	_assert_true(str(property_item.get("hint_string", "")).length() <= 243, "property hint string bounded")

	var return_payload: Dictionary = EditorClassInfo.class_return_payload({"name": "result", "type": TYPE_BOOL, "class_name": "", "hint": 0, "hint_string": ""})
	_assert_eq(return_payload.get("type"), "bool", "return payload type")
	_assert_true(EditorClassInfo.class_return_payload("bad").is_empty(), "non-dictionary return payload is empty")

	var denied_ctx := BridgeContext.new()
	denied_ctx.permissions = {"allow_editor_inspect": false}
	var denied_service: Variant = EditorClassInfo.new(denied_ctx)
	var denied: Dictionary = denied_service.get_class_info({"className": "Node3D"})
	_assert_false(bool(denied.get("ok", true)), "class info denied when inspect permission disabled")
	_assert_eq(((denied.get("error", {}) as Dictionary).get("code")), "permission_denied", "permission error code")

	var ctx := BridgeContext.new()
	ctx.permissions = {"allow_editor_inspect": true}
	ctx.iso_now = Callable(self, "_fake_now")
	var service: Variant = EditorClassInfo.new(ctx)
	var missing_name: Dictionary = service.get_class_info({})
	_assert_false(bool(missing_name.get("ok", true)), "missing class name fails")
	_assert_eq(((missing_name.get("error", {}) as Dictionary).get("code")), "invalid_class_name", "missing class name error code")

	var missing_class: Dictionary = service.get_class_info({"className": "NoSuchGodotClass"})
	_assert_false(bool(missing_class.get("ok", true)), "missing class fails")
	_assert_eq(((missing_class.get("error", {}) as Dictionary).get("code")), "class_not_found", "missing class error code")

	var node_info: Dictionary = service.get_class_info({"className": "Node3D", "limit": 3, "noInheritance": true})
	_assert_true(bool(node_info.get("ok", false)), "Node3D class info succeeds")
	var data := node_info.get("data", {}) as Dictionary
	_assert_eq(data.get("captured_at"), "2026-06-22T00:00:00Z", "timestamp from context")
	_assert_eq(data.get("class_name"), "Node3D", "class name payload")
	_assert_true(bool(data.get("is_node", false)), "Node3D is node")
	_assert_false(bool(data.get("is_resource", true)), "Node3D is not resource")
	_assert_eq(((data.get("limits", {}) as Dictionary).get("max_items_per_section")), 3, "limit clamped into payload")
	_assert_true(((data.get("properties", {}) as Dictionary).has("items")), "properties payload exists")
	_assert_true(((data.get("methods", {}) as Dictionary).has("items")), "methods payload exists")
	_assert_true(((data.get("signals", {}) as Dictionary).has("items")), "signals payload exists")
	_assert_false(bool(data.get("snapshot_refreshed", true)), "class info does not refresh snapshot")


func _fake_now() -> String:
	return "2026-06-22T00:00:00Z"


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures += 1
		push_error(label + " expected=" + str(expected) + " actual=" + str(actual))


func _assert_true(value: bool, label: String) -> void:
	if not value:
		_failures += 1
		push_error(label)


func _assert_false(value: bool, label: String) -> void:
	if value:
		_failures += 1
		push_error(label)
