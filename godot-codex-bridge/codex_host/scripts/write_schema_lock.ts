import { execFile } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import { resolveCodexCommand } from "../src/codexCommand.js";
import { hashSchemaTree } from "../src/schemaTree.js";

const execFileAsync = promisify(execFile);

const packageRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const lockedFiles = [
  "schemas/ServerRequest.ts",
  "schemas/ServerNotification.ts",
  "schemas/json/codex_app_server_protocol.schemas.json",
  "schemas/json/codex_app_server_protocol.v2.schemas.json"
];

const codex = await codexVersion();
const lock = {
  schema_lock_version: 1,
  generated_at: new Date().toISOString(),
  commands: [
    "codex app-server generate-ts --out ./schemas",
    "codex app-server generate-json-schema --out ./schemas/json"
  ],
  codex_cli_version: codex.version,
  files: Object.fromEntries(await Promise.all(lockedFiles.map(async (relativePath) => {
    const absolutePath = path.join(packageRoot, relativePath);
    const bytes = await fs.readFile(absolutePath);
    return [relativePath, {
      bytes: bytes.byteLength,
      sha256: crypto.createHash("sha256").update(bytes).digest("hex")
    }];
  }))),
  // Every generated file, so doctor detects drift outside the core four.
  tree: await hashSchemaTree(path.join(packageRoot, "schemas"))
};

await fs.writeFile(path.join(packageRoot, "schemas", "SCHEMA_LOCK.json"), `${JSON.stringify(lock, null, 2)}\n`, "utf8");

async function codexVersion(): Promise<{ version: string }> {
  const command = resolveCodexCommand(process.env.GODOT_CODEX_HOST_CODEX_BIN ?? "codex", ["--version"]);
  const { stdout } = await execFileAsync(command.file, command.args, { windowsHide: true, timeout: 10_000 });
  return { version: stdout.trim() };
}
