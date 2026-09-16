import { createHash } from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import { inflateSync } from "node:zlib";

import type { JsonObject, ToolEnvelope } from "./types.js";

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

interface ValidatedPng {
  path: string;
}

interface PngMetadata extends JsonObject {
  width: number;
  height: number;
  byte_size: number;
  sha256: string;
}

interface DecodedPng {
  width: number;
  height: number;
  rgba: Uint8Array;
}

export async function createVisualBaseline(
  bridgeDir: string,
  options: { screenshotPath: string; baselineName?: string },
): Promise<ToolEnvelope> {
  const source = await validatePngPath(options.screenshotPath);
  if (!isValidatedPng(source)) {
    return source;
  }

  const baselineName = safeName(options.baselineName ?? path.basename(source.path, ".png"));
  const baselineRoot = path.join(bridgeDir, "artifacts", "visual_regression", "baselines", baselineName);
  await fs.mkdir(baselineRoot, { recursive: true });

  const baselinePath = path.join(baselineRoot, "baseline.png");
  await fs.copyFile(source.path, baselinePath);
  const metadata = await pngMetadata(baselinePath);
  const manifest = {
    status: "ok" as const,
    visual_regression_version: "godot-codex-bridge/visual-regression-v1",
    baseline_name: baselineName,
    created_at: new Date().toISOString(),
    source_path: source.path,
    baseline_path: baselinePath,
    metadata,
  };
  const manifestPath = path.join(baselineRoot, "manifest.json");
  await fs.writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");
  return { ...manifest, manifest_path: manifestPath };
}

export async function compareVisualRegression(
  bridgeDir: string,
  options: { currentScreenshotPath: string; baselineName?: string; baselinePath?: string },
): Promise<ToolEnvelope> {
  const current = await validatePngPath(options.currentScreenshotPath);
  if (!isValidatedPng(current)) {
    return current;
  }

  const baselinePath = options.baselinePath ?? (options.baselineName
    ? path.join(bridgeDir, "artifacts", "visual_regression", "baselines", safeName(options.baselineName), "baseline.png")
    : "");
  const baseline = await validatePngPath(baselinePath);
  if (!isValidatedPng(baseline)) {
    return {
      status: "invalid_request",
      error: {
        code: "baseline_unavailable",
        message: "Baseline PNG was not found or is invalid.",
        details: baseline.error,
      },
    };
  }

  const baselineMetadata = await pngMetadata(baseline.path);
  const currentMetadata = await pngMetadata(current.path);
  const exactMatch = baselineMetadata.sha256 === currentMetadata.sha256;
  const dimensionsMatch =
    baselineMetadata.width === currentMetadata.width &&
    baselineMetadata.height === currentMetadata.height;
  const pixelDiff = await comparePngPixels(baseline.path, current.path, dimensionsMatch);

  const result = {
    status: "ok" as const,
    visual_regression_version: "godot-codex-bridge/visual-regression-v1",
    compared_at: new Date().toISOString(),
    baseline_path: baseline.path,
    current_path: current.path,
    exact_match: exactMatch,
    dimensions_match: dimensionsMatch,
    byte_size_delta: currentMetadata.byte_size - baselineMetadata.byte_size,
    baseline: baselineMetadata,
    current: currentMetadata,
    pixel_diff: pixelDiff,
  };

  const compareRoot = path.join(bridgeDir, "artifacts", "visual_regression", "comparisons");
  await fs.mkdir(compareRoot, { recursive: true });
  const resultPath = path.join(compareRoot, `${new Date().toISOString().replace(/[:.]/g, "-")}.json`);
  await fs.writeFile(resultPath, `${JSON.stringify(result, null, 2)}\n`, "utf8");
  return { ...result, result_path: resultPath };
}

async function validatePngPath(filePath: string): Promise<ValidatedPng | ToolEnvelope> {
  if (!filePath || typeof filePath !== "string") {
    return invalid("path_required", "A PNG path is required.");
  }
  if (path.extname(filePath).toLowerCase() !== ".png") {
    return invalid("png_required", "Visual regression artifacts must be PNG files.");
  }
  try {
    const handle = await fs.open(filePath, "r");
    try {
      const signature = Buffer.alloc(PNG_SIGNATURE.length);
      await handle.read(signature, 0, PNG_SIGNATURE.length, 0);
      if (!signature.equals(PNG_SIGNATURE)) {
        return invalid("invalid_png_signature", "File does not have a PNG signature.");
      }
    } finally {
      await handle.close();
    }
    return { path: path.resolve(filePath) };
  } catch {
    return invalid("png_not_found", "PNG file was not found.");
  }
}

