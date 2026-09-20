import assert from "node:assert/strict";
import path from "node:path";
import test from "node:test";
import { resolveCodexCommand } from "../src/codexCommand.js";

const appData = "C:\\Users\\Test User\\AppData\\Roaming";
const nativeCodex = path.win32.join(appData, "npm/node_modules/@openai/codex/node_modules/@openai/codex-win32-x64/vendor/x86_64-pc-windows-msvc/bin/codex.exe");
const windows = { platform: "win32" as const, arch: "x64", appData, comSpec: "C:\\Windows\\System32\\cmd.exe" };

test("doctor and runtime prefer the same npm native installation over a competing desktop executable", () => {
  const desktop = "C:\\Program Files\\Codex\\codex.exe";
  const installed = new Set([nativeCodex, desktop]);
  const environment = { ...windows, exists: (file: string) => installed.has(file) };
  const doctor = resolveCodexCommand("codex", ["--version"], environment);
  const runtime = resolveCodexCommand("codex", ["app-server", "--listen", "ws://127.0.0.1:49391"], environment);
  assert.equal(doctor.file, nativeCodex);
  assert.equal(runtime.file, doctor.file);
  assert.deepEqual(doctor.args, ["--version"]);
  assert.deepEqual(runtime.args, ["app-server", "--listen", "ws://127.0.0.1:49391"]);
});

test("explicit executable overrides bypass auto-discovery and remain unshelled argument vectors", () => {
  const explicit = "C:\\Custom & Tools\\codex.exe";
  const environment = { ...windows, exists: () => { throw new Error("must not discover another binary"); } };
  assert.deepEqual(resolveCodexCommand(explicit, ["--version"], environment), { file: explicit, args: ["--version"] });
  assert.deepEqual(resolveCodexCommand(explicit, ["app-server", "--listen", "ws://[::1]:49391"], environment), {
    file: explicit, args: ["app-server", "--listen", "ws://[::1]:49391"],
  });
});

test("default Windows fallback uses the same codex shim for version and runtime", () => {
  const environment = { ...windows, exists: () => false };
  assert.deepEqual(resolveCodexCommand("codex", ["--version"], environment), {
    file: windows.comSpec, args: ["/d", "/s", "/c", "codex --version"],
  });
  assert.deepEqual(resolveCodexCommand("codex", ["app-server", "--listen", "ws://[::1]:49391"], environment), {
    file: windows.comSpec, args: ["/d", "/s", "/c", "codex app-server --listen ws://[::1]:49391"],
  });
  assert.throws(() => resolveCodexCommand("codex", ["app-server", "--listen", "ws://127.0.0.1:49391 & arbitrary"], environment), /unsupported_codex_windows_fallback_arguments/);
  assert.throws(() => resolveCodexCommand("codex", ["--version", "& arbitrary"], environment), /unsupported_codex_windows_fallback_arguments/);
});

test("custom Windows batch wrappers fail explicitly rather than interpolating their path", () => {
  for (const wrapper of ["C:\\Custom & Tools\\codex.cmd", "custom.BAT"]) {
    assert.throws(() => resolveCodexCommand(wrapper, ["--version"], { ...windows, exists: () => true }), /native executable.*custom \.cmd\/\.bat wrappers are unsupported/);
  }
});

test("non-Windows commands retain their executable and argument vector", () => {
  assert.deepEqual(resolveCodexCommand("/opt/custom codex", ["--version"], {
    platform: "linux", arch: "x64", exists: () => false,
  }), { file: "/opt/custom codex", args: ["--version"] });
});
