import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { createReadStream } from "node:fs";
import fs from "node:fs/promises";
import path from "node:path";
import { createInterface } from "node:readline";
import { promisify } from "node:util";

import { isInsidePath } from "./config.js";
import { isJsonObject } from "./bridge.js";
import type { JsonObject, JsonValue, ToolEnvelope } from "./types.js";

const execFileAsync = promisify(execFile);

const MAX_INDEX_FILES = 20_000;
const MAX_INDEX_SKIPS = 100;
const DEFAULT_LIST_LIMIT = 100;
const MAX_LIST_LIMIT = 500;
const DEFAULT_SEARCH_LIMIT = 50;
const MAX_SEARCH_LIMIT = 200;
const DEFAULT_READ_LINES = 200;
const MAX_READ_LINES = 1_000;
const DEFAULT_READ_BYTES = 64_000;
const MAX_READ_BYTES = 256_000;
const MAX_TEXT_SEARCH_BYTES = 1_000_000;
const MAX_TEXT_SHA_BYTES = 64_000;
const MAX_SCENE_PARSE_BYTES = 512_000;
const MAX_SCENE_NODES = 1_000;
const MAX_AGENTS_PREVIEW_BYTES = 12_000;
const MAX_AGENTS_PREVIEW_LINES = 200;
const MAX_CURRENT_SOURCE_FILES = 5;
const MAX_PROJECT_MAP_SCENES = 200;
const MAX_PROJECT_MAP_SCRIPTS = 250;
const MAX_PROJECT_MAP_RESOURCES = 250;
const MAX_PROJECT_MAP_IMPORTS = 150;
const MAX_PROJECT_MAP_GROUPS = 120;
const MAX_PROJECT_MAP_SIGNALS = 200;
const MAX_PROJECT_MAP_SCRIPT_BYTES = 128_000;
const MAX_SCENE_GRAPH_SCENES = 250;
const MAX_SCENE_GRAPH_EDGES = 2_500;
const MAX_SCENE_GRAPH_MISSING = 250;
const MAX_SCENE_GRAPH_CYCLES = 25;
const MAX_SCENE_GRAPH_SUB_RESOURCES_PER_SCENE = 200;
const MAX_SCENE_GRAPH_DEPTH = 16;
const MAX_PROJECT_SCRIPT_MAP_SCRIPTS = 300;
const MAX_PROJECT_SCRIPT_MAP_SCRIPTS_HARD = 500;
const MAX_PROJECT_SCRIPT_MAP_SCENES = 250;
const MAX_PROJECT_SCRIPT_MAP_CLASSES = 300;
const MAX_PROJECT_SCRIPT_MAP_USAGE = 500;
const MAX_PROJECT_SCRIPT_MAP_DOCS = 8;
const MAX_PROJECT_SCRIPT_MAP_DOC_PREVIEW_LINES = 80;
const MAX_PROJECT_SCRIPT_MAP_DOC_PREVIEW_BYTES = 6_000;
const TEXT_PROBE_BYTES = 8_192;

const BLOCKED_SEGMENTS = new Set([
  ".godot",
  ".import",
  ".git",
  ".ziva",
  "node_modules",
  "generated",
  "build",
  "dist",
  "export",
  "exports",
]);

const BLOCKED_PREFIXES = [
  "addons/godot_codex_bridge",
  "addons/ziva_agent",
];

const BLOCKED_GLOBS = [
  "!.godot/**",
  "!.import/**",
  "!.git/**",
  "!.ziva/**",
  "!node_modules/**",
  "!generated/**",
  "!build/**",
  "!dist/**",
  "!export/**",
  "!exports/**",
  "!addons/godot_codex_bridge/**",
  "!addons/ziva_agent/**",
];

const TEXT_EXTENSIONS = new Set([
  ".cfg",
  ".cs",
  ".gd",
  ".gdshader",
  ".godot",
  ".import",
  ".ini",
  ".json",
  ".md",
  ".shader",
  ".tres",
  ".tscn",
  ".txt",
  ".xml",
  ".yaml",
  ".yml",
]);

const BINARY_EXTENSIONS = new Set([
  ".7z",
  ".a",
  ".apk",
  ".bin",
  ".bmp",
  ".dll",
  ".dylib",
  ".exe",
  ".exr",
  ".fbx",
  ".glb",
  ".gltf",
  ".hdr",
  ".ico",
  ".jar",
  ".jpg",
  ".jpeg",
  ".mesh",
  ".mp3",
  ".mp4",
  ".ogg",
  ".otf",
  ".pak",
  ".pck",
  ".png",
  ".res",
  ".scn",
  ".so",
  ".ttf",
  ".wav",
  ".webp",
  ".zip",
]);

interface IndexedFile {
  relativePath: string;
  resPath: string;
  absolutePath: string;
  extension: string;
  kind: string;
  byteSize: number;
  mtimeMs: number;
  mtime: string;
  isText: boolean;
  isBinary: boolean;
  textEncoding: string | null;
  binaryReason: string | null;
}

interface ProjectIndex {
  files: IndexedFile[];
  rootPath: string;
  truncated: boolean;
  scannedFiles: number;
  skipped: JsonObject[];
}

interface ResolvedProjectPath {
  relativePath: string;
  absolutePath: string;
  resPath: string;
}

export class ProjectAwarenessError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly details: JsonObject = {},
  ) {
    super(message);
    this.name = "ProjectAwarenessError";
  }
}

export interface SnapshotSource {
  snapshotEnvelope?: ToolEnvelope;
}

export async function getProjectOverview(
  projectRoot: string,
  source: SnapshotSource = {},
): Promise<ToolEnvelope> {
  try {
    const projectFile = path.join(projectRoot, "project.godot");
    const projectText = await readTextIfExists(projectFile);
    const projectConfig = parseProjectConfig(projectText);
    const snapshot = snapshotFromEnvelope(source.snapshotEnvelope);
    const index = await buildProjectIndex(projectRoot);
    const counts = summarizeFiles(index.files);
    const agents = await collectAgentsFiles(projectRoot);
    const mainScene = projectConfig.mainScene ?? stringAt(snapshot, ["project", "main_scene"]);
    const currentScene = objectAt(snapshot, ["current_scene"]);

    return {
      status: "ok",
      awareness_version: "godot-codex-bridge/project-awareness-v1",
      project_root: projectRoot,
      project_file: projectFile,
      project_file_exists: projectText !== undefined,
      project_name: projectConfig.name ?? stringAt(snapshot, ["project", "name"]),
      main_scene: mainScene ?? null,
      main_scene_exists: mainScene ? await safePathExists(projectRoot, mainScene) : null,
      current_scene: currentScene,
      context_snapshot_available: snapshot !== null,
      selected_node_count: arrayAt(snapshot, ["selected_nodes"]).length,
      file_summary: counts,
      scene_candidates: index.files
        .filter((file) => file.kind === "scene")
        .slice(0, 25)
        .map(fileMetadata),
      script_candidates: index.files
        .filter((file) => file.kind === "script")
        .slice(0, 25)
        .map(fileMetadata),
      top_level_entries: topLevelEntries(index.files),
      agents: {
        root_agents_present: agents.rootAgentsPresent,
        files_count: agents.files.length,
        files: agents.files.map((file) => agentsMetadata(file)),
      },
      index_truncated: index.truncated,
      skipped: index.skipped,
      excludes: blockedPathPolicy(),
    };
  } catch (error) {
    return projectAwarenessErrorEnvelope(error);
  }
}

export async function getProjectMap(
  projectRoot: string,
  source: SnapshotSource = {},
): Promise<ToolEnvelope> {
  try {
    const projectFile = path.join(projectRoot, "project.godot");
    const projectText = await readTextIfExists(projectFile);
    const projectConfig = parseProjectConfig(projectText);
    const snapshot = snapshotFromEnvelope(source.snapshotEnvelope);
    const index = await buildProjectIndex(projectRoot);
    const scenes = index.files.filter((file) => file.kind === "scene");
    const scripts = index.files.filter((file) => file.kind === "script");
    const resources = index.files.filter((file) =>
      file.extension !== ".import" && ["resource", "image", "audio", "shader", "unknown"].includes(file.kind)
    );
    const sceneEntries = await Promise.all(scenes.slice(0, MAX_PROJECT_MAP_SCENES).map((file) => sceneMapEntry(projectRoot, file)));
    const scriptEntries = await Promise.all(scripts.slice(0, MAX_PROJECT_MAP_SCRIPTS).map(scriptMapEntry));
    const groups = collectProjectGroups(sceneEntries).slice(0, MAX_PROJECT_MAP_GROUPS);
    const signals = collectProjectSignals(scriptEntries).slice(0, MAX_PROJECT_MAP_SIGNALS);
    const projectAutoloads = projectConfig.autoloads;
    const snapshotAutoloads = arrayAt(snapshot, ["gameplay_context", "autoloads"]);
    const projectInputActions = projectConfig.inputActions;
    const snapshotInputActions = arrayAt(snapshot, ["gameplay_context", "input_actions"]);

    return {
      status: "ok",
      awareness_version: "godot-codex-bridge/project-awareness-v1",
      project_map_version: "godot-codex-bridge/project-map-v1",
      generated_at: new Date().toISOString(),
      project_root: projectRoot,
      project_file: projectFile,
      project_file_exists: projectText !== undefined,
      project_name: projectConfig.name ?? stringAt(snapshot, ["project", "name"]),
      main_scene: projectConfig.mainScene ?? stringAt(snapshot, ["project", "main_scene"]),
      current_scene: objectAt(snapshot, ["current_scene"]),
      context_snapshot_available: snapshot !== null,
      index: {
        scanned_files: index.scannedFiles,
        indexed_files: index.files.length,
        truncated: index.truncated,
        skipped: index.skipped,
        file_summary: summarizeFiles(index.files),
        top_level_entries: topLevelEntries(index.files),
      },
      scenes: {
        total: scenes.length,
        returned: sceneEntries.length,
        truncated: scenes.length > sceneEntries.length,
        items: sceneEntries,
      },
      scripts: {
        total: scripts.length,
        returned: scriptEntries.length,
        truncated: scripts.length > scriptEntries.length,
        items: scriptEntries,
      },
      resources: {
        total: resources.length,
        returned: Math.min(resources.length, MAX_PROJECT_MAP_RESOURCES),
        truncated: resources.length > MAX_PROJECT_MAP_RESOURCES,
        by_kind: summarizeFiles(resources).by_kind,
        items: resources.slice(0, MAX_PROJECT_MAP_RESOURCES).map(fileMetadata),
      },
      imports: {
        source: snapshot ? "context_snapshot" : "unavailable_without_live_snapshot",
        sidecar_content_excluded: true,
        resource_status: objectAt(snapshot, ["resource_status"]),
        items: arrayAt(snapshot, ["resource_status", "resources"]).slice(0, MAX_PROJECT_MAP_IMPORTS),
      },
      autoloads: {
        project: projectAutoloads,
        snapshot: snapshotAutoloads.slice(0, 100),
        merged: mergeNamedObjects(projectAutoloads, snapshotAutoloads, 100),
      },
      input_actions: {
        project: projectInputActions,
        snapshot: snapshotInputActions.slice(0, 100),
        merged: mergeNamedObjects(projectInputActions, snapshotInputActions, 100),
      },
      groups: {
        total: groups.length,
        truncated: collectProjectGroups(sceneEntries).length > groups.length,
        items: groups,
      },
      signals: {
        total: signals.length,
        truncated: collectProjectSignals(scriptEntries).length > signals.length,
        items: signals,
      },
      limits: {
        max_index_files: MAX_INDEX_FILES,
        max_scenes: MAX_PROJECT_MAP_SCENES,
        max_scripts: MAX_PROJECT_MAP_SCRIPTS,
        max_resources: MAX_PROJECT_MAP_RESOURCES,
        max_imports: MAX_PROJECT_MAP_IMPORTS,
        max_groups: MAX_PROJECT_MAP_GROUPS,
        max_signals: MAX_PROJECT_MAP_SIGNALS,
      },
      excludes: blockedPathPolicy(),
    };
  } catch (error) {
    return projectAwarenessErrorEnvelope(error);
  }
}

