$ErrorActionPreference = "Stop"

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gcb-package-security-" + [Guid]::NewGuid().ToString("N"))
$product = Join-Path $tempRoot "product"
$output = Join-Path $tempRoot "output"
$sentinel = Join-Path $tempRoot "sentinel.txt"

try {
  New-Item -ItemType Directory -Force -Path (Join-Path $product "scripts") | Out-Null
  New-Item -ItemType Directory -Force -Path (Join-Path $product "addons") | Out-Null
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot "package_addon.ps1") -Destination (Join-Path $product "scripts\package_addon.ps1")
  Copy-Item -LiteralPath (Join-Path $PSScriptRoot "..\addons\godot_codex_bridge") -Destination (Join-Path $product "addons") -Recurse
  Set-Content -LiteralPath $sentinel -Value "preserve" -NoNewline

  $pluginCfg = Join-Path $product "addons\godot_codex_bridge\plugin.cfg"
  $cfg = Get-Content -Raw -LiteralPath $pluginCfg
  $cfg = [regex]::Replace($cfg, '(?m)^version="[^"]+"', 'version="..\..\sentinel"')
  Set-Content -LiteralPath $pluginCfg -Value $cfg -NoNewline

  $failedClosed = $false
  try {
    & (Join-Path $product "scripts\package_addon.ps1") -OutputRoot $output -NoZip | Out-Null
  } catch {
    $failedClosed = $_.Exception.Message -like "*directory-safe semantic version*"
  }
  if (-not $failedClosed) {
    throw "Malicious package version did not fail closed."
  }
  if ((Get-Content -Raw -LiteralPath $sentinel) -ne "preserve") {
    throw "Sentinel changed during rejected package attempt."
  }

  $cfg = [regex]::Replace($cfg, '(?m)^version="[^"]+"', 'version="0.1.0"')
  Set-Content -LiteralPath $pluginCfg -Value $cfg -NoNewline
  $junctionTarget = Join-Path $tempRoot "junction-target"
  $junctionPath = Join-Path $tempRoot "output-link"
  New-Item -ItemType Directory -Force -Path $junctionTarget | Out-Null
  New-Item -ItemType Junction -Path $junctionPath -Target $junctionTarget | Out-Null
  $reparseFailedClosed = $false
  try {
    & (Join-Path $product "scripts\package_addon.ps1") -OutputRoot (Join-Path $junctionPath "packages") -NoZip | Out-Null
  } catch {
    $reparseFailedClosed = $_.Exception.Message -like "*reparse point*"
  }
  if (-not $reparseFailedClosed) {
    throw "Reparse-point package output did not fail closed."
  }

  [ordered]@{
    status = "passed"
    traversal_version_rejected = $true
    reparse_output_rejected = $true
    sentinel_preserved = $true
  } | ConvertTo-Json
} finally {
  if (Test-Path -LiteralPath $tempRoot) {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
  }
}
