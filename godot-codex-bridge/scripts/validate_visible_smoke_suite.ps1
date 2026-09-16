param(
  [string] $ProjectRoot = "examples\minimal_3d_project",
  [string] $ReportPath = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Resolve-FullPath([string] $PathValue, [string] $BasePath) {
  if ([System.IO.Path]::IsPathRooted($PathValue)) {
    return [System.IO.Path]::GetFullPath($PathValue)
  }
  return [System.IO.Path]::GetFullPath((Join-Path $BasePath $PathValue))
}

function Add-Step([string] $Name, [string] $Status, [string] $Command, [hashtable] $Details = @{}) {
  $entry = [ordered]@{
    name = $Name
    status = $Status
    command = $Command
    duration_ms = if ($Details.ContainsKey("duration_ms")) { [int]$Details.duration_ms } else { 0 }
  }
  foreach ($key in $Details.Keys) {
    if ($key -ne "duration_ms") {
      $entry[$key] = $Details[$key]
    }
  }
  $script:Steps.Add($entry) | Out-Null
}

function Invoke-Step([string] $Name, [string] $Command, [scriptblock] $ScriptBlock) {
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
    Add-Step $Name "ok" $Command @{ duration_ms = $elapsedMs; exit_code = 0 }
    return $true
  }

  Add-Step $Name "failed" $Command @{ duration_ms = $elapsedMs; exit_code = $exitCode; error = $errorMessage }
  $script:HadFailure = $true
  return $false
}

function Read-JsonReport([string] $Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    return $null
  }
  return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function Case-Status([bool] $Condition) {
  if ($Condition) {
    return "ok"
  }
  return "failed"
}

$productRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$resolvedProjectRoot = Resolve-FullPath $ProjectRoot $productRoot
$bridgeDir = Join-Path $resolvedProjectRoot ".godot\godot_codex_bridge"
$artifactsDir = Join-Path $bridgeDir "artifacts"

if (-not (Test-Path -LiteralPath (Join-Path $resolvedProjectRoot "project.godot"))) {
  throw "Godot project.godot not found under ProjectRoot: $resolvedProjectRoot"
}

if ($ReportPath -eq "") {
  $ReportPath = Join-Path $artifactsDir "p9_2_visible_smoke_validation.json"
} else {
  $ReportPath = Resolve-FullPath $ReportPath $productRoot
}

New-Item -ItemType Directory -Force -Path ([System.IO.Path]::GetDirectoryName($ReportPath)) | Out-Null

$script:Steps = New-Object System.Collections.Generic.List[object]
$script:HadFailure = $false
$startedAt = Get-Date

$chatUxReportPath = Join-Path $artifactsDir "chat_ux_regression_validation.json"
$visibleChatReportPath = Join-Path $artifactsDir "visible_chat_editor_validation.json"
$failedRunCleanupReportPath = Join-Path $artifactsDir "failed_run_cleanup_validation.json"

Push-Location $productRoot
try {
  Invoke-Step "chat_ux_visible_smoke" "powershell -NoProfile -ExecutionPolicy Bypass -File scripts\validate_chat_ux_regression.ps1 -ProjectRoot `"$ProjectRoot`"" {
    & powershell -NoProfile -ExecutionPolicy Bypass -File scripts\validate_chat_ux_regression.ps1 -ProjectRoot $ProjectRoot
  } | Out-Null

  Invoke-Step "runtime_run_stop_cleanup" "powershell -NoProfile -ExecutionPolicy Bypass -File scripts\validate_failed_run_cleanup.ps1 -ProjectRoot `"$ProjectRoot`"" {
    & powershell -NoProfile -ExecutionPolicy Bypass -File scripts\validate_failed_run_cleanup.ps1 -ProjectRoot $ProjectRoot
  } | Out-Null
} finally {
  Pop-Location
}

$chatUx = Read-JsonReport $chatUxReportPath
$visibleChat = Read-JsonReport $visibleChatReportPath
$failedRun = Read-JsonReport $failedRunCleanupReportPath

