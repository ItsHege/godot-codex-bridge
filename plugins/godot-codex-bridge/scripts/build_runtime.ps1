param()
$ErrorActionPreference = 'Stop'
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$source = Join-Path $workspace 'godot-codex-bridge\mcp_server\src\index.ts'
$builder = Join-Path $workspace 'godot-codex-bridge\mcp_server\node_modules\.bin\esbuild.cmd'
$output = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\runtime\mcp.mjs'))
if (-not [IO.File]::Exists($source)) { throw "MCP source missing: $source" }
if (-not [IO.File]::Exists($builder)) { throw 'Existing mcp_server development dependencies are required to rebuild the bundle.' }
& $builder $source '--bundle' '--platform=node' '--format=esm' '--target=node22' "--outfile=$output"
if ($LASTEXITCODE -ne 0) { throw "MCP bundle build failed with exit code $LASTEXITCODE" }
Get-FileHash -LiteralPath $output -Algorithm SHA256 | Select-Object Path,Hash
