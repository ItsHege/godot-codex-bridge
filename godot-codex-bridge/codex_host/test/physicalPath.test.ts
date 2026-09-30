import assert from "node:assert/strict";
import fsSync from "node:fs";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { ApprovalGate } from "../src/approvalGate.js";
import { writeFileInsideRootSync } from "../src/physicalPath.js";
import { SessionStore } from "../src/sessionStore.js";

test("Host state initialization rejects a linked events directory", async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-host-state-link-"));
  const projectRoot = path.join(root, "project");
  const stateDir = path.join(projectRoot, ".godot", "godot_codex_bridge", "codex_host");
  const outsideRoot = path.join(root, "outside");
  await fs.mkdir(stateDir, { recursive: true });
  await fs.mkdir(outsideRoot, { recursive: true });
  await fs.symlink(outsideRoot, path.join(stateDir, "events"), process.platform === "win32" ? "junction" : "dir");

  const store = new SessionStore(stateDir, 16, projectRoot);
  await assert.rejects(() => store.init(), /link|junction|reparse/i);
  assert.deepEqual(await fs.readdir(outsideRoot), []);
});

test("Host approval persistence rejects a linked approval directory", async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-host-approval-link-"));
  const projectRoot = path.join(root, "project");
  const stateDir = path.join(projectRoot, ".godot", "godot_codex_bridge", "codex_host");
  const approvalDir = path.join(stateDir, "approvals");
  const outsideRoot = path.join(root, "outside");
  await fs.mkdir(stateDir, { recursive: true });
  await fs.mkdir(outsideRoot, { recursive: true });
  await fs.symlink(outsideRoot, approvalDir, process.platform === "win32" ? "junction" : "dir");

  const gate = new ApprovalGate(approvalDir, () => "off", projectRoot);
  await assert.rejects(() => gate.init(), /link|junction|reparse/i);
  assert.deepEqual(await fs.readdir(outsideRoot), []);
});

test("Host state rejects a project root beneath a linked ancestor", async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-host-root-ancestor-"));
  const outsideRoot = path.join(root, "outside");
  const linkedAncestor = path.join(root, "linked-parent");
  const projectRoot = path.join(linkedAncestor, "project");
  const physicalProjectRoot = path.join(outsideRoot, "project");
  const stateDir = path.join(projectRoot, ".godot", "godot_codex_bridge", "codex_host");
  await fs.mkdir(physicalProjectRoot, { recursive: true });
  await fs.symlink(outsideRoot, linkedAncestor, process.platform === "win32" ? "junction" : "dir");

  const store = new SessionStore(stateDir, 16, projectRoot);
  await assert.rejects(() => store.init(), /root.*(link|junction)|reparse/i);
});

test("Host overwrite rejects a parent replaced after validation and preserves outside content", async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-host-path-race-"));
  const projectRoot = path.join(root, "project");
  const insideDir = path.join(projectRoot, "events");
  const parkedDir = path.join(projectRoot, "events-parked");
  const outsideDir = path.join(root, "outside");
  const target = path.join(insideDir, "state.json");
  await fs.mkdir(insideDir, { recursive: true });
  await fs.mkdir(outsideDir, { recursive: true });
  await fs.writeFile(target, "inside-state", "utf8");
  await fs.writeFile(path.join(outsideDir, "state.json"), "outside-sentinel", "utf8");

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
      () => writeFileInsideRootSync(projectRoot, target, "replacement"),
      (error: unknown) => error instanceof Error && /link|junction|reparse|boundary/i.test(error.message),
    );
    assert.equal(replacementOccurred, true);
    assert.equal(await fs.readFile(path.join(outsideDir, "state.json"), "utf8"), "outside-sentinel");
  } finally {
    fsSync.openSync = originalOpenSync;
    if (replacementOccurred) {
      fsSync.unlinkSync(insideDir);
      fsSync.renameSync(parkedDir, insideDir);
    }
  }
  assert.equal(await fs.readFile(target, "utf8"), "inside-state");
});

test("Host overwrite rejects a hard link that shares an outside file", async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-host-hardlink-"));
  const projectRoot = path.join(root, "project");
  const outsideFile = path.join(root, "outside.txt");
  await fs.mkdir(projectRoot, { recursive: true });
  await fs.writeFile(outsideFile, "keep me\n", "utf8");
  await fs.link(outsideFile, path.join(projectRoot, "session.json"));

  assert.throws(() => writeFileInsideRootSync(projectRoot, path.join(projectRoot, "session.json"), "overwritten"), /hard link/i);
  assert.equal(await fs.readFile(outsideFile, "utf8"), "keep me\n");
});
