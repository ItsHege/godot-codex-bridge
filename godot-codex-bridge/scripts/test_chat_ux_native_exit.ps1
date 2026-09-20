# Focused orchestration regression: shadow the two native command names in this
# test process. Stubs run harmless Node child processes with explicit exit codes.
# Never installs an addon, runs Godot/npm, or opens a real session.
param()
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$productRoot = Split-Path -Parent $PSScriptRoot
$fixtureRoot = Join-Path $productRoot (".tmp_validation/chat-native-exits-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $fixtureRoot -Force | Out-Null
$targetScript = Join-Path $PSScriptRoot "validate_chat_ux_regression.ps1"
$stepNames = @("install_mock_addon", "addon_core", "restore_mock_host_config", "visible_chat_editor")
$results = New-Object 'System.Collections.Generic.List[object]'
$global:GcbExitTestNode = (Get-Command node -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$global:GcbExitTestNativeCount = 0

function Invoke-FakeNative {
  $global:GcbExitTestCallCount += 1
  if ($global:GcbExitTestCallCount -eq $global:GcbExitTestFailureAt) {
    if ($global:GcbExitTestMissingCode) { return }
    $nativeCode = 23
  } else { $nativeCode = 0 }
  $global:GcbExitTestNativeCount += 1
  & $global:GcbExitTestNode -e "process.exit($nativeCode)"
}
function powershell { Invoke-FakeNative }
function npm { Invoke-FakeNative }
function Assert-True([bool] $Condition, [string] $Message) {
  if (-not $Condition) { throw $Message }
}

foreach ($caseNumber in 1..6) {
  $global:GcbExitTestCallCount = 0
  $global:GcbExitTestMissingCode = ($caseNumber -eq 5)
  $global:GcbExitTestFailureAt = if ($caseNumber -le 4) { $caseNumber } elseif ($caseNumber -eq 5) { 1 } else { 0 }
  $projectRoot = Join-Path $fixtureRoot ("case-" + $caseNumber)
  $artifacts = Join-Path $projectRoot ".godot/godot_codex_bridge/artifacts"
  New-Item -ItemType Directory -Path $artifacts -Force | Out-Null
  if ($caseNumber -le 5) {
    # An old success report must not hide a failing current native command.
    [IO.File]::WriteAllText((Join-Path $artifacts "visible_chat_editor_validation.json"), '{"status":"ok"}')
  }
  $caught = $null
  try { & $targetScript -ProjectRoot $projectRoot | Out-Null } catch { $caught = $_ }
  Assert-True ($null -ne $caught) "Case $caseNumber did not stop."
  $report = Get-Content -Raw -LiteralPath (Join-Path $artifacts "chat_ux_regression_validation.json") | ConvertFrom-Json
  Assert-True ($report.status -eq "failed") "Case $caseNumber wrote false success."
  if ($caseNumber -le 5) {
    $failedStep = $stepNames[$global:GcbExitTestFailureAt - 1]
    Assert-True ($global:GcbExitTestCallCount -eq $global:GcbExitTestFailureAt) "Commands continued after failure."
    $failedEntries = @($report.steps | Where-Object { $_.name -eq $failedStep })
    Assert-True ($failedEntries.Count -eq 1 -and $failedEntries[0].status -eq "failed") "Failed command was marked ok."
    if ($caseNumber -eq 5) {
      Assert-True ($null -eq $failedEntries[0].details.exit_code) "Missing native status was invented."
    } else {
      Assert-True ($failedEntries[0].details.exit_code -eq 23) "Native exit code not preserved."
    }
    $results.Add([pscustomobject]@{ case = $caseNumber; step = $failedStep; status = "pass" })
  } else {
    Assert-True ($global:GcbExitTestCallCount -eq 4) "Zero exits did not progress through all commands."
    Assert-True (@($report.steps | Where-Object { $_.status -eq "ok" }).Count -eq 4) "Successful native steps changed."
    Assert-True ($report.error -like "Visible chat editor report was not written:*") "Zero exits did not reach existing artifact gate."
    $results.Add([pscustomobject]@{ case = $caseNumber; step = "zero_exits_reach_report_gate"; status = "pass" })
  }
}
[ordered]@{ status = "ok"; test_count = $results.Count; tests = @($results.ToArray()); fixture_root = $fixtureRoot; native_stub_processes = $global:GcbExitTestNativeCount; product_commands_run = 0 } | ConvertTo-Json -Depth 5
$global:LASTEXITCODE = 0
