import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { compareSchemaTree, hashSchemaTree } from "../src/schemaTree.js";

test("schema tree lock detects changed, added and removed generated files", async () => {
  const dir = await fs.mkdtemp(path.join(os.tmpdir(), "gcb-schema-tree-"));
  await fs.mkdir(path.join(dir, "v2"), { recursive: true });
  await fs.writeFile(path.join(dir, "ServerRequest.ts"), "export type A = 1;\n", "utf8");
  await fs.writeFile(path.join(dir, "v2", "Thread.ts"), "export type T = 1;\n", "utf8");
  await fs.writeFile(path.join(dir, "v2", "Old.ts"), "export type O = 1;\n", "utf8");
  await fs.writeFile(path.join(dir, "SCHEMA_LOCK.json"), "{}\n", "utf8");

  const locked = await hashSchemaTree(dir);
  assert.deepEqual(Object.keys(locked), ["ServerRequest.ts", "v2/Old.ts", "v2/Thread.ts"]);
  assert.deepEqual(compareSchemaTree(locked, await hashSchemaTree(dir)), { changed: [], added: [], removed: [] });

  // A CRLF checkout of the same content must not count as drift.
  await fs.writeFile(path.join(dir, "ServerRequest.ts"), "export type A = 1;\r\n", "utf8");
  await fs.writeFile(path.join(dir, "v2", "Thread.ts"), "export type T = 2;\n", "utf8");
  await fs.rm(path.join(dir, "v2", "Old.ts"));
  await fs.writeFile(path.join(dir, "v2", "New.ts"), "export type N = 1;\n", "utf8");

  assert.deepEqual(compareSchemaTree(locked, await hashSchemaTree(dir)), {
    changed: ["v2/Thread.ts"],
    added: ["v2/New.ts"],
    removed: ["v2/Old.ts"],
  });
});
