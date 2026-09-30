# MCP Tools

The MVP server is a local stdio MCP server implemented in TypeScript/Node with
the official MCP TypeScript SDK. Tools are intentionally narrow and
Godot-aware.

## Live Addon Availability

Every editor action the MCP server sends is registered by the addon, and an
addon test checks that the advertised action list matches the registered
handlers. `godot.editor_viewport_navigate` supports the 2D viewport only; 3D
camera control returns `editor_api_unavailable`.

These tools are registered but intentionally fail closed with
`trusted_runtime_approval_unavailable` until the addon exposes trusted live
runtime authorization:

- `godot.playtest_input`
- `godot.run_playtest_scenario`

## MVP Tools

### godot.get_tool_catalog

Returns a grouped catalog for the flat `godot.*` tool list. Agents should use
this when they are unsure which tool to pick, or before a multi-step workflow.
The payload includes category names, safety levels, short "use when" guidance
for every registered Godot tool, and recommended workflows such as
`orient_before_editing`, `inspect_scene_problem`, `safe_live_scene_edit`,
`text_diff_edit`, and `runtime_smoke`.

Inputs:

- `category` optional: return only one tool category such as
  `orientation`, `scene_mutation`, `runtime`, or `persistence_safety`.
- `intent` optional: describe what the agent is trying to do, such as
  "move a selected node and save the scene" or "run playtest and capture crash
  output". The response includes ranked `matched_workflows` and
  `recommended_next_tools` so agents do not need to scan the whole flat tool
  list before acting.
- `view` optional: `full` returns the complete tool metadata list and remains
  the default for compatibility. `compact` returns workflow routing, category
  summaries, primary tools and an `omitted_tool_count` without returning the
  entire flat tool list. Agents should prefer `view=compact` for initial
  routing, then request `view=full` with a specific `category` only when exact
  tool metadata is needed.

This is a read-only selection helper. It does not contact the live addon, run
Godot, read project files, mutate scenes, or replace the existing narrow tools.
It exists to reduce poor tool selection while preserving backward-compatible
flat MCP tool names.

### godot.bridge_status

Returns bridge readiness diagnostics before an agent tries editor-backed
actions. The payload includes project root, addon path, detectable plugin
enabled status, heartbeat age, snapshot age, protocol version, addon version,
active/stale editor state, and addon request transport diagnostics.

The Host `/bridge/request` HTTP endpoint currently returns
`bridge_rpc_unavailable` while an authenticated MCP transport is designed.
Addon-backed MCP requests use the project-local file bridge (`requests/` and
`responses/`). A discovered Host URL may still appear as the preferred route
in transport diagnostics, but it does not indicate a working HTTP relay.

The MCP server discovers the Host RPC URL from
`addons\godot_codex_bridge\host_config.json` when that file is present. Discovery
is local-only: localhost targets are accepted, non-local hosts are ignored, and
PowerShell-written UTF-8 BOM files are handled.

Addon-backed request tools include transport evidence in their response. With
the current Host, a configured HTTP attempt returns 503 and the response uses
`transport: "file_polling"`, with `fallback_reason` and both attempts recorded.

Agents should call this first. If the editor is stale or unavailable, addon
request tools return structured `bridge_unavailable` instead of waiting for a
silent timeout.

### godot.get_current_scene

Returns current scene metadata from the latest bridge snapshot: project path,
scene path, root node name/type, dirty/open state when available, and generation
timestamp.

### godot.get_scene_tree

Returns a bounded scene tree: node path, name, type, owner path, script path, and
key 3D hints for cameras, lights, meshes, collision shapes, and navigation
regions.

### godot.get_selected_nodes

Returns selected nodes and a bounded inspector/property summary. It should skip
large arrays, binary data, texture payloads, and full private resource dumps.

### godot.get_editor_output

Returns recent bridge/editor output where available. For MVP, bridge logs and
Godot CLI run output are required; direct Output panel scraping is best-effort
only if supported by official APIs.

### godot.get_resource_status

Returns bounded resource/import status, missing resource hints, scan state, and
obvious load/import errors.

### godot.get_gameplay_context

Returns bounded gameplay/project context from the latest snapshot: input actions
from project settings, autoload singletons, named render/physics/navigation
layers and key project settings such as main scene, viewport size, stretch mode,
physics ticks and renderer. This helps agents reason about controls, gameplay
globals, collisions and platform behavior without editing `project.godot`.

### godot.get_script_inventory

Returns a bounded GDScript inventory from the latest snapshot without dumping
full source files. Each script summary may include `class_name`, `extends`,
`@tool`, signals, exports, function signatures, TODO/FIXME markers, scan line
count and truncation status. This helps agents find gameplay entry points and
public script surface before making code changes.

## Live Editor Control V1

These tools require a live Godot editor addon heartbeat. They use the shared
addon request type `editor_control` and return structured errors such as
`bridge_unavailable`, `permission_denied`, `invalid_request` and
`editor_api_unavailable` instead of silently failing.

