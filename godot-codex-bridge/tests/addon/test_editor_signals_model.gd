extends SceneTree

const BridgeContext := preload("res://addons/godot_codex_bridge/core/bridge_context.gd")
const EditorSignals := preload("res://addons/godot_codex_bridge/core/editor_signals.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge editor signals tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge editor signals tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	_assert_eq(EditorSignals.sanitize_identifier_name(" renamed ", "signal"), "renamed", "identifier trims")
	_assert_eq(EditorSignals.sanitize_identifier_name("bad/name", "signal"), "", "identifier rejects slash")
	_assert_eq(EditorSignals.sanitize_identifier_name("bad\nname", "signal"), "", "identifier rejects newline")

	var args := EditorSignals.signal_args_payload([
		{"name": "body", "type": TYPE_OBJECT, "default_value": null},
		{"name": "amount", "type": TYPE_FLOAT, "default_value": 1.0},
	])
	_assert_eq(args.size(), 2, "signal args serialized")
	_assert_eq((args[0] as Dictionary).get("name"), "body", "signal arg name")
	_assert_eq((args[1] as Dictionary).get("type"), "float", "signal arg type")

	var root := Node.new()
	root.name = "Root"
	var source := Node.new()
	source.name = "Source"
	var target := Node.new()
	target.name = "Target"
	root.add_child(source)
	root.add_child(target)
	var callable := Callable(target, "queue_free")
	var connect_error := source.connect("renamed", callable, CONNECT_DEFERRED)
	_assert_eq(connect_error, OK, "test signal connection created")
	var flags := EditorSignals.find_signal_connection_flags(source, "renamed", callable)
	_assert_eq(flags, CONNECT_DEFERRED, "signal flags discovered")
	var connections := EditorSignals.signal_connections_payload(source, "renamed", root)
	_assert_eq(connections.size(), 1, "connection payload count")
	var callable_payload: Dictionary = (connections[0] as Dictionary).get("callable", {})
	_assert_eq(((callable_payload.get("target_node") as Dictionary).get("path")), "Target", "callable target path")
	var ref := EditorSignals.signal_connection_ref_payload(source, "renamed", target, "queue_free", root)
	_assert_eq(((ref.get("source") as Dictionary).get("path")), "Source", "connection source path")
	root.free()

	var ctx := BridgeContext.new()
	ctx.permissions = {"allow_editor_inspect": false, "allow_scene_edits": false}
	var service := EditorSignals.new(ctx)
	var denied_list := service.list_signal_connections({})
	_assert_false(bool(denied_list.get("ok", true)), "list signals denied when inspect permission disabled")
	_assert_eq(((denied_list.get("error", {}) as Dictionary).get("code")), "permission_denied", "inspect permission error")
	var denied_connect := service.connect_signal({})
	_assert_false(bool(denied_connect.get("ok", true)), "connect signal denied when scene edit permission disabled")
	_assert_eq(((denied_connect.get("error", {}) as Dictionary).get("code")), "permission_denied", "scene edit permission error")


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures += 1
		push_error(label + " expected=" + str(expected) + " actual=" + str(actual))


func _assert_false(value: bool, label: String) -> void:
	if value:
		_failures += 1
		push_error(label)
