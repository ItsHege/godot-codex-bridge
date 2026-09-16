param(
  [string] $ProjectRoot = "examples\minimal_3d_project",
  [string] $GodotExecutable = $(if ($env:GODOT_BIN) { $env:GODOT_BIN } elseif (Get-Command godot -ErrorAction SilentlyContinue) { (Get-Command godot).Source } else { "godot" }),
  [int] $StartupTimeoutSeconds = 45,
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
  $request | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $requestPath -Encoding UTF8

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

$productRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
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
$screenshotsDir = Join-Path $artifactsDir "screenshots"
$heartbeatPath = Join-Path $bridgeDir "heartbeat.json"
$snapshotPath = Join-Path $bridgeDir "context_snapshot.json"
$reportPath = Join-Path $artifactsDir "visible_editor_validation.json"

New-Item -ItemType Directory -Force -Path $requestsDir, $responsesDir, $screenshotsDir, $artifactsDir | Out-Null

$process = Start-Process -FilePath $resolvedGodot -ArgumentList @("--path", $resolvedProjectRoot, "--editor") -PassThru
$result = [ordered]@{
  status = "started"
  started_at = (Get-Date).ToUniversalTime().ToString("o")
  process_id = $process.Id
  project_root = $resolvedProjectRoot
  godot_executable = $resolvedGodot
  heartbeat_live = $false
  heartbeat_age_ms = $null
  refresh_status = $null
  editor_control_status = $null
  editor_control_action = $null
  editor_focus_status = $null
  editor_focus_panel_status = $null
  editor_focus_panel_panel = $null
  editor_focus_panel_native_clear_supported = $null
  editor_batch_status = $null
  editor_batch_result_status = $null
  editor_batch_result_count = $null
  editor_batch_all_actions_succeeded = $false
  editor_batch_snapshot_refreshed = $false
  select_node_status = $null
  node_deep_status = $null
  list_resources_status = $null
  imported_assets_status = $null
  class_info_status = $null
  material_inspect_status = $null
  signal_list_status = $null
  create_node_gate_status = $null
  create_node_gate_error_code = $null
  screenshot_status = $null
  screenshot_created = $false
  screenshot_path = $null
  screenshot_width = $null
  screenshot_height = $null
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
    $result.status = "error"
    $result.error = "Godot editor heartbeat did not become live within $StartupTimeoutSeconds seconds."
    return $result | ConvertTo-Json -Depth 10
  }

  $refresh = Send-BridgeRequest "refresh_context" @{ requested_by = "visible_editor_validation" } $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.refresh_status = if ($refresh.response -ne $null) { $refresh.response.status } else { "timeout" }
  $result.refresh_response_path = $refresh.response_path

  $editorState = Send-BridgeRequest "editor_control" @{
    requested_by = "visible_editor_validation"
    action = "get_state"
    params = @{}
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.editor_control_status = if ($editorState.response -ne $null) { $editorState.response.status } else { "timeout" }
  $result.editor_control_response_path = $editorState.response_path
  if ($editorState.response -ne $null -and $editorState.response.data -ne $null) {
    $result.editor_control_action = $editorState.response.data.action
  }

  $editorFocus = Send-BridgeRequest "editor_control" @{
    requested_by = "visible_editor_validation"
    action = "focus_editor"
    params = @{
      main_screen = "3D"
    }
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.editor_focus_status = if ($editorFocus.response -ne $null) { $editorFocus.response.status } else { "timeout" }
  $result.editor_focus_response_path = $editorFocus.response_path

  $editorFocusPanel = Send-BridgeRequest "editor_control" @{
    requested_by = "visible_editor_validation"
    action = "focus_panel"
    params = @{
      panel = "Debugger"
    }
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.editor_focus_panel_status = if ($editorFocusPanel.response -ne $null) { $editorFocusPanel.response.status } else { "timeout" }
  $result.editor_focus_panel_response_path = $editorFocusPanel.response_path
  if ($editorFocusPanel.response -ne $null -and $editorFocusPanel.response.data -ne $null) {
    $result.editor_focus_panel_panel = $editorFocusPanel.response.data.panel
    $result.editor_focus_panel_native_clear_supported = [bool]$editorFocusPanel.response.data.native_clear_supported
  }

  $editorBatch = Send-BridgeRequest "editor_control" @{
    requested_by = "visible_editor_validation"
    action = "editor_batch"
    params = @{
      stop_on_error = $true
      actions = @(
        @{
          action = "focus_editor"
          params = @{
            main_screen = "3D"
          }
        },
        @{
          action = "focus_panel"
          params = @{
            panel = "Debugger"
          }
        },
        @{
          action = "select_node"
          params = @{
            node_path = "Camera3D"
            focus_inspector = $true
          }
        }
      )
    }
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.editor_batch_status = if ($editorBatch.response -ne $null) { $editorBatch.response.status } else { "timeout" }
  $result.editor_batch_response_path = $editorBatch.response_path
  if ($editorBatch.response -ne $null -and $editorBatch.response.data -ne $null) {
    $result.editor_batch_result_status = $editorBatch.response.data.status
    $batchResults = @($editorBatch.response.data.results)
    $result.editor_batch_result_count = $batchResults.Count
    $failedBatchActions = @($batchResults | Where-Object { $_.status -ne "succeeded" })
    $result.editor_batch_all_actions_succeeded = ($batchResults.Count -eq 3 -and $failedBatchActions.Count -eq 0)
    $result.editor_batch_snapshot_refreshed = [bool]$editorBatch.response.data.snapshot_refreshed
  }

  $selectNode = Send-BridgeRequest "editor_control" @{
    requested_by = "visible_editor_validation"
    action = "select_node"
    params = @{
      node_path = "Camera3D"
      focus_inspector = $true
    }
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.select_node_status = if ($selectNode.response -ne $null) { $selectNode.response.status } else { "timeout" }
  $result.select_node_response_path = $selectNode.response_path

  $nodeDeep = Send-BridgeRequest "editor_control" @{
    requested_by = "visible_editor_validation"
    action = "get_node_deep"
    params = @{
      node_path = "."
      depth = 2
      max_nodes = 32
      include_properties = $false
    }
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.node_deep_status = if ($nodeDeep.response -ne $null) { $nodeDeep.response.status } else { "timeout" }
  $result.node_deep_response_path = $nodeDeep.response_path

  $listResources = Send-BridgeRequest "editor_control" @{
    requested_by = "visible_editor_validation"
    action = "list_resources"
    params = @{
      root_path = "res://scenes"
      extensions = @(".tscn")
      limit = 25
    }
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.list_resources_status = if ($listResources.response -ne $null) { $listResources.response.status } else { "timeout" }
  $result.list_resources_response_path = $listResources.response_path

  $importedAssets = Send-BridgeRequest "editor_control" @{
    requested_by = "visible_editor_validation"
    action = "inspect_imported_assets"
    params = @{
      root_path = "res://assets"
      extensions = @(".obj")
      placeable_only = $true
      include_dependencies = $false
      limit = 25
    }
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.imported_assets_status = if ($importedAssets.response -ne $null) { $importedAssets.response.status } else { "timeout" }
  $result.imported_assets_response_path = $importedAssets.response_path

  $classInfo = Send-BridgeRequest "editor_control" @{
    requested_by = "visible_editor_validation"
    action = "get_class_info"
    params = @{
      class_name = "Node3D"
      no_inheritance = $true
      limit = 20
    }
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.class_info_status = if ($classInfo.response -ne $null) { $classInfo.response.status } else { "timeout" }
  $result.class_info_response_path = $classInfo.response_path

  $materialInspect = Send-BridgeRequest "editor_control" @{
    requested_by = "visible_editor_validation"
    action = "inspect_materials"
    params = @{
      node_path = "MeshInstance3D"
      include_shader_params = $true
      include_empty = $true
      max_nodes = 8
      max_slots = 24
    }
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.material_inspect_status = if ($materialInspect.response -ne $null) { $materialInspect.response.status } else { "timeout" }
  $result.material_inspect_response_path = $materialInspect.response_path

  $signalList = Send-BridgeRequest "editor_control" @{
    requested_by = "visible_editor_validation"
    action = "list_signal_connections"
    params = @{
      node_path = "Camera3D"
      include_empty = $true
    }
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.signal_list_status = if ($signalList.response -ne $null) { $signalList.response.status } else { "timeout" }
  $result.signal_list_response_path = $signalList.response_path

  $createGate = Send-BridgeRequest "editor_control" @{
    requested_by = "visible_editor_validation"
    action = "create_node"
    params = @{
      parent_path = "."
      class_name = "Node3D"
      name = "ValidationShouldBeDenied"
    }
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.create_node_gate_status = if ($createGate.response -ne $null) { $createGate.response.status } else { "timeout" }
  $result.create_node_gate_response_path = $createGate.response_path
  if ($createGate.response -ne $null -and $createGate.response.error -ne $null) {
    $result.create_node_gate_error_code = $createGate.response.error.code
  }

  $before = @(Get-ChildItem -LiteralPath $screenshotsDir -Filter *.png -ErrorAction SilentlyContinue).Count
  $screenshot = Send-BridgeRequest "capture_viewport_screenshot" @{ requested_by = "visible_editor_validation" } $requestsDir $responsesDir $RequestTimeoutSeconds
  $afterFiles = @(Get-ChildItem -LiteralPath $screenshotsDir -Filter *.png -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
  $after = $afterFiles.Count
  $result.screenshot_status = if ($screenshot.response -ne $null) { $screenshot.response.status } else { "timeout" }
  $result.screenshot_response_path = $screenshot.response_path
  $result.screenshot_created = ($after -gt $before)

  if ($screenshot.response -ne $null -and $screenshot.response.data -ne $null -and $screenshot.response.data.screenshot -ne $null) {
    $artifact = $screenshot.response.data.screenshot.artifact
    $result.screenshot_path = $artifact.local_path
    $result.screenshot_width = $artifact.width
    $result.screenshot_height = $artifact.height
  } elseif ($afterFiles.Count -gt 0) {
    $result.screenshot_path = $afterFiles[0].FullName
  }

  $result.status = if ($result.refresh_status -eq "succeeded" -and $result.editor_control_status -eq "succeeded" -and $result.editor_focus_status -eq "succeeded" -and $result.editor_focus_panel_status -eq "succeeded" -and $result.editor_focus_panel_panel -eq "Debugger" -and -not $result.editor_focus_panel_native_clear_supported -and $result.editor_batch_status -eq "succeeded" -and $result.editor_batch_result_status -eq "succeeded" -and $result.editor_batch_all_actions_succeeded -and $result.editor_batch_snapshot_refreshed -and $result.select_node_status -eq "succeeded" -and $result.node_deep_status -eq "succeeded" -and $result.list_resources_status -eq "succeeded" -and $result.imported_assets_status -eq "succeeded" -and $result.class_info_status -eq "succeeded" -and $result.material_inspect_status -eq "succeeded" -and $result.signal_list_status -eq "succeeded" -and $result.create_node_gate_status -eq "failed" -and $result.create_node_gate_error_code -eq "permission_denied" -and $result.screenshot_status -eq "succeeded" -and $result.screenshot_created) {
    "ok"
  } else {
    "error"
  }
}
finally {
  $result.completed_at = (Get-Date).ToUniversalTime().ToString("o")
  $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $reportPath -Encoding UTF8

  if (-not $KeepOpen -and $process -and -not $process.HasExited) {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
  }
}

$result | ConvertTo-Json -Depth 10
