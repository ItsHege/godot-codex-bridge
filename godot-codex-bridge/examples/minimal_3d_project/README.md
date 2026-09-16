# Minimal 3D Project Fixture

Tiny Godot 4.7 project used to validate the bridge against a real 3D scene.
It is intentionally text-only and avoids heavy binary assets.

## Contents

- `project.godot` points the default run scene to `res://scenes/main_3d.tscn`.
- `scenes/main_3d.tscn` includes a `Node3D` root, `Camera3D`,
  `DirectionalLight3D`, `MeshInstance3D`, `StaticBody3D` and
  `CollisionShape3D`.
- `scenes/test_3d.tscn` mirrors the same core 3D nodes and exits cleanly after a
  short timer for CLI smoke validation.
- `scenes/test_auto_exit.gd` contains the bounded auto-exit logic.

## Validation Commands

Run these from the workspace root:

```powershell
& $env:GODOT_BIN --version
& $env:GODOT_BIN --headless --path "godot-codex-bridge\examples\minimal_3d_project" --quit
& $env:GODOT_BIN --headless --path "godot-codex-bridge\examples\minimal_3d_project" --scene "res://scenes/test_3d.tscn" --quit-after 60
```

Expected result:

- The version command reports Godot 4.7.1.
- The fixture import/smoke command exits with code 0.
- The test scene prints start and clean-exit messages, then exits with code 0.
