import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import type { HostApproval, ProjectSummary } from "./types.js";

const MAX_UNDO_FILES = 64;
const MAX_UNDO_FILE_BYTES = 5 * 1024 * 1024;
const SNAPSHOT_TEXT_EXTENSIONS = new Set([
  ".cfg",
  ".cs",
  ".gd",
  ".godot",
  ".json",
  ".md",
  ".shader",
  ".tres",
  ".tscn",
  ".txt"
]);

export type UndoSnapshotFile = {
  requested_path: string;
  absolute_path?: string;
  existed: boolean;
  copied: boolean;
  byte_size?: number;
  sha256?: string;
  snapshot_path?: string;
  skipped_reason?: string;
};

export type UndoSnapshotSummary = {
  approval_id: string;
  runtime_approval_id: string;
  created_at: string;
  project_root: string;
  snapshot_dir: string;
  manifest_path: string;
  requested_path_count: number;
  copied_count: number;
  files: UndoSnapshotFile[];
};

export async function createApprovalUndoSnapshot(project: ProjectSummary, approval: HostApproval): Promise<UndoSnapshotSummary> {
  const requestedPaths = collectApprovalPaths(approval).slice(0, MAX_UNDO_FILES);
  if (requestedPaths.length === 0) {
    throw new Error(`approval_undo_paths_required: ${approval.approval_id}`);
  }

  const snapshotDir = path.join(project.hostStateDir, "undo_snapshots", safeSegment(approval.approval_id));
  const filesDir = path.join(snapshotDir, "files");
  await fs.mkdir(filesDir, { recursive: true });

  const files: UndoSnapshotFile[] = [];
  for (const requestedPath of requestedPaths) {
    const normalized = normalizeProjectPath(project.projectRoot, requestedPath);
    if (!normalized.ok) {
      files.push({
        requested_path: requestedPath,
        existed: false,
        copied: false,
        skipped_reason: normalized.reason
      });
      continue;
    }

    const file: UndoSnapshotFile = {
      requested_path: requestedPath,
      absolute_path: normalized.absolutePath,
      existed: false,
      copied: false
    };
    const stat = await fs.stat(normalized.absolutePath).catch(() => null);
    if (!stat) {
      files.push(file);
      continue;
    }
    if (!stat.isFile()) {
      file.skipped_reason = "not_a_file";
      files.push(file);
      continue;
    }
    file.existed = true;
    file.byte_size = stat.size;
    if (stat.size > MAX_UNDO_FILE_BYTES) {
      file.skipped_reason = "file_too_large";
      files.push(file);
      continue;
    }
    if (!SNAPSHOT_TEXT_EXTENSIONS.has(path.extname(normalized.absolutePath).toLowerCase())) {
      file.skipped_reason = "unsupported_extension";
      files.push(file);
      continue;
    }

    const bytes = await fs.readFile(normalized.absolutePath);
    file.sha256 = crypto.createHash("sha256").update(bytes).digest("hex");
    file.snapshot_path = path.join(filesDir, `${safeSegment(normalized.relativePath)}.snapshot`);
    await fs.writeFile(file.snapshot_path, bytes);
    file.copied = true;
    files.push(file);
  }

  const summary: UndoSnapshotSummary = {
    approval_id: approval.approval_id,
    runtime_approval_id: approval.runtime_approval_id,
    created_at: new Date().toISOString(),
    project_root: project.projectRoot,
    snapshot_dir: snapshotDir,
    manifest_path: path.join(snapshotDir, "manifest.json"),
    requested_path_count: requestedPaths.length,
    copied_count: files.filter((file) => file.copied).length,
    files
  };
  await fs.writeFile(summary.manifest_path, `${JSON.stringify(summary, null, 2)}\n`, "utf8");
  return summary;
}

function collectApprovalPaths(approval: HostApproval): string[] {
  const found = new Set<string>();
  visit(approval.file_changes, found);
  visit(approval.diff_evidence, found);
  visit(approval.raw_params, found);
  return [...found];
}

function visit(value: unknown, found: Set<string>): void {
  if (typeof value === "string") {
    if (looksLikeProjectPath(value)) {
      found.add(value);
    }
    return;
  }
  if (!value || typeof value !== "object") {
    return;
  }
  if (Array.isArray(value)) {
    for (const item of value) {
      visit(item, found);
    }
    return;
  }
  for (const [key, nested] of Object.entries(value as Record<string, unknown>)) {
    if (looksLikeProjectPath(key)) {
      found.add(key);
    }
    visit(nested, found);
  }
}

function looksLikeProjectPath(value: string): boolean {
  if (value.includes("\n") || value.length > 260) {
    return false;
  }
  if (value.startsWith("res://")) {
    return true;
  }
  if (value.startsWith(".godot/") || value.startsWith(".godot\\")) {
    return false;
  }
  const ext = path.extname(value).toLowerCase();
  return Boolean(ext) && SNAPSHOT_TEXT_EXTENSIONS.has(ext) && !path.isAbsolute(value);
}

function normalizeProjectPath(projectRoot: string, requestedPath: string): { ok: true; absolutePath: string; relativePath: string } | { ok: false; reason: string } {
  const root = path.resolve(projectRoot);
  const rawRelative = requestedPath.startsWith("res://")
    ? requestedPath.slice("res://".length)
    : requestedPath;
  if (rawRelative === "" || rawRelative.includes("\0")) {
    return { ok: false, reason: "invalid_path" };
  }
  const absolutePath = path.resolve(root, rawRelative);
  if (!isInside(root, absolutePath)) {
    return { ok: false, reason: "outside_project_root" };
  }
  const relativePath = path.relative(root, absolutePath);
  if (relativePath.startsWith(".godot") || relativePath.split(path.sep).includes(".godot")) {
    return { ok: false, reason: "generated_bridge_path" };
  }
  return { ok: true, absolutePath, relativePath };
}

function isInside(root: string, candidate: string): boolean {
  const relative = path.relative(root, candidate);
  return relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative));
}

function safeSegment(value: string): string {
  return value.replace(/[^a-zA-Z0-9._-]/g, "_");
}
