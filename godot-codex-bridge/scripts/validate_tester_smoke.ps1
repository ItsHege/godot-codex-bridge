param(
  [string] $ProjectRoot = "examples\minimal_3d_project",
  [string] $ReportPath = "",
  [switch] $IncludeGovernance
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Resolve-FullPath([string] $PathValue, [string] $BasePath) {
  if ([System.IO.Path]::IsPathRooted($PathValue)) {
    return [System.IO.Path]::GetFullPath($PathValue)
  }
  return [System.IO.Path]::GetFullPath((Join-Path $BasePath $PathValue))
}

function Add-Step([string] $Name, [string] $Status, [hashtable] $Details = @{}) {
  $script:Steps.Add([ordered]@{
    name = $Name
    status = $Status
    details = $Details
  }) | Out-Null
}

function Invoke-SmokeStep([string] $Name, [scriptblock] $Command) {
  $started = Get-Date
  Write-Host "== $Name =="
  try {
    & $Command
    $exitCode = if ($null -eq $global:LASTEXITCODE) { 0 } else { [int]$global:LASTEXITCODE }
    if ($exitCode -ne 0) {
      throw "$Name failed with exit code $exitCode"
    }
    $elapsedMs = [int]((Get-Date) - $started).TotalMilliseconds
    Add-Step $Name "ok" @{ duration_ms = $elapsedMs }
  } catch {
    $elapsedMs = [int]((Get-Date) - $started).TotalMilliseconds
    Add-Step $Name "failed" @{
      duration_ms = $elapsedMs
      error = [string]$_.Exception.Message
    }
    throw
  }
}

$productRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$workspaceRoot = Resolve-Path -LiteralPath (Join-Path $productRoot "..")
$resolvedProjectRoot = Resolve-FullPath $ProjectRoot $productRoot
$bridgeDir = Join-Path $resolvedProjectRoot ".godot\godot_codex_bridge"
$artifactsDir = Join-Path $bridgeDir "artifacts"
if ($ReportPath -eq "") {
  $ReportPath = Join-Path $artifactsDir "tester_smoke_validation.json"
} else {
  $ReportPath = Resolve-FullPath $ReportPath $productRoot
}

if (-not (Test-Path -LiteralPath (Join-Path $resolvedProjectRoot "project.godot"))) {
  throw "Godot project.godot not found under ProjectRoot: $resolvedProjectRoot"
}

New-Item -ItemType Directory -Force -Path ([System.IO.Path]::GetDirectoryName($ReportPath)) | Out-Null

$hostConfigPath = Join-Path $resolvedProjectRoot "addons\godot_codex_bridge\host_config.json"
$hostConfigExisted = Test-Path -LiteralPath $hostConfigPath
$hostConfigBytes = $null
if ($hostConfigExisted) {
  $hostConfigBytes = [System.IO.File]::ReadAllBytes($hostConfigPath)
}

$script:Steps = New-Object System.Collections.Generic.List[object]
$startedAt = Get-Date
$status = "failed"
$errorMessage = ""

Push-Location $productRoot
try {
  if ($IncludeGovernance) {
    Invoke-SmokeStep "agents_doctor" {
      & npx --yes agents-doctor@latest verify --json $workspaceRoot
    }
  }

  Invoke-SmokeStep "host_tests" {
    & npm --prefix codex_host test
  }

  Invoke-SmokeStep "mcp_tests" {
    & npm --prefix mcp_server test
  }

  Invoke-SmokeStep "blender_import_staging" {
    & npm run validate:blender-import-staging
  }

  Invoke-SmokeStep "chat_ux_regression" {
    & npm run validate:chat-ux
  }

  $status = "ok"
} catch {
  $errorMessage = [string]$_.Exception.Message
  throw
} finally {
  Pop-Location

  if ($hostConfigExisted -and $null -ne $hostConfigBytes) {
    [System.IO.File]::WriteAllBytes($hostConfigPath, $hostConfigBytes)
  } elseif ((-not $hostConfigExisted) -and (Test-Path -LiteralPath $hostConfigPath)) {
    Remove-Item -LiteralPath $hostConfigPath -Force
  }

  $summary = [ordered]@{
    status = $status
    started_at = $startedAt.ToUniversalTime().ToString("o")
    completed_at = (Get-Date).ToUniversalTime().ToString("o")
    duration_ms = [int]((Get-Date) - $startedAt).TotalMilliseconds
    product_root = [string]$productRoot
    workspace_root = [string]$workspaceRoot
    project_root = [string]$resolvedProjectRoot
    report_path = [string]$ReportPath
    host_config_restored = $true
    include_governance = [bool]$IncludeGovernance
    steps = @($script:Steps.ToArray())
  }
  if ($errorMessage -ne "") {
    $summary.error = $errorMessage
  }
  $summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
  $summary | ConvertTo-Json -Depth 12
}
