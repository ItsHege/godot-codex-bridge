import fs from "node:fs/promises";
import path from "node:path";

import type { JsonObject, ToolEnvelope } from "./types.js";

const ANNOTATIONS_DIR = path.join("artifacts", "annotations");
const MAX_ANNOTATION_JSON_BYTES = 256_000;
const MAX_ANNOTATIONS_RETURNED = 100;
const ANNOTATION_ID_PATTERN = /^[A-Za-z0-9_.-]+$/;

export async function listAnnotations(
  bridgeDir: string,
  options: { limit?: number } = {},
): Promise<ToolEnvelope> {
  const baseDir = annotationsDir(bridgeDir);
  const limit = boundedLimit(options.limit);
  let entries: string[];
  try {
    entries = await fs.readdir(baseDir);
  } catch {
    return {
      status: "ok",
      annotations_version: "godot-codex-bridge/annotations-v1",
      annotations_dir: baseDir,
      annotations: [],
      returned_count: 0,
    };
  }

  const annotations = [];
  for (const entry of entries) {
    if (!isValidAnnotationId(entry)) {
      continue;
    }
    const envelope = await readAnnotationById(bridgeDir, entry, { includeManifest: false });
    if (envelope.status === "ok") {
      annotations.push(annotationListItem(envelope));
    }
  }
  annotations.sort((a, b) => String(b.captured_at ?? "").localeCompare(String(a.captured_at ?? "")));

  return {
    status: "ok",
    annotations_version: "godot-codex-bridge/annotations-v1",
    annotations_dir: baseDir,
    annotations: annotations.slice(0, limit),
    returned_count: Math.min(annotations.length, limit),
    total_count: annotations.length,
  };
}

export async function getLatestAnnotation(bridgeDir: string): Promise<ToolEnvelope> {
  const listed = await listAnnotations(bridgeDir, { limit: 1 });
  const annotations = Array.isArray(listed.annotations) ? listed.annotations : [];
  const latest = annotations[0] as JsonObject | undefined;
  if (!latest || typeof latest.annotation_id !== "string") {
    return {
      status: "not_found",
      error: {
        code: "annotation_not_found",
        message: "No annotation artifacts were found under the active bridge directory.",
      },
      annotations_dir: annotationsDir(bridgeDir),
    };
  }
  return getAnnotation(bridgeDir, latest.annotation_id);
}

export async function getAnnotation(bridgeDir: string, annotationId: string): Promise<ToolEnvelope> {
  return readAnnotationById(bridgeDir, annotationId, { includeManifest: true });
}

export async function resolveAnnotationTarget(
  bridgeDir: string,
  options: { annotationId?: string; markerId?: string } = {},
): Promise<ToolEnvelope> {
  const envelope = options.annotationId
    ? await getAnnotation(bridgeDir, options.annotationId)
    : await getLatestAnnotation(bridgeDir);
  if (envelope.status !== "ok") {
    return envelope;
  }
  const manifest = isJsonObject(envelope.annotation) ? envelope.annotation : {};
  const markers = Array.isArray(manifest.markers) ? manifest.markers.filter(isJsonObject) : [];
  const marker = selectMarker(markers, options.markerId);
  if (!marker) {
    return {
      status: "not_found",
      error: {
        code: "annotation_marker_not_found",
        message: options.markerId
          ? `Marker was not found in annotation: ${options.markerId}.`
          : "Annotation does not contain marker metadata.",
      },
      annotation_id: envelope.annotation_id,
      marker_id: options.markerId ?? null,
    };
  }

  const candidates = targetCandidates(manifest);
  const confidence = candidates.reduce((max, candidate) => Math.max(max, Number(candidate.confidence ?? 0)), 0);
  return {
    status: "ok",
    annotations_version: "godot-codex-bridge/annotations-v1",
    target_resolution_version: "godot-codex-bridge/annotation-target-v1",
    annotation_id: envelope.annotation_id,
    marker_id: String(marker.id ?? marker.label ?? "A"),
    marker: markerPayload(marker),
    resolution_status: candidates.length > 0 ? "candidate" : "insufficient_context",
    confidence,
    candidates,
    world_ray_supported: false,
    world_hit: null,
    overclaim_guardrail: "This resolver uses annotation metadata and capture-time editor context only. It does not claim pixel-perfect inspector fields, viewport ray hits or world-space targets without a future typed ray/crop contract.",
    suggested_next_tools: suggestedNextTools(candidates),
  };
}

