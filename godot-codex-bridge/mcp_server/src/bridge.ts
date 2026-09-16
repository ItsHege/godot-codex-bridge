import { randomUUID } from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";

import { getBridgeStatus, isLiveBridgeStatus } from "./status.js";
import type { AddonRequest, JsonObject, JsonValue, ServerConfig, ToolEnvelope } from "./types.js";

const SNAPSHOT_FILENAMES = [
  "context_snapshot.json",
  "snapshot.json",
  "context.json",
  "latest_context.json",
];

interface HostRpcAttemptResult {
  envelope: ToolEnvelope | null;
  attempt: JsonObject;
}

export class BridgeClient {
  constructor(private readonly config: ServerConfig) {}

  async readSnapshot(): Promise<ToolEnvelope> {
    const snapshotPath = await this.findFirstExisting(SNAPSHOT_FILENAMES);
    if (!snapshotPath) {
      return bridgeUnavailable(this.config, "No context snapshot is available.");
    }

    const parsed = await readJsonFile(snapshotPath);
    if (!isJsonObject(parsed)) {
      return {
        status: "error",
        error: {
          code: "invalid_snapshot",
          message: "Context snapshot is not a JSON object.",
          path: snapshotPath,
        },
      };
    }

    return {
      status: "ok",
      snapshot_path: snapshotPath,
      snapshot: parsed,
    };
  }

  async readSnapshotSection(section: string): Promise<ToolEnvelope> {
    const snapshotResult = await this.readSnapshot();
    if (snapshotResult.status !== "ok") {
      return snapshotResult;
    }

    const snapshot = snapshotResult.snapshot;
    if (!isJsonObject(snapshot)) {
      return {
        status: "error",
        error: { code: "invalid_snapshot", message: "Snapshot payload is invalid." },
      };
    }

    return {
      status: "ok",
      protocol_version: stringOrNull(snapshot.protocol_version),
      generated_at: stringOrNull(snapshot.generated_at),
      project: objectOrNull(snapshot.project),
      [section]: snapshot[section] ?? null,
    };
  }

  async sendAddonRequest(
    type: string,
    payload: JsonObject,
    timeoutMs: number,
    options: { skipHostRpc?: boolean } = {},
  ): Promise<ToolEnvelope> {
    const status = await getBridgeStatus(this.config);
    if (!isLiveBridgeStatus(status)) {
      return {
        ...bridgeUnavailable(this.config, "Godot addon is not live enough to handle requests."),
        bridge_status: status,
      };
    }

    const id = randomUUID();
    const request: AddonRequest = {
      protocol_version: "godot-codex-bridge/0.1",
      request_id: id,
      type,
      created_at: new Date().toISOString(),
      payload,
    };

    const transportAttempts: JsonObject[] = [];
    const hostRpcResult = options.skipHostRpc
      ? {
          envelope: null,
          attempt: {
            transport: "websocket_rpc",
            status: "skipped",
            reason: "file_polling_required",
          },
        }
      : await this.tryHostRpcRequest(request, timeoutMs);
    transportAttempts.push(hostRpcResult.attempt);
    if (hostRpcResult.envelope) {
      return {
        ...hostRpcResult.envelope,
        transport_attempts: transportAttempts,
      };
    }

    const requestsDir = path.join(this.config.bridgeDir, "requests");
    const responsesDir = path.join(this.config.bridgeDir, "responses");
    await fs.mkdir(requestsDir, { recursive: true });
    await fs.mkdir(responsesDir, { recursive: true });

    const fileStartedAt = Date.now();
    const requestPath = path.join(requestsDir, `${id}.json`);
    await fs.writeFile(requestPath, `${JSON.stringify(request, null, 2)}\n`, "utf8");

    const responsePath = await this.waitForResponse(id, timeoutMs);
    if (!responsePath) {
      transportAttempts.push({
        transport: "file_polling",
        status: "timeout",
        latency_ms: Date.now() - fileStartedAt,
        timeout_ms: timeoutMs,
        request_path: requestPath,
      });
      return {
        status: "timeout",
        transport: "file_polling",
        transport_attempts: transportAttempts,
        fallback_reason: fallbackReason(hostRpcResult.attempt),
        request_id: id,
        request_path: requestPath,
        error: {
          code: "addon_request_timeout",
          message: `Timed out waiting ${timeoutMs}ms for Godot addon response.`,
        },
      };
    }

    const response = await readJsonFile(responsePath);
    if (!isJsonObject(response)) {
      transportAttempts.push({
        transport: "file_polling",
        status: "failed",
        latency_ms: Date.now() - fileStartedAt,
        request_path: requestPath,
        response_path: responsePath,
        error: {
          code: "invalid_addon_response",
          message: "Addon response is not a JSON object.",
        },
      });
      return {
        status: "error",
        transport: "file_polling",
        transport_attempts: transportAttempts,
        fallback_reason: fallbackReason(hostRpcResult.attempt),
        request_id: id,
        response_path: responsePath,
        error: {
          code: "invalid_addon_response",
          message: "Addon response is not a JSON object.",
        },
      };
    }

    transportAttempts.push({
      transport: "file_polling",
      status: "succeeded",
      latency_ms: Date.now() - fileStartedAt,
      request_path: requestPath,
      response_path: responsePath,
    });
    return {
      status: isSuccessfulAddonStatus(response.status) ? "ok" : "error",
      transport: "file_polling",
      transport_attempts: transportAttempts,
      fallback_reason: fallbackReason(hostRpcResult.attempt),
      request_id: id,
      request_path: requestPath,
      response_path: responsePath,
      response,
    };
  }

