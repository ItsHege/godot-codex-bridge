import fs from "node:fs/promises";
import path from "node:path";

import type { JsonObject, JsonValue, ServerConfig, ToolEnvelope } from "./types.js";

export const HEARTBEAT_STALE_MS = 5_000;
export const SNAPSHOT_STALE_MS = 60_000;

export interface BridgeStatusOptions {
  now?: Date;
}

export async function getBridgeStatus(
  config: ServerConfig,
  options: BridgeStatusOptions = {},
): Promise<ToolEnvelope> {
  const now = options.now ?? new Date();
  const projectFile = path.join(config.projectRoot, "project.godot");
  const addonPath = path.join(config.projectRoot, "addons", "godot_codex_bridge");
  const pluginCfgPath = path.join(addonPath, "plugin.cfg");
  const snapshotPath = path.join(config.bridgeDir, "context_snapshot.json");
  const heartbeatPath = path.join(config.bridgeDir, "heartbeat.json");
  const bridgeStatePath = path.join(config.bridgeDir, "bridge_state.json");

  const [
    projectFileExists,
    addonPathExists,
    pluginCfgExists,
    bridgeDirExists,
    godotExecutableExists,
    projectText,
    pluginCfgText,
    heartbeat,
    bridgeState,
    snapshot,
    heartbeatStat,
    snapshotStat,
    hostHealth,
  ] = await Promise.all([
    pathExists(projectFile),
    pathExists(addonPath),
    pathExists(pluginCfgPath),
    pathExists(config.bridgeDir),
    pathExists(config.godotExecutable),
    readTextIfExists(projectFile),
    readTextIfExists(pluginCfgPath),
    readJsonFileIfExists(heartbeatPath),
    readJsonFileIfExists(bridgeStatePath),
    readJsonFileIfExists(snapshotPath),
    statIfExists(heartbeatPath),
    statIfExists(snapshotPath),
    readHostHealth(config.hostRpcUrl),
  ]);

  const heartbeatAgeMs = ageMs(timestampFromJson(heartbeat) ?? heartbeatStat?.mtime, now);
  const snapshotAgeMs = ageMs(timestampFromJson(snapshot, "generated_at") ?? snapshotStat?.mtime, now);
  const pluginEnabled = detectPluginEnabled(projectText);
  const addonVersion =
    stringOrNull(objectValue(bridgeState, "plugin_version")) ??
    parsePluginCfgValue(pluginCfgText, "version") ??
    null;
  const protocolVersion =
    stringOrNull(objectValue(snapshot, "protocol_version")) ??
    stringOrNull(objectValue(bridgeState, "protocol_version")) ??
    stringOrNull(objectValue(heartbeat, "protocol_version")) ??
    null;
  const bridgeStateActive = objectValue(bridgeState, "addon_active");
  const heartbeatActive = objectValue(heartbeat, "addon_active");
  const activeEditorDetected =
    heartbeatActive === true && heartbeatAgeMs !== null && heartbeatAgeMs <= HEARTBEAT_STALE_MS;
  const staleEditor =
    heartbeatAgeMs !== null &&
    heartbeatAgeMs > HEARTBEAT_STALE_MS &&
    (heartbeatActive === true || bridgeStateActive === true);
  const snapshotFresh = snapshotAgeMs !== null && snapshotAgeMs <= SNAPSHOT_STALE_MS;
  const snapshotSchemaCandidate = isJsonObject(snapshot);
  const hostProjectRoot = stringAt(hostHealth, ["activeProject", "projectRoot"]);
  const hostBridgeDir = stringAt(hostHealth, ["activeProject", "bridgeDir"]);
  const projectIdentity = {
    editorProjectRoot: config.projectRoot,
    hostProjectRoot,
    editorBridgeDir: config.bridgeDir,
    hostBridgeDir,
    hostStatusAvailable: hostHealth !== undefined,
    matches: hostProjectRoot === null ? null : samePath(config.projectRoot, hostProjectRoot),
    bridgeDirMatches: hostBridgeDir === null ? null : samePath(config.bridgeDir, hostBridgeDir),
  };
  const projectMismatch = projectIdentity.matches === false || projectIdentity.bridgeDirMatches === false;

  const checks = {
    project_file_exists: projectFileExists,
    addon_path_exists: addonPathExists,
    plugin_cfg_exists: pluginCfgExists,
    plugin_enabled: pluginEnabled,
    bridge_dir_exists: bridgeDirExists,
    heartbeat_exists: heartbeat !== undefined,
    snapshot_exists: snapshot !== undefined,
    snapshot_schema_candidate: snapshotSchemaCandidate,
    godot_executable_exists: godotExecutableExists,
  };

  return {
    status: "ok",
    project_root: config.projectRoot,
    addon_path: addonPath,
    plugin_cfg_path: pluginCfgPath,
    bridge_dir: config.bridgeDir,
    godot_executable: config.godotExecutable,
    addon_request_transport: transportStatus(config),
    bridge_state_path: bridgeStatePath,
    heartbeat_path: heartbeatPath,
    snapshot_path: snapshotPath,
    protocol_version: protocolVersion,
    addon_version: addonVersion,
    plugin_enabled: pluginEnabled,
    active_editor_detected: activeEditorDetected,
    stale_editor: staleEditor,
    project_mismatch: projectMismatch,
    last_heartbeat_age_ms: heartbeatAgeMs,
    snapshot_age_ms: snapshotAgeMs,
    snapshot_fresh: snapshotFresh,
    project_identity: projectIdentity,
    bridge_state_active: typeof bridgeStateActive === "boolean" ? bridgeStateActive : null,
    checks,
    readiness: readiness(checks, activeEditorDetected, staleEditor, snapshotFresh, projectMismatch),
    recommended_next_action: recommendedNextAction(checks, activeEditorDetected, staleEditor, snapshotFresh, projectMismatch),
  };
}

