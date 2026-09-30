# Godot Codex Bridge local Codex plugin

This repo marketplace package teaches Codex how to preview and install the Bridge addon, enables it in `project.godot`, and configures the bundled MCP server for one Godot project. It does not connect to a game until a project root is chosen.

From the repository root, install the local marketplace and plugin:

```powershell
codex plugin marketplace add .
codex plugin add godot-codex-bridge@personal
```

Open a new Codex chat in the Godot project and ask: “Set up Godot Codex Bridge in this project.” Give Codex the checkout path if the Bridge source is elsewhere. Codex should inspect both previews before applying changes. The source checkout is required for the addon and optional in-editor Host. Node.js 22.14 or newer is required for the MCP runtime.

The project setup writes only to that project's `addons/godot_codex_bridge`, `project.godot`, and `.codex/config.toml`. The MCP config uses the source checkout's stable runtime path and pins the tool server to that project root. Codex loads project config only after the project is trusted. From the Godot project directory, verify `codex mcp list --json` shows the bundled runtime and exact project path before using Bridge tools; an existing user-level server may point elsewhere. The in-editor Codex Host is a separate process started through its fingerprint-confirming launcher. Reopen the Codex chat after project MCP configuration so its tools load.

The checked-in `runtime/mcp.mjs` is a bundled build of `godot-codex-bridge/mcp_server/src/index.ts`; it runs without installing the TypeScript server's dependencies in the game project. To rebuild it in the source checkout, use `scripts/build_runtime.ps1` after the existing development dependencies are present.
