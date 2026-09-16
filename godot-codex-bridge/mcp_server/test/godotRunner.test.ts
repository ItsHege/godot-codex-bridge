import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { buildRuntimeSummary, resolveScenePath, runProjectParseCheck, runTestScene } from "../src/godotRunner.js";
import type { ServerConfig } from "../src/types.js";

test("resolveScenePath accepts project-local res scene paths", async () => {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-runner-"));
  const result = resolveScenePath(projectRoot, "res://scenes/test_3d.tscn");

  assert.equal(result.scenePath, "res://scenes/test_3d.tscn");
  assert.equal(result.absolutePath, path.join(projectRoot, "scenes", "test_3d.tscn"));
});

test("resolveScenePath rejects unsafe scene paths", async () => {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-runner-"));

  assert.throws(() => resolveScenePath(projectRoot, "scenes/test_3d.tscn"), /res:\/\//);
  assert.throws(() => resolveScenePath(projectRoot, "res://../outside.tscn"), /traversal/);
  assert.throws(() => resolveScenePath(projectRoot, "res://scenes/test.txt"), /\.tscn and \.scn/);
});

test("runTestScene validates request before attempting unavailable Godot executable", async () => {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-runner-"));
  const config: ServerConfig = {
    projectRoot,
    bridgeDir: path.join(projectRoot, ".godot", "godot_codex_bridge"),
    godotExecutable: path.join(projectRoot, "missing-godot.exe"),
    addonRequestTimeoutMs: 250,
    runSceneTimeoutMs: 1_000,
  };

  const result = await runTestScene(config, { scenePath: "res://scenes/test_3d.tscn" });

  assert.equal(result.status, "error");
  assert.equal((result.error as { code: string }).code, "godot_executable_unavailable");
});

test("runProjectParseCheck reports not_run when Godot executable is unavailable", async () => {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-runner-"));
  const config: ServerConfig = {
    projectRoot,
    bridgeDir: path.join(projectRoot, ".godot", "godot_codex_bridge"),
    godotExecutable: path.join(projectRoot, "missing-godot.exe"),
    addonRequestTimeoutMs: 250,
    runSceneTimeoutMs: 1_000,
  };

  const result = await runProjectParseCheck(config);

  assert.equal(result.status, "not_run");
  assert.equal(result.validation_status, "not_run");
  assert.equal(result.check_kind, "godot_headless_check_only");
  assert.equal((result.error as { code: string }).code, "godot_executable_unavailable");
});

test("buildRuntimeSummary reports runtime warnings and errors", () => {
  const summary = buildRuntimeSummary({
    scenePath: "res://scenes/test_3d.tscn",
    exitCode: 1,
    signal: null,
    timedOut: false,
    durationMs: 1234,
    stdout: "Godot Engine\nWARNING: missing optional resource\n",
    stderr: "SCRIPT ERROR: Invalid call\n",
  });

  assert.equal(summary.summary_version, "godot-codex-bridge/runtime-summary-v1");
  assert.equal(summary.status, "failed");
  assert.equal(summary.scene_path, "res://scenes/test_3d.tscn");
  assert.equal(summary.error_count, 1);
  assert.equal(summary.warning_count, 1);
  const errorSamples = summary.error_samples as Array<{ stream: string; line_number: number; text: string }>;
  const warningSamples = summary.warning_samples as Array<{ stream: string; line_number: number; text: string }>;
  assert.equal(errorSamples.length, 1);
  assert.equal(errorSamples[0].stream, "stderr");
  assert.equal(errorSamples[0].line_number, 1);
  assert.match(errorSamples[0].text, /SCRIPT ERROR/);
  assert.equal(warningSamples.length, 1);
  assert.equal(warningSamples[0].stream, "stdout");
  assert.equal(warningSamples[0].line_number, 2);
  assert.match(warningSamples[0].text, /WARNING/);
  assert.equal(summary.has_errors, true);
  assert.equal(summary.has_warnings, true);
  assert.match(String(summary.guidance), /Runtime produced errors/);
});

test("buildRuntimeSummary reports clean completed runtime", () => {
  const summary = buildRuntimeSummary({
    scenePath: "res://scenes/test_3d.tscn",
    exitCode: 0,
    signal: null,
    timedOut: false,
    durationMs: 250,
    stdout: "test completed\n",
    stderr: "",
  });

  assert.equal(summary.status, "completed");
  assert.deepEqual(summary.error_samples, []);
  assert.deepEqual(summary.warning_samples, []);
  assert.equal(summary.has_errors, false);
  assert.equal(summary.has_warnings, false);
  assert.match(String(summary.guidance), /completed without detected Godot ERROR\/WARNING/);
});

test("buildRuntimeSummary bounds runtime output samples", () => {
  const longLine = `SCRIPT ERROR: ${"x".repeat(900)}`;
  const summary = buildRuntimeSummary({
    scenePath: "res://scenes/test_3d.tscn",
    exitCode: 1,
    signal: null,
    timedOut: false,
    durationMs: 250,
    stdout: [
      longLine,
      "SCRIPT ERROR: one",
      "SCRIPT ERROR: two",
      "SCRIPT ERROR: three",
      "SCRIPT ERROR: four",
      "SCRIPT ERROR: five",
    ].join("\n"),
    stderr: "SCRIPT ERROR: stderr should be past limit",
  });

  const samples = summary.error_samples as Array<{ text: string }>;
  assert.equal(samples.length, 5);
  assert.equal(samples[0].text.length, 500);
  assert.equal(samples[0].text.endsWith("..."), true);
  assert.equal(samples[1].text, "SCRIPT ERROR: one");
  assert.equal(samples[4].text, "SCRIPT ERROR: four");
  assert.equal(samples.some((sample) => sample.text === longLine), false);
});
