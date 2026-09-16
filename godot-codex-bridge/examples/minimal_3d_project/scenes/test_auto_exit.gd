extends Node3D

@export var exit_after_seconds: float = 0.2

func _ready() -> void:
	print("Godot Codex Bridge test scene started")
	await get_tree().create_timer(exit_after_seconds).timeout
	print("Godot Codex Bridge test scene exiting cleanly")
	get_tree().quit(0)
