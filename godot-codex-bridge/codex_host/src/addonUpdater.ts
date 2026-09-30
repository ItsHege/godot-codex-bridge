import { spawn } from "node:child_process";
import { randomUUID } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { writeFileInsideRootSync } from "./physicalPath.js";

// See contracts/ADDON_UPDATE_V1.md. The build source, updater script and
// channel always come from this Host's own product checkout, never from the
// project or the request.

export type AddonUpdateState =
  | "current" | "update_available" | "unmanaged" | "drifted" | "different_channel"
  | "channel_unpublished" | "source_unpublished" | "wrong_project_root" | "updater_unavailable";

export type AddonUpdateCheck = {
  state: AddonUpdateState;
  installed_build_id: string;
  available_build_id: string;
  available_version: string;
  published_at: string;
  source_matches_channel: boolean;
  pending: { update_id: string; build_id: string } | null;
  message?: string;
};

export type ScriptResult = { code: number | null; stdout: string; stderr: string };

export type AddonUpdaterOptions = {
  productRoot?: string;
  platform?: NodeJS.Platform;
  runScript?: (scriptPath: string, args: string[], timeoutMs: number) => Promise<ScriptResult>;
  isAlive?: (pid: number) => boolean;
  launch?: (executable: string, args: string[]) => void;
  sleep?: (ms: number) => Promise<void>;
  exitTimeoutMs?: number;
  activeEditorRetryMs?: number;
  pollMs?: number;
};

type Pending = {
  updateId: string;
  buildId: string;
  fromBuildId: string;
  projectRoot: string;
  bridgeDir: string;
  editorPid: number;
  godotExecutable: string;
  cancelled: boolean;
  installing: boolean;
};

const ACTIVE_EDITOR_MARKER = "while the Godot editor is active";
const STATUS_TIMEOUT_MS = 60_000;
const UPDATE_TIMEOUT_MS = 5 * 60_000;

export class AddonUpdater {
  private readonly productRoot: string;
  private readonly platform: NodeJS.Platform;
  private readonly runScript: (scriptPath: string, args: string[], timeoutMs: number) => Promise<ScriptResult>;
  private readonly isAlive: (pid: number) => boolean;
  private readonly launch: (executable: string, args: string[]) => void;
  private readonly sleep: (ms: number) => Promise<void>;
  private readonly exitTimeoutMs: number;
  private readonly activeEditorRetryMs: number;
  private readonly pollMs: number;
  private pending: Pending | null = null;
  /** Resolves when the scheduled update finishes; exposed for tests. */
  running: Promise<void> | null = null;

  constructor(options: AddonUpdaterOptions = {}) {
    this.productRoot = options.productRoot ?? defaultProductRoot();
    this.platform = options.platform ?? process.platform;
    this.runScript = options.runScript ?? runWindowsPowerShell;
    this.isAlive = options.isAlive ?? processIsAlive;
    this.launch = options.launch ?? launchDetached;
    this.sleep = options.sleep ?? ((ms) => new Promise((resolve) => setTimeout(resolve, ms)));
    this.exitTimeoutMs = options.exitTimeoutMs ?? 30 * 60_000;
    this.activeEditorRetryMs = options.activeEditorRetryMs ?? 60_000;
    this.pollMs = options.pollMs ?? 1_000;
  }

  private get scriptPath(): string {
    return path.join(this.productRoot, "scripts", "gc_work.ps1");
  }

  async check(projectRoot: string): Promise<AddonUpdateCheck> {
    // Only report a pending update to the project it belongs to.
    const pending = this.pending && !this.pending.cancelled && samePath(this.pending.projectRoot, projectRoot)
      ? { update_id: this.pending.updateId, build_id: this.pending.buildId }
      : null;
    const empty = { installed_build_id: "", available_build_id: "", available_version: "", published_at: "", source_matches_channel: false, pending };
    if (this.platform !== "win32" || !fs.existsSync(this.scriptPath)) {
      return { ...empty, state: "updater_unavailable", message: "The Host checkout has no Windows GC-work updater." };
    }
    const result = await this.runScript(this.scriptPath, ["-Action", "Status", "-ProjectRoot", projectRoot], STATUS_TIMEOUT_MS);
    const status = parseJsonObject(result.stdout);
    const project = Array.isArray(status?.projects) ? objectValue(status.projects[0]) : null;
    if (result.code !== 0 || !status || !project) {
      return { ...empty, state: "updater_unavailable", message: firstLine(result.stderr) || "GC-work status failed." };
    }
    const channel = objectValue(status.channel) ?? {};
    const availableBuild = stringValue(channel.build_id);
    const sourceMatches = availableBuild !== "" && stringValue(status.source_build_id) === availableBuild;
    let state = stringValue(project.state) as AddonUpdateState;
    // Only the exact published build is installable; a changed checkout must be
    // reviewed and published first.
    if (state === "update_available" && !sourceMatches) state = "source_unpublished";
    return {
      state,
      installed_build_id: stringValue(project.installed_build_id),
      available_build_id: availableBuild,
      available_version: stringValue(channel.addon_version),
      published_at: stringValue(channel.published_at),
      source_matches_channel: sourceMatches,
      pending,
    };
  }

