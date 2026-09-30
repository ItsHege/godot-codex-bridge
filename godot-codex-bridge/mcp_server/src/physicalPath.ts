import fs from "node:fs";
import { randomUUID } from "node:crypto";
import path from "node:path";

export class PhysicalPathError extends Error {
  constructor(readonly code: string, message: string, readonly targetPath: string) {
    super(message);
    this.name = "PhysicalPathError";
  }
}

export interface PhysicalPathOptions {
  allowMissingLeaf?: boolean;
  allowMissingTail?: boolean;
  requireFile?: boolean;
  requireDirectory?: boolean;
}

export function ensureDirectoryInsideRootSync(rootPath: string, directoryPath: string): void {
  const root = path.resolve(rootPath);
  const directory = path.resolve(directoryPath);
  assertPhysicalPathSync(root, root, { requireDirectory: true });
  if (!isInside(root, directory)) {
    throw new PhysicalPathError("path_boundary_rejected", "Directory is outside the configured root.", directory);
  }

  const relative = path.relative(root, directory);
  const parts = relative === "" ? [] : relative.split(path.sep).filter(Boolean);
  let current = root;
  for (const part of parts) {
    current = path.join(current, part);
    try {
      assertPhysicalPathSync(root, current, { requireDirectory: true });
      continue;
    } catch (error) {
      if (!(error instanceof PhysicalPathError) || (error.code !== "path_unavailable" && error.code !== "root_unavailable")) {
        throw error;
      }
    }
    try {
      fs.mkdirSync(current);
    } catch (error) {
      if (!isNodeError(error) || error.code !== "EEXIST") {
        throw error;
      }
    }
    assertPhysicalPathSync(root, current, { requireDirectory: true });
  }
}

export function writeFileInsideRootSync(
  rootPath: string,
  targetPath: string,
  data: string | NodeJS.ArrayBufferView,
): void {
  const target = path.resolve(targetPath);
  ensureDirectoryInsideRootSync(rootPath, path.dirname(target));
  try {
    assertPhysicalPathSync(rootPath, target, { requireFile: true });
    throw new PhysicalPathError("target_exists", "Refusing to overwrite an existing file through the confined artifact writer.", target);
  } catch (error) {
    if (!(error instanceof PhysicalPathError) || error.code !== "path_unavailable") {
      throw error;
    }
    assertPhysicalPathSync(rootPath, target, { allowMissingLeaf: true });
  }

  const noFollow = process.platform === "win32" ? 0 : fs.constants.O_NOFOLLOW;
  const descriptor = fs.openSync(target, fs.constants.O_CREAT | fs.constants.O_EXCL | fs.constants.O_WRONLY | noFollow, 0o600);
  try {
    const opened = fs.fstatSync(descriptor);
    const current = fs.statSync(target);
    if (!opened.isFile() || opened.ino !== current.ino || opened.dev !== current.dev) {
      throw new PhysicalPathError("file_identity_changed", "File identity changed while it was being opened for writing.", target);
    }
    assertPhysicalPathSync(rootPath, target, { requireFile: true });
    fs.writeFileSync(descriptor, data);
    fs.fsyncSync(descriptor);
    assertPhysicalPathSync(rootPath, target, { requireFile: true });
  } finally {
    fs.closeSync(descriptor);
  }
}

/** Publish a complete new artifact under its final name in one directory rename. */
export function publishFileInsideRootSync(rootPath: string, targetPath: string, data: string | NodeJS.ArrayBufferView): void {
  const target = path.resolve(targetPath);
  ensureDirectoryInsideRootSync(rootPath, path.dirname(target));
  assertPhysicalPathSync(rootPath, target, { allowMissingLeaf: true });
  if (fs.existsSync(target)) {
    throw new PhysicalPathError("target_exists", "Refusing to replace an existing artifact.", target);
  }
  const temporary = path.join(path.dirname(target), `.${path.basename(target)}.${randomUUID()}.tmp`);
  writeFileInsideRootSync(rootPath, temporary, data);
  try {
    assertPhysicalPathSync(rootPath, target, { allowMissingLeaf: true });
    if (fs.existsSync(target)) {
      throw new PhysicalPathError("target_exists", "Refusing to replace an existing artifact.", target);
    }
    fs.renameSync(temporary, target);
    assertPhysicalPathSync(rootPath, target, { requireFile: true });
  } finally {
    if (fs.existsSync(temporary)) {
      assertPhysicalPathSync(rootPath, temporary, { requireFile: true });
      fs.unlinkSync(temporary);
    }
  }
}

