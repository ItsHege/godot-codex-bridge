import fs from "node:fs/promises";
import path from "node:path";

import { isInsidePath } from "./config.js";
import type { JsonObject, ToolEnvelope } from "./types.js";

const DESKTOP_PLATFORMS = ["windows desktop", "linux", "macos"];
const MOBILE_PLATFORMS = ["android", "ios"];

interface ExportPreset extends JsonObject {
  index: number;
  name: string | null;
  platform: string | null;
  export_path: string | null;
  runnable: boolean | null;
}

export async function checkExportReadiness(projectRoot: string, godotExecutable: string): Promise<ToolEnvelope> {
  const projectFile = path.join(projectRoot, "project.godot");
  const exportPresetsFile = path.join(projectRoot, "export_presets.cfg");
  const findings: JsonObject[] = [];
  const projectText = await readTextIfExists(projectFile);
  const exportPresetsText = await readTextIfExists(exportPresetsFile);
  const projectSettings = projectText ? parseGodotConfig(projectText) : {};
  const presets = exportPresetsText ? parseExportPresets(exportPresetsText) : [];

  if (!projectText) {
    findings.push(finding("error", "project_file_missing", "project.godot was not found in the configured project root."));
  }

  const mainScene = stringOrNull(projectSettings["application/run/main_scene"]);
  if (!mainScene) {
    findings.push(finding("warning", "main_scene_missing", "application/run/main_scene is not configured."));
  } else {
    const mainScenePath = resolveResPath(projectRoot, mainScene);
    if (!mainScenePath || !(await pathExists(mainScenePath))) {
      findings.push(finding("warning", "main_scene_not_found", "Configured main scene does not exist.", { main_scene: mainScene }));
    }
  }

  if (!(await pathExists(godotExecutable))) {
    findings.push(finding("warning", "godot_executable_missing", "Configured Godot executable was not found.", { godot_executable: godotExecutable }));
  }

  if (!exportPresetsText) {
    findings.push(finding("warning", "export_presets_missing", "export_presets.cfg was not found; desktop/mobile exports are not configured."));
  }

  const desktopPresets = presets.filter((preset) => platformMatches(preset.platform, DESKTOP_PLATFORMS));
  const mobilePresets = presets.filter((preset) => platformMatches(preset.platform, MOBILE_PLATFORMS));
  if (exportPresetsText && desktopPresets.length === 0) {
    findings.push(finding("warning", "desktop_export_preset_missing", "No Windows/Linux/macOS export preset was found."));
  }
  if (exportPresetsText && mobilePresets.length === 0) {
    findings.push(finding("info", "mobile_export_preset_missing", "No Android/iOS export preset was found."));
  }

  for (const preset of presets) {
    if (!preset.name) {
      findings.push(finding("warning", "export_preset_name_missing", "Export preset is missing a name.", { preset_index: preset.index }));
    }
    if (!preset.platform) {
      findings.push(finding("warning", "export_preset_platform_missing", "Export preset is missing a platform.", { preset_index: preset.index }));
    }
    if (!preset.export_path) {
      findings.push(finding("info", "export_path_missing", "Export preset has no export_path configured.", { preset_index: preset.index, preset_name: preset.name }));
    }
  }

  return {
    status: "ok",
    readiness_version: "godot-codex-bridge/export-readiness-v1",
    project_root: projectRoot,
    project_file: projectFile,
    export_presets_file: exportPresetsFile,
    godot_executable: godotExecutable,
    project: {
      name: stringOrNull(projectSettings["application/config/name"]),
      main_scene: mainScene,
      main_scene_exists: mainScene ? Boolean(resolveResPath(projectRoot, mainScene) && await pathExists(resolveResPath(projectRoot, mainScene) as string)) : false,
    },
    presets,
    summary: {
      export_presets_count: presets.length,
      desktop_preset_count: desktopPresets.length,
      mobile_preset_count: mobilePresets.length,
      ready_for_pc_export: findings.every((item) => item.severity !== "error") && desktopPresets.length > 0 && Boolean(mainScene),
      ready_for_mobile_export: findings.every((item) => item.severity !== "error") && mobilePresets.length > 0 && Boolean(mainScene),
    },
    findings,
    safe_suggestions: findings.map((item) => ({
      code: item.code,
      suggestion: suggestionFor(item),
      mutation_required: false,
    })),
  };
}

