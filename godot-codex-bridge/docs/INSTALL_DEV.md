# Install And Development Usage

This guide is for local MVP development of Godot Codex Bridge.

## Requirements

- Godot 4.7.x editor and console executable. The practical validation baseline
  for this checkout is Godot 4.7.1:

```text
GODOT_BIN (or godot / godot4 on PATH)
```

- Node.js and npm for the MCP server.
- A Godot project that contains the addon at:

```text
addons\godot_codex_bridge
```

Compatibility note: treat Godot 4.7.1 as the release gate. Godot 4.7.x should be
compatible for normal addon use, but a release package is not considered ready
until the validation commands below pass on the exact Godot build used by the
target project.

## Local Privacy Model

The bridge is local-only by default. Generated context, command logs, and
screenshot artifacts live under the active Godot project:

```text
.godot\godot_codex_bridge
```

Do not upload this directory automatically. It can contain private asset names,
project paths, console output, and viewport screenshots.

## Addon Setup

Godot shows an editor plugin only when the active project contains:

```text
addons\godot_codex_bridge\plugin.cfg
addons\godot_codex_bridge\plugin.gd
```

Use the helper from the product root so the target project receives the current
single source of truth addon:

```powershell
cd godot-codex-bridge
npm run package:addon
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install_addon.ps1 -ProjectRoot "C:\path\to\godot\project"
```

`npm run package:addon` writes a clean package under:

```text
dist\addon_package\godot-codex-bridge-addon-<version>
dist\addon_package\godot-codex-bridge-addon-<version>.zip
```

The package includes `package_manifest.json` and only the installable
`addons\godot_codex_bridge` tree. Target projects should install from this
helper flow, not from an arbitrary older copied addon folder.

