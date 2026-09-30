param(
  [ValidateSet("Status", "Publish", "Update")]
  [string] $Action = "Status",

  [string[]] $ProjectRoot = @()
)

$ErrorActionPreference = "Stop"

function Write-Utf8NoBom([string] $PathValue, [string] $Text) {
  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($PathValue, $Text, $encoding)
}

function Read-JsonHashtable([string] $PathValue) {
  if (-not (Test-Path -LiteralPath $PathValue)) {
    return @{}
  }
  return Convert-JsonTextToHashtable (Get-Content -Raw -LiteralPath $PathValue)
}

function Convert-JsonTextToHashtable([string] $Text) {
  $parsed = $Text | ConvertFrom-Json
  $result = @{}
  foreach ($property in $parsed.PSObject.Properties) {
    $result[$property.Name] = $property.Value
  }
  return $result
}

function Get-AddonDigest([string] $AddonRoot, [switch] $Legacy) {
  $root = [System.IO.Path]::GetFullPath($AddonRoot).TrimEnd("\")
  $files = Get-ChildItem -LiteralPath $root -Recurse -File
  # Legacy: culture-aware Sort-Object, which orders differently in Windows
  # PowerShell 5.1 and PowerShell 7. Kept only to recognise installs recorded
  # before ordinal ordering; never used for new builds.
  if ($Legacy) { $files = $files | Sort-Object FullName }
  $entries = New-Object System.Collections.Generic.List[string]
  foreach ($file in $files) {
    $relative = $file.FullName.Substring($root.Length).TrimStart("\").Replace("\", "/")
    if ($relative -in @("host_config.json", "install_manifest.json") -or $relative.EndsWith(".uid", [System.StringComparison]::OrdinalIgnoreCase)) {
      continue
    }
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash.ToLowerInvariant()
    $entries.Add("$relative`:$hash")
  }
  $ordered = $entries.ToArray()
  if (-not $Legacy) { [System.Array]::Sort($ordered, [System.StringComparer]::Ordinal) }
  $payload = [System.Text.Encoding]::UTF8.GetBytes(($ordered -join "`n"))
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    return "sha256:" + ([System.BitConverter]::ToString($sha.ComputeHash($payload))).Replace("-", "").ToLowerInvariant()
  } finally {
    $sha.Dispose()
  }
}

function Resolve-ProjectRoots([string[]] $Requested, [string] $RegistryPath) {
  $roots = New-Object System.Collections.Generic.List[string]
  foreach ($requestedRoot in $Requested) {
    if ([string]::IsNullOrWhiteSpace($requestedRoot)) {
      continue
    }
    $roots.Add([System.IO.Path]::GetFullPath($requestedRoot))
  }
  if ($roots.Count -eq 0) {
    $registry = Read-JsonHashtable $RegistryPath
    foreach ($registeredRoot in @($registry["projects"])) {
      if (-not [string]::IsNullOrWhiteSpace([string]$registeredRoot)) {
        $roots.Add([System.IO.Path]::GetFullPath([string]$registeredRoot))
      }
    }
  }
  if ($roots.Count -eq 0) {
    $current = [System.IO.Path]::GetFullPath((Get-Location).Path)
    if (Test-Path -LiteralPath (Join-Path $current "project.godot")) {
      $roots.Add($current)
    }
  }
  return @($roots | Select-Object -Unique)
}

function Get-ProjectStatus([string] $Root, [hashtable] $Channel) {
  $projectFile = Join-Path $Root "project.godot"
  $installPath = Join-Path $Root "addons\godot_codex_bridge\install_manifest.json"
  $installedAddon = Join-Path $Root "addons\godot_codex_bridge"
  $installed = Read-JsonHashtable $installPath
  $installedBuild = if ($installed.Count -gt 0) { [string]$installed["build_id"] } else { "" }
  $installedChannel = if ($installed.Count -gt 0) { [string]$installed["channel"] } else { "unmanaged" }
  $availableBuild = if ($Channel.Count -gt 0) { [string]$Channel["build_id"] } else { "" }
  $actualBuild = if (Test-Path -LiteralPath $installedAddon) { Get-AddonDigest $installedAddon } else { "" }
  if ($installedBuild -ne "" -and $installedBuild -ne $actualBuild -and (Test-Path -LiteralPath $installedAddon)) {
    # An install recorded with the legacy ordering is still unmodified if the
    # legacy digest matches.
    $legacyBuild = Get-AddonDigest $installedAddon -Legacy
    if ($legacyBuild -eq $installedBuild) { $actualBuild = $installedBuild }
  }
  $state = if (-not (Test-Path -LiteralPath $projectFile)) {
    "wrong_project_root"
  } elseif ($installed.Count -eq 0) {
    "unmanaged"
  } elseif ($installedBuild -ne $actualBuild) {
    "drifted"
  } elseif ($installedChannel -ne "GC-work") {
    "different_channel"
  } elseif ($availableBuild -eq "") {
    "channel_unpublished"
  } elseif ($installedBuild -eq $availableBuild) {
    "current"
  } else {
    "update_available"
  }
  return [ordered]@{
    project_root = $Root
    state = $state
    installed_channel = $installedChannel
    installed_build_id = $installedBuild
    actual_build_id = $actualBuild
    available_build_id = $availableBuild
    install_manifest_path = $installPath
  }
}

function Save-Registry([string] $RegistryPath, [string[]] $Projects) {
  $parent = Split-Path -Parent $RegistryPath
  New-Item -ItemType Directory -Force -Path $parent | Out-Null
  $payload = [ordered]@{
    schema_version = "gc-work-registry/1"
    updated_at = (Get-Date).ToUniversalTime().ToString("o")
    projects = @($Projects | Sort-Object -Unique)
  }
  Write-Utf8NoBom $RegistryPath ($payload | ConvertTo-Json -Depth 6)
}

$productRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$workspaceRoot = (Resolve-Path -LiteralPath (Join-Path $productRoot "..")).Path
$sourceAddon = Join-Path $productRoot "addons\godot_codex_bridge"
$channelPath = Join-Path $productRoot "GC_WORK_CHANNEL.json"
$installScript = Join-Path $productRoot "scripts\install_addon.ps1"
$registryPath = Join-Path $env:LOCALAPPDATA "GodotCodexBridge\gc-work-projects.json"

if ($Action -eq "Publish") {
  $dirtyAddon = @(& git -C $workspaceRoot status --porcelain -- "godot-codex-bridge/addons/godot_codex_bridge")
  if ($LASTEXITCODE -ne 0) {
    throw "Could not inspect the GC-work source repository."
  }
  if ($dirtyAddon.Count -gt 0) {
    throw "GC-work source has uncommitted addon changes. Create a reviewed checkpoint before publishing."
  }
  $commit = (& git -C $workspaceRoot rev-parse HEAD).Trim()
  $branch = (& git -C $workspaceRoot branch --show-current).Trim()
  $pluginCfg = Get-Content -Raw -LiteralPath (Join-Path $sourceAddon "plugin.cfg")
  $versionMatch = [regex]::Match($pluginCfg, '(?m)^version="([^"]+)"')
  $version = if ($versionMatch.Success) { $versionMatch.Groups[1].Value } else { "unknown" }
  $channel = [ordered]@{
    schema_version = "gc-work-channel/1"
    channel = "GC-work"
    addon_version = $version
    build_id = Get-AddonDigest $sourceAddon
    source_commit = $commit
    source_branch = $branch
    published_at = (Get-Date).ToUniversalTime().ToString("o")
  }
  Write-Utf8NoBom $channelPath ($channel | ConvertTo-Json -Depth 6)
  $registeredRoots = Resolve-ProjectRoots @() $registryPath
  [ordered]@{
    status = "published"
    channel_manifest_path = $channelPath
    channel = $channel
    registered_projects = @($registeredRoots | ForEach-Object { Get-ProjectStatus $_ $channel })
  } | ConvertTo-Json -Depth 8
  exit 0
}

$channelData = Read-JsonHashtable $channelPath
$roots = Resolve-ProjectRoots $ProjectRoot $registryPath

if ($Action -eq "Status") {
  [ordered]@{
    status = "ok"
    channel_manifest_path = $channelPath
    channel_published = $channelData.Count -gt 0
    channel = $channelData
    source_build_id = Get-AddonDigest $sourceAddon
    registry_path = $registryPath
    projects = @($roots | ForEach-Object { Get-ProjectStatus $_ $channelData })
  } | ConvertTo-Json -Depth 8
  exit 0
}

if ($channelData.Count -eq 0) {
  throw "GC-work is not published yet. Run with -Action Publish after creating a reviewed checkpoint."
}
$sourceDigest = Get-AddonDigest $sourceAddon
if ($sourceDigest -ne [string]$channelData["build_id"]) {
  throw "Canonical addon source differs from the published GC-work build. Publish a reviewed checkpoint before updating projects."
}
if ($roots.Count -eq 0) {
  throw "No project is registered. Pass -ProjectRoot with the folder containing project.godot."
}

$registry = Read-JsonHashtable $registryPath
$registered = New-Object System.Collections.Generic.List[string]
foreach ($existing in @($registry["projects"])) {
  if (-not [string]::IsNullOrWhiteSpace([string]$existing)) {
    $registered.Add([System.IO.Path]::GetFullPath([string]$existing))
  }
}
$updates = New-Object System.Collections.Generic.List[object]
foreach ($root in $roots) {
  if (-not (Test-Path -LiteralPath (Join-Path $root "project.godot"))) {
    throw "Wrong project root, project.godot not found: $root"
  }
  $before = Get-ProjectStatus $root $channelData
  if ($before["state"] -eq "current") {
    $updates.Add([ordered]@{
      project_root = $root
      preview = [ordered]@{ added_count = 0; changed_count = 0; removed_count = 0 }
      action = "unchanged"
      backup_path = $null
      installed_build_id = $before["installed_build_id"]
      update_available = $false
    })
    $registered.Add($root)
    continue
  }
  $preview = Convert-JsonTextToHashtable (& $installScript -ProjectRoot $root -SourceAddon $sourceAddon -ChannelManifest $channelPath | Out-String)
  $previewChecks = $preview["checks"]
  if ([bool]$previewChecks.active_editor_detected) {
    throw "Refusing automatic GC-work update while the Godot editor is active: $root"
  }
  $previewChanges = $preview["change_preview"]
  if ([int]$previewChanges.removed_count -gt 0) {
    throw "Refusing automatic GC-work update because the preview would remove addon files: $root"
  }
  $result = Convert-JsonTextToHashtable (& $installScript -ProjectRoot $root -SourceAddon $sourceAddon -ChannelManifest $channelPath -Apply -Replace | Out-String)
  $updates.Add([ordered]@{
    project_root = $root
    preview = $previewChanges
    action = $result["action"]
    backup_path = $result["backup_path"]
    installed_build_id = $result["target_build_id"]
    update_available = $result["update_available"]
  })
  $registered.Add($root)
}
Save-Registry $registryPath @($registered | ForEach-Object { $_ })

[ordered]@{
  status = "updated"
  channel = $channelData
  registry_path = $registryPath
  updates = @($updates | ForEach-Object { $_ })
} | ConvertTo-Json -Depth 10
