# Changelog

All notable changes to the Godot Codex Bridge project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- Headless Godot runner container in CI for automated engine-level testing.
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