export async function getProjectSceneGraph(projectRoot: string, options: JsonObject = {}): Promise<ToolEnvelope> {
  try {
    const focusedScene = typeof options.scenePath === "string" && options.scenePath.trim() !== ""
      ? resolveProjectPath(projectRoot, options.scenePath)
      : null;
    const maxDepth = boundedInt(options.maxDepth, 8, 1, MAX_SCENE_GRAPH_DEPTH);
    const includeResources = options.includeResources !== false;
    const includeNodes = options.includeNodes !== false;
    const index = await buildProjectIndex(projectRoot);
    const sceneFiles = focusedScene
      ? index.files.filter((file) => file.relativePath === focusedScene.relativePath)
      : index.files.filter((file) => file.kind === "scene");
    const sceneEntries = await Promise.all(sceneFiles.slice(0, MAX_SCENE_GRAPH_SCENES).map((file) =>
      sceneDependencyEntry(projectRoot, file, { includeResources, includeNodes })
    ));
    const allEdges = sceneEntries.flatMap((scene) => scene.edges);
    const allMissing = sceneEntries.flatMap((scene) => scene.missingResources);
    const diagnostics = sceneEntries.flatMap((entry) =>
      Array.isArray(entry.scene.diagnostics) ? entry.scene.diagnostics as JsonObject[] : []
    ).concat(allMissing);
    const sceneInstanceEdges = allEdges.filter((edge) => edge.kind === "scene_instance");
    const cycles = detectSceneCycles(sceneInstanceEdges);
    const graphNodes = graphNodesFromSceneEntries(sceneEntries, allEdges, allMissing);

    return {
      status: "ok",
      awareness_version: "godot-codex-bridge/project-awareness-v1",
      scene_graph_version: "godot-codex-bridge/project-scene-graph-v1",
      generated_at: new Date().toISOString(),
      project_root: projectRoot,
      scope: {
        mode: focusedScene ? "single_scene" : "project",
        scene_path: focusedScene?.resPath ?? null,
        max_depth: maxDepth,
      },
      index: {
        scanned_files: index.scannedFiles,
        indexed_files: index.files.length,
        truncated: index.truncated,
        skipped: index.skipped,
      },
      scenes: {
        total: focusedScene ? (sceneFiles.length > 0 ? 1 : 0) : sceneFiles.length,
        returned: sceneEntries.length,
        truncated: sceneFiles.length > sceneEntries.length,
        items: sceneEntries.map((entry) => entry.scene),
      },
      graph: {
        nodes: graphNodes,
        edges: allEdges.slice(0, MAX_SCENE_GRAPH_EDGES),
      },
      edges: {
        total: allEdges.length,
        returned: Math.min(allEdges.length, MAX_SCENE_GRAPH_EDGES),
        truncated: allEdges.length > MAX_SCENE_GRAPH_EDGES,
        items: allEdges.slice(0, MAX_SCENE_GRAPH_EDGES),
      },
      missing_resources: {
        total: allMissing.length,
        returned: Math.min(allMissing.length, MAX_SCENE_GRAPH_MISSING),
        truncated: allMissing.length > MAX_SCENE_GRAPH_MISSING,
        items: allMissing.slice(0, MAX_SCENE_GRAPH_MISSING),
      },
      cycles: {
        total: cycles.length,
        returned: Math.min(cycles.length, MAX_SCENE_GRAPH_CYCLES),
        truncated: cycles.length > MAX_SCENE_GRAPH_CYCLES,
        items: cycles.slice(0, MAX_SCENE_GRAPH_CYCLES),
      },
      diagnostics: {
        total: diagnostics.length,
        returned: Math.min(diagnostics.length, MAX_SCENE_GRAPH_MISSING),
        truncated: diagnostics.length > MAX_SCENE_GRAPH_MISSING,
        items: diagnostics.slice(0, MAX_SCENE_GRAPH_MISSING),
      },
      limits: {
        max_scenes: MAX_SCENE_GRAPH_SCENES,
        max_edges: MAX_SCENE_GRAPH_EDGES,
        max_missing_resources: MAX_SCENE_GRAPH_MISSING,
        max_cycles: MAX_SCENE_GRAPH_CYCLES,
        max_scene_parse_bytes: MAX_SCENE_PARSE_BYTES,
        max_depth: MAX_SCENE_GRAPH_DEPTH,
        max_sub_resources_per_scene: MAX_SCENE_GRAPH_SUB_RESOURCES_PER_SCENE,
      },
      index_truncated: index.truncated,
      skipped: index.skipped,
      excludes: blockedPathPolicy(),
    };
  } catch (error) {
    return projectAwarenessErrorEnvelope(error);
  }
}

export async function getProjectScriptMap(projectRoot: string, options: JsonObject = {}): Promise<ToolEnvelope> {
  try {
    const projectFile = path.join(projectRoot, "project.godot");
    const projectText = await readTextIfExists(projectFile);
    const projectConfig = parseProjectConfig(projectText);
    const focusedScript = typeof options.scriptPath === "string" && options.scriptPath.trim() !== ""
      ? resolveProjectPath(projectRoot, options.scriptPath)
      : null;
    if (focusedScript && focusedScript.relativePath.toLowerCase().endsWith(".gd") === false) {
      throw new ProjectAwarenessError("not_a_gdscript_file", "Focused script map supports project-local .gd files.", {
        script_path: focusedScript.resPath,
      });
    }
    const includeUsages = options.includeUsages !== false;
    const includeFunctions = options.includeFunctions !== false;
    const includeSignals = options.includeSignals !== false;
    const includeExports = options.includeExports !== false;
    const includeConstants = options.includeConstants === true;
    const maxScripts = boundedInt(options.maxScripts, MAX_PROJECT_SCRIPT_MAP_SCRIPTS, 1, MAX_PROJECT_SCRIPT_MAP_SCRIPTS_HARD);
    const index = await buildProjectIndex(projectRoot);
    const scripts = focusedScript
      ? index.files.filter((file) => file.relativePath === focusedScript.relativePath)
      : index.files.filter((file) => file.kind === "script");
    const scenes = index.files.filter((file) => file.kind === "scene");
    const scriptEntries = await Promise.all(scripts.slice(0, maxScripts).map(scriptMapEntry));
    const autoloadScriptEntries = focusedScript
      ? await Promise.all(index.files.filter((file) => file.kind === "script").slice(0, maxScripts).map(scriptMapEntry))
      : scriptEntries;
    const sceneEntries = includeUsages
      ? await Promise.all(scenes.slice(0, MAX_PROJECT_SCRIPT_MAP_SCENES).map((file) =>
        sceneDependencyEntry(projectRoot, file, { includeResources: false, includeNodes: true })
      ))
      : [];
    const usage = includeUsages ? scriptUsageFromSceneEntries(sceneEntries) : { byScript: new Map<string, JsonObject>(), items: [] };
    const classItems = classIndexFromScripts(scriptEntries);
    const classDuplicates = duplicateClassesFromClassIndex(classItems);
    const autoloadItems = await autoloadScriptMap(projectRoot, projectConfig.autoloads, autoloadScriptEntries);
    const agents = await collectAgentsFiles(projectRoot, true);
    const docs = await collectProjectDocPreviews(index);

    return {
      status: "ok",
      awareness_version: "godot-codex-bridge/project-awareness-v1",
      script_map_version: "godot-codex-bridge/project-script-map-v1",
      generated_at: new Date().toISOString(),
      project_root: projectRoot,
      project_file: projectFile,
      project_file_exists: projectText !== undefined,
      project_name: projectConfig.name,
      main_scene: projectConfig.mainScene,
      scope: {
        mode: focusedScript ? "single_script" : "project",
        script_path: focusedScript?.resPath ?? null,
        include_usages: includeUsages,
        include_functions: includeFunctions,
        include_signals: includeSignals,
        include_exports: includeExports,
        include_constants: includeConstants,
        max_scripts: maxScripts,
      },
      index: {
        scanned_files: index.scannedFiles,
        indexed_files: index.files.length,
        truncated: index.truncated,
        skipped: index.skipped,
      },
      scripts: {
        total: scripts.length,
        returned: scriptEntries.length,
        truncated: scripts.length > scriptEntries.length,
        items: scriptEntries.map((script) => filterScriptMapEntry(
          enrichScriptMapEntry(script, usage.byScript, autoloadItems.items),
          { includeFunctions, includeSignals, includeExports, includeConstants },
        )),
      },
      classes: {
        total: classItems.length,
        duplicate_count: classDuplicates.length,
        returned: Math.min(classItems.length, MAX_PROJECT_SCRIPT_MAP_CLASSES),
        truncated: classItems.length > MAX_PROJECT_SCRIPT_MAP_CLASSES,
        items: classItems.slice(0, MAX_PROJECT_SCRIPT_MAP_CLASSES),
        duplicates: classDuplicates.slice(0, 100),
      },
      autoloads: autoloadItems,
      scene_usage: {
        total: usage.items.length,
        returned: Math.min(usage.items.length, MAX_PROJECT_SCRIPT_MAP_USAGE),
        truncated: usage.items.length > MAX_PROJECT_SCRIPT_MAP_USAGE,
        items: usage.items.slice(0, MAX_PROJECT_SCRIPT_MAP_USAGE),
      },
      docs: {
        agents_root_present: agents.rootAgentsPresent,
        agents_files: agents.files.slice(0, MAX_PROJECT_SCRIPT_MAP_DOCS),
        project_docs: docs,
      },
      limits: {
        max_scripts: MAX_PROJECT_SCRIPT_MAP_SCRIPTS,
        max_scripts_hard: MAX_PROJECT_SCRIPT_MAP_SCRIPTS_HARD,
        max_scenes: MAX_PROJECT_SCRIPT_MAP_SCENES,
        max_classes: MAX_PROJECT_SCRIPT_MAP_CLASSES,
        max_usage_items: MAX_PROJECT_SCRIPT_MAP_USAGE,
        max_doc_previews: MAX_PROJECT_SCRIPT_MAP_DOCS,
        max_doc_preview_lines: MAX_PROJECT_SCRIPT_MAP_DOC_PREVIEW_LINES,
        max_doc_preview_bytes: MAX_PROJECT_SCRIPT_MAP_DOC_PREVIEW_BYTES,
        max_script_parse_bytes: MAX_PROJECT_MAP_SCRIPT_BYTES,
        max_scene_parse_bytes: MAX_SCENE_PARSE_BYTES,
      },
      excludes: blockedPathPolicy(),
    };
  } catch (error) {
    return projectAwarenessErrorEnvelope(error);
  }
}

export async function listProjectFiles(projectRoot: string, options: JsonObject = {}): Promise<ToolEnvelope> {
  try {
    const limit = boundedInt(options.limit, DEFAULT_LIST_LIMIT, 1, MAX_LIST_LIMIT);
    const offset = boundedInt(options.offset, 0, 0, Number.MAX_SAFE_INTEGER);
    const rootPath = typeof options.rootPath === "string" ? options.rootPath : undefined;
    const scope = rootPath ? resolveProjectPath(projectRoot, rootPath, { allowRoot: true }) : undefined;
    const index = await buildProjectIndex(projectRoot, { rootPath: scope?.relativePath });
    const globs = normalizeGlobList(options.globs);
    const extensionSet = normalizeExtensionSet(options.extensions);
    const kind = typeof options.kind === "string" && options.kind.trim() !== "" ? options.kind.trim() : undefined;

    const filtered = index.files.filter((file) => {
      if (kind && file.kind !== kind) {
        return false;
      }
      if (extensionSet && !extensionSet.has(file.extension)) {
        return false;
      }
      return matchesGlobs(file.relativePath, globs);
    });

    const page = filtered.slice(offset, offset + limit);
    const files = await Promise.all(page.map((file) => fileMetadataWithSmallSha(file)));

    return {
      status: "ok",
      awareness_version: "godot-codex-bridge/project-awareness-v1",
      project_root: projectRoot,
      root_path: scope?.relativePath ?? "",
      offset,
      limit,
      total_matching: filtered.length,
      returned_count: files.length,
      truncated: offset + files.length < filtered.length || index.truncated,
      files,
      skipped: index.skipped,
      excludes: blockedPathPolicy(),
    };
  } catch (error) {
    return projectAwarenessErrorEnvelope(error);
  }
}

