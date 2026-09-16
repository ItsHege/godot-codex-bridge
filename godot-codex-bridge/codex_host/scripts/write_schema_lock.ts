import { execFile } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

const packageRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const lockedFiles = [
  "schemas/ServerRequest.ts",
  "schemas/ServerNotification.ts",
  "schemas/json/codex_app_server_protocol.schemas.json",
  "schemas/json/codex_app_server_protocol.v2.schemas.json"
];

const lock = {
  schema_lock_version: 1,
  generated_at: new Date().toISOString(),
  commands: [
    "codex app-server generate-ts --out ./schemas",
    "codex app-server generate-json-schema --out ./schemas/json"
  ],
  codex_cli_version: await codexVersion(),
  files: Object.fromEntries(await Promise.all(lockedFiles.map(async (relativePath) => {
    const absolutePath = path.join(packageRoot, relativePath);
    const bytes = await fs.readFile(absolutePath);
    return [relativePath, {
      bytes: bytes.byteLength,
      sha256: crypto.createHash("sha256").update(bytes).digest("hex")
    }];
  })))
};

await fs.writeFile(path.join(packageRoot, "schemas", "SCHEMA_LOCK.json"), `${JSON.stringify(lock, null, 2)}\n`, "utf8");

async function codexVersion(): Promise<string> {
  try {
    const { stdout } = await execFileAsync("codex", ["--version"], { windowsHide: true });
    return stdout.trim();
  } catch (error) {
    if (process.platform !== "win32") {
      throw error;
    }
    const { stdout } = await execFileAsync(process.env.ComSpec ?? "cmd.exe", ["/d", "/s", "/c", "codex --version"], { windowsHide: true });
    return stdout.trim();
  }
}
