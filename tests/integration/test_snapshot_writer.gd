extends "res://tests/support/test_case.gd"

const WRITER_PATH := "res://tools/notion_sync/dialogue_snapshot_writer.gd"

var _scenario := ""
var _test_root := ""
var _observer_error: Error = OK

func run() -> void:
	_test_root = "user://test-output/snapshot-writer-%s" % Time.get_ticks_usec()
	assert_true(_test_root.begins_with("user://test-output/snapshot-writer-"), "snapshot test root is uniquely confined")
	var writer_script: Variant = load(WRITER_PATH)
	assert_not_null(writer_script, "dialogue snapshot writer loads")
	if writer_script == null:
		return
	_test_successful_atomic_replacement(writer_script)
	_test_actual_partial_write_failure(writer_script)
	_test_actual_corrupt_reread_failure(writer_script)
	_test_actual_backup_rename_failure(writer_script)
	_test_actual_publish_failure_rolls_back_by_rename(writer_script)
	_test_actual_rollback_failure_preserves_backup(writer_script)
	_test_final_backup_retention_failure_preserves_verified_recovery(writer_script)
	_test_actual_backup_cleanup_failure_is_committed(writer_script)
	_test_empty_payload_fails_closed(writer_script)
	_test_unsafe_scene_names_fail_closed(writer_script)
	_cleanup_exact_test_root()

func _test_successful_atomic_replacement(writer_script: Variant) -> void:
	var state := _setup_previous("success")
	var writer: Variant = writer_script.new()
	var payload := _payload()
	var result: Error = writer.replace_snapshot(state["output"], payload["graphs"], payload["manifest"])
	assert_eq(result, OK, "valid snapshot replaces the previous directory")
	assert_eq(_snapshot_bytes(state["output"]), _payload_bytes(payload), "successful replacement publishes exact verified bytes")
	assert_eq(_snapshot_bytes(state["backup"]), {}, "successful replacement removes the backup sibling")
	assert_eq(_snapshot_bytes(state["temporary"]), {}, "successful replacement removes the temporary sibling")

func _test_actual_partial_write_failure(writer_script: Variant) -> void:
	var state := _setup_previous("partial-write")
	_scenario = "partial_write"
	var writer: Variant = writer_script.new(Callable(self, "_transaction_observer"))
	var payload := _payload()
	var result: Error = writer.replace_snapshot(state["output"], payload["graphs"], payload["manifest"])
	_scenario = ""
	assert_true(result != OK, "actual manifest-file open failure is returned")
	assert_eq(_snapshot_bytes(state["output"]), state["before"], "partial write failure preserves current bytes")
	assert_eq(_snapshot_bytes(state["backup"]), {}, "partial write failure never creates a backup")
	assert_eq(_snapshot_bytes(state["temporary"]), {}, "partial write failure cleans the exact temporary sibling")

func _test_actual_corrupt_reread_failure(writer_script: Variant) -> void:
	var state := _setup_previous("corrupt-reread")
	_scenario = "corrupt_reread"
	var writer: Variant = writer_script.new(Callable(self, "_transaction_observer"))
	var payload := _payload()
	var result: Error = writer.replace_snapshot(state["output"], payload["graphs"], payload["manifest"])
	_scenario = ""
	assert_eq(result, ERR_FILE_CORRUPT, "actual on-disk corruption is detected during reread hashing")
	assert_eq(_snapshot_bytes(state["output"]), state["before"], "verification failure preserves current bytes")
	assert_eq(_snapshot_bytes(state["backup"]), {}, "verification failure never creates a backup")
	assert_eq(_snapshot_bytes(state["temporary"]), {}, "verification failure cleans the exact temporary sibling")

func _test_actual_backup_rename_failure(writer_script: Variant) -> void:
	var state := _setup_previous("backup-rename")
	_scenario = "backup_rename"
	var writer: Variant = writer_script.new(Callable(self, "_transaction_observer"))
	var payload := _payload()
	var result: Error = writer.replace_snapshot(state["output"], payload["graphs"], payload["manifest"])
	_scenario = ""
	assert_true(result != OK, "actual current-to-backup rename failure is returned")
	assert_eq(_snapshot_bytes(state["output"]), state["before"], "backup rename failure preserves current bytes")
	assert_eq(_snapshot_bytes(state["backup"]), {"obstruction.txt":"backup obstruction".to_utf8_buffer()}, "backup rename failure preserves the actual obstruction")
	assert_eq(_snapshot_bytes(state["temporary"]), {}, "backup rename failure cleans the exact temporary sibling")

