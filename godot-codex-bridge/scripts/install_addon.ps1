param(
  [Parameter(Mandatory = $true)]
  [string] $ProjectRoot,

  [string] $SourceAddon = "",

  [string] $ChannelManifest = "",

  [string] $ExpectedProjectFileSha256 = "",

  [switch] $Apply,
  [switch] $Replace,
  [switch] $EnablePlugin,
  [switch] $SimulateFailureAfterBackupForTest,
  [switch] $SimulateFailureAfterProjectEditForTest,
  [switch] $SimulateProjectFileChangeBeforeWriteForTest,

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

function Read-JsonHashtable([string] $PathValue) {
  if ([string]::IsNullOrWhiteSpace($PathValue) -or -not (Test-Path -LiteralPath $PathValue)) {
    return @{}
  }
  $parsed = Get-Content -Raw -LiteralPath $PathValue | ConvertFrom-Json
  $result = @{}
  foreach ($property in $parsed.PSObject.Properties) {
    $result[$property.Name] = $property.Value
  }
  return $result
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

function Get-AddonFileMap([string] $Root, [string[]] $ExcludedRelativePaths = @()) {
  $map = @{}
  if (-not (Test-Path -LiteralPath $Root)) {
    return $map
  }
  $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd("\")
  foreach ($file in (Get-ChildItem -LiteralPath $rootFull -Recurse -File)) {
    $relative = $file.FullName.Substring($rootFull.Length).TrimStart("\")
    if ($relative.EndsWith(".uid", [System.StringComparison]::OrdinalIgnoreCase)) {
      continue
    }
    if ($ExcludedRelativePaths -icontains $relative) {
      continue
    }
    $map[$relative] = $file.FullName
  }
  return $map
}

function Get-AddonChangePreview([string] $SourceRoot, [string] $TargetRoot) {
  $generatedFiles = @("host_config.json", "install_manifest.json")
  $sourceMap = Get-AddonFileMap $SourceRoot $generatedFiles
  $targetMap = Get-AddonFileMap $TargetRoot $generatedFiles
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

function Assert-NoReparseAncestors([string] $PathValue) {
  $current = [System.IO.Path]::GetFullPath($PathValue)
  while (-not [string]::IsNullOrWhiteSpace($current)) {
    if (Test-Path -LiteralPath $current) {
      $item = Get-Item -LiteralPath $current -Force
      if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing addon install through reparse point: $current"
      }
    }
    $parent = Split-Path -Parent $current
    if ($parent -eq $current -or [string]::IsNullOrWhiteSpace($parent)) { break }
    $current = $parent
  }
}

function Get-ProjectTextWithPluginEnabled([string] $ProjectText) {
  $pluginPath = "res://addons/godot_codex_bridge/plugin.cfg"
  $newline = if ($ProjectText.Contains("`r`n")) { "`r`n" } else { "`n" }
  $sectionPattern = '(?m)^\[editor_plugins\][ \t]*\r?$'
  $sections = [regex]::Matches($ProjectText, $sectionPattern)
  if ($sections.Count -gt 1) {
    throw "Cannot enable plugin automatically: project.godot has multiple editor_plugins sections."
  }
  if ($sections.Count -eq 0) {
    return $ProjectText.TrimEnd("`r", "`n") + $newline + $newline + "[editor_plugins]" + $newline + 'enabled=PackedStringArray("' + $pluginPath + '")' + $newline
  }

  $start = $sections[0].Index + $sections[0].Length
  $nextSection = [regex]::Match($ProjectText.Substring($start), '(?m)^\[[^\]\r\n]+\][ \t]*\r?$')
  $end = if ($nextSection.Success) { $start + $nextSection.Index } else { $ProjectText.Length }
  $body = $ProjectText.Substring($start, $end - $start)
  $enabledMatches = [regex]::Matches($body, '(?m)^[ \t]*enabled[ \t]*=[ \t]*(.*)$')
  if ($enabledMatches.Count -gt 1) {
    throw "Cannot enable plugin automatically: editor_plugins has multiple enabled entries."
  }
  if ($enabledMatches.Count -eq 0) {
    $prefix = if ($end -gt 0 -and $ProjectText[$end - 1] -ne "`n") { $newline } else { "" }
    return $ProjectText.Insert($end, $prefix + 'enabled=PackedStringArray("' + $pluginPath + '")' + $newline + $newline)
  }

  $value = $enabledMatches[0].Groups[1].Value.Trim()
  $arrayMatch = [regex]::Match($value, '^PackedStringArray\((.*)\)[ \t]*$')
  if (-not $arrayMatch.Success) {
    throw "Cannot enable plugin automatically: unsupported editor_plugins.enabled format. Enable it in Godot instead."
  }
  $items = $arrayMatch.Groups[1].Value.Trim()
  if ($items -ne '' -and -not [regex]::IsMatch($items, '^"[^"\r\n]*"(?:[ \t]*,[ \t]*"[^"\r\n]*")*$')) {
    throw "Cannot enable plugin automatically: editor_plugins.enabled contains unsupported values. Enable it in Godot instead."
  }
  if ([regex]::IsMatch($items, '(^|[ \t]*,[ \t]*)"' + [regex]::Escape($pluginPath) + '"($|[ \t]*,)')) {
    return $ProjectText
  }
  $replacement = if ($items -eq '') { 'enabled=PackedStringArray("' + $pluginPath + '")' } else { 'enabled=PackedStringArray(' + $items + ', "' + $pluginPath + '")' }
  $match = $enabledMatches[0]
  return $ProjectText.Substring(0, $start + $match.Index) + $replacement + $ProjectText.Substring($start + $match.Index + $match.Length)
}

function Get-EnabledEntry([string] $ProjectText) {
  $section = [regex]::Match($ProjectText, '(?ms)^\[editor_plugins\][ \t]*\r?\n(.*?)(?=^\[[^\]\r\n]+\]|\z)')
  if (-not $section.Success) { return $null }
  $entry = [regex]::Match($section.Groups[1].Value, '(?m)^[ \t]*enabled[ \t]*=.*$')
  if (-not $entry.Success) { return $null }
  return $entry.Value.TrimEnd("`r")
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
$resolvedChannelManifest = if ($ChannelManifest -ne "") {
  Resolve-FullPath $ChannelManifest (Get-Location).Path
} else {
  ""
}
$channelManifestData = Read-JsonHashtable $resolvedChannelManifest
if ($resolvedChannelManifest -ne "" -and $channelManifestData.Count -eq 0) {
  throw "GC-work channel manifest is missing or invalid: $resolvedChannelManifest"
}

$projectFile = Join-Path $resolvedProjectRoot "project.godot"
$targetAddon = Join-Path $resolvedProjectRoot "addons\godot_codex_bridge"
$targetPluginCfg = Join-Path $targetAddon "plugin.cfg"
$targetHostConfig = Join-Path $targetAddon "host_config.json"
$targetInstallManifest = Join-Path $targetAddon "install_manifest.json"
$sourcePluginCfg = Join-Path $resolvedSourceAddon "plugin.cfg"
$sourcePluginGd = Join-Path $resolvedSourceAddon "plugin.gd"
$bridgeDir = Join-Path $resolvedProjectRoot ".godot\godot_codex_bridge"
$heartbeatPath = Join-Path $bridgeDir "heartbeat.json"
$snapshotPath = Join-Path $bridgeDir "context_snapshot.json"

Assert-NoReparseAncestors $resolvedProjectRoot
if (Test-Path -LiteralPath $resolvedProjectRoot) {
  Assert-NoReparsePoint $resolvedProjectRoot $resolvedProjectRoot
  Assert-NoReparsePoint $targetAddon $resolvedProjectRoot
  if (Test-Path -LiteralPath $targetAddon) { Assert-NoReparseTree $targetAddon }
}
if (Test-Path -LiteralPath $resolvedSourceAddon) { Assert-NoReparseTree $resolvedSourceAddon }
if ($EnablePlugin -and (Test-Path -LiteralPath $projectFile)) {
  Assert-NoReparsePoint $projectFile $resolvedProjectRoot
}

$projectExists = Test-Path -LiteralPath $projectFile
$sourceExists = (Test-Path -LiteralPath $sourcePluginCfg) -and (Test-Path -LiteralPath $sourcePluginGd)
$targetExists = Test-Path -LiteralPath $targetPluginCfg
$targetHostConfigExists = Test-Path -LiteralPath $targetHostConfig
$projectText = if ($projectExists) { Get-Content -Raw -LiteralPath $projectFile } else { "" }
$projectFileSha256 = if ($projectExists) { Get-Sha256Hex $projectFile } else { $null }
if ($ExpectedProjectFileSha256 -ne "") {
  if (-not [regex]::IsMatch($ExpectedProjectFileSha256, '^[0-9a-fA-F]{64}$')) {
    throw "ExpectedProjectFileSha256 must be a 64-character SHA-256 hex value."
  }
  if ($projectFileSha256 -ne $ExpectedProjectFileSha256.ToUpperInvariant()) {
    throw "project.godot changed since the reviewed preview; run the dry-run again."
  }
}
$previousEnabledEntry = if ($projectExists) { Get-EnabledEntry $projectText } else { $null }
$pluginEnabled = if ($projectExists) {
  $previousEnabledEntry -ne $null -and $previousEnabledEntry.Contains('"res://addons/godot_codex_bridge/plugin.cfg"')
} else { $null }
$enabledProjectText = $null
$projectFileChangePreview = [ordered]@{
  requested = [bool]$EnablePlugin
  action = "none"
  path = $projectFile
  sha256 = $projectFileSha256
  previous_enabled_entry = $previousEnabledEntry
  proposed_enabled_entry = $null
}
if ($EnablePlugin -and $projectExists -and -not $pluginEnabled) {
  $enabledProjectText = Get-ProjectTextWithPluginEnabled $projectText
  $projectFileChangePreview.action = "enable_plugin"
  $projectFileChangePreview.proposed_enabled_entry = Get-EnabledEntry $enabledProjectText
}
$heartbeatAgeMs = Get-FileAgeMs $heartbeatPath
$snapshotAgeMs = Get-FileAgeMs $snapshotPath
$activeEditorDetected = ($heartbeatAgeMs -ne $null -and $heartbeatAgeMs -le 5000)
$staleEditor = ($heartbeatAgeMs -ne $null -and $heartbeatAgeMs -gt 5000)
$changePreview = if ($sourceExists) { Get-AddonChangePreview $resolvedSourceAddon $targetAddon } else { $null }
$generatedFilePreview = [ordered]@{
  host_config = $(if (Test-Path -LiteralPath $targetHostConfig) { "replace" } else { "add" })
  install_manifest = $(if ($channelManifestData.Count -gt 0) {
    if (Test-Path -LiteralPath $targetInstallManifest) { "replace" } else { "add" }
  } elseif (Test-Path -LiteralPath $targetInstallManifest) { "remove_stale_channel_manifest" } else { "none" })
}
$targetInstallData = Read-JsonHashtable $targetInstallManifest
$sourceChannel = if ($channelManifestData.Count -gt 0) { [string]$channelManifestData["channel"] } else { "stable" }
$sourceBuildId = if ($channelManifestData.Count -gt 0) { [string]$channelManifestData["build_id"] } else { "" }
$targetChannel = if ($targetInstallData.Count -gt 0) { [string]$targetInstallData["channel"] } else { "unmanaged" }
$targetBuildId = if ($targetInstallData.Count -gt 0) { [string]$targetInstallData["build_id"] } else { "" }
$updateAvailable = $sourceBuildId -ne "" -and $sourceBuildId -ne $targetBuildId

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
  $nextAction = if ($EnablePlugin) { "Run this helper with -Apply -EnablePlugin to copy and enable the addon." } else { "Run this helper with -Apply to copy the addon, then enable it in Godot Project Settings -> Plugins." }
} elseif ($pluginEnabled -eq $false) {
  $readiness = "addon_not_enabled"
  $nextAction = if ($EnablePlugin) { "Run this helper with -Apply -Replace -EnablePlugin after reviewing the addon diff." } else { "Open Godot and enable Godot Codex Bridge in Project Settings -> Plugins." }
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
  if ($EnablePlugin -and $activeEditorDetected) {
    throw "Close the Godot editor before changing project.godot to enable the plugin."
  }
  if ($EnablePlugin) {
    Assert-NoReparsePoint $projectFile $resolvedProjectRoot
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
    launch_mode = "manual_trusted_install"
    distribution = [ordered]@{
      channel = $sourceChannel
      build_id = $sourceBuildId
      channel_manifest_path = $resolvedChannelManifest
    }
  }

  $installManifest = $null
  if ($channelManifestData.Count -gt 0) {
    $installManifest = [ordered]@{}
    foreach ($key in $channelManifestData.Keys) {
      $installManifest[$key] = $channelManifestData[$key]
    }
    $installManifest["installed_at"] = (Get-Date).ToUniversalTime().ToString("o")
    $installManifest["source_addon_path"] = $resolvedSourceAddon
    $installManifest["channel_manifest_path"] = $resolvedChannelManifest
    $installManifest["project_root"] = $resolvedProjectRoot
  }

  $targetExistedBefore = Test-Path -LiteralPath $targetAddon
  $originalMovedToBackup = $false
  $stagedAddonActivated = $false
  $projectBackupPath = $null
  $projectFileChanged = $false
  $stagedProjectFile = $null
  try {
    Copy-Item -LiteralPath $resolvedSourceAddon -Destination $stagingPath -Recurse -Force
    if (Test-Path -LiteralPath $targetAddon) {
      $targetRootFull = [System.IO.Path]::GetFullPath($targetAddon).TrimEnd("\")
      foreach ($uidFile in (Get-ChildItem -LiteralPath $targetRootFull -Recurse -File -Filter "*.uid")) {
        $uidRelative = $uidFile.FullName.Substring($targetRootFull.Length).TrimStart("\")
        $stagedUidPath = Join-Path $stagingPath $uidRelative
        if (-not (Test-Path -LiteralPath $stagedUidPath)) {
          New-Item -ItemType Directory -Force -Path (Split-Path -Parent $stagedUidPath) | Out-Null
          Copy-Item -LiteralPath $uidFile.FullName -Destination $stagedUidPath -Force
        }
      }
    }
    $stagingPluginCfg = Join-Path $stagingPath "plugin.cfg"
    $stagingPluginGd = Join-Path $stagingPath "plugin.gd"
    $stagingHostConfig = Join-Path $stagingPath "host_config.json"
    $stagingInstallManifest = Join-Path $stagingPath "install_manifest.json"
    if (-not (Test-Path -LiteralPath $stagingPluginCfg) -or -not (Test-Path -LiteralPath $stagingPluginGd)) {
      throw "Staged addon is incomplete: $stagingPath"
    }
    Write-Utf8NoBom $stagingHostConfig ($hostConfig | ConvertTo-Json -Depth 8)
    if ($installManifest -ne $null) {
      Write-Utf8NoBom $stagingInstallManifest ($installManifest | ConvertTo-Json -Depth 8)
    }

    if (Test-Path -LiteralPath $targetAddon) {
      Move-Item -LiteralPath $targetAddon -Destination $backupPath
      $originalMovedToBackup = $true
      if ($SimulateFailureAfterBackupForTest) {
        throw "Simulated addon install failure after backup move."
      }
    }
    Move-Item -LiteralPath $stagingPath -Destination $targetAddon
    $stagedAddonActivated = $true
    if ($enabledProjectText -ne $null -and $enabledProjectText -ne $projectText) {
      if ($SimulateProjectFileChangeBeforeWriteForTest) {
        [System.IO.File]::AppendAllText($projectFile, "`n; simulated concurrent edit`n")
      }
      Assert-NoReparseAncestors $resolvedProjectRoot
      Assert-NoReparsePoint $projectFile $resolvedProjectRoot
      if ((Get-Sha256Hex $projectFile) -ne $projectFileSha256) {
        throw "project.godot changed during addon installation; run the dry-run again."
      }
      New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
      $projectBackupPath = Join-Path $backupRoot ("project.godot." + $installId)
      Copy-Item -LiteralPath $projectFile -Destination $projectBackupPath
      if ((Get-Sha256Hex $projectBackupPath) -ne $projectFileSha256 -or (Get-Sha256Hex $projectFile) -ne $projectFileSha256) {
        throw "project.godot changed during addon installation; run the dry-run again."
      }
      $stagedProjectFile = Join-Path $resolvedProjectRoot (".project.godot.install." + $installId)
      Write-Utf8NoBom $stagedProjectFile $enabledProjectText
      if ((Get-Sha256Hex $projectFile) -ne $projectFileSha256) {
        throw "project.godot changed during addon installation; run the dry-run again."
      }
      Move-Item -LiteralPath $stagedProjectFile -Destination $projectFile -Force
      $projectFileChanged = $true
      if ($SimulateFailureAfterProjectEditForTest) {
        throw "Simulated addon install failure after project.godot edit."
      }
    }
  } catch {
    $installError = $_
    if ($projectFileChanged -and $projectBackupPath -ne $null -and (Test-Path -LiteralPath $projectBackupPath)) {
      Copy-Item -LiteralPath $projectBackupPath -Destination $projectFile -Force
      $projectFileChanged = $false
    }
    if ($stagedProjectFile -ne $null -and (Test-Path -LiteralPath $stagedProjectFile)) {
      Remove-Item -LiteralPath $stagedProjectFile -Force
    }
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
  $targetInstallData = Read-JsonHashtable $targetInstallManifest
  $targetChannel = if ($targetInstallData.Count -gt 0) { [string]$targetInstallData["channel"] } else { "unmanaged" }
  $targetBuildId = if ($targetInstallData.Count -gt 0) { [string]$targetInstallData["build_id"] } else { "" }
  $updateAvailable = $sourceBuildId -ne "" -and $sourceBuildId -ne $targetBuildId
  $checks.target_plugin_cfg_exists = $targetExists
  $checks.target_host_config_exists = $targetHostConfigExists
  if ($projectFileChanged) {
    $pluginEnabled = $true
    $checks.plugin_enabled = $true
    $projectFileChangePreview.action = "enabled_plugin"
  }

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
  source_channel = $sourceChannel
  source_build_id = $sourceBuildId
  target_channel = $targetChannel
  target_build_id = $targetBuildId
  update_available = $updateAvailable
  target_install_manifest_path = $targetInstallManifest
  change_preview = $changePreview
  generated_file_preview = $generatedFilePreview
  project_file_change_preview = $projectFileChangePreview
  backup_path = $backupPath
  project_file_backup_path = $projectBackupPath
  rollback_performed = $rollbackPerformed
  host_port = $HostPort
  host_runtime = $HostRuntime
  bridge_dir = $bridgeDir
  last_heartbeat_age_ms = $heartbeatAgeMs
  snapshot_age_ms = $snapshotAgeMs
  checks = $checks
  apply_required_for_copy = -not $Apply
} | ConvertTo-Json -Depth 8
