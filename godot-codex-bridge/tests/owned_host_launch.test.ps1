$ErrorActionPreference = 'Stop'
# One-click Connect launcher contract (contracts/ONE_CLICK_CONNECT_V1.md), mock
# runtime, isolated per-user data directory. No account or external project.
$productRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$launcher = Join-Path $productRoot 'scripts\start_codex_host.ps1'
$fixture = Join-Path ([System.IO.Path]::GetTempPath()) ('gcb-owned-launch-' + [guid]::NewGuid().ToString('N'))
$localAppData = Join-Path $fixture 'localappdata'
$project = Join-Path $fixture 'project'
New-Item -ItemType Directory -Force -Path $project, $localAppData | Out-Null
Set-Content -LiteralPath (Join-Path $project 'project.godot') -Value '[application]'
$port = 49520
$node = (Get-Command node -CommandType Application).Source
$shell = (Get-Command pwsh).Source
$checks = [ordered]@{}
function Assert-True([bool] $Condition, [string] $Message) { if (-not $Condition) { throw $Message } }
function Invoke-Launcher([string[]] $Arguments, [hashtable] $Env = @{}) {
  $info = [System.Diagnostics.ProcessStartInfo]::new($shell)
  foreach ($a in @('-NoProfile', '-NonInteractive', '-File', $launcher) + $Arguments) { $info.ArgumentList.Add($a) }
  $info.UseShellExecute = $false
  $info.CreateNoWindow = $true
  $info.RedirectStandardOutput = $true
  $info.RedirectStandardError = $true
  $info.EnvironmentVariables['LOCALAPPDATA'] = $localAppData
  foreach ($key in $Env.Keys) { $info.EnvironmentVariables[$key] = $Env[$key] }
  return [System.Diagnostics.Process]::Start($info)
}
function Test-PortFree([int] $Number) {
  $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Number)
  try { $listener.Start(); return $true } catch { return $false } finally { $listener.Stop() }
}

$owner = $null
$launch = $null
try {
  $trust = Invoke-Launcher @('-Trust', '-Runtime', 'mock', '-Port', "$port", '-NodeExecutable', $node)
  Assert-True $trust.WaitForExit(120000) 'Trust timed out.'
  Assert-True ($trust.ExitCode -eq 0) "Trust failed: $($trust.StandardError.ReadToEnd())"
  $record = Get-Content -Raw (Join-Path $localAppData 'GodotCodexBridge\trusted_host.json') | ConvertFrom-Json
  Assert-True ($record.schema_version -eq 'trusted-host/1' -and $record.fingerprint -match '^[0-9a-f]{64}$') 'Trust record malformed.'
  Assert-True ([string]::Equals($record.start_script, $launcher, [StringComparison]::OrdinalIgnoreCase)) 'Trust record names another launcher.'
  $scriptSha = (Get-FileHash -Algorithm SHA256 -LiteralPath $launcher).Hash.ToLowerInvariant()
  Assert-True ($record.start_script_sha256 -ceq $scriptSha) 'Trust record does not pin the launcher script hash.'
  $checks.trust_record = $true

  $mismatch = Invoke-Launcher @('-Trust', '-Runtime', 'mock', '-Port', "$port", '-NodeExecutable', $node, '-ExpectedFingerprint', ('f' * 64))
  Assert-True $mismatch.WaitForExit(120000) 'Mismatched re-trust timed out.'
  Assert-True ($mismatch.ExitCode -ne 0) 'Re-trust accepted a fingerprint the user did not approve.'
  Assert-True ((Get-Content -Raw (Join-Path $localAppData 'GodotCodexBridge\trusted_host.json') | ConvertFrom-Json).fingerprint -ceq $record.fingerprint) 'Refused re-trust changed the record.'
  $checks.retrust_bound_to_displayed_fingerprint = $true

  $owner = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\ping.exe') -ArgumentList '-n', '600', '127.0.0.1' -WindowStyle Hidden -PassThru
  $statusPath = Join-Path $localAppData "GodotCodexBridge\launch\$($owner.Id).json"
  $ownedArgs = @('-ProjectRoot', $project, '-Runtime', 'mock', '-Port', "$port", '-NodeExecutable', $node, '-OwnerProcessId', "$($owner.Id)", '-Start')

  $wrong = Invoke-Launcher ($ownedArgs + @('-ExpectedFingerprint', ('0' * 64))) @{ GODOT_CODEX_HOST_PAIR_SECRET_INPUT = ('a' * 64) }
  Assert-True $wrong.WaitForExit(120000) 'Wrong-fingerprint launch timed out.'
  Assert-True ($wrong.ExitCode -ne 0) 'Wrong fingerprint started a Host.'
  Assert-True ((Get-Content -Raw $statusPath | ConvertFrom-Json).status -eq 'fingerprint_changed') 'Wrong fingerprint not reported.'
  Assert-True (Test-PortFree $port) 'Wrong fingerprint left the port bound.'
  $checks.fingerprint_changed_refused = $true

  $noSecret = Invoke-Launcher ($ownedArgs + @('-ExpectedFingerprint', $record.fingerprint))
  Assert-True $noSecret.WaitForExit(120000) 'No-secret launch timed out.'
  Assert-True ($noSecret.ExitCode -ne 0 -and (Test-PortFree $port)) 'Launch without an editor secret started a Host.'
  $checks.missing_secret_refused = $true

  $launch = Invoke-Launcher ($ownedArgs + @('-ExpectedFingerprint', $record.fingerprint)) @{ GODOT_CODEX_HOST_PAIR_SECRET_INPUT = ('b' * 64) }
  $deadline = [DateTime]::UtcNow.AddSeconds(120)
  $ready = $false
  while ([DateTime]::UtcNow -lt $deadline -and -not $launch.HasExited) {
    if (Test-Path $statusPath) {
      $status = Get-Content -Raw $statusPath | ConvertFrom-Json
      if ($status.status -eq 'ready') { $ready = $true; break }
    }
    Start-Sleep -Milliseconds 250
  }
  Assert-True $ready "Owned launch never became ready: $(if (Test-Path $statusPath) { Get-Content -Raw $statusPath })"
  Assert-True (-not (Test-PortFree $port)) 'Ready Host is not listening.'
  $checks.owned_launch_ready_without_prompt = $true

  Stop-Process -Id $owner.Id -Force
  Assert-True $launch.WaitForExit(30000) 'Launcher did not exit after its owner closed.'
  $releaseDeadline = [DateTime]::UtcNow.AddSeconds(10)
  while (-not (Test-PortFree $port) -and [DateTime]::UtcNow -lt $releaseDeadline) { Start-Sleep -Milliseconds 200 }
  Assert-True (Test-PortFree $port) 'Host kept the port after the owner closed.'
  $checks.stops_with_owner = $true
} finally {
  if ($owner -and -not $owner.HasExited) { Stop-Process -Id $owner.Id -Force -ErrorAction SilentlyContinue }
  if ($launch -and -not $launch.HasExited) { $launch.Kill($true) }
  Remove-Item -Recurse -Force -LiteralPath $fixture -ErrorAction SilentlyContinue
}
[ordered]@{ status = 'passed'; checks = $checks; scope = 'isolated mock fixture; no account or external project' } | ConvertTo-Json
