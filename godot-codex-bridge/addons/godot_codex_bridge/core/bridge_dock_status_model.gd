@tool
extends RefCounted

## One-line Bridge dock status: "● Snapshot 15:42 · 0 pending". The full status
## text and ISO timestamp go to the tooltip.

const PROBLEM_WORDS := ["fail", "denied", "disabled", "error", "rejected", "unavailable"]


static func summary(last_status: String, last_snapshot_iso: String, pending_count: int, utc_offset_minutes: int = 0) -> Dictionary:
	var time_text := local_clock_text(last_snapshot_iso, utc_offset_minutes)
	var text := ("Snapshot " + time_text if time_text != "" else "No snapshot yet") + " · " + str(pending_count) + " pending"
	var tone := "ok"
	var lowered := last_status.to_lower()
	for word in PROBLEM_WORDS:
		if lowered.contains(word):
			tone = "error"
			break
	if tone == "ok" and (pending_count > 0 or time_text == ""):
		tone = "warn"
	return {
		"text": text,
		"tone": tone,
		"tooltip": "Status: " + last_status + "\nLast snapshot: " + (last_snapshot_iso if last_snapshot_iso != "" else "none") + "\nPending requests: " + str(pending_count),
	}


## "2026-09-30T15:42:47Z" -> local "HH:MM"; "" when not a timestamp.
static func local_clock_text(iso: String, utc_offset_minutes: int) -> String:
	var value := iso.strip_edges()
	if value.length() < 19 or value[10] != "T":
		return ""
	var unix := Time.get_unix_time_from_datetime_string(value.substr(0, 19))
	if unix <= 0:
		return ""
	var local := Time.get_datetime_dict_from_unix_time(unix + utc_offset_minutes * 60)
	return "%02d:%02d" % [int(local.get("hour", 0)), int(local.get("minute", 0))]
