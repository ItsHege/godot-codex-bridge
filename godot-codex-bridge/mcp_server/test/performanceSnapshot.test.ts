import assert from "node:assert/strict";
import test from "node:test";

import { getPerformanceSnapshot } from "../src/performanceSnapshot.js";
import type { ToolEnvelope } from "../src/types.js";

test("getPerformanceSnapshot reports monitor groups and bounded timeline stats", () => {
  const result = getPerformanceSnapshot(snapshotEnvelope({
    scene_tree: {
      node_count: 7,
      truncated: false,
    },
    performance: {
      captured_at: "2026-06-24T10:00:02.000Z",
      source: "godot_performance_monitor",
      status: "available",
      sample_interval_seconds: 1,
      sample_count: 3,
      monitors: {
        render_total_draw_calls_in_frame: 2600,
        render_total_objects_in_frame: 420,
        render_total_primitives_in_frame: 90000,
        physics_3d_active_objects: 42,
        physics_3d_collision_pairs: 1201,
        physics_3d_island_count: 7,
        navigation_active_maps: 1,
        navigation_region_count: 2,
        navigation_agent_count: 3,
      },
      samples: [
        { captured_at: "2026-06-24T10:00:00.000Z", monitors: { render_total_draw_calls_in_frame: 100, physics_3d_collision_pairs: 10 } },
        { captured_at: "2026-06-24T10:00:01.000Z", monitors: { render_total_draw_calls_in_frame: 200, physics_3d_collision_pairs: 20 } },
        { captured_at: "2026-06-24T10:00:02.000Z", monitors: { render_total_draw_calls_in_frame: 2600, physics_3d_collision_pairs: 1201 } },
      ],
    },
  }), { maxSamples: 2 });

  assert.equal(result.status, "ok");
  assert.equal(result.performance_snapshot_version, "godot-codex-bridge/performance-snapshot-v1");
  assert.equal((result.summary as { node_count?: number }).node_count, 7);
  assert.equal(((result.rendering as Record<string, { value?: number }>).draw_calls).value, 2600);
  assert.equal(((result.physics_3d as Record<string, { value?: number }>).collision_pairs).value, 1201);
  assert.equal(((result.navigation as Record<string, { value?: number }>).agent_count).value, 3);
  assert.equal((result.timeline as { sample_count?: number }).sample_count, 2);
  assert.equal(((result.timeline as Record<string, { average?: number }>).draw_calls).average, 1400);
  assert.equal((result.findings as Array<{ code?: string }>).some((finding) => finding.code === "draw_calls_high"), true);
  assert.equal((result.findings as Array<{ code?: string }>).some((finding) => finding.code === "physics_collision_pairs_high"), true);
});

test("getPerformanceSnapshot is honest when performance, memory and VRAM are unavailable", () => {
  const result = getPerformanceSnapshot(snapshotEnvelope({
    scene_tree: {
      node_count: 3,
      truncated: false,
    },
  }));

  assert.equal(result.status, "ok");
  assert.equal((result.summary as { performance_status?: string }).performance_status, "unavailable");
  assert.equal((result.timeline as { status?: string }).status, "unavailable");
  assert.equal((result.memory as { status?: string }).status, "unavailable");
  assert.equal((result.vram as { status?: string }).status, "unavailable");
});

function snapshotEnvelope(snapshot: Record<string, unknown>): ToolEnvelope {
  return {
    status: "ok",
    snapshot_path: "C:\\fixture\\.godot\\godot_codex_bridge\\context_snapshot.json",
    snapshot: {
      protocol_version: "godot-codex-bridge/0.1",
      generated_at: "2026-06-24T10:00:00.000Z",
      current_scene: { path: "res://scenes/main.tscn" },
      ...snapshot,
    },
  };
}
