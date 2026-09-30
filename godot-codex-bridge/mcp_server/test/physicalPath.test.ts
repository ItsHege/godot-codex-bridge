import assert from "node:assert/strict";
import fsSync from "node:fs";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { previewSceneDiff } from "../src/diffPreview.js";
import { assertPhysicalPathSync, readFileInsideRootSync, writeFileInsideRootSync } from "../src/physicalPath.js";
import { createUndoSnapshot } from "../src/undoSnapshot.js";

test("project reads and snapshots reject a linked ancestor that escapes the project", async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-physical-project-"));
  const projectRoot = path.join(root, "project");
  const outsideRoot = path.join(root, "outside");
  const bridgeDir = path.join(projectRoot, ".godot", "godot_codex_bridge");
  await fs.mkdir(projectRoot, { recursive: true });
  await fs.mkdir(outsideRoot, { recursive: true });
  await fs.writeFile(path.join(projectRoot, "project.godot"), "[application]\n", "utf8");
  await fs.writeFile(path.join(outsideRoot, "secret.gd"), "extends Node\n", "utf8");
  await fs.symlink(outsideRoot, path.join(projectRoot, "linked"), process.platform === "win32" ? "junction" : "dir");

  await assert.rejects(
    () => previewSceneDiff({
      projectRoot,
      targetPath: "linked/secret.gd",
      proposedContent: "extends Node3D\n",
    }),
    (error: unknown) => error instanceof Error && /link|reparse/i.test(error.message),
  );

  const snapshot = await createUndoSnapshot(projectRoot, bridgeDir, { paths: ["linked/secret.gd"] });
  assert.equal(snapshot.status, "invalid_request");
  assert.equal(snapshot.error?.code, "reparse_path_rejected");
  assert.equal(await fs.readFile(path.join(outsideRoot, "secret.gd"), "utf8"), "extends Node\n");
});

test("a linked confinement root is rejected before any artifact path is accepted", async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-physical-root-"));
  const outsideRoot = path.join(root, "outside-artifacts");
  const linkedRoot = path.join(root, "artifacts");
  await fs.mkdir(outsideRoot, { recursive: true });
  await fs.writeFile(path.join(outsideRoot, "external.png"), "not-a-png", "utf8");
  await fs.symlink(outsideRoot, linkedRoot, process.platform === "win32" ? "junction" : "dir");

  assert.throws(
    () => assertPhysicalPathSync(linkedRoot, path.join(linkedRoot, "external.png"), { requireFile: true }),
    (error: unknown) => error instanceof Error && /root.*(link|junction)|reparse/i.test(error.message),
  );
});

test("a confinement root beneath a linked ancestor is rejected", async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-physical-root-ancestor-"));
  const outsideRoot = path.join(root, "outside");
  const projectUnderOutside = path.join(outsideRoot, "project");
  const linkedAncestor = path.join(root, "linked-parent");
  await fs.mkdir(projectUnderOutside, { recursive: true });
  await fs.writeFile(path.join(projectUnderOutside, "project.godot"), "[application]\n", "utf8");
  await fs.symlink(outsideRoot, linkedAncestor, process.platform === "win32" ? "junction" : "dir");
  const lexicalProjectRoot = path.join(linkedAncestor, "project");

  assert.throws(
    () => assertPhysicalPathSync(lexicalProjectRoot, path.join(lexicalProjectRoot, "project.godot"), { requireFile: true }),
    (error: unknown) => error instanceof Error && /root.*(link|junction)|reparse/i.test(error.message),
  );
});

