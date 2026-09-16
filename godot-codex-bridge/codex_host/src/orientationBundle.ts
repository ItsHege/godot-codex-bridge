import fs from "node:fs/promises";
import path from "node:path";
import type { ProjectSummary, RuntimeToolInventory } from "./types.js";

const ORIENTATION_AGENTS_PREVIEW_BYTES = 4000;
const ORIENTATION_TOTAL_PREVIEW_BYTES = 8000;
const ORIENTATION_SNAPSHOT_MAX_BYTES = 4 * 1024 * 1024;
const ORIENTATION_MAX_CHARS = 24000;
const ORIENTATION_PROJECT_MAP_MAX_CHARS = 6000;

const MAX_OPEN_SCENES = 8;
const MAX_SELECTED_NODES = 12;
const MAX_SCENE_NODES = 40;
const MAX_PROJECT_MAP_FILES = 4000;
const MAX_PROJECT_MAP_SCENES = 16;
const MAX_PROJECT_MAP_SCRIPTS = 20;
const MAX_PROJECT_MAP_RESOURCES = 24;
const MAX_PROJECT_MAP_RECENT_FILES = 10;
const MAX_AUTOLOADS = 12;
const MAX_INPUT_ACTIONS = 16;
const MAX_SCRIPT_SAMPLES = 18;
const MAX_RESOURCE_TYPES = 12;
const MAX_RECENT_OUTPUT = 8;
const MAX_TOOL_NAMES = 20;
const PRIORITY_GODOT_TOOLS = [
  "godot.editor_get_state",
  "godot.editor_focus",
  "godot.open_scene",
  "godot.select_node",
  "godot.inspect_node",
  "godot.open_script",
  "godot.editor_batch",
  "godot.diagnostics_get",
  "godot.diagnostics_clear",
  "godot.list_annotations",
  "godot.get_latest_annotation",
  "godot.get_annotation",
  "godot.set_node_transform",
  "godot.set_node_properties",
  "godot.capture_viewport_screenshot",
  "godot.get_project_overview",
  "godot.search_project_files",
  "godot.read_project_file"
];

type JsonObject = Record<string, unknown>;

export async function buildProjectOrientationBundle(
  project: ProjectSummary,
  toolInventory: RuntimeToolInventory | null
): Promise<string> {
  const lines: string[] = [
    "[Godot Codex Bridge orientation]",
    "Use this bounded local project context before asking the user for file lists or shell commands.",
    `Project root: ${project.projectRoot}`,
    `Project file: ${project.projectFile}`,
    `Bridge dir: ${project.bridgeDir}`,
    `AGENTS files detected: ${project.agentsFiles.length}`
  ];

  appendToolInventory(lines, toolInventory);
  await appendAgentsPreviews(lines, project);
  await appendCompactProjectMap(lines, project);
  await appendContextSnapshotSummary(lines, project);

  lines.push("[/Godot Codex Bridge orientation]");
  return enforceMaxChars(lines.join("\n"), ORIENTATION_MAX_CHARS);
}

async function appendCompactProjectMap(lines: string[], project: ProjectSummary): Promise<void> {
  const map = await buildCompactProjectMap(project);
  const mapLines: string[] = [
    "",
    "[Project map compact]",
    `Budget: ${ORIENTATION_PROJECT_MAP_MAX_CHARS} chars`,
    `Source: host filesystem scan; generated/.import/addon internals excluded`,
  ];

  if (map.status !== "ok") {
    mapLines.push(`Status: ${map.status} (${map.message})`);
    lines.push(...mapLines);
    return;
  }

  mapLines.push(
    `Project name: ${map.projectName ?? "unknown"}`,
    `Main scene: ${map.mainScene ?? "none"}`,
    `Indexed files: ${map.indexedFiles}/${map.scannedFiles}${map.truncated ? " (truncated)" : ""}`,
    `Counts: scenes=${map.scenes.total}, scripts=${map.scripts.total}, resources=${map.resources.total}`,
  );

  if (map.autoloads.length > 0) {
    mapLines.push(`Autoloads: ${map.autoloads.map((item) => `${item.name}->${item.path}`).join(", ")}`);
  }
  if (map.inputActions.length > 0) {
    mapLines.push(`Input actions: ${map.inputActions.map((item) => item.name).join(", ")}`);
  }

  mapLines.push(`Scenes (${map.scenes.items.length}/${map.scenes.total}):`);
  for (const scene of map.scenes.items) {
    const details = [
      `nodes=${scene.nodeCount ?? "?"}`,
      scene.rootType ? `root=${scene.rootType}` : null,
      scene.scriptPaths.length > 0 ? `scripts=${scene.scriptPaths.join(",")}` : null,
      scene.instanceScenePaths.length > 0 ? `instances=${scene.instanceScenePaths.join(",")}` : null,
    ].filter(Boolean).join(" ");
    mapLines.push(`- ${scene.resPath}${details ? ` (${details})` : ""}`);
  }

  mapLines.push(`Scripts (${map.scripts.items.length}/${map.scripts.total}):`);
  for (const script of map.scripts.items) {
    const details = [
      script.className ? `class=${script.className}` : null,
      script.extendsName ? `extends=${script.extendsName}` : null,
      script.signals.length > 0 ? `signals=${script.signals.join(",")}` : null,
    ].filter(Boolean).join(" ");
    mapLines.push(`- ${script.resPath}${details ? ` (${details})` : ""}`);
  }

  if (map.resources.items.length > 0) {
    mapLines.push(`Resources (${map.resources.items.length}/${map.resources.total}): ${map.resources.items.map((item) => `${item.resPath}:${item.kind}`).join(", ")}`);
  }
  if (map.recentFiles.length > 0) {
    mapLines.push("Recent project files:");
    for (const file of map.recentFiles) {
      mapLines.push(`- ${file.resPath} mtime=${file.mtime}`);
    }
  }

  if (map.skipped.length > 0) {
    mapLines.push(`Skipped/generated omitted: ${map.skipped.join(", ")}`);
  }

  lines.push(enforceSectionMaxChars(mapLines.join("\n"), ORIENTATION_PROJECT_MAP_MAX_CHARS));
}

