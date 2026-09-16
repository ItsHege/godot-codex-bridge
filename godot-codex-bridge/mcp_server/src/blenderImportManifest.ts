import fs from "node:fs/promises";
import path from "node:path";

import { isInsidePath } from "./config.js";
import { isJsonObject } from "./bridge.js";
import type { JsonObject, JsonValue, ServerConfig, ToolEnvelope } from "./types.js";

const ALLOWLIST_ROOT = "res://assets/ai_imports/blender";
const SUPPORTED_ASSET_EXTENSIONS = [".glb", ".gltf", ".obj", ".fbx", ".dae", ".blend", ".tscn", ".scn", ".res", ".tres"];
const MAX_ASSETS = 50;
const MAX_MANIFEST_BYTES = 256 * 1024;
const MAX_METADATA_TEXT = 160;

export async function planBlenderAssetImport(config: ServerConfig, args: JsonObject = {}): Promise<ToolEnvelope> {
  const manifestPath = typeof args.manifestPath === "string" && args.manifestPath.trim() !== ""
    ? args.manifestPath.trim()
    : `${ALLOWLIST_ROOT}/manifest.json`;
  const manifestResPath = validateAllowlistedManifestPath(manifestPath);
  const manifestAbsPath = resPathToAbsolute(config.projectRoot, manifestResPath);
  const allowlistAbsRoot = resPathToAbsolute(config.projectRoot, ALLOWLIST_ROOT);
  if (!isInsidePath(allowlistAbsRoot, manifestAbsPath)) {
    return invalid("invalid_manifest_path", "Manifest must stay inside res://assets/ai_imports/blender.");
  }

  let parsed: unknown;
  let manifestText = "";
  try {
    const stat = await fs.stat(manifestAbsPath);
    if (!stat.isFile()) {
      return invalid("invalid_manifest_path", "Manifest path must point to a file.", {
        manifest_path: manifestResPath,
      });
    }
    if (stat.size > MAX_MANIFEST_BYTES) {
      return invalid("blender_import_manifest_too_large", `Blender import manifest is limited to ${MAX_MANIFEST_BYTES} bytes.`, {
        manifest_path: manifestResPath,
        byte_size: stat.size,
        max_bytes: MAX_MANIFEST_BYTES,
      });
    }
    manifestText = await fs.readFile(manifestAbsPath, "utf8");
  } catch (error) {
    return {
      status: "not_found",
      manifest_path: manifestResPath,
      error: {
        code: "blender_import_manifest_unavailable",
        message: error instanceof Error ? error.message : String(error),
      },
    };
  }
  try {
    parsed = JSON.parse(manifestText) as unknown;
  } catch (error) {
    return invalid("invalid_blender_import_manifest_json", "Blender import manifest must be valid JSON.", {
      manifest_path: manifestResPath,
      parse_error: error instanceof Error ? boundedErrorMessage(error.message) : "unknown parse error",
    });
  }
  if (!isJsonObject(parsed)) {
    return invalid("invalid_blender_import_manifest", "Blender import manifest must be a JSON object.", {
      manifest_path: manifestResPath,
    });
  }

  const rawAssets = Array.isArray(parsed.assets) ? parsed.assets : [];
  if (rawAssets.length > MAX_ASSETS) {
    return invalid("too_many_blender_assets", `Blender import manifest supports at most ${MAX_ASSETS} assets.`, {
      asset_count: rawAssets.length,
      max_assets: MAX_ASSETS,
    });
  }

  const assets: JsonObject[] = [];
  const rejected: JsonObject[] = [];
  for (const [index, rawAsset] of rawAssets.entries()) {
    const normalized = await normalizeManifestAsset(config, allowlistAbsRoot, rawAsset, index);
    if (normalized.status === "ok") {
      assets.push(normalized.asset);
    } else {
      rejected.push(normalized.rejected);
    }
  }
  const placeableAssets = assets.filter((asset) => asset.exists === true);

  return {
    status: "ok",
    manifest_version: boundedMetadataString(parsed.manifest_version),
    generated_at: boundedMetadataString(parsed.generated_at),
    source: boundedMetadataString(parsed.source) ?? "blender",
    allowlist_root: ALLOWLIST_ROOT,
    manifest_path: manifestResPath,
    asset_count: rawAssets.length,
    accepted_count: assets.length,
    rejected_count: rejected.length,
    placeable_count: placeableAssets.length,
    assets,
    rejected_assets: rejected,
    suggested_workflow: [
      {
        tool: "godot.inspect_imported_assets",
        args: {
          rootPath: ALLOWLIST_ROOT,
          placeableOnly: true,
          includeDependencies: true,
          limit: Math.max(1, Math.min(assets.length || 20, 50)),
        },
      },
      ...placeableAssets.map((asset) => ({
        tool: "godot.place_asset_in_scene",
        args: asset.place_asset_args,
      })),
    ],
    safety: {
      read_only: true,
      no_external_copy: true,
      no_overwrite: true,
      no_scene_mutation: true,
      placement_requires_separate_tool_call: true,
      placement_suggestions_require_existing_files: true,
      allowlist_root: ALLOWLIST_ROOT,
    },
  };
}

