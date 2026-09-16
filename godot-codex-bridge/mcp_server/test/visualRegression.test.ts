import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { deflateSync } from "node:zlib";

import { compareVisualRegression, createVisualBaseline } from "../src/visualRegression.js";

const ONE_BY_ONE_PNG = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII=",
  "base64",
);

test("visual regression baseline and compare exact match", async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-visual-"));
  const bridgeDir = path.join(root, ".godot", "godot_codex_bridge");
  const pngPath = path.join(root, "shot.png");
  await fs.writeFile(pngPath, ONE_BY_ONE_PNG);

  const baseline = await createVisualBaseline(bridgeDir, {
    screenshotPath: pngPath,
    baselineName: "main",
  });
  const comparison = await compareVisualRegression(bridgeDir, {
    currentScreenshotPath: pngPath,
    baselineName: "main",
  });

  assert.equal(baseline.status, "ok");
  assert.equal(comparison.status, "ok");
  assert.equal(comparison.exact_match, true);
  assert.equal(comparison.dimensions_match, true);
  assert.equal((comparison.pixel_diff as { status: string; changed_pixels: number }).status, "available");
  assert.equal((comparison.pixel_diff as { status: string; changed_pixels: number }).changed_pixels, 0);
});

test("visual regression reports pixel differences for matching 8-bit RGBA PNGs", async () => {
  const root = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-visual-pixels-"));
  const bridgeDir = path.join(root, ".godot", "godot_codex_bridge");
  const baselinePath = path.join(root, "baseline.png");
  const currentPath = path.join(root, "current.png");
  await fs.writeFile(baselinePath, makeRgbaPng(2, 1, [
    [255, 0, 0, 255],
    [0, 255, 0, 255],
  ]));
  await fs.writeFile(currentPath, makeRgbaPng(2, 1, [
    [255, 0, 0, 255],
    [0, 0, 255, 255],
  ]));

  await createVisualBaseline(bridgeDir, {
    screenshotPath: baselinePath,
    baselineName: "pixels",
  });
  const comparison = await compareVisualRegression(bridgeDir, {
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
  assert.equal(comparison.status, "ok");
  assert.equal(comparison.exact_match, false);
  assert.equal(comparison.dimensions_match, true);
  assert.equal(pixelDiff.status, "available");
  assert.equal(pixelDiff.compared_pixels, 2);
  assert.equal(pixelDiff.changed_pixels, 1);
  assert.equal(pixelDiff.changed_ratio, 0.5);
  assert.equal(pixelDiff.rgba_channel_max_delta, 255);
});

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
