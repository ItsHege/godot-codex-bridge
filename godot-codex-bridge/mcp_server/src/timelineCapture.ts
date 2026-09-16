import { randomUUID } from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";

import { BridgeClient, isJsonObject } from "./bridge.js";
import type { JsonObject, ServerConfig, ToolEnvelope, ToolStatus } from "./types.js";
import { compareVisualRegression } from "./visualRegression.js";

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
  await fs.mkdir(artifactRoot, { recursive: true });

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
    manifest.baseline_comparison = await compareFramesToBaseline(config.bridgeDir, frames, {
      baselineName: options.baselineName,
      baselinePath: options.baselinePath,
    });
  }

  const manifestPath = path.join(artifactRoot, "timeline.json");
  await fs.writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");
  return {
    ...manifest,
    manifest_path: manifestPath,
  };
}

async function compareFramesToBaseline(
  bridgeDir: string,
  frames: JsonObject[],
  options: { baselineName?: string; baselinePath?: string },
): Promise<JsonObject> {
  const comparisons: JsonObject[] = [];
  for (const frame of frames) {
    if (frame.status !== "ok") {
      continue;
    }
    const screenshotPath = screenshotPathFromFrame(frame);
    if (!screenshotPath) {
      comparisons.push({
        frame_index: frame.index,
        frame_ordinal: frame.ordinal,
        status: "invalid_request",
        error: {
          code: "timeline_frame_screenshot_path_missing",
          message: "Timeline frame does not include a local screenshot PNG path for baseline comparison.",
        },
      });
      continue;
    }
    const comparison = await compareVisualRegression(bridgeDir, {
      currentScreenshotPath: screenshotPath,
      baselineName: options.baselineName,
      baselinePath: options.baselinePath,
    });
    comparisons.push({
      frame_index: frame.index,
      frame_ordinal: frame.ordinal,
      current_screenshot_path: screenshotPath,
      ...comparison,
    });
  }

  const compared = comparisons.filter((item) => item.status === "ok");
  const exactMatches = compared.filter((item) => item.exact_match === true).length;
  return {
    status: comparisons.length === 0
      ? "not_found"
      : comparisons.some((item) => item.status !== "ok")
        ? "partial"
        : "ok",
    baseline_name: options.baselineName,
    baseline_path: options.baselinePath,
    frame_count_considered: frames.length,
    frame_count_compared: compared.length,
    frame_count_with_errors: comparisons.length - compared.length,
    exact_match_count: exactMatches,
    changed_frame_count: compared.length - exactMatches,
    comparisons,
  };
}

function screenshotPathFromFrame(frame: JsonObject): string {
  const artifact = objectOrUndefined(frame.artifact);
  const screenshot = objectOrUndefined(frame.screenshot);
  const screenshotArtifact = objectOrUndefined(screenshot?.artifact);
  for (const candidate of [
    artifact?.local_path,
    artifact?.absolute_path,
    screenshotArtifact?.local_path,
    screenshotArtifact?.absolute_path,
    screenshot?.local_path,
  ]) {
    if (typeof candidate === "string" && candidate.trim().length > 0) {
      return candidate;
    }
  }
  return "";
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
