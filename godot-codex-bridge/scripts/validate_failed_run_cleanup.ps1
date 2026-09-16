param(
  [string] $ProjectRoot = "examples\minimal_3d_project",
  [string] $GodotExecutable = $(if ($env:GODOT_BIN) { $env:GODOT_BIN } elseif (Get-Command godot -ErrorAction SilentlyContinue) { (Get-Command godot).Source } else { "godot" }),
  [string] $ScenePath = "res://scenes/main_3d.tscn",
  [string] $PlaytestScenePath = "res://scenes/playtest_input_fixture.tscn",
  [string] $ActionName = "gcb_playtest_jump",
  [int] $StartupTimeoutSeconds = 90,
  [int] $RequestTimeoutSeconds = 20,
  [switch] $KeepOpen
)

$ErrorActionPreference = "Stop"

function Resolve-FullPath([string] $PathValue, [string] $BasePath) {
  if ([System.IO.Path]::IsPathRooted($PathValue)) {
    return [System.IO.Path]::GetFullPath($PathValue)
  }
  return [System.IO.Path]::GetFullPath((Join-Path $BasePath $PathValue))
}

function Convert-ResPathToAbsolute([string] $ProjectRootValue, [string] $ResPath) {
  if (-not $ResPath.StartsWith("res://")) {
    throw "Expected res:// scene path, got $ResPath"
  }
  $relative = $ResPath.Substring("res://".Length).Replace("/", [System.IO.Path]::DirectorySeparatorChar)
  return Join-Path $ProjectRootValue $relative
}

