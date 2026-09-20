# Changelog

All notable changes to the Godot Codex Bridge project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Conversation UX
- Preserve conversation position while streaming, expose a `Jump to latest`
  control when the user scrolls back, and keep expanded diff/message state
  stable across rerenders.
- Improve readable transcript formatting, compact work/diff summaries, history
  interaction, composer sizing, Stop placement, and visible trust/build state.
- Correlate streamed events by thread, turn, item, and event identity so stale
  or duplicate updates do not replace current conversation content.

### Fixed
- Keep Codex turns running through retryable app-server errors and construct
  valid IPv6 loopback URLs.
- Use the same executable resolver for Host and doctor so diagnostics do not
  accidentally inspect a different installed Codex version.
- Deny approval scopes the current UI cannot represent (managed network,
  terminal-input and explicit environments). File approvals require matching
  item evidence and refresh the corresponding preview before review.
- Restrict Codex Host to loopback, reject browser-origin and foreign-Host
  requests, and enforce the WebSocket payload limit before message dispatch.
- Stop chat UX validation immediately when an install, addon or editor runner
  fails, instead of recording that child process as successful.
- Consume exact `serverRequest/resolved` identities, preserve approval state
  until the WebSocket response is confirmed, and reject stale, cancelled, or
  competing approval responses without clearing another active card.
- Remove the production validation-token permission route and enforce screenshot
  permission at capture, annotation, attachment, multi-view, and artifact sinks.

### Changed
- Require Node 22.14+; recommend Node 24 LTS. CI now covers Windows and Ubuntu
  on Node 22/24 and a checksum-pinned Godot 4.7.1 addon regression job.
- Pin GitHub Actions to verified release commits and restrict workflow token
  permissions. Hosted CI results are required before release.
- Lock generated app-server schemas to the tested Codex CLI 0.151.0 runtime and
  populate reasoning options from bounded runtime-reported capabilities.

### Temporary mitigations
- `godot.apply_approved_diff` fails closed until the Host/UI can issue a
  short-lived, single-use receipt bound to the exact project, operation, target,
  reviewed state, and proposed content.
- `godot.create_visual_baseline` fails closed until live screenshot permission
  and project-confined source provenance can be verified.

### Remaining limitations
- Runtime execution authorization, physical symlink/reparse confinement,
  project-controlled executable selection, complete rollback evidence,
  packaging containment, and PNG/request resource limits require follow-up.
- Legacy visible validators that called removed production validation routes
  require an isolated fixture driver; those routes are not restored for tests.

### Compatibility notes
- The generated app-server schema lock was regenerated from the tested Codex
  CLI 0.151.0 executable. Approval resolution and dynamic reasoning inventory
  have targeted regressions, but this is not a complete compatibility claim for
  every newer Codex version or a real-account integration result.

### Planned
- Bi-directional viewport raycasting for 3D cursor placement.
- Multi-project concurrent MCP session routing.

---

## [0.1.0] - 2026-09-15

### Added
- **MCP Server (`godot-codex-bridge-mcp-server`)**:
  - 100+ typed `godot.*` tools for editor introspection, diagnostics, screenshots, and UndoRedo-backed node edits. Some tools depend on addon actions that are not wired in this release; see Known Limitations in the README.
  - Read-first architecture with strict project-root path boundary guardrails.
  - Unified diff preview and token-gated patch application (`godot.preview_scene_diff`, `godot.apply_approved_diff`).
  - Viewport texture capture and 4-view (front, side, top, perspective) offscreen capture (`godot.capture_multi_view_screenshots`).
- **Godot Editor Addon (`godot_codex_bridge`)**:
  - Native Godot 4 Editor plugin (`plugin.gd`) registering dedicated editor dock panels.
  - All editor mutations registered with native Godot `UndoRedo` stack for complete undo/redo support.
  - Periodic background state snapshot generation (`context_snapshot.json`).
  - In-editor Codex Chat panel with responsive layout, conversation history, and diff review.
  - **"Eye Attach"**: Interactive visual region drawing over 3D viewport for grounded agent queries.
- **Codex Host Daemon (`godot-codex-bridge-codex-host`)**:
  - Local relay daemon bridging Godot editor WebSocket connections with OpenAI Codex `app-server`.
  - RPC routing between MCP server and editor addon with automatic reconnection.
- **Fixed**:
  - The live addon now handles the `capture_multi_view` editor action instead of returning `unsupported_editor_action`. File-polling requests wait for live editor frames, so captures come from the GPU SubViewport rather than the software fallback.
- **Developer Ergonomics & Community**:
  - Root npm workspace enabling single-command install (`npm install`), build (`npm run build`), and test (`npm test`).
  - GitHub Actions CI workflow covering Node 20.x and 22.x test execution on Ubuntu.
  - Standard community templates for bug reports, feature requests, and pull requests.
  - Security policy (`SECURITY.md`) and contribution guide (`CONTRIBUTING.md`).