function appendToolInventory(lines: string[], toolInventory: RuntimeToolInventory | null): void {
  if (toolInventory) {
    lines.push(
      `Bridge tools visible: ${toolInventory.available ? "yes" : "no"}`,
      `Bridge MCP server: ${toolInventory.serverName ?? "none"}`,
      `Godot tool count: ${toolInventory.godotToolCount}/${toolInventory.toolCount}`
    );
    if (toolInventory.error) {
      lines.push(`Bridge tools warning: ${singleLine(toolInventory.error)}`);
    }
    if (toolInventory.godotTools.length > 0) {
      lines.push(`Godot tools: ${prioritizedGodotTools(toolInventory.godotTools).slice(0, MAX_TOOL_NAMES).join(", ")}`);
    }
  } else {
    lines.push("Bridge tools visible: unknown");
  }
}

function prioritizedGodotTools(tools: string[]): string[] {
  const seen = new Set<string>();
  const result: string[] = [];
  for (const tool of PRIORITY_GODOT_TOOLS) {
    if (tools.includes(tool) && !seen.has(tool)) {
      result.push(tool);
      seen.add(tool);
    }
  }
  for (const tool of tools) {
    if (!seen.has(tool)) {
      result.push(tool);
      seen.add(tool);
    }
  }
  return result;
}

async function appendAgentsPreviews(lines: string[], project: ProjectSummary): Promise<void> {
  let remainingPreviewBytes = ORIENTATION_TOTAL_PREVIEW_BYTES;
  for (const agentsFile of project.agentsFiles.slice(0, 3)) {
    lines.push(
      "",
      `AGENTS: ${agentsFile.path}`,
      `sha256: ${agentsFile.sha256}`,
      `bytes: ${agentsFile.bytes}`
    );
    if (remainingPreviewBytes <= 0) {
      lines.push("preview: [skipped: preview byte budget exhausted]");
      continue;
    }
    const previewLimit = Math.min(ORIENTATION_AGENTS_PREVIEW_BYTES, remainingPreviewBytes);
    const preview = await readTextPreview(agentsFile.path, previewLimit);
    remainingPreviewBytes -= preview.bytesRead;
    if (preview.text === "") {
      lines.push("preview: [empty or unreadable]");
    } else {
      lines.push("preview:");
      lines.push(preview.text);
      if (preview.truncated) {
        lines.push("[preview truncated]");
      }
    }
  }
}

async function appendContextSnapshotSummary(lines: string[], project: ProjectSummary): Promise<void> {
  const snapshotPath = path.join(project.bridgeDir, "context_snapshot.json");
  const snapshotResult = await readJsonObject(snapshotPath, ORIENTATION_SNAPSHOT_MAX_BYTES);

  lines.push("", "[Godot editor snapshot]");
  if (snapshotResult.status !== "ok") {
    lines.push(`Context snapshot: ${snapshotResult.status} (${snapshotResult.message})`);
    lines.push(`Context snapshot path: ${snapshotPath}`);
    return;
  }

  const snapshot = snapshotResult.value;
  lines.push(
    `Context snapshot: available (${snapshotResult.bytes} bytes)`,
    `Snapshot generated at: ${text(snapshot.generated_at) ?? "unknown"}`,
    `Snapshot protocol: ${text(snapshot.protocol_version) ?? "unknown"}`
  );

  appendProjectSummary(lines, snapshot);
  appendCurrentScene(lines, snapshot);
  appendSelectedNodes(lines, snapshot);
  appendSceneTree(lines, snapshot);
  appendGameplayContext(lines, snapshot);
  appendScriptInventory(lines, snapshot);
  appendResourceStatus(lines, snapshot);
  appendEditorOutput(lines, snapshot);
  appendPerformance(lines, snapshot);
  appendScreenshotSummary(lines, snapshot);
}

