# Architecture

## Goal

Godot Codex Bridge connects a Godot Editor addon to a local MCP server so coding
agents can inspect Godot project state with evidence and minimal risk.

The product is not a replacement for the Godot editor. It makes the editor more
agent-friendly by exposing bounded context, screenshots, run evidence, and diff
previews.

## MVP Data Flow

```text
Codex / MCP client
  -> MCP stdio server
  -> Codex Host /bridge/request when configured
  -> Godot addon WebSocket
  -> Godot Editor addon
  -> official Godot editor APIs
```

If the local Codex Host RPC path is not configured or unavailable, the MCP
server falls back to the project-local bridge dir:

```text
MCP stdio server
  -> .godot\godot_codex_bridge\requests
  -> Godot Editor addon polling fallback
  -> .godot\godot_codex_bridge\responses
```

The project-local bridge dir is:

```text
.godot\godot_codex_bridge
```

The bridge dir is generated evidence/cache. It is local to the Godot project and
should hold context snapshots, fallback request/response records, command logs,
and screenshot artifacts.

MCP-to-addon requests should use Codex Host RPC as the primary route whenever a
local `addons\godot_codex_bridge\host_config.json` is installed. The MCP server
derives `/bridge/request` from that file, accepts only localhost targets, and
falls back to file polling only when the host RPC route is missing or
unavailable.

Every addon-backed MCP request records transport evidence. Responses include
`transport_attempts` with per-route status and latency; file fallback responses
also include `fallback_reason`. This makes transport behavior auditable and
prevents Host RPC failures from silently looking like normal file polling.

## Trust Boundary

The MCP server must not become a broad shell or arbitrary file editor. It exposes
narrow Godot-aware tools and validates the configured Godot project root, bridge
dir, and project-relative file paths.

The Godot addon is the only component that talks directly to editor APIs such as
EditorPlugin and EditorInterface. Screenshot capture and editor context come from
the local editor session, not from an external service.

## MVP Context

The MVP context snapshot should contain:

- protocol version and generation timestamp;
- project metadata and current scene metadata;
- scene tree with bounded node fields;
- selected nodes with bounded inspector/property summaries;
- resource/import status;
- editor or bridge output where available;
- screenshot metadata for local artifacts.

3D scene summaries should include useful hints for Camera3D, Light3D,
MeshInstance3D, CollisionShape3D, and NavigationRegion3D without dumping large
binary resources or full inspector state.

On-demand live diagnostics extend the capped snapshot for specific domains such
as materials/shaders, animation players and rendering effects. These tools stay
bounded and read-only unless a separate UndoRedo-backed editor-control action is
explicitly requested.

## Commands And Evidence

Scene/test execution is bounded to the configured Godot executable:

```text
GODOT_BIN (or godot / godot4 on PATH)
```

The MCP server may run current/test scenes through this executable, capture exit
status and output summaries, and write local logs under the bridge dir. It must
not expose a generic shell.

## Write Gate

Default editing flow starts with diff preview:

```text
proposal -> diff preview -> user review
```

Approved write tools extend that flow with:

```text
undo/snapshot plan -> explicit approval token -> apply -> validation
```

`godot.apply_approved_diff` is narrow and approval-gated. Broad automatic scene
mutation remains out of scope.
