@tool
extends EditorPlugin

const EditorControlManifest := preload("core/editor_control_manifest.gd")
const AssetImportModel := preload("core/asset_import_model.gd")
const ChatDiffModel := preload("core/chat_diff_model.gd")
const ChatActionModel := preload("core/chat_action_model.gd")
const ChatApprovalModel := preload("core/chat_approval_model.gd")
const ChatControlStateModel := preload("core/chat_control_state_model.gd")
const ChatHostConfigModel := preload("core/chat_host_config_model.gd")
const TrustedHostLaunchModel := preload("core/trusted_host_launch_model.gd")
const DockStyle := preload("core/dock_style.gd")
const ChatApprovalReviewModel := preload("core/chat_approval_review_model.gd")
const ChatApprovalPopup := preload("core/chat_approval_popup.gd")
const ChatSessionAllowModel := preload("core/chat_session_allow_model.gd")
const ChatModelPreferenceModel := preload("core/chat_model_preference_model.gd")
const BridgeRequestLimits := preload("core/bridge_request_limits.gd")
const BridgePathGuard := preload("core/bridge_path_guard.gd")
const ChatHostStateModel := preload("core/chat_host_state_model.gd")
const ChatInputModel := preload("core/chat_input_model.gd")
const ChatLayoutStatusModel := preload("core/chat_layout_status_model.gd")
const ChatRuntimeOptionsModel := preload("core/chat_runtime_options_model.gd")
const ChatTechnicalLogModel := preload("core/chat_technical_log_model.gd")
const ChatEventModel := preload("core/chat_event_model.gd")
const ChatRequestModel := preload("core/chat_request_model.gd")
const ChatSocketEventModel := preload("core/chat_socket_event_model.gd")
const ChatSocketController := preload("core/chat_socket_controller.gd")
const ChatTranscriptModel := preload("core/chat_transcript_model.gd")
const ChatTranscriptBatchModel := preload("core/chat_transcript_batch_model.gd")
const ChatTranscriptView := preload("core/chat_transcript_view.gd")
const ChatScrollPolicyModel := preload("core/chat_scroll_policy_model.gd")
const ChatThemeModel := preload("core/chat_theme_model.gd")
const ChatPanelView := preload("core/chat_panel_view.gd")
const GcWorkChannelModel := preload("core/gc_work_channel_model.gd")
const AddonUpdateModel := preload("core/addon_update_model.gd")
const AddonUpdatePanel := preload("core/addon_update_panel.gd")
const BridgeDockStatusModel := preload("core/bridge_dock_status_model.gd")
const PermissionProfileModel := preload("core/permission_profile_model.gd")
const ChatSessionModel := preload("core/chat_session_model.gd")
const ChatStatusModel := preload("core/chat_status_model.gd")
const ChatTeamModel := preload("core/chat_team_model.gd")
const ChatDiffView := preload("core/chat_diff_view.gd")
const VariantCodec := preload("core/variant_codec.gd")
const AnimationModel := preload("core/animation_model.gd")
const ParticleEffectModel := preload("core/particle_effect_model.gd")
const ResourceLifecycleModel := preload("core/resource_lifecycle_model.gd")
const ShaderMaterialModel := preload("core/shader_material_model.gd")
const MaterialDiagnosticsModel := preload("core/material_diagnostics_model.gd")
const AnnotationCanvas := preload("core/annotation_canvas.gd")
const AnnotationArtifactModel := preload("core/annotation_artifact_model.gd")
const AnnotationController := preload("core/annotation_controller.gd")
const EditorControl := preload("core/editor_control.gd")
const EditorUndo := preload("core/editor_undo.gd")
const SpatialBoundsModel := preload("core/spatial_bounds_model.gd")
const EditorDiagnostics := preload("core/editor_diagnostics.gd")
const EditorNodeLifecycle := preload("core/editor_node_lifecycle.gd")
const EditorSceneMutation := preload("core/editor_scene_mutation.gd")
const EditorSceneSave := preload("core/editor_scene_save.gd")
const EditorResourceMaterial := preload("core/editor_resource_material.gd")
const EditorResourceBrowser := preload("core/editor_resource_browser.gd")
const EditorClassInfo := preload("core/editor_class_info.gd")
const EditorPathGuard := preload("core/editor_path_guard.gd")
const EditorSignals := preload("core/editor_signals.gd")
const EditorAnimation := preload("core/editor_animation.gd")
const EditorScriptNavigation := preload("core/editor_script_navigation.gd")
const EditorAssetImport := preload("core/editor_asset_import.gd")
const EditorRenderingEffects := preload("core/editor_rendering_effects.gd")
const EditorPanelNavigation := preload("core/editor_panel_navigation.gd")
const EditorViewportNavigation := preload("core/editor_viewport_navigation.gd")
const EditorInspectorContext := preload("core/editor_inspector_context.gd")
const MultiViewCaptureModel := preload("core/multi_view_capture_model.gd")
const BridgeContext := preload("core/bridge_context.gd")
const BridgeRequestModel := preload("core/bridge_request_model.gd")
const BridgeRequestJournal := preload("core/bridge_request_journal.gd")
const BridgeResponseModel := preload("core/bridge_response_model.gd")
const BridgeUtils := preload("core/bridge_utils.gd")
const SceneIntrospection := preload("core/scene_introspection.gd")

# Constants live in core/bridge_limits.gd (single source of truth) and are
# re-exported here so existing references in this file keep working unchanged.
const BridgeLimits := preload("core/bridge_limits.gd")

const PLUGIN_NAME := BridgeLimits.PLUGIN_NAME
const PLUGIN_VERSION := BridgeLimits.PLUGIN_VERSION
const PROTOCOL_VERSION := BridgeLimits.PROTOCOL_VERSION

const BRIDGE_DIR := BridgeLimits.BRIDGE_DIR
const REQUESTS_DIR := BridgeLimits.REQUESTS_DIR
const RESPONSES_DIR := BridgeLimits.RESPONSES_DIR
const SCREENSHOTS_DIR := BridgeLimits.SCREENSHOTS_DIR
const ANNOTATIONS_DIR := BridgeLimits.ANNOTATIONS_DIR
const CONTEXT_SNAPSHOT_PATH := BridgeLimits.CONTEXT_SNAPSHOT_PATH
const BRIDGE_STATE_PATH := BridgeLimits.BRIDGE_STATE_PATH
const HEARTBEAT_PATH := BridgeLimits.HEARTBEAT_PATH
const PERMISSIONS_PATH := BridgeLimits.PERMISSIONS_PATH
const SEND_CONTEXT_PATH := BridgeLimits.SEND_CONTEXT_PATH
const NOTES_PATH := BridgeLimits.NOTES_PATH
const HOST_CONFIG_PATH := BridgeLimits.HOST_CONFIG_PATH
const DEFAULT_CODEX_HOST_PORT := BridgeLimits.DEFAULT_CODEX_HOST_PORT
const CODEX_HOST_URL := BridgeLimits.CODEX_HOST_URL

const POLL_SECONDS := BridgeLimits.POLL_SECONDS
const CHAT_HOST_START_RETRY_SECONDS := BridgeLimits.CHAT_HOST_START_RETRY_SECONDS
const CHAT_HOST_START_TIMEOUT_SECONDS := BridgeLimits.CHAT_HOST_START_TIMEOUT_SECONDS
const CHAT_MAX_PACKETS_PER_FRAME := BridgeLimits.CHAT_MAX_PACKETS_PER_FRAME
const CHAT_MAX_PACKET_CHARS := BridgeLimits.CHAT_MAX_PACKET_CHARS
const CHAT_MAX_MESSAGE_CHARS := BridgeLimits.CHAT_MAX_MESSAGE_CHARS
const CHAT_ASSISTANT_BUBBLE_CHARS := BridgeLimits.CHAT_ASSISTANT_BUBBLE_CHARS
const CHAT_ASSISTANT_SECTION_CHARS := BridgeLimits.CHAT_ASSISTANT_SECTION_CHARS
const CHAT_COLLAPSE_CHARS := BridgeLimits.CHAT_COLLAPSE_CHARS
const CHAT_COLLAPSE_LINES := BridgeLimits.CHAT_COLLAPSE_LINES
const CHAT_PREVIEW_CHARS := BridgeLimits.CHAT_PREVIEW_CHARS
const CHAT_PREVIEW_LINES := BridgeLimits.CHAT_PREVIEW_LINES
const CHAT_WORK_PREVIEW_CHARS := BridgeLimits.CHAT_WORK_PREVIEW_CHARS
const CHAT_WORK_PREVIEW_LINES := BridgeLimits.CHAT_WORK_PREVIEW_LINES
const CHAT_DIFF_MAX_FILES := BridgeLimits.CHAT_DIFF_MAX_FILES
const CHAT_DIFF_MAX_LINES_PER_FILE := BridgeLimits.CHAT_DIFF_MAX_LINES_PER_FILE
const CHAT_BACKPRESSURE_NOTICE_INTERVAL_MSEC := BridgeLimits.CHAT_BACKPRESSURE_NOTICE_INTERVAL_MSEC
const CHAT_ASSISTANT_FLUSH_INTERVAL_MSEC := BridgeLimits.CHAT_ASSISTANT_FLUSH_INTERVAL_MSEC
const CHAT_HOST_SHUTDOWN_GRACE_MSEC := BridgeLimits.CHAT_HOST_SHUTDOWN_GRACE_MSEC
const MAX_SCENE_NODES := BridgeLimits.MAX_SCENE_NODES
const MAX_CHILDREN_PER_NODE := BridgeLimits.MAX_CHILDREN_PER_NODE
const MAX_SELECTED_NODES := BridgeLimits.MAX_SELECTED_NODES
const MAX_PROPERTIES_PER_NODE := BridgeLimits.MAX_PROPERTIES_PER_NODE
const MAX_PROPERTY_DEPTH := BridgeLimits.MAX_PROPERTY_DEPTH
const MAX_ARRAY_ITEMS := BridgeLimits.MAX_ARRAY_ITEMS
const MAX_DICTIONARY_ITEMS := BridgeLimits.MAX_DICTIONARY_ITEMS
const MAX_RESOURCES := BridgeLimits.MAX_RESOURCES
const MAX_INPUT_ACTIONS := BridgeLimits.MAX_INPUT_ACTIONS
const MAX_SCRIPT_FILES := BridgeLimits.MAX_SCRIPT_FILES
const MAX_SCRIPT_LINES_PER_FILE := BridgeLimits.MAX_SCRIPT_LINES_PER_FILE
const MAX_SCRIPT_SYMBOLS_PER_FILE := BridgeLimits.MAX_SCRIPT_SYMBOLS_PER_FILE
const MAX_SCREENSHOTS_IN_CONTEXT := BridgeLimits.MAX_SCREENSHOTS_IN_CONTEXT
const MAX_BRIDGE_LOG_EVENTS := BridgeLimits.MAX_BRIDGE_LOG_EVENTS
const MAX_REQUESTS_PER_POLL := BridgeLimits.MAX_REQUESTS_PER_POLL
const MAX_REQUEST_QUEUE_FILES := BridgeLimits.MAX_REQUEST_QUEUE_FILES
const MAX_REQUEST_BYTES := BridgeLimits.MAX_REQUEST_BYTES
const MAX_REQUEST_JSON_DEPTH := BridgeLimits.MAX_REQUEST_JSON_DEPTH
const MAX_REQUEST_JSON_NODES := BridgeLimits.MAX_REQUEST_JSON_NODES
const MAX_MATERIALS_PER_MESH := BridgeLimits.MAX_MATERIALS_PER_MESH
const MAX_PERFORMANCE_SAMPLES := BridgeLimits.MAX_PERFORMANCE_SAMPLES
const MAX_STRING_LENGTH := BridgeLimits.MAX_STRING_LENGTH
const MAX_DEPTH := BridgeLimits.MAX_DEPTH
const MAX_EDITOR_BATCH_ACTIONS := BridgeLimits.MAX_EDITOR_BATCH_ACTIONS
const MAX_EDITOR_PROPERTY_CHANGES := BridgeLimits.MAX_EDITOR_PROPERTY_CHANGES
const MAX_RECENT_EDITOR_ACTIONS := BridgeLimits.MAX_RECENT_EDITOR_ACTIONS
const MAX_ANIMATION_PLAYERS := BridgeLimits.MAX_ANIMATION_PLAYERS
const MAX_ANIMATIONS_PER_PLAYER := BridgeLimits.MAX_ANIMATIONS_PER_PLAYER
const MAX_ANIMATION_TRACKS := BridgeLimits.MAX_ANIMATION_TRACKS
const MAX_ANIMATION_KEYS_PER_TRACK := BridgeLimits.MAX_ANIMATION_KEYS_PER_TRACK
const MAX_ANIMATION_INITIAL_TRACKS := BridgeLimits.MAX_ANIMATION_INITIAL_TRACKS
const MAX_MATERIAL_INSPECT_NODES := BridgeLimits.MAX_MATERIAL_INSPECT_NODES
const MAX_MATERIAL_SLOTS := BridgeLimits.MAX_MATERIAL_SLOTS
const MAX_SHADER_UNIFORMS := BridgeLimits.MAX_SHADER_UNIFORMS
const MAX_RENDER_EFFECT_NODES := BridgeLimits.MAX_RENDER_EFFECT_NODES
const MAX_ENVIRONMENT_PROPERTIES := BridgeLimits.MAX_ENVIRONMENT_PROPERTIES
const MAX_IMPORTED_ASSETS := BridgeLimits.MAX_IMPORTED_ASSETS
const MAX_ASSET_DEPENDENCIES := BridgeLimits.MAX_ASSET_DEPENDENCIES
const CHAT_COPY_ICON_TEXT := "⧉"
const CHAT_COPY_BUTTON_SIZE := Vector2(20, 20)

var _dock: Control
var _main_screen: VBoxContainer
var _chat_dock: VBoxContainer
var _chat_socket: WebSocketPeer
var _chat_status_label: Label
var _chat_status_dot: ColorRect
var _chat_build_label: Label
var _chat_trust_indicator: Label
var _chat_readiness_label: Label
var _chat_thread_label: Label
var _chat_new_button: Button
var _chat_clear_button: Button
var _chat_log_frame: Control
var _chat_log_view: ScrollContainer
var _chat_message_list: VBoxContainer
var _chat_bottom_spacer: Control
var _chat_jump_latest_button: Button
var _chat_follow_latest := true
var _chat_scroll_user_input_pending := false
var _chat_input_row: VBoxContainer
var _chat_input: TextEdit
var _chat_eye_button: Button
var _chat_composer_toggle_button: Button
var _chat_connect_button: Button
var _host_pair_dialog: ConfirmationDialog
var _host_pair_input: LineEdit
var _host_pair_secret := ""
var _host_pairing_sent := false
var _host_paired := false
var _host_pair_client_nonce := ""
var _host_pair_server_nonce := ""
var _chat_enable_tools_button: Button
var _chat_send_button: Button
var _chat_cancel_button: Button
var _chat_advanced_toggle: CheckButton
var _chat_advanced_panel: VBoxContainer
var _chat_trust_button: CheckButton
var _chat_working_label: Label
var _chat_model_option: OptionButton
var _chat_reasoning_option: OptionButton
var _team_review_button: Button
var _team_cancel_button: Button
var _team_status_label: Label
var _chat_attach_context: CheckBox
var _chat_attach_selected: CheckBox
var _chat_attach_screenshot: CheckBox
var _chat_pending_annotation_label: Label
var _chat_clear_annotation_button: Button
var _chat_approval_panel: VBoxContainer
var _chat_approval_title: Label
var _chat_approval_body: TextEdit
var _chat_approval_note: LineEdit
var _chat_approve_button: Button
var _chat_approve_session_button: Button
var _chat_allow_session_button: Button
## Last explicitly chosen model/effort, stored in per-user editor settings.
var _model_preference := ChatModelPreferenceModel.new({})
var _model_preference_notices := {}
var _chat_effective_default_model := ""
var _chat_model_badge: Button
## Read-only Godot tools the Host remembers for this session (host.status).
var _chat_session_allowed_tools: Array[String] = []
var _session_allow_row: HBoxContainer
var _session_allow_label: Label
var _auto_approved_state := {}
var _auto_approved_body: RichTextLabel
var _chat_reject_button: Button
var _chat_revise_button: Button
var _status_labels: Array[Label] = []
var _snapshot_labels: Array[Label] = []
var _pending_labels: Array[Label] = []
## Shared context handed to extracted core/ service modules (see bridge_context.gd).
var _context: BridgeContext
var _introspection: SceneIntrospection
var _annotation_controller: AnnotationController
var _editor_control: EditorControl
var _editor_undo: EditorUndo
var _spatial_bounds: SpatialBoundsModel
var _editor_diagnostics: EditorDiagnostics
var _editor_node_lifecycle: EditorNodeLifecycle
var _editor_scene_mutation: EditorSceneMutation
var _editor_scene_save: EditorSceneSave
var _editor_resource_material: EditorResourceMaterial
var _editor_resource_browser: EditorResourceBrowser
var _editor_class_info: EditorClassInfo
var _editor_signals: EditorSignals
var _editor_animation: EditorAnimation
var _editor_script_navigation: EditorScriptNavigation
var _editor_asset_import: EditorAssetImport
var _editor_rendering_effects: EditorRenderingEffects
var _editor_panel_navigation: EditorPanelNavigation
var _editor_viewport_navigation: EditorViewportNavigation
var _editor_inspector_context: EditorInspectorContext
## True only while a play session started by run_current_scene is running;
## emergency_stop never stops a play session the user started.
var _bridge_owned_play_session := false
var _multi_view_capture: MultiViewCaptureModel
var _async_editor_requests_in_flight := {}
var _request_journal: BridgeRequestJournal
var _chat_transcript_view: ChatTranscriptView

var _bridge_dir_abs := ""
var _requests_dir_abs := ""
var _responses_dir_abs := ""
var _journal_dir_abs := ""
var _screenshots_dir_abs := ""
var _annotations_dir_abs := ""
var _context_snapshot_abs := ""
var _bridge_state_abs := ""
var _heartbeat_abs := ""
var _permissions_abs := ""
var _send_context_abs := ""
var _notes_abs := ""
var _host_config_abs := ""

var _last_snapshot_time := "never"
var _last_status := "Bridge starting"
var _bridge_log: Array = []
var _recent_editor_actions: Array = []
var _diagnostics_cleared_at := ""
var _chat_technical_log: Array = []
var _performance_history: Array = []
var _poll_elapsed := 0.0
var _host_config: Dictionary = {}
var _gc_work_status: Dictionary = {}
var _addon_update := AddonUpdateModel.new()
var _addon_update_panel: AddonUpdatePanel
var _dock_status_dot: ColorRect
var _dock_status_label: Label
var _permission_profile_option: OptionButton
var _permission_full_trust_dialog: ConfirmationDialog
var _permission_checkboxes := {}
## Advanced permissions fold state; kept for this editor session.
var _advanced_permissions_expanded := false
var _gc_work_refresh_elapsed := 0.0
var _host_config_status := "missing"
var _host_config_message := ""
var _host_config_runtime := ""
var _host_config_port := 0
var _host_config_launcher_path := ""
var _codex_host_url := CODEX_HOST_URL
var _host_start_in_progress := false
var _host_start_process_id := -1
var _host_start_deadline_msec := 0
var _host_start_retry_elapsed := 0.0
var _host_launch_attempted := false
var _host_connect_autostart_allowed := false
## One-click Connect session (contracts/ONE_CLICK_CONNECT_V1.md). The secret is
## generated here, handed to the launcher only through its environment, and
## kept in memory to pair (and re-pair) with the Host this editor launched.
var _one_click_record: Dictionary = {}
var _one_click_secret := ""
var _one_click_url := ""
var _one_click_launcher_pid := -1
var _one_click_host_pid := -1
var _one_click_launched_unix := 0.0
var _one_click_deadline_msec := 0
var _one_click_waiting := false
var _one_click_owned := false
var _retrust_dialog: ConfirmationDialog
## Theme-derived dock style (colors, icons, code font); fallback when headless.
var _dock_style: Dictionary = DockStyle.resolve(null)
var _approval_popup: ChatApprovalPopup
var _approval_review_button: Button
## Approval ids whose review popup already opened by itself (once per id).
var _approval_popup_opened_ids := {}
var _retrust_fingerprint := ""
var _chat_connection_state := "disconnected"
var _chat_runtime_state := "disconnected"
var _chat_mcp_tools_available := false
var _chat_mcp_tool_count := 0
var _chat_mcp_godot_tool_count := 0
var _chat_mcp_server_name := ""
var _chat_last_tool_inventory_at := ""
var _chat_tool_visibility_error := ""
var _chat_last_reported_tool_visibility_error := ""
var _chat_auto_enable_tools_requested := false
var _chat_trust_mode := "off"
var _chat_foreground_busy_started_msec := 0
var _chat_working_refresh_elapsed := 0.0
var _chat_last_token_usage := {}
var _chat_active_project_root := ""
var _chat_agents_count := -1
var _chat_agents_paths: Array[String] = []
var _chat_recoverable_message := ""
var _chat_fatal_message := ""
var _chat_thread_id := ""
var _chat_turn_id := ""
var _chat_seen_turn_event_ids := {}
var _chat_request_id := 0
var _chat_request_methods := {}
var _chat_last_completed_project_attach_request_id := -1
var _chat_last_completed_project_attach_method := ""
var _chat_models_loaded := false
var _chat_model_options: Array[Dictionary] = []
var _chat_reasoning_efforts: Array[Dictionary] = []
var _chat_composer_expanded := false
var _active_chat_approval: Dictionary = {}
var _active_background_task_id := ""
var _active_background_state := "idle"
var _last_chat_backpressure_notice_msec := 0
var _chat_backpressure_events_since_notice := 0
var _chat_last_backpressure_text := ""
var _chat_active_diff_label: Label
var _chat_active_diff_panel: VBoxContainer
var _chat_active_diff_summary_label: Label
var _chat_active_diff_toggle_button: Button
var _chat_active_diff_text := ""
var _chat_active_diff_updates := 0
var _chat_active_diff_files := PackedStringArray()
var _chat_active_diff_file_count := 0
var _chat_active_diff_added_count := 0
var _chat_active_diff_removed_count := 0
var _chat_active_diff_files_visible := false
var _chat_active_diff_controls := {}
var _chat_active_work_panel: PanelContainer
var _chat_active_work_summary_label: Label
var _chat_active_work_toggle_button: Button
var _chat_active_work_body_label: Label
var _chat_active_work_text := ""
var _chat_active_work_updates := 0
var _chat_active_work_item_id := ""
var _chat_active_work_visible := false
var _chat_active_work_controls := {}
var _permissions := {
	"allow_screenshots": true,
	"allow_ai_markers": true,
	"allow_open_scene": true,
	"allow_run_current_scene": false,
	"allow_fix_selected_node": false,
	"allow_editor_navigation": true,
	"allow_editor_inspect": true,
	"allow_editor_diagnostics": true,
	"allow_clear_diagnostics": false,
	"allow_animation_preview": false,
	"allow_scene_edits": false,
	"allow_scene_save": false,
	"allow_bridge_notes": true,
	"allow_send_context": true,
	"allow_codex_chat": true,
	"allow_background_team_review": true,
}


func _enter_tree() -> void:
	_bridge_dir_abs = ProjectSettings.globalize_path(BRIDGE_DIR)
	_requests_dir_abs = ProjectSettings.globalize_path(REQUESTS_DIR)
	_responses_dir_abs = ProjectSettings.globalize_path(RESPONSES_DIR)
	_journal_dir_abs = _bridge_dir_abs.path_join("request_journal")
	_request_journal = BridgeRequestJournal.new(_journal_dir_abs, Callable(self, "_validate_bridge_path"))
	_screenshots_dir_abs = ProjectSettings.globalize_path(SCREENSHOTS_DIR)
	_annotations_dir_abs = ProjectSettings.globalize_path(ANNOTATIONS_DIR)
	_context_snapshot_abs = ProjectSettings.globalize_path(CONTEXT_SNAPSHOT_PATH)
	_bridge_state_abs = ProjectSettings.globalize_path(BRIDGE_STATE_PATH)
	_heartbeat_abs = ProjectSettings.globalize_path(HEARTBEAT_PATH)
	_permissions_abs = ProjectSettings.globalize_path(PERMISSIONS_PATH)
	_send_context_abs = ProjectSettings.globalize_path(SEND_CONTEXT_PATH)
	_notes_abs = ProjectSettings.globalize_path(NOTES_PATH)
	_host_config_abs = ProjectSettings.globalize_path(HOST_CONFIG_PATH)
	_host_config = _load_host_config()
	_addon_update.project_root = ProjectSettings.globalize_path("res://")
	_model_preference = ChatModelPreferenceModel.new(EditorInterface.get_editor_settings())
	_refresh_gc_work_status()

	_context = BridgeContext.new()
	_context.undo_redo = get_undo_redo()
	_context.permissions = _permissions
	_context.bridge_log = _bridge_log
	_context.recent_editor_actions = _recent_editor_actions
	_context.performance_history = _performance_history
	_context.diagnostics_cleared_at = _diagnostics_cleared_at
	_context.screenshots_dir_abs = _screenshots_dir_abs
	_context.annotations_dir_abs = _annotations_dir_abs
	_context.bridge_dir_abs = _bridge_dir_abs
	_context.owner_node = self
	_context.refresh_snapshot = Callable(self, "_write_context_snapshot")
	_context.log_event = Callable(self, "_log_event")
	_context.record_editor_action = Callable(self, "_record_editor_action")
	_context.ensure_bridge_dirs = Callable(self, "_ensure_bridge_dirs")
	_context.ensure_safe_directory = Callable(self, "_ensure_safe_bridge_directory")
	_context.validate_safe_path = Callable(self, "_validate_bridge_path")
	_context.append_chat_system = Callable(self, "_append_chat_system")
	_context.write_json_file = Callable(self, "_write_json_file")
	_context.current_scene_path = Callable(self, "_current_scene_path_or_null")
	_context.selected_node_paths = Callable(self, "_selected_node_paths")
	_context.iso_now = Callable(self, "_iso_now")
	_context.safe_identifier = Callable(self, "_safe_identifier")
	_context.file_timestamp = Callable(self, "_file_timestamp")
	_context.error_payload = Callable(self, "_error_payload")
	_context.diagnostics_cleared_changed = Callable(self, "_set_diagnostics_cleared_at")
	_introspection = SceneIntrospection.new(_context)
	_annotation_controller = AnnotationController.new(_context)
	_editor_diagnostics = EditorDiagnostics.new(_context, _notes_abs)
	_editor_undo = EditorUndo.new(_context)
	_spatial_bounds = SpatialBoundsModel.new(_context)
	_editor_node_lifecycle = EditorNodeLifecycle.new(_context)
	_editor_scene_mutation = EditorSceneMutation.new(_context)
	_editor_scene_save = EditorSceneSave.new(_context)
	_editor_resource_material = EditorResourceMaterial.new(_context)
	_editor_resource_browser = EditorResourceBrowser.new(_context)
	_editor_class_info = EditorClassInfo.new(_context)
	_editor_signals = EditorSignals.new(_context)
	_editor_animation = EditorAnimation.new(_context)
	_editor_script_navigation = EditorScriptNavigation.new(_context)
	_editor_asset_import = EditorAssetImport.new(_context)
	_editor_rendering_effects = EditorRenderingEffects.new(_context)
	_editor_panel_navigation = EditorPanelNavigation.new(_context)
	_editor_viewport_navigation = EditorViewportNavigation.new(_context)
	_editor_inspector_context = EditorInspectorContext.new(_context)
	_multi_view_capture = MultiViewCaptureModel.new(_context)
	_editor_control = EditorControl.new(
		_context,
		Callable(),
		MAX_EDITOR_BATCH_ACTIONS,
		CONTEXT_SNAPSHOT_PATH
	)
	_editor_control.undo_tracker = _editor_undo
	_register_editor_control_handlers()

	_ensure_bridge_dirs()
	_write_permissions()
	_record_performance_sample()
	_write_bridge_state(true)
	_write_heartbeat()
	_build_dock()
	_show_addon_update_result()
	_log_event("plugin_entered_tree", {"godot_version": Engine.get_version_info()})

	set_process(true)

	call_deferred("_refresh_context_from_startup")


func _exit_tree() -> void:
	_log_event("plugin_exiting_tree")
	_write_bridge_state(false)
	set_process(false)
	# Never stop an addon-started Host that will install a scheduled update.
	_request_one_click_host_shutdown("plugin_exit")
	_disconnect_chat_host(_addon_update.stop_owned_host_on_exit(), "plugin_exit")
	_host_pair_secret = ""
	if _host_pair_dialog != null:
		_host_pair_dialog.queue_free()
		_host_pair_dialog = null
	if _approval_popup != null:
		_approval_popup.queue_free()
		_approval_popup = null
	if _retrust_dialog != null:
		_retrust_dialog.queue_free()
		_retrust_dialog = null

	if _chat_dock != null:
		if _chat_dock.get_parent() != _dock:
			remove_control_from_docks(_chat_dock)
			_chat_dock.queue_free()
		_chat_dock = null

	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null

	if _main_screen != null:
		_main_screen.queue_free()
		_main_screen = null

	_status_labels.clear()
	_snapshot_labels.clear()
	_pending_labels.clear()
	_permission_checkboxes.clear()


func _process(delta: float) -> void:
	_poll_chat_socket(delta)
	_gc_work_refresh_elapsed += delta
	if _gc_work_refresh_elapsed >= 5.0:
		_gc_work_refresh_elapsed = 0.0
		_refresh_gc_work_status()
	if ChatStatusModel.is_foreground_busy(_chat_runtime_state):
		_chat_working_refresh_elapsed += delta
		if _chat_working_refresh_elapsed >= 1.0:
			_chat_working_refresh_elapsed = 0.0
			_update_chat_ui()
	_poll_elapsed += delta
	if _poll_elapsed >= POLL_SECONDS:
		_poll_elapsed = 0.0
		_poll_one_click_launch()
		if _bridge_owned_play_session and not EditorInterface.is_playing_scene():
			_bridge_owned_play_session = false
		_record_performance_sample()
		_poll_requests()


func _build_dock() -> void:
	_dock_style = DockStyle.resolve(EditorInterface.get_base_control())
	var dock_tabs := TabContainer.new()
	dock_tabs.custom_minimum_size = Vector2(320, 0)
	# Size the dock for the largest tab so switching tabs never resizes it.
	dock_tabs.use_hidden_tabs_for_min_size = true
	dock_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dock_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dock_tabs.name = "Codex Tools"

	var bridge_dock_panel := _create_bridge_panel()
	bridge_dock_panel.name = "Bridge"
	dock_tabs.add_child(bridge_dock_panel)

	_chat_dock = _create_chat_panel()
	_chat_dock.name = "Codex Chat"
	dock_tabs.add_child(_chat_dock)
	dock_tabs.current_tab = 1

	_dock = dock_tabs
	_dock.name = "Codex Tools"
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)

	_main_screen = _create_main_screen_panel()
	_main_screen.name = "Codex Bridge"
	_main_screen.visible = false
	EditorInterface.get_editor_main_screen().add_child(_main_screen)

	call_deferred("_focus_codex_chat_panel")
	_update_ui()

	# Pairing requires a code entered by the editor user, so connection starts
	# from the dock's Connect action. Project configuration never starts a process.


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if _main_screen != null:
		_main_screen.visible = visible


func _get_plugin_name() -> String:
	return "Codex Bridge"


func _focus_codex_chat_panel() -> void:
	if _chat_dock == null:
		return
	_activate_parent_tabs(_chat_dock)


func _focus_codex_bridge_panel() -> void:
	if _dock == null:
		return
	_activate_parent_tabs(_dock)
	if _dock is TabContainer:
		var tab_container := _dock as TabContainer
		for index in range(tab_container.get_tab_count()):
			if tab_container.get_tab_title(index) == "Bridge":
				tab_container.current_tab = index
				return


func _activate_parent_tabs(control: Control) -> void:
	var node: Node = control
	while node != null:
		if node is Control:
			(node as Control).show()
		var parent := node.get_parent()
		if parent is TabContainer:
			var tab_container := parent as TabContainer
			if node is Control:
				var tab_index := tab_container.get_tab_idx_from_control(node as Control)
				if tab_index >= 0:
					tab_container.current_tab = tab_index
		node = parent


func _control_visibility_chain(control: Control) -> Array:
	var chain: Array = []
	var node: Node = control
	while node != null:
		var entry := {
			"name": str(node.name),
			"class": node.get_class(),
		}
		if node is Control:
			var item_control := node as Control
			entry["visible"] = item_control.visible
			entry["visible_in_tree"] = item_control.is_visible_in_tree()
			entry["rect"] = _rect_payload(item_control.get_global_rect())
		var parent := node.get_parent()
		if parent is TabContainer and node is Control:
			var tab_container := parent as TabContainer
			entry["parent_tab_index"] = tab_container.get_tab_idx_from_control(node as Control)
			entry["parent_current_tab"] = tab_container.current_tab
			entry["parent_tab_count"] = tab_container.get_tab_count()
		chain.append(entry)
		node = parent
	return chain


func _create_main_screen_panel() -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	panel.add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = PLUGIN_NAME
	title.add_theme_font_size_override("font_size", 18)
	panel.add_child(title)

	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "Use the Codex Tools dock for chat, permissions and editor control. This tab only shows bridge status."
	panel.add_child(hint)

	var status_label := Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(status_label)
	_status_labels.append(status_label)

	var snapshot_label := Label.new()
	snapshot_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(snapshot_label)
	_snapshot_labels.append(snapshot_label)

	var pending_label := Label.new()
	pending_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(pending_label)
	_pending_labels.append(pending_label)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 6)
	panel.add_child(button_row)

	var chat_button := Button.new()
	chat_button.text = "Open Chat Dock"
	chat_button.tooltip_text = "Focus the Codex Chat tab in the Codex Tools dock."
	chat_button.pressed.connect(_focus_codex_chat_panel)
	button_row.add_child(chat_button)

	var bridge_button := Button.new()
	bridge_button.text = "Open Bridge Settings"
	bridge_button.tooltip_text = "Focus the Bridge settings tab in the Codex Tools dock."
	bridge_button.pressed.connect(_focus_codex_bridge_panel)
	button_row.add_child(bridge_button)

	return panel


