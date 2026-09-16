param(
  [string] $ProjectRoot = "examples\minimal_3d_project",
  [string] $GodotExecutable = $(if ($env:GODOT_BIN) { $env:GODOT_BIN } elseif (Get-Command godot -ErrorAction SilentlyContinue) { (Get-Command godot).Source } else { "godot" }),
  [string] $ScenePath = "res://scenes/main_3d.tscn",
  [string] $NodePath = "MeshInstance3D",
  [int] $StartupTimeoutSeconds = 45,
  [int] $RequestTimeoutSeconds = 30,
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
    requested_by = "multi_view_capture_validation"
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

function Get-PngInfo([string] $PathValue) {
  if (-not (Test-Path -LiteralPath $PathValue)) {
    throw "PNG not found: $PathValue"
  }
  $bytes = [System.IO.File]::ReadAllBytes($PathValue)
  $pngSignature = [byte[]](0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a)
  for ($i = 0; $i -lt $pngSignature.Length; $i++) {
    if ($bytes[$i] -ne $pngSignature[$i]) {
      throw "Invalid PNG signature: $PathValue"
    }
  }

  Add-Type -AssemblyName System.Drawing
  $bitmap = [System.Drawing.Bitmap]::FromFile($PathValue)
  try {
    $sampledColors = New-Object 'System.Collections.Generic.HashSet[string]'
    $stepX = [Math]::Max(1, [int][Math]::Floor($bitmap.Width / 32))
    $stepY = [Math]::Max(1, [int][Math]::Floor($bitmap.Height / 32))
    $sampleXs = New-Object 'System.Collections.Generic.List[int]'
    $sampleYs = New-Object 'System.Collections.Generic.List[int]'
    for ($x = 0; $x -lt $bitmap.Width; $x += $stepX) {
      $sampleXs.Add($x)
    }
    if ($sampleXs[$sampleXs.Count - 1] -ne ($bitmap.Width - 1)) {
      $sampleXs.Add($bitmap.Width - 1)
    }
    for ($y = 0; $y -lt $bitmap.Height; $y += $stepY) {
      $sampleYs.Add($y)
    }
    if ($sampleYs[$sampleYs.Count - 1] -ne ($bitmap.Height - 1)) {
      $sampleYs.Add($bitmap.Height - 1)
    }
    foreach ($x in $sampleXs) {
      foreach ($y in $sampleYs) {
        $pixel = $bitmap.GetPixel($x, $y)
        [void]$sampledColors.Add("$($pixel.A),$($pixel.R),$($pixel.G),$($pixel.B)")
      }
    }
    return [ordered]@{
      path = $PathValue
      width = $bitmap.Width
      height = $bitmap.Height
      byte_size = $bytes.Length
      sampled_unique_colors = $sampledColors.Count
      non_uniform_sample = ($sampledColors.Count -gt 1)
    }
  }
  finally {
    $bitmap.Dispose()
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
$heartbeatPath = Join-Path $bridgeDir "heartbeat.json"
$snapshotPath = Join-Path $bridgeDir "context_snapshot.json"
$reportPath = Join-Path $artifactsDir "multi_view_capture_validation.json"

New-Item -ItemType Directory -Force -Path $requestsDir, $responsesDir, $artifactsDir | Out-Null

$process = Start-Process -FilePath $resolvedGodot -ArgumentList @("--path", $resolvedProjectRoot, "--editor") -PassThru
$frames = New-Object System.Collections.ArrayList
$result = [ordered]@{
  status = "started"
  started_at = (Get-Date).ToUniversalTime().ToString("o")
  process_id = $process.Id
  project_root = $resolvedProjectRoot
  godot_executable = $resolvedGodot
  scene_path = $ScenePath
  node_path = $NodePath
  heartbeat_live = $false
  heartbeat_age_ms = $null
  open_scene_status = $null
  select_node_status = $null
  capture_status = $null
  capture_manifest_status = $null
  capture_id = $null
  manifest_path = $null
  manifest_exists = $false
  view_count = 0
  view_count_succeeded = 0
  gpu_frame_count = 0
  fallback_frame_count = 0
  frames = $frames
  all_frames_exist = $false
  all_frames_non_uniform = $false
  all_frames_have_expected_dimensions = $false
  all_frames_have_render_source = $false
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

  $openScene = Send-BridgeRequest "open_scene" @{
    requested_by = "multi_view_capture_validation"
    scene_path = $ScenePath
    make_main_screen = "3D"
    select_in_file_system = $true
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.open_scene_status = Get-ResponseStatus $openScene
  $result.open_scene_response_path = $openScene.response_path
  Assert-Succeeded "open_scene" $openScene

  $selectNode = Invoke-EditorAction "select_node" @{
    node_path = $NodePath
    focus_inspector = $true
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.select_node_status = Get-ResponseStatus $selectNode
  $result.select_node_response_path = $selectNode.response_path
  Assert-Succeeded "select_node" $selectNode

  $capture = Invoke-EditorAction "capture_multi_view" @{
    node_path = $NodePath
    selected_only = $false
    max_nodes = 16
    width = 640
    height = 480
    views = @("front", "side", "top", "perspective")
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  $result.capture_status = Get-ResponseStatus $capture
  $result.capture_response_path = $capture.response_path
  Assert-Succeeded "capture_multi_view" $capture

  $data = $capture.response.data
  $result.capture_manifest_status = [string]$data.status
  $result.capture_id = [string]$data.capture_id
  $result.manifest_path = [string]$data.manifest_path
  $result.manifest_exists = (Test-Path -LiteralPath $result.manifest_path)
  $result.view_count = [int]$data.view_count
  $result.view_count_succeeded = [int]$data.view_count_succeeded

  foreach ($frame in @($data.frames)) {
    $artifact = $frame.artifact
    $localPath = [string]$artifact.local_path
    $png = Get-PngInfo $localPath
    $renderSource = [string]$frame.render_source
    if ($renderSource -eq "subviewport_gpu") {
      $result.gpu_frame_count += 1
    }
    if ($renderSource -eq "software_geometry_fallback") {
      $result.fallback_frame_count += 1
    }
    [void]$frames.Add([ordered]@{
      view = [string]$frame.view
      status = [string]$frame.status
      render_source = $renderSource
      gpu_uniform_fallback = [bool]$frame.gpu_uniform_fallback
      path = $localPath
      exists = (Test-Path -LiteralPath $localPath)
      width = $png.width
      height = $png.height
      byte_size = $png.byte_size
      sampled_unique_colors = $png.sampled_unique_colors
      non_uniform_sample = $png.non_uniform_sample
    })
  }

  $frameArray = @($frames)
  $result.all_frames_exist = ($frameArray.Count -eq 4 -and @($frameArray | Where-Object { -not $_.exists }).Count -eq 0)
  $result.all_frames_non_uniform = ($frameArray.Count -eq 4 -and @($frameArray | Where-Object { -not $_.non_uniform_sample }).Count -eq 0)
  $result.all_frames_have_expected_dimensions = ($frameArray.Count -eq 4 -and @($frameArray | Where-Object { $_.width -ne 640 -or $_.height -ne 480 }).Count -eq 0)
  $result.all_frames_have_render_source = ($frameArray.Count -eq 4 -and @($frameArray | Where-Object { [string]::IsNullOrWhiteSpace($_.render_source) }).Count -eq 0)

  $result.status = if (
    $result.open_scene_status -eq "succeeded" -and
    $result.select_node_status -eq "succeeded" -and
    $result.capture_status -eq "succeeded" -and
    $result.capture_manifest_status -eq "ok" -and
    $result.manifest_exists -and
    $result.view_count -eq 4 -and
    $result.view_count_succeeded -eq 4 -and
    $result.all_frames_exist -and
    $result.all_frames_non_uniform -and
    $result.all_frames_have_expected_dimensions -and
    $result.all_frames_have_render_source -and
    $result.gpu_frame_count -ge 1
  ) {
    "ok"
  } else {
    "error"
  }
}
finally {
  $result.completed_at = (Get-Date).ToUniversalTime().ToString("o")
  $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportPath -Encoding UTF8

  if (-not $KeepOpen -and $process -and -not $process.HasExited) {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
  }
}

$jsonResult = $result | ConvertTo-Json -Depth 12
$jsonResult
if ($result.status -ne "ok") {
  exit 1
}