async function pngMetadata(filePath: string): Promise<PngMetadata> {
  const buffer = await fs.readFile(filePath);
  return {
    width: buffer.readUInt32BE(16),
    height: buffer.readUInt32BE(20),
    byte_size: buffer.byteLength,
    sha256: createHash("sha256").update(buffer).digest("hex"),
  };
}

async function comparePngPixels(baselinePath: string, currentPath: string, dimensionsMatch: boolean): Promise<JsonObject> {
  if (!dimensionsMatch) {
    return {
      status: "skipped",
      reason: "PNG dimensions differ; pixel-by-pixel diff requires matching dimensions.",
    };
  }

  try {
    const baseline = decodePng(await fs.readFile(baselinePath));
    const current = decodePng(await fs.readFile(currentPath));
    if (baseline.width !== current.width || baseline.height !== current.height) {
      return {
        status: "skipped",
        reason: "Decoded PNG dimensions differ; pixel-by-pixel diff requires matching dimensions.",
      };
    }

    let changedPixels = 0;
    let totalChannelDelta = 0;
    let maxChannelDelta = 0;
    const totalPixels = baseline.width * baseline.height;
    for (let offset = 0; offset < baseline.rgba.length; offset += 4) {
      let pixelChanged = false;
      for (let channel = 0; channel < 4; channel += 1) {
        const delta = Math.abs(baseline.rgba[offset + channel] - current.rgba[offset + channel]);
        if (delta > 0) {
          pixelChanged = true;
          totalChannelDelta += delta;
          maxChannelDelta = Math.max(maxChannelDelta, delta);
        }
      }
      if (pixelChanged) {
        changedPixels += 1;
      }
    }

    return {
      status: "available",
      compared_pixels: totalPixels,
      changed_pixels: changedPixels,
      changed_ratio: totalPixels === 0 ? 0 : changedPixels / totalPixels,
      rgba_channel_mean_absolute_error: totalPixels === 0 ? 0 : totalChannelDelta / (totalPixels * 4),
      rgba_channel_max_delta: maxChannelDelta,
    };
  } catch (error) {
    return {
      status: "unavailable",
      reason: error instanceof Error ? error.message : "PNG pixel decoding failed.",
    };
  }
}

function decodePng(buffer: Buffer): DecodedPng {
  if (!buffer.subarray(0, PNG_SIGNATURE.length).equals(PNG_SIGNATURE)) {
    throw new Error("PNG signature is invalid.");
  }

  let offset = PNG_SIGNATURE.length;
  let width = 0;
  let height = 0;
  let bitDepth = 0;
  let colorType = 0;
  let palette: Buffer | null = null;
  const idatChunks: Buffer[] = [];

  while (offset + 12 <= buffer.length) {
    const length = buffer.readUInt32BE(offset);
    const type = buffer.toString("ascii", offset + 4, offset + 8);
    const dataStart = offset + 8;
    const dataEnd = dataStart + length;
    if (dataEnd + 4 > buffer.length) {
      throw new Error("PNG chunk is truncated.");
    }
    const data = buffer.subarray(dataStart, dataEnd);

    if (type === "IHDR") {
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      bitDepth = data[8];
      colorType = data[9];
      const compression = data[10];
      const filter = data[11];
      const interlace = data[12];
      if (compression !== 0 || filter !== 0 || interlace !== 0) {
        throw new Error("Only non-interlaced standard PNG streams are supported for pixel diff.");
      }
    } else if (type === "PLTE") {
      palette = data;
    } else if (type === "IDAT") {
      idatChunks.push(data);
    } else if (type === "IEND") {
      break;
    }

    offset = dataEnd + 4;
  }

  if (width <= 0 || height <= 0) {
    throw new Error("PNG IHDR is missing or invalid.");
  }
  if (bitDepth !== 8) {
    throw new Error("Only 8-bit PNG images are supported for pixel diff.");
  }

  const channelCount = channelsForColorType(colorType);
  const bytesPerPixel = channelCount;
  const scanlineLength = width * channelCount;
  const inflated = inflateSync(Buffer.concat(idatChunks));
  const expectedLength = height * (1 + scanlineLength);
  if (inflated.length < expectedLength) {
    throw new Error("PNG image data is shorter than expected.");
  }

  const raw = Buffer.alloc(height * scanlineLength);
  let inputOffset = 0;
  for (let y = 0; y < height; y += 1) {
    const filter = inflated[inputOffset];
    inputOffset += 1;
    const rowStart = y * scanlineLength;
    const previousRowStart = rowStart - scanlineLength;
    for (let x = 0; x < scanlineLength; x += 1) {
      const value = inflated[inputOffset + x];
      const left = x >= bytesPerPixel ? raw[rowStart + x - bytesPerPixel] : 0;
      const up = y > 0 ? raw[previousRowStart + x] : 0;
      const upLeft = y > 0 && x >= bytesPerPixel ? raw[previousRowStart + x - bytesPerPixel] : 0;
      raw[rowStart + x] = unfilterByte(filter, value, left, up, upLeft);
    }
    inputOffset += scanlineLength;
  }

  return {
    width,
    height,
    rgba: convertToRgba(raw, width, height, colorType, palette),
  };
}

