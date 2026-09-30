$ErrorActionPreference = 'Stop'
$productRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('gcb-trusted-start-denials-' + [guid]::NewGuid().ToString('N'))
$install = Join-Path $fixtureRoot 'installation'
$project = Join-Path $fixtureRoot 'project'
$launcher = Join-Path $install 'scripts\start_codex_host.ps1'
$entry = Join-Path $install 'codex_host\dist\src\index.js'
$sentinel = Join-Path $fixtureRoot 'host-started.sentinel'
$port = 0
$owned = $null
$ownedStarted = $false
$checks = [ordered]@{}

function Assert-True([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }
function New-StartInfo([int] $ChosenPort, [string] $NodePath = '') {
  $info = [System.Diagnostics.ProcessStartInfo]::new()
  $info.FileName = (Get-Command pwsh).Source
  $info.Arguments = '-NoProfile -File "' + $launcher + '" -ProjectRoot "' + $project + '" -Runtime mock -Port ' + $ChosenPort + ' -Start'
  if ($NodePath) { $info.Arguments += ' -NodeExecutable "' + $NodePath + '"' }
  $info.UseShellExecute = $false
  $info.CreateNoWindow = $true
  $info.RedirectStandardInput = $true
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true
  $info.StandardInputEncoding = [System.Text.UTF8Encoding]::new($false)
  return $info
}
function Invoke-Denial([string] $Name, [int] $ChosenPort, [string] $Decision, [string] $NodePath = '', [bool] $AllowExistingSentinel = $false) {
  $proc = [System.Diagnostics.Process]::new()
  $proc.StartInfo = New-StartInfo $ChosenPort $NodePath
  try {
    Assert-True ($proc.Start()) "${Name}: launcher did not start."
    $proc.StandardInput.WriteLine($Decision)
    $proc.StandardInput.Close()
    if (-not $proc.WaitForExit(15000)) {
      $proc.StandardInput.Close()
      if (-not $proc.WaitForExit(5000)) { $proc.Kill(); [void]$proc.WaitForExit(5000) }
      throw "${Name}: launcher did not reject in time; owned process was stopped."
    }
    $stderr = $proc.StandardError.ReadToEnd()
    $stdout = $proc.StandardOutput.ReadToEnd()
    Assert-True ($proc.ExitCode -ne 0) "${Name}: launcher unexpectedly accepted input."
    if (-not $AllowExistingSentinel) { Assert-True (-not (Test-Path -LiteralPath $sentinel)) "${Name}: fixture Host entrypoint ran." }
    Assert-True (-not $stdout.Contains('HOST_READY')) "${Name}: launcher reported Host ready."
    $checks[$Name] = [ordered]@{ rejected = $true; exit_code = $proc.ExitCode; error = (($stderr -split "`r?`n" | Where-Object { $_ -and $_ -notmatch '^\s*At ' }) | Select-Object -First 1) }
  } finally { $proc.Dispose() }
}

try {
  foreach ($dir in @($install, $project, (Join-Path $install 'scripts'), (Join-Path $install 'codex_host\dist\src'), (Join-Path $install 'codex_host\node_modules'), (Join-Path $install 'mcp_server\dist\src'), (Join-Path $install 'mcp_server\node_modules'))) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }
  Copy-Item -LiteralPath (Join-Path $productRoot 'examples\minimal_3d_project\project.godot') -Destination $project
  Copy-Item -LiteralPath (Join-Path $productRoot 'scripts\start_codex_host.ps1') -Destination $launcher
  foreach ($part in @('codex_host', 'mcp_server')) {
    foreach ($manifest in @('package.json', 'package-lock.json')) {
      Copy-Item -LiteralPath (Join-Path $productRoot "$part\$manifest") -Destination (Join-Path $install "$part\$manifest")
    }
  }
  $fixtureJs = @'
import http from 'node:http';
import fs from 'node:fs';
import { createHmac } from 'node:crypto';
const port = Number(process.argv[process.argv.indexOf('--port') + 1]);
fs.writeFileSync(new URL('../../../../host-started.sentinel', import.meta.url), 'owned fixture host');
const server = http.createServer((req, res) => {
  res.setHeader('Content-Type', 'application/json');
  const nonce = process.env.GODOT_CODEX_HOST_LAUNCH_NONCE;
  const launch_proof = createHmac('sha256', Buffer.from(nonce, 'hex')).update('godot-codex-bridge-host-health-v1').digest('hex');
  res.end(JSON.stringify({ runtime: 'mock', port, launch_proof }));
}).listen(port, '127.0.0.1');
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => {
  if (chunk.trim() === `STOP ${process.env.GODOT_CODEX_HOST_LAUNCH_NONCE}`) {
    server.close(() => process.exit(0));
  }
});
process.stdin.on('end', () => server.close(() => process.exit(0)));
'@
  [System.IO.File]::WriteAllText($entry, $fixtureJs, [System.Text.UTF8Encoding]::new($false))
  [System.IO.File]::WriteAllText((Join-Path $install 'mcp_server\dist\src\index.js'), 'export {};', [System.Text.UTF8Encoding]::new($false))
  $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
  try { $listener.Start(); $port = [int]$listener.LocalEndpoint.Port } finally { $listener.Stop() }

  $inspectArgs = @('-NoProfile', '-File', $launcher, '-ProjectRoot', $project, '-Runtime', 'mock', '-Port', [string]$port, '-Inspect')
  $identity = & pwsh @inspectArgs | ConvertFrom-Json
  Assert-True ([string]$identity.fingerprint -match '^[a-f0-9]{64}$') 'Inspection fingerprint missing.'
  Invoke-Denial 'cancelled' $port ''
  $projectConfigDir = Join-Path $project 'addons\godot_codex_bridge'
  New-Item -ItemType Directory -Path $projectConfigDir -Force | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $projectConfigDir 'host_config.json'), ('{"port":' + $port + ',"start_script":"' + $launcher.Replace('\', '\\') + '","approval_token":"' + $identity.fingerprint + '"}'))
  Invoke-Denial 'forged_project_config' $port ''
  $missingCodex = & pwsh -NoProfile -File $launcher -ProjectRoot $project -Runtime app-server -Port $port -Start 2>&1
  Assert-True ($LASTEXITCODE -ne 0 -and -not (Test-Path -LiteralPath $sentinel)) 'Missing Codex executable did not fail closed.'
  $checks.missing_codex_executable = [ordered]@{ rejected = $true; error_contains_required = ([string]($missingCodex | Out-String)).Contains('required') }
  $changedPort = if ($port -lt 65533) { $port + 2 } else { $port - 2 }
  Invoke-Denial 'changed_configuration' $changedPort ('START ' + $identity.fingerprint)
  [System.IO.File]::AppendAllText($entry, "`n// changed after inspection")
  Invoke-Denial 'changed_build' $port ('START ' + $identity.fingerprint)
  $promptProcess = [System.Diagnostics.Process]::new()
  $promptProcess.StartInfo = New-StartInfo $port
  $promptStarted = $false
  try {
    Assert-True ($promptProcess.Start()) 'Prompt-race fixture launcher did not start.'
    $promptStarted = $true
    $displayed = $promptProcess.StandardOutput.ReadLine() | ConvertFrom-Json
    Assert-True ([string]$displayed.fingerprint -match '^[a-f0-9]{64}$') 'Prompt-race fingerprint missing.'
    [System.IO.File]::AppendAllText($entry, "`n// changed during prompt")
    $promptProcess.StandardInput.WriteLine('START ' + $displayed.fingerprint)
    $promptProcess.StandardInput.Close()
    Assert-True ($promptProcess.WaitForExit(15000)) 'Prompt-race launcher did not reject in time.'
    Assert-True ($promptProcess.ExitCode -ne 0 -and -not (Test-Path -LiteralPath $sentinel)) 'Changed build after prompt started a Host.'
    $checks.changed_after_prompt = [ordered]@{ rejected = $true; no_host_process = $true }
  } finally {
    if ($promptStarted -and -not $promptProcess.HasExited) {
      $promptProcess.StandardInput.Close()
      if (-not $promptProcess.WaitForExit(5000)) { $promptProcess.Kill(); [void]$promptProcess.WaitForExit(5000) }
    }
    $promptProcess.Dispose()
  }
  $identity = & pwsh @inspectArgs | ConvertFrom-Json

  $projectExe = Join-Path $project 'project-node.exe'
  Copy-Item -LiteralPath (Join-Path $env:WINDIR 'System32\cmd.exe') -Destination $projectExe
  Invoke-Denial 'project_executable' $port ('START ' + $identity.fingerprint) $projectExe

  $occupied = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)
  try { $occupied.Start(); Invoke-Denial 'occupied_port' $port ('START ' + $identity.fingerprint) } finally { $occupied.Stop() }

  $owned = [System.Diagnostics.Process]::new()
  $owned.StartInfo = New-StartInfo $port
  Assert-True ($owned.Start()) 'Approved fixture launcher did not start.'
  $ownedStarted = $true
  $owned.StandardInput.WriteLine('START ' + $identity.fingerprint)
  $owned.StandardInput.Flush()
  $ready = ''
  $deadline = [DateTime]::UtcNow.AddSeconds(15)
  while ([DateTime]::UtcNow -lt $deadline) {
    if ($owned.HasExited) { throw ('Approved fixture launcher exited before health: ' + $owned.StandardError.ReadToEnd()) }
    $lineTask = $owned.StandardOutput.ReadLineAsync()
    Assert-True ($lineTask.Wait(5000)) 'Approved fixture launcher output timed out.'
    if ([string]$lineTask.Result -like 'HOST_READY *') { $ready = [string]$lineTask.Result; break }
  }
  Assert-True ($ready -match '^HOST_READY pid=(\d+) port=(\d+) fingerprint=([a-f0-9]{64})$') 'Approved fixture Host did not become ready.'
  Assert-True (Test-Path -LiteralPath $sentinel) 'Approved fixture Host entrypoint did not run.'
  $health = Invoke-RestMethod -Uri "http://127.0.0.1:$port/health" -TimeoutSec 2
  Assert-True ([string]$health.runtime -eq 'mock' -and [int]$health.port -eq $port) 'Approved fixture Host health mismatch.'
  Assert-True (-not ($health.PSObject.Properties.Name -contains 'launch_nonce')) 'Health leaked launch nonce.'
  Assert-True ([string]$health.launch_proof -match '^[a-f0-9]{64}$') 'Health lacked launcher proof.'
  $checks.approved_fixture_start = [ordered]@{ ready = $true; health = 'mock'; host_pid = [int]$Matches[1] }

  Invoke-Denial 'repeated_start_occupied' $port ('START ' + $identity.fingerprint) '' $true
  $health = Invoke-RestMethod -Uri "http://127.0.0.1:$port/health" -TimeoutSec 2
  Assert-True ([string]$health.runtime -eq 'mock') 'Repeated start terminated the existing owned Host.'

  $owned.StandardInput.WriteLine('STOP')
  $owned.StandardInput.Flush()
  Assert-True ($owned.WaitForExit(10000)) 'Owned fixture Host did not stop after STOP.'
  $probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)
  try { $probe.Start(); $checks.cleanup = [ordered]@{ launcher_exited = $owned.HasExited; port_released = $true } } finally { $probe.Stop() }
  Remove-Item -LiteralPath $sentinel
  [System.IO.File]::WriteAllText($entry, "throw new Error('fixture startup failure');", [System.Text.UTF8Encoding]::new($false))
  $failureIdentity = & pwsh @inspectArgs | ConvertFrom-Json
  Invoke-Denial 'startup_failure' $port ('START ' + $failureIdentity.fingerprint)
  $probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)
  try { $probe.Start(); $checks.startup_failure_port_released = $true } finally { $probe.Stop() }
  [ordered]@{ status = 'passed'; checks = $checks; scope = 'isolated mock fixture; no account or external project' } | ConvertTo-Json -Depth 8
} finally {
  if ($null -ne $owned) {
    try {
      if ($ownedStarted -and -not $owned.HasExited) {
        $owned.StandardInput.WriteLine('STOP')
        $owned.StandardInput.Flush()
        if (-not $owned.WaitForExit(10000)) {
          $owned.Kill()
          [void]$owned.WaitForExit(5000)
          throw 'Fixture launcher failed to stop its owned Host; owned launcher was terminated and fixture is preserved for descendant check.'
        }
      }
    } finally { $owned.Dispose() }
  }
  $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\', '/')
  $fullFixture = [System.IO.Path]::GetFullPath($fixtureRoot)
  if ($fullFixture.StartsWith(($tempRoot + [System.IO.Path]::DirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase) -and [System.IO.Path]::GetFileName($fullFixture) -like 'gcb-trusted-start-denials-*') {
    Remove-Item -LiteralPath $fullFixture -Recurse -Force -ErrorAction SilentlyContinue
  }
}
