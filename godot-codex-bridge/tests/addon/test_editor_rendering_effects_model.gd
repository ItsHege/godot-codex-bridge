extends SceneTree

const BridgeContext := preload("res://addons/godot_codex_bridge/core/bridge_context.gd")
const EditorRenderingEffects := preload("res://addons/godot_codex_bridge/core/editor_rendering_effects.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge editor rendering/effects tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge editor rendering/effects tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	_assert_true("glow_enabled" in EditorRenderingEffects.environment_property_names(), "environment properties include glow")
	_assert_true("fog_enabled" in EditorRenderingEffects.environment_mutable_property_names(), "mutable environment properties include fog")
	var bad_property := EditorRenderingEffects.validate_environment_mutable_property("sky")
	_assert_eq(bad_property.get("code"), "unsupported_environment_property", "object environment property rejected")
	var ok_property := EditorRenderingEffects.validate_environment_mutable_property("glow_enabled")
	_assert_eq(ok_property.size(), 0, "simple environment property accepted")

	var root := Node3D.new()
	root.name = "Root"
	var world := WorldEnvironment.new()
	world.name = "World"
	world.environment = Environment.new()
	root.add_child(world)
	var particles := GPUParticles3D.new()
	particles.name = "Particles"
	root.add_child(particles)

	var world_nodes: Array = []
	var camera_nodes: Array = []
	var particle_nodes: Array = []
	var state := {"visited": 0, "matched": 0, "truncated": false, "seen": {}}
	EditorRenderingEffects.collect_rendering_effect_nodes(root, root, world_nodes, camera_nodes, particle_nodes, state, 16, true)
	_assert_eq(world_nodes.size(), 1, "world environment collected")
	_assert_eq(particle_nodes.size(), 1, "particle node collected")
	_assert_true(EditorRenderingEffects.node_is_particle_effect(particles), "particle node detected")
	_assert_true(EditorRenderingEffects.node_has_non_null_property(world, "environment"), "environment property detected")

	var stats := {"environment_resources": 0}
	var environment_payload: Variant = EditorRenderingEffects.environment_payload(world.environment, true, stats)
	_assert_true(typeof(environment_payload) == TYPE_DICTIONARY, "environment payload dictionary")
	_assert_true((environment_payload as Dictionary).has("enabled_effects"), "environment payload effects")

	var particle_stats := {"particle_nodes": 0, "particles_without_process_material": 0, "gpu_particles_without_draw_pass": 0}
	var suggestions: Array = []
	var particle_payload := EditorRenderingEffects.particle_node_payload(particles, root, particle_stats, suggestions)
	_assert_eq((particle_payload.get("node", {}) as Dictionary).get("name"), "Particles", "particle payload node name")
	_assert_true(int(particle_stats.get("particles_without_process_material", 0)) >= 1, "missing process material counted")

	var ctx := BridgeContext.new()
	ctx.permissions = {"allow_editor_inspect": false, "allow_scene_edits": false}
	var service := EditorRenderingEffects.new(ctx)
	var denied_inspect := service.inspect_rendering_effects({})
	_assert_false(bool(denied_inspect.get("ok", true)), "inspect rendering denied when permission disabled")
	_assert_eq(((denied_inspect.get("error", {}) as Dictionary).get("code")), "permission_denied", "inspect permission code")
	var denied_edit := service.set_environment_property({})
	_assert_false(bool(denied_edit.get("ok", true)), "set environment denied when permission disabled")
	_assert_eq(((denied_edit.get("error", {}) as Dictionary).get("code")), "permission_denied", "edit permission code")
	root.free()


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
