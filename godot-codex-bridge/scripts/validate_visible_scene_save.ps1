param(
  [string] $ProjectRoot = "examples\minimal_3d_project",
  [string] $GodotExecutable = $(if ($env:GODOT_BIN) { $env:GODOT_BIN } elseif (Get-Command godot -ErrorAction SilentlyContinue) { (Get-Command godot).Source } else { "godot" }),
  [string] $GodotConsoleExecutable = $(if ($env:GODOT_CONSOLE_BIN) { $env:GODOT_CONSOLE_BIN } elseif ($env:GODOT_PATH) { $env:GODOT_PATH } elseif ($env:GODOT_BIN) { $env:GODOT_BIN } else { "godot" }),
  [int] $StartupTimeoutSeconds = 45,
  [int] $RequestTimeoutSeconds = 20
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

function Response-Status($RequestResult) {
  if ($RequestResult.response -ne $null) {
    return [string]$RequestResult.response.status
  }
  return "timeout"
}

function Require-Succeeded([string] $Label, $RequestResult) {
  $status = Response-Status $RequestResult
  if ($status -ne "succeeded") {
    $errorText = ""
    if ($RequestResult.response -ne $null -and $RequestResult.response.error -ne $null) {
      $errorText = ($RequestResult.response.error | ConvertTo-Json -Depth 8)
    }
    throw "$Label failed with status '$status'. $errorText"
  }
}

$productRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$resolvedProjectRoot = Resolve-FullPath $ProjectRoot $productRoot
$resolvedGodot = Resolve-FullPath $GodotExecutable (Get-Location).Path
$resolvedGodotConsole = Resolve-FullPath $GodotConsoleExecutable (Get-Location).Path
$projectFile = Join-Path $resolvedProjectRoot "project.godot"
$sceneRelPath = "scenes\main_3d.tscn"
$sceneAbsPath = Join-Path $resolvedProjectRoot $sceneRelPath
$sceneResPath = "res://scenes/main_3d.tscn"

if (-not (Test-Path -LiteralPath $projectFile)) {
  throw "Wrong project root, project.godot not found: $resolvedProjectRoot"
}
if (-not (Test-Path -LiteralPath $sceneAbsPath)) {
  throw "Fixture scene not found: $sceneAbsPath"
}
if (-not (Test-Path -LiteralPath $resolvedGodot)) {
  throw "Godot executable not found: $resolvedGodot"
}
if (-not (Test-Path -LiteralPath $resolvedGodotConsole)) {
  throw "Godot console executable not found: $resolvedGodotConsole"
}

$bridgeDir = Join-Path $resolvedProjectRoot ".godot\godot_codex_bridge"
$requestsDir = Join-Path $bridgeDir "requests"
$responsesDir = Join-Path $bridgeDir "responses"
$artifactsDir = Join-Path $bridgeDir "artifacts"
$heartbeatPath = Join-Path $bridgeDir "heartbeat.json"
$snapshotPath = Join-Path $bridgeDir "context_snapshot.json"
$permissionsPath = Join-Path $bridgeDir "permissions.json"
$reportPath = Join-Path $artifactsDir "visible_scene_save_validation.json"

New-Item -ItemType Directory -Force -Path $requestsDir, $responsesDir, $artifactsDir | Out-Null

$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssfffZ")
$sceneBackupPath = Join-Path $artifactsDir "main_3d_scene_save_smoke_$stamp.tscn.bak"
$permissionsBackupPath = Join-Path $artifactsDir "permissions_scene_save_smoke_$stamp.json.bak"
Copy-Item -LiteralPath $sceneAbsPath -Destination $sceneBackupPath -Force
$hadPermissions = Test-Path -LiteralPath $permissionsPath
if ($hadPermissions) {
  Copy-Item -LiteralPath $permissionsPath -Destination $permissionsBackupPath -Force
}

$process = $null
$result = [ordered]@{
  status = "started"
  started_at = (Get-Date).ToUniversalTime().ToString("o")
  project_root = $resolvedProjectRoot
  godot_executable = $resolvedGodot
  godot_console_executable = $resolvedGodotConsole
  scene_path = $sceneResPath
  report_path = $reportPath
  scene_backup_path = $sceneBackupPath
  permissions_backup_path = if ($hadPermissions) { $permissionsBackupPath } else { "" }
  original_hash = (Get-FileHash -LiteralPath $sceneAbsPath -Algorithm SHA256).Hash
  changed_hash = ""
  restored_hash = ""
  heartbeat_live = $false
  open_scene_status = $null
  enable_edits_status = $null
  enable_save_status = $null
  edit_status = $null
  save_status = $null
  scene_hash_changed = $false
  saved_marker_seen = $false
  headless_parse_status = $null
  restored = $false
}

try {
  $process = Start-Process -FilePath $resolvedGodot -ArgumentList @("--path", $resolvedProjectRoot, "--editor") -PassThru
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

  $openScene = Send-BridgeRequest "open_scene" @{
    scene_path = $sceneResPath
    make_main_screen = "3D"
    select_in_file_system = $true
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.open_scene_status = Response-Status $openScene
  $result.open_scene_response_path = $openScene.response_path
  Require-Succeeded "open_scene" $openScene

  $enableEdits = Send-BridgeRequest "set_bridge_permission" @{
    validation_token = "GCB_VALIDATE_PERMISSION_TOGGLE"
    key = "allow_scene_edits"
    value = $true
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.enable_edits_status = Response-Status $enableEdits
  $result.enable_edits_response_path = $enableEdits.response_path
  Require-Succeeded "enable allow_scene_edits" $enableEdits

  $enableSave = Send-BridgeRequest "set_bridge_permission" @{
    validation_token = "GCB_VALIDATE_PERMISSION_TOGGLE"
    key = "allow_scene_save"
    value = $true
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.enable_save_status = Response-Status $enableSave
  $result.enable_save_response_path = $enableSave.response_path
  Require-Succeeded "enable allow_scene_save" $enableSave

  $newFov = 61.25 + ((Get-Date).Millisecond / 10000.0)
  $result.requested_fov = $newFov
  $edit = Send-BridgeRequest "editor_control" @{
    requested_by = "visible_scene_save_validation"
    action = "set_node_properties"
    params = @{
      node_path = "Camera3D"
      changes = @(
        @{
          property = "fov"
          value = $newFov
        }
      )
    }
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.edit_status = Response-Status $edit
  $result.edit_response_path = $edit.response_path
  Require-Succeeded "set_node_properties" $edit

  $save = Send-BridgeRequest "editor_control" @{
    requested_by = "visible_scene_save_validation"
    action = "save_scene"
    params = @{}
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.save_status = Response-Status $save
  $result.save_response_path = $save.response_path
  Require-Succeeded "save_scene" $save

  Start-Sleep -Milliseconds 500
  $result.changed_hash = (Get-FileHash -LiteralPath $sceneAbsPath -Algorithm SHA256).Hash
  $result.scene_hash_changed = $result.changed_hash -ne $result.original_hash
  $savedSceneText = Get-Content -Raw -LiteralPath $sceneAbsPath
  $result.saved_marker_seen = $savedSceneText -match "(?m)^fov = "
  if (-not $result.scene_hash_changed) {
    throw "Scene hash did not change after set_node_properties + save_scene."
  }
  if (-not $result.saved_marker_seen) {
    throw "Saved scene did not contain a persisted Camera3D fov property."
  }

  if ($process -and -not $process.HasExited) {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    $process.WaitForExit(5000) | Out-Null
  }

  & $resolvedGodotConsole --headless --path $resolvedProjectRoot --quit
  $result.headless_parse_exit_code = $LASTEXITCODE
  $result.headless_parse_status = if ($LASTEXITCODE -eq 0) { "succeeded" } else { "failed" }
  if ($LASTEXITCODE -ne 0) {
    throw "Headless parse failed after save_scene with exit code $LASTEXITCODE."
  }

  $result.status = "ok"
}
finally {
  if ($process -and -not $process.HasExited) {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
  }
  if (Test-Path -LiteralPath $sceneBackupPath) {
    Copy-Item -LiteralPath $sceneBackupPath -Destination $sceneAbsPath -Force
    $result.restored = $true
    $result.restored_hash = (Get-FileHash -LiteralPath $sceneAbsPath -Algorithm SHA256).Hash
  }
  if ($hadPermissions -and (Test-Path -LiteralPath $permissionsBackupPath)) {
    Copy-Item -LiteralPath $permissionsBackupPath -Destination $permissionsPath -Force
  } elseif (-not $hadPermissions -and (Test-Path -LiteralPath $permissionsPath)) {
    Remove-Item -LiteralPath $permissionsPath -Force -ErrorAction SilentlyContinue
  }
  $result.completed_at = (Get-Date).ToUniversalTime().ToString("o")
  $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportPath -Encoding UTF8
}

$result | ConvertTo-Json -Depth 12
