param(
  [string]$ProjectRoot = "",
  [string]$GodotExecutable = "",
  [switch]$SkipInstall
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
if ($ProjectRoot -eq "") {
  $ProjectRoot = Join-Path $repoRoot "examples\minimal_3d_project"
}
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
$testRoot = Join-Path $repoRoot "tests\addon"

if ([string]::IsNullOrWhiteSpace($GodotExecutable)) {
  if (-not [string]::IsNullOrWhiteSpace($env:GODOT_BIN) -and (Test-Path -LiteralPath $env:GODOT_BIN)) {
    $GodotExecutable = $env:GODOT_BIN
  } elseif (-not [string]::IsNullOrWhiteSpace($env:GODOT_PATH) -and (Test-Path -LiteralPath $env:GODOT_PATH)) {
    $GodotExecutable = $env:GODOT_PATH
  } elseif (Test-Path -LiteralPath (Join-Path $ProjectRoot ".godot_bin")) {
    $GodotExecutable = (Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot ".godot_bin")).Trim()
  } elseif (Get-Command "godot" -ErrorAction SilentlyContinue) {
    $GodotExecutable = (Get-Command "godot").Source
  } elseif (Get-Command "godot4" -ErrorAction SilentlyContinue) {
    $GodotExecutable = (Get-Command "godot4").Source
  } else {
    throw "Godot executable not found. Please set the GODOT_BIN environment variable or ensure 'godot' is in your PATH."
  }
}

if (-not (Test-Path -LiteralPath $GodotExecutable)) {
  throw "Godot executable not found: $GodotExecutable. Please set the GODOT_BIN environment variable or ensure 'godot' is in your PATH."
}
if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot "project.godot"))) {
  throw "Godot project.godot not found under ProjectRoot: $ProjectRoot"
}
if (-not (Test-Path -LiteralPath $testRoot)) {
  throw "Addon core test directory not found: $testRoot"
}

if (-not $SkipInstall) {
  & (Join-Path $PSScriptRoot "install_addon.ps1") -ProjectRoot $ProjectRoot -Apply -Replace | Write-Output
}

$testScripts = Get-ChildItem -LiteralPath $testRoot -Filter "test_*.gd" | Sort-Object Name
if ($testScripts.Count -eq 0) {
  throw "No addon core test scripts found under: $testRoot"
}

$results = @()
foreach ($script in $testScripts) {
  & $GodotExecutable --headless --path $ProjectRoot --script $script.FullName
  $exitCode = $LASTEXITCODE
  $results += [ordered]@{
    script = $script.FullName
    exit_code = $exitCode
  }
  if ($exitCode -ne 0) {
    throw "Addon core test failed with exit code $exitCode`: $($script.FullName)"
  }
}

[ordered]@{
  status = "ok"
  project_root = $ProjectRoot
  test_count = $testScripts.Count
  tests = $results
  godot_executable = $GodotExecutable
} | ConvertTo-Json -Depth 5
