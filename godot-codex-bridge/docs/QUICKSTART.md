# Quickstart Guide: Godot Codex Bridge

This guide takes you from a clean machine to your first agent-driven scene
inspection. Path A uses Codex chat inside the Godot editor (Windows). Path B
connects the MCP server to Codex CLI, Claude Desktop, Cursor or another MCP
client.

---

## 1. Prerequisites

- **Godot 4.7.1:** the tested baseline. Other 4.x versions need validation. On Windows, have both the editor and console executables.
- **Node.js 22.14+** (includes `npm`); Node 24 LTS recommended.
- **For in-editor chat (Path A):** Windows, PowerShell 7 (`pwsh`), and the OpenAI Codex CLI installed with `npm install -g @openai/codex` and signed in.
- **For MCP-only use (Path B):** an MCP client such as Codex CLI, Claude Desktop or Cursor.

---

## 2. Point the Bridge at Godot

Set `GODOT_BIN` so the Bridge can find Godot for scene runs and headless
validation. If it is unset, the Bridge searches `PATH` for `godot` or `godot4`.

### Windows (PowerShell)
```powershell
[System.Environment]::SetEnvironmentVariable('GODOT_BIN', 'C:\Path\To\Godot_console.exe', 'User')
$env:GODOT_BIN = 'C:\Path\To\Godot_console.exe'
```

### macOS / Linux (Bash / Zsh)
```bash
export GODOT_BIN="/usr/local/bin/godot"
echo 'export GODOT_BIN="/usr/local/bin/godot"' >> ~/.bashrc
```

---

## 3. Clone and Build

```bash
git clone https://github.com/ItsHege/godot-codex-bridge.git
cd godot-codex-bridge
npm install
npm run build   # MCP server and Codex Host
npm test        # MCP server and Codex Host test suites
```

All MCP server and Codex Host suites should pass.

---

## 4. Install the Addon

Your game project must be outside the Bridge checkout. From the repository
root, run the installer once as a dry run, review the file preview, then apply:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File godot-codex-bridge/scripts/install_addon.ps1 -ProjectRoot "path/to/your-game"
powershell -NoProfile -ExecutionPolicy Bypass -File godot-codex-bridge/scripts/install_addon.ps1 -ProjectRoot "path/to/your-game" -Apply
```

Add `-Replace` when updating an existing addon copy; the old copy is backed up
under `.godot/godot_codex_bridge/install_backups`. Without PowerShell, copy
`godot-codex-bridge/addons/godot_codex_bridge` into your project's `addons/`
folder.

Then open the project in Godot:

1. Go to **Project → Project Settings → Plugins**.
2. Enable **Godot Codex Bridge**.
3. The **Codex Tools** dock appears next to the Inspector, with **Bridge** and **Codex Chat** tabs.

To just try things out, you can instead open the bundled fixture,
`godot-codex-bridge/examples/minimal_3d_project/project.godot`, which already
contains the addon. It works with Path B; for Path A, copy it outside the
checkout first, because the trusted Host refuses projects inside its own
installation.

---

## 5A. Chat in the Editor (Windows)

Trust the local Codex Host once from a PowerShell 7 terminal in the repository
root:

```powershell
pwsh godot-codex-bridge/scripts/start_codex_host.ps1 -Trust
```

`-Trust` checks the built Host, finds Node on `PATH` and the npm-installed
Codex executable (pass `-CodexExecutable` to choose another), and records them
in `%LOCALAPPDATA%\GodotCodexBridge\trusted_host.json`. That record lives
outside every game project, so project files cannot change what the editor
launches.

In Godot, open the **Codex Chat** tab and press **Connect**. The addon starts
the Host in the background, pairs with it automatically and binds the Bridge
tools to the open project. Closing the editor stops that Host.

When Codex asks to run a command, change files or use a Bridge tool, a review
popup shows the request. Read-only Bridge tools offer **Allow this session**;
project changes, screenshots and runtime input always ask.

If you rebuild or update the Host, Connect shows the old and new fingerprints
and asks you to trust the new version before starting it.

---

## 5B. Connect Another MCP Client

Point the client at the built MCP server and your project root. For the Codex
CLI:

```bash
codex mcp add godot -- node "/path/to/godot-codex-bridge/godot-codex-bridge/mcp_server/dist/src/index.js" --project-root "/path/to/your-game"
```

Or in `.codex/config.toml`:

```toml
[mcp_servers.godot]
command = "node"
args = [
  "/path/to/godot-codex-bridge/godot-codex-bridge/mcp_server/dist/src/index.js",
  "--project-root", "/path/to/your-game"
]
```

The repository README has Claude Desktop and Cursor examples, and a local
Codex plugin that previews and writes this configuration for you.

---

## 6. Run Your First Inspection

With the scene open in Godot, ask the agent:

> *"Check bridge status and summarize the active 3D scene."*

It typically calls:

1. `godot.bridge_status`: confirms a fresh addon heartbeat and snapshot.
2. `godot.get_current_scene`: returns the root node (`Main3D` in the fixture), active camera and environment.
3. `godot.get_scene_tree`: returns a bounded hierarchy of cameras, lights and meshes.

---

## 7. Capture Visual Evidence

Next, ask:

> *"Capture a viewport screenshot and inspect the placement of 3D objects in the scene."*

`godot.capture_viewport_screenshot` saves a PNG under
`.godot/godot_codex_bridge/artifacts/` in your project and returns its local
path. Screenshots stay on your machine.

---

## 8. Keep the Addon Up to Date (Windows)

To update a project from the editor, install it once through the update script
with Godot closed:

```powershell
pwsh godot-codex-bridge/scripts/gc_work.ps1 -Action Publish
pwsh godot-codex-bridge/scripts/gc_work.ps1 -Action Update -ProjectRoot "path/to/your-game"
```

After you pull and rebuild a newer version, run `-Action Publish` again. In the
**Bridge** tab, **Check** then offers **Update**: Godot closes through its
normal close request, the build installs with a backup, and the project
reopens.

---

## 9. Troubleshooting

### `godot_executable_unavailable`
- **Cause:** Neither `GODOT_BIN` nor a `godot` / `godot4` binary on `PATH` was found.
- **Fix:** Set `GODOT_BIN` to the full path of your Godot console executable.

### `bridge_unavailable` / `stale_editor`
- **Cause:** Godot is not running the target project, or the plugin is disabled.
- **Fix:**
  1. Open the project in Godot.
  2. Confirm **Project Settings → Plugins → Godot Codex Bridge** is enabled.
  3. Press **Refresh** in the **Bridge** tab's Context section.

### Connect shows the one-time setup command
- **Cause:** No trusted Host record exists for your user.
- **Fix:** Run `pwsh godot-codex-bridge/scripts/start_codex_host.ps1 -Trust` from the repository root, then press **Connect** again.

### Connect reports a changed installation
- **Cause:** The Host was rebuilt or updated after you trusted it.
- **Fix:** Review the install path and fingerprints in the dialog and confirm to trust the new version.