function appendProjectSummary(lines: string[], snapshot: JsonObject): void {
  const project = object(snapshot.project);
  if (!project) {
    return;
  }
  lines.push(
    "",
    "[Project]",
    `Name: ${text(project.name) ?? "unknown"}`,
    `Godot version: ${text(project.godot_version) ?? "unknown"}`,
    `Main scene: ${text(project.main_scene) ?? "none"}`,
    `Features: ${strings(project.features, 8).join(", ") || "none"}`
  );
}

function appendCurrentScene(lines: string[], snapshot: JsonObject): void {
  const scene = object(snapshot.current_scene);
  if (!scene) {
    lines.push("", "[Current scene]", "Current scene: unavailable");
    return;
  }
  const root = object(scene.root_node);
  const openScenes = strings(scene.open_scenes, MAX_OPEN_SCENES);
  lines.push(
    "",
    "[Current scene]",
    `Scene path: ${text(scene.path) ?? "none"}`,
    `Scene name: ${text(scene.name) ?? "unknown"}`,
    `Dirty: ${boolText(scene.is_dirty)}`,
    `Root: ${formatNodeRef(root)}`,
    `Open scenes (${countArray(scene.open_scenes)}): ${openScenes.join(", ") || "none"}`
  );
}

function appendSelectedNodes(lines: string[], snapshot: JsonObject): void {
  const selected = selectedNodeObjects(snapshot.selected_nodes);
  lines.push("", "[Selected nodes]", `Selected node count: ${selected.length}`);
  for (const selectedNode of selected.slice(0, MAX_SELECTED_NODES)) {
    const node = object(selectedNode.node) ?? selectedNode;
    const props = array(selectedNode.properties_summary);
    const propPreview = props
      .slice(0, 5)
      .map((prop) => {
        const propObj = object(prop);
        if (!propObj) {
          return null;
        }
        const name = text(propObj.name);
        const value = text(propObj.value_summary, 80);
        return name ? `${name}=${value ?? "null"}` : null;
      })
      .filter((item): item is string => Boolean(item));
    lines.push(`- ${formatNodeRef(node)}${propPreview.length > 0 ? ` props: ${propPreview.join("; ")}` : ""}`);
  }
  if (selected.length > MAX_SELECTED_NODES) {
    lines.push(`- [selected nodes truncated: showing ${MAX_SELECTED_NODES} of ${selected.length}]`);
  }
}

function appendSceneTree(lines: string[], snapshot: JsonObject): void {
  const sceneTree = object(snapshot.scene_tree);
  if (!sceneTree) {
    lines.push("", "[Scene tree]", "Scene tree: unavailable");
    return;
  }
  const root = object(sceneTree.root);
  const nodes = collectSceneNodeLines(root, MAX_SCENE_NODES);
  lines.push(
    "",
    "[Scene tree]",
    `Node count: ${numberText(sceneTree.node_count)}`,
    `Snapshot truncated: ${boolText(sceneTree.truncated)}`,
    `Scene nodes shown: ${nodes.lines.length}${nodes.truncated ? ` (truncated to ${MAX_SCENE_NODES})` : ""}`
  );
  lines.push(...nodes.lines);
}

function appendGameplayContext(lines: string[], snapshot: JsonObject): void {
  const gameplay = object(snapshot.gameplay_context);
  if (!gameplay) {
    return;
  }
  const autoloads = array(gameplay.autoloads);
  const inputActions = array(gameplay.input_actions);
  const customActions = inputActions.filter((item) => object(item)?.built_in === false);
  const actionSample = (customActions.length > 0 ? customActions : inputActions)
    .slice(0, MAX_INPUT_ACTIONS)
    .map((item) => {
      const action = object(item);
      if (!action) {
        return null;
      }
      const name = text(action.name);
      if (!name) {
        return null;
      }
      return `${name}(${numberText(action.event_count)} events${action.built_in === true ? ", built-in" : ""})`;
    })
    .filter((item): item is string => Boolean(item));
  const autoloadSample = autoloads
    .slice(0, MAX_AUTOLOADS)
    .map((item) => {
      const autoload = object(item);
      if (!autoload) {
        return null;
      }
      const name = text(autoload.name);
      const autoloadPath = text(autoload.path);
      return name ? `${name}${autoloadPath ? ` -> ${autoloadPath}` : ""}` : null;
    })
    .filter((item): item is string => Boolean(item));

  lines.push(
    "",
    "[Gameplay context]",
    `Autoloads (${autoloads.length}): ${autoloadSample.join(", ") || "none"}`,
    `Input actions (${inputActions.length}, custom ${customActions.length}): ${actionSample.join(", ") || "none"}`
  );
}

