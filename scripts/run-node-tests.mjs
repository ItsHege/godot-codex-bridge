import { readdir } from "node:fs/promises";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";

const root = resolve(process.argv[2] ?? "dist/test");

async function collectTests(dir) {
  const entries = await readdir(dir, { withFileTypes: true });
  const files = [];

  for (const entry of entries) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...await collectTests(path));
    } else if (entry.isFile() && entry.name.endsWith(".test.js")) {
      files.push(path);
    }
  }

  return files;
}

const files = (await collectTests(root)).sort();

if (files.length === 0) {
  console.error(`No compiled test files found under ${root}`);
  process.exit(1);
}

const result = spawnSync(process.execPath, ["--test", ...files], {
  stdio: "inherit",
  shell: false,
});

if (result.error) {
  console.error(result.error);
  process.exit(1);
}

process.exit(result.status ?? 1);
