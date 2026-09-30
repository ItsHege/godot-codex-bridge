@tool
extends RefCounted

## Idempotency journal. While a request could still pass the start window, its
## claim is kept: after a crash an unfinished request is refused rather than
## risking a second editor side effect, and a completed one replays its result.
##
## Retention: begin() only accepts a request whose created_at is at most
## MAX_NEW_REQUEST_AGE_SECONDS old, at most START_SKEW_SECONDS in the future,
## and not past a deadline that is at most MAX_NEW_REQUEST_AGE_SECONDS after
## created_at. A request first claimed at time T therefore cannot pass that
## window after T + 600 + 120. Once an entry is older than PRUNE_AFTER_SECONDS
## (well beyond that bound) a replay of the same body is refused as
## stale_request instead of outcome_unknown/replayed, so it is still never
## re-executed. This holds for unfinished claims too: their deadline expired
## long ago, so keeping them buys nothing. Claims still being run by this
## instance are never pruned. Orphan .lock dirs and .tmp files use their file
## age. Entries of unknown age (unreadable mtime) are kept. The trade-off is
## that request_id uniqueness is only enforced inside the retention window;
## Hosts mint a fresh UUID per request. The cap stays as a fail-closed backstop.
const MAX_CLAIMS := 4096
const MAX_RESULT_BYTES := 1048576
const MAX_NEW_REQUEST_AGE_SECONDS := 600.0
const START_SKEW_SECONDS := 120.0
const PRUNE_AFTER_SECONDS := 1800.0
const MAINTENANCE_INTERVAL_SECONDS := 60.0
const MAX_PRUNE_PER_PASS := 512

var directory_abs := ""
var validate_path: Callable
## Test seams: an optional clock returning unix seconds, and the claim cap.
var clock := Callable()
var max_claims := MAX_CLAIMS

var _active_request_ids := {}
## Cached entry count, refreshed by a throttled scan instead of listing the
## directory on every request. Claims made by other editor processes between
## scans are only seen at the next scan; the cap is a backstop, not a quota.
var _entry_count := -1
var _last_maintenance_unix := 0.0


func _init(path: String, path_validator: Callable) -> void:
	directory_abs = path
	validate_path = path_validator


func begin(request: Dictionary) -> Dictionary:
	var request_id_value: Variant = request.get("request_id")
	if typeof(request_id_value) != TYPE_STRING or not valid_uuid(request_id_value as String):
		return _failure("invalid_request_id", "A UUID request_id is required before an addon action.")
	var request_id := request_id_value as String
	var digest := canonical_json(request).sha256_text()
	var claim_path := _path(request_id, ".claim.json")
	var result_path := _path(request_id, ".result.json")
	var lock_path := _path(request_id, ".lock")
	if not _safe(claim_path) or not _safe(result_path) or not _safe(lock_path):
		return _failure("journal_path_rejected", "The request journal path is unsafe.")
	if FileAccess.file_exists(claim_path):
		var existing := _read(claim_path)
		if not bool(existing.get("ok", false)):
			return _failure("outcome_unknown", "The request claim is unreadable; the action will not be retried.")
		if str(existing.get("payload_hash", "")) != digest:
			return _failure("request_id_conflict", "The request_id was already used with different content.")
		if FileAccess.file_exists(result_path):
			var completed := _read(result_path)
			if bool(completed.get("ok", false)) and str(completed.get("payload_hash", "")) == digest and typeof(completed.get("response")) == TYPE_DICTIONARY:
				return {"ok": true, "state": "completed", "response": completed.get("response")}
		return _failure("outcome_unknown", "The request began earlier; its result is unknown and the action will not be retried.")
	if DirAccess.dir_exists_absolute(lock_path):
		return _failure("outcome_unknown", "Another editor claimed this request; its result is not yet known.")
	var created_at: Variant = request.get("created_at")
	var deadline_at: Variant = request.get("deadline_at")
	if typeof(created_at) != TYPE_STRING or (created_at as String).length() < 19 or typeof(deadline_at) != TYPE_STRING or (deadline_at as String).length() < 19:
		return _failure("invalid_request_time", "Request created_at and deadline_at timestamps are required before an addon action.")
	var created_unix := _iso_unix(created_at as String)
	var deadline_unix := _iso_unix(deadline_at as String)
	var now := _now()
	var age := now - created_unix
	if created_unix <= 0.0 or deadline_unix <= created_unix or deadline_unix - created_unix > MAX_NEW_REQUEST_AGE_SECONDS or age > MAX_NEW_REQUEST_AGE_SECONDS or age < -START_SKEW_SECONDS or now > deadline_unix:
		return _failure("stale_request", "The request timestamp is outside the allowed start window.")
	if not _maintain(now):
		return _failure("journal_unavailable", "The request journal is unavailable.")
	if _entry_count >= max_claims:
		return _failure("journal_full", "The request journal is full; no new action was started.")
	# A same-directory mkdir is the exclusive cross-process claim. If publication
	# fails, keep the lock and refuse replay rather than attempting the action.
	if DirAccess.make_dir_absolute(lock_path) != OK:
		return _failure("outcome_unknown", "Another editor claimed this request; the action will not be retried.")
	_entry_count += 1
	_active_request_ids[request_id.to_lower()] = true
	var claim := {"request_id": request_id, "payload_hash": digest, "state": "in_progress", "claimed_unix": now}
	if not _write_new_atomic(claim_path, claim):
		_active_request_ids.erase(request_id.to_lower())
		return _failure("journal_write_failed", "The request could not be durably claimed; no action was started.")
	return {"ok": true, "state": "claimed", "request_id": request_id}


