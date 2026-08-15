extends "res://tests/support/test_case.gd"

const WRITER_PATH := "res://tools/notion_sync/dialogue_snapshot_writer.gd"

var _failure_stage := ""
var _test_root := ""

func run() -> void:
	_test_root = "user://test-output/snapshot-writer-%s" % Time.get_ticks_usec()
	assert_true(_test_root.begins_with("user://test-output/snapshot-writer-"), "snapshot test root is uniquely confined")
	assert_true(ResourceLoader.exists(WRITER_PATH, "Script"), "dialogue snapshot writer script exists")
	if not ResourceLoader.exists(WRITER_PATH, "Script"):
		return
	var writer_script: Variant = load(WRITER_PATH)
	assert_not_null(writer_script, "dialogue snapshot writer loads")
	if writer_script == null:
		return
	_test_successful_atomic_replacement(writer_script)
	for stage: String in ["write", "verify", "backup_swap", "publish_swap"]:
		_test_failure_preserves_previous_bytes(writer_script, stage)
	_cleanup_exact_test_root()

func _test_successful_atomic_replacement(writer_script: Variant) -> void:
	_cleanup_exact_test_root()
	var output_dir := _test_root.path_join("dialogues")
	assert_eq(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir)), OK, "previous snapshot directory is created")
	_write_bytes(output_dir.path_join("stale.json"), "old snapshot".to_utf8_buffer())
	var payload := _payload()
	var writer: Variant = writer_script.new()
	var result: Error = writer.replace_snapshot(output_dir, payload["graphs"], payload["manifest"])
	assert_eq(result, OK, "valid snapshot replaces the previous directory")
	assert_false(FileAccess.file_exists(output_dir.path_join("stale.json")), "successful replacement removes stale generated files")
	assert_true(FileAccess.file_exists(output_dir.path_join("foundation_inspect.json")), "successful replacement publishes the graph")
	assert_true(FileAccess.file_exists(output_dir.path_join("manifest.json")), "successful replacement publishes the manifest")
	assert_false(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output_dir + ".tmp")), "successful replacement removes the exact temporary sibling")
	assert_false(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output_dir + ".bak")), "successful replacement removes the exact backup sibling")
	var published := FileAccess.get_file_as_string(output_dir.path_join("foundation_inspect.json"))
	assert_eq(published.sha256_text(), payload["manifest"]["files"]["foundation_inspect.json"], "published graph bytes match the manifest hash")

func _test_failure_preserves_previous_bytes(writer_script: Variant, stage: String) -> void:
	_cleanup_exact_test_root()
	var output_dir := _test_root.path_join("dialogues")
	assert_eq(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir.path_join("nested"))), OK, "%s previous snapshot directory is created" % stage)
	_write_bytes(output_dir.path_join("old.json"), ("old snapshot " + stage).to_utf8_buffer())
	_write_bytes(output_dir.path_join("nested/bytes.bin"), PackedByteArray([0, 1, 2, 255]))
	var before := _snapshot_bytes(output_dir)
	_failure_stage = stage
	var writer: Variant = writer_script.new(Callable(self, "_operation_guard"))
	var payload := _payload()
	var result: Error = writer.replace_snapshot(output_dir, payload["graphs"], payload["manifest"])
	_failure_stage = ""
	assert_true(result != OK, "%s failure is returned" % stage)
	assert_eq(_snapshot_bytes(output_dir), before, "%s failure preserves the previous snapshot byte-for-byte" % stage)
	assert_false(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output_dir + ".tmp")), "%s failure removes only the exact temporary sibling" % stage)
	if stage == "publish_swap":
		assert_true(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output_dir + ".bak")), "publish failure retains the previous backup after restoring current output")

func _operation_guard(stage: String, _path: String) -> Error:
	return ERR_CANT_CREATE if stage == _failure_stage else OK

func _payload() -> Dictionary:
	var graph := {
		"schema_version":1,
		"scene_key":"foundation.inspect",
		"entry_node":"end1",
		"nodes":{"end1":{"type":"end"}}
	}
	var graph_json := JSON.stringify(graph, "\t", true, true)
	return {
		"graphs":{"foundation.inspect":graph},
		"manifest":{
			"schema_version":1,
			"generated_at":"2026-08-16T00:00:00Z",
			"sources":[],
			"files":{"foundation_inspect.json":graph_json.sha256_text()},
			"scenes":["foundation.inspect"]
		}
	}

func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file, "test fixture file opens: %s" % path)
	if file == null:
		return
	file.store_buffer(bytes)
	file.close()

func _snapshot_bytes(path: String) -> Dictionary:
	var result := {}
	_capture_directory(path, "", result)
	return result

func _capture_directory(root: String, relative: String, result: Dictionary) -> void:
	var current := root if relative.is_empty() else root.path_join(relative)
	var directory := DirAccess.open(current)
	if directory == null:
		return
	var directories := directory.get_directories()
	directories.sort()
	for child_dir: String in directories:
		var child_relative := child_dir if relative.is_empty() else relative.path_join(child_dir)
		_capture_directory(root, child_relative, result)
	var files := directory.get_files()
	files.sort()
	for filename: String in files:
		var file_relative := filename if relative.is_empty() else relative.path_join(filename)
		result[file_relative] = FileAccess.get_file_as_bytes(root.path_join(file_relative))

func _cleanup_exact_test_root() -> void:
	if _test_root.is_empty() or not _test_root.begins_with("user://test-output/snapshot-writer-"):
		return
	_remove_tree(_test_root)

func _remove_tree(path: String) -> Error:
	var absolute := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return OK
	var directory := DirAccess.open(path)
	if directory == null:
		return DirAccess.get_open_error()
	for child_dir: String in directory.get_directories():
		var error := _remove_tree(path.path_join(child_dir))
		if error != OK:
			return error
	for filename: String in directory.get_files():
		var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path.path_join(filename)))
		if remove_error != OK:
			return remove_error
	return DirAccess.remove_absolute(absolute)
