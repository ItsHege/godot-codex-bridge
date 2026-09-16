param(
  [Parameter(Mandatory = $true)]
  [string] $ProjectRoot,

  [string] $SourceAddon = "",

  [switch] $Apply,
  [switch] $Replace,
  [switch] $SimulateFailureAfterBackupForTest,

  [int] $HostPort = 49390,

  [ValidateSet("app-server", "mock")]
  [string] $HostRuntime = "app-server"
)

$ErrorActionPreference = "Stop"

function Resolve-FullPath([string] $PathValue, [string] $BasePath) {
  if ([System.IO.Path]::IsPathRooted($PathValue)) {
    return [System.IO.Path]::GetFullPath($PathValue)
  }
  return [System.IO.Path]::GetFullPath((Join-Path $BasePath $PathValue))
}

function Get-PluginCfgVersion([string] $PluginCfgPath) {
  if (-not (Test-Path -LiteralPath $PluginCfgPath)) {
    return $null
  }
  $text = Get-Content -Raw -LiteralPath $PluginCfgPath
  $match = [regex]::Match($text, '(?m)^version="([^"]+)"')
  if ($match.Success) {
    return $match.Groups[1].Value
  }
  return $null
}

function Get-FileAgeMs([string] $PathValue) {
  if (-not (Test-Path -LiteralPath $PathValue)) {
    return $null
  }
  $lastWrite = (Get-Item -LiteralPath $PathValue).LastWriteTimeUtc
  return [int64]([DateTime]::UtcNow - $lastWrite).TotalMilliseconds
}

function Write-Utf8NoBom([string] $PathValue, [string] $Text) {
  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($PathValue, $Text, $encoding)
}

