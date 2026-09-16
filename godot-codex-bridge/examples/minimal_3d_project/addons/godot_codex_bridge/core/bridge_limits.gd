@tool
extends RefCounted

## Single source of truth for Godot Codex Bridge constants.
## plugin.gd re-exports these so existing references keep working while the
## monolith is split into core/ service modules. New service modules should
## preload this file directly (e.g. `const L := preload("bridge_limits.gd")`).

const PLUGIN_NAME := "Godot Codex Bridge"
const PLUGIN_VERSION := "0.0.1"
const PROTOCOL_VERSION := "godot-codex-bridge/0.1"

const BRIDGE_DIR := "res://.godot/godot_codex_bridge"
const REQUESTS_DIR := BRIDGE_DIR + "/requests"
const RESPONSES_DIR := BRIDGE_DIR + "/responses"
const SCREENSHOTS_DIR := BRIDGE_DIR + "/artifacts/screenshots"
const ANNOTATIONS_DIR := BRIDGE_DIR + "/artifacts/annotations"
const CONTEXT_SNAPSHOT_PATH := BRIDGE_DIR + "/context_snapshot.json"
const BRIDGE_STATE_PATH := BRIDGE_DIR + "/bridge_state.json"
const HEARTBEAT_PATH := BRIDGE_DIR + "/heartbeat.json"
const PERMISSIONS_PATH := BRIDGE_DIR + "/permissions.json"
const SEND_CONTEXT_PATH := BRIDGE_DIR + "/artifacts/send_context.json"
const NOTES_PATH := BRIDGE_DIR + "/notes.json"
const HOST_CONFIG_PATH := "res://addons/godot_codex_bridge/host_config.json"
const FIX_SELECTED_NODE_APPROVAL_TOKEN := "APPROVE_GODOT_CODEX_BRIDGE_FIX_SELECTED_NODE"
const VALIDATION_PERMISSION_TOKEN := "GCB_VALIDATE_PERMISSION_TOGGLE"
const DEFAULT_CODEX_HOST_PORT := 49390
const CODEX_HOST_URL := "ws://127.0.0.1:49390"

const POLL_SECONDS := 0.25
const HEARTBEAT_SECONDS := 2.0
const HEARTBEAT_STALE_SECONDS := 10.0
const CHAT_HOST_START_RETRY_SECONDS := 0.75
const CHAT_HOST_START_TIMEOUT_SECONDS := 30.0
const CHAT_MAX_PACKETS_PER_FRAME := 48
const CHAT_MAX_PACKET_CHARS := 262144
const CHAT_MAX_MESSAGE_CHARS := 65536
const CHAT_ASSISTANT_BUBBLE_CHARS := 7000
const CHAT_ASSISTANT_SECTION_CHARS := 2200
const CHAT_COLLAPSE_CHARS := 1200
const CHAT_COLLAPSE_LINES := 14
const CHAT_PREVIEW_CHARS := 900
const CHAT_PREVIEW_LINES := 8
const CHAT_WORK_PREVIEW_CHARS := 220
const CHAT_WORK_PREVIEW_LINES := 2
const CHAT_DIFF_MAX_FILES := 24
const CHAT_DIFF_MAX_LINES_PER_FILE := 360
const CHAT_BACKPRESSURE_NOTICE_INTERVAL_MSEC := 10000
const CHAT_ASSISTANT_FLUSH_INTERVAL_MSEC := 50
const CHAT_HOST_SHUTDOWN_GRACE_MSEC := 250
const MAX_SCENE_NODES := 256
const MAX_CHILDREN_PER_NODE := 64
const MAX_SELECTED_NODES := 16
const MAX_PROPERTIES_PER_NODE := 48
const MAX_PROPERTY_DEPTH := 2
const MAX_ARRAY_ITEMS := 12
const MAX_DICTIONARY_ITEMS := 16
const MAX_RESOURCES := 250
const MAX_INPUT_ACTIONS := 128
const MAX_SCRIPT_FILES := 200
const MAX_SCRIPT_LINES_PER_FILE := 400
const MAX_SCRIPT_SYMBOLS_PER_FILE := 64
const MAX_SCREENSHOTS_IN_CONTEXT := 16
const MAX_BRIDGE_LOG_EVENTS := 80
const MAX_REQUESTS_PER_POLL := 16
const MAX_MATERIALS_PER_MESH := 8
const MAX_PERFORMANCE_SAMPLES := 120
const MAX_STRING_LENGTH := 512
const MAX_DEPTH := 32
const MAX_EDITOR_BATCH_ACTIONS := 12
const MAX_EDITOR_PROPERTY_CHANGES := 20
const MAX_RECENT_EDITOR_ACTIONS := 40
const MAX_BRIDGE_NOTES := 200
const MAX_ANIMATION_PLAYERS := 64
const MAX_ANIMATIONS_PER_PLAYER := 80
const MAX_ANIMATION_TRACKS := 120
const MAX_ANIMATION_KEYS_PER_TRACK := 16
const MAX_ANIMATION_INITIAL_TRACKS := 12
const MAX_MATERIAL_INSPECT_NODES := 96
const MAX_MATERIAL_SLOTS := 192
const MAX_SHADER_UNIFORMS := 64
const MAX_RENDER_EFFECT_NODES := 96
const MAX_ENVIRONMENT_PROPERTIES := 48
const MAX_IMPORTED_ASSETS := 250
const MAX_ASSET_DEPENDENCIES := 16
