param(
  [string] $ProjectRoot = "examples\minimal_3d_project",
  [string] $GodotExecutable = $(if ($env:GODOT_BIN) { $env:GODOT_BIN } elseif (Get-Command godot -ErrorAction SilentlyContinue) { (Get-Command godot).Source } else { "godot" }),
  [string] $ScenePath = "res://scenes/main_3d.tscn",
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

function Convert-ResPathToAbsolute([string] $ProjectRootValue, [string] $ResPath) {
  if (-not $ResPath.StartsWith("res://")) {
    throw "Expected res:// scene path, got $ResPath"
  }
  $relative = $ResPath.Substring("res://".Length).Replace("/", [System.IO.Path]::DirectorySeparatorChar)
  return Join-Path $ProjectRootValue $relative
}

function Get-Sha256File([string] $PathValue) {
  $stream = [System.IO.File]::OpenRead($PathValue)
  try {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
      $hashBytes = $sha.ComputeHash($stream)
      return ([System.BitConverter]::ToString($hashBytes)).Replace("-", "")
    }
    finally {
      $sha.Dispose()
    }
  }
  finally {
    $stream.Dispose()
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
    requested_by = "live_mutation_validation"
    action = $Action
    params = $Params
  } $RequestsDir $ResponsesDir $TimeoutSeconds
}

function Add-StepResult([System.Collections.ArrayList] $Steps, [string] $Name, $Result) {
  $status = if ($Result.response -ne $null) { $Result.response.status } elseif ($Result.timeout) { "timeout" } else { "missing_response" }
  $errorCode = $null
  if ($Result.response -ne $null -and $Result.response.error -ne $null) {
    $errorCode = $Result.response.error.code
  }
  [void]$Steps.Add([ordered]@{
    name = $Name
    status = $status
    error_code = $errorCode
    response_path = $Result.response_path
  })
}

