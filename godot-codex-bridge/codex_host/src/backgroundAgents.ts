import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import type { CodexRuntimeAdapter } from "./codexRuntime.js";
import { event } from "./codexRuntime.js";
import { buildProjectOrientationBundle } from "./orientationBundle.js";
import type {
  BackgroundCancelParams,
  BackgroundRoleResult,
  BackgroundStartParams,
  BackgroundTaskState,
  BackgroundTaskSummary,
  HostEvent,
  ProjectSummary
} from "./types.js";

type Broadcast = (hostEvent: HostEvent) => Promise<void>;

type ActiveTurn = {
  runtime: CodexRuntimeAdapter;
  threadId: string;
  turnId: string;
};

type RunningTask = {
  summary: BackgroundTaskSummary;
  cancelled: boolean;
  activeTurns: ActiveTurn[];
  runtimes: CodexRuntimeAdapter[];
};

const DEFAULT_ROLES = ["scene_agent", "script_agent", "qa_agent", "safety_agent"];
const ALLOWED_ROLES = new Set([...DEFAULT_ROLES, "lead_summary"]);
const DEFAULT_ROLE_TIMEOUT_MS = 180_000;
const DEFAULT_SUMMARY_TIMEOUT_MS = 60_000;

export class BackgroundAgentManager {
  private readonly tasks = new Map<string, RunningTask>();
  private readonly roleTimeoutMs = readTimeout("GODOT_CODEX_BACKGROUND_ROLE_TIMEOUT_MS", DEFAULT_ROLE_TIMEOUT_MS);
  private readonly summaryTimeoutMs = readTimeout("GODOT_CODEX_BACKGROUND_SUMMARY_TIMEOUT_MS", DEFAULT_SUMMARY_TIMEOUT_MS);

  constructor(
    private readonly project: ProjectSummary,
    private readonly runtime: CodexRuntimeAdapter,
    private readonly broadcast: Broadcast
  ) {}

  activeCount(): number {
    return [...this.tasks.values()].filter((task) => isActiveState(task.summary.state)).length;
  }

  summaries(): BackgroundTaskSummary[] {
    return [...this.tasks.values()].map((task) => cloneSummary(task.summary));
  }

  async start(params: BackgroundStartParams): Promise<BackgroundTaskSummary> {
    const prompt = normalizePrompt(params.prompt);
    const roles = normalizeRoles(params.roles);
    const taskId = `background-${Date.now()}-${crypto.randomBytes(4).toString("hex")}`;
    const taskDir = path.join(this.project.hostStateDir, "background_tasks", taskId);
    const now = new Date().toISOString();
    const task: RunningTask = {
      cancelled: false,
      activeTurns: [],
      runtimes: [],
      summary: {
        task_id: taskId,
        state: "queued",
        prompt,
        roles,
        sandbox: "read-only",
        project_root: this.project.projectRoot,
        task_dir: taskDir,
        created_at: now,
        updated_at: now,
        results: roles.map((role) => ({ role, state: "queued" }))
      }
    };
    this.tasks.set(taskId, task);
    await fs.mkdir(path.join(taskDir, "roles"), { recursive: true });
    await this.writeTask(task);
    await this.emitTask(task);
    void this.runTask(task);
    return cloneSummary(task.summary);
  }

  async cancel(params: BackgroundCancelParams = {}): Promise<{ cancelled: boolean; task_id?: string; active_tasks: number }> {
    const task = params.task_id
      ? this.tasks.get(params.task_id)
      : [...this.tasks.values()].find((candidate) => isActiveState(candidate.summary.state));
    if (!task) {
      return { cancelled: false, active_tasks: this.activeCount() };
    }

    task.cancelled = true;
    task.summary.state = "cancelled";
    task.summary.updated_at = new Date().toISOString();
    task.summary.completed_at = task.summary.updated_at;
    for (const turn of [...task.activeTurns]) {
      await turn.runtime.interruptTurn(turn.threadId, turn.turnId).catch(() => undefined);
    }
    for (const result of task.summary.results) {
      if (result.state === "queued" || result.state === "running") {
        result.state = "cancelled";
        result.completed_at = task.summary.completed_at;
      }
    }
    await this.writeTask(task);
    await this.emitTask(task);
    return { cancelled: true, task_id: task.summary.task_id, active_tasks: this.activeCount() };
  }

