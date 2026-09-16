param(
  [string] $ProjectRoot = "examples\minimal_3d_project",
  [string] $GodotExecutable = $(if ($env:GODOT_BIN) { $env:GODOT_BIN } elseif (Get-Command godot -ErrorAction SilentlyContinue) { (Get-Command godot).Source } else { "godot" }),
  [int] $Port = 49420,
  [int] $Cycles = 4,
  [int] $StartupTimeoutSeconds = 45,
  [int] $ShutdownTimeoutSeconds = 20,
  [int] $RequestTimeoutSeconds = 10
)

$ErrorActionPreference = "Stop"

function Resolve-FullPath([string] $PathValue, [string] $BasePath) {
  if ([System.IO.Path]::IsPathRooted($PathValue)) {
    return [System.IO.Path]::GetFullPath($PathValue)
  }
  return [System.IO.Path]::GetFullPath((Join-Path $BasePath $PathValue))
}

function Get-ListeningProcessIds([int] $PortValue) {
  try {
    return @(
      Get-NetTCPConnection -LocalPort $PortValue -State Listen -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty OwningProcess -Unique
    )
  } catch {
    return @()
  }
}

function Test-ProcessRunning([int] $ProcessId) {
  if ($ProcessId -le 0) {
    return $false
  }
  try {
    $process = Get-Process -Id $ProcessId -ErrorAction Stop
    return -not $process.HasExited
  } catch {
    return $false
  }
}

function Send-BridgeRequest([string] $Type, [hashtable] $Payload, [string] $RequestsDir, [string] $ResponsesDir, [int] $TimeoutSeconds) {
  $id = [guid]::NewGuid().ToString()
  $requestPath = Join-Path $RequestsDir "$id.json"
  $responsePath = Join-Path $ResponsesDir "$id.json"
  $request = [ordered]@{
    protocol_version = "godot-codex-bridge/0.1"
    request_id = $id
    type = $Type
    created_at = (Get-Date).ToUniversalTime().ToString("o")
    payload = $Payload
  }
  $request | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $requestPath -Encoding UTF8

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    if (Test-Path -LiteralPath $responsePath) {
      $raw = Get-Content -Raw -LiteralPath $responsePath
      return [ordered]@{
        request_path = $requestPath
        response_path = $responsePath
        response = ($raw | ConvertFrom-Json)
        timeout = $false
      }
    }
    Start-Sleep -Milliseconds 250
  }

  return [ordered]@{
    request_path = $requestPath
    response_path = $responsePath
    response = $null
    timeout = $true
  }
}

function Invoke-RetryBridgeRequest([string] $Type, [hashtable] $Payload, [string] $RequestsDir, [string] $ResponsesDir, [int] $TimeoutSeconds, [int] $Retries) {
  $last = $null
  for ($i = 0; $i -lt $Retries; $i++) {
    $last = Send-BridgeRequest $Type $Payload $RequestsDir $ResponsesDir $TimeoutSeconds
    if ($last.response -ne $null -and $last.response.status -eq "succeeded") {
      return $last
    }
    Start-Sleep -Seconds 1
  }
  return $last
}

function Wait-Heartbeat([string] $HeartbeatPath, [int] $TimeoutSeconds) {
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    if (Test-Path -LiteralPath $HeartbeatPath) {
      $ageMs = [int64](((Get-Date).ToUniversalTime() - (Get-Item -LiteralPath $HeartbeatPath).LastWriteTimeUtc).TotalMilliseconds)
      if ($ageMs -le 5000) {
        return $ageMs
      }
    }
    Start-Sleep -Milliseconds 500
  }
  return $null
}

function Wait-HostPid([string] $RequestsDir, [string] $ResponsesDir, [int] $TimeoutSeconds, [int] $RequestTimeoutSeconds) {
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  $lastLayout = $null
  while ((Get-Date) -lt $deadline) {
    $layout = Invoke-RetryBridgeRequest "get_codex_chat_layout_status" @{} $RequestsDir $ResponsesDir $RequestTimeoutSeconds 1
    $lastLayout = $layout
    if ($layout.response -ne $null -and $layout.response.status -eq "succeeded" -and $layout.response.data -ne $null) {
      $hostProcessId = [int]$layout.response.data.host_process_id
      $owned = [bool]$layout.response.data.host_process_owned_by_addon
      if ($hostProcessId -gt 0 -and $owned -and (Test-ProcessRunning $hostProcessId)) {
        return [ordered]@{
          pid = $hostProcessId
          layout = $layout
        }
      }
    }
    Start-Sleep -Milliseconds 500
  }
  return [ordered]@{
    pid = -1
    layout = $lastLayout
  }
}