export function readFileInsideRootSync(rootPath: string, targetPath: string): Buffer {
  const descriptor = openFileInsideRootSync(rootPath, targetPath);
  try {
    const before = fs.fstatSync(descriptor);
    if (!before.isFile()) {
      throw new PhysicalPathError("not_a_file", "Expected a regular file.", targetPath);
    }
    const bytes = fs.readFileSync(descriptor);
    const after = fs.fstatSync(descriptor);
    if (before.size !== after.size || before.mtimeMs !== after.mtimeMs || before.ino !== after.ino) {
      throw new PhysicalPathError("file_changed_during_read", "File changed while it was being read.", targetPath);
    }
    assertPhysicalPathSync(rootPath, targetPath, { requireFile: true });
    return bytes;
  } finally {
    fs.closeSync(descriptor);
  }
}

export function readFileInsideRootBoundedSync(rootPath: string, targetPath: string, maxBytes: number): Buffer {
  if (!Number.isSafeInteger(maxBytes) || maxBytes < 0) {
    throw new PhysicalPathError("invalid_read_limit", "Bounded file reads require a non-negative integer byte limit.", targetPath);
  }

  const descriptor = openFileInsideRootSync(rootPath, targetPath);
  try {
    const before = fs.fstatSync(descriptor);
    if (!before.isFile()) {
      throw new PhysicalPathError("not_a_file", "Expected a regular file.", targetPath);
    }
    if (before.size > maxBytes) {
      throw new PhysicalPathError("file_too_large", `File exceeds the ${maxBytes}-byte read limit.`, targetPath);
    }

    const buffer = Buffer.alloc(Math.min(maxBytes + 1, before.size + 1));
    let bytesRead = 0;
    while (bytesRead < buffer.length) {
      const count = fs.readSync(descriptor, buffer, bytesRead, buffer.length - bytesRead, bytesRead);
      if (count === 0) {
        break;
      }
      bytesRead += count;
    }
    if (bytesRead > maxBytes) {
      throw new PhysicalPathError("file_too_large", `File exceeds the ${maxBytes}-byte read limit.`, targetPath);
    }

    const after = fs.fstatSync(descriptor);
    if (before.size !== after.size || before.mtimeMs !== after.mtimeMs || before.ino !== after.ino) {
      throw new PhysicalPathError("file_changed_during_read", "File changed while it was being read.", targetPath);
    }
    assertPhysicalPathSync(rootPath, targetPath, { requireFile: true });
    return buffer.subarray(0, bytesRead);
  } finally {
    fs.closeSync(descriptor);
  }
}

export function openFileInsideRootSync(rootPath: string, targetPath: string): number {
  assertPhysicalPathSync(rootPath, targetPath, { requireFile: true });
  const noFollow = process.platform === "win32" ? 0 : fs.constants.O_NOFOLLOW;
  const descriptor = fs.openSync(targetPath, fs.constants.O_RDONLY | noFollow);
  try {
    assertPhysicalPathSync(rootPath, targetPath, { requireFile: true });
    const opened = fs.fstatSync(descriptor);
    const current = fs.statSync(targetPath);
    if (!opened.isFile() || opened.size !== current.size || opened.ino !== current.ino || opened.dev !== current.dev) {
      throw new PhysicalPathError("file_identity_changed", "File identity changed while it was being opened.", targetPath);
    }
    // A hard link shares one file with another directory entry that may be
    // outside the project, and path checks cannot see that other entry.
    if (opened.nlink > 1) {
      throw new PhysicalPathError("hardlink_rejected", "Files with more than one hard link are not allowed.", targetPath);
    }
    return descriptor;
  } catch (error) {
    fs.closeSync(descriptor);
    throw error;
  }
}

/**
 * Resolve a path under a trusted root while rejecting symlink/junction/reparse
 * components. This is intentionally synchronous so every caller can apply the
 * same check immediately before a filesystem sink.
 */