export async function searchProjectFiles(projectRoot: string, options: JsonObject = {}): Promise<ToolEnvelope> {
  try {
    const query = stringOption(options.query, "query");
    if (query.trim() === "") {
      throw new ProjectAwarenessError("empty_query", "Search query is required.");
    }
    if (query.length > 200) {
      throw new ProjectAwarenessError("query_too_long", "Search query is limited to 200 characters.", {
        max_length: 200,
      });
    }

    const limit = boundedInt(options.limit, DEFAULT_SEARCH_LIMIT, 1, MAX_SEARCH_LIMIT);
    const offset = boundedInt(options.offset, 0, 0, Number.MAX_SAFE_INTEGER);
    const contextLines = boundedInt(options.contextLines, 0, 0, 5);
    const caseSensitive = options.caseSensitive === true;
    const rootPath = typeof options.rootPath === "string" ? options.rootPath : undefined;
    const scope = rootPath ? resolveProjectPath(projectRoot, rootPath, { allowRoot: true }) : undefined;
    const globs = normalizeGlobList(options.globs);

    const rg = await searchWithRipgrep(projectRoot, {
      query,
      scopePath: scope?.relativePath ?? "",
      globs,
      offset,
      limit,
      contextLines,
      caseSensitive,
    });
    if (rg) {
      return rg;
    }

    return await searchWithNode(projectRoot, {
      query,
      scopePath: scope?.relativePath ?? "",
      globs,
      offset,
      limit,
      contextLines,
      caseSensitive,
    });
  } catch (error) {
    return projectAwarenessErrorEnvelope(error);
  }
}

export async function readProjectFile(projectRoot: string, options: JsonObject = {}): Promise<ToolEnvelope> {
  try {
    const requestedPath = stringOption(options.path, "path");
    const resolved = resolveProjectPath(projectRoot, requestedPath);
    const stat = await statProjectFile(resolved.absolutePath);
    const metadata = await indexedFileFromStat(projectRoot, resolved.relativePath, resolved.absolutePath, stat);

    if (!metadata.isText) {
      return {
        status: "ok",
        awareness_version: "godot-codex-bridge/project-awareness-v1",
        project_root: projectRoot,
        file: fileMetadata(metadata),
        metadata_only: true,
        readable_text: false,
        content: null,
        lines: [],
        note: "Binary assets are returned as metadata only.",
      };
    }

    const startLine = boundedInt(options.startLine, 1, 1, Number.MAX_SAFE_INTEGER);
    const maxLines = boundedInt(options.maxLines, DEFAULT_READ_LINES, 1, MAX_READ_LINES);
    const maxBytes = boundedInt(options.maxBytes, DEFAULT_READ_BYTES, 1, MAX_READ_BYTES);
    const read = await readBoundedLines(resolved.absolutePath, startLine, maxLines, maxBytes);

    return {
      status: "ok",
      awareness_version: "godot-codex-bridge/project-awareness-v1",
      project_root: projectRoot,
      file: await fileMetadataWithSmallSha(metadata),
      metadata_only: false,
      readable_text: true,
      start_line: read.startLine,
      end_line: read.endLine,
      lines_returned: read.lines.length,
      byte_count: read.byteCount,
      truncated_by_lines: read.truncatedByLines,
      truncated_by_bytes: read.truncatedByBytes,
      more_after: read.moreAfter,
      content: read.lines.map((line) => line.text).join("\n"),
      lines: read.lines.map((line) => ({ line: line.line, text: line.text, truncated: line.truncated === true })),
    };
  } catch (error) {
    return projectAwarenessErrorEnvelope(error);
  }
}

export async function getAgentsContext(projectRoot: string): Promise<ToolEnvelope> {
  try {
    const agents = await collectAgentsFiles(projectRoot, true);
    return {
      status: "ok",
      awareness_version: "godot-codex-bridge/project-awareness-v1",
      project_root: projectRoot,
      root_agents_path: path.join(projectRoot, "AGENTS.md"),
      root_agents_present: agents.rootAgentsPresent,
      root_agents_missing: !agents.rootAgentsPresent,
      files_count: agents.files.length,
      files: agents.files,
      precedence_note: "Only project-root-bounded AGENTS.md files are read. Parent directories outside the configured project root are not scanned.",
      outside_root_scan: "not_performed_project_root_bound",
      excludes: blockedPathPolicy(),
    };
  } catch (error) {
    return projectAwarenessErrorEnvelope(error);
  }
}

export async function getSceneFileTree(
  projectRoot: string,
  options: JsonObject = {},
  source: SnapshotSource = {},
): Promise<ToolEnvelope> {
  try {
    const snapshot = snapshotFromEnvelope(source.snapshotEnvelope);
    const requestedScene = typeof options.scenePath === "string" && options.scenePath.trim() !== ""
      ? options.scenePath
      : currentScenePath(snapshot) ?? parseProjectConfig(await readTextIfExists(path.join(projectRoot, "project.godot"))).mainScene;

    if (!requestedScene) {
      return {
        status: "not_found",
        awareness_version: "godot-codex-bridge/project-awareness-v1",
        project_root: projectRoot,
        error: {
          code: "scene_path_unavailable",
          message: "No scene path was provided and no current/main scene was available.",
        },
      };
    }

    return await parseSceneFile(projectRoot, requestedScene);
  } catch (error) {
    return projectAwarenessErrorEnvelope(error);
  }
}

export async function getCurrentSourceContext(
  projectRoot: string,
  source: SnapshotSource = {},
): Promise<ToolEnvelope> {
  try {
    const snapshot = snapshotFromEnvelope(source.snapshotEnvelope);
    const projectConfig = parseProjectConfig(await readTextIfExists(path.join(projectRoot, "project.godot")));
    const scenePath = currentScenePath(snapshot) ?? projectConfig.mainScene ?? null;
    const sceneTree = scenePath ? await parseSceneFile(projectRoot, scenePath) : null;
    const scripts = collectCurrentScriptPaths(snapshot, sceneTree);
    const scriptPreviews: JsonObject[] = [];

    for (const scriptPath of scripts.slice(0, MAX_CURRENT_SOURCE_FILES)) {
      const read = await readProjectFile(projectRoot, {
        path: scriptPath,
        startLine: 1,
        maxLines: 80,
        maxBytes: 16_000,
      });
      if (read.status === "ok") {
        scriptPreviews.push({
          path: scriptPath,
          file: read.file,
          lines_returned: read.lines_returned,
          content: read.content,
          truncated_by_lines: read.truncated_by_lines,
          truncated_by_bytes: read.truncated_by_bytes,
          more_after: read.more_after,
        });
      }
    }

    return {
      status: "ok",
      awareness_version: "godot-codex-bridge/project-awareness-v1",
      project_root: projectRoot,
      context_snapshot_available: snapshot !== null,
      current_scene: objectAt(snapshot, ["current_scene"]),
      current_scene_path: scenePath,
      selected_nodes: arrayAt(snapshot, ["selected_nodes"]).slice(0, 25),
      scene_file_tree: sceneTree?.status === "ok" ? {
        scene_path: sceneTree.scene_path,
        node_count: sceneTree.node_count,
        nodes: sceneTree.nodes,
        tree: sceneTree.tree,
        external_resources: sceneTree.external_resources,
      } : sceneTree,
      script_paths: scripts,
      script_previews: scriptPreviews,
      autoloads: arrayAt(snapshot, ["gameplay_context", "autoloads"]).slice(0, 50),
      input_actions: arrayAt(snapshot, ["gameplay_context", "input_actions"]).slice(0, 50),
      current_script_editor_path: null,
      current_script_editor_note: "The current Godot addon snapshot does not expose the active Script editor file yet.",
    };
  } catch (error) {
    return projectAwarenessErrorEnvelope(error);
  }
}

function projectAwarenessErrorEnvelope(error: unknown): ToolEnvelope {
  if (error instanceof ProjectAwarenessError) {
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
      code: "project_awareness_error",
      message: error instanceof Error ? error.message : String(error),
    },
  };
}

async function buildProjectIndex(
  projectRoot: string,
  options: { rootPath?: string; maxFiles?: number } = {},
): Promise<ProjectIndex> {
  const rootPath = options.rootPath ?? "";
  const rootAbsolutePath = rootPath ? path.resolve(projectRoot, pathFromRelative(rootPath)) : projectRoot;
  if (!isInsidePath(projectRoot, rootAbsolutePath)) {
    throw new ProjectAwarenessError("path_boundary_rejected", "Resolved path is outside the configured project root.");
  }

  const files: IndexedFile[] = [];
  const skipped: JsonObject[] = [];
  const maxFiles = options.maxFiles ?? MAX_INDEX_FILES;
  let scannedFiles = 0;
  let truncated = false;

  async function walk(currentAbsolutePath: string): Promise<void> {
    if (files.length >= maxFiles) {
      truncated = true;
      return;
    }

    let entries;
    try {
      entries = await fs.readdir(currentAbsolutePath, { withFileTypes: true });
    } catch (error) {
      pushSkip(skipped, currentAbsolutePath, "readdir_failed", error instanceof Error ? error.message : String(error));
      return;
    }

    entries.sort((a, b) => a.name.localeCompare(b.name));
    for (const entry of entries) {
      if (files.length >= maxFiles) {
        truncated = true;
        return;
      }

      const absolutePath = path.join(currentAbsolutePath, entry.name);
      const relativePath = toProjectRelative(projectRoot, absolutePath);
      const blocked = blockedReasonFor(relativePath);
      if (blocked) {
        pushSkip(skipped, relativePath, blocked.code, blocked.message);
        continue;
      }

      if (entry.isDirectory()) {
        await walk(absolutePath);
        continue;
      }

      if (!entry.isFile()) {
        pushSkip(skipped, relativePath, "non_file_skipped", "Only regular files are indexed.");
        continue;
      }

      scannedFiles += 1;
      const stat = await fs.stat(absolutePath);
      files.push(await indexedFileFromStat(projectRoot, relativePath, absolutePath, stat));
    }
  }

  const rootStat = await fs.stat(rootAbsolutePath).catch(() => null);
  if (!rootStat) {
    throw new ProjectAwarenessError("path_not_found", "Requested project path does not exist.", {
      path: rootPath,
    });
  }
  if (rootStat.isFile()) {
    files.push(await indexedFileFromStat(projectRoot, rootPath, rootAbsolutePath, rootStat));
  } else {
    await walk(rootAbsolutePath);
  }

  files.sort((a, b) => a.relativePath.localeCompare(b.relativePath));
  return { files, rootPath, truncated, scannedFiles, skipped };
}

async function indexedFileFromStat(
  projectRoot: string,
  relativePath: string,
  absolutePath: string,
  stat: { size: number; mtimeMs: number; mtime: Date },
): Promise<IndexedFile> {
  const extension = path.posix.extname(relativePath).toLowerCase();
  const text = await classifyTextFile(absolutePath, extension, stat.size);
  return {
    relativePath,
    resPath: `res://${relativePath}`,
    absolutePath,
    extension,
    kind: kindForPath(relativePath, extension),
    byteSize: stat.size,
    mtimeMs: stat.mtimeMs,
    mtime: stat.mtime.toISOString(),
    isText: text.isText,
    isBinary: !text.isText,
    textEncoding: text.isText ? "utf8" : null,
    binaryReason: text.isText ? null : text.reason,
  };
}

async function classifyTextFile(
  absolutePath: string,
  extension: string,
  byteSize: number,
): Promise<{ isText: boolean; reason: string | null }> {
  if (BINARY_EXTENSIONS.has(extension)) {
    return { isText: false, reason: "binary_extension" };
  }
  if (TEXT_EXTENSIONS.has(extension)) {
    return { isText: true, reason: null };
  }
  if (byteSize === 0) {
    return { isText: true, reason: null };
  }

  const probe = await readFirstBytes(absolutePath, Math.min(TEXT_PROBE_BYTES, byteSize));
  if (probe.includes(0)) {
    return { isText: false, reason: "nul_byte_probe" };
  }
  if (probe.toString("utf8").includes("\uFFFD")) {
    return { isText: false, reason: "utf8_probe_failed" };
  }
  return { isText: true, reason: null };
}

async function readFirstBytes(absolutePath: string, byteCount: number): Promise<Buffer> {
  const handle = await fs.open(absolutePath, "r");
  try {
    const buffer = Buffer.alloc(byteCount);
    const result = await handle.read(buffer, 0, byteCount, 0);
    return buffer.subarray(0, result.bytesRead);
  } finally {
    await handle.close();
  }
}

async function statProjectFile(absolutePath: string): Promise<{ size: number; mtimeMs: number; mtime: Date; isFile(): boolean }> {
  let stat;
  try {
    stat = await fs.stat(absolutePath);
  } catch {
    throw new ProjectAwarenessError("file_not_found", "Project file does not exist.", {
      path: absolutePath,
    });
  }
  if (!stat.isFile()) {
    throw new ProjectAwarenessError("not_a_file", "Requested path is not a file.", {
      path: absolutePath,
    });
  }
  return stat;
}

