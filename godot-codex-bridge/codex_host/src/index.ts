import { AppServerRuntime } from "./appServerRuntime.js";
import { loadConfig } from "./config.js";
import { MockCodexRuntime } from "./codexRuntime.js";
import { GodotSocketServer } from "./godotSocketServer.js";
import { HostController } from "./hostController.js";
import { randomBytes } from "node:crypto";

const config = loadConfig();
// Keep the one-launch secrets in Host memory, not in descendants or future
// child processes spawned by the runtime.
delete process.env.GODOT_CODEX_HOST_PAIR_SECRET;
delete process.env.GODOT_CODEX_HOST_LAUNCH_NONCE;
const runtime = config.runtime === "mock"
  ? new MockCodexRuntime()
  : new AppServerRuntime({
      codexBin: config.codexBin,
      host: config.host,
      port: config.appServerPort,
      backpressureLimit: config.backpressureLimit
    });
const controller = new HostController(config, runtime);
const pairingSecret = config.pairingSecret ?? randomBytes(32).toString("hex");
const server = new GodotSocketServer(config.host, config.port, controller, config.launchNonce ?? "", pairingSecret);
let shutdownStarted = false;

await server.start();
if (!config.pairingSecret) {
  process.stderr.write(`Godot Codex Host pairing code: ${pairingSecret}\n`);
}
process.stdout.write(JSON.stringify({
  ok: true,
  host: config.host,
  port: config.port,
  runtime: config.runtime
}) + "\n");

async function shutdown(): Promise<void> {
  if (shutdownStarted) {
    return;
  }
  shutdownStarted = true;
  try {
    // A scheduled addon update installs after the editor closes; keep the Host
    // alive until it has finished (the launcher waits for this).
    await controller.whenAddonUpdateSettled();
    await server.stop();
    await controller.shutdown();
    process.exit(0);
  } catch (error) {
    process.stderr.write(`shutdown_failed: ${(error as Error).message}\n`);
    process.exit(1);
  }
}

controller.once("shutdownRequested", () => void shutdown());
process.on("SIGINT", () => void shutdown());
process.on("SIGTERM", () => void shutdown());

// Only the installation-owned launcher receives this pipe. A closed pipe also
// shuts down app-server children if the launcher exits unexpectedly.
if (config.launchNonce && /^[a-f0-9]{64}$/.test(config.launchNonce)) {
  let input = "";
  process.stdin.setEncoding("utf8");
  process.stdin.on("data", (chunk: string) => {
    input += chunk;
    if (input.length > 512) { input = ""; return; }
    const newline = input.indexOf("\n");
    if (newline < 0) { return; }
    const line = input.slice(0, newline).trim();
    input = input.slice(newline + 1);
    if (line === `STOP ${config.launchNonce}`) { void shutdown(); }
  });
  process.stdin.on("end", () => void shutdown());
}
