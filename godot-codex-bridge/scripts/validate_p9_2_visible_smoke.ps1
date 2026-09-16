param(
  [string] $ProjectRoot = "examples\minimal_3d_project",
  [string] $GodotExecutable = $(if ($env:GODOT_BIN) { $env:GODOT_BIN } elseif (Get-Command godot -ErrorAction SilentlyContinue) { (Get-Command godot).Source } else { "godot" }),
  [int] $Port = 49410,
  [int] $AppServerPort = 49411,
  [int] $StartupTimeoutSeconds = 90,
  [int] $RequestTimeoutSeconds = 20,
  [int] $TurnTimeoutSeconds = 180,
  [switch] $KeepEyeAttachEditorOpen
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
  $script:ValidationSteps.Add([ordered]@{
    name = $Name
    status = $Status
    details = $Details
  }) | Out-Null
}

function Assert-True([bool] $Condition, [string] $Message) {
  if (-not $Condition) {
    throw $Message
  }
}

function Get-ResponseStatus($Result) {
  if ($Result.response -ne $null) {
    return [string]$Result.response.status
  }
  if ($Result.timeout) {
    return "timeout"
  }
  return "missing_response"
}

function Send-BridgeRequest([string] $Type, [hashtable] $Payload, [string] $RequestsDir, [string] $ResponsesDir, [int] $TimeoutSeconds) {
  $id = [guid]::NewGuid().ToString()
  $requestPath = Join-Path $RequestsDir "$id.json"
  $responsePath = Join-Path $ResponsesDir "$id.json"
  $request = [ordered]@{
    protocol_version = "godot-codex-bridge/0.1"
    request_id = $id
    type = $Type
    created_at = (Get-Date).ToUniversalTime().ToString("o")
    payload = $Payload
  }
  $request | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $requestPath -Encoding UTF8

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    if (Test-Path -LiteralPath $responsePath) {
      $raw = Get-Content -Raw -LiteralPath $responsePath
      return [ordered]@{
        request_id = $id
        request_path = $requestPath
        response_path = $responsePath
        response = ($raw | ConvertFrom-Json)
        timeout = $false
      }
    }
    Start-Sleep -Milliseconds 250
  }

  return [ordered]@{
    request_id = $id
    request_path = $requestPath
    response_path = $responsePath
    response = $null
    timeout = $true
  }
}

function Invoke-RetryBridgeRequest([string] $Type, [hashtable] $Payload, [string] $RequestsDir, [string] $ResponsesDir, [int] $TimeoutSeconds, [int] $Retries) {
  $last = $null
  for ($i = 0; $i -lt $Retries; $i++) {
    $last = Send-BridgeRequest $Type $Payload $RequestsDir $ResponsesDir $TimeoutSeconds
    if ($last.response -ne $null -and $last.response.status -eq "succeeded") {
      return $last
    }
    Start-Sleep -Seconds 1
  }
  return $last
}

function Assert-Succeeded([string] $Name, $Result) {
  $status = Get-ResponseStatus $Result
  if ($status -ne "succeeded") {
    $raw = if ($Result.response -ne $null) { $Result.response | ConvertTo-Json -Depth 10 } else { $status }
    throw "$Name failed: $raw"
  }
}

function Invoke-ValidationScript([string] $Name, [string[]] $Arguments) {
  Add-Step $Name "started" @{ command = ($Arguments -join " ") }
  & powershell -NoProfile -ExecutionPolicy Bypass @Arguments | Out-Host
  if ($LASTEXITCODE -ne 0) {
    throw "$Name exited with code $LASTEXITCODE."
  }
  Add-Step $Name "ok" @{}
}

function Read-JsonFile([string] $PathValue) {
  if (-not (Test-Path -LiteralPath $PathValue)) {
    throw "Expected JSON report was not written: $PathValue"
  }
  return Get-Content -Raw -LiteralPath $PathValue | ConvertFrom-Json
}

