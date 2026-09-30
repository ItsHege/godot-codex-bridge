import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";

export const SCHEMA_LOCK_FILE = "SCHEMA_LOCK.json";

/**
 * Hash every generated file under schemas/ (except the lock itself), keyed by
 * forward-slash relative path. Line endings are normalized so a Windows CRLF
 * checkout and a Linux LF checkout of the same tree hash identically.
 */
export async function hashSchemaTree(schemasDir: string): Promise<Record<string, string>> {
  const hashes: Record<string, string> = {};
  const walk = async (dir: string): Promise<void> => {
    const entries = await fs.readdir(dir, { withFileTypes: true });
    for (const entry of entries) {
      const fullPath = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        await walk(fullPath);
        continue;
      }
      const relative = path.relative(schemasDir, fullPath).split(path.sep).join("/");
      if (!entry.isFile() || relative === SCHEMA_LOCK_FILE) {
        continue;
      }
      const text = (await fs.readFile(fullPath)).toString("utf8").replace(/\r\n/g, "\n");
      hashes[relative] = crypto.createHash("sha256").update(text).digest("hex");
    }
  };
  await walk(schemasDir);
  return Object.fromEntries(Object.entries(hashes).sort(([a], [b]) => a.localeCompare(b)));
}

export type SchemaTreeDrift = { changed: string[]; added: string[]; removed: string[] };

export function compareSchemaTree(expected: Record<string, string>, actual: Record<string, string>): SchemaTreeDrift {
  const drift: SchemaTreeDrift = { changed: [], added: [], removed: [] };
  for (const [file, hash] of Object.entries(expected)) {
    if (!(file in actual)) drift.removed.push(file);
    else if (actual[file] !== hash) drift.changed.push(file);
  }
  for (const file of Object.keys(actual)) {
    if (!(file in expected)) drift.added.push(file);
  }
  return drift;
}