async function normalizeManifestAsset(
  config: ServerConfig,
  allowlistAbsRoot: string,
  rawAsset: unknown,
  index: number,
): Promise<
  | { status: "ok"; asset: JsonObject }
  | { status: "rejected"; rejected: JsonObject }
> {
  if (!isJsonObject(rawAsset)) {
    return rejected(index, "invalid_asset_entry", "Asset entry must be an object.");
  }
  const assetPathValue = rawAsset.asset_path ?? rawAsset.assetPath ?? rawAsset.path;
  if (typeof assetPathValue !== "string") {
    return rejected(index, "asset_path_required", "Asset entry needs asset_path.");
  }
  const assetPath = validateAllowlistedAssetPath(assetPathValue);
  if (!assetPath.ok) {
    return rejected(index, assetPath.code, assetPath.message, { asset_path: assetPathValue });
  }
  const absolutePath = resPathToAbsolute(config.projectRoot, assetPath.value);
  if (!isInsidePath(allowlistAbsRoot, absolutePath) || !isInsidePath(config.projectRoot, absolutePath)) {
    return rejected(index, "asset_path_outside_allowlist", "Asset path resolved outside the Blender AI import allowlist.", {
      asset_path: assetPath.value,
    });
  }
  let exists = true;
  try {
    await fs.access(absolutePath);
  } catch {
    exists = false;
  }

  const name = safeOptionalName(rawAsset.name ?? rawAsset.node_name ?? rawAsset.nodeName);
  const placeArgs: JsonObject = {
    assetPath: assetPath.value,
    parentPath: ".",
    select: true,
  };
  if (name) {
    placeArgs.name = name;
  }
  copyTransform(rawAsset, placeArgs, "position");
  copyTransform(rawAsset, placeArgs, "rotationDegrees");
  copyTransform(rawAsset, placeArgs, "scale");

  return {
    status: "ok",
    asset: {
      index,
      asset_path: assetPath.value,
      exists,
      name: name ?? null,
      placement_precondition: exists ? "asset_exists" : "asset_missing",
      place_asset_args: placeArgs,
    },
  };
}

function validateAllowlistedManifestPath(value: string): string {
  const normalized = normalizeResPath(value);
  if (!normalized.startsWith(`${ALLOWLIST_ROOT}/`)) {
    throwCoded("invalid_manifest_path", "Manifest must be under res://assets/ai_imports/blender.");
  }
  if (!normalized.toLowerCase().endsWith(".json")) {
    throwCoded("invalid_manifest_extension", "Manifest path must end with .json.");
  }
  return normalized;
}