function transportStatus(config: ServerConfig): JsonObject {
  const hostRpcUrl = config.hostRpcUrl ?? null;
  return {
    preferred: hostRpcUrl ? "host_websocket_rpc" : "file_polling",
    host_rpc_configured: hostRpcUrl !== null,
    host_rpc_url: hostRpcUrl,
    file_polling_fallback: true,
    file_polling_bridge_dir: config.bridgeDir,
  };
}

export function isLiveBridgeStatus(status: ToolEnvelope): boolean {
  const identity = isJsonObject(status.project_identity) ? status.project_identity : null;
  return status.active_editor_detected === true && status.stale_editor !== true && identity?.matches !== false && identity?.bridgeDirMatches !== false;
}

async function pathExists(filePath: string): Promise<boolean> {
  try {
    await fs.access(filePath);
    return true;
  } catch {
    return false;
  }
}

async function statIfExists(filePath: string): Promise<{ mtime: Date } | undefined> {
  try {
    const stat = await fs.stat(filePath);
    return { mtime: stat.mtime };
  } catch {
    return undefined;
  }
}

async function readTextIfExists(filePath: string): Promise<string | undefined> {
  try {
    return await fs.readFile(filePath, "utf8");
  } catch {
    return undefined;
  }
}

async function readJsonFileIfExists(filePath: string): Promise<JsonValue | undefined> {
  const text = await readTextIfExists(filePath);
  if (text === undefined) {
    return undefined;
  }

  try {
    return JSON.parse(text) as JsonValue;
  } catch {
    return undefined;
  }
}

async function readHostHealth(hostRpcUrl: string | null | undefined): Promise<JsonObject | undefined> {
  const healthUrl = hostHealthUrl(hostRpcUrl);
  if (!healthUrl) {
    return undefined;
  }
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 750);
  try {
    const response = await fetch(healthUrl, { method: "GET", signal: controller.signal });
    if (!response.ok) {
      return undefined;
    }
    const parsed = await response.json() as unknown;
    return isJsonObject(parsed) ? parsed : undefined;
  } catch {
    return undefined;
  } finally {
    clearTimeout(timeout);
  }
}

function hostHealthUrl(hostRpcUrl: string | null | undefined): string | null {
  if (!hostRpcUrl) {
    return null;
  }
  try {
    const url = new URL(hostRpcUrl);
    url.pathname = "/health";
    url.search = "";
    url.hash = "";
    return url.toString();
  } catch {
    return null;
  }
}

