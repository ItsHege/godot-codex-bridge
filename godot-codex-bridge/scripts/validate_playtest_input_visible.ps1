param(
  [string] $ProjectRoot = "examples\minimal_3d_project",
  [string] $GodotExecutable = $(if ($env:GODOT_BIN) { $env:GODOT_BIN } elseif (Get-Command godot -ErrorAction SilentlyContinue) { (Get-Command godot).Source } else { "godot" }),
  [string] $ScenePath = "res://scenes/playtest_input_fixture.tscn",
  [string] $ActionName = "gcb_playtest_jump",
  [int] $StartupTimeoutSeconds = 45,
  [int] $RequestTimeoutSeconds = 20,
  [int] $RuntimeTimeoutSeconds = 20,
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

function Invoke-EditorAction([string] $Action, [hashtable] $Params, [string] $RequestsDir, [string] $ResponsesDir, [int] $TimeoutSeconds) {
  return Send-BridgeRequest "editor_control" @{
    requested_by = "playtest_input_visible_validation"
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

function Assert-Succeeded([string] $Name, $Result) {
  $status = Get-ResponseStatus $Result
  if ($status -ne "succeeded") {
    $raw = if ($Result.response -ne $null) { $Result.response | ConvertTo-Json -Depth 12 } else { $status }
    throw "$Name failed: $raw"
  }
}

function Read-JsonFileOrNull([string] $PathValue) {
  if (-not (Test-Path -LiteralPath $PathValue)) {
    return $null
  }
  $raw = Get-Content -Raw -LiteralPath $PathValue
  if ([string]::IsNullOrWhiteSpace($raw)) {
    return $null
  }
  return $raw | ConvertFrom-Json
}

function Read-TextTailSample([string] $PathValue, [int] $MaxLines = 20) {
  if (-not (Test-Path -LiteralPath $PathValue)) {
    return $null
  }
  $lines = @(Get-Content -LiteralPath $PathValue -Tail $MaxLines -ErrorAction SilentlyContinue)
  if ($lines.Count -eq 0) {
    return ""
  }
  return ($lines -join "`n")
}

function Convert-CimTimeToIsoOrNull($Value) {
  if ($Value -eq $null) {
    return $null
  }
  try {
    return ([System.Management.ManagementDateTimeConverter]::ToDateTime([string]$Value)).ToUniversalTime().ToString("o")
  }
  catch {
    return $null
  }
}

function Test-CommandLineContainsPath([string] $CommandLine, [string] $PathValue) {
  if ([string]::IsNullOrWhiteSpace($CommandLine) -or [string]::IsNullOrWhiteSpace($PathValue)) {
    return $false
  }
  $normalizedCommand = $CommandLine.ToLowerInvariant().Replace("\", "/")
  $normalizedPath = $PathValue.ToLowerInvariant().Replace("\", "/")
  return $normalizedCommand.Contains($normalizedPath)
}

function Get-GodotProcessSnapshot([string] $ProjectRootValue, [int] $EditorProcessId) {
  $items = @()
  $processes = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -like "Godot*" })
  foreach ($entry in $processes) {
    $commandLine = [string]$entry.CommandLine
    $matchesProject = Test-CommandLineContainsPath $commandLine $ProjectRootValue
    $matchesEditor = ([int]$entry.ProcessId -eq $EditorProcessId)
    $matchesEditorChild = ($EditorProcessId -gt 0 -and [int]$entry.ParentProcessId -eq $EditorProcessId)
    if (-not $matchesProject -and -not $matchesEditor -and -not $matchesEditorChild) {
      continue
    }
    $items += ,([ordered]@{
      pid = [int]$entry.ProcessId
      parent_pid = [int]$entry.ParentProcessId
      name = [string]$entry.Name
      creation_time_utc = Convert-CimTimeToIsoOrNull $entry.CreationDate
      command_line = $commandLine
      command_has_project_root = $matchesProject
      parent_is_editor = $matchesEditorChild
    })
  }
  return @($items)
}

function Get-PlayProcessCandidates($Snapshot, [int] $EditorProcessId) {
  $items = @()
  foreach ($entry in @($Snapshot)) {
    if ([int]$entry.pid -eq $EditorProcessId) {
      continue
    }
    $commandLine = [string]$entry.command_line
    $looksLikeEditor = ($commandLine -match "(^|\s)--editor(\s|$)")
    $looksLikeUnrelatedHeadlessScript = ($commandLine -match "(^|\s)--headless(\s|$)" -or $commandLine -match "(^|\s)--script(\s|$)")
    if ($looksLikeUnrelatedHeadlessScript -and -not [bool]$entry.parent_is_editor) {
      continue
    }
    if ([bool]$entry.parent_is_editor -or (-not $looksLikeEditor -and [bool]$entry.command_has_project_root)) {
      $items += ,$entry
    }
  }
  return @($items)
}

function Record-PlayProcessSample($Result, $Candidates, $ObservedIds) {
  foreach ($candidate in @($Candidates)) {
    $processId = [int]$candidate.pid
    $ObservedIds[$processId] = $true
    $Result.game_process_observed = $true
    if (@($Result.game_process_samples).Count -lt 8) {
      $Result.game_process_samples += ,$candidate
    }
  }
}

function Has-EventType([object] $EventsDoc, [string] $Type) {
  if ($EventsDoc -eq $null -or $EventsDoc.events -eq $null) {
    return $false
  }
  foreach ($event in @($EventsDoc.events)) {
    if ([string]$event.type -eq $Type) {
      return $true
    }
  }
  return $false
}

function Has-Event([object] $EventsDoc, [string] $Type, [string] $ActionNameValue) {
  if ($EventsDoc -eq $null -or $EventsDoc.events -eq $null) {
    return $false
  }
  foreach ($event in @($EventsDoc.events)) {
    if ([string]$event.type -ne $Type) {
      continue
    }
    $payload = $event.payload
    if ($payload -eq $null) {
      continue
    }
    if ([string]$payload.action -eq $ActionNameValue -or [string]$payload.name -eq $ActionNameValue) {
      return $true
    }
  }
  return $false
}

function Wait-ForEvent([string] $EventsPath, [string] $Type, [string] $ActionNameValue, [int] $TimeoutSeconds) {
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    $events = Read-JsonFileOrNull $EventsPath
    if (Has-Event $events $Type $ActionNameValue) {
      return [ordered]@{
        found = $true
        events = $events
      }
    }
    Start-Sleep -Milliseconds 250
  }
  return [ordered]@{
    found = $false
    events = (Read-JsonFileOrNull $EventsPath)
  }
}

function Wait-ForRuntimeState([string] $StatePath, [int] $TimeoutSeconds) {
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    $state = Read-JsonFileOrNull $StatePath
    if ($state -ne $null -and $state.runtime_state_version -ne $null) {
      return $state
    }
    Start-Sleep -Milliseconds 250
  }
  return $null
}

function Resolve-RuntimeFailurePhase($Result) {
  if ([bool]$Result.runtime_state_seen) {
    return "runtime_state_seen"
  }
  if ([string]$Result.run_status -ne "succeeded" -or -not [bool]$Result.run_started -or -not [bool]$Result.playtest_session_ready) {
    return "editor_play_not_started"
  }
  if (-not [bool]$Result.game_process_observed -and -not [bool]$Result.fixture_diagnostics_seen -and -not [bool]$Result.runtime_events_seen) {
    return "editor_play_process_not_observed"
  }
  if ([bool]$Result.game_process_observed -and -not [bool]$Result.game_process_alive_at_timeout -and -not [bool]$Result.fixture_diagnostics_seen -and -not [bool]$Result.runtime_events_seen) {
    return "game_process_exited_before_probe"
  }
  if ([bool]$Result.fixture_diagnostics_seen -and $Result.fixture_probe_write_ok -ne $null -and -not [bool]$Result.fixture_probe_write_ok) {
    return "runtime_probe_write_failed"
  }
  if ([bool]$Result.fixture_diagnostics_seen -or [bool]$Result.probe_ready_event_seen) {
    return "runtime_probe_state_not_written"
  }
  if ([bool]$Result.game_process_observed) {
    return "runtime_probe_not_reached_or_not_written"
  }
  return "runtime_state_missing_unknown"
}

$productRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$resolvedProjectRoot = Resolve-FullPath $ProjectRoot $productRoot
$resolvedGodot = Resolve-FullPath $GodotExecutable (Get-Location).Path
$projectFile = Join-Path $resolvedProjectRoot "project.godot"
$sceneFile = Convert-ResPathToAbsolute $resolvedProjectRoot $ScenePath

if (-not (Test-Path -LiteralPath $projectFile)) {
  throw "Wrong project root, project.godot not found: $resolvedProjectRoot"
}
if (-not (Test-Path -LiteralPath $resolvedGodot)) {
  throw "Godot executable not found: $resolvedGodot"
}
if (-not (Test-Path -LiteralPath $sceneFile)) {
  throw "Scene file not found: $sceneFile"
}

$bridgeDir = Join-Path $resolvedProjectRoot ".godot\godot_codex_bridge"
$requestsDir = Join-Path $bridgeDir "requests"
$responsesDir = Join-Path $bridgeDir "responses"
$artifactsDir = Join-Path $bridgeDir "artifacts"
$runtimeDir = Join-Path $bridgeDir "runtime"
$heartbeatPath = Join-Path $bridgeDir "heartbeat.json"
$snapshotPath = Join-Path $bridgeDir "context_snapshot.json"
$eventsPath = Join-Path $runtimeDir "events.json"
$statePath = Join-Path $runtimeDir "state.json"
$inputCommandsPath = Join-Path $runtimeDir "input_commands.json"
$playtestSessionPath = Join-Path $runtimeDir "playtest_session.json"
$fixtureDiagnosticsPath = Join-Path $runtimeDir "playtest_fixture_diagnostics.json"
$reportPath = Join-Path $artifactsDir "playtest_input_visible_validation.json"
$editorStdoutPath = Join-Path $artifactsDir "playtest_input_visible_editor_stdout.txt"
$editorStderrPath = Join-Path $artifactsDir "playtest_input_visible_editor_stderr.txt"

New-Item -ItemType Directory -Force -Path $requestsDir, $responsesDir, $artifactsDir, $runtimeDir | Out-Null
Remove-Item -LiteralPath $eventsPath, $statePath, $inputCommandsPath, $playtestSessionPath, $fixtureDiagnosticsPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $editorStdoutPath, $editorStderrPath -Force -ErrorAction SilentlyContinue

$preexistingGodotProcesses = @(Get-GodotProcessSnapshot $resolvedProjectRoot 0)
$process = Start-Process `
  -FilePath $resolvedGodot `
  -ArgumentList @("--path", $resolvedProjectRoot, "--editor") `
  -PassThru `
  -RedirectStandardOutput $editorStdoutPath `
  -RedirectStandardError $editorStderrPath
$permissionPrevious = @{}
$observedPlayProcessIds = @{}
$result = [ordered]@{
  status = "started"
  started_at = (Get-Date).ToUniversalTime().ToString("o")
  process_id = $process.Id
  project_root = $resolvedProjectRoot
  godot_executable = $resolvedGodot
  scene_path = $ScenePath
  action_name = $ActionName
  runtime_state_path = $statePath
  runtime_events_path = $eventsPath
  fixture_diagnostics_path = $fixtureDiagnosticsPath
  editor_stdout_path = $editorStdoutPath
  editor_stderr_path = $editorStderrPath
  editor_stdout_sample = $null
  editor_stderr_sample = $null
  preexisting_godot_processes = $preexistingGodotProcesses
  process_snapshot_after_editor_start = @()
  process_snapshot_before_run = @()
  process_snapshot_after_run = @()
  process_snapshot_at_runtime_timeout = @()
  process_snapshot_final = @()
  game_process_observed = $false
  game_process_alive_after_run = $false
  game_process_alive_at_timeout = $false
  game_process_samples = @()
  cleaned_play_process_ids = @()
  heartbeat_live = $false
  heartbeat_age_ms = $null
  open_scene_status = $null
  enable_run_permission_status = $null
  enable_playtest_permission_status = $null
  run_status = $null
  run_started = $null
  run_playing_scene = $null
  playtest_session_ready = $null
  runtime_state_seen = $false
  runtime_events_seen = $false
  probe_ready_event_seen = $false
  fixture_diagnostics_seen = $false
  fixture_diagnostics_stage = $null
  fixture_probe_write_ok = $null
  fixture_probe_error_code = $null
  runtime_failure_phase = $null
  diagnostic_summary = $null
  press_request_status = $null
  press_applied_event_seen = $false
  pressed_event_seen = $false
  release_request_status = $null
  release_applied_event_seen = $false
  released_event_seen = $false
  stop_status = $null
  stop_was_playing = $null
  stop_stopped = $null
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
    $result.process_snapshot_after_editor_start = @(Get-GodotProcessSnapshot $resolvedProjectRoot $process.Id)
    $result.runtime_failure_phase = "editor_heartbeat_not_live"
    throw "Godot editor heartbeat did not become live within $StartupTimeoutSeconds seconds."
  }
  $result.process_snapshot_after_editor_start = @(Get-GodotProcessSnapshot $resolvedProjectRoot $process.Id)

  [void](Invoke-EditorAction "stop_running_scene" @{} $requestsDir $responsesDir 5)

  $openScene = Send-BridgeRequest "open_scene" @{
    requested_by = "playtest_input_visible_validation"
    scene_path = $ScenePath
    make_main_screen = "3D"
    select_in_file_system = $true
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.open_scene_status = Get-ResponseStatus $openScene
  Assert-Succeeded "open_scene" $openScene

  foreach ($permission in @("allow_run_current_scene", "allow_playtest_input")) {
    $toggle = Send-BridgeRequest "set_bridge_permission" @{
      requested_by = "playtest_input_visible_validation"
      validation_token = "GCB_VALIDATE_PERMISSION_TOGGLE"
      key = $permission
      value = $true
    } $requestsDir $responsesDir $RequestTimeoutSeconds
    if ($toggle.response -ne $null -and $toggle.response.data -ne $null) {
      $permissionPrevious[$permission] = [bool]$toggle.response.data.previous
    }
    Assert-Succeeded "enable $permission" $toggle
    if ($permission -eq "allow_run_current_scene") {
      $result.enable_run_permission_status = Get-ResponseStatus $toggle
    } else {
      $result.enable_playtest_permission_status = Get-ResponseStatus $toggle
    }
  }

  $result.process_snapshot_before_run = @(Get-GodotProcessSnapshot $resolvedProjectRoot $process.Id)
  $run = Send-BridgeRequest "run_current_scene" @{
    requested_by = "playtest_input_visible_validation"
    scene_path = $ScenePath
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.run_status = Get-ResponseStatus $run
  Assert-Succeeded "run_current_scene" $run
  $result.run_started = [bool]$run.response.data.started
  $result.playtest_session_ready = [bool]$run.response.data.playtest_session_ready
  $result.run_scene_file_path = [string]$run.response.data.scene_file_path
  $result.run_playing_scene = [string]$run.response.data.playing_scene
  $result.process_snapshot_after_run = @(Get-GodotProcessSnapshot $resolvedProjectRoot $process.Id)
  $playProcessesAfterRun = @(Get-PlayProcessCandidates $result.process_snapshot_after_run $process.Id)
  $result.game_process_alive_after_run = (@($playProcessesAfterRun).Count -gt 0)
  Record-PlayProcessSample $result $playProcessesAfterRun $observedPlayProcessIds
  if (-not $result.run_started -or -not $result.playtest_session_ready) {
    $result.runtime_failure_phase = Resolve-RuntimeFailurePhase $result
    throw "run_current_scene did not start with a ready playtest session."
  }
  if ($result.run_scene_file_path -ne $ScenePath) {
    $result.runtime_failure_phase = "editor_play_wrong_scene"
    throw "run_current_scene started $($result.run_scene_file_path), expected $ScenePath."
  }

  $state = $null
  $runtimeDeadline = (Get-Date).AddSeconds($RuntimeTimeoutSeconds)
  while ((Get-Date) -lt $runtimeDeadline) {
    $state = Read-JsonFileOrNull $statePath
    if ($state -ne $null -and $state.runtime_state_version -ne $null) {
      break
    }

    $fixtureDiagnostics = Read-JsonFileOrNull $fixtureDiagnosticsPath
    if ($fixtureDiagnostics -ne $null) {
      $result.fixture_diagnostics_seen = $true
      $result.fixture_diagnostics_stage = [string]$fixtureDiagnostics.stage
      if ($fixtureDiagnostics.details -ne $null -and $fixtureDiagnostics.details.PSObject.Properties.Name -contains "probe_write_ok") {
        $result.fixture_probe_write_ok = [bool]$fixtureDiagnostics.details.probe_write_ok
      }
      if (
        $fixtureDiagnostics.details -ne $null -and
        $fixtureDiagnostics.details.probe_result -ne $null -and
        $fixtureDiagnostics.details.probe_result.error -ne $null
      ) {
        $result.fixture_probe_error_code = [string]$fixtureDiagnostics.details.probe_result.error.code
      }
    }

    $eventsDoc = Read-JsonFileOrNull $eventsPath
    if ($eventsDoc -ne $null) {
      $result.runtime_events_seen = $true
      $result.probe_ready_event_seen = Has-EventType $eventsDoc "probe_ready"
    }

    $runtimeSnapshot = @(Get-GodotProcessSnapshot $resolvedProjectRoot $process.Id)
    $runtimePlayProcesses = @(Get-PlayProcessCandidates $runtimeSnapshot $process.Id)
    if (@($runtimePlayProcesses).Count -gt 0) {
      $result.game_process_alive_at_timeout = $true
    }
    Record-PlayProcessSample $result $runtimePlayProcesses $observedPlayProcessIds

    Start-Sleep -Milliseconds 250
  }

  $result.process_snapshot_at_runtime_timeout = @(Get-GodotProcessSnapshot $resolvedProjectRoot $process.Id)
  $timeoutPlayProcesses = @(Get-PlayProcessCandidates $result.process_snapshot_at_runtime_timeout $process.Id)
  $result.game_process_alive_at_timeout = (@($timeoutPlayProcesses).Count -gt 0)
  Record-PlayProcessSample $result $timeoutPlayProcesses $observedPlayProcessIds
  $fixtureDiagnosticsFinal = Read-JsonFileOrNull $fixtureDiagnosticsPath
  if ($fixtureDiagnosticsFinal -ne $null) {
    $result.fixture_diagnostics_seen = $true
    $result.fixture_diagnostics_stage = [string]$fixtureDiagnosticsFinal.stage
    if ($fixtureDiagnosticsFinal.details -ne $null -and $fixtureDiagnosticsFinal.details.PSObject.Properties.Name -contains "probe_write_ok") {
      $result.fixture_probe_write_ok = [bool]$fixtureDiagnosticsFinal.details.probe_write_ok
    }
    if (
      $fixtureDiagnosticsFinal.details -ne $null -and
      $fixtureDiagnosticsFinal.details.probe_result -ne $null -and
      $fixtureDiagnosticsFinal.details.probe_result.error -ne $null
    ) {
      $result.fixture_probe_error_code = [string]$fixtureDiagnosticsFinal.details.probe_result.error.code
    }
  }
  $eventsDocFinal = Read-JsonFileOrNull $eventsPath
  if ($eventsDocFinal -ne $null) {
    $result.runtime_events_seen = $true
    $result.probe_ready_event_seen = Has-EventType $eventsDocFinal "probe_ready"
  }
  $result.runtime_state_seen = ($state -ne $null)
  if (-not $result.runtime_state_seen) {
    $result.runtime_failure_phase = Resolve-RuntimeFailurePhase $result
    $result.diagnostic_summary = "runtime_state_missing; phase=" + $result.runtime_failure_phase + "; game_process_observed=" + [string]$result.game_process_observed + "; game_process_alive_at_timeout=" + [string]$result.game_process_alive_at_timeout + "; fixture_diagnostics_seen=" + [string]$result.fixture_diagnostics_seen + "; probe_ready_event_seen=" + [string]$result.probe_ready_event_seen
    throw "Runtime probe state was not written by the playtest fixture. Diagnostic phase: $($result.runtime_failure_phase)."
  }
  $result.runtime_failure_phase = "runtime_state_seen"

  $press = Invoke-EditorAction "playtest_input" @{
    steps = @(
      @{
        type = "action_press"
        action = $ActionName
        strength = 1.0
      }
    )
    reason = "visible_playtest_input_validation_press"
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.press_request_status = Get-ResponseStatus $press
  Assert-Succeeded "playtest_input press" $press

  $pressApplied = Wait-ForEvent $eventsPath "playtest_input_applied" $ActionName $RuntimeTimeoutSeconds
  $result.press_applied_event_seen = [bool]$pressApplied.found
  $pressed = Wait-ForEvent $eventsPath "input_action_pressed" $ActionName $RuntimeTimeoutSeconds
  $result.pressed_event_seen = [bool]$pressed.found
  if (-not $result.press_applied_event_seen -or -not $result.pressed_event_seen) {
    throw "Runtime did not record playtest input press events."
  }

  $release = Invoke-EditorAction "playtest_input" @{
    steps = @(
      @{
        type = "action_release"
        action = $ActionName
      }
    )
    reason = "visible_playtest_input_validation_release"
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.release_request_status = Get-ResponseStatus $release
  Assert-Succeeded "playtest_input release" $release

  $releaseApplied = Wait-ForEvent $eventsPath "playtest_input_applied" $ActionName $RuntimeTimeoutSeconds
  $result.release_applied_event_seen = [bool]$releaseApplied.found
  $released = Wait-ForEvent $eventsPath "input_action_released" $ActionName $RuntimeTimeoutSeconds
  $result.released_event_seen = [bool]$released.found
  if (-not $result.released_event_seen) {
    throw "Runtime did not record playtest input release event."
  }

  $stop = Invoke-EditorAction "stop_running_scene" @{} $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.stop_status = Get-ResponseStatus $stop
  Assert-Succeeded "stop_running_scene" $stop
  $result.stop_was_playing = [bool]$stop.response.data.was_playing
  $result.stop_stopped = [bool]$stop.response.data.stopped

  $result.status = "ok"
}
catch {
  $result.status = "error"
  $result.error = $_.Exception.Message
  if ($result.runtime_failure_phase -eq $null) {
    $result.runtime_failure_phase = Resolve-RuntimeFailurePhase $result
  }
}
finally {
  try {
    [void](Invoke-EditorAction "stop_running_scene" @{} $requestsDir $responsesDir 5)
  }
  catch {
    $result.final_stop_error = $_.Exception.Message
  }

  foreach ($entry in $permissionPrevious.GetEnumerator()) {
    try {
      [void](Send-BridgeRequest "set_bridge_permission" @{
        requested_by = "playtest_input_visible_validation"
        validation_token = "GCB_VALIDATE_PERMISSION_TOGGLE"
        key = [string]$entry.Key
        value = [bool]$entry.Value
      } $requestsDir $responsesDir 5)
    }
    catch {
      $result.permission_restore_error = $_.Exception.Message
    }
  }

  if (-not $KeepOpen) {
    foreach ($pidValue in @($observedPlayProcessIds.Keys)) {
      $playPid = [int]$pidValue
      if ($process -and $playPid -eq [int]$process.Id) {
        continue
      }
      try {
        $playProcess = Get-Process -Id $playPid -ErrorAction SilentlyContinue
        if ($playProcess -ne $null) {
          Stop-Process -Id $playPid -Force -ErrorAction SilentlyContinue
          $result.cleaned_play_process_ids += ,$playPid
        }
      }
      catch {
        $result.play_process_cleanup_error = $_.Exception.Message
      }
    }
  }

  if (-not $KeepOpen -and $process) {
    $launchedEditorSnapshot = @(Get-GodotProcessSnapshot $resolvedProjectRoot ($process.Id))
    foreach ($entry in @($launchedEditorSnapshot)) {
      $entryPid = [int]$entry.pid
      if ($entryPid -eq [int]$process.Id) {
        continue
      }
      if ([int]$entry.parent_pid -ne [int]$process.Id) {
        continue
      }
      try {
        $childProcess = Get-Process -Id $entryPid -ErrorAction SilentlyContinue
        if ($childProcess -ne $null) {
          Stop-Process -Id $entryPid -Force -ErrorAction SilentlyContinue
          $result.cleaned_play_process_ids += ,$entryPid
        }
      }
      catch {
        $result.editor_child_cleanup_error = $_.Exception.Message
      }
    }
  }

  if (-not $KeepOpen -and $process -and -not $process.HasExited) {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
  }

  $result.process_snapshot_final = @(Get-GodotProcessSnapshot $resolvedProjectRoot ($process.Id))
  $result.editor_stdout_sample = Read-TextTailSample $editorStdoutPath 20
  $result.editor_stderr_sample = Read-TextTailSample $editorStderrPath 20
  $result.completed_at = (Get-Date).ToUniversalTime().ToString("o")
  $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportPath -Encoding UTF8
}

$result | ConvertTo-Json -Depth 12
if ($result.status -ne "ok") {
  exit 1
}
