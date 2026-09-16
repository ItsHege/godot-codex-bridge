param(
  [Parameter(Mandatory = $true)]
  [string] $ProjectRoot,

  [string] $SchemaPath = ""
)

$ErrorActionPreference = "Stop"

$productRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
if ($SchemaPath -eq "") {
  $SchemaPath = Join-Path $productRoot "contracts\schemas\context-snapshot.schema.json"
} elseif (-not [System.IO.Path]::IsPathRooted($SchemaPath)) {
  $SchemaPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $SchemaPath))
}

$snapshotPath = Join-Path $ProjectRoot ".godot\godot_codex_bridge\context_snapshot.json"
if (-not (Test-Path -LiteralPath $snapshotPath)) {
  throw "Context snapshot not found: $snapshotPath"
}

$snapshotJson = Get-Content -Raw -LiteralPath $snapshotPath
$schemaJson = Get-Content -Raw -LiteralPath $SchemaPath

$null = $snapshotJson | ConvertFrom-Json

if (Get-Command Test-Json -ErrorAction SilentlyContinue) {
  if (-not (Test-Json -Json $snapshotJson -Schema $schemaJson)) {
    throw "Context snapshot failed schema validation: $snapshotPath"
  }
} else {
  $ajvRoot = Join-Path $productRoot "mcp_server\node_modules"
  $nodeValidator = @"
const fs = require('fs');
const path = require('path');
const Ajv2020 = require(path.join(process.argv[4], 'ajv/dist/2020')).default;
const addFormats = require(path.join(process.argv[4], 'ajv-formats'));

const snapshotPath = process.argv[2];
const schemaPath = process.argv[3];
const schema = JSON.parse(fs.readFileSync(schemaPath, 'utf8'));
const snapshot = JSON.parse(fs.readFileSync(snapshotPath, 'utf8'));
const ajv = new Ajv2020({ allErrors: true, strict: false });
addFormats(ajv);
const validate = ajv.compile(schema);
if (!validate(snapshot)) {
  console.error(JSON.stringify(validate.errors, null, 2));
  process.exit(1);
}
"@
  $validatorPath = Join-Path ([System.IO.Path]::GetTempPath()) ("gcb-context-validator-{0}.cjs" -f ([Guid]::NewGuid().ToString("N")))
  try {
    Set-Content -LiteralPath $validatorPath -Value $nodeValidator -Encoding utf8
    node $validatorPath $snapshotPath $SchemaPath $ajvRoot
    if ($LASTEXITCODE -ne 0) {
      throw "Context snapshot failed schema validation: $snapshotPath"
    }
  } finally {
    Remove-Item -LiteralPath $validatorPath -Force -ErrorAction SilentlyContinue
  }
}

Write-Output "Context snapshot schema validation passed: $snapshotPath"
