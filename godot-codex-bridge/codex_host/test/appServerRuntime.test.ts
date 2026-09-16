import assert from "node:assert/strict";
import test from "node:test";
import {
  appServerThreadStartParams,
  appServerTurnStartParams,
  diffTextFromFileUpdateChanges,
  fileChangesFromFileUpdateChanges,
  responseForApproval
} from "../src/appServerRuntime.js";

test("app-server command approval maps Godot approve to one-shot accept", () => {
  assert.deepEqual(
    responseForApproval("item/commandExecution/requestApproval", "approve"),
    { decision: "accept" }
  );
  assert.deepEqual(
    responseForApproval("item/commandExecution/requestApproval", "reject"),
    { decision: "decline" }
  );
  assert.deepEqual(
    responseForApproval("item/commandExecution/requestApproval", "expired"),
    { decision: "cancel" }
  );
});

test("app-server approval maps Godot approve_session to session decisions", () => {
  assert.deepEqual(
    responseForApproval("item/commandExecution/requestApproval", "approve_session"),
    { decision: "acceptForSession" }
  );
  assert.deepEqual(
    responseForApproval("item/fileChange/requestApproval", "approve_session"),
    { decision: "acceptForSession" }
  );
  assert.deepEqual(
    responseForApproval("execCommandApproval", "approve_session"),
    { decision: "approved_for_session" }
  );
  assert.deepEqual(
    responseForApproval("applyPatchApproval", "approve_session"),
    { decision: "approved_for_session" }
  );
});

test("app-server elicitation ignores session approval and accepts once", () => {
  assert.deepEqual(
    responseForApproval("mcpServer/elicitation/request", "approve_session", {}, ""),
    { action: "accept", content: {}, _meta: null }
  );
});

test("legacy exec command approval maps Godot approve to approved", () => {
  assert.deepEqual(
    responseForApproval("execCommandApproval", "approve"),
    { decision: "approved" }
  );
  assert.deepEqual(
    responseForApproval("execCommandApproval", "reject"),
    { decision: "denied" }
  );
  assert.deepEqual(
    responseForApproval("execCommandApproval", "expired"),
    { decision: "timed_out" }
  );
});

test("app-server params honor full-machine trust session policy", () => {
  assert.deepEqual(
    appServerThreadStartParams({
      projectRoot: "C:\\Project",
      approvalPolicy: "never",
      sandbox: "danger-full-access",
    }),
    {
      cwd: "C:\\Project",
      approvalPolicy: "never",
      approvalsReviewer: "user",
      sandbox: "danger-full-access",
      threadSource: "user",
      sessionStartSource: "startup",
    },
  );

  const turn = appServerTurnStartParams({
    threadId: "thread-1",
    projectRoot: "C:\\Project",
    message: "Build the scene",
    approvalPolicy: "never",
    sandbox: "danger-full-access",
  });
  assert.equal(turn.approvalPolicy, "never");
  assert.deepEqual(turn.sandboxPolicy, { type: "dangerFullAccess" });
});

test("app-server turn params attach annotation as local image input", () => {
  const turn = appServerTurnStartParams({
    threadId: "thread-annotation",
    projectRoot: "C:\\Project",
    message: "Use marker A",
    attachments: { latest_annotation: true },
    annotation: {
      annotationId: "annotation_test_001",
      manifestPath: "C:\\Project\\.godot\\godot_codex_bridge\\artifacts\\annotations\\annotation_test_001\\annotation.json",
      rawImagePath: "C:\\Project\\.godot\\godot_codex_bridge\\artifacts\\annotations\\annotation_test_001\\raw.png",
      annotatedImagePath: "C:\\Project\\.godot\\godot_codex_bridge\\artifacts\\annotations\\annotation_test_001\\annotated.png",
      imageAttached: true,
      detail: "high",
      summaryText: "[Godot AI Marker attachment]\nAttached marks are user reference annotations.\n[/Godot AI Marker attachment]",
      manifest: {},
    },
  }) as { input: Array<Record<string, unknown>> };

  assert.equal(turn.input.length, 2);
  assert.equal(turn.input[0].type, "text");
  assert.match(String(turn.input[0].text), /latest_annotation/);
  assert.deepEqual(turn.input[1], {
    type: "localImage",
    path: "C:\\Project\\.godot\\godot_codex_bridge\\artifacts\\annotations\\annotation_test_001\\annotated.png",
    detail: "high",
  });
});

test("app-server annotation turn params do not embed PNG bytes in JSON", () => {
  const turn = appServerTurnStartParams({
    threadId: "thread-annotation",
    projectRoot: "C:\\Project",
    message: "Use marker A",
    annotation: {
      annotationId: "annotation_test_001",
      manifestPath: "C:\\Project\\.godot\\godot_codex_bridge\\artifacts\\annotations\\annotation_test_001\\annotation.json",
      rawImagePath: "C:\\Project\\.godot\\godot_codex_bridge\\artifacts\\annotations\\annotation_test_001\\raw.png",
      annotatedImagePath: "C:\\Project\\.godot\\godot_codex_bridge\\artifacts\\annotations\\annotation_test_001\\annotated.png",
      imageAttached: true,
      detail: "high",
      summaryText: "[Godot AI Marker attachment]\nAttached marks are user reference annotations.\n[/Godot AI Marker attachment]",
      manifest: {},
    },
  });

  const serialized = JSON.stringify(turn);
  assert.match(serialized, /"type":"localImage"/);
  assert.match(serialized, /annotated\.png/);
  assert.doesNotMatch(serialized, /data:image\/png/i);
  assert.doesNotMatch(serialized, /iVBOR/);
  assert.doesNotMatch(serialized, /rawImageBytes|annotatedImageBytes|bytesBase64|image_bytes/i);
});

test("app-server permission approval grants requested permissions only when accepted", () => {
  const rawParams = {
    permissions: {
      fileSystem: { writableRoots: ["C:\\Project"] },
      network: null,
    },
  };
  assert.deepEqual(
    responseForApproval("item/permissions/requestApproval", "approve_session", rawParams),
    {
      permissions: { fileSystem: { writableRoots: ["C:\\Project"] } },
      scope: "session",
      strictAutoReview: false,
    },
  );
  assert.deepEqual(
    responseForApproval("item/permissions/requestApproval", "reject", rawParams),
    { permissions: {}, scope: "turn", strictAutoReview: true },
  );
});

test("app-server normalizes file change patch updates for Godot chat diff cards", () => {
  const changes = [
    { path: "res://scripts/player.gd", kind: "update", diff: "@@\n-old\n+new\n" },
    { path: "scenes\\Main.tscn", kind: "add", diff: "@@\n+[node name=\"Main\" type=\"Node3D\"]\n" },
  ];

  const diffText = diffTextFromFileUpdateChanges(changes);
  assert.match(diffText, /diff --git a\/res:\/\/scripts\/player\.gd b\/res:\/\/scripts\/player\.gd/);
  assert.match(diffText, /\n-old\n\+new/);
  assert.match(diffText, /diff --git a\/scenes\/Main\.tscn b\/scenes\/Main\.tscn/);

  const fileChanges = fileChangesFromFileUpdateChanges(changes);
  assert.deepEqual(fileChanges["res://scripts/player.gd"], {
    type: "update",
    unified_diff: "@@\n-old\n+new",
  });
  assert.deepEqual(fileChanges["scenes/Main.tscn"], {
    type: "add",
    unified_diff: "@@\n+[node name=\"Main\" type=\"Node3D\"]",
  });
});