async function readAnnotationById(
  bridgeDir: string,
  annotationId: string,
  options: { includeManifest: boolean },
): Promise<ToolEnvelope> {
  if (!isValidAnnotationId(annotationId)) {
    return {
      status: "invalid_request",
      error: {
        code: "invalid_annotation_id",
        message: "annotationId must contain only letters, numbers, dot, underscore or dash.",
      },
    };
  }

  const baseDir = annotationsDir(bridgeDir);
  const annotationDir = path.resolve(baseDir, annotationId);
  if (!isInside(baseDir, annotationDir)) {
    return {
      status: "invalid_request",
      error: {
        code: "invalid_annotation_path",
        message: "annotationId resolved outside the bridge annotations directory.",
      },
    };
  }

  const manifestPath = path.join(annotationDir, "annotation.json");
  let stat;
  try {
    stat = await fs.stat(manifestPath);
  } catch {
    return {
      status: "not_found",
      error: {
        code: "annotation_not_found",
        message: `Annotation artifact was not found: ${annotationId}.`,
      },
      annotation_id: annotationId,
      artifact_dir: annotationDir,
    };
  }
  if (!stat.isFile()) {
    return {
      status: "invalid_request",
      error: {
        code: "annotation_manifest_invalid",
        message: "annotation.json is not a file.",
      },
      annotation_id: annotationId,
      artifact_dir: annotationDir,
    };
  }
  if (stat.size > MAX_ANNOTATION_JSON_BYTES) {
    return {
      status: "invalid_request",
      error: {
        code: "annotation_manifest_too_large",
        message: `annotation.json exceeds ${MAX_ANNOTATION_JSON_BYTES} bytes.`,
      },
      annotation_id: annotationId,
      artifact_dir: annotationDir,
    };
  }

  let manifest: JsonObject;
  try {
    manifest = JSON.parse(await fs.readFile(manifestPath, "utf8")) as JsonObject;
  } catch (error) {
    return {
      status: "invalid_request",
      error: {
        code: "annotation_manifest_invalid",
        message: (error as Error).message,
      },
      annotation_id: annotationId,
      artifact_dir: annotationDir,
    };
  }

  const rawImagePath = path.join(annotationDir, "raw.png");
  const annotatedImagePath = path.join(annotationDir, "annotated.png");
  const imageStatus = await annotationImageStatus(rawImagePath, annotatedImagePath);

  return {
    status: "ok",
    annotations_version: "godot-codex-bridge/annotations-v1",
    annotation_id: annotationId,
    annotation_role: manifest.annotation_role,
    capture_scope: manifest.capture_scope,
    captured_at: manifest.captured_at ?? manifest.created_at,
    marker_count: Array.isArray(manifest.markers) ? manifest.markers.length : 0,
    markers: Array.isArray(manifest.markers) ? manifest.markers : [],
    manifest_path: manifestPath,
    artifact_dir: annotationDir,
    raw_image_path: rawImagePath,
    annotated_image_path: annotatedImagePath,
    image_status: imageStatus,
    annotation: options.includeManifest ? manifest : undefined,
    privacy: {
      classification: "local_sensitive_evidence",
      external_upload_allowed: false,
      notes: ["Local editor annotation evidence only."],
    },
  };
}

async function annotationImageStatus(rawImagePath: string, annotatedImagePath: string): Promise<JsonObject> {
  const [raw, annotated] = await Promise.all([
    fileSummary(rawImagePath),
    fileSummary(annotatedImagePath),
  ]);
  return {
    raw_exists: raw.exists,
    raw_byte_size: raw.byteSize,
    annotated_exists: annotated.exists,
    annotated_byte_size: annotated.byteSize,
  };
}

async function fileSummary(filePath: string): Promise<{ exists: boolean; byteSize: number }> {
  try {
    const stat = await fs.stat(filePath);
    return { exists: stat.isFile(), byteSize: stat.isFile() ? stat.size : 0 };
  } catch {
    return { exists: false, byteSize: 0 };
  }
}

function annotationListItem(envelope: ToolEnvelope): JsonObject {
  return {
    annotation_id: envelope.annotation_id,
    annotation_role: envelope.annotation_role,
    capture_scope: envelope.capture_scope,
    captured_at: envelope.captured_at,
    marker_count: envelope.marker_count,
    manifest_path: envelope.manifest_path,
    annotated_image_path: envelope.annotated_image_path,
  };
}

function selectMarker(markers: JsonObject[], markerId?: string): JsonObject | null {
  if (!markerId) {
    return markers[0] ?? null;
  }
  return markers.find((marker) => String(marker.id ?? marker.label ?? "") === markerId) ?? null;
}

