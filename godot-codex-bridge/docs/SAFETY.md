# Safety Model

## Defaults

- Local-only by default.
- Read-first by default.
- No external upload of screenshots, scene data, console output, or project
  metadata by default.
- No broad shell through MCP.
- File writes are opt-in only through narrow approval-gated tools.

`godot.get_tool_catalog` is a read-only tool-selection helper. It only returns
static category, safety and workflow guidance for registered MCP tools plus
optional intent-matched workflow recommendations. It does not inspect project
files, contact the live addon, run Godot, mutate scenes or weaken any
approval/permission gate.

## Private Project Data

Godot projects can contain private art, unreleased code, paid assets, asset
store paths, internal scene names, and secrets inside scripts or config files.
Treat scene trees, selected node summaries, editor output, command logs, and
viewport screenshots as local evidence unless the user explicitly approves
sharing.

Eye Attach / AI Marker captures can include the whole Godot editor window:
FileSystem paths, Inspector values, error panels, scene contents and private
assets. They are created only by explicit user action, stored locally under the
bridge artifacts directory, and marked with `non_game_overlay: true` plus
`do_not_recreate_marker_graphics: true` so Codex treats drawn markers as user
annotations rather than requested game content.

Whole-editor capture prefers the Godot editor root viewport texture, which is
marked `target_window_verified=true` and `occlusion_sensitive=false`. If that
texture is unavailable or blank, the Bridge can fall back to
`DisplayServer.screen_get_image_rect(...)`. This fallback is
occlusion-sensitive because another foreground window can cover Godot and
appear in the captured rectangle; it is marked `target_window_verified=false`
and `occlusion_sensitive=true` and must not be treated as authoritative Godot
UI proof without a target-window-specific capture.

Programmatic chat visual-evidence capture obeys the same `allow_screenshots`
permission as other screenshot flows. The artifact manifest preserves
`capture_source`, `target_window_verified`, and `occlusion_sensitive` so a
consumer can reject unsafe evidence without inferring provenance from a file
name. The validation capture also rejects a visible exclusive editor modal
instead of treating content underneath that modal as unobstructed evidence.

Bridge artifacts live under:

```text
.godot\godot_codex_bridge
```

This directory should not be published as a release artifact and should not be
uploaded automatically.

## Path Boundaries

The MCP server must use an explicit Godot project root allowlist and the
project-local bridge dir. Diff preview must accept only safe project-relative
text paths and reject:

- absolute paths;
- `..` traversal;
- generated/imported files;
- binary files;
- paths outside the configured project root.

## Addon Install And Packaging

The canonical addon source is:

```text
addons\godot_codex_bridge
```

Target Godot projects should receive addon copies only through the package or
install helper. The install helper must stay dry-run by default and require
`-Apply` before copying into any project. Replacing an existing project-local
addon copy requires an additional explicit `-Replace` flag after review. The
dry run reports an exact SHA-256 added/changed/removed preview. Apply rejects
reparse-point targets, stages the replacement first, preserves the old addon in
the project-local bridge backup directory, and restores it if the swap fails.

## Scene And Test Runs

Scene execution is limited to the configured Godot console executable:

```text
GODOT_BIN (or godot / godot4 on PATH)
```

Run tools should return structured status, logs, exit code, and timeout evidence.
They must not become arbitrary shell execution.

## Diff Preview And Apply Gates

Default diff flow:

```text
proposal -> diff preview -> user review
```

`godot.preview_scene_diff` and default scene generation may produce a unified
diff, but must leave target files unchanged.

Approved write flow:

```text
proposal -> diff preview -> undo/snapshot plan -> explicit approval -> apply -> validation
```

`godot.apply_approved_diff` is intentionally narrow. It requires the explicit
approval token `APPROVE_GODOT_CODEX_BRIDGE_APPLY`, validates the project-relative
target path, optionally checks `expectedCurrentSha256` for drift, creates an undo
snapshot before replacing existing files, and never runs arbitrary shell
commands. New files require `allowCreate: true`.

## Arbitrary Command And File-Write Review Checklist

Use this checklist before adding, approving, documenting or releasing any new
tool that can execute commands, write files, save scenes, mutate live editor
state, import assets, run exports or change external projects.

Reject the change unless every applicable answer is yes:

- Scope is typed and allowlisted. The tool performs one named Godot Bridge
  action, not arbitrary shell, arbitrary GDScript, arbitrary Node.js,
  arbitrary PowerShell or generic "run this command" behavior.
