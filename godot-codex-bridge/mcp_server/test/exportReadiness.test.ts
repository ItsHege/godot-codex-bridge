import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { checkExportReadiness } from "../src/exportReadiness.js";

test("checkExportReadiness reports configured desktop and mobile presets", async () => {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-export-"));
  await fs.mkdir(path.join(projectRoot, "scenes"), { recursive: true });
  await fs.writeFile(path.join(projectRoot, "scenes", "main.tscn"), "[gd_scene format=3]\n", "utf8");
  await fs.writeFile(
    path.join(projectRoot, "project.godot"),
    '[application]\nconfig/name="Fixture"\nrun/main_scene="res://scenes/main.tscn"\n',
    "utf8",
  );
  await fs.writeFile(
    path.join(projectRoot, "export_presets.cfg"),
    '[preset.0]\nname="Windows"\nplatform="Windows Desktop"\nrunnable=true\nexport_path="build/game.exe"\n\n[preset.1]\nname="Android"\nplatform="Android"\nrunnable=true\nexport_path="build/game.apk"\n',
    "utf8",
  );

  const result = await checkExportReadiness(projectRoot, process.execPath);

  assert.equal(result.status, "ok");
  assert.equal((result.summary as { ready_for_pc_export: boolean }).ready_for_pc_export, true);
  assert.equal((result.summary as { ready_for_mobile_export: boolean }).ready_for_mobile_export, true);
  assert.equal((result.summary as { export_presets_count: number }).export_presets_count, 2);
});

test("checkExportReadiness reports missing export presets", async () => {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-export-missing-"));
  await fs.writeFile(path.join(projectRoot, "project.godot"), "[application]\nconfig/name=\"Fixture\"\n", "utf8");

  const result = await checkExportReadiness(projectRoot, process.execPath);
  const findings = result.findings as Array<{ code: string }>;

  assert.equal(result.status, "ok");
  assert.ok(findings.some((finding) => finding.code === "main_scene_missing"));
  assert.ok(findings.some((finding) => finding.code === "export_presets_missing"));
});
