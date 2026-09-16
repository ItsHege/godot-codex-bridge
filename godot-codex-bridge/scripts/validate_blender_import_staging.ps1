$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Invoke-StageHelper(
  [string] $ProjectRoot,
  [string[]] $AssetPaths,
  [string] $BatchName,
  [switch] $Apply,
  [switch] $Replace
) {
  $output = if ($Apply -and $Replace) {
    & $script:StageScript -ProjectRoot $ProjectRoot -AssetPath $AssetPaths -BatchName $BatchName -Apply -Replace
  } elseif ($Apply) {
    & $script:StageScript -ProjectRoot $ProjectRoot -AssetPath $AssetPaths -BatchName $BatchName -Apply
  } elseif ($Replace) {
    & $script:StageScript -ProjectRoot $ProjectRoot -AssetPath $AssetPaths -BatchName $BatchName -Replace
  } else {
    & $script:StageScript -ProjectRoot $ProjectRoot -AssetPath $AssetPaths -BatchName $BatchName
  }
  return $output | ConvertFrom-Json
}

function Assert-True([bool] $Condition, [string] $Message) {
  if (-not $Condition) {
    throw $Message
  }
}

function Assert-ThrowsContaining([scriptblock] $ScriptBlock, [string] $Needle, [string] $Message) {
  $matched = $false
  try {
    & $ScriptBlock
  } catch {
    $matched = ([string]$_.Exception.Message).Contains($Needle)
  }
  Assert-True $matched $Message
}

function Assert-ManifestSchema([string] $ManifestPath, [string] $SchemaPath) {
  $manifestJson = Get-Content -Raw -LiteralPath $ManifestPath
  $schemaJson = Get-Content -Raw -LiteralPath $SchemaPath
  $null = $manifestJson | ConvertFrom-Json
  if (Get-Command Test-Json -ErrorAction SilentlyContinue) {
    if (-not (Test-Json -Json $manifestJson -Schema $schemaJson)) {
      throw "Blender import manifest failed schema validation: $ManifestPath"
    }
  } else {
    $manifest = $manifestJson | ConvertFrom-Json
    Assert-True ($manifest.manifest_version -eq "godot-codex-bridge/blender-import-manifest-v1") "Manifest version mismatch."
    Assert-True ($manifest.assets.Count -le 50) "Manifest asset cap exceeded."
  }
}

function Assert-McpPlannerAcceptsManifest([string] $ProjectRoot, [string] $ManifestResPath) {
  Push-Location $script:ProductRoot
  try {
    & npm --prefix mcp_server run build | Out-Host
    if ($LASTEXITCODE -ne 0) {
      throw "MCP build failed before planner smoke."
    }
    $nodeSmoke = @"
import path from "node:path";
import { pathToFileURL } from "node:url";

const projectRoot = process.argv[2];
const manifestPath = process.argv[3];
const productRoot = process.argv[4];
const { createToolHandlers } = await import(pathToFileURL(path.join(productRoot, "mcp_server", "dist", "src", "tools.js")).href);
const handlers = createToolHandlers({
  projectRoot,
  bridgeDir: path.join(projectRoot, ".godot", "godot_codex_bridge"),
  godotExecutable: process.execPath,
  addonRequestTimeoutMs: 250,
  runSceneTimeoutMs: 1000,
});
const result = await handlers["godot.plan_blender_asset_import"]({ manifestPath });
if (result.isError || result.structuredContent?.status !== "ok") {
  console.error(JSON.stringify(result.structuredContent, null, 2));
  process.exit(1);
}
if (result.structuredContent.accepted_count !== result.structuredContent.placeable_count) {
  console.error(JSON.stringify(result.structuredContent, null, 2));
  process.exit(2);
}
console.log(JSON.stringify({
  status: "ok",
  accepted_count: result.structuredContent.accepted_count,
  placeable_count: result.structuredContent.placeable_count,
}));
"@
    $nodePath = Join-Path ([System.IO.Path]::GetTempPath()) ("gcb-blender-planner-{0}.mjs" -f ([Guid]::NewGuid().ToString("N")))
    try {
      Set-Content -LiteralPath $nodePath -Value $nodeSmoke -Encoding utf8
      node $nodePath $ProjectRoot $ManifestResPath $script:ProductRoot | Out-Host
      if ($LASTEXITCODE -ne 0) {
        throw "MCP planner did not accept staged manifest."
      }
    } finally {
      Remove-Item -LiteralPath $nodePath -Force -ErrorAction SilentlyContinue
    }
  } finally {
    Pop-Location
  }
}

$productRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$script:ProductRoot = [string]$productRoot
$script:StageScript = Join-Path $productRoot "scripts\stage_blender_import.ps1"
$schemaPath = Join-Path $productRoot "contracts\schemas\blender-import-manifest.schema.json"
if (-not (Test-Path -LiteralPath $script:StageScript)) {
  throw "Stage helper not found: $script:StageScript"
}
if (-not (Test-Path -LiteralPath $schemaPath)) {
  throw "Manifest schema not found: $schemaPath"
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gcb-blender-stage-" + [guid]::NewGuid().ToString("N"))
$projectRoot = Join-Path $tempRoot "project"
$sourceRoot = Join-Path $tempRoot "source"
$sourceRoot2 = Join-Path $tempRoot "source2"
New-Item -ItemType Directory -Force -Path $projectRoot, $sourceRoot, $sourceRoot2 | Out-Null
Set-Content -LiteralPath (Join-Path $projectRoot "project.godot") -Value "[application]`nconfig/name=`"Blender Stage Test`"`n" -Encoding UTF8
Set-Content -LiteralPath (Join-Path $sourceRoot "tree.glb") -Value "glTF fixture" -Encoding UTF8
Set-Content -LiteralPath (Join-Path $sourceRoot "rock.obj") -Value "o Rock`nv 0 0 0`n" -Encoding UTF8
Set-Content -LiteralPath (Join-Path $sourceRoot "note.txt") -Value "not an asset" -Encoding UTF8
Set-Content -LiteralPath (Join-Path $sourceRoot2 "tree.glb") -Value "duplicate target" -Encoding UTF8
New-Item -ItemType Directory -Force -Path (Join-Path $sourceRoot ".godot") | Out-Null
Set-Content -LiteralPath (Join-Path $sourceRoot ".godot\cached.glb") -Value "cached" -Encoding UTF8

$steps = New-Object System.Collections.Generic.List[object]
$status = "failed"
try {
  $forbiddenCommandPattern = 'Start-Process|Invoke-Expression|\biex\b|cmd\s*/|cmd\.exe|blender\.exe|godot.*\.exe|\bnpm\s'
  $forbidden = Select-String -LiteralPath $script:StageScript -Pattern $forbiddenCommandPattern -CaseSensitive:$false
  Assert-True ($null -eq $forbidden) "Stage helper must not contain command execution patterns."
  $steps.Add([ordered]@{ name = "static_no_command_execution"; status = "ok" }) | Out-Null

  $dryRun = Invoke-StageHelper -ProjectRoot $projectRoot -AssetPaths @(
    (Join-Path $sourceRoot "tree.glb"),
    (Join-Path $sourceRoot "rock.obj")
  ) -BatchName "test_batch"
  Assert-True ($dryRun.action -eq "dry_run") "Dry-run should not apply copies."
  Assert-True ($dryRun.apply_required_for_copy -eq $true) "Dry-run should report apply_required_for_copy."
  Assert-True ($dryRun.post_copy_import_status.status -eq "not_run") "Dry-run import status should be not_run."
  Assert-True (-not (Test-Path -LiteralPath (Join-Path $projectRoot "assets\ai_imports\blender\test_batch"))) "Dry-run must not create target folder."
  $steps.Add([ordered]@{ name = "dry_run"; status = "ok" }) | Out-Null

  $applied = Invoke-StageHelper -ProjectRoot $projectRoot -AssetPaths @(
    (Join-Path $sourceRoot "tree.glb"),
    (Join-Path $sourceRoot "rock.obj")
  ) -BatchName "test_batch" -Apply
  Assert-True ($applied.action -eq "staged") "Apply should stage files."
  Assert-True ($applied.manifest_res_path -eq "res://assets/ai_imports/blender/test_batch/manifest.json") "Manifest res path mismatch."
  Assert-True ($applied.post_copy_import_status.status -eq "pending_godot_import_scan") "Apply should report pending import scan."
  Assert-True ($applied.post_copy_import_status.next_tool -eq "godot.inspect_imported_assets") "Apply should point to inspect_imported_assets."
  Assert-True ($applied.assets[0].target_exists_after -eq $true) "Applied asset should exist after copy."
  Assert-True ($applied.assets[0].post_copy_import_status.status -eq "pending_godot_import_scan") "Applied asset import status should be pending scan."
  $targetTree = Join-Path $projectRoot "assets\ai_imports\blender\test_batch\tree.glb"
  $manifestPath = Join-Path $projectRoot "assets\ai_imports\blender\test_batch\manifest.json"
  Assert-True (Test-Path -LiteralPath $targetTree) "tree.glb was not copied."
  Assert-True (Test-Path -LiteralPath $manifestPath) "manifest.json was not written."
  $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
  Assert-True ($manifest.manifest_version -eq "godot-codex-bridge/blender-import-manifest-v1") "Manifest version mismatch."
  Assert-True ($manifest.assets.Count -eq 2) "Manifest should list two assets."
  Assert-True ($manifest.assets[0].asset_path -eq "res://assets/ai_imports/blender/test_batch/tree.glb") "First asset path mismatch."
  Assert-ManifestSchema $manifestPath $schemaPath
  Assert-McpPlannerAcceptsManifest $projectRoot "res://assets/ai_imports/blender/test_batch/manifest.json"
  $steps.Add([ordered]@{ name = "apply"; status = "ok" }) | Out-Null

  Assert-ThrowsContaining {
    Invoke-StageHelper -ProjectRoot $projectRoot -AssetPaths @((Join-Path $sourceRoot "tree.glb")) -BatchName "test_batch" -Apply | Out-Null
  } "already exists" "Apply without -Replace should block existing targets."
  $steps.Add([ordered]@{ name = "no_overwrite_without_replace"; status = "ok" }) | Out-Null

  Set-Content -LiteralPath (Join-Path $sourceRoot "tree.glb") -Value "updated fixture" -Encoding UTF8
  $replaced = Invoke-StageHelper -ProjectRoot $projectRoot -AssetPaths @((Join-Path $sourceRoot "tree.glb")) -BatchName "test_batch" -Apply -Replace
  Assert-True ($replaced.action -eq "replaced") "Replace should report replaced."
  Assert-True ((Get-Content -Raw -LiteralPath $targetTree).Contains("updated fixture")) "Replace should overwrite only listed target asset."
  Assert-True (Test-Path -LiteralPath (Join-Path $projectRoot "assets\ai_imports\blender\test_batch\rock.obj")) "Replace must not remove unlisted existing batch files."
  $steps.Add([ordered]@{ name = "replace_only_listed"; status = "ok" }) | Out-Null

  Assert-ThrowsContaining {
    Invoke-StageHelper -ProjectRoot $projectRoot -AssetPaths @((Join-Path $sourceRoot "note.txt")) -BatchName "bad_batch" | Out-Null
  } "Unsupported asset extension" "Unsupported extension should be rejected."
  $steps.Add([ordered]@{ name = "unsupported_extension"; status = "ok" }) | Out-Null

  Assert-ThrowsContaining {
    Invoke-StageHelper -ProjectRoot $projectRoot -AssetPaths @($sourceRoot) -BatchName "directory_batch" | Out-Null
  } "not found" "Directory source input should be rejected."
  $steps.Add([ordered]@{ name = "directory_input_rejected"; status = "ok" }) | Out-Null

  Assert-ThrowsContaining {
    Invoke-StageHelper -ProjectRoot $projectRoot -AssetPaths @((Join-Path $sourceRoot "tree.glb")) -BatchName ".." | Out-Null
  } "BatchName must match" "Unsafe batch name should be rejected."
  $steps.Add([ordered]@{ name = "unsafe_batch_rejected"; status = "ok" }) | Out-Null

  Assert-ThrowsContaining {
    Invoke-StageHelper -ProjectRoot $projectRoot -AssetPaths @(
      (Join-Path $sourceRoot "tree.glb"),
      (Join-Path $sourceRoot2 "tree.glb")
    ) -BatchName "duplicate_batch" | Out-Null
  } "same target filename" "Duplicate target filenames should be rejected."
  $steps.Add([ordered]@{ name = "duplicate_target_rejected"; status = "ok" }) | Out-Null

  Assert-ThrowsContaining {
    Invoke-StageHelper -ProjectRoot $projectRoot -AssetPaths @((Join-Path $sourceRoot ".godot\cached.glb")) -BatchName "cache_batch" | Out-Null
  } "Generated Godot cache" ".godot source paths should be rejected."
  $steps.Add([ordered]@{ name = "generated_source_rejected"; status = "ok" }) | Out-Null

  $manyRoot = Join-Path $tempRoot "many"
  New-Item -ItemType Directory -Force -Path $manyRoot | Out-Null
  $manyAssets = New-Object System.Collections.Generic.List[string]
  for ($i = 0; $i -lt 51; $i++) {
    $asset = Join-Path $manyRoot ("asset_$i.glb")
    Set-Content -LiteralPath $asset -Value "many $i" -Encoding UTF8
    $manyAssets.Add($asset) | Out-Null
  }
  Assert-ThrowsContaining {
    Invoke-StageHelper -ProjectRoot $projectRoot -AssetPaths @($manyAssets.ToArray()) -BatchName "many_batch" | Out-Null
  } "At most 50 assets" "51 assets should be rejected."
  $steps.Add([ordered]@{ name = "max_asset_cap"; status = "ok" }) | Out-Null

  $status = "ok"
} finally {
  if (Test-Path -LiteralPath $tempRoot) {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
  }
}

[ordered]@{
  status = $status
  script = $script:StageScript
  steps = @($steps.ToArray())
} | ConvertTo-Json -Depth 8
