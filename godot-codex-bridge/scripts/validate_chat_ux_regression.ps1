param(
  [string] $ProjectRoot = "examples\minimal_3d_project",
  [int] $Port = 49396,
  [int] $AppServerPort = 49397,
  [int] $StartupTimeoutSeconds = 45,
  [int] $RequestTimeoutSeconds = 20,
  [int] $TurnTimeoutSeconds = 180
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Resolve-FullPath([string] $PathValue, [string] $BasePath) {
  if ([System.IO.Path]::IsPathRooted($PathValue)) {
    return [System.IO.Path]::GetFullPath($PathValue)
  }
  return [System.IO.Path]::GetFullPath((Join-Path $BasePath $PathValue))
}

function Add-Step([string] $Name, [string] $Status, [hashtable] $Details = @{}) {
  $script:ValidationSteps.Add([ordered]@{
    name = $Name
    status = $Status
    details = $Details
  }) | Out-Null
}

function Assert-True([bool] $Condition, [string] $Message) {
  if (-not $Condition) {
    throw $Message
  }
}

function Get-Number($Value) {
  if ($null -eq $Value) {
    return 0.0
  }
  return [double]$Value
}

function Assert-StableComposer($Visible, [string] $Prefix) {
  $inputVisibleField = if ($Prefix -eq "") { "chat_input_visible" } else { "$Prefix`_chat_input_visible" }
  $inputInsideField = if ($Prefix -eq "") { "chat_input_inside_panel" } else { "$Prefix`_chat_input_inside_panel" }
  $logInsideField = if ($Prefix -eq "") { "chat_log_inside_panel" } else { "$Prefix`_chat_log_inside_panel" }
  $composerBelowField = if ($Prefix -eq "") { "chat_composer_below_log" } else { "$Prefix`_chat_composer_below_log" }
  $approvalAboveField = if ($Prefix -eq "") { "chat_approval_above_input" } else { "$Prefix`_chat_approval_above_input" }
  $inputRectField = if ($Prefix -eq "") { "chat_input_rect" } else { "$Prefix`_chat_input_rect" }
  $minimumSizeField = if ($Prefix -eq "") { "chat_input_minimum_size" } else { "$Prefix`_chat_input_minimum_size" }
  $rowMinimumSizeField = if ($Prefix -eq "") { "chat_input_row_minimum_size" } else { "$Prefix`_chat_input_row_minimum_size" }
  $scrollFitField = if ($Prefix -eq "") { "chat_input_scroll_fit_content_height" } else { "$Prefix`_chat_input_scroll_fit_content_height" }
  $label = if ($Prefix -eq "") { "initial" } else { $Prefix }

  Assert-True ([bool]$Visible.$inputVisibleField) "Codex Chat $label input is not visible."
  Assert-True ([bool]$Visible.$inputInsideField) "Codex Chat $label input is not inside the chat panel."
  Assert-True ([bool]$Visible.$logInsideField) "Codex Chat $label log is not inside the chat panel."
  Assert-True ([bool]$Visible.$composerBelowField) "Codex Chat $label composer is not below the transcript."
  Assert-True ([bool]$Visible.$approvalAboveField) "Codex Chat $label approval card is not above the input."
  Assert-True ((Get-Number $Visible.$inputRectField.height) -ge 240) "Codex Chat $label input height regressed below 240 px."
  Assert-True ((Get-Number $Visible.$minimumSizeField.y) -ge 260) "Codex Chat $label input minimum height regressed below 260 px."
  Assert-True ((Get-Number $Visible.$rowMinimumSizeField.y) -ge 294) "Codex Chat $label composer row minimum height regressed below 294 px."
  Assert-True (-not [bool]$Visible.$scrollFitField) "Codex Chat $label input scroll_fit_content_height must stay false."
}

$productRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$resolvedProjectRoot = Resolve-FullPath $ProjectRoot $productRoot
$bridgeDir = Join-Path $resolvedProjectRoot ".godot\godot_codex_bridge"
$artifactsDir = Join-Path $bridgeDir "artifacts"
$reportPath = Join-Path $artifactsDir "chat_ux_regression_validation.json"
$visibleReportPath = Join-Path $artifactsDir "visible_chat_editor_validation.json"
$script:ValidationSteps = New-Object System.Collections.Generic.List[object]

New-Item -ItemType Directory -Force -Path $artifactsDir | Out-Null

Push-Location $productRoot
try {
  & powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\install_addon.ps1" -ProjectRoot $ProjectRoot -Apply -Replace -HostRuntime mock -HostPort $Port | Out-Host
  Add-Step "install_mock_addon" "ok" @{ port = $Port }

  & npm run validate:addon-core | Out-Host
  Add-Step "addon_core" "ok" @{}

  # validate:addon-core reinstalls the fixture with app-server defaults. Restore
  # mock host config before starting the visible editor smoke.
  & powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\install_addon.ps1" -ProjectRoot $ProjectRoot -Apply -Replace -HostRuntime mock -HostPort $Port | Out-Host
  Add-Step "restore_mock_host_config" "ok" @{ port = $Port }

  & powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\validate_visible_chat_editor.ps1" `
    -ProjectRoot $ProjectRoot `
    -Runtime mock `
    -Port $Port `
    -AppServerPort $AppServerPort `
    -StartupTimeoutSeconds $StartupTimeoutSeconds `
    -RequestTimeoutSeconds $RequestTimeoutSeconds `
    -TurnTimeoutSeconds $TurnTimeoutSeconds | Out-Host
  Add-Step "visible_chat_editor" "ok" @{ report_path = $visibleReportPath }

  if (-not (Test-Path -LiteralPath $visibleReportPath)) {
    throw "Visible chat editor report was not written: $visibleReportPath"
  }

  $visible = Get-Content -Raw -LiteralPath $visibleReportPath | ConvertFrom-Json

  Assert-True ($visible.status -eq "ok") "Visible chat editor validation did not complete successfully."
  Assert-StableComposer $visible ""
  Assert-True ($visible.chat_multiline_validation_status -eq "succeeded") "Codex Chat multiline validation did not succeed."
  Assert-True ([bool]$visible.chat_multiline_has_newline) "Shift+Enter did not insert a newline in Codex Chat input."
  Assert-True ([int]$visible.chat_multiline_line_count -ge 2) "Shift+Enter line count stayed below 2."
  Assert-True ([bool]$visible.chat_multiline_handled_event) "Shift+Enter InputEventKey was not handled by Codex Chat input."
  Assert-True ([bool]$visible.chat_multiline_expanded_after_shift_enter) "Shift+Enter did not switch the Codex Chat composer to expanded mode."
  Assert-True ([double]$visible.chat_multiline_auto_input_minimum_size.y -ge 260) "Shift+Enter did not auto-grow the Codex Chat input."
  Assert-True ([double]$visible.chat_multiline_auto_input_row_minimum_size.y -ge 294) "Shift+Enter did not auto-grow the Codex Chat input row."
  Assert-True (-not [bool]$visible.chat_multiline_input_scroll_fit_content_height) "Multiline validation reports scroll_fit_content_height=true."
  Assert-True ($visible.chat_enter_send_validation_status -eq "succeeded") "Codex Chat Enter-to-send validation did not succeed."
  Assert-True ([bool]$visible.chat_enter_send_handled_event) "Enter InputEventKey was not handled by Codex Chat input."
  Assert-True ([bool]$visible.chat_enter_send_sent) "Enter did not send through Codex Chat input."
  Assert-True ([bool]$visible.chat_enter_send_input_cleared) "Enter-to-send did not clear the Codex Chat input."
  Assert-True ([bool]$visible.chat_enter_send_turn_completed) "Enter-to-send did not complete a Codex turn."
  Assert-True ($visible.chat_wrapped_prompt_validation_status -eq "succeeded") "Codex Chat wrapped prompt validation did not succeed."
  Assert-True ([bool]$visible.chat_wrapped_prompt_expanded_after_text) "Wrapped prompt did not switch the Codex Chat composer to expanded mode."
  Assert-True ([double]$visible.chat_wrapped_prompt_auto_input_minimum_size.y -ge 260) "Wrapped prompt did not auto-grow the Codex Chat input."
  Assert-True ([double]$visible.chat_wrapped_prompt_auto_input_row_minimum_size.y -ge 294) "Wrapped prompt did not auto-grow the Codex Chat input row."
  Assert-True ($visible.chat_long_prompt_validation_status -eq "succeeded") "Codex Chat long prompt validation did not succeed."
  Assert-True ([bool]$visible.chat_long_prompt_expanded_after_text) "Long prompt did not switch the Codex Chat composer to expanded mode."
  Assert-True ([double]$visible.chat_long_prompt_auto_input_minimum_size.y -ge 360) "Long prompt did not auto-grow the Codex Chat input."
  Assert-True ([double]$visible.chat_long_prompt_auto_input_row_minimum_size.y -ge 454) "Long prompt did not auto-grow the Codex Chat input row."
  Assert-True (-not [bool]$visible.chat_long_prompt_input_scroll_fit_content_height) "Long prompt validation reports scroll_fit_content_height=true."
  Assert-True ($visible.composer_open_status -eq "succeeded") "Composer expand request did not succeed."
  Assert-True ([double]$visible.composer_open_input_minimum_size.y -ge 420) "Composer expand did not raise the input min height."
  Assert-True ($visible.composer_close_status -eq "succeeded") "Composer collapse request did not succeed."
  Assert-True ([double]$visible.composer_close_input_minimum_size.y -eq 260) "Composer collapse did not restore the comfortable input min height."
  Assert-StableComposer $visible "final"
  Assert-True (-not [bool]$visible.advanced_visible) "Advanced controls are visible by default."
  Assert-True ([bool]$visible.advanced_toggle_visible) "Advanced toggle is not visible."
  Assert-True ([bool]$visible.advanced_toggle_inside_chat_panel) "Advanced toggle is outside the chat panel."
  Assert-True (-not [bool]$visible.bottom_panel_registered) "Codex Bridge registered a bottom panel; this regresses the visible screen bottom layout."
  Assert-True ([bool]$visible.main_screen_registered) "Codex Bridge main screen tab is not registered."
  Assert-True ([bool]$visible.dock_registered) "Codex Bridge dock is not registered."
  Assert-True ([bool]$visible.eye_button_visible) "Eye Attach button is not visible in the slim chat composer."
  Assert-True ([bool]$visible.eye_button_inside_chat_panel) "Eye Attach button is outside the chat panel."
  Assert-True ($visible.advanced_open_status -eq "succeeded") "Advanced open request did not succeed."
  Assert-True ($visible.advanced_close_status -eq "succeeded") "Advanced close request did not succeed."
  Assert-True (-not [bool]$visible.final_advanced_visible) "Advanced controls are visible after chat activity."
  Assert-True ($visible.eye_attach_status -eq "succeeded") "Eye Attach validation did not succeed."
  Assert-True ([bool]$visible.eye_attach_capture_succeeded) "Eye Attach capture did not succeed."
  Assert-True (-not [bool]$visible.eye_attach_capture_looked_blank) "Eye Attach capture looked blank."
  Assert-True ([int]$visible.eye_attach_image_width -gt 0) "Eye Attach capture width is invalid."
  Assert-True ([int]$visible.eye_attach_image_height -gt 0) "Eye Attach capture height is invalid."
  Assert-True ([bool]$visible.eye_attach_dialog_visible_after_open) "Eye Attach dialog did not open."
  Assert-True ([bool]$visible.eye_attach_canvas_has_image_after_open) "Eye Attach canvas did not receive a source image."
  Assert-True ([bool]$visible.eye_attach_marker_created_for_cancel) "Eye Attach cancel marker was not created."
  Assert-True ([int]$visible.eye_attach_marker_count_before_cancel -ge 1) "Eye Attach cancel path did not contain a marker."
  Assert-True ([bool]$visible.eye_attach_cancel_left_no_pending) "Eye Attach cancel left a pending annotation."
  Assert-True ([bool]$visible.eye_attach_dialog_hidden_after_cancel) "Eye Attach cancel did not hide the dialog."
  Assert-True ([bool]$visible.eye_attach_marker_created_for_attach) "Eye Attach attach marker was not created."
  Assert-True ([int]$visible.eye_attach_marker_count_before_attach -ge 1) "Eye Attach attach path did not contain a marker."
  Assert-True ([bool]$visible.eye_attach_pending_after_attach) "Eye Attach attach did not create a pending annotation."
  Assert-True ([int]$visible.eye_attach_pending_marker_count -ge 1) "Eye Attach pending annotation has no marker."
  Assert-True ([bool]$visible.eye_attach_pending_label_visible) "Eye Attach pending chip was not visible after attach."
  Assert-True ([bool]$visible.eye_attach_clear_button_visible) "Eye Attach clear button was not visible after attach."
  Assert-True ([bool]$visible.eye_attach_raw_exists) "Eye Attach raw artifact was not written."
  Assert-True ([bool]$visible.eye_attach_annotated_exists) "Eye Attach annotated artifact was not written."
  Assert-True ([bool]$visible.eye_attach_manifest_exists) "Eye Attach manifest was not written."
  Assert-True ([bool]$visible.eye_attach_manifest_has_guardrails) "Eye Attach manifest is missing anti-recreate guardrails."
  Assert-True ([bool]$visible.eye_attach_clear_removed_pending) "Eye Attach clear did not remove pending annotation."
  Assert-True ([bool]$visible.eye_attach_pending_label_hidden_after_clear) "Eye Attach pending chip stayed visible after clear."
  Assert-True ([bool]$visible.eye_attach_clear_button_hidden_after_clear) "Eye Attach clear button stayed visible after clear."
  Assert-True ($visible.diff_overflow_validation_status -eq "succeeded") "Diff overflow validation did not succeed."
  Assert-True ([int]$visible.diff_overflow_generated_file_count -ge 32) "Diff overflow fixture did not generate enough files."
  Assert-True ([int]$visible.diff_overflow_active_file_count -eq [int]$visible.diff_overflow_ui_file_limit) "Diff overflow active file count did not match the UI cap."
  Assert-True ([int]$visible.diff_overflow_active_added_count -eq 72) "Diff overflow added count should reflect the 24 rendered file cap."
  Assert-True ([int]$visible.diff_overflow_active_removed_count -eq 72) "Diff overflow removed count should reflect the 24 rendered file cap."
  Assert-True ([int]$visible.diff_overflow_file_section_count -eq [int]$visible.diff_overflow_ui_file_limit) "Diff overflow rendered file sections did not match the UI cap."
  Assert-True ([int]$visible.diff_overflow_preview_count -eq 1) "Diff overflow should render one diff preview card."
  Assert-True ([int]$visible.diff_overflow_files_box_visible_count -eq 1) "Diff overflow file list should be visible during the layout check."
  Assert-True ([bool]$visible.diff_overflow_active_files_visible) "Diff overflow active file list was not expanded."
  Assert-True ([bool]$visible.diff_overflow_input_visible) "Diff overflow hid the chat composer."
  Assert-True ([bool]$visible.diff_overflow_input_inside_panel) "Diff overflow moved the chat composer outside the panel."
  Assert-True ([bool]$visible.diff_overflow_log_inside_panel) "Diff overflow moved the transcript outside the panel."
  Assert-True ([bool]$visible.diff_overflow_composer_below_log) "Diff overflow changed the composer/log ordering."
  Assert-True ([bool]$visible.diff_overflow_approval_above_input) "Diff overflow changed the approval/composer ordering."
  Assert-True ([double]$visible.diff_overflow_input_rect.height -ge 240) "Diff overflow shrank the chat composer below the stable visible height."
  Assert-True ($visible.diff_overflow_visual_status -eq "succeeded") "Diff overflow visual evidence capture did not succeed."
  Assert-True (-not [string]::IsNullOrWhiteSpace([string]$visible.diff_overflow_visual_path)) "Diff overflow visual evidence path is missing."
  Assert-True (Test-Path -LiteralPath ([string]$visible.diff_overflow_visual_path)) "Diff overflow visual evidence PNG does not exist."
  Assert-True ([int]$visible.diff_overflow_visual_width -gt 0) "Diff overflow visual evidence width is invalid."
  Assert-True ([int]$visible.diff_overflow_visual_height -gt 0) "Diff overflow visual evidence height is invalid."
  Assert-True (-not [bool]$visible.diff_overflow_visual_looks_blank) "Diff overflow visual evidence PNG looks blank."
  Assert-True ([bool]$visible.final_mcp_tools_available) "MCP tools were not available by the end of the visible chat smoke."
  Assert-True ([bool]$visible.approval_requested) "Approval flow was not exercised by the visible chat smoke."
  Assert-True ([bool]$visible.approval_resolved) "Approval flow was not resolved by the visible chat smoke."

  $summary = [ordered]@{
    status = "ok"
    completed_at = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $resolvedProjectRoot
    port = $Port
    app_server_port = $AppServerPort
    report_path = $reportPath
    visible_report_path = $visibleReportPath
    checks = [ordered]@{
      initial_chat_input_height = $visible.chat_input_rect.height
      final_chat_input_height = $visible.final_chat_input_rect.height
      input_min_height = $visible.chat_input_minimum_size.y
      input_row_min_height = $visible.chat_input_row_minimum_size.y
      final_input_min_height = $visible.final_chat_input_minimum_size.y
      final_input_row_min_height = $visible.final_chat_input_row_minimum_size.y
      shift_enter_line_count = $visible.chat_multiline_line_count
      shift_enter_has_newline = [bool]$visible.chat_multiline_has_newline
      shift_enter_handled_event = [bool]$visible.chat_multiline_handled_event
      shift_enter_expanded_after = [bool]$visible.chat_multiline_expanded_after_shift_enter
      shift_enter_auto_input_min_height = $visible.chat_multiline_auto_input_minimum_size.y
      shift_enter_auto_row_min_height = $visible.chat_multiline_auto_input_row_minimum_size.y
      enter_send_status = $visible.chat_enter_send_validation_status
      enter_send_handled_event = [bool]$visible.chat_enter_send_handled_event
      enter_send_sent = [bool]$visible.chat_enter_send_sent
      enter_send_input_cleared = [bool]$visible.chat_enter_send_input_cleared
      enter_send_turn_completed = [bool]$visible.chat_enter_send_turn_completed
      wrapped_prompt_status = $visible.chat_wrapped_prompt_validation_status
      wrapped_prompt_length = $visible.chat_wrapped_prompt_text_length
      wrapped_prompt_width = $visible.chat_wrapped_prompt_input_width
      wrapped_prompt_expected_height = $visible.chat_wrapped_prompt_expected_height
      wrapped_prompt_expanded_after = [bool]$visible.chat_wrapped_prompt_expanded_after_text
      wrapped_prompt_auto_input_min_height = $visible.chat_wrapped_prompt_auto_input_minimum_size.y
      wrapped_prompt_auto_row_min_height = $visible.chat_wrapped_prompt_auto_input_row_minimum_size.y
      long_prompt_status = $visible.chat_long_prompt_validation_status
      long_prompt_length = $visible.chat_long_prompt_text_length
      long_prompt_expected_height = $visible.chat_long_prompt_expected_height
      long_prompt_expanded_after = [bool]$visible.chat_long_prompt_expanded_after_text
      long_prompt_auto_input_min_height = $visible.chat_long_prompt_auto_input_minimum_size.y
      long_prompt_auto_row_min_height = $visible.chat_long_prompt_auto_input_row_minimum_size.y
      composer_open_status = $visible.composer_open_status
      composer_open_min_height = $visible.composer_open_input_minimum_size.y
      composer_close_status = $visible.composer_close_status
      composer_close_min_height = $visible.composer_close_input_minimum_size.y
      advanced_default_collapsed = -not [bool]$visible.advanced_visible
      advanced_open_status = $visible.advanced_open_status
      advanced_close_status = $visible.advanced_close_status
      final_advanced_collapsed = -not [bool]$visible.final_advanced_visible
      main_screen_registered = [bool]$visible.main_screen_registered
      dock_registered = [bool]$visible.dock_registered
      bottom_panel_registered = [bool]$visible.bottom_panel_registered
      eye_button_visible = [bool]$visible.eye_button_visible
      eye_button_inside_chat_panel = [bool]$visible.eye_button_inside_chat_panel
      eye_attach_status = $visible.eye_attach_status
      eye_attach_capture_scope = $visible.eye_attach_capture_scope
      eye_attach_capture_source = $visible.eye_attach_capture_source
      eye_attach_image_width = $visible.eye_attach_image_width
      eye_attach_image_height = $visible.eye_attach_image_height
      eye_attach_marker_count_before_cancel = $visible.eye_attach_marker_count_before_cancel
      eye_attach_marker_count_before_attach = $visible.eye_attach_marker_count_before_attach
      eye_attach_pending_marker_count = $visible.eye_attach_pending_marker_count
      eye_attach_manifest_has_guardrails = [bool]$visible.eye_attach_manifest_has_guardrails
      eye_attach_artifacts_written = [bool]$visible.eye_attach_raw_exists -and [bool]$visible.eye_attach_annotated_exists -and [bool]$visible.eye_attach_manifest_exists
      eye_attach_clear_removed_pending = [bool]$visible.eye_attach_clear_removed_pending
      diff_overflow_status = $visible.diff_overflow_validation_status
      diff_overflow_generated_file_count = $visible.diff_overflow_generated_file_count
      diff_overflow_ui_file_limit = $visible.diff_overflow_ui_file_limit
      diff_overflow_active_file_count = $visible.diff_overflow_active_file_count
      diff_overflow_active_added_count = $visible.diff_overflow_active_added_count
      diff_overflow_active_removed_count = $visible.diff_overflow_active_removed_count
      diff_overflow_file_section_count = $visible.diff_overflow_file_section_count
      diff_overflow_files_box_visible_count = $visible.diff_overflow_files_box_visible_count
      diff_overflow_input_height = $visible.diff_overflow_input_rect.height
      diff_overflow_composer_below_log = [bool]$visible.diff_overflow_composer_below_log
      diff_overflow_approval_above_input = [bool]$visible.diff_overflow_approval_above_input
      diff_overflow_visual_status = $visible.diff_overflow_visual_status
      diff_overflow_visual_path = $visible.diff_overflow_visual_path
      diff_overflow_visual_width = $visible.diff_overflow_visual_width
      diff_overflow_visual_height = $visible.diff_overflow_visual_height
      diff_overflow_visual_looks_blank = [bool]$visible.diff_overflow_visual_looks_blank
      final_mcp_tools_available = [bool]$visible.final_mcp_tools_available
      approval_requested = [bool]$visible.approval_requested
      approval_resolved = [bool]$visible.approval_resolved
    }
    cases = [ordered]@{
      no_bottom_panel_regression = [ordered]@{
        status = "ok"
        main_screen_registered = [bool]$visible.main_screen_registered
        dock_registered = [bool]$visible.dock_registered
        bottom_panel_registered = [bool]$visible.bottom_panel_registered
        window_inside_usable_screen = [bool]$visible.window_inside_usable_screen
        final_window_inside_usable_screen = [bool]$visible.final_window_inside_usable_screen
      }
      eye_attach_capture_marker_cancel_attach = [ordered]@{
        status = "ok"
        capture_scope = $visible.eye_attach_capture_scope
        capture_source = $visible.eye_attach_capture_source
        image_width = $visible.eye_attach_image_width
        image_height = $visible.eye_attach_image_height
        marker_count_before_cancel = $visible.eye_attach_marker_count_before_cancel
        cancel_left_no_pending = [bool]$visible.eye_attach_cancel_left_no_pending
        marker_count_before_attach = $visible.eye_attach_marker_count_before_attach
        pending_marker_count = $visible.eye_attach_pending_marker_count
        artifacts_written = [bool]$visible.eye_attach_raw_exists -and [bool]$visible.eye_attach_annotated_exists -and [bool]$visible.eye_attach_manifest_exists
        manifest_has_guardrails = [bool]$visible.eye_attach_manifest_has_guardrails
        clear_removed_pending = [bool]$visible.eye_attach_clear_removed_pending
      }
      diff_batch_ui = [ordered]@{
        status = "ok"
        generated_file_count = $visible.diff_overflow_generated_file_count
        ui_file_limit = $visible.diff_overflow_ui_file_limit
        rendered_file_sections = $visible.diff_overflow_file_section_count
        files_box_visible_count = $visible.diff_overflow_files_box_visible_count
        expanded_file_list_visible = [bool]$visible.diff_overflow_active_files_visible
        composer_still_visible = [bool]$visible.diff_overflow_input_visible
        visual_evidence_path = $visible.diff_overflow_visual_path
        visual_evidence_size = @{
          width = $visible.diff_overflow_visual_width
          height = $visible.diff_overflow_visual_height
        }
        visual_evidence_nonblank = -not [bool]$visible.diff_overflow_visual_looks_blank
      }
      composer_and_approval_layout = [ordered]@{
        status = "ok"
        composer_below_log = [bool]$visible.final_chat_composer_below_log
        approval_above_input = [bool]$visible.final_chat_approval_above_input
        shift_enter_line_count = $visible.chat_multiline_line_count
        enter_send_turn_completed = [bool]$visible.chat_enter_send_turn_completed
      }
    }
    steps = @($script:ValidationSteps.ToArray())
  }

  $summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportPath -Encoding UTF8
  $summary | ConvertTo-Json -Depth 12
} catch {
  Add-Step "chat_ux_regression" "failed" @{ error = [string]$_.Exception.Message }
  $summary = [ordered]@{
    status = "failed"
    completed_at = (Get-Date).ToUniversalTime().ToString("o")
    project_root = [string]$resolvedProjectRoot
    port = $Port
    app_server_port = $AppServerPort
    report_path = [string]$reportPath
    error = [string]$_.Exception.Message
    steps = @($script:ValidationSteps.ToArray())
  }
  $summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportPath -Encoding UTF8
  throw
} finally {
  Pop-Location
}