function resolveProjectPath(
  projectRoot: string,
  requestedPath: string,
  options: { allowRoot?: boolean } = {},
): ResolvedProjectPath {
  if (typeof requestedPath !== "string" || requestedPath.trim() === "") {
    if (options.allowRoot) {
      return {
        relativePath: "",
        absolutePath: projectRoot,
        resPath: "res://",
      };
    }
    throw new ProjectAwarenessError("empty_path", "Project-relative path is required.");
  }

  const trimmed = requestedPath.trim();
  if (trimmed.includes("\0")) {
    throw new ProjectAwarenessError("nul_path_rejected", "Path must not contain NUL bytes.");
  }
  if (isAnyAbsolutePath(trimmed)) {
    throw new ProjectAwarenessError("absolute_path_rejected", "Use a res:// or project-relative path, not an absolute path.");
  }

  const withoutResPrefix = trimmed.startsWith("res://") ? trimmed.slice("res://".length) : trimmed;
  if (isAnyAbsolutePath(withoutResPrefix)) {
    throw new ProjectAwarenessError("absolute_path_rejected", "Use a res:// or project-relative path, not an absolute path.");
  }

  const normalized = path.posix.normalize(withoutResPrefix.replaceAll("\\", "/"));
  if (normalized === ".") {
    if (options.allowRoot) {
      return {
        relativePath: "",
        absolutePath: projectRoot,
        resPath: "res://",
      };
    }
    throw new ProjectAwarenessError("empty_path", "Project-relative file path is required.");
  }
  if (normalized === ".." || normalized.startsWith("../") || path.posix.isAbsolute(normalized)) {
    throw new ProjectAwarenessError("path_traversal_rejected", "Path traversal outside the project is not allowed.");
  }

  const blocked = blockedReasonFor(normalized);
  if (blocked) {
    throw new ProjectAwarenessError(blocked.code, blocked.message, {
      path: normalized,
    });
  }

  const absolutePath = path.resolve(projectRoot, pathFromRelative(normalized));
  if (!isInsidePath(projectRoot, absolutePath)) {
    throw new ProjectAwarenessError("path_boundary_rejected", "Resolved path is outside the configured project root.");
  }

  return {
    relativePath: normalized,
    absolutePath,
    resPath: `res://${normalized}`,
  };
}

function blockedReasonFor(relativePath: string): { code: string; message: string } | null {
  const normalized = relativePath.replaceAll("\\", "/").replace(/^\.\/+/, "");
  if (normalized === "") {
    return null;
  }

  const segments = normalized.split("/").filter(Boolean);
  const blockedSegment = segments.find((segment) => BLOCKED_SEGMENTS.has(segment.toLowerCase()));
  if (blockedSegment) {
    return {
      code: "generated_path_rejected",
      message: `Generated/cache path segment is not readable through project awareness tools: ${blockedSegment}.`,
    };
  }

  const lower = normalized.toLowerCase();
  if (lower.endsWith(".import")) {
    return {
      code: "generated_path_rejected",
      message: "Godot .import metadata files are generated and are not readable through project awareness tools.",
    };
  }

  const blockedPrefix = BLOCKED_PREFIXES.find((prefix) => lower === prefix || lower.startsWith(`${prefix}/`));
  if (blockedPrefix) {
    return {
      code: "generated_path_rejected",
      message: `Generated or third-party assistant addon path is excluded: ${blockedPrefix}.`,
    };
  }

  return null;
}

function blockedPathPolicy(): JsonObject {
  return {
    blocked_segments: [...BLOCKED_SEGMENTS].sort(),
    blocked_prefixes: [...BLOCKED_PREFIXES].sort(),
    binary_assets: "metadata_only",
    absolute_paths: "rejected",
    traversal: "rejected",
  };
}

function isAnyAbsolutePath(value: string): boolean {
  return path.isAbsolute(value) || path.win32.isAbsolute(value) || path.posix.isAbsolute(value) || /^[A-Za-z]:[\\/]/.test(value);
}

function pathFromRelative(relativePath: string): string {
  return relativePath.split("/").join(path.sep);
}

function toProjectRelative(projectRoot: string, absolutePath: string): string {
  return path.relative(projectRoot, absolutePath).replaceAll(path.sep, "/");
}

function fileMetadata(file: IndexedFile): JsonObject {
  return {
    path: file.relativePath,
    res_path: file.resPath,
    extension: file.extension,
    kind: file.kind,
    byte_size: file.byteSize,
    mtime: file.mtime,
    is_text: file.isText,
    is_binary: file.isBinary,
    text_encoding: file.textEncoding,
    binary_reason: file.binaryReason,
  };
}

async function fileMetadataWithSmallSha(file: IndexedFile): Promise<JsonObject> {
  const metadata = fileMetadata(file);
  if (file.isText && file.byteSize <= MAX_TEXT_SHA_BYTES) {
    const content = await fs.readFile(file.absolutePath);
    metadata.sha256 = sha256Buffer(content);
  } else {
    metadata.sha256 = null;
    metadata.sha256_skipped_reason = file.isText ? "file_too_large" : "binary_metadata_only";
  }
  return metadata;
}

function kindForPath(relativePath: string, extension: string): string {
  const lower = relativePath.toLowerCase();
  if (lower.startsWith("addons/")) {
    return "addon";
  }
  if ([".gd", ".cs"].includes(extension)) {
    return "script";
  }
  if ([".tscn", ".scn"].includes(extension)) {
    return "scene";
  }
  if ([".tres", ".res"].includes(extension)) {
    return "resource";
  }
  if ([".gdshader", ".shader"].includes(extension)) {
    return "shader";
  }
  if ([".png", ".jpg", ".jpeg", ".webp", ".bmp", ".svg", ".ico", ".exr", ".hdr"].includes(extension)) {
    return "image";
  }
  if ([".mp3", ".ogg", ".wav"].includes(extension)) {
    return "audio";
  }
  if ([".godot", ".cfg", ".ini", ".json", ".yaml", ".yml"].includes(extension)) {
    return "config";
  }
  if ([".md", ".txt"].includes(extension)) {
    return "doc";
  }
  return "unknown";
}

function summarizeFiles(files: IndexedFile[]): JsonObject {
  const byKind: Record<string, number> = {};
  const byExtension: Record<string, number> = {};
  let textCount = 0;
  let binaryCount = 0;
  for (const file of files) {
    byKind[file.kind] = (byKind[file.kind] ?? 0) + 1;
    byExtension[file.extension || "(none)"] = (byExtension[file.extension || "(none)"] ?? 0) + 1;
    if (file.isText) {
      textCount += 1;
    } else {
      binaryCount += 1;
    }
  }
  return {
    file_count: files.length,
    text_count: textCount,
    binary_count: binaryCount,
    by_kind: byKind,
    by_extension: byExtension,
  };
}

function topLevelEntries(files: IndexedFile[]): JsonObject[] {
  const entries = new Map<string, { files: number; dirs: number }>();
  for (const file of files) {
    const parts = file.relativePath.split("/");
    const name = parts[0] ?? file.relativePath;
    const current = entries.get(name) ?? { files: 0, dirs: 0 };
    if (parts.length === 1) {
      current.files += 1;
    } else {
      current.dirs += 1;
    }
    entries.set(name, current);
  }
  return [...entries.entries()]
    .sort((a, b) => a[0].localeCompare(b[0]))
    .slice(0, 50)
    .map(([name, counts]) => ({
      name,
      direct_files: counts.files,
      nested_files: counts.dirs,
    }));
}

async function sceneMapEntry(projectRoot: string, file: IndexedFile): Promise<JsonObject> {
  const base = fileMetadata(file);
  if (!file.isText || file.extension === ".scn" || file.byteSize > MAX_SCENE_PARSE_BYTES) {
    return {
      ...base,
      metadata_only: true,
      node_count: null,
      external_resource_count: null,
      script_paths: [],
      groups: [],
      note: !file.isText || file.extension === ".scn"
        ? "Binary scene returned as metadata only."
        : `Scene exceeds parser byte limit of ${MAX_SCENE_PARSE_BYTES}.`,
    };
  }

  const content = await fs.readFile(file.absolutePath, "utf8");
  const parsed = parseTscn(content);
  return {
    ...base,
    metadata_only: false,
    node_count: parsed.nodes.length,
    nodes_truncated: parsed.nodesTruncated,
    root_node: parsed.nodes[0] ?? null,
    node_types: uniqueStrings(parsed.nodes.map((node) => typeof node.type === "string" ? node.type : ""), 30),
    script_paths: uniqueStrings(parsed.nodes.map((node) => typeof node.script_path === "string" ? node.script_path : ""), 50),
    external_resource_count: parsed.externalResources.length,
    external_resources: parsed.externalResources.slice(0, 50),
    groups: sceneGroupsFromContent(content),
    sub_resource_count: parsed.subResourceCount,
    load_steps: parsed.loadSteps,
    uid: parsed.uid,
  };
}

async function sceneDependencyEntry(projectRoot: string, file: IndexedFile, options: { includeResources: boolean; includeNodes: boolean }): Promise<{
  scene: JsonObject;
  edges: JsonObject[];
  missingResources: JsonObject[];
}> {
  const base = fileMetadata(file);
  const scene: JsonObject = {
    ...base,
    metadata_only: true,
    node_count: null,
    nodes_truncated: false,
    scene_instances: [],
    script_paths: [],
    instance_scene_paths: [],
    external_resources: [],
    sub_resources: [],
    sub_resource_count: null,
    missing_resources: [],
    diagnostics: [],
  };
  const edges: JsonObject[] = [];
  const missingResources: JsonObject[] = [];

  if (!file.isText || file.extension === ".scn" || file.byteSize > MAX_SCENE_PARSE_BYTES) {
    scene.note = !file.isText || file.extension === ".scn"
      ? "Binary scene returned as metadata only."
      : `Scene exceeds parser byte limit of ${MAX_SCENE_PARSE_BYTES}.`;
    return { scene, edges, missingResources };
  }

  const content = await fs.readFile(file.absolutePath, "utf8");
  const parsed = parseTscn(content);
  const sceneResPath = file.resPath;
  const externalResources = parsed.externalResources.slice(0, 200);
  const scriptPaths = uniqueStrings(parsed.nodes.map((node) =>
    typeof node.script_path === "string" ? node.script_path : ""
  ), 100);
  const sceneInstances = options.includeNodes ? parsed.nodes
    .filter((node) => typeof node.instance_scene_path === "string")
    .slice(0, 100)
    .map((node) => ({
      node_path: typeof node.scene_path === "string" ? node.scene_path : null,
      node_name: typeof node.name === "string" ? node.name : null,
      scene_path: node.instance_scene_path,
    })) : [];

  if (options.includeResources) {
    for (const resource of externalResources) {
      if (typeof resource.path !== "string" || resource.path === "") {
        continue;
      }
      edges.push({
        kind: "external_resource",
        from_scene: sceneResPath,
        from: sceneResPath,
        to: resource.path,
        resource_type: typeof resource.type === "string" ? resource.type : null,
        ext_resource_id: typeof resource.id === "string" ? resource.id : null,
      });
    }
  }

  for (const node of options.includeNodes ? parsed.nodes : []) {
    if (typeof node.script_path === "string" && node.script_path !== "") {
      edges.push({
        kind: "script_attachment",
        graph_kind: "uses_script",
        from_scene: sceneResPath,
        from: sceneResPath,
        to: node.script_path,
        node_path: typeof node.scene_path === "string" ? node.scene_path : null,
        node_type: typeof node.type === "string" ? node.type : null,
        via_node_path: typeof node.scene_path === "string" ? node.scene_path : null,
      });
    } else if (typeof node.script_resource_id === "string" && node.script_resource_id !== "") {
      (scene.diagnostics as JsonObject[]).push({
        code: "unresolved_script_resource",
        severity: "warning",
        scene_path: sceneResPath,
        ext_resource_id: node.script_resource_id,
        node_path: typeof node.scene_path === "string" ? node.scene_path : null,
        message: `Node script references missing ExtResource id ${node.script_resource_id}.`,
      });
    }
    if (typeof node.instance_scene_path === "string" && node.instance_scene_path !== "") {
      edges.push({
        kind: "scene_instance",
        graph_kind: "instances",
        from_scene: sceneResPath,
        from: sceneResPath,
        to: node.instance_scene_path,
        node_path: typeof node.scene_path === "string" ? node.scene_path : null,
        via_node_path: typeof node.scene_path === "string" ? node.scene_path : null,
      });
    } else if (typeof node.instance_resource_id === "string" && node.instance_resource_id !== "") {
      (scene.diagnostics as JsonObject[]).push({
        code: "unresolved_instance_resource",
        severity: "warning",
        scene_path: sceneResPath,
        ext_resource_id: node.instance_resource_id,
        node_path: typeof node.scene_path === "string" ? node.scene_path : null,
        message: `Node instance references missing ExtResource id ${node.instance_resource_id}.`,
      });
    }
  }

  const referencedPaths = uniqueStrings(externalResources.map((resource) =>
    typeof resource.path === "string" ? resource.path : ""
  ), 500);
  const missingChecks = await Promise.all(referencedPaths.map(async (resourcePath) => ({
    path: resourcePath,
    exists: resourcePath.startsWith("res://") ? await safePathExists(projectRoot, resourcePath) : null,
  })));
  for (const check of missingChecks) {
    if (check.exists === false) {
      missingResources.push({
        scene: sceneResPath,
        scene_path: sceneResPath,
        path: check.path,
        code: "missing_resource",
        severity: "error",
        message: `Scene references missing project resource ${check.path}.`,
      });
    }
  }

  scene.metadata_only = false;
  scene.node_count = parsed.nodes.length;
  scene.nodes_truncated = parsed.nodesTruncated;
  scene.root_node = parsed.nodes[0] ?? null;
  scene.scene_instances = sceneInstances;
  scene.instance_scene_paths = uniqueStrings(sceneInstances.map((item) =>
    typeof item.scene_path === "string" ? item.scene_path : ""
  ), 100);
  scene.script_paths = scriptPaths;
  scene.external_resources = options.includeResources ? externalResources : [];
  scene.sub_resources = parsed.subResources.slice(0, MAX_SCENE_GRAPH_SUB_RESOURCES_PER_SCENE);
  scene.sub_resource_count = parsed.subResourceCount;
  scene.sub_resources_truncated = parsed.subResources.length > MAX_SCENE_GRAPH_SUB_RESOURCES_PER_SCENE;
  scene.load_steps = parsed.loadSteps;
  scene.uid = parsed.uid;
  scene.missing_resource_count = missingResources.length;
  scene.missing_resources = missingResources;

  return { scene, edges, missingResources };
}

