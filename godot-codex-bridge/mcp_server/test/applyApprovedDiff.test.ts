import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { applyApprovedDiff } from "../src/applyApprovedDiff.js";

test("applyApprovedDiff fails closed for absent, altered, expired, replayed, cancelled, and legacy approvals", async () => {
  const projectRoot = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-apply-disabled-"));
  const bridgeDir = path.join(projectRoot, ".godot", "godot_codex_bridge");
  const filePath = path.join(projectRoot, "script.gd");
  const original = "extends Node\n# sentinel: unchanged\n";
  await fs.writeFile(filePath, original, "utf8");

  const cases: Array<{ name: string; approvalToken?: string }> = [
    { name: "missing" },
    { name: "altered", approvalToken: "altered-receipt" },
    { name: "expired", approvalToken: "expired-receipt" },
    { name: "replayed", approvalToken: "replayed-receipt" },
    { name: "cancelled", approvalToken: "cancelled-receipt" },
    { name: "legacy-public-token", approvalToken: "APPROVE_GODOT_CODEX_BRIDGE_APPLY" },
  ];

  for (const item of cases) {
    const result = await applyApprovedDiff(projectRoot, bridgeDir, {
      path: "script.gd",
      proposedContent: `extends Node\n# attempted: ${item.name}\n`,
      approvalToken: item.approvalToken,
    });
    assert.equal(result.status, "bridge_unavailable", item.name);
    assert.equal(result.applied, false, item.name);
    assert.equal((result.error as { code: string }).code, "trusted_approval_unavailable", item.name);
    assert.equal(await fs.readFile(filePath, "utf8"), original, item.name);
  }
});
