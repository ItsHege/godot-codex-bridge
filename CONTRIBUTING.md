# Contributing to Godot Codex Bridge

Thank you for your interest in contributing to Godot Codex Bridge! This guide covers our local development workflow, architecture expectations, and safety requirements.

---

## Quick Setup

Requirements:
- **Node.js**: `>=20.11` (Node 20 LTS or Node 22 recommended)
- **Godot Engine**: `4.3` or later (for addon validation)
- **Git**

From the repository root:

```bash
# 1. Install root and workspace dependencies
npm install

# 2. Compile TypeScript packages (MCP server & Codex host)
npm run build

# 3. Run all Node.js test suites
npm test
```

---

## Running Tests

From the repository root:
- `npm test` — runs both MCP server and Codex host test suites.
- `npm run test:mcp` — runs the 127+ MCP tool and server tests.
- `npm run test:host` — runs the 46+ Codex Host tests.
- `npm run validate:addon-core` — runs the 64 Godot addon GDScript test suites headlessly (requires Godot 4.3+ on `PATH` or configured via `GODOT_BIN`).

Package-local commands remain fully supported if working directly within a package directory:
- `cd godot-codex-bridge/mcp_server && npm test`
- `cd godot-codex-bridge/codex_host && npm test`

---

## Core Guidelines & Expectations

### 1. Do Not Break Tool Contracts
The MCP tool schemas (`godot.*`) form the public interface with AI coding agents (OpenAI Codex, Claude, Cursor).
- Never rename existing tools or remove parameters without formal deprecation.
- Return structured, typed results adhering to existing Zod schemas in `godot-codex-bridge/mcp_server/src/schemas/`.
- Ensure new tools provide rich context while keeping token usage bounded.

### 2. Maintain Safety & Permission Boundaries
- **Read-First Philosophy**: Keep tools read-only by default.
- **UndoRedo Guarantee**: Any mutating editor action must execute through Godot's native `UndoRedo` stack.
- **Path Guard**: Never bypass `isInsidePath` checks or access files outside the targeted Godot project root.
- **Local-Only**: Do not introduce network calls, cloud dependencies, external telemetry, or analytics.

### 3. Godot Engine Compatibility
- Use modern Godot 4.x idioms (GDScript 2.0 with static typing).
- Avoid engine-private or unstable APIs that break across minor Godot releases (4.3, 4.4, 4.7).

---

## Pull Request Checklist

Before opening a pull request:
1. [ ] Ran `npm run build` and resolved all TypeScript errors.
2. [ ] Ran `npm test` and ensured all tests pass.
3. [ ] If modifying the Godot addon, verified headlessly via `npm run validate:addon-core`.
4. [ ] Maintained existing tool contracts and Zod schema compatibility.
5. [ ] Preserved path boundary checks and safety guardrails.
6. [ ] Kept commit messages clear and descriptive.