func _create_bridge_panel() -> Control:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	scroll.add_child(margin)

	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(0, 0)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(panel)

	# One compact status line; the dock tab already names the plugin.
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 6)
	panel.add_child(status_row)
	_dock_status_dot = ColorRect.new()
	_dock_status_dot.custom_minimum_size = Vector2(8, 8)
	_dock_status_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_dock_status_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_row.add_child(_dock_status_dot)
	_dock_status_label = Label.new()
	_dock_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dock_status_label.clip_text = true
	_dock_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_dock_status_label.mouse_filter = Control.MOUSE_FILTER_PASS
	status_row.add_child(_dock_status_label)

	_addon_update_panel = AddonUpdatePanel.new()
	_addon_update_panel.check_pressed.connect(_check_addon_update)
	_addon_update_panel.update_confirmed.connect(_schedule_addon_update)
	_addon_update_panel.cancel_pressed.connect(_cancel_addon_update)
	panel.add_child(DockStyle.section_header(_dock_style, "Updates"))
	panel.add_child(_addon_update_panel)
	DockStyle.apply_icon(_addon_update_panel.check_button, _dock_style, "Reload", false, false)
	_apply_addon_update_view()

	panel.add_child(DockStyle.section_header(_dock_style, "Context"))
	var button_row := HBoxContainer.new()
	button_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button_row.add_theme_constant_override("separation", DockStyle.SPACE_S)
	panel.add_child(button_row)

	var refresh_button := Button.new()
	refresh_button.text = "Refresh"
	refresh_button.tooltip_text = "Refresh Context: capture the latest Godot project and editor state."
	refresh_button.clip_text = true
	refresh_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refresh_button.pressed.connect(_refresh_context_from_ui)
	button_row.add_child(refresh_button)

	var screenshot_button := Button.new()
	screenshot_button.text = "Screenshot"
	screenshot_button.tooltip_text = "Capture Screenshot: take an editor viewport screenshot."
	screenshot_button.clip_text = true
	screenshot_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	screenshot_button.pressed.connect(_capture_screenshot_from_ui)
	button_row.add_child(screenshot_button)

	var send_button := Button.new()
	send_button.text = "Send"
	send_button.tooltip_text = "Send Context: export current context to agent bridge files."
	send_button.clip_text = true
	send_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	send_button.pressed.connect(_send_context_to_agent_from_ui)
	button_row.add_child(send_button)
	DockStyle.apply_icon(refresh_button, _dock_style, "Reload", false, false)
	DockStyle.apply_icon(screenshot_button, _dock_style, "Image", false, false)
	DockStyle.apply_icon(send_button, _dock_style, "ArrowRight", false, false)

	panel.add_child(DockStyle.section_header(_dock_style, "Permissions"))
	var profile_row := HBoxContainer.new()
	profile_row.add_theme_constant_override("separation", 6)
	panel.add_child(profile_row)
	var profile_label := Label.new()
	profile_label.text = "Profile"
	profile_row.add_child(profile_label)
	_permission_profile_option = OptionButton.new()
	_permission_profile_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_permission_profile_option.clip_text = true
	for profile in PermissionProfileModel.profiles():
		var profile_dict := profile as Dictionary
		_permission_profile_option.add_item(str(profile_dict.get("label", "")))
		var index := _permission_profile_option.item_count - 1
		_permission_profile_option.set_item_metadata(index, str(profile_dict.get("id", "")))
		_permission_profile_option.set_item_tooltip(index, str(profile_dict.get("description", "")))
	_permission_profile_option.add_item("Custom")
	_permission_profile_option.set_item_metadata(_permission_profile_option.item_count - 1, PermissionProfileModel.CUSTOM_PROFILE_ID)
	_permission_profile_option.set_item_disabled(_permission_profile_option.item_count - 1, true)
	_permission_profile_option.item_selected.connect(_on_permission_profile_selected)
	profile_row.add_child(_permission_profile_option)

	_permission_full_trust_dialog = ConfirmationDialog.new()
	_permission_full_trust_dialog.title = "Full Trust permissions"
	_permission_full_trust_dialog.dialog_text = str(PermissionProfileModel.profile_metadata("full_trust").get("profile_description", "")) + "\n\nApply the Full Trust profile?"
	_permission_full_trust_dialog.confirmed.connect(func() -> void: _apply_permission_profile("full_trust"))
	_permission_full_trust_dialog.canceled.connect(_sync_permission_controls)
	panel.add_child(_permission_full_trust_dialog)

	var advanced := _create_advanced_permissions_section()
	panel.add_child(advanced)
	_sync_permission_controls()

	return scroll


## Individual permission checkboxes, collapsed by default. Their behaviour is
## unchanged; the profile dropdown above only sets the same keys in bulk.
func _create_advanced_permissions_section() -> Container:
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_permission_group(body, "Permissions", [
		["allow_screenshots", "Screenshots"],
		["allow_ai_markers", "AI marker attachments"],
		["allow_open_scene", "Open scene"],
		["allow_run_current_scene", "Run current scene"],
	])
	_add_permission_group(body, "Editor Control", [
		["allow_editor_navigation", "Navigate editor"],
		["allow_editor_inspect", "Inspect/select nodes"],
		["allow_editor_diagnostics", "Diagnostics capture"],
		["allow_clear_diagnostics", "Clear diagnostics"],
		["allow_animation_preview", "Animation preview"],
		["allow_scene_edits", "Scene edits via UndoRedo"],
		["allow_bridge_notes", "Bridge notes"],
	])
	_add_permission_group(body, "Chat", [
		["allow_send_context", "Send context"],
		["allow_codex_chat", "Codex chat"],
		["allow_background_team_review", "Background team review"],
	])
	var detail_label := Label.new()
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.text = "Local bridge dir: " + BRIDGE_DIR
	body.add_child(detail_label)

	if ClassDB.class_exists("FoldableContainer"):
		var foldable := ClassDB.instantiate("FoldableContainer") as Container
		foldable.name = "AdvancedPermissions"
		foldable.set("title", "Advanced permissions")
		foldable.set("folded", not _advanced_permissions_expanded)
		foldable.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		foldable.connect("folding_changed", func(is_folded: bool) -> void: _advanced_permissions_expanded = not is_folded)
		foldable.add_child(body)
		return foldable
	var section := VBoxContainer.new()
	section.name = "AdvancedPermissions"
	var toggle := Button.new()
	toggle.text = "Advanced permissions"
	toggle.toggle_mode = true
	toggle.button_pressed = _advanced_permissions_expanded
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	body.visible = _advanced_permissions_expanded
	toggle.toggled.connect(func(pressed: bool) -> void:
		_advanced_permissions_expanded = pressed
		body.visible = pressed
	)
	section.add_child(toggle)
	section.add_child(body)
	return section


func _add_permission_group(body: VBoxContainer, title: String, entries: Array) -> void:
	var group_title := Label.new()
	group_title.text = title
	body.add_child(group_title)
	for entry in entries:
		_add_permission_checkbox(body, str(entry[0]), str(entry[1]))


func _on_permission_profile_selected(index: int) -> void:
	var profile_id := str(_permission_profile_option.get_item_metadata(index))
	if profile_id == PermissionProfileModel.CUSTOM_PROFILE_ID:
		_sync_permission_controls()
		return
	# Full Trust also enables the Host full-machine Trust Session permission,
	# so it asks first. The other profiles apply directly.
	if profile_id == "full_trust" and _permission_full_trust_dialog != null:
		_permission_full_trust_dialog.popup_centered(Vector2i(460, 200))
		return
	_apply_permission_profile(profile_id)


func _apply_permission_profile(profile_id: String) -> void:
	var profile_permissions := PermissionProfileModel.permissions_for_profile(profile_id)
	for key in profile_permissions.keys():
		_permissions[key] = bool(profile_permissions[key])
	if not bool(_permissions.get("allow_screenshots", false)) and _annotation_controller != null:
		_annotation_controller.invalidate_sensitive_capture()
	_write_permissions()
	_write_bridge_state(true)
	_log_event("permission_profile_applied", {"profile": profile_id})
	_sync_permission_controls()
	_update_ui()


func _sync_permission_controls() -> void:
	for key in _permission_checkboxes.keys():
		var checkbox := _permission_checkboxes[key] as CheckBox
		if checkbox != null:
			checkbox.set_pressed_no_signal(bool(_permissions.get(key, false)))
	if _permission_profile_option == null:
		return
	var current := PermissionProfileModel.matching_profile_id(_permissions)
	for index in range(_permission_profile_option.item_count):
		if str(_permission_profile_option.get_item_metadata(index)) == current:
			_permission_profile_option.select(index)
			break
	_permission_profile_option.tooltip_text = str(PermissionProfileModel.current_profile_metadata(_permissions).get("profile_description", ""))


func _create_chat_panel() -> VBoxContainer:
	var panel_controls := ChatPanelView.create_panel_controls(ChatStatusModel.COLOR_IDLE)
	var refs := ChatPanelView.control_refs(panel_controls)
	var panel := refs.get("panel") as VBoxContainer

	_chat_status_dot = refs.get("status_dot") as ColorRect
	_chat_status_label = refs.get("status_label") as Label
	_chat_build_label = refs.get("build_label") as Label
	_apply_gc_work_status()
	_chat_trust_indicator = refs.get("trust_indicator") as Label
	_chat_advanced_toggle = refs.get("advanced_toggle") as CheckButton
	_chat_advanced_toggle.toggled.connect(_set_chat_advanced_visible)

	_chat_advanced_panel = refs.get("advanced_panel") as VBoxContainer
	_session_allow_row = HBoxContainer.new()
	_session_allow_row.visible = false
	_session_allow_label = Label.new()
	_session_allow_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_session_allow_label.mouse_filter = Control.MOUSE_FILTER_PASS
	_session_allow_row.add_child(_session_allow_label)
	var forget_button := Button.new()
	forget_button.text = "Forget"
	forget_button.tooltip_text = "Ask again before every Godot tool use (clears this session's allowed tools on the Host)."
	forget_button.pressed.connect(_forget_session_allowed_tools)
	_session_allow_row.add_child(forget_button)
	_chat_advanced_panel.add_child(_session_allow_row)

	_chat_readiness_label = refs.get("readiness_label") as Label
	_chat_thread_label = refs.get("thread_label") as Label
	_chat_new_button = refs.get("new_button") as Button
	_chat_new_button.pressed.connect(_start_new_chat_thread)
	_chat_clear_button = refs.get("clear_button") as Button
	_chat_clear_button.pressed.connect(_clear_chat_transcript)

	_chat_working_label = refs.get("working_label") as Label

	_chat_connect_button = refs.get("connect_button") as Button
	_chat_connect_button.pressed.connect(_connect_chat_host)
	_host_pair_dialog = ConfirmationDialog.new()
	_host_pair_dialog.title = "Pair with Codex Host"
	_host_pair_dialog.dialog_text = "Paste the pairing secret shown in the trusted Host launcher. It is kept only for this connection."
	_host_pair_input = LineEdit.new()
	_host_pair_input.placeholder_text = "64-character pairing secret"
	_host_pair_input.secret = true
	_host_pair_dialog.get_label().get_parent().add_child(_host_pair_input)
	_host_pair_dialog.register_text_enter(_host_pair_input)
	_host_pair_dialog.confirmed.connect(_confirm_host_pairing)
	_host_pair_dialog.canceled.connect(func() -> void:
		_host_pair_input.clear()
	)
	panel.add_child(_host_pair_dialog)
	_chat_cancel_button = refs.get("cancel_button") as Button
	_chat_cancel_button.pressed.connect(_cancel_chat_turn)
	_chat_enable_tools_button = refs.get("enable_tools_button") as Button
	_chat_enable_tools_button.pressed.connect(_enable_bridge_tools)

	_chat_model_option = refs.get("model_option") as OptionButton
	# item_selected fires only for user picks (select() does not emit it), so
	# only explicit choices are remembered.
	_chat_model_option.item_selected.connect(func(_index: int) -> void:
		_model_preference.save_model(_selected_chat_model())
		_apply_runtime_model_options_effects(_chat_model_selection_effects())
	)
	_chat_reasoning_option = refs.get("reasoning_option") as OptionButton
	_chat_reasoning_option.item_selected.connect(func(_index: int) -> void:
		_model_preference.save_effort(_selected_chat_reasoning())
		_update_chat_ui()
	)
	_populate_default_runtime_options()

	_chat_trust_button = refs.get("trust_button") as CheckButton
	_chat_trust_button.toggled.connect(_toggle_trust_session)

	_chat_input_row = refs.get("input_row") as VBoxContainer

	_chat_eye_button = refs.get("eye_button") as Button
	_chat_eye_button.pressed.connect(_open_eye_attach_dialog)

	_chat_input = refs.get("input") as TextEdit
	ChatPanelView.connect_prompt_input(
		_chat_input,
		Callable(self, "_handle_chat_input_text_changed"),
		Callable(self, "_handle_chat_input_focus_entered"),
		Callable(self, "_handle_chat_input_action"),
		Callable(self, "_handle_chat_input_key_event")
	)

	_chat_send_button = refs.get("send_button") as Button
	_chat_send_button.pressed.connect(_send_chat_message)

	_chat_composer_toggle_button = refs.get("composer_toggle_button") as Button
	_chat_composer_toggle_button.pressed.connect(_toggle_chat_composer_expanded)
	# Always-visible model/effort summary next to the composer controls.
	_chat_model_badge = Button.new()
	_chat_model_badge.flat = true
	_chat_model_badge.clip_text = true
	_chat_model_badge.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_chat_model_badge.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_chat_model_badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_model_badge.custom_minimum_size = Vector2(60, 0)
	_chat_model_badge.pressed.connect(func() -> void: _set_chat_advanced_visible(true))
	var composer_row := _chat_composer_toggle_button.get_parent()
	composer_row.add_child(_chat_model_badge)
	composer_row.move_child(_chat_model_badge, _chat_composer_toggle_button.get_index() + 1)
	_set_chat_composer_expanded(false)

	_chat_attach_context = refs.get("attach_context") as CheckBox
	_chat_attach_selected = refs.get("attach_selected") as CheckBox
	_chat_attach_screenshot = refs.get("attach_screenshot") as CheckBox

	_chat_pending_annotation_label = refs.get("pending_annotation_label") as Label

	_chat_clear_annotation_button = refs.get("clear_annotation_button") as Button
	_chat_clear_annotation_button.pressed.connect(func() -> void:
		if _annotation_controller != null:
			_annotation_controller.clear_pending(true)
	)
	if _annotation_controller != null:
		_annotation_controller.setup_pending_ui(_chat_pending_annotation_label, _chat_clear_annotation_button)

	_team_review_button = refs.get("team_review_button") as Button
	_team_review_button.pressed.connect(_run_team_review)
	_team_cancel_button = refs.get("team_cancel_button") as Button
	_team_cancel_button.pressed.connect(_cancel_team_review)
	_team_status_label = refs.get("team_status_label") as Label

	_chat_approval_panel = refs.get("approval_panel") as VBoxContainer
	_chat_approval_title = refs.get("approval_title") as Label
	_chat_approval_body = refs.get("approval_body") as TextEdit
	_chat_approval_note = refs.get("approval_note") as LineEdit
	_approval_review_button = refs.get("approval_review_button") as Button
	_chat_allow_session_button = refs.get("allow_session_button") as Button
	if _chat_allow_session_button != null:
		_chat_allow_session_button.pressed.connect(func() -> void:
			_respond_to_chat_approval(ChatApprovalModel.DECISION_APPROVE_REMEMBER)
		)
	if _approval_review_button != null:
		_approval_review_button.pressed.connect(_open_approval_review)
	_approval_popup = ChatApprovalPopup.new()
	_approval_popup.apply_style(_dock_style, _chat_theme_palette())
	_approval_popup.decision_requested.connect(_on_approval_popup_decision)
	EditorInterface.get_base_control().add_child(_approval_popup)

	_chat_approve_button = refs.get("approve_button") as Button
	_chat_approve_button.pressed.connect(func() -> void:
		_respond_to_chat_approval("approve")
	)

	_chat_approve_session_button = refs.get("approve_session_button") as Button
	_chat_approve_session_button.pressed.connect(func() -> void:
		_respond_to_chat_approval("approve_session")
	)

	_chat_reject_button = refs.get("reject_button") as Button
	_chat_reject_button.pressed.connect(func() -> void:
		_respond_to_chat_approval("reject")
	)

	_chat_revise_button = refs.get("revise_button") as Button
	_chat_revise_button.pressed.connect(func() -> void:
		_respond_to_chat_approval("revise")
	)

	_chat_log_frame = refs.get("log_frame") as Control
	_chat_log_view = refs.get("log_view") as ScrollContainer
	_chat_log_view.gui_input.connect(_on_chat_log_gui_input)
	_chat_message_list = refs.get("message_list") as VBoxContainer
	_chat_bottom_spacer = refs.get("bottom_spacer") as Control
	_chat_jump_latest_button = refs.get("jump_latest_button") as Button
	_chat_jump_latest_button.pressed.connect(_jump_chat_to_latest)
	_setup_chat_transcript_view()
	_apply_chat_dock_style()

	_set_chat_advanced_visible(false)

	if _host_config.is_empty():
		_append_chat_system("Press Connect. If Codex cannot start, refresh the addon install.")
	else:
		_append_chat_system("Looking for an already-running trusted Host. If unavailable, start it from the trusted installation, then press Connect.")
	_update_chat_ui()
	return panel


func _refresh_gc_work_status() -> void:
	var install_path := ProjectSettings.globalize_path(GcWorkChannelModel.INSTALL_MANIFEST_PATH)
	var installed := GcWorkChannelModel.load_manifest(install_path)
	var available := {}
	var channel_path := GcWorkChannelModel.channel_manifest_path(installed)
	if channel_path != "":
		available = GcWorkChannelModel.load_manifest(channel_path)
	var next_status := GcWorkChannelModel.status(installed, available)
	_addon_update.set_local(installed, next_status)
	if next_status != _gc_work_status:
		_gc_work_status = next_status
		_apply_gc_work_status()
		_apply_addon_update_view()


func _apply_addon_update_view() -> void:
	if _addon_update_panel == null:
		return
	_addon_update.set_paired(_host_paired)
	_addon_update_panel.apply(_addon_update.view(), _addon_update.confirmation_text())


func _check_addon_update() -> void:
	_refresh_gc_work_status()
	if _addon_update.begin_check():
		_send_addon_update_rpc(AddonUpdateModel.METHOD_CHECK, {})
	_apply_addon_update_view()


func _schedule_addon_update() -> void:
	var params := _addon_update.begin_schedule(OS.get_process_id(), OS.get_executable_path())
	if not params.is_empty():
		_send_addon_update_rpc(AddonUpdateModel.METHOD_SCHEDULE, params)
	_apply_addon_update_view()


func _cancel_addon_update() -> void:
	if _addon_update.begin_cancel():
		_send_addon_update_rpc(AddonUpdateModel.METHOD_CANCEL, {})
	_apply_addon_update_view()


func _send_addon_update_rpc(method: String, params: Dictionary) -> void:
	var previous_id := _chat_request_id
	_send_chat_json(method, params)
	if _chat_request_id == previous_id or not _chat_request_methods.has(_chat_request_id):
		_addon_update.apply_response(method, null, {"message": "The Codex Host connection is not open."})


func _handle_addon_update_response(method: String, message: Dictionary) -> void:
	var error_value: Variant = message.get("error", {})
	var error: Dictionary = error_value if typeof(error_value) == TYPE_DICTIONARY else {"message": "invalid error"}
	var effects := _addon_update.apply_response(method, message.get("result"), error if message.has("error") else {})
	if method == AddonUpdateModel.METHOD_CANCEL and _addon_update.phase == "idle":
		AddonUpdateModel.clear_scheduled_id(_addon_update_scheduled_id_path())
	_apply_addon_update_view()
	if bool(effects.get("close_editor", false)):
		var update_id := str(_addon_update.host_check.get("update_id", ""))
		if not AddonUpdateModel.write_scheduled_id(_addon_update_scheduled_id_path(), update_id):
			_log_event("addon_update_id_not_persisted", {"update_id": update_id})
		_log_event("addon_update_scheduled", {"update_id": update_id})
		call_deferred("_request_editor_close")


## Godot's own close request: EditorNode asks about unsaved changes and the
## user may cancel. The Bridge never saves and never force-quits.
func _request_editor_close() -> void:
	get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)


func _addon_update_scheduled_id_path() -> String:
	var paths := EditorInterface.get_editor_paths()
	return AddonUpdateModel.scheduled_id_path(paths.get_data_dir() if paths != null else "", ProjectSettings.globalize_path("res://"))


func _show_addon_update_result() -> void:
	var id_path := _addon_update_scheduled_id_path()
	var scheduled_id := AddonUpdateModel.read_scheduled_id(id_path)
	var result_path := _bridge_dir_abs.path_join(AddonUpdateModel.RESULT_FILE_NAME)
	if scheduled_id == "" or not bool(_validate_bridge_path(result_path, true).get("ok", false)):
		return
	var result := AddonUpdateModel.read_json_file(result_path)
	var notice := AddonUpdateModel.startup_notice(result, scheduled_id)
	if notice.is_empty():
		if not result.is_empty():
			_log_event("addon_update_result_ignored", {"reason": "update_id does not match the update this editor scheduled"})
		return
	AddonUpdateModel.clear_scheduled_id(id_path)
	_addon_update.notice = str(notice.get("text", ""))
	_addon_update.notice_tone = str(notice.get("tone", "neutral"))
	_append_chat_system(_addon_update.notice)
	_apply_addon_update_view()


func _apply_gc_work_status() -> void:
	if _chat_build_label == null:
		return
	_chat_build_label.text = str(_gc_work_status.get("label", "Addon: unmanaged"))
	_chat_build_label.tooltip_text = str(_gc_work_status.get("tooltip", ""))
	# Build label stays muted unless it needs attention.
	var build_tone := str(_gc_work_status.get("tone", "neutral"))
	_chat_build_label.add_theme_color_override("font_color", DockStyle.tone_color(_dock_style, "warn") if build_tone == "warn" else _dock_style.get("muted", DockStyle.FALLBACK["muted"]))


func _set_chat_advanced_visible(visible: bool) -> void:
	ChatPanelView.apply_advanced_visibility(
		_chat_advanced_panel,
		_chat_advanced_toggle,
		visible
	)


func _set_chat_composer_expanded(expanded: bool) -> void:
	_chat_composer_expanded = expanded
	_refresh_chat_composer_height()


func _handle_chat_input_text_changed() -> void:
	_refresh_chat_composer_height(true)


func _handle_chat_input_focus_entered() -> void:
	if _chat_input == null:
		return
	if not _chat_composer_expanded:
		var rendered_height := _chat_input.get_global_rect().size.y
		if ChatInputModel.should_rescue_collapsed_composer(rendered_height, ChatPanelView.INPUT_MIN_HEIGHT):
			_chat_composer_expanded = true
	_refresh_chat_composer_height()


func _refresh_chat_composer_height(auto_expand_from_text := false) -> void:
	if _chat_input == null or _chat_input_row == null:
		return
	var input_width := _chat_input.get_rect().size.x
	if input_width <= 0.0:
		input_width = _chat_input.custom_minimum_size.x
	if auto_expand_from_text and not _chat_composer_expanded:
		var rendered_height := _chat_input.get_global_rect().size.y
		if ChatInputModel.should_rescue_collapsed_composer(rendered_height, ChatPanelView.INPUT_MIN_HEIGHT):
			_chat_composer_expanded = true
	if auto_expand_from_text and not _chat_composer_expanded:
		if ChatInputModel.should_auto_expand_composer(_chat_input.text, input_width):
			_chat_composer_expanded = true
	var height := ChatInputModel.composer_height_for_text_width(
		_chat_input.text,
		_chat_composer_expanded,
		ChatPanelView.INPUT_MIN_HEIGHT,
		ChatPanelView.INPUT_AUTO_HEIGHT,
		ChatPanelView.INPUT_EXPANDED_HEIGHT,
		input_width
	)
	ChatPanelView.apply_composer_height(
		_chat_input_row,
		_chat_input,
		_chat_composer_toggle_button,
		height,
		_chat_composer_expanded
	)
	_chat_input_row.queue_sort()
	_chat_input.queue_redraw()


func _toggle_chat_composer_expanded() -> void:
	_set_chat_composer_expanded(not _chat_composer_expanded)


func _handle_chat_input_enter(shift_pressed: bool) -> void:
	_apply_chat_input_action_effects(ChatInputModel.action_effect_plan(
		ChatInputModel.ACTION_NEWLINE if shift_pressed else ChatInputModel.ACTION_SEND,
		_chat_input != null
	).get("effects", []) as Array)


func _handle_chat_input_action(action: String) -> void:
	var plan := ChatInputModel.action_effect_plan(action, _chat_input != null)
	_apply_chat_input_action_effects(plan.get("effects", []) as Array)


func _apply_chat_input_action_effects(effects: Array) -> void:
	for effect in effects:
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		var effect_dict := effect as Dictionary
		match str(effect_dict.get("action", "")):
			"set_composer_expanded":
				_chat_composer_expanded = bool(effect_dict.get("expanded", _chat_composer_expanded))
			"insert_text_at_caret":
				if _chat_input != null:
					_chat_input.insert_text_at_caret(str(effect_dict.get("text", "")))
			"refresh_composer_height":
				_refresh_chat_composer_height(bool(effect_dict.get("auto_expand_from_text", false)))
			"send_message":
				_send_chat_message()


func _handle_chat_input_key_event(key_event: InputEventKey) -> bool:
	var shift_down := key_event.shift_pressed or Input.is_key_pressed(KEY_SHIFT)
	var action := ChatInputModel.key_event_action_with_shift_override(key_event, shift_down)
	if action == ChatInputModel.ACTION_IGNORE:
		return false
	if action == ChatInputModel.ACTION_NEWLINE:
		_handle_chat_input_enter(true)
	else:
		_handle_chat_input_enter(false)
	return true


func _dispatch_chat_input_key_event(key_event: InputEventKey) -> bool:
	if _chat_input != null and _chat_input.has_method("handle_key_event"):
		return bool(_chat_input.call("handle_key_event", key_event, key_event.shift_pressed or Input.is_key_pressed(KEY_SHIFT)))
	return _handle_chat_input_key_event(key_event)


func _setup_chat_transcript_view() -> void:
	if _chat_transcript_view == null:
		_chat_transcript_view = ChatTranscriptView.new()
	_chat_transcript_view.setup(
		_chat_message_list,
		_chat_bottom_spacer,
		Callable(self, "_scroll_chat_to_bottom"),
		Callable(self, "_append_chat_detail"),
		{
			"max_message_chars": CHAT_MAX_MESSAGE_CHARS,
			"collapse_chars": CHAT_COLLAPSE_CHARS,
			"collapse_lines": CHAT_COLLAPSE_LINES,
			"preview_chars": CHAT_PREVIEW_CHARS,
			"preview_lines": CHAT_PREVIEW_LINES,
			"assistant_section_chars": CHAT_ASSISTANT_SECTION_CHARS,
			"assistant_flush_interval_msec": CHAT_ASSISTANT_FLUSH_INTERVAL_MSEC,
			"work_preview_chars": CHAT_WORK_PREVIEW_CHARS,
			"work_preview_lines": CHAT_WORK_PREVIEW_LINES,
			"palette": _chat_theme_palette(),
			"code_font": _dock_style.get("code_font"),
		}
	)


func _add_permission_checkbox(panel: VBoxContainer, key: String, label: String) -> void:
	var checkbox := CheckBox.new()
	checkbox.text = label
	checkbox.button_pressed = bool(_permissions.get(key, false))
	checkbox.toggled.connect(func(pressed: bool) -> void:
		_permissions[key] = pressed
		if key == "allow_screenshots" and not pressed and _annotation_controller != null:
			_annotation_controller.invalidate_sensitive_capture()
		_write_permissions()
		_write_bridge_state(true)
		_log_event("permission_changed", {"permission": key, "enabled": pressed})
		_sync_permission_controls()
		_update_ui()
	)
	_permission_checkboxes[key] = checkbox
	panel.add_child(checkbox)


func _refresh_context_from_startup() -> void:
	_write_context_snapshot("startup")


func _refresh_context_from_ui() -> void:
	_write_context_snapshot("ui")


func _capture_screenshot_from_ui() -> void:
	if not _permission_enabled("allow_screenshots"):
		_last_status = "Screenshot permission disabled"
		_log_event("permission_denied", {"permission": "allow_screenshots", "source": "ui"})
		_update_ui()
		return

	var result := _capture_viewport_screenshot("ui")
	if result.get("ok", false):
		_last_status = "Screenshot captured"
		_write_context_snapshot("screenshot")
	else:
		_last_status = "Screenshot failed: " + str(result.get("error", {}).get("message", "unknown error"))
		_update_ui()


func _open_eye_attach_dialog() -> void:
	if _annotation_controller != null:
		_annotation_controller.open_eye_attach_dialog()


func _clear_pending_annotation(show_status: bool = false) -> void:
	if _annotation_controller != null:
		_annotation_controller.clear_pending(show_status)


func _update_pending_annotation_ui() -> void:
	if _annotation_controller != null:
		_annotation_controller.update_pending_ui()

func _update_ui() -> void:
	var pending_count := str(_count_pending_requests())
	for label in _status_labels:
		if label != null:
			label.text = "Status: " + _last_status
	for label in _snapshot_labels:
		if label != null:
			label.text = "Last snapshot: " + _last_snapshot_time
	for label in _pending_labels:
		if label != null:
			label.text = "Pending requests: " + pending_count
	if _dock_status_label != null:
		var summary := BridgeDockStatusModel.summary(_last_status, _last_snapshot_time, int(pending_count), int(Time.get_time_zone_from_system().get("bias", 0)))
		_dock_status_label.text = str(summary.get("text", ""))
		_dock_status_label.tooltip_text = str(summary.get("tooltip", ""))
		_dock_status_dot.color = DockStyle.tone_color(_dock_style, str(summary.get("tone", "ok")))
	_update_chat_ui()


func _count_pending_requests() -> int:
	if not bool(_validate_bridge_path(_requests_dir_abs, false).get("ok", false)):
		return 0
	var pending := 0
	for file_name in _list_files_with_extension(_requests_dir_abs, ".json", MAX_REQUEST_QUEUE_FILES + 1):
		var response_path := _responses_dir_abs.path_join(str(file_name))
		if not FileAccess.file_exists(response_path):
			pending += 1
	return pending


func _ensure_bridge_dirs() -> void:
	for dir_path in [_bridge_dir_abs, _requests_dir_abs, _responses_dir_abs, _journal_dir_abs, _screenshots_dir_abs, _annotations_dir_abs, _bridge_dir_abs.path_join("artifacts")]:
		if dir_path == "":
			continue
		var result := _ensure_safe_bridge_directory(dir_path)
		if not bool(result.get("ok", false)):
			_log_event("directory_error", {"path": dir_path, "error": result.get("error", {})})


func _ensure_safe_bridge_directory(dir_path: String) -> Dictionary:
	return BridgePathGuard.ensure_project_directory(ProjectSettings.globalize_path("res://"), dir_path)


func _validate_bridge_path(path_value: String, allow_missing_tail := false) -> Dictionary:
	return BridgePathGuard.validate_project_path(ProjectSettings.globalize_path("res://"), path_value, allow_missing_tail)


func _write_context_snapshot(reason: String) -> Dictionary:
	_ensure_bridge_dirs()
	_write_heartbeat()

	var snapshot := _collect_context_snapshot(reason)
	var write_result := _write_json_file(_context_snapshot_abs, snapshot)
	if write_result.get("ok", false):
		_last_snapshot_time = str(snapshot.get("generated_at", "unknown"))
		_last_status = "Context snapshot written"
		_log_event("context_snapshot_written", {
			"path": CONTEXT_SNAPSHOT_PATH,
			"reason": reason,
			"generated_at": _last_snapshot_time,
		})
		_write_bridge_state(true)
	else:
		_last_status = "Snapshot write failed: " + str(write_result.get("error", {}).get("message", "unknown error"))
		_log_event("context_snapshot_failed", write_result)

	_update_ui()
	return snapshot


func _send_context_to_agent_from_ui() -> void:
	if not _permission_enabled("allow_send_context"):
		_last_status = "Send context permission disabled"
		_log_event("permission_denied", {"permission": "allow_send_context", "source": "ui"})
		_update_ui()
		return

	var snapshot := _write_context_snapshot("send_context")
	var payload := {
		"protocol_version": PROTOCOL_VERSION,
		"created_at": _iso_now(),
		"context_snapshot_path": CONTEXT_SNAPSHOT_PATH,
		"context_snapshot_absolute_path": _context_snapshot_abs,
		"current_scene": snapshot.get("current_scene", {}),
		"selected_node_paths": _selected_node_paths(),
		"scene_node_count": snapshot.get("scene_tree", {}).get("node_count", 0),
		"note": "Local handoff marker for Codex agent context.",
	}
	_write_json_file(_send_context_abs, payload)
	_log_event("context_sent_to_agent", payload)
	_last_status = "Context handoff written"
	_update_ui()


func _collect_context_snapshot(reason: String) -> Dictionary:
	return _introspection.collect_context_snapshot(reason)


func _set_diagnostics_cleared_at(value: String) -> void:
	_diagnostics_cleared_at = value


func _project_payload() -> Dictionary:
	return _introspection._project_payload()
func _current_scene_payload(scene_root: Node) -> Dictionary:
	return _introspection._current_scene_payload(scene_root)
func _open_scenes_payload() -> Array:
	return _introspection._open_scenes_payload()
func _editor_state_payload(scene_root: Node) -> Dictionary:
	return _introspection._editor_state_payload(scene_root)
func _selected_files_payload() -> Array:
	return _introspection._selected_files_payload()
func _editor_capabilities_payload() -> Dictionary:
	return _introspection._editor_capabilities_payload()
func _scene_tree_payload(scene_root: Node) -> Dictionary:
	return _introspection._scene_tree_payload(scene_root)
func _scene_limits_payload() -> Dictionary:
	return _introspection._scene_limits_payload()
