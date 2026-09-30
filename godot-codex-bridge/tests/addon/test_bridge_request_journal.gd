extends SceneTree

const Journal := preload("res://addons/godot_codex_bridge/core/bridge_request_journal.gd")

var failures := 0


func _initialize() -> void:
	var directory := ProjectSettings.globalize_path("res://.godot/godot_codex_bridge/journal_test_" + str(Time.get_ticks_usec()))
	DirAccess.make_dir_recursive_absolute(directory)
	var journal := Journal.new(directory, Callable(self, "_validate_path"))
	var request_id := "123e4567-e89b-42d3-a456-426614174000"
	var now := int(Time.get_unix_time_from_system())
	var request := {"request_id": request_id, "type": "test", "created_at": Time.get_datetime_string_from_unix_time(now), "deadline_at": Time.get_datetime_string_from_unix_time(now + 60), "payload": {"b": 2, "a": 1}}
	_check(str(journal.begin(request).get("state", "")) == "claimed", "first claim")
	_check(str(journal.begin(request).get("error", {}).get("code", "")) == "outcome_unknown", "unfinished retry refused")
	var different := request.duplicate(true)
	different["payload"] = {"a": 3}
	_check(str(journal.begin(different).get("error", {}).get("code", "")) == "request_id_conflict", "changed body refused")
	var response := {"request_id": request_id, "status": "completed", "data": {"count": 1}}
	_check(bool(journal.complete(request_id, response).get("ok", false)), "result recorded")
	var replay := journal.begin(request)
	var replay_response: Dictionary = replay.get("response", {})
	_check(str(replay.get("state", "")) == "completed" and str(replay_response.get("request_id", "")) == request_id and int((replay_response.get("data", {}) as Dictionary).get("count", 0)) == 1, "completed retry replays")
	var stale := {"request_id": "123e4567-e89b-42d3-a456-426614174001", "type": "test", "created_at": "2020-01-01T00:00:00Z", "deadline_at": "2020-01-01T00:01:00Z", "payload": {}}
	_check(str(journal.begin(stale).get("error", {}).get("code", "")) == "stale_request", "stale new request refused")
	var short_request := {"request_id": "123e4567-e89b-42d3-a456-426614174003", "type": "test", "created_at": Time.get_datetime_string_from_unix_time(now) + ".000Z", "deadline_at": Time.get_datetime_string_from_unix_time(now + 1) + ".900Z", "payload": {}}
	_check(str(journal.begin(short_request).get("state", "")) == "claimed", "subsecond timestamp accepted")
	_check(absf(Journal._iso_unix("2026-09-29T12:00:00.900Z") - Journal._iso_unix("2026-09-29T12:00:00.100Z") - 0.8) < 0.001, "subsecond deadline order retained")
	_check(str(journal.begin({"request_id": "bad", "created_at": request.created_at}).get("error", {}).get("code", "")) == "invalid_request_id", "invalid ID refused")
	var interrupted_id := "123e4567-e89b-42d3-a456-426614174002"
	var interrupted := request.duplicate(true)
	interrupted["request_id"] = interrupted_id
	_check(str(journal.begin(interrupted).get("state", "")) == "claimed", "interrupted claim starts")
	var after_restart := Journal.new(directory, Callable(self, "_validate_path"))
	_check(str(after_restart.begin(interrupted).get("error", {}).get("code", "")) == "outcome_unknown", "restart refuses unfinished action")
	_check(Journal.canonical_json({"b": 2, "a": {"z": 1, "x": 3}}) == Journal.canonical_json({"a": {"x": 3, "z": 1}, "b": 2}), "canonical key order")
	DirAccess.remove_absolute(directory.path_join(request_id + ".claim.json"))
	DirAccess.remove_absolute(directory.path_join(request_id + ".result.json"))
	DirAccess.remove_absolute(directory.path_join(interrupted_id + ".claim.json"))
	DirAccess.remove_absolute(directory.path_join("123e4567-e89b-42d3-a456-426614174003.claim.json"))
	DirAccess.remove_absolute(directory.path_join(request_id + ".lock"))
	DirAccess.remove_absolute(directory.path_join(interrupted_id + ".lock"))
	DirAccess.remove_absolute(directory.path_join("123e4567-e89b-42d3-a456-426614174003.lock"))
	DirAccess.remove_absolute(directory)
	_test_retention()
	_test_cap_recovers()
	print("bridge request journal failures: ", failures)
	quit(1 if failures > 0 else 0)


var fake_now := 0.0


func _fake_now() -> float:
	return fake_now


func _request_at(request_id: String, created_unix: float, payload: Dictionary = {}) -> Dictionary:
	return {"request_id": request_id, "type": "test", "created_at": Time.get_datetime_string_from_unix_time(int(created_unix)), "deadline_at": Time.get_datetime_string_from_unix_time(int(created_unix) + 60), "payload": payload}


func _new_dir(label: String) -> String:
	var directory := ProjectSettings.globalize_path("res://.godot/godot_codex_bridge/journal_" + label + "_" + str(Time.get_ticks_usec()))
	DirAccess.make_dir_recursive_absolute(directory)
	return directory