  async schedule(
    projectRoot: string,
    bridgeDir: string,
    params: { build_id?: unknown; editor_pid?: unknown; godot_executable?: unknown },
  ): Promise<{ scheduled: true; update_id: string; build_id: string }> {
    const buildId = stringValue(params.build_id);
    const editorPid = Number(params.editor_pid);
    const executable = stringValue(params.godot_executable);
    if (!Number.isSafeInteger(editorPid) || editorPid <= 0 || !this.isAlive(editorPid)) {
      throw new Error("addon_update_invalid_editor_pid: editor_pid must be the running editor process.");
    }
    validateGodotExecutable(executable, projectRoot, this.platform);
    const check = await this.check(projectRoot);
    if (check.state !== "update_available") {
      throw new Error(`addon_update_not_available: ${check.state}`);
    }
    if (buildId !== check.available_build_id) {
      throw new Error("addon_update_build_mismatch: the confirmed build is no longer the published build; check again.");
    }
    if (this.pending?.installing) {
      throw new Error("addon_update_busy: an update is being installed.");
    }
    if (this.pending) this.pending.cancelled = true;
    const pending: Pending = {
      updateId: randomUUID(), buildId, fromBuildId: check.installed_build_id,
      projectRoot, bridgeDir, editorPid, godotExecutable: executable, cancelled: false, installing: false,
    };
    this.pending = pending;
    this.running = this.run(pending);
    return { scheduled: true, update_id: pending.updateId, build_id: buildId };
  }

  cancel(): { cancelled: boolean; reason?: string } {
    if (!this.pending || this.pending.cancelled) return { cancelled: false };
    if (this.pending.installing) return { cancelled: false, reason: "installing" };
    this.pending.cancelled = true;
    return { cancelled: true };
  }

  /** True while an update is scheduled or installing; the Host defers shutdown. */
  isBusy(): boolean {
    return this.pending !== null && !this.pending.cancelled;
  }

  private async run(pending: Pending): Promise<void> {
    const outcome = await this.install(pending).catch((error: Error) => ({ status: "failed" as const, error: error.message }));
    if (this.pending === pending) this.pending = null;
    if (outcome.status === "superseded") return;
    this.writeResult(pending, outcome);
    // Never open a second editor: a failure because an editor is already
    // running means the project is open again (reload, manual reopen).
    const editorAlreadyOpen = outcome.status === "failed" && "error" in outcome && outcome.error.includes(ACTIVE_EDITOR_MARKER);
    if (outcome.status !== "cancelled" && !editorAlreadyOpen) {
      try {
        this.launch(pending.godotExecutable, ["--editor", "--path", pending.projectRoot]);
      } catch {
        // The result file still records the install outcome.
      }
    }
  }

  private async install(pending: Pending): Promise<
    { status: "installed"; backupPath: string | null; toBuildId: string }
    | { status: "failed" | "cancelled" | "superseded"; error: string }
  > {
    const exitDeadline = Date.now() + this.exitTimeoutMs;
    while (this.isAlive(pending.editorPid)) {
      if (pending.cancelled) return { status: this.pending === pending ? "cancelled" : "superseded", error: "Update cancelled before Godot closed." };
      if (Date.now() > exitDeadline) return { status: "cancelled", error: "Godot did not close within 30 minutes; update cancelled." };
      await this.sleep(this.pollMs);
    }
    pending.installing = true;
    const retryDeadline = Date.now() + this.activeEditorRetryMs;
    for (;;) {
      const result = await this.runScript(this.scriptPath, ["-Action", "Update", "-ProjectRoot", pending.projectRoot], UPDATE_TIMEOUT_MS);
      if (result.code === 0) {
        const report = parseJsonObject(result.stdout);
        const update = Array.isArray(report?.updates) ? objectValue(report.updates[0]) : null;
        return {
          status: "installed",
          backupPath: update && typeof update.backup_path === "string" ? update.backup_path : null,
          toBuildId: stringValue(update?.installed_build_id) || pending.buildId,
        };
      }
      const error = firstLine(result.stderr) || firstLine(result.stdout) || `GC-work update exited with ${result.code}`;
      // The editor heartbeat stays fresh for a few seconds after exit.
      if (!(result.stderr + result.stdout).includes(ACTIVE_EDITOR_MARKER) || Date.now() > retryDeadline) {
        return { status: "failed", error };
      }
      await this.sleep(Math.max(this.pollMs, 2_000));
    }
  }