func _summary_limits_payload() -> Dictionary:
	return _introspection._summary_limits_payload()
func _node_tree_payload(node: Node, scene_root: Node, state: Dictionary) -> Dictionary:
	return _introspection._node_tree_payload(node, scene_root, state)
func _basic_node_payload(node: Node, scene_root: Node) -> Dictionary:
	return _introspection._basic_node_payload(node, scene_root)
func _node_ref_payload(node: Node, scene_root: Node) -> Dictionary:
	return _introspection._node_ref_payload(node, scene_root)
func _node_3d_hints(node: Node) -> Dictionary:
	return _introspection._node_3d_hints(node)
func _transform_summary(node_3d: Node3D) -> Dictionary:
	return _introspection._transform_summary(node_3d)
func _camera_projection_name(projection: int) -> String:
	return _introspection._camera_projection_name(projection)
func _color_to_hex(value: Variant) -> Variant:
	return _introspection._color_to_hex(value)
func _resolve_shader_material_target(node: Node, slot_kind: String, surface_index: int) -> Dictionary:
	if _editor_resource_material == null:
		return _err("editor_resource_material_unavailable", "Editor resource/material service is not initialized.")
	return _editor_resource_material.resolve_shader_material_target(node, slot_kind, surface_index)
func _resolve_material_assignment_target(node: Node, slot_kind: String, surface_index: int) -> Dictionary:
	if _editor_resource_material == null:
		return _err("editor_resource_material_unavailable", "Editor resource/material service is not initialized.")
	return _editor_resource_material.resolve_material_assignment_target(node, slot_kind, surface_index)
func _add_material_assignment_undo(undo: EditorUndoRedoManager, node: Node, target: Dictionary, new_material: Material, old_material: Variant) -> void:
	EditorResourceMaterial.add_material_assignment_undo(undo, node, target, new_material, old_material)
func _texture_resource_extensions() -> Array:
	return EditorResourceMaterial.texture_resource_extensions()
func _selected_nodes_payload(scene_root: Node) -> Array:
	return _introspection._selected_nodes_payload(scene_root)
func _selected_node_payload(node: Node, scene_root: Node) -> Dictionary:
	return _introspection._selected_node_payload(node, scene_root)
func _bounded_property_summary(object: Object) -> Array:
	return _introspection._bounded_property_summary(object)
func _resource_status_payload() -> Dictionary:
	return _introspection._resource_status_payload()
func _collect_resource_files(directory: EditorFileSystemDirectory, resources: Array, invalid_imports: Array, state: Dictionary) -> void:
	_introspection._collect_resource_files(directory, resources, invalid_imports, state)
func _editor_output_payload() -> Dictionary:
	return _introspection._editor_output_payload()
func _gameplay_context_payload() -> Dictionary:
	return _introspection._gameplay_context_payload()
func _input_actions_payload() -> Array:
	return _introspection._input_actions_payload()
func _input_event_summary(event: Variant) -> Dictionary:
	return _introspection._input_event_summary(event)
func _autoloads_payload() -> Array:
	return _introspection._autoloads_payload()
func _layer_names_payload() -> Dictionary:
	return _introspection._layer_names_payload()
func _important_project_settings_payload() -> Dictionary:
	return _introspection._important_project_settings_payload()
func _script_inventory_payload() -> Dictionary:
	return _introspection._script_inventory_payload()
func _collect_script_inventory(directory: EditorFileSystemDirectory, scripts: Array, state: Dictionary) -> void:
	_introspection._collect_script_inventory(directory, scripts, state)
func _script_summary(script_path: String) -> Dictionary:
	return _introspection._script_summary(script_path)
func _scan_script_line(line: String, line_number: int, summary: Dictionary) -> void:
	_introspection._scan_script_line(line, line_number, summary)
func _script_symbol_payload(line: String, line_number: int) -> Dictionary:
	return _introspection._script_symbol_payload(line, line_number)
func _performance_payload() -> Dictionary:
	return _introspection._performance_payload()
func _record_performance_sample() -> Dictionary:
	return _introspection._record_performance_sample()
func _performance_monitors_payload() -> Dictionary:
	return _introspection._performance_monitors_payload()
func _screenshots_payload() -> Array:
	return _introspection._screenshots_payload()
func _capture_viewport_screenshot(reason: String) -> Dictionary:
	if not _permission_enabled("allow_screenshots"):
		var permission_error := _error_payload("permission_denied", "Screenshot permission is disabled in the Codex Bridge dock.")
		_log_event("permission_denied", {"permission": "allow_screenshots", "source": reason})
		return {"ok": false, "error": permission_error}
	_ensure_bridge_dirs()

	if DisplayServer.get_name().to_lower() == "headless":
		var headless_error := _error_payload("viewport_image_unavailable", "3D editor viewport image is unavailable in headless display mode.")
		_log_event("screenshot_failed", headless_error)
		return {"ok": false, "error": headless_error}

	var viewport := EditorInterface.get_editor_viewport_3d(0)
	if viewport == null:
		var no_viewport_error := _error_payload("viewport_unavailable", "3D editor viewport 0 is unavailable.")
		_log_event("screenshot_failed", no_viewport_error)
		return {"ok": false, "error": no_viewport_error}

	var texture := viewport.get_texture()
	if texture == null:
		var no_texture_error := _error_payload("viewport_texture_unavailable", "3D editor viewport texture is unavailable.")
		_log_event("screenshot_failed", no_texture_error)
		return {"ok": false, "error": no_texture_error}

	var image := texture.get_image()
	if image == null or image.is_empty():
		var no_image_error := _error_payload("viewport_image_unavailable", "3D editor viewport image is empty.")
		_log_event("screenshot_failed", no_image_error)
		return {"ok": false, "error": no_image_error}

	var file_name := "viewport_3d_" + _file_timestamp() + ".png"
	var abs_path := _screenshots_dir_abs.path_join(file_name)
	var path_guard := _validate_bridge_path(abs_path, true)
	if not bool(path_guard.get("ok", false)):
		return {"ok": false, "error": path_guard.get("error", _error_payload("screenshot_path_rejected", "Screenshot path is unsafe."))}
	var err := image.save_png(abs_path)
	if err != OK:
		var save_error := _error_payload("screenshot_save_failed", "Failed to save viewport screenshot: " + error_string(err))
		_log_event("screenshot_failed", save_error)
		return {"ok": false, "error": save_error}

	var camera := viewport.get_camera_3d()
	var screenshot := _screenshot_metadata(file_name, abs_path, image.get_width(), image.get_height(), reason, camera)

	_log_event("screenshot_captured", screenshot)
	return {
		"ok": true,
		"screenshot": screenshot,
	}


func _camera_payload(camera: Camera3D) -> Variant:
	return _introspection._camera_payload(camera)
func _screenshot_metadata(file_name: String, abs_path: String, width: int, height: int, reason: String, camera: Camera3D) -> Dictionary:
	return _introspection._screenshot_metadata(file_name, abs_path, width, height, reason, camera)
func _connect_chat_host() -> void:
	if _host_pair_secret == "" and not _host_paired:
		if _one_click_waiting:
			_append_chat_system("Starting the Codex Host…")
			return
		if _one_click_secret != "" and not OS.is_process_running(_one_click_launcher_pid):
			_forget_one_click_session()
		if _one_click_secret != "" and _one_click_url != "":
			# The Host this editor launched: pair again with its in-memory secret.
			_host_pair_secret = _one_click_secret
		elif not _try_one_click_launch():
			if _host_pair_dialog != null:
				_host_pair_dialog.popup_centered(Vector2i(520, 180))
			return
		else:
			return
	var socket_present := _chat_socket != null
	var socket_state := WebSocketPeer.STATE_CLOSED
	if socket_present:
		socket_state = _chat_socket.get_ready_state()
	var connect_plan := ChatSocketController.connect_request_effect_plan(
		_permission_enabled("allow_codex_chat"),
		socket_present,
		socket_state
	)
	_apply_chat_connect_request_effects(connect_plan.get("effects", []) as Array)


func _confirm_host_pairing() -> void:
	if _host_pair_input == null:
		return
	var supplied := _host_pair_input.text.strip_edges()
	_host_pair_input.clear()
	if supplied.length() != 64 or not supplied.is_valid_hex_number():
		_append_chat_system("Pairing secret must be 64 hexadecimal characters from the Host launcher.")
		return
	_host_pair_secret = supplied.to_lower()
	_connect_chat_host()


func _apply_chat_connect_request_effects(effects: Array) -> void:
	for effect in effects:
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		var effect_dict := effect as Dictionary
		match str(effect_dict.get("action", "")):
			"apply_connect_request_state":
				var state := effect_dict.get("state", {}) as Dictionary
				_host_connect_autostart_allowed = bool(state.get("host_connect_autostart_allowed", _host_connect_autostart_allowed))
				_host_launch_attempted = bool(state.get("host_launch_attempted", _host_launch_attempted))
				_chat_auto_enable_tools_requested = bool(state.get("chat_auto_enable_tools_requested", _chat_auto_enable_tools_requested))
			"attempt_connect":
				_attempt_chat_socket_connect(bool(effect_dict.get("log_attempt", true)))
			"reattach_project":
				_reattach_chat_project()
			"system_message":
				_append_chat_system(str(effect_dict.get("message", "")))
			"update_ui":
				_update_chat_ui()


func _attempt_chat_socket_connect(log_attempt: bool) -> void:
	var one_click := _one_click_url != "" and _one_click_secret != "" and _host_pair_secret == _one_click_secret
	var target_url := _one_click_url if one_click else _codex_host_url
	if not one_click and (_host_config_status != "manual_start_required" or _codex_host_url == ""):
		_chat_connection_state = "disconnected"
		_append_chat_system(_host_config_message)
		_update_chat_ui()
		return
	_chat_socket = WebSocketPeer.new()
	_host_pairing_sent = false
	_host_paired = false
	_host_pair_client_nonce = ""
	_host_pair_server_nonce = ""
	var err := _chat_socket.connect_to_url(target_url)
	var connect_plan := ChatSocketController.connect_result_effect_plan(err, target_url, log_attempt)
	_apply_chat_connect_result_effects(connect_plan.get("effects", []))


func _apply_chat_connect_result_effects(effects: Array) -> void:
	for effect in effects:
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		var effect_dict := effect as Dictionary
		match str(effect_dict.get("action", "")):
			"apply_state_patch":
				var patch := effect_dict.get("patch", {}) as Dictionary
				_chat_connection_state = str(patch.get("connection_state", _chat_connection_state))
				_chat_runtime_state = str(patch.get("runtime_state", _chat_runtime_state))
			"system_message":
				_append_chat_system(str(effect_dict.get("message", "")))
			"detail_message":
				_append_chat_detail(str(effect_dict.get("message", "")))
			"update_ui":
				_update_chat_ui()


func _disconnect_chat_host(stop_owned_host := false, reason := "disconnect") -> void:
	_host_pair_secret = ""
	_host_pairing_sent = false
	_host_paired = false
	_host_pair_client_nonce = ""
	_host_pair_server_nonce = ""
	if _host_pair_input != null:
		_host_pair_input.clear()
	var disconnect_plan := ChatSocketController.disconnect_request_effect_plan(stop_owned_host, _chat_socket != null, _chat_runtime_state, reason)
	_apply_chat_disconnect_request_effects(disconnect_plan.get("effects", []) as Array)


func _apply_chat_disconnect_request_effects(effects: Array) -> void:
	for effect in effects:
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		var effect_dict := effect as Dictionary
		match str(effect_dict.get("action", "")):
			"stop_owned_host":
				_stop_owned_codex_host(str(effect_dict.get("reason", "disconnect")))
			"close_socket":
				if _chat_socket != null:
					_chat_socket.close()
			"clear_socket":
				_chat_socket = null
			"apply_disconnect_state":
				var state := effect_dict.get("state", {}) as Dictionary
				_host_start_in_progress = bool(state.get("host_start_in_progress", false))
				_host_connect_autostart_allowed = bool(state.get("host_connect_autostart_allowed", false))
				_host_launch_attempted = bool(state.get("host_launch_attempted", false))
				_chat_connection_state = str(state.get("connection_state", "disconnected"))
				_chat_runtime_state = str(state.get("runtime_state", "disconnected"))
				_chat_trust_mode = str(state.get("trust_mode", "off"))
				_chat_auto_enable_tools_requested = bool(state.get("chat_auto_enable_tools_requested", false))
			"update_ui":
				_update_chat_ui()


## Returns true when a trusted launch started (the caller waits for it). Returns
## false, after explaining why, when the manual pairing dialog should be used.
func _try_one_click_launch() -> bool:
	var local_app_data := OS.get_environment("LOCALAPPDATA")
	var record := TrustedHostLaunchModel.read_json(TrustedHostLaunchModel.record_path(local_app_data))
	var validation := TrustedHostLaunchModel.validate_record(record, ProjectSettings.globalize_path("res://"))
	if not bool(validation.get("ok", false)):
		if str(validation.get("error_code", "")) == "missing":
			_append_chat_system("One-click Connect is not set up yet. " + TrustedHostLaunchModel.setup_text() + "\nOr paste a pairing code now.")
		else:
			_append_chat_system("One-click Connect is unavailable: " + str(validation.get("message", "")) + " Paste a pairing code instead.")
		return false
	var trusted := validation.get("record", {}) as Dictionary
	if _host_port_listening(int(trusted.get("port", 0))):
		_append_chat_system("A Codex Host is already running; paste its pairing code or wait until it stops.")
		return false
	return _launch_trusted_host(trusted)


func _launch_trusted_host(record: Dictionary) -> bool:
	if not TrustedHostLaunchModel.start_script_matches(record):
		_append_chat_system(TrustedHostLaunchModel.script_changed_message())
		return false
	var secret := Crypto.new().generate_random_bytes(32).hex_encode()
	var args := TrustedHostLaunchModel.launch_args(record, ProjectSettings.globalize_path("res://"), OS.get_process_id())
	# The secret reaches the launcher only through its inherited environment.
	OS.set_environment(TrustedHostLaunchModel.SECRET_ENV, secret)
	var launcher_pid := OS.create_process(str(record.get("powershell_executable", "")), args, false)
	OS.unset_environment(TrustedHostLaunchModel.SECRET_ENV)
	if launcher_pid <= 0:
		_append_chat_system("Could not start the trusted Codex Host launcher. Paste a pairing code instead.")
		return false
	_one_click_record = record
	_one_click_secret = secret
	_one_click_url = ""
	_one_click_launcher_pid = launcher_pid
	_one_click_host_pid = -1
	_one_click_launched_unix = Time.get_unix_time_from_system()
	_one_click_deadline_msec = Time.get_ticks_msec() + int(TrustedHostLaunchModel.LAUNCH_TIMEOUT_SECONDS * 1000.0)
	_one_click_waiting = true
	_chat_connection_state = "connecting"
	_append_chat_system("Starting the trusted Codex Host…")
	_log_event("codex_host_one_click_launch", {"launcher_pid": launcher_pid, "install_root": str(record.get("install_root", ""))})
	_update_chat_ui()
	return true


func _poll_one_click_launch() -> void:
	if not _one_click_waiting:
		return
	var status_path := TrustedHostLaunchModel.launch_status_path(OS.get_environment("LOCALAPPDATA"), OS.get_process_id())
	var state := TrustedHostLaunchModel.launch_state(TrustedHostLaunchModel.read_json(status_path), _one_click_launched_unix, _one_click_record)
	match str(state.get("state", "waiting")):
		"ready":
			_one_click_waiting = false
			_one_click_owned = true
			var status := TrustedHostLaunchModel.read_json(status_path)
			_one_click_host_pid = int(status.get("host_pid", -1)) if typeof(status.get("host_pid")) in [TYPE_INT, TYPE_FLOAT] else -1
			_one_click_url = ChatHostConfigModel.host_url(int(_one_click_record.get("port", 0)))
			_host_pair_secret = _one_click_secret
			_connect_chat_host()
		"fingerprint_changed":
			_end_one_click_launch("")
			_show_retrust_dialog(str(state.get("new_fingerprint", "")))
		"untrusted":
			_end_one_click_launch("The Host installation is not trusted: " + str(state.get("message", "")) + "\nSetup: " + TrustedHostLaunchModel.setup_text())
		"failed":
			_end_one_click_launch("Codex Host failed to start: " + str(state.get("message", "")))
		_:
			if Time.get_ticks_msec() > _one_click_deadline_msec:
				# Keep the secret: if the Host comes up later, Connect pairs with it.
				_one_click_waiting = false
				_one_click_url = ChatHostConfigModel.host_url(int(_one_click_record.get("port", 0)))
				_chat_connection_state = "disconnected"
				_append_chat_system("The Codex Host did not report ready within %d s. Press Connect to retry. Launch status: %s" % [int(TrustedHostLaunchModel.LAUNCH_TIMEOUT_SECONDS), status_path])
				_update_chat_ui()


func _end_one_click_launch(message: String) -> void:
	var record := _one_click_record
	_forget_one_click_session()
	_one_click_record = record
	_chat_connection_state = "disconnected"
	if message != "":
		_append_chat_system(message)
	_update_chat_ui()


func _forget_one_click_session() -> void:
	_one_click_secret = ""
	_one_click_url = ""
	_one_click_waiting = false
	_one_click_owned = false
	_one_click_launcher_pid = -1
	_one_click_host_pid = -1


func _show_retrust_dialog(new_fingerprint: String) -> void:
	# In-addon re-trust only when the start script is still the trusted one and
	# the launcher reported a well-formed new fingerprint to confirm.
	if new_fingerprint == "" or not TrustedHostLaunchModel.start_script_matches(_one_click_record):
		_append_chat_system(TrustedHostLaunchModel.script_changed_message() if new_fingerprint != "" else "The Host installation changed and no new fingerprint was reported. " + TrustedHostLaunchModel.setup_text())
		return
	_retrust_fingerprint = new_fingerprint
	if _retrust_dialog == null:
		_retrust_dialog = ConfirmationDialog.new()
		_retrust_dialog.title = "Trust updated Codex Host?"
		_retrust_dialog.ok_button_text = "Trust and connect"
		_retrust_dialog.confirmed.connect(_retrust_and_connect)
		_retrust_dialog.canceled.connect(func() -> void: _append_chat_system("The changed Host installation was not trusted. Paste a pairing code to connect manually."))
		EditorInterface.get_base_control().add_child(_retrust_dialog)
	_retrust_dialog.dialog_text = TrustedHostLaunchModel.retrust_dialog_text(_one_click_record, new_fingerprint)
	_retrust_dialog.popup_centered(Vector2i(560, 220))


## Runs `-Trust` with the executables of the existing record only after the user
## confirmed the dialog, then connects again.
func _retrust_and_connect() -> void:
	var record := _one_click_record
	if record.is_empty() or not TrustedHostLaunchModel.is_sha256_hex(_retrust_fingerprint):
		return
	if not TrustedHostLaunchModel.start_script_matches(record):
		_append_chat_system(TrustedHostLaunchModel.script_changed_message())
		return
	var output: Array = []
	var exit_code := OS.execute(str(record.get("powershell_executable", "")), TrustedHostLaunchModel.trust_args(record, _retrust_fingerprint), output, true)
	if exit_code != 0:
		var first_line := TrustedHostLaunchModel.plain_message(str(output[0]).strip_edges().get_slice("\n", 0)) if not output.is_empty() else ""
		_append_chat_system("Re-trusting the Host failed (exit %d). %s" % [exit_code, first_line])
		return
	_append_chat_system("Trusted the updated Host installation.")
	_connect_chat_host()


## Ask the Host this editor launched to stop, unless an addon update is pending
## (the Host installs it after the editor exits). The launcher also stops the
## Host when this editor process exits.
func _request_one_click_host_shutdown(reason: String) -> void:
	if not _one_click_owned or not _addon_update.stop_owned_host_on_exit():
		return
	if _chat_socket == null or _chat_socket.get_ready_state() != WebSocketPeer.STATE_OPEN or not _host_paired:
		return
	_send_chat_json("host.shutdown", {"reason": reason, "owner": "godot_addon", "process_id": _one_click_host_pid})
	_chat_socket.poll()


func _host_port_listening(port: int) -> bool:
	if port < 1 or port > 65535:
		return false
	var peer := StreamPeerTCP.new()
	if peer.connect_to_host("127.0.0.1", port) != OK:
		return false
	var deadline := Time.get_ticks_msec() + 300
	while Time.get_ticks_msec() < deadline:
		peer.poll()
		var status := peer.get_status()
		if status == StreamPeerTCP.STATUS_CONNECTED:
			peer.disconnect_from_host()
			return true
		if status == StreamPeerTCP.STATUS_ERROR or status == StreamPeerTCP.STATUS_NONE:
			return false
		OS.delay_msec(10)
	peer.disconnect_from_host()
	return false


func _stop_owned_codex_host(reason: String) -> void:
	var stop_plan := ChatSocketController.owned_host_stop_plan(
		_host_start_process_id,
		reason,
		_chat_socket != null and _chat_socket.get_ready_state() == WebSocketPeer.STATE_OPEN
	)
	if str(stop_plan.get("action", "none")) == "none":
		return

	var process_id := int(stop_plan.get("process_id", _host_start_process_id))
	var graceful_requested := false
	if bool(stop_plan.get("send_shutdown", false)):
		_send_chat_json(str(stop_plan.get("shutdown_method", "host.shutdown")), stop_plan.get("shutdown_params", {}))
		_chat_socket.poll()
		graceful_requested = true
		OS.delay_msec(CHAT_HOST_SHUTDOWN_GRACE_MSEC)

	var process_alive := OS.is_process_running(process_id)
	var kill_error := OK
	if process_alive:
		kill_error = OS.kill(process_id)
	var complete_state := ChatSocketController.owned_host_stop_complete_state(process_id, reason, graceful_requested, process_alive, kill_error)
	_host_start_process_id = int(complete_state.get("host_start_process_id", -1))
	_host_start_in_progress = bool(complete_state.get("host_start_in_progress", false))
	_host_start_retry_elapsed = float(complete_state.get("host_start_retry_elapsed", 0.0))
	_host_start_deadline_msec = int(complete_state.get("host_start_deadline_msec", 0))
	_log_event(str(complete_state.get("log_event", "codex_host_stop_requested")), complete_state.get("log_payload", {}))


func _poll_chat_socket(delta: float) -> void:
	if not _permission_enabled("allow_codex_chat"):
		return

	if _chat_socket == null:
		_poll_host_start_retry(delta)
		return

	_chat_socket.poll()
	var poll_plan := ChatSocketController.poll_socket_effect_plan(
		_chat_socket.get_ready_state(),
		_chat_connection_state,
		_chat_runtime_state,
		_host_connect_autostart_allowed,
		_host_launch_attempted,
		_host_start_in_progress,
		ProjectSettings.globalize_path("res://"),
		_bridge_dir_abs
	)
	if _apply_chat_poll_socket_effects(poll_plan.get("effects", [])):
		return


func _apply_chat_poll_socket_effects(effects: Array) -> bool:
	for effect in effects:
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		var effect_dict := effect as Dictionary
		match str(effect_dict.get("action", "")):
			"apply_open_socket_effects":
				_apply_chat_open_socket_effects(effect_dict.get("effects", []))
			"apply_closed_socket_effects":
				if _apply_chat_closed_socket_effects(effect_dict.get("effects", [])):
					return true
			"apply_poll_state":
				var state := effect_dict.get("state", {}) as Dictionary
				_chat_connection_state = str(state.get("connection_state", _chat_connection_state))
			"drain_packets":
				_drain_chat_packets()
	return false


func _apply_chat_open_socket_effects(effects: Array) -> void:
	if not _host_paired:
		if not _host_pairing_sent and _host_pair_secret != "":
			_host_pairing_sent = true
			_host_pair_client_nonce = Crypto.new().generate_random_bytes(32).hex_encode()
			_send_chat_json("host.pair", {"client_nonce": _host_pair_client_nonce})
		_drain_chat_packets()
		return
	for effect in effects:
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		var effect_dict := effect as Dictionary
		match str(effect_dict.get("action", "")):
			"apply_state_patch":
				_apply_chat_open_socket_state_patch(effect_dict.get("patch", {}) as Dictionary)
			"system_message":
				_append_chat_system(str(effect_dict.get("message", "")))
			"send_requests":
				_send_chat_socket_effect_requests(effect_dict.get("requests", []))
			"request_models":
				_request_runtime_models()
			"auto_enable_tools":
				_maybe_auto_enable_bridge_tools()
			"drain_packets":
				_drain_chat_packets()


func _apply_chat_open_socket_state_patch(patch: Dictionary) -> void:
	_host_start_in_progress = bool(patch.get("host_start_in_progress", false))
	_host_connect_autostart_allowed = bool(patch.get("host_connect_autostart_allowed", false))
	_host_start_retry_elapsed = float(patch.get("host_start_retry_elapsed", 0.0))
	_chat_connection_state = str(patch.get("connection_state", "ready"))
	_chat_runtime_state = str(patch.get("runtime_state", "ready"))
	_chat_trust_mode = str(patch.get("trust_mode", "off"))


func _reattach_chat_project() -> void:
	if not _chat_socket_ready():
		return
	_chat_auto_enable_tools_requested = false
	_chat_mcp_tools_available = false
	_chat_mcp_tool_count = 0
	_chat_mcp_godot_tool_count = 0
	_chat_last_tool_inventory_at = ""
	_chat_tool_visibility_error = ""
	_send_chat_socket_effect_requests(ChatSocketController.ready_transition(
		ProjectSettings.globalize_path("res://"),
		_bridge_dir_abs
	).get("requests", []) as Array)
	_request_runtime_models()
	_update_chat_ui()


func _send_chat_socket_effect_requests(requests: Array) -> void:
	for request in requests:
		if typeof(request) != TYPE_DICTIONARY:
			continue
		var request_dict := request as Dictionary
		_send_chat_json(str(request_dict.get("method", "")), request_dict.get("params", {}))


func _apply_chat_closed_socket_effects(effects: Array) -> bool:
	for effect in effects:
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		var effect_dict := effect as Dictionary
		match str(effect_dict.get("action", "")):
			"start_host":
				if _start_codex_host_if_configured():
					if _apply_chat_closed_socket_effects(effect_dict.get("success_effects", [])):
						return true
			"set_host_launch_attempted":
				_host_launch_attempted = bool(effect_dict.get("value", _host_launch_attempted))
			"clear_socket":
				_chat_socket = null
			"system_message":
				_append_chat_system(str(effect_dict.get("message", "")))
			"apply_state_patch":
				_apply_chat_closed_socket_state_patch(effect_dict.get("patch", {}) as Dictionary)
			"update_ui":
				_update_chat_ui()
			"stop_processing":
				return true
	return false


func _apply_chat_closed_socket_state_patch(patch: Dictionary) -> void:
	if not _host_paired and _one_click_secret != "" and _host_pair_secret == _one_click_secret:
		# The launched Host is gone or rejected its own secret; relaunch next time.
		_forget_one_click_session()
	_host_pair_secret = ""
	_host_pairing_sent = false
	_host_paired = false
	_host_pair_client_nonce = ""
	_host_pair_server_nonce = ""
	_chat_connection_state = str(patch.get("connection_state", "disconnected"))
	_chat_runtime_state = str(patch.get("runtime_state", "disconnected"))
	_chat_trust_mode = str(patch.get("trust_mode", "off"))


func _poll_host_start_retry(delta: float) -> void:
	var retry_plan := ChatSocketController.host_start_retry_effect_plan(_host_start_in_progress, Time.get_ticks_msec(), _host_start_deadline_msec, _host_start_retry_elapsed, delta, CHAT_HOST_START_RETRY_SECONDS, CHAT_HOST_START_TIMEOUT_SECONDS)
	_apply_host_start_retry_effects(retry_plan.get("effects", []))


func _apply_host_start_retry_effects(effects: Array) -> void:
	for effect in effects:
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		var effect_dict := effect as Dictionary
		match str(effect_dict.get("action", "")):
			"set_retry_elapsed":
				_host_start_retry_elapsed = float(effect_dict.get("value", _host_start_retry_elapsed))
			"stop_owned_host":
				_stop_owned_codex_host(str(effect_dict.get("reason", "startup_timeout")))
			"apply_state_patch":
				var patch := effect_dict.get("patch", {}) as Dictionary
				_host_start_in_progress = bool(patch.get("host_start_in_progress", _host_start_in_progress))
				_host_connect_autostart_allowed = bool(patch.get("host_connect_autostart_allowed", _host_connect_autostart_allowed))
				_chat_connection_state = str(patch.get("connection_state", _chat_connection_state))
				_chat_runtime_state = str(patch.get("runtime_state", _chat_runtime_state))
			"system_message":
				_append_chat_system(str(effect_dict.get("message", "")))
			"update_ui":
				_update_chat_ui()
			"attempt_connect":
				_attempt_chat_socket_connect(bool(effect_dict.get("log_attempt", false)))


func _start_codex_host_if_configured() -> bool:
	if _host_start_in_progress:
		return true
	var start_script := str(_host_config.get("start_script", ""))
	var node_entry := str(_host_config.get("node_entry", ""))
	var plan := ChatHostConfigModel.launch_plan(
		_host_config,
		node_entry != "" and FileAccess.file_exists(node_entry),
		start_script != "" and FileAccess.file_exists(start_script),
		DEFAULT_CODEX_HOST_PORT
	)
	if not bool(plan.get("ok", false)):
		var failure_plan := ChatSocketController.host_start_failure_effect_plan(plan)
		_apply_host_start_effects(failure_plan.get("effects", []))
		return false

	var executable := str(plan.get("executable", ""))
	var args: PackedStringArray = plan.get("args", PackedStringArray())
	var process_id := OS.create_process(executable, args, false)
	if process_id <= 0:
		var process_failure_plan := ChatSocketController.host_process_failure_effect_plan()
		_apply_host_start_effects(process_failure_plan.get("effects", []))
		return false

	var success_plan := ChatSocketController.host_start_success_effect_plan(process_id, Time.get_ticks_msec(), CHAT_HOST_START_TIMEOUT_SECONDS, plan)
	_apply_host_start_effects(success_plan.get("effects", []))
	return true


func _apply_host_start_effects(effects: Array) -> void:
	for effect in effects:
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		var effect_dict := effect as Dictionary
		match str(effect_dict.get("action", "")):
			"system_message":
				_append_chat_system(str(effect_dict.get("message", "")))
			"apply_host_config_failure":
				var state := effect_dict.get("state", {}) as Dictionary
				_host_config_status = str(state.get("host_config_status", _host_config_status))
				_host_config_message = str(state.get("host_config_message", _host_config_message))
			"apply_recoverable_message":
				_chat_recoverable_message = str(effect_dict.get("message", _chat_recoverable_message))
			"apply_start_state":
				var start_state := effect_dict.get("state", {}) as Dictionary
				_host_start_process_id = int(start_state.get("host_start_process_id", _host_start_process_id))
				_host_start_in_progress = bool(start_state.get("host_start_in_progress", _host_start_in_progress))
				_host_start_deadline_msec = int(start_state.get("host_start_deadline_msec", _host_start_deadline_msec))
				_host_start_retry_elapsed = float(start_state.get("host_start_retry_elapsed", _host_start_retry_elapsed))
				_chat_connection_state = str(start_state.get("connection_state", _chat_connection_state))
				_chat_runtime_state = str(start_state.get("runtime_state", _chat_runtime_state))
			"detail_message":
				_append_chat_detail(str(effect_dict.get("message", "")))
			"log_event":
				_log_event(str(effect_dict.get("event", "codex_host_start_requested")), effect_dict.get("payload", {}))
			"update_ui":
				_update_chat_ui()


func _apply_host_config_state(state: Dictionary) -> void:
	_host_config_status = str(state.get("status", "missing"))
	_host_config_message = str(state.get("message", "Launcher config missing. Refresh the addon install."))
	_host_config_runtime = str(state.get("runtime", ""))
	_host_config_port = int(state.get("port", DEFAULT_CODEX_HOST_PORT))
	_host_config_launcher_path = str(state.get("launcher_path", ""))
	_codex_host_url = str(state.get("host_url", CODEX_HOST_URL))


func _drain_chat_packets() -> void:
	if _chat_socket == null:
		return

	var packet_count: int = min(_chat_socket.get_available_packet_count(), CHAT_MAX_PACKETS_PER_FRAME)
	for _index in range(packet_count):
		var packet: PackedByteArray = _chat_socket.get_packet()
		var text := packet.get_string_from_utf8()
		var packet_gate := ChatSocketEventModel.packet_gate(_chat_socket.was_string_packet(), text.length(), CHAT_MAX_PACKET_CHARS)
		_apply_chat_packet_gate_effects(ChatSocketEventModel.packet_gate_effect_plan(packet_gate, text).get("effects", []) as Array)

	var remaining_packets := _chat_socket.get_available_packet_count()
	if remaining_packets > 0:
		_record_chat_backpressure(remaining_packets)


