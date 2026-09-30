# Godot Codex Bridge

Godot Codex Bridge is a local Godot Editor addon plus MCP server for
agent-friendly Godot 3D development. It helps Codex agents inspect scenes,
selected nodes, editor evidence, resources, screenshots, and safe diff previews
without replacing the Godot editor.

## Status Labels

- `MVP working surface` means the feature belongs to the MVP contract and should
  be considered working only after the implementation and validation commands
  pass in this checkout.
- `Future work` means the feature is intentionally outside the MVP.
- This checkout contains the first MVP implementation. It is still local-dev
  software, not a release-ready plugin package.

## MVP Working Surface

- Read current scene metadata.
- Read scene tree with bounded node metadata and 3D hints.
- Read selected node context with bounded inspector/property summaries.
- Read bridge/editor output and command logs where available.
- Read resource/import status.
- Read gameplay context: input actions, autoloads, layer names and key project
  settings that affect controls, collisions, rendering and runtime behavior.
- Read bounded GDScript inventory with class names, inheritance, signals,
  exports, functions and TODO/FIXME markers without full source dumps.
- Capture viewport screenshots as local-only evidence.
- Capture bounded local screenshot timelines for animation, shader, camera and
  runtime feedback loops.
- Inspect live rendering effects: WorldEnvironment resources, Camera3D
  environment overrides, Environment post-processing flags and particle node
  visibility/emission hints without mutating scenes.
- Attach AI-safe visual markers from the Godot editor chat: the Eye Attach
  button captures the editor window or viewport, lets the user draw reference
  markers, and sends Codex local marker metadata with a guardrail that the
  marker graphics are annotations, not game art to recreate.
- Run current scene or a configured test scene through the known Godot console
  executable.
- Generate diff previews for allowed project-relative text files without
  applying changes.
- Inspect 3D scene sanity with read-only diagnostics for cameras, lights,
  meshes, collision shapes, navigation regions, selected nodes and node-count
  performance probes.
- Read best-effort Godot Performance monitor values for draw calls, primitives,
  3D physics objects, collision pairs and navigation counters when present in
  the live editor snapshot, including a bounded local timeline summary when
  samples are available.
- Get a grouped MCP tool catalog with safety levels and recommended workflows
  so agents can choose from the flat `godot.*` tool list more reliably.
- Estimate camera framing against captured mesh bounds and persist local
  diagnostic snapshots for collision/navmesh/debug review.
- Check PC/mobile export readiness from `project.godot` and
  `export_presets.cfg` without running exports.
- Create local undo snapshot artifacts for explicitly listed project-relative
  scene/script/resource files before risky edits.
- Visual-regression baseline creation and comparison currently fail closed
  pending live screenshot permission and trusted Bridge-owned provenance for
  both image inputs.
- See `docs/RESTRICTED_BUILD.md` for the current capability matrix, supported
  manual workflows, and conditions for re-enabling disabled operations.
- Convert scene prompts into bounded live-editor action plans without writing
  generated `.tscn` templates or applying default geometry.
- Preview text diffs. Direct MCP diff application and selected-node fixes
  currently fail closed pending trusted, one-use, exact-bound human approval
  receipts.

## Not In MVP

- Automatic broad write/fix actions without approval tokens and undo evidence.
- External Godot project mutation without explicit user permission.
- Marketplace publishing or production release.
- Telemetry upload or external screenshot sharing.
- Broad shell commands through MCP.

## Local Bridge Directory

The addon writes snapshots and local evidence into a generated project-local
bridge directory:

```text
.godot\godot_codex_bridge
```

Expected MVP contents are local snapshots, fallback request/response records,
command logs, screenshot artifacts, and Eye Attach annotation artifacts. This
directory can contain private scene names, asset paths, console output,
screenshots, and whole-editor captures, so treat it as local evidence.

Live addon-backed MCP requests currently use project-local request and response
files. The Host `/bridge/request` HTTP relay is disabled until the MCP process
has a separate authenticated transport. The MCP server may still discover the
local Host URL from `addons\godot_codex_bridge\host_config.json`; a refused
HTTP attempt falls back to file polling.

The discovered Host RPC target is local-only. The MCP server accepts localhost
host config targets such as `127.0.0.1`, `localhost` and `::1`; non-local hosts
are ignored and the file bridge remains the fallback path.

## Components

- `addons\godot_codex_bridge` - Godot Editor plugin.
- `mcp_server` - TypeScript/Node MCP server using the official MCP TypeScript
  SDK. Addon requests currently use the local bridge directory.
- `codex_host` - local WebSocket host for the Godot in-editor Codex chat. It
  owns Codex app-server compatibility lock, project attachment, streaming state,
  reconnect/cancel/backpressure and future approval orchestration.
- `docs` - architecture, tool, safety, install, and validation docs.
- `examples\minimal_3d_project` - small Godot fixture for smoke validation.
- `tests` - contract and smoke tests as they are added by implementation agents.

## Quick Development Flow

1. Confirm Godot:

```powershell
& $env:GODOT_BIN --version
```

2. Package and dry-run check the addon install from the single source of truth:

```powershell
cd godot-codex-bridge
npm run package:addon
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install_addon.ps1 -ProjectRoot "C:\path\to\godot\project"
```

Packaging refuses to replace an existing output by default. After reviewing
the exact output path, use
`npm run package:addon -- -ReplaceExistingPackage` for an intentional rebuild.

3. After reviewing the dry-run output, copy the addon into the target Godot
   project with `-Apply`, then enable "Godot Codex Bridge" in Project Settings
   -> Plugins. The plugin appears as a Codex Bridge main screen and a Codex
   Tools dock next to the Inspector with Bridge and Codex Chat tabs.