function validateAllowlistedAssetPath(value: string): { ok: true; value: string } | { ok: false; code: string; message: string } {
  let normalized: string;
  try {
    normalized = normalizeResPath(value);
  } catch (error) {
    return { ok: false, code: codedErrorCode(error), message: error instanceof Error ? error.message : String(error) };
  }
  if (!normalized.startsWith(`${ALLOWLIST_ROOT}/`)) {
    return { ok: false, code: "asset_path_outside_allowlist", message: "Asset must be under res://assets/ai_imports/blender." };
  }
  const lower = normalized.toLowerCase();
  if (!SUPPORTED_ASSET_EXTENSIONS.some((extension) => lower.endsWith(extension))) {
    return { ok: false, code: "unsupported_blender_asset_extension", message: `Asset must end in one of: ${SUPPORTED_ASSET_EXTENSIONS.join(", ")}.` };
  }
  return { ok: true, value: normalized };
}

function normalizeResPath(value: string): string {
  if (!value.startsWith("res://")) {
    throwCoded("invalid_res_path", "Path must be a project-local res:// path.");
  }
  const resourcePath = value.slice("res://".length).replace(/\\/g, "/");
  if (resourcePath.length === 0 || resourcePath.split("/").some((part) => part === "" || part === "." || part === "..")) {
    throwCoded("invalid_res_path", "Path must not contain empty, current-directory or parent-directory segments.");
  }
  if (
    resourcePath.startsWith(".godot/") ||
    resourcePath.startsWith(".import/") ||
    resourcePath.includes("/.godot/") ||
    resourcePath.includes("/.import/")
  ) {
    throwCoded("invalid_res_path", "Generated Godot cache/import paths are not allowed.");
  }
  return `res://${resourcePath}`;
}

function resPathToAbsolute(projectRoot: string, resPath: string): string {
  const resourcePath = resPath.slice("res://".length).replace(/\\/g, "/");
  return path.resolve(path.resolve(projectRoot), ...resourcePath.split("/"));
}

function copyTransform(rawAsset: JsonObject, target: JsonObject, key: "position" | "rotationDegrees" | "scale"): void {
  const value = rawAsset[key];
  if (!isJsonObject(value)) {
    return;
  }
  const xyz: JsonObject = {};
  for (const axis of ["x", "y", "z"]) {
    const axisValue = value[axis];
    if (typeof axisValue === "number" && Number.isFinite(axisValue)) {
      xyz[axis] = axisValue;
    }
  }
  if (Object.keys(xyz).length > 0) {
    target[key] = xyz;
  }
}

function safeOptionalName(value: JsonValue | undefined): string | null {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  if (trimmed === "" || trimmed.length > 80 || !/^[A-Za-z_][A-Za-z0-9_ -]*$/.test(trimmed)) {
    return null;
  }
  return trimmed;
}

function boundedMetadataString(value: JsonValue | undefined): string | null {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  if (trimmed === "") {
    return null;
  }
  return trimmed.length > MAX_METADATA_TEXT ? `${trimmed.slice(0, MAX_METADATA_TEXT)}...` : trimmed;
}

function boundedErrorMessage(value: string): string {
  const trimmed = value.trim();
  return trimmed.length > MAX_METADATA_TEXT ? `${trimmed.slice(0, MAX_METADATA_TEXT)}...` : trimmed;
}

function rejected(index: number, code: string, message: string, extra: JsonObject = {}): { status: "rejected"; rejected: JsonObject } {
  return {
    status: "rejected",
    rejected: {
      index,
      code,
      message,
      ...extra,
    },
  };
}

function invalid(code: string, message: string, extra: JsonObject = {}): ToolEnvelope {
  return {
    status: "invalid_request",
    error: {
      code,
      message,
      ...extra,
    },
  };
}

function throwCoded(code: string, message: string): never {
  const error = new Error(message) as Error & { code: string };
  error.code = code;
  throw error;
}

function codedErrorCode(error: unknown): string {
  return error instanceof Error && "code" in error && typeof (error as { code?: unknown }).code === "string"
    ? String((error as { code: string }).code)
    : "invalid_res_path";
}
