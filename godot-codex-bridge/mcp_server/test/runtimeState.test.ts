import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { getRuntimeEvents, getRuntimeState } from "../src/runtimeState.js";
import type { ServerConfig } from "../src/types.js";

test("getRuntimeState reads a bounded local runtime state file", async () => {
  const config = await makeConfig();
  await writeRuntimeState(config, {
    runtime_state_version: "godot-codex-bridge/runtime-state-v1",
    generated_at: "2026-06-23T12:00:00.000Z",
    runtime: {
      paused: false,
      process_frames: 12,
      physics_frames: 11,
      time_scale: 1,
    },
    input: {
      active_actions: ["move_right"],
      sampled_actions: ["move_left", "move_right"],
      action_states: [
        { name: "move_left", pressed: false, strength: 0 },
        { name: "move_right", pressed: true, strength: 1 },
      ],
      max_actions: 80,
    },
    tree: {
      current_scene: "/root/Main",
      active_scene: { name: "Main", type: "Node3D", path: "/root/Main" },
      summary: {
        active_scene_name: "Main",
        node_count_sampled: 2,
        key_position_count: 1,
        autoload_count: 1,
      },
      node_type_counts: { Node3D: 1, Timer: 1 },
      key_positions: [
        {
          path: "/root/Main/Player",
          name: "Player",
          type: "CharacterBody3D",
          dimension: "3d",
          global_position: { x: 1, y: 2, z: 3 },
        },
      ],
      nodes: [
        {
          name: "Main",
          huge: "x".repeat(1_500),
          state: { kind: "Timer", stopped: false, time_left: 0.5 },
        },
      ],
    },
    autoloads: {
      total: 1,
      sampled: [{ name: "GameState", present_in_tree: true, node_path: "/root/GameState" }],
      truncated: false,
      max_autoloads: 40,
    },
  });

  const result = await getRuntimeState(config, { maxAgeMs: 60_000 });

  assert.equal(result.status, "ok");
  assert.equal(result.runtime_state_version, "godot-codex-bridge/runtime-state-v1");
  assert.equal(result.freshness, "fresh");
  assert.equal(typeof result.state_path, "string");
  const state = result.state as { tree?: { nodes?: Array<{ huge?: string }> } };
  assert.equal(state.tree?.nodes?.[0]?.huge?.endsWith("..."), true);
  assert.equal((result.state as { runtime?: { process_frames?: number } }).runtime?.process_frames, 12);
  assert.deepEqual((result.state as { input?: { active_actions?: string[] } }).input?.active_actions, ["move_right"]);
  assert.deepEqual((result.state as { input?: { action_states?: Array<{ name?: string; pressed?: boolean; strength?: number }> } }).input?.action_states?.[1], {
    name: "move_right",
    pressed: true,
    strength: 1,
  });
  assert.equal((result.state as { tree?: { active_scene?: { name?: string } } }).tree?.active_scene?.name, "Main");
  assert.equal((result.state as { tree?: { summary?: { key_position_count?: number } } }).tree?.summary?.key_position_count, 1);
  assert.equal((result.state as { tree?: { key_positions?: Array<{ global_position?: { z?: number } }> } }).tree?.key_positions?.[0]?.global_position?.z, 3);
  assert.equal((result.state as { tree?: { node_type_counts?: { Timer?: number } } }).tree?.node_type_counts?.Timer, 1);
  assert.equal(
    (result.state as { tree?: { nodes?: Array<{ state?: { kind?: string } }> } }).tree?.nodes?.[0]?.state?.kind,
    "Timer",
  );
  assert.equal((result.state as { autoloads?: { sampled?: Array<{ name?: string }> } }).autoloads?.sampled?.[0]?.name, "GameState");
});

test("getRuntimeState reports missing runtime probe state as not_found", async () => {
  const config = await makeConfig();

  const result = await getRuntimeState(config);

  assert.equal(result.status, "not_found");
  assert.equal(result.error?.code, "runtime_state_not_found");
});

test("getRuntimeState reports invalid JSON as an error", async () => {
  const config = await makeConfig();
  const runtimeDir = path.join(config.bridgeDir, "runtime");
  await fs.mkdir(runtimeDir, { recursive: true });
  await fs.writeFile(path.join(runtimeDir, "state.json"), "{ nope", "utf8");

  const result = await getRuntimeState(config);

  assert.equal(result.status, "error");
  assert.equal(result.error?.code, "invalid_runtime_state_json");
});

test("getRuntimeState marks old runtime state as stale", async () => {
  const config = await makeConfig();
  const statePath = await writeRuntimeState(config, {
    runtime_state_version: "godot-codex-bridge/runtime-state-v1",
    generated_at: "2026-06-23T12:00:00.000Z",
  });
  const oldDate = new Date(Date.now() - 120_000);
  await fs.utimes(statePath, oldDate, oldDate);

  const result = await getRuntimeState(config, { maxAgeMs: 1_000 });

  assert.equal(result.status, "ok");
  assert.equal(result.freshness, "stale");
});