func complete(request_id: String, response: Dictionary) -> Dictionary:
	_active_request_ids.erase(request_id.to_lower())
	var result_path := _path(request_id, ".result.json")
	var claim_path := _path(request_id, ".claim.json")
	if not valid_uuid(request_id) or not _safe(result_path) or not _safe(claim_path):
		return _failure("journal_path_rejected", "The result journal path is unsafe.")
	var claim := _read(claim_path)
	if not bool(claim.get("ok", false)):
		return _failure("outcome_unknown", "The request claim is unavailable; the action will not be retried.")
	if FileAccess.file_exists(result_path):
		return _failure("journal_result_exists", "The request already has a durable result.")
	if not _write_new_atomic(result_path, {"request_id": request_id, "payload_hash": str(claim.get("payload_hash", "")), "response": response, "completed_unix": Time.get_unix_time_from_system()}):
		return _failure("outcome_unknown", "The action ran but its result could not be durably recorded; it will not be retried.")
	return {"ok": true, "response": response}


static func valid_uuid(value: String) -> bool:
	if value.length() != 36:
		return false
	for i in range(36):
		var character := value[i]
		if i in [8, 13, 18, 23]:
			if character != "-":
				return false
		elif not character.to_lower() in "0123456789abcdef":
			return false
	return true


static func canonical_json(value: Variant) -> String:
	if typeof(value) == TYPE_DICTIONARY:
		var dictionary := value as Dictionary
		var keys: Array[String] = []
		for key in dictionary.keys():
			keys.append(str(key))
		keys.sort()
		var pairs: Array[String] = []
		for key in keys:
			pairs.append(JSON.stringify(key) + ":" + canonical_json(dictionary.get(key)))
		return "{" + ",".join(pairs) + "}"
	if typeof(value) == TYPE_ARRAY:
		var items: Array[String] = []
		for item in value as Array:
			items.append(canonical_json(item))
		return "[" + ",".join(items) + "]"
	return JSON.stringify(value)


static func _iso_unix(value: String) -> float:
	var whole := Time.get_unix_time_from_datetime_string(value.substr(0, 19))
	if value.length() < 21 or value[19] != ".":
		return whole
	var fraction := value.substr(20).split("Z", false, 1)[0]
	if fraction.length() == 0 or not fraction.is_valid_int():
		return -1.0
	return whole + float((fraction + "000").substr(0, 3).to_int()) / 1000.0


func _path(request_id: String, suffix: String) -> String:
	return directory_abs.path_join(request_id.to_lower() + suffix)


func _safe(path: String) -> bool:
	return bool(validate_path.call(path, true).get("ok", false))


func _read(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_RESULT_BYTES:
		return {"ok": false}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false}
	var result := parsed as Dictionary
	result["ok"] = true
	return result


func _write_new_atomic(path: String, data: Dictionary) -> bool:
	var temporary := path + "." + str(Time.get_ticks_usec()) + ".tmp"
	if not _safe(temporary):
		return false
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	file.flush()
	var write_ok := file.get_error() == OK
	file.close()
	if not write_ok or FileAccess.file_exists(path):
		DirAccess.remove_absolute(temporary)
		return false
	var rename_error := DirAccess.rename_absolute(temporary, path)
	if rename_error != OK:
		DirAccess.remove_absolute(temporary)
	return rename_error == OK


