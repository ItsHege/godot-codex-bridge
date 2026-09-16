#!/usr/bin/env pwsh
# Links the example project's addon folder to the canonical dev addon via a
# directory junction, so there is ONE real copy of the addon.
#
# Why: examples/minimal_3d_project is the project we open in Godot to validate
# the addon. Godot can only load an addon that lives under the project's
# addons/ folder. Instead of keeping a second physical copy (which drifts and
# must be hand-synced before every test), we junction it to the dev addon.
#
# Junctions need no admin rights and Godot follows them transparently.
# Re-running this script is safe (idempotent): it recreates the link.
#
# Usage:  pwsh godot-codex-bridge/scripts/link-example-addon.ps1

$ErrorActionPreference = "Stop"

# Repo-relative paths resolved from this script's location (scripts/ -> repo root).
$repoRoot = Split-Path -Parent $PSScriptRoot
$target = Join-Path $repoRoot "addons\godot_codex_bridge"
$link = Join-Path $repoRoot "examples\minimal_3d_project\addons\godot_codex_bridge"

if (-not (Test-Path $target)) {
    throw "Dev addon not found at: $target"
}

# Remove whatever is there (stale copy or old link), then create the junction.
if (Test-Path $link) {
    Remove-Item -Recurse -Force $link
}

$linkParent = Split-Path -Parent $link
if (-not (Test-Path $linkParent)) {
    New-Item -ItemType Directory -Force -Path $linkParent | Out-Null
}

New-Item -ItemType Junction -Path $link -Target $target | Out-Null

$item = Get-Item $link -Force
Write-Host "Linked example addon -> dev addon"
Write-Host "  link:   $link"
Write-Host "  target: $($item.Target)"
Write-Host "  type:   $($item.LinkType)"
