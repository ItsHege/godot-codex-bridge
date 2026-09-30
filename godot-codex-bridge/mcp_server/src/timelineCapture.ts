import { randomUUID } from "node:crypto";
import path from "node:path";

import { BridgeClient, isJsonObject } from "./bridge.js";
import { ensureDirectoryInsideRootSync, writeFileInsideRootSync } from "./physicalPath.js";
import type { JsonObject, ServerConfig, ToolEnvelope, ToolStatus } from "./types.js";

const TIMELINE_CAPTURE_VERSION = "godot-codex-bridge/timeline-capture-v1";

export interface TimelineCaptureOptions {
  frameCount: number;
  intervalMs: number;
  timeoutMs: number;
  reason?: string;
  baselineName?: string;
  baselinePath?: string;
}

export async function captureTimelineScreenshots(
  config: ServerConfig,
  bridge: BridgeClient,
  options: TimelineCaptureOptions,
): Promise<ToolEnvelope> {
  const frameCount = clampInteger(options.frameCount, 2, 12);
  const intervalMs = clampInteger(options.intervalMs, 50, 5_000);
  const timeoutMs = clampInteger(options.timeoutMs, 250, 30_000);
  const captureId = makeCaptureId();
  const createdAt = new Date().toISOString();
  const reason = sanitizeReason(options.reason);
  const frames: JsonObject[] = [];
  let aborted = false;
  let failureStatus: ToolStatus | null = null;
  let failureError: JsonObject | undefined;

  for (let index = 0; index < frameCount; index += 1) {
    if (index > 0) {
      await sleep(intervalMs);
    }

    const requestedAtMs = Date.now();
    const requestedAt = new Date(requestedAtMs).toISOString();
    const envelope = await bridge.sendAddonRequest(
      "capture_viewport_screenshot",
      {
        requested_by: "mcp_server",
        reason: `timeline:${captureId}:frame:${index + 1}${reason ? `:${reason}` : ""}`,
      },
      timeoutMs,
    );
    const completedAtMs = Date.now();
    const frame = frameFromEnvelope(index, requestedAt, new Date(completedAtMs).toISOString(), completedAtMs - requestedAtMs, envelope);
    frames.push(frame);

    if (frame.status !== "ok") {
      aborted = true;
      failureStatus = envelope.status;
      failureError = objectOrUndefined(frame.error);
      break;
    }
  }

  const succeededFrames = frames.filter((frame) => frame.status === "ok").length;
  const captureStatus = succeededFrames === frameCount ? "completed" : succeededFrames > 0 ? "partial" : "failed";
  const manifestStatus: ToolStatus = captureStatus === "failed" ? failureStatus ?? "error" : "ok";
  const artifactRoot = path.join(config.bridgeDir, "artifacts", "timeline_captures", captureId);
  ensureDirectoryInsideRootSync(config.projectRoot, artifactRoot);

  const manifest: ToolEnvelope = {
    status: manifestStatus,
    timeline_capture_version: TIMELINE_CAPTURE_VERSION,
    capture_id: captureId,
    capture_status: captureStatus,
    created_at: createdAt,
    completed_at: new Date().toISOString(),
    project_root: config.projectRoot,
    bridge_dir: config.bridgeDir,
    frame_count_requested: frameCount,
    frame_count_captured: frames.length,
    frame_count_succeeded: succeededFrames,
    interval_ms: intervalMs,
    timeout_ms_per_frame: timeoutMs,
    aborted,
    reason,
    frames,
    privacy: {
      classification: "local_sensitive_evidence",
      external_upload_allowed: false,
      notes: [
        "Timeline capture stores only local screenshot metadata and manifest JSON.",
        "PNG bytes are not sent through MCP responses.",
      ],
    },
  };

  if (failureError) {
    manifest.error = failureError;
  }
  if (options.baselineName || options.baselinePath) {
    manifest.baseline_comparison = disabledBaselineComparison(options.baselineName, options.baselinePath, frames.length);
  }

  const manifestPath = path.join(artifactRoot, "timeline.json");
  writeFileInsideRootSync(config.projectRoot, manifestPath, `${JSON.stringify(manifest, null, 2)}\n`);
  return {
    ...manifest,
    manifest_path: manifestPath,
  };
}

function disabledBaselineComparison(baselineName: string | undefined, baselinePath: string | undefined, frameCount: number): JsonObject {
  return {
    status: "disabled",
    baseline_name: baselineName,
    baseline_path: baselinePath,
    frame_count_considered: frameCount,
    frame_count_compared: 0,
    mitigation: "trusted_visual_input_provenance_unavailable",
    message: "Visual comparison is disabled until both inputs have Bridge-owned provenance and live screenshot permission can be verified.",
  };
}

function frameFromEnvelope(
  index: number,
  requestedAt: string,
  completedAt: string,
  latencyMs: number,
  envelope: ToolEnvelope,
): JsonObject {
  const response = objectOrUndefined(envelope.response);
  const data = objectOrUndefined(response?.data);
  const screenshot = objectOrUndefined(data?.screenshot);
  const error = objectOrUndefined(envelope.error) ?? objectOrUndefined(response?.error);
  const status: ToolStatus = envelope.status === "ok" && screenshot ? "ok" : envelope.status === "ok" ? "error" : envelope.status;

  const frame: JsonObject = {
    index,
    ordinal: index + 1,
    status,
    requested_at: requestedAt,
    completed_at: completedAt,
    latency_ms: latencyMs,
  };

  if (typeof envelope.request_id === "string") {
    frame.request_id = envelope.request_id;
  }
  if (typeof envelope.transport === "string") {
    frame.transport = envelope.transport;
  }
  if (screenshot) {
    frame.screenshot = screenshot;
    const artifact = objectOrUndefined(screenshot.artifact);
    if (artifact) {
      frame.artifact = artifact;
    }
  }
  if (status !== "ok") {
    frame.error = error ?? {
      code: "screenshot_metadata_missing",
      message: "Addon screenshot response did not include screenshot metadata.",
    };
  }

  return frame;
}

function makeCaptureId(): string {
  const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
  return `timeline_${timestamp}_${randomUUID().slice(0, 8)}`;
}

function sanitizeReason(value: string | undefined): string {
  if (!value) {
    return "";
  }
  return value
    .trim()
    .replace(/[\r\n]+/g, " ")
    .slice(0, 120);
}

function objectOrUndefined(value: unknown): JsonObject | undefined {
  return isJsonObject(value) ? value : undefined;
}

function clampInteger(value: number, min: number, max: number): number {
  if (!Number.isFinite(value)) {
    return min;
  }
  return Math.min(Math.max(Math.floor(value), min), max);
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
