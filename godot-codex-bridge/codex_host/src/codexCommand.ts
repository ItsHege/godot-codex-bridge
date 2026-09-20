import { existsSync } from "node:fs";
import path from "node:path";

type CommandEnvironment = {
  platform: NodeJS.Platform;
  arch: string;
  appData?: string;
  comSpec?: string;
  exists: (file: string) => boolean;
};

export type CodexCommand = { file: string; args: string[] };

// Doctor and the runtime must inspect and launch the same installation.
export function resolveCodexCommand(
  codexBin: string,
  args: readonly string[],
  environment: CommandEnvironment = {
    platform: process.platform,
    arch: process.arch,
    appData: process.env.APPDATA,
    comSpec: process.env.ComSpec,
    exists: existsSync,
  },
): CodexCommand {
  if (environment.platform !== "win32") {
    return { file: codexBin, args: [...args] };
  }
  if (codexBin !== "codex") {
    if (/\.(?:cmd|bat)$/i.test(codexBin)) {
      throw new Error("GODOT_CODEX_HOST_CODEX_BIN must point to a native executable on Windows; custom .cmd/.bat wrappers are unsupported. Use codex.exe or unset the override.");
    }
    return { file: codexBin, args: [...args] };
  }
  if (environment.appData) {
    const arm64 = environment.arch === "arm64";
    const nativeCodex = path.win32.join(
      environment.appData, "npm", "node_modules", "@openai", "codex", "node_modules", "@openai",
      arm64 ? "codex-win32-arm64" : "codex-win32-x64", "vendor",
      arm64 ? "aarch64-pc-windows-msvc" : "x86_64-pc-windows-msvc", "bin", "codex.exe",
    );
    if (environment.exists(nativeCodex)) {
      return { file: nativeCodex, args: [...args] };
    }
  }

  // npm's default Windows shim needs cmd.exe. Never interpolate a user-supplied
  // executable path or arbitrary argument into its shell command string.
  let command: string;
  if (args.length === 1 && args[0] === "--version") {
    command = "codex --version";
  } else if (args.length === 3 && args[0] === "app-server" && args[1] === "--listen"
    && /^ws:\/\/(?:127\.0\.0\.1|\[::1\]):[0-9]+$/.test(args[2])) {
    command = `codex app-server --listen ${args[2]}`;
  } else {
    throw new Error("unsupported_codex_windows_fallback_arguments");
  }
  return { file: environment.comSpec ?? "cmd.exe", args: ["/d", "/s", "/c", command] };
}