func _handle_chat_packet(text: String) -> void:
	var raw_message: Variant = JSON.parse_string(text)
	if typeof(raw_message) == TYPE_DICTIONARY:
		var message := raw_message as Dictionary
		var request_id := int(message.get("id", -1))
		var pair_method := str(_chat_request_methods.get(request_id, ""))
		if request_id >= 0 and pair_method == "host.pair":
			_chat_request_methods.erase(request_id)
			var result: Variant = message.get("result", {})
			if typeof(result) != TYPE_DICTIONARY:
				_fail_host_pairing()
				return
			var proof_result := result as Dictionary
			var server_nonce := str(proof_result.get("server_nonce", ""))
			var server_proof := str(proof_result.get("server_proof", ""))
			if server_nonce.length() != 64 or not server_nonce.is_valid_hex_number():
				_fail_host_pairing()
				return
			_host_pair_server_nonce = server_nonce.to_lower()
			var expected_proof := _host_pair_hmac("host:" + _host_pair_client_nonce + ":" + _host_pair_server_nonce)
			if expected_proof == "" or server_proof != expected_proof:
				_fail_host_pairing()
				return
			_send_chat_json("host.pair_complete", {
				"client_proof": _host_pair_hmac("addon:" + _host_pair_client_nonce + ":" + _host_pair_server_nonce)
			})
			return
		if request_id >= 0 and pair_method == "host.pair_complete":
			_chat_request_methods.erase(request_id)
			var complete_result: Variant = message.get("result", {})
			if typeof(complete_result) != TYPE_DICTIONARY or not bool((complete_result as Dictionary).get("paired", false)):
				_fail_host_pairing()
				return
			_host_paired = true
			_host_pair_secret = ""
			_host_pair_client_nonce = ""
			_host_pair_server_nonce = ""
			_chat_connection_state = "ready"
			_chat_runtime_state = "ready"
			_append_chat_system("Paired with Codex Host.")
			_reattach_chat_project()
			_update_chat_ui()
			return
		if not _host_paired and str(message.get("method", "")) == "host.pair_required":
			return
		if _host_paired and request_id >= 0 and pair_method == ChatSessionAllowModel.CLEAR_METHOD:
			_chat_request_methods.erase(request_id)
			if message.has("error"):
				var clear_error: Variant = message.get("error")
				_append_chat_system("Could not forget allowed tools: " + (str((clear_error as Dictionary).get("message", "error")) if clear_error is Dictionary else "error"))
			elif message.get("result") is Dictionary and (message.get("result") as Dictionary).get("cleared") == true:
				_set_session_allowed_tools([])
				_append_chat_system("Codex will ask again before using Godot tools.")
			return
		if _host_paired and request_id >= 0 and pair_method.begins_with("addon.update."):
			_chat_request_methods.erase(request_id)
			_handle_addon_update_response(pair_method, message)
			return
	if not _host_paired:
		_append_chat_system("Host sent an unexpected message before pairing. Connection closed.")
		if _chat_socket != null:
			_chat_socket.close()
		return
	var packet := ChatSocketEventModel.classify_packet_text(text)
	var plan := ChatSocketEventModel.packet_effect_plan(packet)
	_apply_chat_packet_effects(plan.get("effects", []))


func _host_pair_hmac(message: String) -> String:
	var key := _host_pair_secret.hex_decode()
	if key.size() != 32:
		return ""
	return Crypto.new().hmac_digest(HashingContext.HASH_SHA256, key, message.to_utf8_buffer()).hex_encode()


func _fail_host_pairing() -> void:
	_host_pair_secret = ""
	_host_pair_client_nonce = ""
	_host_pair_server_nonce = ""
	_append_chat_system("Host pairing failed. Use Connect to enter the current launcher secret.")
	if _chat_socket != null:
		_chat_socket.close()
	_update_chat_ui()


func _apply_chat_packet_gate_effects(effects: Array) -> void:
	for effect in effects:
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		var effect_dict := effect as Dictionary
		match str(effect_dict.get("action", "")):
			"handle_packet_text":
				_handle_chat_packet(str(effect_dict.get("text", "")))
			"detail_message":
				_append_chat_detail(str(effect_dict.get("message", "")))


func _apply_chat_packet_effects(effects: Array) -> void:
	for effect in effects:
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		var effect_dict := effect as Dictionary
		match str(effect_dict.get("action", "")):
			"detail_message":
				_append_chat_detail(str(effect_dict.get("message", "")))
			"system_message":
				_append_chat_system(str(effect_dict.get("message", "")))
			"apply_runtime_state":
				_chat_runtime_state = str(effect_dict.get("runtime_state", _chat_runtime_state))
			"handle_result":
				_handle_chat_result(effect_dict.get("result", {}), int(effect_dict.get("request_id", -1)))
			"handle_addon_request":
				_handle_host_bridge_addon_request(effect_dict.get("params", {}))
			"handle_event":
				_handle_chat_event(str(effect_dict.get("method", "")), effect_dict.get("params", {}))
			"update_ui":
				_update_chat_ui()
			"stop_processing":
				return


func _handle_chat_result(result: Variant, request_id := -1) -> void:
	if typeof(result) != TYPE_DICTIONARY:
		return
	var data := result as Dictionary
	var source_method := ""
	if request_id >= 0:
		source_method = str(_chat_request_methods.get(request_id, ""))
		_chat_request_methods.erase(request_id)
		if source_method in ["project.attach", "host.restart_for_project"]:
			_chat_last_completed_project_attach_request_id = request_id
			_chat_last_completed_project_attach_method = source_method
	var plan := ChatHostStateModel.result_effect_plan(data, {
		"runtime_state": _chat_runtime_state,
		"background_task_id": _active_background_task_id,
		"background_state": _active_background_state,
		"trust_mode": _chat_trust_mode,
		"mcp_tools_available": _chat_mcp_tools_available,
		"tool_visibility_error": _chat_tool_visibility_error,
		"last_reported_tool_visibility_error": _chat_last_reported_tool_visibility_error,
		"source_method": source_method,
	})
	_apply_chat_result_effects(plan.get("effects", []))


func _update_chat_tool_visibility(data: Dictionary) -> void:
	var patch := ChatHostStateModel.tool_visibility_patch(data, {
		"tools_available": _chat_mcp_tools_available,
		"last_reported_error": _chat_last_reported_tool_visibility_error,
	})
	_apply_chat_tool_visibility_patch(patch)


func _update_chat_host_status(data: Dictionary) -> void:
	_apply_chat_host_status_patch(ChatHostStateModel.host_status_patch(data))


func _apply_chat_result_effects(effects: Array) -> void:
	for effect in effects:
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		var effect_dict := effect as Dictionary
		match str(effect_dict.get("action", "")):
			"apply_runtime_state":
				_chat_runtime_state = str(effect_dict.get("runtime_state", _chat_runtime_state))
			"apply_token_usage_patch":
				_apply_chat_token_usage_patch(effect_dict.get("patch", {}) as Dictionary)
			"apply_host_status_patch":
				_apply_chat_host_status_patch(effect_dict.get("patch", {}) as Dictionary)
			"apply_tool_visibility_patch":
				_apply_chat_tool_visibility_patch(effect_dict.get("patch", {}) as Dictionary)
			"apply_result_state_patch":
				_apply_chat_result_state_patch(effect_dict.get("patch", {}) as Dictionary)
			"update_background_status_label":
				_update_background_status_label({})
			"restore_background_tasks":
				_restore_background_status_from_tasks(effect_dict.get("tasks"))
			"auto_enable_tools":
				_maybe_auto_enable_bridge_tools(bool(effect_dict.get("force", false)))
			"system_message":
				_append_chat_system(str(effect_dict.get("message", "")))
			"detail_message":
				_append_chat_detail(str(effect_dict.get("message", "")))
			"update_runtime_model_options":
				_update_runtime_model_options(effect_dict.get("data", {}) as Dictionary)
			"update_ui":
				_update_chat_ui()


func _apply_chat_result_state_patch(patch: Dictionary) -> void:
	if patch.has("thread_id"):
		_chat_thread_id = str(patch.get("thread_id", _chat_thread_id))
	if patch.has("background_task_id"):
		_active_background_task_id = str(patch.get("background_task_id", _active_background_task_id))
	if patch.has("background_state"):
		_active_background_state = str(patch.get("background_state", _active_background_state))


func _apply_chat_tool_visibility_patch(patch: Dictionary) -> void:
	if patch.has("mcp_tools_available"):
		_chat_mcp_tools_available = bool(patch.get("mcp_tools_available", _chat_mcp_tools_available))
		if _chat_mcp_tools_available:
			_chat_auto_enable_tools_requested = false
	if patch.has("mcp_tool_count"):
		_chat_mcp_tool_count = int(patch.get("mcp_tool_count", _chat_mcp_tool_count))
	if patch.has("mcp_godot_tool_count"):
		_chat_mcp_godot_tool_count = int(patch.get("mcp_godot_tool_count", _chat_mcp_godot_tool_count))
	if patch.has("mcp_server_name"):
		_chat_mcp_server_name = str(patch.get("mcp_server_name", _chat_mcp_server_name))
	if patch.has("last_tool_inventory_at"):
		_chat_last_tool_inventory_at = str(patch.get("last_tool_inventory_at", _chat_last_tool_inventory_at))
	if patch.has("tool_visibility_error"):
		_chat_tool_visibility_error = str(patch.get("tool_visibility_error", _chat_tool_visibility_error))
	if patch.has("last_reported_tool_visibility_error"):
		_chat_last_reported_tool_visibility_error = str(patch.get("last_reported_tool_visibility_error", _chat_last_reported_tool_visibility_error))
	for message in patch.get("detail_messages", []):
		_append_chat_detail(str(message))


func _apply_chat_host_status_patch(patch: Dictionary) -> void:
	if patch.has("recoverable_message"):
		_chat_recoverable_message = str(patch.get("recoverable_message", _chat_recoverable_message))
	if patch.has("fatal_message"):
		_chat_fatal_message = str(patch.get("fatal_message", _chat_fatal_message))
	if patch.has("trust_mode"):
		_chat_trust_mode = str(patch.get("trust_mode", _chat_trust_mode))
	if patch.has("session_allowed_tools"):
		_set_session_allowed_tools(patch.get("session_allowed_tools", []))
	if patch.has("active_project_root"):
		_chat_active_project_root = str(patch.get("active_project_root", _chat_active_project_root))
	if patch.has("agents_count"):
		_chat_agents_count = int(patch.get("agents_count", _chat_agents_count))
	if patch.has("agents_paths"):
		_chat_agents_paths.clear()
		var paths: Variant = patch.get("agents_paths", [])
		if typeof(paths) == TYPE_ARRAY:
			for path in paths:
				_chat_agents_paths.append(str(path))


func _apply_chat_token_usage_patch(patch: Dictionary) -> void:
	if not patch.is_empty():
		_chat_last_token_usage = patch


func _handle_chat_event(method: String, params: Dictionary) -> void:
	if method == "approval.auto_approved":
		_record_auto_approved(params)
		return
	var plan := ChatEventModel.event_handler_effect_plan(method, params, {
		"runtime_state": _chat_runtime_state,
		"thread_id": _chat_thread_id,
		"turn_id": _chat_turn_id,
		"approval": _active_chat_approval,
	})
	_apply_chat_event_effects(plan.get("effects", []) as Array)


func _apply_chat_event_effects(effects: Array) -> void:
	for effect in effects:
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		var effect_dict := effect as Dictionary
		var params := effect_dict.get("params", {}) as Dictionary
		var action := str(effect_dict.get("action", ""))
		match action:
			"apply_state_patch":
				_apply_chat_event_state_patch(effect_dict.get("patch", {}) as Dictionary)
			"update_host_status":
				_update_chat_host_status(params)
			"update_tool_visibility":
				_update_chat_tool_visibility(params)
			"flush_assistant":
				_flush_chat_assistant_text()
			"reset_stream_state":
				_reset_chat_assistant_stream_state(false)
			"reset_diff_batch":
				_reset_chat_diff_batch()
			"reset_work_batch":
				_reset_chat_work_batch()
			"turn_event":
				_handle_chat_turn_event(params)
			"show_approval":
				_show_chat_approval(params)
			"clear_approval":
				_clear_chat_approval(str(effect_dict.get("message", "")))
			"background_update":
				_handle_background_update(params)
			"system_message":
				_append_chat_system(str(effect_dict.get("message", "")))
			"detail_message":
				_append_chat_detail(str(effect_dict.get("message", "")))
			"update_ui":
				_update_chat_ui()


func _apply_chat_event_state_patch(patch: Dictionary) -> void:
	if patch.has("runtime_state"):
		_chat_runtime_state = str(patch.get("runtime_state", _chat_runtime_state))
	if patch.has("thread_id"):
		_chat_thread_id = str(patch.get("thread_id", _chat_thread_id))
	if patch.has("turn_id"):
		var next_turn_id := str(patch.get("turn_id", _chat_turn_id))
		if next_turn_id != _chat_turn_id:
			_chat_seen_turn_event_ids.clear()
		_chat_turn_id = next_turn_id


func _handle_chat_turn_event(params: Dictionary) -> void:
	var plan := ChatEventModel.turn_event_handler_effect_plan(params)
	_apply_chat_turn_event_effects(plan.get("effects", []) as Array)


func _apply_chat_turn_event_effects(effects: Array) -> void:
	for effect in effects:
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		var effect_dict := effect as Dictionary
		if _chat_turn_event_is_duplicate(effect_dict):
			continue
		match str(effect_dict.get("action", "")):
			"assistant_delta":
				_append_chat_assistant_delta(
					str(effect_dict.get("text", "")),
					str(effect_dict.get("item_id", "")),
					str(effect_dict.get("phase", ""))
				)
			"diff_updated":
				_record_chat_diff_update(str(effect_dict.get("diff_text", "")))
			"detail_message":
				_append_chat_detail(str(effect_dict.get("message", "")))


func _chat_turn_event_is_duplicate(effect: Dictionary) -> bool:
	var event_id := str(effect.get("event_id", "")).strip_edges()
	if event_id == "":
		return false
	var turn_id := str(effect.get("turn_id", _chat_turn_id)).strip_edges()
	var identity := turn_id + ":" + event_id
	if _chat_seen_turn_event_ids.has(identity):
		return true
	_chat_seen_turn_event_ids[identity] = true
	return false


func _send_chat_message() -> void:
	var message := _chat_input.text.strip_edges()
	var preflight := ChatActionModel.chat_message_preflight(
		_permission_enabled("allow_codex_chat"),
		_chat_socket_ready(),
		message
	)
	if not bool(preflight.get("ok", false)):
		_apply_chat_action_effects(ChatActionModel.chat_message_preflight_effect_plan(preflight).get("effects", []) as Array)
		return

	message = str(preflight.get("message", message))

	if not _permission_enabled("allow_screenshots") and _annotation_controller != null and _annotation_controller.has_pending():
		_annotation_controller.invalidate_sensitive_capture()
	if not _permission_enabled("allow_screenshots") and _chat_attach_screenshot != null:
		_chat_attach_screenshot.button_pressed = false
	var has_pending_annotation := _annotation_controller != null and _annotation_controller.has_pending()
	var pending_annotation := _annotation_controller.pending() if has_pending_annotation else {}
	var send_plan := ChatActionModel.chat_send_plan(
		message,
		_chat_thread_id,
		_chat_attach_context != null and _chat_attach_context.button_pressed,
		_chat_attach_selected != null and _chat_attach_selected.button_pressed,
		_chat_attach_screenshot != null and _chat_attach_screenshot.button_pressed,
		has_pending_annotation,
		pending_annotation,
		_selected_chat_model(),
		_selected_chat_reasoning(),
		_permission_enabled("allow_screenshots")
	)
	var effect_plan := ChatActionModel.chat_send_effect_plan(send_plan, message)
	_apply_chat_send_effects(effect_plan.get("effects", []) as Array)


func _apply_chat_send_effects(effects: Array) -> void:
	for effect: Variant in effects:
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		var effect_dict := effect as Dictionary
		match str(effect_dict.get("type", "")):
			"capture_screenshot":
				_capture_viewport_screenshot(str(effect_dict.get("reason", "codex_chat")))
			"write_context_snapshot":
				_write_context_snapshot(str(effect_dict.get("reason", "codex_chat")))
			"append_user_message":
				_append_chat_user_message(str(effect_dict.get("message", "")))
			"clear_chat_input":
				if _chat_input != null:
					_chat_input.text = ""
			"refresh_composer_height":
				_refresh_chat_composer_height()
			"send_json":
				var params_value: Variant = effect_dict.get("params", {})
				var params := {}
				if typeof(params_value) == TYPE_DICTIONARY:
					params = params_value as Dictionary
				_send_chat_json(str(effect_dict.get("method", "thread.send")), params)
			"clear_pending_annotation":
				_clear_pending_annotation(bool(effect_dict.get("notify", false)))
			"update_ui":
				_update_chat_ui()


func _cancel_chat_turn() -> void:
	var cancel_plan := ChatActionModel.cancel_turn_plan(_chat_socket_ready())
	_apply_chat_action_effects(ChatActionModel.cancel_turn_effect_plan(cancel_plan).get("effects", []) as Array)


func _enable_bridge_tools() -> void:
	var enable_plan := ChatActionModel.enable_tools_plan(
		_permission_enabled("allow_codex_chat"),
		_chat_socket_ready(),
		_chat_active_project_root
	)
	_apply_chat_action_effects(ChatActionModel.enable_tools_effect_plan(enable_plan).get("effects", []) as Array)


func _maybe_auto_enable_bridge_tools(force := false) -> void:
	var auto_enable := ChatActionModel.auto_enable_tools_request(
		_chat_connection_state,
		_chat_mcp_tools_available,
		_chat_auto_enable_tools_requested,
		_permission_enabled("allow_codex_chat"),
		_chat_active_project_root,
		force
	)
	_apply_chat_action_effects(ChatActionModel.auto_enable_tools_effect_plan(auto_enable).get("effects", []) as Array)


func _toggle_trust_session(enabled: bool) -> void:
	var trust_plan := ChatActionModel.trust_session_plan(enabled, _chat_socket_ready())
	_apply_chat_action_effects(ChatActionModel.trust_session_effect_plan(trust_plan).get("effects", []) as Array)


func _run_team_review() -> void:
	var preflight := ChatActionModel.team_review_preflight(
		_permission_enabled("allow_codex_chat"),
		_permission_enabled("allow_background_team_review"),
		_chat_socket_ready()
	)
	if not bool(preflight.get("ok", false)):
		_apply_chat_action_effects(ChatActionModel.team_review_preflight_effect_plan(preflight).get("effects", []) as Array)
		return

	var input_text := ""
	if _chat_input != null and _chat_input.text.strip_edges() != "":
		input_text = _chat_input.text

	var review_plan := ChatActionModel.team_review_plan(
		input_text,
		_chat_attach_context != null and _chat_attach_context.button_pressed
	)
	_apply_chat_action_effects(ChatActionModel.team_review_effect_plan(review_plan).get("effects", []) as Array)


func _cancel_team_review() -> void:
	var cancel_plan := ChatActionModel.cancel_team_review_plan(_chat_socket_ready(), _active_background_task_id)
	_apply_chat_action_effects(ChatActionModel.cancel_team_review_effect_plan(cancel_plan).get("effects", []) as Array)


func _apply_chat_action_effects(effects: Array) -> void:
	for effect: Variant in effects:
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		var effect_dict := effect as Dictionary
		match str(effect_dict.get("type", "")):
			"system_message":
				_append_chat_system(str(effect_dict.get("message", "")))
			"detail_message":
				_append_chat_detail(str(effect_dict.get("message", "")))
			"connect_host":
				_connect_chat_host()
			"set_auto_enable_tools_requested":
				_chat_auto_enable_tools_requested = bool(effect_dict.get("value", true))
			"send_json":
				var params_value: Variant = effect_dict.get("params", {})
				var params := {}
				if typeof(params_value) == TYPE_DICTIONARY:
					params = params_value as Dictionary
				_send_chat_json(str(effect_dict.get("method", "")), params)
			"update_ui":
				_update_chat_ui()
			"set_trust_mode":
				_chat_trust_mode = str(effect_dict.get("mode", "off"))
			"clear_chat_input":
				if _chat_input != null:
					_chat_input.text = ""
			"refresh_composer_height":
				_refresh_chat_composer_height()
			"write_context_snapshot":
				_write_context_snapshot(str(effect_dict.get("reason", "codex_chat")))
			"set_background_state":
				_active_background_state = str(effect_dict.get("state", _active_background_state))
			"set_background_task_id":
				_active_background_task_id = str(effect_dict.get("task_id", _active_background_task_id))
			"update_background_status_label":
				var status_params_value: Variant = effect_dict.get("params", {})
				var status_params := {}
				if typeof(status_params_value) == TYPE_DICTIONARY:
					status_params = status_params_value as Dictionary
				_update_background_status_label(status_params)


func _handle_background_update(params: Dictionary) -> void:
	var plan := ChatTeamModel.background_update_plan(params, _active_background_task_id, _active_background_state)
	_apply_chat_action_effects(ChatTeamModel.background_update_effect_plan(plan).get("effects", []) as Array)


func _restore_background_status_from_tasks(tasks: Array) -> void:
	var plan := ChatTeamModel.background_restore_plan(tasks, _active_background_task_id, _active_background_state)
	_apply_chat_action_effects(ChatTeamModel.background_restore_effect_plan(plan).get("effects", []) as Array)


## Popup lifecycle: opens by itself once per approval id, follows the active
## approval and closes as soon as it is resolved, invalidated or replaced.
## Closing the window is not a decision.
func _present_approval_review() -> void:
	if _approval_popup == null or _active_chat_approval.is_empty():
		return
	var approval_id := str(_active_chat_approval.get("approval_id", ""))
	_approval_popup.set_review(approval_id, ChatApprovalReviewModel.review(_active_chat_approval))
	if ChatApprovalReviewModel.should_auto_open(_active_chat_approval, _approval_popup_opened_ids):
		if _approval_popup_opened_ids.size() > 64:
			_approval_popup_opened_ids.clear()
		_approval_popup_opened_ids[approval_id] = true
		_approval_popup.open_centered()
	_update_chat_ui()


func _open_approval_review() -> void:
	if _approval_popup == null or _active_chat_approval.is_empty():
		return
	if _approval_popup.approval_id != str(_active_chat_approval.get("approval_id", "")):
		_approval_popup.set_review(str(_active_chat_approval.get("approval_id", "")), ChatApprovalReviewModel.review(_active_chat_approval))
	_update_chat_ui()
	_approval_popup.open_centered()


func _sync_approval_popup() -> void:
	if _approval_popup != null and ChatApprovalReviewModel.popup_stale(_approval_popup.approval_id, _active_chat_approval):
		_approval_popup.close_review()


func _on_approval_popup_decision(decision: String) -> void:
	if _approval_popup == null or ChatApprovalReviewModel.popup_stale(_approval_popup.approval_id, _active_chat_approval):
		# A late click on a review that is no longer active does nothing.
		if _approval_popup != null:
			_approval_popup.close_review()
		return
	var previous_request_id := _chat_request_id
	_respond_to_chat_approval(decision)
	if _chat_request_id != previous_request_id:
		_approval_popup.hide()


func _apply_chat_dock_style() -> void:
	if _chat_advanced_toggle != null:
		DockStyle.apply_icon(_chat_advanced_toggle, _dock_style, "Tools", true)
	if _chat_build_label != null:
		DockStyle.muted_label(_dock_style, _chat_build_label, 10)
	if _chat_cancel_button != null:
		DockStyle.apply_icon(_chat_cancel_button, _dock_style, "Stop", false)
	if _chat_eye_button != null:
		DockStyle.apply_icon(_chat_eye_button, _dock_style, "GuiVisibilityVisible", true)
	if _chat_composer_toggle_button != null:
		_chat_composer_toggle_button.set_meta("dock_icon_expand", DockStyle.icon(_dock_style, "ExpandTree"))
		_chat_composer_toggle_button.set_meta("dock_icon_collapse", DockStyle.icon(_dock_style, "CollapseTree"))
		DockStyle.apply_icon(_chat_composer_toggle_button, _dock_style, "ExpandTree", true)
	if _chat_send_button != null:
		DockStyle.apply_accent_button(_chat_send_button, _dock_style)
	if _chat_jump_latest_button != null:
		DockStyle.apply_icon(_chat_jump_latest_button, _dock_style, "ArrowDown", false, false)
	if _approval_review_button != null:
		DockStyle.apply_icon(_approval_review_button, _dock_style, "Search", false)
	if _chat_approve_button != null:
		DockStyle.apply_accent_button(_chat_approve_button, _dock_style)
	if _chat_approval_panel != null:
		_chat_approval_panel.add_theme_constant_override("separation", DockStyle.SPACE_S)
	if _chat_approval_title != null:
		_chat_approval_title.add_theme_color_override("font_color", DockStyle.tone_color(_dock_style, "warn"))
	if _chat_input != null:
		var focus_box := DockStyle.card_box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, Vector2(DockStyle.SPACE_M, DockStyle.SPACE_S))
		focus_box.draw_center = false
		focus_box.set_border_width_all(1)
		focus_box.border_color = _dock_style.get("accent", DockStyle.FALLBACK["accent"])
		_chat_input.add_theme_stylebox_override("focus", focus_box)


func _set_session_allowed_tools(value: Variant) -> void:
	_chat_session_allowed_tools = ChatSessionAllowModel.sanitize_tools(value)
	if _session_allow_row != null:
		_session_allow_row.visible = not _chat_session_allowed_tools.is_empty()
		_session_allow_label.text = ChatSessionAllowModel.summary_text(_chat_session_allowed_tools)
		_session_allow_label.tooltip_text = ChatSessionAllowModel.summary_tooltip(_chat_session_allowed_tools)


func _forget_session_allowed_tools() -> void:
	if not _chat_socket_ready():
		_append_chat_system("Connect to the Codex Host to forget allowed tools.")
		return
	_send_chat_json(ChatSessionAllowModel.CLEAR_METHOD, {})


## approval.auto_approved: one muted line per turn, updated in place while it is
## still the latest transcript line.
func _record_auto_approved(params: Dictionary) -> void:
	if _chat_transcript_view == null:
		_setup_chat_transcript_view()
	var still_last := _auto_approved_body != null and is_instance_valid(_auto_approved_body) and _chat_transcript_view.is_last_message(_auto_approved_body)
	var result := ChatSessionAllowModel.coalesce(_auto_approved_state, params, still_last)
	_auto_approved_state = result.get("state", {})
	if bool(result.get("new_line", true)):
		_auto_approved_body = _chat_transcript_view.append_status_row(str(result.get("text", "")))
	else:
		_chat_transcript_view.set_bubble_text(_auto_approved_body, str(result.get("text", "")))
	var tool := str(params.get("tool", ""))
	if ChatSessionAllowModel.valid_tool_name(tool) and not _chat_session_allowed_tools.has(tool):
		_chat_session_allowed_tools.append(tool)
		_set_session_allowed_tools(_chat_session_allowed_tools.duplicate())


func _update_background_status_label(params: Dictionary) -> void:
	if _team_status_label == null:
		return
	_team_status_label.text = ChatTeamModel.status_text(_active_background_state, params)


func _show_chat_approval(params: Dictionary) -> void:
	_apply_chat_approval_effects(ChatApprovalModel.show_effect_plan(params, _chat_active_diff_text).get("effects", []) as Array)


func _clear_chat_approval(message: String) -> void:
	_apply_chat_approval_effects(ChatApprovalModel.clear_effect_plan(message).get("effects", []) as Array)


func _respond_to_chat_approval(decision: String) -> void:
	var note := ""
	if _approval_popup != null and _approval_popup.approval_id != "" and _approval_popup.approval_id == str(_active_chat_approval.get("approval_id", "")):
		note = _approval_popup.note_edit.text
	elif _chat_approval_note != null:
		note = _chat_approval_note.text

	_apply_chat_approval_effects(ChatApprovalModel.response_effect_plan(_active_chat_approval, decision, note, _chat_socket_ready()).get("effects", []) as Array)


func _apply_chat_approval_effects(effects: Array) -> void:
	for effect in effects:
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		var effect_dict := effect as Dictionary
		match str(effect_dict.get("action", "")):
			"set_active_approval":
				_active_chat_approval = effect_dict.get("value", {}) as Dictionary
				_sync_approval_popup()
			"show_panel":
				if _chat_approval_panel != null:
					_chat_approval_panel.visible = bool(effect_dict.get("visible", true))
					if _chat_message_list != null and _chat_approval_panel.get_parent() == _chat_message_list:
						var target_index := _chat_message_list.get_child_count() - 1
						if _chat_bottom_spacer != null and _chat_bottom_spacer.get_parent() == _chat_message_list:
							target_index = max(_chat_message_list.get_child_count() - 2, 0)
						_chat_message_list.move_child(_chat_approval_panel, target_index)
				_present_approval_review()
			"set_panel_visible":
				if _chat_approval_panel != null:
					_chat_approval_panel.visible = bool(effect_dict.get("visible", false))
			"set_title":
				if _chat_approval_title != null:
					var bar_text := ChatApprovalReviewModel.bar_text(_active_chat_approval) if not _active_chat_approval.is_empty() else str(effect_dict.get("text", ""))
					_chat_approval_title.text = "⚠ " + bar_text
					_chat_approval_title.tooltip_text = bar_text
			"set_body":
				if _chat_approval_body != null:
					_chat_approval_body.text = str(effect_dict.get("text", ""))
			"set_note":
				if _chat_approval_note != null:
					_chat_approval_note.text = str(effect_dict.get("text", ""))
					_chat_approval_note.placeholder_text = str(effect_dict.get("placeholder", "Optional note for Codex"))
			"set_note_text":
				if _chat_approval_note != null:
					_chat_approval_note.text = str(effect_dict.get("text", ""))
			"record_diff":
				_record_chat_diff_update(str(effect_dict.get("diff_text", "")))
			"detail_message":
				_append_chat_detail(str(effect_dict.get("message", "")))
			"system_message":
				_append_chat_system(str(effect_dict.get("message", "")))
			"send_json":
				_send_chat_json(str(effect_dict.get("method", "approval.respond")), effect_dict.get("params", {}) as Dictionary)
			"clear_approval":
				_clear_chat_approval(str(effect_dict.get("message", "")))
			"scroll_to_bottom":
				call_deferred("_scroll_chat_to_bottom")
			"update_ui":
				_update_chat_ui()


func _send_chat_json(method: String, params: Dictionary) -> void:
	if _chat_socket == null or _chat_socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	if not _host_paired and method not in ["host.pair", "host.pair_complete"]:
		return
	_chat_request_id += 1
	_chat_request_methods[_chat_request_id] = method
	var err := _chat_socket.send_text(ChatSocketController.rpc_request_text(_chat_request_id, method, params))
	_apply_chat_socket_send_effects(ChatSocketController.request_send_result_effect_plan(err).get("effects", []) as Array)
	if err != OK:
		_chat_request_methods.erase(_chat_request_id)


func _send_chat_notification(method: String, params: Dictionary) -> void:
	if _chat_socket == null or _chat_socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	if not _host_paired:
		return
	var err := _chat_socket.send_text(ChatSocketController.rpc_notification_text(method, params))
	_apply_chat_socket_send_effects(ChatSocketController.notification_send_result_effect_plan(err).get("effects", []) as Array)


func _apply_chat_socket_send_effects(effects: Array) -> void:
	for effect: Variant in effects:
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		var effect_dict := effect as Dictionary
		match str(effect_dict.get("action", "")):
			"system_message":
				_append_chat_system(str(effect_dict.get("message", "")))
			"detail_message":
				_append_chat_detail(str(effect_dict.get("message", "")))


func _handle_host_bridge_addon_request(params: Dictionary) -> void:
	var effect_plan := ChatRequestModel.addon_rpc_effect_plan(params)
	_apply_host_bridge_addon_request_effects(effect_plan.get("effects", []) as Array)


func _apply_host_bridge_addon_request_effects(effects: Array) -> void:
	for effect: Variant in effects:
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		var effect_dict := effect as Dictionary
		match str(effect_dict.get("action", "")):
			"send_addon_error_response":
				var request_id := str(effect_dict.get("request_id", ""))
				var request_action := str(effect_dict.get("request_action", "unknown"))
				var request_source := str(effect_dict.get("request_source", "websocket_rpc"))
				_send_chat_notification("bridge.addon_response", {
					"request_id": request_id,
					"response": _response_payload(request_id, request_action, "error", {}, _error_payload(
						str(effect_dict.get("error_code", "invalid_rpc_request")),
						str(effect_dict.get("error_message", "bridge.addon_request params.request must be an object."))
					), request_source),
				})
			"handle_addon_request":
				var request_id := str(effect_dict.get("request_id", ""))
				var request := effect_dict.get("request", {}) as Dictionary
				var request_source := str(effect_dict.get("request_source", "websocket_rpc"))
				var response := _handle_request(request_id, request, request_source)
				_send_chat_notification("bridge.addon_response", {
					"request_id": request_id,
					"response": response,
				})


func _append_chat_log(text: String, _newline: bool = true) -> void:
	_append_chat_system(text)


func _append_chat_user_message(text: String) -> void:
	_flush_chat_assistant_text()
	_reset_chat_assistant_stream_state(false)
	if _chat_transcript_view == null:
		_setup_chat_transcript_view()
	if _chat_transcript_view != null:
		_chat_transcript_view.append_user_message(text)


func _append_chat_system(text: String) -> void:
	if _chat_transcript_view == null:
		_setup_chat_transcript_view()
	if _chat_transcript_view != null:
		_chat_transcript_view.append_status_message(text)


func _append_chat_assistant_delta(text: String, item_id: String = "", phase: String = "") -> void:
	var route := ChatTranscriptBatchModel.assistant_delta_route(text, phase, _chat_assistant_current_phase())
	match str(route.get("route", "ignore")):
		"ignore":
			return
		"work":
			_record_chat_work_update(text, item_id)
			return
	var normalized_phase := str(route.get("phase", ""))
	if _chat_transcript_view == null:
		_setup_chat_transcript_view()
	if _chat_transcript_view != null:
		_chat_transcript_view.append_assistant_delta(text, item_id, normalized_phase, Time.get_ticks_msec())


func _flush_chat_assistant_text() -> void:
	if _chat_transcript_view != null:
		_chat_transcript_view.flush_assistant_text(Time.get_ticks_msec())


func _reset_chat_assistant_stream_state(flush_first := true) -> void:
	if _chat_transcript_view != null:
		_chat_transcript_view.reset_assistant_stream(flush_first, Time.get_ticks_msec())


func _chat_assistant_current_phase() -> String:
	if _chat_transcript_view == null:
		return ""
	return _chat_transcript_view.assistant_current_phase()


func _chat_work_state_payload() -> Dictionary:
	return {
		"text": _chat_active_work_text,
		"updates": _chat_active_work_updates,
		"item_id": _chat_active_work_item_id,
		"visible": _chat_active_work_visible,
	}


func _apply_chat_work_state(state: Dictionary) -> void:
	_chat_active_work_text = str(state.get("text", ""))
	_chat_active_work_updates = int(state.get("updates", 0))
	_chat_active_work_item_id = str(state.get("item_id", ""))
	_chat_active_work_visible = bool(state.get("visible", false))


