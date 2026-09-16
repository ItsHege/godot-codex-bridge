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
1. **Path Boundary Confinement:** All file read and write operations must strictly stay confined within the configured Godot project root. Any path traversal (`../`), symlink bypass, or access to sensitive parent directories is treated as a critical security vulnerability.
2. **Approval-Gated Mutation:** Mutating tools that write to disk or apply patches (`godot.apply_approved_diff`, `godot.save_scene`) require explicit approval tokens and confirmation gates. Bypassing these gates is a vulnerability.
3. **Local-Only Scope:** Visual evidence, screenshots, and logs remain on the local machine within `.godot/godot_codex_bridge/`. No telemetry, unapproved external HTTP requests, or remote uploads are permitted.
4. **UndoRedo Guarantee:** Live editor operations must register native Godot `UndoRedo` actions so user actions cannot permanently corrupt editor state without a rollback path.

For full architectural details on our security and containment design, see [SAFETY.md](godot-codex-bridge/docs/SAFETY.md).