function appendScriptInventory(lines: string[], snapshot: JsonObject): void {
  const inventory = object(snapshot.script_inventory);
  if (!inventory) {
    return;
  }
  const scripts = array(inventory.scripts);
  const samples = scripts
    .slice(0, MAX_SCRIPT_SAMPLES)
    .map((item) => {
      const script = object(item);
      if (!script) {
        return null;
      }
      const scriptPath = text(script.path);
      if (!scriptPath) {
        return null;
      }
      const className = text(script.class_name);
      const extendsName = text(script.extends);
      const functions = array(script.functions).length;
      const exports = array(script.exports).length;
      const bits = [
        className ? `class ${className}` : null,
        extendsName ? `extends ${extendsName}` : null,
        functions > 0 ? `${functions} funcs` : null,
        exports > 0 ? `${exports} exports` : null
      ].filter(Boolean);
      return `${scriptPath}${bits.length > 0 ? ` (${bits.join(", ")})` : ""}`;
    })
    .filter((item): item is string => Boolean(item));
  lines.push(
    "",
    "[Script inventory]",
    `Script count: ${numberText(inventory.script_count)}; truncated: ${boolText(inventory.truncated)}`,
    `Script samples: ${samples.join("; ") || "none"}`
  );
}

function appendResourceStatus(lines: string[], snapshot: JsonObject): void {
  const status = object(snapshot.resource_status);
  if (!status) {
    return;
  }
  const resources = array(status.resources);
  const missing = strings(status.missing_resources, 8);
  const importErrors = array(status.import_errors);
  const typeCounts = new Map<string, number>();
  for (const item of resources) {
    const resource = object(item);
    const typeName = text(resource?.type) ?? "unknown";
    typeCounts.set(typeName, (typeCounts.get(typeName) ?? 0) + 1);
  }
  const typeSummary = [...typeCounts.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, MAX_RESOURCE_TYPES)
    .map(([typeName, count]) => `${typeName}:${count}`);
  lines.push(
    "",
    "[Resource status]",
    `Scan status: ${text(status.scan_status) ?? "unknown"}; resources: ${resources.length}; truncated: ${boolText(status.truncated)}`,
    `Resource types: ${typeSummary.join(", ") || "none"}`,
    `Missing resources (${countArray(status.missing_resources)}): ${missing.join(", ") || "none"}`,
    `Import errors: ${importErrors.length}`
  );
}

function appendEditorOutput(lines: string[], snapshot: JsonObject): void {
  const output = object(snapshot.editor_output);
  if (!output) {
    return;
  }
  const entries = array(output.entries)
    .map((item) => object(item))
    .filter((item): item is JsonObject => Boolean(item));
  const warnings = entries.filter((entry) => text(entry.level) === "warning");
  const errors = entries.filter((entry) => text(entry.level) === "error");
  const relevantEntries = [...warnings, ...errors].slice(-MAX_RECENT_OUTPUT);
  const fallbackEntries = relevantEntries.length > 0 ? relevantEntries : entries.slice(-Math.min(4, MAX_RECENT_OUTPUT));
  lines.push(
    "",
    "[Editor output]",
    `Source: ${text(output.source) ?? "unknown"}; entries: ${entries.length}; warnings: ${warnings.length}; errors: ${errors.length}`
  );
  for (const entry of fallbackEntries) {
    const loc = [text(entry.file), numberText(entry.line)].filter((item) => item !== "unknown").join(":");
    lines.push(`- ${text(entry.level) ?? "info"}: ${text(entry.message, 220) ?? ""}${loc ? ` (${loc})` : ""}`);
  }
}

function appendPerformance(lines: string[], snapshot: JsonObject): void {
  const performance = object(snapshot.performance);
  const monitors = object(performance?.monitors);
  if (!performance || !monitors) {
    return;
  }
  const parts = [
    ["fps", monitors.time_fps],
    ["draw_calls", monitors.render_total_draw_calls_in_frame],
    ["objects", monitors.render_total_objects_in_frame],
    ["primitives", monitors.render_total_primitives_in_frame],
    ["physics_3d_objects", monitors.physics_3d_active_objects],
    ["collision_pairs", monitors.physics_3d_collision_pairs],
    ["navigation_regions", monitors.navigation_region_count]
  ]
    .map(([label, value]) => `${label}=${numberText(value)}`)
    .join(", ");
  lines.push("", "[Performance]", `Status: ${text(performance.status) ?? "unknown"}; ${parts}`);
}