$noBottomOk = (
  $visibleChat -ne $null -and
  [bool]$visibleChat.main_screen_registered -and
  [bool]$visibleChat.dock_registered -and
  -not [bool]$visibleChat.bottom_panel_registered -and
  [bool]$visibleChat.window_inside_usable_screen -and
  [bool]$visibleChat.final_window_inside_usable_screen
)
$eyeAttachOk = (
  $visibleChat -ne $null -and
  [string]$visibleChat.eye_attach_status -eq "succeeded" -and
  [bool]$visibleChat.eye_attach_capture_succeeded -and
  -not [bool]$visibleChat.eye_attach_capture_looked_blank -and
  [int]$visibleChat.eye_attach_image_width -gt 0 -and
  [int]$visibleChat.eye_attach_image_height -gt 0 -and
  [bool]$visibleChat.eye_attach_dialog_visible_after_open -and
  [bool]$visibleChat.eye_attach_canvas_has_image_after_open -and
  [bool]$visibleChat.eye_attach_marker_created_for_cancel -and
  [bool]$visibleChat.eye_attach_cancel_left_no_pending -and
  [bool]$visibleChat.eye_attach_marker_created_for_attach -and
  [bool]$visibleChat.eye_attach_pending_after_attach -and
  [bool]$visibleChat.eye_attach_manifest_has_guardrails -and
  [bool]$visibleChat.eye_attach_clear_removed_pending
)
$diffBatchOk = (
  $visibleChat -ne $null -and
  [string]$visibleChat.diff_overflow_validation_status -eq "succeeded" -and
  [int]$visibleChat.diff_overflow_generated_file_count -ge 32 -and
  [int]$visibleChat.diff_overflow_active_file_count -eq [int]$visibleChat.diff_overflow_ui_file_limit -and
  [int]$visibleChat.diff_overflow_file_section_count -eq [int]$visibleChat.diff_overflow_ui_file_limit -and
  [bool]$visibleChat.diff_overflow_active_files_visible -and
  [bool]$visibleChat.diff_overflow_input_visible -and
  [string]$visibleChat.diff_overflow_visual_status -eq "succeeded" -and
  -not [string]::IsNullOrWhiteSpace([string]$visibleChat.diff_overflow_visual_path) -and
  (Test-Path -LiteralPath ([string]$visibleChat.diff_overflow_visual_path)) -and
  -not [bool]$visibleChat.diff_overflow_visual_looks_blank
)
$runtimeRunStopOk = (
  $failedRun -ne $null -and
  [string]$failedRun.status -eq "ok" -and
  [string]$failedRun.first_run_status -eq "succeeded" -and
  [bool]$failedRun.first_run_started -and
  [bool]$failedRun.failed_run_rejected_as_already_playing -and
  [string]$failedRun.cleanup_stop_status -eq "succeeded" -and
  [bool]$failedRun.cleanup_stop_was_playing -and
  [bool]$failedRun.cleanup_stop_stopped -and
  [bool]$failedRun.post_cleanup_idle_confirmed -and
  [string]$failedRun.emergency_stop_status -eq "succeeded" -and
  [bool]$failedRun.emergency_cleanup_ok
)

if (-not ($noBottomOk -and $eyeAttachOk -and $diffBatchOk -and $runtimeRunStopOk)) {
  $script:HadFailure = $true
}

