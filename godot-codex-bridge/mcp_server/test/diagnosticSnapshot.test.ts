import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { createDiagnosticSnapshot } from "../src/diagnosticSnapshot.js";

test("createDiagnosticSnapshot writes local diagnostic artifact", async () => {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-diagnostic-"));
  const bridgeDir = path.join(projectRoot, ".godot", "godot_codex_bridge");
  const result = await createDiagnosticSnapshot(
    projectRoot,
    bridgeDir,
    {
      status: "ok",
      diagnostics_version: "godot-codex-bridge/3d-diagnostics-v1",
      findings: [],
    },
    "Camera pass",
  );

  assert.equal(result.status, "ok");
  assert.equal(result.contains_source_mutation, false);
  await fs.access(String(result.manifest_path));
  await fs.access(String(result.diagnostic_path));
});

test("createDiagnosticSnapshot returns diagnostic error unchanged", async () => {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-diagnostic-error-"));
  const bridgeDir = path.join(projectRoot, ".godot", "godot_codex_bridge");
  const result = await createDiagnosticSnapshot(projectRoot, bridgeDir, {
    status: "not_found",
    error: { code: "scene_tree_missing" },
  });

  assert.equal(result.status, "not_found");
  assert.deepEqual(result.error, { code: "scene_tree_missing" });
});