function appendScreenshotSummary(lines: string[], snapshot: JsonObject): void {
  const screenshots = array(snapshot.screenshots);
  if (screenshots.length === 0) {
    return;
  }
  const latest = object(screenshots[0]);
  const artifact = object(latest?.artifact);
  lines.push(
    "",
    "[Screenshots]",
    `Screenshot count: ${screenshots.length}`,
    `Latest: ${text(latest?.screenshot_id) ?? "unknown"} scene=${text(latest?.scene_path) ?? "unknown"} size=${numberText(artifact?.width)}x${numberText(artifact?.height)}`
  );
}

type CompactIndexedFile = {
  relativePath: string;
  resPath: string;
  extension: string;
  kind: "scene" | "script" | "resource" | "image" | "audio" | "shader" | "unknown";
  byteSize: number;
  mtimeMs: number;
  isText: boolean;
};

type CompactProjectMap =
  | { status: "ok";
      projectName: string | null;
      mainScene: string | null;
      scannedFiles: number;
      indexedFiles: number;
      truncated: boolean;
      skipped: string[];
      autoloads: Array<{ name: string; path: string }>;
      inputActions: Array<{ name: string }>;
      scenes: { total: number; items: CompactSceneSummary[] };
      scripts: { total: number; items: CompactScriptSummary[] };
      resources: { total: number; items: Array<{ resPath: string; kind: string }> };
      recentFiles: Array<{ resPath: string; mtime: string }>;
    }
  | { status: "missing" | "unreadable"; message: string };

type CompactSceneSummary = {
  resPath: string;
  nodeCount: number | null;
  rootType: string | null;
  scriptPaths: string[];
  instanceScenePaths: string[];
};

type CompactScriptSummary = {
  resPath: string;
  className: string | null;
  extendsName: string | null;
  signals: string[];
};

async function buildCompactProjectMap(project: ProjectSummary): Promise<CompactProjectMap> {
  const projectFile = path.join(project.projectRoot, "project.godot");
  const projectText = await fs.readFile(projectFile, "utf8").catch(() => null);
  if (projectText === null) {
    return { status: "missing", message: "project.godot not readable" };
  }

  const projectConfig = parseCompactProjectConfig(projectText);
  const index = await scanCompactProjectFiles(project.projectRoot);
  const scenes = index.files.filter((file) => file.kind === "scene");
  const scripts = index.files.filter((file) => file.kind === "script");
  const resources = index.files.filter((file) => ["resource", "image", "audio", "shader"].includes(file.kind));
  const sceneItems = await Promise.all(scenes.slice(0, MAX_PROJECT_MAP_SCENES).map((file) => compactSceneSummary(project.projectRoot, file)));
  const scriptItems = await Promise.all(scripts.slice(0, MAX_PROJECT_MAP_SCRIPTS).map((file) => compactScriptSummary(project.projectRoot, file)));
  const resourceItems = resources
    .slice(0, MAX_PROJECT_MAP_RESOURCES)
    .map((file) => ({ resPath: file.resPath, kind: file.kind }));
  const recentFiles = index.files
    .slice()
    .sort((a, b) => b.mtimeMs - a.mtimeMs || a.relativePath.localeCompare(b.relativePath))
    .slice(0, MAX_PROJECT_MAP_RECENT_FILES)
    .map((file) => ({ resPath: file.resPath, mtime: new Date(file.mtimeMs).toISOString() }));

  return {
    status: "ok",
    projectName: projectConfig.name,
    mainScene: projectConfig.mainScene,
    scannedFiles: index.scannedFiles,
    indexedFiles: index.files.length,
    truncated: index.truncated,
    skipped: index.skipped,
    autoloads: projectConfig.autoloads.slice(0, MAX_AUTOLOADS),
    inputActions: projectConfig.inputActions.slice(0, MAX_INPUT_ACTIONS),
    scenes: { total: scenes.length, items: sceneItems },
    scripts: { total: scripts.length, items: scriptItems },
    resources: { total: resources.length, items: resourceItems },
    recentFiles,
  };
}

async function scanCompactProjectFiles(projectRoot: string): Promise<{
  files: CompactIndexedFile[];
  scannedFiles: number;
  truncated: boolean;
  skipped: string[];
}> {
  const files: CompactIndexedFile[] = [];
  const skipped = new Set<string>();
  let scannedFiles = 0;
  let truncated = false;

  async function walk(directory: string): Promise<void> {
    if (files.length >= MAX_PROJECT_MAP_FILES) {
      truncated = true;
      return;
    }
    let entries: Array<{ name: string; isDirectory(): boolean; isFile(): boolean }>;
    try {
      entries = await fs.readdir(directory, { withFileTypes: true });
    } catch {
      skipped.add("unreadable");
      return;
    }
    entries.sort((a, b) => a.name.localeCompare(b.name));
    for (const entry of entries) {
      if (files.length >= MAX_PROJECT_MAP_FILES) {
        truncated = true;
        return;
      }
      const absolutePath = path.join(directory, entry.name);
      const relativePath = path.relative(projectRoot, absolutePath).replaceAll(path.sep, "/");
      const blocked = compactBlockedReason(relativePath, entry.isDirectory());
      if (blocked) {
        skipped.add(blocked);
        continue;
      }
      if (entry.isDirectory()) {
        await walk(absolutePath);
        continue;
      }
      if (!entry.isFile()) {
        continue;
      }
      scannedFiles += 1;
      const stat = await fs.stat(absolutePath).catch(() => null);
      if (!stat?.isFile()) {
        continue;
      }
      const extension = path.extname(entry.name).toLowerCase();
      files.push({
        relativePath,
        resPath: `res://${relativePath}`,
        extension,
        kind: compactKindForPath(extension),
        byteSize: stat.size,
        mtimeMs: stat.mtimeMs,
        isText: compactTextExtension(extension),
      });
    }
  }

  await walk(projectRoot);
  return {
    files,
    scannedFiles,
    truncated,
    skipped: [...skipped].sort(),
  };
}