4. Start the MCP server from `mcp_server`:

```powershell
npm install
npm run build
npm test
npm run doctor
```

5. Point the MCP server at the same Godot project and bridge directory used by
   the addon. Keep the project root allowlist narrow.

6. Use `godot.bridge_status` first, then MCP tools for inspection and evidence
   gathering. Use `godot.preview_scene_diff` for review-first evidence. Direct
   MCP diff application remains disabled until trusted receipts are available;
   other write tools retain their documented permission and undo requirements.

   Before adding or approving any new command, file-write, save, export, import
   or external-project mutation path, use the review checklist in
   `docs\SAFETY.md`. Before handing a package to another project or tester, use
   `docs\RELEASE_CHECKLIST.md`.

7. Run the tester smoke before handing a build to someone else:

```powershell
npm run validate:tester-smoke
```

This runs host tests, MCP tests and the live-ish chat UX regression in sequence,
then writes a JSON report under the fixture bridge artifacts folder. It restores
the fixture `host_config.json` after the chat validation so the smoke does not
leave generated Git noise.

8. To stage exported Blender/AI assets for Codex review, use the dry-run helper
   first. It copies nothing until `-Apply` is present and stages files only
   under `assets\ai_imports\blender\<batch>`:

```powershell
npm run stage:blender-import -- -ProjectRoot "C:\path\to\godot\project" -AssetPath "C:\exports\tree.glb","C:\exports\tree_preview.png" -BatchName "forest_test"
npm run stage:blender-import -- -ProjectRoot "C:\path\to\godot\project" -AssetPath "C:\exports\tree.glb","C:\exports\tree_preview.png" -BatchName "forest_test" -Apply
```

Then Codex can call `godot.plan_blender_asset_import` with
`res://assets/ai_imports/blender/forest_test/manifest.json`.

9. For narrower validation, use the individual fixture paths:

```powershell
npm run validate:addon-core
npm run validate:visible-editor
npm run validate:restricted-fixture
npm run validate:blender-import-staging
npm run validate:blender-mcp-handoff
```

`validate:restricted-fixture` verifies supported startup, connection, capture,
and mock chat paths, but does not claim the broader historical UX scenarios.
The older `validate:chat-ux` and `validate:visible-chat-editor` scripts still
depend on removed production validation routes and are not restricted-build
gates; a legacy failure is not a PASS. Real-account and external-project checks
require separate authorization.

The broad local validator writes machine-readable JSON and supports scoped
modes:

```powershell
npm run validate:all-local -- -Fast -TargetProject "examples\minimal_3d_project" -ReportPath ".godot\godot_codex_bridge\artifacts\all_local_fast.json"
npm run validate:all-local -- -Visible
npm run validate:all-local -- -RealApp
```

`-Fast` runs only addon core, host tests and MCP tests, then records the
restricted fixture, visible editor, playtest and real-app checks as `not_run`
with skip reasons.
The broader `-Visible` and `-RealApp` legacy suites are not evidence for the
restricted build until their removed-route expectations are replaced.
Each JSON report includes `fixture_restore` evidence for the fixture
`host_config.json`.

10. For the in-editor Codex chat, build and check the local Host:

```powershell
npm run host:install
npm run host:build
npm run host:test
npm run host:doctor
```

`npm run host:schemas` regenerates the app-server schema lock; run it only
when deliberately moving the supported Codex CLI baseline, with the same
binary the Host launches.

On Windows with PowerShell 7, trust the Host installation once, then press
`Connect` beside the `Codex Chat` status:

```powershell
pwsh scripts\start_codex_host.ps1 -Trust
```

`-Trust` writes a per-user record under `%LOCALAPPDATA%\GodotCodexBridge`.
Connect launches only what that record names, pairs automatically and stops
its owned Host when Godot closes. A rebuilt Host has a new fingerprint, so
Connect asks to trust it again. See `contracts\ONE_CLICK_CONNECT_V1.md`.
`Advanced` keeps model, reasoning, trust, team, attachment and tool controls
out of the primary path.

The install helper generates `addons\godot_codex_bridge\host_config.json` for
loopback connection and compatibility metadata. That project-local file is not
executable authority: the addon never launches its `node_entry` or
`start_script`.

Without a trust record, or to inspect exactly what would run, start the Host
explicitly for an installed project outside the product tree:

```powershell
npm run start:codex-host -- -Inspect -ProjectRoot "<installed Godot project>" -Runtime app-server -CodexExecutable "<absolute codex.exe>"
npm run start:codex-host -- -Start -ProjectRoot "<installed Godot project>" -Runtime app-server -CodexExecutable "<absolute codex.exe>"
```

Review the displayed paths and fingerprint; type the exact requested `START`
line in the second command, then paste the one-launch pairing code it prints
into the dock after pressing Connect. Keep that terminal open and type `STOP`
to shut down its owned Host; closing Godot never stops a manually started
Host. `-Runtime mock` is for isolated fixture validation, not an
authenticated Codex turn. The addon connects to the configured loopback port;
its project-local config cannot launch or trust a Host. The bundled example
project is inside the product tree, so use the isolated fixture driver or a
separately installed project for trusted startup.

### Example project addon (single source of truth)

`examples\minimal_3d_project\addons\godot_codex_bridge` is a tracked **copy** of
the canonical `addons\godot_codex_bridge`, not a junction. Edit only the canonical
addon; `npm run validate:addon-core` reinstalls the copy before its checks. For
live iteration in the example project you can replace the copy with a junction:

```powershell
pwsh scripts\link-example-addon.ps1
```

See `docs\INSTALL_DEV.md` for the full validation command set.
See `docs\RELEASE_CHECKLIST.md` for `dev usable`, `MVP validated`, and
`release package ready` gates.
