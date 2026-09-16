# Godot Codex Bridge Addon

Godot Editor addon for exposing local editor context to the Godot Codex Bridge
MCP server.

## Current Status

This checkout contains the first MVP addon implementation: a dock, local context
snapshot export, request polling, screenshot capture, and run-current-scene
request handling. It still needs in-editor validation before release packaging.

Target editor:

```text
Godot 4.7.1 (set GODOT_BIN to your Godot executable, or put godot on PATH)
```

## MVP Responsibilities

- Add a Godot Codex Bridge dock with bridge status and simple actions.
- Capture read-only current scene metadata.
- Capture bounded scene tree data.
- Capture selected node context and bounded inspector/property summaries.
- Capture resource/import status where supported.
- Capture viewport screenshots to local artifacts.
- Poll or respond to bridge requests from the project-local bridge dir.

The addon should use official Godot editor APIs such as EditorPlugin and
EditorInterface. It should avoid screen scraping and avoid full resource dumps.

## Local Bridge Directory

The addon writes only local bridge state under the active Godot project:

```text
.godot\godot_codex_bridge
```

Expected MVP artifact area:

```text
.godot\godot_codex_bridge\artifacts\screenshots
```

Screenshots can reveal private assets and should stay local unless the user
chooses to share them.

## Install For Local Development

Use the standard Godot addon shape inside a Godot project:

```text
addons\godot_codex_bridge\plugin.cfg
addons\godot_codex_bridge\plugin.gd
```

Godot will not show the plugin if this folder exists only in the bridge repo.
It must be present inside the active Godot project's `addons` folder.

Preferred local flow from the product root:

```powershell
npm run package:addon
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\install_addon.ps1 -ProjectRoot "C:\path\to\godot\project"
```

The install helper is dry-run by default. Use `-Apply` only after reviewing the
target project. With `-Apply`, the helper also writes
`addons\godot_codex_bridge\host_config.json`, which lets the `Codex Chat`
`Connect` button start the local Codex Host automatically. Then open the
project in Godot 4.7.1 and enable the plugin from Project Settings -> Plugins.

For workspace validation, use the minimal fixture project:

```powershell
& $env:GODOT_BIN --headless --path "godot-codex-bridge\examples\minimal_3d_project" --quit
```

## Out Of Scope For The Addon MVP

- Applying diffs.
- Mutating scenes or resources automatically.
- Uploading screenshots or project context.
- Publishing to the Godot Asset Library.
