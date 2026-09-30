import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { AddonUpdater, validateGodotExecutable, type ScriptResult } from "../src/addonUpdater.js";

const AVAILABLE = "sha256:" + "b".repeat(64);
const INSTALLED = "sha256:" + "a".repeat(64);

async function fixture() {
  const base = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-addon-update-"));
  const productRoot = path.join(base, "product");
  const projectRoot = path.join(base, "project");
  const bridgeDir = path.join(projectRoot, ".godot", "godot_codex_bridge");
  await fs.mkdir(path.join(productRoot, "scripts"), { recursive: true });
  await fs.writeFile(path.join(productRoot, "scripts", "gc_work.ps1"), "# fake\n", "utf8");
  await fs.mkdir(bridgeDir, { recursive: true });
  await fs.writeFile(path.join(projectRoot, "project.godot"), "[application]\n", "utf8");
  const godot = path.join(base, "tools", "Godot.exe");
  await fs.mkdir(path.dirname(godot), { recursive: true });
  await fs.writeFile(godot, "", "utf8");
  return { base, productRoot, projectRoot, bridgeDir, godot };
}

function statusJson(state: string, sourceBuild = AVAILABLE): string {
  return JSON.stringify({
    status: "ok",
    channel: { build_id: AVAILABLE, addon_version: "0.1.0", published_at: "2026-09-30T00:00:00Z" },
    source_build_id: sourceBuild,
    projects: [{ state, installed_build_id: INSTALLED }],
  });
}

function harness(options: { state?: string; sourceBuild?: string; updateResults?: ScriptResult[] } = {}) {
  const calls: string[][] = [];
  const launches: Array<{ exe: string; args: string[] }> = [];
  const alive = new Set<number>([4242]);
  const updateResults = [...(options.updateResults ?? [{ code: 0, stdout: JSON.stringify({ updates: [{ backup_path: "C:/backup", installed_build_id: AVAILABLE }] }), stderr: "" }])];
  return {
    calls, launches, alive,
    options: {
      platform: "win32" as const,
      runScript: async (_script: string, args: string[], _timeoutMs: number) => {
        calls.push(args);
        if (args[1] === "Status") return { code: 0, stdout: statusJson(options.state ?? "update_available", options.sourceBuild), stderr: "" };
        return updateResults.shift() ?? { code: 1, stdout: "", stderr: "no more results" };
      },
      isAlive: (pid: number) => alive.has(pid),
      launch: (exe: string, args: string[]) => { launches.push({ exe, args }); },
      sleep: async () => { alive.clear(); },
      pollMs: 1,
    },
  };
}

test("addon update check reports update_available only when the source is the published build", async () => {
  const f = await fixture();
  const ok = harness();
  const updater = new AddonUpdater({ productRoot: f.productRoot, ...ok.options });
  const check = await updater.check(f.projectRoot);
  assert.equal(check.state, "update_available");
  assert.equal(check.available_build_id, AVAILABLE);
  assert.equal(check.source_matches_channel, true);

  const drifted = harness({ sourceBuild: "sha256:" + "c".repeat(64) });
  const unpublished = await new AddonUpdater({ productRoot: f.productRoot, ...drifted.options }).check(f.projectRoot);
  assert.equal(unpublished.state, "source_unpublished");

  const linux = await new AddonUpdater({ productRoot: f.productRoot, ...ok.options, platform: "linux" }).check(f.projectRoot);
  assert.equal(linux.state, "updater_unavailable");
});

test("scheduled update waits for the editor to exit, installs, records the result and reopens the project", async () => {
  const f = await fixture();
  const h = harness();
  const updater = new AddonUpdater({ productRoot: f.productRoot, ...h.options });
  const scheduled = await updater.schedule(f.projectRoot, f.bridgeDir, { build_id: AVAILABLE, editor_pid: 4242, godot_executable: f.godot });
  assert.equal(scheduled.scheduled, true);
  await updater.running;

  assert.deepEqual(h.calls.map((args) => args[1]), ["Status", "Update"]);
  assert.deepEqual(h.calls[1], ["-Action", "Update", "-ProjectRoot", f.projectRoot]);
  const result = JSON.parse(await fs.readFile(path.join(f.bridgeDir, "addon_update_result.json"), "utf8"));
  assert.equal(result.update_id, scheduled.update_id);
  assert.equal(result.status, "installed");
  assert.equal(result.from_build_id, INSTALLED);
  assert.equal(result.to_build_id, AVAILABLE);
  assert.equal(result.backup_path, "C:/backup");
  assert.deepEqual(h.launches, [{ exe: f.godot, args: ["--editor", "--path", f.projectRoot] }]);
});