$completedAt = Get-Date
$summary = [ordered]@{
  status = if ($script:HadFailure) { "failed" } else { "ok" }
  started_at = $startedAt.ToUniversalTime().ToString("o")
  completed_at = $completedAt.ToUniversalTime().ToString("o")
  duration_ms = [int]($completedAt - $startedAt).TotalMilliseconds
  project_root = [string]$resolvedProjectRoot
  report_path = [string]$ReportPath
  source_reports = [ordered]@{
    chat_ux = [string]$chatUxReportPath
    visible_chat_editor = [string]$visibleChatReportPath
    failed_run_cleanup = [string]$failedRunCleanupReportPath
  }
  cases = [ordered]@{
    no_bottom_panel_regression = [ordered]@{
      status = Case-Status $noBottomOk
      main_screen_registered = if ($visibleChat -ne $null) { [bool]$visibleChat.main_screen_registered } else { $false }
      dock_registered = if ($visibleChat -ne $null) { [bool]$visibleChat.dock_registered } else { $false }
      bottom_panel_registered = if ($visibleChat -ne $null) { [bool]$visibleChat.bottom_panel_registered } else { $true }
      window_inside_usable_screen = if ($visibleChat -ne $null) { [bool]$visibleChat.window_inside_usable_screen } else { $false }
      final_window_inside_usable_screen = if ($visibleChat -ne $null) { [bool]$visibleChat.final_window_inside_usable_screen } else { $false }
    }
    eye_attach_capture_marker_cancel_attach = [ordered]@{
      status = Case-Status $eyeAttachOk
      capture_scope = if ($visibleChat -ne $null) { $visibleChat.eye_attach_capture_scope } else { "" }
      capture_source = if ($visibleChat -ne $null) { $visibleChat.eye_attach_capture_source } else { "" }
      capture_looked_blank = if ($visibleChat -ne $null) { [bool]$visibleChat.eye_attach_capture_looked_blank } else { $true }
      image_width = if ($visibleChat -ne $null) { [int]$visibleChat.eye_attach_image_width } else { 0 }
      image_height = if ($visibleChat -ne $null) { [int]$visibleChat.eye_attach_image_height } else { 0 }
      marker_count_before_cancel = if ($visibleChat -ne $null) { [int]$visibleChat.eye_attach_marker_count_before_cancel } else { 0 }
      cancel_left_no_pending = if ($visibleChat -ne $null) { [bool]$visibleChat.eye_attach_cancel_left_no_pending } else { $false }
      marker_count_before_attach = if ($visibleChat -ne $null) { [int]$visibleChat.eye_attach_marker_count_before_attach } else { 0 }
      pending_marker_count = if ($visibleChat -ne $null) { [int]$visibleChat.eye_attach_pending_marker_count } else { 0 }
      manifest_has_guardrails = if ($visibleChat -ne $null) { [bool]$visibleChat.eye_attach_manifest_has_guardrails } else { $false }
      clear_removed_pending = if ($visibleChat -ne $null) { [bool]$visibleChat.eye_attach_clear_removed_pending } else { $false }
    }
    diff_batch_ui = [ordered]@{
      status = Case-Status $diffBatchOk
      generated_file_count = if ($visibleChat -ne $null) { [int]$visibleChat.diff_overflow_generated_file_count } else { 0 }
      ui_file_limit = if ($visibleChat -ne $null) { [int]$visibleChat.diff_overflow_ui_file_limit } else { 0 }
      rendered_file_sections = if ($visibleChat -ne $null) { [int]$visibleChat.diff_overflow_file_section_count } else { 0 }
      active_file_count = if ($visibleChat -ne $null) { [int]$visibleChat.diff_overflow_active_file_count } else { 0 }
      files_expanded = if ($visibleChat -ne $null) { [bool]$visibleChat.diff_overflow_active_files_visible } else { $false }
      composer_visible = if ($visibleChat -ne $null) { [bool]$visibleChat.diff_overflow_input_visible } else { $false }
      visual_evidence_path = if ($visibleChat -ne $null) { [string]$visibleChat.diff_overflow_visual_path } else { "" }
      visual_evidence_nonblank = if ($visibleChat -ne $null) { -not [bool]$visibleChat.diff_overflow_visual_looks_blank } else { $false }
    }
    runtime_run_stop = [ordered]@{
      status = Case-Status $runtimeRunStopOk
      first_run_status = if ($failedRun -ne $null) { $failedRun.first_run_status } else { "" }
      first_run_started = if ($failedRun -ne $null) { [bool]$failedRun.first_run_started } else { $false }
      failed_run_rejected_as_already_playing = if ($failedRun -ne $null) { [bool]$failedRun.failed_run_rejected_as_already_playing } else { $false }
      cleanup_stop_status = if ($failedRun -ne $null) { $failedRun.cleanup_stop_status } else { "" }
      cleanup_stop_stopped = if ($failedRun -ne $null) { [bool]$failedRun.cleanup_stop_stopped } else { $false }
      post_cleanup_idle_confirmed = if ($failedRun -ne $null) { [bool]$failedRun.post_cleanup_idle_confirmed } else { $false }
      emergency_stop_status = if ($failedRun -ne $null) { $failedRun.emergency_stop_status } else { "" }
      emergency_cleanup_ok = if ($failedRun -ne $null) { [bool]$failedRun.emergency_cleanup_ok } else { $false }
    }
  }
  steps = @($script:Steps.ToArray())
}

$summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $ReportPath -Encoding UTF8
$summary | ConvertTo-Json -Depth 12

if ($script:HadFailure) {
  exit 1
}
