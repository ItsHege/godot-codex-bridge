param(
  [string] $GodotExecutable = $(if ($env:GODOT_BIN) { $env:GODOT_BIN } elseif (Get-Command godot -ErrorAction SilentlyContinue) { (Get-Command godot).Source } else { "godot" }),
  [int] $HostPort = 49420
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Resolve-FullPath([string] $PathValue, [string] $BasePath) {
  if ([System.IO.Path]::IsPathRooted($PathValue)) {
    return [System.IO.Path]::GetFullPath($PathValue)
  }
  return [System.IO.Path]::GetFullPath((Join-Path $BasePath $PathValue))
}

function Resolve-HeadlessGodotExecutable([string] $GodotPath) {
  $directory = Split-Path -Parent $GodotPath
  $fileName = Split-Path -Leaf $GodotPath
  if ($fileName -notmatch "_console\.exe$") {
    $consoleName = $fileName -replace "\.exe$", "_console.exe"
    $consolePath = Join-Path $directory $consoleName
    if (Test-Path -LiteralPath $consolePath) {
      return $consolePath
    }
  }
  return $GodotPath
}

function Write-Utf8NoBom([string] $PathValue, [string] $Text) {
  $encoding = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($PathValue, $Text, $encoding)
}

function Invoke-JsonScript([string[]] $Arguments, [string] $OutputPath) {
  $output = & powershell -NoProfile -ExecutionPolicy Bypass @Arguments
  $exit = $LASTEXITCODE
  $text = ($output | Out-String).Trim()
  $text | Set-Content -LiteralPath $OutputPath -Encoding UTF8
  if ($exit -ne 0) {
    throw "Command failed with exit code $exit`: $($Arguments -join ' ')"
  }
  if ([string]::IsNullOrWhiteSpace($text)) {
    throw "Command produced no JSON output: $($Arguments -join ' ')"
  }
  return $text | ConvertFrom-Json
}

function Get-Sha256Hex([string] $PathValue) {
  $stream = [System.IO.File]::OpenRead($PathValue)
  try {
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
      $bytes = $sha.ComputeHash($stream)
      return ([System.BitConverter]::ToString($bytes)).Replace("-", "").ToLowerInvariant()
    } finally {
      $sha.Dispose()
    }
  } finally {
    $stream.Dispose()
  }
}

