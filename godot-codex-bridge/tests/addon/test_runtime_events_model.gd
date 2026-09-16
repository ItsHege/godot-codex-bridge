extends SceneTree

const RuntimeEventsModel := preload("res://addons/godot_codex_bridge/core/runtime_events_model.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge runtime events model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge runtime events model tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var first := RuntimeEventsModel.append_event([], "probe_ready", {"message": "hello"}, {
		"generated_at": "2026-06-24T13:00:00Z",
		"id": "event-1",
		"max_events": 2,
	})
	var events := first.get("events", []) as Array
	_assert_eq(events.size(), 1, "one event appended")
	_assert_eq(((events[0] as Dictionary).get("type")), "probe_ready", "event type")
	_assert_eq(((events[0] as Dictionary).get("id")), "event-1", "event id")

	var second := RuntimeEventsModel.append_event(events, "node_added", {"long": "abcdef"}, {
		"generated_at": "2026-06-24T13:00:01Z",
		"id": "event-2",
		"max_events": 2,
		"max_payload_chars": 5,
	})
	var second_events := second.get("events", []) as Array
	_assert_eq(second_events.size(), 2, "two events retained")
	_assert_eq((((second_events[1] as Dictionary).get("payload", {}) as Dictionary).get("long")), "ab...", "payload truncated")

	var third := RuntimeEventsModel.append_event(second_events, "scene_changed", {}, {
		"generated_at": "2026-06-24T13:00:02Z",
		"id": "event-3",
		"max_events": 2,
	})
	var third_events := third.get("events", []) as Array
	_assert_eq(third_events.size(), 2, "bounded events retained")
	_assert_eq(((third_events[0] as Dictionary).get("id")), "event-2", "oldest event dropped")
	_assert_true(bool(third.get("truncated", false)), "append reports truncation")

	var document := RuntimeEventsModel.build_document(third_events, {
		"generated_at": "2026-06-24T13:00:03Z",
		"max_events": 5,
	})
	_assert_eq(document.get("runtime_events_version"), RuntimeEventsModel.EVENTS_VERSION, "events version")
	_assert_eq(document.get("event_count"), 2, "document event count")
	_assert_eq(((document.get("privacy", {}) as Dictionary).get("external_upload_allowed")), false, "privacy local only")
	_assert_eq(((document.get("observability", {}) as Dictionary).get("input_injection")), "gated_playtest_commands_only", "gated input injection disclosed")

	var input_result := RuntimeEventsModel.input_transition_events({}, {
		"action_states": [
			{"name": "move_right", "pressed": true, "strength": 1.0},
			{"name": "jump", "pressed": false, "strength": 0.0},
		],
	})
	var input_events := input_result.get("events", []) as Array
	_assert_eq(input_events.size(), 1, "one input press event")
	_assert_eq(((input_events[0] as Dictionary).get("type")), "input_action_pressed", "input pressed event")
	var release_result := RuntimeEventsModel.input_transition_events(input_result.get("pressed", {}) as Dictionary, {
		"action_states": [
			{"name": "move_right", "pressed": false, "strength": 0.0},
		],
	})
	_assert_eq(((release_result.get("events", []) as Array)[0] as Dictionary).get("type"), "input_action_released", "input released event")
	var overflow_release_result := RuntimeEventsModel.input_transition_events({"overflow_jump": true}, {
		"action_states": [
			{"name": "ui_accept", "pressed": false, "strength": 0.0},
		],
	})
	_assert_eq(((overflow_release_result.get("events", []) as Array)[0] as Dictionary).get("type"), "input_action_released", "overflow input released event")
	_assert_eq((((overflow_release_result.get("events", []) as Array)[0] as Dictionary).get("payload", {}) as Dictionary).get("name"), "overflow_jump", "overflow input released name")

	var scene_event := RuntimeEventsModel.scene_change_event("", "/root/Main", {"name": "Main"})
	_assert_eq(scene_event.get("type"), "scene_changed", "scene changed emitted")
	_assert_true(RuntimeEventsModel.scene_change_event("/root/Main", "/root/Main", {}).is_empty(), "same scene no event")

	var node := Node3D.new()
	node.name = "RuntimeNode"
	get_root().add_child(node)
	node.position = Vector3(1, 2, 3)
	var node_payload := RuntimeEventsModel.node_event_payload(node)
	_assert_eq(node_payload.get("name"), "RuntimeNode", "node payload name")
	_assert_eq(node_payload.get("dimension"), "3d", "node payload dimension")
	_assert_eq((node_payload.get("global_position", {}) as Dictionary).get("z"), 3.0, "node payload z")
	node.queue_free()


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures += 1
		push_error(label + " expected=" + str(expected) + " actual=" + str(actual))


func _assert_true(value: bool, label: String) -> void:
	if not value:
		_failures += 1
		push_error(label)
