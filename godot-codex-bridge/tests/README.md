# Tests

Validation layers for Godot Codex Bridge:

- MCP server contract tests.
- Godot addon smoke tests.
- Minimal fixture scene checks.
- Screenshot artifact existence checks.
- Diff preview safety tests.
- Addon-side pure GDScript core tests.

## Minimal Fixture Smoke

The first runnable test asset is the Godot 4.7 fixture under
`godot-codex-bridge/examples/minimal_3d_project`.

Run from the workspace root:

```powershell
& $env:GODOT_BIN --version
& $env:GODOT_BIN --headless --path "godot-codex-bridge\examples\minimal_3d_project" --quit
& $env:GODOT_BIN --headless --path "godot-codex-bridge\examples\minimal_3d_project" --scene "res://scenes/test_3d.tscn" --quit-after 60
```

Pass criteria:

- Godot executable resolves and reports 4.7.1.
- Project loads/imports in headless mode without scene parse errors.
- `res://scenes/test_3d.tscn` exits with code 0 after printing the bounded
  auto-exit messages.

## MCP Server Tests

Run from the MCP package:

```powershell
cd godot-codex-bridge\mcp_server
npm run build
npm test
```

Pass criteria:

- TypeScript build succeeds.
- Node test suite passes.
- Diff preview tests prove target files are not modified.
- Bridge status and doctor tests cover wrong root, live heartbeat, stale editor
  and ready states.
- 3D diagnostics tests cover healthy scene summaries and safe suggestions for
  missing camera/light/collision issues.
- Camera framing/debug layer tests cover estimated mesh bounds, far-clip
  warnings, material surface mismatch and collision debug layer payloads.
- Diagnostic snapshot tests cover local artifact writing and error passthrough.
- Export readiness tests cover configured PC/mobile presets and missing preset
  findings.
- Undo snapshot tests cover explicit file snapshot creation and unsafe path
  rejection.
- Visual regression tests cover local PNG baseline creation, metadata compare,
  real 8-bit RGBA PNG pixel diff and missing baseline failures.
- Approved apply tests cover required approval token, drift checks, undo
  evidence and successful gated writes.
- Scene generator tests cover default diff-preview behavior and approval-gated
  creation.
- Gameplay/script context handler tests cover the new read-only snapshot
  sections for input/autoload/layer/project settings and bounded GDScript
  inventory.
- MCP tool tests cover the new visual regression, scene generation, approved
  apply and selected-node fix request handlers.

## Addon Core Tests

Run from the product root:

```powershell
cd godot-codex-bridge
npm run validate:addon-core
```

Pass criteria:

- The canonical addon is installed into the minimal fixture from the single
  source of truth.
- Godot runs every `tests\addon\test_*.gd` addon-side GDScript test harness
  headlessly.
- `core\chat_diff_model.gd` parses diff preview events, file-change payloads,
  per-file summaries, truncation and line kinds without loading the full editor
  plugin UI.
- `core\variant_codec.gd` serializes Godot Variants into bounded JSON payloads
  and coerces live editor property/transform values for UndoRedo-backed
  mutations.

## Real Addon Snapshot Contract

After enabling the addon in a Godot editor session and pressing Refresh Context,
validate the generated snapshot from the workspace root:

```powershell
.\godot-codex-bridge\tests\validate_context_snapshot.ps1 -ProjectRoot "C:\path\to\godot\project"
```

For the minimal fixture, use:

```powershell
.\godot-codex-bridge\tests\validate_context_snapshot.ps1 -ProjectRoot "godot-codex-bridge\examples\minimal_3d_project"
```

Pass criteria:

- `.godot\godot_codex_bridge\context_snapshot.json` exists.
- The snapshot validates against
  `godot-codex-bridge\contracts\schemas\context-snapshot.schema.json`.

## Manual Visible-Editor Validation

This is required before marking the build `MVP validated`:

1. Package the addon from the single source of truth:

```powershell
cd godot-codex-bridge
npm run package:addon
```

2. Dry-run install against the fixture or target project:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install_addon.ps1 -ProjectRoot "godot-codex-bridge\examples\minimal_3d_project"
```

3. Apply only after reviewing the dry-run output, then open Godot visibly,
   enable the plugin, and verify:
   - plugin appears in Project Settings -> Plugins;
   - Codex Bridge main screen tab and dock appear; no bottom panel is present;
   - Refresh Context writes a schema-valid snapshot;
   - Capture Screenshot writes a local PNG or structured failure;
   - Send Context writes a local send-context artifact;
   - the permissions toggles explain denied run/fix requests;
   - MCP request polling writes a request and receives a response.

For the fixture, the visible-editor request/screenshot path can be validated
automatically from the product root:

```powershell
npm run validate:visible-editor
```

Pass criteria:

- live heartbeat is detected;
- `refresh_context` returns `succeeded`;
- `capture_viewport_screenshot` returns `succeeded`;
- a PNG is created under `.godot\godot_codex_bridge\artifacts\screenshots`;
- `.godot\godot_codex_bridge\artifacts\visible_editor_validation.json` records
  the evidence.

Readiness labels:

- `dev usable`: automated checks and doctor pass.
- `MVP validated`: visible-editor checklist passes.
- `release package ready`: package zip/copy helper, docs and safety review pass.
