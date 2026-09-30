# Restricted Build Capabilities

This table describes the current development build. “Working” identifies an
implemented route; the validation report must still identify whether its
evidence is live, mock, or static. A disabled route returns a clear error and
does not perform its former operation.

| Capability and entrypoint | Status | User-visible behavior and current workflow | Requirement for safe re-enablement |
|---|---|---|---|
| Addon startup and editor UI (`plugin.gd`) | Working | The Codex Bridge screen and dock load in Godot. The dock can show Host connection state before a Host exists. | No re-enablement needed. |
| Explicit trusted Host startup (`scripts/start_codex_host.ps1 -Inspect` / `-Start`) | Working in isolated mock fixture; app-server/account unverified | From a separate trusted installation, review the exact Node, Host/MCP entrypoints, optional Codex executable, ports, and fingerprint. `-Start` requires typing the fingerprint. Keep the terminal open; `STOP` stops only its owned Host. | Account-backed startup and Codex turns need separately authorized live evidence. Installation files must remain outside project control. |
| Operator-started Host connection (dock **Connect** / **Reconnect**) | Working with mock Host; account-backed chat unverified | Connect attaches to an already-running Host using valid loopback connection metadata. The addon may reconnect. Missing or malformed config now fails closed with an install instruction. | Account-backed Codex turns need a separately authorized live test. |
| Automatic Host process launch on project open or dock **Connect** | Intentionally disabled | Project `host_config.json` is connection metadata only. Opening a project or pressing Connect never starts Node or Codex. | Separate authority and lifecycle review; explicit trusted startup does not authorize project-driven auto-launch. |
| Scene and project inspection (`godot.bridge_status`, catalog, context and editor inspection tools) | Working | Read bounded current-scene, node, project and editor context after a live editor heartbeat. | No re-enablement needed; stale editor state must remain explicit. |
| Viewport screenshot (`godot.capture_viewport_screenshot`, dock **Screenshot**) | Working when `allow_screenshots` is enabled | Captures a local viewport artifact. With permission off, the request is denied. | No re-enablement needed; permission and path checks remain required at every capture sink. |
| Eye Attach (dock **Eye Attach**) | Working when marker and screenshot permissions are enabled | Captures editor imagery, lets the user draw reference annotations, and attaches the local artifact to a later prompt. It does not compare images automatically. | No re-enablement needed; capture provenance and user action remain required. |
| Automated visual baseline and comparison (`godot.create_visual_baseline`, `godot.compare_visual_regression`) | Intentionally disabled | Both tools return a disabled error. Screenshot and Eye Attach capture remain separate usable actions. | Verify live screenshot permission and Bridge-owned provenance for each input; require an explicit versioned baseline replacement decision. |
| In-editor chat UI and foreground turn (`send_codex_chat_message`) | Working with mock Host; real Codex turn unverified | The composer and transcript accept a message and render a mock Host response. | Separately authorized account-backed turn and version-specific protocol evidence. |
| Live editor edits (typed `editor_control` scene mutation) | Unverified in this visible checkpoint | The addon has permission-gated UndoRedo handlers, but the restricted fixture run does not exercise a live edit. | Visible fixture edit/undo proof and exact permission checks before a broader availability claim. |
| Diff preview and scene planning (`godot.preview_scene_diff`, `godot.generate_scene_from_prompt`) | Working | Returns review material or an action plan without applying files or saving scenes. | No re-enablement needed. |
| Direct file apply and selected-node quick fix (`godot.apply_approved_diff`, `godot.fix_selected_node`) | Intentionally disabled | Requests fail closed. Review the preview and use a human-controlled editor action instead. | Trusted short-lived, single-use human receipt bound to project, operation, target, reviewed state, proposed content, and cancellation state. |
| Bridge scene save (`godot.save_scene`, `godot.save_all_scenes`) | Intentionally disabled | Bridge tools do not persist the edited scene even if a standing save permission is enabled. | One scene first: trusted one-use approval bound to the exact scene and dirty state, complete rollback evidence, drift and replay rejection. Save-all remains disabled. |
| Native Godot **Save Scene** | Working outside Bridge | After reviewing live edits, the human saves using Godot's own editor UI. This is distinct from a Bridge save approval. | No Bridge re-enablement needed. |
| Editor current-scene run (`godot.run_current_scene`) | Unverified in this visible checkpoint | The addon has a dock permission gate and a normal editor run handler; this restricted fixture does not start gameplay. | Separate live runtime permission and stop/cleanup evidence before claiming visible runtime validation. |
| Direct test-scene and playtest tools (`godot.run_test_scene`, `godot.playtest_input`, `godot.run_playtest_scenario`) | Intentionally disabled | Requests fail closed pending live runtime authority. | A default-off live runtime permission bound to the active editor session and an implemented, reviewed addon action. |

`npm run validate:trusted-startup-fixture`
uses the existing isolated fixture driver, simulates the confirmation input,
and checks startup, connection, inspection, permission-gated screenshot and
mock chat. It is not human approval or authenticated Codex evidence. The
default driver retains the operator-started Host path.
`npm run validate:trusted-host-start` checks cancellation, changed identity,
project-sourced executable rejection, occupied ports, repeat requests, startup
failure and owned cleanup in a tiny local fixture. Both require PowerShell 7.
The typed fingerprint is an operator intent check, not human authentication:
native code running as the same OS user could script the CLI. Project config
and typed MCP tools cannot invoke startup, but do not run untrusted executable
project scripts under the local-user trust boundary. The addon pairs with the
running Host through fresh nonce and HMAC proofs in both directions before it
accepts editor or approval traffic. The one-launch pairing secret is pasted
into the dock and is not sent over the socket. The launch nonce separately
binds the launcher's health check. Same-user code with full machine access can
still inspect process memory or the trusted terminal.
The fingerprint covers the launcher, compiled Host and MCP entrypoints and
their local dependencies, both package manifests and lockfiles, the selected
native Node executable, and the selected native Codex executable in
`app-server` mode. It also binds the installation path, target project, runtime
and ports. It does not cover OS libraries, Godot project/addon files, Codex
account state, or an already-running foreign loopback service.
See
`docs/CREATE_ONLY_PATH_RACE.md` for the separate physical-confinement residual.
The older `validate:chat-ux` visible script still calls the removed
`validate_eye_attach_flow` production request and is **not a passing gate** for
this restricted build. Do not restore that route; use the isolated fixture
driver for the supported capture and chat paths.