func _now() -> float:
	if clock.is_valid():
		return float(clock.call())
	return Time.get_unix_time_from_system()


## Throttled, bounded retention pass. Refreshes the cached entry count and
## deletes at most MAX_PRUNE_PER_PASS entries older than PRUNE_AFTER_SECONDS.
func _maintain(now: float) -> bool:
	if _entry_count >= 0 and absf(now - _last_maintenance_unix) < MAINTENANCE_INTERVAL_SECONDS:
		return true
	var access := DirAccess.open(directory_abs)
	if access == null:
		return false
	_last_maintenance_unix = now
	var files := access.get_files()
	var present := {}
	for name in files:
		present[str(name)] = true
	var budget := MAX_PRUNE_PER_PASS
	var count := 0
	for file_name in files:
		var name := str(file_name)
		var request_id := name.substr(0, 36).to_lower()
		if not valid_uuid(request_id):
			continue
		if name == request_id + ".claim.json":
			if budget > 0 and _entry_is_expired(request_id, now) and _remove_entry(request_id):
				budget -= 1
				continue
			count += 1
		elif name.ends_with(".tmp") or (name == request_id + ".result.json" and not present.has(request_id + ".claim.json")):
			# Interrupted atomic writes and results whose claim is already gone.
			if budget > 0 and not _active_request_ids.has(request_id) and _older_than_retention(directory_abs.path_join(name), 0.0, now):
				if _remove_file(directory_abs.path_join(name)):
					budget -= 1
	for dir_name in access.get_directories():
		var name := str(dir_name)
		var request_id := name.trim_suffix(".lock").to_lower()
		if name != request_id + ".lock" or not valid_uuid(request_id) or present.has(request_id + ".claim.json"):
			continue
		var lock_path := _path(request_id, ".lock")
		if not DirAccess.dir_exists_absolute(lock_path):
			continue
		# A lock without a claim is a claim that never published. Once past
		# retention its request can no longer start, so the lock is dropped.
		if budget > 0 and not _active_request_ids.has(request_id) and _older_than_retention(lock_path, 0.0, now) and _safe(lock_path) and DirAccess.remove_absolute(lock_path) == OK:
			budget -= 1
			continue
		count += 1
	_entry_count = count
	return true


func _entry_is_expired(request_id: String, now: float) -> bool:
	if _active_request_ids.has(request_id):
		return false
	var claim_path := _path(request_id, ".claim.json")
	var result_path := _path(request_id, ".result.json")
	var recorded := 0.0
	var claim := _read(claim_path)
	if bool(claim.get("ok", false)):
		recorded = maxf(recorded, float(claim.get("claimed_unix", 0.0)))
	if FileAccess.file_exists(result_path):
		if not _older_than_retention(result_path, 0.0, now):
			return false
		var result := _read(result_path)
		if bool(result.get("ok", false)):
			recorded = maxf(recorded, float(result.get("completed_unix", 0.0)))
	return _older_than_retention(claim_path, recorded, now)


## True only when both the file mtime and any recorded timestamp are known and
## past retention. A future timestamp (clock moved back) keeps the entry.
func _older_than_retention(path: String, recorded_unix: float, now: float) -> bool:
	var modified := float(FileAccess.get_modified_time(path))
	if modified <= 0.0:
		return false
	return now - maxf(modified, recorded_unix) > PRUNE_AFTER_SECONDS


## Removes result, then claim, then lock. A partial failure leaves the claim
## (a replay is refused as outcome_unknown) or an orphan lock (pruned later).
func _remove_entry(request_id: String) -> bool:
	for suffix in [".result.json", ".claim.json"]:
		var path := _path(request_id, suffix)
		if FileAccess.file_exists(path) and not _remove_file(path):
			return false
	var lock_path := _path(request_id, ".lock")
	if DirAccess.dir_exists_absolute(lock_path) and _safe(lock_path):
		DirAccess.remove_absolute(lock_path)
	return true


func _remove_file(path: String) -> bool:
	return _safe(path) and DirAccess.remove_absolute(path) == OK


static func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "error": {"code": code, "message": message}}
