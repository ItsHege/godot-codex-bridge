## Description

Briefly describe the purpose of this change and what problem it solves.

## Affected Components

- [ ] MCP Server (`godot-codex-bridge/mcp_server`)
- [ ] Codex Host (`godot-codex-bridge/codex_host`)
- [ ] Godot Addon Core (`godot-codex-bridge/addons/godot_codex_bridge`)
- [ ] In-Editor UI / Dock (`godot-codex-bridge/addons/godot_codex_bridge/ui`)
- [ ] Documentation / Examples / Workflows

## Safety & Boundary Checklist

- [ ] No existing MCP tool contracts or schemas were broken.
- [ ] Read-only vs mutating privileges are preserved (destructive operations require approval / UndoRedo).
- [ ] Path confinement remains enforced (no arbitrary file system traversal outside project root).
- [ ] Godot editor mutations register undo actions through `UndoRedo` where applicable.

## Verification & Testing

Explain how the changes were verified:

- [ ] `npm test` from repository root passed (MCP server + Codex host suites).
- [ ] `npm run build` completed without TypeScript errors.
- [ ] Headless Godot core validation run if addon code changed (`npm run validate:addon-core`).
- [ ] Manual verification steps performed (if applicable):
  - *e.g., tested with minimal 3D project in Godot 4.x*

## Related Issues

Closes #