func _test_actual_publish_failure_rolls_back_by_rename(writer_script: Variant) -> void:
	var state := _setup_previous("publish-rollback")
	_scenario = "publish_then_fail"
	var writer: Variant = writer_script.new(Callable(self, "_transaction_observer"))
	var payload := _payload()
	var result: Error = writer.replace_snapshot(state["output"], payload["graphs"], payload["manifest"])
	_scenario = ""
	assert_true(result != OK, "actual missing-temp publish primitive failure is returned after rollback")
	assert_eq(_snapshot_bytes(state["output"]), state["before"], "rename rollback restores exact old current bytes")
	assert_eq(_snapshot_bytes(state["backup"]), state["before"], "successful rollback retains an exact backup as the literal error contract requires")
	assert_eq(_snapshot_bytes(state["temporary"]), {}, "successful rename rollback removes the failed new snapshot")

func _test_actual_rollback_failure_preserves_backup(writer_script: Variant) -> void:
	var state := _setup_previous("rollback-failure")
	_scenario = "rollback_obstruction"
	var writer: Variant = writer_script.new(Callable(self, "_transaction_observer"))
	var payload := _payload()
	var result: Error = writer.replace_snapshot(state["output"], payload["graphs"], payload["manifest"])
	_scenario = ""
	assert_eq(result, ERR_CANT_RESOLVE, "rollback primitive failure returns the distinct recovery error")
	assert_eq(_snapshot_bytes(state["output"]), {"obstruction.txt":"external obstruction".to_utf8_buffer()}, "rollback failure does not delete the current-path obstruction")
	assert_eq(_snapshot_bytes(state["backup"]), state["before"], "rollback failure preserves the intact old backup byte-for-byte")
	assert_eq(_snapshot_bytes(String(state["temporary"]).path_join("recovery")), state["before"], "rollback failure preserves the verified recovery copy")
	var recovery: Dictionary = writer.last_recovery
	assert_eq(recovery.get("recovery_path", ""), ProjectSettings.globalize_path(String(state["temporary"]).path_join("recovery")), "rollback failure identifies the verified recovery path")
	assert_true(bool(recovery.get("recoverable", false)), "verified recovery bytes make rollback failure actionable")

func _test_final_backup_retention_failure_preserves_verified_recovery(writer_script: Variant) -> void:
	var state := _setup_previous("retain-backup-failure")
	_scenario = "retain_backup_obstruction"
	_observer_error = OK
	var writer: Variant = writer_script.new(Callable(self, "_transaction_observer"))
	var payload := _payload()
	var result: Error = writer.replace_snapshot(state["output"], payload["graphs"], payload["manifest"])
	_scenario = ""
	assert_eq(_observer_error, OK, "actual unrelated backup obstruction is created after current restoration")
	assert_eq(result, ERR_CANT_RESOLVE, "final recovery-to-backup rename failure returns the distinct rollback error")
	assert_eq(_snapshot_bytes(state["output"]), state["before"], "final rollback step failure leaves exact old current bytes restored")
	assert_eq(_snapshot_bytes(state["backup"]), {"obstruction.txt":"unrelated backup obstruction".to_utf8_buffer()}, "unrelated backup obstruction remains untouched")
	var recovery_path := String(state["temporary"]).path_join("recovery")
	assert_eq(_snapshot_bytes(recovery_path), state["before"], "final rollback step failure preserves exact verified recovery bytes")
	var recovery: Dictionary = writer.last_recovery
	assert_eq(recovery.get("recovery_path", ""), ProjectSettings.globalize_path(recovery_path), "failure state points to the verified recovery copy, not unrelated backup")
	assert_true(bool(recovery.get("recoverable", false)), "verified recovery path is actionable")
	assert_false(bool(recovery.get("backup_recoverable", true)), "unrelated backup obstruction is explicitly non-recoverable")
	assert_true(recovery.get("recovery_path", "") != recovery.get("backup_path", ""), "unrelated backup obstruction is never labeled as the recoverable artifact")