function Assert-StepSucceeded([string] $Name, $Result) {
  if ($Result.response -eq $null -or $Result.response.status -ne "succeeded") {
    $raw = if ($Result.response -ne $null) { $Result.response | ConvertTo-Json -Depth 8 } else { "timeout" }
    throw "$Name failed: $raw"
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
$reportPath = Join-Path $artifactsDir "live_mutation_validation.json"

New-Item -ItemType Directory -Force -Path $requestsDir, $responsesDir, $artifactsDir | Out-Null

$beforeHash = Get-Sha256File $sceneFile
$process = Start-Process -FilePath $resolvedGodot -ArgumentList @("--path", $resolvedProjectRoot, "--editor") -PassThru
$steps = [System.Collections.ArrayList]::new()
$result = [ordered]@{
  status = "started"
  started_at = (Get-Date).ToUniversalTime().ToString("o")
  process_id = $process.Id
  project_root = $resolvedProjectRoot
  godot_executable = $resolvedGodot
  scene_path = $ScenePath
  scene_file = $sceneFile
  scene_sha256_before = $beforeHash
  scene_sha256_after = $null
  scene_hash_unchanged = $false
  heartbeat_live = $false
  heartbeat_age_ms = $null
  steps = $steps
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
    requested_by = "live_mutation_validation"
    scene_path = $ScenePath
    make_main_screen = "3D"
    select_in_file_system = $true
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "open_scene" $openScene
  Assert-StepSucceeded "open_scene" $openScene

  $enableEdits = Send-BridgeRequest "set_bridge_permission" @{
    requested_by = "live_mutation_validation"
    validation_token = "GCB_VALIDATE_PERMISSION_TOGGLE"
    key = "allow_scene_edits"
    value = $true
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "enable_scene_edits_permission" $enableEdits
  Assert-StepSucceeded "enable_scene_edits_permission" $enableEdits

  $enableAnimationPreview = Send-BridgeRequest "set_bridge_permission" @{
    requested_by = "live_mutation_validation"
    validation_token = "GCB_VALIDATE_PERMISSION_TOGGLE"
    key = "allow_animation_preview"
    value = $true
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "enable_animation_preview_permission" $enableAnimationPreview
  Assert-StepSucceeded "enable_animation_preview_permission" $enableAnimationPreview

  $floatMesh = Invoke-EditorAction "set_node_transform" @{
    node_path = "MeshInstance3D"
    mode = "absolute"
    position = @{
      x = 0.35
      y = 3.0
      z = 0.25
    }
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "prepare_mesh_for_spatial_snap" $floatMesh
  Assert-StepSucceeded "prepare_mesh_for_spatial_snap" $floatMesh

  $snapGround = Invoke-EditorAction "snap_to_ground" @{
    node_path = "MeshInstance3D"
    ground_y = 0.0
    tolerance = 0.05
    grid_size = 1.0
    grid_origin = @{
      x = 0.0
      y = 0.0
      z = 0.0
    }
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "snap_mesh_to_ground" $snapGround
  Assert-StepSucceeded "snap_mesh_to_ground" $snapGround
  if (-not [bool]$snapGround.response.data.changed) {
    throw "snap_to_ground did not report a changed node."
  }

  $boundsAfterSnap = Invoke-EditorAction "get_spatial_bounds" @{
    node_path = "MeshInstance3D"
    ground_y = 0.0
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "bounds_after_snap_to_ground" $boundsAfterSnap
  Assert-StepSucceeded "bounds_after_snap_to_ground" $boundsAfterSnap
  $snappedNode = @($boundsAfterSnap.response.data.nodes)[0]
  $snappedGap = [double]$snappedNode.ground_gap
  $snappedX = [double]$snappedNode.global_position.x
  $snappedZ = [double]$snappedNode.global_position.z
  if ([Math]::Abs($snappedGap) -gt 0.06) {
    throw "snap_to_ground left ground gap $snappedGap."
  }
  if ([Math]::Abs($snappedX) -gt 0.001 -or [Math]::Abs($snappedZ) -gt 0.001) {
    throw "snap_to_ground grid snap did not align X/Z: x=$snappedX z=$snappedZ."
  }

  $undoSnapGround = Invoke-EditorAction "undo_last_bridge_action" @{} $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "undo_snap_to_ground" $undoSnapGround
  Assert-StepSucceeded "undo_snap_to_ground" $undoSnapGround

  $boundsAfterUndo = Invoke-EditorAction "get_spatial_bounds" @{
    node_path = "MeshInstance3D"
    ground_y = 0.0
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "bounds_after_snap_undo" $boundsAfterUndo
  Assert-StepSucceeded "bounds_after_snap_undo" $boundsAfterUndo
  $undoNode = @($boundsAfterUndo.response.data.nodes)[0]
  $undoGap = [double]$undoNode.ground_gap
  if ($undoGap -le 0.5) {
    throw "undo_last_bridge_action did not restore the floating mesh gap; gap=$undoGap."
  }

  $snapGrid = Invoke-EditorAction "snap_to_grid" @{
    node_path = "MeshInstance3D"
    grid_size = 1.0
    axes = @("x", "z")
    tolerance = 0.001
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "snap_mesh_to_grid" $snapGrid
  Assert-StepSucceeded "snap_mesh_to_grid" $snapGrid
  if (-not [bool]$snapGrid.response.data.changed) {
    throw "snap_to_grid did not report a changed node."
  }

  $undoSnapGrid = Invoke-EditorAction "undo_last_bridge_action" @{} $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "undo_snap_to_grid" $undoSnapGrid
  Assert-StepSucceeded "undo_snap_to_grid" $undoSnapGrid

  $inspectMaterials = Invoke-EditorAction "inspect_materials" @{
    node_path = "MeshInstance3D"
    include_shader_params = $true
    include_empty = $false
    max_nodes = 4
    max_slots = 8
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "inspect_materials" $inspectMaterials
  Assert-StepSucceeded "inspect_materials" $inspectMaterials

  $setShaderParameter = Invoke-EditorAction "set_shader_parameter" @{
    node_path = "MeshInstance3D"
    slot_kind = "geometry_material_override"
    parameter = "glow_strength"
    value = 0.9
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "set_shader_parameter" $setShaderParameter
  Assert-StepSucceeded "set_shader_parameter" $setShaderParameter

  $inspectImportedAssets = Invoke-EditorAction "inspect_imported_assets" @{
    root_path = "res://assets"
    extensions = @(".obj")
    placeable_only = $true
    limit = 25
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "inspect_imported_assets" $inspectImportedAssets
  Assert-StepSucceeded "inspect_imported_assets" $inspectImportedAssets

  $placeAsset = Invoke-EditorAction "place_asset_in_scene" @{
    asset_path = "res://assets/models/validation_triangle.obj"
    parent_path = "."
    name = "ValidationPlacedAsset"
    position = @{
      x = 2.0
      y = 0.0
      z = 0.0
    }
    scale = @{
      x = 1.0
      y = 1.0
      z = 1.0
    }
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "place_imported_asset" $placeAsset
  Assert-StepSucceeded "place_imported_asset" $placeAsset

  $createParent = Invoke-EditorAction "create_node" @{
    parent_path = "."
    class_name = "Node3D"
    name = "ValidationParent"
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "create_parent_node" $createParent
  Assert-StepSucceeded "create_parent_node" $createParent

  $createChild = Invoke-EditorAction "create_node" @{
    parent_path = "ValidationParent"
    class_name = "Node3D"
    name = "ValidationChild"
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "create_child_node" $createChild
  Assert-StepSucceeded "create_child_node" $createChild

  $renameChild = Invoke-EditorAction "rename_node" @{
    node_path = "ValidationParent/ValidationChild"
    new_name = "ValidationLeaf"
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "rename_child_node" $renameChild
  Assert-StepSucceeded "rename_child_node" $renameChild

  $duplicate = Invoke-EditorAction "duplicate_node" @{
    node_path = "ValidationParent/ValidationLeaf"
    parent_path = "."
    name = "ValidationDuplicate"
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "duplicate_node" $duplicate
  Assert-StepSucceeded "duplicate_node" $duplicate

  $reparent = Invoke-EditorAction "reparent_node" @{
    node_path = "ValidationDuplicate"
    new_parent_path = "StaticBody3D"
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "reparent_node" $reparent
  Assert-StepSucceeded "reparent_node" $reparent

  $createMeshResource = Invoke-EditorAction "create_node_resource" @{
    node_path = "MeshInstance3D"
    property = "mesh"
    resource_class = "BoxMesh"
    changes = @(
      @{
        property = "size"
        value = @{
          x = 1.5
          y = 0.75
          z = 2.25
        }
      }
    )
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "create_mesh_resource" $createMeshResource
  Assert-StepSucceeded "create_mesh_resource" $createMeshResource

  $createMaterialResource = Invoke-EditorAction "create_node_resource" @{
    node_path = "MeshInstance3D"
    property = "material_override"
    resource_class = "StandardMaterial3D"
    changes = @(
      @{
        property = "albedo_color"
        value = @{
          r = 0.18
          g = 0.72
          b = 1.0
          a = 1.0
        }
      },
      @{
        property = "roughness"
        value = 0.55
      }
    )
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "create_material_resource" $createMaterialResource
  Assert-StepSucceeded "create_material_resource" $createMaterialResource

  $setMaterialProperties = Invoke-EditorAction "set_resource_properties" @{
    node_path = "MeshInstance3D"
    property = "material_override"
    changes = @(
      @{
        property = "albedo_color"
        value = @{
          r = 1.0
          g = 0.42
          b = 0.18
          a = 1.0
        }
      }
    )
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "set_material_properties" $setMaterialProperties
  Assert-StepSucceeded "set_material_properties" $setMaterialProperties

  $clearMaterialResource = Invoke-EditorAction "assign_resource_to_node" @{
    node_path = "MeshInstance3D"
    property = "material_override"
    clear = $true
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "clear_material_resource" $clearMaterialResource
  Assert-StepSucceeded "clear_material_resource" $clearMaterialResource

  $createShaderMaterial = Invoke-EditorAction "create_shader_material_for_node" @{
    node_path = "MeshInstance3D"
    slot_kind = "geometry_material_override"
    shader_path = "res://assets/shaders/validation_glow.gdshader"
    parameters = @{
      glow_strength = 0.35
      tint_color = @{
        r = 0.25
        g = 0.85
        b = 1.0
        a = 1.0
      }
    }
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "create_shader_material_for_node" $createShaderMaterial
  Assert-StepSucceeded "create_shader_material_for_node" $createShaderMaterial

  $setShaderTextureParameter = Invoke-EditorAction "set_shader_texture_parameter" @{
    node_path = "MeshInstance3D"
    slot_kind = "geometry_material_override"
    parameter = "detail_texture"
    texture_path = "res://assets/textures/validation_checker.svg"
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "set_shader_texture_parameter" $setShaderTextureParameter
  Assert-StepSucceeded "set_shader_texture_parameter" $setShaderTextureParameter

  $setCreatedShaderParameter = Invoke-EditorAction "set_shader_parameter" @{
    node_path = "MeshInstance3D"
    slot_kind = "geometry_material_override"
    parameter = "glow_strength"
    value = 0.65
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "set_created_shader_parameter" $setCreatedShaderParameter
  Assert-StepSucceeded "set_created_shader_parameter" $setCreatedShaderParameter

  $setEnvironmentProperty = Invoke-EditorAction "set_environment_property" @{
    node_path = "WorldEnvironment"
    property = "glow_intensity"
    value = 0.55
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "set_environment_property" $setEnvironmentProperty
  Assert-StepSucceeded "set_environment_property" $setEnvironmentProperty

  $createParticleEffect = Invoke-EditorAction "create_particle_effect" @{
    parent_path = "."
    name = "ValidationParticles"
    amount = 32
    lifetime = 1.25
    position = @{
      x = 0.0
      y = 1.5
      z = 0.0
    }
    color = @{
      r = 1.0
      g = 0.72
      b = 0.22
      a = 1.0
    }
    initial_velocity_min = 0.6
    initial_velocity_max = 1.8
    particle_scale_min = 0.12
    particle_scale_max = 0.32
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "create_particle_effect" $createParticleEffect
  Assert-StepSucceeded "create_particle_effect" $createParticleEffect

  $setParticleEffectProperties = Invoke-EditorAction "set_particle_effect_properties" @{
    node_path = "ValidationParticles"
    amount = 48
    emitting = $true
    draw_mesh = "unchanged"
    draw_size = 0.45
    color = @{
      r = 0.35
      g = 0.82
      b = 1.0
      a = 1.0
    }
    initial_velocity_min = 1.0
    initial_velocity_max = 2.6
    particle_scale_min = 0.18
    particle_scale_max = 0.42
    restart = $true
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "set_particle_effect_properties" $setParticleEffectProperties
  Assert-StepSucceeded "set_particle_effect_properties" $setParticleEffectProperties

  $createAnimationPlayer = Invoke-EditorAction "create_node" @{
    parent_path = "."
    class_name = "AnimationPlayer"
    name = "ValidationAnimationPlayer"
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "create_animation_player_node" $createAnimationPlayer
  Assert-StepSucceeded "create_animation_player_node" $createAnimationPlayer

  $createAnimationClip = Invoke-EditorAction "create_animation_clip" @{
    node_path = "ValidationAnimationPlayer"
    animation_name = "float_test"
    length = 1.0
    step = 0.1
    loop_mode = 0
    tracks = @(
      @{
        type = "value"
        path = "MeshInstance3D:position"
        value_type = "vector3"
        keys = @(
          @{
            time = 0.0
            value = @{
              x = 0.0
              y = 0.0
              z = 0.0
            }
          },
          @{
            time = 1.0
            value = @{
              x = 0.0
              y = 1.0
              z = 0.0
            }
          }
        )
      }
    )
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "create_animation_clip" $createAnimationClip
  Assert-StepSucceeded "create_animation_clip" $createAnimationClip

  $listAnimations = Invoke-EditorAction "list_animation_players" @{
    max_players = 16
    include_empty = $true
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "list_animation_players" $listAnimations
  Assert-StepSucceeded "list_animation_players" $listAnimations

  $inspectAnimation = Invoke-EditorAction "inspect_animation" @{
    node_path = "ValidationAnimationPlayer"
    animation_name = "float_test"
    include_keys = $true
    max_tracks = 8
    max_keys_per_track = 4
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "inspect_animation" $inspectAnimation
  Assert-StepSucceeded "inspect_animation" $inspectAnimation

  $previewAnimation = Invoke-EditorAction "preview_animation" @{
    node_path = "ValidationAnimationPlayer"
    animation_name = "float_test"
    mode = "seek"
    position = 0.5
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "preview_animation_seek" $previewAnimation
  Assert-StepSucceeded "preview_animation_seek" $previewAnimation

  $stopAnimation = Invoke-EditorAction "stop_animation_preview" @{
    node_path = "ValidationAnimationPlayer"
    keep_state = $true
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "stop_animation_preview" $stopAnimation
  Assert-StepSucceeded "stop_animation_preview" $stopAnimation

  $connectSignal = Invoke-EditorAction "connect_signal" @{
    source_node_path = "ValidationParent"
    signal_name = "tree_entered"
    target_node_path = "."
    method_name = "get_name"
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "connect_signal" $connectSignal
  Assert-StepSucceeded "connect_signal" $connectSignal

  $listSignals = Invoke-EditorAction "list_signal_connections" @{
    node_path = "ValidationParent"
    include_empty = $false
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "list_signal_connections" $listSignals
  Assert-StepSucceeded "list_signal_connections" $listSignals

  $disconnectSignal = Invoke-EditorAction "disconnect_signal" @{
    source_node_path = "ValidationParent"
    signal_name = "tree_entered"
    target_node_path = "."
    method_name = "get_name"
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "disconnect_signal" $disconnectSignal
  Assert-StepSucceeded "disconnect_signal" $disconnectSignal

  $deepNode = Invoke-EditorAction "get_node_deep" @{
    node_path = "."
    depth = 3
    max_nodes = 64
    include_properties = $false
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "get_node_deep_after_mutation" $deepNode
  Assert-StepSucceeded "get_node_deep_after_mutation" $deepNode

  $disableAnimationPreview = Send-BridgeRequest "set_bridge_permission" @{
    requested_by = "live_mutation_validation"
    validation_token = "GCB_VALIDATE_PERMISSION_TOGGLE"
    key = "allow_animation_preview"
    value = $false
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "disable_animation_preview_permission" $disableAnimationPreview
  Assert-StepSucceeded "disable_animation_preview_permission" $disableAnimationPreview

  $disableEdits = Send-BridgeRequest "set_bridge_permission" @{
    requested_by = "live_mutation_validation"
    validation_token = "GCB_VALIDATE_PERMISSION_TOGGLE"
    key = "allow_scene_edits"
    value = $false
  } $requestsDir $responsesDir $RequestTimeoutSeconds
  Add-StepResult $steps "disable_scene_edits_permission" $disableEdits
  Assert-StepSucceeded "disable_scene_edits_permission" $disableEdits

  Start-Sleep -Milliseconds 500
  $afterHash = Get-Sha256File $sceneFile
  $result.scene_sha256_after = $afterHash
  $result.scene_hash_unchanged = ($beforeHash -eq $afterHash)
  $result.status = if ($result.scene_hash_unchanged) { "ok" } else { "error" }
  if (-not $result.scene_hash_unchanged) {
    $result.error = "Scene file hash changed even though live editor actions should not save scenes."
  }
}
catch {
  $result.status = "error"
  $result.error = $_.Exception.Message
  if ((Test-Path -LiteralPath $sceneFile)) {
    $result.scene_sha256_after = Get-Sha256File $sceneFile
    $result.scene_hash_unchanged = ($beforeHash -eq $result.scene_sha256_after)
  }
}
finally {
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
