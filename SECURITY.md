# Security Policy

## Reporting a Vulnerability

We take the security of Godot Codex Bridge seriously. Because this project connects AI agents to a live game engine editor with tool execution capabilities, maintaining strict privilege boundaries and preventing unintended system access is essential.

If you discover a potential security vulnerability, please **do not open a public issue**. Instead, please report it responsibly:

- **GitHub Private Security Advisory (Recommended):** If viewing this repository on GitHub, submit a report via the **Security** tab → **Advisories** → **Report a vulnerability**.
- **Maintainer Contact:** If private advisories are not enabled, contact the repository maintainers directly using the contact methods listed on their primary repository profile.

Please include:
- A clear description of the vulnerability.
- Steps or a proof-of-concept demonstrating the issue.
- The affected component (e.g. MCP Server, Codex Host, Godot Addon, Path Guard).
- Any potential impact on the host system or Godot project files.

We will review reports promptly and coordinate a fix prior to public disclosure.

---

## Security Model & Privilege Boundaries

Godot Codex Bridge operates with significant capabilities within a developer's local environment:
- **Editor Mutations:** Can create, transform, reparent, and delete nodes inside an active Godot Editor session.
- **Local Tool Execution:** Executes Node.js processes, WebSocket daemons, and local engine commands.
- **File System Access:** Reads scene files, scripts, logs, and writes project artifacts inside `.godot/godot_codex_bridge/`.

Because of these capabilities, the following areas are strictly **security-relevant**:
1. **Path Boundary Confinement:** All file read and write operations must stay inside the configured Godot project root. Path traversal (`../`), absolute paths, symbolic links, junctions and hard-linked files are rejected; any bypass is a critical vulnerability.
2. **Secret Files:** Project reading tools never return common secret-bearing files (`.env*`, private keys, keystores, credentials and similar). Exposing one to an agent is a vulnerability.
3. **Host Pairing and Trust:** The Codex Host binds to loopback only and pairs with the addon through a per-launch secret and mutual proofs; unpaired sockets cannot call privileged methods. One-click Connect launches only what the per-user trust record at `%LOCALAPPDATA%\GodotCodexBridge\trusted_host.json` names, and refuses a changed installation until the user trusts it again. Project files must never be able to choose what the editor launches.
4. **Approval-Gated Mutation:** Command, file-change and tool approvals are bound to the active Codex thread and turn. Only read-only Bridge tools may be allowed for a session; project changes, screenshots and runtime input always ask. Scene-save tools and direct diff application (`godot.save_scene`, `godot.apply_approved_diff`) fail closed until trusted, single-use approval receipts exist. Bypassing any of these gates is a vulnerability.
5. **Local-Only Scope:** Visual evidence, screenshots and logs remain on the local machine within `.godot/godot_codex_bridge/`. No telemetry, unapproved external HTTP requests or remote uploads are permitted.
6. **UndoRedo Guarantee:** Live editor operations must register native Godot `UndoRedo` actions so agent changes always have a rollback path.

For full architectural details on our security and containment design, see [SAFETY.md](godot-codex-bridge/docs/SAFETY.md).