  async shutdown(): Promise<void> {
    for (const task of this.tasks.values()) {
      task.cancelled = true;
      await Promise.all(task.runtimes.map((runtime) => runtime.shutdown().catch(() => undefined)));
    }
    this.tasks.clear();
  }

  private async runTask(task: RunningTask): Promise<void> {
    try {
      await this.updateTaskState(task, "running");
      const results = await Promise.all(task.summary.roles.map((role, index) => this.runRole(task, role, index)));
      task.summary.results = results;

      if (task.cancelled) {
        await this.updateTaskState(task, "cancelled", true);
        return;
      }

      await this.updateTaskState(task, "summarizing");
      task.summary.summary = await this.summarize(task);
      task.summary.summary_path = path.join(task.summary.task_dir, "summary.md");
      await fs.writeFile(task.summary.summary_path, task.summary.summary, "utf8");
      const failed = results.filter((result) => result.state === "failed");
      if (failed.length > 0) {
        task.summary.error = `${failed.length} background role(s) failed; partial summary written`;
        await this.updateTaskState(task, "failed", true);
        return;
      }
      await this.updateTaskState(task, "completed", true);
    } catch (error) {
      task.summary.error = (error as Error).message;
      await this.updateTaskState(task, task.cancelled ? "cancelled" : "failed", true);
    } finally {
      for (const runtime of task.runtimes) {
        await runtime.shutdown().catch(() => undefined);
      }
    }
  }

  private async runRole(task: RunningTask, role: string, index: number): Promise<BackgroundRoleResult> {
    const runtime = this.runtime.createBackgroundRuntime?.(index) ?? this.runtime;
    task.runtimes.push(runtime);
    const result: BackgroundRoleResult = {
      role,
      state: "running",
      started_at: new Date().toISOString(),
      warnings: []
    };
    this.replaceRoleResult(task, result);
    await this.writeTask(task);
    await this.emitTask(task);

    let text = "";
    try {
      const deadline = Date.now() + this.roleTimeoutMs;
      const thread = await withDeadline(runtime.startThread({
        projectRoot: this.project.projectRoot,
        sandbox: "read-only",
        background: true
      }), deadline, `${role}_thread_start_timeout`);
      const orientation = await buildProjectOrientationBundle(this.project, null);
      result.thread_id = thread.threadId;
      const input = {
        threadId: thread.threadId,
        projectRoot: this.project.projectRoot,
        message: [
          rolePrompt(role, task.summary.prompt, this.project.projectRoot),
          "",
          orientation
        ].join("\n"),
        attachments: {
          context_snapshot: true,
          selected_nodes: true,
          gameplay_context: true,
          script_inventory: true
        }
      };

      const iterator = runtime.runTurn(input)[Symbol.asyncIterator]();
      while (true) {
        const next = await withDeadline(iterator.next(), deadline, `${role}_turn_timeout`);
        if (next.done) {
          break;
        }
        const runtimeEvent = next.value;
        if (task.cancelled) {
          if (result.thread_id && result.turn_id) {
            await runtime.interruptTurn(result.thread_id, result.turn_id).catch(() => undefined);
          }
          result.state = "cancelled";
          break;
        }
        if (runtimeEvent.method === "turn.started") {
          result.turn_id = String(runtimeEvent.params.turn_id ?? "");
          if (result.turn_id) {
            task.activeTurns.push({ runtime, threadId: thread.threadId, turnId: result.turn_id });
          }
        } else if (runtimeEvent.method === "turn.event" && runtimeEvent.params.event === "agent_message_delta") {
          text += String(runtimeEvent.params.text ?? "");
        } else if (runtimeEvent.method === "runtime.warning") {
          result.warnings?.push(String(runtimeEvent.params.message ?? "runtime warning"));
        } else if (runtimeEvent.method === "approval.requested") {
          const approvalId = String(runtimeEvent.params.runtime_approval_id ?? "");
          if (approvalId) {
            await runtime.respondToApproval(approvalId, "reject").catch(() => undefined);
          }
          result.warnings?.push("Background role requested approval; denied by read-only policy.");
        } else if (runtimeEvent.method === "error") {
          throw new Error(String(runtimeEvent.params.message ?? "background_runtime_error"));
        } else if (runtimeEvent.method === "turn.completed") {
          result.state = "completed";
        } else if (runtimeEvent.method === "turn.interrupted") {
          result.state = "cancelled";
        }
      }
      if (result.state === "running") {
        result.state = task.cancelled ? "cancelled" : "completed";
      }
      result.output = text.trim();
    } catch (error) {
      result.state = task.cancelled ? "cancelled" : "failed";
      result.error = (error as Error).message;
      if (!task.cancelled && result.thread_id && result.turn_id) {
        await runtime.interruptTurn(result.thread_id, result.turn_id).catch(() => undefined);
      }
      if (!task.cancelled) {
        await runtime.shutdown().catch(() => undefined);
      }
    } finally {
      result.completed_at = new Date().toISOString();
      if (result.turn_id) {
        task.activeTurns = task.activeTurns.filter((turn) => turn.turnId !== result.turn_id);
      }
      result.artifact_path = path.join(task.summary.task_dir, "roles", `${safeFileName(role)}.json`);
      await fs.writeFile(result.artifact_path, `${JSON.stringify(result, null, 2)}\n`, "utf8");
      this.replaceRoleResult(task, result);
      task.summary.updated_at = new Date().toISOString();
      await this.writeTask(task);
      await this.emitTask(task);
    }
    return result;
  }

