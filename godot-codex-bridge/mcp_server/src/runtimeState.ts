import fs from "node:fs/promises";
import path from "node:path";

import { isInsidePath } from "./config.js";
import { isJsonObject } from "./bridge.js";
import type { JsonObject, JsonValue, ServerConfig, ToolEnvelope } from "./types.js";

const DEFAULT_MAX_AGE_MS = 5_000;
const DEFAULT_MAX_BYTES = 512 * 1024;
const MAX_DEPTH = 8;
const MAX_ARRAY_ITEMS = 120;
const MAX_OBJECT_KEYS = 120;
const MAX_STRING_LENGTH = 1_000;

export async function getRuntimeState(config: ServerConfig, args: JsonObject = {}): Promise<ToolEnvelope> {
  const runtimeDir = path.join(config.bridgeDir, "runtime");
  const statePath = path.join(runtimeDir, "state.json");
  if (!isInsidePath(runtimeDir, statePath) || !isInsidePath(config.bridgeDir, statePath)) {
    return {
      status: "error",
      error: {
        code: "runtime_state_path_outside_bridge",
        message: "Runtime state path resolved outside the bridge runtime directory.",
      },
    };
  }

  let stat;
  try {
    stat = await fs.stat(statePath);
  } catch {
    return {
      status: "not_found",
      runtime_dir: runtimeDir,
      expected_state_path: statePath,
      error: {
        code: "runtime_state_not_found",
        message: "No runtime state file is available yet. Add res://addons/godot_codex_bridge/runtime_state_probe.gd to a running scene or autoload.",
      },
    };
  }

  if (!stat.isFile()) {
    return {
      status: "error",
      runtime_dir: runtimeDir,
      state_path: statePath,
      error: {
        code: "runtime_state_not_file",
        message: "Runtime state path exists but is not a file.",
      },
    };
  }

  const maxBytes = boundedNumber(args.maxBytes, DEFAULT_MAX_BYTES, 16 * 1024, 2 * 1024 * 1024);
  if (stat.size > maxBytes) {
    return {
      status: "error",
      runtime_dir: runtimeDir,
      state_path: statePath,
      size_bytes: stat.size,
      max_bytes: maxBytes,
      error: {
        code: "runtime_state_too_large",
        message: "Runtime state file is larger than the configured safety limit.",
      },
    };
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(await fs.readFile(statePath, "utf8")) as unknown;
  } catch (error) {
    return {
      status: "error",
      runtime_dir: runtimeDir,
      state_path: statePath,
      error: {
        code: "invalid_runtime_state_json",
        message: error instanceof Error ? error.message : String(error),
      },
    };
  }

  if (!isJsonObject(parsed)) {
    return {
      status: "error",
      runtime_dir: runtimeDir,
      state_path: statePath,
      error: {
        code: "invalid_runtime_state",
        message: "Runtime state must be a JSON object.",
      },
    };
  }

  const ageMs = Math.max(0, Date.now() - stat.mtimeMs);
  const maxAgeMs = boundedNumber(args.maxAgeMs, DEFAULT_MAX_AGE_MS, 0, 10 * 60 * 1000);
  return {
    status: "ok",
    runtime_state_version: typeof parsed.runtime_state_version === "string" ? parsed.runtime_state_version : null,
    freshness: maxAgeMs > 0 && ageMs > maxAgeMs ? "stale" : "fresh",
    age_ms: Math.round(ageMs),
    max_age_ms: maxAgeMs,
    runtime_dir: runtimeDir,
    state_path: statePath,
    size_bytes: stat.size,
    state: sanitizeJson(parsed),
  };
}

