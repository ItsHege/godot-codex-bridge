param(
  [string] $ProjectRoot = "examples\minimal_3d_project",
  [string] $TargetProject = "",
  [string] $ReportPath = "",
  [switch] $Fast,
  [switch] $Visible,
  [switch] $NoVisible,
  [switch] $RealApp,
  [switch] $IncludeRealApp
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Resolve-FullPath([string] $PathValue, [string] $BasePath) {
  if ([System.IO.Path]::IsPathRooted($PathValue)) {
    return [System.IO.Path]::GetFullPath($PathValue)
  }
  return [System.IO.Path]::GetFullPath((Join-Path $BasePath $PathValue))
}

function Add-ValidationStep([string] $Name, [string] $Status, [string] $Command, [hashtable] $Details = @{}) {
  $entry = [ordered]@{
    name = $Name
    status = $Status
    duration_ms = if ($Details.ContainsKey("duration_ms")) { [int]$Details.duration_ms } else { 0 }
    command = $Command
  }

  foreach ($key in $Details.Keys) {
    if ($key -ne "duration_ms") {
      $entry[$key] = $Details[$key]
    }
  }

  $script:Steps.Add($entry) | Out-Null
}

function Add-SkippedStep([string] $Name, [string] $Command, [string] $Reason) {
  Add-ValidationStep $Name "not_run" $Command @{
    reason = $Reason
  }
}

function Invoke-ValidationStep([string] $Name, [string] $Command, [scriptblock] $ScriptBlock) {
  $started = Get-Date
  Write-Host "== $Name =="
  Write-Host $Command

  $exitCode = 0
  $errorMessage = ""

  try {
    $global:LASTEXITCODE = 0
    & $ScriptBlock
    $exitCode = if ($null -eq $global:LASTEXITCODE) { 0 } else { [int]$global:LASTEXITCODE }
    if ($exitCode -ne 0) {
      $errorMessage = "$Name failed with exit code $exitCode"
    }
  } catch {
    $exitCode = 1
    $errorMessage = [string]$_.Exception.Message
  }

  $elapsedMs = [int]((Get-Date) - $started).TotalMilliseconds
  if ($exitCode -eq 0 -and $errorMessage -eq "") {
    Add-ValidationStep $Name "ok" $Command @{
      duration_ms = $elapsedMs
      exit_code = 0
    }
    return $true
  }

  Add-ValidationStep $Name "failed" $Command @{
    duration_ms = $elapsedMs
    exit_code = $exitCode
    error = $errorMessage
  }
  $script:HadFailure = $true
  return $false
}

$productRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$workspaceRoot = Resolve-Path -LiteralPath (Join-Path $productRoot "..")
if ($TargetProject -ne "") {
  $ProjectRoot = $TargetProject
}
if ($RealApp) {
  $IncludeRealApp = $true
}
$resolvedProjectRoot = Resolve-FullPath $ProjectRoot $productRoot
$bridgeDir = Join-Path $resolvedProjectRoot ".godot\godot_codex_bridge"
$artifactsDir = Join-Path $bridgeDir "artifacts"

if ($ReportPath -eq "") {
  $ReportPath = Join-Path $artifactsDir "all_local_validation.json"
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
$script:HadFailure = $false
$startedAt = Get-Date
$visibleDisabled = [bool]($Fast -or ($NoVisible -and -not $Visible))
$validationMode = if ($Fast) {
  "fast"
} elseif ($IncludeRealApp) {
  "real_app"
} elseif ($visibleDisabled) {
  "headless"
} else {
  "visible"
}

Push-Location $productRoot
try {
  Invoke-ValidationStep "addon_core" "npm run validate:addon-core" {
    & npm run validate:addon-core
  } | Out-Null

  Invoke-ValidationStep "host_tests" "npm run host:test" {
    & npm run host:test
  } | Out-Null

  Invoke-ValidationStep "mcp_tests" "npm --prefix mcp_server test" {
    & npm --prefix mcp_server test
  } | Out-Null

  if ($visibleDisabled) {
    $reason = if ($Fast) { "skipped_by_fast" } else { "skipped_by_no_visible" }
    Add-SkippedStep "chat_ux" "npm run validate:chat-ux" $reason
  } else {
    Invoke-ValidationStep "chat_ux" "npm run validate:chat-ux" {
      & npm run validate:chat-ux
    } | Out-Null
  }

  if ($visibleDisabled) {
    $reason = if ($Fast) { "skipped_by_fast" } else { "skipped_by_no_visible" }
    Add-SkippedStep "visible_editor" "npm run validate:visible-editor" $reason
    Add-SkippedStep "live_mutation" "npm run validate:live-mutation" $reason
    Add-SkippedStep "multi_view_capture" "npm run validate:multi-view-capture" $reason
    Add-SkippedStep "playtest_scenario_evidence" "npm run validate:playtest-scenario-evidence" $reason
    Add-SkippedStep "visible_scene_save" "powershell -NoProfile -ExecutionPolicy Bypass -File scripts\validate_visible_scene_save.ps1" $reason
    Add-SkippedStep "failed_run_cleanup" "npm run validate:failed-run-cleanup" $reason
  } else {
    Invoke-ValidationStep "visible_editor" "npm run validate:visible-editor" {
      & npm run validate:visible-editor
    } | Out-Null

    Invoke-ValidationStep "live_mutation" "npm run validate:live-mutation" {
      & npm run validate:live-mutation
    } | Out-Null

    Invoke-ValidationStep "multi_view_capture" "npm run validate:multi-view-capture" {
      & npm run validate:multi-view-capture
    } | Out-Null

    Invoke-ValidationStep "playtest_scenario_evidence" "npm run validate:playtest-scenario-evidence" {
      & npm run validate:playtest-scenario-evidence
    } | Out-Null

    Invoke-ValidationStep "visible_scene_save" "powershell -NoProfile -ExecutionPolicy Bypass -File scripts\validate_visible_scene_save.ps1" {
      & powershell -NoProfile -ExecutionPolicy Bypass -File scripts\validate_visible_scene_save.ps1
    } | Out-Null

    Invoke-ValidationStep "failed_run_cleanup" "npm run validate:failed-run-cleanup" {
      & npm run validate:failed-run-cleanup
    } | Out-Null
  }

  if ($IncludeRealApp -and (-not $Fast)) {
    if (Test-Path -LiteralPath (Join-Path $productRoot "scripts\validate_real_app_server_background.ps1")) {
      Invoke-ValidationStep "real_app_background" "npm run validate:real-app-background" {
        & npm run validate:real-app-background
      } | Out-Null
    } else {
      Add-SkippedStep "real_app_background" "npm run validate:real-app-background" "script_missing"
    }
  } else {
    $reason = if ($Fast) { "skipped_by_fast" } else { "include_real_app_not_requested" }
    Add-SkippedStep "real_app_background" "npm run validate:real-app-background" $reason
  }
} finally {
  Pop-Location

  if ($hostConfigExisted -and $null -ne $hostConfigBytes) {
    [System.IO.File]::WriteAllBytes($hostConfigPath, $hostConfigBytes)
  } elseif ((-not $hostConfigExisted) -and (Test-Path -LiteralPath $hostConfigPath)) {
    Remove-Item -LiteralPath $hostConfigPath -Force
  }

  $hostConfigExistsAfter = Test-Path -LiteralPath $hostConfigPath

  $completedAt = Get-Date
  $status = if ($script:HadFailure) { "failed" } else { "ok" }
  $summary = [ordered]@{
    status = $status
    started_at = $startedAt.ToUniversalTime().ToString("o")
    completed_at = $completedAt.ToUniversalTime().ToString("o")
    duration_ms = [int]($completedAt - $startedAt).TotalMilliseconds
    product_root = [string]$productRoot
    workspace_root = [string]$workspaceRoot
    project_root = [string]$resolvedProjectRoot
    report_path = [string]$ReportPath
    flags = [ordered]@{
      fast = [bool]$Fast
      visible = -not $visibleDisabled
      no_visible = [bool]$NoVisible
      real_app = [bool]$RealApp
      include_real_app = [bool]$IncludeRealApp
      target_project = [string]$ProjectRoot
    }
    validation_mode = $validationMode
    host_config_restored = $true
    fixture_restore = [ordered]@{
      status = "ok"
      host_config_path = [string]$hostConfigPath
      host_config_existed_before = [bool]$hostConfigExisted
      host_config_exists_after = [bool]$hostConfigExistsAfter
      host_config_restored = $true
    }
    steps = @($script:Steps.ToArray())
  }

  $summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
  $summary | ConvertTo-Json -Depth 12
}

if ($script:HadFailure) {
  exit 1
}
