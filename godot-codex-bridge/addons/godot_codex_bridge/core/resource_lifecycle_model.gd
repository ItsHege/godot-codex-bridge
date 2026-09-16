@tool
extends RefCounted

const VariantCodec := preload("variant_codec.gd")


static func sanitize_resource_class_name(value: String) -> String:
	var resource_class := value.strip_edges()
	if resource_class.length() > 96 or resource_class.find("\n") >= 0 or resource_class.find("\r") >= 0:
		return ""
	return resource_class


static func validate_assignment_property(node: Node, property_name: String) -> Dictionary:
	var property_error := validate_editor_property(node, property_name)
	if not property_error.is_empty():
		return {"ok": false, "error": property_error}
	var property_info := find_object_property_info(node, property_name)
	if property_info.is_empty():
		return _err("property_not_found", "Node does not expose property: " + property_name)
	var old_value: Variant = node.get(property_name)
	if int(property_info.get("type", TYPE_NIL)) != TYPE_OBJECT and not (old_value is Resource) and old_value != null:
		return _err("unsupported_property_type", "Property is not a Resource/Object slot: " + property_name)
	var expected_class := expected_resource_class_for_property(property_info, old_value)
	if expected_class == "" and old_value == null and int(property_info.get("type", TYPE_NIL)) != TYPE_OBJECT:
		return _err("unsupported_property_type", "Property is not a Resource slot: " + property_name)
	return {
		"ok": true,
		"property_info": property_info,
		"expected_class": expected_class,
	}


static func validate_editor_property(node: Node, property_name: String) -> Dictionary:
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


static func expected_resource_class_for_property(property_info: Dictionary, old_value: Variant) -> String:
	var expected_class_name := str(property_info.get("class_name", "")).strip_edges()
	if expected_class_name == "":
		var hint_string := str(property_info.get("hint_string", "")).strip_edges()
		if hint_string != "":
			var first_hint := str(hint_string.split(",")[0]).strip_edges()
			if first_hint != "" and ClassDB.class_exists(first_hint):
				expected_class_name = first_hint
	if expected_class_name == "" and old_value is Resource:
		expected_class_name = (old_value as Resource).get_class()
	return expected_class_name


static func validate_matches_property(property_info: Dictionary, old_value: Variant, resource_value: Variant) -> Dictionary:
	if resource_value == null:
		return {}
	if not (resource_value is Resource):
		return _error_payload("invalid_resource", "Assigned value is not a Resource.")
	var expected_classes := expected_resource_class_candidates(property_info, old_value)
	if expected_classes.is_empty() or "Resource" in expected_classes:
		return {}
	var resource := resource_value as Resource
	var resource_class := resource.get_class()
	for expected_class in expected_classes:
		var expected := str(expected_class)
		if resource_class == expected or ClassDB.is_parent_class(resource_class, expected):
			return {}
	return _error_payload("resource_type_mismatch", "Resource class " + resource_class + " is not compatible with property type(s) " + str(expected_classes) + ".")


static func expected_resource_class_candidates(property_info: Dictionary, old_value: Variant) -> Array:
	var candidates: Array = []
	var raw_values := [
		str(property_info.get("class_name", "")).strip_edges(),
		str(property_info.get("hint_string", "")).strip_edges(),
	]
	for raw_value in raw_values:
		for part in str(raw_value).split(","):
			var candidate := str(part).strip_edges()
			if candidate == "" or not ClassDB.class_exists(candidate):
				continue
			if not candidate in candidates:
				candidates.append(candidate)
	if candidates.is_empty() and old_value is Resource:
		candidates.append((old_value as Resource).get_class())
	return candidates


static func validate_resource_property(resource: Resource, property_name: String) -> Dictionary:
	if property_name == "":
		return _error_payload("invalid_property", "Resource property name cannot be empty.")
	if property_name.begins_with("_") or property_name in ["script", "resource_path"]:
		return _error_payload("unsupported_property", "Resource property is not editable through editor control: " + property_name)
	if property_name.find("\n") >= 0 or property_name.length() > 160:
		return _error_payload("invalid_property", "Resource property name is invalid or too long.")
	for property_info in resource.get_property_list():
		if typeof(property_info) == TYPE_DICTIONARY and str((property_info as Dictionary).get("name", "")) == property_name:
			return {}
	return _error_payload("property_not_found", "Resource does not expose property: " + property_name)


static func prepare_property_changes(resource: Resource, changes_value: Variant, max_changes: int) -> Dictionary:
	if typeof(changes_value) != TYPE_ARRAY:
		return _err("invalid_property_changes", "changes must be an array.")
	var requested_changes: Array = changes_value
	if requested_changes.size() > max_changes:
		return _err("too_many_property_changes", "Resource property changes support at most " + str(max_changes) + " changes per request.")
	var prepared_changes: Array = []
	for item in requested_changes:
		if typeof(item) != TYPE_DICTIONARY:
			return _err("invalid_property_change", "Each resource property change must be an object.")
		var change: Dictionary = item
		var property_name := str(change.get("property", "")).strip_edges()
		var property_error := validate_resource_property(resource, property_name)
		if not property_error.is_empty():
			return {"ok": false, "error": property_error}
		var old_value: Variant = resource.get(property_name)
		var coercion := VariantCodec.coerce_editor_property_value(old_value, change.get("value"))
		if not coercion.get("ok", false):
			return coercion
		prepared_changes.append({
			"property": property_name,
			"old_value": old_value,
			"new_value": VariantCodec.coerced_value(coercion),
		})
	return {
		"ok": true,
		"changes": prepared_changes,
	}


static func find_object_property_info(object: Object, property_name: String) -> Dictionary:
	for property_info in object.get_property_list():
		if typeof(property_info) == TYPE_DICTIONARY and str((property_info as Dictionary).get("name", "")) == property_name:
			return property_info as Dictionary
	return {}


static func _err(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"error": _error_payload(code, message),
	}


static func _error_payload(code: String, message: String) -> Dictionary:
	return {
		"code": code,
		"message": message,
	}