The install helper is dry-run by default. It diagnoses wrong root, missing addon,
not enabled, stale editor, heartbeat age and snapshot age. The JSON output also
contains a SHA-256 `change_preview` with the exact added, changed, and removed
addon-relative files. To copy into the target project after reviewing the
dry-run output:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install_addon.ps1 -ProjectRoot "C:\path\to\godot\project" -Apply
```

If an older addon copy already exists, review the target project first and use
`-Apply -Replace` only when replacing that project-local addon is intended.
Apply stages the complete replacement before touching the active addon, rejects
reparse-point targets, moves the previous addon into the project-local backup
directory, and atomically moves the staged addon into place. On failure, the
helper removes a partial replacement and restores the backup. Its JSON result
reports `backup_path` and `rollback_performed`.

Backups are stored under:

```text
.godot\godot_codex_bridge\install_backups
```

Then open the project in Godot 4.7.1 and enable "Godot Codex Bridge" from
Project Settings -> Plugins. The plugin exposes a Codex Bridge main screen,
and a left Codex Tools dock with internal Bridge and Codex Chat tabs; use
Refresh Context and Capture Screenshot from there.

## MCP Server Setup

The MVP MCP server is TypeScript/Node using the official MCP TypeScript SDK.

```powershell
cd godot-codex-bridge\mcp_server
npm install
npm run build
npm test
```

Configure the server to use the same Godot project root and
`.godot\godot_codex_bridge` directory as the addon. Keep the allowlist limited
to that project.

Bridge status and doctor checks:

```powershell
cd godot-codex-bridge\mcp_server
npm run doctor
```

The MCP server also exposes `godot.bridge_status`, which reports addon path,
project root, plugin enabled status when detectable, heartbeat age, snapshot
age, protocol version, addon version, and active/stale editor state.
It also reports addon request transport. A correctly installed addon with
`addons\godot_codex_bridge\host_config.json` should show
`preferred: host_websocket_rpc`; `file_polling` means the compatibility fallback
is in use because Host RPC is missing or unavailable.

Visible editor validation can be automated for the fixture from the product
root:

```powershell
cd godot-codex-bridge
npm run validate:visible-editor
```

This launches the Godot editor (`GODOT_BIN`, or `godot` on PATH) visibly, waits for a live
heartbeat, sends `refresh_context` and `capture_viewport_screenshot` bridge
requests, writes `.godot\godot_codex_bridge\artifacts\visible_editor_validation.json`
and closes the editor process it started.

Codex Host chat transport validation:

```powershell
cd godot-codex-bridge
npm run validate:visible-chat
```

This starts the local Codex Host with the mock runtime, attaches the fixture
project, validates foreground chat streaming, validates a read-only background
team review, and validates the nonce/diff-hash approval response path.

Visible editor Codex Chat validation:

```powershell
cd godot-codex-bridge
npm run validate:visible-chat-editor
npm run validate:visible-chat-editor:auto-start
npm run validate:visible-chat-editor:real
```

This starts a mock Codex Host, launches the fixture in a visible Godot editor,
waits for the addon to attach the project to the host, then drives the addon's
own chat request path for a foreground chat turn, background team review and
approval response. It writes
`.godot\godot_codex_bridge\artifacts\visible_chat_editor_validation.json`.
The `:auto-start` variant does not pre-start the host. It refreshes the fixture
addon install, verifies `addons\godot_codex_bridge\host_config.json`, presses
the addon's connect path, and expects the Godot addon to start the local Codex
Host itself.
The `:real` variant uses the installed `codex app-server` for one visible
editor foreground chat turn and requires the fixture `AGENTS.md` marker in the
response. It writes
`.godot\godot_codex_bridge\artifacts\visible_chat_editor_real_app_server_validation.json`.

Real app-server background validation:

```powershell
cd godot-codex-bridge
npm run validate:real-app-background
```

This uses the installed local `codex app-server` runtime and existing Codex
auth. It runs a bounded read-only `scene_agent` background review against the
fixture and writes
`.godot\godot_codex_bridge\artifacts\real_app_server_background_validation.json`.

## Codex Chat Troubleshooting

Normal use should not require a terminal. After installing the addon through
`scripts\install_addon.ps1 -Apply`, press `Connect` in the Godot `Codex Chat`
dock. The addon reads `addons\godot_codex_bridge\host_config.json`, starts the
local Codex Host in the background, waits briefly for it to become available
and then attaches the current project.

If the chat shows `Tools: missing`, press `Enable Tools`. This registers the
local `godot_codex_bridge` MCP server in Codex app-server config, reloads MCP
servers, and verifies that `godot.*` tools are visible. The host writes rollback
evidence under `.godot\godot_codex_bridge\codex_host\bridge_tools`. The
registration is project-bound through `GODOT_CODEX_BRIDGE_PROJECT_ROOT` and
`GODOT_CODEX_BRIDGE_DIR`.

If the Godot dock shows `Host: disconnected` after pressing `Connect`, first
check that `addons\godot_codex_bridge\host_config.json` exists in the active
Godot project. If it is missing, reinstall the addon through the SSOT helper
instead of copying an old addon folder by hand:

```powershell
cd godot-codex-bridge
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install_addon.ps1 -ProjectRoot "<your Godot project>" -Apply -Replace
```

For host-only developer debugging, you can still start the local host manually:

```powershell
cd godot-codex-bridge
npm run start:codex-host -- -Runtime app-server
```

The addon does not auto-retry forever when the host is missing; it performs one
connect-triggered auto-start attempt with a bounded retry window so the editor
log does not fill with repeated connect/disconnect messages.

Host lifecycle:

- If the Godot addon starts Codex Host from `host_config.json`, it owns that
  process for the current editor session.
- When Godot closes or the addon is disabled, the addon sends `host.shutdown`
  and then falls back to stopping only that owned host process if it is still
  alive.
- Codex Host shutdown closes its WebSocket clients, stops background tasks, and
  shuts down the Codex app-server child process.
- If you started Codex Host manually in a terminal for development, the addon
  only disconnects from it; it does not treat that manual process as owned.

If the chat input is not visible, refresh the addon through the SSOT helper:

```powershell
cd godot-codex-bridge
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install_addon.ps1 -ProjectRoot "<your Godot project>" -Apply -Replace
```

The current dock layout keeps the input row above the chat log and validates it
with `npm run validate:visible-chat-editor`.

If a target project still behaves like an older addon after install, verify all
three of these before debugging code:

1. `scripts\install_addon.ps1 -ProjectRoot "<project>"` dry-run reports the
   expected `addon_path`.
2. `scripts\install_addon.ps1 -ProjectRoot "<project>" -Apply -Replace` was run
   from the current checkout after `npm run package:addon`.
3. Godot was restarted or the plugin was disabled/enabled in Project Settings ->
   Plugins so the editor reloads the copied scripts.

## Validation Commands

Tester smoke:

```powershell
cd godot-codex-bridge
npm run validate:tester-smoke
```

This is the preferred handoff command for QA. It runs host tests, MCP tests and
the visible chat UX regression sequentially, writes
`examples\minimal_3d_project\.godot\godot_codex_bridge\artifacts\tester_smoke_validation.json`,
and restores the fixture `host_config.json` before exiting.

Godot executable:

```powershell
& $env:GODOT_BIN --version
```

Fixture import/smoke:

```powershell
& $env:GODOT_BIN --headless --path "godot-codex-bridge\examples\minimal_3d_project" --quit
```

Test scene run:

```powershell
& $env:GODOT_BIN --headless --path "godot-codex-bridge\examples\minimal_3d_project" --scene "res://scenes/test_3d.tscn" --quit-after 60
```

MCP server validation:

```powershell
cd godot-codex-bridge\mcp_server
npm run build
npm test
```

## Acceptance Checklist

- Addon loads without editor/plugin errors.
- `godot.bridge_status` reports the expected project root, addon path, protocol
  version, addon version, heartbeat age and snapshot age.
- Refresh Context writes a valid local context snapshot.
- MCP tools return scene, selection, resource, and output context from local
  bridge data.
- Screenshot capture returns local path and metadata, or a structured
  bridge-unavailable error.
- Scene/test run tools return bounded status, exit code, output summary, timeout
  state, and local log path.
- `godot.preview_scene_diff` returns a unified diff and leaves target files
  unchanged.
- `godot.apply_approved_diff` applies only with approval token, safe path
  validation, optional SHA drift check and undo evidence.
- `godot.generate_scene_from_prompt` returns a live-editor action plan with
  concrete `suggested_tool_calls`; it does not generate `.tscn` content, return
  a diff preview or apply files, and vague prompts do not invent default scene
  geometry.
- `godot.get_tool_catalog` accepts an optional `intent` string and returns
  ranked workflow matches plus `recommended_next_tools` before choosing from
  the flat `godot.*` list.
- `godot.editor_focus_panel` can focus known native Godot panels such as
  Output, Debugger, Audio, Animation and Shader Editor. It is navigation-only
  and does not clear native diagnostic panels.
- `godot.fix_selected_node` requires a live editor, dock permission, approval
  token and Godot undo/redo support.
- `background.start`, `background.status` and `background.cancel` run
  read-only Codex Host team reviews and persist local role/summary artifacts
  under `.godot\godot_codex_bridge\codex_host\background_tasks`.

## Release Package Handoff

Before handing a package to another project or tester:

1. Run `npm run package:addon`.
2. Confirm `dist\addon_package\godot-codex-bridge-addon-<version>.zip` exists.
3. Confirm `dist\addon_package\godot-codex-bridge-addon-<version>\package_manifest.json`
   lists the expected addon version and validation report count.
4. Run `scripts\install_addon.ps1 -ProjectRoot "<target project>"` without
   `-Apply` and review the dry-run JSON.
5. If the target is correct, run the same command with `-Apply -Replace`.
6. Run the Godot 4.7.x target project once and check Project Settings -> Plugins
   shows "Godot Codex Bridge".
7. Run `godot.bridge_status` or `npm --prefix mcp_server run doctor` and confirm
   project root, addon version, heartbeat age and snapshot age are for that
   target project.
8. Keep the generated validation JSON reports under
   `.godot\godot_codex_bridge\artifacts` as local evidence; do not include that
   `.godot` bridge directory in public release packages.

## Eye Attach / AI Marker

In the Codex Tools dock, use the small `Eye` button next to the chat input when
you want to point at something visually before the next message.

1. Click `Eye`.
2. Choose `Editor Window`, `3D Viewport`, or `2D Viewport`.
3. Draw a pin, rectangle, arrow, freehand mark, or label.
4. Click `Attach`.
5. Send the next chat message.

The addon writes:

```text
.godot\godot_codex_bridge\artifacts\annotations\<annotation_id>\raw.png
.godot\godot_codex_bridge\artifacts\annotations\<annotation_id>\annotated.png
.godot\godot_codex_bridge\artifacts\annotations\<annotation_id>\annotation.json
```

`Ctrl+F12` remains Godot's plain screenshot shortcut. `Eye` is different: it
adds marker metadata and a guardrail telling Codex that the drawn marker is a
user reference annotation, not game art to recreate.

## Visible Editor Validation

Headless Godot validates parsing and imports, but it does not prove the editor
dock or viewport screenshot path. Before marking the build `MVP validated`, run
this visible-editor checklist against the fixture or target project. For the
fixture, `npm run validate:visible-editor` covers the live heartbeat, fallback
request polling and screenshot capture evidence.

1. The plugin appears in Project Settings -> Plugins as "Godot Codex Bridge".
2. Enabling it shows the Codex Bridge main screen and the left Codex Tools
   dock.
3. Refresh Context writes `.godot\godot_codex_bridge\context_snapshot.json`.
4. `tests\validate_context_snapshot.ps1` passes for that project root.
5. Capture Screenshot creates a PNG under
   `.godot\godot_codex_bridge\artifacts\screenshots` or returns a structured
   failure without Godot null-parameter errors.
6. `godot.bridge_status` reports `addon_request_transport.preferred` as
   `host_websocket_rpc` when the local addon `host_config.json` can be read, or
   `file_polling` when the fallback path is the only configured route.
7. An MCP screenshot/request call succeeds through Host RPC when available; the
   fallback path writes a request under `requests\` and receives a matching
   response under `responses\`.
8. Eye Attach can capture the editor window, attach one marker, and clear the
   pending marker after the next chat send.

Readiness labels:

- `dev usable`: install helper, bridge status and automated tests pass.
- `MVP validated`: visible-editor checklist passes with evidence.
- `release package ready`: zip/copy package, troubleshooting docs and safety
  review are complete.
