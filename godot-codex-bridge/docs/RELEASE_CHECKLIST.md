# Release Readiness Checklist

Godot Codex Bridge is local-dev software until these gates pass.

## Dev Usable

- `npm run package:addon` creates a fresh addon package from
  `addons\godot_codex_bridge`.
- `scripts\install_addon.ps1` dry-run diagnoses the target Godot project.
- `godot.bridge_status` returns project root, addon path, protocol version,
  addon version, heartbeat age, snapshot age, editor freshness and addon request
  transport diagnostics.
- `godot.inspect_3d_scene` returns read-only camera/light/mesh/collision/nav
  diagnostics with safe suggestions only.
- Performance probes report node count and, when the live editor snapshot
  contains them, Godot Performance monitor values for draw calls, primitives,
  physics objects, collision pairs, navigation counters and bounded timeline
  min/max/average summaries.
- `godot.performance_get_snapshot` returns the dedicated performance snapshot
  summary with rendering, physics_3d, navigation, timeline and honest
  unavailable memory/VRAM fields.
- `godot.check_export_readiness` reports project and preset gaps without running
  exports.
- `godot.create_undo_snapshot` copies only explicitly listed safe text files into
  local bridge artifacts.
- `godot.create_visual_baseline` and `godot.compare_visual_regression` work on
  local PNG metadata and supported pixel diffs without uploading screenshots.
- `godot.generate_scene_from_prompt` returns a live-editor action plan plus
  concrete `suggested_tool_calls`; it does not generate or apply `.tscn` file
  content, and vague prompts do not invent default scene geometry, cameras or
  lights.
- `godot.apply_approved_diff` requires approval token, path validation, optional
  SHA drift check and undo evidence.
- `godot.fix_selected_node` requires live editor permission, approval token and
  Godot undo/redo support.
- `npm test` passes in `mcp_server`.
- Godot headless fixture and test scene smoke commands pass.

## MVP Validated

- The addon is copied into the fixture or target project through the install
  helper, not by stale manual copy.
- Godot Project Settings -> Plugins shows "Godot Codex Bridge".
- Enabling the plugin shows the Codex Bridge main screen and left Codex Tools
  dock.
- Refresh Context writes a schema-valid context snapshot.
- Capture Screenshot succeeds in visible editor mode or returns a structured
  failure without Godot null-parameter errors.
- MCP addon requests prefer Host RPC when `host_config.json` is present and
  fall back to request/response files when Host RPC is unavailable.
- `npm run validate:visible-editor` passes against the fixture and writes
  `.godot\godot_codex_bridge\artifacts\visible_editor_validation.json`.

## Release Package Ready

- The release zip is built from the canonical addon source.
- `npm run package:addon` writes
  `dist\addon_package\godot-codex-bridge-addon-<version>.zip` and a
  `package_manifest.json` naming the canonical source addon path.
- Generated project-local `.godot` artifacts are not bundled.
- A dry-run `scripts\install_addon.ps1 -ProjectRoot "<target project>"` was
  reviewed before any `-Apply -Replace` target-project copy.
- Install/troubleshooting docs are current for Godot 4.7.1.
- Safety review confirms apply/write tools are approval-gated, local-only and
  narrow, with no external upload and no broad shell command.
- The arbitrary command/file-write review checklist in `docs\SAFETY.md` was
  applied to every new or changed mutation/write/process tool.
- Validation evidence is attached or referenced:
  - `npm --prefix mcp_server test`;
  - `npm run validate:addon-core`;
  - `npm run validate:tester-smoke` for QA handoff;
  - visible-editor or target-project validation JSON when UI/editor behavior
    changed.
- Export readiness findings are reviewed for intended PC/mobile targets.
- Generated `.godot\godot_codex_bridge` artifacts are excluded from public
  release packages.
- Marketplace publishing, real export execution, signing and upload remain
  blocked until separate user approval and release-specific QA are complete.

## P4 Gate

3D diagnostics v1, export readiness checks, explicit-file undo snapshots,
visual regression metadata/pixel checks, bounded performance timelines, bounded
scene generation, approved diff apply and narrow selected-node fixes are allowed
as local safety tools. Real export execution, signing, marketplace packaging
and automatic broad mutation still require additional validation gates.
