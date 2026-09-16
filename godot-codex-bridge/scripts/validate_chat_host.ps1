param(
  [string] $ProjectRoot = "examples\minimal_3d_project",
  [int] $Port = 49390
)

$ErrorActionPreference = "Stop"

function Resolve-FullPath([string] $PathValue, [string] $BasePath) {
  if ([System.IO.Path]::IsPathRooted($PathValue)) {
    return [System.IO.Path]::GetFullPath($PathValue)
  }
  return [System.IO.Path]::GetFullPath((Join-Path $BasePath $PathValue))
}

$productRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$hostRoot = Join-Path $productRoot "codex_host"
$resolvedProjectRoot = Resolve-FullPath $ProjectRoot $productRoot
$projectFile = Join-Path $resolvedProjectRoot "project.godot"

if (-not (Test-Path -LiteralPath $projectFile)) {
  throw "Godot project.godot not found: $resolvedProjectRoot"
}

Push-Location $hostRoot
$hostProcess = $null
$probePath = Join-Path $hostRoot (".chat-probe-" + [Guid]::NewGuid().ToString("N") + ".mjs")
try {
  npm run build | Write-Output

  $hostProcess = Start-Process `
    -FilePath "node" `
    -ArgumentList @("dist/src/index.js", "--runtime", "mock", "--port", [string]$Port) `
    -WorkingDirectory $hostRoot `
    -WindowStyle Hidden `
    -PassThru

  $healthUri = "http://127.0.0.1:$Port/health"
  $deadline = [DateTime]::UtcNow.AddSeconds(15)
  $health = $null
  while ([DateTime]::UtcNow -lt $deadline) {
    try {
      $health = Invoke-RestMethod -Uri $healthUri -TimeoutSec 1
      break
    } catch {
      Start-Sleep -Milliseconds 250
    }
  }
  if ($null -eq $health) {
    throw "Codex host did not become healthy at $healthUri"
  }

  $probe = @'
import path from 'node:path';
import WebSocket from 'ws';

const port = Number(process.argv[2]);
const projectRoot = process.argv[3];
const bridgeDir = path.join(projectRoot, '.godot', 'godot_codex_bridge');
const socket = new WebSocket(`ws://127.0.0.1:${port}`);
const queue = [];
let done = false;
let backgroundDone = false;
let approvalRequested = null;
let approvalResolved = false;

socket.on('message', raw => {
  const message = JSON.parse(String(raw));
  queue.push(message);
  if (message.method === 'turn.completed') {
    done = true;
  }
  if (message.method === 'background.updated' && message.params?.state === 'completed') {
    backgroundDone = true;
  }
  if (message.method === 'approval.requested') {
    approvalRequested = message.params;
  }
  if (message.method === 'approval.resolved') {
    approvalResolved = true;
  }
});

await new Promise((resolve, reject) => {
  socket.once('open', resolve);
  socket.once('error', reject);
});

async function waitForResponse(id) {
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    const found = queue.find(message => message.id === id);
    if (found) {
      return found;
    }
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  throw new Error(`Timed out waiting for response ${id}`);
}

socket.send(JSON.stringify({
  jsonrpc: '2.0',
  id: 1,
  method: 'project.attach',
  params: { project_root: projectRoot, bridge_dir: bridgeDir }
}));
await waitForResponse(1);

socket.send(JSON.stringify({
  jsonrpc: '2.0',
  id: 2,
  method: 'thread.send',
  params: {
    message: 'Validate Godot Codex chat transport',
    attachments: { context_snapshot: true, selected_nodes: true }
  }
}));

const deadline = Date.now() + 10000;
while (!done && Date.now() < deadline) {
  await new Promise(resolve => setTimeout(resolve, 100));
}

socket.send(JSON.stringify({
  jsonrpc: '2.0',
  id: 3,
  method: 'background.start',
  params: {
    prompt: 'Validate read-only Godot background team transport',
    roles: ['scene_agent', 'script_agent']
  }
}));
await waitForResponse(3);

const backgroundDeadline = Date.now() + 10000;
while (!backgroundDone && Date.now() < backgroundDeadline) {
  await new Promise(resolve => setTimeout(resolve, 100));
}

socket.send(JSON.stringify({
  jsonrpc: '2.0',
  id: 4,
  method: 'thread.send',
  params: {
    message: 'Validate approval flow',
    attachments: { context_snapshot: true }
  }
}));
await waitForResponse(4);

const approvalDeadline = Date.now() + 10000;
while (!approvalRequested && Date.now() < approvalDeadline) {
  await new Promise(resolve => setTimeout(resolve, 100));
}
if (approvalRequested) {
  socket.send(JSON.stringify({
    jsonrpc: '2.0',
    id: 5,
    method: 'approval.respond',
    params: {
      approval_id: approvalRequested.approval_id,
      nonce: approvalRequested.nonce,
      diff_hash: approvalRequested.diff_hash,
      decision: 'approve',
      note: 'validate_chat_host approval smoke'
    }
  }));
  await waitForResponse(5);
}

const approvalResolvedDeadline = Date.now() + 10000;
while (!approvalResolved && Date.now() < approvalResolvedDeadline) {
  await new Promise(resolve => setTimeout(resolve, 100));
}
socket.close();

const summary = {
  ok: done && backgroundDone && Boolean(approvalRequested) && approvalResolved,
  messages: queue.length,
  methods: queue.map(message => message.method ?? `response:${message.id}`)
};
console.log(JSON.stringify(summary, null, 2));
if (!done || !backgroundDone || !approvalRequested || !approvalResolved) {
  process.exit(1);
}
'@
  Set-Content -LiteralPath $probePath -Value $probe -Encoding utf8
  node $probePath $Port $resolvedProjectRoot
  if ($LASTEXITCODE -ne 0) {
    throw "Chat host probe failed with exit code $LASTEXITCODE"
  }
} finally {
  if ($hostProcess -ne $null -and -not $hostProcess.HasExited) {
    Stop-Process -Id $hostProcess.Id -Force
  }
  if (Test-Path -LiteralPath $probePath) {
    Remove-Item -LiteralPath $probePath -Force
  }
  Pop-Location
}