function Wait-ProcessStopped([int] $ProcessId, [int] $TimeoutSeconds) {
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    if (-not (Test-ProcessRunning $ProcessId)) {
      return $true
    }
    Start-Sleep -Milliseconds 500
  }
  return -not (Test-ProcessRunning $ProcessId)
}

function Wait-CleanupEvidence([string] $CleanupDir, [int] $ProcessId, [int] $TimeoutSeconds) {
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    if (Test-Path -LiteralPath $CleanupDir) {
      $files = @(
        Get-ChildItem -LiteralPath $CleanupDir -Filter "owned-host-cleanup-*.json" -ErrorAction SilentlyContinue |
          Sort-Object LastWriteTimeUtc -Descending
      )
      foreach ($file in $files) {
        try {
          $payload = Get-Content -Raw -LiteralPath $file.FullName | ConvertFrom-Json
          if ([int]$payload.process_id -eq $ProcessId) {
            return [ordered]@{
              path = $file.FullName
              payload = $payload
            }
          }
        } catch {
        }
      }
    }
    Start-Sleep -Milliseconds 500
  }
  return $null
}

$productRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$productRootPath = $productRoot.Path
$resolvedProjectRoot = Resolve-FullPath $ProjectRoot $productRootPath
$resolvedGodot = Resolve-FullPath $GodotExecutable (Get-Location).Path
$bridgeDir = Join-Path $resolvedProjectRoot ".godot\godot_codex_bridge"
$requestsDir = Join-Path $bridgeDir "requests"
$responsesDir = Join-Path $bridgeDir "responses"
$heartbeatPath = Join-Path $bridgeDir "heartbeat.json"
$cleanupDir = Join-Path $bridgeDir "artifacts\codex_host_cleanup"
$reportPath = Join-Path $bridgeDir "artifacts\host_cleanup_cycles_validation.json"

if (-not (Test-Path -LiteralPath (Join-Path $resolvedProjectRoot "project.godot"))) {
  throw "Project root does not contain project.godot: $resolvedProjectRoot"
}
if (-not (Test-Path -LiteralPath $resolvedGodot)) {
  throw "Godot executable not found: $resolvedGodot"
}
if ($Cycles -lt 1) {
  throw "Cycles must be at least 1."
}

Push-Location $productRootPath
try {
  & ".\scripts\install_addon.ps1" -ProjectRoot $resolvedProjectRoot -Apply -Replace -HostRuntime mock -HostPort $Port | Write-Output
} finally {
  Pop-Location
}

New-Item -ItemType Directory -Force -Path $requestsDir | Out-Null
New-Item -ItemType Directory -Force -Path $responsesDir | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $reportPath) | Out-Null

$preExistingListeners = @(Get-ListeningProcessIds $Port)
if ($preExistingListeners.Count -gt 0) {
  throw "Port $Port is already listening before cleanup cycle validation: $($preExistingListeners -join ', ')."
}

$result = [ordered]@{
  status = "started"
  started_at = (Get-Date).ToUniversalTime().ToString("o")
  project_root = $resolvedProjectRoot
  godot_executable = $resolvedGodot
  host_port = $Port
  cycles_requested = $Cycles
  cycles = @()
  report_path = $reportPath
}
$activeGodotProcess = $null

