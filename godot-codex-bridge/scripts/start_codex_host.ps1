param(
  [int] $Port = 49390,
  [ValidateSet("app-server", "mock")]
  [string] $Runtime = "app-server"
)

$ErrorActionPreference = "Stop"

$productRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$hostRoot = Join-Path $productRoot "codex_host"

if (-not (Test-Path -LiteralPath (Join-Path $hostRoot "package.json"))) {
  throw "codex_host package not found: $hostRoot"
}

Push-Location $hostRoot
try {
  npm run build | Write-Output
  $env:GODOT_CODEX_HOST_PORT = [string]$Port
  $env:GODOT_CODEX_HOST_RUNTIME = $Runtime
  node dist/src/index.js --port $Port --runtime $Runtime
} finally {
  Pop-Location
}