  private async tryHostRpcRequest(request: AddonRequest, timeoutMs: number): Promise<HostRpcAttemptResult> {
    const url = this.config.hostRpcUrl;
    if (!url) {
      return {
        envelope: null,
        attempt: {
          transport: "websocket_rpc",
          status: "skipped",
          reason: "host_rpc_not_configured",
        },
      };
    }
    const startedAt = Date.now();
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), Math.min(Math.max(timeoutMs, 250), 30_000));
    try {
      const response = await fetch(url, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          project_root: this.config.projectRoot,
          bridge_dir: this.config.bridgeDir,
          timeout_ms: timeoutMs,
          request,
        }),
        signal: controller.signal,
      });
      if (!response.ok) {
        const error = await responseError(response);
        return {
          envelope: null,
          attempt: {
            transport: "websocket_rpc",
            status: "failed",
            host_rpc_url: url,
            http_status: response.status,
            latency_ms: Date.now() - startedAt,
            error,
          },
        };
      }
      const parsed = await response.json() as unknown;
      if (!isJsonObject(parsed) || parsed.status !== "ok" || !isJsonObject(parsed.response)) {
        return {
          envelope: null,
          attempt: {
            transport: "websocket_rpc",
            status: "failed",
            host_rpc_url: url,
            http_status: response.status,
            latency_ms: Date.now() - startedAt,
            error: {
              code: "host_rpc_invalid_response",
              message: "Host RPC response was not an ok envelope with an addon response object.",
            },
          },
        };
      }
      const addonResponse = parsed.response;
      return {
        envelope: {
          status: isSuccessfulAddonStatus(addonResponse.status) ? "ok" : "error",
          transport: "websocket_rpc",
          request_id: request.request_id,
          response: addonResponse,
        },
        attempt: {
          transport: "websocket_rpc",
          status: "succeeded",
          host_rpc_url: url,
          http_status: response.status,
          latency_ms: Date.now() - startedAt,
        },
      };
    } catch (error) {
      return {
        envelope: null,
        attempt: {
          transport: "websocket_rpc",
          status: "failed",
          host_rpc_url: url,
          latency_ms: Date.now() - startedAt,
          error: {
            code: error instanceof DOMException && error.name === "AbortError" ? "host_rpc_timeout" : "host_rpc_unavailable",
            message: error instanceof Error ? error.message : String(error),
          },
        },
      };
    } finally {
      clearTimeout(timeout);
    }
  }

  private async findFirstExisting(filenames: string[]): Promise<string | undefined> {
    for (const filename of filenames) {
      const candidate = path.join(this.config.bridgeDir, filename);
      try {
        await fs.access(candidate);
        return candidate;
      } catch {
        // Try the next supported bridge filename.
      }
    }

    return undefined;
  }

  private async waitForResponse(id: string, timeoutMs: number): Promise<string | undefined> {
    const deadline = Date.now() + timeoutMs;
    const candidates = [
      path.join(this.config.bridgeDir, "responses", `${id}.json`),
      path.join(this.config.bridgeDir, "responses", `${id}.response.json`),
    ];

    while (Date.now() <= deadline) {
      for (const candidate of candidates) {
        try {
          await fs.access(candidate);
          return candidate;
        } catch {
          // Keep polling until timeout.
        }
      }

      await sleep(100);
    }

    return undefined;
  }
}

export function bridgeUnavailable(config: ServerConfig, message: string): ToolEnvelope {
  return {
    status: "bridge_unavailable",
    bridge_dir: config.bridgeDir,
    error: {
      code: "bridge_unavailable",
      message,
      expected_snapshot: path.join(config.bridgeDir, "context_snapshot.json"),
    },
  };
}

export function isJsonObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

async function readJsonFile(filePath: string): Promise<JsonValue> {
  const text = await fs.readFile(filePath, "utf8");
  return JSON.parse(text) as JsonValue;
}

function stringOrNull(value: JsonValue | undefined): string | null {
  return typeof value === "string" ? value : null;
}

function objectOrNull(value: JsonValue | undefined): JsonObject | null {
  return isJsonObject(value) ? value : null;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function isSuccessfulAddonStatus(status: unknown): boolean {
  return status === "ok" || status === "completed" || status === "succeeded";
}

async function responseError(response: Response): Promise<JsonObject> {
  try {
    const parsed = await response.json() as unknown;
    if (isJsonObject(parsed) && isJsonObject(parsed.error)) {
      return {
        code: typeof parsed.error.code === "string" ? parsed.error.code : `host_rpc_http_${response.status}`,
        message: typeof parsed.error.message === "string" ? parsed.error.message : response.statusText,
      };
    }
  } catch {
    // Fall through to the HTTP status summary.
  }
  return {
    code: `host_rpc_http_${response.status}`,
    message: response.statusText || `Host RPC returned HTTP ${response.status}.`,
  };
}

function fallbackReason(attempt: JsonObject): string {
  if (attempt.status === "skipped") {
    return typeof attempt.reason === "string" ? attempt.reason : "host_rpc_skipped";
  }
  const error = isJsonObject(attempt.error) ? attempt.error : undefined;
  if (typeof error?.code === "string") {
    return error.code;
  }
  if (typeof attempt.http_status === "number") {
    return `host_rpc_http_${attempt.http_status}`;
  }
  return "host_rpc_unavailable";
}
