# Godot Codex Bridge Contracts

Protocol version: `godot-codex-bridge/0.1`

This directory defines the MVP bridge contract between the Godot Editor addon
and the MCP server. The contract is deliberately local, bounded and
privacy-aware.

## Local Bridge Transport

The addon and MCP server exchange state through the Godot project-local bridge
directory:

```text
.godot/godot_codex_bridge
```

Recommended layout:

```text
.godot/godot_codex_bridge/context_snapshot.json
.godot/godot_codex_bridge/requests/<request_id>.json
.godot/godot_codex_bridge/responses/<request_id>.json
.godot/godot_codex_bridge/artifacts/screenshots/<screenshot_id>.png
.godot/godot_codex_bridge/artifacts/logs/<run_id>.log
```

The bridge directory is generated local evidence/cache. It must not be treated
as public release material and should not be uploaded without user approval.

## MVP Request Types

- `refresh_context`: ask the addon to capture a fresh context snapshot.
- `capture_viewport_screenshot`: ask the addon to save a viewport screenshot
  under the local bridge artifacts directory and return metadata.
- `run_current_scene`: ask the addon/editor side to run the currently open
  scene through the approved Godot execution path.

## Schema Files

- `schemas/context-snapshot.schema.json`: full read-only Godot context snapshot.
- `schemas/bridge-request.schema.json`: addon request envelope.
- `schemas/bridge-response.schema.json`: addon response envelope.
- `schemas/screenshot-metadata.schema.json`: local screenshot evidence shape.
- `schemas/diff-preview-result.schema.json`: safe diff preview result shape.
- `schemas/blender-import-manifest.schema.json`: project-local Blender/AI
  import manifest shape under `res://assets/ai_imports/blender`, including
  mesh/scene/resource assets and `.png` Sprite2D assets.

## Bounding And Privacy Rules

- Scene trees are summaries, not full serialized scenes.
- MVP 3D node hints cover `Camera3D`, `Light3D` subclasses,
  `MeshInstance3D`, `CollisionShape3D` and `NavigationRegion3D`.
- Selected node properties are allowlisted/summarized and may be redacted.
- Large values, binary data, texture/image payloads, imported asset contents,
  environment secrets and full script bodies are omitted.
- Screenshots are local sensitive evidence. The schema intentionally has no
  external URL field.
- Diff preview results describe proposed changes only. They do not apply,
  approve or authorize mutation.
- Blender/AI import manifests are read-only planning inputs. They must reference
  project-local assets under `res://assets/ai_imports/blender`; they do not
  authorize external copying, overwrites, automatic placement or scene saves.