Navigation and inspection tools are enabled by default in the Godot dock.
Scene mutation tools require the `Scene edits via UndoRedo` permission and do
not save scenes automatically.

### godot.refresh_editor_context

Asks the addon to write a fresh `context_snapshot.json` and returns snapshot
metadata, current scene and selected node count.

### godot.editor_get_state

Returns live editor state: current/open scenes, selected nodes/files, editor
permissions, editor-control capabilities, diagnostics counts, recent actions
and a read-only project settings summary.

### godot.editor_focus

Switches Godot main screens (`2D`, `3D`, `Script`, `Game`, `AssetLib` or
`Codex Bridge`) and can select an existing `res://` file in the FileSystem dock.
It is editor navigation only and does not mutate scenes.

### godot.editor_focus_panel

Focuses a native Godot editor panel/tab such as `Output`, `Debugger`,
`Stack Trace`, `Audio`, `Animation`, `Shader Editor`, `Signal Visualizer`,
`Profiler`, `Visual Profiler`, `Monitors`, `Video RAM`, `Network Profiler`,
`Inspector`, `FileSystem`, `Scene`, or `Import`.

This is navigation-only. It uses the live editor control tree to focus a known
tab and returns `editor_panel_not_found` if the tab is not present in the
current layout. It does not clear native Output/Debugger content; use
`godot.diagnostics_clear` only for the bridge-owned diagnostics buffer.

### godot.select_node

Selects a scene-local node path in the live editor. It can optionally open the
target scene first and focus the Inspector. Node paths must be scene-local, not
absolute filesystem paths or `res://` file paths.

### godot.inspect_node

Selects a node, focuses the Inspector and returns bounded node/property
metadata. Large values, resources, arrays, dictionaries and object payloads stay
summarized or omitted.

### godot.get_inspector_context

Reads the current Inspector edited object, selected property path and a bounded
property-category summary. It does not scrape the native Inspector UI, so
visible/folded category state is reported as unsupported instead of guessed.

### godot.get_node_deep

Reads an on-demand bounded node subtree from the live editor. This is meant for
the cases where the global `context_snapshot.json` is intentionally capped and
the agent needs deeper context around one specific node.

Inputs include a scene-local `nodePath`, `depth`, `maxNodes` and
`includeProperties`. Returned properties still use bounded summaries: resources,
objects, arrays, dictionaries and binary-like values are summarized or omitted.

### godot.get_spatial_bounds

Reads bounded world-space Node3D placement facts from the live editor:
scene-local node path, global transform, world-space AABB, bounds source,
ground reference and signed `ground_gap`. It supports a single `nodePath`,
current selection, a simple `groupName`, or a bounded scene scan.

### godot.spatial_query

Runs read-only geometric spatial queries against the edited scene. Supported
queries are `ground_gap`, `aabb_overlap` and `runtime_raycast`. Runtime raycast
returns `spatial_query_unavailable` from editor context until a real runtime
playtest/raycast flow owns that session.

### godot.placement_check

Runs a bounded read-only placement validation over one node, the selection, a
group, or a scene scan. It flags `floating`, `below_ground`, `clipping`,
`off_grid` and `unmeasured` targets with measured gap/overlap/grid deltas and
safe suggested follow-up actions. It does not move nodes, save scenes or apply
fixes.

### godot.undo_last_bridge_action

Undoes the latest Godot Codex Bridge editor action from the current editor
session, in the current scene's or the global (external resource) history. It
runs the editor's own Undo so Godot's history stays consistent, and it never
undoes a user action: it refuses with `newer_editor_action` when any edit, undo
or redo happened afterward, `no_tracked_bridge_action` after a plugin reload or
when nothing was tracked, `not_bridge_action`, `bridge_action_in_other_scene`,
`editor_undo_unavailable`, `undo_mismatch` or `undo_failed`. Repeated calls walk
back through consecutive Bridge actions. The scene is never saved.

Node lifecycle tools follow the Scene dock's ownership rules: deleting or
reparenting a node that belongs to an instanced sub-scene fails with
`foreign_scene_node`, and creating, duplicating, instancing or reparenting under
a parent inside an instance without Editable Children fails with
`parent_not_editable`. Owners of all descendants survive delete/undo, reparent
and duplicate, so children are kept on save.

### godot.snap_to_ground

Moves measured Node3D targets through UndoRedo so their world-space AABB bottom
rests on the ground reference. Inputs use the spatial selector contract:
`nodePath`, `groupName`, or `selectedOnly=true`; broad scene mutation is
rejected. Optional `groundY`, `tolerance`, `gridSize`, `gridOrigin` and
`alignToSurface` are accepted. Current editor-time `alignToSurface` rotates only
when a reliable ground/terrain/floor Node3D top surface normal is detected;
otherwise it reports that no surface normal was available instead of guessing.

The tool returns before/after global positions, measured ground deltas, skipped
items, summary counts, `undo_redo_action=true`, `auto_saved=false` and, by
default, a local `screenshot_after_action` response. It never saves the scene.

### godot.snap_to_grid

