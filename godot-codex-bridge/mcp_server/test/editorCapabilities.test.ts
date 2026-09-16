import assert from "node:assert/strict";
import test from "node:test";

import { getEditorCapabilities } from "../src/editorCapabilities.js";

test("getEditorCapabilities returns honest native panel limitations without a snapshot", () => {
  const result = getEditorCapabilities();

  assert.equal(result.status, "ok");
  assert.equal(result.capabilities_version, "godot-codex-bridge/editor-capabilities-v1");
  assert.equal(result.snapshot_status, "not_found");
  assert.equal((result.can_clear as { native_output_panel?: boolean }).native_output_panel, false);
  assert.equal((result.can_clear as { native_debugger_panel?: boolean }).native_debugger_panel, false);
  assert.equal((result.screenshot_only as { panels?: string[] }).panels?.includes("Output"), true);
  assert.equal((result.unsupported as Array<{ capability?: string }>).some((item) => item.capability === "native_output_text_scrape"), true);
});

test("getEditorCapabilities incorporates snapshot editor_control capabilities when available", () => {
  const result = getEditorCapabilities({
    status: "ok",
    snapshot_path: "C:/project/.godot/godot_codex_bridge/context_snapshot.json",
    snapshot: {
      editor_state: {
        capabilities: {
          mutation_model: "undo_redo_unsaved_with_explicit_save",
          max_batch_actions: 9,
          max_property_changes: 17,
          actions: ["focus_panel", "open_scene"],
          focusable_native_panels: ["Output", "Scene"],
          screenshot_only_native_panels: ["Output"],
          native_panel_limitations_tooltip: "Use screenshots for native Output.",
        },
      },
    },
  });

  assert.equal(result.status, "ok");
  assert.equal(result.snapshot_status, "ok");
  assert.equal(result.snapshot_path, "C:/project/.godot/godot_codex_bridge/context_snapshot.json");
  assert.deepEqual((result.typed_editor_control as { actions?: string[] }).actions, ["focus_panel", "open_scene"]);
  assert.equal((result.typed_editor_control as { max_batch_actions?: number }).max_batch_actions, 9);
  assert.deepEqual((result.can_focus as { native_panels?: string[] }).native_panels, ["Output", "Scene"]);
  assert.deepEqual((result.screenshot_only as { panels?: string[] }).panels, ["Output"]);
  assert.equal(result.tooltip, "Use screenshots for native Output.");
});
