export type JsonPrimitive = string | number | boolean | null;
export type JsonValue = JsonPrimitive | JsonObject | JsonValue[];

export interface JsonObject {
  [key: string]: JsonValue | undefined;
}

export type ToolStatus =
  | "ok"
  | "bridge_unavailable"
  | "timeout"
  | "invalid_request"
  | "not_found"
  | "error";

export interface ToolEnvelope extends JsonObject {
  status: ToolStatus;
  error?: JsonObject;
}

export interface ServerConfig {
  projectRoot: string;
  bridgeDir: string;
  godotExecutable: string;
  addonRequestTimeoutMs: number;
  runSceneTimeoutMs: number;
  hostRpcUrl?: string | null;
}

export interface AddonRequest extends JsonObject {
  protocol_version: "godot-codex-bridge/0.1";
  request_id: string;
  type: string;
  created_at: string;
  payload: JsonObject;
}