  private async summarize(task: RunningTask): Promise<string> {
    const roleBlocks = task.summary.results.map((result) => [
      `## ${result.role}`,
      result.output || result.error || "No output.",
      result.warnings && result.warnings.length > 0 ? `Warnings: ${result.warnings.join("; ")}` : ""
    ].filter(Boolean).join("\n\n")).join("\n\n");

    const summaryRuntime = this.runtime.createBackgroundRuntime?.(task.summary.roles.length) ?? null;
    if (!summaryRuntime) {
      return deterministicSummary(task.summary, roleBlocks);
    }
    task.runtimes.push(summaryRuntime);
    try {
      const deadline = Date.now() + this.summaryTimeoutMs;
      const thread = await withDeadline(summaryRuntime.startThread({
        projectRoot: this.project.projectRoot,
        sandbox: "read-only",
        background: true
      }), deadline, "summary_thread_start_timeout");
      let text = "";
      const iterator = summaryRuntime.runTurn({
        threadId: thread.threadId,
        projectRoot: this.project.projectRoot,
        message: [
          "Summarize this Godot background team review for the user.",
          "Do not propose applying files silently. Keep recommendations safe and concrete.",
          "",
          `Original task: ${task.summary.prompt}`,
          "",
          roleBlocks
        ].join("\n"),
        attachments: { context_snapshot: true }
      })[Symbol.asyncIterator]();
      while (true) {
        const next = await withDeadline(iterator.next(), deadline, "summary_turn_timeout");
        if (next.done) {
          break;
        }
        const runtimeEvent = next.value;
        if (runtimeEvent.method === "turn.event" && runtimeEvent.params.event === "agent_message_delta") {
          text += String(runtimeEvent.params.text ?? "");
        } else if (runtimeEvent.method === "approval.requested") {
          const approvalId = String(runtimeEvent.params.runtime_approval_id ?? "");
          if (approvalId) {
            await summaryRuntime.respondToApproval(approvalId, "reject").catch(() => undefined);
          }
        }
      }
      return text.trim() || deterministicSummary(task.summary, roleBlocks);
    } catch {
      return deterministicSummary(task.summary, roleBlocks);
    }
  }

  private replaceRoleResult(task: RunningTask, result: BackgroundRoleResult): void {
    const index = task.summary.results.findIndex((candidate) => candidate.role === result.role);
    if (index >= 0) {
      task.summary.results[index] = result;
    } else {
      task.summary.results.push(result);
    }
  }