async function scriptMapEntry(file: IndexedFile): Promise<JsonObject> {
  const base = fileMetadata(file);
  if (!file.isText || file.byteSize > MAX_PROJECT_MAP_SCRIPT_BYTES) {
    return {
      ...base,
      metadata_only: true,
      class_name: null,
      extends: null,
      signals: [],
      exports: [],
      functions: [],
      note: file.isText ? `Script exceeds parser byte limit of ${MAX_PROJECT_MAP_SCRIPT_BYTES}.` : "Binary script metadata only.",
    };
  }

  const content = await fs.readFile(file.absolutePath, "utf8");
  const parsed = parseGdScriptSummary(content);
  return {
    ...base,
    metadata_only: false,
    ...parsed,
  };
}

function parseGdScriptSummary(content: string): JsonObject {
  const signals: JsonObject[] = [];
  const exports: JsonObject[] = [];
  const functions: JsonObject[] = [];
  const constants: string[] = [];
  let className: string | null = null;
  let extendsName: string | null = null;

  const lines = content.split(/\r?\n/);
  for (let index = 0; index < lines.length; index += 1) {
    const lineNumber = index + 1;
    const line = lines[index].trim();
    if (line === "" || line.startsWith("#")) {
      continue;
    }
    const classMatch = /^class_name\s+([A-Za-z_][A-Za-z0-9_]*)/.exec(line);
    if (classMatch && className === null) {
      className = classMatch[1];
      continue;
    }
    const extendsMatch = /^extends\s+([A-Za-z_][A-Za-z0-9_./"]*)/.exec(line);
    if (extendsMatch && extendsName === null) {
      extendsName = stripQuotes(extendsMatch[1]);
      continue;
    }
    const signalMatch = /^signal\s+([A-Za-z_][A-Za-z0-9_]*)/.exec(line);
    if (signalMatch && signals.length < 30) {
      signals.push({ name: signalMatch[1], line: lineNumber });
      continue;
    }
    const exportMatch = /^(?:@export[^\n]*\s+)?var\s+([A-Za-z_][A-Za-z0-9_]*)/.exec(line);
    if (line.startsWith("@export") && exportMatch && exports.length < 30) {
      exports.push({ name: exportMatch[1], line: lineNumber });
      continue;
    }
    const functionMatch = /^func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/.exec(line);
    if (functionMatch && functions.length < 50) {
      functions.push({ name: functionMatch[1], line: lineNumber });
      continue;
    }
    const constMatch = /^const\s+([A-Za-z_][A-Za-z0-9_]*)/.exec(line);
    if (constMatch && constants.length < 30) {
      constants.push(constMatch[1]);
    }
  }

  return {
    class_name: className,
    extends: extendsName,
    signals,
    exports,
    functions,
    constants,
  };
}

function sceneGroupsFromContent(content: string): JsonObject[] {
  const groups = new Map<string, { count: number; nodes: string[] }>();
  const lines = content.split(/\r?\n/);
  for (const line of lines) {
    const section = /^\[(.*)\]$/.exec(line.trim());
    if (!section) {
      continue;
    }
    const header = section[1];
    if (!header.startsWith("node ")) {
      continue;
    }
    const attrs = parseSectionAttributes(header);
    const nodeName = typeof attrs.name === "string" ? attrs.name : "";
    const groupsMatch = /\bgroups=\[([^\]]*)\]/.exec(header);
    if (!groupsMatch) {
      continue;
    }
    for (const rawGroup of groupsMatch[1].split(",")) {
      const groupName = stripQuotes(rawGroup.trim());
      if (!groupName) {
        continue;
      }
      const entry = groups.get(groupName) ?? { count: 0, nodes: [] };
      entry.count += 1;
      if (nodeName && entry.nodes.length < 12) {
        entry.nodes.push(nodeName);
      }
      groups.set(groupName, entry);
    }
  }
  return [...groups.entries()]
    .sort((a, b) => b[1].count - a[1].count || a[0].localeCompare(b[0]))
    .map(([name, value]) => ({ name, count: value.count, sample_nodes: value.nodes }));
}

function collectProjectGroups(sceneEntries: JsonObject[]): JsonObject[] {
  const groups = new Map<string, { count: number; scenes: string[]; nodes: string[] }>();
  for (const scene of sceneEntries) {
    const scenePath = typeof scene.res_path === "string" ? scene.res_path : typeof scene.path === "string" ? scene.path : "";
    const sceneGroups = Array.isArray(scene.groups) ? scene.groups : [];
    for (const group of sceneGroups) {
      if (!isJsonObject(group) || typeof group.name !== "string") {
        continue;
      }
      const entry = groups.get(group.name) ?? { count: 0, scenes: [], nodes: [] };
      entry.count += typeof group.count === "number" ? group.count : 1;
      if (scenePath && !entry.scenes.includes(scenePath) && entry.scenes.length < 12) {
        entry.scenes.push(scenePath);
      }
      const sampleNodes = Array.isArray(group.sample_nodes) ? group.sample_nodes : [];
      for (const node of sampleNodes) {
        if (typeof node === "string" && entry.nodes.length < 12) {
          entry.nodes.push(node);
        }
      }
      groups.set(group.name, entry);
    }
  }
  return [...groups.entries()]
    .sort((a, b) => b[1].count - a[1].count || a[0].localeCompare(b[0]))
    .map(([name, value]) => ({
      name,
      count: value.count,
      sample_scenes: value.scenes,
      sample_nodes: value.nodes,
    }));
}

function collectProjectSignals(scriptEntries: JsonObject[]): JsonObject[] {
  const signals: JsonObject[] = [];
  for (const script of scriptEntries) {
    const scriptPath = typeof script.res_path === "string" ? script.res_path : typeof script.path === "string" ? script.path : "";
    const scriptSignals = Array.isArray(script.signals) ? script.signals : [];
    for (const signal of scriptSignals) {
      if (!isJsonObject(signal) || typeof signal.name !== "string") {
        continue;
      }
      signals.push({
        name: signal.name,
        script_path: scriptPath,
        line: typeof signal.line === "number" ? signal.line : null,
      });
    }
  }
  return signals.sort((a, b) =>
    String(a.name).localeCompare(String(b.name)) || String(a.script_path).localeCompare(String(b.script_path))
  );
}

function scriptUsageFromSceneEntries(sceneEntries: Array<{ scene: JsonObject; edges: JsonObject[] }>): {
  byScript: Map<string, JsonObject>;
  items: JsonObject[];
} {
  const byScript = new Map<string, JsonObject>();
  for (const entry of sceneEntries) {
    for (const edge of entry.edges) {
      if (edge.kind !== "script_attachment" || typeof edge.to !== "string") {
        continue;
      }
      const scriptPath = edge.to;
      const usage = byScript.get(scriptPath) ?? {
        script_path: scriptPath,
        scene_paths: [],
        nodes: [],
      };
      const scenePath = typeof edge.from_scene === "string" ? edge.from_scene : null;
      const nodePath = typeof edge.via_node_path === "string" ? edge.via_node_path : null;
      if (scenePath && !(usage.scene_paths as string[]).includes(scenePath)) {
        (usage.scene_paths as string[]).push(scenePath);
      }
      if (scenePath && (usage.nodes as JsonObject[]).length < MAX_PROJECT_SCRIPT_MAP_USAGE) {
        (usage.nodes as JsonObject[]).push({
          scene_path: scenePath,
          node_path: nodePath,
          node_type: typeof edge.node_type === "string" ? edge.node_type : null,
        });
      }
      byScript.set(scriptPath, usage);
    }
  }

  const items: JsonObject[] = [...byScript.values()]
    .map((usage) => ({
      ...usage,
      scene_count: Array.isArray(usage.scene_paths) ? usage.scene_paths.length : 0,
      node_count: Array.isArray(usage.nodes) ? usage.nodes.length : 0,
    }))
    .sort((a, b) => String((a as JsonObject).script_path).localeCompare(String((b as JsonObject).script_path)));

  return { byScript, items };
}

function classIndexFromScripts(scriptEntries: JsonObject[]): JsonObject[] {
  return scriptEntries
    .filter((script) => typeof script.class_name === "string" && script.class_name !== "")
    .map((script) => ({
      class_name: script.class_name,
      script_path: typeof script.res_path === "string" ? script.res_path : script.path,
      extends: typeof script.extends === "string" ? script.extends : null,
      metadata_only: script.metadata_only === true,
    }))
    .sort((a, b) =>
      String(a.class_name).localeCompare(String(b.class_name)) ||
      String(a.script_path).localeCompare(String(b.script_path))
    );
}

function duplicateClassesFromClassIndex(classItems: JsonObject[]): JsonObject[] {
  const byClass = new Map<string, string[]>();
  for (const item of classItems) {
    const className = typeof item.class_name === "string" ? item.class_name : "";
    const scriptPath = typeof item.script_path === "string" ? item.script_path : "";
    if (!className || !scriptPath) {
      continue;
    }
    const paths = byClass.get(className) ?? [];
    paths.push(scriptPath);
    byClass.set(className, paths);
  }
  return [...byClass.entries()]
    .filter(([, paths]) => paths.length > 1)
    .map(([className, paths]) => ({
      class_name: className,
      script_paths: paths.sort(),
      severity: "warning",
      code: "duplicate_class_name",
      message: `class_name ${className} is declared in ${paths.length} scripts.`,
    }))
    .sort((a, b) => String(a.class_name).localeCompare(String(b.class_name)));
}

async function autoloadScriptMap(
  projectRoot: string,
  autoloads: JsonObject[],
  scriptEntries: JsonObject[],
): Promise<{
  total: number;
  items: JsonObject[];
  missing: JsonObject[];
}> {
  const scriptByPath = new Map<string, JsonObject>();
  for (const script of scriptEntries) {
    const scriptPath = typeof script.res_path === "string" ? script.res_path : typeof script.path === "string" ? script.path : "";
    if (scriptPath !== "") {
      scriptByPath.set(scriptPath, script);
    }
  }

  const items: JsonObject[] = [];
  const missing: JsonObject[] = [];
  for (const autoload of autoloads) {
    const autoloadPath = typeof autoload.path === "string" ? autoload.path : "";
    const script = scriptByPath.get(autoloadPath);
    const exists = autoloadPath.startsWith("res://") ? await safePathExists(projectRoot, autoloadPath) : false;
    const item: JsonObject = {
      name: autoload.name,
      path: autoloadPath,
      exists,
      singleton: autoload.singleton === true,
      script_found: script !== undefined,
      class_name: script && typeof script.class_name === "string" ? script.class_name : null,
      extends: script && typeof script.extends === "string" ? script.extends : null,
    };
    items.push(item);
    if (!exists) {
      missing.push({
        name: autoload.name,
        path: autoloadPath,
        code: "missing_autoload_script",
        severity: "error",
        message: `Project autoload ${autoload.name} references missing script ${autoloadPath}.`,
      });
    }
  }
  return {
    total: autoloads.length,
    items,
    missing,
  };
}

function enrichScriptMapEntry(
  script: JsonObject,
  usageByScript: Map<string, JsonObject>,
  autoloads: JsonObject[],
): JsonObject {
  const scriptPath = typeof script.res_path === "string" ? script.res_path : typeof script.path === "string" ? script.path : "";
  const usage = usageByScript.get(scriptPath);
  const autoload = autoloads.find((item) => item.path === scriptPath) ?? null;
  return {
    ...script,
    used_by_scene_count: usage && Array.isArray(usage.scene_paths) ? usage.scene_paths.length : 0,
    used_by_scenes: usage && Array.isArray(usage.scene_paths) ? usage.scene_paths : [],
    scene_usage: usage && Array.isArray(usage.nodes) ? usage.nodes : [],
    autoload,
  };
}

function filterScriptMapEntry(
  script: JsonObject,
  options: { includeFunctions: boolean; includeSignals: boolean; includeExports: boolean; includeConstants: boolean },
): JsonObject {
  const filtered = { ...script };
  if (!options.includeFunctions) {
    filtered.functions = [];
  }
  if (!options.includeSignals) {
    filtered.signals = [];
  }
  if (!options.includeExports) {
    filtered.exports = [];
  }
  if (!options.includeConstants) {
    filtered.constants = [];
  }
  return filtered;
}

async function collectProjectDocPreviews(index: ProjectIndex): Promise<JsonObject[]> {
  const candidates = index.files
    .filter((file) => file.kind === "doc" && file.isText)
    .filter((file) => path.posix.basename(file.relativePath).toLowerCase() !== "agents.md")
    .sort((a, b) => pathDepth(a.relativePath) - pathDepth(b.relativePath) || a.relativePath.localeCompare(b.relativePath))
    .slice(0, MAX_PROJECT_SCRIPT_MAP_DOCS);
  const docs: JsonObject[] = [];
  for (const file of candidates) {
    const metadata = await fileMetadataWithSmallSha(file);
    const preview = await readBoundedLines(
      file.absolutePath,
      1,
      MAX_PROJECT_SCRIPT_MAP_DOC_PREVIEW_LINES,
      MAX_PROJECT_SCRIPT_MAP_DOC_PREVIEW_BYTES,
    );
    docs.push({
      ...metadata,
      preview: preview.lines.map((line) => line.text).join("\n"),
      preview_lines: preview.lines.length,
      preview_bytes: preview.byteCount,
      preview_truncated: preview.truncatedByBytes || preview.truncatedByLines || preview.moreAfter,
    });
  }
  return docs;
}

function detectSceneCycles(edges: JsonObject[]): JsonObject[] {
  const adjacency = new Map<string, Set<string>>();
  const displayPath = new Map<string, string>();
  for (const edge of edges) {
    const from = typeof edge.from_scene === "string" ? edge.from_scene : "";
    const to = typeof edge.to === "string" ? edge.to : "";
    if (!from || !to || !isSceneResPath(to)) {
      continue;
    }
    const fromKey = normalizeGraphPath(from);
    const toKey = normalizeGraphPath(to);
    displayPath.set(fromKey, from);
    displayPath.set(toKey, to);
    const targets = adjacency.get(fromKey) ?? new Set<string>();
    targets.add(toKey);
    adjacency.set(fromKey, targets);
  }

  const cycles: JsonObject[] = [];
  const seenCycles = new Set<string>();
  const visiting = new Set<string>();
  const pathStack: string[] = [];

  const visit = (node: string): void => {
    if (cycles.length >= MAX_SCENE_GRAPH_CYCLES) {
      return;
    }
    if (visiting.has(node)) {
      const start = pathStack.indexOf(node);
      if (start >= 0) {
        const cycleKeys = [...pathStack.slice(start), node];
        const signature = canonicalCycleSignature(cycleKeys);
        if (!seenCycles.has(signature)) {
          seenCycles.add(signature);
          cycles.push({
            kind: "scene_instance_cycle",
            paths: cycleKeys.map((key) => displayPath.get(key) ?? key),
          });
        }
      }
      return;
    }
    visiting.add(node);
    pathStack.push(node);
    for (const target of adjacency.get(node) ?? []) {
      visit(target);
    }
    pathStack.pop();
    visiting.delete(node);
  };

  for (const node of [...adjacency.keys()].sort()) {
    visit(node);
    if (cycles.length >= MAX_SCENE_GRAPH_CYCLES) {
      break;
    }
  }

  return cycles;
}

function graphNodesFromSceneEntries(
  sceneEntries: Array<{ scene: JsonObject; edges: JsonObject[]; missingResources: JsonObject[] }>,
  edges: JsonObject[],
  missingResources: JsonObject[],
): JsonObject[] {
  const nodes = new Map<string, JsonObject>();
  for (const entry of sceneEntries) {
    const scenePath = typeof entry.scene.res_path === "string" ? entry.scene.res_path : "";
    if (scenePath) {
      nodes.set(scenePath, {
        id: scenePath,
        kind: "scene",
        path: scenePath,
        exists: true,
        metadata_only: entry.scene.metadata_only === true,
      });
    }
  }

  const missing = new Set(missingResources
    .map((item) => typeof item.path === "string" ? item.path : "")
    .filter(Boolean)
    .map(normalizeGraphPath));

  for (const edge of edges) {
    const to = typeof edge.to === "string" ? edge.to : "";
    if (!to || nodes.has(to)) {
      continue;
    }
    const resourceType = typeof edge.resource_type === "string" ? edge.resource_type : "";
    nodes.set(to, {
      id: to,
      kind: graphNodeKind(to, String(edge.kind), resourceType),
      path: to,
      type: resourceType || null,
      exists: to.startsWith("res://") ? !missing.has(normalizeGraphPath(to)) : null,
    });
  }

  return [...nodes.values()].slice(0, MAX_SCENE_GRAPH_SCENES + MAX_SCENE_GRAPH_EDGES);
}

function graphNodeKind(pathValue: string, edgeKind: string, resourceType: string): string {
  if (edgeKind === "script_attachment" || pathValue.endsWith(".gd") || pathValue.endsWith(".cs")) {
    return "script";
  }
  if (edgeKind === "scene_instance" || isSceneResPath(pathValue)) {
    return "scene";
  }
  if (resourceType === "Script") {
    return "script";
  }
  if (resourceType === "PackedScene") {
    return "scene";
  }
  return "resource";
}

function isSceneResPath(value: string): boolean {
  const extension = path.posix.extname(value.replaceAll("\\", "/")).toLowerCase();
  return value.startsWith("res://") && [".tscn", ".scn"].includes(extension);
}

function normalizeGraphPath(value: string): string {
  return value.replaceAll("\\", "/").replace(/\/+$/, "").toLowerCase();
}

function canonicalCycleSignature(cycleKeys: string[]): string {
  const withoutDuplicateEnd = cycleKeys.length > 1 && cycleKeys[0] === cycleKeys[cycleKeys.length - 1]
    ? cycleKeys.slice(0, -1)
    : cycleKeys;
  if (withoutDuplicateEnd.length === 0) {
    return "";
  }
  const rotations = withoutDuplicateEnd.map((_, index) =>
    [...withoutDuplicateEnd.slice(index), ...withoutDuplicateEnd.slice(0, index)].join(">")
  );
  rotations.sort();
  return rotations[0];
}

function mergeNamedObjects(primary: JsonObject[], secondary: JsonValue[], limit: number): JsonObject[] {
  const merged = new Map<string, JsonObject>();
  for (const item of primary) {
    if (typeof item.name === "string") {
      merged.set(item.name, item);
    }
  }
  for (const item of secondary) {
    if (isJsonObject(item) && typeof item.name === "string" && !merged.has(item.name)) {
      merged.set(item.name, item);
    }
  }
  return [...merged.values()].slice(0, limit);
}

function uniqueStrings(values: string[], limit: number): string[] {
  return [...new Set(values.filter((value) => value.trim() !== ""))].sort().slice(0, limit);
}

async function searchWithRipgrep(
  projectRoot: string,
  options: {
    query: string;
    scopePath: string;
    globs: string[];
    offset: number;
    limit: number;
    contextLines: number;
    caseSensitive: boolean;
  },
): Promise<ToolEnvelope | null> {
  if (process.env.GODOT_CODEX_BRIDGE_DISABLE_RG === "1") {
    return null;
  }

  const args = [
    "--json",
    "--fixed-strings",
    "--line-number",
    "--column",
    "--max-columns",
    "400",
    "--max-columns-preview",
    "--context",
    String(options.contextLines),
    "--max-count",
    String(Math.max(options.offset + options.limit + 1, options.limit)),
  ];
  if (!options.caseSensitive) {
    args.push("--ignore-case");
  }
  for (const glob of BLOCKED_GLOBS) {
    args.push("--glob", glob);
  }
  for (const glob of options.globs) {
    args.push("--glob", glob);
  }
  args.push("--", options.query, options.scopePath || ".");

  let stdout = "";
  try {
    const result = await execFileAsync("rg", args, {
      cwd: projectRoot,
      timeout: 5_000,
      maxBuffer: 4 * 1024 * 1024,
      windowsHide: true,
    });
    stdout = result.stdout;
  } catch (error) {
    if (isExecError(error) && error.code === 1) {
      stdout = error.stdout ?? "";
    } else {
      return null;
    }
  }

  const rawMatches: Array<{ relativePath: string; line: number; column: number; preview: string }> = [];
  for (const rawLine of stdout.split(/\r?\n/)) {
    if (!rawLine.trim()) {
      continue;
    }
    let event;
    try {
      event = JSON.parse(rawLine) as JsonObject;
    } catch {
      continue;
    }
    if (event.type !== "match" || !isJsonObject(event.data)) {
      continue;
    }

    const relativePath = rgPathText(event.data);
    const lineNumber = Number(event.data.line_number);
    const lines = isJsonObject(event.data.lines) ? event.data.lines : null;
    const submatches = Array.isArray(event.data.submatches) ? event.data.submatches : [];
    const firstSubmatch = isJsonObject(submatches[0]) ? submatches[0] : null;
    const column = typeof firstSubmatch?.start === "number" ? firstSubmatch.start + 1 : 1;
    if (!relativePath || !Number.isInteger(lineNumber)) {
      continue;
    }

    let resolved;
    try {
      resolved = resolveProjectPath(projectRoot, relativePath);
    } catch {
      continue;
    }
    rawMatches.push({
      relativePath: resolved.relativePath,
      line: lineNumber,
      column,
      preview: truncateLine(typeof lines?.text === "string" ? lines.text : ""),
    });
  }

  const page = rawMatches.slice(options.offset, options.offset + options.limit);
  const matches = await Promise.all(page.map((match) => enrichSearchMatch(projectRoot, match, options.contextLines)));

  return {
    status: "ok",
    awareness_version: "godot-codex-bridge/project-awareness-v1",
    project_root: projectRoot,
    search_engine: "ripgrep",
    match_type: "literal",
    query: options.query,
    case_sensitive: options.caseSensitive,
    offset: options.offset,
    limit: options.limit,
    context_lines: options.contextLines,
    total_matching_at_least: rawMatches.length,
    returned_count: matches.length,
    truncated: options.offset + matches.length < rawMatches.length,
    matches,
    skipped: [],
    excludes: blockedPathPolicy(),
  };
}

async function searchWithNode(
  projectRoot: string,
  options: {
    query: string;
    scopePath: string;
    globs: string[];
    offset: number;
    limit: number;
    contextLines: number;
    caseSensitive: boolean;
  },
): Promise<ToolEnvelope> {
  const index = await buildProjectIndex(projectRoot, { rootPath: options.scopePath });
  const matches: JsonObject[] = [];
  const skipped = [...index.skipped];
  const needle = options.caseSensitive ? options.query : options.query.toLowerCase();
  let seenMatches = 0;
  let truncated = false;

  for (const file of index.files) {
    if (!file.isText || !matchesGlobs(file.relativePath, options.globs)) {
      continue;
    }
    if (file.byteSize > MAX_TEXT_SEARCH_BYTES) {
      pushSkip(skipped, file.relativePath, "search_file_too_large", `Search skips text files over ${MAX_TEXT_SEARCH_BYTES} bytes.`);
      continue;
    }

    const content = await fs.readFile(file.absolutePath, "utf8");
    const lines = content.split(/\r?\n/);
    for (let index = 0; index < lines.length; index += 1) {
      const haystack = options.caseSensitive ? lines[index] : lines[index].toLowerCase();
      const column = haystack.indexOf(needle);
      if (column < 0) {
        continue;
      }

      seenMatches += 1;
      if (seenMatches <= options.offset) {
        continue;
      }
      if (matches.length >= options.limit) {
        truncated = true;
        break;
      }

      matches.push(searchMatchObject(file.relativePath, index + 1, column + 1, lines, options.contextLines));
    }
    if (truncated) {
      break;
    }
  }

  return {
    status: "ok",
    awareness_version: "godot-codex-bridge/project-awareness-v1",
    project_root: projectRoot,
    search_engine: "node_fallback",
    match_type: "literal",
    query: options.query,
    case_sensitive: options.caseSensitive,
    offset: options.offset,
    limit: options.limit,
    context_lines: options.contextLines,
    total_matching_at_least: seenMatches,
    returned_count: matches.length,
    truncated: truncated || index.truncated,
    matches,
    skipped,
    excludes: blockedPathPolicy(),
  };
}

async function enrichSearchMatch(
  projectRoot: string,
  match: { relativePath: string; line: number; column: number; preview: string },
  contextLines: number,
): Promise<JsonObject> {
  const resolved = resolveProjectPath(projectRoot, match.relativePath);
  const content = await fs.readFile(resolved.absolutePath, "utf8");
  const lines = content.split(/\r?\n/);
  return searchMatchObject(match.relativePath, match.line, match.column, lines, contextLines, match.preview);
}

function searchMatchObject(
  relativePath: string,
  line: number,
  column: number,
  lines: string[],
  contextLines: number,
  previewOverride?: string,
): JsonObject {
  const index = line - 1;
  const beforeStart = Math.max(0, index - contextLines);
  const afterEnd = Math.min(lines.length, index + contextLines + 1);
  return {
    path: relativePath,
    res_path: `res://${relativePath}`,
    line,
    column,
    preview: previewOverride ?? truncateLine(lines[index] ?? ""),
    context_before: lines.slice(beforeStart, index).map((text, offset) => ({
      line: beforeStart + offset + 1,
      text: truncateLine(text),
    })),
    context_after: lines.slice(index + 1, afterEnd).map((text, offset) => ({
      line: index + offset + 2,
      text: truncateLine(text),
    })),
  };
}

function rgPathText(data: JsonObject): string | null {
  const pathData = isJsonObject(data.path) ? data.path : null;
  const raw = typeof pathData?.text === "string" ? pathData.text : null;
  if (!raw) {
    return null;
  }
  return raw.replaceAll("\\", "/").replace(/^\.\//, "");
}

function isExecError(error: unknown): error is Error & { code?: number | string; stdout?: string; stderr?: string } {
  return error instanceof Error && ("code" in error || "stdout" in error);
}

async function readBoundedLines(
  absolutePath: string,
  startLine: number,
  maxLines: number,
  maxBytes: number,
): Promise<{
  lines: Array<{ line: number; text: string; truncated?: boolean }>;
  startLine: number;
  endLine: number | null;
  byteCount: number;
  truncatedByLines: boolean;
  truncatedByBytes: boolean;
  moreAfter: boolean;
}> {
  const stream = createReadStream(absolutePath, { encoding: "utf8" });
  const reader = createInterface({ input: stream, crlfDelay: Infinity });
  const lines: Array<{ line: number; text: string; truncated?: boolean }> = [];
  let currentLine = 0;
  let byteCount = 0;
  let truncatedByLines = false;
  let truncatedByBytes = false;
  let moreAfter = false;

  try {
    for await (const line of reader) {
      currentLine += 1;
      if (currentLine < startLine) {
        continue;
      }

      if (lines.length >= maxLines) {
        truncatedByLines = true;
        moreAfter = true;
        break;
      }

      const lineBytes = Buffer.byteLength(line, "utf8") + (lines.length > 0 ? 1 : 0);
      if (byteCount + lineBytes > maxBytes) {
        const remaining = Math.max(0, maxBytes - byteCount - (lines.length > 0 ? 1 : 0));
        if (remaining > 0) {
          const truncated = truncateUtf8(line, remaining);
          lines.push({ line: currentLine, text: truncated, truncated: true });
          byteCount += Buffer.byteLength(truncated, "utf8");
        }
        truncatedByBytes = true;
        moreAfter = true;
        break;
      }

      lines.push({ line: currentLine, text: line });
      byteCount += lineBytes;
    }
  } finally {
    reader.close();
    stream.destroy();
  }

  return {
    lines,
    startLine,
    endLine: lines.length > 0 ? lines[lines.length - 1].line : null,
    byteCount,
    truncatedByLines,
    truncatedByBytes,
    moreAfter,
  };
}

async function collectAgentsFiles(
  projectRoot: string,
  includePreview = false,
): Promise<{ rootAgentsPresent: boolean; files: JsonObject[] }> {
  const index = await buildProjectIndex(projectRoot);
  const agents = index.files
    .filter((file) => path.posix.basename(file.relativePath).toLowerCase() === "agents.md")
    .sort((a, b) => pathDepth(a.relativePath) - pathDepth(b.relativePath) || a.relativePath.localeCompare(b.relativePath));
  const files: JsonObject[] = [];

  for (let i = 0; i < agents.length; i += 1) {
    const file = agents[i];
    const metadata = await fileMetadataWithSmallSha(file);
    const item: JsonObject = {
      ...metadata,
      precedence: i + 1,
      scope_directory: path.posix.dirname(file.relativePath) === "." ? "" : path.posix.dirname(file.relativePath),
    };
    if (includePreview) {
      const preview = await readBoundedLines(file.absolutePath, 1, MAX_AGENTS_PREVIEW_LINES, MAX_AGENTS_PREVIEW_BYTES);
      item.preview = preview.lines.map((line) => line.text).join("\n");
      item.preview_lines = preview.lines.length;
      item.preview_bytes = preview.byteCount;
      item.preview_truncated = preview.truncatedByBytes || preview.truncatedByLines || preview.moreAfter;
    }
    files.push(item);
  }

  return {
    rootAgentsPresent: agents.some((file) => file.relativePath.toLowerCase() === "agents.md"),
    files,
  };
}

function agentsMetadata(file: JsonObject): JsonObject {
  return {
    path: file.path,
    res_path: file.res_path,
    byte_size: file.byte_size,
    sha256: file.sha256,
    precedence: file.precedence,
    scope_directory: file.scope_directory,
  };
}

async function parseSceneFile(projectRoot: string, scenePath: string): Promise<ToolEnvelope> {
  const resolved = resolveProjectPath(projectRoot, scenePath);
  const extension = path.posix.extname(resolved.relativePath).toLowerCase();
  if (![".tscn", ".scn"].includes(extension)) {
    throw new ProjectAwarenessError("not_a_scene_file", "Scene tree parsing supports .tscn text scenes and .scn metadata only.", {
      path: resolved.relativePath,
    });
  }

  const stat = await statProjectFile(resolved.absolutePath);
  const metadata = await indexedFileFromStat(projectRoot, resolved.relativePath, resolved.absolutePath, stat);
  if (!metadata.isText || extension === ".scn") {
    return {
      status: "ok",
      awareness_version: "godot-codex-bridge/project-awareness-v1",
      project_root: projectRoot,
      scene_path: resolved.relativePath,
      scene_res_path: resolved.resPath,
      file: fileMetadata(metadata),
      metadata_only: true,
      readable_text: false,
      node_count: null,
      nodes: [],
      tree: null,
      note: "Binary scene files are returned as metadata only.",
    };
  }
  if (metadata.byteSize > MAX_SCENE_PARSE_BYTES) {
    return {
      status: "ok",
      awareness_version: "godot-codex-bridge/project-awareness-v1",
      project_root: projectRoot,
      scene_path: resolved.relativePath,
      scene_res_path: resolved.resPath,
      file: fileMetadata(metadata),
      metadata_only: true,
      readable_text: true,
      node_count: null,
      nodes: [],
      tree: null,
      note: `Scene exceeds parser byte limit of ${MAX_SCENE_PARSE_BYTES}.`,
    };
  }

  const content = await fs.readFile(resolved.absolutePath, "utf8");
  const parsed = parseTscn(content);
  return {
    status: "ok",
    awareness_version: "godot-codex-bridge/project-awareness-v1",
    project_root: projectRoot,
    scene_path: resolved.relativePath,
    scene_res_path: resolved.resPath,
    file: await fileMetadataWithSmallSha(metadata),
    metadata_only: false,
    readable_text: true,
    node_count: parsed.nodes.length,
    nodes_truncated: parsed.nodesTruncated,
    nodes: parsed.nodes,
    tree: parsed.tree,
    external_resources: parsed.externalResources,
    sub_resource_count: parsed.subResourceCount,
    load_steps: parsed.loadSteps,
    uid: parsed.uid,
  };
}

function parseTscn(content: string): {
  nodes: JsonObject[];
  tree: JsonObject | null;
  externalResources: JsonObject[];
  subResources: JsonObject[];
  subResourceCount: number;
  nodesTruncated: boolean;
  loadSteps: number | null;
  uid: string | null;
} {
  const lines = content.split(/\r?\n/);
  const externalResources = new Map<string, JsonObject>();
  const subResources: JsonObject[] = [];
  const nodes: JsonObject[] = [];
  let currentNode: JsonObject | null = null;
  let subResourceCount = 0;
  let loadSteps: number | null = null;
  let uid: string | null = null;
  let nodesTruncated = false;

  for (const line of lines) {
    const section = /^\[(.*)\]$/.exec(line.trim());
    if (section) {
      currentNode = null;
      const header = section[1];
      const kind = header.split(/\s+/, 1)[0];
      const attrs = parseSectionAttributes(header);
      if (kind === "gd_scene") {
        loadSteps = numberOrNull(attrs.load_steps);
        uid = typeof attrs.uid === "string" ? attrs.uid : null;
      } else if (kind === "ext_resource") {
        const id = typeof attrs.id === "string" ? attrs.id : null;
        if (id) {
          externalResources.set(id, {
            id,
            type: attrs.type ?? null,
            path: attrs.path ?? null,
          });
        }
      } else if (kind === "sub_resource") {
        subResourceCount += 1;
        if (subResources.length < MAX_SCENE_GRAPH_SUB_RESOURCES_PER_SCENE) {
          subResources.push({
            id: typeof attrs.id === "string" ? attrs.id : null,
            type: attrs.type ?? null,
          });
        }
      } else if (kind === "node") {
        if (nodes.length >= MAX_SCENE_NODES) {
          nodesTruncated = true;
          continue;
        }
        const name = typeof attrs.name === "string" ? attrs.name : `Node${nodes.length + 1}`;
        const parent = typeof attrs.parent === "string" ? attrs.parent : null;
        currentNode = {
          name,
          type: attrs.type ?? "Node",
          parent,
          scene_path: nodeScenePath(name, parent, nodes),
          script_path: null,
          script_resource_id: null,
          instance_scene_path: null,
          instance_resource_id: null,
        };
        const headerInstanceId = extResourceId(attrs.instance);
        if (headerInstanceId) {
          currentNode.instance_resource_id = headerInstanceId;
          const resource = externalResources.get(headerInstanceId);
          currentNode.instance_scene_path = typeof resource?.path === "string" ? resource.path : null;
        }
        nodes.push(currentNode);
      }
      continue;
    }

    if (currentNode) {
      const script = /^\s*script\s*=\s*ExtResource\("([^"]+)"\)/.exec(line);
      if (script) {
        currentNode.script_resource_id = script[1];
        const resource = externalResources.get(script[1]);
        currentNode.script_path = typeof resource?.path === "string" ? resource.path : null;
      }
      const instance = /^\s*instance\s*=\s*ExtResource\("([^"]+)"\)/.exec(line);
      if (instance) {
        currentNode.instance_resource_id = instance[1];
        const resource = externalResources.get(instance[1]);
        currentNode.instance_scene_path = typeof resource?.path === "string" ? resource.path : null;
      }
    }
  }

  return {
    nodes,
    tree: sceneNodeTree(nodes),
    externalResources: [...externalResources.values()],
    subResources,
    subResourceCount,
    nodesTruncated,
    loadSteps,
    uid,
  };
}