function channelsForColorType(colorType: number): number {
  switch (colorType) {
    case 0:
      return 1;
    case 2:
      return 3;
    case 3:
      return 1;
    case 4:
      return 2;
    case 6:
      return 4;
    default:
      throw new Error(`Unsupported PNG color type for pixel diff: ${colorType}.`);
  }
}

function unfilterByte(filter: number, value: number, left: number, up: number, upLeft: number): number {
  switch (filter) {
    case 0:
      return value;
    case 1:
      return (value + left) & 0xff;
    case 2:
      return (value + up) & 0xff;
    case 3:
      return (value + Math.floor((left + up) / 2)) & 0xff;
    case 4:
      return (value + paeth(left, up, upLeft)) & 0xff;
    default:
      throw new Error(`Unsupported PNG row filter: ${filter}.`);
  }
}

function paeth(left: number, up: number, upLeft: number): number {
  const estimate = left + up - upLeft;
  const leftDistance = Math.abs(estimate - left);
  const upDistance = Math.abs(estimate - up);
  const upLeftDistance = Math.abs(estimate - upLeft);
  if (leftDistance <= upDistance && leftDistance <= upLeftDistance) {
    return left;
  }
  if (upDistance <= upLeftDistance) {
    return up;
  }
  return upLeft;
}

function convertToRgba(raw: Buffer, width: number, height: number, colorType: number, palette: Buffer | null): Uint8Array {
  const totalPixels = width * height;
  const rgba = new Uint8Array(totalPixels * 4);
  let rawOffset = 0;
  for (let pixel = 0; pixel < totalPixels; pixel += 1) {
    const out = pixel * 4;
    if (colorType === 0) {
      const gray = raw[rawOffset];
      rgba[out] = gray;
      rgba[out + 1] = gray;
      rgba[out + 2] = gray;
      rgba[out + 3] = 255;
      rawOffset += 1;
    } else if (colorType === 2) {
      rgba[out] = raw[rawOffset];
      rgba[out + 1] = raw[rawOffset + 1];
      rgba[out + 2] = raw[rawOffset + 2];
      rgba[out + 3] = 255;
      rawOffset += 3;
    } else if (colorType === 3) {
      if (!palette) {
        throw new Error("Indexed PNG is missing a PLTE chunk.");
      }
      const paletteOffset = raw[rawOffset] * 3;
      rgba[out] = palette[paletteOffset] ?? 0;
      rgba[out + 1] = palette[paletteOffset + 1] ?? 0;
      rgba[out + 2] = palette[paletteOffset + 2] ?? 0;
      rgba[out + 3] = 255;
      rawOffset += 1;
    } else if (colorType === 4) {
      const gray = raw[rawOffset];
      rgba[out] = gray;
      rgba[out + 1] = gray;
      rgba[out + 2] = gray;
      rgba[out + 3] = raw[rawOffset + 1];
      rawOffset += 2;
    } else if (colorType === 6) {
      rgba[out] = raw[rawOffset];
      rgba[out + 1] = raw[rawOffset + 1];
      rgba[out + 2] = raw[rawOffset + 2];
      rgba[out + 3] = raw[rawOffset + 3];
      rawOffset += 4;
    }
  }
  return rgba;
}

function isValidatedPng(value: ValidatedPng | ToolEnvelope): value is ValidatedPng {
  return typeof (value as ValidatedPng).path === "string";
}

function invalid(code: string, message: string): ToolEnvelope {
  return { status: "invalid_request", error: { code, message } };
}

function safeName(value: string): string {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9_-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 64) || "baseline";
}
