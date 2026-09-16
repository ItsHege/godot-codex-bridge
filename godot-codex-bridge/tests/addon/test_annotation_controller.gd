extends SceneTree

const AnnotationController := preload("res://addons/godot_codex_bridge/core/annotation_controller.gd")
const BridgeContext := preload("res://addons/godot_codex_bridge/core/bridge_context.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge annotation controller tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge annotation controller tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var ctx := BridgeContext.new()
	ctx.permissions = {"allow_ai_markers": true}
	var controller := AnnotationController.new(ctx)
	_assert_true(controller != null, "annotation controller instantiates")
	_assert_false(controller.has_pending(), "annotation controller starts without pending marker")
	_assert_eq(controller.selected_scope(), "editor_window", "default annotation scope")
	_assert_eq(controller.selected_tool(), "rectangle", "default annotation tool")
	var status := controller.status_payload()
	_assert_eq(status.get("pending_annotation"), false, "status reports no pending marker")
	_assert_eq(status.get("annotation_marker_count"), 0, "status reports no markers")

	var pending_label := Label.new()
	var clear_button := Button.new()
	controller.setup_pending_ui(pending_label, clear_button)
	_assert_false(pending_label.visible, "pending label starts hidden")
	_assert_false(clear_button.visible, "clear button starts hidden")
	controller.pending_annotation = {
		"annotation_id": "annotation_test_001",
		"primary_marker": "A",
	}
	controller.update_pending_ui()
	_assert_true(controller.has_pending(), "controller has pending marker")
	_assert_true(pending_label.visible, "pending label visible with marker")
	_assert_true(clear_button.visible, "clear button visible with marker")
	_assert_eq(pending_label.text, "Marker A attached", "pending label previews marker")
	controller.clear_pending(true)
	_assert_false(controller.has_pending(), "clear pending removes marker")
	_assert_false(pending_label.visible, "pending label hidden after clear")
	_assert_false(clear_button.visible, "clear button hidden after clear")
	_assert_eq(pending_label.text, "", "pending label clears text")
	pending_label.free()
	clear_button.free()


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