func _test_retention() -> void:
	fake_now = floorf(Time.get_unix_time_from_system())
	var directory := _new_dir("retention")
	var journal := Journal.new(directory, Callable(self, "_validate_path"))
	journal.clock = Callable(self, "_fake_now")
	var other_editor := Journal.new(directory, Callable(self, "_validate_path"))
	other_editor.clock = Callable(self, "_fake_now")
	var done_id := "223e4567-e89b-42d3-a456-426614174000"
	var unfinished_id := "223e4567-e89b-42d3-a456-426614174001"
	var active_id := "223e4567-e89b-42d3-a456-426614174002"
	var orphan_lock_id := "223e4567-e89b-42d3-a456-426614174003"
	var done := _request_at(done_id, fake_now, {"x": 1})
	var unfinished := _request_at(unfinished_id, fake_now)
	var active := _request_at(active_id, fake_now)
	_check(str(journal.begin(done).get("state", "")) == "claimed", "retention: claim")
	_check(bool(journal.complete(done_id, {"request_id": done_id, "status": "completed"}).get("ok", false)), "retention: complete")
	_check(str(other_editor.begin(unfinished).get("state", "")) == "claimed", "retention: other editor claim")
	_check(str(journal.begin(active).get("state", "")) == "claimed", "retention: active claim")
	DirAccess.make_dir_absolute(directory.path_join(orphan_lock_id + ".lock"))
	var tmp_path := directory.path_join(orphan_lock_id + ".claim.json.1.tmp")
	var tmp := FileAccess.open(tmp_path, FileAccess.WRITE)
	tmp.store_string("{}")
	tmp.close()
	# Inside retention: a fresh completed entry survives a maintenance pass and replays.
	fake_now += 120.0
	_check(str(journal.begin(_request_at("223e4567-e89b-42d3-a456-426614174010", fake_now)).get("state", "")) == "claimed", "retention: fresh request claims")
	_check(str(journal.begin(done).get("state", "")) == "completed", "retention: fresh completed entry still replays")
	_check(FileAccess.file_exists(directory.path_join(done_id + ".claim.json")), "retention: fresh claim kept")
	_check(DirAccess.dir_exists_absolute(directory.path_join(orphan_lock_id + ".lock")), "retention: fresh orphan lock kept")
	# Past retention: old entries are pruned, but never re-executed.
	fake_now += Journal.PRUNE_AFTER_SECONDS + 60.0
	_check(str(journal.begin(_request_at("223e4567-e89b-42d3-a456-426614174011", fake_now)).get("state", "")) == "claimed", "retention: later request claims")
	_check(not FileAccess.file_exists(directory.path_join(done_id + ".claim.json")), "retention: old claim pruned")
	_check(not FileAccess.file_exists(directory.path_join(done_id + ".result.json")), "retention: old result pruned")
	_check(not DirAccess.dir_exists_absolute(directory.path_join(done_id + ".lock")), "retention: old lock pruned")
	_check(not FileAccess.file_exists(directory.path_join(unfinished_id + ".claim.json")), "retention: expired unfinished claim pruned")
	_check(not DirAccess.dir_exists_absolute(directory.path_join(orphan_lock_id + ".lock")), "retention: old orphan lock pruned")
	_check(not FileAccess.file_exists(tmp_path), "retention: old temporary file pruned")
	_check(FileAccess.file_exists(directory.path_join(active_id + ".claim.json")), "retention: claim still running here kept")
	_check(str(journal.begin(done).get("error", {}).get("code", "")) == "stale_request", "retention: pruned completed request refused as stale")
	_check(str(other_editor.begin(unfinished).get("error", {}).get("code", "")) == "stale_request", "retention: pruned unfinished request refused as stale")
	_check(str(journal.begin(active).get("error", {}).get("code", "")) == "outcome_unknown", "retention: running claim still refuses replay")
	_check(bool(journal.complete(active_id, {"request_id": active_id, "status": "completed"}).get("ok", false)), "retention: running claim completes")
	_remove_tree(directory)


func _test_cap_recovers() -> void:
	fake_now = floorf(Time.get_unix_time_from_system())
	var directory := _new_dir("cap")
	var journal := Journal.new(directory, Callable(self, "_validate_path"))
	journal.clock = Callable(self, "_fake_now")
	journal.max_claims = 2
	var ids := ["323e4567-e89b-42d3-a456-426614174000", "323e4567-e89b-42d3-a456-426614174001", "323e4567-e89b-42d3-a456-426614174002", "323e4567-e89b-42d3-a456-426614174003"]
	for index in range(2):
		_check(str(journal.begin(_request_at(ids[index], fake_now)).get("state", "")) == "claimed", "cap: claim " + str(index))
		journal.complete(ids[index], {"request_id": ids[index], "status": "completed"})
	_check(str(journal.begin(_request_at(ids[2], fake_now)).get("error", {}).get("code", "")) == "journal_full", "cap: full journal fails closed")
	fake_now += Journal.PRUNE_AFTER_SECONDS + 60.0
	_check(str(journal.begin(_request_at(ids[3], fake_now)).get("state", "")) == "claimed", "cap: journal recovers after retention")
	_remove_tree(directory)


func _remove_tree(directory: String) -> void:
	var access := DirAccess.open(directory)
	if access == null:
		return
	for name in access.get_files():
		DirAccess.remove_absolute(directory.path_join(name))
	for name in access.get_directories():
		DirAccess.remove_absolute(directory.path_join(name))
	DirAccess.remove_absolute(directory)


func _validate_path(_path: String, _allow_missing: bool) -> Dictionary:
	return {"ok": true}


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