Moves selected, grouped or single Node3D targets through UndoRedo to a placement
grid. `gridSize` is required; `gridOrigin`, `axes` (`x`, `y`, `z`), `tolerance`
and `captureScreenshot` are optional. The default axes are X/Z. Like
`snap_to_ground`, broad scene mutation is rejected and the scene is not saved.

### godot.open_script

Opens an existing project-local `.gd`, `.cs`, `.gdshader` or `.shader` file in
the Script editor and can request a line jump when the editor API supports it.

### godot.list_resources

Asks the live Godot ResourceFilesystem for bounded resource/import metadata.
Inputs can filter by `rootPath`, file `extensions`, Godot `typeFilter` and
`limit`. The tool returns paths, resource types and import validity; it does not
load resource contents or dump binary data.

### godot.inspect_imported_assets

Reads bounded imported-asset metadata through the live editor resource listing.
Inputs can filter by `rootPath`, `extensions`, `typeFilter`, `invalidOnly`,
`placeableOnly`, `includeDependencies` and `limit`. The response adds
asset-oriented fields such as `placeable`, `placeable_kind`, `loadable`,
`import_valid` and optional dependency summaries.

This is read-only. V1 does not edit import presets, reimport files, copy external
assets into the project, delete assets or save scenes.

### godot.plan_blender_asset_import

Reads a project-local Blender/AI import manifest from
`res://assets/ai_imports/blender/manifest.json` by default, or another `.json`
manifest under the same allowlisted folder. The manifest may list up to 50
assets with project-local `res://assets/ai_imports/blender/...` paths. V1
placeable import assets include mesh/scene/resource files plus `.png` textures,
which are placed as `Sprite2D` nodes.

This is a read-only planner. It does not call Blender, copy external files,
overwrite project assets, place nodes, mutate scenes or save anything. The
response returns sanitized manifest metadata, accepted/rejected asset entries
and a `suggested_workflow`: first inspect the import folder with
`godot.inspect_imported_assets`, then optionally call `godot.place_asset_in_scene`
for existing assets only. Placement remains a separate UndoRedo-backed tool call
with normal scene-edit permissions.

If exported files are still outside the Godot project, use
`npm run stage:blender-import -- ...` first. That helper is dry-run by default
and requires `-Apply` before it copies explicitly listed files into
`assets/ai_imports/blender/<batch>/` and writes the compatible manifest. Its
JSON response includes `post_copy_import_status`: dry-runs report `not_run`,
while applied copies report `pending_godot_import_scan` and point to
`godot.inspect_imported_assets` for the read-only post-copy import/resource
status check.

### godot.get_class_info

Reads bounded ClassDB metadata for Godot engine/GDExtension classes: parent
class, instantiate support, node/resource classification, properties, methods,
signals, integer constants and enums. This is useful before creating nodes or
setting properties. Script-defined `class_name` classes are not part of ClassDB
and remain discoverable through project/script inventory tools instead.

### godot.inspect_materials

Reads live material and shader diagnostics from the current edited scene. Inputs
can target one `nodePath`, selected nodes only or a bounded scene scan. The tool
returns material slots for `CanvasItem`, `GeometryInstance3D` and
`MeshInstance3D`, including mesh surface materials, surface overrides, effective
active materials, common material properties and `ShaderMaterial` shader/uniform
summaries.

This is read-only. It does not compile shaders, clear native Godot shader
errors, open native shader code popups, edit shader code or mutate material
parameters. Use `godot.set_shader_parameter` or the live Resource/material tools
for explicit UndoRedo-backed material edits after inspection.

### godot.create_shader_material_for_node

Creates a live `ShaderMaterial`, optionally loads a project-local Shader from
`res://.../*.gdshader`, `*.shader`, `*.tres` or `*.res`, applies up to 20
initial JSON-safe uniform values and assigns the material to a node material
slot through Godot UndoRedo. It targets the same slot names returned by
`godot.inspect_materials`: `canvas_item_material`, `geometry_material_override`
or `mesh_surface` with `surfaceIndex`.

This tool requires the Godot dock `Scene edits via UndoRedo` permission. It
does not save scenes or shader/resource files. V1 creates an unsaved live
subresource only; saving/external resource creation and texture/resource uniform
assignment remain future work.

### godot.set_shader_parameter

Edits one `ShaderMaterial` uniform on a live material slot through Godot
UndoRedo. It targets the same slot names returned by `godot.inspect_materials`:
`canvas_item_material`, `geometry_material_override` or `mesh_surface` with a
`surfaceIndex`. Supported V1 uniform values are JSON-safe bool, int, float,
string, Vector2, Vector3, Vector4 and Color payloads.

This tool requires the Godot dock `Scene edits via UndoRedo` permission, leaves
the scene dirty in the editor and never saves `.tscn`, `.tres` or shader files.
Texture/resource/object uniforms and shader source edits are intentionally out
of scope for V1.

### godot.set_shader_texture_parameter

