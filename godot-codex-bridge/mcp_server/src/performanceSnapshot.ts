import type { JsonObject, JsonValue, ToolEnvelope } from "./types.js";

const PERFORMANCE_SNAPSHOT_VERSION = "godot-codex-bridge/performance-snapshot-v1";
const DEFAULT_MAX_SAMPLES = 24;
const MAX_SAMPLES = 120;

const RENDERING_MONITORS = {
  draw_calls: "render_total_draw_calls_in_frame",
  objects: "render_total_objects_in_frame",
  primitives: "render_total_primitives_in_frame",
} as const;

const PHYSICS_3D_MONITORS = {
  active_objects: "physics_3d_active_objects",
  collision_pairs: "physics_3d_collision_pairs",
  island_count: "physics_3d_island_count",
} as const;

const NAVIGATION_MONITORS = {
  active_maps: "navigation_active_maps",
  region_count: "navigation_region_count",
  agent_count: "navigation_agent_count",
} as const;

export function getPerformanceSnapshot(snapshotEnvelope: ToolEnvelope, args: JsonObject = {}): ToolEnvelope {
  if (snapshotEnvelope.status !== "ok") {
    return snapshotEnvelope;
  }

  const snapshot = objectOrNull(snapshotEnvelope.snapshot);
  if (!snapshot) {
    return {
      status: "not_found",
      error: {
        code: "snapshot_missing",
        message: "Latest context snapshot is missing or invalid.",
      },
    };
  }

  const performance = objectOrNull(snapshot.performance);
  const sceneTree = objectOrNull(snapshot.scene_tree);
  const currentScene = objectOrNull(snapshot.current_scene);
  const maxSamples = boundedInteger(args.maxSamples ?? args.max_samples, DEFAULT_MAX_SAMPLES, 0, MAX_SAMPLES);
  const samples = boundedSamples(arrayOrEmpty(performance?.samples), maxSamples);
  const monitors = objectOrNull(performance?.monitors) ?? {};
  const performanceStatus = stringOrNull(performance?.status) ?? (performance ? "available" : "unavailable");
  const source = stringOrNull(performance?.source) ?? "context_snapshot";
  const findings: JsonObject[] = [];
  addPerformanceFindings(findings, monitors);

  return {
    status: "ok",
    performance_snapshot_version: PERFORMANCE_SNAPSHOT_VERSION,
    protocol_version: stringOrNull(snapshot.protocol_version),
    generated_at: stringOrNull(snapshot.generated_at),
    snapshot_path: stringOrNull(snapshotEnvelope.snapshot_path),
    current_scene: currentScene ?? null,
    summary: {
      node_count: numberOrNull(sceneTree?.node_count),
      scene_tree_truncated: boolOrNull(sceneTree?.truncated),
      source,
      captured_at: stringOrNull(performance?.captured_at),
      performance_status: performanceStatus,
      sample_count: numberOrNull(performance?.sample_count) ?? arrayOrEmpty(performance?.samples).length,
      sample_interval_seconds: numberOrNull(performance?.sample_interval_seconds),
    },
    rendering: monitorGroup(monitors, RENDERING_MONITORS),
    physics_3d: monitorGroup(monitors, PHYSICS_3D_MONITORS),
    navigation: monitorGroup(monitors, NAVIGATION_MONITORS),
    memory: {
      status: "unavailable",
      reason: "Current editor snapshot contract does not include stable memory monitors.",
    },
    vram: {
      status: "unavailable",
      reason: "Current editor snapshot contract does not include stable VRAM/video memory monitors.",
    },
    timeline: summarizeTimeline(samples, performance),
    findings,
    limits: {
      max_samples: MAX_SAMPLES,
      returned_max_samples: maxSamples,
      returned_sample_count: samples.length,
    },
    privacy: {
      classification: "local_sensitive_performance_evidence",
      external_upload_allowed: false,
    },
  };
}