async function compactSceneSummary(projectRoot: string, file: CompactIndexedFile): Promise<CompactSceneSummary> {
  if (!file.isText || file.byteSize > 512_000) {
    return { resPath: file.resPath, nodeCount: null, rootType: null, scriptPaths: [], instanceScenePaths: [] };
  }
  const content = await fs.readFile(path.join(projectRoot, file.relativePath), "utf8").catch(() => "");
  const externalResources = new Map<string, string>();
  const scriptPaths: string[] = [];
  const instanceScenePaths: string[] = [];
  let nodeCount = 0;
  let rootType: string | null = null;
  let currentNode = false;

  for (const rawLine of content.split(/\r?\n/)) {
    const line = rawLine.trim();
    const section = /^\[(.*)\]$/.exec(line);
    if (section) {
      currentNode = false;
      const header = section[1];
      const kind = header.split(/\s+/, 1)[0];
      const attrs = parseCompactAttributes(header);
      if (kind === "ext_resource" && typeof attrs.id === "string" && typeof attrs.path === "string") {
        externalResources.set(attrs.id, attrs.path);
      } else if (kind === "node") {
        nodeCount += 1;
        currentNode = true;
        if (nodeCount === 1) {
          rootType = typeof attrs.type === "string" ? attrs.type : "Node";
        }
        const inlineInstance = compactExtResourceId(typeof attrs.instance === "string" ? attrs.instance : null);
        const inlinePath = inlineInstance ? externalResources.get(inlineInstance) : null;
        if (inlinePath?.startsWith("res://") && instanceScenePaths.length < 10) {
          instanceScenePaths.push(inlinePath);
        }
      }
      continue;
    }
    if (!currentNode) {
      continue;
    }
    const scriptMatch = /^\s*script\s*=\s*ExtResource\("([^"]+)"\)/.exec(rawLine);
    if (scriptMatch) {
      const scriptPath = externalResources.get(scriptMatch[1]);
      if (scriptPath?.startsWith("res://") && scriptPaths.length < 10 && !scriptPaths.includes(scriptPath)) {
        scriptPaths.push(scriptPath);
      }
    }
    const instanceMatch = /^\s*instance\s*=\s*ExtResource\("([^"]+)"\)/.exec(rawLine);
    if (instanceMatch) {
      const scenePath = externalResources.get(instanceMatch[1]);
      if (scenePath?.startsWith("res://") && instanceScenePaths.length < 10 && !instanceScenePaths.includes(scenePath)) {
        instanceScenePaths.push(scenePath);
      }
    }
  }

  return { resPath: file.resPath, nodeCount, rootType, scriptPaths, instanceScenePaths };
}

