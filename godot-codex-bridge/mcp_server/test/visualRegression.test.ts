import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { deflateSync } from "node:zlib";

import { compareVisualRegression, createVisualBaseline, visualRegressionTestSupport } from "../src/visualRegression.js";

const ONE_BY_ONE_PNG = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=",
  "base64",
);

test("visual regression baseline and compare exact match", async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-visual-"));
  const bridgeDir = path.join(root, ".godot", "godot_codex_bridge");
  const pngPath = path.join(bridgeDir, "artifacts", "screenshots", "shot.png");
  await fs.mkdir(path.dirname(pngPath), { recursive: true });
  await fs.writeFile(pngPath, ONE_BY_ONE_PNG);

  const baseline = await createVisualBaseline(bridgeDir, {
    screenshotPath: pngPath,
    baselineName: "main",
  });
  await installBaseline(bridgeDir, "main", ONE_BY_ONE_PNG);
  const comparison = await visualRegressionTestSupport.compareTrustedArtifacts(root, bridgeDir, {
    currentScreenshotPath: pngPath,
    baselineName: "main",
  });

  assert.equal(baseline.status, "bridge_unavailable");
  assert.equal(baseline.created, false);
  assert.equal(baseline.error?.code, "trusted_screenshot_permission_unavailable");
  assert.equal(comparison.status, "ok");
  assert.equal(comparison.exact_match, true);
  assert.equal(comparison.dimensions_match, true);
  assert.equal((comparison.pixel_diff as { status: string; changed_pixels: number }).status, "available");
  assert.equal((comparison.pixel_diff as { status: string; changed_pixels: number }).changed_pixels, 0);
});

test("visual regression reports pixel differences for matching 8-bit RGBA PNGs", async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-visual-pixels-"));
  const bridgeDir = path.join(root, ".godot", "godot_codex_bridge");
  const screenshotRoot = path.join(bridgeDir, "artifacts", "screenshots");
  await fs.mkdir(screenshotRoot, { recursive: true });
  const baselinePath = path.join(screenshotRoot, "baseline.png");
  const currentPath = path.join(screenshotRoot, "current.png");
  await fs.writeFile(baselinePath, makeRgbaPng(2, 1, [
    [255, 0, 0, 255],
    [0, 255, 0, 255],
  ]));
  await fs.writeFile(currentPath, makeRgbaPng(2, 1, [
    [255, 0, 0, 255],
    [0, 0, 255, 255],
  ]));

  const baseline = await createVisualBaseline(bridgeDir, {
    screenshotPath: baselinePath,
    baselineName: "pixels",
  });
  await installBaseline(bridgeDir, "pixels", await fs.readFile(baselinePath));
  const comparison = await visualRegressionTestSupport.compareTrustedArtifacts(root, bridgeDir, {
    currentScreenshotPath: currentPath,
    baselineName: "pixels",
  });

  const pixelDiff = comparison.pixel_diff as {
    status: string;
    compared_pixels: number;
    changed_pixels: number;
    changed_ratio: number;
    rgba_channel_max_delta: number;
  };
  assert.equal(baseline.status, "bridge_unavailable");
  assert.equal(baseline.created, false);
  assert.equal(comparison.status, "ok");
  assert.equal(comparison.exact_match, false);
  assert.equal(comparison.dimensions_match, true);
  assert.equal(pixelDiff.status, "available");
  assert.equal(pixelDiff.compared_pixels, 2);
  assert.equal(pixelDiff.changed_pixels, 1);
  assert.equal(pixelDiff.changed_ratio, 0.5);
  assert.equal(pixelDiff.rgba_channel_max_delta, 255);
});

test("visual regression rejects PNG inputs outside bridge artifacts", async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-visual-outside-"));
  const bridgeDir = path.join(root, ".godot", "godot_codex_bridge");
  const outsidePath = path.join(root, "outside.png");
  await fs.writeFile(outsidePath, ONE_BY_ONE_PNG);
  await installBaseline(bridgeDir, "confined", ONE_BY_ONE_PNG);

  const comparison = await visualRegressionTestSupport.compareTrustedArtifacts(root, bridgeDir, {
    currentScreenshotPath: outsidePath,
    baselineName: "confined",
  });

  assert.equal(comparison.status, "invalid_request");
  assert.equal(comparison.error?.code, "path_boundary_rejected");
});

test("visual regression bounds hostile PNG dimensions before inflation", async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-visual-bounds-"));
  const bridgeDir = path.join(root, ".godot", "godot_codex_bridge");
  const screenshotRoot = path.join(bridgeDir, "artifacts", "screenshots");
  await fs.mkdir(screenshotRoot, { recursive: true });
  const hostilePath = path.join(screenshotRoot, "hostile.png");
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(100_000, 0);
  ihdr.writeUInt32BE(100_000, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  const hostilePng = Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    pngChunk("IHDR", ihdr),
    pngChunk("IDAT", deflateSync(Buffer.from([0]))),
    pngChunk("IEND", Buffer.alloc(0)),
  ]);
  await fs.writeFile(hostilePath, hostilePng);
  await installBaseline(bridgeDir, "bounded", hostilePng);

  const comparison = await visualRegressionTestSupport.compareTrustedArtifacts(root, bridgeDir, {
    currentScreenshotPath: hostilePath,
    baselineName: "bounded",
  });

  assert.equal(comparison.status, "ok");
  assert.equal((comparison.pixel_diff as { status: string }).status, "unavailable");
  assert.match(String((comparison.pixel_diff as { reason: string }).reason), /dimensions exceed/);
  assert.equal(comparison.dimensions_match, true);
});

test("production visual comparison fails closed without live permission and provenance", async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-visual-disabled-"));
  const bridgeDir = path.join(root, ".godot", "godot_codex_bridge");
  const comparison = await compareVisualRegression(root, bridgeDir, {
    currentScreenshotPath: path.join(bridgeDir, "artifacts", "private.png"),
    baselinePath: path.join(bridgeDir, "artifacts", "baseline.png"),
  });

  assert.equal(comparison.status, "bridge_unavailable");
  assert.equal(comparison.compared, false);
  assert.equal(comparison.error?.code, "trusted_visual_input_provenance_unavailable");
});

async function installBaseline(bridgeDir: string, name: string, contents: Buffer): Promise<void> {
  const baselineRoot = path.join(bridgeDir, "artifacts", "visual_regression", "baselines", name);
  await fs.mkdir(baselineRoot, { recursive: true });
  await fs.writeFile(path.join(baselineRoot, "baseline.png"), contents);
}

function makeRgbaPng(width: number, height: number, pixels: Array<[number, number, number, number]>): Buffer {
  const signature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;

  const rows: number[] = [];
  for (let y = 0; y < height; y += 1) {
    rows.push(0);
    for (let x = 0; x < width; x += 1) {
      const pixel = pixels[y * width + x] ?? [0, 0, 0, 255];
      rows.push(...pixel);
    }
  }

  return Buffer.concat([
    signature,
    pngChunk("IHDR", ihdr),
    pngChunk("IDAT", deflateSync(Buffer.from(rows))),
    pngChunk("IEND", Buffer.alloc(0)),
  ]);
}

function pngChunk(type: string, data: Buffer): Buffer {
  const typeBuffer = Buffer.from(type, "ascii");
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length, 0);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([typeBuffer, data])), 0);
  return Buffer.concat([length, typeBuffer, data, crc]);
}

function crc32(buffer: Buffer): number {
  let crc = 0xffffffff;
  for (const byte of buffer) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) {
      crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}