func _chat_diff_state_payload() -> Dictionary:
	return {
		"text": _chat_active_diff_text,
		"updates": _chat_active_diff_updates,
		"files": _chat_active_diff_files,
		"file_count": _chat_active_diff_file_count,
		"added_count": _chat_active_diff_added_count,
		"removed_count": _chat_active_diff_removed_count,
		"files_visible": _chat_active_diff_files_visible,
	}


func _apply_chat_diff_state(state: Dictionary) -> void:
	_chat_active_diff_text = str(state.get("text", ""))
	_chat_active_diff_updates = int(state.get("updates", 0))
	_chat_active_diff_files = state.get("files", PackedStringArray()) as PackedStringArray
	_chat_active_diff_file_count = int(state.get("file_count", 0))
	_chat_active_diff_added_count = int(state.get("added_count", 0))
	_chat_active_diff_removed_count = int(state.get("removed_count", 0))
	_chat_active_diff_files_visible = bool(state.get("files_visible", false))


func _reset_chat_work_batch() -> void:
	_chat_active_work_panel = null
	_chat_active_work_summary_label = null
	_chat_active_work_toggle_button = null
	_chat_active_work_body_label = null
	_apply_chat_work_state(ChatTranscriptBatchModel.empty_work_state())
	_chat_active_work_controls = {}


func _record_chat_work_update(text: String, item_id: String = "") -> void:
	var work_plan := ChatTranscriptBatchModel.record_work_update_effect_plan(
		_chat_work_state_payload(),
		text,
		item_id,
		_chat_active_work_panel != null and is_instance_valid(_chat_active_work_panel)
	)
	_apply_chat_work_update_effects(work_plan.get("effects", []) as Array)


func _apply_chat_work_update_effects(effects: Array) -> void:
	for effect in effects:
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		var effect_dict := effect as Dictionary
		match str(effect_dict.get("action", "")):
			"flush_assistant_text":
				_flush_chat_assistant_text()
			"apply_work_state":
				_apply_chat_work_state(effect_dict.get("state", {}) as Dictionary)
			"ensure_work_panel":
				if _chat_active_work_panel == null or not is_instance_valid(_chat_active_work_panel):
					_chat_active_work_panel = _append_chat_work_bubble()
			"update_work_batch":
				_update_chat_work_batch_bubble()


func _update_chat_work_batch_bubble() -> void:
	if _chat_active_work_panel == null or not is_instance_valid(_chat_active_work_panel):
		return
	if _chat_transcript_view != null:
		_chat_transcript_view.update_work_batch(
			_chat_active_work_controls,
			_chat_active_work_updates,
			_chat_active_work_text,
			_chat_active_work_visible
		)


func _append_chat_work_bubble() -> PanelContainer:
	if _chat_transcript_view == null:
		return null
	var owned_controls := {}
	_chat_active_work_controls = _chat_transcript_view.append_work_batch(func() -> void:
		if owned_controls == _chat_active_work_controls:
			var owned_body := owned_controls.get("body_label", null) as Control
			_set_chat_work_visible(owned_body != null and owned_body.visible)
	)
	owned_controls = _chat_active_work_controls
	_chat_active_work_panel = _chat_active_work_controls.get("panel", null) as PanelContainer
	_chat_active_work_summary_label = _chat_active_work_controls.get("summary_label", null) as Label
	_chat_active_work_toggle_button = _chat_active_work_controls.get("toggle_button", null) as Button
	_chat_active_work_body_label = _chat_active_work_controls.get("body_label", null) as Label
	return _chat_active_work_panel


func _set_chat_work_visible(visible: bool) -> void:
	_apply_chat_work_state(ChatTranscriptBatchModel.work_state_visible(_chat_work_state_payload(), visible))
	if _chat_transcript_view != null:
		_chat_transcript_view.set_work_batch_visible(_chat_active_work_controls, _chat_active_work_updates, visible)


func _reset_chat_diff_batch() -> void:
	_chat_active_diff_label = null
	_chat_active_diff_panel = null
	_chat_active_diff_summary_label = null
	_chat_active_diff_toggle_button = null
	_apply_chat_diff_state(ChatTranscriptBatchModel.empty_diff_state())
	_chat_active_diff_controls = {}


func _record_chat_diff_update(diff_text: String) -> void:
	_flush_chat_assistant_text()
	var diff_result := ChatTranscriptBatchModel.record_diff_update(_chat_diff_state_payload(), diff_text)
	_apply_chat_diff_state(diff_result.get("state", {}) as Dictionary)
	if _chat_active_diff_panel == null or not is_instance_valid(_chat_active_diff_panel):
		_chat_active_diff_panel = _append_chat_diff_bubble()
	_update_chat_diff_batch_bubble()


func _update_chat_diff_batch_bubble() -> void:
	if _chat_active_diff_panel == null or not is_instance_valid(_chat_active_diff_panel):
		return
	if _chat_transcript_view == null:
		return
	var diff_result := _chat_transcript_view.update_diff_batch(
		_chat_active_diff_controls,
		_chat_active_diff_updates,
		_chat_active_diff_text,
		_chat_active_diff_files_visible
	)
	_chat_active_diff_file_count = int(diff_result.get("file_count", 0))
	_chat_active_diff_added_count = int(diff_result.get("added_count", 0))
	_chat_active_diff_removed_count = int(diff_result.get("removed_count", 0))
	_apply_chat_diff_state(ChatTranscriptBatchModel.diff_state_with_counts(_chat_diff_state_payload(), diff_result))


func _append_chat_diff_bubble() -> VBoxContainer:
	if _chat_transcript_view == null:
		return null
	var owned_controls := {}
	_chat_active_diff_controls = _chat_transcript_view.append_diff_batch(func() -> void:
		if owned_controls == _chat_active_diff_controls:
			var owned_files := owned_controls.get("files_box", null) as Control
			_set_chat_diff_files_visible(owned_files != null and owned_files.visible)
	)
	owned_controls = _chat_active_diff_controls
	_chat_active_diff_panel = _chat_active_diff_controls.get("files_box", null) as VBoxContainer
	_chat_active_diff_summary_label = _chat_active_diff_controls.get("summary_label", null) as Label
	_chat_active_diff_toggle_button = _chat_active_diff_controls.get("toggle_button", null) as Button
	return _chat_active_diff_panel


func _set_chat_diff_files_visible(visible: bool) -> void:
	_apply_chat_diff_state(ChatTranscriptBatchModel.diff_state_visible(_chat_diff_state_payload(), visible))
	if _chat_transcript_view != null:
		_chat_transcript_view.set_diff_batch_visible(_chat_active_diff_controls, _chat_active_diff_file_count, visible)


func _record_chat_backpressure(remaining_count: int) -> void:
	var notice := ChatSocketEventModel.backpressure_notice(
		remaining_count,
		_chat_backpressure_events_since_notice,
		Time.get_ticks_msec(),
		_last_chat_backpressure_notice_msec,
		CHAT_BACKPRESSURE_NOTICE_INTERVAL_MSEC
	)
	_apply_chat_backpressure_effects(ChatSocketEventModel.backpressure_effect_plan(notice).get("effects", []) as Array)


func _apply_chat_backpressure_effects(effects: Array) -> void:
	for effect in effects:
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		var effect_dict := effect as Dictionary
		match str(effect_dict.get("action", "")):
			"set_backpressure_state":
				_chat_backpressure_events_since_notice = int(effect_dict.get("events_since_notice", _chat_backpressure_events_since_notice))
				_last_chat_backpressure_notice_msec = int(effect_dict.get("last_notice_msec", _last_chat_backpressure_notice_msec))
				_chat_last_backpressure_text = str(effect_dict.get("last_backpressure_text", _chat_last_backpressure_text))
			"detail_message":
				_append_chat_detail(str(effect_dict.get("message", "")))
			"update_ui":
				_update_chat_ui()


func _append_chat_detail(text: String) -> void:
	var detail := ChatTechnicalLogModel.append_detail(
		_chat_technical_log,
		text,
		_iso_now(),
		MAX_BRIDGE_LOG_EVENTS,
		2000,
		1000
	)
	_chat_technical_log.clear()
	for entry in detail.get("entries", []):
		_chat_technical_log.append(entry)
	_log_event(
		str(detail.get("log_event_type", "codex_chat_detail")),
		detail.get("log_event_data", {})
	)


func _append_chat_bubble(author: String, text: String, background: Color, accent: Color, force_collapsed: bool = false) -> RichTextLabel:
	if _chat_transcript_view == null:
		_setup_chat_transcript_view()
	if _chat_transcript_view == null:
		return null
	return _chat_transcript_view.append_bubble(author, text, background, accent, force_collapsed)


func _chat_theme_palette() -> Dictionary:
	var base_control: Control = null
	if get_editor_interface() != null:
		base_control = get_editor_interface().get_base_control()
	if base_control == null:
		base_control = _chat_dock
	return ChatThemeModel.palette_from_control(base_control)


func _clear_chat_transcript() -> void:
	_chat_follow_latest = true
	_update_jump_latest_button()
	_flush_chat_assistant_text()
	_reset_chat_assistant_stream_state(false)
	_reset_chat_work_batch()
	_reset_chat_diff_batch()
	if _chat_transcript_view == null:
		_setup_chat_transcript_view()
	if _chat_transcript_view != null:
		_chat_transcript_view.clear_messages()
	_update_chat_ui()


func _start_new_chat_thread() -> void:
	if not ChatSessionModel.can_start_new_chat(_chat_runtime_state):
		_append_chat_system(ChatSessionModel.new_chat_tooltip(_chat_thread_id, _chat_runtime_state))
		_update_chat_ui()
		return
	_chat_thread_id = ""
	_chat_turn_id = ""
	_clear_chat_transcript()


func _chat_message_count() -> int:
	if _chat_transcript_view == null:
		_setup_chat_transcript_view()
	if _chat_transcript_view == null:
		return 0
	return _chat_transcript_view.message_count()


func _chat_message_control_counts() -> Dictionary:
	if _chat_transcript_view == null:
		_setup_chat_transcript_view()
	if _chat_transcript_view == null:
		return ChatTranscriptView.empty_control_counts()
	return _chat_transcript_view.control_counts()


func _scroll_chat_to_bottom() -> void:
	if _chat_log_view == null:
		return
	var update := ChatScrollPolicyModel.content_update(_chat_follow_latest)
	if not bool(update.get("scroll_to_bottom", false)):
		_update_jump_latest_button()
		return
	var scroll_bar := _chat_log_view.get_v_scroll_bar()
	if scroll_bar != null:
		scroll_bar.value = scroll_bar.max_value
	_update_jump_latest_button()


func _on_chat_log_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_LEFT]:
			_chat_scroll_user_input_pending = true
			call_deferred("_apply_chat_user_scroll_position")
	elif event is InputEventPanGesture:
		_chat_scroll_user_input_pending = true
		call_deferred("_apply_chat_user_scroll_position")


func _apply_chat_user_scroll_position() -> void:
	if not _chat_scroll_user_input_pending or _chat_log_view == null:
		return
	_chat_scroll_user_input_pending = false
	var scroll_bar := _chat_log_view.get_v_scroll_bar()
	if scroll_bar == null:
		return
	_chat_follow_latest = bool(ChatScrollPolicyModel.after_user_scroll(scroll_bar.value, scroll_bar.max_value).get("follow_latest", true))
	_update_jump_latest_button()


func _jump_chat_to_latest() -> void:
	_chat_follow_latest = true
	_scroll_chat_to_bottom()


func _update_jump_latest_button() -> void:
	if _chat_jump_latest_button != null:
		_chat_jump_latest_button.visible = not _chat_follow_latest


func _truncate_chat_text(text: String, limit: int) -> String:
	return ChatTranscriptModel.truncate_text(text, limit)


func _is_chat_runtime_state(value: String) -> bool:
	return ChatSocketEventModel.is_runtime_state(value)


func _chat_tools_state_label() -> String:
	return str(_chat_status_context().get("tools_state_label", "checking"))


func _chat_agents_state_label() -> String:
	return str(_chat_status_context().get("instructions_state_label", "not attached"))


func _chat_agents_status_detail() -> String:
	return str(_chat_status_context().get("instructions_status_detail", ""))


func _chat_status_state() -> Dictionary:
	return {
		"chat_enabled": _permission_enabled("allow_codex_chat"),
		"connected": _chat_socket != null and _chat_socket.get_ready_state() == WebSocketPeer.STATE_OPEN,
		"connecting": _chat_connection_state == "connecting" or _host_start_in_progress,
		"has_approval": not _active_chat_approval.is_empty(),
		"connection_state": _chat_connection_state,
		"runtime_state": _chat_runtime_state,
		"thread_id": _chat_thread_id,
		"host_config_status": _host_config_status,
		"host_config_message": _host_config_message,
		"host_config_path": HOST_CONFIG_PATH,
		"host_config_runtime": _host_config_runtime,
		"host_config_port": _host_config_port,
		"host_config_launcher_path": _host_config_launcher_path,
		"tools_available": _chat_mcp_tools_available,
		"mcp_tool_count": _chat_mcp_tool_count,
		"mcp_godot_tool_count": _chat_mcp_godot_tool_count,
		"mcp_server_name": _chat_mcp_server_name,
		"last_tool_inventory_at": _chat_last_tool_inventory_at,
		"tool_visibility_error": _chat_tool_visibility_error,
		"active_project_root": _chat_active_project_root,
		"agents_count": _chat_agents_count,
		"agents_paths": _chat_agents_paths,
		"recoverable_message": _chat_recoverable_message,
		"fatal_message": _chat_fatal_message,
		"backpressure_text": _chat_last_backpressure_text,
		"trust_mode": _chat_trust_mode,
		"selected_model": _selected_chat_model(),
		"selected_reasoning": _selected_chat_reasoning(),
	}


func _chat_status_payload() -> Dictionary:
	return ChatStatusModel.status_payload(_chat_status_state())


func _chat_status_context() -> Dictionary:
	return ChatStatusModel.status_context(_chat_status_state())


func _populate_default_runtime_options() -> void:
	_chat_model_options.clear()
	_chat_reasoning_efforts = ChatRuntimeOptionsModel.DEFAULT_REASONING_EFFORTS.duplicate(true)
	_rebuild_model_options("")
	_rebuild_reasoning_options("")


func _request_runtime_models() -> void:
	_apply_chat_action_effects(ChatRuntimeOptionsModel.request_models_effect_plan(_chat_socket_ready()).get("effects", []) as Array)


func _update_runtime_model_options(data: Dictionary) -> void:
	var plan := ChatRuntimeOptionsModel.update_model_options_effect_plan(data, _chat_model_options, _chat_reasoning_efforts)
	_apply_runtime_model_options_effects(plan.get("effects", []) as Array)
	if bool(plan.get("ok", false)):
		_apply_model_preference(str(data.get("defaultModel", "")))


## Restores the remembered model/effort when the inventory arrives. Selection
## here is programmatic and never saved.
func _apply_model_preference(default_model: String) -> void:
	if _chat_model_option == null or _chat_reasoning_option == null:
		return
	_chat_effective_default_model = ChatModelPreferenceModel.effective_default_model(_chat_model_options, default_model)
	var selection := ChatModelPreferenceModel.initial_selection(
		_chat_model_options,
		default_model,
		_model_preference.has_saved_model(),
		_model_preference.saved_model(),
		_model_preference.saved_effort(),
		_chat_reasoning_efforts
	)
	var model := str(selection.get("model", ""))
	var model_index := 0 if model == "" else ChatRuntimeOptionsModel.selected_index_for_model_metadata(_option_metadata_items(_chat_model_option), model)
	if model_index >= 0:
		_chat_model_option.select(model_index)
	_apply_runtime_model_options_effects(_chat_model_selection_effects())
	var effort := str(selection.get("effort", ""))
	var effort_index := 0 if effort == "" else ChatRuntimeOptionsModel.selected_index_for_reasoning_metadata(_option_metadata_items(_chat_reasoning_option), effort)
	if effort_index >= 0:
		_chat_reasoning_option.select(effort_index)
	var notice := str(selection.get("notice", ""))
	if notice != "" and not _model_preference_notices.has(notice):
		_model_preference_notices[notice] = true
		_append_chat_system(notice)
	_update_chat_ui()


func _apply_runtime_model_options_effects(effects: Array) -> void:
	for effect in effects:
		if typeof(effect) != TYPE_DICTIONARY:
			continue
		var effect_dict := effect as Dictionary
		match str(effect_dict.get("action", "")):
			"apply_runtime_options":
				_chat_model_options = effect_dict.get("models", []) as Array[Dictionary]
				_chat_reasoning_efforts = effect_dict.get("reasoning_efforts", []) as Array[Dictionary]
				_chat_models_loaded = bool(effect_dict.get("models_loaded", _chat_models_loaded))
			"rebuild_model_options":
				_rebuild_model_options(str(effect_dict.get("default_model", "")))
			"update_reasoning_options_for_selected_model":
				_update_reasoning_options_for_selected_model()
			"rebuild_reasoning_options":
				_rebuild_reasoning_options(
					str(effect_dict.get("selected_effort", "")),
					effect_dict.get("efforts", []) as Array[Dictionary]
				)
			"select_model":
				if _chat_model_option != null:
					_chat_model_option.select(int(effect_dict.get("index", 0)))
					if bool(effect_dict.get("refresh_reasoning", false)):
						_apply_runtime_model_options_effects(_chat_model_selection_effects())
			"select_reasoning":
				_select_chat_reasoning_from_effect(effect_dict)
			"detail_message":
				_append_chat_detail(str(effect_dict.get("message", "")))
			"update_ui":
				_update_chat_ui()


func _rebuild_model_options(default_model: String) -> void:
	if _chat_model_option == null:
		return
	var selected_model := _selected_chat_model()
	var model_options := ChatRuntimeOptionsModel.model_option_rows(_chat_model_options, selected_model, default_model)
	_chat_model_option.clear()
	for row in model_options.get("rows", []):
		var row_data := row as Dictionary
		_chat_model_option.add_item(str(row_data.get("label", "")))
		var index := _chat_model_option.get_item_count() - 1
		_chat_model_option.set_item_metadata(index, row_data.get("metadata", {}))
	_chat_model_option.select(int(model_options.get("select_index", 0)))


func _update_reasoning_options_for_selected_model() -> void:
	_apply_runtime_model_options_effects(_chat_model_selection_effects())


func _chat_model_selection_effects() -> Array:
	var plan := ChatRuntimeOptionsModel.model_selection_effect_plan(_selected_chat_model_data(), _chat_reasoning_efforts, _selected_chat_reasoning())
	return plan.get("effects", []) as Array


func _select_chat_reasoning_from_effect(effect: Dictionary) -> void:
	if _chat_reasoning_option == null:
		return
	var effort := str(effect.get("effort", ""))
	var effort_index := int(effect.get("index", -1))
	if effort_index < 0 and effort != "":
		effort_index = ChatRuntimeOptionsModel.selected_index_for_reasoning_metadata(_option_metadata_items(_chat_reasoning_option), effort)
	if effort_index >= 0:
		_chat_reasoning_option.select(effort_index)


func _rebuild_reasoning_options(selected_effort: String, efforts: Array[Dictionary] = []) -> void:
	if _chat_reasoning_option == null:
		return
	if efforts.is_empty():
		efforts = ChatRuntimeOptionsModel.DEFAULT_REASONING_EFFORTS.duplicate(true)
	var reasoning_options := ChatRuntimeOptionsModel.reasoning_option_rows(efforts, selected_effort)
	_chat_reasoning_option.clear()
	for row in reasoning_options.get("rows", []):
		var row_data := row as Dictionary
		_chat_reasoning_option.add_item(str(row_data.get("label", "")))
		var index := _chat_reasoning_option.get_item_count() - 1
		_chat_reasoning_option.set_item_metadata(index, row_data.get("metadata", {}))
	_chat_reasoning_option.select(int(reasoning_options.get("select_index", 0)))


func _selected_chat_model_data() -> Dictionary:
	if _chat_model_option == null or _chat_model_option.get_item_count() == 0:
		return {}
	var selected := _chat_model_option.selected
	if selected < 0:
		return {}
	var metadata: Variant = _chat_model_option.get_item_metadata(selected)
	return metadata if typeof(metadata) == TYPE_DICTIONARY else {}


func _selected_chat_model() -> String:
	return str(_selected_chat_model_data().get("model", "")).strip_edges()


func _selected_chat_reasoning() -> String:
	if _chat_reasoning_option == null or _chat_reasoning_option.get_item_count() == 0:
		return ""
	var selected := _chat_reasoning_option.selected
	if selected < 0:
		return ""
	var metadata: Variant = _chat_reasoning_option.get_item_metadata(selected)
	if typeof(metadata) != TYPE_DICTIONARY:
		return ""
	return str((metadata as Dictionary).get("reasoningEffort", "")).strip_edges()


func _option_metadata_items(option: OptionButton) -> Array:
	var items: Array = []
	if option == null:
		return items
	for index in range(option.get_item_count()):
		items.append(option.get_item_metadata(index))
	return items


func _reasoning_effort_label(effort: String) -> String:
	return ChatRuntimeOptionsModel.reasoning_effort_label(effort)


func _chat_readiness_tooltip() -> String:
	return str(_chat_status_context().get("readiness_tooltip", ""))


func _update_chat_ui() -> void:
	_apply_addon_update_view()
	var status_context := _chat_status_context()
	var ui_context := ChatControlStateModel.ui_context({
		"chat_enabled": _permission_enabled("allow_codex_chat"),
		"marker_enabled": _permission_enabled("allow_ai_markers"),
		"team_permission": _permission_enabled("allow_background_team_review"),
		"connected": _chat_socket != null and _chat_socket.get_ready_state() == WebSocketPeer.STATE_OPEN,
		"connecting": _chat_connection_state == "connecting" or _host_start_in_progress,
		"runtime_state": _chat_runtime_state,
		"host_config_status": _host_config_status,
		"thread_id": _chat_thread_id,
		"turn_id": _chat_turn_id,
		"message_count": _chat_message_count(),
		"tools_available": _chat_mcp_tools_available,
		"active_project_root": _chat_active_project_root,
		"trust_mode": _chat_trust_mode,
		"background_state": _active_background_state,
		"host_config_message": _host_config_message,
		"approval": _active_chat_approval,
	})
	if _chat_status_label != null:
		var status := status_context.get("status", ui_context.get("status", {})) as Dictionary
		_chat_status_label.text = str(status.get("label", "Ready"))
		if _chat_status_dot != null:
			var dot_color: Color = status.get("color", ChatStatusModel.COLOR_IDLE)
			_chat_status_dot.color = dot_color
		var status_tooltip := str(status_context.get("status_tooltip", ""))
		_chat_status_label.tooltip_text = _chat_status_label.text + ("\n" + status_tooltip if status_tooltip != "" else "")
		if not _chat_session_allowed_tools.is_empty():
			_chat_status_label.tooltip_text += "\n" + ChatSessionAllowModel.summary_text(_chat_session_allowed_tools)
	if _chat_readiness_label != null:
		_chat_readiness_label.text = str(status_context.get("readiness_label", ""))
		_chat_readiness_label.tooltip_text = str(status_context.get("readiness_tooltip", ""))
	var foreground_busy := bool(ui_context.get("foreground_busy", false))
	var controls: Dictionary = ui_context.get("controls", {})
	if _chat_thread_label != null:
		_chat_thread_label.text = ChatSessionModel.thread_label(_chat_thread_id)
		_chat_thread_label.tooltip_text = "Current Codex thread id: " + (_chat_thread_id if _chat_thread_id != "" else "none yet")
	if foreground_busy and _chat_foreground_busy_started_msec <= 0:
		_chat_foreground_busy_started_msec = Time.get_ticks_msec()
		_chat_working_refresh_elapsed = 0.0
	elif not foreground_busy:
		_chat_foreground_busy_started_msec = 0
		_chat_working_refresh_elapsed = 0.0
		_chat_last_token_usage = {}
	if _chat_working_label != null:
		_chat_working_label.visible = foreground_busy
		var elapsed_seconds := 0
		if foreground_busy and _chat_foreground_busy_started_msec > 0:
			elapsed_seconds = int((Time.get_ticks_msec() - _chat_foreground_busy_started_msec) / 1000)
		_chat_working_label.text = ChatStatusModel.working_indicator_text(_chat_runtime_state, elapsed_seconds, _chat_last_token_usage)
	if _chat_trust_indicator != null:
		_chat_trust_indicator.visible = _chat_trust_mode != "off"
		_chat_trust_indicator.text = "Trust " + _chat_trust_mode.replace("_", " ")
	if _chat_connect_button != null:
		ChatPanelView.apply_button_state(_chat_connect_button, controls.get("connect", {}))
	if _chat_send_button != null:
		ChatPanelView.apply_button_state(_chat_send_button, controls.get("send", {}))
	if _chat_eye_button != null:
		ChatPanelView.apply_button_state(_chat_eye_button, controls.get("eye", {}))
	if _chat_new_button != null:
		ChatPanelView.apply_button_state(_chat_new_button, controls.get("new", {}))
	if _chat_clear_button != null:
		ChatPanelView.apply_button_state(_chat_clear_button, controls.get("clear", {}))
	_update_pending_annotation_ui()
	if _chat_cancel_button != null:
		ChatPanelView.apply_button_state(_chat_cancel_button, controls.get("cancel", {}))
		# Stop only appears while a turn is running (next to the working timer).
		_chat_cancel_button.visible = foreground_busy or not _chat_cancel_button.disabled
	if _chat_enable_tools_button != null:
		ChatPanelView.apply_button_state(_chat_enable_tools_button, controls.get("enable_tools", {}))
	if _chat_trust_button != null:
		ChatPanelView.apply_check_button_state(_chat_trust_button, controls.get("trust", {}))
	if _team_review_button != null:
		ChatPanelView.apply_button_state(_team_review_button, controls.get("team_review", {}))
	if _team_cancel_button != null:
		ChatPanelView.apply_button_state(_team_cancel_button, controls.get("team_cancel", {}))
	if _chat_approve_button != null:
		ChatPanelView.apply_button_state(_chat_approve_button, controls.get("approve", {}))
	if _chat_reject_button != null:
		ChatPanelView.apply_button_state(_chat_reject_button, controls.get("reject", {}))
	# Session approval and Revise are in the review popup; the dock bar keeps
	# only Review + quick Approve/Reject.
	if _chat_approve_session_button != null:
		ChatPanelView.apply_button_state(_chat_approve_session_button, controls.get("approve_session", {}))
		_chat_approve_session_button.visible = _approval_popup == null and _chat_approve_session_button.visible
	if _chat_revise_button != null:
		ChatPanelView.apply_button_state(_chat_revise_button, controls.get("revise", {}))
		_chat_revise_button.visible = _approval_popup == null
	if _chat_allow_session_button != null:
		ChatPanelView.apply_button_state(_chat_allow_session_button, controls.get("allow_session_tool", {}))
	if _chat_model_badge != null:
		var default_label := ChatModelPreferenceModel.model_label(ChatModelPreferenceModel.find_model(_chat_model_options, _chat_effective_default_model), _chat_effective_default_model)
		_chat_model_badge.text = ChatModelPreferenceModel.badge_text(_selected_chat_model_data(), default_label if _chat_effective_default_model != "" else "", _selected_chat_reasoning())
		_chat_model_badge.tooltip_text = "Model for the next message: " + _chat_model_badge.text + ".\nClick to change it (Advanced). Your last choice is remembered for this editor user."
	if _approval_popup != null:
		_approval_popup.apply_button_states(controls)


func _poll_requests() -> void:
	# Startup and artifact writers create these directories. Rechecking every
	# directory on every 250 ms poll is expensive on Windows; repair only when
	# transport directories are missing. The physical path guards below still
	# run before reading requests or writing the heartbeat.
	if not DirAccess.dir_exists_absolute(_requests_dir_abs) or not DirAccess.dir_exists_absolute(_responses_dir_abs):
		_ensure_bridge_dirs()
	var requests_guard := _validate_bridge_path(_requests_dir_abs, false)
	var responses_guard := _validate_bridge_path(_responses_dir_abs, false)
	if not bool(requests_guard.get("ok", false)) or not bool(responses_guard.get("ok", false)):
		_log_event("request_transport_path_rejected", {"requests": requests_guard, "responses": responses_guard})
		return
	if not bool(_ensure_safe_bridge_directory(_journal_dir_abs).get("ok", false)):
		_log_event("request_journal_path_rejected", {"path": _journal_dir_abs})
		return
	_write_heartbeat()

	var request_files := _list_files_with_extension(_requests_dir_abs, ".json", MAX_REQUEST_QUEUE_FILES + 1)
	if request_files.size() > MAX_REQUEST_QUEUE_FILES:
		request_files.resize(MAX_REQUEST_QUEUE_FILES)
		_log_event("request_queue_limited", {"max_files": MAX_REQUEST_QUEUE_FILES})
	request_files.sort()

	var handled := 0
	for file_name in request_files:
		if handled >= MAX_REQUESTS_PER_POLL:
			break

		var response_path := _responses_dir_abs.path_join(str(file_name))
		if FileAccess.file_exists(response_path):
			DirAccess.remove_absolute(_requests_dir_abs.path_join(str(file_name)))
			continue
		if _async_editor_requests_in_flight.has(str(file_name)):
			continue

		var request_path := _requests_dir_abs.path_join(str(file_name))
		var read_result := _read_json_file(request_path)
		var response: Dictionary

		if read_result.get("ok", false) and _is_async_editor_control_request(read_result.get("data", {}) as Dictionary):
			_async_editor_requests_in_flight[str(file_name)] = true
			_handle_async_editor_control_request(str(file_name), read_result.get("data", {}) as Dictionary, response_path)
			handled += 1
			continue

		if read_result.get("ok", false):
			response = _handle_request(str(file_name).get_basename(), read_result.get("data", {}), str(file_name))
		else:
			response = _response_payload(str(file_name).get_basename(), "unknown", "error", {}, read_result.get("error", {}), str(file_name))

		_write_response_atomic(response_path, response)
		handled += 1

	_update_ui()


# capture_multi_view must wait for live editor frames before reading SubViewport
# textures, so the request-file path runs it as a coroutine. WebSocket RPC and
# editor_batch keep using the synchronous registered handler.
func _is_async_editor_control_request(request: Dictionary) -> bool:
	var identity := BridgeRequestModel.request_identity("", request)
	if str(identity.get("request_type", "")) != "editor_control":
		return false
	var payload := BridgeRequestModel.request_payload(request)
	return str(payload.get("action", "")).strip_edges() == "capture_multi_view"


func _handle_async_editor_control_request(file_name: String, request: Dictionary, response_path: String) -> void:
	var identity := BridgeRequestModel.request_identity(file_name.get_basename(), request)
	var request_id := str(identity.get("request_id", file_name.get_basename()))
	var request_type := str(identity.get("request_type", "editor_control"))
	var claim := _claim_request(file_name.get_basename(), request, file_name)
	if str(claim.get("state", "")) != "claimed":
		_write_response_atomic(response_path, _journal_response(request_id, request_type, file_name, claim))
		_async_editor_requests_in_flight.erase(file_name)
		return
	var payload := BridgeRequestModel.request_payload(request)
	var started_msec := Time.get_ticks_msec()
	var result: Dictionary
	var params_value: Variant = payload.get("params", {})
	if typeof(params_value) != TYPE_DICTIONARY:
		result = _err("invalid_request", "editor_control params must be an object.")
	else:
		result = await _multi_view_capture.capture_multi_view_async(params_value as Dictionary)
	var final_result := _editor_control.finalize_action_result(request_id, "capture_multi_view", result, started_msec)
	var response := _response_from_request_result(request_id, request_type, final_result, file_name)
	var completion := _request_journal.complete(request_id, response)
	_write_response_atomic(response_path, _journal_response(request_id, request_type, file_name, completion))
	_async_editor_requests_in_flight.erase(file_name)
	_update_ui()


func _handle_request(fallback_id: String, request: Dictionary, request_file_name: String) -> Dictionary:
	var identity := BridgeRequestModel.request_identity(fallback_id, request)
	var request_id := str(identity.get("request_id", fallback_id))
	var request_type := str(identity.get("request_type", ""))
	var claim := _claim_request(fallback_id, request, request_file_name)
	if str(claim.get("state", "")) != "claimed":
		return _journal_response(request_id, request_type, request_file_name, claim)
	var response := _dispatch_request(fallback_id, request, request_file_name)
	var completion := _request_journal.complete(request_id, response)
	return _journal_response(request_id, request_type, request_file_name, completion)


func _claim_request(fallback_id: String, request: Dictionary, request_source: String) -> Dictionary:
	if request_source != "" and request_source != "websocket_rpc" and request_source.ends_with(".json") and fallback_id != str(request.get("request_id", "")):
		return {"ok": false, "error": _error_payload("request_id_mismatch", "The request filename and request_id differ.")}
	if request_source == "websocket_rpc" and fallback_id != str(request.get("request_id", "")):
		return {"ok": false, "error": _error_payload("request_id_mismatch", "The RPC request_id and body request_id differ.")}
	if JSON.stringify(request).to_utf8_buffer().size() > MAX_REQUEST_BYTES:
		return {"ok": false, "error": _error_payload("request_too_large", "The Bridge request is too large.")}
	var limits := BridgeRequestLimits.validate_json_limits(request, 0, {"nodes": 0})
	if not bool(limits.get("ok", false)):
		return limits
	if not bool(_ensure_safe_bridge_directory(_journal_dir_abs).get("ok", false)):
		return {"ok": false, "error": _error_payload("journal_unavailable", "The request journal is unavailable.")}
	return _request_journal.begin(request)


func _journal_response(request_id: String, request_type: String, request_source: String, journal_result: Dictionary) -> Dictionary:
	if bool(journal_result.get("ok", false)) and typeof(journal_result.get("response")) == TYPE_DICTIONARY:
		return journal_result.get("response", {}) as Dictionary
	var error: Dictionary = journal_result.get("error", _error_payload("outcome_unknown", "The request result is unknown; the action will not be retried."))
	return _response_payload(request_id, request_type, "error", {}, error, request_source)


