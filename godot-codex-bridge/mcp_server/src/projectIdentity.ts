import crypto from "node:crypto";
import path from "node:path";

/**
 * Non-secret project identity for the unauthenticated /health response: a
 * hash lets the MCP server detect a Host attached to another project without
 * the Host revealing which project is open. Mirrored in
 * codex_host/src/projectIdentity.ts; both must produce identical hashes.
 */
export function projectIdentityHash(value: string, platform: NodeJS.Platform = process.platform): string {
  let normalized = path.resolve(value).replace(/\\/g, "/").replace(/\/+$/, "");
  if (platform === "win32") normalized = normalized.toLowerCase();
  return crypto.createHash("sha256").update(`godot-codex-bridge-project-v1:${normalized}`).digest("hex");
}