function Get-Sha256Hex([string] $PathValue) {
  $stream = [System.IO.File]::OpenRead($PathValue)
  try {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
      return ([System.BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-", "")
    } finally {
      $sha.Dispose()
    }
  } finally {
    $stream.Dispose()
  }
}

function Get-AddonFileMap([string] $Root, [string] $ExcludedRelativePath = "") {
  $map = @{}
  if (-not (Test-Path -LiteralPath $Root)) {
    return $map
  }
  $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd("\")
  foreach ($file in (Get-ChildItem -LiteralPath $rootFull -Recurse -File)) {
    $relative = $file.FullName.Substring($rootFull.Length).TrimStart("\")
    if ($ExcludedRelativePath -ne "" -and $relative -ieq $ExcludedRelativePath) {
      continue
    }
    $map[$relative] = $file.FullName
  }
  return $map
}

function Get-AddonChangePreview([string] $SourceRoot, [string] $TargetRoot) {
  $sourceMap = Get-AddonFileMap $SourceRoot
  $targetMap = Get-AddonFileMap $TargetRoot "host_config.json"
  $added = New-Object System.Collections.Generic.List[string]
  $changed = New-Object System.Collections.Generic.List[string]
  $removed = New-Object System.Collections.Generic.List[string]

  foreach ($relative in $sourceMap.Keys) {
    if (-not $targetMap.ContainsKey($relative)) {
      $added.Add($relative)
      continue
    }
    $sourceHash = Get-Sha256Hex $sourceMap[$relative]
    $targetHash = Get-Sha256Hex $targetMap[$relative]
    if ($sourceHash -ne $targetHash) {
      $changed.Add($relative)
    }
  }
  foreach ($relative in $targetMap.Keys) {
    if (-not $sourceMap.ContainsKey($relative)) {
      $removed.Add($relative)
    }
  }

  return [ordered]@{
    added = @($added | Sort-Object)
    changed = @($changed | Sort-Object)
    removed = @($removed | Sort-Object)
    added_count = $added.Count
    changed_count = $changed.Count
    removed_count = $removed.Count
  }
}

function Assert-NoReparsePoint([string] $PathValue, [string] $BoundaryPath) {
  $boundary = [System.IO.Path]::GetFullPath($BoundaryPath).TrimEnd("\")
  $current = [System.IO.Path]::GetFullPath($PathValue).TrimEnd("\")
  while ($current.StartsWith($boundary, [System.StringComparison]::OrdinalIgnoreCase)) {
    if (Test-Path -LiteralPath $current) {
      $item = Get-Item -LiteralPath $current -Force
      if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing addon install through reparse point: $current"
      }
    }
    if ($current -ieq $boundary) {
      break
    }
    $parent = Split-Path -Parent $current
    if ($parent -eq $current -or [string]::IsNullOrWhiteSpace($parent)) {
      break
    }
    $current = $parent
  }
}

function Assert-NoReparseTree([string] $RootPath) {
  $root = Get-Item -LiteralPath $RootPath -Force
  $pending = New-Object System.Collections.Generic.Stack[System.IO.DirectoryInfo]
  if (($root.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "Refusing addon install from reparse point: $($root.FullName)"
  }
  $pending.Push($root)
  while ($pending.Count -gt 0) {
    $directory = $pending.Pop()
    foreach ($item in (Get-ChildItem -LiteralPath $directory.FullName -Force)) {
      if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing addon install from reparse point: $($item.FullName)"
      }
      if ($item.PSIsContainer) {
        $pending.Push($item)
      }
    }
  }
}

$productRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$productRootPath = $productRoot.Path
$hostRoot = Join-Path $productRootPath "codex_host"
$startScript = Join-Path $productRootPath "scripts\start_codex_host.ps1"
$nodeEntry = Join-Path $hostRoot "dist\src\index.js"
$resolvedProjectRoot = Resolve-FullPath $ProjectRoot (Get-Location).Path
$resolvedSourceAddon = if ($SourceAddon -ne "") {
  Resolve-FullPath $SourceAddon (Get-Location).Path
} else {
  Join-Path $productRootPath "addons\godot_codex_bridge"
}

$projectFile = Join-Path $resolvedProjectRoot "project.godot"
$targetAddon = Join-Path $resolvedProjectRoot "addons\godot_codex_bridge"
$targetPluginCfg = Join-Path $targetAddon "plugin.cfg"
$targetHostConfig = Join-Path $targetAddon "host_config.json"
$sourcePluginCfg = Join-Path $resolvedSourceAddon "plugin.cfg"
$sourcePluginGd = Join-Path $resolvedSourceAddon "plugin.gd"
$bridgeDir = Join-Path $resolvedProjectRoot ".godot\godot_codex_bridge"
$heartbeatPath = Join-Path $bridgeDir "heartbeat.json"
$snapshotPath = Join-Path $bridgeDir "context_snapshot.json"

$projectExists = Test-Path -LiteralPath $projectFile
$sourceExists = (Test-Path -LiteralPath $sourcePluginCfg) -and (Test-Path -LiteralPath $sourcePluginGd)
$targetExists = Test-Path -LiteralPath $targetPluginCfg
$targetHostConfigExists = Test-Path -LiteralPath $targetHostConfig
$projectText = if ($projectExists) { Get-Content -Raw -LiteralPath $projectFile } else { "" }
$pluginEnabled = if ($projectExists) { $projectText.Contains("res://addons/godot_codex_bridge/plugin.cfg") } else { $null }
$heartbeatAgeMs = Get-FileAgeMs $heartbeatPath
$snapshotAgeMs = Get-FileAgeMs $snapshotPath
$activeEditorDetected = ($heartbeatAgeMs -ne $null -and $heartbeatAgeMs -le 5000)
$staleEditor = ($heartbeatAgeMs -ne $null -and $heartbeatAgeMs -gt 5000)
$changePreview = if ($sourceExists) { Get-AddonChangePreview $resolvedSourceAddon $targetAddon } else { $null }

$checks = [ordered]@{
  project_file_exists = $projectExists
  source_addon_exists = $sourceExists
  target_plugin_cfg_exists = $targetExists
  target_host_config_exists = $targetHostConfigExists
  plugin_enabled = $pluginEnabled
  active_editor_detected = $activeEditorDetected
  stale_editor = $staleEditor
  snapshot_exists = Test-Path -LiteralPath $snapshotPath
}

if (-not $projectExists) {
  $readiness = "wrong_project_root"
  $nextAction = "Use -ProjectRoot with the folder that contains project.godot."
} elseif (-not $sourceExists) {
  $readiness = "missing_source_addon"
  $nextAction = "Run from the bridge repo or pass -SourceAddon pointing at a packaged addons\godot_codex_bridge folder."
} elseif (-not $targetExists) {
  $readiness = "addon_not_installed"
  $nextAction = "Run this helper with -Apply to copy the addon, then enable it in Godot Project Settings -> Plugins."
} elseif ($pluginEnabled -eq $false) {
  $readiness = "addon_not_enabled"
  $nextAction = "Open Godot and enable Godot Codex Bridge in Project Settings -> Plugins."
} elseif (-not $targetHostConfigExists) {
  $readiness = "host_config_missing"
  $nextAction = "Run this helper with -Apply -Replace to refresh the addon and generate addons\godot_codex_bridge\host_config.json."
} elseif ($staleEditor) {
  $readiness = "stale_editor"
  $nextAction = "Bring the Godot editor online or reload the project so heartbeat resumes."
} elseif (-not $activeEditorDetected) {
  $readiness = "editor_not_active"
  $nextAction = "Open the project in Godot with the addon enabled."
} else {
  $readiness = "ready"
  $nextAction = "Bridge addon appears installed; use Refresh Context in the Codex Bridge dock."
}

$action = "dry_run"
$backupPath = $null
$rollbackPerformed = $false
if ($Apply) {
  if (-not $projectExists) {
    throw "Wrong project root, project.godot not found: $resolvedProjectRoot"
  }
  if (-not $sourceExists) {
    throw "Source addon is incomplete: $resolvedSourceAddon"
  }

  $resolvedTargetAddon = [System.IO.Path]::GetFullPath($targetAddon)
  $expectedAddonsRoot = [System.IO.Path]::GetFullPath((Join-Path $resolvedProjectRoot "addons"))
  if (-not $resolvedTargetAddon.StartsWith($expectedAddonsRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to install outside target project's addons folder: $resolvedTargetAddon"
  }
  Assert-NoReparsePoint $expectedAddonsRoot $resolvedProjectRoot
  Assert-NoReparsePoint $resolvedTargetAddon $expectedAddonsRoot
  Assert-NoReparseTree $resolvedSourceAddon

  if ((Test-Path -LiteralPath $targetAddon) -and -not $Replace) {
    throw "Addon already exists at $targetAddon. Re-run with -Replace only after reviewing this project-local mutation."
  }

  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $targetAddon) | Out-Null
  if (-not (Test-Path -LiteralPath $startScript)) {
    throw "Host start script not found: $startScript"
  }

  $installId = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss_fff") + "_" + [Guid]::NewGuid().ToString("N").Substring(0, 8)
  $stagingPath = Join-Path $expectedAddonsRoot (".godot_codex_bridge.install." + $installId)
  $backupRoot = Join-Path $resolvedProjectRoot ".godot\godot_codex_bridge\install_backups"
  Assert-NoReparsePoint $backupRoot $resolvedProjectRoot
  if (Test-Path -LiteralPath $targetAddon) {
    New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
    $backupPath = Join-Path $backupRoot ("godot_codex_bridge." + $installId)
  }

  $hostConfig = [ordered]@{
    protocol_version = "godot-codex-bridge/0.1"
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
    addon_version = Get-PluginCfgVersion $sourcePluginCfg
    product_root = $productRootPath
    host_root = $hostRoot
    start_script = $startScript
    node_entry = $nodeEntry
    port = $HostPort
    runtime = $HostRuntime
    launch_mode = "local_hidden_process"
  }

  $targetExistedBefore = Test-Path -LiteralPath $targetAddon
  $originalMovedToBackup = $false
  $stagedAddonActivated = $false
  try {
    Copy-Item -LiteralPath $resolvedSourceAddon -Destination $stagingPath -Recurse -Force
    $stagingPluginCfg = Join-Path $stagingPath "plugin.cfg"
    $stagingPluginGd = Join-Path $stagingPath "plugin.gd"
    $stagingHostConfig = Join-Path $stagingPath "host_config.json"
    if (-not (Test-Path -LiteralPath $stagingPluginCfg) -or -not (Test-Path -LiteralPath $stagingPluginGd)) {
      throw "Staged addon is incomplete: $stagingPath"
    }
    Write-Utf8NoBom $stagingHostConfig ($hostConfig | ConvertTo-Json -Depth 8)

    if (Test-Path -LiteralPath $targetAddon) {
      Move-Item -LiteralPath $targetAddon -Destination $backupPath
      $originalMovedToBackup = $true
      if ($SimulateFailureAfterBackupForTest) {
        throw "Simulated addon install failure after backup move."
      }
    }
    Move-Item -LiteralPath $stagingPath -Destination $targetAddon
    $stagedAddonActivated = $true
  } catch {
    $installError = $_
    if (
      (Test-Path -LiteralPath $targetAddon) -and
      ($originalMovedToBackup -or -not $targetExistedBefore)
    ) {
      Remove-Item -LiteralPath $targetAddon -Recurse -Force
    }
    if (
      $originalMovedToBackup -and
      $backupPath -ne $null -and
      (Test-Path -LiteralPath $backupPath)
    ) {
      Move-Item -LiteralPath $backupPath -Destination $targetAddon
      $rollbackPerformed = $true
    }
    if (Test-Path -LiteralPath $stagingPath) {
      Remove-Item -LiteralPath $stagingPath -Recurse -Force
    }
    throw $installError
  }

  $action = if ($Replace) { "replaced" } else { "installed" }
  $targetExists = Test-Path -LiteralPath $targetPluginCfg
  $targetHostConfigExists = Test-Path -LiteralPath $targetHostConfig
  $checks.target_plugin_cfg_exists = $targetExists
  $checks.target_host_config_exists = $targetHostConfigExists

  if ($pluginEnabled -eq $false) {
    $readiness = "addon_not_enabled"
    $nextAction = "Open Godot and enable Godot Codex Bridge in Project Settings -> Plugins."
  } elseif ($staleEditor) {
    $readiness = "stale_editor"
    $nextAction = "Bring the Godot editor online or reload the project so heartbeat resumes."
  } elseif (-not $activeEditorDetected) {
    $readiness = "editor_not_active"
    $nextAction = "Open the project in Godot with the addon enabled, then press Connect in Codex Chat."
  } else {
    $readiness = "ready"
    $nextAction = "Bridge addon appears installed; press Connect in the Codex Chat dock."
  }
}

[ordered]@{
  status = "ok"
  action = $action
  readiness = $readiness
  recommended_next_action = $nextAction
  project_root = $resolvedProjectRoot
  source_addon_path = $resolvedSourceAddon
  target_addon_path = $targetAddon
  target_host_config_path = $targetHostConfig
  source_addon_version = Get-PluginCfgVersion $sourcePluginCfg
  target_addon_version = Get-PluginCfgVersion $targetPluginCfg
  change_preview = $changePreview
  backup_path = $backupPath
  rollback_performed = $rollbackPerformed
  host_port = $HostPort
  host_runtime = $HostRuntime
  bridge_dir = $bridgeDir
  last_heartbeat_age_ms = $heartbeatAgeMs
  snapshot_age_ms = $snapshotAgeMs
  checks = $checks
  apply_required_for_copy = -not $Apply
} | ConvertTo-Json -Depth 8