function Invoke-EyeAttachVisibleSmoke(
  [string] $ResolvedProjectRoot,
  [string] $ResolvedGodot,
  [string] $BridgeDir,
  [string] $RequestsDir,
  [string] $ResponsesDir,
  [int] $StartupSeconds,
  [int] $TimeoutSeconds,
  [bool] $KeepOpen
) {
  New-Item -ItemType Directory -Force -Path $RequestsDir, $ResponsesDir | Out-Null
  $heartbeatPath = Join-Path $BridgeDir "heartbeat.json"
  $snapshotPath = Join-Path $BridgeDir "context_snapshot.json"
  $startedAt = (Get-Date).ToUniversalTime()
  $process = Start-Process -FilePath $ResolvedGodot -ArgumentList @("--path", $ResolvedProjectRoot, "--editor") -PassThru
  $permissionPrevious = $null
  $result = [ordered]@{
    process_id = $process.Id
    heartbeat_live = $false
    heartbeat_age_ms = $null
    enable_marker_permission_status = $null
    marker_permission_previous = $null
    eye_attach_status = $null
    eye_attach_response_path = $null
    restore_marker_permission_status = $null
    data = $null
  }

  try {
    $deadline = (Get-Date).AddSeconds($StartupSeconds)
    while ((Get-Date) -lt $deadline) {
      if ((Test-Path -LiteralPath $heartbeatPath) -and (Test-Path -LiteralPath $snapshotPath)) {
        $heartbeatItem = Get-Item -LiteralPath $heartbeatPath
        $ageMs = [int64](((Get-Date).ToUniversalTime() - $heartbeatItem.LastWriteTimeUtc).TotalMilliseconds)
        if ($heartbeatItem.LastWriteTimeUtc -ge $startedAt.AddSeconds(-2) -and $ageMs -le 5000) {
          $result.heartbeat_live = $true
          $result.heartbeat_age_ms = $ageMs
          break
        }
      }
      Start-Sleep -Milliseconds 500
    }

    if (-not $result.heartbeat_live) {
      throw "Godot editor heartbeat did not become live within $StartupSeconds seconds for Eye Attach validation."
    }

    $enable = Invoke-RetryBridgeRequest "set_bridge_permission" @{
      requested_by = "p9_2_visible_smoke"
      validation_token = "GCB_VALIDATE_PERMISSION_TOGGLE"
      key = "allow_ai_markers"
      value = $true
    } $RequestsDir $ResponsesDir $TimeoutSeconds 3
    $result.enable_marker_permission_status = Get-ResponseStatus $enable
    Assert-Succeeded "enable allow_ai_markers permission" $enable
    $permissionPrevious = [bool]$enable.response.data.previous
    $result.marker_permission_previous = $permissionPrevious

    $eye = Invoke-RetryBridgeRequest "validate_eye_attach_flow" @{
      requested_by = "p9_2_visible_smoke"
    } $RequestsDir $ResponsesDir $TimeoutSeconds 3
    $result.eye_attach_status = Get-ResponseStatus $eye
    $result.eye_attach_response_path = $eye.response_path
    Assert-Succeeded "validate_eye_attach_flow" $eye
    $result.data = $eye.response.data

    Assert-True ([bool]$result.data.capture_succeeded) "Eye Attach capture did not succeed."
    Assert-True (-not [bool]$result.data.capture_looked_blank) "Eye Attach capture looked blank."
    Assert-True ([bool]$result.data.dialog_visible_after_open) "Eye Attach dialog was not visible after open."
    Assert-True ([bool]$result.data.canvas_has_image_after_open) "Eye Attach canvas had no captured image."
    Assert-True ([bool]$result.data.marker_created_for_cancel) "Eye Attach cancel marker was not created."
    Assert-True ([int]$result.data.marker_count_before_cancel -ge 1) "Eye Attach cancel marker count stayed below 1."
    Assert-True ([bool]$result.data.cancel_left_no_pending) "Eye Attach cancel left a pending annotation."
    Assert-True ([bool]$result.data.marker_created_for_attach) "Eye Attach attach marker was not created."
    Assert-True ([bool]$result.data.pending_after_attach) "Eye Attach did not create a pending annotation."
    Assert-True ([bool]$result.data.pending_label_visible) "Eye Attach pending marker chip was not visible."
    Assert-True ([string]$result.data.pending_label_text -eq "Marker A attached") "Eye Attach pending chip text was unexpected."
    Assert-True ([bool]$result.data.raw_exists) "Eye Attach raw.png artifact was not written."
    Assert-True ([bool]$result.data.annotated_exists) "Eye Attach annotated.png artifact was not written."
    Assert-True ([bool]$result.data.manifest_exists) "Eye Attach annotation.json artifact was not written."
    Assert-True ([bool]$result.data.manifest_has_guardrails) "Eye Attach manifest guardrails were missing."
    Assert-True ([bool]$result.data.clear_removed_pending) "Eye Attach clear did not remove pending annotation state."
    Assert-True ([bool]$result.data.pending_label_hidden_after_clear) "Eye Attach pending chip stayed visible after clear."
    return $result
  } finally {
    if ($permissionPrevious -ne $null) {
      $restore = Invoke-RetryBridgeRequest "set_bridge_permission" @{
        requested_by = "p9_2_visible_smoke"
        validation_token = "GCB_VALIDATE_PERMISSION_TOGGLE"
        key = "allow_ai_markers"
        value = $permissionPrevious
      } $RequestsDir $ResponsesDir $TimeoutSeconds 3
      $result.restore_marker_permission_status = Get-ResponseStatus $restore
    }
    if (-not $KeepOpen -and $process -and -not $process.HasExited) {
      Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
  }
}

$productRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$resolvedProjectRoot = Resolve-FullPath $ProjectRoot $productRoot
$resolvedGodot = Resolve-FullPath $GodotExecutable (Get-Location).Path
$projectFile = Join-Path $resolvedProjectRoot "project.godot"
$bridgeDir = Join-Path $resolvedProjectRoot ".godot\godot_codex_bridge"
$requestsDir = Join-Path $bridgeDir "requests"
$responsesDir = Join-Path $bridgeDir "responses"
$artifactsDir = Join-Path $bridgeDir "artifacts"
$reportPath = Join-Path $artifactsDir "p9_2_visible_smoke_validation.json"
$chatUxReportPath = Join-Path $artifactsDir "chat_ux_regression_validation.json"
$visibleChatReportPath = Join-Path $artifactsDir "visible_chat_editor_validation.json"
$failedRunReportPath = Join-Path $artifactsDir "failed_run_cleanup_validation.json"
$script:ValidationSteps = New-Object System.Collections.Generic.List[object]

if (-not (Test-Path -LiteralPath $projectFile)) {
  throw "Wrong project root, project.godot not found: $resolvedProjectRoot"
}
if (-not (Test-Path -LiteralPath $resolvedGodot)) {
  throw "Godot executable not found: $resolvedGodot"
}
New-Item -ItemType Directory -Force -Path $artifactsDir | Out-Null

$summary = [ordered]@{
  status = "started"
  started_at = (Get-Date).ToUniversalTime().ToString("o")
  project_root = $resolvedProjectRoot
  godot_executable = $resolvedGodot
  report_path = $reportPath
  no_bottom_panel = $null
  diff_batch_ui = $null
  eye_attach = $null
  runtime_run_stop = $null
  external_project_mutation = "not_used"
  scene_save = "not_used"
  real_account_or_api = "not_used"
  steps = @()
}

Push-Location $productRoot
try {
  $pluginPath = Join-Path $productRoot "addons\godot_codex_bridge\plugin.gd"
  $pluginText = Get-Content -Raw -LiteralPath $pluginPath
  $noBottom = [ordered]@{
    source_file = $pluginPath
    add_control_to_bottom_panel_absent = (-not $pluginText.Contains("add_control_to_bottom_panel"))
    uses_right_dock = $pluginText.Contains("add_control_to_dock(DOCK_SLOT_RIGHT_UL")
    dock_name = "Codex Tools"
  }
  Assert-True ([bool]$noBottom.add_control_to_bottom_panel_absent) "plugin.gd still references add_control_to_bottom_panel."
  Assert-True ([bool]$noBottom.uses_right_dock) "plugin.gd does not register Codex Tools as a right dock."
  Add-Step "no_bottom_panel_static_regression" "ok" @{}

  Invoke-ValidationScript "chat_ux_regression" @(
    "-File", "scripts\validate_chat_ux_regression.ps1",
    "-ProjectRoot", $ProjectRoot,
    "-Port", [string]$Port,
    "-AppServerPort", [string]$AppServerPort,
    "-StartupTimeoutSeconds", [string]$StartupTimeoutSeconds,
    "-RequestTimeoutSeconds", [string]$RequestTimeoutSeconds,
    "-TurnTimeoutSeconds", [string]$TurnTimeoutSeconds
  )
  $chatUx = Read-JsonFile $chatUxReportPath
  $visibleChat = Read-JsonFile $visibleChatReportPath
  Assert-True ($chatUx.status -eq "ok") "chat_ux_regression report status was not ok."
  Assert-True ($visibleChat.status -eq "ok") "visible_chat_editor report status was not ok."

  $noBottom["chat_panel_visible"] = [bool]$visibleChat.chat_input_visible
  $noBottom["chat_input_inside_panel"] = [bool]$visibleChat.chat_input_inside_panel
  $noBottom["chat_log_inside_panel"] = [bool]$visibleChat.chat_log_inside_panel
  $noBottom["composer_below_log"] = [bool]$visibleChat.chat_composer_below_log
  Assert-True ([bool]$noBottom.chat_panel_visible) "Codex Chat panel was not visible in the dock smoke."
  Assert-True ([bool]$noBottom.chat_input_inside_panel) "Codex Chat input was outside the panel."
  Assert-True ([bool]$noBottom.chat_log_inside_panel) "Codex Chat log was outside the panel."

  $diffBatch = [ordered]@{
    visible_report_path = $visibleChatReportPath
    chat_ux_report_path = $chatUxReportPath
    status = $visibleChat.diff_overflow_validation_status
    generated_file_count = [int]$visibleChat.diff_overflow_generated_file_count
    ui_file_limit = [int]$visibleChat.diff_overflow_ui_file_limit
    active_file_count = [int]$visibleChat.diff_overflow_active_file_count
    added_count = [int]$visibleChat.diff_overflow_active_added_count
    removed_count = [int]$visibleChat.diff_overflow_active_removed_count
    file_section_count = [int]$visibleChat.diff_overflow_file_section_count
    files_box_visible_count = [int]$visibleChat.diff_overflow_files_box_visible_count
    active_files_visible = [bool]$visibleChat.diff_overflow_active_files_visible
    input_visible = [bool]$visibleChat.diff_overflow_input_visible
    input_inside_panel = [bool]$visibleChat.diff_overflow_input_inside_panel
    log_inside_panel = [bool]$visibleChat.diff_overflow_log_inside_panel
    composer_below_log = [bool]$visibleChat.diff_overflow_composer_below_log
    approval_above_input = [bool]$visibleChat.diff_overflow_approval_above_input
  }
  Assert-True ($diffBatch.status -eq "succeeded") "Diff overflow validation status was not succeeded."
  Assert-True ($diffBatch.generated_file_count -ge 32) "Diff overflow generated fewer than 32 files."
  Assert-True ($diffBatch.active_file_count -eq $diffBatch.ui_file_limit) "Diff overflow active file count did not match the UI cap."
  Assert-True ($diffBatch.added_count -eq 72) "Diff overflow added count was not +72."
  Assert-True ($diffBatch.removed_count -eq 72) "Diff overflow removed count was not -72."
  Assert-True ($diffBatch.file_section_count -eq $diffBatch.ui_file_limit) "Diff overflow rendered file section count did not match the UI cap."
  Assert-True ($diffBatch.files_box_visible_count -eq 1) "Diff overflow expanded file list was not visible."
  Assert-True ($diffBatch.active_files_visible) "Diff overflow active file list was not expanded."
  Assert-True ($diffBatch.input_visible -and $diffBatch.input_inside_panel -and $diffBatch.log_inside_panel -and $diffBatch.composer_below_log -and $diffBatch.approval_above_input) "Diff overflow layout containment regressed."

  Add-Step "install_mock_addon_for_eye_attach" "started" @{ port = $Port }
  & powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\install_addon.ps1" -ProjectRoot $ProjectRoot -Apply -Replace -HostRuntime mock -HostPort $Port | Out-Host
  if ($LASTEXITCODE -ne 0) {
    throw "install_addon for Eye Attach exited with code $LASTEXITCODE."
  }
  Add-Step "install_mock_addon_for_eye_attach" "ok" @{ port = $Port }

  $eyeAttach = Invoke-EyeAttachVisibleSmoke `
    -ResolvedProjectRoot $resolvedProjectRoot `
    -ResolvedGodot $resolvedGodot `
    -BridgeDir $bridgeDir `
    -RequestsDir $requestsDir `
    -ResponsesDir $responsesDir `
    -StartupSeconds $StartupTimeoutSeconds `
    -TimeoutSeconds $RequestTimeoutSeconds `
    -KeepOpen ([bool]$KeepEyeAttachEditorOpen)
  Add-Step "eye_attach_visible_flow" "ok" @{ response_path = $eyeAttach.eye_attach_response_path }

  Invoke-ValidationScript "failed_run_cleanup" @(
    "-File", "scripts\validate_failed_run_cleanup.ps1",
    "-ProjectRoot", $ProjectRoot,
    "-GodotExecutable", $resolvedGodot,
    "-StartupTimeoutSeconds", [string]$StartupTimeoutSeconds,
    "-RequestTimeoutSeconds", [string]$RequestTimeoutSeconds
  )
  $failedRun = Read-JsonFile $failedRunReportPath
  Assert-True ($failedRun.status -eq "ok") "failed_run_cleanup report status was not ok."
  $runtimeRunStop = [ordered]@{
    failed_run_report_path = $failedRunReportPath
    first_run_status = $failedRun.first_run_status
    first_run_started = [bool]$failedRun.first_run_started
    duplicate_run_status = $failedRun.failed_run_status
    duplicate_run_error_code = $failedRun.failed_run_error_code
    duplicate_run_rejected_as_already_playing = [bool]$failedRun.failed_run_rejected_as_already_playing
    cleanup_stop_status = $failedRun.cleanup_stop_status
    cleanup_stop_was_playing = [bool]$failedRun.cleanup_stop_was_playing
    cleanup_stop_stopped = [bool]$failedRun.cleanup_stop_stopped
    post_cleanup_stop_status = $failedRun.post_cleanup_stop_status
    post_cleanup_stop_was_playing = [bool]$failedRun.post_cleanup_stop_was_playing
    post_cleanup_idle_confirmed = [bool]$failedRun.post_cleanup_idle_confirmed
  }
  Assert-True ($runtimeRunStop.first_run_status -eq "succeeded") "first run_current_scene did not succeed."
  Assert-True ($runtimeRunStop.first_run_started) "first run_current_scene did not report started=true."
  Assert-True ($runtimeRunStop.duplicate_run_rejected_as_already_playing) "second run_current_scene was not rejected as scene_already_playing."
  Assert-True ($runtimeRunStop.cleanup_stop_was_playing -and $runtimeRunStop.cleanup_stop_stopped) "stop_running_scene did not stop an active play session."
  Assert-True ($runtimeRunStop.post_cleanup_idle_confirmed -and -not $runtimeRunStop.post_cleanup_stop_was_playing) "follow-up stop_running_scene did not prove the editor was idle."

  $summary.status = "ok"
  $summary.completed_at = (Get-Date).ToUniversalTime().ToString("o")
  $summary.no_bottom_panel = $noBottom
  $summary.diff_batch_ui = $diffBatch
  $summary.eye_attach = $eyeAttach
  $summary.runtime_run_stop = $runtimeRunStop
  $summary.steps = @($script:ValidationSteps.ToArray())
  $summary | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $reportPath -Encoding UTF8
  $summary | ConvertTo-Json -Depth 16
} catch {
  Add-Step "p9_2_visible_smoke" "failed" @{ error = [string]$_.Exception.Message }
  $summary.status = "failed"
  $summary.completed_at = (Get-Date).ToUniversalTime().ToString("o")
  $summary.error = [string]$_.Exception.Message
  $summary.steps = @($script:ValidationSteps.ToArray())
  $summary | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $reportPath -Encoding UTF8
  throw
} finally {
  Pop-Location
}
