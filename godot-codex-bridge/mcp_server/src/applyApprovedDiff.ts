import type { ToolEnvelope } from "./types.js";

export interface ApplyApprovedDiffOptions {
  path: string;
  proposedContent: string;
  allowCreate?: boolean;
  expectedCurrentSha256?: string;
  approvalToken?: string;
  label?: string;
}

export async function applyApprovedDiff(
  _projectRoot: string,
  _bridgeDir: string,
  _options: ApplyApprovedDiffOptions,
): Promise<ToolEnvelope> {
  return {
    status: "bridge_unavailable",
    applied: false,
    mitigation: "operation_disabled",
    error: {
      code: "trusted_approval_unavailable",
      message: "Direct file application is disabled until Godot Codex Bridge can verify a short-lived, single-use human approval receipt bound to the exact project, operation, target, reviewed state, and proposed content. Use godot.preview_scene_diff and apply the reviewed change through a trusted user-controlled workflow.",
    },
  };
}
