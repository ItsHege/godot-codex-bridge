# Install And Development Usage

This guide is for local development of Godot Codex Bridge.

## Requirements

- Godot 4.7.x editor and console executable. The practical validation baseline
  for this checkout is Godot 4.7.1:

```text
GODOT_BIN (or godot / godot4 on PATH)
```

- Node.js 22.14+ and npm for the MCP server and Codex Host; Node 24 LTS recommended.
- A Godot project that contains the addon at:

```text
addons\godot_codex_bridge
```

Compatibility note: treat Godot 4.7.1 as the release gate. Godot 4.7.x should be
compatible for normal addon use, but a release package is not considered ready
until the validation commands below pass on the exact Godot build used by the
target project.

## Codex Compatibility

The host uses Codex app-server. Its checked-in generated schema lock was
regenerated from Codex CLI 0.156.1. Targeted protocol and mock regressions cover
that runtime; authenticated runtime compatibility remains unvalidated.
This does not imply full compatibility with the latest Codex release. Run the
host doctor, compare version-specific schemas and validate approval/stream
behavior before upgrading the supported CLI baseline. Mock tests cannot prove
a real authenticated conversation. WebSocket app-server transport is experimental.

On Windows, the shell's npm `codex.ps1` and a desktop-provided `codex.exe` can
be different versions. Host and doctor share a resolver that prefers npm's
native binary for the default `codex` command, falling back to the normal shim.
Explicit overrides must be native executables; custom Windows .cmd/.bat wrappers
are rejected instead of being interpolated into shell commands.
Check the executable/version printed by host doctor; select
`GODOT_CODEX_HOST_CODEX_BIN` explicitly when validating a version, and generate
schemas with the same binary. Never treat shell `codex --version` alone as proof
of which runtime the Bridge launches.

The current addon UI cannot faithfully review managed network, terminal-input,
explicit-environment, command-policy, persistent write-root or permission-grant
requests, so the host denies those scopes with a visible explanation. Ordinary
local command/file approvals retain their one-use gates and active-turn binding.
Server-resolved approval invalidation uses exact request identity, and reasoning
options are populated from a bounded runtime-reported inventory with a legacy
fallback.

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

Packaging refuses to replace an existing package or zip by default. After
reviewing the exact output path, use
`npm run package:addon -- -ReplaceExistingPackage` for an intentional rebuild.

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
Project Settings -> Plugins. The plugin exposes a Codex Bridge main screen and
a Codex Tools dock next to the Inspector with Bridge and Codex Chat tabs. Use
Refresh and Screenshot in the Bridge tab's Context section.

The target project must be a separate tree from the Bridge checkout. The
trusted Host launcher refuses projects inside its own installation, so copy
the bundled fixture elsewhere before using in-editor chat with it.

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
It also reports addon request transport. The Host HTTP relay is temporarily
disabled while its MCP authentication contract is designed; addon-backed MCP
requests currently use project-local file polling. A discovered Host URL in
`host_config.json` does not mean HTTP forwarding is enabled.

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

Restricted visible editor and mock chat validation:

```powershell
cd godot-codex-bridge
npm run validate:restricted-fixture
```

This command runs the out-of-band restricted fixture driver. It creates a fresh
temporary project and first observes the editor with no Host, then starts a
mock Host from the trusted product checkout and checks connection, inspection,
screenshot permission, fixture-only Eye Attach capture, and a mock chat turn.
The driver records JSON evidence in that temporary project and stops its own
processes. It does not use the removed production validation routes or an
account. The older visible chat validator and its real-account variant are not
supported restricted-build gates; previous broad UX and approval scenarios
are not implied by this fixture pass. See `RESTRICTED_BUILD.md`.

Real app-server background validation:

```powershell
cd godot-codex-bridge
npm run validate:real-app-background
```

This uses the installed local `codex app-server` runtime and existing Codex
auth. It runs a bounded read-only `scene_agent` background review against the
fixture and writes
`.godot\godot_codex_bridge\artifacts\real_app_server_background_validation.json`.

## In-Editor Codex Chat

One-click Connect is Windows-only and uses PowerShell 7. Build the Host first
(`npm install` and `npm run build` from the repository root), then trust the
installation once from the repository root:

```powershell
pwsh godot-codex-bridge\scripts\start_codex_host.ps1 -Trust
```

`-Trust` validates the built Host, resolves Node from PATH and the npm-installed
Codex executable (override with `-NodeExecutable` or `-CodexExecutable`),
computes the installation fingerprint and writes a per-user record:

```text
%LOCALAPPDATA%\GodotCodexBridge\trusted_host.json
```

Running `-Trust` is your approval. The record lives outside every Godot
project; project content, including `host_config.json`, never chooses what the
addon launches.

Press `Connect` in the Godot `Codex Chat` tab. If a paired Host is already
reachable, the addon reuses it. Otherwise it generates a one-launch pairing
secret, starts the trusted PowerShell launcher hidden for this project, waits
for the launch status under `%LOCALAPPDATA%\GodotCodexBridge\launch`, and pairs
automatically. The launcher starts nothing if its script, executables or
fingerprint differ from the record. Closing the editor stops this owned Host,
except while an addon update is pending.

After a rebuild or update the fingerprint changes. Connect then shows the
install path with the old and new fingerprints and asks whether to trust the
new version. Without a trust record, Connect shows the one-time `-Trust`
command. The full contract is `contracts\ONE_CLICK_CONNECT_V1.md`.

