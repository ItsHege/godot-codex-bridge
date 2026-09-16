import { fileURLToPath } from "node:url";

import { createServerConfig } from "./config.js";
import { getBridgeStatus } from "./status.js";
import type { JsonObject } from "./types.js";

export async function runDoctor(): Promise<JsonObject> {
  const config = createServerConfig();
  const bridgeStatus = await getBridgeStatus(config);
  const checks = isJsonObject(bridgeStatus.checks) ? bridgeStatus.checks : {};
  const requiredPass =
    checks.project_file_exists === true &&
    checks.plugin_cfg_exists === true &&
    checks.godot_executable_exists === true &&
    bridgeStatus.active_editor_detected === true &&
    bridgeStatus.snapshot_fresh === true;

  return {
    status: requiredPass ? "ok" : "error",
    readiness: bridgeStatus.readiness,
    bridge_status: bridgeStatus,
  };
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  runDoctor()
    .then((result) => {
      console.log(JSON.stringify(result, null, 2));
      process.exitCode = result.status === "ok" ? 0 : 1;
    })
    .catch((error) => {
      console.error(JSON.stringify({
        status: "error",
        error: {
          code: "doctor_failed",
          message: error instanceof Error ? error.message : String(error),
        },
      }, null, 2));
      process.exitCode = 1;
    });
}

function isJsonObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
