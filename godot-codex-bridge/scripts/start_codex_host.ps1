param(
  [string] $ProjectRoot = '',
  [ValidateRange(1, 65534)][int] $Port = 49390,
  [ValidateSet('app-server', 'mock')][string] $Runtime = 'app-server',
  [string] $NodeExecutable = '',
  [string] $CodexExecutable = '',
  [switch] $Inspect,
  [switch] $Start,
  # Record this installation in the per-user trust record so the Godot dock's
  # Connect button may start it (contracts/ONE_CLICK_CONNECT_V1.md).
  [switch] $Trust,
  # Owned launch by a Godot editor: non-interactive, bound to the trust record.
  [int] $OwnerProcessId = 0,
  [string] $ExpectedFingerprint = ''
)

$ErrorActionPreference = 'Stop'
if (@($Inspect, $Start, $Trust | Where-Object { $_ }).Count -ne 1) { throw 'Choose exactly one action: -Inspect, -Start or -Trust. Startup is never automatic.' }
if (-not $Trust -and [string]::IsNullOrWhiteSpace($ProjectRoot)) { throw '-ProjectRoot is required for -Inspect and -Start.' }
if ($OwnerProcessId -gt 0 -and -not $Start) { throw '-OwnerProcessId is only valid with -Start.' }
$trustDir = Join-Path $env:LOCALAPPDATA 'GodotCodexBridge'
$trustPath = Join-Path $trustDir 'trusted_host.json'

