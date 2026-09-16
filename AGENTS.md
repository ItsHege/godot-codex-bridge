# AGENTS.md

Guidance for AI coding agents (and humans) changing Godot Codex Bridge.

## Project Scope

Godot Codex Bridge lets MCP-capable coding agents inspect and carefully edit a
live Godot 4 editor session. It has three parts:

- a Godot editor addon that runs inside the editor;
- a TypeScript MCP server that exposes `godot.*` tools;
- a local Codex Host that relays in-editor chat and addon RPC.

It is local developer tooling. It is not a Godot fork, a cloud service, or a
general-purpose shell.

## Where Code Lives

| Area | Path |
|---|---|
| Godot addon (GDScript) | `godot-codex-bridge/addons/godot_codex_bridge/` |
| Addon service modules | `godot-codex-bridge/addons/godot_codex_bridge/core/` |
| MCP server (TypeScript) | `godot-codex-bridge/mcp_server/src/` and `test/` |
| Codex Host (TypeScript) | `godot-codex-bridge/codex_host/src/` and `test/` |
| Bridge JSON schemas and samples | `godot-codex-bridge/contracts/` |
| Addon GDScript tests | `godot-codex-bridge/tests/addon/` |
| Fixture Godot project | `godot-codex-bridge/examples/minimal_3d_project/` |
| Install, package, and validation scripts | `godot-codex-bridge/scripts/` |

Keep `plugin.gd` as wiring. Put new addon behavior in a `core/` module that
receives the shared `BridgeContext`, and register editor actions in
`_register_editor_control_handlers()`.

## Validate Changes

From the repository root:

```bash
npm ci
npm run build
npm test                      # MCP server + Codex Host
npm run validate:addon-core   # GDScript addon tests; needs Godot via GODOT_BIN or PATH
```

When you touch editor UI, screenshots, or live addon requests, also run the
matching visible-editor script from `godot-codex-bridge/`, for example
`npm run validate:visible-editor` or `npm run validate:multi-view-capture`.
Report what you ran and what passed. If a check cannot run (for example, no
Godot binary), say so explicitly.

## Safety Non-Negotiables

- Tools are read-only by default. Mutations go through Godot `UndoRedo` and
  the dock permission toggles.
- Never write outside the target Godot project root. Keep path traversal,
  absolute-path, and reparse-point checks intact.
- Scene saves stay explicit (`godot.save_scene`). File patches stay behind diff
  preview plus approval token (`godot.preview_scene_diff`,
  `godot.apply_approved_diff`).
- Evidence (snapshots, screenshots, logs) stays under
  `.godot/godot_codex_bridge/` in the local project. No uploads, telemetry, or
  new network destinations.
- Do not add arbitrary command execution or broad file-write tools.
- Do not commit machine-specific files such as
  `addons/godot_codex_bridge/host_config.json`.

## Contract Stability

- `godot.*` tool names, input fields, and structured error codes are a public
  interface. Do not rename or remove them without a deprecation note in
  `CHANGELOG.md`.
- The bridge protocol (`godot-codex-bridge/0.1`) and the schemas in
  `contracts/schemas/` must stay backward compatible. Update samples and tests
  together with any schema change.
- Every editor action the MCP server sends must be registered in the addon and
  listed in `core/editor_control_manifest.gd`. Add a test that proves it is
  callable.
- Update `docs/MCP_TOOLS.md` when tool behavior changes.
