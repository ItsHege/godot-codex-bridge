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
- Create visual-regression baselines and compare current screenshots by
  dimensions, byte size, SHA-256 and supported PNG pixel diff.
- Convert scene prompts into bounded live-editor action plans without writing
  generated `.tscn` templates or applying default geometry.
- Apply approved text diffs and narrow selected-node fixes only behind explicit
  approval tokens and safety gates.

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

For live addon-backed MCP requests, the preferred path is the local Codex Host
RPC relay: the MCP server discovers `addons\godot_codex_bridge\host_config.json`,
calls the host `/bridge/request` endpoint, and the host forwards the request to
the connected Godot addon over WebSocket. The file bridge remains a
compatibility/debug fallback when the host RPC path is not configured or not
available.

The discovered Host RPC target is local-only. The MCP server accepts localhost
host config targets such as `127.0.0.1`, `localhost` and `::1`; non-local hosts
are ignored and the file bridge remains the fallback path.

## Components

- `addons\godot_codex_bridge` - Godot Editor plugin.
- `mcp_server` - TypeScript/Node MCP server using the official MCP TypeScript
  SDK. It prefers Codex Host RPC for live addon requests and falls back to the
  local bridge directory when needed.
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

3. After reviewing the dry-run output, copy the addon into the target Godot
   project with `-Apply`, then enable "Godot Codex Bridge" in Project Settings
   -> Plugins. The plugin appears as a Codex Bridge main screen and a left
   Codex Tools dock with internal Bridge and Codex Chat tabs.

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
   gathering. Use `godot.preview_scene_diff` for review-first edits; use
   approved write tools only with their explicit approval tokens and undo
   evidence.

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
npm run validate:chat-ux
npm run validate:p9-2-visible-smoke
npm run validate:external-project-install-smoke
npm run validate:visible-editor
npm run validate:visible-chat-editor
npm run validate:visible-chat-editor:auto-start
npm run validate:visible-chat-editor:real
npm run validate:external-project-install-smoke
npm run validate:blender-import-staging
npm run validate:blender-mcp-handoff
```

The broad local validator writes machine-readable JSON and supports scoped
modes:

```powershell
npm run validate:all-local -- -Fast -TargetProject "examples\minimal_3d_project" -ReportPath ".godot\godot_codex_bridge\artifacts\all_local_fast.json"
npm run validate:all-local -- -Visible
npm run validate:all-local -- -RealApp
```

`-Fast` runs only addon core, host tests and MCP tests, then records chat UX,
visible editor, playtest and real-app checks as `not_run` with skip reasons.
Each JSON report includes `fixture_restore` evidence for the fixture
`host_config.json`.

10. For the in-editor Codex chat prototype, install and validate the local host:

```powershell
npm run host:install
npm run host:schemas
npm run host:test
npm run host:doctor
```

The normal Godot user flow is one click: install the addon through the helper,
open the project, then use the always-visible contextual `Connect`, `Refresh`,
or `Reconnect` action beside the `Codex Chat` status. `Advanced` keeps model,
reasoning, trust, team, attachment, and tool controls out of the primary path.
The helper generates `addons\godot_codex_bridge\host_config.json`, and the addon
uses that config to start the local Codex Host automatically in the background.
If the addon started that host, closing Godot or disabling the addon requests a
clean `host.shutdown` and stops only the owned host process if it is still
alive. Manually started developer hosts are left under your control.

For host-only development, you can still start the local host manually with:

```powershell
npm run start:codex-host -- -Runtime mock
```

Use `-Runtime mock` for deterministic local validation and `-Runtime app-server`
when testing against the installed Codex app-server runtime. The Godot addon
connects to `ws://127.0.0.1:49390`.

### Example project addon (single source of truth)

`examples\minimal_3d_project\addons\godot_codex_bridge` is a **directory junction**
to the canonical `addons\godot_codex_bridge`, so there is only one real copy of
the addon. Open the example project in Godot to validate changes with no manual
copy step. If the junction is ever missing (fresh checkout or archive extract),
recreate it with:

```powershell
pwsh scripts\link-example-addon.ps1
```

See `docs\INSTALL_DEV.md` for the full validation command set.
See `docs\RELEASE_CHECKLIST.md` for `dev usable`, `MVP validated`, and
`release package ready` gates.