func _test_actual_backup_cleanup_failure_is_committed(writer_script: Variant) -> void:
	var state := _setup_previous("cleanup-failure")
	_write_raw(String(state["output"]).path_join("a-old.json"), "deleted first".to_utf8_buffer())
	_write_raw(String(state["output"]).path_join("m-old.json"), "read only middle".to_utf8_buffer())
	_write_raw(String(state["output"]).path_join("z-old.json"), "retained last".to_utf8_buffer())
	state["before"] = _snapshot_bytes(state["output"])
	_scenario = "cleanup_mid_order"
	_observer_error = OK
	var writer: Variant = writer_script.new(Callable(self, "_transaction_observer"))
	var payload := _payload()
	var result: Error = writer.replace_snapshot(state["output"], payload["graphs"], payload["manifest"])
	_scenario = ""
	assert_eq(_observer_error, OK, "cleanup failure fixture makes the actual backup file read-only")
	assert_eq(result, OK, "a valid committed output is not reported as an import failure when backup cleanup fails")
	assert_eq(_snapshot_bytes(state["output"]), _payload_bytes(payload), "cleanup failure leaves the committed output current")
	var residue := _snapshot_bytes(state["backup"])
	assert_false(residue.has("a-old.json"), "mid-order cleanup proves an earlier backup file was actually deleted")
	assert_true(residue.has("m-old.json") and residue.has("old.json") and residue.has("z-old.json"), "mid-order cleanup leaves a deterministic partial residue")
	var recovery: Variant = writer.get("last_recovery")
	assert_true(typeof(recovery) == TYPE_DICTIONARY and recovery.get("code", "") == "backup_cleanup_residue", "cleanup failure names the artifact as residue, not a recovery backup")
	assert_false(bool(recovery.get("recoverable", true)), "partial cleanup residue is never advertised as recoverable")
	var retry_writer: Variant = writer_script.new()
	assert_eq(retry_writer.replace_snapshot(state["output"], payload["graphs"], payload["manifest"]), ERR_ALREADY_EXISTS, "retained backup makes future replacement deterministic")
	assert_eq(retry_writer.last_recovery.get("code", ""), "backup_artifact_present", "future replacement truthfully reports a generic blocking artifact")
	assert_false(bool(retry_writer.last_recovery.get("recoverable", true)), "future process does not guess that a stale artifact is recoverable")
	_set_tree_read_only(state["backup"], false)

func _test_empty_payload_fails_closed(writer_script: Variant) -> void:
	var state := _setup_previous("empty-payload")
	var writer: Variant = writer_script.new()
	var manifest := {"schema_version":1, "generated_at":"2026-08-16T00:00:00Z", "sources":[], "files":{}, "scenes":[]}
	var result: Error = writer.replace_snapshot(state["output"], {}, manifest)
	assert_eq(result, ERR_INVALID_DATA, "writer rejects a manifest-only empty snapshot")
	assert_eq(_snapshot_bytes(state["output"]), state["before"], "empty writer payload preserves the current snapshot byte-for-byte")
	assert_eq(_snapshot_bytes(state["backup"]), {}, "empty writer payload creates no backup")
	assert_eq(_snapshot_bytes(state["temporary"]), {}, "empty writer payload creates no temporary transaction")

func _test_unsafe_scene_names_fail_closed(writer_script: Variant) -> void:
	for scene_key: String in ["manifest", "CON", "bad:name"]:
		var state := _setup_previous("unsafe-" + scene_key.replace(":", "_"))
		var writer: Variant = writer_script.new()
		var payload := _payload_for_scenes([scene_key])
		assert_eq(writer.replace_snapshot(state["output"], payload["graphs"], payload["manifest"]), ERR_INVALID_PARAMETER, "writer rejects unsafe scene key %s" % scene_key)
		assert_eq(_snapshot_bytes(state["output"]), state["before"], "unsafe scene key %s preserves current bytes" % scene_key)
		assert_eq(_snapshot_bytes(state["temporary"]), {}, "unsafe scene key %s creates no temporary sibling" % scene_key)
	var collision_state := _setup_previous("writer-collision")
	var collision_payload := _payload_for_scenes(["a.b", "a_b"])
	assert_eq(writer_script.new().replace_snapshot(collision_state["output"], collision_payload["graphs"], collision_payload["manifest"]), ERR_ALREADY_EXISTS, "writer rejects cross-platform filename collisions")
	assert_eq(_snapshot_bytes(collision_state["output"]), collision_state["before"], "filename collision preserves current bytes")

