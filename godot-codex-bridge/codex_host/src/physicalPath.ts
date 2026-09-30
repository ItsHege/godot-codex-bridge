import fs from "node:fs";
import path from "node:path";

export class PhysicalPathError extends Error {
  constructor(readonly code: string, message: string, readonly targetPath: string) {
    super(message);
    this.name = "PhysicalPathError";
  }
}

export function ensureDirectoryInsideRootSync(rootPath: string, directoryPath: string): void {
  const root = path.resolve(rootPath);
  const directory = path.resolve(directoryPath);
  assertPhysicalPathSync(root, root);
  if (!isInside(root, directory)) {
    throw new PhysicalPathError("outside_project_root", "Directory is outside the project root.", directory);
  }
  const relative = path.relative(root, directory);
  const parts = relative === "" ? [] : relative.split(path.sep).filter(Boolean);
  let current = root;
  for (const part of parts) {
    current = path.join(current, part);
    try {
      assertPhysicalPathSync(root, current);
      const stat = fs.lstatSync(current);
      if (!stat.isDirectory()) {
        throw new PhysicalPathError("not_a_directory", "Expected a directory.", current);
      }
      continue;
    } catch (error) {
      if (!(error instanceof PhysicalPathError) || error.code !== "path_unavailable") {
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
    assertPhysicalPathSync(root, current);
    if (!fs.lstatSync(current).isDirectory()) {
      throw new PhysicalPathError("not_a_directory", "Expected a directory.", current);
    }
  }
}

export function writeFileInsideRootSync(
  rootPath: string,
  targetPath: string,
  data: string | NodeJS.ArrayBufferView,
): void {
  const target = path.resolve(targetPath);
  ensureDirectoryInsideRootSync(rootPath, path.dirname(target));
  const noFollow = process.platform === "win32" ? 0 : fs.constants.O_NOFOLLOW;
  let descriptor: number;
  try {
    assertPhysicalPathSync(rootPath, target);
    if (!fs.lstatSync(target).isFile()) {
      throw new PhysicalPathError("not_a_file", "Expected a regular file.", target);
    }
    descriptor = fs.openSync(target, fs.constants.O_RDWR | noFollow);
  } catch (error) {
    if (!(error instanceof PhysicalPathError) || error.code !== "path_unavailable") {
      throw error;
    }
    assertPhysicalPathSync(rootPath, target, true);
    descriptor = fs.openSync(target, fs.constants.O_CREAT | fs.constants.O_EXCL | fs.constants.O_WRONLY | noFollow, 0o600);
  }
  try {
    verifyOpenFile(rootPath, target, descriptor);
    fs.ftruncateSync(descriptor, 0);
    fs.writeFileSync(descriptor, data);
    fs.fsyncSync(descriptor);
    assertPhysicalPathSync(rootPath, target);
  } finally {
    fs.closeSync(descriptor);
  }
}

export function appendFileInsideRootSync(rootPath: string, targetPath: string, data: string): void {
  const target = path.resolve(targetPath);
  // SessionStore creates and verifies this parent once during initialization.
  // Re-check it immediately before opening, then verify the opened handle against
  // the still-confined path before writing. Avoid repeating the full recursive
  // directory creation walk for every event on the Host event-loop hot path.
  assertPhysicalPathSync(rootPath, path.dirname(target));
  const noFollow = process.platform === "win32" ? 0 : fs.constants.O_NOFOLLOW;
  let descriptor: number;
  try {
    descriptor = fs.openSync(target, fs.constants.O_RDWR | fs.constants.O_APPEND | noFollow);
  } catch (error) {
    if (!isNodeError(error) || error.code !== "ENOENT") {
      throw error;
    }
    assertPhysicalPathSync(rootPath, target, true);
    descriptor = fs.openSync(target, fs.constants.O_CREAT | fs.constants.O_EXCL | fs.constants.O_WRONLY | noFollow, 0o600);
  }
  try {
    verifyOpenFile(rootPath, target, descriptor);
    fs.writeFileSync(descriptor, data);
  } finally {
    fs.closeSync(descriptor);
  }
}

export function readFileInsideRootSync(rootPath: string, targetPath: string): Buffer {
  assertPhysicalPathSync(rootPath, targetPath);
  const noFollow = process.platform === "win32" ? 0 : fs.constants.O_NOFOLLOW;
  const descriptor = fs.openSync(targetPath, fs.constants.O_RDONLY | noFollow);
  try {
    verifyOpenFile(rootPath, targetPath, descriptor);
    const before = fs.fstatSync(descriptor);
    const bytes = fs.readFileSync(descriptor);
    const after = fs.fstatSync(descriptor);
    if (before.size !== after.size || before.mtimeMs !== after.mtimeMs || before.ino !== after.ino) {
      throw new PhysicalPathError("file_changed_during_read", "File changed while it was being read.", targetPath);
    }
    return bytes;
  } finally {
    fs.closeSync(descriptor);
  }
}

export function assertPhysicalPathSync(rootPath: string, targetPath: string, allowMissingLeaf = false): void {
  const root = path.resolve(rootPath);
  const target = path.resolve(targetPath);
  if (!isInside(root, target)) {
    throw new PhysicalPathError("outside_project_root", "Path is outside the project root.", target);
  }
  assertNoLinkedRootComponents(root);
  const rootStat = fs.lstatSync(root);
  if (rootStat.isSymbolicLink()) {
    throw new PhysicalPathError("reparse_root_rejected", "The project root cannot be a symbolic link or junction.", root);
  }
  if (!rootStat.isDirectory()) {
    throw new PhysicalPathError("root_not_a_directory", "The project root must be a directory.", root);
  }
  const rootReal = fs.realpathSync.native(root);
  const relative = path.relative(root, target);
  const parts = relative === "" ? [] : relative.split(path.sep).filter(Boolean);
  let current = root;
  for (let index = 0; index < parts.length; index += 1) {
    current = path.join(current, parts[index]);
    let stat: fs.Stats;
    try {
      stat = fs.lstatSync(current);
    } catch (error) {
      if (isNodeError(error) && error.code === "ENOENT" && allowMissingLeaf) {
        return;
      }
      throw new PhysicalPathError("path_unavailable", "Path does not exist or cannot be inspected.", current);
    }
    if (stat.isSymbolicLink()) {
      throw new PhysicalPathError("reparse_path_rejected", "Symbolic-link and junction path components are not allowed.", current);
    }
    const currentReal = fs.realpathSync.native(current);
    if (!isInside(rootReal, currentReal)) {
      throw new PhysicalPathError("physical_boundary_rejected", "Resolved path escapes the project root.", current);
    }
  }
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
      throw new PhysicalPathError("root_unavailable", "Project root does not exist or cannot be inspected.", current);
    }
    if (stat.isSymbolicLink()) {
      throw new PhysicalPathError("reparse_root_rejected", "No project-root component may be a symbolic link or junction.", current);
    }
    if (!stat.isDirectory()) {
      throw new PhysicalPathError("root_not_a_directory", "Every project-root component must be a directory.", current);
    }
  }
}

function isInside(root: string, candidate: string): boolean {
  const relative = path.relative(path.resolve(root), path.resolve(candidate));
  return relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative));
}

function isNodeError(error: unknown): error is NodeJS.ErrnoException {
  return error instanceof Error && "code" in error;
}

function verifyOpenFile(rootPath: string, targetPath: string, descriptor: number): void {
  const opened = fs.fstatSync(descriptor);
  const current = fs.statSync(targetPath);
  if (!opened.isFile() || opened.ino !== current.ino || opened.dev !== current.dev) {
    throw new PhysicalPathError("file_identity_changed", "File identity changed while it was being opened.", targetPath);
  }
  // A hard link shares one file with another directory entry that may be
  // outside the project, and path checks cannot see that other entry.
  if (opened.nlink > 1) {
    throw new PhysicalPathError("hardlink_rejected", "Files with more than one hard link are not allowed.", targetPath);
  }
  assertPhysicalPathSync(rootPath, targetPath);
}
