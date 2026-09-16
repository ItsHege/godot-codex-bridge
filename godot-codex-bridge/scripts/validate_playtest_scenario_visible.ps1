param(
  [string] $ProjectRoot = "examples\minimal_3d_project",
  [string] $GodotExecutable = $(if ($env:GODOT_BIN) { $env:GODOT_BIN } elseif (Get-Command godot -ErrorAction SilentlyContinue) { (Get-Command godot).Source } else { "godot" }),
  [string] $ScenePath = "res://scenes/playtest_input_fixture.tscn",
  [string] $ScenarioPath = "",
  [string] $ActionName = "gcb_playtest_jump",
  [int] $StartupTimeoutSeconds = 45,
  [int] $RequestTimeoutSeconds = 20,
  [int] $RuntimeTimeoutSeconds = 20,
  [int] $MaxSteps = 32,
  [int] $MaxScenarioSeconds = 30,
  [switch] $RequireFutureRunner,
  [switch] $RequireEvidenceRefs,
  [switch] $ContractOnly,
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

function Get-Field($Value, [string] $Name, $Default = $null) {
  if ($null -eq $Value) {
    return $Default
  }
  if ($Value -is [System.Collections.IDictionary] -and $Value.Contains($Name)) {
    return $Value[$Name]
  }
  $property = $Value.PSObject.Properties[$Name]
  if ($null -ne $property) {
    return $property.Value
  }
  return $Default
}

function Test-ObjectLike($Value) {
  if ($null -eq $Value) {
    return $false
  }
  if ($Value -is [System.Collections.IDictionary]) {
    return $true
  }
  return ($Value -is [pscustomobject])
}

function New-DefaultScenario([string] $ScenarioScenePath, [string] $ScenarioActionName) {
  $steps = @(
    [ordered]@{
      id = "capture_baseline_state"
      type = "capture"
      source = "runtime_state"
    },
    [ordered]@{
      id = "assert_marker_node_exists"
      type = "assert"
      assertion = "runtime_state_node_exists"
      node_path = "/root/PlaytestInputFixture/PlaytestMarker"
    },
    [ordered]@{
      id = "press_jump"
      type = "press_action"
      action = $ScenarioActionName
      strength = 1.0
    },
    [ordered]@{
      id = "wait_after_press"
      type = "wait_seconds"
      seconds = 0.5
    }
  )

  if ($RequireEvidenceRefs) {
    $steps += [ordered]@{
      id = "capture_timeline_screenshot"
      type = "capture"
      source = "timeline_screenshot"
      frame_count = 2
      interval_ms = 50
    }
  }

  $steps += @(
    [ordered]@{
      id = "capture_runtime_state"
      type = "capture"
      source = "runtime_state"
    },
    [ordered]@{
      id = "assert_marker_moved_up"
      type = "assert"
      assertion = "runtime_state_position_delta"
      node_path = "/root/PlaytestInputFixture/PlaytestMarker"
      axis = "y"
      min_delta = 1.0
      epsilon = 0.05
    },
    [ordered]@{
      id = "assert_jump_pressed_event"
      type = "assert"
      assertion = "runtime_event_present"
      event_type = "input_action_pressed"
      action = $ScenarioActionName
    },
    [ordered]@{
      id = "release_jump"
      type = "release_action"
      action = $ScenarioActionName
    },
    [ordered]@{
      id = "assert_jump_released_event"
      type = "assert"
      assertion = "runtime_event_present"
      event_type = "input_action_released"
      action = $ScenarioActionName
    }
  )

  return [ordered]@{
    scenario_version = "godot-codex-bridge/playtest-scenario-v1"
    scene_path = $ScenarioScenePath
    global_timeout_seconds = 10
    steps = $steps
  }
}

function Read-ScenarioDocument([string] $PathValue, [string] $DefaultScenePath, [string] $DefaultActionName) {
  if ([string]::IsNullOrWhiteSpace($PathValue)) {
    return New-DefaultScenario $DefaultScenePath $DefaultActionName
  }
  $resolved = Resolve-FullPath $PathValue (Get-Location).Path
  if (-not (Test-Path -LiteralPath $resolved)) {
    throw "ScenarioPath not found: $resolved"
  }
  $raw = Get-Content -Raw -LiteralPath $resolved
  return $raw | ConvertFrom-Json
}

function Test-ActionName([string] $Value) {
  return ($Value -match "^[A-Za-z0-9_.:-]{1,96}$")
}

function Add-ScenarioError([System.Collections.Generic.List[string]] $Errors, [string] $Message) {
  $Errors.Add($Message) | Out-Null
}

function Validate-ScenarioDocument($Scenario, [int] $StepLimit, [int] $ScenarioSecondsLimit) {
  $errors = New-Object System.Collections.Generic.List[string]
  $normalizedSteps = New-Object System.Collections.Generic.List[object]

  if (-not (Test-ObjectLike $Scenario)) {
    Add-ScenarioError $errors "scenario must be an object"
    return [ordered]@{ ok = $false; errors = @($errors.ToArray()); normalized_steps = @(); step_count = 0; estimated_duration_seconds = 0 }
  }

  $version = [string](Get-Field $Scenario "scenario_version" "")
  if ($version -ne "godot-codex-bridge/playtest-scenario-v1") {
    Add-ScenarioError $errors "scenario_version must be godot-codex-bridge/playtest-scenario-v1"
  }

  $scenePathValue = [string](Get-Field $Scenario "scene_path" "")
  if (-not $scenePathValue.StartsWith("res://")) {
    Add-ScenarioError $errors "scene_path must be a res:// path"
  }

  $timeoutSeconds = [double](Get-Field $Scenario "global_timeout_seconds" 0)
  if ($timeoutSeconds -le 0 -or $timeoutSeconds -gt $ScenarioSecondsLimit) {
    Add-ScenarioError $errors "global_timeout_seconds must be > 0 and <= $ScenarioSecondsLimit"
  }

  if ($null -ne (Get-Field $Scenario "loop" $null) -or $null -ne (Get-Field $Scenario "repeat" $null)) {
    Add-ScenarioError $errors "scenario-level loops/repeats are not supported"
  }

  $rawSteps = Get-Field $Scenario "steps" @()
  $steps = @($rawSteps)
  if ($steps.Count -eq 0) {
    Add-ScenarioError $errors "steps must contain at least one step"
  }
  if ($steps.Count -gt $StepLimit) {
    Add-ScenarioError $errors "steps exceeds max step cap $StepLimit"
  }

  $estimatedDuration = 0.0
  $allowedCaptureSources = @("runtime_state", "runtime_events", "fixture_diagnostics", "viewport_screenshot", "timeline_screenshot")
  $allowedAssertions = @(
    "runtime_event_present",
    "fixture_marker_y_increased",
    "runtime_state_node_exists",
    "runtime_state_position_delta",
    "runtime_state_rotation_delta",
    "runtime_state_active_scene",
    "runtime_scene_changed"
  )

  for ($index = 0; $index -lt $steps.Count; $index++) {
    $step = $steps[$index]
    if (-not (Test-ObjectLike $step)) {
      Add-ScenarioError $errors "step $index must be an object"
      continue
    }
    if ($null -ne (Get-Field $step "loop" $null) -or $null -ne (Get-Field $step "repeat" $null)) {
      Add-ScenarioError $errors "step $index loops/repeats are not supported"
    }
    $type = [string](Get-Field $step "type" "")
    $id = [string](Get-Field $step "id" ("step_" + $index))
    $entry = [ordered]@{
      index = $index
      id = $id
      type = $type
    }

    switch ($type) {
      "press_action" {
        $action = [string](Get-Field $step "action" "")
        if (-not (Test-ActionName $action)) {
          Add-ScenarioError $errors "step $index press_action requires a safe action name"
        }
        $strength = [double](Get-Field $step "strength" 1.0)
        if ($strength -lt 0 -or $strength -gt 1) {
          Add-ScenarioError $errors "step $index strength must be between 0 and 1"
        }
        $entry.action = $action
        $entry.strength = $strength
      }
      "release_action" {
        $action = [string](Get-Field $step "action" "")
        if (-not (Test-ActionName $action)) {
          Add-ScenarioError $errors "step $index release_action requires a safe action name"
        }
        $entry.action = $action
      }
      "move_axis" {
        $negativeAction = [string](Get-Field $step "negative_action" (Get-Field $step "negativeAction" ""))
        $positiveAction = [string](Get-Field $step "positive_action" (Get-Field $step "positiveAction" ""))
        $value = [double](Get-Field $step "value" 0.0)
        if (-not (Test-ActionName $negativeAction) -or -not (Test-ActionName $positiveAction)) {
          Add-ScenarioError $errors "step $index move_axis requires safe negative_action and positive_action names"
        }
        if ($value -lt -1 -or $value -gt 1) {
          Add-ScenarioError $errors "step $index move_axis value must be between -1 and 1"
        }
        $entry.negative_action = $negativeAction
        $entry.positive_action = $positiveAction
        $entry.value = $value
      }
      "wait_seconds" {
        $seconds = [double](Get-Field $step "seconds" 0)
        if ($seconds -lt 0 -or $seconds -gt $ScenarioSecondsLimit) {
          Add-ScenarioError $errors "step $index wait_seconds must be >= 0 and <= $ScenarioSecondsLimit"
        }
        $estimatedDuration += $seconds
        $entry.seconds = $seconds
      }
      "wait_frames" {
        $frames = [int](Get-Field $step "frames" 0)
        if ($frames -le 0 -or $frames -gt 3600) {
          Add-ScenarioError $errors "step $index wait_frames must be between 1 and 3600"
        }
        $estimatedDuration += ([double]$frames / 60.0)
        $entry.frames = $frames
      }
      "capture" {
        $source = [string](Get-Field $step "source" "runtime_state")
        if (-not ($allowedCaptureSources -contains $source)) {
          Add-ScenarioError $errors "step $index capture source is unsupported: $source"
        }
        $entry.source = $source
        if ($source -eq "timeline_screenshot") {
          $frameCount = [int](Get-Field $step "frame_count" (Get-Field $step "frameCount" 3))
          $intervalMs = [int](Get-Field $step "interval_ms" (Get-Field $step "intervalMs" 250))
          if ($frameCount -lt 2 -or $frameCount -gt 12) {
            Add-ScenarioError $errors "step $index timeline_screenshot frame_count must be between 2 and 12"
          }
          if ($intervalMs -lt 50 -or $intervalMs -gt 5000) {
            Add-ScenarioError $errors "step $index timeline_screenshot interval_ms must be between 50 and 5000"
          }
          $entry.frame_count = $frameCount
          $entry.interval_ms = $intervalMs
        }
      }
      "assert" {
        $assertion = [string](Get-Field $step "assertion" "")
        if (-not ($allowedAssertions -contains $assertion)) {
          Add-ScenarioError $errors "step $index assertion is unsupported: $assertion"
        }
        $entry.assertion = $assertion
        $entry.event_type = [string](Get-Field $step "event_type" "")
        $entry.action = [string](Get-Field $step "action" "")
        $entry.min_delta = [double](Get-Field $step "min_delta" 0.0)
        $entry.max_delta = [double](Get-Field $step "max_delta" 1000000000000.0)
        $entry.epsilon = [double](Get-Field $step "epsilon" 0.0001)
        $entry.axis = [string](Get-Field $step "axis" "")
        $entry.node_path = [string](Get-Field $step "node_path" "")
      }
      default {
        Add-ScenarioError $errors "step $index has unsupported type: $type"
      }
    }

    $normalizedSteps.Add($entry) | Out-Null
  }

  if ($timeoutSeconds -gt 0 -and $estimatedDuration -gt $timeoutSeconds) {
    Add-ScenarioError $errors "estimated wait duration exceeds global_timeout_seconds"
  }

  return [ordered]@{
    ok = ($errors.Count -eq 0)
    errors = @($errors.ToArray())
    normalized_steps = @($normalizedSteps.ToArray())
    step_count = $steps.Count
    estimated_duration_seconds = [Math]::Round($estimatedDuration, 3)
    global_timeout_seconds = $timeoutSeconds
    max_steps = $StepLimit
    max_scenario_seconds = $ScenarioSecondsLimit
  }
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
  $request | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $requestPath -Encoding UTF8

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
    requested_by = "playtest_scenario_visible_validation"
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

function Get-ResponseErrorCode($Result) {
  if ($Result.response -eq $null) {
    return ""
  }
  if ($Result.response.error -ne $null -and $Result.response.error.code -ne $null) {
    return [string]$Result.response.error.code
  }
  if ($Result.response.data -ne $null -and $Result.response.data.error -ne $null -and $Result.response.data.error.code -ne $null) {
    return [string]$Result.response.data.error.code
  }
  return ""
}

function Get-ResponseErrorMessage($Result) {
  if ($Result.response -eq $null) {
    return ""
  }
  if ($Result.response.error -ne $null -and $Result.response.error.message -ne $null) {
    return [string]$Result.response.error.message
  }
  if ($Result.response.data -ne $null -and $Result.response.data.error -ne $null -and $Result.response.data.error.message -ne $null) {
    return [string]$Result.response.data.error.message
  }
  return ""
}

function Test-NotAvailableResponse($Result) {
  $code = Get-ResponseErrorCode $Result
  $message = Get-ResponseErrorMessage $Result
  if ($Result.timeout) {
    return $false
  }
  if ($code -match "unsupported_editor_action|run_playtest_scenario_unavailable|playtest_unavailable|not_implemented|unavailable") {
    return $true
  }
  return ($message -match "Unsupported editor_control action|not available|not implemented")
}

function Assert-Succeeded([string] $Name, $Result) {
  $status = Get-ResponseStatus $Result
  if ($status -ne "succeeded") {
    $raw = if ($Result.response -ne $null) { $Result.response | ConvertTo-Json -Depth 12 } else { $status }
    throw "$Name failed: $raw"
  }
}

function Assert-FutureRunnerEvidenceRefs($Response) {
  if ($Response -eq $null -or $Response.data -eq $null) {
    throw "run_playtest_scenario evidence check failed: missing response data."
  }
  $data = $Response.data
  if ($data.evidence -eq $null) {
    throw "run_playtest_scenario evidence check failed: missing top-level evidence."
  }
  if ([string]::IsNullOrWhiteSpace([string]$data.evidence.runtime_state_path)) {
    throw "run_playtest_scenario evidence check failed: missing runtime_state_path."
  }
  if ([string]::IsNullOrWhiteSpace([string]$data.evidence.runtime_events_path)) {
    throw "run_playtest_scenario evidence check failed: missing runtime_events_path."
  }
  $captureCount = 0
  if ($data.evidence.captures -ne $null) {
    $captureCount = @($data.evidence.captures).Count
  }
  if ($captureCount -lt 2) {
    throw "run_playtest_scenario evidence check failed: expected at least two captures, got $captureCount."
  }

  $assertionCount = 0
  foreach ($step in @($data.steps)) {
    if ([string]$step.type -ne "assert" -or $step.data -eq $null) {
      continue
    }
    $assertionCount += 1
    if ($step.data.evidence -eq $null) {
      throw "run_playtest_scenario evidence check failed: assertion step $($step.index) has no evidence."
    }
  }
  if ($assertionCount -lt 3) {
    throw "run_playtest_scenario evidence check failed: expected at least three assertion evidence entries, got $assertionCount."
  }

  $timelineCount = 0
  foreach ($capture in @($data.evidence.captures)) {
    if ([string]$capture.source -ne "timeline_screenshot") {
      continue
    }
    $timelineCount += 1
    $frames = @($capture.frames)
    if ($frames.Count -lt 2) {
      throw "run_playtest_scenario evidence check failed: timeline_screenshot capture has fewer than two frames."
    }
    foreach ($frame in $frames) {
      if ($frame.artifact -eq $null -or [string]::IsNullOrWhiteSpace([string]$frame.artifact.path)) {
        throw "run_playtest_scenario evidence check failed: timeline frame is missing a scenario artifact path."
      }
    }
  }
  if ($timelineCount -lt 1) {
    throw "run_playtest_scenario evidence check failed: expected at least one timeline_screenshot capture."
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

function Has-Event([object] $EventsDoc, [string] $Type, [string] $ActionNameValue) {
  if ($EventsDoc -eq $null -or $EventsDoc.events -eq $null) {
    return $false
  }
  foreach ($event in @($EventsDoc.events)) {
    if ([string]$event.type -ne $Type) {
      continue
    }
    if ([string]::IsNullOrWhiteSpace($ActionNameValue)) {
      return $true
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

function Wait-ForFixtureMarkerY([string] $DiagnosticsPath, [double] $MinDelta, [int] $TimeoutSeconds) {
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    $diagnostics = Read-JsonFileOrNull $DiagnosticsPath
    if (
      $diagnostics -ne $null -and
      $diagnostics.details -ne $null -and
      $diagnostics.details.marker_position -ne $null
    ) {
      $y = [double]$diagnostics.details.marker_position.y
      if ($y -ge $MinDelta) {
        return [ordered]@{
          found = $true
          y = $y
          diagnostics = $diagnostics
        }
      }
    }
    Start-Sleep -Milliseconds 250
  }
  return [ordered]@{
    found = $false
    y = $null
    diagnostics = (Read-JsonFileOrNull $DiagnosticsPath)
  }
}

function Add-StepResult([System.Collections.ArrayList] $StepResults, $Step, [string] $Status, [hashtable] $Details = @{}) {
  $entry = [ordered]@{
    index = [int]$Step.index
    id = [string]$Step.id
    type = [string]$Step.type
    status = $Status
  }
  foreach ($key in $Details.Keys) {
    $entry[$key] = $Details[$key]
  }
  $StepResults.Add($entry) | Out-Null
}

function Invoke-ScenarioFallback($ScenarioValidation, [string] $RequestsDir, [string] $ResponsesDir, [string] $StatePath, [string] $EventsPath, [string] $FixtureDiagnosticsPath, [int] $RequestTimeout, [int] $RuntimeTimeout) {
  $stepResults = New-Object System.Collections.ArrayList
  foreach ($step in @($ScenarioValidation.normalized_steps)) {
    switch ([string]$step.type) {
      "press_action" {
        $press = Invoke-EditorAction "playtest_input" @{
          steps = @(
            @{
              type = "action_press"
              action = [string]$step.action
              strength = [double]$step.strength
            }
          )
          reason = "visible_playtest_scenario_press:" + [string]$step.id
        } $RequestsDir $ResponsesDir $RequestTimeout
        Assert-Succeeded ("scenario step " + [string]$step.id) $press
        Add-StepResult $stepResults $step "ok" @{ request_status = Get-ResponseStatus $press }
      }
      "release_action" {
        $release = Invoke-EditorAction "playtest_input" @{
          steps = @(
            @{
              type = "action_release"
              action = [string]$step.action
            }
          )
          reason = "visible_playtest_scenario_release:" + [string]$step.id
        } $RequestsDir $ResponsesDir $RequestTimeout
        Assert-Succeeded ("scenario step " + [string]$step.id) $release
        Add-StepResult $stepResults $step "ok" @{ request_status = Get-ResponseStatus $release }
      }
      "move_axis" {
        $axis = Invoke-EditorAction "playtest_input" @{
          steps = @(
            @{
              type = "axis"
              negative_action = [string]$step.negative_action
              positive_action = [string]$step.positive_action
              value = [double]$step.value
            }
          )
          reason = "visible_playtest_scenario_axis:" + [string]$step.id
        } $RequestsDir $ResponsesDir $RequestTimeout
        Assert-Succeeded ("scenario step " + [string]$step.id) $axis
        Add-StepResult $stepResults $step "ok" @{ request_status = Get-ResponseStatus $axis }
      }
      "wait_seconds" {
        Start-Sleep -Milliseconds ([int]([double]$step.seconds * 1000.0))
        Add-StepResult $stepResults $step "ok" @{ waited_seconds = [double]$step.seconds }
      }
      "wait_frames" {
        $milliseconds = [int](([double]$step.frames / 60.0) * 1000.0)
        Start-Sleep -Milliseconds $milliseconds
        Add-StepResult $stepResults $step "ok" @{ waited_frames = [int]$step.frames; approximated_ms = $milliseconds }
      }
      "capture" {
        $source = [string]$step.source
        $path = $null
        $seen = $false
        if ($source -eq "runtime_state") {
          $path = $StatePath
          $seen = (Read-JsonFileOrNull $StatePath) -ne $null
        } elseif ($source -eq "runtime_events") {
          $path = $EventsPath
          $seen = (Read-JsonFileOrNull $EventsPath) -ne $null
        } elseif ($source -eq "fixture_diagnostics") {
          $path = $FixtureDiagnosticsPath
          $seen = (Read-JsonFileOrNull $FixtureDiagnosticsPath) -ne $null
        } else {
          Add-StepResult $stepResults $step "not_available" @{ reason = "fallback_capture_source_not_available"; source = $source }
          break
        }
        if (-not $seen) {
          throw "Scenario capture step $($step.id) could not read $source."
        }
        Add-StepResult $stepResults $step "ok" @{ source = $source; path = $path }
      }
      "assert" {
        $assertion = [string]$step.assertion
        if ($assertion -eq "runtime_event_present") {
          $eventResult = Wait-ForEvent $EventsPath ([string]$step.event_type) ([string]$step.action) $RuntimeTimeout
          if (-not [bool]$eventResult.found) {
            throw "Scenario assertion failed: event $($step.event_type) action $($step.action) not found."
          }
          Add-StepResult $stepResults $step "ok" @{ assertion = $assertion; event_type = [string]$step.event_type; action = [string]$step.action }
        } elseif ($assertion -eq "fixture_marker_y_increased") {
          $marker = Wait-ForFixtureMarkerY $FixtureDiagnosticsPath ([double]$step.min_delta) $RuntimeTimeout
          if (-not [bool]$marker.found) {
            throw "Scenario assertion failed: fixture marker y did not increase by $($step.min_delta)."
          }
          Add-StepResult $stepResults $step "ok" @{ assertion = $assertion; observed_y = [double]$marker.y; min_delta = [double]$step.min_delta }
        } else {
          Add-StepResult $stepResults $step "not_available" @{ reason = "fallback_assertion_not_available"; assertion = $assertion }
          throw "Scenario assertion $assertion is valid for the contract but unavailable in the fallback runner."
        }
      }
      default {
        Add-StepResult $stepResults $step "not_available" @{ reason = "fallback_step_type_not_available" }
        throw "Scenario step type $($step.type) is valid for the contract but unavailable in the fallback runner."
      }
    }
  }

  return [ordered]@{
    status = "ok"
    step_results = @($stepResults.ToArray())
  }
}

$productRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$resolvedProjectRoot = Resolve-FullPath $ProjectRoot $productRoot
$resolvedGodot = Resolve-FullPath $GodotExecutable (Get-Location).Path
$projectFile = Join-Path $resolvedProjectRoot "project.godot"
$sceneFile = Convert-ResPathToAbsolute $resolvedProjectRoot $ScenePath

if (-not (Test-Path -LiteralPath $projectFile)) {
  throw "Wrong project root, project.godot not found: $resolvedProjectRoot"
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
$reportPath = Join-Path $artifactsDir "playtest_scenario_visible_validation.json"
$editorStdoutPath = Join-Path $artifactsDir "playtest_scenario_visible_editor_stdout.txt"
$editorStderrPath = Join-Path $artifactsDir "playtest_scenario_visible_editor_stderr.txt"

New-Item -ItemType Directory -Force -Path $requestsDir, $responsesDir, $artifactsDir, $runtimeDir | Out-Null

$scenario = Read-ScenarioDocument $ScenarioPath $ScenePath $ActionName
$scenarioValidation = Validate-ScenarioDocument $scenario $MaxSteps $MaxScenarioSeconds
$invalidLoopScenario = [ordered]@{
  scenario_version = "godot-codex-bridge/playtest-scenario-v1"
  scene_path = $ScenePath
  global_timeout_seconds = $MaxScenarioSeconds + 1
  repeat = "forever"
  steps = @(
    [ordered]@{
      type = "wait_seconds"
      seconds = $MaxScenarioSeconds + 1
    }
  )
}
$invalidLoopValidation = Validate-ScenarioDocument $invalidLoopScenario $MaxSteps $MaxScenarioSeconds

$result = [ordered]@{
  status = "started"
  started_at = (Get-Date).ToUniversalTime().ToString("o")
  project_root = $resolvedProjectRoot
  godot_executable = $resolvedGodot
  scene_path = $ScenePath
  scenario_path = $ScenarioPath
  scenario = $scenario
  scenario_contract = $scenarioValidation
  invalid_loop_contract_rejected = (-not [bool]$invalidLoopValidation.ok)
  invalid_loop_contract_errors = @($invalidLoopValidation.errors)
  report_path = $reportPath
  runtime_state_path = $statePath
  runtime_events_path = $eventsPath
  fixture_diagnostics_path = $fixtureDiagnosticsPath
  editor_stdout_path = $editorStdoutPath
  editor_stderr_path = $editorStderrPath
  editor_stdout_sample = $null
  editor_stderr_sample = $null
  process_id = $null
  heartbeat_live = $false
  heartbeat_age_ms = $null
  open_scene_status = $null
  enable_run_permission_status = $null
  enable_playtest_permission_status = $null
  future_runner_status = "not_run"
  future_runner_error_code = $null
  future_runner_error_message = $null
  future_runner_response = $null
  future_runner_evidence_refs_ok = $false
  fallback_runner_status = "not_run"
  fallback_runner_reason = $null
  fallback_step_results = @()
  run_status = $null
  run_started = $null
  playtest_session_ready = $null
  run_scene_file_path = $null
  runtime_state_seen = $false
  stop_status = $null
  stop_was_playing = $null
  stop_stopped = $null
  cleaned_play_process_ids = @()
  process_snapshot_final = @()
}

if (-not [bool]$scenarioValidation.ok) {
  $result.status = "error"
  $result.error = "Scenario contract validation failed."
  $result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $reportPath -Encoding UTF8
  $result | ConvertTo-Json -Depth 20
  exit 1
}
if ([bool]$invalidLoopValidation.ok) {
  $result.status = "error"
  $result.error = "Negative contract validation did not reject an unbounded scenario."
  $result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $reportPath -Encoding UTF8
  $result | ConvertTo-Json -Depth 20
  exit 1
}

if ($ContractOnly) {
  $result.status = "ok"
  $result.future_runner_status = "not_run"
  $result.fallback_runner_status = "not_run"
  $result.fallback_runner_reason = "contract_only"
  $result.completed_at = (Get-Date).ToUniversalTime().ToString("o")
  $result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $reportPath -Encoding UTF8
  $result | ConvertTo-Json -Depth 20
  exit 0
}

if (-not (Test-Path -LiteralPath $resolvedGodot)) {
  $result.status = "error"
  $result.error = "Godot executable not found: $resolvedGodot"
  $result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $reportPath -Encoding UTF8
  $result | ConvertTo-Json -Depth 20
  exit 1
}

Remove-Item -LiteralPath $eventsPath, $statePath, $inputCommandsPath, $playtestSessionPath, $fixtureDiagnosticsPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $editorStdoutPath, $editorStderrPath -Force -ErrorAction SilentlyContinue

$process = $null
$permissionPrevious = @{}
$observedPlayProcessIds = @{}

try {
  $process = Start-Process `
    -FilePath $resolvedGodot `
    -ArgumentList @("--path", $resolvedProjectRoot, "--editor") `
    -PassThru `
    -RedirectStandardOutput $editorStdoutPath `
    -RedirectStandardError $editorStderrPath
  $result.process_id = $process.Id

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

  [void](Invoke-EditorAction "stop_running_scene" @{} $requestsDir $responsesDir 5)

  $openScene = Send-BridgeRequest "open_scene" @{
    requested_by = "playtest_scenario_visible_validation"
    scene_path = $ScenePath
    make_main_screen = "3D"
    select_in_file_system = $true
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.open_scene_status = Get-ResponseStatus $openScene
  Assert-Succeeded "open_scene" $openScene

  foreach ($permission in @("allow_run_current_scene", "allow_playtest_input")) {
    $toggle = Send-BridgeRequest "set_bridge_permission" @{
      requested_by = "playtest_scenario_visible_validation"
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

  $futureTimeout = [Math]::Max($RequestTimeoutSeconds, [int]$scenarioValidation.global_timeout_seconds + $RequestTimeoutSeconds)
  $future = Invoke-EditorAction "run_playtest_scenario" @{
    scenario = $scenario
    validation_mode = "visible"
  } $requestsDir $responsesDir $futureTimeout
  $result.future_runner_response = $future.response

  if ((Get-ResponseStatus $future) -eq "succeeded") {
    $result.future_runner_status = "succeeded"
    if ($RequireEvidenceRefs) {
      Assert-FutureRunnerEvidenceRefs $future.response
      $result.future_runner_evidence_refs_ok = $true
    }
    $result.status = "ok"
  } elseif (Test-NotAvailableResponse $future) {
    $result.future_runner_status = "not_available"
    $result.future_runner_error_code = Get-ResponseErrorCode $future
    $result.future_runner_error_message = Get-ResponseErrorMessage $future
    if ($RequireFutureRunner) {
      throw "run_playtest_scenario is not available: $($result.future_runner_error_code)"
    }
  } else {
    $result.future_runner_status = Get-ResponseStatus $future
    $result.future_runner_error_code = Get-ResponseErrorCode $future
    $result.future_runner_error_message = Get-ResponseErrorMessage $future
    throw "run_playtest_scenario returned an unexpected result: $($result.future_runner_status) $($result.future_runner_error_code) $($result.future_runner_error_message)"
  }

  if ($result.future_runner_status -ne "succeeded") {
    $run = Send-BridgeRequest "run_current_scene" @{
      requested_by = "playtest_scenario_visible_validation"
      scene_path = $ScenePath
    } $requestsDir $responsesDir $RequestTimeoutSeconds
    $result.run_status = Get-ResponseStatus $run
    Assert-Succeeded "run_current_scene" $run
    $result.run_started = [bool]$run.response.data.started
    $result.playtest_session_ready = [bool]$run.response.data.playtest_session_ready
    $result.run_scene_file_path = [string]$run.response.data.scene_file_path
    if (-not $result.run_started -or -not $result.playtest_session_ready) {
      throw "run_current_scene did not start with a ready playtest session."
    }
    if ($result.run_scene_file_path -ne $ScenePath) {
      throw "run_current_scene started $($result.run_scene_file_path), expected $ScenePath."
    }

    $state = Wait-ForRuntimeState $statePath $RuntimeTimeoutSeconds
    $result.runtime_state_seen = ($state -ne $null)
    if (-not $result.runtime_state_seen) {
      throw "Runtime probe state was not written by the playtest fixture."
    }

    $fallback = Invoke-ScenarioFallback $scenarioValidation $requestsDir $responsesDir $statePath $eventsPath $fixtureDiagnosticsPath $RequestTimeoutSeconds $RuntimeTimeoutSeconds
    $result.fallback_runner_status = [string]$fallback.status
    $result.fallback_step_results = @($fallback.step_results)
    $result.status = "ok"
  }

  $stop = Invoke-EditorAction "stop_running_scene" @{} $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.stop_status = Get-ResponseStatus $stop
  Assert-Succeeded "stop_running_scene" $stop
  $result.stop_was_playing = [bool]$stop.response.data.was_playing
  $result.stop_stopped = [bool]$stop.response.data.stopped
}
catch {
  $result.status = "error"
  $result.error = $_.Exception.Message
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
        requested_by = "playtest_scenario_visible_validation"
        validation_token = "GCB_VALIDATE_PERMISSION_TOGGLE"
        key = [string]$entry.Key
        value = [bool]$entry.Value
      } $requestsDir $responsesDir 5)
    }
    catch {
      $result.permission_restore_error = $_.Exception.Message
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

  if ($process) {
    $result.process_snapshot_final = @(Get-GodotProcessSnapshot $resolvedProjectRoot ($process.Id))
  }
  $result.editor_stdout_sample = Read-TextTailSample $editorStdoutPath 20
  $result.editor_stderr_sample = Read-TextTailSample $editorStderrPath 20
  $result.completed_at = (Get-Date).ToUniversalTime().ToString("o")
  $result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $reportPath -Encoding UTF8
}

$result | ConvertTo-Json -Depth 20
if ($result.status -ne "ok") {
  exit 1
}