func _transaction_observer(stage: String, paths_value: Variant) -> void:
	if typeof(paths_value) != TYPE_DICTIONARY:
		return
	var paths: Dictionary = paths_value
	var publish_path := String(paths.get("publish", paths["temporary"]))
	match _scenario:
		"partial_write":
			if stage == "before_write":
				_observer_error = DirAccess.make_dir_recursive_absolute(publish_path.path_join("manifest.json"))
		"corrupt_reread":
			if stage == "after_write":
				_write_raw(publish_path.path_join("foundation_inspect.json"), "corrupt".to_utf8_buffer())
		"backup_rename":
			if stage == "before_backup_rename":
				_observer_error = DirAccess.make_dir_recursive_absolute(String(paths["backup"]))
				_write_raw(String(paths["backup"]).path_join("obstruction.txt"), "backup obstruction".to_utf8_buffer())
		"publish_then_fail":
			if stage == "before_publish_rename":
				_observer_error = DirAccess.rename_absolute(publish_path, String(paths["output"]))
		"rollback_obstruction":
			if stage == "before_publish_rename":
				_observer_error = DirAccess.make_dir_recursive_absolute(String(paths["output"]))
				_write_raw(String(paths["output"]).path_join("obstruction.txt"), "external obstruction".to_utf8_buffer())
		"retain_backup_obstruction":
			if stage == "before_publish_rename":
				_observer_error = DirAccess.rename_absolute(publish_path, String(paths["output"]))
			elif stage == "before_retain_backup_rename":
				_observer_error = DirAccess.make_dir_recursive_absolute(String(paths["backup"]))
				_write_raw(String(paths["backup"]).path_join("obstruction.txt"), "unrelated backup obstruction".to_utf8_buffer())
		"cleanup_mid_order":
			if stage == "before_backup_cleanup":
				_observer_error = FileAccess.set_read_only_attribute(String(paths["backup"]).path_join("m-old.json"), true)

func _setup_previous(label: String) -> Dictionary:
	_cleanup_exact_test_root()
	var output := _test_root.path_join("dialogues")
	assert_eq(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.path_join("nested"))), OK, "%s previous snapshot directory is created" % label)
	_write_raw(output.path_join("old.json"), ("old snapshot " + label).to_utf8_buffer())
	_write_raw(output.path_join("nested/bytes.bin"), PackedByteArray([0, 1, 2, 255]))
	return {"output":output, "temporary":output + ".tmp", "backup":output + ".bak", "before":_snapshot_bytes(output)}

func _payload() -> Dictionary:
	return _payload_for_scenes(["foundation.inspect"])

func _payload_for_scenes(scene_keys: Array) -> Dictionary:
	var graphs := {}
	var files := {}
	var sorted_scene_keys: Array = scene_keys.duplicate()
	sorted_scene_keys.sort()
	for scene_key_value: Variant in sorted_scene_keys:
		var scene_key := String(scene_key_value)
		var graph := {"schema_version":1, "scene_key":scene_key, "entry_node":"end1", "nodes":{"end1":{"type":"end"}}}
		graphs[scene_key] = graph
		files[scene_key.replace(".", "_") + ".json"] = JSON.stringify(graph, "\t", true, true).sha256_text()
	return {"graphs":graphs, "manifest":{"schema_version":1, "generated_at":"2026-08-16T00:00:00Z", "sources":[], "files":files, "scenes":sorted_scene_keys}}

func _payload_bytes(payload: Dictionary) -> Dictionary:
	var result := {"manifest.json":JSON.stringify(payload["manifest"], "\t", true, true).to_utf8_buffer()}
	for scene_key_value: Variant in payload["graphs"]:
		var scene_key := String(scene_key_value)
		result[scene_key.replace(".", "_") + ".json"] = JSON.stringify(payload["graphs"][scene_key], "\t", true, true).to_utf8_buffer()
	return result

func _write_raw(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file, "test fixture file opens: %s" % path)
	if file != null:
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

func _set_tree_read_only(path: String, read_only: bool) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for child_dir: String in directory.get_directories():
		_set_tree_read_only(path.path_join(child_dir), read_only)
	for filename: String in directory.get_files():
		FileAccess.set_read_only_attribute(path.path_join(filename), read_only)

func _cleanup_exact_test_root() -> void:
	if _test_root.is_empty() or not _test_root.begins_with("user://test-output/snapshot-writer-"):
		return
	_set_tree_read_only(_test_root, false)
	_remove_tree(_test_root)

func _remove_tree(path: String) -> Error:
	var absolute := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(absolute):
		FileAccess.set_read_only_attribute(absolute, false)
		return DirAccess.remove_absolute(absolute)
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
		var file_path := ProjectSettings.globalize_path(path.path_join(filename))
		FileAccess.set_read_only_attribute(file_path, false)
		var remove_error := DirAccess.remove_absolute(file_path)
		if remove_error != OK:
			return remove_error
	return DirAccess.remove_absolute(absolute)
