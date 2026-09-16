param(
  [ValidateSet("app-server", "mock")]
  [string] $Runtime = "app-server"
)

$ErrorActionPreference = "Stop"

$productRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$hostRoot = Join-Path $productRoot "codex_host"

Push-Location $hostRoot
try {
  $env:GODOT_CODEX_HOST_RUNTIME = $Runtime
  npm run doctor -- --json
} finally {
  Pop-Location
}