function parseGodotConfig(text: string): Record<string, string | boolean | number> {
  const values: Record<string, string | boolean | number> = {};
  let section = "";
  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith(";") || line.startsWith("#")) {
      continue;
    }
    const sectionMatch = /^\[([^\]]+)\]$/.exec(line);
    if (sectionMatch) {
      section = sectionMatch[1];
      continue;
    }
    const equals = line.indexOf("=");
    if (equals < 0) {
      continue;
    }
    const key = line.slice(0, equals).trim();
    const value = parseGodotValue(line.slice(equals + 1).trim());
    values[section ? `${section}/${key}` : key] = value;
  }
  return values;
}

function parseExportPresets(text: string): ExportPreset[] {
  const sections = parseSections(text);
  const presets: ExportPreset[] = [];
  for (const [sectionName, values] of Object.entries(sections)) {
    const match = /^preset\.(\d+)$/.exec(sectionName);
    if (!match) {
      continue;
    }
    presets.push({
      index: Number(match[1]),
      name: stringOrNull(values.name),
      platform: stringOrNull(values.platform),
      export_path: stringOrNull(values.export_path),
      runnable: typeof values.runnable === "boolean" ? values.runnable : null,
    });
  }
  return presets.sort((a, b) => a.index - b.index);
}

function parseSections(text: string): Record<string, Record<string, string | boolean | number>> {
  const sections: Record<string, Record<string, string | boolean | number>> = {};
  let section = "";
  for (const rawLine of text.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith(";") || line.startsWith("#")) {
      continue;
    }
    const sectionMatch = /^\[([^\]]+)\]$/.exec(line);
    if (sectionMatch) {
      section = sectionMatch[1];
      sections[section] = sections[section] ?? {};
      continue;
    }
    const equals = line.indexOf("=");
    if (equals < 0 || !section) {
      continue;
    }
    sections[section][line.slice(0, equals).trim()] = parseGodotValue(line.slice(equals + 1).trim());
  }
  return sections;
}

function parseGodotValue(raw: string): string | boolean | number {
  if (raw.startsWith('"') && raw.endsWith('"')) {
    return raw.slice(1, -1);
  }
  if (raw === "true") {
    return true;
  }
  if (raw === "false") {
    return false;
  }
  const numberValue = Number(raw);
  return Number.isFinite(numberValue) ? numberValue : raw;
}

function resolveResPath(projectRoot: string, value: string): string | null {
  if (!value.startsWith("res://")) {
    return null;
  }
  const candidate = path.resolve(projectRoot, value.slice("res://".length));
  return isInsidePath(projectRoot, candidate) ? candidate : null;
}

async function readTextIfExists(filePath: string): Promise<string | undefined> {
  try {
    return await fs.readFile(filePath, "utf8");
  } catch {
    return undefined;
  }
}

async function pathExists(filePath: string): Promise<boolean> {
  try {
    await fs.access(filePath);
    return true;
  } catch {
    return false;
  }
}

function platformMatches(platform: string | null, needles: string[]): boolean {
  if (!platform) {
    return false;
  }
  const normalized = platform.toLowerCase();
  return needles.some((needle) => normalized.includes(needle));
}

function finding(severity: string, code: string, message: string, details: JsonObject = {}): JsonObject {
  return { severity, code, message, ...details };
}

function suggestionFor(item: JsonObject): string {
  switch (item.code) {
    case "main_scene_missing":
      return "Set application/run/main_scene in project.godot before export validation.";
    case "export_presets_missing":
      return "Create export presets in Godot's Export dialog for PC and mobile targets you intend to ship.";
    case "desktop_export_preset_missing":
      return "Add a Windows, Linux, or macOS export preset for PC readiness.";
    case "mobile_export_preset_missing":
      return "Add Android or iOS export presets when mobile shipping becomes a target.";
    case "export_path_missing":
      return "Set an export path on the preset before using automated export checks.";
    default:
      return "Review this export readiness finding in Godot before release.";
  }
}

function stringOrNull(value: unknown): string | null {
  return typeof value === "string" && value !== "" ? value : null;
}