export async function getRuntimeEvents(config: ServerConfig, args: JsonObject = {}): Promise<ToolEnvelope> {
  const runtimeDir = path.join(config.bridgeDir, "runtime");
  const eventsPath = path.join(runtimeDir, "events.json");
  if (!isInsidePath(runtimeDir, eventsPath) || !isInsidePath(config.bridgeDir, eventsPath)) {
    return {
      status: "error",
      error: {
        code: "runtime_events_path_outside_bridge",
        message: "Runtime events path resolved outside the bridge runtime directory.",
      },
    };
  }

  let stat;
  try {
    stat = await fs.stat(eventsPath);
  } catch {
    return {
      status: "not_found",
      runtime_dir: runtimeDir,
      expected_events_path: eventsPath,
      error: {
        code: "runtime_events_not_found",
        message: "No runtime events file is available yet. Add res://addons/godot_codex_bridge/runtime_state_probe.gd to a running scene or autoload.",
      },
    };
  }

  if (!stat.isFile()) {
    return {
      status: "error",
      runtime_dir: runtimeDir,
      events_path: eventsPath,
      error: {
        code: "runtime_events_not_file",
        message: "Runtime events path exists but is not a file.",
      },
    };
  }

  const maxBytes = boundedNumber(args.maxBytes, DEFAULT_MAX_BYTES, 16 * 1024, 2 * 1024 * 1024);
  if (stat.size > maxBytes) {
    return {
      status: "error",
      runtime_dir: runtimeDir,
      events_path: eventsPath,
      size_bytes: stat.size,
      max_bytes: maxBytes,
      error: {
        code: "runtime_events_too_large",
        message: "Runtime events file is larger than the configured safety limit.",
      },
    };
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(await fs.readFile(eventsPath, "utf8")) as unknown;
  } catch (error) {
    return {
      status: "error",
      runtime_dir: runtimeDir,
      events_path: eventsPath,
      error: {
        code: "invalid_runtime_events_json",
        message: error instanceof Error ? error.message : String(error),
      },
    };
  }

  if (!isJsonObject(parsed)) {
    return {
      status: "error",
      runtime_dir: runtimeDir,
      events_path: eventsPath,
      error: {
        code: "invalid_runtime_events",
        message: "Runtime events must be a JSON object.",
      },
    };
  }

  const ageMs = Math.max(0, Date.now() - stat.mtimeMs);
  const maxAgeMs = boundedNumber(args.maxAgeMs, DEFAULT_MAX_AGE_MS, 0, 10 * 60 * 1000);
  return {
    status: "ok",
    runtime_events_version: typeof parsed.runtime_events_version === "string" ? parsed.runtime_events_version : null,
    freshness: maxAgeMs > 0 && ageMs > maxAgeMs ? "stale" : "fresh",
    age_ms: Math.round(ageMs),
    max_age_ms: maxAgeMs,
    runtime_dir: runtimeDir,
    events_path: eventsPath,
    size_bytes: stat.size,
    events: sanitizeJson(parsed),
  };
}

function sanitizeJson(value: unknown, depth = 0): JsonValue {
  if (value === null || typeof value === "boolean") {
    return value;
  }
  if (typeof value === "number") {
    return Number.isFinite(value) ? value : null;
  }
  if (typeof value === "string") {
    return value.length > MAX_STRING_LENGTH ? `${value.slice(0, MAX_STRING_LENGTH)}...` : value;
  }
  if (depth >= MAX_DEPTH) {
    return "[truncated:max_depth]";
  }
  if (Array.isArray(value)) {
    const items = value.slice(0, MAX_ARRAY_ITEMS).map((item) => sanitizeJson(item, depth + 1));
    if (value.length > MAX_ARRAY_ITEMS) {
      items.push(`[truncated:${value.length - MAX_ARRAY_ITEMS}_items]`);
    }
    return items;
  }
  if (isJsonObject(value)) {
    const result: JsonObject = {};
    const entries = Object.entries(value).slice(0, MAX_OBJECT_KEYS);
    for (const [key, item] of entries) {
      result[key] = sanitizeJson(item, depth + 1);
    }
    if (Object.keys(value).length > MAX_OBJECT_KEYS) {
      result.__truncated_keys = Object.keys(value).length - MAX_OBJECT_KEYS;
    }
    return result;
  }
  return String(value);
}

function boundedNumber(value: JsonValue | undefined, fallback: number, min: number, max: number): number {
  const parsed = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(parsed)) {
    return fallback;
  }
  return Math.min(Math.max(Math.trunc(parsed), min), max);
}
