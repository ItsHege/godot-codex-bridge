import { AppServerRuntime } from "./appServerRuntime.js";
import { loadConfig } from "./config.js";
import { MockCodexRuntime } from "./codexRuntime.js";
import { GodotSocketServer } from "./godotSocketServer.js";
import { HostController } from "./hostController.js";

const config = loadConfig();
const runtime = config.runtime === "mock"
  ? new MockCodexRuntime()
  : new AppServerRuntime({
      codexBin: config.codexBin,
      host: config.host,
      port: config.appServerPort,
      backpressureLimit: config.backpressureLimit
    });
const controller = new HostController(config, runtime);
const server = new GodotSocketServer(config.host, config.port, controller);
let shutdownStarted = false;

await server.start();
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
