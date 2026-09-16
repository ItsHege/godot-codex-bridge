extends SceneTree

const ChatDiffModel := preload("res://addons/godot_codex_bridge/core/chat_diff_model.gd")

var _failures := 0


func _init() -> void:
	_run()
	if _failures == 0:
		print("Godot Codex Bridge addon core tests passed")
		quit(0)
	else:
		push_error("Godot Codex Bridge addon core tests failed: " + str(_failures))
		quit(1)


func _run() -> void:
	var file_changes := {
		"res://scripts/player.gd": {
			"type": "update",
			"unified_diff": "@@\n-old\n+new\n",
		},
		"scenes/Main.tscn": {
			"type": "add",
			"unified_diff": "@@\n+[node name=\"Main\" type=\"Node3D\"]\n",
		},
	}

	var diff_text := ChatDiffModel.diff_from_file_changes(file_changes)
	_assert_true(diff_text.find("diff --git a/res://scripts/player.gd b/res://scripts/player.gd") >= 0, "file change diff includes player header")
	_assert_true(diff_text.find("-old") >= 0, "file change diff includes removed line")
	_assert_true(diff_text.find("+new") >= 0, "file change diff includes added line")

	var event_diff := ChatDiffModel.diff_text_from_event_params({"file_changes": file_changes})
	_assert_eq(event_diff, diff_text, "event diff falls back to file_changes")
	_assert_eq(ChatDiffModel.diff_text_from_event_params({"diff_text": "@@\n-a\n+b"}), "@@\n-a\n+b", "event diff prefers diff_text")

	var parsed := ChatDiffModel.parse_diff_files(diff_text, 24, 360)
	_assert_eq(parsed.size(), 2, "parse produces two file sections")
	_assert_eq(str(parsed[0].get("path", "")), "res://scripts/player.gd", "parse first path")
	_assert_eq(int(parsed[0].get("added", 0)), 1, "parse added count")
	_assert_eq(int(parsed[0].get("removed", 0)), 1, "parse removed count")

	var truncated := ChatDiffModel.parse_diff_files(diff_text, 24, 2)
	_assert_eq(bool(truncated[0].get("truncated", false)), true, "parse marks truncated file sections")

	var files := ChatDiffModel.extract_diff_files(diff_text)
	_assert_eq(files.size(), 2, "extract two diff file paths")
	_assert_eq(files[0], "res://scripts/player.gd", "extract normalizes a/ b/ paths")

	_assert_eq(ChatDiffModel.normalize_diff_file_path("\"b/scenes/Main.tscn\""), "scenes/Main.tscn", "normalize quoted b path")
	_assert_eq(ChatDiffModel.normalize_diff_file_path("/dev/null"), "", "normalize dev null")
	_assert_eq(ChatDiffModel.diff_line_kind("+added"), "added", "added line kind")
	_assert_eq(ChatDiffModel.diff_line_kind("-removed"), "removed", "removed line kind")
	_assert_eq(ChatDiffModel.diff_line_kind("@@"), "hunk", "hunk line kind")
	_assert_eq(ChatDiffModel.diff_line_kind("+++ b/file.gd"), "file_header", "file header line kind")

	var summary := ChatDiffModel.file_changes_summary(file_changes, 1)
	_assert_true(summary.find("2 file(s), +2 -1") >= 0, "summary counts files and lines")
	_assert_true(summary.find("... 1 more") >= 0, "summary limits paths")

	var batch_summary := ChatDiffModel.batch_summary(3, parsed, 1)
	_assert_true(batch_summary.find("3 update(s), 2 file(s), +2 -1") >= 0, "batch summary counts updates files and lines")
	_assert_true(batch_summary.find("Show files") >= 0, "batch summary explains expandable files")
	_assert_eq(ChatDiffModel.batch_toggle_text(false, 2), "Show 2 files", "collapsed batch toggle text")
	_assert_eq(ChatDiffModel.batch_toggle_text(true, 2), "Hide files", "expanded batch toggle text")

	var overflow_fixture := ChatDiffModel.many_file_overflow_fixture(32, 3)
	var overflow_all_files := ChatDiffModel.extract_diff_files(overflow_fixture)
	_assert_eq(overflow_all_files.size(), 32, "overflow fixture contains all requested files")
	_assert_eq(overflow_all_files[0], "res://diff_overflow/file_00.gd", "overflow fixture first path")
	var overflow_parsed := ChatDiffModel.parse_diff_files(overflow_fixture, 24, 32)
	_assert_eq(overflow_parsed.size(), 24, "overflow fixture is capped by UI file limit")
	_assert_eq(str(overflow_parsed[23].get("path", "")), "res://diff_overflow/file_23.gd", "overflow fixture last rendered path")
	_assert_eq(int(overflow_parsed[0].get("added", 0)), 3, "overflow fixture counts added lines")
	_assert_eq(int(overflow_parsed[0].get("removed", 0)), 3, "overflow fixture counts removed lines")


func _assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures += 1
		push_error(label + " expected=" + str(expected) + " actual=" + str(actual))


func _assert_true(value: bool, label: String) -> void:
	if not value:
		_failures += 1
		push_error(label)
