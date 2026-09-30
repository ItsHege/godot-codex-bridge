param(
  [string] $GodotExecutable = $(if ($env:GODOT_BIN) { $env:GODOT_BIN } elseif (Get-Command godot -ErrorAction SilentlyContinue) { (Get-Command godot).Source } else { '' }),
  [int] $StartupTimeoutSeconds = 60,
  [int] $RequestTimeoutSeconds = 20,
  [switch] $TrustedStartup
)

$ErrorActionPreference = 'Stop'
$productRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$sourceProject = Join-Path $productRoot 'examples\minimal_3d_project'
$sourceAddon = Join-Path $productRoot 'addons\godot_codex_bridge'
$hostRoot = Join-Path $productRoot 'codex_host'
$hostEntry = Join-Path $hostRoot 'dist\src\index.js'
$probeSource = Join-Path $productRoot 'tests\fixture\restricted_probe_plugin.gd'
$fixtureRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('godot-codex-bridge-restricted-' + [guid]::NewGuid().ToString('N'))
$bridgeDir = Join-Path $fixtureRoot '.godot\godot_codex_bridge'
$requestsDir = Join-Path $bridgeDir 'requests'
$responsesDir = Join-Path $bridgeDir 'responses'
$reportPath = Join-Path $fixtureRoot 'checkpoint_evidence.json'
$hostProcess = $null
$launcherProcess = $null
$godotProcess = $null
$port = 0
$evidence = [ordered]@{
  status = 'started'
  started_at = [DateTime]::UtcNow.ToString('o')
  fixture_root = $fixtureRoot
  report_path = $reportPath
  source_addon = $sourceAddon
  host_entry = $hostEntry
  godot_executable = $GodotExecutable
  runtime = 'mock'
  host_start_mode = $(if ($TrustedStartup) { 'trusted_explicit_fixture_confirmation' } else { 'legacy_direct_fixture' })
  checks = [ordered]@{}
  process_ids = [ordered]@{}
  gaps = @('Real Codex account and external game are out of scope.', 'Visual appearance is not independently reviewed by a human.')
}

function Assert-True([bool] $Condition, [string] $Message) {
  if (-not $Condition) { throw $Message }
}

