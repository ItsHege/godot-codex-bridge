import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import type { ProjectSummary } from "./types.js";

const SKIP_DIRS = new Set([".git", ".godot", ".import", "node_modules", "dist"]);

export async function resolveProject(projectRootInput: string, bridgeDirInput?: string): Promise<ProjectSummary> {
  const projectRoot = path.resolve(projectRootInput);
  const projectFile = path.join(projectRoot, "project.godot");
  const stat = await fs.stat(projectFile).catch(() => null);
  if (!stat?.isFile()) {
    throw new Error(`wrong_root: project.godot not found at ${projectFile}`);
  }

  const bridgeDir = bridgeDirInput
    ? assertInside(projectRoot, path.resolve(bridgeDirInput), "bridge_dir")
    : path.join(projectRoot, ".godot", "godot_codex_bridge");
  const hostStateDir = path.join(bridgeDir, "codex_host");
  await fs.mkdir(hostStateDir, { recursive: true });

  return {
    projectRoot,
    projectFile,
    bridgeDir,
    hostStateDir,
    agentsFiles: await findAgentsFiles(projectRoot)
  };
}

export function assertInside(root: string, candidate: string, label: string): string {
  const relative = path.relative(root, candidate);
  if (relative.startsWith("..") || path.isAbsolute(relative)) {
    throw new Error(`${label}_outside_project_root: ${candidate}`);
  }
  return candidate;
}

async function findAgentsFiles(projectRoot: string): Promise<ProjectSummary["agentsFiles"]> {
  const found: ProjectSummary["agentsFiles"] = [];
  await walk(projectRoot, async (filePath) => {
    if (path.basename(filePath).toLowerCase() !== "agents.md") {
      return;
    }
    const buffer = await fs.readFile(filePath);
    found.push({
      path: filePath,
      sha256: crypto.createHash("sha256").update(buffer).digest("hex"),
      bytes: buffer.byteLength
    });
  });
  return found.sort((a, b) => a.path.localeCompare(b.path));
}

async function walk(dir: string, visitFile: (filePath: string) => Promise<void>): Promise<void> {
  const entries = await fs.readdir(dir, { withFileTypes: true }).catch(() => []);
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (!SKIP_DIRS.has(entry.name)) {
        await walk(fullPath, visitFile);
      }
      continue;
    }
    if (entry.isFile()) {
      await visitFile(fullPath);
    }
  }
}
