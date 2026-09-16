extends SceneTree

const RuntimeStateModel := preload("res://addons/godot_codex_bridge/core/runtime_state_model.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge runtime state model tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge runtime state model tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var root := Node3D.new()
	root.name = "RuntimeRoot"
	get_root().add_child(root)
	current_scene = root

	var actor := Node3D.new()
	actor.name = "Actor"
	actor.position = Vector3(1, 2, 3)
	actor.add_to_group("runtime_actor")
	root.add_child(actor)

	var ui := Label.new()
	ui.name = "RuntimeLabel"
	ui.text = "Visible State"
	root.add_child(ui)

	var timer := Timer.new()
	timer.name = "RuntimeTimer"
	timer.wait_time = 2.5
	timer.one_shot = true
	root.add_child(timer)

	var camera := Camera3D.new()
	camera.name = "RuntimeCamera"
	camera.current = true
	camera.fov = 65.0
	root.add_child(camera)

	var animation_player := AnimationPlayer.new()
	animation_player.name = "RuntimeAnimation"
	animation_player.speed_scale = 1.25
	root.add_child(animation_player)

	var autoload_node := Node.new()
	autoload_node.name = "RuntimeAutoload"
	get_root().add_child(autoload_node)
	ProjectSettings.set_setting("autoload/RuntimeAutoload", "*res://scripts/runtime_autoload.gd")

	if not InputMap.has_action("runtime_probe_test_action"):
		InputMap.add_action("runtime_probe_test_action")
	Input.action_press("runtime_probe_test_action")

	var state := RuntimeStateModel.collect_state(self, {
		"reason": "test",
		"max_nodes": 10,
		"max_depth": 4,
		"max_key_positions": 10,
		"max_autoloads": 10,
		"max_input_actions": 500,
	})
	_assert_eq(state.get("runtime_state_version"), RuntimeStateModel.SCHEMA_VERSION, "schema version")
	_assert_eq(state.get("reason"), "test", "reason")
	var tree := state.get("tree", {}) as Dictionary
	_assert_false(bool(tree.get("truncated", true)), "not truncated")
	_assert_eq(tree.get("node_count_sampled"), 6, "node count")
	_assert_eq((tree.get("node_type_counts", {}) as Dictionary).get("Node3D"), 2, "node3d type count")
	_assert_eq((tree.get("node_type_counts", {}) as Dictionary).get("Timer"), 1, "timer type count")
	var active_scene := tree.get("active_scene", {}) as Dictionary
	_assert_eq(active_scene.get("name"), "RuntimeRoot", "active scene name")
	_assert_eq(active_scene.get("type"), "Node3D", "active scene type")
	var summary := tree.get("summary", {}) as Dictionary
	_assert_eq(summary.get("active_scene_name"), "RuntimeRoot", "summary active scene name")
	_assert_eq(summary.get("node_count_sampled"), 6, "summary node count")
	_assert_true(int(summary.get("key_position_count", 0)) >= 2, "summary key position count")
	_assert_true(int(summary.get("autoload_count", 0)) >= 1, "summary autoload count")
	var key_positions := tree.get("key_positions", []) as Array
	_assert_true(key_positions.size() >= 2, "key positions include transformed nodes")
	var actor_position := key_positions[1] as Dictionary
	_assert_eq(actor_position.get("name"), "Actor", "key position actor name")
	_assert_eq(actor_position.get("dimension"), "3d", "key position dimension")
	_assert_eq((actor_position.get("global_position", {}) as Dictionary).get("y"), 2.0, "key position actor y")
	var nodes := tree.get("nodes", []) as Array
	_assert_eq(nodes.size(), 1, "root node entry")
	var root_entry := nodes[0] as Dictionary
	_assert_eq(root_entry.get("name"), "RuntimeRoot", "root name")
	_assert_eq(((root_entry.get("visibility", {}) as Dictionary).get("visible")), true, "root visible")
	var children := root_entry.get("children", []) as Array
	_assert_eq(children.size(), 5, "child count")
	var actor_entry := children[0] as Dictionary
	_assert_eq(actor_entry.get("name"), "Actor", "actor name")
	_assert_eq(((actor_entry.get("transform_3d", {}) as Dictionary).get("position", {}) as Dictionary).get("x"), 1.0, "actor x")
	_assert_eq((((actor_entry.get("transform_3d", {}) as Dictionary).get("global", {}) as Dictionary).get("position", {}) as Dictionary).get("z"), 3.0, "actor global z")
	_assert_eq(((actor_entry.get("groups", []) as Array)[0]), "runtime_actor", "actor group")
	var timer_entry := children[2] as Dictionary
	_assert_eq((timer_entry.get("state", {}) as Dictionary).get("kind"), "Timer", "timer state kind")
	_assert_eq((timer_entry.get("state", {}) as Dictionary).get("wait_time"), 2.5, "timer wait")
	var camera_entry := children[3] as Dictionary
	_assert_eq((camera_entry.get("state", {}) as Dictionary).get("kind"), "Camera3D", "camera state kind")
	_assert_eq((camera_entry.get("state", {}) as Dictionary).get("current"), true, "camera current")
	var animation_entry := children[4] as Dictionary
	_assert_eq((animation_entry.get("state", {}) as Dictionary).get("kind"), "AnimationPlayer", "animation state kind")
	_assert_eq((animation_entry.get("state", {}) as Dictionary).get("speed_scale"), 1.25, "animation speed")
	var runtime := state.get("runtime", {}) as Dictionary
	_assert_true(runtime.has("process_frames"), "runtime process frames")
	_assert_true(runtime.has("physics_frames"), "runtime physics frames")
	var input := state.get("input", {}) as Dictionary
	_assert_eq(input.get("max_actions"), 500, "input max actions")
	_assert_true((input.get("active_actions", []) as Array).has("runtime_probe_test_action"), "active action")
	var action_states := input.get("action_states", []) as Array
	var action_state := _find_named(action_states, "runtime_probe_test_action")
	_assert_eq(action_state.get("pressed"), true, "action state pressed")
	_assert_eq(action_state.get("strength"), 1.0, "action state strength")
	var autoloads := state.get("autoloads", {}) as Dictionary
	_assert_eq(autoloads.get("max_autoloads"), 10, "autoload max")
	_assert_true(int(autoloads.get("total", 0)) >= 1, "autoload total")
	var sampled_autoloads := autoloads.get("sampled", []) as Array
	var runtime_autoload := _find_named(sampled_autoloads, "RuntimeAutoload")
	_assert_eq(runtime_autoload.get("resource_path"), "res://scripts/runtime_autoload.gd", "autoload resource")
	_assert_eq(runtime_autoload.get("singleton"), true, "autoload singleton")
	_assert_eq(runtime_autoload.get("present_in_tree"), true, "autoload present")
	_assert_eq(runtime_autoload.get("node_path"), "RuntimeAutoload", "autoload node path")

	var truncated_input_state := RuntimeStateModel.collect_state(self, {
		"reason": "input_truncated",
		"max_nodes": 10,
		"max_depth": 4,
		"max_input_actions": 1,
	})
	var truncated_input := truncated_input_state.get("input", {}) as Dictionary
	_assert_eq((truncated_input.get("sampled_actions", []) as Array).size(), 1, "input sampled cap")
	_assert_true((truncated_input.get("active_actions", []) as Array).has("runtime_probe_test_action"), "truncated input active overflow action")
	var truncated_action_state := _find_named(truncated_input.get("action_states", []) as Array, "runtime_probe_test_action")
	_assert_eq(truncated_action_state.get("pressed"), true, "truncated input active overflow state")
	_assert_true(bool(truncated_input.get("truncated", false)), "input truncated")

	var truncated := RuntimeStateModel.collect_state(self, {
		"reason": "truncated",
		"max_nodes": 1,
		"max_depth": 4,
	})
	var truncated_tree := truncated.get("tree", {}) as Dictionary
	_assert_true(bool(truncated_tree.get("truncated", false)), "truncated flag")
	_assert_eq(truncated_tree.get("node_count_sampled"), 1, "truncated count")
	var truncated_root := ((truncated_tree.get("nodes", []) as Array)[0]) as Dictionary
	_assert_eq(truncated_root.get("children_truncated"), true, "children truncated flag")
	_assert_eq(truncated_root.get("omitted_child_count"), 5, "omitted children count")

	Input.action_release("runtime_probe_test_action")
	InputMap.erase_action("runtime_probe_test_action")
	ProjectSettings.set_setting("autoload/RuntimeAutoload", null)
	autoload_node.queue_free()
	root.queue_free()


func _find_named(items: Array, name: String) -> Dictionary:
	for item in items:
		var entry := item as Dictionary
		if str(entry.get("name", "")) == name:
			return entry
	return {}


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
