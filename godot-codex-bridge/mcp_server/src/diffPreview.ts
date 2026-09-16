import { createHash } from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";

import { createTwoFilesPatch } from "diff";

import { isInsidePath } from "./config.js";
import type { JsonObject } from "./types.js";

const MAX_TEXT_BYTES = 2_000_000;

const BLOCKED_SEGMENTS = new Set([".godot", ".import", "generated"]);

const BINARY_EXTENSIONS = new Set([
  ".7z",
  ".a",
  ".bin",
  ".bmp",
  ".dll",
  ".dylib",
  ".exe",
  ".exr",
  ".fbx",
  ".glb",
  ".hdr",
  ".ico",
  ".jar",
  ".jpg",
  ".jpeg",
  ".mesh",
  ".mp3",
  ".mp4",
  ".ogg",
  ".otf",
  ".pak",
  ".png",
  ".pck",
  ".res",
  ".so",
  ".ttf",
  ".wav",
  ".webp",
  ".zip",
]);

const TEXT_EXTENSIONS = new Set([
  ".cfg",
  ".cs",
  ".gd",
  ".gdshader",
  ".godot",
  ".json",
  ".md",
  ".shader",
  ".tres",
  ".tscn",
  ".txt",
]);

export class PreviewDiffError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly details: JsonObject = {},
  ) {
    super(message);
    this.name = "PreviewDiffError";
  }
}

export interface PreviewSceneDiffOptions {
  projectRoot: string;
  targetPath: string;
  proposedContent: string;
  allowCreate?: boolean;
  contextLines?: number;
}

export async function previewSceneDiff(options: PreviewSceneDiffOptions): Promise<JsonObject> {
  const resolved = resolvePreviewTarget(options.projectRoot, options.targetPath);

  if (Buffer.byteLength(options.proposedContent, "utf8") > MAX_TEXT_BYTES) {
    throw new PreviewDiffError("proposed_content_too_large", "Proposed content exceeds MVP preview size limit.", {
      max_bytes: MAX_TEXT_BYTES,
    });
  }

  if (containsNul(options.proposedContent)) {
    throw new PreviewDiffError("binary_content_rejected", "Proposed content appears to be binary.");
  }

  const existing = await readExistingText(resolved.absolutePath, Boolean(options.allowCreate));
  const context = Math.min(Math.max(Math.trunc(options.contextLines ?? 3), 0), 20);
  const patch = createTwoFilesPatch(
    resolved.relativePath,
    resolved.relativePath,
    existing.content,
    options.proposedContent,
    existing.exists ? "current" : "missing",
    "proposed",
    { context },
  );

  return {
    status: "ok",
    operation: existing.exists ? "modify" : "create",
    path: resolved.relativePath,
    absolute_path: resolved.absolutePath,
    unchanged: existing.content === options.proposedContent,
    current_sha256: sha256(existing.content),
    proposed_sha256: sha256(options.proposedContent),
    diff: patch,
    applied: false,
  };
}

export function resolvePreviewTarget(projectRoot: string, targetPath: string): {
  relativePath: string;
  absolutePath: string;
} {
  if (!targetPath || targetPath.trim() === "") {
    throw new PreviewDiffError("empty_path", "Target path is required.");
  }

  if (path.isAbsolute(targetPath) || /^[A-Za-z]:[\\/]/.test(targetPath)) {
    throw new PreviewDiffError("absolute_path_rejected", "Use a project-relative path, not an absolute path.");
  }

  const withoutResPrefix = targetPath.startsWith("res://") ? targetPath.slice("res://".length) : targetPath;
  const normalized = path.normalize(withoutResPrefix.replaceAll("/", path.sep));

  if (
    normalized === "." ||
    normalized.startsWith(`..${path.sep}`) ||
    normalized === ".." ||
    path.isAbsolute(normalized)
  ) {
    throw new PreviewDiffError("path_traversal_rejected", "Path traversal outside the project is not allowed.");
  }

  const segments = normalized.split(/[\\/]+/).map((segment) => segment.toLowerCase());
  const blockedSegment = segments.find((segment) => BLOCKED_SEGMENTS.has(segment));
  if (blockedSegment) {
    throw new PreviewDiffError("blocked_path_rejected", "Generated/import bridge paths are not diff-preview targets.", {
      segment: blockedSegment,
    });
  }

  const extension = path.extname(normalized).toLowerCase();
  if (extension === ".import" || BINARY_EXTENSIONS.has(extension)) {
    throw new PreviewDiffError("binary_path_rejected", "Binary/import files are not diff-preview targets.", {
      extension,
    });
  }

  if (!TEXT_EXTENSIONS.has(extension)) {
    throw new PreviewDiffError("unsupported_text_extension", "Only known text scene/script/resource files are allowed.", {
      extension,
    });
  }

  const absolutePath = path.resolve(projectRoot, normalized);
  if (!isInsidePath(projectRoot, absolutePath)) {
    throw new PreviewDiffError("path_boundary_rejected", "Resolved path is outside the configured project root.");
  }

  return {
    relativePath: normalized.replaceAll(path.sep, "/"),
    absolutePath,
  };
}

async function readExistingText(filePath: string, allowCreate: boolean): Promise<{ exists: boolean; content: string }> {
  let buffer: Buffer;
  try {
    buffer = await fs.readFile(filePath);
  } catch (error) {
    if (allowCreate && isNodeError(error) && error.code === "ENOENT") {
      return { exists: false, content: "" };
    }

    throw new PreviewDiffError("file_not_found", "Target file does not exist. Set allowCreate for new files.", {
      path: filePath,
    });
  }

  if (buffer.byteLength > MAX_TEXT_BYTES) {
    throw new PreviewDiffError("current_content_too_large", "Current file exceeds MVP preview size limit.", {
      max_bytes: MAX_TEXT_BYTES,
    });
  }

  if (buffer.includes(0)) {
    throw new PreviewDiffError("binary_content_rejected", "Current file appears to be binary.");
  }

  return { exists: true, content: buffer.toString("utf8") };
}

function containsNul(value: string): boolean {
  return value.includes("\0");
}

function sha256(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

function isNodeError(error: unknown): error is NodeJS.ErrnoException {
  return error instanceof Error && "code" in error;
}
