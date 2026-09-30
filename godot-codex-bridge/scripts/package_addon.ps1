param(
  [string] $OutputRoot = "dist\addon_package",
  [switch] $NoZip,
  [switch] $ReplaceExistingPackage
)

$ErrorActionPreference = "Stop"

$productRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$sourceAddon = Join-Path $productRoot "addons\godot_codex_bridge"
$pluginCfg = Join-Path $sourceAddon "plugin.cfg"
$pluginGd = Join-Path $sourceAddon "plugin.gd"

if (-not (Test-Path -LiteralPath $pluginCfg)) {
  throw "Canonical addon plugin.cfg not found: $pluginCfg"
}
if (-not (Test-Path -LiteralPath $pluginGd)) {
  throw "Canonical addon plugin.gd not found: $pluginGd"
}

$pluginCfgText = Get-Content -Raw -LiteralPath $pluginCfg
$versionMatch = [regex]::Match($pluginCfgText, '(?m)^version="([^"]+)"')
$version = if ($versionMatch.Success) { $versionMatch.Groups[1].Value } else { "0.0.0" }
if ($version -notmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$') {
  throw "Addon version must be a directory-safe semantic version: $version"
}

$resolvedOutputRoot = if ([System.IO.Path]::IsPathRooted($OutputRoot)) {
  $OutputRoot
} else {
  Join-Path $productRoot $OutputRoot
}

$packageRoot = Join-Path $resolvedOutputRoot "godot-codex-bridge-addon-$version"
$packageAddon = Join-Path $packageRoot "addons\godot_codex_bridge"
$validationReportsSource = Join-Path $productRoot "..\outputs"
$validationReportsPackage = Join-Path $packageRoot "validation_reports"
$expectedOutputRoot = [System.IO.Path]::GetFullPath($resolvedOutputRoot)
$resolvedPackageRoot = [System.IO.Path]::GetFullPath($packageRoot)

if (-not ([System.IO.Path]::GetDirectoryName($resolvedPackageRoot) -ieq $expectedOutputRoot)) {
  throw "Refusing to package outside output root: $resolvedPackageRoot"
}

function Assert-NoReparseAncestor([string] $PathValue, [string] $BoundaryPath) {
  $boundary = [System.IO.Path]::GetFullPath($BoundaryPath).TrimEnd('\')
  $current = [System.IO.Path]::GetFullPath($PathValue).TrimEnd('\')
  while ($current.StartsWith($boundary, [System.StringComparison]::OrdinalIgnoreCase)) {
    if (Test-Path -LiteralPath $current) {
      $item = Get-Item -LiteralPath $current -Force
      if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Refusing to package through reparse point: $current"
      }
    }
    if ($current -ieq $boundary) { break }
    $parent = Split-Path -Parent $current
    if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current) { break }
    $current = $parent
  }
}

$trustedOutputBoundary = if ([System.IO.Path]::IsPathRooted($OutputRoot)) {
  [System.IO.Path]::GetPathRoot($expectedOutputRoot)
} else {
  $productRoot.Path
}
Assert-NoReparseAncestor $expectedOutputRoot $trustedOutputBoundary
New-Item -ItemType Directory -Force -Path $expectedOutputRoot | Out-Null
Assert-NoReparseAncestor $expectedOutputRoot $trustedOutputBoundary
Assert-NoReparseAncestor $resolvedPackageRoot $expectedOutputRoot

if (Test-Path -LiteralPath $packageRoot) {
  if (-not $ReplaceExistingPackage) {
    throw "Package already exists at $resolvedPackageRoot. Re-run with -ReplaceExistingPackage after reviewing that exact path."
  }
  Assert-NoReparseAncestor $resolvedPackageRoot $trustedOutputBoundary
  Remove-Item -LiteralPath $packageRoot -Recurse -Force
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $packageAddon) | Out-Null
Assert-NoReparseAncestor $resolvedPackageRoot $trustedOutputBoundary
Copy-Item -LiteralPath $sourceAddon -Destination (Split-Path -Parent $packageAddon) -Recurse -Force

$validationReports = @()
if (Test-Path -LiteralPath $validationReportsSource) {
  New-Item -ItemType Directory -Force -Path $validationReportsPackage | Out-Null
  $validationReports = Get-ChildItem -LiteralPath $validationReportsSource -File -Filter "*.md" |
    Sort-Object Name |
    ForEach-Object {
      $destination = Join-Path $validationReportsPackage $_.Name
      Copy-Item -LiteralPath $_.FullName -Destination $destination -Force
      [ordered]@{
        name = $_.Name
        package_path = "validation_reports\$($_.Name)"
      }
    }
}

$manifest = [ordered]@{
  package_name = "godot-codex-bridge-addon"
  addon_name = "godot_codex_bridge"
  addon_version = $version
  source_addon_path = (Resolve-Path -LiteralPath $sourceAddon).Path
  package_addon_path = $packageAddon
  validation_reports_path = if ($validationReports.Count -gt 0) { $validationReportsPackage } else { $null }
  validation_reports = $validationReports
  created_at = (Get-Date).ToUniversalTime().ToString("o")
  install_path_inside_godot_project = "addons\godot_codex_bridge"
}

$manifestPath = Join-Path $packageRoot "package_manifest.json"
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding utf8

$zipPath = $null
if (-not $NoZip) {
  $zipPath = Join-Path $resolvedOutputRoot "godot-codex-bridge-addon-$version.zip"
  if (Test-Path -LiteralPath $zipPath) {
    if (-not $ReplaceExistingPackage) {
      throw "Package archive already exists at $zipPath. Re-run with -ReplaceExistingPackage after reviewing that exact path."
    }
    Assert-NoReparseAncestor $zipPath $trustedOutputBoundary
    Remove-Item -LiteralPath $zipPath -Force
  }
  Assert-NoReparseAncestor $resolvedPackageRoot $trustedOutputBoundary
  Compress-Archive -LiteralPath (Join-Path $packageRoot "addons") -DestinationPath $zipPath -Force
}

[ordered]@{
  status = "ok"
  addon_version = $version
  package_root = $packageRoot
  package_addon_path = $packageAddon
  manifest_path = $manifestPath
  validation_reports_path = if ($validationReports.Count -gt 0) { $validationReportsPackage } else { $null }
  validation_report_count = $validationReports.Count
  zip_path = $zipPath
} | ConvertTo-Json -Depth 8