Connect binds the Codex Bridge tools to the attached project at Host launch.
If the tools are unavailable, press `Enable Tools` (or `Refresh Tools`). The
host writes rollback evidence under
`.godot\godot_codex_bridge\codex_host\bridge_tools`. The registration is
project-bound through `GODOT_CODEX_BRIDGE_PROJECT_ROOT` and
`GODOT_CODEX_BRIDGE_DIR`.

### Manual Host start

The interactive launcher still works without a trust record, for example to
inspect exactly what would run:

```powershell
cd godot-codex-bridge
npm run start:codex-host -- -Inspect -ProjectRoot "<your Godot project>" -Runtime app-server -CodexExecutable "<absolute codex.exe>"
npm run start:codex-host -- -Start -ProjectRoot "<your Godot project>" -Runtime app-server -CodexExecutable "<absolute codex.exe>"
```

Review the displayed installation, executable and entrypoint paths, runtime,
ports and fingerprint. In the second command type the exact requested `START`
line. A changed build or configuration needs a fresh decision. `STOP` stops
only the Host owned by that launcher; an occupied port is never killed. The
prompt verifies operator intent in a terminal, not the OS identity of a
human; native same-user code could script it. After `HOST_READY`, copy the
64-character pairing secret shown in the launcher terminal, press `Connect` in
the dock and paste it into the pairing dialog. The addon holds the secret only
for this connection and asks again after disconnect. The addon does not own or
stop a manually started Host; it only disconnects from it.

### Chat troubleshooting

If the Godot dock shows `Host: disconnected` after pressing `Connect`, first
check that `addons\godot_codex_bridge\host_config.json` exists in the active
Godot project. It holds loopback connection metadata. If it is missing or
invalid, Connect reports an install/configuration error instead of using a
default port. Reinstall the addon through the SSOT helper instead of copying an
old addon folder by hand. The same fix applies when the chat input is not
visible:

```powershell
cd godot-codex-bridge
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install_addon.ps1 -ProjectRoot "<your Godot project>" -Apply -Replace
```

If a target project still behaves like an older addon after install, verify all
three of these before debugging code:

1. `scripts\install_addon.ps1 -ProjectRoot "<project>"` dry-run reports the
   expected `addon_path`.
2. `scripts\install_addon.ps1 -ProjectRoot "<project>" -Apply -Replace` was run
   from the current checkout after `npm run package:addon`.
3. Godot was restarted or the plugin was disabled/enabled in Project Settings ->
   Plugins so the editor reloads the copied scripts.

## Keeping Projects Up to Date

The Bridge tab can check for and install a newer reviewed addon build
(Windows, PowerShell 7). Builds always come from the trusted Host's own
checkout, never from the project or the request. To make a project updatable,
install it once through the update script while Godot is closed:

```powershell
pwsh godot-codex-bridge\scripts\gc_work.ps1 -Action Publish
pwsh godot-codex-bridge\scripts\gc_work.ps1 -Action Update -ProjectRoot "<your Godot project>"
```

`Publish` requires a committed, unmodified addon tree and records its build id
in `godot-codex-bridge\GC_WORK_CHANNEL.json`. `Update` installs that build with
a backup, refuses to remove files or run while the editor is active, and adds
the project to `%LOCALAPPDATA%\GodotCodexBridge\gc-work-projects.json`.
`-Action Status` reports the state of registered projects.

After pulling and rebuilding a newer version, run `-Action Publish` again. In
the Bridge tab, `Check` asks the paired Host and `Update` appears when a newer
build is available. Confirming closes Godot through its normal close request
(Godot still asks about unsaved changes), installs after the editor exits,
writes `.godot\godot_codex_bridge\addon_update_result.json` and reopens the
project. The dock shows the result once on the next start. The full contract is
`contracts\ADDON_UPDATE_V1.md`.

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
- `godot.apply_approved_diff` fails closed with `trusted_approval_unavailable`
  until a Host/UI-issued, short-lived, single-use, fully bound approval receipt
  flow is implemented.
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
- `godot.fix_selected_node` is temporarily disabled pending a trusted,
  state-bound, single-use human approval receipt. Make the change directly in
  the Godot editor so its normal UndoRedo workflow applies.
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
2. Enabling it shows the Codex Bridge main screen and the Codex Tools dock
   next to the Inspector.
3. Refresh (Bridge tab, Context section) writes `.godot\godot_codex_bridge\context_snapshot.json`.
4. `tests\validate_context_snapshot.ps1` passes for that project root.
5. Screenshot creates a PNG under
   `.godot\godot_codex_bridge\artifacts\screenshots` or returns a structured
   failure without Godot null-parameter errors.
6. `godot.bridge_status` reports a discovered Host URL when the local addon
   `host_config.json` can be read. This is configuration metadata, not evidence
   that HTTP forwarding is enabled.
7. An MCP screenshot/request call uses file polling: it writes one request
   under `requests\` and receives the matching response under `responses\`.
   A configured Host HTTP attempt returns 503 with `bridge_rpc_unavailable`.
8. Eye Attach can capture the editor window, attach one marker, and clear the
   pending marker after the next chat send.

Readiness labels:

- `dev usable`: install helper, bridge status and automated tests pass.
- `MVP validated`: visible-editor checklist passes with evidence.
- `release package ready`: zip/copy package, troubleshooting docs and safety
  review are complete.