function detectPluginEnabled(projectText: string | undefined): boolean | null {
  if (projectText === undefined) {
    return null;
  }

  return projectText.includes("res://addons/godot_codex_bridge/plugin.cfg");
}

function parsePluginCfgValue(text: string | undefined, key: string): string | undefined {
  if (text === undefined) {
    return undefined;
  }

  const pattern = new RegExp(`^${key}="([^"]+)"`, "m");
  return pattern.exec(text)?.[1];
}

function timestampFromJson(value: JsonValue | undefined, key = "updated_at"): Date | undefined {
  const raw = objectValue(value, key);
  if (typeof raw !== "string") {
    return undefined;
  }

  const normalized = /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(raw)
    ? `${raw.replace(" ", "T")}Z`
    : raw;
  const date = new Date(normalized);
  return Number.isNaN(date.getTime()) ? undefined : date;
}

function ageMs(date: Date | undefined, now: Date): number | null {
  if (date === undefined) {
    return null;
  }

  return Math.max(0, now.getTime() - date.getTime());
}

function readiness(
  checks: JsonObject,
  activeEditorDetected: boolean,
  staleEditor: boolean,
  snapshotFresh: boolean,
  projectMismatch: boolean,
): string {
  if (checks.project_file_exists !== true) {
    return "wrong_project_root";
  }
  if (projectMismatch) {
    return "project_mismatch";
  }
  if (checks.plugin_cfg_exists !== true) {
    return "addon_not_installed";
  }
  if (checks.plugin_enabled === false) {
    return "addon_not_enabled";
  }
  if (activeEditorDetected && snapshotFresh) {
    return "ready";
  }
  if (staleEditor) {
    return "stale_editor";
  }
  if (checks.heartbeat_exists !== true) {
    return "editor_not_active";
  }
  if (checks.snapshot_exists !== true) {
    return "snapshot_missing";
  }
  return "needs_refresh";
}

function recommendedNextAction(
  checks: JsonObject,
  activeEditorDetected: boolean,
  staleEditor: boolean,
  snapshotFresh: boolean,
  projectMismatch: boolean,
): string {
  if (checks.project_file_exists !== true) {
    return "Point the bridge at a Godot project root that contains project.godot.";
  }
  if (projectMismatch) {
    return "Reconnect Codex Host from this Godot project so tools point at the current editor project.";
  }
  if (checks.plugin_cfg_exists !== true) {
    return "Install the addon into this project with the addon install helper, then reopen Godot.";
  }
  if (checks.plugin_enabled === false) {
    return "Enable Godot Codex Bridge in Godot Project Settings -> Plugins.";
  }
  if (staleEditor) {
    return "Bring the Godot editor window back online or reload the project so heartbeat resumes.";
  }
  if (!activeEditorDetected) {
    return "Open the project in Godot and enable the addon before using addon-backed MCP tools.";
  }
  if (!snapshotFresh) {
    return "Click Refresh Context in the Codex Bridge dock or call an addon refresh request.";
  }
  return "Bridge is ready for read-only context and addon-backed requests.";
}

function objectValue(value: JsonValue | undefined, key: string): JsonValue | undefined {
  return isJsonObject(value) ? value[key] : undefined;
}

function stringOrNull(value: JsonValue | undefined): string | null {
  return typeof value === "string" ? value : null;
}

function stringAt(value: JsonValue | undefined, pathSegments: string[]): string | null {
  let current: JsonValue | undefined = value;
  for (const segment of pathSegments) {
    if (!isJsonObject(current)) {
      return null;
    }
    current = current[segment];
  }
  return typeof current === "string" ? current : null;
}

function samePath(left: string, right: string): boolean {
  const normalizedLeft = path.resolve(left);
  const normalizedRight = path.resolve(right);
  return process.platform === "win32"
    ? normalizedLeft.toLowerCase() === normalizedRight.toLowerCase()
    : normalizedLeft === normalizedRight;
}

function isJsonObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
