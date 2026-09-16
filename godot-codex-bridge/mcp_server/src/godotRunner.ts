import fs from "node:fs";
import fsp from "node:fs/promises";
import path from "node:path";
import { execFile } from "node:child_process";

import { boundedNumber, isInsidePath } from "./config.js";
import type { JsonObject, ServerConfig } from "./types.js";

const SCENE_EXTENSIONS = new Set([".tscn", ".scn"]);
const SUMMARY_LIMIT = 8_000;
const RUNTIME_SAMPLE_LIMIT = 5;
const RUNTIME_SAMPLE_LINE_LIMIT = 500;
const MIN_QUIT_AFTER_ITERATIONS = 60;

export interface RunTestSceneOptions {
  scenePath: string;
  timeoutMs?: number;
}

export interface RunProjectParseCheckOptions {
  timeoutMs?: number;
}

export async function runProjectParseCheck(config: ServerConfig, options: RunProjectParseCheckOptions = {}): Promise<JsonObject> {
  const timeoutMs = boundedNumber(options.timeoutMs ?? config.runSceneTimeoutMs, 1_000, 60_000);

  if (!fs.existsSync(config.godotExecutable)) {
    return {
      status: "not_run",
      validation_status: "not_run",
      check_kind: "godot_headless_check_only",
      error: {
        code: "godot_executable_unavailable",
        message: "Configured Godot executable does not exist. Set the GODOT_BIN environment variable or ensure Godot is on your PATH.",
        godot_executable: config.godotExecutable,
      },
    };
  }

  if (!fs.existsSync(path.join(config.projectRoot, "project.godot"))) {
    return {
      status: "invalid_request",
      validation_status: "not_run",
      check_kind: "godot_headless_check_only",
      error: {
        code: "project_godot_missing",
        message: "Configured project root does not contain project.godot.",
        project_root: config.projectRoot,
      },
    };
  }

  const args = [
    "--headless",
    "--path",
    config.projectRoot,
    "--check-only",
    "--quit",
  ];

  const startedAt = Date.now();
  const result = await execFileCapture(config.godotExecutable, args, timeoutMs, config.projectRoot);
  const durationMs = Date.now() - startedAt;
  const logPath = await writeRunLog(config, {
    command: config.godotExecutable,
    args,
    check_kind: "godot_headless_check_only",
    timeout_ms: timeoutMs,
    duration_ms: durationMs,
    ...result,
  }, "post-save-check");

  return {
    status: result.timed_out ? "timeout" : result.exit_code === 0 ? "ok" : "error",
    validation_status: result.timed_out ? "timeout" : result.exit_code === 0 ? "passed" : "failed",
    check_kind: "godot_headless_check_only",
    exit_code: result.exit_code,
    signal: result.signal,
    timed_out: result.timed_out,
    duration_ms: durationMs,
    runtime_summary: buildRuntimeSummary({
      scenePath: "res://",
      exitCode: result.exit_code,
      signal: result.signal,
      timedOut: result.timed_out,
      durationMs,
      stdout: result.stdout,
      stderr: result.stderr,
    }),
    stdout: summarize(result.stdout),
    stderr: summarize(result.stderr),
    log_path: logPath,
  };
}