function Write-JsonFile([string] $PathValue, $Value) {
  $json = $Value | ConvertTo-Json -Depth 16
  [System.IO.File]::WriteAllText($PathValue, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-FileSha256([string] $PathValue) {
  $stream = [System.IO.File]::OpenRead($PathValue)
  $algorithm = [System.Security.Cryptography.SHA256]::Create()
  try { return [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-', '') }
  finally { $algorithm.Dispose(); $stream.Dispose() }
}

function Assert-NoReparseTree([string] $RootPath) {
  $pending = New-Object System.Collections.Generic.Stack[System.IO.DirectoryInfo]
  $pending.Push((Get-Item -LiteralPath $RootPath -Force))
  while ($pending.Count -gt 0) {
    $directory = $pending.Pop()
    Assert-True (($directory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) "Source addon contains a reparse point: $($directory.FullName)"
    foreach ($item in (Get-ChildItem -LiteralPath $directory.FullName -Force)) {
      Assert-True (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) "Source addon contains a reparse point: $($item.FullName)"
      if ($item.PSIsContainer) { $pending.Push($item) }
    }
  }
}

function Invoke-FixtureRequest([string] $Type, [hashtable] $Payload) {
  $id = [guid]::NewGuid().ToString('N')
  $requestPath = Join-Path $requestsDir "$id.json"
  $responsePath = Join-Path $responsesDir "$id.json"
  Write-JsonFile $requestPath ([ordered]@{
    protocol_version = 'godot-codex-bridge/0.1'
    request_id = $id
    type = $Type
    created_at = [DateTime]::UtcNow.ToString('o')
    payload = $Payload
  })
  $deadline = [DateTime]::UtcNow.AddSeconds($RequestTimeoutSeconds)
  while ([DateTime]::UtcNow -lt $deadline) {
    if (Test-Path -LiteralPath $responsePath) {
      $response = Get-Content -Raw -LiteralPath $responsePath | ConvertFrom-Json
      Assert-True ([string]$response.request_id -eq $id -and [string]$response.type -eq $Type) "Uncorrelated response for $Type request $id."
      return $response
    }
    Start-Sleep -Milliseconds 200
  }
  throw "Timed out waiting for $Type response $id"
}

function Assert-Response($Response, [string] $Status, [string] $Label) {
  $evidence.checks[$Label] = [ordered]@{
    request_id = [string]$Response.request_id
    type = [string]$Response.type
    status = [string]$Response.status
    error_code = if ($null -ne $Response.error) { [string]$Response.error.code } else { '' }
  }
  Assert-True ($Response.status -eq $Status) "$Label returned $($Response.status), expected $Status"
}

try {
  Assert-True (-not [string]::IsNullOrWhiteSpace($GodotExecutable)) 'Pass -GodotExecutable or set GODOT_BIN to a trusted local Godot executable.'
  foreach ($pathValue in @((Join-Path $sourceProject 'project.godot'), (Join-Path $sourceProject 'scenes'), (Join-Path $sourceProject 'assets'), (Join-Path $sourceAddon 'plugin.cfg'), $probeSource, $hostEntry, $GodotExecutable)) {
    Assert-True (Test-Path -LiteralPath $pathValue) "Required local prerequisite missing: $pathValue"
  }
  $godotItem = Get-Item -LiteralPath $GodotExecutable
  $evidence.godot_executable = $godotItem.FullName
  $evidence.godot_sha256 = Get-FileSha256 $godotItem.FullName
  $evidence.host_sha256 = Get-FileSha256 $hostEntry

  $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
  try {
    $listener.Start()
    $port = [int]$listener.LocalEndpoint.Port
  } finally { $listener.Stop() }
  $evidence.host_port = $port
  Assert-True ($port -gt 0) 'Could not reserve an unused loopback port.'

  New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
  Assert-True (-not (Test-Path -LiteralPath (Join-Path $fixtureRoot 'addons'))) 'Fixture unexpectedly contains an addon.'
  Assert-NoReparseTree (Join-Path $sourceProject 'scenes')
  Assert-NoReparseTree (Join-Path $sourceProject 'assets')
  Copy-Item -LiteralPath (Join-Path $sourceProject 'project.godot') -Destination $fixtureRoot
  Copy-Item -LiteralPath (Join-Path $sourceProject 'scenes') -Destination $fixtureRoot -Recurse
  Copy-Item -LiteralPath (Join-Path $sourceProject 'assets') -Destination $fixtureRoot -Recurse
  $fixtureAddons = Join-Path $fixtureRoot 'addons'
  New-Item -ItemType Directory -Path $fixtureAddons | Out-Null
  $fixtureAddon = Join-Path $fixtureAddons 'godot_codex_bridge'
  Assert-NoReparseTree $sourceAddon
  Copy-Item -LiteralPath $sourceAddon -Destination $fixtureAddon -Recurse
  Copy-Item -LiteralPath $probeSource -Destination (Join-Path $fixtureAddon 'restricted_probe_plugin.gd')
  $cfgPath = Join-Path $fixtureAddon 'plugin.cfg'
  $cfg = [System.IO.File]::ReadAllText($cfgPath)
  Assert-True ($cfg.Contains('script="plugin.gd"')) 'Canonical plugin.cfg has unexpected script entry.'
  [System.IO.File]::WriteAllText($cfgPath, $cfg.Replace('script="plugin.gd"', 'script="restricted_probe_plugin.gd"'))
  Write-JsonFile (Join-Path $fixtureAddon 'host_config.json') ([ordered]@{
    protocol_version = 'godot-codex-bridge/0.1'
    port = $port
    runtime = 'mock'
    node_entry = $hostEntry
    start_script = (Join-Path $productRoot 'scripts\start_codex_host.ps1')
  })
  New-Item -ItemType Directory -Path $requestsDir, $responsesDir -Force | Out-Null
  $evidence.checks.isolated_fixture = [ordered]@{ status = 'passed'; source = 'canonical addon'; source_addon_reparse_guard = 'passed'; preexisting_host = $false }

  $godotProcess = Start-Process -FilePath $godotItem.FullName -ArgumentList @('--path', $fixtureRoot, '--editor') -PassThru
  $evidence.process_ids.godot = $godotProcess.Id
  $heartbeatPath = Join-Path $bridgeDir 'heartbeat.json'
  $snapshotPath = Join-Path $bridgeDir 'context_snapshot.json'
  $deadline = [DateTime]::UtcNow.AddSeconds($StartupTimeoutSeconds)
  $startupReady = $false
  while ([DateTime]::UtcNow -lt $deadline) {
    Assert-True (-not $godotProcess.HasExited) "Owned Godot exited with code $($godotProcess.ExitCode)."
    if ((Test-Path -LiteralPath $heartbeatPath) -and (Test-Path -LiteralPath $snapshotPath)) {
      $ageMs = ([DateTime]::UtcNow - (Get-Item -LiteralPath $heartbeatPath).LastWriteTimeUtc).TotalMilliseconds
      if ($ageMs -lt 5000) { $startupReady = $true; break }
    }
    Start-Sleep -Milliseconds 300
  }
  Assert-True $startupReady 'Godot startup heartbeat or context snapshot did not become fresh.'
  $evidence.checks.startup = [ordered]@{ status = 'passed'; heartbeat = $heartbeatPath; snapshot = $snapshotPath }

  $layout = Invoke-FixtureRequest 'get_codex_chat_layout_status' @{}
  Assert-Response $layout 'succeeded' 'layout'
  Assert-True ([bool]$layout.data.input_visible_in_tree -and [bool]$layout.data.input_inside_chat_panel -and [bool]$layout.data.eye_button_visible_in_tree) 'Visible chat layout invariants failed.'
  Assert-True ($layout.data.host_config_status -eq 'manual_start_required' -and [int]$layout.data.host_config_port -eq $port) 'Fixture Host config was not recognized as manual-start.'
  $evidence.checks.layout.input_visible = [bool]$layout.data.input_visible_in_tree
  $evidence.checks.layout.eye_visible = [bool]$layout.data.eye_button_visible_in_tree

  # Before starting the Host, prove that the selected loopback port remains free
  # and the visible addon has not attached to a Host.
  $preHostListener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)
  try { $preHostListener.Start() } finally { $preHostListener.Stop() }
  Assert-True ([string]$layout.data.connection_state -ne 'ready') "Pre-Host addon connection state was $($layout.data.connection_state)."
  Assert-True ([string]$layout.data.active_project_root -eq '') 'Pre-Host addon unexpectedly had an active project attachment.'
  $preHostChat = Invoke-FixtureRequest 'send_codex_chat_message' @{ message = 'Pre-Host connection probe' }
  Assert-Response $preHostChat 'failed' 'pre_host_chat_denied'
  Assert-True ([string]$preHostChat.error.code -eq 'chat_host_not_connected') "Pre-Host chat failed with $($preHostChat.error.code) instead of chat_host_not_connected."
  $evidence.checks.pre_host = [ordered]@{
    status = 'passed'
    selected_port_bindable = $true
    connection_state = [string]$layout.data.connection_state
    active_project_root = [string]$layout.data.active_project_root
    godot_pid = $godotProcess.Id
  }

  $openedScene = Invoke-FixtureRequest 'open_scene' @{ scene_path = 'res://scenes/main_3d.tscn'; make_main_screen = '3D' }
  Assert-Response $openedScene 'succeeded' 'open_fixture_scene'
  $context = Invoke-FixtureRequest 'refresh_context' @{ requested_by = 'checkpoint_fixture_visible' }
  Assert-Response $context 'succeeded' 'context'
  Assert-True ([int]$context.data.scene_node_count -gt 0) 'Context contains no scene nodes.'
  $evidence.checks.context.scene_node_count = [int]$context.data.scene_node_count

  $toggleOff = Invoke-FixtureRequest 'fixture_set_screenshot_permission' @{ allowed = $false }
  Assert-Response $toggleOff 'succeeded' 'fixture_permission_off'
  $denied = Invoke-FixtureRequest 'capture_viewport_screenshot' @{}
  Assert-Response $denied 'failed' 'screenshot_denied'
  Assert-True ($denied.error.code -eq 'permission_denied') 'Screenshot denial did not use permission_denied.'
  $toggleOn = Invoke-FixtureRequest 'fixture_set_screenshot_permission' @{ allowed = $true }
  Assert-Response $toggleOn 'succeeded' 'fixture_permission_on'
  $allowed = Invoke-FixtureRequest 'capture_viewport_screenshot' @{}
  Assert-Response $allowed 'succeeded' 'screenshot_allowed'
  $shotPath = [string]$allowed.data.screenshot.artifact.local_path
  Assert-True ($shotPath -ne '' -and (Test-Path -LiteralPath $shotPath)) 'Allowed screenshot artifact missing.'
  $evidence.checks.screenshot_allowed.path = $shotPath
  $evidence.checks.screenshot_allowed.width = [int]$allowed.data.screenshot.artifact.width
  $evidence.checks.screenshot_allowed.height = [int]$allowed.data.screenshot.artifact.height

  $eye = Invoke-FixtureRequest 'fixture_eye_attach_probe' @{}
  Assert-Response $eye 'succeeded' 'fixture_eye_attach'
  Assert-True ([bool]$eye.data.capture_succeeded -and [bool]$eye.data.manifest_has_guardrails -and [bool]$eye.data.clear_removed_pending) 'Fixture-only Eye Attach assertions failed.'
  $evidence.checks.fixture_eye_attach.capture_scope = [string]$eye.data.capture_scope

  if ($TrustedStartup) {
    $powerShellSeven = Get-Command pwsh -ErrorAction SilentlyContinue
    Assert-True ($null -ne $powerShellSeven) 'Trusted startup fixture driver requires PowerShell 7 for BOM-free redirected approval input.'
    $launcherScript = Join-Path $productRoot 'scripts\start_codex_host.ps1'
    $launcherArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $launcherScript, '-ProjectRoot', $fixtureRoot, '-Runtime', 'mock', '-Port', [string]$port)
    $inspection = & $powerShellSeven.Source @launcherArgs -Inspect | ConvertFrom-Json
    Assert-True ([string]$inspection.fingerprint -match '^[a-f0-9]{64}$') 'Trusted launcher inspection did not return an installation fingerprint.'
    $evidence.checks.trusted_launcher = [ordered]@{ status = 'inspected'; fingerprint = $inspection.fingerprint; node_executable = $inspection.node_executable; host_entrypoint = $inspection.host_entrypoint; fixture_confirmation = 'simulated; not a human approval' }
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $powerShellSeven.Source
    $startInfo.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $launcherScript + '" -ProjectRoot "' + $fixtureRoot + '" -Runtime mock -Port ' + $port + ' -Start'
    $startInfo.WorkingDirectory = $productRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.StandardInputEncoding = [System.Text.UTF8Encoding]::new($false)
    $launcherProcess = [System.Diagnostics.Process]::new()
    $launcherProcess.StartInfo = $startInfo
    Assert-True ($launcherProcess.Start()) 'Trusted launcher process did not start.'
    $launcherProcess.StandardInput.WriteLine('START ' + $inspection.fingerprint)
    $launcherProcess.StandardInput.Flush()
    $evidence.process_ids.launcher = $launcherProcess.Id
    $readyTask = $launcherProcess.StandardOutput.ReadLineAsync()
    $readyDeadline = [DateTime]::UtcNow.AddSeconds(20)
    $readyLine = ''
    while ([DateTime]::UtcNow -lt $readyDeadline) {
      Assert-True (-not $launcherProcess.HasExited) "Trusted launcher exited early (code $($launcherProcess.ExitCode))."
      if ($readyTask.IsCompleted) {
        $line = [string]$readyTask.Result
        if ($line.StartsWith('HOST_READY ')) { $readyLine = $line; break }
        $readyTask = $launcherProcess.StandardOutput.ReadLineAsync()
      }
      Start-Sleep -Milliseconds 100
    }
    Assert-True ($readyLine -match '^HOST_READY pid=(\d+) port=(\d+) fingerprint=([a-f0-9]{64})$') 'Trusted launcher did not report its owned healthy Host.'
    Assert-True ([int]$Matches[2] -eq $port -and [string]$Matches[3] -eq [string]$inspection.fingerprint) 'Trusted launcher identity or port changed.'
    $evidence.process_ids.host = [int]$Matches[1]
    $evidence.checks.trusted_launcher.status = 'started'
  } else {
    $hostProcess = Start-Process -FilePath 'node' -ArgumentList @($hostEntry, '--runtime', 'mock', '--port', [string]$port) -WorkingDirectory $hostRoot -WindowStyle Hidden -PassThru
    $evidence.process_ids.host = $hostProcess.Id
  }
  $health = $null
  $deadline = [DateTime]::UtcNow.AddSeconds(15)
  while ([DateTime]::UtcNow -lt $deadline) {
    if ($TrustedStartup) { Assert-True (-not $launcherProcess.HasExited) "Trusted launcher exited with code $($launcherProcess.ExitCode)." }
    else { Assert-True (-not $hostProcess.HasExited) "Owned Host exited with code $($hostProcess.ExitCode)." }
    try { $health = Invoke-RestMethod -Uri "http://127.0.0.1:$port/health" -TimeoutSec 1; break } catch { Start-Sleep -Milliseconds 200 }
  }
  Assert-True ($null -ne $health -and [string]$health.runtime -eq 'mock' -and [int]$health.port -eq $port) 'Owned mock Host did not become healthy on its selected port.'
  $evidence.checks.host_health = [ordered]@{ status = 'passed'; response = $health }

  $connect = Invoke-FixtureRequest 'connect_codex_chat_host' @{}
  Assert-Response $connect 'succeeded' 'host_connect'
  $deadline = [DateTime]::UtcNow.AddSeconds($StartupTimeoutSeconds)
  $attached = $false
  while ([DateTime]::UtcNow -lt $deadline) {
    $layout = Invoke-FixtureRequest 'get_codex_chat_layout_status' @{}
    if ($layout.status -eq 'succeeded' -and [string]$layout.data.active_project_root -eq $fixtureRoot) { $attached = $true; break }
    Start-Sleep -Milliseconds 300
  }
  Assert-True $attached 'Mock Host did not attach the isolated fixture.'
  $evidence.checks.host_connect.active_project_root = [string]$layout.data.active_project_root
  if ($TrustedStartup) {
    $reconnect = Invoke-FixtureRequest 'connect_codex_chat_host' @{}
    Assert-Response $reconnect 'succeeded' 'host_reconnect'
    $reconnectedLayout = Invoke-FixtureRequest 'get_codex_chat_layout_status' @{}
    Assert-True ([string]$reconnectedLayout.data.active_project_root -eq $fixtureRoot) 'Trusted Host reconnect lost the fixture attachment.'
    $evidence.checks.host_reconnect = [ordered]@{ status = 'passed'; active_project_root = [string]$reconnectedLayout.data.active_project_root }
  }

  $eventPath = Join-Path $bridgeDir 'codex_host\events\host-events.jsonl'
  $eventCount = if (Test-Path -LiteralPath $eventPath) { @(Get-Content -LiteralPath $eventPath).Count } else { 0 }
  $beforeTurnLayout = Invoke-FixtureRequest 'get_codex_chat_layout_status' @{}
  Assert-Response $beforeTurnLayout 'succeeded' 'pre_turn_layout'
  $messageCountBefore = [int]$beforeTurnLayout.data.chat_message_count
  $chat = Invoke-FixtureRequest 'send_codex_chat_message' @{ message = 'Fixture-only mock chat turn'; attachments = @{ context_snapshot = $true; selected_nodes = $true; latest_screenshot = $false } }
  Assert-Response $chat 'succeeded' 'mock_chat_send'
  $deadline = [DateTime]::UtcNow.AddSeconds(20)
  $completed = $false
  while ([DateTime]::UtcNow -lt $deadline) {
    if (Test-Path -LiteralPath $eventPath) {
      foreach ($line in @(Get-Content -LiteralPath $eventPath | Select-Object -Skip $eventCount)) {
        try { $event = $line | ConvertFrom-Json } catch { continue }
        if ($event.method -eq 'turn.completed') { $completed = $true; break }
      }
    }
    if ($completed) { break }
    Start-Sleep -Milliseconds 250
  }
  Assert-True $completed 'Mock chat turn did not emit turn.completed.'
  $evidence.checks.mock_chat_send.turn_completed = $true
  $deadline = [DateTime]::UtcNow.AddSeconds(15)
  $transcriptUpdated = $false
  $afterTurnLayout = $null
  while ([DateTime]::UtcNow -lt $deadline) {
    $afterTurnLayout = Invoke-FixtureRequest 'get_codex_chat_layout_status' @{}
    if ($afterTurnLayout.status -eq 'succeeded' -and [int]$afterTurnLayout.data.chat_message_count -gt $messageCountBefore -and -not [bool]$afterTurnLayout.data.working_indicator_visible) {
      $transcriptUpdated = $true
      break
    }
    Start-Sleep -Milliseconds 250
  }
  $evidence.checks.mock_chat_send.chat_message_count_before = $messageCountBefore
  $evidence.checks.mock_chat_send.chat_message_count_after = if ($null -ne $afterTurnLayout) { [int]$afterTurnLayout.data.chat_message_count } else { $null }
  $evidence.checks.mock_chat_send.working_indicator_visible_after = if ($null -ne $afterTurnLayout) { [bool]$afterTurnLayout.data.working_indicator_visible } else { $null }
  Assert-True $transcriptUpdated 'Mock turn completed, but the visible transcript did not grow or the working indicator stayed on.'
  $evidence.status = 'passed'
} catch {
  $evidence.status = 'failed'
  $evidence.error = [string]$_.Exception.Message
} finally {
  $evidence.completed_at = [DateTime]::UtcNow.ToString('o')
  if ($null -ne $launcherProcess) {
    try {
      if (-not $launcherProcess.HasExited) {
        $launcherProcess.StandardInput.WriteLine('STOP')
        $launcherProcess.StandardInput.Flush()
        Assert-True ($launcherProcess.WaitForExit(10000)) 'Trusted launcher did not stop its owned Host after STOP.'
      }
      $evidence.process_ids.launcher_stopped = $launcherProcess.HasExited
    } catch {
      $evidence.process_ids.launcher_stop_error = [string]$_.Exception.Message
      $evidence.status = 'failed'
      $evidence.error = 'Trusted launcher cleanup failed: ' + [string]$_.Exception.Message
      try { if (-not $launcherProcess.HasExited) { $launcherProcess.Kill(); [void]$launcherProcess.WaitForExit(5000) } } catch { }
    }
    if ($port -gt 0) {
      $released = $false
      $releaseDeadline = [DateTime]::UtcNow.AddSeconds(5)
      while (-not $released -and [DateTime]::UtcNow -lt $releaseDeadline) {
        $probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $port)
        try { $probe.Start(); $released = $true } catch { Start-Sleep -Milliseconds 200 } finally { $probe.Stop() }
      }
      $evidence.process_ids.host_port_released = $released
      if (-not $released) { $evidence.status = 'failed'; $evidence.error = 'Trusted Host port remained occupied after launcher cleanup.' }
    }
    $launcherProcess.Dispose()
  }
  foreach ($entry in @(@{ name = 'godot'; process = $godotProcess }, @{ name = 'host'; process = $hostProcess })) {
    $owned = $entry.process
    if ($null -ne $owned) {
      try {
        if (-not $owned.HasExited) { $owned.Kill(); [void]$owned.WaitForExit(5000) }
        $evidence.process_ids[$entry.name + '_stopped'] = $owned.HasExited
      } catch { $evidence.process_ids[$entry.name + '_stop_error'] = [string]$_.Exception.Message }
    }
  }
  if (Test-Path -LiteralPath $fixtureRoot) { Write-JsonFile $reportPath $evidence }
}

$evidence | ConvertTo-Json -Depth 16
if ($evidence.status -ne 'passed') { exit 1 }
