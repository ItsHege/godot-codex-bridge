param(
  [string] $GodotExecutable = $(if ($env:GODOT_BIN) { $env:GODOT_BIN } elseif (Test-Path -LiteralPath "C:\AI\Tools\Godot\Godot_console.exe") { "C:\AI\Tools\Godot\Godot_console.exe" } elseif (Get-Command godot -ErrorAction SilentlyContinue) { (Get-Command godot).Source } else { "godot" }),
  [switch] $Headless
)

$ErrorActionPreference = "Stop"
$productRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$projectRoot = Join-Path $productRoot "examples\minimal_3d_project"
$hostEntry = Join-Path $productRoot "codex_host\dist\src\index.js"
$testScript = Join-Path $productRoot "tests\fixture\test_host_pairing_editor.gd"
$reportPath = Join-Path $projectRoot ".godot\godot_codex_bridge\artifacts\host_pairing_fixture_validation.json"
$port = 49390
$testSecret = "c" * 64
if (-not (Test-Path -LiteralPath $GodotExecutable) -or -not (Test-Path -LiteralPath $hostEntry)) {
  throw "Godot executable or built mock Host is missing. Build the Host and provide GodotExecutable."
}
if (Get-NetTCPConnection -LocalAddress "127.0.0.1" -LocalPort $port -State Listen -ErrorAction SilentlyContinue) {
  throw "Port $port already has a listener; refusing to use or stop an unrelated Host."
}

$previousHostSecret = $env:GODOT_CODEX_HOST_PAIR_SECRET
$previousAllowedRoot = $env:GODOT_CODEX_HOST_ALLOWED_PROJECT_ROOT
$previousTestSecret = $env:GCB_TEST_PAIR_SECRET
$hostProcess = $null
$result = [ordered]@{
  status = "started"
  coverage = $(if ($Headless) { "headless_editor_fixture" } else { "rendered_editor_fixture" })
  project_root = $projectRoot
  godot_executable = $GodotExecutable
  started_at = (Get-Date).ToUniversalTime().ToString("o")
  report_path = $reportPath
}
try {
  $env:GODOT_CODEX_HOST_PAIR_SECRET = $testSecret
  $env:GODOT_CODEX_HOST_ALLOWED_PROJECT_ROOT = $projectRoot
  $hostProcess = Start-Process -FilePath "node" -ArgumentList @($hostEntry, "--runtime", "mock", "--port", [string]$port) -WorkingDirectory (Split-Path -Parent $hostEntry) -WindowStyle Hidden -PassThru
  $result.host_process_id = $hostProcess.Id
  $env:GODOT_CODEX_HOST_PAIR_SECRET = $previousHostSecret
  $env:GODOT_CODEX_HOST_ALLOWED_PROJECT_ROOT = $previousAllowedRoot

  $deadline = (Get-Date).AddSeconds(15)
  $healthy = $false
  while ((Get-Date) -lt $deadline) {
    if ($hostProcess.HasExited) { throw "Fixture mock Host exited before health was ready." }
    try {
      $health = Invoke-RestMethod -Uri "http://127.0.0.1:$port/health" -TimeoutSec 1
      if ($health.ok -and $health.runtime -eq "mock") { $healthy = $true; break }
    } catch { }
    Start-Sleep -Milliseconds 200
  }
  if (-not $healthy) { throw "Fixture mock Host did not become healthy." }
  $result.host_healthy = $true

  $env:GCB_TEST_PAIR_SECRET = $testSecret
  $args = @("--editor", "--path", $projectRoot, "--script", $testScript)
  if ($Headless) { $args = @("--headless") + $args }
  & $GodotExecutable @args
  $result.godot_exit_code = $LASTEXITCODE
  if ($null -eq $LASTEXITCODE) { throw "Godot did not return a native exit code; use the console executable for this fixture." }
  if ($LASTEXITCODE -ne 0) { throw "Host pairing fixture editor test failed with exit code $LASTEXITCODE." }
  $result.status = "ok"
} finally {
  $env:GODOT_CODEX_HOST_PAIR_SECRET = $previousHostSecret
  $env:GODOT_CODEX_HOST_ALLOWED_PROJECT_ROOT = $previousAllowedRoot
  $env:GCB_TEST_PAIR_SECRET = $previousTestSecret
  if ($hostProcess -and -not $hostProcess.HasExited) {
    Stop-Process -Id $hostProcess.Id -Force -ErrorAction SilentlyContinue
  }
  $result.completed_at = (Get-Date).ToUniversalTime().ToString("o")
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $reportPath) | Out-Null
  $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding UTF8
}

$result | ConvertTo-Json -Depth 6