export async function runTestScene(config: ServerConfig, options: RunTestSceneOptions): Promise<JsonObject> {
  const scene = resolveScenePath(config.projectRoot, options.scenePath);
  const timeoutMs = boundedNumber(options.timeoutMs ?? config.runSceneTimeoutMs, 1_000, 60_000);

  if (!fs.existsSync(config.godotExecutable)) {
    return {
      status: "error",
      error: {
        code: "godot_executable_unavailable",
        message: "Configured Godot executable does not exist. Set the GODOT_BIN environment variable or ensure Godot is on your PATH.",
        godot_executable: config.godotExecutable,
      },
    };
  }

  if (!fs.existsSync(path.join(config.projectRoot, "project.godot"))) {
    return {
      status: "invalid_request",
      error: {
        code: "project_godot_missing",
        message: "Configured project root does not contain project.godot.",
        project_root: config.projectRoot,
      },
    };
  }

  if (!fs.existsSync(scene.absolutePath)) {
    return {
      status: "not_found",
      error: {
        code: "scene_not_found",
        message: "Scene path does not exist in configured project root.",
        scene_path: scene.scenePath,
      },
    };
  }

  const args = [
    "--headless",
    "--path",
    config.projectRoot,
    "--scene",
    scene.scenePath,
    "--quit-after",
    String(Math.max(MIN_QUIT_AFTER_ITERATIONS, Math.ceil(timeoutMs / 16))),
  ];

  const startedAt = Date.now();
  const result = await execFileCapture(config.godotExecutable, args, timeoutMs, config.projectRoot);
  const durationMs = Date.now() - startedAt;
  const logPath = await writeRunLog(config, {
    command: config.godotExecutable,
    args,
    scene_path: scene.scenePath,
    timeout_ms: timeoutMs,
    duration_ms: durationMs,
    ...result,
  }, "run-test-scene");

  return {
    status: result.timed_out ? "timeout" : result.exit_code === 0 ? "ok" : "error",
    scene_path: scene.scenePath,
    exit_code: result.exit_code,
    signal: result.signal,
    timed_out: result.timed_out,
    duration_ms: durationMs,
    runtime_summary: buildRuntimeSummary({
      scenePath: scene.scenePath,
      exitCode: result.exit_code,
      signal: result.signal,
      timedOut: result.timed_out,
      durationMs,
      stdout: result.stdout,
      stderr: result.stderr,
    }),
    stdout: summarize(result.stdout),
    stderr: summarize(result.stderr),
    log_path: logPath,
  };
}

export function buildRuntimeSummary(input: {
  scenePath: string;
  exitCode: number | null;
  signal: NodeJS.Signals | null;
  timedOut: boolean;
  durationMs: number;
  stdout: string;
  stderr: string;
}): JsonObject {
  const combinedOutput = `${input.stdout}\n${input.stderr}`;
  const errorCount = countRuntimeMatches(combinedOutput, /\b(ERROR|SCRIPT ERROR|CORE ERROR)\b/g);
  const warningCount = countRuntimeMatches(combinedOutput, /\b(WARNING|SCRIPT WARNING|CORE WARNING)\b/g);
  const errorSamples = extractRuntimeSamples(
    [
      { stream: "stdout", text: input.stdout },
      { stream: "stderr", text: input.stderr },
    ],
    /\b(ERROR|SCRIPT ERROR|CORE ERROR)\b/,
  );
  const warningSamples = extractRuntimeSamples(
    [
      { stream: "stdout", text: input.stdout },
      { stream: "stderr", text: input.stderr },
    ],
    /\b(WARNING|SCRIPT WARNING|CORE WARNING)\b/,
  );
  const status = input.timedOut ? "timed_out" : input.exitCode === 0 ? "completed" : "failed";
  return {
    summary_version: "godot-codex-bridge/runtime-summary-v1",
    mode: "headless_test_scene",
    status,
    scene_path: input.scenePath,
    exit_code: input.exitCode,
    signal: input.signal,
    timed_out: input.timedOut,
    duration_ms: input.durationMs,
    stdout_chars: input.stdout.length,
    stderr_chars: input.stderr.length,
    error_count: errorCount,
    warning_count: warningCount,
    error_samples: errorSamples,
    warning_samples: warningSamples,
    has_errors: errorCount > 0 || (!input.timedOut && input.exitCode !== 0),
    has_warnings: warningCount > 0,
    guidance: runtimeGuidance(status, errorCount, warningCount),
  };
}

export function resolveScenePath(projectRoot: string, scenePath: string): {
  scenePath: string;
  absolutePath: string;
} {
  if (!scenePath || scenePath.trim() === "") {
    throwInvalidScene("empty_scene_path", "Scene path is required.");
  }

  if (!scenePath.startsWith("res://")) {
    throwInvalidScene("scene_path_must_be_res", "Scene path must use res://.");
  }

  const relative = scenePath.slice("res://".length);
  if (path.isAbsolute(relative) || /^[A-Za-z]:[\\/]/.test(relative)) {
    throwInvalidScene("absolute_scene_path_rejected", "Scene path must stay inside res://.");
  }

  const normalized = path.normalize(relative.replaceAll("/", path.sep));
  if (
    normalized === "." ||
    normalized === ".." ||
    normalized.startsWith(`..${path.sep}`) ||
    path.isAbsolute(normalized)
  ) {
    throwInvalidScene("scene_traversal_rejected", "Scene path traversal is not allowed.");
  }

  const extension = path.extname(normalized).toLowerCase();
  if (!SCENE_EXTENSIONS.has(extension)) {
    throwInvalidScene("unsupported_scene_extension", "Only .tscn and .scn scenes may be run.", {
      extension,
    });
  }

  const absolutePath = path.resolve(projectRoot, normalized);
  if (!isInsidePath(projectRoot, absolutePath)) {
    throwInvalidScene("scene_boundary_rejected", "Resolved scene path is outside the configured project root.");
  }

  return {
    scenePath,
    absolutePath,
  };
}

