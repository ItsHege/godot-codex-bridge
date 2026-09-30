param(
  [Parameter(Mandatory = $true)] [string] $ProjectRoot,
  [string] $BridgeSourceRoot = '',
  [switch] $Apply
)

$ErrorActionPreference = 'Stop'
$root = [System.IO.Path]::GetFullPath($ProjectRoot)
$projectFile = Join-Path $root 'project.godot'
if (-not [System.IO.File]::Exists($projectFile)) {
  throw "Not a Godot project: $root"
}

function Assert-NotReparse([string] $PathValue) {
  $item = Get-Item -LiteralPath $PathValue -Force
  if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "Reparse point is not allowed: $PathValue"
  }
}

$cursor = $root
while ($cursor -and [System.IO.Directory]::Exists($cursor)) {
  Assert-NotReparse $cursor
  $parent = [System.IO.Directory]::GetParent($cursor)
  if ($null -eq $parent) { break }
  $cursor = $parent.FullName
}

$configDir = Join-Path $root '.codex'
$configPath = Join-Path $configDir 'config.toml'
if ([System.IO.Directory]::Exists($configDir)) { Assert-NotReparse $configDir }
if ([System.IO.File]::Exists($configPath)) { Assert-NotReparse $configPath }

$runtime = if ([string]::IsNullOrWhiteSpace($BridgeSourceRoot)) {
  [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\runtime\mcp.mjs'))
} else {
  $sourceRoot = [System.IO.Path]::GetFullPath($BridgeSourceRoot)
  if (-not [System.IO.File]::Exists((Join-Path $sourceRoot 'scripts\install_addon.ps1'))) {
    throw "Not a Bridge source checkout: $sourceRoot"
  }
  [System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $sourceRoot) 'plugins\godot-codex-bridge\runtime\mcp.mjs'))
}
if (-not [System.IO.File]::Exists($runtime)) { throw "Bundled MCP runtime is missing: $runtime" }
$node = Get-Command node -ErrorAction SilentlyContinue
if ($null -eq $node) { throw 'Node.js 22.14 or newer is required on PATH.' }
$nodeVersion = & node --version
if ($LASTEXITCODE -ne 0 -or [version]($nodeVersion.TrimStart('v')) -lt [version]'22.14.0') {
  throw "Node.js 22.14 or newer is required; found $nodeVersion"
}

function Quote-Toml([string] $Value) {
  return '"' + $Value.Replace('\', '/').Replace('"', '\"') + '"'
}

$begin = '# BEGIN godot-codex-bridge managed MCP'
$end = '# END godot-codex-bridge managed MCP'
$block = @(
  $begin,
  '[mcp_servers.godot_codex_bridge]',
  'command = "node"',
  ('args = [' + (Quote-Toml $runtime) + ', "--project-root", ' + (Quote-Toml $root) + ', "--bridge-dir", ' + (Quote-Toml (Join-Path $root '.godot\godot_codex_bridge')) + ']'),
  $end
) -join "`n"

$current = if ([System.IO.File]::Exists($configPath)) { [System.IO.File]::ReadAllText($configPath) } else { '' }
$startAt = $current.IndexOf($begin, [System.StringComparison]::Ordinal)
$endAt = $current.IndexOf($end, [System.StringComparison]::Ordinal)
if (($startAt -ge 0) -ne ($endAt -ge 0)) { throw 'Incomplete managed MCP block in config.toml.' }
if ($startAt -ge 0) {
  if ($current.IndexOf($begin, $startAt + $begin.Length, [System.StringComparison]::Ordinal) -ge 0 -or
      $current.IndexOf($end, $endAt + $end.Length, [System.StringComparison]::Ordinal) -ge 0 -or
      $endAt -lt $startAt) { throw 'Ambiguous managed MCP block in config.toml.' }
  $afterEnd = $endAt + $end.Length
  $outside = $current.Substring(0, $startAt) + $current.Substring($afterEnd)
  if ($outside -match '(?m)^\s*\[mcp_servers\.godot_codex_bridge\]\s*$') {
    throw 'An unmanaged godot_codex_bridge MCP entry already exists.'
  }
  $proposed = $current.Substring(0, $startAt) + $block + $current.Substring($afterEnd)
} else {
  if ($current -match '(?m)^\s*\[mcp_servers\.godot_codex_bridge\]\s*$') {
    throw 'An unmanaged godot_codex_bridge MCP entry already exists.'
  }
  $proposed = $current.TrimEnd("`r", "`n") + $(if ($current.Length -gt 0) { "`n`n" } else { '' }) + $block + "`n"
}

$changed = $proposed -cne $current
$backupPath = $null
if ($Apply -and $changed) {
  if (-not [System.IO.Directory]::Exists($configDir)) {
    [System.IO.Directory]::CreateDirectory($configDir) | Out-Null
  }
  Assert-NotReparse $configDir
  if ([System.IO.File]::Exists($configPath)) { Assert-NotReparse $configPath }
  $latest = if ([System.IO.File]::Exists($configPath)) { [System.IO.File]::ReadAllText($configPath) } else { '' }
  if ($latest -cne $current) { throw 'config.toml changed since preview; rerun setup.' }
  $stagingPath = Join-Path $configDir ('.godot-codex-bridge-config-' + [guid]::NewGuid().ToString('N') + '.tmp')
  $encoding = New-Object System.Text.UTF8Encoding($false)
  try {
    [System.IO.File]::WriteAllText($stagingPath, $proposed, $encoding)
    if ([System.IO.File]::Exists($configPath)) {
      $backupPath = "$configPath.godot-codex-bridge.$([DateTime]::UtcNow.ToString('yyyyMMddHHmmssfff')).bak"
      [System.IO.File]::Replace($stagingPath, $configPath, $backupPath)
    } else {
      [System.IO.File]::Move($stagingPath, $configPath)
    }
  } finally {
    if ([System.IO.File]::Exists($stagingPath)) { [System.IO.File]::Delete($stagingPath) }
  }
}

[pscustomobject]@{
  project_root = $root
  config_path = $configPath
  runtime_path = $runtime
  action = $(if (-not $changed) { 'unchanged' } elseif ($Apply) { 'applied' } else { 'preview' })
  changed = $changed
  managed_block = $block
  backup_path = $backupPath
} | ConvertTo-Json -Depth 5