Assigns or clears a project-local `Texture2D` resource on one `ShaderMaterial`
sampler uniform through Godot UndoRedo. Inputs mirror `godot.set_shader_parameter`
but use `texturePath` instead of inline JSON `value`; supported paths are
project-local `res://` texture/resource files such as `.png`, `.jpg`, `.webp`,
`.svg`, `.tres` and `.res`.

This tool requires the Godot dock `Scene edits via UndoRedo` permission, leaves
the scene dirty in the editor and never saves scene, material or texture files.
V1 is limited to `Texture2D`/sampler2D-style parameters; cubemaps, 3D textures
and arbitrary resource uniforms remain future work.

### godot.inspect_rendering_effects

Reads live rendering/effects diagnostics from the current edited scene. The
response can include `WorldEnvironment` nodes, `Camera3D` environment override
resources, bounded `Environment` properties such as background, ambient light,
tonemap, glow, fog, volumetric fog, SSAO/SSIL/SDFGI and color adjustment flags,
plus particle node summaries for `GPUParticles*` and `CPUParticles*`.

Inputs can scan the current scene or only selected nodes. The tool is read-only:
it does not create particle materials, compile shaders, clear native Godot
errors, edit Environment resources, change draw passes or save scenes. It is
meant to tell Codex what rendering state already exists before using explicit
UndoRedo-backed resource/property tools.

### godot.set_environment_property

Edits one allowlisted `Environment` property on a live `WorldEnvironment` node
or `Camera3D` environment override through Godot UndoRedo. Use
`godot.inspect_rendering_effects` first to identify the target node and current
property values. Supported V1 properties cover JSON-safe background color/mode,
ambient/reflected light, tonemap, glow, fog, volumetric fog, SSAO/SSIL/SDFGI and
adjustment scalar/color fields.

This tool requires the Godot dock `Scene edits via UndoRedo` permission, leaves
the scene dirty in the editor and never saves scene/resource files. It can create
an unsaved live `Environment` resource when `createIfMissing=true`. Object or
resource slots such as `sky` and `adjustment_color_correction` remain out of
scope for this V1 mutator.

### godot.create_particle_effect

Creates a live `GPUParticles3D` node with a `ParticleProcessMaterial` and, by
default, a `QuadMesh` draw pass so the effect is visible in the editor. The
tool supports bounded V1 fields for amount, lifetime, emitting/one-shot,
explosiveness/randomness, speed scale, initial transform, material color,
direction, gravity, spread, initial velocity and particle scale ranges.

This tool requires the Godot dock `Scene edits via UndoRedo` permission, leaves
the scene dirty in the editor and never saves scene/resource files. V1 is 3D
only (`kind=gpu_particles_3d`) and does not create particle collision nodes,
subemitters, curves/ramps, 2D particle effects or external saved resources.

### godot.set_particle_effect_properties

Edits an existing live `GPUParticles3D` node and its `ParticleProcessMaterial`
through Godot UndoRedo. The tool only changes fields explicitly provided by the
caller, so omitted fields keep their current editor values. V1 supports bounded
amount/lifetime/emission fields, visibility AABB size, `QuadMesh` draw size,
material color, direction, gravity, spread, initial velocity and particle scale.

This tool requires the Godot dock `Scene edits via UndoRedo` permission, leaves
the scene dirty in the editor and never saves scene/resource files. It can
create an unsaved `ParticleProcessMaterial` only when the node has no existing
process material and `createProcessMaterialIfMissing` is enabled. It does not
replace existing non-`ParticleProcessMaterial` shader process materials, and it
does not create particle collision nodes, subemitters, curves/ramps or saved
external resources.

### godot.editor_batch

Runs up to 12 typed editor-control actions in one addon request, for example:

```text
open_scene -> editor_focus -> select_node -> capture_viewport_screenshot
```

Batching is meant to reduce live editor latency. Nested batches and arbitrary
Godot method names are rejected.

### godot.set_node_transform

Applies an UndoRedo-backed unsaved transform edit to a live `Node2D` or
`Node3D`. Supported fields are local `position`, `rotationDegrees` and `scale`
with `mode` `absolute` or `relative`.

The tool records before/after values in the response. It leaves the scene dirty
in the editor and never writes `.tscn` files by itself.

### godot.set_node_properties

Applies up to 20 UndoRedo-backed unsaved safe property edits to a live editor
node. V1 supports JSON-safe scalar/struct values that match the existing
property type: bool, int, float, string, NodePath, Vector2, Vector3 and Color.

Unsupported properties such as `script`, `owner`, resources, objects, arrays and
dictionaries are rejected.

### godot.assign_resource_to_node

Assigns an existing project-local resource file to a Resource/Object node
property through editor UndoRedo, or clears the property when `clear: true`.
The tool validates `res://` paths and rejects absolute paths, traversal and
generated `.godot` / `.import` cache paths. It does not save the scene.

V1 is meant for properties such as `MeshInstance3D.mesh`,
`MeshInstance3D.material_override`, collision `shape` slots and similar
Resource-valued Inspector fields. Runtime compatibility is validated again by
the addon against the live property metadata.