function markerPayload(marker: JsonObject): JsonObject {
  const bounds = isJsonObject(marker.normalized_bounds) ? marker.normalized_bounds : null;
  const center = markerCenter(marker);
  return {
    id: String(marker.id ?? marker.label ?? "A"),
    label: String(marker.label ?? marker.id ?? "A"),
    type: typeof marker.type === "string" ? marker.type : "unknown",
    normalized_bounds: bounds,
    normalized_center: center,
  };
}

function markerCenter(marker: JsonObject): JsonObject | null {
  const bounds = isJsonObject(marker.normalized_bounds) ? marker.normalized_bounds : null;
  if (bounds) {
    const x = finiteNumber(bounds.x);
    const y = finiteNumber(bounds.y);
    const w = finiteNumber(bounds.w);
    const h = finiteNumber(bounds.h);
    if (x !== null && y !== null && w !== null && h !== null) {
      return {
        x: round4(x + w / 2),
        y: round4(y + h / 2),
      };
    }
  }
  const point = isJsonObject(marker.normalized_point) ? marker.normalized_point : null;
  if (point) {
    const x = finiteNumber(point.x);
    const y = finiteNumber(point.y);
    if (x !== null && y !== null) {
      return { x: round4(x), y: round4(y) };
    }
  }
  return null;
}

function targetCandidates(manifest: JsonObject): JsonObject[] {
  const candidates: JsonObject[] = [];
  const selectedNodes = Array.isArray(manifest.selected_nodes) ? manifest.selected_nodes.filter(isJsonObject).slice(0, 5) : [];
  for (const node of selectedNodes) {
    const nodePath = stringField(node, ["path", "node_path"]);
    candidates.push({
      target_kind: "selected_node_context",
      confidence: selectedNodes.length === 1 ? 0.55 : 0.45,
      node_path: nodePath,
      node_name: stringField(node, ["name"]),
      node_type: stringField(node, ["type", "class"]),
      reason: "The annotation manifest recorded this selected node at capture time. Treat it as contextual evidence, not a pixel hit test.",
      supported_editor_actions: nodePath ? [{ tool: "godot.select_node", args: { nodePath } }] : [],
    });
  }

  const currentScene = manifest.current_scene;
  if (isJsonObject(currentScene)) {
    const scenePath = stringField(currentScene, ["path", "scene_path"]);
    if (scenePath) {
      candidates.push({
        target_kind: "current_scene_context",
        confidence: selectedNodes.length > 0 ? 0.35 : 0.3,
        scene_path: scenePath,
        scene_name: stringField(currentScene, ["name"]),
        reason: "The annotation was captured while this scene was active; no narrower node or world target was proven.",
        supported_editor_actions: [{ tool: "godot.open_scene", args: { scenePath } }],
      });
    }
  } else if (typeof currentScene === "string" && currentScene.startsWith("res://")) {
    candidates.push({
      target_kind: "current_scene_context",
      confidence: 0.3,
      scene_path: currentScene,
      reason: "The annotation was captured while this scene was active; no narrower node or world target was proven.",
      supported_editor_actions: [{ tool: "godot.open_scene", args: { scenePath: currentScene } }],
    });
  }

  return candidates;
}

function suggestedNextTools(candidates: JsonObject[]): JsonObject[] {
  return candidates.flatMap((candidate) => {
    const actions = candidate.supported_editor_actions;
    return Array.isArray(actions) ? actions.filter(isJsonObject) : [];
  }).slice(0, 6);
}

function stringField(source: JsonObject, keys: string[]): string | null {
  for (const key of keys) {
    const value = source[key];
    if (typeof value === "string" && value.length > 0) {
      return value;
    }
  }
  return null;
}

function finiteNumber(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function round4(value: number): number {
  return Math.round(value * 10000) / 10000;
}

function annotationsDir(bridgeDir: string): string {
  return path.join(path.resolve(bridgeDir), ANNOTATIONS_DIR);
}

function boundedLimit(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value)
    ? Math.max(1, Math.min(Math.floor(value), MAX_ANNOTATIONS_RETURNED))
    : 20;
}

function isValidAnnotationId(value: string): boolean {
  return value.length > 0 && value.length <= 128 && ANNOTATION_ID_PATTERN.test(value) && !value.includes("..");
}

function isInside(baseDir: string, candidate: string): boolean {
  const relative = path.relative(path.resolve(baseDir), path.resolve(candidate));
  return relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative));
}

function isJsonObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
