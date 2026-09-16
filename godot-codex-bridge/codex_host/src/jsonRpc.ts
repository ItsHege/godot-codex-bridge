import type { JsonRpcId, JsonRpcResponse } from "./types.js";

export function ok(id: JsonRpcId, result: unknown): JsonRpcResponse {
  return {
    jsonrpc: "2.0",
    id,
    result
  };
}

export function fail(id: JsonRpcId, code: number, message: string, data?: unknown): JsonRpcResponse {
  return {
    jsonrpc: "2.0",
    id,
    error: {
      code,
      message,
      data
    }
  };
}

export function parseMessage(raw: string): unknown {
  try {
    return JSON.parse(raw);
  } catch (error) {
    throw new Error(`invalid_json: ${(error as Error).message}`);
  }
}