async function compactScriptSummary(projectRoot: string, file: CompactIndexedFile): Promise<CompactScriptSummary> {
  if (!file.isText || file.byteSize > 128_000) {
    return { resPath: file.resPath, className: null, extendsName: null, signals: [] };
  }
  const content = await fs.readFile(path.join(projectRoot, file.relativePath), "utf8").catch(() => "");
  let className: string | null = null;
  let extendsName: string | null = null;
  const signals: string[] = [];
  for (const rawLine of content.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (line === "" || line.startsWith("#")) {
      continue;
    }
    className ??= /^class_name\s+([A-Za-z_][A-Za-z0-9_]*)/.exec(line)?.[1] ?? null;
    extendsName ??= /^extends\s+([A-Za-z_][A-Za-z0-9_./"]*)/.exec(line)?.[1]?.replaceAll("\"", "") ?? null;
    const signal = /^signal\s+([A-Za-z_][A-Za-z0-9_]*)/.exec(line)?.[1];
    if (signal && signals.length < 8 && !signals.includes(signal)) {
      signals.push(signal);
    }
  }
  return { resPath: file.resPath, className, extendsName, signals };
}

function parseCompactProjectConfig(content: string): {
  name: string | null;
  mainScene: string | null;
  autoloads: Array<{ name: string; path: string }>;
  inputActions: Array<{ name: string }>;
} {
  let section = "";
  let name: string | null = null;
  let mainScene: string | null = null;
  const autoloads: Array<{ name: string; path: string }> = [];
  const inputActions: Array<{ name: string }> = [];
  for (const rawLine of content.split(/\r?\n/)) {
    const line = rawLine.trim();
    const sectionMatch = /^\[([^\]]+)\]$/.exec(line);
    if (sectionMatch) {
      section = sectionMatch[1];
      continue;
    }
    if (line === "" || line.startsWith(";") || line.startsWith("#")) {
      continue;
    }
    if (section === "application") {
      name ??= /^config\/name="([^"]+)"/.exec(line)?.[1] ?? null;
      mainScene ??= /^run\/main_scene="([^"]+)"/.exec(line)?.[1] ?? null;
    } else if (section === "autoload") {
      const match = /^([^=]+)="\*?([^"]+)"/.exec(line);
      if (match && autoloads.length < MAX_AUTOLOADS) {
        autoloads.push({ name: match[1].trim(), path: match[2] });
      }
    } else if (section === "input") {
      const action = /^([^=]+)=/.exec(line)?.[1]?.trim();
      if (action && inputActions.length < MAX_INPUT_ACTIONS) {
        inputActions.push({ name: action });
      }
    }
  }
  return { name, mainScene, autoloads, inputActions };
}

function parseCompactAttributes(header: string): Record<string, string> {
  const attrs: Record<string, string> = {};
  const pattern = /([A-Za-z_][A-Za-z0-9_]*)=(?:"([^"]*)"|([^\s]+))/g;
  for (const match of header.matchAll(pattern)) {
    attrs[match[1]] = match[2] ?? match[3] ?? "";
  }
  return attrs;
}

function compactExtResourceId(value: string | null): string | null {
  if (!value) {
    return null;
  }
  return /^ExtResource\("([^"]+)"\)$/.exec(value)?.[1] ?? null;
}

function compactKindForPath(extension: string): CompactIndexedFile["kind"] {
  if (extension === ".tscn" || extension === ".scn") {
    return "scene";
  }
  if (extension === ".gd" || extension === ".cs") {
    return "script";
  }
  if (extension === ".tres" || extension === ".res") {
    return "resource";
  }
  if ([".png", ".jpg", ".jpeg", ".webp", ".svg", ".bmp", ".tga", ".exr"].includes(extension)) {
    return "image";
  }
  if ([".wav", ".ogg", ".mp3"].includes(extension)) {
    return "audio";
  }
  if (extension === ".gdshader" || extension === ".shader") {
    return "shader";
  }
  return "unknown";
}

function compactTextExtension(extension: string): boolean {
  return [".tscn", ".tres", ".gd", ".cs", ".gdshader", ".shader", ".cfg", ".md", ".json", ".txt"].includes(extension);
}

function compactBlockedReason(relativePath: string, isDirectory: boolean): string | null {
  const normalized = relativePath.replaceAll("\\", "/").toLowerCase();
  const segments = normalized.split("/").filter(Boolean);
  const blockedSegments = new Set([".godot", ".git", ".import", "node_modules", "dist", "build", "generated", ".tmp", "tmp"]);
  const segment = segments.find((part) => blockedSegments.has(part));
  if (segment) {
    return `${segment}/`;
  }
  if (normalized === "addons/godot_codex_bridge" || normalized.startsWith("addons/godot_codex_bridge/")) {
    return "addons/godot_codex_bridge/";
  }
  if (!isDirectory && normalized.endsWith(".import")) {
    return "*.import";
  }
  return null;
}

function selectedNodeObjects(value: unknown): JsonObject[] {
  const direct = array(value)
    .map((item) => object(item))
    .filter((item): item is JsonObject => Boolean(item));
  if (direct.length > 0 || Array.isArray(value)) {
    return direct;
  }
  const wrapped = object(value);
  return array(wrapped?.nodes)
    .map((item) => object(item))
    .filter((item): item is JsonObject => Boolean(item));
}

function collectSceneNodeLines(root: JsonObject | null, limit: number): { lines: string[]; truncated: boolean } {
  if (!root) {
    return { lines: ["- [no root node in snapshot]"], truncated: false };
  }
  const lines: string[] = [];
  const queue: Array<{ node: JsonObject; depth: number }> = [{ node: root, depth: 0 }];
  while (queue.length > 0 && lines.length < limit) {
    const current = queue.shift()!;
    const indent = "  ".repeat(Math.min(current.depth, 5));
    lines.push(`${indent}- ${formatNodeRef(current.node)}${nodeTags(current.node)}`);
    for (const child of array(current.node.children)) {
      const childObj = object(child);
      if (childObj) {
        queue.push({ node: childObj, depth: current.depth + 1 });
      }
    }
  }
  return {
    lines,
    truncated: queue.length > 0
  };
}