try {
  for ($cycle = 1; $cycle -le $Cycles; $cycle++) {
    $cycleResult = [ordered]@{
      cycle = $cycle
      godot_process_id = -1
      host_process_id = -1
      heartbeat_age_ms = $null
      host_running_before_close = $false
      godot_exit_code = $null
      host_stopped_after_close = $false
      port_listeners_after_close = @()
      cleanup_evidence_path = ""
    }

    $godotProcess = Start-Process -FilePath $resolvedGodot -ArgumentList @("--path", $resolvedProjectRoot, "--editor") -PassThru
    $activeGodotProcess = $godotProcess
    $cycleResult.godot_process_id = $godotProcess.Id

    $heartbeatAge = Wait-Heartbeat $heartbeatPath $StartupTimeoutSeconds
    if ($null -eq $heartbeatAge) {
      throw "Cycle ${cycle}: Godot editor heartbeat did not become live within $StartupTimeoutSeconds seconds."
    }
    $cycleResult.heartbeat_age_ms = $heartbeatAge

    $hostState = Wait-HostPid $requestsDir $responsesDir $StartupTimeoutSeconds $RequestTimeoutSeconds
    $hostPid = [int]$hostState.pid
    if ($hostPid -le 0) {
      throw "Cycle ${cycle}: addon-owned Codex Host process did not start."
    }
    $cycleResult.host_process_id = $hostPid
    $cycleResult.host_running_before_close = Test-ProcessRunning $hostPid
    if (-not $cycleResult.host_running_before_close) {
      throw "Cycle ${cycle}: Codex Host PID $hostPid was not running before closing Godot."
    }

    if (-not $godotProcess.HasExited) {
      $godotProcess.CloseMainWindow() | Out-Null
    }
    if (-not $godotProcess.WaitForExit($ShutdownTimeoutSeconds * 1000)) {
      Stop-Process -Id $godotProcess.Id -Force -ErrorAction SilentlyContinue
      throw "Cycle ${cycle}: Godot did not close within $ShutdownTimeoutSeconds seconds."
    }
    $cycleResult.godot_exit_code = $godotProcess.ExitCode

    $cycleResult.host_stopped_after_close = Wait-ProcessStopped $hostPid $ShutdownTimeoutSeconds
    $cycleResult.port_listeners_after_close = @(Get-ListeningProcessIds $Port)
    if (-not $cycleResult.host_stopped_after_close) {
      throw "Cycle ${cycle}: addon-owned Codex Host PID $hostPid remained running after Godot closed."
    }
    if ($cycleResult.port_listeners_after_close.Count -gt 0) {
      throw "Cycle ${cycle}: port $Port still has listeners after Godot close: $($cycleResult.port_listeners_after_close -join ', ')."
    }

    $cleanupEvidence = Wait-CleanupEvidence $cleanupDir $hostPid $ShutdownTimeoutSeconds
    if ($null -eq $cleanupEvidence) {
      throw "Cycle ${cycle}: cleanup evidence was not written for addon-owned host PID $hostPid."
    }
    $cycleResult.cleanup_evidence_path = [string]$cleanupEvidence.path
    $cleanupPayload = $cleanupEvidence.payload
    if (
      [string]$cleanupPayload.reason -ne "plugin_exit" -or
      -not [bool]$cleanupPayload.owned_by_addon -or
      [bool]$cleanupPayload.process_alive_after
    ) {
      throw "Cycle ${cycle}: cleanup evidence for PID $hostPid did not prove plugin_exit owned cleanup. Path=$($cycleResult.cleanup_evidence_path)"
    }

    $activeGodotProcess = $null
    $result.cycles += $cycleResult
    Start-Sleep -Seconds 1
  }

  $result.status = "ok"
  $result.completed_at = (Get-Date).ToUniversalTime().ToString("o")
  $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportPath -Encoding UTF8
  $result | ConvertTo-Json -Depth 12
} catch {
  $result.status = "failed"
  $result.error = $_.Exception.Message
  $result.completed_at = (Get-Date).ToUniversalTime().ToString("o")
  $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportPath -Encoding UTF8
  throw
} finally {
  if ($activeGodotProcess -ne $null) {
    try {
      if (-not $activeGodotProcess.HasExited) {
        $activeGodotProcess.CloseMainWindow() | Out-Null
        if (-not $activeGodotProcess.WaitForExit(5000)) {
          Stop-Process -Id $activeGodotProcess.Id -Force -ErrorAction SilentlyContinue
        }
      }
    } catch {
    }
  }
  foreach ($listenerPid in @(Get-ListeningProcessIds $Port)) {
    Stop-Process -Id $listenerPid -Force -ErrorAction SilentlyContinue
  }
}
