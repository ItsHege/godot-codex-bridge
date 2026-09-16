param(
  [string] $ProjectRoot = "examples\minimal_3d_project",
  [string] $GodotExecutable = $(if ($env:GODOT_BIN) { $env:GODOT_BIN } elseif (Get-Command godot -ErrorAction SilentlyContinue) { (Get-Command godot).Source } else { "godot" }),
  [int] $Port = 49390,
  [int] $AppServerPort = 49391,
  [int] $StartupTimeoutSeconds = 45,
  [int] $RequestTimeoutSeconds = 20,
  [int] $TurnTimeoutSeconds = 180,
  [ValidateSet("mock", "app-server")]
  [string] $Runtime = "mock",
  [switch] $ChatOnly,
  [switch] $RequireAgentsMarker,
  [switch] $RequireSceneContext,
  [switch] $AddonStartsHost,
  [switch] $KeepOpen
)

$ErrorActionPreference = "Stop"

function Resolve-FullPath([string] $PathValue, [string] $BasePath) {
  if ([System.IO.Path]::IsPathRooted($PathValue)) {
    return [System.IO.Path]::GetFullPath($PathValue)
  }
  return [System.IO.Path]::GetFullPath((Join-Path $BasePath $PathValue))
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
        request_path = $requestPath
        response_path = $responsePath
        response = ($raw | ConvertFrom-Json)
        timeout = $false
      }
    }
    Start-Sleep -Milliseconds 250
  }

  return [ordered]@{
    request_path = $requestPath
    response_path = $responsePath
    response = $null
    timeout = $true
  }
}

function Get-EventLines([string] $EventLogPath, [int] $Skip) {
  if (-not (Test-Path -LiteralPath $EventLogPath)) {
    return @()
  }
  $lines = @(Get-Content -LiteralPath $EventLogPath)
  if ($lines.Count -le $Skip) {
    return @()
  }
  return @($lines | Select-Object -Skip $Skip)
}

function Wait-Event([string] $EventLogPath, [int] $Skip, [scriptblock] $Predicate, [int] $TimeoutSeconds) {
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    foreach ($line in (Get-EventLines $EventLogPath $Skip)) {
      if ([string]::IsNullOrWhiteSpace($line)) {
        continue
      }
      try {
        $event = $line | ConvertFrom-Json
        if (& $Predicate $event) {
          return $event
        }
      } catch {
      }
    }
    Start-Sleep -Milliseconds 250
  }
  return $null
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

function Wait-TurnCompletedThroughAddon([string] $EventLogPath, [int] $Skip, [string] $RequestsDir, [string] $ResponsesDir, [int] $TimeoutSeconds, [bool] $AutoRejectApprovals) {
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  $respondedApprovals = @{}
  $text = New-Object System.Text.StringBuilder
  $approvalCount = 0
  $autoRejected = 0
  while ((Get-Date) -lt $deadline) {
    foreach ($line in (Get-EventLines $EventLogPath $Skip)) {
      if ([string]::IsNullOrWhiteSpace($line)) {
        continue
      }
      try {
        $event = $line | ConvertFrom-Json
      } catch {
        continue
      }
      if ($event.method -eq "turn.event" -and $event.params.event -eq "agent_message_delta") {
        [void]$text.Append([string]$event.params.text)
      }
      if ($event.method -eq "approval.requested") {
        $approvalCount += 1
        $approvalId = [string]$event.params.approval_id
        if ($AutoRejectApprovals -and $approvalId -ne "" -and -not $respondedApprovals.ContainsKey($approvalId)) {
          Start-Sleep -Seconds 1
          $response = Invoke-RetryBridgeRequest "respond_codex_chat_approval" @{
            decision = "reject"
            note = "validate_visible_chat_editor auto reject for smoke"
          } $RequestsDir $ResponsesDir 10 3
          if ($response.response -ne $null -and $response.response.status -eq "succeeded") {
            $autoRejected += 1
            $respondedApprovals[$approvalId] = $true
          }
        }
      }
      if ($event.method -eq "turn.completed") {
        return [ordered]@{
          completed = $true
          text = $text.ToString()
          approval_count = $approvalCount
          auto_rejected_approvals = $autoRejected
        }
      }
    }
    Start-Sleep -Milliseconds 250
  }
  return [ordered]@{
    completed = $false
    text = $text.ToString()
    approval_count = $approvalCount
    auto_rejected_approvals = $autoRejected
  }
}

function Get-ListeningProcessIds([int] $Port) {
  try {
    return @(
      Get-NetTCPConnection -LocalAddress "127.0.0.1" -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty OwningProcess -Unique
    )
  } catch {
    return @()
  }
}

function Stop-ListeningPortProcesses([int] $Port) {
  foreach ($processId in (Get-ListeningProcessIds $Port)) {
    if ($processId -gt 0) {
      Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
    }
  }
}

function Get-CurrentScenePathFromSnapshot([string] $BridgeDir) {
  $snapshotPath = Join-Path $BridgeDir "context_snapshot.json"
  if (-not (Test-Path -LiteralPath $snapshotPath)) {
    return $null
  }
  try {
    $snapshot = Get-Content -Raw -LiteralPath $snapshotPath | ConvertFrom-Json
    if ($snapshot.current_scene -ne $null -and -not [string]::IsNullOrWhiteSpace([string]$snapshot.current_scene.path)) {
      return [string]$snapshot.current_scene.path
    }
    if ($snapshot.project -ne $null -and -not [string]::IsNullOrWhiteSpace([string]$snapshot.project.main_scene)) {
      return [string]$snapshot.project.main_scene
    }
  } catch {
    return $null
  }
  return $null
}

$productRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$hostRoot = Join-Path $productRoot "codex_host"
$resolvedProjectRoot = Resolve-FullPath $ProjectRoot $productRoot
$resolvedGodot = Resolve-FullPath $GodotExecutable (Get-Location).Path
$projectFile = Join-Path $resolvedProjectRoot "project.godot"

if (-not (Test-Path -LiteralPath $projectFile)) {
  throw "Wrong project root, project.godot not found: $resolvedProjectRoot"
}
if (-not (Test-Path -LiteralPath $resolvedGodot)) {
  throw "Godot executable not found: $resolvedGodot"
}

$bridgeDir = Join-Path $resolvedProjectRoot ".godot\godot_codex_bridge"
$requestsDir = Join-Path $bridgeDir "requests"
$responsesDir = Join-Path $bridgeDir "responses"
$artifactsDir = Join-Path $bridgeDir "artifacts"
$heartbeatPath = Join-Path $bridgeDir "heartbeat.json"
$eventLogPath = Join-Path $bridgeDir "codex_host\events\host-events.jsonl"
$hostConfigPath = Join-Path $resolvedProjectRoot "addons\godot_codex_bridge\host_config.json"
$reportName = if ($AddonStartsHost) {
  "visible_chat_editor_autostart_$Runtime`_validation.json"
} elseif ($Runtime -eq "app-server" -and $ChatOnly) {
  "visible_chat_editor_real_app_server_validation.json"
} elseif ($Runtime -eq "mock" -and -not $ChatOnly) {
  "visible_chat_editor_validation.json"
} else {
  "visible_chat_editor_$Runtime`_validation.json"
}
$reportPath = Join-Path $artifactsDir $reportName

New-Item -ItemType Directory -Force -Path $requestsDir, $responsesDir, $artifactsDir | Out-Null
$eventLineStart = if (Test-Path -LiteralPath $eventLogPath) { @(Get-Content -LiteralPath $eventLogPath).Count } else { 0 }

$hostProcess = $null
$godotProcess = $null
$result = [ordered]@{
  status = "started"
  started_at = (Get-Date).ToUniversalTime().ToString("o")
  project_root = $resolvedProjectRoot
  godot_executable = $resolvedGodot
  host_port = $Port
  app_server_port = $AppServerPort
  runtime = $Runtime
  chat_only = [bool]$ChatOnly
  require_agents_marker = [bool]$RequireAgentsMarker
  require_scene_context = [bool]$RequireSceneContext
  addon_starts_host = [bool]$AddonStartsHost
  agents_marker_seen = $false
  scene_context_marker_seen = $false
  expected_scene_path_seen = $false
  heartbeat_live = $false
  chat_input_visible = $false
  chat_input_inside_panel = $false
  connect_request_status = $null
  host_attached = $false
  chat_send_status = $null
  turn_completed = $false
  background_start_status = $null
  background_completed = $false
  approval_send_status = $null
  approval_requested = $false
  approval_response_status = $null
  approval_resolved = $false
  bridge_tools_enabled_status_count_before_connect = $null
  bridge_tools_enabled_status_count_after_attach = $null
  bridge_tools_attach_status_delta = $null
  bridge_tools_enabled_status_count_before_refresh = $null
  bridge_tools_enabled_status_count_after_refresh = $null
  bridge_tools_refresh_status_delta = $null
  refreshing_tools_status_count_before_refresh = $null
  refreshing_tools_status_count_after_refresh = $null
  refreshing_tools_refresh_status_delta = $null
  report_path = $reportPath
}