function Resolve-HeadlessGodotExecutable([string] $GodotPath) {
  $directory = Split-Path -Parent $GodotPath
  $fileName = Split-Path -Leaf $GodotPath
  if ($fileName -notmatch "_console\.exe$") {
    $consoleName = $fileName -replace "\.exe$", "_console.exe"
    $consolePath = Join-Path $directory $consoleName
    if (Test-Path -LiteralPath $consolePath) {
      return $consolePath
    }
  }
  return $GodotPath
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
  $request | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $requestPath -Encoding UTF8

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

function Invoke-EditorAction([string] $Action, [hashtable] $Params, [string] $RequestsDir, [string] $ResponsesDir, [int] $TimeoutSeconds) {
  return Send-BridgeRequest "editor_control" @{
    requested_by = "failed_run_cleanup_validation"
    action = $Action
    params = $Params
  } $RequestsDir $ResponsesDir $TimeoutSeconds
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

function Get-ErrorCode($Result) {
  if ($Result.response -ne $null -and $Result.response.error -ne $null) {
    return [string]$Result.response.error.code
  }
  return $null
}

function Assert-Succeeded([string] $Name, $Result) {
  $status = Get-ResponseStatus $Result
  if ($status -ne "succeeded") {
    $raw = if ($Result.response -ne $null) { $Result.response | ConvertTo-Json -Depth 8 } else { $status }
    throw "$Name failed: $raw"
  }
}

$productRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$resolvedProjectRoot = Resolve-FullPath $ProjectRoot $productRoot
$resolvedGodot = Resolve-FullPath $GodotExecutable (Get-Location).Path
$resolvedHeadlessGodot = Resolve-HeadlessGodotExecutable $resolvedGodot
$projectFile = Join-Path $resolvedProjectRoot "project.godot"
$sceneFile = Convert-ResPathToAbsolute $resolvedProjectRoot $ScenePath
$playtestSceneFile = Convert-ResPathToAbsolute $resolvedProjectRoot $PlaytestScenePath

if (-not (Test-Path -LiteralPath $projectFile)) {
  throw "Wrong project root, project.godot not found: $resolvedProjectRoot"
}
if (-not (Test-Path -LiteralPath $resolvedGodot)) {
  throw "Godot executable not found: $resolvedGodot"
}
if (-not (Test-Path -LiteralPath $sceneFile)) {
  throw "Scene file not found: $sceneFile"
}
if (-not (Test-Path -LiteralPath $playtestSceneFile)) {
  throw "Playtest scene file not found: $playtestSceneFile"
}

$bridgeDir = Join-Path $resolvedProjectRoot ".godot\godot_codex_bridge"
$requestsDir = Join-Path $bridgeDir "requests"
$responsesDir = Join-Path $bridgeDir "responses"
$artifactsDir = Join-Path $bridgeDir "artifacts"
$heartbeatPath = Join-Path $bridgeDir "heartbeat.json"
$snapshotPath = Join-Path $bridgeDir "context_snapshot.json"
$reportPath = Join-Path $artifactsDir "failed_run_cleanup_validation.json"

New-Item -ItemType Directory -Force -Path $requestsDir, $responsesDir, $artifactsDir | Out-Null

$process = Start-Process -FilePath $resolvedGodot -ArgumentList @("--path", $resolvedProjectRoot, "--editor") -PassThru
$permissionPrevious = $null
$playtestPermissionPrevious = $null
$result = [ordered]@{
  status = "started"
  started_at = (Get-Date).ToUniversalTime().ToString("o")
  process_id = $process.Id
  project_root = $resolvedProjectRoot
  godot_executable = $resolvedGodot
  headless_godot_executable = $resolvedHeadlessGodot
  scene_path = $ScenePath
  playtest_scene_path = $PlaytestScenePath
  action_name = $ActionName
  heartbeat_live = $false
  heartbeat_age_ms = $null
  initial_stop_status = $null
  initial_stop_was_playing = $null
  failed_test_scene_path = "res://scenes/does_not_exist_for_cleanup_validation.tscn"
  failed_test_scene_exit_code = $null
  failed_test_scene_failed = $false
  failed_test_scene_output_sample = $null
  after_failed_test_stop_status = $null
  after_failed_test_stop_was_playing = $null
  failed_test_scene_left_editor_idle = $false
  open_scene_status = $null
  enable_run_permission_status = $null
  enable_playtest_permission_status = $null
  run_permission_previous = $null
  playtest_permission_previous = $null
  first_run_status = $null
  first_run_started = $null
  failed_run_status = $null
  failed_run_error_code = $null
  failed_run_rejected_as_already_playing = $false
  cleanup_stop_status = $null
  cleanup_stop_was_playing = $null
  cleanup_stop_stopped = $null
  post_cleanup_idle_confirmed = $false
  post_cleanup_stop_status = $null
  post_cleanup_stop_was_playing = $null
  emergency_start_status = $null
  emergency_input_status = $null
  emergency_input_held_after = $null
  emergency_stop_status = $null
  emergency_stop_was_playing = $null
  emergency_auto_released_actions = $null
  emergency_held_actions_after = $null
  emergency_session_closed = $null
  emergency_cleanup_ok = $false
  emergency_session_file_active = $null
  failed_scenario_status = $null
  failed_scenario_error_code = $null
  failed_scenario_cleanup_ok = $false
  failed_scenario_auto_released_actions = $null
  failed_scenario_held_actions_after = $null
  failed_scenario_session_closed = $null
  failed_scenario_idle_confirmed = $false
  failed_scenario_stop_status = $null
  failed_scenario_stop_was_playing = $null
  restore_run_permission_status = $null
  restore_playtest_permission_status = $null
  report_path = $reportPath
}

try {
  $deadline = (Get-Date).AddSeconds($StartupTimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    if ((Test-Path -LiteralPath $heartbeatPath) -and (Test-Path -LiteralPath $snapshotPath)) {
      $ageMs = [int64](((Get-Date).ToUniversalTime() - (Get-Item -LiteralPath $heartbeatPath).LastWriteTimeUtc).TotalMilliseconds)
      if ($ageMs -le 5000) {
        $result.heartbeat_live = $true
        $result.heartbeat_age_ms = $ageMs
        break
      }
    }
    Start-Sleep -Milliseconds 500
  }

  if (-not $result.heartbeat_live) {
    throw "Godot editor heartbeat did not become live within $StartupTimeoutSeconds seconds."
  }

  $initialStop = Invoke-EditorAction "stop_running_scene" @{} $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.initial_stop_status = Get-ResponseStatus $initialStop
  if ($initialStop.response -ne $null -and $initialStop.response.data -ne $null) {
    $result.initial_stop_was_playing = [bool]$initialStop.response.data.was_playing
  }
  Assert-Succeeded "initial stop_running_scene" $initialStop

  $headlessStdoutPath = Join-Path $artifactsDir "failed_run_cleanup_headless_stdout.txt"
  $headlessStderrPath = Join-Path $artifactsDir "failed_run_cleanup_headless_stderr.txt"
  $headlessProcess = Start-Process `
    -FilePath $resolvedHeadlessGodot `
    -ArgumentList @("--headless", "--path", $resolvedProjectRoot, "--scene", $result.failed_test_scene_path, "--quit-after", "60") `
    -Wait `
    -PassThru `
    -WindowStyle Hidden `
    -RedirectStandardOutput $headlessStdoutPath `
    -RedirectStandardError $headlessStderrPath
  $failedTestOutput = @()
  if (Test-Path -LiteralPath $headlessStdoutPath) {
    $failedTestOutput += @(Get-Content -LiteralPath $headlessStdoutPath -ErrorAction SilentlyContinue)
  }
  if (Test-Path -LiteralPath $headlessStderrPath) {
    $failedTestOutput += @(Get-Content -LiteralPath $headlessStderrPath -ErrorAction SilentlyContinue)
  }
  $result.failed_test_scene_exit_code = $headlessProcess.ExitCode
  $result.failed_test_scene_failed = ($result.failed_test_scene_exit_code -ne 0)
  $result.failed_test_scene_output_sample = (($failedTestOutput | Select-Object -First 8) -join "`n")
  if (-not $result.failed_test_scene_failed) {
    throw "failed headless test scene unexpectedly exited with code 0."
  }

  $afterFailedTestStop = Invoke-EditorAction "stop_running_scene" @{} $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.after_failed_test_stop_status = Get-ResponseStatus $afterFailedTestStop
  if ($afterFailedTestStop.response -ne $null -and $afterFailedTestStop.response.data -ne $null) {
    $result.after_failed_test_stop_was_playing = [bool]$afterFailedTestStop.response.data.was_playing
    $result.failed_test_scene_left_editor_idle = (-not $result.after_failed_test_stop_was_playing)
  }
  Assert-Succeeded "post failed test scene stop_running_scene" $afterFailedTestStop
  if (-not $result.failed_test_scene_left_editor_idle) {
    throw "failed headless test scene left an editor play session active."
  }

  $openScene = Send-BridgeRequest "open_scene" @{
    requested_by = "failed_run_cleanup_validation"
    scene_path = $ScenePath
    make_main_screen = "3D"
    select_in_file_system = $true
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.open_scene_status = Get-ResponseStatus $openScene
  Assert-Succeeded "open_scene" $openScene

  $enableRun = Send-BridgeRequest "set_bridge_permission" @{
    requested_by = "failed_run_cleanup_validation"
    validation_token = "GCB_VALIDATE_PERMISSION_TOGGLE"
    key = "allow_run_current_scene"
    value = $true
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.enable_run_permission_status = Get-ResponseStatus $enableRun
  if ($enableRun.response -ne $null -and $enableRun.response.data -ne $null) {
    $permissionPrevious = [bool]$enableRun.response.data.previous
    $result.run_permission_previous = $permissionPrevious
  }
  Assert-Succeeded "enable run_current_scene permission" $enableRun

  $enablePlaytest = Send-BridgeRequest "set_bridge_permission" @{
    requested_by = "failed_run_cleanup_validation"
    validation_token = "GCB_VALIDATE_PERMISSION_TOGGLE"
    key = "allow_playtest_input"
    value = $true
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.enable_playtest_permission_status = Get-ResponseStatus $enablePlaytest
  if ($enablePlaytest.response -ne $null -and $enablePlaytest.response.data -ne $null) {
    $playtestPermissionPrevious = [bool]$enablePlaytest.response.data.previous
    $result.playtest_permission_previous = $playtestPermissionPrevious
  }
  Assert-Succeeded "enable playtest input permission" $enablePlaytest

  $firstRun = Send-BridgeRequest "run_current_scene" @{
    requested_by = "failed_run_cleanup_validation"
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.first_run_status = Get-ResponseStatus $firstRun
  if ($firstRun.response -ne $null -and $firstRun.response.data -ne $null) {
    $result.first_run_started = [bool]$firstRun.response.data.started
  }
  Assert-Succeeded "first run_current_scene" $firstRun
  if (-not $result.first_run_started) {
    throw "first run_current_scene did not report started=true."
  }

  Start-Sleep -Milliseconds 1500

  $failedRun = Send-BridgeRequest "run_current_scene" @{
    requested_by = "failed_run_cleanup_validation"
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.failed_run_status = Get-ResponseStatus $failedRun
  $result.failed_run_error_code = Get-ErrorCode $failedRun
  $result.failed_run_rejected_as_already_playing = ($result.failed_run_status -eq "failed" -and $result.failed_run_error_code -eq "scene_already_playing")
  if (-not $result.failed_run_rejected_as_already_playing) {
    $raw = if ($failedRun.response -ne $null) { $failedRun.response | ConvertTo-Json -Depth 8 } else { Get-ResponseStatus $failedRun }
    throw "second run_current_scene did not fail with scene_already_playing: $raw"
  }

  $cleanupStop = Invoke-EditorAction "stop_running_scene" @{} $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.cleanup_stop_status = Get-ResponseStatus $cleanupStop
  if ($cleanupStop.response -ne $null -and $cleanupStop.response.data -ne $null) {
    $result.cleanup_stop_was_playing = [bool]$cleanupStop.response.data.was_playing
    $result.cleanup_stop_stopped = [bool]$cleanupStop.response.data.stopped
  }
  Assert-Succeeded "cleanup stop_running_scene" $cleanupStop
  if (-not $result.cleanup_stop_was_playing -or -not $result.cleanup_stop_stopped) {
    throw "cleanup stop_running_scene did not prove an active play session was stopped."
  }

  $idleDeadline = (Get-Date).AddSeconds($RequestTimeoutSeconds)
  while ((Get-Date) -lt $idleDeadline) {
    Start-Sleep -Milliseconds 500
    $postStop = Invoke-EditorAction "stop_running_scene" @{} $requestsDir $responsesDir $RequestTimeoutSeconds
    $result.post_cleanup_stop_status = Get-ResponseStatus $postStop
    if ($postStop.response -ne $null -and $postStop.response.data -ne $null) {
      $result.post_cleanup_stop_was_playing = [bool]$postStop.response.data.was_playing
      if (-not $result.post_cleanup_stop_was_playing) {
        $result.post_cleanup_idle_confirmed = $true
        break
      }
    }
  }

  if (-not $result.post_cleanup_idle_confirmed) {
    throw "stop_running_scene did not reach was_playing=false after failed run cleanup."
  }

  $emergencyStart = Send-BridgeRequest "run_current_scene" @{
    requested_by = "failed_run_cleanup_validation"
    scene_path = $PlaytestScenePath
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.emergency_start_status = Get-ResponseStatus $emergencyStart
  Assert-Succeeded "emergency cleanup run_current_scene" $emergencyStart

  Start-Sleep -Milliseconds 1500

  $emergencyInput = Invoke-EditorAction "playtest_input" @{
    steps = @(
      [ordered]@{
        type = "action_press"
        action = $ActionName
        strength = 1.0
      }
    )
    reason = "failed_run_cleanup_validation:emergency_stop"
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.emergency_input_status = Get-ResponseStatus $emergencyInput
  if ($emergencyInput.response -ne $null -and $emergencyInput.response.data -ne $null) {
    $result.emergency_input_held_after = @($emergencyInput.response.data.held_actions_after)
  }
  Assert-Succeeded "emergency cleanup playtest_input" $emergencyInput
  if (-not (@($result.emergency_input_held_after) -contains $ActionName)) {
    throw "playtest_input did not hold expected action before emergency_stop."
  }

  $emergencyStop = Invoke-EditorAction "emergency_stop" @{} $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.emergency_stop_status = Get-ResponseStatus $emergencyStop
  if ($emergencyStop.response -ne $null -and $emergencyStop.response.data -ne $null) {
    $result.emergency_stop_was_playing = [bool]$emergencyStop.response.data.was_playing
    $result.emergency_cleanup_ok = [bool]$emergencyStop.response.data.playtest_cleanup_ok
    $result.emergency_session_closed = [bool]$emergencyStop.response.data.session_closed
    if ($emergencyStop.response.data.playtest_input_cleanup -ne $null) {
      $result.emergency_auto_released_actions = @($emergencyStop.response.data.playtest_input_cleanup.auto_released_actions)
      $result.emergency_held_actions_after = @($emergencyStop.response.data.playtest_input_cleanup.held_actions_after)
    }
  }
  Assert-Succeeded "emergency_stop" $emergencyStop
  if (-not $result.emergency_stop_was_playing -or -not $result.emergency_cleanup_ok) {
    throw "emergency_stop did not prove stopped play session and clean playtest input/session cleanup."
  }
  if (-not (@($result.emergency_auto_released_actions) -contains $ActionName)) {
    throw "emergency_stop did not auto-release expected held action."
  }
  if (@($result.emergency_held_actions_after).Count -ne 0) {
    throw "emergency_stop left held actions after cleanup."
  }

  $sessionPath = Join-Path $bridgeDir "runtime\playtest_session.json"
  if (Test-Path -LiteralPath $sessionPath) {
    $sessionDocument = Get-Content -Raw -LiteralPath $sessionPath | ConvertFrom-Json
    $result.emergency_session_file_active = [bool]$sessionDocument.active
    if ($result.emergency_session_file_active) {
      throw "emergency_stop left playtest_session.json active=true."
    }
  }

  $failedScenario = [ordered]@{
    scenario_version = "godot-codex-bridge/playtest-scenario-v1"
    scene_path = $PlaytestScenePath
    global_timeout_seconds = 5
    steps = @(
      [ordered]@{
        id = "hold_action_before_timeout"
        type = "press_action"
        action = $ActionName
        strength = 1.0
      },
      [ordered]@{
        id = "force_timeout"
        type = "wait_for_event"
        event = "never_happens_for_cleanup_validation"
        action = $ActionName
        timeout_seconds = 0.05
      }
    )
  }

  $failedScenarioResult = Invoke-EditorAction "run_playtest_scenario" @{
    scenario = $failedScenario
  } $requestsDir $responsesDir ([Math]::Max($RequestTimeoutSeconds, 15))
  $result.failed_scenario_status = Get-ResponseStatus $failedScenarioResult
  $result.failed_scenario_error_code = Get-ErrorCode $failedScenarioResult
  if ($result.failed_scenario_status -ne "failed" -or $result.failed_scenario_error_code -ne "playtest_scenario_event_timeout") {
    $raw = if ($failedScenarioResult.response -ne $null) { $failedScenarioResult.response | ConvertTo-Json -Depth 12 } else { Get-ResponseStatus $failedScenarioResult }
    throw "failed run_playtest_scenario did not fail with playtest_scenario_event_timeout: $raw"
  }
  $stopDetails = $null
  if ($failedScenarioResult.response.error.details -ne $null) {
    $stopDetails = $failedScenarioResult.response.error.details.stop_result
  }
  if ($stopDetails -eq $null) {
    $stopDetails = $failedScenarioResult.response.error.stop_result
  }
  if ($stopDetails -ne $null) {
    $result.failed_scenario_cleanup_ok = [bool]$stopDetails.playtest_cleanup_ok
    $result.failed_scenario_session_closed = [bool]$stopDetails.session_closed
    if ($stopDetails.playtest_input_cleanup -ne $null) {
      $result.failed_scenario_auto_released_actions = @($stopDetails.playtest_input_cleanup.auto_released_actions)
      $result.failed_scenario_held_actions_after = @($stopDetails.playtest_input_cleanup.held_actions_after)
    }
  }
  if (-not $result.failed_scenario_cleanup_ok -or -not $result.failed_scenario_session_closed) {
    throw "failed run_playtest_scenario did not report clean stop_result cleanup."
  }
  if (-not (@($result.failed_scenario_auto_released_actions) -contains $ActionName)) {
    throw "failed run_playtest_scenario did not auto-release expected held action."
  }
  if (@($result.failed_scenario_held_actions_after).Count -ne 0) {
    throw "failed run_playtest_scenario left held actions after cleanup."
  }

  $failedScenarioStop = Invoke-EditorAction "stop_running_scene" @{} $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.failed_scenario_stop_status = Get-ResponseStatus $failedScenarioStop
  if ($failedScenarioStop.response -ne $null -and $failedScenarioStop.response.data -ne $null) {
    $result.failed_scenario_stop_was_playing = [bool]$failedScenarioStop.response.data.was_playing
    $result.failed_scenario_idle_confirmed = (-not $result.failed_scenario_stop_was_playing)
  }
  Assert-Succeeded "post failed scenario stop_running_scene" $failedScenarioStop
  if (-not $result.failed_scenario_idle_confirmed) {
    throw "failed run_playtest_scenario left an editor play session active."
  }

  $result.status = "ok"
}
catch {
  $result.status = "error"
  $result.error = $_.Exception.Message
}
finally {
  if ($permissionPrevious -ne $null) {
    try {
      $restoreRun = Send-BridgeRequest "set_bridge_permission" @{
        requested_by = "failed_run_cleanup_validation"
        validation_token = "GCB_VALIDATE_PERMISSION_TOGGLE"
        key = "allow_run_current_scene"
        value = $permissionPrevious
      } $requestsDir $responsesDir $RequestTimeoutSeconds
      $result.restore_run_permission_status = Get-ResponseStatus $restoreRun
    }
    catch {
      $result.restore_run_permission_status = "restore_failed"
      $result.restore_run_permission_error = $_.Exception.Message
    }
  }

  if ($playtestPermissionPrevious -ne $null) {
    try {
      $restorePlaytest = Send-BridgeRequest "set_bridge_permission" @{
        requested_by = "failed_run_cleanup_validation"
        validation_token = "GCB_VALIDATE_PERMISSION_TOGGLE"
        key = "allow_playtest_input"
        value = $playtestPermissionPrevious
      } $requestsDir $responsesDir $RequestTimeoutSeconds
      $result.restore_playtest_permission_status = Get-ResponseStatus $restorePlaytest
    }
    catch {
      $result.restore_playtest_permission_status = "restore_failed"
      $result.restore_playtest_permission_error = $_.Exception.Message
    }
  }

  try {
    [void](Invoke-EditorAction "stop_running_scene" @{} $requestsDir $responsesDir 5)
  }
  catch {
    $result.final_cleanup_error = $_.Exception.Message
  }

  $result.completed_at = (Get-Date).ToUniversalTime().ToString("o")
  $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportPath -Encoding UTF8

  if (-not $KeepOpen -and $process -and -not $process.HasExited) {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
  }
}

$result | ConvertTo-Json -Depth 12
if ($result.status -ne "ok") {
  exit 1
}