  private async updateTaskState(task: RunningTask, state: BackgroundTaskState, completed = false): Promise<void> {
    task.summary.state = state;
    task.summary.updated_at = new Date().toISOString();
    if (completed) {
      task.summary.completed_at = task.summary.updated_at;
    }
    await this.writeTask(task);
    await this.emitTask(task);
  }

  private async emitTask(task: RunningTask): Promise<void> {
    await this.broadcast(event("background.updated", cloneSummary(task.summary) as unknown as Record<string, unknown>));
  }

  private async writeTask(task: RunningTask): Promise<void> {
    await fs.mkdir(task.summary.task_dir, { recursive: true });
    await fs.writeFile(path.join(task.summary.task_dir, "task.json"), `${JSON.stringify(task.summary, null, 2)}\n`, "utf8");
  }
}

function normalizePrompt(prompt: string): string {
  const normalized = typeof prompt === "string" ? prompt.trim() : "";
  if (!normalized) {
    return "Review the current Godot project and summarize useful next steps.";
  }
  return normalized.slice(0, 8000);
}

function readTimeout(name: string, fallback: number): number {
  const raw = process.env[name];
  if (!raw) {
    return fallback;
  }
  const value = Number.parseInt(raw, 10);
  return Number.isFinite(value) && value > 0 ? value : fallback;
}

async function withDeadline<T>(promise: Promise<T>, deadline: number, message: string): Promise<T> {
  const remaining = Math.max(deadline - Date.now(), 0);
  if (remaining <= 0) {
    throw new Error(message);
  }
  let timer: NodeJS.Timeout | undefined;
  try {
    return await Promise.race([
      promise,
      new Promise<never>((_resolve, reject) => {
        timer = setTimeout(() => reject(new Error(message)), remaining);
        timer.unref();
      })
    ]);
  } finally {
    if (timer) {
      clearTimeout(timer);
    }
  }
}

function normalizeRoles(roles: string[] | undefined): string[] {
  const normalized = (roles && roles.length > 0 ? roles : DEFAULT_ROLES)
    .map((role) => String(role).trim())
    .filter((role) => ALLOWED_ROLES.has(role));
  return normalized.length > 0 ? [...new Set(normalized)].slice(0, 6) : [...DEFAULT_ROLES];
}

function isActiveState(state: BackgroundTaskState): boolean {
  return state === "queued" || state === "running" || state === "summarizing";
}

function rolePrompt(role: string, userPrompt: string, projectRoot: string): string {
  const roleBriefs: Record<string, string> = {
    scene_agent: "Inspect scene structure, camera framing, lights, materials, colliders, navmesh and 3D diagnostics.",
    script_agent: "Inspect gameplay scripts, input actions, autoloads, Godot API usage, TODO/FIXME markers and testability.",
    qa_agent: "Inspect validation options: scene/test commands, screenshots, visual regression, export readiness and smoke tests.",
    safety_agent: "Review safety: path boundaries, proposed changes, approval gates, secrets, screenshots and local-only evidence.",
    lead_summary: "Summarize specialist findings into a concise implementation plan."
  };
  return [
    `You are ${role} for a Godot Codex Bridge background team review.`,
    roleBriefs[role] ?? "Review the Godot project from your specialist perspective.",
    `Project root: ${projectRoot}`,
    "Rules: read-only only; do not request writes, shell escalation, network, approvals or external uploads.",
    "Use available project files and Godot bridge context if the runtime exposes them.",
    "Return concrete findings, risks, and safe next actions. Keep it concise.",
    "",
    `User request: ${userPrompt}`
  ].join("\n");
}

function deterministicSummary(task: BackgroundTaskSummary, roleBlocks: string): string {
  return [
    `# Background Team Review ${task.task_id}`,
    "",
    `Prompt: ${task.prompt}`,
    "",
    "## Specialist Findings",
    "",
    roleBlocks,
    "",
    "## Safe Next Step",
    "",
    "Review these findings in Godot before approving any write, scene mutation or export action."
  ].join("\n");
}

function cloneSummary(summary: BackgroundTaskSummary): BackgroundTaskSummary {
  return JSON.parse(JSON.stringify(summary)) as BackgroundTaskSummary;
}

function safeFileName(value: string): string {
  return value.replace(/[^a-zA-Z0-9._-]/g, "_");
}
