import path from "node:path";
import { existsSync } from "node:fs";
import { fileURLToPath } from "node:url";

export type RuntimeKind = "app-server" | "mock";

export type HostConfig = {
  host: string;
  port: number;
  runtime: RuntimeKind;
  codexBin: string;
  appServerPort: number;
  maxReplayEvents: number;
  backpressureLimit: number;
};

function readNumber(name: string, fallback: number): number {
  const raw = process.env[name];
  if (!raw) {
    return fallback;
  }
  const parsed = Number.parseInt(raw, 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function parseRuntime(value: string | undefined): RuntimeKind {
  return value === "mock" ? "mock" : "app-server";
}

export function loadConfig(argv = process.argv.slice(2)): HostConfig {
  const runtimeArg = readArg(argv, "--runtime");
  const portArg = readArg(argv, "--port");
  const appServerPortArg = readArg(argv, "--app-server-port");

  return {
    host: process.env.GODOT_CODEX_HOST_BIND ?? "127.0.0.1",
    port: portArg ? Number.parseInt(portArg, 10) : readNumber("GODOT_CODEX_HOST_PORT", 49390),
    runtime: parseRuntime(runtimeArg ?? process.env.GODOT_CODEX_HOST_RUNTIME),
    codexBin: process.env.GODOT_CODEX_HOST_CODEX_BIN ?? "codex",
    appServerPort: appServerPortArg
      ? Number.parseInt(appServerPortArg, 10)
      : readNumber("GODOT_CODEX_APP_SERVER_PORT", 49391),
    maxReplayEvents: readNumber("GODOT_CODEX_HOST_MAX_REPLAY_EVENTS", 200),
    backpressureLimit: readNumber("GODOT_CODEX_HOST_BACKPRESSURE_LIMIT", 500)
  };
}

export function readArg(argv: string[], name: string): string | undefined {
  const index = argv.indexOf(name);
  if (index >= 0 && index < argv.length - 1) {
    return argv[index + 1];
  }
  const prefix = `${name}=`;
  const inline = argv.find((arg) => arg.startsWith(prefix));
  return inline ? inline.slice(prefix.length) : undefined;
}

export function productRootFromHost(): string {
  const here = path.dirname(fileURLToPath(import.meta.url));
  const candidates = [
    path.resolve(here, "..", ".."),
    path.resolve(here, "..", "..", "..")
  ];
  for (const candidate of candidates) {
    if (
      existsSync(path.join(candidate, "mcp_server")) &&
      existsSync(path.join(candidate, "addons", "godot_codex_bridge"))
    ) {
      return candidate;
    }
  }
  return candidates[0];
}
