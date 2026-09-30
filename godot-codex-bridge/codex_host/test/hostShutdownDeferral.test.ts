import assert from "node:assert/strict";
import test from "node:test";
import { AddonUpdater } from "../src/addonUpdater.js";
import { MockCodexRuntime } from "../src/codexRuntime.js";
import { loadConfig } from "../src/config.js";
import { HostController } from "../src/hostController.js";

class BusyUpdater extends AddonUpdater {
  release!: () => void;
  constructor() {
    super({ platform: "linux" });
    this.running = new Promise<void>((resolve) => { this.release = resolve; });
  }
  override isBusy(): boolean { return true; }
}

test("shutdown waits for a pending addon update and accepts no new work meanwhile", async () => {
  const updater = new BusyUpdater();
  const controller = new HostController(loadConfig(["--runtime", "mock"]), new MockCodexRuntime(), updater);
  let shutdownRequested = false;
  controller.once("shutdownRequested", () => { shutdownRequested = true; });

  const response = await controller.handleRequest({ jsonrpc: "2.0", id: 1, method: "host.shutdown" }) as { deferred_for_addon_update: boolean };
  assert.equal(response.deferred_for_addon_update, true);
  assert.equal(controller.isShuttingDown(), true);
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(shutdownRequested, false, "shutdown must wait for the update");

  await assert.rejects(controller.handleRequest({ jsonrpc: "2.0", id: 2, method: "thread.send", params: { text: "hi" } }), /host_shutting_down/);
  await assert.rejects(controller.handleRequest({ jsonrpc: "2.0", id: 3, method: "addon.update.schedule", params: {} }), /host_shutting_down/);
  assert.ok(await controller.handleRequest({ jsonrpc: "2.0", id: 4, method: "host.health" }));

  updater.release();
  await updater.running;
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(shutdownRequested, true);
  await controller.shutdown();
});
