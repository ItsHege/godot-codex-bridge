param(
  [string] $GodotExecutable = $(if ($env:GODOT_BIN) { $env:GODOT_BIN } else { "C:\AI\Tools\Godot\Godot_console.exe" })
)

$ErrorActionPreference = "Stop"
$productRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$projectRoot = Join-Path $productRoot "examples\minimal_3d_project"
$runId = [guid]::NewGuid().ToString("N")
$testRoot = Join-Path $projectRoot ".godot\godot_codex_bridge\claim_race_$runId"
$journalDir = Join-Path $testRoot "journal"
New-Item -ItemType Directory -Force -Path $journalDir | Out-Null
$now = [DateTime]::UtcNow
$env:GCB_JOURNAL_RACE_DIR = $journalDir
$env:GCB_JOURNAL_RACE_REQUEST_JSON = (@{
  request_id = [guid]::NewGuid().ToString()
  type = "test"
  created_at = $now.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
  deadline_at = $now.AddMinutes(1).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
  payload = @{}
} | ConvertTo-Json -Compress)
try {
  $scriptPath = Join-Path $productRoot "tests\fixture\test_request_claim_race.gd"
  $processes = @()
  foreach ($index in 1..2) {
    $stdout = Join-Path $testRoot "worker_$index.out"
    $stderr = Join-Path $testRoot "worker_$index.err"
    $processes += Start-Process -FilePath $GodotExecutable -ArgumentList @("--headless", "--path", $projectRoot, "--script", $scriptPath) -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
  }
  foreach ($process in $processes) {
    $process.WaitForExit(30000) | Out-Null
    if (-not $process.HasExited) {
      Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
      throw "Godot claim worker timed out."
    }
    $process.Refresh()
    if ($null -ne $process.ExitCode -and $process.ExitCode -ne 0) { throw "Godot claim worker failed: $($process.ExitCode)" }
  }
  $states = @(1..2 | ForEach-Object { (Get-Content -LiteralPath (Join-Path $testRoot "worker_$_.out") | Select-String "CLAIM_RACE_STATE=").ToString().Split("=")[1] })
  if (($states | Where-Object { $_ -eq "claimed" }).Count -ne 1 -or ($states | Where-Object { $_ -eq "outcome_unknown" }).Count -ne 1) {
    throw "Expected one claim and one refusal; got $($states -join ', '). Evidence: $testRoot"
  }
  @{ status = "ok"; states = $states; evidence_dir = $testRoot } | ConvertTo-Json -Compress
} finally {
  Remove-Item Env:GCB_JOURNAL_RACE_DIR -ErrorAction SilentlyContinue
  Remove-Item Env:GCB_JOURNAL_RACE_REQUEST_JSON -ErrorAction SilentlyContinue
}
