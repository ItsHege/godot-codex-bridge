# Godot Codex Bridge - MCP Server

The local Model Context Protocol (MCP) server exposing 75+ typed Godot Editor inspection, diagnostics, and guarded mutation tools to AI coding agents (OpenAI Codex, Claude Desktop, Cursor, Antigravity).

## Current Status

Implemented in TypeScript on Node.js using the official `@modelcontextprotocol/sdk` (`v1.29+`), passing 127 automated unit and contract tests in `test/`.

## Runtime Requirements

- Node.js `>=20.11`
- Godot Engine `4.x` (4.3+ or 4.7)
- MCP stdio client

## Executable & Project Configuration

The server resolves the Godot executable automatically using the following priority:

1. CLI flag: `--godot-executable <path>`
2. Environment variable: `GODOT_BIN`
3. Project-local config file: `.godot_bin` in the target project root
4. System `PATH` search (`godot`, `godot4`, `Godot_console.exe`, `Godot.exe`)
5. Compatible environment variables: `GODOT_EXECUTABLE`, `GODOT_PATH`
6. Fallback defaults

### Environment Variables & CLI Flags

| CLI Flag | Environment Variable | Default / Description |
| :--- | :--- | :--- |
| `--project-root` | `GODOT_CODEX_BRIDGE_PROJECT_ROOT` | Target Godot project root (containing `project.godot`). |
| `--bridge-dir` | `GODOT_CODEX_BRIDGE_DIR` | `<projectRoot>/.godot/godot_codex_bridge` |
| `--godot-executable` | `GODOT_BIN` | Path to Godot 4 executable. |
| `--host-rpc-url` | `GODOT_CODEX_BRIDGE_HOST_RPC_URL` | Auto-discovered from `addons/godot_codex_bridge/host_config.json`. |
| `--addon-timeout-ms` | `GODOT_CODEX_BRIDGE_ADDON_TIMEOUT_MS` | Default: `5000` (bounded: 250-30000ms). |
| `--run-timeout-ms` | `GODOT_CODEX_BRIDGE_RUN_TIMEOUT_MS` | Default: `15000` (bounded: 1000-60000ms). |

---

## Tool Catalog Overview

The server exposes 75+ tools organized into 12 functional categories:

1. **`orientation`**: Project overview, script map, scene graphs, AGENTS context, live editor state, bridge status.
2. **`project_files`**: Bounded project file search, file reading, `.tscn` tree parsing, GDScript inventory.
3. **`annotations`**: Read and resolve local "Eye Attach" visual annotation markers.
4. **`editor_navigation`**: Open scenes/scripts, select nodes, inspect node/inspector properties, focus tabs.
5. **`diagnostics`**: 3D scene sanity checks, spatial bounds, placement checks, screenshots, multi-view captures.
6. **`materials_rendering`**: Inspect and edit materials, shaders, environment properties, and particle systems.
7. **`animation_signals`**: List and inspect animation players, signal connections, preview clips.
8. **`scene_mutation`**: UndoRedo-backed node creation, transform edits, snapping to ground/grid, resource creation.
9. **`persistence_safety`**: Explicit scene save (`godot.save_scene`), undo snapshots, diff previews, approval-gated diff apply.
10. **`runtime`**: Run current/test scenes, inject playtest inputs, read runtime probe events and telemetry.
11. **`planning_batch`**: Scene prompt planning, editor action batching (`godot.editor_batch`), tool catalog discovery.
12. **`notes`**: Project-local bridge notes buffer.

Agents can call `godot.get_tool_catalog` (with `view: "compact"`) to explore tool workflows dynamically.

---

## Client Integration Examples

### OpenAI Codex CLI (`.codex/config.toml`)

```toml
[mcp_servers.godot]
command = "node"
args = [
  "C:/path/to/godot-codex-bridge/godot-codex-bridge/mcp_server/dist/src/index.js",
  "--project-root", "C:/path/to/your/godot_project"
]
```

### Claude Desktop (`claude_desktop_config.json`)

```json
{
  "mcpServers": {
    "godot": {
      "command": "node",
      "args": [
        "C:/path/to/godot-codex-bridge/godot-codex-bridge/mcp_server/dist/src/index.js",
        "--project-root",
        "C:/path/to/your/godot_project"
      ],
      "env": {
        "GODOT_BIN": "C:/Path/To/Godot_console.exe"
      }
    }
  }
}
```

### Cursor (`.cursor/mcp.json`)

```json
{
  "mcpServers": {
    "godot": {
      "command": "node",
      "args": [
        "${workspaceFolder}/godot-codex-bridge/mcp_server/dist/src/index.js",
        "--project-root",
        "${workspaceFolder}"
      ]
    }
  }
}
```

---

## Development & Testing

```bash
# Install dependencies
npm install

# Compile TypeScript
npm run build

# Run all 127 unit and contract tests
npm test

# Run bridge health diagnostic
npm run doctor
```