### godot.create_node_resource

Creates an instantiable Godot `Resource`-derived class as a local live
subresource and assigns it to a node Resource property through editor UndoRedo.
Optional `changes` can set up to 20 scalar/vector/color properties on the new
resource before assignment. The scene becomes dirty in the editor, but no
`.tscn`, `.tres` or `.res` file is written automatically.

Practical V1 examples include creating a `BoxMesh` for `MeshInstance3D.mesh` or
a `StandardMaterial3D` for `MeshInstance3D.material_override`.

### godot.set_resource_properties

Edits up to 20 safe properties on the Resource currently assigned to a node
property, through editor UndoRedo. This is for live material/mesh/shape tweaks,
for example changing a `StandardMaterial3D.albedo_color` or a `BoxMesh.size`.

Like node property edits, V1 supports JSON-safe scalar/struct values that match
the existing property type: bool, int, float, string, NodePath, Vector2,
Vector3 and Color. Resource/object/array/dictionary property values are
rejected until a dedicated resource graph editor layer exists.

### godot.list_animation_players

Lists `AnimationPlayer` nodes in the active edited scene. The response includes
bounded node paths, current/assigned animation metadata, playback state,
animation libraries and animation names. This is read-only and uses the live
editor scene tree, not raw `.tscn` text parsing.

### godot.inspect_animation

Inspects one animation clip from an `AnimationPlayer`. Inputs include
`playerPath` and optional `animationName` / `libraryKey`. The payload is
bounded by track and key limits and summarizes track type, path, interpolation,
loop/length metadata and JSON-safe key values.

This is meant for "what does this animation do?" workflows before edits. Large,
object-like or unsupported key values are summarized rather than dumped.

### godot.preview_animation

Previews an animation in the editor through the selected `AnimationPlayer`.
Supported modes are `play` and `seek`. Preview is gated by the Godot dock
permission `Animation preview`, does not save scenes and is treated as editor
state, not a file mutation.

### godot.stop_animation_preview

Stops editor-side preview playback for an `AnimationPlayer`. This is also gated
by `Animation preview` and does not mutate disk files. Preview changes node
properties outside UndoRedo, so stop restores the values recorded before the
preview (up to 512 animated properties) unless `keepPose` is true. The response
reports `changed`, `pose_restored`, `restored_property_count`,
`restore_failed_count` and `restore_conflict_count`: a property edited during
the preview (by the user or an UndoRedo action) is left as edited and counted
as a conflict. In play mode user edits cannot be told apart from playback, so
`conflict_detection` is `playback_unverifiable`; seek/pause report `exact`. Saving while a preview is still running saves the
previewed pose, as in Godot's own animation editor.

### godot.create_animation_clip

Creates or replaces an animation clip on an existing `AnimationPlayer` through
Godot editor UndoRedo. Inputs include `playerPath`, `animationName`, optional
`libraryKey`, `length`, loop flag and initial tracks. V1 only creates value
tracks with JSON-safe key values: bool, int, float, string, Vector2, Vector3 and
Color.

The scene is left dirty in the editor and is never saved automatically. V1 does
not edit imported animation files, `AnimationTree` graphs, method/audio/bezier
tracks or arbitrary nested Resource/Object values.

### godot.create_node

Creates a Godot `Node`-derived child under a scene-local parent path through
editor UndoRedo. Inputs include `parentPath`, `className`, optional `name` and
optional child `index`. The scene is left dirty in the editor and is not saved.

### godot.delete_node

Removes a non-root node from the live edited scene through editor UndoRedo. The
edited scene root cannot be deleted through this tool.

### godot.rename_node

Renames a live editor node through UndoRedo. The response includes before/after
node references. Names with path separators or newlines are rejected.

### godot.reparent_node

Moves a non-root node under another scene-local node through UndoRedo. The tool
rejects attempts to reparent a node under itself or one of its descendants.

### godot.duplicate_node

Duplicates a non-root node and adds the duplicate under the same parent or an
explicit scene-local parent. The duplicate is selected after the edit. The tool
does not save the scene.

### godot.instance_scene

Instances an existing project-local `.tscn` or `.scn` `PackedScene` under a
scene-local parent path through UndoRedo. Absolute paths, traversal and generated
cache/import paths are rejected.

### godot.place_asset_in_scene

Places an existing project-local asset under a scene-local parent through
UndoRedo. V1 supports `PackedScene` assets and mesh-like imported/local assets
such as `.glb`, `.gltf`, `.obj`, `.fbx`, `.dae`, `.blend`, `.mesh`, `.tscn`,
`.scn`, `.res` and `.tres` when Godot can load them as a `PackedScene` or
`Mesh`, plus `.png` assets loaded as `Texture2D` and placed as `Sprite2D`.
Optional inputs can set the new node name, position, rotation and scale.
`createCollider=true` requests a best-effort `StaticBody3D` +
`CollisionShape3D` box collider for placed `MeshInstance3D` assets.
`materialColor` applies an unsaved `StandardMaterial3D` override to
`MeshInstance3D` placements or `modulate` to `Sprite2D`/`CanvasItem` placements.
Unsupported option/asset combinations are reported as skipped in
`placement_options` rather than silently claimed.