test("getRuntimeState rejects files larger than the safety limit", async () => {
  const config = await makeConfig();
  const runtimeDir = path.join(config.bridgeDir, "runtime");
  await fs.mkdir(runtimeDir, { recursive: true });
  await fs.writeFile(path.join(runtimeDir, "state.json"), JSON.stringify({ text: "x".repeat(64 * 1024) }), "utf8");

  const result = await getRuntimeState(config, { maxBytes: 16 * 1024 });

  assert.equal(result.status, "error");
  assert.equal(result.error?.code, "runtime_state_too_large");
});

test("getRuntimeEvents reads a bounded local runtime events file", async () => {
  const config = await makeConfig();
  await writeRuntimeEvents(config, {
    runtime_events_version: "godot-codex-bridge/runtime-events-v1",
    generated_at: "2026-06-24T13:00:00.000Z",
    event_count: 2,
    events: [
      {
        id: "event-1",
        at: "2026-06-24T13:00:00.000Z",
        type: "scene_changed",
        payload: { current_scene: "/root/Main", huge: "x".repeat(1_500) },
      },
      {
        id: "event-2",
        at: "2026-06-24T13:00:01.000Z",
        type: "input_action_pressed",
        payload: { name: "move_right", strength: 1 },
      },
    ],
  });

  const result = await getRuntimeEvents(config, { maxAgeMs: 60_000 });

  assert.equal(result.status, "ok");
  assert.equal(result.runtime_events_version, "godot-codex-bridge/runtime-events-v1");
  assert.equal(result.freshness, "fresh");
  assert.equal(typeof result.events_path, "string");
  const document = result.events as { events?: Array<{ type?: string; payload?: { huge?: string; name?: string } }> };
  assert.equal(document.events?.[0]?.type, "scene_changed");
  assert.equal(document.events?.[0]?.payload?.huge?.endsWith("..."), true);
  assert.equal(document.events?.[1]?.payload?.name, "move_right");
});

test("getRuntimeEvents reports missing runtime probe events as not_found", async () => {
  const config = await makeConfig();

  const result = await getRuntimeEvents(config);

  assert.equal(result.status, "not_found");
  assert.equal(result.error?.code, "runtime_events_not_found");
});

test("getRuntimeEvents reports invalid JSON as an error", async () => {
  const config = await makeConfig();
  const runtimeDir = path.join(config.bridgeDir, "runtime");
  await fs.mkdir(runtimeDir, { recursive: true });
  await fs.writeFile(path.join(runtimeDir, "events.json"), "{ nope", "utf8");

  const result = await getRuntimeEvents(config);

  assert.equal(result.status, "error");
  assert.equal(result.error?.code, "invalid_runtime_events_json");
});

test("getRuntimeEvents marks old runtime events as stale", async () => {
  const config = await makeConfig();
  const eventsPath = await writeRuntimeEvents(config, {
    runtime_events_version: "godot-codex-bridge/runtime-events-v1",
    generated_at: "2026-06-24T13:00:00.000Z",
    events: [],
  });
  const oldDate = new Date(Date.now() - 120_000);
  await fs.utimes(eventsPath, oldDate, oldDate);

  const result = await getRuntimeEvents(config, { maxAgeMs: 1_000 });

  assert.equal(result.status, "ok");
  assert.equal(result.freshness, "stale");
});

test("getRuntimeEvents rejects files larger than the safety limit", async () => {
  const config = await makeConfig();
  const runtimeDir = path.join(config.bridgeDir, "runtime");
  await fs.mkdir(runtimeDir, { recursive: true });
  await fs.writeFile(path.join(runtimeDir, "events.json"), JSON.stringify({ text: "x".repeat(64 * 1024) }), "utf8");

  const result = await getRuntimeEvents(config, { maxBytes: 16 * 1024 });

  assert.equal(result.status, "error");
  assert.equal(result.error?.code, "runtime_events_too_large");
});

async function makeConfig(): Promise<ServerConfig> {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-runtime-"));
  return {
    projectRoot,
    bridgeDir: path.join(projectRoot, ".godot", "godot_codex_bridge"),
    godotExecutable: process.execPath,
    addonRequestTimeoutMs: 250,
    runSceneTimeoutMs: 1_000,
  };
}

async function writeRuntimeState(config: ServerConfig, data: Record<string, unknown>): Promise<string> {
  const runtimeDir = path.join(config.bridgeDir, "runtime");
  const statePath = path.join(runtimeDir, "state.json");
  await fs.mkdir(runtimeDir, { recursive: true });
  await fs.writeFile(statePath, JSON.stringify(data), "utf8");
  return statePath;
}

async function writeRuntimeEvents(config: ServerConfig, data: Record<string, unknown>): Promise<string> {
  const runtimeDir = path.join(config.bridgeDir, "runtime");
  const eventsPath = path.join(runtimeDir, "events.json");
  await fs.mkdir(runtimeDir, { recursive: true });
  await fs.writeFile(eventsPath, JSON.stringify(data), "utf8");
  return eventsPath;
}
