param(
  [Parameter(Mandatory = $true)]
  [string] $ProjectRoot,

  [Parameter(Mandatory = $true)]
  [string[]] $AssetPath,

  [string] $BatchName = "",

  [switch] $Apply,
  [switch] $Replace
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$AllowedExtensions = @(".glb", ".gltf", ".obj", ".fbx", ".dae", ".blend", ".tscn", ".scn", ".res", ".tres", ".png")
$MaxAssets = 50
$ImportRootRes = "res://assets/ai_imports/blender"
$ReservedDeviceNames = @("CON", "PRN", "AUX", "NUL", "CLOCK$", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9")

function Resolve-FullPath([string] $PathValue, [string] $BasePath) {
  if ([System.IO.Path]::IsPathRooted($PathValue)) {
    return [System.IO.Path]::GetFullPath($PathValue)
  }
  return [System.IO.Path]::GetFullPath((Join-Path $BasePath $PathValue))
}

function Write-Utf8NoBom([string] $PathValue, [string] $Text) {
  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($PathValue, $Text, $encoding)
}

function New-BatchName() {
  return "blender_" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
}

function Assert-BatchName([string] $Value) {
  if ($Value -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$') {
    throw "BatchName must match ^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$"
  }
}

function Convert-ToNodeName([string] $FileNameWithoutExtension) {
  $safe = [regex]::Replace($FileNameWithoutExtension, '[^A-Za-z0-9_ -]', "_").Trim()
  if ($safe -eq "" -or $safe -notmatch '^[A-Za-z_]') {
    $safe = "Asset_$safe"
  }
  if ($safe.Length -gt 80) {
    $safe = $safe.Substring(0, 80)
  }
  return $safe
}

function Get-RelativeResourcePath([string] $ProjectRootPath, [string] $AbsolutePath) {
  $relative = (Get-RelativePathCompat $ProjectRootPath $AbsolutePath).Replace("\", "/")
  if ($relative -eq ".." -or $relative.StartsWith("../") -or [System.IO.Path]::IsPathRooted($relative)) {
    throw "Target path resolved outside project root: $AbsolutePath"
  }
  return "res://$relative"
}

function Get-RelativePathCompat([string] $RootPath, [string] $CandidatePath) {
  $rootFull = [System.IO.Path]::GetFullPath($RootPath)
  $candidateFull = [System.IO.Path]::GetFullPath($CandidatePath)
  if (-not $rootFull.EndsWith([System.IO.Path]::DirectorySeparatorChar.ToString())) {
    $rootFull = $rootFull + [System.IO.Path]::DirectorySeparatorChar
  }
  $rootUri = [System.Uri]::new($rootFull)
  $candidateUri = [System.Uri]::new($candidateFull)
  if ($rootUri.Scheme -ne $candidateUri.Scheme) {
    return $candidateFull
  }
  return [System.Uri]::UnescapeDataString($rootUri.MakeRelativeUri($candidateUri).ToString()).Replace("/", "\")
}

function Assert-PathInside([string] $RootPath, [string] $CandidatePath, [string] $Message) {
  $rootFull = [System.IO.Path]::GetFullPath($RootPath)
  $candidateFull = [System.IO.Path]::GetFullPath($CandidatePath)
  $relative = Get-RelativePathCompat $rootFull $candidateFull
  if ($relative -eq ".." -or $relative.StartsWith("..$([System.IO.Path]::DirectorySeparatorChar)") -or [System.IO.Path]::IsPathRooted($relative)) {
    throw "$Message $candidateFull"
  }
}

function Test-PathHasGeneratedSegment([string] $PathValue) {
  $segments = $PathValue.Replace("/", "\").Split([char[]]@("\"), [System.StringSplitOptions]::RemoveEmptyEntries)
  foreach ($segment in $segments) {
    if ($segment -eq ".godot" -or $segment -eq ".import") {
      return $true
    }
  }
  return $false
}

function Assert-SafeLeafFileName([string] $FileName) {
  if ($FileName -eq "" -or $FileName -match '[\\/:*?"<>|]' -or $FileName.IndexOfAny([char[]](0..31)) -ge 0) {
    throw "Invalid source asset filename: $FileName"
  }
  $baseName = [System.IO.Path]::GetFileNameWithoutExtension($FileName).TrimEnd(".").ToUpperInvariant()
  if ($ReservedDeviceNames.Contains($baseName)) {
    throw "Reserved Windows device filename is not allowed: $FileName"
  }
}

$productRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$resolvedProjectRoot = Resolve-FullPath $ProjectRoot (Get-Location).Path
$projectFile = Join-Path $resolvedProjectRoot "project.godot"
if (-not (Test-Path -LiteralPath $projectFile)) {
  throw "Godot project.godot not found under ProjectRoot: $resolvedProjectRoot"
}

if ($AssetPath.Count -lt 1) {
  throw "At least one -AssetPath is required."
}
if ($AssetPath.Count -gt $MaxAssets) {
  throw "At most $MaxAssets assets can be staged in one Blender import batch."
}

$resolvedBatchName = if ($BatchName -eq "") { New-BatchName } else { $BatchName }
Assert-BatchName $resolvedBatchName

$targetBatchDir = Join-Path $resolvedProjectRoot (Join-Path "assets\ai_imports\blender" $resolvedBatchName)
$targetBatchDirFull = [System.IO.Path]::GetFullPath($targetBatchDir)
$allowedRootFull = [System.IO.Path]::GetFullPath((Join-Path $resolvedProjectRoot "assets\ai_imports\blender"))
Assert-PathInside $allowedRootFull $targetBatchDirFull "Refusing to stage outside assets\ai_imports\blender:"

$manifestPath = Join-Path $targetBatchDirFull "manifest.json"
$seenTargets = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$plannedAssets = New-Object System.Collections.Generic.List[object]

foreach ($inputPath in $AssetPath) {
  $resolvedSource = Resolve-FullPath $inputPath (Get-Location).Path
  if (-not (Test-Path -LiteralPath $resolvedSource -PathType Leaf)) {
    throw "Asset source file not found: $resolvedSource"
  }
  if (Test-PathHasGeneratedSegment $resolvedSource) {
    throw "Generated Godot cache/import source paths are not allowed: $resolvedSource"
  }
  $sourceItem = Get-Item -LiteralPath $resolvedSource
  if (($sourceItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "Reparse point or symlink source assets are not allowed: $resolvedSource"
  }
  $extension = [System.IO.Path]::GetExtension($resolvedSource).ToLowerInvariant()
  if (-not $AllowedExtensions.Contains($extension)) {
    throw "Unsupported asset extension '$extension' for: $resolvedSource"
  }
  $fileName = [System.IO.Path]::GetFileName($resolvedSource)
  Assert-SafeLeafFileName $fileName
  $targetPath = [System.IO.Path]::GetFullPath((Join-Path $targetBatchDirFull $fileName))
  Assert-PathInside $targetBatchDirFull $targetPath "Refusing to stage outside batch directory:"
  if (-not $seenTargets.Add($targetPath)) {
    throw "Two source assets resolve to the same target filename: $fileName"
  }
  $targetExistsBefore = Test-Path -LiteralPath $targetPath
  if ($Apply -and $targetExistsBefore -and -not $Replace) {
    throw "Target asset already exists: $targetPath. Re-run with -Replace after reviewing the overwrite."
  }

  $resPath = Get-RelativeResourcePath $resolvedProjectRoot $targetPath
  $plannedAssets.Add([ordered]@{
    source_path = $resolvedSource
    target_path = $targetPath
    asset_path = $resPath
    name = Convert-ToNodeName ([System.IO.Path]::GetFileNameWithoutExtension($fileName))
    extension = $extension
    will_copy = [bool]$Apply
    target_exists = $targetExistsBefore
    target_exists_before = $targetExistsBefore
    target_exists_after = $targetExistsBefore
    copy_status = "dry_run_not_copied"
    post_copy_import_status = [ordered]@{
      status = "not_run"
      reason = "dry_run_no_files_copied"
      source = "stage_blender_import.ps1"
      next_tool = "godot.inspect_imported_assets"
    }
  }) | Out-Null
}

if ($Apply -and (Test-Path -LiteralPath $manifestPath) -and -not $Replace) {
  throw "Manifest already exists: $manifestPath. Re-run with -Replace after reviewing the overwrite."
}

$manifestAssets = @($plannedAssets.ToArray() | ForEach-Object {
  [ordered]@{
    asset_path = $_.asset_path
    name = $_.name
  }
})
$manifest = [ordered]@{
  manifest_version = "godot-codex-bridge/blender-import-manifest-v1"
  generated_at = (Get-Date).ToUniversalTime().ToString("o")
  source = "godot-codex-bridge-stage-helper"
  assets = $manifestAssets
}

$action = "dry_run"
if ($Apply) {
  New-Item -ItemType Directory -Force -Path $targetBatchDirFull | Out-Null
  foreach ($asset in $plannedAssets) {
    Copy-Item -LiteralPath ([string]$asset.source_path) -Destination ([string]$asset.target_path) -Force:$Replace
    $asset["target_exists_after"] = Test-Path -LiteralPath ([string]$asset.target_path)
    $asset["copy_status"] = if ($Replace -and [bool]$asset.target_exists_before) { "replaced" } else { "copied" }
    $asset["post_copy_import_status"] = [ordered]@{
      status = "pending_godot_import_scan"
      reason = "file_copied_to_project_import_allowlist"
      source = "filesystem_copy"
      next_tool = "godot.inspect_imported_assets"
      root_path = $ImportRootRes
      asset_path = [string]$asset.asset_path
      target_exists = [bool]$asset.target_exists_after
    }
  }
  Write-Utf8NoBom $manifestPath ($manifest | ConvertTo-Json -Depth 8)
  $action = if ($Replace) { "replaced" } else { "staged" }
}

$postCopySummary = [ordered]@{
  status = if ($Apply) { "pending_godot_import_scan" } else { "not_run" }
  source = if ($Apply) { "filesystem_copy" } else { "stage_blender_import.ps1" }
  reason = if ($Apply) { "files_copied_manifest_written_godot_import_status_requires_editor_scan" } else { "dry_run_no_files_copied" }
  next_tool = "godot.inspect_imported_assets"
  root_path = $ImportRootRes
}

[ordered]@{
  status = "ok"
  action = $action
  project_root = $resolvedProjectRoot
  batch_name = $resolvedBatchName
  import_root = $ImportRootRes
  batch_root = "$ImportRootRes/$resolvedBatchName"
  batch_path = $targetBatchDirFull
  manifest_path = $manifestPath
  manifest_res_path = "$ImportRootRes/$resolvedBatchName/manifest.json"
  asset_count = $plannedAssets.Count
  assets = @($plannedAssets.ToArray())
  manifest = $manifest
  post_copy_import_status = $postCopySummary
  apply_required_for_copy = -not $Apply
} | ConvertTo-Json -Depth 12