test("artifact writers reject a linked output subtree", async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-physical-output-"));
  const projectRoot = path.join(root, "project");
  const outsideRoot = path.join(root, "outside");
  const bridgeDir = path.join(projectRoot, ".godot", "godot_codex_bridge");
  const sourcePath = path.join(projectRoot, "scripts", "player.gd");
  await fs.mkdir(path.dirname(sourcePath), { recursive: true });
  await fs.mkdir(path.join(bridgeDir, "artifacts"), { recursive: true });
  await fs.mkdir(outsideRoot, { recursive: true });
  await fs.writeFile(sourcePath, "extends Node\n", "utf8");
  await fs.symlink(
    outsideRoot,
    path.join(bridgeDir, "artifacts", "undo_snapshots"),
    process.platform === "win32" ? "junction" : "dir",
  );

  await assert.rejects(
    () => createUndoSnapshot(projectRoot, bridgeDir, { paths: ["scripts/player.gd"] }),
    (error: unknown) => error instanceof Error && /link|junction|reparse/i.test(error.message),
  );
  assert.deepEqual(await fs.readdir(outsideRoot), []);
});

test("confined artifact writes never truncate an occupied target", async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-physical-occupied-"));
  const target = path.join(root, "artifacts", "result.json");
  await fs.mkdir(path.dirname(target), { recursive: true });
  await fs.writeFile(target, "sentinel", "utf8");

  assert.throws(
    () => writeFileInsideRootSync(root, target, "replacement"),
    (error: unknown) => error instanceof Error && /overwrite|exists/i.test(error.message),
  );
  assert.equal(await fs.readFile(target, "utf8"), "sentinel");
});

test("a parent replaced with a junction between validation and open cannot expose outside bytes", async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-physical-race-"));
  const projectRoot = path.join(root, "project");
  const insideDir = path.join(projectRoot, "inside");
  const parkedDir = path.join(projectRoot, "inside-parked");
  const outsideDir = path.join(root, "outside");
  const target = path.join(insideDir, "target.txt");
  await fs.mkdir(insideDir, { recursive: true });
  await fs.mkdir(outsideDir, { recursive: true });
  await fs.writeFile(target, "inside", "utf8");
  await fs.writeFile(path.join(outsideDir, "target.txt"), "outside-sentinel", "utf8");

  const originalOpenSync = fsSync.openSync;
  let replacementOccurred = false;
  try {
    fsSync.openSync = ((filePath: fsSync.PathLike, flags: string | number, mode?: fsSync.Mode) => {
      if (!replacementOccurred && path.resolve(String(filePath)) === target) {
        replacementOccurred = true;
        fsSync.renameSync(insideDir, parkedDir);
        fsSync.symlinkSync(outsideDir, insideDir, process.platform === "win32" ? "junction" : "dir");
      }
      return originalOpenSync(filePath, flags, mode);
    }) as typeof fsSync.openSync;

    assert.throws(
      () => readFileInsideRootSync(projectRoot, target),
      (error: unknown) => error instanceof Error && /link|junction|reparse|boundary/i.test(error.message),
    );
    assert.equal(replacementOccurred, true);
    assert.equal(await fs.readFile(path.join(outsideDir, "target.txt"), "utf8"), "outside-sentinel");
  } finally {
    fsSync.openSync = originalOpenSync;
    if (replacementOccurred) {
      fsSync.unlinkSync(insideDir);
      fsSync.renameSync(parkedDir, insideDir);
    }
  }
  assert.equal(await fs.readFile(target, "utf8"), "inside");
});

test("project reads reject a hard link that shares an outside file", async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-physical-hardlink-"));
  const projectRoot = path.join(root, "project");
  const outsideFile = path.join(root, "outside-secret.txt");
  await fs.mkdir(projectRoot, { recursive: true });
  await fs.writeFile(outsideFile, "outside secret\n", "utf8");
  await fs.link(outsideFile, path.join(projectRoot, "linked.txt"));
  await fs.writeFile(path.join(projectRoot, "plain.txt"), "plain\n", "utf8");

  assert.throws(() => readFileInsideRootSync(projectRoot, path.join(projectRoot, "linked.txt")), /hard link/i);
  assert.equal(readFileInsideRootSync(projectRoot, path.join(projectRoot, "plain.txt")).toString("utf8"), "plain\n");
});
