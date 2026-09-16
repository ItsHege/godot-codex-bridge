@tool
extends RefCounted

const BridgeContext := preload("bridge_context.gd")
const BridgeLimits := preload("bridge_limits.gd")
const EditorSignals := preload("editor_signals.gd")

var _context: BridgeContext


func _init(context: BridgeContext = null) -> void:
	_context = context


func get_class_info(params: Dictionary) -> Dictionary:
	if not _permission_enabled("allow_editor_inspect"):
		return _err("permission_denied", "Inspect/select nodes permission is disabled in the Codex Bridge dock.")

	var requested_class := sanitize_class_name(str(params.get("class_name", params.get("className", ""))).strip_edges())
	if requested_class == "":
		return _err("invalid_class_name", "className is required.")
	if not ClassDB.class_exists(requested_class):
		return _err("class_not_found", "ClassDB does not contain class: " + requested_class + ". Script-defined class_name classes are not part of ClassDB.")
	var no_inheritance := bool(params.get("no_inheritance", params.get("noInheritance", false)))
	var max_items := clampi(int(params.get("limit", 80)), 1, 200)
	return _ok({
		"captured_at": _timestamp(),
		"class_name": requested_class,
		"exists": true,
		"parent_class": str(ClassDB.get_parent_class(requested_class)),
		"can_instantiate": ClassDB.can_instantiate(requested_class),
		"is_node": ClassDB.is_parent_class(requested_class, "Node") or requested_class == "Node",
		"is_resource": ClassDB.is_parent_class(requested_class, "Resource") or requested_class == "Resource",
		"api_type": int(ClassDB.class_get_api_type(requested_class)),
		"no_inheritance": no_inheritance,
		"properties": class_property_list_payload(ClassDB.class_get_property_list(requested_class, no_inheritance), max_items),
		"methods": class_method_list_payload(ClassDB.class_get_method_list(requested_class, no_inheritance), max_items),
		"signals": class_signal_list_payload(ClassDB.class_get_signal_list(requested_class, no_inheritance), max_items),
		"integer_constants": packed_string_array_to_limited_array(ClassDB.class_get_integer_constant_list(requested_class, no_inheritance), max_items),
		"enums": packed_string_array_to_limited_array(ClassDB.class_get_enum_list(requested_class, no_inheritance), max_items),
		"limits": {
			"max_items_per_section": max_items,
			"max_string_length": BridgeLimits.MAX_STRING_LENGTH,
		},
		"snapshot_refreshed": false,
	})


static func sanitize_class_name(value: String) -> String:
	var sanitized := value.strip_edges()
	if sanitized.length() > 96 or sanitized.find("\n") >= 0 or sanitized.find("\r") >= 0:
		return ""
	return sanitized


static func class_property_list_payload(items: Array, max_items: int) -> Dictionary:
	var properties: Array = []
	var count: int = min(items.size(), max_items)
	for index in range(count):
		var item: Variant = items[index]
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var info := item as Dictionary
		properties.append({
			"name": str(info.get("name", "")),
			"type": type_string(int(info.get("type", TYPE_NIL))),
			"class_name": str(info.get("class_name", "")),
			"hint": int(info.get("hint", 0)),
			"hint_string": truncate_string(str(info.get("hint_string", "")), 240),
			"usage": int(info.get("usage", 0)),
		})
	return {
		"items": properties,
		"count": items.size(),
		"returned": properties.size(),
		"truncated": items.size() > max_items,
	}


static func class_method_list_payload(items: Array, max_items: int) -> Dictionary:
	var methods: Array = []
	var count: int = min(items.size(), max_items)
	for index in range(count):
		var item: Variant = items[index]
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var info := item as Dictionary
		methods.append({
			"name": str(info.get("name", "")),
			"args": EditorSignals.signal_args_payload(info.get("args", [])),
			"return": class_return_payload(info.get("return", {})),
			"flags": int(info.get("flags", 0)),
		})
	return {
		"items": methods,
		"count": items.size(),
		"returned": methods.size(),
		"truncated": items.size() > max_items,
	}


static func class_signal_list_payload(items: Array, max_items: int) -> Dictionary:
	var signals: Array = []
	var count: int = min(items.size(), max_items)
	for index in range(count):
		var item: Variant = items[index]
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var info := item as Dictionary
		signals.append({
			"name": str(info.get("name", "")),
			"args": EditorSignals.signal_args_payload(info.get("args", [])),
			"return": class_return_payload(info.get("return", {})),
			"flags": int(info.get("flags", 0)),
		})
	return {
		"items": signals,
		"count": items.size(),
		"returned": signals.size(),
		"truncated": items.size() > max_items,
	}


static func class_return_payload(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var info := value as Dictionary
	return {
		"name": str(info.get("name", "")),
		"type": type_string(int(info.get("type", TYPE_NIL))),
		"class_name": str(info.get("class_name", "")),
		"hint": int(info.get("hint", 0)),
		"hint_string": truncate_string(str(info.get("hint_string", "")), 240),
	}


static func packed_string_array_to_limited_array(value: Variant, max_items: int) -> Dictionary:
	var all_items := packed_string_array_to_array(value)
	var items: Array = []
	var count: int = min(all_items.size(), max_items)
	for index in range(count):
		items.append(all_items[index])
	return {
		"items": items,
		"count": all_items.size(),
		"returned": items.size(),
		"truncated": all_items.size() > max_items,
	}


static func packed_string_array_to_array(value: Variant) -> Array:
	var output: Array = []
	if value is PackedStringArray:
		for item in value:
			output.append(str(item))
	elif value is Array:
		for item in value:
			output.append(str(item))
	return output


static func truncate_string(value: String, max_length: int = 4096) -> String:
	if value.length() <= max_length:
		return value
	return value.substr(0, max(0, max_length - 1)) + "..."


func _permission_enabled(key: String) -> bool:
	return _context != null and _context.permission_enabled(key)


func _timestamp() -> String:
	if _context != null:
		return _context.timestamp_iso()
	return Time.get_datetime_string_from_system(true, true)


func _ok(data: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"data": data,
	}


func _err(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"error": _context.err(code, message) if _context != null else {"code": code, "message": message},
	}