function extResourceId(value: JsonValue | undefined): string | null {
  if (typeof value !== "string") {
    return null;
  }
  const match = /^ExtResource\("([^"]+)"\)$/.exec(value.trim());
  return match ? match[1] : null;
}

function parseSectionAttributes(header: string): JsonObject {
  const attrs: JsonObject = {};
  const pattern = /([A-Za-z_][A-Za-z0-9_]*)=(?:"([^"]*)"|([^\s]+))/g;
  for (const match of header.matchAll(pattern)) {
    attrs[match[1]] = match[2] ?? match[3] ?? "";
  }
  return attrs;
}

function nodeScenePath(name: string, parent: string | null, existingNodes: JsonObject[]): string {
  if (!parent) {
    return name;
  }
  if (parent === ".") {
    const root = existingNodes.find((node) => typeof node.parent !== "string");
    return root && typeof root.scene_path === "string" ? `${root.scene_path}/${name}` : name;
  }
  const normalizedParent = parent.replace(/^\.\//, "");
  const root = existingNodes.find((node) => typeof node.parent !== "string");
  if (root && typeof root.scene_path === "string" && !normalizedParent.startsWith(String(root.scene_path))) {
    return `${root.scene_path}/${normalizedParent}/${name}`;
  }
  return `${normalizedParent}/${name}`;
}

function sceneNodeTree(nodes: JsonObject[]): JsonObject | null {
  if (nodes.length === 0) {
    return null;
  }

  const byPath = new Map<string, JsonObject>();
  for (const node of nodes) {
    const clone: JsonObject = {
      name: node.name,
      type: node.type,
      scene_path: node.scene_path,
      script_path: node.script_path,
      children: [],
    };
    byPath.set(String(node.scene_path), clone);
  }

  let root = byPath.get(String(nodes[0].scene_path)) ?? null;
  for (const node of nodes.slice(1)) {
    const scenePath = String(node.scene_path);
    const parentPath = scenePath.includes("/") ? scenePath.slice(0, scenePath.lastIndexOf("/")) : "";
    const parent = byPath.get(parentPath);
    const current = byPath.get(scenePath);
    if (parent && current && Array.isArray(parent.children)) {
      parent.children.push(current);
    } else if (root && current && Array.isArray(root.children)) {
      root.children.push(current);
    }
  }
  return root;
}

function collectCurrentScriptPaths(snapshot: JsonObject | null, sceneTree: ToolEnvelope | null): string[] {
  const scripts = new Set<string>();
  for (const selected of arrayAt(snapshot, ["selected_nodes"])) {
    const selectedObject = isJsonObject(selected) ? selected : null;
    addScriptPath(scripts, objectString(selectedObject, ["script_path"]));
    addScriptPath(scripts, objectString(selectedObject, ["node", "script_path"]));
  }
  const sceneRootScript = objectString(snapshot, ["scene_tree", "root", "script_path"]);
  addScriptPath(scripts, sceneRootScript);
  if (sceneTree?.status === "ok" && Array.isArray(sceneTree.nodes)) {
    for (const node of sceneTree.nodes) {
      if (isJsonObject(node)) {
        addScriptPath(scripts, typeof node.script_path === "string" ? node.script_path : null);
      }
    }
  }
  return [...scripts].slice(0, 25);
}

function addScriptPath(paths: Set<string>, value: string | null): void {
  if (value && value.startsWith("res://")) {
    paths.add(value);
  }
}

function currentScenePath(snapshot: JsonObject | null): string | null {
  return objectString(snapshot, ["current_scene", "path"]);
}

function snapshotFromEnvelope(envelope: ToolEnvelope | undefined): JsonObject | null {
  if (!envelope || envelope.status !== "ok" || !isJsonObject(envelope.snapshot)) {
    return null;
  }
  return envelope.snapshot;
}

function parseProjectConfig(text: string | undefined): {
  name: string | null;
  mainScene: string | null;
  autoloads: JsonObject[];
  inputActions: JsonObject[];
} {
  if (!text) {
    return { name: null, mainScene: null, autoloads: [], inputActions: [] };
  }
  return {
    name: parseGodotValue(text, "config/name"),
    mainScene: parseGodotValue(text, "run/main_scene"),
    autoloads: parseProjectAutoloads(text),
    inputActions: parseProjectInputActions(text),
  };
}

function parseGodotValue(text: string, key: string): string | null {
  const escaped = key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = new RegExp(`^${escaped}=([^\\r\\n]+)`, "m").exec(text);
  if (!match) {
    return null;
  }
  return stripQuotes(match[1].trim());
}

function parseProjectAutoloads(text: string): JsonObject[] {
  return parseProjectSection(text, "autoload").map((entry) => {
    const rawPath = stripQuotes(entry.value.trim()).replace(/^\*/, "");
    return {
      name: entry.key,
      path: rawPath,
      singleton: true,
    };
  }).filter((entry) => typeof entry.path === "string" && String(entry.path).startsWith("res://"));
}

function parseProjectInputActions(text: string): JsonObject[] {
  return parseProjectSection(text, "input").map((entry) => ({
    name: entry.key,
    raw: truncateLine(entry.value.trim()),
  }));
}

function parseProjectSection(text: string, sectionName: string): Array<{ key: string; value: string }> {
  const entries: Array<{ key: string; value: string }> = [];
  let currentSection = "";
  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim();
    const sectionMatch = /^\[([^\]]+)\]$/.exec(line);
    if (sectionMatch) {
      currentSection = sectionMatch[1].trim();
      continue;
    }
    if (currentSection !== sectionName || line === "" || line.startsWith(";") || line.startsWith("#")) {
      continue;
    }
    const splitAt = line.indexOf("=");
    if (splitAt <= 0) {
      continue;
    }
    const key = line.slice(0, splitAt).trim();
    const value = line.slice(splitAt + 1).trim();
    if (key) {
      entries.push({ key, value });
    }
  }
  return entries;
}