- Project boundary is explicit. Inputs resolve inside the configured Godot
  project root or project-local bridge directory, reject absolute paths and
  reject `..` traversal.
- Generated/import/cache boundaries are explicit. `.godot`, `.import`, build
  output, release packages and addon internals are excluded unless the tool is
  specifically a bridge-artifact read/write tool.
- Read-only default is preserved. Inspection tools do not save scenes, change
  project files, edit ProjectSettings, reimport assets, run exports or start
  external services.
- Mutation gate is explicit. Live scene edits require the relevant Godot dock
  permission and use UndoRedo; persistent file writes require diff/approval
  evidence; scene saves require the Save permission.
- Evidence exists before apply. Risky file writes have a diff preview, current
  hash or drift check where practical, undo snapshot or rollback artifact, and
  a clear validation step after apply.
- Approval cannot be forged accidentally. Approval tokens, nonces or diff hashes
  are checked by the host/tool that actually applies the write, not only by UI
  wording.
- Output is bounded. Large source, console, screenshot, runtime, performance or
  diagnostic payloads have item/byte/time limits and return truncation metadata.
- Private data stays local. No tool uploads screenshots, project paths, paid
  assets, logs, exports or `.godot\godot_codex_bridge` artifacts without a
  separate explicit user action.
- Failure is honest. Unsupported native editor scraping, native Output clearing,
  memory/VRAM metrics, runtime raycasts or 3D viewport camera control must return
  structured `*_unavailable` or `editor_api_unavailable`, not fake success.
- Cleanup is defined. External process, run-scene, playtest, import staging and
  host lifecycle tools define timeout, stop/cleanup, stale-state and retry
  behavior.
- Tests cover denial paths. Add at least one automated test for unsafe path,
  permission-off, stale/unavailable bridge and invalid input cases.

Reviewer sign-off should name the exact tool, its safety class from
`godot.get_tool_catalog`, the files it may read/write, the permission or
approval gate it uses, and the validation command that proved the gate.

## Undo Snapshots

`godot.create_undo_snapshot` may create local evidence under the bridge artifact
directory for explicitly listed files. It must not snapshot broad project trees,
generated import/cache directories, absolute paths, path traversal targets or
large binary assets. It does not restore files automatically.

Use this before risky write flows, but keep the write/apply gate separate:

```text
create undo snapshot -> diff preview -> explicit approval -> apply -> validate
```

Undo snapshots are evidence and rollback material. They are not a silent restore
mechanism.

## Selected Node Fixes

`godot.fix_selected_node` is not a broad mutator. It sends a request to the live
Godot addon and can only apply one allowlisted fix to the first selected node.
The Godot dock permission `Fix selected node` must be enabled, and the request
must include approval token `APPROVE_GODOT_CODEX_BRIDGE_FIX_SELECTED_NODE`.

The addon uses Godot editor undo/redo actions for the property change and does
not save scenes automatically. Supported fixes are intentionally small:

- unhide node;
- make selected camera current;
- enable collision shape;
- enable navigation region;
- set light energy to a safe default;
- enable light shadows.

## Live Editor Control

`editor_control` is a typed Godot editor API layer, not a generic UI robot and
not shell access. Navigation and inspection actions may be enabled by default:
open/focus scenes, switch editor screens, select files, select nodes and inspect
bounded properties. Read-only material/shader diagnostics can inspect live
material slots and ShaderMaterial uniforms, but they do not compile shaders,
open native shader popups, clear native shader errors or mutate shader/material
parameters.

Scene edit actions require the Godot dock permission `Scene edits via UndoRedo`.
They include `Node2D`/`Node3D` transform edits, safe scalar/vector/color
property edits, node create/delete/rename/reparent/duplicate, project-local
scene instancing, signal connect/disconnect and live Resource assignment/editing
for Resource-valued node properties. They also include creating simple
AnimationPlayer clips with value tracks. The addon applies them through Godot
editor UndoRedo and does not save scenes automatically, so disk `.tscn` files
remain unchanged until a separate diff/save flow exists.

The live scene-tree mutation layer still has deliberate limits:

- deleting, duplicating or reparenting the edited scene root is rejected;
- reparenting a node under itself or one of its descendants is rejected;
- instancing is limited to project-local `.tscn`/`.scn` paths;
- imported/local asset placement is limited to project-local, allowlisted scene
  or mesh-like resource paths and creates only live editor nodes through
  UndoRedo. It does not import external files, edit import presets, reimport
  assets, delete assets or save scenes;
- signal tools connect existing signals to named target methods, but do not
  edit scripts or create missing callback methods;