function monitorGroup<T extends Record<string, string>>(monitors: JsonObject, names: T): JsonObject {
  const result: JsonObject = {};
  for (const [label, monitorName] of Object.entries(names)) {
    result[label] = monitorValue(monitors, monitorName);
  }
  return result;
}

function monitorValue(monitors: JsonObject, monitorName: string): JsonObject {
  const value = numberOrNull(monitors[monitorName]);
  if (value === null) {
    return {
      status: "unavailable",
      monitor: monitorName,
    };
  }
  return {
    status: "available",
    monitor: monitorName,
    value,
  };
}

function summarizeTimeline(samples: JsonObject[], performance: JsonObject | null): JsonObject {
  if (samples.length === 0) {
    return {
      status: "unavailable",
      reason: "No performance samples were present in the context snapshot.",
      sample_count: 0,
    };
  }
  return {
    status: "available",
    sample_count: samples.length,
    sample_interval_seconds: numberOrNull(performance?.sample_interval_seconds),
    first_captured_at: stringOrNull(samples[0]?.captured_at),
    last_captured_at: stringOrNull(samples[samples.length - 1]?.captured_at),
    draw_calls: sampleStats(samples, RENDERING_MONITORS.draw_calls),
    objects: sampleStats(samples, RENDERING_MONITORS.objects),
    primitives: sampleStats(samples, RENDERING_MONITORS.primitives),
    physics_active_objects: sampleStats(samples, PHYSICS_3D_MONITORS.active_objects),
    physics_collision_pairs: sampleStats(samples, PHYSICS_3D_MONITORS.collision_pairs),
    navigation_agents: sampleStats(samples, NAVIGATION_MONITORS.agent_count),
  };
}

function sampleStats(samples: JsonObject[], monitorName: string): JsonObject {
  const values = samples
    .map((sample) => numberOrNull(objectOrNull(sample.monitors)?.[monitorName]))
    .filter((value): value is number => value !== null);
  if (values.length === 0) {
    return {
      status: "unavailable",
      monitor: monitorName,
    };
  }
  const min = Math.min(...values);
  const max = Math.max(...values);
  const average = values.reduce((total, value) => total + value, 0) / values.length;
  return {
    status: "available",
    monitor: monitorName,
    min,
    max,
    average,
  };
}

function addPerformanceFindings(findings: JsonObject[], monitors: JsonObject): void {
  const drawCalls = numberOrNull(monitors[RENDERING_MONITORS.draw_calls]);
  if (drawCalls !== null && drawCalls > 2500) {
    findings.push({
      severity: "warning",
      code: "draw_calls_high",
      message: "Editor snapshot reports more than 2500 draw calls in the current frame.",
      value: drawCalls,
    });
  }
  const collisionPairs = numberOrNull(monitors[PHYSICS_3D_MONITORS.collision_pairs]);
  if (collisionPairs !== null && collisionPairs > 1000) {
    findings.push({
      severity: "warning",
      code: "physics_collision_pairs_high",
      message: "Editor snapshot reports more than 1000 3D collision pairs.",
      value: collisionPairs,
    });
  }
}

function boundedSamples(value: JsonObject[], maxSamples: number): JsonObject[] {
  if (maxSamples <= 0) {
    return [];
  }
  return value.slice(Math.max(0, value.length - maxSamples));
}

function boundedInteger(value: JsonValue | undefined, fallback: number, min: number, max: number): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return fallback;
  }
  return Math.max(min, Math.min(max, Math.trunc(value)));
}

function objectOrNull(value: JsonValue | undefined): JsonObject | null {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    return null;
  }
  return value;
}

function arrayOrEmpty(value: JsonValue | undefined): JsonObject[] {
  return Array.isArray(value)
    ? value.filter((entry): entry is JsonObject => objectOrNull(entry) !== null)
    : [];
}

function stringOrNull(value: JsonValue | undefined): string | null {
  return typeof value === "string" ? value : null;
}

function numberOrNull(value: JsonValue | undefined): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function boolOrNull(value: JsonValue | undefined): boolean | null {
  return typeof value === "boolean" ? value : null;
}