function stripQuotes(value: string): string {
  return value.startsWith("\"") && value.endsWith("\"") ? value.slice(1, -1) : value;
}

async function safePathExists(projectRoot: string, requestedPath: string): Promise<boolean> {
  try {
    const resolved = resolveProjectPath(projectRoot, requestedPath);
    await fs.access(resolved.absolutePath);
    return true;
  } catch {
    return false;
  }
}

async function readTextIfExists(filePath: string): Promise<string | undefined> {
  try {
    return await fs.readFile(filePath, "utf8");
  } catch {
    return undefined;
  }
}

function normalizeGlobList(value: JsonValue | undefined): string[] {
  if (value === undefined) {
    return [];
  }
  if (!Array.isArray(value)) {
    throw new ProjectAwarenessError("invalid_globs", "globs must be an array of project-relative glob strings.");
  }
  return value.map((item) => {
    if (typeof item !== "string" || item.trim() === "") {
      throw new ProjectAwarenessError("invalid_glob", "Each glob must be a non-empty string.");
    }
    return normalizeSafeGlob(item);
  });
}

function normalizeSafeGlob(value: string): string {
  const raw = value.trim().startsWith("res://") ? value.trim().slice("res://".length) : value.trim();
  if (isAnyAbsolutePath(raw) || raw.includes("\0")) {
    throw new ProjectAwarenessError("invalid_glob", "Globs must be project-relative and must not contain NUL bytes.");
  }
  const normalized = path.posix.normalize(raw.replaceAll("\\", "/"));
  if (normalized === ".." || normalized.startsWith("../") || path.posix.isAbsolute(normalized)) {
    throw new ProjectAwarenessError("glob_traversal_rejected", "Glob traversal outside the project is not allowed.");
  }
  const literalSegments = normalized.split("/").filter((segment) => !segment.includes("*") && !segment.includes("?"));
  const blocked = blockedReasonFor(literalSegments.join("/"));
  if (blocked) {
    throw new ProjectAwarenessError(blocked.code, blocked.message, { glob: value });
  }
  return normalized;
}