interface ExecFileResult {
  exit_code: number | null;
  signal: NodeJS.Signals | null;
  timed_out: boolean;
  stdout: string;
  stderr: string;
}

async function execFileCapture(
  command: string,
  args: string[],
  timeoutMs: number,
  cwd: string,
): Promise<ExecFileResult> {
  return await new Promise((resolve) => {
    execFile(
      command,
      args,
      {
        cwd,
        timeout: timeoutMs,
        windowsHide: true,
        maxBuffer: 2 * 1024 * 1024,
      },
      (error, stdout, stderr) => {
        if (!error) {
          resolve({ exit_code: 0, signal: null, timed_out: false, stdout, stderr });
          return;
        }

        const nodeError = error as NodeJS.ErrnoException & {
          code?: number | string | null;
          signal?: NodeJS.Signals | null;
          killed?: boolean;
        };

        resolve({
          exit_code: typeof nodeError.code === "number" ? nodeError.code : null,
          signal: nodeError.signal ?? null,
          timed_out: Boolean(nodeError.killed),
          stdout,
          stderr,
        });
      },
    );
  });
}

async function writeRunLog(config: ServerConfig, data: JsonObject, prefix: string): Promise<string> {
  const logsDir = path.join(config.bridgeDir, "artifacts", "logs");
  await fsp.mkdir(logsDir, { recursive: true });
  const logPath = path.join(logsDir, `${prefix}-${new Date().toISOString().replaceAll(":", "-")}.json`);
  await fsp.writeFile(logPath, `${JSON.stringify(data, null, 2)}\n`, "utf8");
  return logPath;
}

function summarize(value: string): string {
  if (value.length <= SUMMARY_LIMIT) {
    return value;
  }

  return `${value.slice(0, SUMMARY_LIMIT)}\n...[truncated ${value.length - SUMMARY_LIMIT} chars]`;
}

function countRuntimeMatches(value: string, pattern: RegExp): number {
  return Array.from(value.matchAll(pattern)).length;
}

function extractRuntimeSamples(
  streams: Array<{ stream: "stdout" | "stderr"; text: string }>,
  pattern: RegExp,
): JsonObject[] {
  const samples: JsonObject[] = [];
  for (const stream of streams) {
    const lines = stream.text.split(/\r?\n/);
    for (let index = 0; index < lines.length; index += 1) {
      const line = lines[index].trim();
      if (!line || !pattern.test(line)) {
        continue;
      }
      samples.push({
        stream: stream.stream,
        line_number: index + 1,
        text: truncateLine(line),
      });
      if (samples.length >= RUNTIME_SAMPLE_LIMIT) {
        return samples;
      }
    }
  }
  return samples;
}

function truncateLine(value: string): string {
  if (value.length <= RUNTIME_SAMPLE_LINE_LIMIT) {
    return value;
  }
  return `${value.slice(0, RUNTIME_SAMPLE_LINE_LIMIT - 3)}...`;
}

function runtimeGuidance(status: string, errorCount: number, warningCount: number): string {
  if (status === "timed_out") {
    return "Scene did not finish before timeout; inspect the run log and consider a shorter test scene or longer timeout.";
  }
  if (status === "failed" || errorCount > 0) {
    return "Runtime produced errors; inspect stderr/stdout summaries and the full log before continuing gameplay edits.";
  }
  if (warningCount > 0) {
    return "Runtime completed with warnings; inspect warnings if they are related to the current change.";
  }
  return "Runtime completed without detected Godot ERROR/WARNING markers in captured output.";
}

function throwInvalidScene(code: string, message: string, details: JsonObject = {}): never {
  const error = new Error(message) as Error & { code: string; details: JsonObject };
  error.name = "InvalidScenePathError";
  error.code = code;
  error.details = details;
  throw error;
}