func _write_response_atomic(path: String, response: Dictionary) -> Dictionary:
	var temporary := path + "." + str(Time.get_ticks_usec()) + ".tmp"
	var guard := _validate_bridge_path(temporary, true)
	if not bool(guard.get("ok", false)):
		return {"ok": false, "error": guard.get("error", {})}
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": _error_payload("response_write_failed", "Could not open response staging file.")}
	file.store_string(JSON.stringify(response))
	file.flush()
	var write_ok := file.get_error() == OK
	file.close()
	if not write_ok:
		DirAccess.remove_absolute(temporary)
		return {"ok": false, "error": _error_payload("response_write_failed", "Could not flush response staging file.")}
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(temporary)
		return {"ok": false, "error": _error_payload("response_exists", "Response already exists.")}
	var rename_error := DirAccess.rename_absolute(temporary, path)
	if rename_error != OK:
		DirAccess.remove_absolute(temporary)
		return {"ok": false, "error": _error_payload("response_write_failed", "Could not publish the response file.")}
	return {"ok": true}


func _dispatch_request(fallback_id: String, request: Dictionary, request_file_name: String) -> Dictionary:
	var identity := BridgeRequestModel.request_identity(fallback_id, request)
	var request_id := str(identity.get("request_id", fallback_id))
	var request_type := str(identity.get("request_type", ""))
	var payload := BridgeRequestModel.request_payload(request)

	if ChatRequestModel.is_codex_chat_request_type(request_type):
		var chat_request_result := _codex_chat_request(request_type, payload)
		return _response_from_request_result(request_id, request_type, chat_request_result, request_file_name)

	match request_type:
		"refresh_context":
			var snapshot := _write_context_snapshot("request:" + request_id)
			return _response_payload(request_id, request_type, "completed", {
				"context_snapshot_path": CONTEXT_SNAPSHOT_PATH,
				"context_snapshot_absolute_path": _context_snapshot_abs,
				"generated_at": snapshot.get("generated_at", ""),
				"current_scene": snapshot.get("current_scene", {}),
				"scene_node_count": snapshot.get("scene_tree", {}).get("node_count", 0),
			}, {}, request_file_name)

		"capture_viewport_screenshot":
			if not _permission_enabled("allow_screenshots"):
				return _response_payload(request_id, request_type, "error", {}, _error_payload(
					"permission_denied",
					"Screenshot permission is disabled in the Codex Bridge dock."
				), request_file_name)
			var screenshot_result := _capture_viewport_screenshot("request:" + request_id)
			if screenshot_result.get("ok", false):
				_write_context_snapshot("request_screenshot:" + request_id)
				return _response_payload(request_id, request_type, "completed", {
					"screenshot": screenshot_result.get("screenshot", {}),
				}, {}, request_file_name)
			return _response_payload(request_id, request_type, "error", {}, screenshot_result.get("error", {}), request_file_name)

		"open_scene":
			if not _permission_enabled("allow_open_scene"):
				return _response_payload(request_id, request_type, "error", {}, _error_payload(
					"permission_denied",
					"Open scene permission is disabled in the Codex Bridge dock."
				), request_file_name)
			var open_result := _open_scene_request(payload)
			if open_result.get("ok", false):
				_write_context_snapshot("open_scene:" + request_id)
			return _response_from_request_result(request_id, request_type, open_result, request_file_name)

		"run_current_scene":
			if not _permission_enabled("allow_run_current_scene"):
				return _response_payload(request_id, request_type, "error", {}, _error_payload(
					"permission_denied",
					"Run current scene permission is disabled in the Codex Bridge dock."
				), request_file_name)
			var run_result := _run_current_scene_request()
			return _response_from_request_result(request_id, request_type, run_result, request_file_name)

		"fix_selected_node":
			return _response_payload(request_id, request_type, "error", {}, _error_payload(
				"trusted_node_fix_approval_unavailable",
				"Direct selected-node fixes are disabled until a trusted one-use human approval receipt is bound to the exact selected-node state and proposed property change."
			), request_file_name)

		"editor_control":
			var editor_result := _editor_control_request(request_id, payload)
			return _response_from_request_result(request_id, request_type, editor_result, request_file_name)

		"get_codex_chat_layout_status":
			var layout_result := _get_codex_chat_layout_status_request()
			return _response_from_request_result(request_id, request_type, layout_result, request_file_name)

		"set_codex_chat_advanced_visible":
			var advanced_result := _set_codex_chat_advanced_visible_request(payload)
			return _response_from_request_result(request_id, request_type, advanced_result, request_file_name)

		"set_codex_chat_composer_expanded":
			var composer_result := _set_codex_chat_composer_expanded_request(payload)
			return _response_from_request_result(request_id, request_type, composer_result, request_file_name)

		_:
			return _response_payload(request_id, request_type, "error", {}, _error_payload(
				"unsupported_request_type",
				"Unsupported Godot Codex Bridge request type: " + request_type
			), request_file_name)


func _response_from_request_result(request_id: String, request_type: String, result: Dictionary, request_file_name: String) -> Dictionary:
	var parts := BridgeRequestModel.result_response_parts(result)
	return _response_payload(
		request_id,
		request_type,
		str(parts.get("status", "error")),
		parts.get("data", {}) as Dictionary,
		parts.get("error", {}) as Dictionary,
		request_file_name
	)


func _editor_control_request(request_id: String, payload: Dictionary) -> Dictionary:
	if _editor_control == null:
		return _err("editor_control_unavailable", "Editor control service is not initialized.")
	return _editor_control.handle_request(request_id, payload)


func _register_editor_control_handlers() -> void:
	_editor_control.register_action("refresh_context", Callable(self, "_editor_control_refresh_context_request"))
	_editor_control.register_action("get_state", Callable(self, "_editor_control_get_state_request"))
	_editor_control.register_action("focus_editor", Callable(self, "_focus_editor_request"))
	_editor_control.register_action("focus_panel", Callable(_editor_panel_navigation, "focus_panel"))
	_editor_control.register_action("viewport_navigate", Callable(_editor_viewport_navigation, "navigate"))
	_editor_control.register_action("open_scene", Callable(self, "_editor_control_open_scene_request"))
	_editor_control.register_action("select_node", Callable(self, "_editor_control_select_node_request"))
	_editor_control.register_action("inspect_node", Callable(self, "_editor_control_inspect_node_request"))
	_editor_control.register_action("get_inspector_context", Callable(_editor_inspector_context, "get_inspector_context"))
	_editor_control.register_action("get_node_deep", Callable(self, "_get_node_deep_request"))
	_editor_control.register_action("open_script", Callable(self, "_open_script_request"))
	_editor_control.register_action("list_resources", Callable(_editor_resource_browser, "list_resources"))
	_editor_control.register_action("inspect_imported_assets", Callable(_editor_asset_import, "inspect_imported_assets"))
	_editor_control.register_action("get_class_info", Callable(_editor_class_info, "get_class_info"))
	_editor_control.register_action("inspect_materials", Callable(self, "_inspect_materials_request"))
	_editor_control.register_action("create_shader_material_for_node", Callable(_editor_resource_material, "create_shader_material_for_node"))
	_editor_control.register_action("set_shader_parameter", Callable(_editor_resource_material, "set_shader_parameter"))
	_editor_control.register_action("set_shader_texture_parameter", Callable(_editor_resource_material, "set_shader_texture_parameter"))
	_editor_control.register_action("inspect_rendering_effects", Callable(_editor_rendering_effects, "inspect_rendering_effects"))
	_editor_control.register_action("set_environment_property", Callable(_editor_rendering_effects, "set_environment_property"))
	_editor_control.register_action("create_particle_effect", Callable(_editor_rendering_effects, "create_particle_effect"))
	_editor_control.register_action("set_particle_effect_properties", Callable(_editor_rendering_effects, "set_particle_effect_properties"))
	_editor_control.register_action("list_animation_players", Callable(_editor_animation, "list_animation_players"))
	_editor_control.register_action("inspect_animation", Callable(_editor_animation, "inspect_animation"))
	_editor_control.register_action("preview_animation", Callable(_editor_animation, "preview_animation"))
	_editor_control.register_action("stop_animation_preview", Callable(_editor_animation, "stop_animation_preview"))
	_editor_control.register_action("get_diagnostics", Callable(_editor_diagnostics, "get_diagnostics"))
	_editor_control.register_action("get_spatial_bounds", Callable(_spatial_bounds, "get_spatial_bounds"))
	_editor_control.register_action("spatial_query", Callable(_spatial_bounds, "spatial_query"))
	_editor_control.register_action("placement_check", Callable(_spatial_bounds, "placement_check"))
	_editor_control.register_action("snap_to_ground", Callable(_spatial_bounds, "snap_to_ground"))
	_editor_control.register_action("snap_to_grid", Callable(_spatial_bounds, "snap_to_grid"))
	_editor_control.register_action("clear_diagnostics", Callable(_editor_diagnostics, "clear_diagnostics"))
	_editor_control.register_action("undo_last_bridge_action", Callable(_editor_undo, "undo_last_bridge_action"))
	_editor_control.register_action("set_node_transform", Callable(_editor_scene_mutation, "set_node_transform"))
	_editor_control.register_action("set_node_properties", Callable(_editor_scene_mutation, "set_node_properties"))
	_editor_control.register_action("save_scene", Callable(_editor_scene_save, "save_scene"))
	_editor_control.register_action("save_all_scenes", Callable(_editor_scene_save, "save_all_scenes"))
	_editor_control.register_action("assign_resource_to_node", Callable(_editor_resource_material, "assign_resource_to_node"))
	_editor_control.register_action("create_node_resource", Callable(_editor_resource_material, "create_node_resource"))
	_editor_control.register_action("set_resource_properties", Callable(_editor_resource_material, "set_resource_properties"))
	_editor_control.register_action("place_asset_in_scene", Callable(_editor_asset_import, "place_asset_in_scene"))
	_editor_control.register_action("create_node", Callable(_editor_node_lifecycle, "create_node"))
	_editor_control.register_action("delete_node", Callable(_editor_node_lifecycle, "delete_node"))
	_editor_control.register_action("rename_node", Callable(_editor_node_lifecycle, "rename_node"))
	_editor_control.register_action("reparent_node", Callable(_editor_node_lifecycle, "reparent_node"))
	_editor_control.register_action("duplicate_node", Callable(_editor_node_lifecycle, "duplicate_node"))
	_editor_control.register_action("instance_scene", Callable(_editor_node_lifecycle, "instance_scene"))
	_editor_control.register_action("list_signal_connections", Callable(_editor_signals, "list_signal_connections"))
	_editor_control.register_action("connect_signal", Callable(_editor_signals, "connect_signal"))
	_editor_control.register_action("disconnect_signal", Callable(_editor_signals, "disconnect_signal"))
	_editor_control.register_action("create_animation_clip", Callable(_editor_animation, "create_animation_clip"))
	_editor_control.register_action("notes_get", Callable(_editor_diagnostics, "notes_get"))
	_editor_control.register_action("notes_append", Callable(_editor_diagnostics, "notes_append"))
	_editor_control.register_action("notes_clear", Callable(_editor_diagnostics, "notes_clear"))
	_editor_control.register_action("stop_running_scene", Callable(self, "_stop_running_scene_request"))
	_editor_control.register_action("emergency_stop", Callable(self, "_emergency_stop_request"))
	_editor_control.register_action("capture_multi_view", Callable(_multi_view_capture, "capture_multi_view"))


func _editor_control_refresh_context_request(_params: Dictionary) -> Dictionary:
	var snapshot := _write_context_snapshot("editor_control:refresh_context")
	return _ok({
		"context_snapshot_path": CONTEXT_SNAPSHOT_PATH,
		"context_snapshot_absolute_path": _context_snapshot_abs,
		"generated_at": snapshot.get("generated_at", ""),
		"current_scene": snapshot.get("current_scene", {}),
		"selected_nodes_count": (snapshot.get("selected_nodes", []) as Array).size() if typeof(snapshot.get("selected_nodes", [])) == TYPE_ARRAY else 0,
		"snapshot_refreshed": true,
	})


func _editor_control_get_state_request(_params: Dictionary) -> Dictionary:
	return _ok({
		"editor_state": _editor_state_payload(EditorInterface.get_edited_scene_root()),
	})