function normalizeExtensionSet(value: JsonValue | undefined): Set<string> | null {
  if (value === undefined) {
    return null;
  }
  if (!Array.isArray(value)) {
    throw new ProjectAwarenessError("invalid_extensions", "extensions must be an array.");
  }
  return new Set(value.map((item) => {
    if (typeof item !== "string" || item.trim() === "") {
      throw new ProjectAwarenessError("invalid_extension", "Each extension must be a non-empty string.");
    }
    const extension = item.trim().toLowerCase();
    return extension.startsWith(".") ? extension : `.${extension}`;
  }));
}

function matchesGlobs(relativePath: string, globs: string[]): boolean {
  if (globs.length === 0) {
    return true;
  }
  return globs.some((glob) => globToRegExp(glob).test(relativePath));
}

function globToRegExp(glob: string): RegExp {
  let body = "";
  for (let i = 0; i < glob.length; i += 1) {
    const char = glob[i];
    if (char === "*") {
      if (glob[i + 1] === "*") {
        if (glob[i + 2] === "/") {
          body += "(?:.*/)?";
          i += 2;
        } else {
          body += ".*";
          i += 1;
        }
      } else {
        body += "[^/]*";
      }
    } else if (char === "?") {
      body += "[^/]";
    } else {
      body += escapeRegExp(char);
    }
  }
  const prefix = glob.includes("/") ? "^" : "(^|/)";
  return new RegExp(`${prefix}${body}$`);
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function stringOption(value: JsonValue | undefined, name: string): string {
  if (typeof value !== "string") {
    throw new ProjectAwarenessError(`${name}_required`, `${name} must be a string.`);
  }
  return value;
}

function boundedInt(value: JsonValue | undefined, fallback: number, min: number, max: number): number {
  const raw = value === undefined ? fallback : value;
  const parsed = typeof raw === "number" && Number.isFinite(raw) ? raw : fallback;
  return Math.min(Math.max(Math.trunc(parsed), min), max);
}

function pushSkip(skipped: JsonObject[], pathValue: string, code: string, message: string): void {
  if (skipped.length >= MAX_INDEX_SKIPS) {
    return;
  }
  const safePath = pathValue.toLowerCase().endsWith(".import") ? "*.import" : pathValue;
  skipped.push({
    path: safePath,
    code,
    message,
  });
}

function sha256Buffer(value: Buffer): string {
  return createHash("sha256").update(value).digest("hex");
}

function pathDepth(relativePath: string): number {
  return relativePath.split("/").filter(Boolean).length;
}

function truncateLine(value: string): string {
  return value.length <= 500 ? value : `${value.slice(0, 500)}...`;
}

function truncateUtf8(value: string, maxBytes: number): string {
  if (Buffer.byteLength(value, "utf8") <= maxBytes) {
    return value;
  }
  let low = 0;
  let high = value.length;
  while (low < high) {
    const mid = Math.ceil((low + high) / 2);
    if (Buffer.byteLength(value.slice(0, mid), "utf8") <= maxBytes) {
      low = mid;
    } else {
      high = mid - 1;
    }
  }
  return value.slice(0, low);
}

function objectAt(root: JsonObject | null, keys: string[]): JsonObject | null {
  let current: JsonValue | undefined | null = root;
  for (const key of keys) {
    if (!isJsonObject(current)) {
      return null;
    }
    current = current[key];
  }
  return isJsonObject(current) ? current : null;
}

function arrayAt(root: JsonObject | null, keys: string[]): JsonValue[] {
  let current: JsonValue | undefined | null = root;
  for (const key of keys) {
    if (!isJsonObject(current)) {
      return [];
    }
    current = current[key];
  }
  return Array.isArray(current) ? current : [];
}

function objectString(root: JsonObject | null, keys: string[]): string | null {
  let current: JsonValue | undefined | null = root;
  for (const key of keys) {
    if (!isJsonObject(current)) {
      return null;
    }
    current = current[key];
  }
  return typeof current === "string" ? current : null;
}

function stringAt(root: JsonObject | null, keys: string[]): string | null {
  return objectString(root, keys);
}

function numberOrNull(value: JsonValue | undefined): number | null {
  return typeof value === "number" ? value : typeof value === "string" && value.trim() !== "" ? Number(value) : null;
}
