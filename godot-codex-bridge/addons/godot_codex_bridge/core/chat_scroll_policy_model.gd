@tool
extends RefCounted

const DEFAULT_BOTTOM_TOLERANCE := 32.0


static func is_near_bottom(value: float, maximum: float, tolerance := DEFAULT_BOTTOM_TOLERANCE) -> bool:
	return value >= max(maximum - max(tolerance, 0.0), 0.0)


static func after_user_scroll(value: float, maximum: float, tolerance := DEFAULT_BOTTOM_TOLERANCE) -> Dictionary:
	var follow_latest := is_near_bottom(value, maximum, tolerance)
	return {
		"follow_latest": follow_latest,
		"show_jump_latest": not follow_latest,
	}


static func content_update(follow_latest: bool) -> Dictionary:
	return {
		"scroll_to_bottom": follow_latest,
		"show_jump_latest": not follow_latest,
	}


static func jump_to_latest() -> Dictionary:
	return {
		"follow_latest": true,
		"scroll_to_bottom": true,
		"show_jump_latest": false,
	}