function Get-AddonFileHashes([string] $Root) {
  $rootFull = [System.IO.Path]::GetFullPath($Root)
  $rootPrefix = $rootFull.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
  $hashes = [ordered]@{}
  Get-ChildItem -LiteralPath $rootFull -Recurse -File |
    Sort-Object FullName |
    ForEach-Object {
      $fileFull = [System.IO.Path]::GetFullPath($_.FullName)
      if (-not $fileFull.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to hash file outside addon root: $fileFull"
      }
      $relative = $fileFull.Substring($rootPrefix.Length).Replace("\", "/")
      $hashes[$relative] = Get-Sha256Hex $_.FullName
    }
  return $hashes
}

function Compare-ExactHashSets($Expected, $Actual) {
  $missing = New-Object System.Collections.Generic.List[string]
  $mismatched = New-Object System.Collections.Generic.List[string]
  $extra = New-Object System.Collections.Generic.List[string]
  foreach ($key in $Expected.Keys) {
    if (-not $Actual.Contains($key)) {
      $missing.Add($key) | Out-Null
    } elseif ($Actual[$key] -ne $Expected[$key]) {
      $mismatched.Add($key) | Out-Null
    }
  }
  foreach ($key in $Actual.Keys) {
    if (-not $Expected.Contains($key)) {
      $extra.Add($key) | Out-Null
    }
  }
  return [ordered]@{
    ok = ($missing.Count -eq 0 -and $mismatched.Count -eq 0 -and $extra.Count -eq 0)
    missing = @($missing.ToArray())
    mismatched = @($mismatched.ToArray())
    extra = @($extra.ToArray())
  }
}

function Compare-ExpectedSubset($Expected, $Actual) {
  $missing = New-Object System.Collections.Generic.List[string]
  $mismatched = New-Object System.Collections.Generic.List[string]
  $extra = New-Object System.Collections.Generic.List[string]
  foreach ($key in $Expected.Keys) {
    if (-not $Actual.Contains($key)) {
      $missing.Add($key) | Out-Null
    } elseif ($Actual[$key] -ne $Expected[$key]) {
      $mismatched.Add($key) | Out-Null
    }
  }
  foreach ($key in $Actual.Keys) {
    if (-not $Expected.Contains($key)) {
      $extra.Add($key) | Out-Null
    }
  }
  return [ordered]@{
    ok = ($missing.Count -eq 0 -and $mismatched.Count -eq 0)
    missing = @($missing.ToArray())
    mismatched = @($mismatched.ToArray())
    extra = @($extra.ToArray())
  }
}

function Assert-True([bool] $Condition, [string] $Message) {
  if (-not $Condition) {
    throw $Message
  }
}

function Invoke-GodotCheckOnly([string] $Executable, [string] $ProjectRoot, [string] $StdoutPath, [string] $StderrPath, [int] $TimeoutMilliseconds) {
  if (Test-Path -LiteralPath $StdoutPath) {
    Remove-Item -LiteralPath $StdoutPath -Force
  }
  if (Test-Path -LiteralPath $StderrPath) {
    Remove-Item -LiteralPath $StderrPath -Force
  }
  $process = Start-Process `
    -FilePath $Executable `
    -ArgumentList @("--headless", "--path", $ProjectRoot, "--check-only", "--quit") `
    -PassThru `
    -WindowStyle Hidden `
    -RedirectStandardOutput $StdoutPath `
    -RedirectStandardError $StderrPath
  if (-not $process.WaitForExit($TimeoutMilliseconds)) {
    try {
      $process.Kill()
    } catch {
    }
    Get-CimInstance Win32_Process |
      Where-Object { $_.Name -like "*Godot*" -and $_.CommandLine -like "*$ProjectRoot*" } |
      ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    throw "Godot --check-only timed out after $([int]($TimeoutMilliseconds / 1000)) seconds."
  }
  return [ordered]@{
    exit_code = $process.ExitCode
    stdout_path = $StdoutPath
    stderr_path = $StderrPath
  }
}

$productRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$productRootPath = $productRoot.Path
$resolvedGodot = Resolve-FullPath $GodotExecutable (Get-Location).Path
$resolvedHeadlessGodot = Resolve-HeadlessGodotExecutable $resolvedGodot
$canonicalAddon = Join-Path $productRootPath "addons\godot_codex_bridge"
$artifactsRoot = Join-Path $productRootPath ".godot\godot_codex_bridge\artifacts\external_project_install_smoke"
$runId = "external_install_" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$runRoot = Join-Path $artifactsRoot $runId
$packageOutputRoot = Join-Path $runRoot "package"
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) "godot-codex-bridge-external-install\$runId"
$tempProjectRoot = Join-Path $tempRoot "external_project"
$reportsDir = Join-Path $runRoot "reports"
$reportPath = Join-Path $reportsDir "external_project_install_smoke_validation.json"
$packageReportPath = Join-Path $reportsDir "package_addon_report.json"
$installDryRunReportPath = Join-Path $reportsDir "install_addon_dry_run_report.json"
$installApplyReportPath = Join-Path $reportsDir "install_addon_apply_report.json"
$installVerifyReportPath = Join-Path $reportsDir "install_addon_verify_report.json"
$installRollbackStdoutPath = Join-Path $reportsDir "install_addon_rollback_stdout.txt"
$installRollbackStderrPath = Join-Path $reportsDir "install_addon_rollback_stderr.txt"

if (-not (Test-Path -LiteralPath $resolvedHeadlessGodot)) {
  throw "Godot executable not found: $resolvedHeadlessGodot"
}
if (-not (Test-Path -LiteralPath (Join-Path $canonicalAddon "plugin.cfg"))) {
  throw "Canonical addon is missing plugin.cfg: $canonicalAddon"
}

New-Item -ItemType Directory -Force -Path $tempProjectRoot, $reportsDir | Out-Null

$projectGodot = @'
; Generated by validate_external_project_install_smoke.ps1.
; This is a bounded local smoke fixture, not a user project.

config_version=5

[application]

config/name="Godot Codex Bridge External Install Smoke"
run/main_scene="res://scenes/main.tscn"
config/features=PackedStringArray("4.7", "Forward Plus")

[editor_plugins]

enabled=PackedStringArray("res://addons/godot_codex_bridge/plugin.cfg")

[rendering]

renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
'@
Write-Utf8NoBom (Join-Path $tempProjectRoot "project.godot") $projectGodot
New-Item -ItemType Directory -Force -Path (Join-Path $tempProjectRoot "scenes") | Out-Null
$mainScene = @'
[gd_scene format=3 uid="uid://gcb_external_install_smoke"]

[node name="ExternalInstallSmoke" type="Node3D"]
'@
Write-Utf8NoBom (Join-Path $tempProjectRoot "scenes\main.tscn") $mainScene

$summary = [ordered]@{
  status = "started"
  started_at = (Get-Date).ToUniversalTime().ToString("o")
  run_id = $runId
  project_root = $tempProjectRoot
  temp_root = $tempRoot
  generated_project = $true
  real_external_project_mutation = $false
  godot_executable = $resolvedHeadlessGodot
  report_path = $reportPath
  package_report_path = $packageReportPath
  install_dry_run_report_path = $installDryRunReportPath
  install_apply_report_path = $installApplyReportPath
  install_verify_report_path = $installVerifyReportPath
}

Push-Location $productRootPath
try {
  $package = Invoke-JsonScript @(
    "-File", "scripts\package_addon.ps1",
    "-OutputRoot", $packageOutputRoot,
    "-NoZip"
  ) $packageReportPath
  Assert-True ($package.status -eq "ok") "package_addon report status was not ok."
  Assert-True (Test-Path -LiteralPath $package.package_addon_path) "Package addon path does not exist."

  $installDryRun = Invoke-JsonScript @(
    "-File", "scripts\install_addon.ps1",
    "-ProjectRoot", $tempProjectRoot,
    "-SourceAddon", $package.package_addon_path,
    "-HostRuntime", "mock",
    "-HostPort", [string]$HostPort
  ) $installDryRunReportPath
  Assert-True ($installDryRun.status -eq "ok") "install_addon dry-run report status was not ok."
  Assert-True ([bool]$installDryRun.apply_required_for_copy) "install_addon dry-run should not copy files."
  Assert-True ($installDryRun.readiness -eq "addon_not_installed") "install_addon dry-run did not detect addon_not_installed."

  $installApply = Invoke-JsonScript @(
    "-File", "scripts\install_addon.ps1",
    "-ProjectRoot", $tempProjectRoot,
    "-SourceAddon", $package.package_addon_path,
    "-Apply",
    "-HostRuntime", "mock",
    "-HostPort", [string]$HostPort
  ) $installApplyReportPath
  Assert-True ($installApply.status -eq "ok") "install_addon apply report status was not ok."
  Assert-True ($installApply.action -eq "installed") "install_addon apply action was not installed."
  Assert-True ([bool]$installApply.checks.target_plugin_cfg_exists) "Installed addon plugin.cfg was missing."
  Assert-True ([bool]$installApply.checks.target_host_config_exists) "Installed addon host_config.json was missing."
  Assert-True ([bool]$installApply.checks.plugin_enabled) "Generated external project did not report plugin enabled."

  $installVerify = Invoke-JsonScript @(
    "-File", "scripts\install_addon.ps1",
    "-ProjectRoot", $tempProjectRoot,
    "-SourceAddon", $package.package_addon_path,
    "-HostRuntime", "mock",
    "-HostPort", [string]$HostPort
  ) $installVerifyReportPath
  Assert-True ($installVerify.status -eq "ok") "install_addon verify report status was not ok."
  Assert-True ($installVerify.readiness -eq "editor_not_active") "install_addon verify readiness should be editor_not_active for generated closed project."
  Assert-True ([bool]$installVerify.checks.plugin_enabled) "install_addon verify did not see plugin enabled."

  $targetAddon = Join-Path $tempProjectRoot "addons\godot_codex_bridge"
  $rollbackProbePath = Join-Path $targetAddon "rollback_probe.txt"
  Write-Utf8NoBom $rollbackProbePath "rollback probe"
  $rollbackBeforeHashes = Get-AddonFileHashes $targetAddon
  $rollbackProcess = Start-Process `
    -FilePath "powershell" `
    -ArgumentList @(
      "-NoProfile",
      "-ExecutionPolicy", "Bypass",
      "-File", (Join-Path $productRootPath "scripts\install_addon.ps1"),
      "-ProjectRoot", $tempProjectRoot,
      "-SourceAddon", $package.package_addon_path,
      "-Apply",
      "-Replace",
      "-SimulateFailureAfterBackupForTest",
      "-HostRuntime", "mock",
      "-HostPort", [string]$HostPort
    ) `
    -PassThru `
    -WindowStyle Hidden `
    -Wait `
    -RedirectStandardOutput $installRollbackStdoutPath `
    -RedirectStandardError $installRollbackStderrPath
  Assert-True ([int]$rollbackProcess.ExitCode -ne 0) "Simulated installer failure unexpectedly succeeded."
  $rollbackAfterHashes = Get-AddonFileHashes $targetAddon
  $rollbackParity = Compare-ExactHashSets $rollbackBeforeHashes $rollbackAfterHashes
  Assert-True ([bool]$rollbackParity.ok) "Installer rollback did not restore the exact previous addon."
  $stagingResidue = @(
    Get-ChildItem -LiteralPath (Join-Path $tempProjectRoot "addons") -Directory -Force |
      Where-Object { $_.Name -like ".godot_codex_bridge.install.*" }
  )
  Assert-True ($stagingResidue.Count -eq 0) "Installer rollback left a staging directory behind."
  Remove-Item -LiteralPath $rollbackProbePath -Force

  $sourceHashes = Get-AddonFileHashes $canonicalAddon
  $packageHashes = Get-AddonFileHashes $package.package_addon_path
  $targetHashes = Get-AddonFileHashes $targetAddon
  $sourcePackageParity = Compare-ExactHashSets $sourceHashes $packageHashes
  $packageTargetParity = Compare-ExpectedSubset $packageHashes $targetHashes
  Assert-True ([bool]$sourcePackageParity.ok) "Canonical addon and packaged addon SHA parity failed."
  Assert-True ([bool]$packageTargetParity.ok) "Packaged addon and installed addon SHA parity failed."

  $stdoutPath = Join-Path $reportsDir "godot_check_only_stdout.txt"
  $stderrPath = Join-Path $reportsDir "godot_check_only_stderr.txt"
  $godotCheck = Invoke-GodotCheckOnly $resolvedHeadlessGodot $tempProjectRoot $stdoutPath $stderrPath 60000
  Assert-True ([int]$godotCheck.exit_code -eq 0) "Godot --check-only failed with exit code $($godotCheck.exit_code)."

  $summary["status"] = "ok"
  $summary["completed_at"] = (Get-Date).ToUniversalTime().ToString("o")
  $summary["package"] = [ordered]@{
    addon_version = $package.addon_version
    package_root = $package.package_root
    package_addon_path = $package.package_addon_path
    manifest_path = $package.manifest_path
    validation_report_count = $package.validation_report_count
  }
  $summary["install"] = [ordered]@{
    dry_run_readiness = $installDryRun.readiness
    apply_action = $installApply.action
    apply_readiness = $installApply.readiness
    verify_readiness = $installVerify.readiness
    plugin_cfg_exists = [bool]$installApply.checks.target_plugin_cfg_exists
    host_config_exists = [bool]$installApply.checks.target_host_config_exists
    plugin_enabled = [bool]$installVerify.checks.plugin_enabled
    target_addon_path = $installApply.target_addon_path
    target_host_config_path = $installApply.target_host_config_path
    simulated_failure_exit_code = [int]$rollbackProcess.ExitCode
    rollback_exact_restore = [bool]$rollbackParity.ok
    rollback_staging_residue_count = $stagingResidue.Count
  }
  $summary["sha_parity"] = [ordered]@{
    source_package = $sourcePackageParity
    package_target = $packageTargetParity
    package_file_count = $packageHashes.Count
    target_extra_files = @($packageTargetParity.extra)
  }
  $summary["godot_check_only"] = [ordered]@{
    exit_code = [int]$godotCheck.exit_code
    stdout_path = $godotCheck.stdout_path
    stderr_path = $godotCheck.stderr_path
  }
  if (Test-Path -LiteralPath $tempRoot) {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force
  }
  $summary["temp_cleanup"] = [ordered]@{
    removed = -not (Test-Path -LiteralPath $tempRoot)
    path = $tempRoot
  }
  $summary | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $reportPath -Encoding UTF8
  $summary | ConvertTo-Json -Depth 16
} catch {
  $summary["status"] = "failed"
  $summary["completed_at"] = (Get-Date).ToUniversalTime().ToString("o")
  $summary["error"] = [string]$_.Exception.Message
  $summary | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $reportPath -Encoding UTF8
  throw
} finally {
  Pop-Location
}
