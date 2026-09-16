import fs from "node:fs/promises";
import path from "node:path";

import { previewSceneDiff } from "./diffPreview.js";
import { createUndoSnapshot } from "./undoSnapshot.js";
import type { ToolEnvelope } from "./types.js";

export const APPLY_APPROVAL_TOKEN = "APPROVE_GODOT_CODEX_BRIDGE_APPLY";

export interface ApplyApprovedDiffOptions {
  path: string;
  proposedContent: string;
  allowCreate?: boolean;
  expectedCurrentSha256?: string;
  approvalToken?: string;
  label?: string;
}

export async function applyApprovedDiff(
  projectRoot: string,
  bridgeDir: string,
  options: ApplyApprovedDiffOptions,
): Promise<ToolEnvelope> {
  if (options.approvalToken !== APPLY_APPROVAL_TOKEN) {
    return {
      status: "invalid_request",
      error: {
        code: "approval_token_required",
        message: `Set approvalToken to ${APPLY_APPROVAL_TOKEN} after reviewing the diff and undo plan.`,
      },
    };
  }

  const preview = await previewSceneDiff({
    projectRoot,
    targetPath: options.path,
    proposedContent: options.proposedContent,
    allowCreate: options.allowCreate,
  });
  if (options.expectedCurrentSha256 && preview.current_sha256 !== options.expectedCurrentSha256) {
    return {
      status: "invalid_request",
      error: {
        code: "current_sha256_mismatch",
        message: "Current file hash does not match the reviewed diff.",
        expected: options.expectedCurrentSha256,
        actual: preview.current_sha256,
      },
    };
  }

  let undoSnapshot: ToolEnvelope | null = null;
  if (preview.operation === "modify") {
    undoSnapshot = await createUndoSnapshot(projectRoot, bridgeDir, {
      paths: [String(preview.path)],
      label: options.label ?? "before-approved-diff",
    });
    if (undoSnapshot.status !== "ok") {
      return undoSnapshot;
    }
  }

  await fs.mkdir(path.dirname(String(preview.absolute_path)), { recursive: true });
  await fs.writeFile(String(preview.absolute_path), options.proposedContent, "utf8");

  return {
    status: "ok",
    applied: true,
    approval_token_used: true,
    path: preview.path,
    absolute_path: preview.absolute_path,
    operation: preview.operation,
    previous_sha256: preview.current_sha256,
    applied_sha256: preview.proposed_sha256,
    undo_snapshot: undoSnapshot,
    diff: preview.diff,
  };
}