- Resource tools can assign existing project-local resources, create local live
  subresources and edit simple properties on an assigned Resource, but they do
  not create `.tres`/`.res` files, import assets, save scenes or edit arbitrary
  nested resource graphs;
- animation preview has its own `Animation preview` permission because it changes
  live editor playback state. Animation clip creation remains under
  `Scene edits via UndoRedo`, supports only value tracks in V1 and does not edit
  imported animation files, method/audio/bezier tracks or `AnimationTree`
  graphs;
- arbitrary GDScript execution, ProjectSettings writes, scene save and export
  execution remain outside this layer.

`Trust Session` in Codex Chat may reduce Codex runtime approvals, but it must
not bypass Godot Bridge permissions. Bridge permissions remain the final local
gate for run, clear diagnostics and scene edit actions.

`godot.diagnostics_clear` clears only bridge-owned diagnostics after writing a
local evidence artifact. It must not pretend to clear native Godot Output or
Debugger panels unless a stable official API path is implemented.

`godot.editor_focus_panel` is navigation-only. It may focus known native Godot
tabs such as Output, Debugger, Audio, Animation or Shader Editor through the
editor control tree, but it must not delete, clear, acknowledge, or rewrite
diagnostics. Missing tabs must return a structured not-found error.

Automated validation uses a narrow `set_bridge_permission` request with token
`GCB_VALIDATE_PERMISSION_TOGGLE` to simulate pressing local permission
checkboxes in a controlled fixture editor. It exists for smoke tests such as
`npm run validate:live-mutation`; normal MCP tools do not expose it as a public
Godot capability.

## Scene Generation

`godot.generate_scene_from_prompt` is now a planning tool only. It returns a
bounded live-editor action plan and recommended Godot Bridge tools, but it does
not create `.tscn` text, return `proposed_content`, call
`godot.apply_approved_diff`, import assets, or write files. Scene edits should
use the live editor tools with Godot UndoRedo, then an explicit permission-gated
`godot.save_scene` after review. The planner also avoids inventing default
geometry from vague prompts; it only lists feature-specific actions when the
prompt names concrete environment cues.

The planner may include `suggested_tool_calls` with concrete live-editor MCP
tool names and arguments, but these are not executed automatically. Vague
prompts should stay inspect/navigation/evidence-only; explicit camera or
lighting prompts may suggest those node operations without creating unrelated
geometry.

## Visual Regression

`godot.create_visual_baseline` and `godot.compare_visual_regression` operate on
local PNG screenshots only. They store and compare baseline metadata under the
project-local bridge artifact directory. Current v1 comparison uses PNG
signature, dimensions, byte size, SHA-256 and pixel diff for matching-dimension
non-interlaced 8-bit PNGs. It does not upload screenshots.

`godot.capture_timeline_screenshots` is also local-only screenshot evidence. It
orchestrates a small sequence of normal addon viewport screenshot requests and
writes a manifest under the bridge artifact directory. V1 is bounded to 12
frames, does not stream image bytes through MCP, does not start external
profilers, and does not mutate scenes or resources.

## Addon Permissions UI

The Godot dock/main screen exposes local permissions. Screenshot capture and
Send Context are enabled by default for local use; run-current-scene and
fix-selected-node are disabled by default. The addon writes the current
permission state into bridge artifacts so `godot.bridge_status` and diagnostics
can explain denied requests.

## Performance Timeline

The addon may include a bounded local `performance.samples` timeline in
`context_snapshot.json`. It is sourced from Godot `Performance` monitors and is
read-only evidence for agent diagnostics. It must not start external profilers,
upload traces, run exports or mutate the project.

## Export Readiness

`godot.check_export_readiness` is read-only. It may inspect `project.godot` and
`export_presets.cfg`, but it must not run exports, sign mobile builds, upload
artifacts, publish releases or use real accounts.

## Diagnostic Snapshots

`godot.create_diagnostic_snapshot` may persist read-only diagnostic JSON under
the local bridge artifact directory. It is evidence for review only and must not
change scenes, resources, imports, project settings or external files.

## Gameplay And Script Context

`gameplay_context` and `script_inventory` are read-only and bounded. They may
include input action names, autoload paths, layer names, key project settings and
script signatures, but they must not dump full script bodies or mutate
`project.godot`, scenes or resources. Treat these fields as local project
metadata.

## Release And Publishing

Do not claim marketplace readiness, public release readiness, or external
project write safety without QA evidence, safety review, and explicit user
approval.