try {
  $healthUri = "http://127.0.0.1:$Port/health"
  if ($AddonStartsHost) {
    if (-not (Test-Path -LiteralPath $hostConfigPath)) {
      throw "Addon auto-start config not found: $hostConfigPath. Run scripts\install_addon.ps1 with -Apply -Replace first."
    }
    $hostConfig = Get-Content -Raw -LiteralPath $hostConfigPath | ConvertFrom-Json
    $result.host_config_path = $hostConfigPath
    $result.host_config_runtime = [string]$hostConfig.runtime
    $result.host_config_port = [int]$hostConfig.port
    if ([int]$hostConfig.port -ne $Port) {
      throw "host_config.json port $($hostConfig.port) does not match validation port $Port."
    }
    if ([string]$hostConfig.runtime -ne $Runtime) {
      throw "host_config.json runtime $($hostConfig.runtime) does not match validation runtime $Runtime."
    }
    $existingListeners = @(Get-ListeningProcessIds $Port)
    if ($existingListeners.Count -gt 0) {
      throw "Port $Port is already listening before auto-start validation: $($existingListeners -join ', '). Close the existing Codex Host first."
    }
  } else {
    Push-Location $hostRoot
    npm run build | Write-Output
    Pop-Location

    $hostProcess = Start-Process `
      -FilePath "node" `
      -ArgumentList @((Join-Path $hostRoot "dist\src\index.js"), "--runtime", $Runtime, "--port", [string]$Port, "--app-server-port", [string]$AppServerPort) `
      -WorkingDirectory $hostRoot `
      -WindowStyle Hidden `
      -PassThru

    $deadline = (Get-Date).AddSeconds(15)
    $health = $null
    while ((Get-Date) -lt $deadline) {
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
    $result.host_process_id = $hostProcess.Id
  }

  $godotProcess = Start-Process -FilePath $resolvedGodot -ArgumentList @("--path", $resolvedProjectRoot, "--editor") -PassThru
  $result.godot_process_id = $godotProcess.Id

  $deadline = (Get-Date).AddSeconds($StartupTimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    if (Test-Path -LiteralPath $heartbeatPath) {
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

  $layout = Invoke-RetryBridgeRequest "get_codex_chat_layout_status" @{} $requestsDir $responsesDir $RequestTimeoutSeconds 3
  $result.layout_status = if ($layout.response -ne $null) { $layout.response.status } else { "timeout" }
  $result.layout_response_path = $layout.response_path
  if ($layout.response -ne $null -and $layout.response.data -ne $null) {
    $result.chat_input_visible = [bool]$layout.response.data.input_visible_in_tree
    $result.chat_input_inside_panel = [bool]$layout.response.data.input_inside_chat_panel
    $result.chat_log_inside_panel = [bool]$layout.response.data.log_inside_chat_panel
    $result.chat_composer_below_log = [bool]$layout.response.data.composer_below_log
    $result.chat_approval_above_input = [bool]$layout.response.data.approval_above_input
    $result.chat_panel_rect = $layout.response.data.panel_rect
    $result.chat_input_rect = $layout.response.data.input_rect
    $result.chat_input_row_rect = $layout.response.data.input_row_rect
    $result.chat_input_minimum_size = $layout.response.data.input_minimum_size
    $result.chat_input_row_minimum_size = $layout.response.data.input_row_minimum_size
    $result.chat_input_scroll_fit_content_height = [bool]$layout.response.data.input_scroll_fit_content_height
    $result.chat_composer_expanded = [bool]$layout.response.data.composer_expanded
    $result.chat_composer_toggle_visible = [bool]$layout.response.data.composer_toggle_visible_in_tree
    $result.chat_composer_toggle_inside_panel = [bool]$layout.response.data.composer_toggle_inside_chat_panel
    $result.chat_composer_toggle_text = $layout.response.data.composer_toggle_text
    $result.chat_approval_rect = $layout.response.data.approval_rect
    $result.chat_log_frame_rect = $layout.response.data.log_frame_rect
    $result.chat_log_rect = $layout.response.data.log_rect
    $result.chat_log_frame_minimum_size = $layout.response.data.log_frame_minimum_size
    $result.chat_message_count = $layout.response.data.chat_message_count
    $result.bridge_tools_enabled_status_count_before_connect = [int]$layout.response.data.chat_bridge_tools_enabled_status_count
    $result.technical_log_count = $layout.response.data.technical_log_count
    $result.advanced_visible = [bool]$layout.response.data.advanced_visible
    $result.advanced_toggle_visible = [bool]$layout.response.data.advanced_toggle_visible
    $result.advanced_toggle_inside_chat_panel = [bool]$layout.response.data.advanced_toggle_inside_chat_panel
    $result.advanced_toggle_focus_mode = [int]$layout.response.data.advanced_toggle_focus_mode
    $result.connect_button_visible = [bool]$layout.response.data.connect_button_visible
    $result.connect_button_inside_chat_panel = [bool]$layout.response.data.connect_button_inside_chat_panel
    $result.connect_button_in_status_header = [bool]$layout.response.data.connect_button_in_status_header
    $result.connect_button_focus_mode = [int]$layout.response.data.connect_button_focus_mode
    $result.enable_tools_button_visible = [bool]$layout.response.data.enable_tools_button_visible
    $result.model_option_visible = [bool]$layout.response.data.model_option_visible
    $result.reasoning_option_visible = [bool]$layout.response.data.reasoning_option_visible
    $result.trust_button_visible = [bool]$layout.response.data.trust_button_visible
    $result.attach_context_visible = [bool]$layout.response.data.attach_context_visible
    $result.attach_selected_visible = [bool]$layout.response.data.attach_selected_visible
    $result.attach_screenshot_visible = [bool]$layout.response.data.attach_screenshot_visible
    $result.team_review_button_visible = [bool]$layout.response.data.team_review_button_visible
    $result.team_status_visible = [bool]$layout.response.data.team_status_visible
    $result.eye_button_visible = [bool]$layout.response.data.eye_button_visible_in_tree
    $result.eye_button_inside_chat_panel = [bool]$layout.response.data.eye_button_inside_chat_panel
    $result.main_screen_registered = [bool]$layout.response.data.main_screen_registered
    $result.dock_registered = [bool]$layout.response.data.dock_registered
    $result.bottom_panel_registered = [bool]$layout.response.data.bottom_panel_registered
    $result.mcp_tools_available = [bool]$layout.response.data.mcp_tools_available
    $result.mcp_tool_count = $layout.response.data.mcp_tool_count
    $result.mcp_godot_tool_count = $layout.response.data.mcp_godot_tool_count
    $result.mcp_server_name = $layout.response.data.mcp_server_name
    $result.last_tool_inventory_at = $layout.response.data.last_tool_inventory_at
    $result.tool_visibility_error = $layout.response.data.tool_visibility_error
    $result.host_config_status = $layout.response.data.host_config_status
    $result.host_config_message = $layout.response.data.host_config_message
    $result.host_config_runtime = $layout.response.data.host_config_runtime
    $result.host_config_port = $layout.response.data.host_config_port
    $result.host_config_launcher_path = $layout.response.data.host_config_launcher_path
    $result.active_project_root = $layout.response.data.active_project_root
    $result.agents_count = $layout.response.data.agents_count
    $result.agents_status = $layout.response.data.agents_status
    $result.recoverable_message = $layout.response.data.recoverable_message
    $result.fatal_message = $layout.response.data.fatal_message
    $result.window_mode = $layout.response.data.window_mode
    $result.window_position = $layout.response.data.window_position
    $result.window_size = $layout.response.data.window_size
    $result.usable_screen_rect = $layout.response.data.usable_screen_rect
    $result.window_inside_usable_screen = [bool]$layout.response.data.window_inside_usable_screen
  }
  if ($result.host_config_status -ne "ok") {
    throw "Godot addon host_config status is '$($result.host_config_status)': $($result.host_config_message)"
  }
  if ([string]$result.host_config_runtime -ne $Runtime) {
    throw "Godot addon host_config runtime '$($result.host_config_runtime)' does not match validation runtime '$Runtime'. Refresh the addon install config before validation."
  }
  if ([int]$result.host_config_port -ne $Port) {
    throw "Godot addon host_config port '$($result.host_config_port)' does not match validation port '$Port'. Refresh the addon install config before validation."
  }
  if ($result.layout_status -ne "succeeded" -or -not $result.chat_input_visible -or -not $result.chat_input_inside_panel -or -not $result.chat_log_inside_panel -or -not $result.chat_composer_below_log) {
    throw "Codex Chat input or transcript viewport is not visible inside the chat panel, or the composer is not below the transcript."
  }
  if ([double]$result.chat_input_rect.height -lt 240 -or [double]$result.chat_input_minimum_size.y -lt 260 -or $result.chat_input_scroll_fit_content_height) {
    throw "Codex Chat composer is not a stable multiline input. Height=$($result.chat_input_rect.height), minHeight=$($result.chat_input_minimum_size.y), scrollFit=$($result.chat_input_scroll_fit_content_height)."
  }
  if ($result.chat_composer_expanded -or -not $result.chat_composer_toggle_visible -or -not $result.chat_composer_toggle_inside_panel -or [string]$result.chat_composer_toggle_text -ne "Expand") {
    throw "Codex Chat composer toggle is not available in collapsed state."
  }
  if ($result.advanced_visible -or -not $result.advanced_toggle_visible -or -not $result.advanced_toggle_inside_chat_panel) {
    throw "Codex Chat Advanced controls are not collapsed cleanly by default."
  }
  if (
    $result.enable_tools_button_visible -or
    $result.model_option_visible -or
    $result.reasoning_option_visible -or
    $result.trust_button_visible -or
    $result.attach_context_visible -or
    $result.attach_selected_visible -or
    $result.attach_screenshot_visible -or
    $result.team_review_button_visible -or
    $result.team_status_visible
  ) {
    throw "Codex Chat Advanced-only controls are visible while Advanced is collapsed."
  }
  if (
    -not $result.connect_button_visible -or
    -not $result.connect_button_inside_chat_panel -or
    -not $result.connect_button_in_status_header -or
    [int]$result.connect_button_focus_mode -ne 2 -or
    [int]$result.advanced_toggle_focus_mode -ne 2
  ) {
    throw "Codex Chat primary recovery action or Advanced toggle is hidden, outside the header, or unavailable to keyboard focus."
  }
  if (-not $result.eye_button_visible -or -not $result.eye_button_inside_chat_panel) {
    throw "Eye Attach button is not visible inside the slim Codex Chat composer."
  }
  if (-not $result.main_screen_registered -or -not $result.dock_registered -or $result.bottom_panel_registered) {
    throw "Codex Bridge visibility regression: expected main screen + dock registration and no bottom panel registration."
  }

  $advancedOpen = Invoke-RetryBridgeRequest "set_codex_chat_advanced_visible" @{
    visible = $true
  } $requestsDir $responsesDir $RequestTimeoutSeconds 3
  $result.advanced_open_status = if ($advancedOpen.response -ne $null) { $advancedOpen.response.status } else { "timeout" }
  $result.advanced_open_response_path = $advancedOpen.response_path
  if (
    $advancedOpen.response -eq $null -or
    $advancedOpen.response.status -ne "succeeded" -or
    -not [bool]$advancedOpen.response.data.advanced_visible -or
    -not [bool]$advancedOpen.response.data.connect_button_visible -or
    -not [bool]$advancedOpen.response.data.model_option_visible -or
    -not [bool]$advancedOpen.response.data.trust_button_visible -or
    -not [bool]$advancedOpen.response.data.attach_context_visible -or
    -not [bool]$advancedOpen.response.data.team_review_button_visible
  ) {
    throw "Codex Chat Advanced controls did not become visible when expanded."
  }

  $advancedClose = Invoke-RetryBridgeRequest "set_codex_chat_advanced_visible" @{
    visible = $false
  } $requestsDir $responsesDir $RequestTimeoutSeconds 3
  $result.advanced_close_status = if ($advancedClose.response -ne $null) { $advancedClose.response.status } else { "timeout" }
  $result.advanced_close_response_path = $advancedClose.response_path
  if (
    $advancedClose.response -eq $null -or
    $advancedClose.response.status -ne "succeeded" -or
    [bool]$advancedClose.response.data.advanced_visible -or
    -not [bool]$advancedClose.response.data.connect_button_visible -or
    -not [bool]$advancedClose.response.data.connect_button_in_status_header -or
    [bool]$advancedClose.response.data.model_option_visible -or
    [bool]$advancedClose.response.data.team_review_button_visible -or
    -not [bool]$advancedClose.response.data.eye_button_visible_in_tree -or
    -not [bool]$advancedClose.response.data.input_visible_in_tree
  ) {
    throw "Codex Chat Advanced controls did not collapse back to the slim chat surface."
  }

  $eyeAttach = Invoke-RetryBridgeRequest "validate_eye_attach_flow" @{} $requestsDir $responsesDir $RequestTimeoutSeconds 3
  $result.eye_attach_status = if ($eyeAttach.response -ne $null) { $eyeAttach.response.status } else { "timeout" }
  $result.eye_attach_response_path = $eyeAttach.response_path
  if ($eyeAttach.response -ne $null -and $eyeAttach.response.data -ne $null) {
    $result.eye_attach_capture_succeeded = [bool]$eyeAttach.response.data.capture_succeeded
    $result.eye_attach_capture_scope = $eyeAttach.response.data.capture_scope
    $result.eye_attach_capture_source = $eyeAttach.response.data.capture_source
    $result.eye_attach_capture_looked_blank = [bool]$eyeAttach.response.data.capture_looked_blank
    $result.eye_attach_image_width = [int]$eyeAttach.response.data.image_width
    $result.eye_attach_image_height = [int]$eyeAttach.response.data.image_height
    $result.eye_attach_dialog_visible_after_open = [bool]$eyeAttach.response.data.dialog_visible_after_open
    $result.eye_attach_canvas_has_image_after_open = [bool]$eyeAttach.response.data.canvas_has_image_after_open
    $result.eye_attach_marker_created_for_cancel = [bool]$eyeAttach.response.data.marker_created_for_cancel
    $result.eye_attach_marker_count_before_cancel = [int]$eyeAttach.response.data.marker_count_before_cancel
    $result.eye_attach_cancel_left_no_pending = [bool]$eyeAttach.response.data.cancel_left_no_pending
    $result.eye_attach_dialog_hidden_after_cancel = [bool]$eyeAttach.response.data.dialog_hidden_after_cancel
    $result.eye_attach_marker_created_for_attach = [bool]$eyeAttach.response.data.marker_created_for_attach
    $result.eye_attach_marker_count_before_attach = [int]$eyeAttach.response.data.marker_count_before_attach
    $result.eye_attach_pending_after_attach = [bool]$eyeAttach.response.data.pending_after_attach
    $result.eye_attach_pending_annotation_id = $eyeAttach.response.data.pending_annotation_id
    $result.eye_attach_pending_marker_count = [int]$eyeAttach.response.data.pending_marker_count
    $result.eye_attach_pending_label_visible = [bool]$eyeAttach.response.data.pending_label_visible
    $result.eye_attach_clear_button_visible = [bool]$eyeAttach.response.data.clear_button_visible
    $result.eye_attach_raw_exists = [bool]$eyeAttach.response.data.raw_exists
    $result.eye_attach_annotated_exists = [bool]$eyeAttach.response.data.annotated_exists
    $result.eye_attach_manifest_exists = [bool]$eyeAttach.response.data.manifest_exists
    $result.eye_attach_manifest_has_guardrails = [bool]$eyeAttach.response.data.manifest_has_guardrails
    $result.eye_attach_clear_removed_pending = [bool]$eyeAttach.response.data.clear_removed_pending
    $result.eye_attach_pending_label_hidden_after_clear = [bool]$eyeAttach.response.data.pending_label_hidden_after_clear
    $result.eye_attach_clear_button_hidden_after_clear = [bool]$eyeAttach.response.data.clear_button_hidden_after_clear
  }
  if (
    $result.eye_attach_status -ne "succeeded" -or
    -not $result.eye_attach_capture_succeeded -or
    $result.eye_attach_capture_looked_blank -or
    [int]$result.eye_attach_image_width -le 0 -or
    [int]$result.eye_attach_image_height -le 0 -or
    -not $result.eye_attach_dialog_visible_after_open -or
    -not $result.eye_attach_canvas_has_image_after_open -or
    -not $result.eye_attach_marker_created_for_cancel -or
    [int]$result.eye_attach_marker_count_before_cancel -lt 1 -or
    -not $result.eye_attach_cancel_left_no_pending -or
    -not $result.eye_attach_dialog_hidden_after_cancel -or
    -not $result.eye_attach_marker_created_for_attach -or
    [int]$result.eye_attach_marker_count_before_attach -lt 1 -or
    -not $result.eye_attach_pending_after_attach -or
    [int]$result.eye_attach_pending_marker_count -lt 1 -or
    -not $result.eye_attach_pending_label_visible -or
    -not $result.eye_attach_clear_button_visible -or
    -not $result.eye_attach_raw_exists -or
    -not $result.eye_attach_annotated_exists -or
    -not $result.eye_attach_manifest_exists -or
    -not $result.eye_attach_manifest_has_guardrails -or
    -not $result.eye_attach_clear_removed_pending -or
    -not $result.eye_attach_pending_label_hidden_after_clear -or
    -not $result.eye_attach_clear_button_hidden_after_clear
  ) {
    throw "Eye Attach capture/marker/cancel/attach validation failed."
  }

  $diffOverflow = Invoke-RetryBridgeRequest "validate_codex_chat_diff_overflow" @{
    file_count = 32
    lines_per_file = 3
    updates = 4
  } $requestsDir $responsesDir $RequestTimeoutSeconds 3
  $result.diff_overflow_status = if ($diffOverflow.response -ne $null) { $diffOverflow.response.status } else { "timeout" }
  $result.diff_overflow_validation_status = $result.diff_overflow_status
  $result.diff_overflow_response_path = $diffOverflow.response_path
  if ($diffOverflow.response -ne $null -and $diffOverflow.response.data -ne $null) {
    $result.diff_overflow_requested_file_count = [int]$diffOverflow.response.data.diff_overflow_requested_file_count
    $result.diff_overflow_generated_file_count = [int]$diffOverflow.response.data.diff_overflow_generated_file_count
    $result.diff_overflow_ui_file_limit = [int]$diffOverflow.response.data.diff_overflow_ui_file_limit
    $result.diff_overflow_fixture_chars = [int]$diffOverflow.response.data.diff_overflow_fixture_chars
    $result.diff_overflow_chat_message_count = [int]$diffOverflow.response.data.chat_message_count
    $result.diff_overflow_preview_count = [int]$diffOverflow.response.data.chat_diff_preview_count
    $result.diff_overflow_file_section_count = [int]$diffOverflow.response.data.chat_diff_file_section_count
    $result.diff_overflow_files_box_visible_count = [int]$diffOverflow.response.data.chat_diff_files_box_visible_count
    $result.diff_overflow_active_file_count = [int]$diffOverflow.response.data.active_diff_file_count
    $result.diff_overflow_active_added_count = [int]$diffOverflow.response.data.active_diff_added_count
    $result.diff_overflow_active_removed_count = [int]$diffOverflow.response.data.active_diff_removed_count
    $result.diff_overflow_active_files_visible = [bool]$diffOverflow.response.data.active_diff_files_visible
    $result.diff_overflow_input_visible = [bool]$diffOverflow.response.data.input_visible_in_tree
    $result.diff_overflow_input_inside_panel = [bool]$diffOverflow.response.data.input_inside_chat_panel
    $result.diff_overflow_log_inside_panel = [bool]$diffOverflow.response.data.log_inside_chat_panel
    $result.diff_overflow_composer_below_log = [bool]$diffOverflow.response.data.composer_below_log
    $result.diff_overflow_approval_above_input = [bool]$diffOverflow.response.data.approval_above_input
    $result.diff_overflow_input_rect = $diffOverflow.response.data.input_rect
    $result.diff_overflow_log_frame_rect = $diffOverflow.response.data.log_frame_rect
    $result.diff_overflow_log_rect = $diffOverflow.response.data.log_rect
  }
  if ($result.diff_overflow_status -ne "succeeded") {
    throw "Codex Chat diff overflow validation failed. Status=$($result.diff_overflow_status)."
  }
  if (
    [int]$result.diff_overflow_generated_file_count -lt 32 -or
    [int]$result.diff_overflow_active_file_count -ne [int]$result.diff_overflow_ui_file_limit -or
    [int]$result.diff_overflow_file_section_count -ne [int]$result.diff_overflow_ui_file_limit -or
    [int]$result.diff_overflow_preview_count -ne 1 -or
    [int]$result.diff_overflow_files_box_visible_count -ne 1 -or
    [int]$result.diff_overflow_active_added_count -ne 72 -or
    [int]$result.diff_overflow_active_removed_count -ne 72 -or
    -not [bool]$result.diff_overflow_active_files_visible
  ) {
    throw "Codex Chat diff overflow did not render a bounded expanded file list. Generated=$($result.diff_overflow_generated_file_count), active=$($result.diff_overflow_active_file_count), sections=$($result.diff_overflow_file_section_count), visibleBoxes=$($result.diff_overflow_files_box_visible_count)."
  }
  if (
    -not [bool]$result.diff_overflow_input_visible -or
    -not [bool]$result.diff_overflow_input_inside_panel -or
    -not [bool]$result.diff_overflow_log_inside_panel -or
    -not [bool]$result.diff_overflow_composer_below_log -or
    -not [bool]$result.diff_overflow_approval_above_input -or
    [double]$result.diff_overflow_input_rect.height -lt 240
  ) {
    throw "Codex Chat diff overflow layout regressed; composer/log/approval are not in the expected panel order."
  }

  Start-Sleep -Milliseconds 500
  $diffVisualPrepare = Invoke-RetryBridgeRequest "prepare_codex_chat_diff_visual_evidence" @{} $requestsDir $responsesDir $RequestTimeoutSeconds 3
  $result.diff_overflow_visual_prepare_status = if ($diffVisualPrepare.response -ne $null) { $diffVisualPrepare.response.status } else { "timeout" }
  $result.diff_overflow_visual_prepare_response_path = $diffVisualPrepare.response_path
  if ($diffVisualPrepare.response -ne $null -and $diffVisualPrepare.response.data -ne $null) {
    $result.diff_overflow_visual_prepare_data = $diffVisualPrepare.response.data
  }
  if (
    $result.diff_overflow_visual_prepare_status -ne "succeeded" -or
    [string]$result.diff_overflow_visual_prepare_data.target -ne "active_diff_first_file" -or
    [double]$result.diff_overflow_visual_prepare_data.target_content_y -lt 0
  ) {
    throw "Codex Chat diff visual target could not be prepared for capture."
  }
  Start-Sleep -Milliseconds 500
  $diffVisual = Invoke-RetryBridgeRequest "capture_codex_chat_visual_evidence" @{
    reason = "diff_overflow_expanded"
    require_active_diff = $true
  } $requestsDir $responsesDir $RequestTimeoutSeconds 3
  $result.diff_overflow_visual_status = if ($diffVisual.response -ne $null) { $diffVisual.response.status } else { "timeout" }
  $result.diff_overflow_visual_response_path = $diffVisual.response_path
  if ($diffVisual.response -ne $null -and $diffVisual.response.data -ne $null -and $diffVisual.response.data.artifact -ne $null) {
    $result.diff_overflow_visual_path = [string]$diffVisual.response.data.artifact.absolute_path
    $result.diff_overflow_visual_width = [int]$diffVisual.response.data.artifact.width
    $result.diff_overflow_visual_height = [int]$diffVisual.response.data.artifact.height
    $result.diff_overflow_visual_looks_blank = [bool]$diffVisual.response.data.artifact.looks_blank
    $result.diff_overflow_visual_source = [string]$diffVisual.response.data.artifact.source
    $result.diff_overflow_visual_target_window_verified = [bool]$diffVisual.response.data.artifact.target_window_verified
    $result.diff_overflow_visual_occlusion_sensitive = [bool]$diffVisual.response.data.artifact.occlusion_sensitive
    $result.diff_overflow_visual_exclusive_modal_visible = [bool]$diffVisual.response.data.artifact.exclusive_modal_visible
    $result.diff_overflow_visual_capture_warning = [string]$diffVisual.response.data.artifact.capture_warning
    $result.diff_overflow_visual_semantic_target = $diffVisual.response.data.artifact.semantic_target
  }
  if ($result.diff_overflow_visual_status -ne "succeeded") {
    throw "Codex Chat diff overflow visual evidence capture failed. Status=$($result.diff_overflow_visual_status)."
  }
  if (
    [string]::IsNullOrWhiteSpace([string]$result.diff_overflow_visual_path) -or
    -not (Test-Path -LiteralPath ([string]$result.diff_overflow_visual_path)) -or
    [int]$result.diff_overflow_visual_width -le 0 -or
    [int]$result.diff_overflow_visual_height -le 0 -or
    [bool]$result.diff_overflow_visual_looks_blank -or
    -not [bool]$result.diff_overflow_visual_target_window_verified -or
    [bool]$result.diff_overflow_visual_occlusion_sensitive -or
    [bool]$result.diff_overflow_visual_exclusive_modal_visible -or
    [string]$result.diff_overflow_visual_semantic_target.target -ne "active_diff_first_file" -or
    -not [bool]$result.diff_overflow_visual_semantic_target.target_visible_in_tree -or
    -not [bool]$result.diff_overflow_visual_semantic_target.files_box_visible_in_tree -or
    -not [bool]$result.diff_overflow_visual_semantic_target.target_intersects_log_view -or
    -not [bool]$result.diff_overflow_visual_semantic_target.target_intersects_capture_root
  ) {
    throw "Codex Chat diff overflow visual evidence was missing, blank, unverified, occlusion-sensitive, or did not visibly contain the active diff target."
  }

  $multiline = Invoke-RetryBridgeRequest "validate_codex_chat_input_multiline" @{} $requestsDir $responsesDir $RequestTimeoutSeconds 3
  $result.chat_multiline_validation_status = if ($multiline.response -ne $null) { $multiline.response.status } else { "timeout" }
  $result.chat_multiline_validation_response_path = $multiline.response_path
  if ($multiline.response -ne $null -and $multiline.response.data -ne $null) {
    $result.chat_multiline_has_newline = [bool]$multiline.response.data.has_newline
    $result.chat_multiline_handled_event = [bool]$multiline.response.data.handled_event
    $result.chat_multiline_line_count = [int]$multiline.response.data.line_count
    $result.chat_multiline_auto_input_minimum_size = $multiline.response.data.auto_input_minimum_size
    $result.chat_multiline_auto_input_row_minimum_size = $multiline.response.data.auto_input_row_minimum_size
    $result.chat_multiline_input_minimum_size = $multiline.response.data.input_minimum_size
    $result.chat_multiline_input_scroll_fit_content_height = [bool]$multiline.response.data.input_scroll_fit_content_height
    $result.chat_multiline_expanded_after_shift_enter = [bool]$multiline.response.data.expanded_after_shift_enter
  }
  if ($result.chat_multiline_validation_status -ne "succeeded" -or -not $result.chat_multiline_handled_event -or -not $result.chat_multiline_has_newline -or [int]$result.chat_multiline_line_count -lt 2) {
    throw "Codex Chat Shift+Enter multiline validation failed. Status=$($result.chat_multiline_validation_status), handledEvent=$($result.chat_multiline_handled_event), hasNewline=$($result.chat_multiline_has_newline), lineCount=$($result.chat_multiline_line_count)."
  }
  if ([double]$result.chat_multiline_auto_input_minimum_size.y -lt 260 -or [double]$result.chat_multiline_auto_input_row_minimum_size.y -lt 294) {
    throw "Codex Chat multiline auto-grow failed. InputMin=$($result.chat_multiline_auto_input_minimum_size.y), RowMin=$($result.chat_multiline_auto_input_row_minimum_size.y)."
  }
  if (-not [bool]$result.chat_multiline_expanded_after_shift_enter) {
    throw "Codex Chat Shift+Enter inserted text but did not switch the composer into expanded mode."
  }

  $wrappedPrompt = Invoke-RetryBridgeRequest "validate_codex_chat_input_long_prompt" @{
    text = "This deliberately wrapped Codex prompt is long enough to occupy several visual lines in the Godot chat dock, so typing it should switch the composer into the expanded writing mode instead of leaving the prompt box feeling cramped."
  } $requestsDir $responsesDir $RequestTimeoutSeconds 3
  $result.chat_wrapped_prompt_validation_status = if ($wrappedPrompt.response -ne $null) { $wrappedPrompt.response.status } else { "timeout" }
  $result.chat_wrapped_prompt_validation_response_path = $wrappedPrompt.response_path
  if ($wrappedPrompt.response -ne $null -and $wrappedPrompt.response.data -ne $null) {
    $result.chat_wrapped_prompt_text_length = [int]$wrappedPrompt.response.data.input_text_length
    $result.chat_wrapped_prompt_input_width = [double]$wrappedPrompt.response.data.input_width
    $result.chat_wrapped_prompt_expected_height = [double]$wrappedPrompt.response.data.expected_height
    $result.chat_wrapped_prompt_auto_input_minimum_size = $wrappedPrompt.response.data.auto_input_minimum_size
    $result.chat_wrapped_prompt_auto_input_row_minimum_size = $wrappedPrompt.response.data.auto_input_row_minimum_size
    $result.chat_wrapped_prompt_expanded_after_text = [bool]$wrappedPrompt.response.data.expanded_after_text
  }
  if ($result.chat_wrapped_prompt_validation_status -ne "succeeded") {
    throw "Codex Chat wrapped prompt validation failed. Status=$($result.chat_wrapped_prompt_validation_status)."
  }
  if ([double]$result.chat_wrapped_prompt_auto_input_minimum_size.y -lt 260 -or [double]$result.chat_wrapped_prompt_auto_input_row_minimum_size.y -lt 294) {
    throw "Codex Chat wrapped prompt auto-grow failed. InputMin=$($result.chat_wrapped_prompt_auto_input_minimum_size.y), RowMin=$($result.chat_wrapped_prompt_auto_input_row_minimum_size.y)."
  }
  if (-not [bool]$result.chat_wrapped_prompt_expanded_after_text) {
    throw "Codex Chat wrapped prompt did not switch the composer into expanded mode."
  }

  $longPrompt = Invoke-RetryBridgeRequest "validate_codex_chat_input_long_prompt" @{
    text = "This is a deliberately long single-line Codex prompt used to prove that typing more text expands the composer instead of leaving the chat input feeling like one cramped line in the Godot dock."
  } $requestsDir $responsesDir $RequestTimeoutSeconds 3
  $result.chat_long_prompt_validation_status = if ($longPrompt.response -ne $null) { $longPrompt.response.status } else { "timeout" }
  $result.chat_long_prompt_validation_response_path = $longPrompt.response_path
  if ($longPrompt.response -ne $null -and $longPrompt.response.data -ne $null) {
    $result.chat_long_prompt_text_length = [int]$longPrompt.response.data.input_text_length
    $result.chat_long_prompt_longest_line = [int]$longPrompt.response.data.longest_line
    $result.chat_long_prompt_expected_height = [double]$longPrompt.response.data.expected_height
    $result.chat_long_prompt_auto_input_minimum_size = $longPrompt.response.data.auto_input_minimum_size
    $result.chat_long_prompt_auto_input_row_minimum_size = $longPrompt.response.data.auto_input_row_minimum_size
    $result.chat_long_prompt_input_scroll_fit_content_height = [bool]$longPrompt.response.data.input_scroll_fit_content_height
    $result.chat_long_prompt_expanded_after_text = [bool]$longPrompt.response.data.expanded_after_text
  }
  if ($result.chat_long_prompt_validation_status -ne "succeeded") {
    throw "Codex Chat long prompt validation failed. Status=$($result.chat_long_prompt_validation_status)."
  }
  if ([double]$result.chat_long_prompt_auto_input_minimum_size.y -lt 360 -or [double]$result.chat_long_prompt_auto_input_row_minimum_size.y -lt 394) {
    throw "Codex Chat long prompt auto-grow failed. InputMin=$($result.chat_long_prompt_auto_input_minimum_size.y), RowMin=$($result.chat_long_prompt_auto_input_row_minimum_size.y)."
  }
  if ([bool]$result.chat_long_prompt_input_scroll_fit_content_height) {
    throw "Codex Chat long prompt validation reports scroll_fit_content_height=true."
  }
  if (-not [bool]$result.chat_long_prompt_expanded_after_text) {
    throw "Codex Chat long prompt did not switch the composer into expanded mode."
  }

  $composerOpen = Invoke-RetryBridgeRequest "set_codex_chat_composer_expanded" @{
    expanded = $true
  } $requestsDir $responsesDir $RequestTimeoutSeconds 3
  $result.composer_open_status = if ($composerOpen.response -ne $null) { $composerOpen.response.status } else { "timeout" }
  $result.composer_open_response_path = $composerOpen.response_path
  if (
    $composerOpen.response -eq $null -or
    $composerOpen.response.status -ne "succeeded" -or
    -not [bool]$composerOpen.response.data.composer_expanded -or
    [double]$composerOpen.response.data.input_minimum_size.y -lt 420 -or
    [string]$composerOpen.response.data.composer_toggle_text -ne "Collapse"
  ) {
    throw "Codex Chat composer did not expand cleanly."
  }
  $result.composer_open_input_minimum_size = $composerOpen.response.data.input_minimum_size
  $result.composer_open_input_rect = $composerOpen.response.data.input_rect
  Start-Sleep -Milliseconds 350
  $composerOpenLayout = Invoke-RetryBridgeRequest "get_codex_chat_layout_status" @{} $requestsDir $responsesDir $RequestTimeoutSeconds 3
  $result.composer_open_layout_status = if ($composerOpenLayout.response -ne $null) { $composerOpenLayout.response.status } else { "timeout" }
  if (
    $composerOpenLayout.response -eq $null -or
    $composerOpenLayout.response.status -ne "succeeded" -or
    -not [bool]$composerOpenLayout.response.data.composer_expanded -or
    [double]$composerOpenLayout.response.data.input_rect.height -lt 360
  ) {
    throw "Codex Chat composer minimum expanded, but the visible input height did not grow."
  }
  $result.composer_open_visible_input_rect = $composerOpenLayout.response.data.input_rect

  $composerClose = Invoke-RetryBridgeRequest "set_codex_chat_composer_expanded" @{
    expanded = $false
  } $requestsDir $responsesDir $RequestTimeoutSeconds 3
  $result.composer_close_status = if ($composerClose.response -ne $null) { $composerClose.response.status } else { "timeout" }
  $result.composer_close_response_path = $composerClose.response_path
  if (
    $composerClose.response -eq $null -or
    $composerClose.response.status -ne "succeeded" -or
    [bool]$composerClose.response.data.composer_expanded -or
    [double]$composerClose.response.data.input_minimum_size.y -ne 260 -or
    [string]$composerClose.response.data.composer_toggle_text -ne "Expand"
  ) {
    throw "Codex Chat composer did not collapse cleanly."
  }
  $result.composer_close_input_minimum_size = $composerClose.response.data.input_minimum_size
  Start-Sleep -Milliseconds 350
  $composerCloseLayout = Invoke-RetryBridgeRequest "get_codex_chat_layout_status" @{} $requestsDir $responsesDir $RequestTimeoutSeconds 3
  $result.composer_close_layout_status = if ($composerCloseLayout.response -ne $null) { $composerCloseLayout.response.status } else { "timeout" }
  if (
    $composerCloseLayout.response -eq $null -or
    $composerCloseLayout.response.status -ne "succeeded" -or
    [bool]$composerCloseLayout.response.data.composer_expanded -or
    [double]$composerCloseLayout.response.data.input_rect.height -lt 240 -or
    [double]$composerCloseLayout.response.data.input_rect.height -gt 280
  ) {
    throw "Codex Chat composer did not visibly return to the compact height."
  }
  $result.composer_close_visible_input_rect = $composerCloseLayout.response.data.input_rect
  $result.bridge_tools_enabled_status_count_before_connect = [int]$composerCloseLayout.response.data.chat_bridge_tools_enabled_status_count

  $primaryActionEventLineStart = if (Test-Path -LiteralPath $eventLogPath) { @(Get-Content -LiteralPath $eventLogPath).Count } else { 0 }
  $connect = Invoke-RetryBridgeRequest "activate_codex_chat_primary_action" @{} $requestsDir $responsesDir $RequestTimeoutSeconds 3
  $result.connect_request_status = if ($connect.response -ne $null) { $connect.response.status } else { "timeout" }
  $result.connect_response_path = $connect.response_path
  if ($connect.response -ne $null -and $connect.response.data -ne $null) {
    $result.connect_response_data = $connect.response.data
    $result.primary_action_signal_emitted = [bool]$connect.response.data.signal_emitted
    $result.primary_action_signal_handled = [bool]$connect.response.data.signal_handled
    $result.primary_action_handler_count_before = [int]$connect.response.data.handler_count_before
    $result.primary_action_handler_count_after = [int]$connect.response.data.handler_count_after
    $result.primary_action_handler_count_delta = [int]$connect.response.data.handler_count_delta
    $result.primary_action_attach_request_id_before = [int]$connect.response.data.attach_request_id_before
    $result.primary_action_attach_request_id_after = [int]$connect.response.data.attach_request_id_after
    $result.primary_action_attach_request_sent = [bool]$connect.response.data.attach_request_sent
    $result.primary_action_attach_request_method = [string]$connect.response.data.attach_request_method
    $result.primary_action_visible_before = [bool]$connect.response.data.visible_before
    $result.primary_action_in_status_header = [bool]$connect.response.data.in_status_header
    $result.primary_action_focus_mode = [int]$connect.response.data.focus_mode
    $result.primary_action_advanced_visible_before = [bool]$connect.response.data.advanced_visible_before
    $result.primary_action_text_before = [string]$connect.response.data.action_text_before
  }
  if (
    $result.connect_request_status -ne "succeeded" -or
    -not $result.primary_action_signal_emitted -or
    -not $result.primary_action_signal_handled -or
    [int]$result.primary_action_handler_count_delta -ne 1 -or
    -not $result.primary_action_attach_request_sent -or
    [int]$result.primary_action_attach_request_id_after -le [int]$result.primary_action_attach_request_id_before -or
    @("project.attach", "host.restart_for_project") -notcontains [string]$result.primary_action_attach_request_method -or
    -not $result.primary_action_visible_before -or
    -not $result.primary_action_in_status_header -or
    [int]$result.primary_action_focus_mode -ne 2 -or
    $result.primary_action_advanced_visible_before
  ) {
    throw "Godot chat primary Connect/Refresh action signal failed from the collapsed status header."
  }

  $expectedAttachRequestId = [int]$result.primary_action_attach_request_id_after
  $attachCompletionDeadline = (Get-Date).AddSeconds($StartupTimeoutSeconds)
  $attachCompletionLayout = $null
  while ((Get-Date) -lt $attachCompletionDeadline) {
    $candidateLayout = Invoke-RetryBridgeRequest "get_codex_chat_layout_status" @{} $requestsDir $responsesDir $RequestTimeoutSeconds 1
    if (
      $candidateLayout.response -ne $null -and
      $candidateLayout.response.status -eq "succeeded" -and
      [int]$candidateLayout.response.data.last_completed_project_attach_request_id -eq $expectedAttachRequestId -and
      @("project.attach", "host.restart_for_project") -contains [string]$candidateLayout.response.data.last_completed_project_attach_method
    ) {
      $attachCompletionLayout = $candidateLayout
      break
    }
    Start-Sleep -Milliseconds 250
  }
  $result.primary_action_attach_response_correlated = $attachCompletionLayout -ne $null
  if ($attachCompletionLayout -ne $null) {
    $result.primary_action_completed_attach_request_id = [int]$attachCompletionLayout.response.data.last_completed_project_attach_request_id
    $result.primary_action_completed_attach_method = [string]$attachCompletionLayout.response.data.last_completed_project_attach_method
  }
  if (-not $result.primary_action_attach_response_correlated) {
    throw "Godot chat primary action did not receive the exactly correlated project attachment response."
  }

  $attachEvent = Wait-Event $eventLogPath $primaryActionEventLineStart {
    param($event)
    return $event.method -eq "host.status" -and $event.params.activeProject -ne $null
  } $StartupTimeoutSeconds
  $result.host_attached = $attachEvent -ne $null
  if (-not $result.host_attached) {
    throw "Godot addon did not attach the project to Codex Host."
  }

  if ($Runtime -eq "mock") {
    Start-Sleep -Milliseconds 1200
    $afterAttachLayout = Invoke-RetryBridgeRequest "get_codex_chat_layout_status" @{} $requestsDir $responsesDir $RequestTimeoutSeconds 3
    $result.after_attach_layout_status = if ($afterAttachLayout.response -ne $null) { $afterAttachLayout.response.status } else { "timeout" }
    $result.after_attach_layout_response_path = $afterAttachLayout.response_path
    if ($afterAttachLayout.response -eq $null -or $afterAttachLayout.response.status -ne "succeeded") {
      throw "Godot chat layout status failed after project attach."
    }
    $result.bridge_tools_enabled_status_count_after_attach = [int]$afterAttachLayout.response.data.chat_bridge_tools_enabled_status_count
    $result.bridge_tools_attach_status_delta = [int]$result.bridge_tools_enabled_status_count_after_attach - [int]$result.bridge_tools_enabled_status_count_before_connect
    if ([int]$result.bridge_tools_attach_status_delta -gt 1) {
      throw "Project attach produced more than one new Bridge tools enabled status message. Delta=$($result.bridge_tools_attach_status_delta), before=$($result.bridge_tools_enabled_status_count_before_connect), after=$($result.bridge_tools_enabled_status_count_after_attach)."
    }
    if ([int]$result.bridge_tools_attach_status_delta -lt 0) {
      throw "Bridge tools enabled status count went backwards after project attach. Delta=$($result.bridge_tools_attach_status_delta), before=$($result.bridge_tools_enabled_status_count_before_connect), after=$($result.bridge_tools_enabled_status_count_after_attach)."
    }

    $result.bridge_tools_enabled_status_count_before_refresh = [int]$afterAttachLayout.response.data.chat_bridge_tools_enabled_status_count
    $result.refreshing_tools_status_count_before_refresh = [int]$afterAttachLayout.response.data.chat_refreshing_tools_status_count
    $enableTools = Invoke-RetryBridgeRequest "enable_codex_bridge_tools" @{} $requestsDir $responsesDir $RequestTimeoutSeconds 3
    $result.bridge_tools_enable_status = if ($enableTools.response -ne $null) { $enableTools.response.status } else { "timeout" }
    $result.bridge_tools_enable_response_path = $enableTools.response_path
    if ($result.bridge_tools_enable_status -ne "succeeded") {
      throw "Godot bridge tools enable request failed in mock runtime: $($result.bridge_tools_enable_status)"
    }
    Start-Sleep -Milliseconds 500
    $afterRefreshLayout = Invoke-RetryBridgeRequest "get_codex_chat_layout_status" @{} $requestsDir $responsesDir $RequestTimeoutSeconds 3
    $result.after_refresh_layout_status = if ($afterRefreshLayout.response -ne $null) { $afterRefreshLayout.response.status } else { "timeout" }
    $result.after_refresh_layout_response_path = $afterRefreshLayout.response_path
    if ($afterRefreshLayout.response -eq $null -or $afterRefreshLayout.response.status -ne "succeeded") {
      throw "Godot chat layout status failed after Bridge tools refresh."
    }
    $result.bridge_tools_enabled_status_count_after_refresh = [int]$afterRefreshLayout.response.data.chat_bridge_tools_enabled_status_count
    $result.refreshing_tools_status_count_after_refresh = [int]$afterRefreshLayout.response.data.chat_refreshing_tools_status_count
    $result.bridge_tools_refresh_status_delta = [int]$result.bridge_tools_enabled_status_count_after_refresh - [int]$result.bridge_tools_enabled_status_count_before_refresh
    $result.refreshing_tools_refresh_status_delta = [int]$result.refreshing_tools_status_count_after_refresh - [int]$result.refreshing_tools_status_count_before_refresh
    $result.bridge_tools_refresh_status_coalesced = ([int]$result.bridge_tools_refresh_status_delta -eq 0)
    if ([int]$result.bridge_tools_refresh_status_delta -lt 0 -or [int]$result.bridge_tools_refresh_status_delta -gt 1) {
      throw "One Bridge tools refresh should produce zero or one new Bridge tools enabled status message after transcript coalescing. Delta=$($result.bridge_tools_refresh_status_delta), before=$($result.bridge_tools_enabled_status_count_before_refresh), after=$($result.bridge_tools_enabled_status_count_after_refresh)."
    }
    if ([int]$result.refreshing_tools_refresh_status_delta -lt 0 -or [int]$result.refreshing_tools_refresh_status_delta -gt 1) {
      throw "One Bridge tools refresh should produce at most one new Refreshing tools status message after transcript coalescing. Delta=$($result.refreshing_tools_refresh_status_delta), before=$($result.refreshing_tools_status_count_before_refresh), after=$($result.refreshing_tools_status_count_after_refresh)."
    }
  } else {
    $result.bridge_tools_enable_status = "skipped_real_runtime"
  }

  $enterSend = Invoke-RetryBridgeRequest "validate_codex_chat_input_enter_send" @{
    message = "Visible editor Enter-to-send smoke"
    attach_context = $false
    attach_selected = $false
    attach_screenshot = $false
  } $requestsDir $responsesDir $RequestTimeoutSeconds 3
  $result.chat_enter_send_validation_status = if ($enterSend.response -ne $null) { $enterSend.response.status } else { "timeout" }
  $result.chat_enter_send_validation_response_path = $enterSend.response_path
  if ($enterSend.response -ne $null -and $enterSend.response.data -ne $null) {
    $result.chat_enter_send_handled_event = [bool]$enterSend.response.data.handled_event
    $result.chat_enter_send_sent = [bool]$enterSend.response.data.sent
    $result.chat_enter_send_input_cleared = [bool]$enterSend.response.data.input_cleared
    $result.chat_enter_send_request_id_before = [int]$enterSend.response.data.request_id_before
    $result.chat_enter_send_request_id_after = [int]$enterSend.response.data.request_id_after
  }
  if (
    $enterSend.response -eq $null -or
    $enterSend.response.status -ne "succeeded" -or
    -not [bool]$enterSend.response.data.handled_event -or
    -not [bool]$enterSend.response.data.sent -or
    -not [bool]$enterSend.response.data.input_cleared -or
    [int]$enterSend.response.data.request_id_after -le [int]$enterSend.response.data.request_id_before
  ) {
    throw "Codex Chat Enter-to-send validation failed."
  }
  $enterTurnResult = Wait-TurnCompletedThroughAddon $eventLogPath $eventLineStart $requestsDir $responsesDir $TurnTimeoutSeconds ($Runtime -eq "app-server")
  $result.chat_enter_send_turn_completed = [bool]$enterTurnResult.completed
  $result.chat_enter_send_agent_text_chars = ([string]$enterTurnResult.text).Length
  if (-not $result.chat_enter_send_turn_completed) {
    throw "Codex Host did not observe turn.completed from Enter-to-send validation."
  }
  $eventLineStart = if (Test-Path -LiteralPath $eventLogPath) { @(Get-Content -LiteralPath $eventLogPath).Count } else { 0 }

  $expectedScenePath = $null
  if ($RequireSceneContext) {
    $expectedScenePath = Get-CurrentScenePathFromSnapshot $bridgeDir
    $result.expected_scene_path = $expectedScenePath
    if ([string]::IsNullOrWhiteSpace($expectedScenePath)) {
      throw "RequireSceneContext was set, but no current/main scene path was found in context_snapshot.json."
    }
  }

  $chatPromptParts = @("Visible editor real Codex chat smoke. Reply in one concise paragraph.")
  if ($RequireAgentsMarker) {
    $chatPromptParts += "Include exact marker GCB_FIXTURE_AGENTS_LOADED if project AGENTS.md instructions are loaded."
  }
  if ($RequireSceneContext) {
    $chatPromptParts += "If the Godot Codex Bridge orientation includes current scene context, include exact marker GCB_SCENE_CONTEXT_LOADED and include this exact scene path: $expectedScenePath"
  }
  if (-not $RequireAgentsMarker -and -not $RequireSceneContext) {
    $chatPromptParts = @("Visible editor chat smoke")
  }
  $chatMessage = $chatPromptParts -join " "
  $chat = Invoke-RetryBridgeRequest "send_codex_chat_message" @{
    message = $chatMessage
    attachments = @{
      context_snapshot = $true
      selected_nodes = $true
      latest_screenshot = $false
    }
  } $requestsDir $responsesDir $RequestTimeoutSeconds 5
  $result.chat_send_status = if ($chat.response -ne $null) { $chat.response.status } else { "timeout" }
  $result.chat_send_response_path = $chat.response_path
  if ($result.chat_send_status -ne "succeeded") {
    throw "Godot chat send request failed: $($result.chat_send_status)"
  }

  $turnResult = Wait-TurnCompletedThroughAddon $eventLogPath $eventLineStart $requestsDir $responsesDir $TurnTimeoutSeconds ($Runtime -eq "app-server")
  $result.turn_completed = [bool]$turnResult.completed
  $result.agent_text_chars = ([string]$turnResult.text).Length
  $result.approval_count = $turnResult.approval_count
  $result.auto_rejected_approvals = $turnResult.auto_rejected_approvals
  $result.agents_marker_seen = ([string]$turnResult.text).Contains("GCB_FIXTURE_AGENTS_LOADED")
  $result.scene_context_marker_seen = ([string]$turnResult.text).Contains("GCB_SCENE_CONTEXT_LOADED")
  if (-not [string]::IsNullOrWhiteSpace($expectedScenePath)) {
    $result.expected_scene_path_seen = ([string]$turnResult.text).Contains($expectedScenePath)
  }
  if (-not $result.turn_completed) {
    throw "Codex Host did not observe turn.completed from Godot chat send."
  }
  if ($RequireAgentsMarker -and -not $result.agents_marker_seen) {
    throw "Real Codex chat output did not contain GCB_FIXTURE_AGENTS_LOADED."
  }
  if ($RequireSceneContext -and -not $result.scene_context_marker_seen) {
    throw "Real Codex chat output did not contain GCB_SCENE_CONTEXT_LOADED."
  }
  if ($RequireSceneContext -and -not $result.expected_scene_path_seen) {
    throw "Real Codex chat output did not contain expected scene path: $expectedScenePath"
  }

  if (-not $ChatOnly) {
    $background = Invoke-RetryBridgeRequest "start_codex_background_team_review" @{
      prompt = "Visible editor team smoke"
      attachments = @{
        context_snapshot = $true
        selected_nodes = $true
        latest_screenshot = $false
      }
    } $requestsDir $responsesDir $RequestTimeoutSeconds 3
    $result.background_start_status = if ($background.response -ne $null) { $background.response.status } else { "timeout" }
    $result.background_start_response_path = $background.response_path
    if ($result.background_start_status -ne "succeeded") {
      throw "Godot background team request failed: $($result.background_start_status)"
    }

    $backgroundCompleted = Wait-Event $eventLogPath $eventLineStart {
      param($event)
      return $event.method -eq "background.updated" -and $event.params.state -eq "completed"
    } 30
    $result.background_completed = $backgroundCompleted -ne $null
    if (-not $result.background_completed) {
      throw "Codex Host did not observe completed background team from Godot request."
    }

    $approvalSend = Invoke-RetryBridgeRequest "send_codex_chat_message" @{
      message = "Validate approval flow"
      attachments = @{
        context_snapshot = $true
        selected_nodes = $false
        latest_screenshot = $false
      }
    } $requestsDir $responsesDir $RequestTimeoutSeconds 5
    $result.approval_send_status = if ($approvalSend.response -ne $null) { $approvalSend.response.status } else { "timeout" }
    $result.approval_send_response_path = $approvalSend.response_path
    if ($result.approval_send_status -ne "succeeded") {
      throw "Godot approval trigger chat request failed: $($result.approval_send_status)"
    }

    $approvalRequested = Wait-Event $eventLogPath $eventLineStart {
      param($event)
      return $event.method -eq "approval.requested"
    } 20
    $result.approval_requested = $approvalRequested -ne $null
    if (-not $result.approval_requested) {
      throw "Codex Host did not observe approval.requested."
    }

    Start-Sleep -Seconds 2
    $approvalResponse = Invoke-RetryBridgeRequest "respond_codex_chat_approval" @{
      decision = "approve"
      note = "validate_visible_chat_editor approval smoke"
    } $requestsDir $responsesDir $RequestTimeoutSeconds 5
    $result.approval_response_status = if ($approvalResponse.response -ne $null) { $approvalResponse.response.status } else { "timeout" }
    $result.approval_response_path = $approvalResponse.response_path
    if ($result.approval_response_status -ne "succeeded") {
      throw "Godot approval response request failed: $($result.approval_response_status)"
    }

    $approvalResolved = Wait-Event $eventLogPath $eventLineStart {
      param($event)
      return $event.method -eq "approval.resolved"
    } 20
    $result.approval_resolved = $approvalResolved -ne $null
    if (-not $result.approval_resolved) {
      throw "Codex Host did not observe approval.resolved."
    }
  }

  $finalLayout = Invoke-RetryBridgeRequest "get_codex_chat_layout_status" @{} $requestsDir $responsesDir $RequestTimeoutSeconds 3
  $result.final_layout_status = if ($finalLayout.response -ne $null) { $finalLayout.response.status } else { "timeout" }
  $result.final_layout_response_path = $finalLayout.response_path
  if ($finalLayout.response -ne $null -and $finalLayout.response.data -ne $null) {
    $result.final_chat_input_visible = [bool]$finalLayout.response.data.input_visible_in_tree
    $result.final_chat_input_inside_panel = [bool]$finalLayout.response.data.input_inside_chat_panel
    $result.final_chat_log_inside_panel = [bool]$finalLayout.response.data.log_inside_chat_panel
    $result.final_chat_composer_below_log = [bool]$finalLayout.response.data.composer_below_log
    $result.final_chat_approval_above_input = [bool]$finalLayout.response.data.approval_above_input
    $result.final_chat_input_rect = $finalLayout.response.data.input_rect
    $result.final_chat_input_row_rect = $finalLayout.response.data.input_row_rect
    $result.final_chat_input_minimum_size = $finalLayout.response.data.input_minimum_size
    $result.final_chat_input_row_minimum_size = $finalLayout.response.data.input_row_minimum_size
    $result.final_chat_composer_expanded = [bool]$finalLayout.response.data.composer_expanded
    $result.final_chat_composer_toggle_visible = [bool]$finalLayout.response.data.composer_toggle_visible_in_tree
    $result.final_chat_composer_toggle_text = $finalLayout.response.data.composer_toggle_text
    $result.final_chat_input_scroll_fit_content_height = [bool]$finalLayout.response.data.input_scroll_fit_content_height
    $result.final_chat_approval_rect = $finalLayout.response.data.approval_rect
    $result.final_chat_log_frame_rect = $finalLayout.response.data.log_frame_rect
    $result.final_chat_log_rect = $finalLayout.response.data.log_rect
    $result.final_chat_message_count = $finalLayout.response.data.chat_message_count
    $result.final_technical_log_count = $finalLayout.response.data.technical_log_count
    $result.final_chat_bridge_tools_enabled_status_count = $finalLayout.response.data.chat_bridge_tools_enabled_status_count
    $result.final_chat_refreshing_tools_status_count = $finalLayout.response.data.chat_refreshing_tools_status_count
    $result.final_mcp_tools_available = [bool]$finalLayout.response.data.mcp_tools_available
    $result.final_mcp_tool_count = $finalLayout.response.data.mcp_tool_count
    $result.final_mcp_godot_tool_count = $finalLayout.response.data.mcp_godot_tool_count
    $result.final_mcp_server_name = $finalLayout.response.data.mcp_server_name
    $result.final_last_tool_inventory_at = $finalLayout.response.data.last_tool_inventory_at
    $result.final_tool_visibility_error = $finalLayout.response.data.tool_visibility_error
    $result.final_host_config_status = $finalLayout.response.data.host_config_status
    $result.final_host_config_message = $finalLayout.response.data.host_config_message
    $result.final_host_config_runtime = $finalLayout.response.data.host_config_runtime
    $result.final_host_config_port = $finalLayout.response.data.host_config_port
    $result.final_host_config_launcher_path = $finalLayout.response.data.host_config_launcher_path
    $result.final_active_project_root = $finalLayout.response.data.active_project_root
    $result.final_agents_count = $finalLayout.response.data.agents_count
    $result.final_agents_status = $finalLayout.response.data.agents_status
    $result.final_recoverable_message = $finalLayout.response.data.recoverable_message
    $result.final_fatal_message = $finalLayout.response.data.fatal_message
    $result.final_advanced_visible = [bool]$finalLayout.response.data.advanced_visible
    $result.final_connect_button_visible = [bool]$finalLayout.response.data.connect_button_visible
    $result.final_connect_button_in_status_header = [bool]$finalLayout.response.data.connect_button_in_status_header
    $result.final_connect_button_focus_mode = [int]$finalLayout.response.data.connect_button_focus_mode
    $result.final_model_option_visible = [bool]$finalLayout.response.data.model_option_visible
    $result.final_team_review_button_visible = [bool]$finalLayout.response.data.team_review_button_visible
    $result.final_window_mode = $finalLayout.response.data.window_mode
    $result.final_window_position = $finalLayout.response.data.window_position
    $result.final_window_size = $finalLayout.response.data.window_size
    $result.final_usable_screen_rect = $finalLayout.response.data.usable_screen_rect
    $result.final_window_inside_usable_screen = [bool]$finalLayout.response.data.window_inside_usable_screen
  }
  if (
    $result.final_layout_status -ne "succeeded" -or
    -not $result.final_chat_input_visible -or
    -not $result.final_chat_input_inside_panel -or
    -not $result.final_chat_log_inside_panel -or
    -not $result.final_chat_composer_below_log -or
    -not $result.final_chat_approval_above_input
  ) {
    throw "Codex Chat layout is not contained after chat messages are rendered, or the composer/approval stack is ordered incorrectly."
  }
  if ([double]$result.final_chat_input_rect.height -lt 240 -or [double]$result.final_chat_input_minimum_size.y -lt 260 -or [double]$result.final_chat_input_row_minimum_size.y -lt 294 -or $result.final_chat_input_scroll_fit_content_height) {
    throw "Codex Chat composer regressed after messages rendered. Height=$($result.final_chat_input_rect.height), minHeight=$($result.final_chat_input_minimum_size.y), scrollFit=$($result.final_chat_input_scroll_fit_content_height)."
  }
  if ($result.final_chat_composer_expanded -or -not $result.final_chat_composer_toggle_visible -or [string]$result.final_chat_composer_toggle_text -ne "Expand") {
    throw "Codex Chat composer toggle regressed after chat activity."
  }
  if (
    $result.final_advanced_visible -or
    -not $result.final_connect_button_visible -or
    -not $result.final_connect_button_in_status_header -or
    [int]$result.final_connect_button_focus_mode -ne 2 -or
    $result.final_model_option_visible -or
    $result.final_team_review_button_visible
  ) {
    throw "Codex Chat Advanced controls became visible again after chat activity."
  }

  $result.status = "ok"
}
finally {
  $result.completed_at = (Get-Date).ToUniversalTime().ToString("o")
  $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportPath -Encoding UTF8

  if (-not $KeepOpen -and $godotProcess -and -not $godotProcess.HasExited) {
    Stop-Process -Id $godotProcess.Id -Force -ErrorAction SilentlyContinue
  }
  if ($hostProcess -and -not $hostProcess.HasExited) {
    Stop-Process -Id $hostProcess.Id -Force -ErrorAction SilentlyContinue
  }
  while ((Get-Location).Path -eq $hostRoot) {
    Pop-Location
  }
}

$result | ConvertTo-Json -Depth 12
