import type { CallToolResult } from "@modelcontextprotocol/sdk/types.js";
import fs from "node:fs/promises";
import path from "node:path";

import { getAnnotation, getLatestAnnotation, listAnnotations, resolveAnnotationTarget } from "./annotations.js";
import { applyApprovedDiff } from "./applyApprovedDiff.js";
import { BridgeClient, isJsonObject } from "./bridge.js";
import { planBlenderAssetImport } from "./blenderImportManifest.js";
import { createDiagnosticSnapshot } from "./diagnosticSnapshot.js";
import { getEditorCapabilities } from "./editorCapabilities.js";
import { checkExportReadiness } from "./exportReadiness.js";
import { PreviewDiffError, previewSceneDiff } from "./diffPreview.js";
import { runProjectParseCheck, runTestScene } from "./godotRunner.js";
import {
  getAgentsContext,
  getCurrentSourceContext,
  getProjectMap,
  getProjectOverview,
  getProjectSceneGraph,
  getProjectScriptMap,
  getSceneFileTree,
  listProjectFiles,
  readProjectFile,
  searchProjectFiles,
} from "./projectAwareness.js";
import { inspect3dScene } from "./sceneDiagnostics.js";
import { generateSceneFromPrompt } from "./sceneGenerator.js";
import { getPerformanceSnapshot } from "./performanceSnapshot.js";
import { getBridgeStatus } from "./status.js";
import { getRuntimeEvents, getRuntimeState } from "./runtimeState.js";
import { captureTimelineScreenshots } from "./timelineCapture.js";
import { getToolCatalog } from "./toolCatalog.js";
import { createUndoSnapshot } from "./undoSnapshot.js";
import { compareVisualRegression, createVisualBaseline } from "./visualRegression.js";
import type { JsonObject, JsonValue, ServerConfig, ToolEnvelope } from "./types.js";