function FullPath([string] $Value) { return [System.IO.Path]::GetFullPath($Value).TrimEnd('\', '/') }
function IsInside([string] $PathValue, [string] $RootValue) {
  $path = FullPath $PathValue
  $root = FullPath $RootValue
  return $path.Equals($root, [StringComparison]::OrdinalIgnoreCase) -or $path.StartsWith(($root + '\'), [StringComparison]::OrdinalIgnoreCase)
}
function Assert-PlainPath([string] $PathValue) {
  $current = FullPath $PathValue
  while ($true) {
    if (Test-Path -LiteralPath $current) {
      $item = Get-Item -LiteralPath $current -Force
      if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse point is not trusted: $current" }
    }
    $parent = [System.IO.Path]::GetDirectoryName($current)
    if ([string]::IsNullOrEmpty($parent) -or $parent -eq $current) { break }
    $current = $parent
  }
}
function Resolve-NativeExecutable([string] $Value, [string] $Label) {
  if ([string]::IsNullOrWhiteSpace($Value)) { throw "$Label is required." }
  $candidate = if ([System.IO.Path]::IsPathRooted($Value)) { $Value } else {
    $command = Get-Command $Value -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $command.Source
  }
  $resolved = FullPath $candidate
  if (-not [System.IO.File]::Exists($resolved) -or [System.IO.Path]::GetExtension($resolved) -ne '.exe') {
    throw "$Label must be an existing native .exe: $resolved"
  }
  Assert-PlainPath $resolved
  if ($project -and (IsInside $resolved $project)) { throw "$Label cannot come from the target project: $resolved" }
  return $resolved
}
function Assert-PortFree([int] $Number) {
  $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Number)
  try { $listener.Start() } catch { throw "Loopback port $Number is occupied; stop its owner or choose another port. No process was stopped." }
  finally { $listener.Stop() }
}
function Get-Identity([string] $ProjectField = $project) {
  $files = New-Object System.Collections.Generic.List[string]
  foreach ($single in @($scriptPath, $node, $codex, (Join-Path $hostRoot 'package.json'), (Join-Path $hostRoot 'package-lock.json'), (Join-Path $installRoot 'mcp_server\package.json'), (Join-Path $installRoot 'mcp_server\package-lock.json'))) {
    if (-not [string]::IsNullOrEmpty($single)) {
      if (-not [System.IO.File]::Exists($single)) { throw "Trusted installation file missing: $single. Build/install the Host first." }
      Assert-PlainPath $single
      $files.Add($single)
    }
  }
  foreach ($tree in @((Join-Path $hostRoot 'dist\src'), (Join-Path $hostRoot 'node_modules'), (Join-Path $installRoot 'mcp_server\dist\src'), (Join-Path $installRoot 'mcp_server\node_modules'))) {
    if (-not [System.IO.Directory]::Exists($tree)) { throw "Trusted installation tree missing: $tree. Run npm ci and npm run build in the trusted installation." }
    Assert-PlainPath $tree
    $pending = [System.Collections.Generic.Stack[string]]::new()
    $pending.Push($tree)
    while ($pending.Count -gt 0) {
      foreach ($item in (Get-ChildItem -LiteralPath $pending.Pop() -Force)) {
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Reparse point is not trusted: $($item.FullName)" }
        if ($item.PSIsContainer) { $pending.Push($item.FullName) }
        else {
          $files.Add($item.FullName)
          if ($files.Count -gt 5000) { throw 'Trusted installation exceeds the 5000-file identity limit.' }
        }
      }
    }
  }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $stream = [System.IO.MemoryStream]::new()
  $writer = [System.IO.BinaryWriter]::new($stream, [System.Text.Encoding]::UTF8)
  $bytes = [long]0
  try {
    foreach ($field in @('trusted-host-start-v1', $installRoot, $ProjectField, $node, $codex, $Runtime, [string]$Port, [string]($Port + 1))) { $writer.Write([string]$field) }
    foreach ($file in ($files | Sort-Object -Unique)) {
      $info = [System.IO.FileInfo]::new($file)
      $bytes += $info.Length
      if ($bytes -gt 536870912) { throw 'Trusted installation exceeds the 512 MiB identity limit.' }
      $writer.Write([string]$file)
      $writer.Write([long]$info.Length)
      $inputStream = [System.IO.File]::Open($file, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
      try { $writer.Write([byte[]]$sha.ComputeHash($inputStream)) } finally { $inputStream.Dispose() }
    }
    $writer.Flush()
    $stream.Position = 0
    return [ordered]@{
      fingerprint = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '').ToLowerInvariant()
      file_count = $files.Count
      covered_bytes = $bytes
    }
  } finally { $writer.Dispose(); $stream.Dispose(); $sha.Dispose() }
}

$scriptPath = FullPath $MyInvocation.MyCommand.Path
$installRoot = FullPath (Join-Path $PSScriptRoot '..')
$hostRoot = FullPath (Join-Path $installRoot 'codex_host')
$entry = FullPath (Join-Path $hostRoot 'dist\src\index.js')
$project = if ($Trust) { '' } else { FullPath $ProjectRoot }
$ownedLaunch = $Start -and $OwnerProcessId -gt 0
$launchStatusPath = if ($ownedLaunch) { Join-Path (Join-Path $trustDir 'launch') "$OwnerProcessId.json" } else { '' }
function Write-LaunchStatus([string] $Status, [string] $Message, [hashtable] $Extra = @{}) {
  if (-not $launchStatusPath) { return }
  $payload = [ordered]@{ status = $Status; message = $Message; updated_at = (Get-Date).ToUniversalTime().ToString('o') }
  foreach ($key in $Extra.Keys) { $payload[$key] = $Extra[$key] }
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $launchStatusPath) | Out-Null
  $temporary = "$launchStatusPath.$([guid]::NewGuid().ToString('N')).tmp"
  [System.IO.File]::WriteAllText($temporary, ($payload | ConvertTo-Json -Compress), [System.Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporary -Destination $launchStatusPath -Force
}
function Get-DefaultCodex {
  $arm = $env:PROCESSOR_ARCHITECTURE -eq 'ARM64'
  $candidate = Join-Path $env:APPDATA ('npm\node_modules\@openai\codex\node_modules\@openai\' + $(if ($arm) { 'codex-win32-arm64\vendor\aarch64-pc-windows-msvc' } else { 'codex-win32-x64\vendor\x86_64-pc-windows-msvc' }) + '\bin\codex.exe')
  if ([System.IO.File]::Exists($candidate)) { return $candidate }
  return ''
}
try {
if ($project) {
  if (-not [System.IO.File]::Exists((Join-Path $project 'project.godot'))) { throw "Target is not a Godot project: $project" }
  Assert-PlainPath $project
  if ((IsInside $installRoot $project) -or (IsInside $project $installRoot)) {
    throw 'Trusted installation and target project must be separate trees.'
  }
}
Assert-PlainPath $scriptPath
Assert-PlainPath $installRoot
$node = Resolve-NativeExecutable $(if ($NodeExecutable) { $NodeExecutable } else { 'node.exe' }) 'Node executable'
$codex = if ($Runtime -eq 'app-server') { Resolve-NativeExecutable $(if ($CodexExecutable) { $CodexExecutable } else { Get-DefaultCodex }) 'Codex executable' } else { '' }
if (-not [System.IO.File]::Exists($entry)) { throw "Built Host entrypoint missing: $entry. Run npm ci and npm run build in the trusted installation." }

# Project-independent identity: what a trust record approves for every project.
$installation = Get-Identity ''
if ($Trust) {
  # The owned launch reuses this shell; the launcher needs PowerShell 7 APIs.
  if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Run -Trust with PowerShell 7 (pwsh), which the Connect button will use to start the Host.' }
  # When the editor asks to re-trust, it names the fingerprint it showed the
  # user; refuse if the files on disk differ from what was approved.
  if ($ExpectedFingerprint -and $installation.fingerprint -cne $ExpectedFingerprint) {
    throw "The Host installation differs from the fingerprint you approved ($ExpectedFingerprint); nothing was trusted."
  }
  $shell = FullPath (Get-Process -Id $PID).Path
  # The editor verifies this hash itself before running the launcher, so a
  # modified launcher cannot vouch for its own checks.
  $scriptSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $scriptPath).Hash.ToLowerInvariant()
  $record = [ordered]@{
    schema_version = 'trusted-host/1'
    install_root = $installRoot
    start_script = $scriptPath
    start_script_sha256 = $scriptSha
    powershell_executable = $shell
    node_executable = $node
    codex_executable = $codex
    runtime = $Runtime
    port = $Port
    fingerprint = $installation.fingerprint
    trusted_at = (Get-Date).ToUniversalTime().ToString('o')
  }
  New-Item -ItemType Directory -Force -Path $trustDir | Out-Null
  $temporary = "$trustPath.$([guid]::NewGuid().ToString('N')).tmp"
  [System.IO.File]::WriteAllText($temporary, ($record | ConvertTo-Json), [System.Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporary -Destination $trustPath -Force
  $record | ConvertTo-Json -Compress | Write-Output
  [Console]::Error.WriteLine("Trusted this Host installation for one-click Connect: $trustPath")
  return
}

if ($ownedLaunch) {
  Write-LaunchStatus 'starting' 'Verifying the trusted Host installation.'
  if (-not [System.IO.File]::Exists($trustPath)) { Write-LaunchStatus 'untrusted' 'No trusted Host record. Run start_codex_host.ps1 -Trust once.'; exit 3 }
  $record = Get-Content -Raw -LiteralPath $trustPath | ConvertFrom-Json
  $same = { param($a, $b) [string]::Equals([string]$a, [string]$b, [StringComparison]::OrdinalIgnoreCase) }
  if (-not ((& $same $record.start_script $scriptPath) -and (& $same $record.node_executable $node) -and (& $same $record.codex_executable $codex) -and ([string]$record.runtime -eq $Runtime) -and ([int]$record.port -eq $Port))) {
    Write-LaunchStatus 'untrusted' 'This launch does not match the trusted Host record.'; exit 3
  }
  if ($installation.fingerprint -cne [string]$record.fingerprint -or $installation.fingerprint -cne $ExpectedFingerprint) {
    Write-LaunchStatus 'fingerprint_changed' 'The Host installation changed since it was trusted.' @{ fingerprint = $installation.fingerprint; trusted_fingerprint = [string]$record.fingerprint }
    exit 4
  }
  $pairInput = [string]$env:GODOT_CODEX_HOST_PAIR_SECRET_INPUT
  # This launcher lives as long as the editor; do not keep the secret around.
  Remove-Item Env:GODOT_CODEX_HOST_PAIR_SECRET_INPUT -ErrorAction SilentlyContinue
  if ($pairInput -cnotmatch '^[0-9a-f]{64}$') { Write-LaunchStatus 'failed' 'The editor did not provide a valid pairing secret.'; exit 3 }
  if (-not [string]::Equals((Get-Process -Id $PID).Path, [string]$record.powershell_executable, [StringComparison]::OrdinalIgnoreCase)) {
    Write-LaunchStatus 'untrusted' 'The launcher is not running under the trusted PowerShell.'; exit 3
  }
  # Hold a handle now so a later reuse of the editor PID cannot keep the Host alive.
  $ownerProcess = Get-Process -Id $OwnerProcessId -ErrorAction SilentlyContinue
  if (-not $ownerProcess) { Write-LaunchStatus 'failed' 'The requesting editor is no longer running.'; exit 3 }
}
$identity = Get-Identity
$display = [ordered]@{
  installation = $installRoot
  target_project = $project
  host_entrypoint = $entry
  node_executable = $node
  codex_executable = $codex
  runtime = $Runtime
  host_port = $Port
  app_server_port = $Port + 1
  fingerprint = $identity.fingerprint
  covered_file_count = $identity.file_count
  covered_bytes = $identity.covered_bytes
  coverage = 'Launcher, Host/MCP dist/src and node_modules, both package manifests and lockfiles, Node executable, and Codex executable when app-server is selected. Excludes OS libraries, Godot addon/project contents, and account state.'
}
$display | ConvertTo-Json -Compress | Write-Output
if ($Inspect) { return }

Assert-PortFree $Port
Assert-PortFree ($Port + 1)
if (-not $ownedLaunch) {
  # Manual start: the human approves the exact identity here. An owned start
  # was approved earlier through -Trust and matched the record above.
  [Console]::Error.WriteLine("To start this exact installation and configuration, type START $($identity.fingerprint)")
  $decision = [Console]::ReadLine()
  if ($decision -cne "START $($identity.fingerprint)") { throw 'Startup cancelled or approval did not match the displayed installation identity. No Host was started.' }
  $current = Get-Identity
  if ($current.fingerprint -cne $identity.fingerprint) { throw 'Trusted installation changed after review. No Host was started; inspect and approve again.' }
  Assert-PortFree $Port
  Assert-PortFree ($Port + 1)
}

$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $node
$startInfo.Arguments = '"' + $entry + '" --port ' + $Port + ' --runtime ' + $Runtime
$startInfo.WorkingDirectory = $hostRoot
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.RedirectStandardInput = $true
$launchNonce = [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')
if ($ownedLaunch) {
  # The editor generated this secret and pairs with it automatically.
  $pairSecret = $pairInput
} else {
  $pairBytes = [byte[]]::new(32)
  [System.Security.Cryptography.RandomNumberGenerator]::Fill($pairBytes)
  $pairSecret = [Convert]::ToHexString($pairBytes).ToLowerInvariant()
}
foreach ($key in @($startInfo.EnvironmentVariables.Keys)) {
  if ($key -like 'GODOT_CODEX_HOST_*' -or $key -in @('NODE_OPTIONS', 'NODE_PATH')) { $startInfo.EnvironmentVariables.Remove($key) }
}
$startInfo.EnvironmentVariables['GODOT_CODEX_HOST_BIND'] = '127.0.0.1'
$startInfo.EnvironmentVariables['GODOT_CODEX_HOST_PORT'] = [string]$Port
$startInfo.EnvironmentVariables['GODOT_CODEX_HOST_RUNTIME'] = $Runtime
$startInfo.EnvironmentVariables['GODOT_CODEX_APP_SERVER_PORT'] = [string]($Port + 1)
$startInfo.EnvironmentVariables['GODOT_CODEX_HOST_LAUNCH_NONCE'] = $launchNonce
$startInfo.EnvironmentVariables['GODOT_CODEX_HOST_PAIR_SECRET'] = $pairSecret
$startInfo.EnvironmentVariables['GODOT_CODEX_HOST_ALLOWED_PROJECT_ROOT'] = $project
if ($codex) { $startInfo.EnvironmentVariables['GODOT_CODEX_HOST_CODEX_BIN'] = $codex }
$owned = [System.Diagnostics.Process]::new()
$owned.StartInfo = $startInfo
$ownedStarted = $false
$proofKey = [Convert]::FromHexString($launchNonce)
$proofHmac = [System.Security.Cryptography.HMACSHA256]::new($proofKey)
try { $expectedProof = [Convert]::ToHexString($proofHmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes('godot-codex-bridge-host-health-v1'))).ToLowerInvariant() }
finally { $proofHmac.Dispose() }
try {
  if (-not $owned.Start()) { throw 'Trusted Host process did not start.' }
  $ownedStarted = $true
  $deadline = [DateTime]::UtcNow.AddSeconds(15)
  $healthy = $false
  while ([DateTime]::UtcNow -lt $deadline) {
    if ($owned.HasExited) { throw "Trusted Host exited during startup (code $($owned.ExitCode))." }
    try {
      $health = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 1
      if ([string]$health.runtime -eq $Runtime -and [int]$health.port -eq $Port -and [string]$health.launch_proof -ceq $expectedProof) { $healthy = $true; break }
    } catch { }
    Start-Sleep -Milliseconds 200
  }
  if (-not $healthy) { throw 'Trusted Host did not become healthy. Check installation and port configuration.' }
  Start-Sleep -Milliseconds 300
  if ($owned.HasExited) { throw "Trusted Host exited after health check (code $($owned.ExitCode))." }
  Write-Output "HOST_READY pid=$($owned.Id) port=$Port fingerprint=$($identity.fingerprint)"
  if ($ownedLaunch) {
    Write-LaunchStatus 'ready' 'Codex Host is running.' @{ host_pid = $owned.Id; port = $Port; fingerprint = $installation.fingerprint }
    # Live as long as the owning editor; the Host itself may outlive it while
    # an addon update installs (it defers shutdown, see below).
    while (-not $owned.HasExited -and -not $ownerProcess.HasExited) { Start-Sleep -Milliseconds 500 }
    if ($owned.HasExited) { Write-LaunchStatus 'failed' "Codex Host exited (code $($owned.ExitCode))."; exit 1 }
  } else {
    [Console]::Error.WriteLine("Paste this one-launch pairing code into the Godot Codex Bridge dock: $pairSecret")
    [Console]::Error.WriteLine('Press Enter or type STOP to stop this owned Host. Connect or reconnect from the Godot dock while it runs.')
    $stopTask = [Console]::In.ReadLineAsync()
    while (-not $owned.HasExited -and -not $stopTask.IsCompleted) { Start-Sleep -Milliseconds 200 }
    if ($owned.HasExited) { throw "Trusted Host exited (code $($owned.ExitCode))." }
  }
} finally {
  $cleanupFailure = ''
  if ($ownedStarted -and -not $owned.HasExited) {
    try {
      $owned.StandardInput.WriteLine("STOP $launchNonce")
      $owned.StandardInput.Flush()
      # A pending addon update keeps the Host alive until it installs and
      # reopens the project (installer timeout 5 min after a 30 min exit wait).
      $graceMs = if ($ownedLaunch) { 15 * 60 * 1000 } else { 5000 }
      if (-not $owned.WaitForExit($graceMs)) { $cleanupFailure = 'Owned Host did not complete graceful shutdown in time.' }
    } catch { $cleanupFailure = "Owned Host graceful shutdown failed: $($_.Exception.Message)" }
    if (-not $owned.HasExited) {
      try { $owned.Kill($true); [void]$owned.WaitForExit(5000) }
      catch { $cleanupFailure += " Forced termination also failed: $($_.Exception.Message)" }
      if (-not $cleanupFailure) { $cleanupFailure = 'Owned Host required forced termination.' }
    }
  }
  $owned.Dispose()
  if ($cleanupFailure) { throw "$cleanupFailure App-server descendant cleanup is unverified; inspect before retrying." }
}
} catch {
  Write-LaunchStatus 'failed' $_.Exception.Message
  throw
}