# Blender MCP Handoff

This document defines the V1 handoff from a Blender-capable agent or Blender MCP
server into Godot Codex Bridge. The bridge does not control Blender in this
flow. Blender export is an upstream step; Godot Codex Bridge receives explicit
local files, stages them into a Godot project allowlist, and plans safe Godot
follow-up tools.

## Scope

V1 supports this path:

1. A Blender-side tool exports local asset files.
2. The agent reviews the exported file list and chooses a batch name.
3. The agent runs the staging helper in dry-run mode.
4. After review, the agent runs the staging helper with `-Apply`.
5. Codex calls `godot.plan_blender_asset_import` on the staged manifest.
6. Codex calls `godot.inspect_imported_assets` to read Godot import/resource
   status.
7. Codex may call `godot.place_asset_in_scene` for existing placeable assets,
   with normal scene-edit permission and UndoRedo behavior.
8. Codex captures viewport evidence after placement when visual proof is needed.

The flow does not run Blender, execute scripts, overwrite existing project files
without `-Replace`, place assets automatically, save scenes, edit import presets,
or mutate external Godot projects without explicit user approval.

## Handoff Input

A Blender MCP bridge should hand Codex a small reviewed export summary, not an
arbitrary command. The minimum useful shape is:

```json
{
  "source": "blender-mcp-export",
  "batch_name": "forest_test",
  "exported_assets": [
    {
      "source_path": "C:\\exports\\tree.glb",
      "role": "scene_asset",
      "name": "Tree"
    },
    {
      "source_path": "C:\\exports\\tree_preview.png",
      "role": "texture_sidecar",
      "name": "TreePreview"
    }
  ]
}
```

`exported_assets` are the files passed to `stage_blender_import.ps1`.
Supported placeable extensions are `.glb`, `.gltf`, `.obj`, `.fbx`, `.dae`,
`.blend`, `.tscn`, `.scn`, `.res` and `.tres`.

PNG files in this Blender handoff are treated as sidecars/export evidence, not
placeable Blender assets. The planner rejects them with
`unsupported_blender_asset_extension` so Codex does not accidentally place
preview or texture sidecars as scene objects. Direct PNG/Sprite2D placement is a
separate `godot.place_asset_in_scene` workflow outside this Blender import
manifest contract.

## Staging

Run the staging helper from the product root. The first run should omit
`-Apply`:

```powershell
npm run stage:blender-import -- -ProjectRoot "C:\path\to\godot\project" -AssetPath "C:\exports\tree.glb","C:\exports\tree_preview.png" -BatchName "forest_test"
```

Review the JSON response:

- `action` is `dry_run`.
- `apply_required_for_copy` is `true`.
- `post_copy_import_status.status` is `not_run`.
- `batch_root` is under `res://assets/ai_imports/blender/<batch>`.
- Each `asset_path` is project-local and under that batch.

After review, copy the explicit assets:

```powershell
npm run stage:blender-import -- -ProjectRoot "C:\path\to\godot\project" -AssetPath "C:\exports\tree.glb","C:\exports\tree_preview.png" -BatchName "forest_test" -Apply
```

If a target file or manifest already exists, the helper refuses to overwrite it.
Use `-Replace` only after reviewing that the listed files are intended to
replace the existing batch assets.

The applied response includes:

- `manifest_res_path`, such as
  `res://assets/ai_imports/blender/forest_test/manifest.json`.
- `post_copy_import_status.status = pending_godot_import_scan`.
- `post_copy_import_status.next_tool = godot.inspect_imported_assets`.

This is filesystem copy evidence only. It is not a claim that Godot imported or
validated the asset.

## Godot Planning

Call:

```text
godot.plan_blender_asset_import({
  "manifestPath": "res://assets/ai_imports/blender/forest_test/manifest.json"
})
```

The planner is read-only. It returns accepted and rejected manifest assets, then
suggests this workflow:

1. `godot.inspect_imported_assets` for the import root.
2. `godot.place_asset_in_scene` only for assets that already exist in the
   project.

The planner never calls Blender, copies external files, runs editor batches,
places assets, saves scenes or edits import settings.

## Safety Checklist

- Confirm the target `ProjectRoot` is the intended Godot project.
- Do not use this flow on an external project without explicit user approval.
- Run dry-run before `-Apply`.
- Review overwrite risk before `-Replace`.
- Keep all staged files under `assets/ai_imports/blender/<batch>`.
- Treat `.png` exports as sidecars in the Blender import manifest; do not use
  the Blender import manifest as a material texture-assignment or Sprite2D
  placement contract.
- Use `godot.inspect_imported_assets` before placement.
- Use `godot.place_asset_in_scene` only as a separate, permission-gated
  UndoRedo action.
- Capture screenshot evidence after placement when closing a visual import task.

## Local Smoke

Run:

```powershell
npm run validate:blender-mcp-handoff
```

The smoke creates a temporary Godot project, a fake Blender MCP export summary,
a fake `.glb` file and a fake `.png` file. It proves:

- the handoff summary contains GLB plus PNG export evidence;
- dry-run staging copies nothing;
- applied staging writes a compatible manifest for the GLB plus PNG sidecar;
- the MCP planner accepts the staged GLB and rejects the PNG sidecar with
  `unsupported_blender_asset_extension`;
- suggested placement covers only the GLB asset;
- suggested MCP follow-up tools do not include editor batch or scene saving.

Real Blender control remains optional and separately gated. A future Blender MCP
integration may generate the handoff summary, but it must still preserve the
same staging, allowlist, review and Godot-side permission boundaries.