export function assertPhysicalPathSync(
  rootPath: string,
  targetPath: string,
  options: PhysicalPathOptions = {},
): { rootPath: string; rootRealPath: string; targetPath: string; targetRealPath: string | null } {
  const root = path.resolve(rootPath);
  const target = path.resolve(targetPath);
  if (!isInside(root, target)) {
    throw new PhysicalPathError("path_boundary_rejected", "Path is outside the configured root.", target);
  }

  let rootReal: string;
  try {
    assertNoLinkedRootComponents(root);
    const rootStat = fs.lstatSync(root);
    if (rootStat.isSymbolicLink()) {
      throw new PhysicalPathError("reparse_root_rejected", "The configured root cannot be a symbolic link or junction.", root);
    }
    if (!rootStat.isDirectory()) {
      throw new PhysicalPathError("root_not_a_directory", "The configured root must be a directory.", root);
    }
    rootReal = fs.realpathSync.native(root);
  } catch (error) {
    if (error instanceof PhysicalPathError) {
      throw error;
    }
    throw new PhysicalPathError("root_unavailable", "Configured root does not exist or cannot be resolved.", root);
  }

  const relative = path.relative(root, target);
  const parts = relative === "" ? [] : relative.split(path.sep).filter(Boolean);
  let current = root;
  for (let index = 0; index < parts.length; index += 1) {
    current = path.join(current, parts[index]);
    let stat: fs.Stats;
    try {
      stat = fs.lstatSync(current);
    } catch (error) {
      if (isNodeError(error) && error.code === "ENOENT" && (options.allowMissingTail || (options.allowMissingLeaf && index === parts.length - 1))) {
        return { rootPath: root, rootRealPath: rootReal, targetPath: target, targetRealPath: null };
      }
      throw new PhysicalPathError("path_unavailable", "Path does not exist or cannot be inspected.", current);
    }
    if (stat.isSymbolicLink()) {
      throw new PhysicalPathError("reparse_path_rejected", "Symbolic-link and junction path components are not allowed.", current);
    }
    const currentReal = fs.realpathSync.native(current);
    if (!isInside(rootReal, currentReal)) {
      throw new PhysicalPathError("physical_boundary_rejected", "Resolved path escapes the configured root.", current);
    }
  }

  const targetReal = fs.realpathSync.native(target);
  if (!isInside(rootReal, targetReal)) {
    throw new PhysicalPathError("physical_boundary_rejected", "Resolved path escapes the configured root.", target);
  }
  const targetStat = fs.lstatSync(target);
  if (targetStat.isSymbolicLink()) {
    throw new PhysicalPathError("reparse_path_rejected", "Symbolic-link and junction targets are not allowed.", target);
  }
  if (options.requireFile && !targetStat.isFile()) {
    throw new PhysicalPathError("not_a_file", "Expected a regular file.", target);
  }
  if (options.requireDirectory && !targetStat.isDirectory()) {
    throw new PhysicalPathError("not_a_directory", "Expected a directory.", target);
  }
  return { rootPath: root, rootRealPath: rootReal, targetPath: target, targetRealPath: targetReal };
}

function assertNoLinkedRootComponents(root: string): void {
  const anchor = path.parse(root).root;
  const relative = path.relative(anchor, root);
  let current = anchor;
  for (const part of relative.split(path.sep).filter(Boolean)) {
    current = path.join(current, part);
    let stat: fs.Stats;
    try {
      stat = fs.lstatSync(current);
    } catch {
      throw new PhysicalPathError("root_unavailable", "Configured root does not exist or cannot be inspected.", current);
    }
    if (stat.isSymbolicLink()) {
      throw new PhysicalPathError("reparse_root_rejected", "No configured-root component may be a symbolic link or junction.", current);
    }
    if (!stat.isDirectory()) {
      throw new PhysicalPathError("root_not_a_directory", "Every configured-root component must be a directory.", current);
    }
  }
}

export function isInside(rootPath: string, candidatePath: string): boolean {
  const relative = path.relative(path.resolve(rootPath), path.resolve(candidatePath));
  return relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative));
}

function isNodeError(error: unknown): error is NodeJS.ErrnoException {
  return error instanceof Error && "code" in error;
}
