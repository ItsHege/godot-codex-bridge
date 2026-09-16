$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Invoke-StageHelper(
  [string] $ProjectRoot,
  [string[]] $AssetPaths,
  [string] $BatchName,
  [switch] $Apply
) {
  $output = if ($Apply) {
    & $script:StageScript -ProjectRoot $ProjectRoot -AssetPath $AssetPaths -BatchName $BatchName -Apply
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

function Assert-ManifestSchema([string] $ManifestPath, [string] $SchemaPath) {
  $manifestJson = Get-Content -Raw -LiteralPath $ManifestPath
  $schemaJson = Get-Content -Raw -LiteralPath $SchemaPath
  $null = $manifestJson | ConvertFrom-Json
  if (Get-Command Test-Json -ErrorAction SilentlyContinue) {
    if (-not (Test-Json -Json $manifestJson -Schema $schemaJson)) {
      throw "Blender handoff manifest failed schema validation: $ManifestPath"
    }
  }
}

function Invoke-PlannerSmoke([string] $ProjectRoot, [string] $ManifestResPath) {
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
const content = result.structuredContent;
const workflow = content.suggested_workflow ?? [];
if (content.accepted_count !== 1 || content.placeable_count !== 1 || content.rejected_count !== 1) {
  console.error(JSON.stringify(content, null, 2));
  process.exit(2);
}
if (workflow[0]?.tool !== "godot.inspect_imported_assets") {
  console.error(JSON.stringify(workflow, null, 2));
  process.exit(3);
}
if (workflow.some((step) => step.tool === "godot.editor_batch" || step.tool === "godot.save_scene")) {
  console.error(JSON.stringify(workflow, null, 2));
  process.exit(4);
}
const placementAssets = workflow.slice(1).map((step) => step.args?.assetPath);
if (!placementAssets.includes("res://assets/ai_imports/blender/mcp_smoke/tree.glb") ||
    placementAssets.includes("res://assets/ai_imports/blender/mcp_smoke/tree_preview.png")) {
  console.error(JSON.stringify(workflow, null, 2));
  process.exit(5);
}
if (!content.rejected_assets?.some((asset) => asset.code === "unsupported_blender_asset_extension" &&
    asset.asset_path === "res://assets/ai_imports/blender/mcp_smoke/tree_preview.png")) {
  console.error(JSON.stringify(content.rejected_assets, null, 2));
  process.exit(6);
}
console.log(JSON.stringify({
  status: "ok",
  accepted_count: content.accepted_count,
  placeable_count: content.placeable_count,
  first_tool: workflow[0].tool,
  placement_assets: placementAssets,
}));
"@
  $nodePath = Join-Path ([System.IO.Path]::GetTempPath()) ("gcb-blender-handoff-{0}.mjs" -f ([Guid]::NewGuid().ToString("N")))
  try {
    Set-Content -LiteralPath $nodePath -Value $nodeSmoke -Encoding utf8
    node $nodePath $ProjectRoot $ManifestResPath $script:ProductRoot | Out-Host
    if ($LASTEXITCODE -ne 0) {
      throw "MCP planner did not accept Blender MCP handoff manifest."
    }
  } finally {
    Remove-Item -LiteralPath $nodePath -Force -ErrorAction SilentlyContinue
  }
}

$productRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$script:ProductRoot = [string]$productRoot
$script:StageScript = Join-Path $productRoot "scripts\stage_blender_import.ps1"
$schemaPath = Join-Path $productRoot "contracts\schemas\blender-import-manifest.schema.json"

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("gcb-blender-handoff-" + [guid]::NewGuid().ToString("N"))
$projectRoot = Join-Path $tempRoot "project"
$exportRoot = Join-Path $tempRoot "blender_export"
New-Item -ItemType Directory -Force -Path $projectRoot, $exportRoot | Out-Null
Set-Content -LiteralPath (Join-Path $projectRoot "project.godot") -Value "[application]`nconfig/name=`"Blender MCP Handoff Smoke`"`n" -Encoding UTF8
Set-Content -LiteralPath (Join-Path $exportRoot "tree.glb") -Value "fake glb from Blender MCP smoke" -Encoding UTF8
Set-Content -LiteralPath (Join-Path $exportRoot "tree_preview.png") -Value "fake png from Blender MCP smoke" -Encoding UTF8

$steps = New-Object System.Collections.Generic.List[object]
$status = "failed"
try {
  $handoff = [ordered]@{
    source = "blender-mcp-export"
    batch_name = "mcp_smoke"
    placeable_assets = @(
      [ordered]@{ source_path = (Join-Path $exportRoot "tree.glb"); role = "scene_asset"; name = "Tree" }
    )
    sidecar_files = @(
      [ordered]@{ source_path = (Join-Path $exportRoot "tree_preview.png"); role = "texture_sidecar"; name = "TreePreview" }
    )
    real_blender_control = "not_used"
  }
  Assert-True ($handoff.placeable_assets.Count -eq 1) "Expected one placeable GLB asset in handoff summary."
  Assert-True ($handoff.sidecar_files.Count -eq 1) "Expected one PNG sidecar in handoff summary."
  Assert-True ([System.IO.Path]::GetExtension($handoff.placeable_assets[0].source_path).ToLowerInvariant() -eq ".glb") "Placeable asset must be the GLB."
  Assert-True ([System.IO.Path]::GetExtension($handoff.sidecar_files[0].source_path).ToLowerInvariant() -eq ".png") "Sidecar must be the PNG."
  $steps.Add([ordered]@{ name = "fake_blender_mcp_handoff_glb_png_sidecar"; status = "ok" }) | Out-Null

  Push-Location $productRoot
  try {
    & npm --prefix mcp_server run build | Out-Host
    if ($LASTEXITCODE -ne 0) {
      throw "MCP build failed before Blender handoff smoke."
    }

    $assetPaths = @(
      (Join-Path $exportRoot "tree.glb"),
      (Join-Path $exportRoot "tree_preview.png")
    )
    $dryRun = Invoke-StageHelper -ProjectRoot $projectRoot -AssetPaths $assetPaths -BatchName "mcp_smoke"
    Assert-True ($dryRun.action -eq "dry_run") "Dry-run should not copy Blender MCP handoff files."
    Assert-True ($dryRun.apply_required_for_copy -eq $true) "Dry-run should require -Apply."
    Assert-True ($dryRun.post_copy_import_status.status -eq "not_run") "Dry-run import status should be not_run."
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $projectRoot "assets\ai_imports\blender\mcp_smoke"))) "Dry-run must not create the staged batch."
    $steps.Add([ordered]@{ name = "dry_run_no_copy"; status = "ok" }) | Out-Null

    $applied = Invoke-StageHelper -ProjectRoot $projectRoot -AssetPaths $assetPaths -BatchName "mcp_smoke" -Apply
    Assert-True ($applied.action -eq "staged") "Apply should stage Blender MCP handoff files."
    Assert-True ($applied.asset_count -eq 2) "Apply should stage GLB and PNG assets."
    Assert-True ($applied.post_copy_import_status.status -eq "pending_godot_import_scan") "Apply should report pending Godot import scan."
    $manifestPath = Join-Path $projectRoot "assets\ai_imports\blender\mcp_smoke\manifest.json"
    Assert-True (Test-Path -LiteralPath (Join-Path $projectRoot "assets\ai_imports\blender\mcp_smoke\tree.glb")) "GLB was not staged."
    Assert-True (Test-Path -LiteralPath (Join-Path $projectRoot "assets\ai_imports\blender\mcp_smoke\tree_preview.png")) "PNG was not staged."
    Assert-True (Test-Path -LiteralPath $manifestPath) "Manifest was not staged."
    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    Assert-True ($manifest.assets.Count -eq 2) "Manifest should list GLB and PNG."
    $glbMatches = @($manifest.assets | Where-Object { $_.asset_path -eq "res://assets/ai_imports/blender/mcp_smoke/tree.glb" })
    $pngMatches = @($manifest.assets | Where-Object { $_.asset_path -eq "res://assets/ai_imports/blender/mcp_smoke/tree_preview.png" })
    Assert-True ($glbMatches.Count -eq 1) "Manifest missing GLB asset."
    Assert-True ($pngMatches.Count -eq 1) "Manifest missing PNG asset."
    Assert-ManifestSchema $manifestPath $schemaPath
    $steps.Add([ordered]@{ name = "apply_manifest_glb_png"; status = "ok"; manifest_res_path = $applied.manifest_res_path }) | Out-Null

    Invoke-PlannerSmoke $projectRoot "res://assets/ai_imports/blender/mcp_smoke/manifest.json"
    $steps.Add([ordered]@{ name = "mcp_planner_accepts_glb_rejects_png_sidecar"; status = "ok" }) | Out-Null
  } finally {
    Pop-Location
  }

  $status = "ok"
} finally {
  if (Test-Path -LiteralPath $tempRoot) {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
  }
}

[ordered]@{
  status = $status
  script = $MyInvocation.MyCommand.Path
  real_blender_control = "not_used"
  project_scope = "temporary_local_fixture"
  steps = @($steps.ToArray())
} | ConvertTo-Json -Depth 8
