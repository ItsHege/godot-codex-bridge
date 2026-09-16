# Quickstart Guide: Godot Codex Bridge

This guide walks you through setting up Godot Codex Bridge from scratch on a clean machine and running your first agent-driven 3D inspection and verification flow.

---

## 1. Prerequisites

Before starting, ensure you have installed:

- **Godot Engine 4.x:** (Godot 4.3 stable or 4.7+). Ensure you have both standard and console binaries if on Windows.
- **Node.js 20.11+** (includes `npm`).
- **OpenAI Codex CLI** (or another MCP client such as Claude Desktop or Cursor).

---

## 2. Environment Configuration

Define the `GODOT_BIN` environment variable so the bridge can launch Godot for scene execution and headless validation:

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

*(Note: If `GODOT_BIN` is unset, the bridge will search your system `PATH` for `godot` or `godot4` automatically.)*

---

## 3. Clone and Build the Repository

```bash
git clone https://github.com/ItsHege/godot-codex-bridge.git
cd godot-codex-bridge

# Install root & workspace dependencies
npm install

# Compile TypeScript packages (MCP Server & Codex Host)
npm run build

# Run unit tests to verify your setup (127 MCP tests, 46 Host tests)
npm test
```

You should see all MCP and Codex Host test suites passing cleanly (173 tests total).

---

## 4. Open the Minimal 3D Example Project

1. Launch Godot Engine.
2. In the Godot Project Manager, click **Import**.
3. Browse to the repository fixture directory:
   ```text
   godot-codex-bridge/examples/minimal_3d_project/project.godot
   ```
4. Click **Import & Edit**.
5. Once opened in the editor, verify that the plugin is active:
   - Go to **Project → Project Settings → Plugins**.
   - Ensure **Godot Codex Bridge** is set to **Enable**.
   - You should see the **Codex Tools** dock tab appear next to the Inspector.

---

## 5. Configure OpenAI Codex (Primary Workflow)

Configure Codex to launch the MCP server pointing to your project directory.

In your project root (or global Codex config):

```toml
# .codex/config.toml
[mcp_servers.godot]
command = "node"
args = [
  "C:/path/to/godot-codex-bridge/godot-codex-bridge/mcp_server/dist/src/index.js",
  "--project-root", "C:/path/to/godot-codex-bridge/godot-codex-bridge/examples/minimal_3d_project"
]
```

Or register using the Codex CLI directly:

```bash
codex mcp add godot -- node "C:/path/to/godot-codex-bridge/godot-codex-bridge/mcp_server/dist/src/index.js" --project-root "C:/path/to/godot-codex-bridge/godot-codex-bridge/examples/minimal_3d_project"
```

---

## 6. Run Your First Inspection Command

With your Godot Editor open to the minimal 3D scene, ask Codex:

> *"Check bridge status and summarize the active 3D scene."*

Codex will execute:
1. `godot.bridge_status`
   - Confirms heartbeat is active (< 5 seconds old).
   - Confirms snapshot is fresh.
2. `godot.get_current_scene`
   - Returns root node name (`Main3D`), active camera, and environment settings.
3. `godot.get_scene_tree`
   - Returns bounded hierarchy of cameras, directional lights, and mesh instances.

---

## 7. Run a Visual Verification Command

Next, ask Codex:

> *"Capture a viewport screenshot and inspect the placement of 3D objects in the scene."*

Codex will execute:
1. `godot.capture_viewport_screenshot`
   - Instructs Godot to grab the active viewport texture and save it to `.godot/godot_codex_bridge/artifacts/`.
   - Returns the local PNG file path for visual inspection.

You will see the screenshot artifact appear in your editor's `.godot/godot_codex_bridge/artifacts/` folder.

---

## 8. Troubleshooting

### Problem: `godot_executable_unavailable`
- **Cause:** Neither `GODOT_BIN` nor a `godot` binary in system `PATH` was found.
- **Fix:** Set `$env:GODOT_BIN = "C:\full\path\to\Godot_console.exe"` (or `export GODOT_BIN=...` on Linux/macOS).

### Problem: `bridge_unavailable` / `stale_editor`
- **Cause:** The Godot editor is either not running the target project or the plugin is disabled.
- **Fix:**
  1. Open the project in Godot.
  2. Confirm **Project Settings → Plugins → Godot Codex Bridge** is enabled.
  3. Click **Refresh Context** in the **Codex Tools** dock in Godot.

### Problem: Tool calls take 5 seconds to respond
- **Cause:** The high-speed WebSocket RPC relay (`codex_host`) is not running, so the MCP server is falling back to file polling.
- **Fix:** Run the local host daemon:
  ```powershell
  cd godot-codex-bridge
  npm run start:codex-host
  ```
  Then click **Connect** in the **Codex Chat** dock inside Godot.