By default the MCP wrapper captures a post-placement viewport screenshot and
returns it as `screenshot_after_action`. Set `captureScreenshot=false` to skip
that evidence request.

The tool never saves the scene automatically. It rejects absolute paths,
traversal, generated `.godot`/`.import` paths and unsupported resource types.

### godot.list_signal_connections

Reads signal connection metadata for a live node. It can include only connected
signals or all declared signals with empty connection lists. This is read-only.

### godot.connect_signal / godot.disconnect_signal

Connects or disconnects a source node signal to a target node method through
UndoRedo. The tool validates scene-local source/target node paths and simple
signal/method names. It does not edit scripts or create missing callback
methods; that remains a normal code/file workflow with review.

### godot.diagnostics_get

Returns bridge-owned diagnostics, import/resource status evidence already in
snapshots, recent run/check summaries where present and support flags for native
Godot Output/Debugger capture.

### godot.diagnostics_clear

Clears only the bridge-owned diagnostics buffer after first writing a local
evidence artifact. V1 does not claim to clear Godot's native Output/Debugger
panel unless a supported official API path is added later.

### godot.notes_get / godot.notes_append / godot.notes_clear

Manage local bridge notes under `.godot\godot_codex_bridge`. These notes are
for agent/editor coordination and do not mutate project gameplay files.

### godot.inspect_3d_scene

Returns read-only 3D diagnostics from the latest scene tree snapshot. The tool
summarizes cameras, current cameras, lights, meshes, collision shapes,
navigation regions, selected nodes, node count, and bounded performance probes.

It reports findings and safe suggestions for common issues such as missing
Camera3D, no current camera, missing lights, meshes without collision shapes,
disabled collision shapes, missing navigation meshes, hidden important 3D nodes,
camera far clip likely missing captured mesh bounds, material count below surface
count, and truncated snapshots. Suggestions are advisory only and never mutate
project files or scenes.

The response includes `camera_framing` with estimated mesh bounds and current
camera distance/far-clip margin when mesh AABB data is available. It also
includes `debug_layers` for collision shapes and navigation regions.

When the addon has written a `performance` block into the latest snapshot, the
tool reports best-effort Godot Performance monitor values for draw calls,
rendered objects, primitives, 3D active physics objects, collision pairs,
physics islands and navigation counters. If those monitors are absent, the tool
returns a structured unavailable reason.

When the snapshot contains performance samples, the tool also returns a bounded
timeline summary: sample count, first/last timestamps, min/max/average draw
calls, primitives, render objects, 3D physics object/collision-pair counts and
navigation agent counts.

### godot.performance_get_snapshot

Returns a dedicated read-only performance summary from the latest context
snapshot. The response separates rendering, 3D physics and navigation monitor
groups, includes bounded timeline stats, reports scene node count when present,
and returns findings for high draw-call or collision-pair snapshots.

The tool is intentionally honest about unsupported metrics: memory and
VRAM/video-memory fields return `status: "unavailable"` until the addon snapshot
contract exposes stable editor monitors for them.

### godot.create_diagnostic_snapshot

Persists the current read-only 3D diagnostics payload as a local bridge artifact:

```text
.godot\godot_codex_bridge\artifacts\diagnostic_snapshots
```

This is useful for collision/navmesh/debug review and visual QA notes. It does
not mutate project scenes or resources.

### godot.check_export_readiness

Reads `project.godot` and `export_presets.cfg` to report PC/mobile export
readiness without running exports. It checks project name, main scene presence,
main scene file existence, configured Godot executable, desktop presets
Windows/Linux/macOS, mobile presets Android/iOS, preset names, platforms and
export paths.

This is advisory only. It does not create export presets, run exports, sign
mobile builds, publish artifacts, or touch real accounts.

### godot.create_undo_snapshot

Creates a local bridge artifact snapshot for explicitly listed project-relative
text scene/script/resource files. It copies those files under:

```text
.godot\godot_codex_bridge\artifacts\undo_snapshots
```

The tool rejects absolute paths, `..` traversal, generated cache/import paths,
unsupported file extensions, directories and oversized files. It does not modify
the source project files and does not restore anything automatically.

### godot.create_visual_baseline

Temporarily disabled. The MCP server cannot yet verify both the live screenshot
permission and project-confined provenance of the supplied PNG. Calls fail
closed with `trusted_screenshot_permission_unavailable`; this is a mitigation,
not a completed approval design.

### godot.compare_visual_regression

Temporarily disabled. Project confinement alone cannot prove that arbitrary PNGs
under the artifact tree were captured by the Bridge with live screenshot
permission. Calls fail closed with
`trusted_visual_input_provenance_unavailable`. The bounded PNG parser remains
covered by isolated tests for a future provenance-backed workflow.

### godot.generate_scene_from_prompt

