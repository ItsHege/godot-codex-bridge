import fs from "node:fs/promises";
import path from "node:path";

import type { ToolEnvelope } from "./types.js";

export async function createDiagnosticSnapshot(
  bridgeDir: string,
  diagnostics: ToolEnvelope,
  label?: string,
): Promise<ToolEnvelope> {
  if (diagnostics.status !== "ok") {
    return diagnostics;
  }

  const snapshotId = snapshotIdFor(label);
  const snapshotRoot = path.join(bridgeDir, "artifacts", "diagnostic_snapshots", snapshotId);
  await fs.mkdir(snapshotRoot, { recursive: true });

  const diagnosticPath = path.join(snapshotRoot, "inspect_3d_scene.json");
  const manifestPath = path.join(snapshotRoot, "manifest.json");
  await fs.writeFile(diagnosticPath, `${JSON.stringify(diagnostics, null, 2)}\n`, "utf8");

  const manifest = {
    status: "ok" as const,
    snapshot_version: "godot-codex-bridge/diagnostic-snapshot-v1",
    snapshot_id: snapshotId,
    label: label ?? null,
    created_at: new Date().toISOString(),
    snapshot_root: snapshotRoot,
    diagnostic_path: diagnosticPath,
    contains_source_mutation: false,
    notes: [
      "Local diagnostic evidence only.",
      "Collision and navigation debug layers are derived from the latest context snapshot.",
    ],
  };
  await fs.writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");

  return {
    ...manifest,
    manifest_path: manifestPath,
  };
}

function snapshotIdFor(label: string | undefined): string {
  const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
  const safeLabel = (label ?? "inspect-3d")
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 48);
  return `${timestamp}_${safeLabel || "inspect-3d"}`;
}