func _editor_control_open_scene_request(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_open_scene"):
		return _err("permission_denied", "Open scene permission is disabled in the Codex Bridge dock.")
	return _open_scene_request(params)


func _editor_control_select_node_request(params: Dictionary) -> Dictionary:
	return _select_node_request(params, false)


func _editor_control_inspect_node_request(params: Dictionary) -> Dictionary:
	return _select_node_request(params, true)


func _editor_control_notes_get_request(_params: Dictionary) -> Dictionary:
	return _notes_get_request()


func _execute_editor_control_action(action: String, params: Dictionary) -> Dictionary:
	if _editor_control == null:
		return _err("editor_control_unavailable", "Editor control service is not initialized.")
	return _editor_control.execute_action(action, params)


func _focus_editor_request(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_editor_navigation"):
		return _err("permission_denied", "Navigate editor permission is disabled in the Codex Bridge dock.")

	var main_screen := str(params.get("main_screen", params.get("mainScreen", ""))).strip_edges()
	var selected_file: Variant = null
	if main_screen != "":
		var screen_error := _validate_main_screen_name(main_screen)
		if not screen_error.is_empty():
			return {"ok": false, "error": screen_error}
		EditorInterface.set_main_screen_editor(main_screen)

	var select_file := str(params.get("select_file", params.get("selectFile", ""))).strip_edges()
	if select_file != "":
		var file_error := _validate_res_path(select_file, [], "resource", true)
		if not file_error.is_empty():
			return {"ok": false, "error": file_error}
		EditorInterface.select_file(select_file)
		selected_file = select_file

	var snapshot := _write_context_snapshot("editor_control:focus_editor")
	var data := {
		"main_screen": main_screen,
		"selected_file": selected_file,
		"editor_state": _editor_state_payload(EditorInterface.get_edited_scene_root()),
		"snapshot_refreshed": true,
		"generated_at": snapshot.get("generated_at", ""),
	}
	_log_event("editor_focus_requested", data)
	return _ok(data)


func _select_node_request(params: Dictionary, force_inspect: bool) -> Dictionary:
	if not _permission_enabled("allow_editor_inspect"):
		return _err("permission_denied", "Inspect/select nodes permission is disabled in the Codex Bridge dock.")

	var scene_path := str(params.get("scene_path", params.get("scenePath", ""))).strip_edges()
	if scene_path != "":
		var current_scene := str(_current_scene_path_or_null())
		if current_scene != scene_path:
			if not _permission_enabled("allow_open_scene"):
				return _err("permission_denied", "Open scene permission is disabled; cannot switch scene before selecting a node.")
			var open_result := _open_scene_request({"scene_path": scene_path})
			if not open_result.get("ok", false):
				return open_result

	var node_path := str(params.get("node_path", params.get("nodePath", ""))).strip_edges()
	var node_result := _resolve_editor_node(node_path)
	if not node_result.get("ok", false):
		return node_result
	var node: Node = node_result.get("node", null)
	var scene_root: Node = node_result.get("scene_root", null)

	var additive := bool(params.get("additive", false))
	var selection := EditorInterface.get_selection()
	if selection == null:
		return _err("selection_unavailable", "Godot editor selection is unavailable.")
	if not additive:
		selection.clear()
	selection.add_node(node)

	var focus_inspector := force_inspect or bool(params.get("focus_inspector", params.get("focusInspector", true)))
	if focus_inspector:
		EditorInterface.edit_node(node)
		if EditorInterface.has_method("inspect_object"):
			EditorInterface.call("inspect_object", node)

	var snapshot := _write_context_snapshot("editor_control:select_node")
	var data := {
		"selected_node": _node_inspector_payload(node, scene_root),
		"selected_nodes": _selected_nodes_payload(scene_root),
		"current_scene": _current_scene_payload(scene_root),
		"focus_inspector": focus_inspector,
		"snapshot_refreshed": true,
		"generated_at": snapshot.get("generated_at", ""),
	}
	_log_event("editor_node_selected", {
		"node_path": _scene_path_for(node, scene_root),
		"focus_inspector": focus_inspector,
	})
	return _ok(data)


func _get_node_deep_request(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_editor_inspect"):
		return _err("permission_denied", "Inspect/select nodes permission is disabled in the Codex Bridge dock.")

	var node_result := _resolve_editor_node(str(params.get("node_path", params.get("nodePath", ""))).strip_edges())
	if not node_result.get("ok", false):
		return node_result
	var node: Node = node_result.get("node", null)
	var scene_root: Node = node_result.get("scene_root", null)
	var max_depth := clampi(int(params.get("depth", 2)), 0, 8)
	var max_nodes := clampi(int(params.get("max_nodes", params.get("maxNodes", 96))), 1, MAX_SCENE_NODES)
	var include_properties := bool(params.get("include_properties", params.get("includeProperties", true)))
	var state := {
		"count": 0,
		"truncated": false,
		"max_nodes": max_nodes,
	}
	return _ok({
		"captured_at": _iso_now(),
		"root": _deep_node_payload(node, scene_root, max_depth, include_properties, state),
		"node_count": int(state.get("count", 0)),
		"truncated": bool(state.get("truncated", false)),
		"limits": {
			"max_depth": max_depth,
			"max_nodes": max_nodes,
			"max_properties_per_node": MAX_PROPERTIES_PER_NODE,
			"max_string_length": MAX_STRING_LENGTH,
		},
		"snapshot_refreshed": false,
	})


func _inspect_imported_assets_request(params: Dictionary) -> Dictionary:
	if _editor_asset_import == null:
		return _err("editor_asset_import_unavailable", "Editor asset/import service is not initialized.")
	return _editor_asset_import.inspect_imported_assets(params)


func _inspect_materials_request(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_editor_inspect"):
		return _err("permission_denied", "Inspect/select nodes permission is disabled in the Codex Bridge dock.")

	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return _err("no_current_scene", "No edited scene is open.")

	var include_shader_params := bool(params.get("include_shader_params", params.get("includeShaderParams", true)))
	var include_empty := bool(params.get("include_empty", params.get("includeEmpty", false)))
	var selected_only := bool(params.get("selected_only", params.get("selectedOnly", false)))
	var max_nodes := clampi(int(params.get("max_nodes", params.get("maxNodes", MAX_MATERIAL_INSPECT_NODES))), 1, MAX_MATERIAL_INSPECT_NODES)
	var max_slots := clampi(int(params.get("max_slots", params.get("maxSlots", MAX_MATERIAL_SLOTS))), 1, MAX_MATERIAL_SLOTS)
	var node_path := str(params.get("node_path", params.get("nodePath", ""))).strip_edges()

	var targets: Array = []
	var collect_state := {
		"visited": 0,
		"truncated": false,
	}
	if node_path != "":
		var node_result := _resolve_editor_node(node_path)
		if not node_result.get("ok", false):
			return node_result
		targets.append(node_result.get("node", null))
	elif selected_only:
		var selection := EditorInterface.get_selection()
		if selection != null:
			for selected in selection.get_selected_nodes():
				if selected != null and (selected == scene_root or scene_root.is_ancestor_of(selected)):
					targets.append(selected)
					if targets.size() >= max_nodes:
						collect_state["truncated"] = true
						break
	else:
		MaterialDiagnosticsModel.collect_candidate_nodes(scene_root, targets, collect_state, max_nodes)

	var nodes: Array = []
	var suggestions: Array = []
	var unique_materials := {}
	var stats := {
		"material_slots": 0,
		"shader_materials": 0,
		"shader_uniforms": 0,
	}
	var material_limits := {
		"max_materials_per_mesh": MAX_MATERIALS_PER_MESH,
		"max_shader_uniforms": MAX_SHADER_UNIFORMS,
		"max_property_depth": MAX_PROPERTY_DEPTH,
		"max_array_items": MAX_ARRAY_ITEMS,
		"max_dictionary_items": MAX_DICTIONARY_ITEMS,
		"max_string_length": MAX_STRING_LENGTH,
	}
	var slots_truncated := false
	for target in targets:
		if target == null:
			continue
		if int(stats.get("material_slots", 0)) >= max_slots:
			slots_truncated = true
			break
		var node_payload := MaterialDiagnosticsModel.node_materials_payload(
			target as Node,
			scene_root,
			include_shader_params,
			include_empty,
			max_slots - int(stats.get("material_slots", 0)),
			stats,
			unique_materials,
			suggestions,
			material_limits
		)
		var slot_count := (node_payload.get("material_slots", []) as Array).size()
		if include_empty or slot_count > 0:
			nodes.append(node_payload)
		if bool(node_payload.get("slots_truncated", false)):
			slots_truncated = true
			break

	return _ok({
		"captured_at": _iso_now(),
		"current_scene": _current_scene_payload(scene_root),
		"node_path": node_path if node_path != "" else null,
		"selected_only": selected_only,
		"include_shader_params": include_shader_params,
		"include_empty": include_empty,
		"nodes": nodes,
		"returned_node_count": nodes.size(),
		"candidate_node_count": targets.size(),
		"visited_node_count": int(collect_state.get("visited", 0)),
		"material_slot_count": int(stats.get("material_slots", 0)),
		"unique_material_count": unique_materials.size(),
		"shader_material_count": int(stats.get("shader_materials", 0)),
		"shader_uniform_count": int(stats.get("shader_uniforms", 0)),
		"suggestions": suggestions,
		"truncated": bool(collect_state.get("truncated", false)) or slots_truncated,
		"limits": {
			"max_nodes": max_nodes,
			"max_slots": max_slots,
			"max_materials_per_mesh": MAX_MATERIALS_PER_MESH,
			"max_shader_uniforms": MAX_SHADER_UNIFORMS,
		},
		"snapshot_refreshed": false,
	})


func _inspect_rendering_effects_request(params: Dictionary) -> Dictionary:
	if _editor_rendering_effects == null:
		return _err("editor_rendering_effects_unavailable", "Editor rendering/effects service is not initialized.")
	return _editor_rendering_effects.inspect_rendering_effects(params)


func _collect_rendering_effect_nodes(node: Node, scene_root: Node, world_environment_nodes: Array, camera_nodes: Array, particle_nodes: Array, state: Dictionary, max_nodes: int, include_particles: bool) -> void:
	EditorRenderingEffects.collect_rendering_effect_nodes(node, scene_root, world_environment_nodes, camera_nodes, particle_nodes, state, max_nodes, include_particles)


func _register_rendering_effect_match(state: Dictionary, max_nodes: int) -> bool:
	return EditorRenderingEffects.register_rendering_effect_match(state, max_nodes)


func _node_is_particle_effect(node: Node) -> bool:
	return EditorRenderingEffects.node_is_particle_effect(node)


func _node_has_non_null_property(node: Node, property_name: String) -> bool:
	return EditorRenderingEffects.node_has_non_null_property(node, property_name)


func _world_environment_payload(node: Node, scene_root: Node, include_environment_properties: bool, stats: Dictionary, suggestions: Array) -> Dictionary:
	return EditorRenderingEffects.world_environment_payload(node, scene_root, include_environment_properties, stats, suggestions)


func _camera_environment_payload(node: Node, scene_root: Node, include_environment_properties: bool, stats: Dictionary, suggestions: Array) -> Dictionary:
	return EditorRenderingEffects.camera_environment_payload(node, scene_root, include_environment_properties, stats, suggestions)


func _environment_payload(environment: Environment, include_properties: bool, stats: Dictionary) -> Variant:
	return EditorRenderingEffects.environment_payload(environment, include_properties, stats)


func _environment_enabled_effects(environment: Environment) -> Array:
	return EditorRenderingEffects.environment_enabled_effects(environment)


func _environment_property_names() -> Array:
	return EditorRenderingEffects.environment_property_names()


func _environment_mutable_property_names() -> Array:
	return EditorRenderingEffects.environment_mutable_property_names()


func _set_environment_property_request(params: Dictionary) -> Dictionary:
	if _editor_rendering_effects == null:
		return _err("editor_rendering_effects_unavailable", "Editor rendering/effects service is not initialized.")
	return _editor_rendering_effects.set_environment_property(params)


func _validate_environment_mutable_property(property_name: String) -> Dictionary:
	return EditorRenderingEffects.validate_environment_mutable_property(property_name)


func _particle_node_payload(node: Node, scene_root: Node, stats: Dictionary, suggestions: Array) -> Dictionary:
	return EditorRenderingEffects.particle_node_payload(node, scene_root, stats, suggestions)


func _create_particle_effect_request(params: Dictionary) -> Dictionary:
	if _editor_rendering_effects == null:
		return _err("editor_rendering_effects_unavailable", "Editor rendering/effects service is not initialized.")
	return _editor_rendering_effects.create_particle_effect(params)


func _set_particle_effect_properties_request(params: Dictionary) -> Dictionary:
	if _editor_rendering_effects == null:
		return _err("editor_rendering_effects_unavailable", "Editor rendering/effects service is not initialized.")
	return _editor_rendering_effects.set_particle_effect_properties(params)


func _append_initial_property_change(object: Object, property_name: String, new_value: Variant, changes: Array) -> void:
	EditorRenderingEffects.append_initial_property_change(object, property_name, new_value, changes)


func _add_object_property_change_to_undo(undo: EditorUndoRedoManager, change: Dictionary) -> void:
	EditorRenderingEffects.add_object_property_change_to_undo(undo, change)


func _object_named_properties_payload(object: Object, property_names: Array) -> Dictionary:
	return EditorRenderingEffects.object_named_properties_payload(object, property_names)


func _particle_draw_passes_payload(node: Node) -> Array:
	return EditorRenderingEffects.particle_draw_passes_payload(node)


func _list_animation_players_request(params: Dictionary) -> Dictionary:
	if _editor_animation == null:
		return _err("editor_animation_unavailable", "Editor animation service is not initialized.")
	return _editor_animation.list_animation_players(params)
func _inspect_animation_request(params: Dictionary) -> Dictionary:
	if _editor_animation == null:
		return _err("editor_animation_unavailable", "Editor animation service is not initialized.")
	return _editor_animation.inspect_animation(params)
func _preview_animation_request(params: Dictionary) -> Dictionary:
	if _editor_animation == null:
		return _err("editor_animation_unavailable", "Editor animation service is not initialized.")
	return _editor_animation.preview_animation(params)
func _stop_animation_preview_request(params: Dictionary) -> Dictionary:
	if _editor_animation == null:
		return _err("editor_animation_unavailable", "Editor animation service is not initialized.")
	return _editor_animation.stop_animation_preview(params)
func _open_script_request(params: Dictionary) -> Dictionary:
	if _editor_script_navigation == null:
		return _err("editor_script_navigation_unavailable", "Editor script navigation service is not initialized.")
	return _editor_script_navigation.open_script(params)


func _get_diagnostics_request(params: Dictionary) -> Dictionary:
	if _editor_diagnostics == null:
		return _err("editor_diagnostics_unavailable", "Editor diagnostics service is not initialized.")
	return _editor_diagnostics.get_diagnostics(params)


func _clear_diagnostics_request(_params: Dictionary) -> Dictionary:
	if _editor_diagnostics == null:
		return _err("editor_diagnostics_unavailable", "Editor diagnostics service is not initialized.")
	return _editor_diagnostics.clear_diagnostics(_params)


func _set_node_transform_request(params: Dictionary) -> Dictionary:
	if _editor_scene_mutation == null:
		return _err("editor_scene_mutation_unavailable", "Editor scene mutation service is not initialized.")
	return _editor_scene_mutation.set_node_transform(params)


func _set_node_properties_request(params: Dictionary) -> Dictionary:
	if _editor_scene_mutation == null:
		return _err("editor_scene_mutation_unavailable", "Editor scene mutation service is not initialized.")
	return _editor_scene_mutation.set_node_properties(params)


func _assign_resource_to_node_request(params: Dictionary) -> Dictionary:
	if _editor_resource_material == null:
		return _err("editor_resource_material_unavailable", "Editor resource/material service is not initialized.")
	return _editor_resource_material.assign_resource_to_node(params)
func _create_node_resource_request(params: Dictionary) -> Dictionary:
	if _editor_resource_material == null:
		return _err("editor_resource_material_unavailable", "Editor resource/material service is not initialized.")
	return _editor_resource_material.create_node_resource(params)
func _set_resource_properties_request(params: Dictionary) -> Dictionary:
	if _editor_resource_material == null:
		return _err("editor_resource_material_unavailable", "Editor resource/material service is not initialized.")
	return _editor_resource_material.set_resource_properties(params)
func _create_shader_material_for_node_request(params: Dictionary) -> Dictionary:
	if _editor_resource_material == null:
		return _err("editor_resource_material_unavailable", "Editor resource/material service is not initialized.")
	return _editor_resource_material.create_shader_material_for_node(params)
func _set_shader_parameter_request(params: Dictionary) -> Dictionary:
	if _editor_resource_material == null:
		return _err("editor_resource_material_unavailable", "Editor resource/material service is not initialized.")
	return _editor_resource_material.set_shader_parameter(params)
func _set_shader_texture_parameter_request(params: Dictionary) -> Dictionary:
	if _editor_resource_material == null:
		return _err("editor_resource_material_unavailable", "Editor resource/material service is not initialized.")
	return _editor_resource_material.set_shader_texture_parameter(params)
func _place_asset_in_scene_request(params: Dictionary) -> Dictionary:
	if _editor_asset_import == null:
		return _err("editor_asset_import_unavailable", "Editor asset/import service is not initialized.")
	return _editor_asset_import.place_asset_in_scene(params)


func _create_node_request(params: Dictionary) -> Dictionary:
	if _editor_node_lifecycle == null:
		return _err("editor_node_lifecycle_unavailable", "Editor node lifecycle service is not initialized.")
	return _editor_node_lifecycle.create_node(params)


func _delete_node_request(params: Dictionary) -> Dictionary:
	if _editor_node_lifecycle == null:
		return _err("editor_node_lifecycle_unavailable", "Editor node lifecycle service is not initialized.")
	return _editor_node_lifecycle.delete_node(params)


func _rename_node_request(params: Dictionary) -> Dictionary:
	if _editor_node_lifecycle == null:
		return _err("editor_node_lifecycle_unavailable", "Editor node lifecycle service is not initialized.")
	return _editor_node_lifecycle.rename_node(params)


func _reparent_node_request(params: Dictionary) -> Dictionary:
	if _editor_node_lifecycle == null:
		return _err("editor_node_lifecycle_unavailable", "Editor node lifecycle service is not initialized.")
	return _editor_node_lifecycle.reparent_node(params)


func _duplicate_node_request(params: Dictionary) -> Dictionary:
	if _editor_node_lifecycle == null:
		return _err("editor_node_lifecycle_unavailable", "Editor node lifecycle service is not initialized.")
	return _editor_node_lifecycle.duplicate_node(params)


func _instance_scene_request(params: Dictionary) -> Dictionary:
	if _editor_node_lifecycle == null:
		return _err("editor_node_lifecycle_unavailable", "Editor node lifecycle service is not initialized.")
	return _editor_node_lifecycle.instance_scene(params)


func _list_signal_connections_request(params: Dictionary) -> Dictionary:
	if _editor_signals == null:
		return _err("editor_signals_unavailable", "Editor signals service is not initialized.")
	return _editor_signals.list_signal_connections(params)
func _connect_signal_request(params: Dictionary) -> Dictionary:
	if _editor_signals == null:
		return _err("editor_signals_unavailable", "Editor signals service is not initialized.")
	return _editor_signals.connect_signal(params)
func _disconnect_signal_request(params: Dictionary) -> Dictionary:
	if _editor_signals == null:
		return _err("editor_signals_unavailable", "Editor signals service is not initialized.")
	return _editor_signals.disconnect_signal(params)
func _create_animation_clip_request(params: Dictionary) -> Dictionary:
	if _editor_animation == null:
		return _err("editor_animation_unavailable", "Editor animation service is not initialized.")
	return _editor_animation.create_animation_clip(params)
func _run_current_scene_request() -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return {
			"ok": false,
			"error": _error_payload("no_current_scene", "Cannot run current scene because no scene is open."),
		}

	if EditorInterface.is_playing_scene():
		return {
			"ok": false,
			"error": _error_payload("scene_already_playing", "Godot is already playing a scene."),
		}

	EditorInterface.play_current_scene()
	_bridge_owned_play_session = true
	var data := {
		"started": true,
		"scene_file_path": scene_root.scene_file_path,
		"requested_at": _iso_now(),
		"playing_scene": EditorInterface.get_playing_scene(),
	}
	_log_event("run_current_scene_requested", data)
	_last_status = "Run current scene requested"
	_update_ui()

	return {
		"ok": true,
		"data": data,
	}


func _stop_running_scene_request(_params: Dictionary = {}) -> Dictionary:
	var was_playing := EditorInterface.is_playing_scene()
	var playing_scene := EditorInterface.get_playing_scene()
	if was_playing:
		EditorInterface.stop_playing_scene()
	_bridge_owned_play_session = false
	var data := {
		"was_playing": was_playing,
		"playing_scene": playing_scene,
		"stopped": was_playing,
		"requested_at": _iso_now(),
		"guidance": "Stopped the active Godot play session." if was_playing else "No Godot play session was active.",
	}
	_log_event("stop_running_scene_requested", data)
	_last_status = "Stop running scene requested" if was_playing else "No running scene to stop"
	_update_ui()

	return {
		"ok": true,
		"data": data,
	}


## Safety cleanup: stops only a play session Bridge started. It never saves,
## never mutates the edited scene and never stops a user-started session.
## This addon version holds no playtest input or session token (playtest input
## is disabled), so there is no held input or token left to release.
func _emergency_stop_request(params: Dictionary = {}) -> Dictionary:
	var source := str(params.get("source", "emergency_stop")).strip_edges().left(64)
	if source == "":
		source = "emergency_stop"
	var was_playing := EditorInterface.is_playing_scene()
	var bridge_owned := _bridge_owned_play_session and was_playing
	var data := {}
	if bridge_owned:
		data = (_stop_running_scene_request({"source": source}).get("data", {}) as Dictionary).duplicate()
	else:
		_bridge_owned_play_session = false
		data = {
			"was_playing": was_playing,
			"playing_scene": EditorInterface.get_playing_scene(),
			"stopped": false,
			"requested_at": _iso_now(),
		}
	data["action"] = "emergency_stop"
	data["emergency_stop"] = true
	data["source"] = source
	data["bridge_owned_play_session"] = bridge_owned
	data["playtest_input_active"] = false
	data["held_actions_released"] = true
	data["session_closed"] = true
	data["playtest_cleanup_ok"] = true
	data["runtime_input_blocked_after_stop"] = true
	data["scene_mutated"] = false
	if bridge_owned:
		data["guidance"] = "Emergency stop stopped the Bridge-owned play session. Playtest input is disabled in this addon version, so no held input or session token remained."
	elif was_playing:
		data["guidance"] = "A play session is running but was not started by Godot Codex Bridge, so emergency stop left it running. Stop it in the editor or with stop_running_scene."
	else:
		data["guidance"] = "No Godot play session was active; Bridge runtime work is idle."
	_log_event("emergency_stop_requested", data)
	return _ok(data)


func _open_scene_request(payload: Dictionary) -> Dictionary:
	var scene_path := str(payload.get("scene_path", payload.get("scenePath", ""))).strip_edges()
	var path_error := _validate_open_scene_path(scene_path)
	if not path_error.is_empty():
		return {
			"ok": false,
			"error": path_error,
		}

	var make_main_screen := str(payload.get("make_main_screen", payload.get("makeMainScreen", ""))).strip_edges()
	if make_main_screen != "" and make_main_screen != "2D" and make_main_screen != "3D" and make_main_screen != "Script":
		return {
			"ok": false,
			"error": _error_payload("invalid_main_screen", "make_main_screen must be 2D, 3D or Script."),
		}

	var select_in_file_system := bool(payload.get("select_in_file_system", payload.get("selectInFileSystem", false)))
	if select_in_file_system:
		EditorInterface.select_file(scene_path)
	if make_main_screen != "":
		EditorInterface.set_main_screen_editor(make_main_screen)

	EditorInterface.open_scene_from_path(scene_path)
	var scene_root := EditorInterface.get_edited_scene_root()
	var current_scene := _current_scene_payload(scene_root)
	var opened_path := str(current_scene.get("path", ""))
	var data := {
		"opened_scene": scene_path,
		"current_scene": current_scene,
		"open_scenes": _open_scenes_payload(),
		"selected_file": scene_path if select_in_file_system else null,
		"main_screen": make_main_screen,
		"requested_at": _iso_now(),
	}
	_log_event("open_scene_requested", data)
	_last_status = "Open scene requested: " + scene_path
	_update_ui()
	if opened_path != "" and opened_path != scene_path:
		_append_chat_detail("Open scene requested, but active scene is currently " + opened_path)

	return {
		"ok": true,
		"data": data,
	}


func _validate_open_scene_path(scene_path: String) -> Dictionary:
	return EditorPathGuard.validate_scene_path(scene_path, true)


func _validate_placeable_asset_path(asset_path: String) -> Dictionary:
	return _validate_res_path(asset_path, AssetImportModel.placeable_asset_extensions(), "asset", true)


func _get_codex_chat_layout_status_request() -> Dictionary:
	if _chat_dock == null or _chat_input == null or _chat_log_frame == null or _chat_log_view == null:
		return {
			"ok": false,
			"error": _error_payload("chat_ui_unavailable", "Codex Chat UI controls are not initialized."),
		}

	_focus_codex_chat_panel()

	var panel_rect := _chat_dock.get_global_rect()
	var input_rect := _chat_input.get_global_rect()
	var input_row_rect := _chat_input_row.get_global_rect() if _chat_input_row != null else Rect2()
	var eye_rect := _chat_eye_button.get_global_rect() if _chat_eye_button != null else Rect2()
	var composer_toggle_rect := _chat_composer_toggle_button.get_global_rect() if _chat_composer_toggle_button != null else Rect2()
	var advanced_toggle_rect := _chat_advanced_toggle.get_global_rect() if _chat_advanced_toggle != null else Rect2()
	var connect_button_rect := _chat_connect_button.get_global_rect() if _chat_connect_button != null else Rect2()
	var frame_rect := _chat_log_frame.get_global_rect()
	var log_rect := _chat_log_view.get_global_rect()
	var approval_rect := _chat_approval_panel.get_global_rect() if _chat_approval_panel != null else Rect2()
	var status_header: Node = _chat_status_label.get_parent() if _chat_status_label != null else null
	var connect_button_in_status_header := (
		status_header != null
		and _chat_connect_button != null
		and _chat_connect_button.get_parent() == status_header
		and _chat_advanced_toggle != null
		and _chat_advanced_toggle.get_parent() == status_header
	)
	var editor_main_screen: Control = EditorInterface.get_editor_main_screen()
	var main_screen_registered := (
		_main_screen != null
		and is_instance_valid(_main_screen)
		and _main_screen.get_parent() == editor_main_screen
		and _main_screen.is_inside_tree()
	)
	var dock_registered := (
		_dock != null
		and is_instance_valid(_dock)
		and _dock.get_parent() != null
		and _dock.is_inside_tree()
		and _chat_dock != null
		and _dock.is_ancestor_of(_chat_dock)
	)
	var bottom_panel_registered := (
		_chat_dock != null
		and _chat_dock.is_inside_tree()
		and _chat_dock.get_parent() != null
		and _chat_dock.get_parent() != _dock
	)
	var window_position := DisplayServer.window_get_position()
	var window_size := DisplayServer.window_get_size()
	var window_screen := DisplayServer.window_get_current_screen()
	var usable_rect := DisplayServer.screen_get_usable_rect(window_screen)
	var chat_control_counts := _chat_message_control_counts()
	var annotation_status := _annotation_controller.status_payload() if _annotation_controller != null else {}
	var status_data := ChatLayoutStatusModel.build_status(
		{
			"panel_rect": panel_rect,
			"input_rect": input_rect,
			"input_row_rect": input_row_rect,
			"eye_rect": eye_rect,
			"composer_toggle_rect": composer_toggle_rect,
			"connect_button_rect": connect_button_rect,
			"frame_rect": frame_rect,
			"log_rect": log_rect,
			"approval_rect": approval_rect,
			"advanced_toggle_rect": advanced_toggle_rect,
		},
		{
			"input_visible": _chat_input.is_visible_in_tree(),
			"input_minimum_size": _chat_input.custom_minimum_size,
			"input_row_minimum_size": _chat_input_row.custom_minimum_size if _chat_input_row != null else Vector2(),
			"input_scroll_fit_content_height": _chat_input.scroll_fit_content_height,
			"composer_expanded": _chat_composer_expanded,
			"composer_toggle_visible": _chat_composer_toggle_button != null and _chat_composer_toggle_button.is_visible_in_tree(),
			"composer_toggle_text": DockStyle.button_label(_chat_composer_toggle_button),
			"eye_button_visible": _chat_eye_button != null and _chat_eye_button.is_visible_in_tree(),
			"approval_visible": _chat_approval_panel != null and _chat_approval_panel.visible,
			"panel_minimum_size": _chat_dock.custom_minimum_size,
			"log_frame_minimum_size": _chat_log_frame.custom_minimum_size,
			"log_minimum_size": _chat_log_view.custom_minimum_size,
			"visibility_chain": _control_visibility_chain(_chat_dock),
			"readiness_label_text": _chat_readiness_label.text if _chat_readiness_label != null else "",
			"readiness_label_tooltip": _chat_readiness_label.tooltip_text if _chat_readiness_label != null else "",
			"advanced_visible": _chat_advanced_panel != null and _chat_advanced_panel.visible,
			"advanced_toggle_visible": _chat_advanced_toggle != null and _chat_advanced_toggle.is_visible_in_tree(),
			"advanced_toggle_focus_mode": _chat_advanced_toggle.focus_mode if _chat_advanced_toggle != null else -1,
			"connect_button_visible": _chat_connect_button != null and _chat_connect_button.is_visible_in_tree(),
			"connect_button_in_status_header": connect_button_in_status_header,
			"connect_button_focus_mode": _chat_connect_button.focus_mode if _chat_connect_button != null else -1,
			"enable_tools_button_visible": _chat_enable_tools_button != null and _chat_enable_tools_button.is_visible_in_tree(),
			"model_option_visible": _chat_model_option != null and _chat_model_option.is_visible_in_tree(),
			"reasoning_option_visible": _chat_reasoning_option != null and _chat_reasoning_option.is_visible_in_tree(),
			"trust_button_visible": _chat_trust_button != null and _chat_trust_button.is_visible_in_tree(),
			"attach_context_visible": _chat_attach_context != null and _chat_attach_context.is_visible_in_tree(),
			"attach_selected_visible": _chat_attach_selected != null and _chat_attach_selected.is_visible_in_tree(),
			"attach_screenshot_visible": _chat_attach_screenshot != null and _chat_attach_screenshot.is_visible_in_tree(),
			"team_review_button_visible": _team_review_button != null and _team_review_button.is_visible_in_tree(),
			"team_status_visible": _team_status_label != null and _team_status_label.is_visible_in_tree(),
			"main_screen_registered": main_screen_registered,
			"dock_registered": dock_registered,
			"bottom_panel_registered": bottom_panel_registered,
		},
		{
			"connection_state": _chat_connection_state,
			"runtime_state": _chat_runtime_state,
			"mcp_tools_available": _chat_mcp_tools_available,
			"mcp_tool_count": _chat_mcp_tool_count,
			"mcp_godot_tool_count": _chat_mcp_godot_tool_count,
			"mcp_server_name": _chat_mcp_server_name,
			"last_tool_inventory_at": _chat_last_tool_inventory_at,
			"tool_visibility_error": _chat_tool_visibility_error,
			"host_config_path": HOST_CONFIG_PATH,
			"host_config_loaded": not _host_config.is_empty(),
			"host_config_status": _host_config_status,
			"host_config_message": _host_config_message,
			"host_config_runtime": _host_config_runtime,
			"host_config_port": _host_config_port,
			"host_config_launcher_path": _host_config_launcher_path,
			"host_url": _codex_host_url,
			"host_start_in_progress": _host_start_in_progress,
			"host_process_id": _host_start_process_id,
			"host_process_owned_by_addon": _host_start_process_id > 0,
			"last_completed_project_attach_request_id": _chat_last_completed_project_attach_request_id,
			"last_completed_project_attach_method": _chat_last_completed_project_attach_method,
			"trust_mode": _chat_trust_mode,
			"working_indicator_visible": _chat_working_label != null and _chat_working_label.visible,
			"working_indicator_text": _chat_working_label.text if _chat_working_label != null else "",
			"working_elapsed_seconds": int((Time.get_ticks_msec() - _chat_foreground_busy_started_msec) / 1000) if _chat_foreground_busy_started_msec > 0 else 0,
			"thread_label_text": _chat_thread_label.text if _chat_thread_label != null else "",
			"new_chat_button_visible": _chat_new_button != null and _chat_new_button.is_visible_in_tree(),
			"new_chat_button_disabled": _chat_new_button.disabled if _chat_new_button != null else true,
			"clear_chat_button_visible": _chat_clear_button != null and _chat_clear_button.is_visible_in_tree(),
			"clear_chat_button_disabled": _chat_clear_button.disabled if _chat_clear_button != null else true,
			"active_project_root": _chat_active_project_root,
			"agents_count": _chat_agents_count,
			"agents_paths": _chat_agents_paths,
			"agents_status": _chat_agents_state_label(),
			"agents_status_detail": _chat_agents_status_detail(),
			"recoverable_message": _chat_recoverable_message,
			"fatal_message": _chat_fatal_message,
		},
		{
			"chat_message_count": _chat_message_count(),
			"chat_copy_button_count": chat_control_counts.get("copy_button_count", 0),
			"chat_copy_icon_button_count": chat_control_counts.get("copy_icon_button_count", 0),
			"chat_copy_icon_button_max_width": chat_control_counts.get("copy_icon_button_max_width", 0.0),
			"chat_copy_icon_button_max_height": chat_control_counts.get("copy_icon_button_max_height", 0.0),
			"chat_collapsible_message_count": chat_control_counts.get("collapsible_message_count", 0),
			"chat_collapsed_message_count": chat_control_counts.get("collapsed_message_count", 0),
			"chat_diff_preview_count": chat_control_counts.get("diff_preview_count", 0),
			"chat_diff_file_section_count": chat_control_counts.get("diff_file_section_count", 0),
			"chat_diff_expanded_file_section_count": chat_control_counts.get("diff_expanded_file_section_count", 0),
			"chat_diff_files_box_visible_count": chat_control_counts.get("diff_files_box_visible_count", 0),
			"chat_work_batch_count": chat_control_counts.get("work_batch_count", 0),
			"chat_work_details_visible_count": chat_control_counts.get("work_details_visible_count", 0),
			"active_work_updates": _chat_active_work_updates,
			"active_work_visible": _chat_active_work_visible,
			"active_diff_file_count": _chat_active_diff_file_count,
			"active_diff_added_count": _chat_active_diff_added_count,
			"active_diff_removed_count": _chat_active_diff_removed_count,
			"active_diff_files_visible": _chat_active_diff_files_visible,
			"technical_log_count": _chat_technical_log.size(),
		},
		annotation_status,
		{
			"window_mode": DisplayServer.window_get_mode(),
			"window_position": window_position,
			"window_size": window_size,
			"window_screen": window_screen,
			"usable_rect": usable_rect,
		}
	)
	status_data["host_pair_dialog_visible"] = _host_pair_dialog != null and _host_pair_dialog.visible
	status_data["host_pair_input_masked"] = _host_pair_input != null and _host_pair_input.secret
	status_data["host_paired"] = _host_paired
	return {
		"ok": true,
		"data": status_data,
	}


func _set_codex_chat_advanced_visible_request(payload: Dictionary) -> Dictionary:
	if _chat_advanced_panel == null:
		return _err("chat_ui_unavailable", "Codex Chat advanced controls are not initialized.")
	_set_chat_advanced_visible(bool(payload.get("visible", false)))
	return _get_codex_chat_layout_status_request()


func _set_codex_chat_composer_expanded_request(payload: Dictionary) -> Dictionary:
	if _chat_input == null or _chat_input_row == null or _chat_composer_toggle_button == null:
		return _err("chat_ui_unavailable", "Codex Chat composer controls are not initialized.")
	_set_chat_composer_expanded(bool(payload.get("expanded", false)))
	return _get_codex_chat_layout_status_request()


func _validate_codex_chat_input_multiline_request() -> Dictionary:
	if _chat_input == null:
		return _err("chat_input_unavailable", "Codex Chat input is not initialized.")
	var previous_text := _chat_input.text
	var previous_caret_line := _chat_input.get_caret_line()
	var previous_caret_column := _chat_input.get_caret_column()
	var previous_expanded := _chat_composer_expanded
	_chat_input.text = "line one"
	_refresh_chat_composer_height(true)
	_chat_input.set_caret_line(0)
	_chat_input.set_caret_column(_chat_input.text.length())
	var shift_enter_event := InputEventKey.new()
	shift_enter_event.keycode = KEY_ENTER
	shift_enter_event.physical_keycode = KEY_ENTER
	shift_enter_event.pressed = true
	shift_enter_event.shift_pressed = true
	var handled_event := _dispatch_chat_input_key_event(shift_enter_event)
	var result_text := _chat_input.text
	var line_count := _chat_input.get_line_count()
	var auto_minimum_size := _chat_input.custom_minimum_size
	var auto_row_minimum_size := _chat_input_row.custom_minimum_size if _chat_input_row != null else Vector2()
	var has_newline := result_text.find("\n") >= 0
	var expanded_after_shift_enter := _chat_composer_expanded
	_chat_input.text = previous_text
	_chat_composer_expanded = previous_expanded
	_refresh_chat_composer_height()
	_chat_input.set_caret_line(min(previous_caret_line, max(_chat_input.get_line_count() - 1, 0)))
	_chat_input.set_caret_column(previous_caret_column)
	return _ok({
		"text_after_shift_enter": result_text,
		"handled_event": handled_event,
		"has_newline": has_newline,
		"line_count": line_count,
		"auto_input_minimum_size": _variant_to_json_value(auto_minimum_size),
		"auto_input_row_minimum_size": _variant_to_json_value(auto_row_minimum_size),
		"expanded_after_shift_enter": expanded_after_shift_enter,
		"input_minimum_size": _variant_to_json_value(_chat_input.custom_minimum_size),
		"input_row_minimum_size": _variant_to_json_value(_chat_input_row.custom_minimum_size) if _chat_input_row != null else _variant_to_json_value(Vector2()),
		"input_scroll_fit_content_height": _chat_input.scroll_fit_content_height,
		"composer_expanded": _chat_composer_expanded,
	})


func _validate_codex_chat_history_interaction_request() -> Dictionary:
	if _chat_transcript_view == null or _chat_message_list == null:
		return _err("chat_ui_unavailable", "Codex Chat transcript is not initialized.")
	_clear_chat_transcript()
	_append_chat_user_message("Prašau patikrinti senesnių darbo užrašų elgseną.")

	_record_chat_work_update("Skaitau miesto sceną ir renku tikrus mazgų duomenis.", "replay-work-1")
	_record_chat_work_update("Tikrinamos ilgos res://world/city/characters/merchant_very_long_resource_name.tscn nuorodos.", "replay-work-2")
	var first_controls := _chat_active_work_controls.duplicate()
	var first_body := first_controls.get("body_label", null) as Label
	var first_toggle := first_controls.get("toggle_button", null) as Button
	first_toggle.pressed.emit()
	var first_expanded := first_body != null and first_body.visible

	_reset_chat_work_batch()
	_append_chat_user_message("Antra užduotis: patikrink sklandų lipimą laiptais.")
	_record_chat_work_update("Lyginu veikėjo vertikalų judėjimą su laiptų kolizija.", "replay-work-3")
	var second_controls := _chat_active_work_controls.duplicate()
	var second_body := second_controls.get("body_label", null) as Label
	var second_toggle := second_controls.get("toggle_button", null) as Button
	second_toggle.pressed.emit()
	second_toggle.pressed.emit()
	var second_collapsed := second_body != null and not second_body.visible
	var first_unchanged_after_second := first_body != null and first_body.visible

	_reset_chat_work_batch()
	_append_chat_user_message("Trečia užduotis: pasiūlyk miesto tekstūrų kryptį.")
	_record_chat_work_update("Peržiūriu medžiagų spalvas ir paviršių pasikartojimą.", "replay-work-4")
	var current_body := _chat_active_work_controls.get("body_label", null) as Label
	first_toggle.pressed.emit()
	var first_collapsed_during_stream := first_body != null and not first_body.visible
	_record_chat_work_update(" Naujesnis stream atnaujinimas lieka dabartinėje grupėje.", "replay-work-4")
	var current_unchanged := current_body != null and not current_body.visible
	first_toggle.pressed.emit()

	var diff_text := "\n".join([
		"diff --git a/scripts/player.gd b/scripts/player.gd",
		"--- a/scripts/player.gd",
		"+++ b/scripts/player.gd",
		"@@",
		"-var stair_snap = 0.0",
		"+var stair_snap = 0.18",
		"diff --git a/materials/city_wall.tres b/materials/city_wall.tres",
		"--- a/materials/city_wall.tres",
		"+++ b/materials/city_wall.tres",
		"@@",
		"-roughness = 0.2",
		"+roughness = 0.55",
	])
	_record_chat_diff_update(diff_text)
	_set_chat_diff_files_visible(true)
	var files_box := _chat_active_diff_controls.get("files_box", null) as VBoxContainer
	var first_file: VBoxContainer = null
	if files_box != null and files_box.get_child_count() > 0:
		first_file = files_box.get_child(0) as VBoxContainer
	var first_file_toggle: Button = null
	if first_file != null:
		first_file_toggle = first_file.get_child(0) as Button
	if first_file_toggle != null:
		first_file_toggle.pressed.emit()
	_record_chat_diff_update(diff_text + "\n+velocity.y = lerp(velocity.y, target_y, delta * 12.0)")
	var rerendered_first_file: VBoxContainer = null
	if files_box != null and files_box.get_child_count() > 0:
		rerendered_first_file = files_box.get_child(0) as VBoxContainer
	var rerendered_details: PanelContainer = null
	if rerendered_first_file != null:
		rerendered_details = rerendered_first_file.get_child(1) as PanelContainer

	_append_chat_assistant_delta(
		"**Replay rezultatas**\n\n- Senos grupės valdomos nepriklausomai.\n- Lietuviškas tekstas išlieka skaitomas.\n\n`res://world/city/materials/very_long_filename_that_must_wrap.tres`\n\n```gdscript\nfunc smooth_step(delta: float) -> void:\n    velocity.y = lerp(velocity.y, target_y, delta * 12.0)\n```",
		"replay-answer-1",
		"final_answer"
	)
	_flush_chat_assistant_text()
	_chat_follow_latest = false
	_update_jump_latest_button()
	call_deferred("_position_chat_history_for_evidence")
	return _ok({
		"evidence_kind": "local_mock_replay",
		"first_expanded": first_expanded,
		"second_collapsed": second_collapsed,
		"first_unchanged_after_second": first_unchanged_after_second,
		"first_collapsed_during_newer_stream": first_collapsed_during_stream,
		"current_group_unchanged": current_unchanged,
		"first_expanded_final": first_body != null and first_body.visible,
		"diff_file_expansion_survived_stream": rerendered_details != null and rerendered_details.visible,
		"work_batch_count": int(_chat_message_control_counts().get("work_batch_count", 0)),
		"jump_latest_visible": _chat_jump_latest_button != null and _chat_jump_latest_button.visible,
	})


func _position_chat_history_for_evidence() -> void:
	if _chat_log_view == null:
		return
	var scroll_bar := _chat_log_view.get_v_scroll_bar()
	if scroll_bar != null:
		scroll_bar.value = max(scroll_bar.max_value * 0.35, 0.0)


func _validate_codex_chat_input_enter_send_request(payload: Dictionary) -> Dictionary:
	if _chat_input == null:
		return _err("chat_input_unavailable", "Codex Chat input is not initialized.")
	if not _permission_enabled("allow_codex_chat"):
		return _err("permission_disabled", "Codex Chat permission is disabled.")
	if not _chat_socket_ready():
		return _err("chat_unavailable", "Codex Chat socket is not ready.")
	var message := str(payload.get("message", "Enter-to-send validation"))
	if message.strip_edges() == "":
		message = "Enter-to-send validation"
	var previous_text := _chat_input.text
	var previous_caret_line := _chat_input.get_caret_line()
	var previous_caret_column := _chat_input.get_caret_column()
	var previous_expanded := _chat_composer_expanded
	var previous_context := _chat_attach_context.button_pressed if _chat_attach_context != null else false
	var previous_selected := _chat_attach_selected.button_pressed if _chat_attach_selected != null else false
	var previous_screenshot := _chat_attach_screenshot.button_pressed if _chat_attach_screenshot != null else false
	if _chat_attach_context != null:
		_chat_attach_context.button_pressed = bool(payload.get("attach_context", false))
	if _chat_attach_selected != null:
		_chat_attach_selected.button_pressed = bool(payload.get("attach_selected", false))
	if _chat_attach_screenshot != null:
		_chat_attach_screenshot.button_pressed = bool(payload.get("attach_screenshot", false))
	var request_id_before := _chat_request_id
	_chat_input.text = message
	_refresh_chat_composer_height(true)
	_chat_input.set_caret_line(0)
	_chat_input.set_caret_column(_chat_input.text.length())
	var enter_event := InputEventKey.new()
	enter_event.keycode = KEY_ENTER
	enter_event.physical_keycode = KEY_ENTER
	enter_event.pressed = true
	enter_event.shift_pressed = false
	var handled_event := _dispatch_chat_input_key_event(enter_event)
	var request_id_after := _chat_request_id
	var input_after := _chat_input.text
	var sent := handled_event and request_id_after > request_id_before and input_after == ""
	if not sent:
		_chat_input.text = previous_text
		_chat_composer_expanded = previous_expanded
		_refresh_chat_composer_height()
		_chat_input.set_caret_line(min(previous_caret_line, max(_chat_input.get_line_count() - 1, 0)))
		_chat_input.set_caret_column(previous_caret_column)
	if _chat_attach_context != null:
		_chat_attach_context.button_pressed = previous_context
	if _chat_attach_selected != null:
		_chat_attach_selected.button_pressed = previous_selected
	if _chat_attach_screenshot != null:
		_chat_attach_screenshot.button_pressed = previous_screenshot
	return _ok({
		"handled_event": handled_event,
		"sent": sent,
		"message_length": message.length(),
		"request_id_before": request_id_before,
		"request_id_after": request_id_after,
		"input_cleared": input_after == "",
		"input_after": input_after,
		"composer_expanded": _chat_composer_expanded,
		"input_minimum_size": _variant_to_json_value(_chat_input.custom_minimum_size),
		"input_row_minimum_size": _variant_to_json_value(_chat_input_row.custom_minimum_size) if _chat_input_row != null else _variant_to_json_value(Vector2()),
	})


func _validate_codex_chat_input_long_prompt_request(payload: Dictionary) -> Dictionary:
	if _chat_input == null:
		return _err("chat_input_unavailable", "Codex Chat input is not initialized.")
	var previous_text := _chat_input.text
	var previous_caret_line := _chat_input.get_caret_line()
	var previous_caret_column := _chat_input.get_caret_column()
	var previous_expanded := _chat_composer_expanded
	var requested_text := str(payload.get("text", ""))
	if requested_text.strip_edges() == "":
		requested_text = "Long Codex prompt validation ".repeat(8)
	_chat_input.text = requested_text
	_refresh_chat_composer_height(true)
	var auto_minimum_size := _chat_input.custom_minimum_size
	var auto_row_minimum_size := _chat_input_row.custom_minimum_size if _chat_input_row != null else Vector2()
	var longest_line := ChatInputModel.longest_line_length(_chat_input.text)
	var line_count := _chat_input.get_line_count()
	var expanded_after_text := _chat_composer_expanded
	var input_width := _chat_input.get_rect().size.x
	if input_width <= 0.0:
		input_width = _chat_input.custom_minimum_size.x
	var expected_height := ChatInputModel.composer_height_for_text_width(
		_chat_input.text,
		_chat_composer_expanded,
		ChatPanelView.INPUT_MIN_HEIGHT,
		ChatPanelView.INPUT_AUTO_HEIGHT,
		ChatPanelView.INPUT_EXPANDED_HEIGHT,
		input_width
	)
	_chat_input.text = previous_text
	_chat_composer_expanded = previous_expanded
	_refresh_chat_composer_height()
	_chat_input.set_caret_line(min(previous_caret_line, max(_chat_input.get_line_count() - 1, 0)))
	_chat_input.set_caret_column(previous_caret_column)
	return _ok({
		"input_text_length": requested_text.length(),
		"line_count": line_count,
		"longest_line": longest_line,
		"expected_height": expected_height,
		"input_width": input_width,
		"auto_input_minimum_size": _variant_to_json_value(auto_minimum_size),
		"auto_input_row_minimum_size": _variant_to_json_value(auto_row_minimum_size),
		"input_minimum_size": _variant_to_json_value(_chat_input.custom_minimum_size),
		"input_row_minimum_size": _variant_to_json_value(_chat_input_row.custom_minimum_size) if _chat_input_row != null else _variant_to_json_value(Vector2()),
		"input_scroll_fit_content_height": _chat_input.scroll_fit_content_height,
		"expanded_after_text": expanded_after_text,
		"composer_expanded": _chat_composer_expanded,
	})


func _validate_eye_attach_flow_request() -> Dictionary:
	if not _permission_enabled("allow_ai_markers"):
		return _err("permission_disabled", "Eye Attach permission is disabled.")
	if not _permission_enabled("allow_screenshots"):
		return _err("permission_denied", "Screenshot permission is disabled in the Codex Bridge dock.")
	if _annotation_controller == null:
		return _err("annotation_controller_unavailable", "Eye Attach controller is not initialized.")

	_annotation_controller.clear_pending(false)
	if _annotation_controller.dialog != null:
		_annotation_controller.dialog.hide()
	_annotation_controller.open_eye_attach_dialog()

	var capture: Dictionary = _annotation_controller.source
	var image: Image = capture.get("image") as Image
	var capture_succeeded := bool(capture.get("ok", false)) and image != null and not image.is_empty()
	if not capture_succeeded or _annotation_controller.canvas == null or _annotation_controller.dialog == null:
		if _annotation_controller.dialog != null:
			_annotation_controller.dialog.hide()
		_annotation_controller.clear_pending(false)
		return _err("annotation_capture_failed", "Eye Attach validation could not capture the editor image.")

	var image_width := image.get_width()
	var image_height := image.get_height()
	var first_point := Vector2(maxf(2.0, float(image_width) * 0.10), maxf(2.0, float(image_height) * 0.10))
	var second_point := Vector2(maxf(first_point.x + 4.0, float(image_width) * 0.25), maxf(first_point.y + 4.0, float(image_height) * 0.25))
	var validation_marker := {
		"id": "A",
		"type": "rectangle",
		"label": "A",
		"color": "#ff00ff",
		"points": [
			{"x": first_point.x, "y": first_point.y},
			{"x": second_point.x, "y": second_point.y},
		],
	}
	var dialog_visible_after_open := _annotation_controller.dialog.visible
	var canvas_has_image_after_open := _annotation_controller.canvas.source_image != null
	_annotation_controller.canvas.markers.append(validation_marker.duplicate(true))
	_annotation_controller.canvas.queue_redraw()
	_annotation_controller.update_status()
	var marker_count_before_cancel := _annotation_controller.canvas.marker_count()
	_annotation_controller.dialog.hide()
	var cancel_left_no_pending := not _annotation_controller.has_pending()
	var dialog_hidden_after_cancel := not _annotation_controller.dialog.visible

	_annotation_controller.open_eye_attach_dialog()
	if _annotation_controller.canvas == null or _annotation_controller.canvas.source_image == null:
		if _annotation_controller.dialog != null:
			_annotation_controller.dialog.hide()
		_annotation_controller.clear_pending(false)
		return _err("annotation_recapture_failed", "Eye Attach validation could not recapture the editor image.")
	_annotation_controller.canvas.markers.append(validation_marker.duplicate(true))
	_annotation_controller.canvas.queue_redraw()
	_annotation_controller.update_status()
	var marker_count_before_attach := _annotation_controller.canvas.marker_count()
	_annotation_controller.attach_current_annotation()

	var pending: Dictionary = _annotation_controller.pending()
	var manifest_path := str(pending.get("manifest_path", ""))
	var annotated_path := str(pending.get("annotated_path", ""))
	var raw_path := manifest_path.get_base_dir().path_join("raw.png") if manifest_path != "" else ""
	var manifest_read := _read_json_file(manifest_path) if manifest_path != "" else {"ok": false}
	var manifest: Dictionary = manifest_read.get("data", {}) if bool(manifest_read.get("ok", false)) else {}
	var privacy: Dictionary = manifest.get("privacy", {}) if typeof(manifest.get("privacy", {})) == TYPE_DICTIONARY else {}
	var manifest_has_guardrails := (
		str(manifest.get("annotation_version", "")) == AnnotationArtifactModel.ANNOTATION_VERSION
		and str(manifest.get("annotation_role", "")) == AnnotationArtifactModel.ANNOTATION_ROLE
		and bool(manifest.get("non_game_overlay", false))
		and bool(manifest.get("do_not_recreate_marker_graphics", false))
		and str(manifest.get("instruction", "")) == AnnotationArtifactModel.NON_GAME_INSTRUCTION
		and not bool(privacy.get("external_upload_allowed", true))
	)
	var pending_after_attach := _annotation_controller.has_pending()
	var pending_label_visible := _annotation_controller.pending_label != null and _annotation_controller.pending_label.visible
	var clear_button_visible := _annotation_controller.clear_button != null and _annotation_controller.clear_button.visible

	_annotation_controller.clear_pending(false)
	if _annotation_controller.dialog != null:
		_annotation_controller.dialog.hide()

	return _ok({
		"capture_succeeded": capture_succeeded,
		"capture_scope": str(capture.get("capture_scope", "")),
		"capture_source": str(capture.get("source", "")),
		"capture_looked_blank": AnnotationArtifactModel.image_looks_blank(image),
		"image_width": image_width,
		"image_height": image_height,
		"dialog_visible_after_open": dialog_visible_after_open,
		"canvas_has_image_after_open": canvas_has_image_after_open,
		"marker_created_for_cancel": marker_count_before_cancel > 0,
		"marker_count_before_cancel": marker_count_before_cancel,
		"cancel_left_no_pending": cancel_left_no_pending,
		"dialog_hidden_after_cancel": dialog_hidden_after_cancel,
		"marker_created_for_attach": marker_count_before_attach > 0,
		"marker_count_before_attach": marker_count_before_attach,
		"pending_after_attach": pending_after_attach,
		"pending_annotation_id": str(pending.get("annotation_id", "")),
		"pending_marker_count": int(pending.get("marker_count", 0)),
		"pending_label_visible": pending_label_visible,
		"clear_button_visible": clear_button_visible,
		"raw_exists": raw_path != "" and FileAccess.file_exists(raw_path),
		"annotated_exists": annotated_path != "" and FileAccess.file_exists(annotated_path),
		"manifest_exists": manifest_path != "" and FileAccess.file_exists(manifest_path),
		"manifest_has_guardrails": manifest_has_guardrails,
		"clear_removed_pending": not _annotation_controller.has_pending(),
		"pending_label_hidden_after_clear": _annotation_controller.pending_label == null or not _annotation_controller.pending_label.visible,
		"clear_button_hidden_after_clear": _annotation_controller.clear_button == null or not _annotation_controller.clear_button.visible,
	})


func _validate_codex_chat_diff_overflow_request(payload: Dictionary) -> Dictionary:
	if _chat_transcript_view == null or _chat_log_view == null or _chat_input == null:
		return _err("chat_ui_unavailable", "Codex Chat transcript controls are not initialized.")
	var requested_file_count := clampi(int(payload.get("file_count", 32)), 1, 64)
	var lines_per_file := clampi(int(payload.get("lines_per_file", 3)), 1, 64)
	var update_count := clampi(int(payload.get("updates", 4)), 1, 16)
	var fixture := ChatDiffModel.many_file_overflow_fixture(requested_file_count, lines_per_file)
	var previous_root := _chat_active_diff_controls.get("root_panel", null) as Control
	if previous_root != null and is_instance_valid(previous_root):
		var previous_parent := previous_root.get_parent()
		if previous_parent != null:
			previous_parent.remove_child(previous_root)
		previous_root.queue_free()
	_reset_chat_diff_batch()
	for _update_index in range(update_count):
		_record_chat_diff_update(fixture)
	_set_chat_diff_files_visible(true)
	var layout_result := _get_codex_chat_layout_status_request()
	if not bool(layout_result.get("ok", false)):
		return layout_result
	var layout: Dictionary = layout_result.get("data", {})
	var counts := _chat_message_control_counts()
	return _ok({
		"diff_overflow_requested_file_count": requested_file_count,
		"diff_overflow_generated_file_count": ChatDiffModel.extract_diff_files(fixture).size(),
		"diff_overflow_ui_file_limit": CHAT_DIFF_MAX_FILES,
		"diff_overflow_fixture_chars": fixture.length(),
		"chat_message_count": _chat_message_count(),
		"chat_diff_preview_count": int(counts.get("diff_preview_count", 0)),
		"chat_diff_file_section_count": int(counts.get("diff_file_section_count", 0)),
		"chat_diff_files_box_visible_count": int(counts.get("diff_files_box_visible_count", 0)),
		"active_diff_file_count": _chat_active_diff_file_count,
		"active_diff_added_count": _chat_active_diff_added_count,
		"active_diff_removed_count": _chat_active_diff_removed_count,
		"active_diff_files_visible": _chat_active_diff_files_visible,
		"input_visible_in_tree": bool(layout.get("input_visible_in_tree", false)),
		"input_inside_chat_panel": bool(layout.get("input_inside_chat_panel", false)),
		"log_inside_chat_panel": bool(layout.get("log_inside_chat_panel", false)),
		"composer_below_log": bool(layout.get("composer_below_log", false)),
		"approval_above_input": bool(layout.get("approval_above_input", false)),
		"input_rect": layout.get("input_rect", {}),
		"log_frame_rect": layout.get("log_frame_rect", {}),
		"log_rect": layout.get("log_rect", {}),
	})


func _prepare_codex_chat_diff_visual_evidence_request() -> Dictionary:
	if _chat_transcript_view == null or _chat_log_view == null:
		return _err("chat_ui_unavailable", "Codex Chat transcript controls are not initialized.")
	var files_box := _chat_active_diff_controls.get("files_box", null) as Control
	if not _chat_active_diff_files_visible or files_box == null or not files_box.visible:
		_set_chat_diff_files_visible(true)
	_focus_codex_chat_panel()
	var target := _active_chat_diff_visual_target()
	var scroll_before := _chat_log_view.scroll_vertical
	var target_content_y := _chat_control_content_y_in_scroll(target, _chat_log_view)
	if target != null and target_content_y >= 0.0:
		var scroll_bar := _chat_log_view.get_v_scroll_bar()
		var max_scroll := int(scroll_bar.max_value) if scroll_bar != null else 0
		_chat_log_view.scroll_vertical = clampi(int(floor(target_content_y - 16.0)), 0, max_scroll)
		_chat_log_view.queue_redraw()
		call_deferred("_stabilize_active_chat_diff_visual_scroll")
	var status := _active_chat_diff_visual_evidence_status()
	status["scroll_vertical_before"] = scroll_before
	status["scroll_vertical_after"] = _chat_log_view.scroll_vertical
	status["scroll_vertical_max"] = int(_chat_log_view.get_v_scroll_bar().max_value) if _chat_log_view.get_v_scroll_bar() != null else 0
	status["target_content_y"] = target_content_y
	return _ok(status)


func _stabilize_active_chat_diff_visual_scroll() -> void:
	if _chat_log_view == null:
		return
	var target := _active_chat_diff_visual_target()
	var target_content_y := _chat_control_content_y_in_scroll(target, _chat_log_view)
	if target == null or target_content_y < 0.0:
		return
	var scroll_bar := _chat_log_view.get_v_scroll_bar()
	var max_scroll := int(scroll_bar.max_value) if scroll_bar != null else 0
	_chat_log_view.scroll_vertical = clampi(int(floor(target_content_y - 16.0)), 0, max_scroll)
	_chat_log_view.queue_redraw()


func _capture_codex_chat_visual_evidence_request(payload: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_screenshots"):
		return _err("permission_denied", "Screenshot permission is disabled in the Codex Bridge dock.")
	if _annotation_controller == null or _chat_transcript_view == null or _chat_log_view == null or _chat_dock == null:
		return _err("chat_ui_unavailable", "Codex Chat visual evidence controls are not initialized.")
	var semantic_target := _active_chat_diff_visual_evidence_status(_chat_dock)
	if bool(payload.get("require_active_diff", false)) and not bool(semantic_target.get("target_available", false)):
		return _err("chat_diff_target_unavailable", "The active diff visual target is unavailable.")
	var capture := _annotation_controller._capture_editor_root_viewport_image()
	if not bool(capture.get("ok", false)):
		return {"ok": false, "error": capture.get("error", _error_payload("chat_visual_capture_failed", "Editor capture failed."))}
	var image: Image = capture.get("image") as Image
	if image == null or image.is_empty():
		return _err("chat_visual_capture_failed", "Editor capture returned an empty image.")
	_ensure_bridge_dirs()
	var reason := str(payload.get("reason", "codex_chat_visual_evidence")).strip_edges()
	var file_name := "codex_chat_" + _safe_identifier(reason) + "_" + _file_timestamp() + ".png"
	var absolute_path := _screenshots_dir_abs.path_join(file_name)
	var path_guard := _validate_bridge_path(absolute_path, true)
	if not bool(path_guard.get("ok", false)):
		return {"ok": false, "error": path_guard.get("error", _error_payload("chat_visual_path_rejected", "Visual evidence path is unsafe."))}
	if not _permission_enabled("allow_screenshots"):
		return _err("permission_denied", "Screenshot permission was revoked before the visual evidence artifact was written.")
	var save_error := image.save_png(absolute_path)
	if save_error != OK:
		return _err("chat_visual_save_failed", "Failed to save Codex Chat visual evidence: " + error_string(save_error))
	return _ok({
		"artifact": {
			"absolute_path": absolute_path,
			"width": image.get_width(),
			"height": image.get_height(),
			"looks_blank": AnnotationArtifactModel.image_looks_blank(image),
			"source": str(capture.get("source", "editor_root_viewport")),
			"target_window_verified": bool(capture.get("target_window_verified", false)),
			"occlusion_sensitive": bool(capture.get("occlusion_sensitive", true)),
			"exclusive_modal_visible": false,
			"capture_warning": "",
			"semantic_target": semantic_target,
		},
	})


func _active_chat_diff_visual_target() -> Control:
	var files_box := _chat_active_diff_controls.get("files_box", null) as VBoxContainer
	if files_box == null or not is_instance_valid(files_box):
		return null
	for child in files_box.get_children():
		if child is Control and (child as Control).visible:
			return child as Control
	return null


func _active_chat_diff_visual_evidence_status(capture_root: Control = null) -> Dictionary:
	var files_box := _chat_active_diff_controls.get("files_box", null) as Control
	var target := _active_chat_diff_visual_target()
	var log_rect := _chat_log_view.get_global_rect() if _chat_log_view != null else Rect2()
	var root_rect := capture_root.get_global_rect() if capture_root != null else Rect2()
	var target_rect := target.get_global_rect() if target != null else Rect2()
	var log_intersection := log_rect.intersection(target_rect)
	var root_intersection := root_rect.intersection(target_rect)
	return {
		"target": "active_diff_first_file",
		"target_available": target != null,
		"target_visible_in_tree": target != null and target.is_visible_in_tree(),
		"files_box_visible_in_tree": files_box != null and files_box.is_visible_in_tree(),
		"target_intersects_log_view": target != null and log_intersection.size.x > 0.0 and log_intersection.size.y > 0.0,
		"target_intersects_capture_root": target != null and capture_root != null and root_intersection.size.x > 0.0 and root_intersection.size.y > 0.0,
		"target_rect": target_rect,
		"log_view_rect": log_rect,
		"capture_root_rect": root_rect,
		"log_intersection_rect": log_intersection,
		"capture_root_intersection_rect": root_intersection,
	}


func _chat_control_content_y_in_scroll(target: Control, scroll_view: ScrollContainer) -> float:
	if target == null or scroll_view == null:
		return -1.0
	var content_y := 0.0
	var current: Control = target
	while current != null and current.get_parent() != scroll_view:
		content_y += current.position.y
		current = current.get_parent() as Control
	return content_y if current != null else -1.0


func _activate_codex_chat_primary_action_request() -> Dictionary:
	if _chat_connect_button == null:
		return _err("chat_ui_unavailable", "Codex Chat primary action is not initialized.")
	var status_header := _chat_status_label.get_parent() if _chat_status_label != null else null
	var request_id_before := _chat_request_id
	var visible_before := _chat_connect_button.is_visible_in_tree()
	var advanced_visible_before := _chat_advanced_panel != null and _chat_advanced_panel.visible
	var action_text_before := _chat_connect_button.text
	var handler_count_before := 0
	_chat_connect_button.pressed.emit()
	var attach_request_id_after := -1
	var attach_request_method := ""
	for candidate_id in _chat_request_methods.keys():
		var numeric_id := int(candidate_id)
		var method := str(_chat_request_methods.get(candidate_id, ""))
		if numeric_id > request_id_before and method in ["project.attach", "host.restart_for_project"]:
			attach_request_id_after = numeric_id
			attach_request_method = method
			break
	var signal_handled := attach_request_id_after > request_id_before
	return _ok({
		"signal_emitted": true,
		"signal_handled": signal_handled,
		"handler_count_before": handler_count_before,
		"handler_count_after": handler_count_before + (1 if signal_handled else 0),
		"handler_count_delta": 1 if signal_handled else 0,
		"attach_request_id_before": request_id_before,
		"attach_request_id_after": attach_request_id_after,
		"attach_request_sent": signal_handled,
		"attach_request_method": attach_request_method,
		"visible_before": visible_before,
		"in_status_header": status_header != null and _chat_connect_button.get_parent() == status_header,
		"focus_mode": _chat_connect_button.focus_mode,
		"advanced_visible_before": advanced_visible_before,
		"action_text_before": action_text_before,
	})


func _rect_contains(container_rect: Rect2, child_rect: Rect2) -> bool:
	return (
		child_rect.position.x >= container_rect.position.x
		and child_rect.position.y >= container_rect.position.y
		and child_rect.position.x + child_rect.size.x <= container_rect.position.x + container_rect.size.x
		and child_rect.position.y + child_rect.size.y <= container_rect.position.y + container_rect.size.y
	)


func _rect_payload(rect: Rect2) -> Dictionary:
	return {
		"x": rect.position.x,
		"y": rect.position.y,
		"width": rect.size.x,
		"height": rect.size.y,
	}


func _window_rect_payload(window: Window) -> Dictionary:
	if window == null:
		return _rect_payload(Rect2())
	return {
		"x": window.position.x,
		"y": window.position.y,
		"width": window.size.x,
		"height": window.size.y,
	}


func _codex_chat_request(request_type: String, payload: Dictionary = {}) -> Dictionary:
	var result_plan := ChatRequestModel.request_dispatch_effect_result_plan(
		request_type,
		_chat_request_context(),
		payload,
		_chat_request_state()
	)
	_apply_chat_request_effects(result_plan.get("effects", []) as Array)
	return result_plan.get("result", {}) as Dictionary


func _chat_request_context() -> Dictionary:
	return ChatRequestModel.request_context({
		"chat_permission_enabled": _permission_enabled("allow_codex_chat"),
		"background_permission_enabled": _permission_enabled("allow_background_team_review"),
		"socket_ready": _chat_socket_ready(),
		"has_active_approval": not _active_chat_approval.is_empty(),
		"active_project_root": _chat_active_project_root,
	})


func _chat_socket_ready() -> bool:
	return _host_paired and _chat_socket != null and _chat_socket.get_ready_state() == WebSocketPeer.STATE_OPEN


func _set_chat_attachment_flags(value: Variant) -> void:
	var updates := ChatActionModel.attachment_flag_updates(
		value,
		_chat_attach_context != null and _chat_attach_context.button_pressed,
		_chat_attach_selected != null and _chat_attach_selected.button_pressed,
		_chat_attach_screenshot != null and _chat_attach_screenshot.button_pressed
	)
	if _chat_attach_context != null and updates.has("context_snapshot"):
		_chat_attach_context.button_pressed = bool(updates.get("context_snapshot", _chat_attach_context.button_pressed))
	if _chat_attach_selected != null and updates.has("selected_nodes"):
		_chat_attach_selected.button_pressed = bool(updates.get("selected_nodes", _chat_attach_selected.button_pressed))
	if _chat_attach_screenshot != null and updates.has("latest_screenshot"):
		_chat_attach_screenshot.button_pressed = bool(updates.get("latest_screenshot", _chat_attach_screenshot.button_pressed))


func _set_chat_runtime_options_from_payload(payload: Dictionary) -> void:
	var runtime_options := ChatActionModel.runtime_options_from_payload(payload)
	var selection_plan := ChatRuntimeOptionsModel.runtime_selection_effect_plan(
		runtime_options,
		_option_metadata_items(_chat_model_option),
		_option_metadata_items(_chat_reasoning_option)
	)
	_apply_runtime_model_options_effects(selection_plan.get("effects", []) as Array)


func _apply_chat_request_effects(effects: Array) -> void:
	for effect_dict: Dictionary in ChatRequestModel.request_application_effects(effects):
		match str(effect_dict.get("action", "")):
			"connect_host":
				_connect_chat_host()
			"enable_tools":
				_enable_bridge_tools()
			"set_attachment_flags":
				_set_chat_attachment_flags(effect_dict.get("value", {}))
			"set_runtime_options":
				var options := effect_dict.get("value", {}) as Dictionary
				_set_chat_runtime_options_from_payload(options)
			"set_chat_input":
				if _chat_input != null:
					_chat_input.text = str(effect_dict.get("text", ""))
					if bool(effect_dict.get("refresh_composer", false)):
						_refresh_chat_composer_height()
			"send_chat_message":
				_send_chat_message()
			"run_team_review":
				_run_team_review()
			"cancel_team_review":
				_cancel_team_review()
func _chat_request_state() -> Dictionary:
	return ChatRequestModel.request_state({
		"chat_request_id": _chat_request_id,
		"connection_state": _chat_connection_state,
		"runtime_state": _chat_runtime_state,
		"thread_id": _chat_thread_id,
		"turn_id": _chat_turn_id,
		"background_task_id": _active_background_task_id,
		"background_state": _active_background_state,
		"host_config_loaded": not _host_config.is_empty(),
		"host_url": _codex_host_url,
		"host_start_in_progress": _host_start_in_progress,
		"host_process_id": _host_start_process_id,
		"trust_mode": _chat_trust_mode,
		"active_project_root": _chat_active_project_root,
	})


func _sanitize_node_name(value: String, fallback: String) -> String:
	var name := value.strip_edges()
	if name == "":
		name = fallback.strip_edges()
	if name.length() > 96:
		name = name.substr(0, 96)
	return name


func _is_valid_node_name(value: String) -> bool:
	return value != "" and value.find("/") < 0 and value.find("\\") < 0 and value.find("\n") < 0 and value.find("\r") < 0


func _sanitize_identifier_name(value: String, kind: String) -> String:
	return EditorSignals.sanitize_identifier_name(value, kind)
func _bounded_child_index(parent: Node, requested_index: int) -> int:
	if parent == null:
		return 0
	var child_count := parent.get_child_count()
	if requested_index < 0:
		return child_count
	return clampi(requested_index, 0, child_count)


func _select_single_node(node: Node) -> void:
	if node == null:
		return
	var selection := EditorInterface.get_selection()
	if selection != null:
		selection.clear()
		selection.add_node(node)
	EditorInterface.edit_node(node)


func _set_owner_recursive(node: Node, owner: Node) -> void:
	if node == null:
		return
	node.owner = owner
	for child in node.get_children():
		if child is Node:
			_set_owner_recursive(child, owner)


func _prepare_initial_transform_changes(node: Node, params: Dictionary) -> Dictionary:
	var has_transform := _payload_has_any(params, ["position", "rotation_degrees", "rotationDegrees", "scale"])
	if not has_transform:
		return {"ok": true, "changes": []}
	if not (node is Node2D) and not (node is Node3D):
		return _err("unsupported_node_type", "Initial transform is supported only for Node2D and Node3D placements.")

	var changes: Array = []
	var parse_result: Dictionary
	if _payload_has_any(params, ["position"]):
		parse_result = _coerce_transform_value(node.get("position"), params.get("position"), "position", "absolute")
		if not parse_result.get("ok", false):
			return parse_result
		changes.append({"property": "position", "old_value": node.get("position"), "new_value": parse_result.get("value")})
	if _payload_has_any(params, ["rotation_degrees", "rotationDegrees"]):
		parse_result = _coerce_transform_value(node.get("rotation_degrees"), _payload_get_any(params, ["rotation_degrees", "rotationDegrees"]), "rotation_degrees", "absolute")
		if not parse_result.get("ok", false):
			return parse_result
		changes.append({"property": "rotation_degrees", "old_value": node.get("rotation_degrees"), "new_value": parse_result.get("value")})
	if _payload_has_any(params, ["scale"]):
		parse_result = _coerce_transform_value(node.get("scale"), params.get("scale"), "scale", "absolute")
		if not parse_result.get("ok", false):
			return parse_result
		changes.append({"property": "scale", "old_value": node.get("scale"), "new_value": parse_result.get("value")})
	return {"ok": true, "changes": changes}


func _signal_args_payload(args_value: Variant) -> Array:
	return EditorSignals.signal_args_payload(args_value)
func _signal_connections_payload(node: Node, signal_name: String, scene_root: Node) -> Array:
	return EditorSignals.signal_connections_payload(node, signal_name, scene_root)
func _callable_payload(callable: Variant, scene_root: Node) -> Dictionary:
	return EditorSignals.callable_payload(callable, scene_root)
func _signal_connection_ref_payload(source: Node, signal_name: String, target: Node, method_name: String, scene_root: Node) -> Dictionary:
	return EditorSignals.signal_connection_ref_payload(source, signal_name, target, method_name, scene_root)
func _find_signal_connection_flags(source: Node, signal_name: String, callable: Callable) -> int:
	return EditorSignals.find_signal_connection_flags(source, signal_name, callable)
func _deep_node_payload(node: Node, scene_root: Node, depth_remaining: int, include_properties: bool, state: Dictionary) -> Dictionary:
	state["count"] = int(state.get("count", 0)) + 1
	var payload := _basic_node_payload(node, scene_root)
	payload["child_count"] = node.get_child_count()
	if include_properties:
		payload["properties"] = _bounded_property_summary(node)
	payload["children"] = []
	if depth_remaining <= 0:
		if node.get_child_count() > 0:
			payload["children_truncated"] = true
			state["truncated"] = true
		return payload

	var max_nodes := int(state.get("max_nodes", MAX_SCENE_NODES))
	for child in node.get_children():
		if int(state.get("count", 0)) >= max_nodes:
			state["truncated"] = true
			payload["children_truncated"] = true
			break
		if child is Node:
			payload["children"].append(_deep_node_payload(child, scene_root, depth_remaining - 1, include_properties, state))
	return payload


func _path_extension(path_value: String) -> String:
	var file_name := path_value.get_file()
	var dot_index := file_name.rfind(".")
	if dot_index < 0:
		return ""
	return file_name.substr(dot_index).to_lower()


func _res_path_join(base_path: String, file_name: String) -> String:
	if base_path.ends_with("/"):
		return base_path + file_name
	return base_path + "/" + file_name


func _resolve_animation_player(node_path: String) -> Dictionary:
	if _editor_animation == null:
		return _err("editor_animation_unavailable", "Editor animation service is not initialized.")
	return _editor_animation.resolve_animation_player(node_path)
func _ok(data: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"data": data,
	}


func _err(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"error": _error_payload(code, message),
	}


func _record_editor_action(action: String, status: String, data: Dictionary) -> void:
	var entry := {
		"at": _iso_now(),
		"action": action,
		"status": status,
		"summary": _editor_action_summary(data),
	}
	_recent_editor_actions.append(entry)
	while _recent_editor_actions.size() > MAX_RECENT_EDITOR_ACTIONS:
		_recent_editor_actions.pop_front()


func _editor_action_summary(data: Dictionary) -> Dictionary:
	var summary := {}
	if data.has("error"):
		summary["error"] = data.get("error")
	if data.has("node"):
		summary["node"] = data.get("node")
	if data.has("selected_node"):
		summary["selected_node"] = (data.get("selected_node") as Dictionary).get("node", data.get("selected_node")) if typeof(data.get("selected_node")) == TYPE_DICTIONARY else data.get("selected_node")
	if data.has("opened_scene"):
		summary["opened_scene"] = data.get("opened_scene")
	if data.has("opened_script"):
		summary["opened_script"] = data.get("opened_script")
	if data.has("main_screen"):
		summary["main_screen"] = data.get("main_screen")
	if data.has("changes"):
		var changes: Array = data.get("changes", [])
		var properties: Array = []
		for change in changes:
			if typeof(change) == TYPE_DICTIONARY:
				properties.append(str((change as Dictionary).get("property", "")))
		summary["changed_properties"] = properties
	if data.has("latency_ms"):
		summary["latency_ms"] = data.get("latency_ms")
	if data.has("snapshot_refreshed"):
		summary["snapshot_refreshed"] = data.get("snapshot_refreshed")
	return summary


func _validate_main_screen_name(main_screen: String) -> Dictionary:
	if main_screen in ["2D", "3D", "Script", "Game", "AssetLib", "Codex Bridge"]:
		return {}
	return _error_payload("invalid_main_screen", "main_screen must be 2D, 3D, Script, Game, AssetLib or Codex Bridge.")


func _validate_res_path(res_path: String, allowed_extensions: Array, kind: String, must_exist: bool) -> Dictionary:
	return EditorPathGuard.validate_res_path(res_path, allowed_extensions, kind, must_exist)


func _resolve_editor_node(node_path: String) -> Dictionary:
	var scene_root := EditorInterface.get_edited_scene_root()
	if scene_root == null:
		return _err("no_current_scene", "No edited scene is open.")
	if node_path == "" or node_path == ".":
		return {
			"ok": true,
			"node": scene_root,
			"scene_root": scene_root,
		}
	var path_error := EditorPathGuard.validate_scene_local_node_path(node_path)
	if not path_error.is_empty():
		return _err(str(path_error.get("code", "invalid_node_path")), str(path_error.get("message", "")))

	var node: Node = null
	if node_path.begins_with("/"):
		node = get_tree().root.get_node_or_null(NodePath(node_path))
	else:
		node = scene_root.get_node_or_null(NodePath(node_path))
	if node == null:
		return _err("node_not_found", "Node not found in the edited scene: " + node_path)
	if node != scene_root and not scene_root.is_ancestor_of(node):
		return _err("node_outside_scene", "Resolved node is outside the edited scene.")
	return {
		"ok": true,
		"node": node,
		"scene_root": scene_root,
	}


func _node_inspector_payload(node: Node, scene_root: Node) -> Dictionary:
	return {
		"node": _node_ref_payload(node, scene_root),
		"script_path": _resource_path_or_null(node.get_script()),
		"scene_file_path": _null_if_empty(node.scene_file_path),
		"properties": _bounded_property_summary(node),
	}


func _notes_get_request() -> Dictionary:
	if _editor_diagnostics == null:
		return _err("editor_diagnostics_unavailable", "Editor diagnostics service is not initialized.")
	return _editor_diagnostics.notes_get({})


func _notes_append_request(params: Dictionary) -> Dictionary:
	if _editor_diagnostics == null:
		return _err("editor_diagnostics_unavailable", "Editor diagnostics service is not initialized.")
	return _editor_diagnostics.notes_append(params)


func _notes_clear_request() -> Dictionary:
	if _editor_diagnostics == null:
		return _err("editor_diagnostics_unavailable", "Editor diagnostics service is not initialized.")
	return _editor_diagnostics.notes_clear({})


func _find_object_property_info(object: Object, property_name: String) -> Dictionary:
	for property_info in object.get_property_list():
		if typeof(property_info) == TYPE_DICTIONARY and str((property_info as Dictionary).get("name", "")) == property_name:
			return property_info as Dictionary
	return {}


func _serialized_property_changes(changes: Array) -> Array:
	var serialized: Array = []
	for change in changes:
		if typeof(change) != TYPE_DICTIONARY:
			continue
		var change_dict := change as Dictionary
		serialized.append({
			"property": change_dict.get("property", ""),
			"old_value": _variant_to_json_value(change_dict.get("old_value")),
			"new_value": _variant_to_json_value(change_dict.get("new_value")),
		})
	return serialized


func _validate_editor_property(node: Node, property_name: String) -> Dictionary:
	if property_name == "":
		return _error_payload("invalid_property", "Property name cannot be empty.")
	if property_name.begins_with("_") or property_name in ["script", "owner"]:
		return _error_payload("unsupported_property", "Property is not editable through editor control: " + property_name)
	if property_name.find("\n") >= 0 or property_name.length() > 160:
		return _error_payload("invalid_property", "Property name is invalid or too long.")
	for property_info in node.get_property_list():
		if typeof(property_info) == TYPE_DICTIONARY and str((property_info as Dictionary).get("name", "")) == property_name:
			return {}
	return _error_payload("property_not_found", "Node does not expose property: " + property_name)


func _coerce_editor_property_value(old_value: Variant, raw_value: Variant) -> Dictionary:
	return VariantCodec.coerce_editor_property_value(old_value, raw_value)


func _coerce_transform_value(old_value: Variant, raw_value: Variant, property_name: String, mode: String) -> Dictionary:
	return VariantCodec.coerce_transform_value(old_value, raw_value, property_name, mode)


func _vector2_from_payload(value: Variant) -> Dictionary:
	return VariantCodec.vector2_from_payload(value)


func _vector3_from_payload(value: Variant) -> Dictionary:
	return VariantCodec.vector3_from_payload(value)


func _color_from_payload(value: Variant) -> Dictionary:
	return VariantCodec.color_from_payload(value)


func _coerced_value(result: Dictionary) -> Variant:
	return VariantCodec.coerced_value(result)


func _payload_has_any(payload: Dictionary, keys: Array) -> bool:
	for key in keys:
		if payload.has(str(key)):
			return true
	return false


func _payload_get_any(payload: Dictionary, keys: Array) -> Variant:
	for key in keys:
		if payload.has(str(key)):
			return payload.get(str(key))
	return null


func _response_payload(request_id: String, request_type: String, status: String, data: Dictionary, error: Dictionary, request_file_name: String) -> Dictionary:
	return BridgeResponseModel.response_payload(
		PROTOCOL_VERSION,
		request_id,
		request_type,
		status,
		data,
		error,
		_iso_now(),
		_iso_now()
	)


func _load_host_config() -> Dictionary:
	_apply_host_config_state(ChatHostConfigModel.missing_state(DEFAULT_CODEX_HOST_PORT))
	if _host_config_abs == "" or not FileAccess.file_exists(_host_config_abs):
		_log_event("host_config_missing", {"path": HOST_CONFIG_PATH})
		return {}

	var read_result := _read_json_file(_host_config_abs)
	if not read_result.get("ok", false):
		_apply_host_config_state(ChatHostConfigModel.invalid_state(DEFAULT_CODEX_HOST_PORT, "Host connection config is not valid JSON. Refresh the addon install; no default port was used."))
		_log_event("host_config_invalid", {
			"path": HOST_CONFIG_PATH,
			"error": read_result.get("error", {}),
		})
		return {}

	var data: Dictionary = read_result.get("data", {})
	var node_entry := str(data.get("node_entry", ""))
	var start_script := str(data.get("start_script", ""))
	var state := ChatHostConfigModel.normalize_config(
		data,
		node_entry != "" and FileAccess.file_exists(node_entry),
		start_script != "" and FileAccess.file_exists(start_script),
		DEFAULT_CODEX_HOST_PORT
	)
	_apply_host_config_state(state)
	_log_event("host_config_loaded", {
		"path": HOST_CONFIG_PATH,
		"port": _host_config_port,
		"runtime": _host_config_runtime,
		"start_script": start_script,
		"node_entry": node_entry,
		"status": _host_config_status,
	})
	return data


func _read_json_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {
			"ok": false,
			"error": _error_payload("file_read_failed", "Failed to read JSON file: " + path + " (" + error_string(FileAccess.get_open_error()) + ")"),
		}

	var text := ""
	if path.begins_with(_requests_dir_abs):
		var bytes := file.get_buffer(MAX_REQUEST_BYTES + 1)
		var bounded_request := BridgeRequestLimits.parse_bounded_request(bytes)
		if not bool(bounded_request.get("ok", false)):
			return bounded_request
		return bounded_request
	else:
		text = file.get_as_text()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {
			"ok": false,
			"error": _error_payload("invalid_json", "Expected a JSON object in: " + path),
		}

	return {
		"ok": true,
		"data": parsed,
	}


func _write_json_file(path: String, data: Dictionary) -> Dictionary:
	var path_guard := _validate_bridge_path(path, true)
	if not bool(path_guard.get("ok", false)):
		return {
			"ok": false,
			"error": path_guard.get("error", _error_payload("file_path_rejected", "Bridge JSON path is unsafe: " + path)),
		}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {
			"ok": false,
			"error": _error_payload("file_write_failed", "Failed to write JSON file: " + path + " (" + error_string(FileAccess.get_open_error()) + ")"),
		}

	file.store_string(JSON.stringify(data, "\t"))
	return {"ok": true}


func _write_bridge_state(addon_active: bool) -> void:
	if _bridge_state_abs == "":
		return

	_write_json_file(_bridge_state_abs, {
		"protocol_version": PROTOCOL_VERSION,
		"addon_active": addon_active,
		"plugin_name": PLUGIN_NAME,
		"plugin_version": PLUGIN_VERSION,
		"bridge_dir": BRIDGE_DIR,
		"permissions": _permissions,
		"updated_at": _iso_now(),
	})


func _write_heartbeat() -> void:
	if _heartbeat_abs == "":
		return

	_write_json_file(_heartbeat_abs, {
		"protocol_version": PROTOCOL_VERSION,
		"addon_active": true,
		"updated_at": _iso_now(),
	})


func _write_permissions() -> void:
	if _permissions_abs == "":
		return

	_write_json_file(_permissions_abs, {
		"protocol_version": PROTOCOL_VERSION,
		"updated_at": _iso_now(),
		"permissions": _permissions,
	})


func _permission_enabled(key: String) -> bool:
	return bool(_permissions.get(key, false))


func _error_payload(code: String, message: String) -> Dictionary:
	return BridgeResponseModel.error_payload(code, message)


func _scene_path_for(node: Node, scene_root: Node) -> String:
	return _introspection._scene_path_for(node, scene_root)
func _parent_scene_path_for(node: Node, scene_root: Node) -> Variant:
	return _introspection._parent_scene_path_for(node, scene_root)
func _count_scene_nodes(root: Node) -> int:
	if root == null:
		return 0

	var count := 1
	for child in root.get_children():
		count += _count_scene_nodes(child)
	return count


func _current_scene_path_or_null() -> Variant:
	return _introspection._current_scene_path_or_null()
func _selected_node_paths() -> Array:
	return _introspection._selected_node_paths()
func _resource_reference(value: Variant) -> Variant:
	return _introspection._resource_reference(value)
func _resource_path_or_null(value: Variant) -> Variant:
	return VariantCodec.resource_path_or_null(value)


func _null_if_empty(value: String) -> Variant:
	return null if value == "" else value


func _property_value_summary(value: Variant) -> Variant:
	return _introspection._property_value_summary(value)
func _is_redacted_value(value: Variant) -> bool:
	return _introspection._is_redacted_value(value)
func _omitted_reason_for(value: Variant) -> Variant:
	return _introspection._omitted_reason_for(value)
func _truncate_string(value: String, max_length: int = MAX_STRING_LENGTH) -> String:
	if value.length() <= max_length:
		return value
	return value.substr(0, max_length)


func _variant_to_json_value(value: Variant, depth: int = 0) -> Variant:
	return VariantCodec.variant_to_json_value(value, depth, MAX_PROPERTY_DEPTH, MAX_ARRAY_ITEMS, MAX_DICTIONARY_ITEMS)


func _array_to_json_summary(value: Array, depth: int) -> Dictionary:
	return VariantCodec.array_to_json_summary(value, depth, MAX_PROPERTY_DEPTH, MAX_ARRAY_ITEMS, MAX_DICTIONARY_ITEMS)


func _dictionary_to_json_summary(value: Dictionary, depth: int) -> Dictionary:
	return VariantCodec.dictionary_to_json_summary(value, depth, MAX_PROPERTY_DEPTH, MAX_ARRAY_ITEMS, MAX_DICTIONARY_ITEMS)


func _packed_array_sample(value: Variant) -> Array:
	return VariantCodec.packed_array_sample(value, MAX_PROPERTY_DEPTH, MAX_ARRAY_ITEMS, MAX_DICTIONARY_ITEMS)


func _string_array(values: Array) -> Array:
	var strings: Array = []
	for value in values:
		strings.append(str(value))
	return strings


func _list_files_with_extension(dir_path: String, extension: String, max_results: int = 0) -> Array:
	var files: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return files

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(extension):
			files.append(file_name)
			if max_results > 0 and files.size() >= max_results:
				break
		file_name = dir.get_next()
	dir.list_dir_end()

	return files


func _log_event(event_type: String, data: Dictionary = {}) -> void:
	_bridge_log.append({
		"at": _iso_now(),
		"type": event_type,
		"data": data,
	})

	while _bridge_log.size() > MAX_BRIDGE_LOG_EVENTS:
		_bridge_log.pop_front()


func _iso_now() -> String:
	return Time.get_datetime_string_from_system(true, false) + "Z"


func _file_timestamp() -> String:
	return _iso_now().replace("-", "").replace(":", "").replace("T", "_").replace("Z", "")


func _safe_identifier(value: String) -> String:
	var safe := ""
	for index in range(value.length()):
		var character := value.substr(index, 1)
		if character.is_valid_identifier() or character.is_valid_int() or character == "-" or character == ".":
			safe += character
		else:
			safe += "_"
	return safe.strip_edges().substr(0, 128) if safe.strip_edges() != "" else "artifact"