Returns a safe live-editor action plan for building or editing a scene from a
prompt. It no longer generates `.tscn` file content, returns `proposed_content`,
or applies files. This prevents agents from using a keyword template when the
live Godot editor tools can inspect the actual scene, create nodes through
UndoRedo, capture screenshots, and explicitly save after review.

The result includes human-readable `planned_actions`, machine-oriented
`suggested_tool_calls`, `recommended_tools`, detected feature tags and a clear
`write_behavior` value of `no_file_write_no_generated_scene_content_no_apply`.
If `apply=true` is passed, the tool rejects the request with
`scene_generator_apply_removed`.

`suggested_tool_calls` contains concrete MCP tool names and arguments for the
live editor path, such as `godot.editor_get_state`, `godot.open_scene`,
`godot.create_node`, `godot.create_node_resource`,
`godot.set_node_transform`, `godot.set_node_properties`,
`godot.editor_batch`. These are suggestions, not an
automatic batch: the agent should still inspect permissions, live editor state
and screenshots. Save reviewed changes from the Godot editor UI.

Feature tags are intentionally conservative. A vague prompt such as "make this
feel more dramatic" returns editor/navigation/evidence planning steps without
inventing default ground, cube, wall, camera, light or prop geometry. Concrete
scene features are only planned when the prompt names clear environment cues
such as ground, terrain, forest, room, wall, trees, water, rocks, paths or
platforms. Explicit camera or lighting prompts still produce camera/light tool
call suggestions even when no geometry feature is detected.

### godot.save_scene

Temporarily disabled. Every call fails closed with
`trusted_scene_save_approval_unavailable`. A standing permission toggle is not
enough to bind a save to the exact dirty scene state, target and rollback
evidence. Save reviewed changes from the Godot editor UI.

### godot.save_all_scenes

Temporarily disabled with the same fail-closed error. Re-enabling save-all
requires one-use approval and rollback coverage for every exact dirty scene.

### godot.apply_approved_diff

Temporarily disabled. Every call fails closed with
`trusted_approval_unavailable`; caller-supplied approval tokens are not accepted.
Use `godot.preview_scene_diff` for review and a trusted user-controlled workflow
for application until Host/UI-issued, short-lived, single-use, fully bound
approval receipts are implemented.

### godot.fix_selected_node

Temporarily disabled. The former public token was not a trusted human approval
and has been removed. Use the Godot editor UI and UndoRedo directly until a
short-lived, single-use receipt can bind the exact project, selected node,
property, old value, and proposed value.

### godot.capture_viewport_screenshot

Requests the addon to capture a viewport screenshot and returns local metadata:
artifact path, timestamp, dimensions if known, and bridge request status.

Screenshots stay local under:

```text
.godot\godot_codex_bridge\artifacts\screenshots
```

If the editor bridge is unavailable, the tool should return a structured
`bridge_unavailable` style error rather than pretending capture succeeded.

### godot.capture_timeline_screenshots

Requests a bounded sequence of viewport screenshots from the live addon and
writes a local manifest under:

```text
.godot\godot_codex_bridge\artifacts\timeline_captures
```

Inputs:

- `frameCount`: 2-12 frames, default 3.
- `intervalMs`: 50-5000 ms between frames, default 250.
- `reason`: optional short label for the capture sequence.
- `timeoutMs`: per-frame addon request timeout.

The tool is intended for animation, shader, camera-framing and runtime feedback
loops where a single screenshot is too weak. It returns local metadata and
manifest paths only; PNG bytes are not sent through MCP responses. If a frame
fails, the manifest records captured frames and the first structured error.

### godot.capture_multi_view_screenshots

Requests the live addon to render offscreen local PNG evidence for a 3D target
from multiple angles: front, side, top and perspective. It is intended for
placement validation where one ambiguous viewport angle is not enough.

Inputs:

- `nodePath`: optional scene-local Node3D target.
- `groupName`: optional simple Godot group selector. Use either `nodePath` or
  `groupName`, not both.
- `selectedOnly`: defaults to true when no explicit selector is provided.
- `maxNodes`: bounded target/descendant scan, default 32, max 256.
- `width` / `height`: 64-2048 pixels, default 1024x768.
- `views`: any subset of `front`, `side`, `top`, `perspective`.
- `baselineName` / `baselinePath`: optional local visual regression comparison.

The addon stores artifacts under:

```text
.godot\godot_codex_bridge\artifacts\multi_view_captures
```

Responses include the local manifest path, per-view local PNG paths, camera
metadata, render diagnostics and optional `baseline_comparison`. Each frame
declares `render_source`: `subviewport_gpu` for a live offscreen rendered frame,
or `software_geometry_fallback` when the GPU frame was detected as uniform/
background-only and replaced with labelled geometry evidence. PNG bytes are not
sent through MCP JSON responses. This is read-only: it does not move nodes, save
scenes or mutate resources. Headless/unavailable editor states return structured
errors such as `multi_view_capture_unavailable` or `bridge_unavailable`.

### godot.list_annotations

