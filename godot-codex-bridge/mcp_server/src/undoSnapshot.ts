import fs from "node:fs/promises";
import path from "node:path";

import { isInsidePath } from "./config.js";
import type { JsonObject, ToolEnvelope } from "./types.js";

const ALLOWED_EXTENSIONS = new Set([".gd", ".tscn", ".tres", ".cfg", ".godot", ".json"]);
const MAX_SNAPSHOT_FILES = 50;
const MAX_FILE_BYTES = 2_000_000;

export interface UndoSnapshotOptions {
  paths: string[];
  label?: string;
}

export async function createUndoSnapshot(
  projectRoot: string,
  bridgeDir: string,
  options: UndoSnapshotOptions,
): Promise<ToolEnvelope> {
  const requestedPaths = Array.isArray(options.paths) ? options.paths : [];
  if (requestedPaths.length === 0) {
    return invalidRequest("paths_required", "Provide at least one project-relative file path to snapshot.");
  }
  if (requestedPaths.length > MAX_SNAPSHOT_FILES) {
    return invalidRequest("too_many_paths", `Undo snapshots are limited to ${MAX_SNAPSHOT_FILES} files.`);
  }

  const validated: Array<{ relativePath: string; absolutePath: string; byteSize: number }> = [];
  for (const requestedPath of requestedPaths) {
    const result = await validateSnapshotPath(projectRoot, requestedPath);
    if ("error" in result) {
      return invalidRequest(result.error.code, result.error.message, { path: requestedPath });
    }
    validated.push(result);
  }

  const snapshotId = snapshotIdFor(options.label);
  const snapshotRoot = path.join(bridgeDir, "artifacts", "undo_snapshots", snapshotId);
  const filesRoot = path.join(snapshotRoot, "files");
  await fs.mkdir(filesRoot, { recursive: true });

  const files: JsonObject[] = [];
  for (const item of validated) {
    const destination = path.join(filesRoot, item.relativePath);
    await fs.mkdir(path.dirname(destination), { recursive: true });
    await fs.copyFile(item.absolutePath, destination);
    files.push({
      project_relative_path: item.relativePath,
      source_path: item.absolutePath,
      snapshot_path: destination,
      byte_size: item.byteSize,
    });
  }

  const manifest = {
    status: "ok" as const,
    snapshot_version: "godot-codex-bridge/undo-snapshot-v1",
    snapshot_id: snapshotId,
    label: options.label ?? null,
    project_root: projectRoot,
    snapshot_root: snapshotRoot,
    created_at: new Date().toISOString(),
    file_count: files.length,
    files,
    restore_note: "This snapshot is local evidence only. Review files manually before restoring.",
  };
  const manifestPath = path.join(snapshotRoot, "manifest.json");
  await fs.writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");

  return {
    ...manifest,
    manifest_path: manifestPath,
  };
}

async function validateSnapshotPath(
  projectRoot: string,
  requestedPath: string,
): Promise<{ relativePath: string; absolutePath: string; byteSize: number } | { error: { code: string; message: string } }> {
  if (typeof requestedPath !== "string" || requestedPath.trim() === "") {
    return { error: { code: "invalid_path", message: "Snapshot path must be a non-empty string." } };
  }
  if (path.isAbsolute(requestedPath)) {
    return { error: { code: "absolute_path_rejected", message: "Snapshot paths must be project-relative." } };
  }
  if (requestedPath.includes("..")) {
    return { error: { code: "path_traversal_rejected", message: "Snapshot paths must not contain '..'." } };
  }
  const normalizedRelative = requestedPath.replace(/^res:\/\//, "").replace(/[\\/]+/g, path.sep);
  if (normalizedRelative.startsWith(".godot") || normalizedRelative.startsWith(".import")) {
    return { error: { code: "generated_path_rejected", message: "Generated Godot cache/import paths are not snapshot targets." } };
  }

  const extension = path.extname(normalizedRelative).toLowerCase();
  if (!ALLOWED_EXTENSIONS.has(extension)) {
    return { error: { code: "unsupported_snapshot_extension", message: `Unsupported snapshot extension: ${extension || "(none)"}.` } };
  }

  const absolutePath = path.resolve(projectRoot, normalizedRelative);
  if (!isInsidePath(projectRoot, absolutePath)) {
    return { error: { code: "path_boundary_rejected", message: "Resolved snapshot path is outside the project root." } };
  }

  let stat;
  try {
    stat = await fs.stat(absolutePath);
  } catch {
    return { error: { code: "snapshot_source_missing", message: "Snapshot source file does not exist." } };
  }
  if (!stat.isFile()) {
    return { error: { code: "snapshot_source_not_file", message: "Snapshot source must be a file." } };
  }
  if (stat.size > MAX_FILE_BYTES) {
    return { error: { code: "snapshot_source_too_large", message: `Snapshot source exceeds ${MAX_FILE_BYTES} bytes.` } };
  }

  return {
    relativePath: normalizedRelative,
    absolutePath,
    byteSize: stat.size,
  };
}

function invalidRequest(code: string, message: string, details: JsonObject = {}): ToolEnvelope {
  return {
    status: "invalid_request",
    error: {
      code,
      message,
      ...details,
    },
  };
}

function snapshotIdFor(label: string | undefined): string {
  const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
  const safeLabel = (label ?? "manual")
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 48);
  return `${timestamp}_${safeLabel || "manual"}`;
}