  private writeResult(pending: Pending, outcome: { status: string; error?: string; backupPath?: string | null; toBuildId?: string }): void {
    const payload = {
      update_id: pending.updateId,
      status: outcome.status,
      from_build_id: pending.fromBuildId,
      to_build_id: outcome.status === "installed" ? outcome.toBuildId ?? pending.buildId : pending.buildId,
      backup_path: outcome.backupPath ?? null,
      error: outcome.error ?? null,
      finished_at: new Date().toISOString(),
    };
    const target = path.join(pending.bridgeDir, "addon_update_result.json");
    try {
      writeFileInsideRootSync(pending.projectRoot, target, `${JSON.stringify(payload, null, 2)}\n`);
    } catch {
      // Never let evidence writing break the Host.
    }
  }
}

export function validateGodotExecutable(executable: string, projectRoot: string, platform: NodeJS.Platform = process.platform): void {
  if (!executable || !path.isAbsolute(executable)) {
    throw new Error("addon_update_invalid_executable: godot_executable must be an absolute path.");
  }
  if (platform === "win32" && !/\.exe$/i.test(executable)) {
    throw new Error("addon_update_invalid_executable: godot_executable must be an .exe.");
  }
  const relative = path.relative(path.resolve(projectRoot), path.resolve(executable));
  if (relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative))) {
    throw new Error("addon_update_invalid_executable: godot_executable cannot be inside the project.");
  }
  if (!fs.existsSync(executable) || !fs.statSync(executable).isFile()) {
    throw new Error("addon_update_invalid_executable: godot_executable does not exist.");
  }
}

function defaultProductRoot(): string {
  // dist/src/addonUpdater.js -> codex_host -> product root.
  return path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..", "..");
}

function runWindowsPowerShell(scriptPath: string, args: string[], timeoutMs: number): Promise<ScriptResult> {
  // Absolute paths only, never PATH. Prefer PowerShell 7 (what publishes and
  // installs builds); fall back to the System32 Windows PowerShell.
  const pwsh7 = path.win32.join(process.env.ProgramFiles ?? "C:\\Program Files", "PowerShell", "7", "pwsh.exe");
  const powershell = fs.existsSync(pwsh7)
    ? pwsh7
    : path.win32.join(process.env.SystemRoot ?? "C:\\Windows", "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
  // A PSModulePath inherited from PowerShell 7 makes Windows PowerShell 5.1
  // load incompatible modules (Get-FileHash disappears); let it rebuild its own.
  const env = { ...process.env };
  delete env.PSModulePath;
  return new Promise((resolve) => {
    const child = spawn(powershell, ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", scriptPath, ...args], {
      stdio: ["ignore", "pipe", "pipe"],
      windowsHide: true,
      env,
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { if (stdout.length < 1_000_000) stdout += String(chunk); });
    child.stderr.on("data", (chunk) => { if (stderr.length < 100_000) stderr += String(chunk); });
    // A hung updater (e.g. a slow or linked tree) must not block the Host.
    const timer = setTimeout(() => {
      stderr = `GC-work updater timed out after ${timeoutMs} ms. ${stderr}`;
      child.kill();
    }, timeoutMs);
    child.on("error", (error) => { clearTimeout(timer); resolve({ code: -1, stdout, stderr: error.message }); });
    child.on("close", (code) => { clearTimeout(timer); resolve({ code, stdout, stderr }); });
  });
}

function processIsAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return (error as NodeJS.ErrnoException).code === "EPERM";
  }
}

function launchDetached(executable: string, args: string[]): void {
  const child = spawn(executable, args, { detached: true, stdio: "ignore" });
  child.on("error", () => undefined);
  child.unref();
}

function samePath(a: string, b: string): boolean {
  const left = path.resolve(a);
  const right = path.resolve(b);
  return process.platform === "win32" ? left.toLowerCase() === right.toLowerCase() : left === right;
}

function parseJsonObject(text: string): Record<string, unknown> | null {
  try {
    return objectValue(JSON.parse(text));
  } catch {
    return null;
  }
}

function objectValue(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : null;
}

function stringValue(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function firstLine(text: string): string {
  return text.split(/\r?\n/).map((line) => line.trim()).find(Boolean)?.slice(0, 500) ?? "";
}
