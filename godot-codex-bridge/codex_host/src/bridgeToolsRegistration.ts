import { existsSync } from "node:fs";
import path from "node:path";
import { productRootFromHost } from "./config.js";
import type { BridgeToolsRegistrationPlan, ProjectSummary } from "./types.js";

export const BRIDGE_MCP_SERVER_NAME = "godot_codex_bridge";

export function buildBridgeToolsRegistrationPlan(project: ProjectSummary): BridgeToolsRegistrationPlan {
  const productRoot = productRootFromHost();
  const mcpServerEntry = path.join(productRoot, "mcp_server", "dist", "src", "index.js");
  const warnings: string[] = [];
  if (!existsSync(mcpServerEntry)) {
    warnings.push(`mcp_server_entry_missing: ${mcpServerEntry}`);
  }

  return {
    serverName: BRIDGE_MCP_SERVER_NAME,
    keyPath: `mcp_servers.${BRIDGE_MCP_SERVER_NAME}`,
    projectRoot: project.projectRoot,
    bridgeDir: project.bridgeDir,
    productRoot,
    mcpServerEntry,
    mcpServerConfig: {
      command: process.execPath,
      args: [mcpServerEntry],
      env: {
        GODOT_CODEX_BRIDGE_PROJECT_ROOT: project.projectRoot,
        GODOT_CODEX_BRIDGE_DIR: project.bridgeDir
      }
    },
    ready: warnings.length === 0,
    existingConfigPresent: false,
    alreadyConfigured: false,
    warnings
  };
}