export function createToolHandlers(config: ServerConfig): Record<string, (args?: JsonObject) => Promise<CallToolResult>> {
  const bridge = new BridgeClient(config);

  return {
    "godot.get_tool_catalog": async (args = {}) =>
      toolResult(getToolCatalog(
        typeof args.category === "string" ? args.category : undefined,
        typeof args.intent === "string" ? args.intent : undefined,
        args.view === "full" ? "full" : "compact",
      )),
    "godot.bridge_status": async () => toolResult(await getBridgeStatus(config)),
    "godot.get_project_overview": async () => toolResult(await getProjectOverview(config.projectRoot, {
      snapshotEnvelope: await bridge.readSnapshot(),
    })),
    "godot.project_get_map": async () => toolResult(await getProjectMap(config.projectRoot, {
      snapshotEnvelope: await bridge.readSnapshot(),
    })),
    "godot.project_scene_graph": async (args = {}) => toolResult(await getProjectSceneGraph(config.projectRoot, args)),
    "godot.project_script_map": async (args = {}) => toolResult(await getProjectScriptMap(config.projectRoot, args)),
    "godot.list_project_files": async (args = {}) => toolResult(await listProjectFiles(config.projectRoot, args)),
    "godot.search_project_files": async (args = {}) => toolResult(await searchProjectFiles(config.projectRoot, args)),
    "godot.read_project_file": async (args = {}) => toolResult(await readProjectFile(config.projectRoot, args)),
    "godot.get_agents_context": async () => toolResult(await getAgentsContext(config.projectRoot)),
    "godot.get_scene_file_tree": async (args = {}) => toolResult(await getSceneFileTree(config.projectRoot, args, {
      snapshotEnvelope: await bridge.readSnapshot(),
    })),
    "godot.get_current_source_context": async () => toolResult(await getCurrentSourceContext(config.projectRoot, {
      snapshotEnvelope: await bridge.readSnapshot(),
    })),
    "godot.get_current_scene": async () =>
      toolResult(await enrichCurrentScene(await bridge.readSnapshotSection("current_scene"), config)),
    "godot.get_scene_tree": async () => toolResult(await bridge.readSnapshotSection("scene_tree")),
    "godot.get_selected_nodes": async () => toolResult(await bridge.readSnapshotSection("selected_nodes")),
    "godot.get_editor_output": async () => toolResult(await bridge.readSnapshotSection("editor_output")),
    "godot.get_resource_status": async () => toolResult(await bridge.readSnapshotSection("resource_status")),
    "godot.performance_get_snapshot": async (args = {}) => toolResult(getPerformanceSnapshot(await bridge.readSnapshot(), args)),
    "godot.get_gameplay_context": async () => toolResult(await bridge.readSnapshotSection("gameplay_context")),
    "godot.get_script_inventory": async () => toolResult(await bridge.readSnapshotSection("script_inventory")),
    "godot.list_annotations": async (args = {}) =>
      toolResult(await listAnnotations(config.bridgeDir, { limit: numberOrDefault(args.limit, 20) })),
    "godot.get_latest_annotation": async () => toolResult(await getLatestAnnotation(config.bridgeDir)),
    "godot.get_annotation": async (args = {}) =>
      toolResult(await getAnnotation(config.bridgeDir, stringOrDefault(args.annotationId, ""))),
    "godot.resolve_annotation_target": async (args = {}) =>
      toolResult(await resolveAnnotationTarget(config.bridgeDir, {
        annotationId: typeof args.annotationId === "string" ? args.annotationId : undefined,
        markerId: typeof args.markerId === "string" ? args.markerId : undefined,
      })),
    "godot.refresh_editor_context": async (args = {}) =>
      toolResult(
        await sendEditorControlRequest(
          bridge,
          "refresh_context",
          {},
          numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
        ),
      ),
    "godot.editor_get_state": async (args = {}) =>
      toolResult(
        await sendEditorControlRequest(
          bridge,
          "get_state",
          {},
          numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
        ),
      ),
    "godot.editor_capabilities": async () => toolResult(getEditorCapabilities(await bridge.readSnapshot())),
    "godot.editor_focus": async (args = {}) => {
      try {
        const params: JsonObject = {};
        const mainScreen = optionalEditorMainScreen(args.mainScreen);
        if (mainScreen) {
          params.main_screen = mainScreen;
        }
        if (typeof args.selectFile === "string" && args.selectFile.length > 0) {
          params.select_file = await validateProjectResPath(config.projectRoot, args.selectFile, {
            kind: "resource",
            extensions: [],
            mustExist: true,
          });
        }
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "focus_editor",
            params,
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.editor_focus_panel": async (args = {}) => {
      try {
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "focus_panel",
            { panel: optionalEditorPanel(args.panel) },
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.get_inspector_context": async (args = {}) =>
      toolResult(
        await sendEditorControlRequest(
          bridge,
          "get_inspector_context",
          {},
          numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
        ),
      ),
    "godot.editor_viewport_navigate": async (args = {}) => {
      try {
        const viewport = optionalViewport(args.viewport);
        const action = optionalViewportAction(viewport, args.action);
        const params: JsonObject = { viewport, action };
        copyBoundedNumberField(args, params, "deltaX", "delta_x", -100000, 100000, "invalid_viewport_delta");
        copyBoundedNumberField(args, params, "deltaY", "delta_y", -100000, 100000, "invalid_viewport_delta");
        copyBoundedNumberField(args, params, "zoomFactor", "zoom_factor", 0.05, 20, "invalid_viewport_zoom_factor");
        copyBoundedNumberField(args, params, "centerX", "center_x", -100000, 100000, "invalid_viewport_center");
        copyBoundedNumberField(args, params, "centerY", "center_y", -100000, 100000, "invalid_viewport_center");
        copyBoundedNumberField(args, params, "orbitYawDegrees", "orbit_yaw_degrees", -3600, 3600, "invalid_viewport_orbit");
        copyBoundedNumberField(args, params, "orbitPitchDegrees", "orbit_pitch_degrees", -3600, 3600, "invalid_viewport_orbit");
        copyBoundedNumberField(args, params, "zoomDelta", "zoom_delta", -1000, 1000, "invalid_viewport_zoom_delta");

        const timeoutMs = numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs);
        const result = await sendEditorControlRequest(bridge, "viewport_navigate", params, timeoutMs);
        if (args.captureScreenshot === false || result.status !== "ok") {
          return toolResult(result);
        }
        const screenshotResult = await bridge.sendAddonRequest(
          "capture_viewport_screenshot",
          { requested_by: "mcp_server", reason: "editor_viewport_navigate" },
          timeoutMs,
        );
        return toolResult({
          ...result,
          screenshot_after_action: screenshotResult,
        });
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.select_node": async (args = {}) => {
      try {
        const params: JsonObject = {
          node_path: validateNodePath(stringOrDefault(args.nodePath, "")),
          focus_inspector: args.focusInspector !== false,
          additive: args.additive === true,
        };
        if (typeof args.scenePath === "string" && args.scenePath.length > 0) {
          params.scene_path = await validateOpenScenePath(config.projectRoot, args.scenePath);
        }
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "select_node",
            params,
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.inspect_node": async (args = {}) => {
      try {
        const params: JsonObject = {
          node_path: validateNodePath(stringOrDefault(args.nodePath, "")),
          focus_inspector: true,
          additive: args.additive === true,
        };
        if (typeof args.scenePath === "string" && args.scenePath.length > 0) {
          params.scene_path = await validateOpenScenePath(config.projectRoot, args.scenePath);
        }
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "inspect_node",
            params,
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.get_node_deep": async (args = {}) => {
      try {
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "get_node_deep",
            {
              node_path: validateNodePath(stringOrDefault(args.nodePath, "")),
              depth: boundedInteger(args.depth, 2, 0, 8, "invalid_depth"),
              max_nodes: boundedInteger(args.maxNodes, 96, 1, 256, "invalid_max_nodes"),
              include_properties: args.includeProperties !== false,
            },
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.get_spatial_bounds": async (args = {}) => {
      try {
        const nodePath = typeof args.nodePath === "string" ? args.nodePath.trim() : "";
        const groupName = typeof args.groupName === "string" ? args.groupName.trim() : "";
        if (nodePath !== "" && groupName !== "") {
          throw codedError("invalid_spatial_selector", "Use either nodePath or groupName, not both.");
        }
        const params: JsonObject = {
          selected_only: args.selectedOnly !== false,
          max_nodes: boundedInteger(args.maxNodes, 24, 1, 96, "invalid_max_nodes"),
        };
        if (nodePath !== "") {
          params.node_path = validateNodePath(nodePath);
          params.selected_only = false;
        }
        if (groupName !== "") {
          params.group_name = validateSpatialGroupName(groupName);
          params.selected_only = false;
        }
        if (typeof args.groundY === "number" && Number.isFinite(args.groundY)) {
          params.ground_y = Math.max(-100_000, Math.min(100_000, args.groundY));
        }
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "get_spatial_bounds",
            params,
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.spatial_query": async (args = {}) => {
      try {
        const nodePath = typeof args.nodePath === "string" ? args.nodePath.trim() : "";
        const groupName = typeof args.groupName === "string" ? args.groupName.trim() : "";
        if (nodePath !== "" && groupName !== "") {
          throw codedError("invalid_spatial_selector", "Use either nodePath or groupName, not both.");
        }
        const params: JsonObject = {
          query: validateSpatialQuery(stringOrDefault(args.query ?? args.queryType, "ground_gap")),
          selected_only: args.selectedOnly !== false,
          max_nodes: boundedInteger(args.maxNodes, 24, 1, 96, "invalid_max_nodes"),
        };
        if (nodePath !== "") {
          params.node_path = validateNodePath(nodePath);
          params.selected_only = false;
        }
        if (groupName !== "") {
          params.group_name = validateSpatialGroupName(groupName);
          params.selected_only = false;
        }
        if (typeof args.groundY === "number" && Number.isFinite(args.groundY)) {
          params.ground_y = Math.max(-100_000, Math.min(100_000, args.groundY));
        }
        if (typeof args.tolerance === "number" && Number.isFinite(args.tolerance)) {
          params.tolerance = Math.max(0, Math.min(1000, args.tolerance));
        }
        if (typeof args.maxPairs === "number" && Number.isFinite(args.maxPairs)) {
          params.max_pairs = boundedInteger(args.maxPairs, 128, 1, 512, "invalid_max_pairs");
        }
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "spatial_query",
            params,
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.placement_check": async (args = {}) => {
      try {
        const nodePath = typeof args.nodePath === "string" ? args.nodePath.trim() : "";
        const groupName = typeof args.groupName === "string" ? args.groupName.trim() : "";
        if (nodePath !== "" && groupName !== "") {
          throw codedError("invalid_spatial_selector", "Use either nodePath or groupName, not both.");
        }
        const params: JsonObject = {
          selected_only: args.selectedOnly !== false,
          max_nodes: boundedInteger(args.maxNodes, 24, 1, 96, "invalid_max_nodes"),
          max_pairs: boundedInteger(args.maxPairs, 128, 1, 512, "invalid_max_pairs"),
          max_issues: boundedInteger(args.maxIssues, 128, 1, 512, "invalid_max_issues"),
        };
        if (nodePath !== "") {
          params.node_path = validateNodePath(nodePath);
          params.selected_only = false;
        }
        if (groupName !== "") {
          params.group_name = validateSpatialGroupName(groupName);
          params.selected_only = false;
        }
        if (typeof args.groundY === "number" && Number.isFinite(args.groundY)) {
          params.ground_y = Math.max(-100_000, Math.min(100_000, args.groundY));
        }
        if (typeof args.tolerance === "number" && Number.isFinite(args.tolerance)) {
          params.tolerance = Math.max(0, Math.min(1000, args.tolerance));
        }
        if (typeof args.gridSize === "number" && Number.isFinite(args.gridSize)) {
          params.grid_size = Math.max(0, Math.min(100_000, args.gridSize));
        }
        if (args.gridOrigin !== undefined) {
          params.grid_origin = validateGridOrigin(args.gridOrigin);
        }
        if (args.checks !== undefined) {
          params.checks = validatePlacementChecks(args.checks);
        }
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "placement_check",
            params,
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.snap_to_ground": async (args = {}) => {
      try {
        const params = spatialMutationParams(args);
        if (typeof args.groundY === "number" && Number.isFinite(args.groundY)) {
          params.ground_y = Math.max(-100_000, Math.min(100_000, args.groundY));
        }
        if (typeof args.tolerance === "number" && Number.isFinite(args.tolerance)) {
          params.tolerance = Math.max(0, Math.min(1000, args.tolerance));
        }
        if (typeof args.gridSize === "number" && Number.isFinite(args.gridSize)) {
          if (args.gridSize <= 0) {
            throw codedError("invalid_grid_size", "gridSize must be greater than 0 when provided.");
          }
          params.grid_size = Math.min(100_000, args.gridSize);
        }
        if (args.gridOrigin !== undefined) {
          params.grid_origin = validateGridOrigin(args.gridOrigin);
        }
        if (typeof args.alignToSurface === "boolean") {
          params.align_to_surface = args.alignToSurface;
        }
        const result = await sendEditorControlRequest(
          bridge,
          "snap_to_ground",
          params,
          numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
        );
        return toolResult(await withOptionalPostActionScreenshot(bridge, config, args, result, "snap_to_ground"));
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.snap_to_grid": async (args = {}) => {
      try {
        const params = spatialMutationParams(args);
        if (typeof args.gridSize !== "number" || !Number.isFinite(args.gridSize) || args.gridSize <= 0) {
          throw codedError("invalid_grid_size", "gridSize is required and must be greater than 0.");
        }
        params.grid_size = Math.min(100_000, args.gridSize);
        if (args.gridOrigin !== undefined) {
          params.grid_origin = validateGridOrigin(args.gridOrigin);
        }
        if (args.axes !== undefined) {
          params.axes = validateGridAxes(args.axes);
        }
        if (typeof args.tolerance === "number" && Number.isFinite(args.tolerance)) {
          params.tolerance = Math.max(0, Math.min(1000, args.tolerance));
        }
        const result = await sendEditorControlRequest(
          bridge,
          "snap_to_grid",
          params,
          numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
        );
        return toolResult(await withOptionalPostActionScreenshot(bridge, config, args, result, "snap_to_grid"));
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.open_script": async (args = {}) => {
      try {
        const params: JsonObject = {
          script_path: await validateProjectResPath(config.projectRoot, stringOrDefault(args.scriptPath, ""), {
            kind: "script",
            extensions: [".gd", ".cs", ".gdshader", ".shader"],
            mustExist: true,
          }),
        };
        if (typeof args.line === "number" && Number.isFinite(args.line)) {
          params.line = Math.max(1, Math.floor(args.line));
        }
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "open_script",
            params,
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.list_resources": async (args = {}) => {
      try {
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "list_resources",
            {
              root_path: validateProjectResRootPath(stringOrDefault(args.rootPath, "res://")),
              extensions: validateExtensions(args.extensions),
              type_filter: optionalResourceType(args.typeFilter),
              limit: boundedInteger(args.limit, 120, 1, 250, "invalid_resource_limit"),
            },
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.inspect_imported_assets": async (args = {}) => {
      try {
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "inspect_imported_assets",
            {
              root_path: validateProjectResRootPath(stringOrDefault(args.rootPath, "res://")),
              extensions: validateExtensions(args.extensions),
              type_filter: optionalResourceType(args.typeFilter),
              invalid_only: args.invalidOnly === true,
              placeable_only: args.placeableOnly === true,
              include_dependencies: args.includeDependencies === true,
              limit: boundedInteger(args.limit, 120, 1, 250, "invalid_imported_asset_limit"),
            },
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.plan_blender_asset_import": async (args = {}) => {
      try {
        return toolResult(await planBlenderAssetImport(config, args));
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.get_class_info": async (args = {}) => {
      try {
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "get_class_info",
            {
              class_name: validateNodeClassName(stringOrDefault(args.className, "")),
              no_inheritance: args.noInheritance === true,
              limit: boundedInteger(args.limit, 80, 1, 200, "invalid_class_info_limit"),
            },
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.inspect_materials": async (args = {}) => {
      try {
        const params: JsonObject = {
          selected_only: args.selectedOnly === true,
          include_shader_params: args.includeShaderParams !== false,
          include_empty: args.includeEmpty === true,
          max_nodes: boundedInteger(args.maxNodes, 96, 1, 96, "invalid_max_material_nodes"),
          max_slots: boundedInteger(args.maxSlots, 192, 1, 192, "invalid_max_material_slots"),
        };
        if (typeof args.nodePath === "string" && args.nodePath.length > 0) {
          params.node_path = validateNodePath(args.nodePath);
        }
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "inspect_materials",
            params,
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.create_shader_material_for_node": async (args = {}) => {
      try {
        const slotKind = validateMaterialSlotKind(stringOrDefault(args.slotKind, "geometry_material_override"));
        const params: JsonObject = {
          node_path: validateNodePath(stringOrDefault(args.nodePath, "")),
          slot_kind: slotKind,
          local_to_scene: args.localToScene !== false,
          parameters: validateOptionalShaderParameterMap(args.parameters),
        };
        if (slotKind === "mesh_surface") {
          params.surface_index = validateSurfaceIndex(args.surfaceIndex);
        } else if (args.surfaceIndex !== undefined) {
          params.surface_index = boundedInteger(args.surfaceIndex, 0, 0, 1024, "invalid_surface_index");
        }
        if (typeof args.shaderPath === "string" && args.shaderPath.trim().length > 0) {
          params.shader_path = await validateProjectResPath(config.projectRoot, args.shaderPath, {
            kind: "shader",
            extensions: [".gdshader", ".shader", ".tres", ".res"],
            mustExist: true,
          });
        }
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "create_shader_material_for_node",
            params,
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.set_shader_parameter": async (args = {}) => {
      try {
        const slotKind = validateMaterialSlotKind(stringOrDefault(args.slotKind, "geometry_material_override"));
        const params: JsonObject = {
          node_path: validateNodePath(stringOrDefault(args.nodePath, "")),
          slot_kind: slotKind,
          parameter: validateShaderParameterName(stringOrDefault(args.parameter, "")),
          value: validateJsonValue(args.value, "invalid_shader_parameter_value", "value"),
        };
        if (slotKind === "mesh_surface") {
          params.surface_index = validateSurfaceIndex(args.surfaceIndex);
        } else if (args.surfaceIndex !== undefined) {
          params.surface_index = boundedInteger(args.surfaceIndex, 0, 0, 1024, "invalid_surface_index");
        }
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "set_shader_parameter",
            params,
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.set_shader_texture_parameter": async (args = {}) => {
      try {
        const slotKind = validateMaterialSlotKind(stringOrDefault(args.slotKind, "geometry_material_override"));
        const clear = args.clear === true;
        const params: JsonObject = {
          node_path: validateNodePath(stringOrDefault(args.nodePath, "")),
          slot_kind: slotKind,
          parameter: validateShaderParameterName(stringOrDefault(args.parameter, "")),
          clear,
        };
        if (slotKind === "mesh_surface") {
          params.surface_index = validateSurfaceIndex(args.surfaceIndex);
        } else if (args.surfaceIndex !== undefined) {
          params.surface_index = boundedInteger(args.surfaceIndex, 0, 0, 1024, "invalid_surface_index");
        }
        if (!clear) {
          params.texture_path = await validateProjectResPath(config.projectRoot, stringOrDefault(args.texturePath, ""), {
            kind: "texture",
            extensions: [".png", ".jpg", ".jpeg", ".webp", ".svg", ".bmp", ".tga", ".exr", ".hdr", ".dds", ".ktx", ".ktx2", ".tres", ".res"],
            mustExist: true,
          });
        }
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "set_shader_texture_parameter",
            params,
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.inspect_rendering_effects": async (args = {}) => {
      try {
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "inspect_rendering_effects",
            {
              selected_only: args.selectedOnly === true,
              include_environment_properties: args.includeEnvironmentProperties !== false,
              include_particles: args.includeParticles !== false,
              max_nodes: boundedInteger(args.maxNodes, 96, 1, 96, "invalid_max_render_effect_nodes"),
            },
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.set_environment_property": async (args = {}) => {
      try {
        const params: JsonObject = {
          node_path: validateNodePath(stringOrDefault(args.nodePath, "")),
          property: validateEnvironmentPropertyName(stringOrDefault(args.property, "")),
          value: validateJsonValue(args.value, "invalid_environment_value", "value"),
          create_if_missing: args.createIfMissing === true,
          local_to_scene: args.localToScene !== false,
        };
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "set_environment_property",
            params,
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.create_particle_effect": async (args = {}) => {
      try {
        const params: JsonObject = {
          kind: validateParticleEffectKind(args.kind),
          parent_path: args.parentPath === undefined ? "." : validateNodePath(stringOrDefault(args.parentPath, ".")),
          name: optionalNodeName(args.name),
          index: optionalIndex(args.index),
          amount: boundedInteger(args.amount, 64, 1, 10_000, "invalid_particle_amount"),
          lifetime: boundedNumber(args.lifetime, 1.5, 0.05, 60, "invalid_particle_lifetime"),
          emitting: args.emitting !== false,
          one_shot: args.oneShot === true,
          explosiveness: boundedNumber(args.explosiveness, 0, 0, 1, "invalid_particle_explosiveness"),
          randomness: boundedNumber(args.randomness, 0.15, 0, 1, "invalid_particle_randomness"),
          speed_scale: boundedNumber(args.speedScale, 1, 0, 16, "invalid_particle_speed_scale"),
          fixed_fps: boundedInteger(args.fixedFps, 30, 1, 240, "invalid_particle_fixed_fps"),
          visibility_aabb_size: boundedNumber(args.visibilityAabbSize, 8, 0.1, 1000, "invalid_particle_visibility_aabb_size"),
          draw_mesh: validateParticleDrawMesh(args.drawMesh),
          draw_size: boundedNumber(args.drawSize, 0.35, 0.01, 100, "invalid_particle_draw_size"),
          spread: boundedNumber(args.spread, 35, 0, 180, "invalid_particle_spread"),
          initial_velocity_min: boundedNumber(args.initialVelocityMin, 0.8, 0, 10000, "invalid_particle_initial_velocity"),
          initial_velocity_max: boundedNumber(args.initialVelocityMax, 2.4, 0, 10000, "invalid_particle_initial_velocity"),
          particle_scale_min: boundedNumber(args.particleScaleMin, 0.15, 0, 1000, "invalid_particle_scale"),
          particle_scale_max: boundedNumber(args.particleScaleMax, 0.35, 0, 1000, "invalid_particle_scale"),
          local_to_scene: args.localToScene !== false,
          restart: args.restart !== false,
          select: args.select !== false,
        };
        copyJsonField(args, params, "position");
        copyJsonField(args, params, "rotationDegrees");
        copyJsonField(args, params, "scale");
        copyJsonField(args, params, "direction");
        copyJsonField(args, params, "gravity");
        copyJsonField(args, params, "color");
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "create_particle_effect",
            params,
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.set_particle_effect_properties": async (args = {}) => {
      try {
        const params: JsonObject = {
          node_path: validateNodePath(stringOrDefault(args.nodePath, "")),
        };
        copyBoundedIntegerField(args, params, "amount", "amount", 1, 10_000, "invalid_particle_amount");
        copyBoundedNumberField(args, params, "lifetime", "lifetime", 0.05, 60, "invalid_particle_lifetime");
        copyBooleanField(args, params, "emitting", "emitting", "invalid_particle_emitting");
        copyBooleanField(args, params, "oneShot", "one_shot", "invalid_particle_one_shot");
        copyBoundedNumberField(args, params, "explosiveness", "explosiveness", 0, 1, "invalid_particle_explosiveness");
        copyBoundedNumberField(args, params, "randomness", "randomness", 0, 1, "invalid_particle_randomness");
        copyBoundedNumberField(args, params, "speedScale", "speed_scale", 0, 16, "invalid_particle_speed_scale");
        copyBoundedIntegerField(args, params, "fixedFps", "fixed_fps", 1, 240, "invalid_particle_fixed_fps");
        copyBoundedNumberField(args, params, "visibilityAabbSize", "visibility_aabb_size", 0.1, 1000, "invalid_particle_visibility_aabb_size");
        if (args.drawMesh !== undefined) {
          params.draw_mesh = validateParticleDrawMeshForEdit(args.drawMesh);
        }
        copyBoundedNumberField(args, params, "drawSize", "draw_size", 0.01, 100, "invalid_particle_draw_size");
        copyBoundedNumberField(args, params, "spread", "spread", 0, 180, "invalid_particle_spread");
        copyBoundedNumberField(args, params, "initialVelocityMin", "initial_velocity_min", 0, 10000, "invalid_particle_initial_velocity");
        copyBoundedNumberField(args, params, "initialVelocityMax", "initial_velocity_max", 0, 10000, "invalid_particle_initial_velocity");
        copyBoundedNumberField(args, params, "particleScaleMin", "particle_scale_min", 0, 1000, "invalid_particle_scale");
        copyBoundedNumberField(args, params, "particleScaleMax", "particle_scale_max", 0, 1000, "invalid_particle_scale");
        copyBooleanField(args, params, "createProcessMaterialIfMissing", "create_process_material_if_missing", "invalid_particle_material_create_flag");
        copyBooleanField(args, params, "localToScene", "local_to_scene", "invalid_local_to_scene");
        copyBooleanField(args, params, "restart", "restart", "invalid_particle_restart");
        copyBooleanField(args, params, "select", "select", "invalid_particle_select");
        copyJsonField(args, params, "direction");
        copyJsonField(args, params, "gravity");
        copyJsonField(args, params, "color");
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "set_particle_effect_properties",
            params,
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.list_animation_players": async (args = {}) => {
      try {
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "list_animation_players",
            {
              max_players: boundedInteger(args.maxPlayers, 64, 1, 64, "invalid_max_players"),
              include_empty: args.includeEmpty !== false,
            },
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.inspect_animation": async (args = {}) => {
      try {
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "inspect_animation",
            {
              node_path: validateNodePath(stringOrDefault(args.nodePath, "")),
              animation_name: optionalAnimationName(args.animationName),
              include_keys: args.includeKeys !== false,
              max_tracks: boundedInteger(args.maxTracks, 120, 1, 120, "invalid_max_tracks"),
              max_keys_per_track: boundedInteger(args.maxKeysPerTrack, 16, 0, 16, "invalid_max_keys_per_track"),
            },
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.preview_animation": async (args = {}) => {
      try {
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "preview_animation",
            {
              node_path: validateNodePath(stringOrDefault(args.nodePath, "")),
              animation_name: validateAnimationName(stringOrDefault(args.animationName, "")),
              mode: optionalAnimationPreviewMode(args.mode),
              position: optionalNumber(args.position, 0),
              speed: optionalNumber(args.speed, 1),
              custom_blend: optionalNumber(args.customBlend, -1),
              from_end: args.fromEnd === true,
            },
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.stop_animation_preview": async (args = {}) => {
      try {
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "stop_animation_preview",
            {
              node_path: validateNodePath(stringOrDefault(args.nodePath, "")),
              keep_state: args.keepState !== false,
            },
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.diagnostics_get": async (args = {}) =>
      toolResult(
        await sendEditorControlRequest(
          bridge,
          "get_diagnostics",
          { limit: numberOrDefault(args.limit, 80) },
          numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
        ),
      ),
    "godot.diagnostics_clear": async (args = {}) =>
      toolResult(
        await sendEditorControlRequest(
          bridge,
          "clear_diagnostics",
          { confirm: args.confirm === true },
          numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
        ),
      ),
    "godot.set_node_transform": async (args = {}) => {
      try {
        const params: JsonObject = {
          node_path: validateNodePath(stringOrDefault(args.nodePath, "")),
          mode: optionalTransformMode(args.mode),
          space: "local",
        };
        copyJsonField(args, params, "position");
        copyJsonField(args, params, "rotationDegrees");
        copyJsonField(args, params, "scale");
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "set_node_transform",
            params,
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.set_node_properties": async (args = {}) => {
      try {
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "set_node_properties",
            {
              node_path: validateNodePath(stringOrDefault(args.nodePath, "")),
              changes: validatePropertyChanges(args.changes),
            },
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.undo_last_bridge_action": async (args = {}) =>
      toolResult(
        await sendEditorControlRequest(
          bridge,
          "undo_last_bridge_action",
          {},
          numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
        ),
      ),
    "godot.assign_resource_to_node": async (args = {}) => {
      try {
        const params: JsonObject = {
          node_path: validateNodePath(stringOrDefault(args.nodePath, "")),
          property: validatePropertyName(args.property),
          clear: args.clear === true,
        };
        if (args.clear !== true) {
          params.resource_path = await validateProjectResPath(config.projectRoot, stringOrDefault(args.resourcePath, ""), {
            kind: "resource",
            extensions: [],
            mustExist: true,
          });
        }
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "assign_resource_to_node",
            params,
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.create_node_resource": async (args = {}) => {
      try {
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "create_node_resource",
            {
              node_path: validateNodePath(stringOrDefault(args.nodePath, "")),
              property: validatePropertyName(args.property),
              resource_class: validateResourceClassName(stringOrDefault(args.resourceClass, "")),
              local_to_scene: args.localToScene !== false,
              changes: validateOptionalPropertyChanges(args.changes),
            },
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.set_resource_properties": async (args = {}) => {
      try {
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "set_resource_properties",
            {
              node_path: validateNodePath(stringOrDefault(args.nodePath, "")),
              property: validatePropertyName(args.property),
              changes: validatePropertyChanges(args.changes),
            },
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.create_node": async (args = {}) => {
      try {
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "create_node",
            {
              parent_path: args.parentPath === undefined ? "." : validateNodePath(stringOrDefault(args.parentPath, ".")),
              class_name: validateNodeClassName(stringOrDefault(args.className, "Node")),
              name: optionalNodeName(args.name),
              index: optionalIndex(args.index),
            },
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.delete_node": async (args = {}) => {
      try {
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "delete_node",
            { node_path: validateNodePath(stringOrDefault(args.nodePath, "")) },
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.rename_node": async (args = {}) => {
      try {
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "rename_node",
            {
              node_path: validateNodePath(stringOrDefault(args.nodePath, "")),
              new_name: validateNodeName(stringOrDefault(args.newName, "")),
            },
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.reparent_node": async (args = {}) => {
      try {
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "reparent_node",
            {
              node_path: validateNodePath(stringOrDefault(args.nodePath, "")),
              new_parent_path: validateNodePath(stringOrDefault(args.newParentPath, "")),
              index: optionalIndex(args.index),
            },
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.duplicate_node": async (args = {}) => {
      try {
        const params: JsonObject = {
          node_path: validateNodePath(stringOrDefault(args.nodePath, "")),
          index: optionalIndex(args.index),
        };
        if (typeof args.parentPath === "string" && args.parentPath.trim() !== "") {
          params.parent_path = validateNodePath(args.parentPath);
        }
        if (args.name !== undefined) {
          params.name = optionalNodeName(args.name);
        }
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "duplicate_node",
            params,
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.instance_scene": async (args = {}) => {
      try {
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "instance_scene",
            {
              scene_path: await validateOpenScenePath(config.projectRoot, stringOrDefault(args.scenePath, "")),
              parent_path: args.parentPath === undefined ? "." : validateNodePath(stringOrDefault(args.parentPath, ".")),
              name: optionalNodeName(args.name),
              index: optionalIndex(args.index),
            },
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.place_asset_in_scene": async (args = {}) => {
      try {
        const params: JsonObject = {
          asset_path: await validatePlaceableAssetPath(config.projectRoot, stringOrDefault(args.assetPath, "")),
          parent_path: args.parentPath === undefined ? "." : validateNodePath(stringOrDefault(args.parentPath, ".")),
          name: optionalNodeName(args.name),
          index: optionalIndex(args.index),
          select: args.select !== false,
        };
        copyJsonField(args, params, "position");
        copyJsonField(args, params, "rotationDegrees");
        copyJsonField(args, params, "scale");
        copyBooleanField(args, params, "createCollider", "create_collider", "invalid_create_collider");
        if (args.materialColor !== undefined) {
          params.material_color = args.materialColor;
        }
        const result = await sendEditorControlRequest(
          bridge,
          "place_asset_in_scene",
          params,
          numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
        );
        return toolResult(await withOptionalPostActionScreenshot(bridge, config, args, result, "place_asset_in_scene"));
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.list_signal_connections": async (args = {}) => {
      try {
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "list_signal_connections",
            {
              node_path: validateNodePath(stringOrDefault(args.nodePath, "")),
              include_empty: args.includeEmpty === true,
            },
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.connect_signal": async (args = {}) => {
      try {
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "connect_signal",
            {
              source_node_path: validateNodePath(stringOrDefault(args.sourceNodePath, "")),
              signal_name: validateIdentifierName(stringOrDefault(args.signalName, ""), "signal"),
              target_node_path: validateNodePath(stringOrDefault(args.targetNodePath, "")),
              method_name: validateIdentifierName(stringOrDefault(args.methodName, ""), "method"),
              flags: optionalFlags(args.flags),
            },
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.disconnect_signal": async (args = {}) => {
      try {
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "disconnect_signal",
            {
              source_node_path: validateNodePath(stringOrDefault(args.sourceNodePath, "")),
              signal_name: validateIdentifierName(stringOrDefault(args.signalName, ""), "signal"),
              target_node_path: validateNodePath(stringOrDefault(args.targetNodePath, "")),
              method_name: validateIdentifierName(stringOrDefault(args.methodName, ""), "method"),
            },
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.create_animation_clip": async (args = {}) => {
      try {
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "create_animation_clip",
            {
              node_path: validateNodePath(stringOrDefault(args.nodePath, "")),
              animation_name: validateAnimationName(stringOrDefault(args.animationName, "")),
              library_key: optionalAnimationLibraryKey(args.libraryKey),
              length: boundedNumber(args.length, 1, 0.001, 3600, "invalid_animation_length"),
              step: boundedNumber(args.step, 0.033333335, 0.001, 10, "invalid_animation_step"),
              loop_mode: boundedInteger(args.loopMode, 0, 0, 2, "invalid_animation_loop_mode"),
              tracks: validateAnimationTracks(args.tracks),
            },
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.editor_batch": async (args = {}) => {
      try {
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "editor_batch",
            {
              actions: validateEditorBatch(args.actions),
              stopOnError: args.stopOnError !== false,
            },
            numberOrDefault(args.timeoutMs, Math.max(config.addonRequestTimeoutMs, 30_000)),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.save_scene": async (args = {}) => {
      const result = await sendEditorControlRequest(
        bridge,
        "save_scene",
        {},
        numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
      );
      return toolResult(await attachPostSaveCheck(result, config, args));
    },
    "godot.save_all_scenes": async (args = {}) =>
      toolResult(
        await sendEditorControlRequest(
          bridge,
          "save_all_scenes",
          {},
          numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
        ),
      ),
    "godot.notes_get": async (args = {}) =>
      toolResult(
        await sendEditorControlRequest(
          bridge,
          "notes_get",
          {},
          numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
        ),
      ),
    "godot.notes_append": async (args = {}) => {
      try {
        const text = stringOrDefault(args.text, "").trim();
        if (!text) {
          throw codedError("note_required", "text is required.");
        }
        if (text.length > 4_000) {
          throw codedError("note_too_large", "text is limited to 4000 characters.");
        }
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "notes_append",
            { text, author: stringOrDefault(args.author, "codex") },
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.notes_clear": async (args = {}) =>
      toolResult(
        await sendEditorControlRequest(
          bridge,
          "notes_clear",
          {},
          numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
        ),
      ),
    "godot.inspect_3d_scene": async () => toolResult(inspect3dScene(await bridge.readSnapshot())),
    "godot.create_diagnostic_snapshot": async (args = {}) =>
      toolResult(
        await createDiagnosticSnapshot(
          config.bridgeDir,
          inspect3dScene(await bridge.readSnapshot()),
          typeof args.label === "string" ? args.label : undefined,
        ),
      ),
    "godot.check_export_readiness": async () => toolResult(await checkExportReadiness(config.projectRoot, config.godotExecutable)),
    "godot.create_undo_snapshot": async (args = {}) =>
      toolResult(
        await createUndoSnapshot(config.projectRoot, config.bridgeDir, {
          paths: stringArrayOrEmpty(args.paths),
          label: typeof args.label === "string" ? args.label : undefined,
        }),
      ),
    "godot.create_visual_baseline": async (args = {}) =>
      toolResult(await createVisualBaseline(config.bridgeDir, {
        screenshotPath: stringOrDefault(args.screenshotPath, ""),
        baselineName: typeof args.baselineName === "string" ? args.baselineName : undefined,
      })),
    "godot.compare_visual_regression": async (args = {}) =>
      toolResult(await compareVisualRegression(config.bridgeDir, {
        currentScreenshotPath: stringOrDefault(args.currentScreenshotPath, ""),
        baselineName: typeof args.baselineName === "string" ? args.baselineName : undefined,
        baselinePath: typeof args.baselinePath === "string" ? args.baselinePath : undefined,
      })),
    "godot.apply_approved_diff": async (args = {}) => {
      try {
        return toolResult(await applyApprovedDiff(config.projectRoot, config.bridgeDir, {
          path: stringOrDefault(args.path, ""),
          proposedContent: stringOrDefault(args.proposedContent, ""),
          allowCreate: args.allowCreate === true,
          expectedCurrentSha256: typeof args.expectedCurrentSha256 === "string" ? args.expectedCurrentSha256 : undefined,
          approvalToken: typeof args.approvalToken === "string" ? args.approvalToken : undefined,
          label: typeof args.label === "string" ? args.label : undefined,
        }));
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.generate_scene_from_prompt": async (args = {}) => {
      try {
        return toolResult(await generateSceneFromPrompt(config.projectRoot, config.bridgeDir, {
          prompt: stringOrDefault(args.prompt, ""),
          path: stringOrDefault(args.path, ""),
          apply: args.apply === true,
          approvalToken: typeof args.approvalToken === "string" ? args.approvalToken : undefined,
        }));
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.fix_selected_node": async (args = {}) =>
      toolResult(
        await bridge.sendAddonRequest(
          "fix_selected_node",
          {
            requested_by: "mcp_server",
            fix_code: stringOrDefault(args.fixCode, ""),
            approval_token: stringOrDefault(args.approvalToken, ""),
          },
          numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
        ),
      ),
    "godot.capture_viewport_screenshot": async (args = {}) =>
      toolResult(
        await bridge.sendAddonRequest(
          "capture_viewport_screenshot",
          { requested_by: "mcp_server" },
          numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
        ),
      ),
    "godot.capture_timeline_screenshots": async (args = {}) => {
      try {
        return toolResult(
          await captureTimelineScreenshots(config, bridge, {
            frameCount: boundedInteger(args.frameCount, 3, 2, 12, "invalid_timeline_frame_count"),
            intervalMs: boundedInteger(args.intervalMs, 250, 50, 5_000, "invalid_timeline_interval_ms"),
            timeoutMs: boundedInteger(args.timeoutMs, config.addonRequestTimeoutMs, 250, 30_000, "invalid_timeline_timeout_ms"),
            reason: typeof args.reason === "string" ? args.reason : undefined,
            baselineName: typeof args.baselineName === "string" ? args.baselineName : undefined,
            baselinePath: typeof args.baselinePath === "string" ? args.baselinePath : undefined,
          }),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.capture_multi_view_screenshots": async (args = {}) => {
      try {
        const nodePath = typeof args.nodePath === "string" ? args.nodePath.trim() : "";
        const groupName = typeof args.groupName === "string" ? args.groupName.trim() : "";
        if (nodePath !== "" && groupName !== "") {
          throw codedError("invalid_spatial_selector", "Use either nodePath or groupName, not both.");
        }
        const params: JsonObject = {
          selected_only: args.selectedOnly !== false,
          max_nodes: boundedInteger(args.maxNodes, 32, 1, 256, "invalid_max_nodes"),
          width: boundedInteger(args.width, 1024, 64, 2048, "invalid_multi_view_width"),
          height: boundedInteger(args.height, 768, 64, 2048, "invalid_multi_view_height"),
          views: validateMultiViewViews(args.views),
        };
        if (nodePath !== "") {
          params.node_path = validateNodePath(nodePath);
          params.selected_only = false;
        }
        if (groupName !== "") {
          params.group_name = validateSpatialGroupName(groupName);
          params.selected_only = false;
        }
        const result = await sendEditorControlRequest(
          bridge,
          "capture_multi_view",
          params,
          numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          // The addon awaits live editor frames for this action on the request-file path only.
          { skipHostRpc: true },
        );
        return toolResult(await withOptionalMultiViewBaselineComparison(config, result, args));
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.open_scene": async (args = {}) => {
      try {
        const scenePath = await validateOpenScenePath(config.projectRoot, stringOrDefault(args.scenePath, ""));
        const makeMainScreen = optionalMainScreen(args.makeMainScreen);
        return toolResult(
          await bridge.sendAddonRequest(
            "open_scene",
            {
              requested_by: "mcp_server",
              scene_path: scenePath,
              make_main_screen: makeMainScreen,
              select_in_file_system: args.selectInFileSystem === true,
            },
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.run_current_scene": async (args = {}) => {
      try {
        const payload: JsonObject = {
          requested_by: "mcp_server",
          timeout_ms: numberOrDefault(args.timeoutMs, config.runSceneTimeoutMs),
        };
        if (typeof args.scenePath === "string" && args.scenePath.length > 0) {
          payload.scene_path = await validateOpenScenePath(config.projectRoot, args.scenePath);
        }
        return toolResult(
          await bridge.sendAddonRequest(
            "run_current_scene",
            payload,
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.stop_running_scene": async (args = {}) =>
      toolResult(
        await sendEditorControlRequest(
          bridge,
          "stop_running_scene",
          {},
          numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
        ),
      ),
    "godot.emergency_stop": async (args = {}) =>
      toolResult(
        await sendEditorControlRequest(
          bridge,
          "emergency_stop",
          { source: "mcp_server" },
          numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
        ),
      ),
    "godot.playtest_input": async (args = {}) => {
      try {
        return toolResult(
          await sendEditorControlRequest(
            bridge,
            "playtest_input",
            playtestInputParams(args),
            numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.run_playtest_scenario": async (args = {}) => {
      try {
        const timeoutMs = boundedInteger(args.timeoutMs, config.runSceneTimeoutMs, 1_000, 60_000, "invalid_playtest_scenario_timeout");
        return toolResult(
          await bridge.sendAddonRequest(
            "editor_control",
            {
              requested_by: "mcp_server",
              action: "run_playtest_scenario",
              params: {
                scene_path: await validateOpenScenePath(config.projectRoot, stringOrDefault(args.scenePath, "")),
                steps: validatePlaytestScenarioSteps(args.steps),
                timeout_ms: timeoutMs,
              },
            },
            timeoutMs,
            { skipHostRpc: true },
          ),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.runtime_get_state": async (args = {}) => toolResult(await getRuntimeState(config, args)),
    "godot.runtime_get_events": async (args = {}) => toolResult(await getRuntimeEvents(config, args)),
    "godot.run_test_scene": async (args = {}) => {
      try {
        return toolResult(
          await runTestScene(config, {
            scenePath: stringOrDefault(args.scenePath, "res://scenes/test_3d.tscn"),
            timeoutMs: numberOrUndefined(args.timeoutMs),
          }),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
    "godot.preview_scene_diff": async (args = {}) => {
      try {
        return toolResult(
          await previewSceneDiff({
            projectRoot: config.projectRoot,
            targetPath: stringOrDefault(args.path, ""),
            proposedContent: stringOrDefault(args.proposedContent, ""),
            allowCreate: args.allowCreate === true,
            contextLines: numberOrUndefined(args.contextLines),
          }),
        );
      } catch (error) {
        return toolResult(errorEnvelope(error));
      }
    },
  };
}

export function toolResult(envelope: ToolEnvelope | JsonObject): CallToolResult {
  const isError = envelope.status !== "ok";
  return {
    content: [{ type: "text", text: JSON.stringify(envelope, null, 2) }],
    structuredContent: envelope,
    isError,
  };
}

async function sendEditorControlRequest(
  bridge: BridgeClient,
  action: string,
  params: JsonObject,
  timeoutMs: number,
  options: { skipHostRpc?: boolean } = {},
): Promise<ToolEnvelope> {
  return bridge.sendAddonRequest(
    "editor_control",
    {
      requested_by: "mcp_server",
      action,
      params,
    },
    timeoutMs,
    options,
  );
}

async function enrichCurrentScene(envelope: ToolEnvelope, config: ServerConfig): Promise<ToolEnvelope> {
  if (envelope.status !== "ok") {
    return envelope;
  }

  return {
    ...envelope,
    project_root: config.projectRoot,
    bridge_dir: config.bridgeDir,
  };
}

async function attachPostSaveCheck(
  envelope: ToolEnvelope,
  config: ServerConfig,
  args: JsonObject,
): Promise<ToolEnvelope> {
  if (envelope.status !== "ok" || !isJsonObject(envelope.response)) {
    return envelope;
  }
  const response = envelope.response;
  if (response.status !== "succeeded" || !isJsonObject(response.data)) {
    return envelope;
  }
  const data = response.data;
  if (data.saved !== true) {
    return envelope;
  }

  const postSaveCheck = await runProjectParseCheck(config, {
    timeoutMs: numberOrDefault(args.postSaveCheckTimeoutMs, config.runSceneTimeoutMs),
  });
  return {
    ...envelope,
    post_save_check: postSaveCheck,
    post_save_check_passed: postSaveCheck.status === "ok",
    response: {
      ...response,
      data: {
        ...data,
        post_save_check: postSaveCheck,
        post_save_check_passed: postSaveCheck.status === "ok",
      },
    },
  };
}

function errorEnvelope(error: unknown): ToolEnvelope {
  if (error instanceof PreviewDiffError) {
    return {
      status: "invalid_request",
      error: {
        code: error.code,
        message: error.message,
        ...error.details,
      },
    };
  }

  if (isCodedError(error)) {
    return {
      status: "invalid_request",
      error: {
        code: error.code,
        message: error.message,
        ...error.details,
      },
    };
  }

  return {
    status: "error",
    error: {
      code: "unexpected_error",
      message: error instanceof Error ? error.message : String(error),
    },
  };
}

function numberOrDefault(value: unknown, fallback: number): number {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function numberOrUndefined(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function stringOrDefault(value: unknown, fallback: string): string {
  return typeof value === "string" ? value : fallback;
}

function stringArrayOrEmpty(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

function isCodedError(error: unknown): error is Error & { code: string; details?: JsonObject } {
  return error instanceof Error && "code" in error && typeof (error as { code?: unknown }).code === "string";
}

async function validateOpenScenePath(projectRoot: string, scenePath: string): Promise<string> {
  return validateProjectResPath(projectRoot, scenePath, {
    kind: "scene",
    extensions: [".tscn", ".scn"],
    mustExist: true,
  });
}

async function validatePlaceableAssetPath(projectRoot: string, assetPath: string): Promise<string> {
  return validateProjectResPath(projectRoot, assetPath, {
    kind: "asset",
    extensions: [".glb", ".gltf", ".obj", ".fbx", ".dae", ".blend", ".mesh", ".res", ".tres", ".tscn", ".scn", ".png"],
    mustExist: true,
  });
}

interface ResPathValidationOptions {
  kind: string;
  extensions: string[];
  mustExist: boolean;
}

async function validateProjectResPath(
  projectRoot: string,
  resPath: string,
  options: ResPathValidationOptions,
): Promise<string> {
  const { kind, extensions, mustExist } = options;
  const pathCode = `invalid_${kind}_path`;
  const extensionCode = `invalid_${kind}_extension`;
  if (!resPath.startsWith("res://")) {
    throw codedError(pathCode, `${kind} path must be a project-local res:// path.`);
  }
  const resourcePath = resPath.slice("res://".length).replace(/\\/g, "/");
  if (resourcePath.length === 0 || resourcePath.split("/").some((part) => part === "" || part === "." || part === "..")) {
    throw codedError(pathCode, `${kind} path must not contain empty, current-directory or parent-directory segments.`);
  }
  if (resourcePath.startsWith(".godot/") || resourcePath.startsWith(".import/") || resourcePath.includes("/.import/")) {
    throw codedError(pathCode, "Generated Godot cache/import paths cannot be used through the bridge.");
  }
  const lower = resourcePath.toLowerCase();
  if (extensions.length > 0 && !extensions.some((extension) => lower.endsWith(extension))) {
    throw codedError(extensionCode, `${kind} path must end in one of: ${extensions.join(", ")}.`);
  }

  const projectRootResolved = path.resolve(projectRoot);
  const absolutePath = path.resolve(projectRootResolved, ...resourcePath.split("/"));
  const relative = path.relative(projectRootResolved, absolutePath);
  if (relative.startsWith("..") || path.isAbsolute(relative)) {
    throw codedError(pathCode, `${kind} path resolved outside the Godot project root.`);
  }
  if (mustExist) {
    try {
      await fs.access(absolutePath);
    } catch {
      throw codedError(`${kind}_not_found`, `${kind} file does not exist: ${resPath}.`, { absolute_path: absolutePath });
    }
  }
  return `res://${resourcePath}`;
}

function validateProjectResRootPath(resPath: string): string {
  if (!resPath.startsWith("res://")) {
    throw codedError("invalid_resource_root", "rootPath must be a project-local res:// path.");
  }
  const resourcePath = resPath.slice("res://".length).replace(/\\/g, "/");
  if (resourcePath.length === 0) {
    return "res://";
  }
  if (resourcePath.split("/").some((part) => part === "" || part === "." || part === "..")) {
    throw codedError("invalid_resource_root", "rootPath must not contain empty, current-directory or parent-directory segments.");
  }
  if (resourcePath.startsWith(".godot/") || resourcePath.startsWith(".import/") || resourcePath.includes("/.import/")) {
    throw codedError("invalid_resource_root", "Generated Godot cache/import paths cannot be listed through the bridge.");
  }
  return `res://${resourcePath.replace(/\/+$/, "")}`;
}

function validateExtensions(value: unknown): string[] {
  if (value === undefined || value === null) {
    return [];
  }
  if (!Array.isArray(value)) {
    throw codedError("invalid_extensions", "extensions must be an array when provided.");
  }
  if (value.length > 24) {
    throw codedError("too_many_extensions", "extensions supports at most 24 entries.");
  }
  const extensions: string[] = [];
  for (const item of value) {
    if (typeof item !== "string") {
      throw codedError("invalid_extension", "Each extension must be a string.");
    }
    const extension = item.trim().toLowerCase().replace(/^\./, "");
    if (!extension || extension.length > 15 || /[\\/.\r\n]/.test(extension)) {
      throw codedError("invalid_extension", "Extensions must be simple file suffixes such as gd or tscn.");
    }
    const normalized = `.${extension}`;
    if (!extensions.includes(normalized)) {
      extensions.push(normalized);
    }
  }
  return extensions;
}

function optionalResourceType(value: unknown): string {
  if (value === undefined || value === null || value === "") {
    return "";
  }
  const typeName = stringOrDefault(value, "").trim();
  if (!typeName || typeName.length > 96 || /[\r\n/\\]/.test(typeName)) {
    throw codedError("invalid_resource_type", "typeFilter must be a simple Godot resource type name.");
  }
  return typeName;
}

function optionalMainScreen(value: unknown): string {
  if (value === undefined || value === null || value === "") {
    return "";
  }
  if (value === "2D" || value === "3D" || value === "Script") {
    return value;
  }
  throw codedError("invalid_main_screen", "makeMainScreen must be 2D, 3D or Script when provided.");
}

function optionalEditorMainScreen(value: unknown): string {
  if (value === undefined || value === null || value === "") {
    return "";
  }
  if (
    value === "2D" ||
    value === "3D" ||
    value === "Script" ||
    value === "Game" ||
    value === "AssetLib" ||
    value === "Codex Bridge"
  ) {
    return value;
  }
  throw codedError("invalid_main_screen", "mainScreen must be 2D, 3D, Script, Game, AssetLib or Codex Bridge when provided.");
}

function optionalEditorPanel(value: unknown): string {
  if (value === undefined || value === null || value === "") {
    throw codedError("invalid_editor_panel", "panel is required.");
  }
  const panel = stringOrDefault(value, "").trim();
  const allowed = new Set([
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
  ]);
  const aliases: Record<string, string> = {
    output: "Output",
    console: "Output",
    log: "Output",
    debugger: "Debugger",
    errors: "Debugger",
    error: "Debugger",
    warnings: "Debugger",
    warning: "Debugger",
    stacktrace: "Stack Trace",
    "stack trace": "Stack Trace",
    audio: "Audio",
    animation: "Animation",
    shader: "Shader Editor",
    "shader editor": "Shader Editor",
    signals: "Signal Visualizer",
    "signal visualizer": "Signal Visualizer",
    profiler: "Profiler",
    "visual profiler": "Visual Profiler",
    monitors: "Monitors",
    "video ram": "Video RAM",
    "network profiler": "Network Profiler",
    inspector: "Inspector",
    filesystem: "FileSystem",
    "file system": "FileSystem",
    scene: "Scene",
    import: "Import",
  };
  const normalized = panel.toLowerCase().replace(/[_-]+/g, " ").replace(/\s+/g, " ").trim();
  const canonical = aliases[normalized] ?? panel;
  if (allowed.has(canonical)) {
    return canonical;
  }
  throw codedError("invalid_editor_panel", "panel must be Output, Debugger, Stack Trace, Audio, Animation, Shader Editor, Signal Visualizer, Profiler, Visual Profiler, Monitors, Video RAM, Network Profiler, Inspector, FileSystem, Scene or Import.");
}

function optionalViewport(value: unknown): "2D" | "3D" {
  if (value === undefined || value === null || value === "") {
    return "2D";
  }
  const normalized = stringOrDefault(value, "").trim().toLowerCase().replace(/[_-]+/g, " ").replace(/\s+/g, " ");
  if (normalized === "2d" || normalized === "canvas" || normalized === "canvas 2d") {
    return "2D";
  }
  if (normalized === "3d" || normalized === "spatial") {
    return "3D";
  }
  throw codedError("invalid_viewport", "viewport must be 2D or 3D.");
}

function optionalViewportAction(viewport: "2D" | "3D", value: unknown): string {
  const raw = stringOrDefault(value, "").trim();
  if (!raw) {
    return viewport === "2D" ? "pan" : "frame_selected";
  }
  const normalized = raw.toLowerCase().replace(/[_-]+/g, " ").replace(/\s+/g, " ").trim();
  const canonical = normalized.replace(/\s+/g, "_");
  const allowed = viewport === "2D"
    ? new Set(["pan", "zoom", "reset"])
    : new Set(["frame_selected", "orbit", "zoom"]);
  if (allowed.has(canonical)) {
    return canonical;
  }
  throw codedError(
    "invalid_viewport_action",
    viewport === "2D"
      ? "2D viewport action must be pan, zoom or reset."
      : "3D viewport action must be frame_selected, orbit or zoom.",
  );
}

function optionalTransformMode(value: unknown): string {
  if (value === undefined || value === null || value === "") {
    return "absolute";
  }
  if (value === "absolute" || value === "relative") {
    return value;
  }
  throw codedError("invalid_transform_mode", "mode must be absolute or relative.");
}

function spatialMutationParams(args: JsonObject): JsonObject {
  const nodePath = typeof args.nodePath === "string" ? args.nodePath.trim() : "";
  const groupName = typeof args.groupName === "string" ? args.groupName.trim() : "";
  if (nodePath !== "" && groupName !== "") {
    throw codedError("invalid_spatial_selector", "Use either nodePath or groupName, not both.");
  }
  const selectedOnly = args.selectedOnly !== false;
  if (nodePath === "" && groupName === "" && !selectedOnly) {
    throw codedError("broad_scene_mutation_rejected", "Spatial mutation requires nodePath, groupName or selectedOnly=true.");
  }
  const params: JsonObject = {
    selected_only: selectedOnly,
    max_nodes: boundedInteger(args.maxNodes, 24, 1, 96, "invalid_max_nodes"),
  };
  if (nodePath !== "") {
    params.node_path = validateNodePath(nodePath);
    params.selected_only = false;
  }
  if (groupName !== "") {
    params.group_name = validateSpatialGroupName(groupName);
    params.selected_only = false;
  }
  return params;
}

async function withOptionalPostActionScreenshot(
  bridge: BridgeClient,
  config: ServerConfig,
  args: JsonObject,
  result: ToolEnvelope,
  reason: string,
): Promise<ToolEnvelope> {
  if (result.status !== "ok" || args.captureScreenshot === false) {
    return result;
  }
  const screenshot = await bridge.sendAddonRequest(
    "capture_viewport_screenshot",
    {
      requested_by: "mcp_server",
      reason,
    },
    numberOrDefault(args.timeoutMs, config.addonRequestTimeoutMs),
  );
  return {
    ...result,
    screenshot_after_action: screenshot,
  };
}

async function withOptionalMultiViewBaselineComparison(
  config: ServerConfig,
  result: ToolEnvelope,
  args: JsonObject,
): Promise<ToolEnvelope> {
  const baselineName = typeof args.baselineName === "string" ? args.baselineName : undefined;
  const baselinePath = typeof args.baselinePath === "string" ? args.baselinePath : undefined;
  if (result.status !== "ok" || (!baselineName && !baselinePath)) {
    return result;
  }

  const frames = multiViewFrames(result);
  const comparisons: JsonObject[] = [];
  for (const frame of frames) {
    const view = typeof frame.view === "string" ? frame.view : "unknown";
    const screenshotPath = screenshotPathFromFrame(frame);
    if (!screenshotPath) {
      comparisons.push({
        view,
        status: "skipped",
        reason: "frame_without_png_path",
      });
      continue;
    }
    comparisons.push({
      view,
      screenshot_path: screenshotPath,
      result: await compareVisualRegression(config.bridgeDir, {
        currentScreenshotPath: screenshotPath,
        baselineName,
        baselinePath,
      }),
    });
  }

  return {
    ...result,
    baseline_comparison: {
      status: comparisons.some((comparison) => {
        const comparisonResult = comparison.result;
        return isJsonObject(comparisonResult) && comparisonResult.status === "ok";
      }) ? "ok" : "no_successful_comparisons",
      baseline_name: baselineName ?? null,
      baseline_path: baselinePath ?? null,
      compared_frames: comparisons.length,
      comparisons,
    },
  };
}

function multiViewFrames(result: ToolEnvelope): JsonObject[] {
  const response = result.response;
  const data = isJsonObject(response) && isJsonObject(response.data)
    ? response.data
    : result.data;
  if (isJsonObject(data) && Array.isArray(data.frames)) {
    return data.frames.filter(isJsonObject);
  }
  return [];
}

function screenshotPathFromFrame(frame: JsonObject): string | null {
  const artifact = frame.artifact;
  if (!isJsonObject(artifact)) {
    return null;
  }
  if (typeof artifact.local_path === "string" && artifact.local_path.trim() !== "") {
    return artifact.local_path;
  }
  if (typeof artifact.absolute_path === "string" && artifact.absolute_path.trim() !== "") {
    return artifact.absolute_path;
  }
  return null;
}

function validateNodePath(value: string): string {
  const nodePath = value.trim();
  if (!nodePath) {
    throw codedError("invalid_node_path", "nodePath is required.");
  }
  if (nodePath.length > 400 || nodePath.includes("\n") || nodePath.includes("\r")) {
    throw codedError("invalid_node_path", "nodePath is too long or contains a newline.");
  }
  if (nodePath.startsWith("res://") || nodePath.includes("..")) {
    throw codedError("invalid_node_path", "nodePath must be a scene-local node path.");
  }
  return nodePath;
}

function validateSpatialGroupName(value: string): string {
  const groupName = value.trim();
  if (!groupName || groupName.length > 96 || /[\r\n/\\]/.test(groupName) || groupName.includes("..")) {
    throw codedError("invalid_group_name", "groupName must be a simple Godot group name.");
  }
  return groupName;
}

function validateSpatialQuery(value: string): string {
  const query = value.trim().toLowerCase();
  if (query === "ground_gap" || query === "aabb_overlap" || query === "runtime_raycast" || query === "raycast") {
    return query;
  }
  throw codedError("invalid_spatial_query", "query must be ground_gap, aabb_overlap or runtime_raycast.");
}

function validateMultiViewViews(value: unknown): JsonValue {
  if (value === undefined || value === null) {
    return ["front", "side", "top", "perspective"];
  }
  if (!Array.isArray(value)) {
    throw codedError("invalid_multi_view_views", "views must be an array of front, side, top and/or perspective.");
  }
  const views: string[] = [];
  for (const item of value) {
    if (typeof item !== "string") {
      throw codedError("invalid_multi_view_views", "views must contain only strings.");
    }
    const view = item.trim().toLowerCase();
    if (view !== "front" && view !== "side" && view !== "top" && view !== "perspective") {
      throw codedError("invalid_multi_view_views", "views must contain only front, side, top and/or perspective.");
    }
    if (!views.includes(view)) {
      views.push(view);
    }
  }
  if (views.length === 0) {
    throw codedError("invalid_multi_view_views", "views must include at least one view.");
  }
  if (views.length > 4) {
    throw codedError("invalid_multi_view_views", "views may include at most four unique views.");
  }
  return views;
}

function validatePlacementChecks(value: unknown): JsonValue {
  if (!Array.isArray(value)) {
    throw codedError("invalid_placement_checks", "checks must be an array of ground_gap, overlap or grid.");
  }
  const checks: string[] = [];
  for (const item of value) {
    if (typeof item !== "string") {
      throw codedError("invalid_placement_checks", "checks must contain only strings.");
    }
    const check = item.trim().toLowerCase();
    if (check !== "ground_gap" && check !== "overlap" && check !== "grid") {
      throw codedError("invalid_placement_checks", "checks must contain only ground_gap, overlap or grid.");
    }
    if (!checks.includes(check)) {
      checks.push(check);
    }
  }
  if (checks.length === 0) {
    throw codedError("invalid_placement_checks", "checks must contain at least one check.");
  }
  return checks;
}

function validateGridOrigin(value: unknown): JsonObject {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw codedError("invalid_grid_origin", "gridOrigin must be an object with finite x/z and optional y numbers.");
  }
  const origin = value as Record<string, unknown>;
  const x = origin.x;
  const y = origin.y ?? 0;
  const z = origin.z;
  if (typeof x !== "number" || !Number.isFinite(x) || typeof y !== "number" || !Number.isFinite(y) || typeof z !== "number" || !Number.isFinite(z)) {
    throw codedError("invalid_grid_origin", "gridOrigin x/y/z values must be finite numbers.");
  }
  return { x, y, z };
}

function validateGridAxes(value: unknown): JsonValue {
  if (!Array.isArray(value)) {
    throw codedError("invalid_grid_axes", "axes must be an array containing x, y and/or z.");
  }
  const axes: string[] = [];
  for (const item of value) {
    if (typeof item !== "string") {
      throw codedError("invalid_grid_axes", "axes must contain only strings.");
    }
    const axis = item.trim().toLowerCase();
    if (axis !== "x" && axis !== "y" && axis !== "z") {
      throw codedError("invalid_grid_axes", "axes must contain only x, y and/or z.");
    }
    if (!axes.includes(axis)) {
      axes.push(axis);
    }
  }
  if (axes.length === 0) {
    throw codedError("invalid_grid_axes", "axes must contain at least one axis.");
  }
  return axes;
}

function validateNodeClassName(value: string): string {
  const className = value.trim();
  if (!className || className.length > 96 || /[\r\n/\\]/.test(className)) {
    throw codedError("invalid_node_class", "className is required and must be a simple Godot class name.");
  }
  return className;
}

function validateResourceClassName(value: string): string {
  const className = value.trim();
  if (!className || className.length > 96 || /[\r\n/\\]/.test(className)) {
    throw codedError("invalid_resource_class", "resourceClass is required and must be a simple Godot Resource class name.");
  }
  return className;
}

function validateMaterialSlotKind(value: string): "canvas_item_material" | "geometry_material_override" | "mesh_surface" {
  const slotKind = value.trim();
  if (slotKind === "canvas_item_material" || slotKind === "geometry_material_override" || slotKind === "mesh_surface") {
    return slotKind;
  }
  throw codedError("invalid_material_slot", "slotKind must be canvas_item_material, geometry_material_override or mesh_surface.");
}

function validateSurfaceIndex(value: unknown): number {
  if (value === undefined || value === null || value === "") {
    throw codedError("invalid_surface_index", "surfaceIndex is required for mesh_surface shader parameter edits.");
  }
  return boundedInteger(value, 0, 0, 1024, "invalid_surface_index");
}

function validateShaderParameterName(value: string): string {
  const parameter = value.trim();
  if (!parameter || parameter.length > 160 || /[\r\n/\\]/.test(parameter)) {
    throw codedError("invalid_shader_parameter", "parameter is required and must not contain path separators or newlines.");
  }
  return parameter;
}

function validateEnvironmentPropertyName(value: string): string {
  const property = value.trim();
  if (!property || property.length > 160 || /[\r\n/\\]/.test(property)) {
    throw codedError("invalid_environment_property", "property is required and must be a simple Environment property name.");
  }
  const allowed = new Set([
    "background_mode",
    "background_color",
    "background_energy_multiplier",
    "sky_custom_fov",
    "ambient_light_source",
    "ambient_light_color",
    "ambient_light_energy",
    "reflected_light_source",
    "tonemap_mode",
    "tonemap_exposure",
    "tonemap_white",
    "glow_enabled",
    "glow_intensity",
    "glow_strength",
    "glow_bloom",
    "fog_enabled",
    "fog_light_color",
    "fog_density",
    "fog_height",
    "fog_height_density",
    "volumetric_fog_enabled",
    "volumetric_fog_density",
    "volumetric_fog_albedo",
    "ssao_enabled",
    "ssao_radius",
    "ssao_intensity",
    "ssil_enabled",
    "sdfgi_enabled",
    "adjustment_enabled",
    "adjustment_brightness",
    "adjustment_contrast",
    "adjustment_saturation",
  ]);
  if (!allowed.has(property)) {
    throw codedError("unsupported_environment_property", "property is not editable through godot.set_environment_property V1.");
  }
  return property;
}

function validateParticleEffectKind(value: unknown): "gpu_particles_3d" {
  const kind = stringOrDefault(value, "gpu_particles_3d").trim().toLowerCase();
  if (kind !== "gpu_particles_3d") {
    throw codedError("unsupported_particle_effect_kind", "kind must be gpu_particles_3d for create_particle_effect V1.");
  }
  return "gpu_particles_3d";
}

function validateParticleDrawMesh(value: unknown): "quad" | "none" {
  const drawMesh = stringOrDefault(value, "quad").trim().toLowerCase();
  if (drawMesh === "quad" || drawMesh === "none") {
    return drawMesh;
  }
  throw codedError("unsupported_particle_draw_mesh", "drawMesh must be quad or none.");
}

function validateParticleDrawMeshForEdit(value: unknown): "quad" | "none" | "unchanged" {
  const drawMesh = stringOrDefault(value, "unchanged").trim().toLowerCase();
  if (drawMesh === "quad" || drawMesh === "none" || drawMesh === "unchanged") {
    return drawMesh;
  }
  throw codedError("unsupported_particle_draw_mesh", "drawMesh must be quad, none or unchanged.");
}

function validateOptionalShaderParameterMap(value: unknown): JsonObject {
  if (value === undefined || value === null) {
    return {};
  }
  if (!isJsonObjectLike(value)) {
    throw codedError("invalid_shader_parameters", "parameters must be an object keyed by shader uniform name.");
  }
  const entries = Object.entries(value);
  if (entries.length > 20) {
    throw codedError("too_many_shader_parameters", "create_shader_material_for_node supports at most 20 initial parameters.");
  }
  const parameters: JsonObject = {};
  for (const [key, item] of entries) {
    parameters[validateShaderParameterName(key)] = validateJsonValue(item, "invalid_shader_parameter_value", `parameters.${key}`);
  }
  return parameters;
}

function validateNodeName(value: string): string {
  const nodeName = value.trim();
  if (!nodeName || nodeName.length > 96 || /[\r\n/\\]/.test(nodeName)) {
    throw codedError("invalid_node_name", "Node name is required and must not contain path separators.");
  }
  return nodeName;
}

function optionalNodeName(value: unknown): string {
  if (value === undefined || value === null || value === "") {
    return "";
  }
  return validateNodeName(stringOrDefault(value, ""));
}

function validateIdentifierName(value: string, kind: "signal" | "method"): string {
  const name = value.trim();
  if (!name || name.length > 160 || /[\r\n/\\]/.test(name)) {
    throw codedError(`invalid_${kind}_name`, `${kind} name is required and must be a simple Godot identifier/pathless name.`);
  }
  return name;
}

function optionalIndex(value: unknown): number {
  if (value === undefined || value === null || value === "") {
    return -1;
  }
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw codedError("invalid_child_index", "index must be a finite number when provided.");
  }
  return Math.floor(value);
}

function optionalFlags(value: unknown): number {
  if (value === undefined || value === null || value === "") {
    return 0;
  }
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw codedError("invalid_signal_flags", "flags must be a finite number when provided.");
  }
  const flags = Math.floor(value);
  if (flags < 0 || flags > 65_535) {
    throw codedError("invalid_signal_flags", "flags must be between 0 and 65535.");
  }
  return flags;
}

function optionalNumber(value: unknown, fallback: number): number {
  if (value === undefined || value === null || value === "") {
    return fallback;
  }
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw codedError("invalid_number", "Expected a finite number.");
  }
  return value;
}

function boundedNumber(value: unknown, fallback: number, min: number, max: number, code: string): number {
  if (value === undefined || value === null || value === "") {
    return fallback;
  }
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw codedError(code, `Expected a finite number between ${min} and ${max}.`);
  }
  if (value < min || value > max) {
    throw codedError(code, `Expected a value between ${min} and ${max}.`);
  }
  return value;
}

function boundedInteger(value: unknown, fallback: number, min: number, max: number, code: string): number {
  if (value === undefined || value === null || value === "") {
    return fallback;
  }
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw codedError(code, `Expected a finite number between ${min} and ${max}.`);
  }
  const integer = Math.floor(value);
  if (integer < min || integer > max) {
    throw codedError(code, `Expected a value between ${min} and ${max}.`);
  }
  return integer;
}

function copyBoundedNumberField(
  source: JsonObject,
  target: JsonObject,
  sourceField: string,
  targetField: string,
  min: number,
  max: number,
  code: string,
): void {
  if (source[sourceField] === undefined) {
    return;
  }
  target[targetField] = boundedNumber(source[sourceField], 0, min, max, code);
}

function copyBoundedIntegerField(
  source: JsonObject,
  target: JsonObject,
  sourceField: string,
  targetField: string,
  min: number,
  max: number,
  code: string,
): void {
  if (source[sourceField] === undefined) {
    return;
  }
  target[targetField] = boundedInteger(source[sourceField], 0, min, max, code);
}

function copyBooleanField(source: JsonObject, target: JsonObject, sourceField: string, targetField: string, code: string): void {
  const value = source[sourceField];
  if (value === undefined) {
    return;
  }
  if (typeof value !== "boolean") {
    throw codedError(code, `${sourceField} must be a boolean when provided.`);
  }
  target[targetField] = value;
}

function validateAnimationName(value: string): string {
  const name = value.trim();
  if (!name || name.length > 120 || /[\r\n/\\]/.test(name)) {
    throw codedError("invalid_animation_name", "animationName is required and must be a simple animation key without path separators.");
  }
  return name;
}

function optionalAnimationName(value: unknown): string {
  if (value === undefined || value === null || value === "") {
    return "";
  }
  return validateAnimationName(stringOrDefault(value, ""));
}

function optionalAnimationLibraryKey(value: unknown): string {
  if (value === undefined || value === null || value === "") {
    return "";
  }
  const key = stringOrDefault(value, "").trim();
  if (key.length > 120 || /[\r\n\\]/.test(key) || key.includes("/")) {
    throw codedError("invalid_animation_library", "libraryKey must be simple and must not contain slashes or newlines.");
  }
  return key;
}

function optionalAnimationPreviewMode(value: unknown): string {
  if (value === undefined || value === null || value === "") {
    return "seek";
  }
  if (value === "seek" || value === "play" || value === "pause") {
    return value;
  }
  throw codedError("invalid_animation_preview_mode", "mode must be seek, play or pause.");
}

function validateAnimationTrackPath(value: unknown): string {
  if (typeof value !== "string") {
    throw codedError("invalid_animation_track_path", "Track path must be a string.");
  }
  const trackPath = value.trim();
  if (!trackPath || trackPath.length > 400 || trackPath.includes("\n") || trackPath.includes("\r")) {
    throw codedError("invalid_animation_track_path", "Track path is required and must not contain newlines.");
  }
  if (trackPath.startsWith("res://") || trackPath.includes("..") || !trackPath.includes(":")) {
    throw codedError("invalid_animation_track_path", "Track path must be scene-local and include a property separator, e.g. MeshInstance3D:position.");
  }
  return trackPath;
}

function validateAnimationValueType(value: unknown): string {
  const valueType = stringOrDefault(value, "variant").trim().toLowerCase();
  const allowed = new Set(["variant", "bool", "int", "float", "string", "vector2", "vector3", "color"]);
  if (!allowed.has(valueType)) {
    throw codedError("unsupported_animation_key_value_type", "Unsupported animation valueType.");
  }
  return valueType;
}

function validateAnimationTracks(value: unknown): JsonObject[] {
  if (value === undefined || value === null) {
    return [];
  }
  if (!Array.isArray(value)) {
    throw codedError("invalid_animation_tracks", "tracks must be an array.");
  }
  if (value.length > 12) {
    throw codedError("too_many_animation_tracks", "create_animation_clip supports at most 12 tracks.");
  }
  return value.map((item) => {
    if (!isJsonObjectLike(item)) {
      throw codedError("invalid_animation_track", "Each animation track must be an object.");
    }
    const trackType = stringOrDefault(item.type, "value").trim().toLowerCase();
    if (trackType !== "value") {
      throw codedError("unsupported_animation_track_type", "V1 create_animation_clip supports only value tracks.");
    }
    if (!Array.isArray(item.keys) || item.keys.length === 0) {
      throw codedError("invalid_animation_keys", "Each animation track requires at least one key.");
    }
    if (item.keys.length > 16) {
      throw codedError("too_many_animation_keys", "Each animation track supports at most 16 keys.");
    }
    const valueType = validateAnimationValueType(item.valueType ?? item.value_type);
    return {
      type: "value",
      path: validateAnimationTrackPath(item.path),
      value_type: valueType,
      interpolation_type: boundedInteger(item.interpolationType ?? item.interpolation_type, 1, 0, 2, "invalid_animation_interpolation"),
      keys: item.keys.map((key) => {
        if (!isJsonObjectLike(key)) {
          throw codedError("invalid_animation_key", "Each animation key must be an object.");
        }
        if (!isJsonValue(key.value)) {
          throw codedError("invalid_animation_key_value", "Animation key value must be JSON-serializable.");
        }
        return {
          time: boundedNumber(key.time, 0, 0, 3600, "invalid_animation_key_time"),
          transition: boundedNumber(key.transition, 1, -1024, 1024, "invalid_animation_key_transition"),
          value: key.value,
        };
      }),
    };
  });
}

function validatePropertyName(value: unknown): string {
  if (typeof value !== "string") {
    throw codedError("invalid_property", "Property name must be a string.");
  }
  const property = value.trim();
  if (!property || property.length > 160 || property.includes("\n") || property.includes("\r")) {
    throw codedError("invalid_property", "Property name is empty, too long, or contains a newline.");
  }
  if (property.startsWith("_") || property === "script" || property === "owner") {
    throw codedError("unsupported_property", `Property is not editable through editor control: ${property}.`);
  }
  return property;
}

function validatePropertyChanges(value: unknown): JsonObject[] {
  if (!Array.isArray(value)) {
    throw codedError("invalid_property_changes", "changes must be an array.");
  }
  if (value.length === 0) {
    throw codedError("invalid_property_changes", "changes cannot be empty.");
  }
  if (value.length > 20) {
    throw codedError("too_many_property_changes", "set_node_properties supports at most 20 changes.");
  }
  return value.map((item) => {
    if (!isJsonObjectLike(item)) {
      throw codedError("invalid_property_change", "Each property change must be an object.");
    }
    if (!isJsonValue(item.value)) {
      throw codedError("invalid_property_value", "Property value must be JSON-serializable.");
    }
    return {
      property: validatePropertyName(item.property),
      value: item.value,
    };
  });
}

function validateOptionalPropertyChanges(value: unknown): JsonObject[] {
  if (value === undefined || value === null) {
    return [];
  }
  return validatePropertyChanges(value);
}

function validateJsonValue(value: unknown, code: string, label: string): JsonValue {
  if (!isJsonValue(value)) {
    throw codedError(code, `${label} must be JSON-serializable.`);
  }
  return value;
}

function validateEditorBatch(value: unknown): JsonObject[] {
  if (!Array.isArray(value)) {
    throw codedError("invalid_batch", "actions must be an array.");
  }
  if (value.length === 0) {
    throw codedError("invalid_batch", "actions cannot be empty.");
  }
  if (value.length > 12) {
    throw codedError("too_many_batch_actions", "editor_batch supports at most 12 actions.");
  }
  return value.map((item) => {
    if (!isJsonObjectLike(item)) {
      throw codedError("invalid_batch_action", "Each batch action must be an object.");
    }
    if (typeof item.action !== "string" || item.action.trim() === "") {
      throw codedError("invalid_batch_action", "Each batch action requires an action string.");
    }
    if (item.action === "editor_batch") {
      throw codedError("nested_batch_rejected", "Nested editor_batch actions are not supported.");
    }
    const params = item.params === undefined ? {} : item.params;
    if (!isJsonObjectLike(params)) {
      throw codedError("invalid_batch_action", "Batch action params must be an object when provided.");
    }
    return {
      action: item.action.trim(),
      params,
    };
  });
}

function playtestInputParams(args: JsonObject): JsonObject {
  const params: JsonObject = {};
  if (args.steps !== undefined) {
    params.steps = validatePlaytestInputSteps(args.steps);
  } else {
    params.steps = [validatePlaytestInputStep(args)];
  }
  if (typeof args.reason === "string" && args.reason.trim() !== "") {
    params.reason = args.reason.trim().slice(0, 160);
  }
  return params;
}

function validatePlaytestInputSteps(value: unknown): JsonObject[] {
  if (!Array.isArray(value)) {
    throw codedError("invalid_playtest_input_steps", "steps must be an array.");
  }
  if (value.length === 0) {
    throw codedError("invalid_playtest_input_steps", "steps must contain at least one item.");
  }
  if (value.length > 16) {
    throw codedError("too_many_playtest_input_steps", "godot.playtest_input supports at most 16 steps.");
  }
  return value.map((item) => validatePlaytestInputStep(item));
}

function validatePlaytestInputStep(value: unknown): JsonObject {
  if (!isJsonObjectLike(value)) {
    throw codedError("invalid_playtest_input_step", "Each playtest input step must be an object.");
  }
  const type = stringOrDefault(value.type, "").trim();
  if (type !== "action_press" && type !== "action_release" && type !== "axis" && type !== "key" && type !== "mouse_button") {
    throw codedError("unsupported_playtest_input_step", "type must be action_press, action_release, axis, key or mouse_button.");
  }
  const step: JsonObject = { type };
  if (type === "action_press" || type === "action_release") {
    step.action = validateInputActionName(value.action);
    if (type === "action_press") {
      step.strength = boundedNumber(value.strength, 1, 0, 1, "invalid_playtest_strength");
    }
  } else if (type === "axis") {
    step.negative_action = validateInputActionName(value.negativeAction ?? value.negative_action);
    step.positive_action = validateInputActionName(value.positiveAction ?? value.positive_action);
    step.value = boundedNumber(value.value, 0, -1, 1, "invalid_playtest_axis_value");
  } else if (type === "key") {
    step.keycode = boundedInteger(value.keycode, 0, 1, 2_147_483_647, "invalid_playtest_keycode");
    step.physical_keycode = boundedInteger(value.physicalKeycode ?? value.physical_keycode ?? value.keycode, step.keycode as number, 1, 2_147_483_647, "invalid_playtest_keycode");
    step.pressed = value.pressed !== false;
  } else if (type === "mouse_button") {
    step.button_index = boundedInteger(value.buttonIndex ?? value.button_index, 0, 1, 16, "invalid_playtest_mouse_button");
    step.pressed = value.pressed !== false;
    if (value.position !== undefined) {
      step.position = validatePlaytestPosition(value.position);
    }
  }
  return step;
}

function validatePlaytestScenarioSteps(value: unknown): JsonObject[] {
  if (!Array.isArray(value)) {
    throw codedError("invalid_playtest_scenario_steps", "steps must be an array.");
  }
  if (value.length === 0) {
    throw codedError("invalid_playtest_scenario_steps", "steps must contain at least one item.");
  }
  if (value.length > 32) {
    throw codedError("too_many_playtest_scenario_steps", "godot.run_playtest_scenario supports at most 32 steps.");
  }
  return value.map((item) => validatePlaytestScenarioStep(item));
}

function validatePlaytestScenarioStep(value: unknown): JsonObject {
  if (!isJsonObjectLike(value)) {
    throw codedError("invalid_playtest_scenario_step", "Each playtest scenario step must be an object.");
  }
  const type = stringOrDefault(value.type, "").trim();
  if (type === "press_action") {
    return {
      type,
      action: validateInputActionName(value.action),
      strength: boundedNumber(value.strength, 1, 0, 1, "invalid_playtest_scenario_strength"),
    };
  }
  if (type === "release_action") {
    return {
      type,
      action: validateInputActionName(value.action),
    };
  }
  if (type === "wait_seconds") {
    return {
      type,
      seconds: boundedNumber(value.seconds, 0, 0, 10, "invalid_playtest_scenario_wait_seconds"),
    };
  }
  if (type === "wait_for_event") {
    return {
      type,
      event: validatePlaytestScenarioEventName(value.event ?? value.eventName),
      ...(typeof value.action === "string" && value.action.trim() !== "" ? { action: validateInputActionName(value.action) } : {}),
      timeout_seconds: boundedNumber(value.timeoutSeconds ?? value.timeout_seconds, 5, 0.05, 30, "invalid_playtest_scenario_event_timeout"),
    };
  }
  if (type === "capture") {
    const step: JsonObject = {
      type,
      source: validatePlaytestScenarioCaptureSource(value.source),
    };
    if (step.source === "timeline_screenshot") {
      step.frame_count = boundedInteger(value.frameCount ?? value.frame_count, 3, 2, 12, "invalid_playtest_timeline_frame_count");
      step.interval_ms = boundedInteger(value.intervalMs ?? value.interval_ms, 250, 50, 5_000, "invalid_playtest_timeline_interval_ms");
    }
    return step;
  }
  if (type === "assert") {
    return validatePlaytestScenarioAssertStep(value);
  }
  throw codedError("unsupported_playtest_scenario_step", "type must be press_action, release_action, wait_seconds, wait_for_event, capture or assert.");
}

function validatePlaytestScenarioAssertStep(value: JsonObject): JsonObject {
  const assertion = validatePlaytestScenarioAssertionName(value.assertion);
  const step: JsonObject = { type: "assert", assertion };
  if (assertion === "runtime_event_present") {
    step.event_type = validatePlaytestScenarioEventName(value.event_type ?? value.event ?? value.eventName);
    if (typeof value.action === "string" && value.action.trim() !== "") {
      step.action = validateInputActionName(value.action);
    }
    return step;
  }
  if (assertion === "runtime_scene_changed") {
    if (typeof value.scenePath === "string" || typeof value.scene_path === "string") {
      step.scene_path = validateRuntimeScenePathString(value.scenePath ?? value.scene_path);
    }
    return step;
  }
  if (assertion === "runtime_state_active_scene") {
    if (typeof value.scenePath === "string" || typeof value.scene_path === "string") {
      step.scene_path = validateRuntimeScenePathString(value.scenePath ?? value.scene_path);
    }
    if (typeof value.nodePath === "string" || typeof value.node_path === "string") {
      step.node_path = validateNodePath(stringOrDefault(value.nodePath ?? value.node_path, ""));
    }
    if (typeof value.sceneName === "string" || typeof value.scene_name === "string") {
      step.scene_name = validateSimplePlaytestName(value.sceneName ?? value.scene_name, "invalid_playtest_scene_name", 128);
    }
    return step;
  }
  if (assertion === "runtime_state_node_exists") {
    const hasNodePath = typeof value.nodePath === "string" || typeof value.node_path === "string";
    const hasNodeName = typeof value.nodeName === "string" || typeof value.node_name === "string";
    const hasNodeType = typeof value.nodeType === "string" || typeof value.node_type === "string";
    if (!hasNodePath && !hasNodeName && !hasNodeType) {
      throw codedError("invalid_playtest_assertion_target", "runtime_state_node_exists requires nodePath, nodeName or nodeType.");
    }
    if (hasNodePath) {
      step.node_path = validateNodePath(stringOrDefault(value.nodePath ?? value.node_path, ""));
    }
    if (hasNodeName) {
      step.node_name = validateSimplePlaytestName(value.nodeName ?? value.node_name, "invalid_playtest_node_name", 128);
    }
    if (hasNodeType) {
      step.node_type = validateNodeClassName(stringOrDefault(value.nodeType ?? value.node_type, ""));
    }
    return step;
  }
  if (assertion === "runtime_state_position_delta" || assertion === "runtime_state_rotation_delta") {
    step.node_path = validateNodePath(stringOrDefault(value.nodePath ?? value.node_path, ""));
    if (typeof value.axis === "string" && value.axis.trim() !== "") {
      step.axis = validatePlaytestAxis(value.axis);
    }
    step.min_delta = boundedNumber(value.minDelta ?? value.min_delta, 0, 0, 1_000_000, "invalid_playtest_min_delta");
    if (value.maxDelta !== undefined || value.max_delta !== undefined) {
      step.max_delta = boundedNumber(value.maxDelta ?? value.max_delta, 0, 0, 1_000_000, "invalid_playtest_max_delta");
    }
    step.epsilon = boundedNumber(value.epsilon, 0.0001, 0, 1000, "invalid_playtest_epsilon");
    return step;
  }
  throw codedError("unsupported_playtest_scenario_assertion", `Unsupported playtest scenario assertion: ${assertion}.`);
}

function validatePlaytestScenarioCaptureSource(value: unknown): string {
  const source = stringOrDefault(value, "runtime_state").trim();
  if (
    source === "runtime_state"
    || source === "runtime_events"
    || source === "fixture_diagnostics"
    || source === "viewport_screenshot"
    || source === "timeline_screenshot"
  ) {
    return source;
  }
  throw codedError("unsupported_playtest_capture_source", "capture source must be runtime_state, runtime_events, fixture_diagnostics, viewport_screenshot or timeline_screenshot.");
}

function validatePlaytestScenarioAssertionName(value: unknown): string {
  const assertion = stringOrDefault(value, "").trim();
  const allowed = new Set([
    "runtime_event_present",
    "runtime_scene_changed",
    "runtime_state_active_scene",
    "runtime_state_node_exists",
    "runtime_state_position_delta",
    "runtime_state_rotation_delta",
  ]);
  if (!allowed.has(assertion)) {
    throw codedError("unsupported_playtest_scenario_assertion", "Unsupported playtest scenario assertion.");
  }
  return assertion;
}

function validateRuntimeScenePathString(value: unknown): string {
  const scenePath = stringOrDefault(value, "").trim();
  if (!scenePath.startsWith("res://") || (!scenePath.endsWith(".tscn") && !scenePath.endsWith(".scn")) || scenePath.includes("..") || /[\r\n\\]/.test(scenePath)) {
    throw codedError("invalid_playtest_scene_path", "scene path must be a project-local res:// .tscn or .scn path.");
  }
  return scenePath;
}

function validateSimplePlaytestName(value: unknown, code: string, maxLength: number): string {
  const name = stringOrDefault(value, "").trim();
  if (!name || name.length > maxLength || /[\r\n/\\]/.test(name) || name.includes("..")) {
    throw codedError(code, "Playtest name is required and must not contain path separators or newlines.");
  }
  return name;
}

function validatePlaytestAxis(value: unknown): string {
  const axis = stringOrDefault(value, "").trim().toLowerCase();
  if (axis === "x" || axis === "y" || axis === "z") {
    return axis;
  }
  throw codedError("invalid_playtest_axis", "axis must be x, y or z.");
}

function validateInputActionName(value: unknown): string {
  if (typeof value !== "string") {
    throw codedError("invalid_input_action", "Input action name must be a string.");
  }
  const action = value.trim();
  if (!action || action.length > 128 || /[\r\n/\\]/.test(action)) {
    throw codedError("invalid_input_action", "Input action name is required and must not contain path separators or newlines.");
  }
  return action;
}

function validatePlaytestScenarioEventName(value: unknown): string {
  if (typeof value !== "string") {
    throw codedError("invalid_playtest_scenario_event", "Event name must be a string.");
  }
  const event = value.trim();
  if (!event || event.length > 160 || /[\r\n/\\]/.test(event)) {
    throw codedError("invalid_playtest_scenario_event", "Event name is required and must not contain path separators or newlines.");
  }
  return event;
}

function validatePlaytestPosition(value: unknown): JsonObject {
  if (!isJsonObjectLike(value)) {
    throw codedError("invalid_playtest_position", "position must be an object with finite x/y numbers.");
  }
  const x = value.x;
  const y = value.y;
  if (typeof x !== "number" || !Number.isFinite(x) || typeof y !== "number" || !Number.isFinite(y)) {
    throw codedError("invalid_playtest_position", "position x/y values must be finite numbers.");
  }
  return { x, y };
}

function copyJsonField(source: JsonObject, target: JsonObject, field: string): void {
  const value = source[field];
  if (value !== undefined) {
    if (!isJsonValue(value)) {
      throw codedError("invalid_json_value", `${field} must be JSON-serializable.`);
    }
    target[field] = value;
  }
}

function isJsonObjectLike(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isJsonValue(value: unknown): value is JsonValue {
  if (
    value === null ||
    typeof value === "string" ||
    typeof value === "number" ||
    typeof value === "boolean"
  ) {
    return typeof value !== "number" || Number.isFinite(value);
  }
  if (Array.isArray(value)) {
    return value.every((item) => isJsonValue(item));
  }
  if (isJsonObjectLike(value)) {
    return Object.values(value).every((item) => item === undefined || isJsonValue(item));
  }
  return false;
}

function codedError(code: string, message: string, details: JsonObject = {}): Error & { code: string; details: JsonObject } {
  const error = new Error(message) as Error & { code: string; details: JsonObject };
  error.code = code;
  error.details = details;
  return error;
}
