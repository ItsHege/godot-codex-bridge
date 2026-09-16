param(
  [string] $ProjectRoot = "examples\minimal_3d_project",
  [int] $Port = 49394,
  [int] $AppServerPort = 49395,
  [int] $TimeoutSeconds = 420,
  [string[]] $Roles = @("scene_agent"),
  [switch] $RequireSceneContext
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
$bridgeDir = Join-Path $resolvedProjectRoot ".godot\godot_codex_bridge"
$artifactsDir = Join-Path $bridgeDir "artifacts"
$reportPath = Join-Path $artifactsDir "real_app_server_background_validation.json"

if (-not (Test-Path -LiteralPath $projectFile)) {
  throw "Godot project.godot not found: $resolvedProjectRoot"
}

New-Item -ItemType Directory -Force -Path $artifactsDir | Out-Null

$expectedScenePath = $null
if ($RequireSceneContext) {
  $snapshotPath = Join-Path $bridgeDir "context_snapshot.json"
  if (-not (Test-Path -LiteralPath $snapshotPath)) {
    throw "RequireSceneContext was set, but context_snapshot.json does not exist: $snapshotPath"
  }
  try {
    $snapshot = Get-Content -Raw -LiteralPath $snapshotPath | ConvertFrom-Json
    if ($snapshot.current_scene -ne $null -and -not [string]::IsNullOrWhiteSpace([string]$snapshot.current_scene.path)) {
      $expectedScenePath = [string]$snapshot.current_scene.path
    } elseif ($snapshot.project -ne $null -and -not [string]::IsNullOrWhiteSpace([string]$snapshot.project.main_scene)) {
      $expectedScenePath = [string]$snapshot.project.main_scene
    }
  } catch {
    throw "Failed to read current scene from context_snapshot.json: $($_.Exception.Message)"
  }
  if ([string]::IsNullOrWhiteSpace($expectedScenePath)) {
    throw "RequireSceneContext was set, but no current/main scene path was found in context_snapshot.json."
  }
}

Push-Location $hostRoot
$hostProcess = $null
$probePath = Join-Path $hostRoot (".real-background-probe-" + [Guid]::NewGuid().ToString("N") + ".mjs")
try {
  npm run build | Write-Output

  $hostProcess = Start-Process `
    -FilePath "node" `
    -ArgumentList @("dist/src/index.js", "--runtime", "app-server", "--port", [string]$Port, "--app-server-port", [string]$AppServerPort) `
    -WorkingDirectory $hostRoot `
    -WindowStyle Hidden `
    -PassThru

  $healthUri = "http://127.0.0.1:$Port/health"
  $deadline = [DateTime]::UtcNow.AddSeconds(30)
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

  $rolesJson = ConvertTo-Json -Compress -InputObject $Roles
  $rolesBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($rolesJson))
  $probe = @'
import fs from 'node:fs/promises';
import path from 'node:path';
import WebSocket from 'ws';

const port = Number(process.argv[2]);
const projectRoot = process.argv[3];
const reportPath = process.argv[4];
const timeoutSeconds = Number(process.argv[5]);
const roles = JSON.parse(Buffer.from(process.argv[6], 'base64').toString('utf8'));
const requireSceneContext = process.argv[7] === 'true';
const expectedScenePath = process.argv[8] ?? '';
const agentsMarker = 'GCB_FIXTURE_AGENTS_LOADED';
const sceneMarker = 'GCB_BACKGROUND_SCENE_CONTEXT_LOADED';
const bridgeDir = path.join(projectRoot, '.godot', 'godot_codex_bridge');
const socket = new WebSocket(`ws://127.0.0.1:${port}`);
const queue = [];
let finalTask = null;

socket.on('message', raw => {
  const message = JSON.parse(String(raw));
  queue.push(message);
  if (message.method === 'background.updated') {
    finalTask = message.params;
  }
});

await new Promise((resolve, reject) => {
  socket.once('open', resolve);
  socket.once('error', reject);
});

async function waitForResponse(id, ms = 30000) {
  const deadline = Date.now() + ms;
  while (Date.now() < deadline) {
    const found = queue.find(message => message.id === id);
    if (found) {
      return found;
    }
    await new Promise(resolve => setTimeout(resolve, 100));
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
    method: 'background.start',
  params: {
    prompt: [
      `Real app-server smoke: perform a very short read-only Godot project review and answer in one concise paragraph.`,
      `If project AGENTS.md instructions are loaded, include marker ${agentsMarker}.`,
      requireSceneContext ? `If current scene context is visible in the Godot Codex Bridge orientation, include marker ${sceneMarker} and include this exact scene path: ${expectedScenePath}` : ''
    ].filter(Boolean).join(' '),
    roles
  }
}));
const started = await waitForResponse(2);

const deadline = Date.now() + timeoutSeconds * 1000;
while (Date.now() < deadline) {
  if (finalTask && ['completed', 'failed', 'cancelled'].includes(finalTask.state)) {
    break;
  }
  await new Promise(resolve => setTimeout(resolve, 250));
}
socket.close();

const evidenceText = JSON.stringify(finalTask ?? {});
const agentsMarkerSeen = evidenceText.includes(agentsMarker);
const sceneMarkerSeen = evidenceText.includes(sceneMarker);
const expectedScenePathSeen = expectedScenePath !== '' && evidenceText.includes(expectedScenePath);
const result = {
  ok: Boolean(
    finalTask &&
    finalTask.state === 'completed' &&
    agentsMarkerSeen &&
    (!requireSceneContext || (sceneMarkerSeen && expectedScenePathSeen))
  ),
  agents_marker: agentsMarker,
  agents_marker_seen: agentsMarkerSeen,
  scene_marker: sceneMarker,
  scene_marker_seen: sceneMarkerSeen,
  require_scene_context: requireSceneContext,
  expected_scene_path: expectedScenePath,
  expected_scene_path_seen: expectedScenePathSeen,
  started,
  final_task: finalTask,
  message_count: queue.length,
  methods: queue.map(message => message.method ?? `response:${message.id}`),
  report_path: reportPath
};
await fs.writeFile(reportPath, `${JSON.stringify(result, null, 2)}\n`, 'utf8');
console.log(JSON.stringify(result, null, 2));
if (!result.ok) {
  process.exit(1);
}
'@
  Set-Content -LiteralPath $probePath -Value $probe -Encoding utf8
  node $probePath $Port $resolvedProjectRoot $reportPath $TimeoutSeconds $rolesBase64 ([string][bool]$RequireSceneContext).ToLowerInvariant() $expectedScenePath
  if ($LASTEXITCODE -ne 0) {
    throw "Real app-server background probe failed with exit code $LASTEXITCODE"
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
