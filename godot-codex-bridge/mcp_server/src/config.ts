import fs from "node:fs";
import path from "node:path";

import type { ServerConfig } from "./types.js";

const DEFAULT_ADDON_REQUEST_TIMEOUT_MS = 5_000;
const DEFAULT_RUN_SCENE_TIMEOUT_MS = 15_000;

export interface ConfigOverrides {
  projectRoot?: string;
  bridgeDir?: string;
  godotExecutable?: string;
  addonRequestTimeoutMs?: number;
  runSceneTimeoutMs?: number;
  hostRpcUrl?: string | null;
}

export function createServerConfig(overrides: ConfigOverrides = {}): ServerConfig {
  const projectRoot = normalizePath(
    overrides.projectRoot ??
      envOrArg("GODOT_CODEX_BRIDGE_PROJECT_ROOT", "--project-root") ??
      discoverDefaultProjectRoot(process.cwd()),
  );

  const bridgeDir = normalizePath(
    overrides.bridgeDir ??
      envOrArg("GODOT_CODEX_BRIDGE_DIR", "--bridge-dir") ??
      path.join(projectRoot, ".godot", "godot_codex_bridge"),
  );

  return {
    projectRoot,
    bridgeDir,
    hostRpcUrl:
      overrides.hostRpcUrl ??
      envOrArg("GODOT_CODEX_BRIDGE_HOST_RPC_URL", "--host-rpc-url") ??
      discoverHostRpcUrl(projectRoot),
    godotExecutable: discoverGodotExecutable(
      overrides.godotExecutable ?? envOrArg("GODOT_CODEX_BRIDGE_GODOT_EXECUTABLE", "--godot-executable"),
      projectRoot,
    ),
    addonRequestTimeoutMs: boundedNumber(
      overrides.addonRequestTimeoutMs ??
        numberFromEnvOrArg("GODOT_CODEX_BRIDGE_ADDON_TIMEOUT_MS", "--addon-timeout-ms") ??
        DEFAULT_ADDON_REQUEST_TIMEOUT_MS,
      250,
      30_000,
    ),
    runSceneTimeoutMs: boundedNumber(
      overrides.runSceneTimeoutMs ??
        numberFromEnvOrArg("GODOT_CODEX_BRIDGE_RUN_TIMEOUT_MS", "--run-timeout-ms") ??
        DEFAULT_RUN_SCENE_TIMEOUT_MS,
      1_000,
      60_000,
    ),
  };
}

export function isInsidePath(root: string, candidate: string): boolean {
  const relative = path.relative(normalizePath(root), normalizePath(candidate));
  return relative === "" || (!relative.startsWith("..") && !path.isAbsolute(relative));
}

export function boundedNumber(value: number, min: number, max: number): number {
  if (!Number.isFinite(value)) {
    return min;
  }
  return Math.min(Math.max(Math.trunc(value), min), max);
}

function envOrArg(envName: string, argName: string): string | undefined {
  return process.env[envName] ?? argValue(argName);
}

function numberFromEnvOrArg(envName: string, argName: string): number | undefined {
  const raw = envOrArg(envName, argName);
  if (raw === undefined) {
    return undefined;
  }
  const parsed = Number(raw);
  return Number.isFinite(parsed) ? parsed : undefined;
}

function argValue(name: string): string | undefined {
  const prefix = `${name}=`;
  const inline = process.argv.find((arg) => arg.startsWith(prefix));
  if (inline) {
    return inline.slice(prefix.length);
  }

  const index = process.argv.indexOf(name);
  if (index >= 0 && process.argv[index + 1]) {
    return process.argv[index + 1];
  }

  return undefined;
}

function discoverDefaultProjectRoot(cwd: string): string {
  if (fs.existsSync(path.join(cwd, "project.godot"))) {
    return cwd;
  }

  const fixtureFromPackage = path.resolve(cwd, "..", "examples", "minimal_3d_project");
  if (fs.existsSync(path.join(fixtureFromPackage, "project.godot"))) {
    return fixtureFromPackage;
  }

  return cwd;
}

function normalizePath(value: string): string {
  return path.resolve(value);
}

export function discoverHostRpcUrl(projectRoot: string): string | null {
	const configPath = path.join(projectRoot, "addons", "godot_codex_bridge", "host_config.json");
	if (!fs.existsSync(configPath)) {
		return null;
	}
	try {
		const parsed = JSON.parse(stripUtf8Bom(fs.readFileSync(configPath, "utf8"))) as { port?: unknown; host?: unknown };
		const port = Number(parsed.port);
		if (!Number.isFinite(port) || port <= 0) {
			return null;
		}
		const host = localHostOrNull(parsed.host);
		if (!host) {
			return null;
		}
		return `http://${host}:${Math.trunc(port)}/bridge/request`;
	} catch {
		return null;
	}
}

function stripUtf8Bom(value: string): string {
	return value.charCodeAt(0) === 0xfeff ? value.slice(1) : value;
}

function localHostOrNull(value: unknown): string | null {
	const host = typeof value === "string" && value.trim() !== "" ? value.trim() : "127.0.0.1";
	if (host === "127.0.0.1" || host === "localhost" || host === "::1" || host === "[::1]") {
		return host;
	}
	return null;
}

export function discoverGodotExecutable(explicit?: string, projectRoot?: string): string {
	// 1. Explicit override (from CLI flag --godot-executable or programmatic override)
	if (explicit && explicit.trim() !== "") {
		return normalizePath(explicit.trim());
	}

	// 2. Primary environment variable: GODOT_BIN
	const godotBin = process.env.GODOT_BIN;
	if (godotBin && godotBin.trim() !== "") {
		return normalizePath(godotBin.trim());
	}

	// 3. Project-local config file if present (.godot_bin)
	if (projectRoot) {
		const localBinFile = path.join(projectRoot, ".godot_bin");
		if (fs.existsSync(localBinFile)) {
			try {
				const content = fs.readFileSync(localBinFile, "utf8").trim();
				if (content.length > 0) {
					return normalizePath(content);
				}
			} catch {
				// ignore read error
			}
		}
	}

	// 4. Search PATH for discoverable Godot binaries
	const onPath = findGodotOnPath();
	if (onPath) {
		return onPath;
	}

	// 5. Compatible legacy environment variables: GODOT_EXECUTABLE, GODOT_PATH
	const compatEnv = process.env.GODOT_EXECUTABLE ?? process.env.GODOT_PATH;
	if (compatEnv && compatEnv.trim() !== "") {
		return normalizePath(compatEnv.trim());
	}

	// 6. Actionable default executable name
	return process.platform === "win32" ? "godot.exe" : "godot";
}

export function findGodotOnPath(pathEnv: string | undefined = process.env.PATH): string | null {
	if (!pathEnv) {
		return null;
	}

	const delimiter = process.platform === "win32" ? ";" : ":";
	const candidateNames = process.platform === "win32"
		? ["godot.exe", "godot4.exe", "Godot.exe", "Godot4.exe", "Godot_console.exe"]
		: ["godot", "godot4", "Godot", "Godot4"];

	const dirs = pathEnv.split(delimiter).map((d) => d.trim()).filter(Boolean);
	for (const dir of dirs) {
		for (const name of candidateNames) {
			const candidatePath = path.join(dir, name);
			try {
				if (fs.existsSync(candidatePath)) {
					const stat = fs.statSync(candidatePath);
					if (stat.isFile()) {
						return candidatePath;
					}
				}
			} catch {
				// ignore permission or access errors during scan
			}
		}
	}

	return null;
}