function nodeTags(node: JsonObject): string {
  const typeName = text(node.type) ?? "";
  const tags = new Set<string>();
  for (const token of ["Camera3D", "Camera2D", "Light3D", "MeshInstance3D", "CollisionShape3D", "NavigationRegion3D", "Sprite2D", "AnimatedSprite2D", "TileMapLayer", "Area2D", "CharacterBody2D", "StaticBody2D"]) {
    if (typeName.includes(token)) {
      tags.add(token);
    }
  }
  const threeD = object(node.three_d);
  for (const key of ["camera", "light", "mesh", "collision_shape", "navigation_region"]) {
    if (threeD && threeD[key] !== undefined && threeD[key] !== null) {
      tags.add(key);
    }
  }
  return tags.size > 0 ? ` [${[...tags].join(", ")}]` : "";
}

function formatNodeRef(node: JsonObject | null): string {
  if (!node) {
    return "none";
  }
  const nodePath = text(node.path) ?? ".";
  const name = text(node.name) ?? "unnamed";
  const typeName = text(node.type) ?? "Node";
  const script = text(node.script_path);
  return `${nodePath} name=${name} type=${typeName}${script ? ` script=${script}` : ""}`;
}

async function readJsonObject(filePath: string, maxBytes: number): Promise<
  | { status: "ok"; value: JsonObject; bytes: number }
  | { status: "missing" | "too_large" | "invalid" | "unreadable"; message: string }
> {
  let stat;
  try {
    stat = await fs.stat(filePath);
  } catch {
    return { status: "missing", message: "context_snapshot.json not found" };
  }
  if (!stat.isFile()) {
    return { status: "unreadable", message: "context_snapshot.json is not a file" };
  }
  if (stat.size > maxBytes) {
    return { status: "too_large", message: `${stat.size} bytes exceeds ${maxBytes} byte orientation limit` };
  }
  try {
    const raw = await fs.readFile(filePath, "utf8");
    const parsed: unknown = JSON.parse(raw);
    const parsedObject = object(parsed);
    if (!parsedObject) {
      return { status: "invalid", message: "snapshot root is not an object" };
    }
    return { status: "ok", value: parsedObject, bytes: Buffer.byteLength(raw) };
  } catch (error) {
    return { status: "invalid", message: (error as Error).message };
  }
}

async function readTextPreview(filePath: string, maxBytes: number): Promise<{ text: string; bytesRead: number; truncated: boolean }> {
  try {
    const buffer = await fs.readFile(filePath);
    const slice = buffer.subarray(0, Math.max(0, maxBytes));
    return {
      text: slice.toString("utf8"),
      bytesRead: slice.byteLength,
      truncated: buffer.byteLength > slice.byteLength
    };
  } catch {
    return {
      text: "",
      bytesRead: 0,
      truncated: false
    };
  }
}

function object(value: unknown): JsonObject | null {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? value as JsonObject
    : null;
}

function array(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function strings(value: unknown, limit: number): string[] {
  return array(value)
    .map((item) => text(item))
    .filter((item): item is string => Boolean(item))
    .slice(0, limit);
}

function text(value: unknown, maxLength = 240): string | null {
  if (value === null || value === undefined) {
    return null;
  }
  if (typeof value !== "string" && typeof value !== "number" && typeof value !== "boolean") {
    return null;
  }
  return singleLine(String(value), maxLength);
}

function singleLine(value: string, maxLength = 240): string {
  const compact = value.replace(/\s+/g, " ").trim();
  if (compact.length <= maxLength) {
    return compact;
  }
  return `${compact.slice(0, Math.max(0, maxLength - 16))}... [truncated]`;
}

function boolText(value: unknown): string {
  return typeof value === "boolean" ? String(value) : "unknown";
}

function numberText(value: unknown): string {
  return typeof value === "number" && Number.isFinite(value) ? String(value) : "unknown";
}

function countArray(value: unknown): number {
  return Array.isArray(value) ? value.length : 0;
}

function enforceMaxChars(value: string, maxChars: number): string {
  if (value.length <= maxChars) {
    return value;
  }
  const marker = "\n[orientation truncated]\n[/Godot Codex Bridge orientation]";
  const endMarker = "\n[/Godot Codex Bridge orientation]";
  const withoutEnd = value.endsWith(endMarker) ? value.slice(0, -endMarker.length) : value;
  return `${withoutEnd.slice(0, Math.max(0, maxChars - marker.length))}${marker}`;
}

function enforceSectionMaxChars(value: string, maxChars: number): string {
  if (value.length <= maxChars) {
    return value;
  }
  const marker = "\n[project map compact truncated]";
  return `${value.slice(0, Math.max(0, maxChars - marker.length))}${marker}`;
}