test("update retries while the editor heartbeat is still fresh, then reports a real failure and reopens", async () => {
  const f = await fixture();
  const active = { code: 1, stdout: "", stderr: "Refusing automatic GC-work update while the Godot editor is active: X" };
  const h = harness({ updateResults: [active, { code: 1, stdout: "", stderr: "Refusing automatic GC-work update because the preview would remove addon files" }] });
  const updater = new AddonUpdater({ productRoot: f.productRoot, ...h.options });
  await updater.schedule(f.projectRoot, f.bridgeDir, { build_id: AVAILABLE, editor_pid: 4242, godot_executable: f.godot });
  await updater.running;
  assert.deepEqual(h.calls.map((args) => args[1]), ["Status", "Update", "Update"]);
  const result = JSON.parse(await fs.readFile(path.join(f.bridgeDir, "addon_update_result.json"), "utf8"));
  assert.equal(result.status, "failed");
  assert.match(result.error, /remove addon files/);
  assert.equal(h.launches.length, 1);
});

test("cancelled update never installs or reopens", async () => {
  const f = await fixture();
  const h = harness();
  let release!: () => void;
  const updater = new AddonUpdater({
    productRoot: f.productRoot, ...h.options,
    sleep: () => new Promise<void>((resolve) => { release = resolve; }),
  });
  await updater.schedule(f.projectRoot, f.bridgeDir, { build_id: AVAILABLE, editor_pid: 4242, godot_executable: f.godot });
  assert.deepEqual(updater.cancel(), { cancelled: true });
  release();
  await updater.running;
  assert.deepEqual(h.calls.map((args) => args[1]), ["Status"]);
  const result = JSON.parse(await fs.readFile(path.join(f.bridgeDir, "addon_update_result.json"), "utf8"));
  assert.equal(result.status, "cancelled");
  assert.equal(h.launches.length, 0);
});

test("schedule refuses a stale build, a dead editor, and executables inside the project", async () => {
  const f = await fixture();
  const h = harness();
  const updater = new AddonUpdater({ productRoot: f.productRoot, ...h.options });
  await assert.rejects(updater.schedule(f.projectRoot, f.bridgeDir, { build_id: INSTALLED, editor_pid: 4242, godot_executable: f.godot }), /build_mismatch/);
  await assert.rejects(updater.schedule(f.projectRoot, f.bridgeDir, { build_id: AVAILABLE, editor_pid: 999, godot_executable: f.godot }), /invalid_editor_pid/);
  const inside = path.join(f.projectRoot, "tools", "Godot.exe");
  await fs.mkdir(path.dirname(inside), { recursive: true });
  await fs.writeFile(inside, "", "utf8");
  assert.throws(() => validateGodotExecutable(inside, f.projectRoot, "win32"), /inside the project/);
  assert.throws(() => validateGodotExecutable("Godot.exe", f.projectRoot, "win32"), /absolute/);
  assert.throws(() => validateGodotExecutable(path.join(f.base, "tools", "run.cmd"), f.projectRoot, "win32"), /\.exe/);

  const current = harness({ state: "current" });
  await assert.rejects(
    new AddonUpdater({ productRoot: f.productRoot, ...current.options }).schedule(f.projectRoot, f.bridgeDir, { build_id: AVAILABLE, editor_pid: 4242, godot_executable: f.godot }),
    /not_available: current/,
  );
});

test("an update blocked by a reopened editor does not open a second editor", async () => {
  const f = await fixture();
  const active = { code: 1, stdout: "", stderr: "Refusing automatic GC-work update while the Godot editor is active: X" };
  const h = harness({ updateResults: Array.from({ length: 50 }, () => active) });
  const updater = new AddonUpdater({ productRoot: f.productRoot, ...h.options, activeEditorRetryMs: 0 });
  await updater.schedule(f.projectRoot, f.bridgeDir, { build_id: AVAILABLE, editor_pid: 4242, godot_executable: f.godot });
  await updater.running;
  const result = JSON.parse(await fs.readFile(path.join(f.bridgeDir, "addon_update_result.json"), "utf8"));
  assert.equal(result.status, "failed");
  assert.equal(h.launches.length, 0);
});

test("pending is reported only to its own project and cancel is refused once installing", async () => {
  const f = await fixture();
  const h = harness();
  let startInstall!: () => void;
  let installing!: () => void;
  const installStarted = new Promise<void>((resolve) => { installing = resolve; });
  const updater = new AddonUpdater({
    productRoot: f.productRoot, ...h.options,
    isAlive: () => false,
    runScript: async (script, args, timeoutMs) => {
      if (args[1] === "Update") {
        installing();
        await new Promise<void>((resolve) => { startInstall = resolve; });
      }
      return h.options.runScript(script, args, timeoutMs);
    },
  });
  // Schedule checks liveness first, so allow it once.
  let first = true;
  (updater as unknown as { isAlive: (pid: number) => boolean }).isAlive = () => { const alive = first; first = false; return alive; };
  const scheduled = await updater.schedule(f.projectRoot, f.bridgeDir, { build_id: AVAILABLE, editor_pid: 4242, godot_executable: f.godot });
  assert.equal((await updater.check(f.projectRoot)).pending?.update_id, scheduled.update_id);
  assert.equal((await updater.check(path.join(f.base, "other"))).pending, null);
  await installStarted;
  assert.equal(updater.isBusy(), true);
  assert.deepEqual(updater.cancel(), { cancelled: false, reason: "installing" });
  startInstall();
  await updater.running;
  assert.equal(updater.isBusy(), false);
});