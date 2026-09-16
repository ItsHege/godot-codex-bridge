import { isJsonObject } from "./bridge.js";
import type { JsonObject, ToolEnvelope } from "./types.js";

const FOCUSABLE_NATIVE_PANELS = [
  "Output",
  "Debugger",
  "Stack Trace",
  "Audio",
  "Animation",
  "Shader Editor",
  "Signal Visualizer",
  "Profiler",
  "Visual Profiler",
  "Monitors",
  "Video RAM",
  "Network Profiler",
  "Inspector",
  "FileSystem",
  "Scene",
  "Import",
];

const SCREENSHOT_ONLY_NATIVE_PANELS = [
  "Output",
  "Debugger",
  "Stack Trace",
  "Profiler",
  "Visual Profiler",
  "Monitors",
  "Video RAM",
  "Network Profiler",
];

export function getEditorCapabilities(snapshotEnvelope?: ToolEnvelope): ToolEnvelope {
  const snapshotCapabilities = snapshotEditorCapabilities(snapshotEnvelope);
  return {
    status: "ok",
    capabilities_version: "godot-codex-bridge/editor-capabilities-v1",
    snapshot_status: snapshotEnvelope?.status ?? "not_found",
    snapshot_path: typeof snapshotEnvelope?.snapshot_path === "string" ? snapshotEnvelope.snapshot_path : null,
    typed_editor_control: {
      available_via: "editor_control",
      mutation_model: stringOrDefault(snapshotCapabilities?.mutation_model, "undo_redo_unsaved_with_explicit_save"),
      auto_save_supported: boolOrDefault(snapshotCapabilities?.auto_save_supported, false),
      explicit_save_supported: boolOrDefault(snapshotCapabilities?.explicit_save_supported, true),
      max_batch_actions: numberOrDefault(snapshotCapabilities?.max_batch_actions, 12),
      max_property_changes: numberOrDefault(snapshotCapabilities?.max_property_changes, 20),
      actions: arrayOfStrings(snapshotCapabilities?.actions),
    },
    can_focus: {
      main_screens: ["2D", "3D", "Script", "Game", "AssetLib", "Codex Bridge"],
      native_panels: arrayOfStrings(snapshotCapabilities?.focusable_native_panels, FOCUSABLE_NATIVE_PANELS),
      tool: "godot.editor_focus_panel",
    },
    can_read: {
      current_scene: "godot.get_current_scene",
      scene_tree: "godot.get_scene_tree",
      selected_nodes: "godot.get_selected_nodes",
      editor_state: "godot.editor_get_state",
      project_map: "godot.project_get_map",
      scene_graph: "godot.project_scene_graph",
      script_map: "godot.project_script_map",
      diagnostics: "godot.diagnostics_get",
      runtime_state: "godot.runtime_get_state",
      runtime_events: "godot.runtime_get_events",
    },
    can_clear: {
      bridge_owned_diagnostics: "godot.diagnostics_clear",
      native_output_panel: false,
      native_debugger_panel: false,
    },
    screenshot_only: {
      panels: arrayOfStrings(snapshotCapabilities?.screenshot_only_native_panels, SCREENSHOT_ONLY_NATIVE_PANELS),
      reason: "Godot does not expose a stable Bridge-supported API for reading native Output/Debugger/Profiler panel contents directly.",
      recommended_tools: ["godot.editor_focus_panel", "godot.capture_viewport_screenshot", "godot.diagnostics_get"],
    },
    unsupported: [
      {
        capability: "native_output_text_scrape",
        status: "editor_api_unavailable",
        safe_fallback: "Use godot.diagnostics_get for Bridge-owned logs or focus/capture the panel as visual evidence.",
      },
      {
        capability: "native_debugger_error_list_scrape",
        status: "editor_api_unavailable",
        safe_fallback: "Use run/check logs, diagnostics_get summaries, or focused screenshots.",
      },
      {
        capability: "arbitrary_editor_ui_clicking",
        status: "unsupported",
        safe_fallback: "Use typed editor_control tools only.",
      },
    ],
    tooltip: stringOrDefault(
      snapshotCapabilities?.native_panel_limitations_tooltip,
      "Native Godot panels can be focused, but Output/Debugger/Profiler contents are not scraped through a stable editor API. Use diagnostics_get for Bridge-owned logs or screenshots for visual evidence.",
    ),
  };
}

function snapshotEditorCapabilities(snapshotEnvelope: ToolEnvelope | undefined): JsonObject | null {
  if (!snapshotEnvelope || snapshotEnvelope.status !== "ok" || !isJsonObject(snapshotEnvelope.snapshot)) {
    return null;
  }
  const snapshot = snapshotEnvelope.snapshot;
  if (!isJsonObject(snapshot.editor_state)) {
    return null;
  }
  return isJsonObject(snapshot.editor_state.capabilities) ? snapshot.editor_state.capabilities : null;
}

function arrayOfStrings(value: unknown, fallback: string[] = []): string[] {
  if (!Array.isArray(value)) {
    return [...fallback];
  }
  return value.filter((item): item is string => typeof item === "string");
}

function stringOrDefault(value: unknown, fallback: string): string {
  return typeof value === "string" && value.length > 0 ? value : fallback;
}

function boolOrDefault(value: unknown, fallback: boolean): boolean {
  return typeof value === "boolean" ? value : fallback;
}

function numberOrDefault(value: unknown, fallback: number): number {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}
