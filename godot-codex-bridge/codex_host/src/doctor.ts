import { execFile } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import { loadConfig } from "./config.js";

const execFileAsync = promisify(execFile);

type Finding = {
  id: string;
  status: "ok" | "warning" | "error";
  message: string;
  data?: Record<string, unknown>;
};

async function main(): Promise<void> {
  const config = loadConfig();
  const root = await findPackageRoot(path.dirname(fileURLToPath(import.meta.url)));
  const findings: Finding[] = [];
  let codexCliVersion = "";

  try {
    const codexExecutable = await resolveExecutable(config.codexBin);
    const { stdout } = await runCodexVersion(config.codexBin, codexExecutable);
    codexCliVersion = stdout.trim();
    findings.push({
      id: "codex_cli",
      status: "ok",
      message: codexCliVersion,
      data: { executable: codexExecutable }
    });
  } catch (error) {
    findings.push({
      id: "codex_cli",
      status: "error",
      message: (error as Error).message
    });
  }

  for (const relative of ["schemas/index.ts", "schemas/json/codex_app_server_protocol.schemas.json"]) {
    const filePath = path.join(root, relative);
    const stat = await fs.stat(filePath).catch(() => null);
    findings.push({
      id: `schema:${relative}`,
      status: stat?.isFile() ? "ok" : "error",
      message: stat?.isFile() ? "present" : "missing",
      data: stat?.isFile() ? { bytes: stat.size } : undefined
    });
  }

  findings.push(...await checkSchemaLock(root, codexCliVersion));

  const errorCount = findings.filter((finding) => finding.status === "error").length;
  const result = {
    ok: errorCount === 0,
    config: {
      host: config.host,
      port: config.port,
      runtime: config.runtime,
      appServerPort: config.appServerPort
    },
    findings
  };

  if (process.argv.includes("--json")) {
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  } else {
    for (const finding of findings) {
      process.stdout.write(`${finding.status.toUpperCase()} ${finding.id}: ${finding.message}\n`);
    }
  }

  process.exitCode = errorCount === 0 ? 0 : 1;
}

await main();

async function findPackageRoot(startDir: string): Promise<string> {
  let current = path.resolve(startDir);
  while (true) {
    const packagePath = path.join(current, "package.json");
    const text = await fs.readFile(packagePath, "utf8").catch(() => "");
    if (text.includes("\"name\": \"godot-codex-bridge-codex-host\"")) {
      return current;
    }
    const parent = path.dirname(current);
    if (parent === current) {
      throw new Error(`codex_host package root not found from ${startDir}`);
    }
    current = parent;
  }
}

async function resolveExecutable(command: string): Promise<string> {
  if (path.isAbsolute(command)) {
    return command;
  }

  if (process.platform !== "win32") {
    return command;
  }

  const { stdout } = await execFileAsync("where.exe", [command], { windowsHide: true });
  const candidates = stdout
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);
  return candidates.find((candidate) => candidate.toLowerCase().endsWith(".exe")) ?? candidates[0] ?? command;
}

async function runCodexVersion(command: string, executable: string): Promise<{ stdout: string }> {
  try {
    return await execFileAsync(executable, ["--version"], { windowsHide: true });
  } catch (error) {
    if (process.platform !== "win32" || command !== "codex") {
      throw error;
    }
    const shell = process.env.ComSpec ?? "cmd.exe";
    return execFileAsync(shell, ["/d", "/s", "/c", "codex --version"], { windowsHide: true });
  }
}

async function checkSchemaLock(root: string, codexCliVersion: string): Promise<Finding[]> {
  const lockPath = path.join(root, "schemas", "SCHEMA_LOCK.json");
  const text = await fs.readFile(lockPath, "utf8").catch(() => "");
  if (!text) {
    return [{
      id: "schema_lock",
      status: "error",
      message: "missing schemas/SCHEMA_LOCK.json; run npm run generate:schemas"
    }];
  }

  let lock: {
    codex_cli_version?: string;
    files?: Record<string, { sha256?: string; bytes?: number }>;
  };
  try {
    lock = JSON.parse(text) as typeof lock;
  } catch (error) {
    return [{
      id: "schema_lock",
      status: "error",
      message: `invalid JSON: ${(error as Error).message}`
    }];
  }

  const findings: Finding[] = [{
    id: "schema_lock",
    status: lock.codex_cli_version === codexCliVersion ? "ok" : "error",
    message: lock.codex_cli_version === codexCliVersion
      ? "Codex CLI version locked"
      : `Codex CLI version drift: lock=${lock.codex_cli_version ?? "missing"} current=${codexCliVersion || "unknown"}`
  }];

  for (const [relative, expected] of Object.entries(lock.files ?? {})) {
    const filePath = path.join(root, relative);
    const bytes = await fs.readFile(filePath).catch(() => null);
    if (!bytes) {
      findings.push({
        id: `schema_lock:${relative}`,
        status: "error",
        message: "locked file missing"
      });
      continue;
    }
    const sha256 = crypto.createHash("sha256").update(bytes).digest("hex");
    findings.push({
      id: `schema_lock:${relative}`,
      status: sha256 === expected.sha256 ? "ok" : "error",
      message: sha256 === expected.sha256 ? "hash matches" : "hash drift; regenerate schemas or update lock",
      data: {
        bytes: bytes.byteLength,
        expected_bytes: expected.bytes ?? null
      }
    });
  }

  return findings;
}