Lists local Eye Attach / AI Marker artifacts created by the Godot editor addon.
This is read-only and returns annotation ids, capture scope, marker count,
local artifact paths and privacy notes. It does not send PNG bytes through MCP.

### godot.get_latest_annotation

Returns the newest local annotation artifact under:

```text
.godot\godot_codex_bridge\artifacts\annotations
```

The returned manifest marks every drawn shape as `user_reference_marker` with
`non_game_overlay: true` and `do_not_recreate_marker_graphics: true`.

### godot.get_annotation

Reads one annotation by id. The id is bridge-directory bounded and must contain
only letters, numbers, dot, underscore or dash. Absolute paths and traversal are
rejected.

### godot.resolve_annotation_target

Reads a local annotation and resolves one marker into conservative editor target
candidates. V1 uses marker metadata, normalized bounds, capture-time selected
nodes and current scene context. It returns confidence-scored candidates and
suggested editor tools such as `godot.select_node` / `godot.open_scene` when
safe. It explicitly returns `world_ray_supported:false` and does not claim
pixel-perfect Inspector fields, viewport ray hits or world-space targets without
a future typed ray/crop contract.

### godot.run_current_scene

Requests a run of the editor's current scene. Optional `scenePath` may be used
for deterministic playtest flows when the agent must run a specific
project-local `.tscn` / `.scn` instead of relying on the active editor tab.
Absolute paths, traversal and missing scenes are rejected before the addon
request is written.

### godot.stop_running_scene

Stops the current Godot editor play session if one is active. This is a typed
editor-control cleanup action for `godot.run_current_scene` workflows. It
returns `was_playing`, `playing_scene`, `stopped` and `requested_at`. Playtest
input is disabled in this addon version, so there is no held input or playtest
session token to release.

It does not inspect the running game tree or gameplay state.

### godot.emergency_stop

Emergency cleanup wrapper around the same typed stop path. It stops the play
session only when Godot Codex Bridge started it (`bridge_owned_play_session`);
a play session the user started keeps running and the response says so. It
never saves or mutates the edited scene. Use it when a live editor task is interrupted,
times out or the agent needs to guarantee the runtime harness is idle before a
new attempt.

This is not a broad process killer and does not terminate external programs. It
only uses Godot editor APIs and Bridge-owned playtest session cleanup.

### godot.playtest_input

Temporarily disabled. The addon does not currently expose a production
`playtest_input` editor-control action, so MCP fails closed with
`trusted_runtime_approval_unavailable` instead of advertising a permission gate
that cannot be exercised and verified end to end.

### godot.run_playtest_scenario

Temporarily disabled with the same fail-closed error. Re-enabling it requires a
default-off addon action that binds the exact project, scene, bounded steps and
Bridge-owned runtime session to live authorization and cleanup evidence.

Safety model: it requires both `Run current scene` and `Playtest input`
permissions, writes no scene files, executes no arbitrary scripts, only targets
project-local `.tscn` / `.scn` paths and stops the bridge-owned play session on
success or failure. If the scenario harness cannot initialize the runtime probe,
it returns `playtest_unavailable` with the original reason instead of pretending
that gameplay was tested. Failed scenarios include `stop_result` cleanup
evidence so callers can verify no held actions or active playtest session token
remain.

`npm run validate:playtest-scenario-evidence` is the visible proof gate for
assertion evidence refs. `npm run validate:failed-run-cleanup` is the safety
gate for emergency stop, failed-run cleanup and stuck-input prevention.

### godot.runtime_get_state

Reads the local opt-in runtime probe file:

`.godot/godot_codex_bridge/runtime/state.json`

To produce this file, add
`res://addons/godot_codex_bridge/runtime_state_probe.gd` to a running scene or
autoload in the Godot project. The probe writes bounded node, group, transform
and performance monitor evidence for the running game. The current runtime
shape also includes bounded engine/time counters, sampled input action names
with currently active actions, node type counts, global transforms, visibility
and small typed summaries for known engine-owned node types such as Timer,
Camera2D/3D, AnimationPlayer, AudioStreamPlayer and CharacterBody2D/3D. This
is local sensitive runtime evidence and is not uploaded by the bridge.

This tool is read-only. It does not start the game, call arbitrary scripts,
inspect script/exported properties, inspect debugger internals, mutate scenes,
or save resources. Missing or stale state is reported as a normal diagnostic
result.

### godot.run_test_scene

Temporarily disabled. Every call fails closed with
`trusted_runtime_approval_unavailable`; project `.godot_bin` files are not
executable authority. Use the permission-gated Godot editor run workflow until
the MCP path can verify a live, default-off runtime authorization.

### godot.preview_scene_diff

Generates a unified diff preview for allowed project-relative text scene, script,
or resource files. It never writes files.

The tool must reject absolute paths, `..` traversal, generated/imported files,
binary files, and paths outside the configured project root.

## Separate Approval Scope

Automatic broad mutation directly from diagnostics, real export execution,
signing and publishing are not part of the current local-dev plan. They require
separate user approval, additional undo/validation gates and, for publishing or
signing, explicit release credentials/process review.
