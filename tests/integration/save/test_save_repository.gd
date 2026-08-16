extends "res://tests/support/test_case.gd"

const REPOSITORY_PATH := "res://app/save/save_repository.gd"
const TEST_ROOT := "user://test-saves"

var _repository_script: Script
var _run_suffix := "%s_%s" % [OS.get_process_id(), Time.get_ticks_usec()]

func run() -> void:
	_repository_script = load(REPOSITORY_PATH) as Script
	assert_not_null(_repository_script, "SaveRepository script exists")
	if _repository_script == null:
		return
	_test_exact_slot_filenames()
	_test_first_write_and_overwrite()
	_test_temp_is_verified_before_rotation()
	_test_corrupt_current_preserves_valid_backup_on_write()
	_test_backup_recovery_for_corrupt_and_missing_current()
	_test_closed_failures_and_stale_temp()
	_test_metadata_is_read_only_and_recoverable()
	_test_injected_transaction_stage_failures()
	_test_candidates_are_bound_to_slot_and_intended_write()
	_test_injected_recovery_stage_failures()

func _test_exact_slot_filenames() -> void:
	for slot_id in [&"auto", &"slot_1", &"slot_2", &"slot_3", &"slot_4", &"slot_5"]:
		var repository: RefCounted = _new_repository("filenames_%s" % slot_id)
		assert_eq(repository.call("write_slot", slot_id, _snapshot(String(slot_id), 1.0)), OK, "%s writes successfully" % slot_id)
		assert_true(FileAccess.file_exists(_path(repository, "%s.json" % slot_id)), "%s resolves to its exact JSON filename" % slot_id)
		assert_false(FileAccess.file_exists(_path(repository, "%s.json.tmp" % slot_id)), "%s leaves no stale temp" % slot_id)
		_cleanup_case(repository)
	var invalid_repository: RefCounted = _new_repository("invalid_slots")
	for invalid in [&"", &"slot_0", &"slot_6", &"../slot_1", &"slot_1/other", &"slot_1.json", &"C:\\slot_1"]:
		assert_eq(invalid_repository.call("write_slot", invalid, _snapshot("slot_1", 1.0)), ERR_INVALID_PARAMETER, "path-like or unknown slot %s is rejected" % invalid)
		assert_false(invalid_repository.call("read_slot", invalid).get("ok", true), "invalid slot %s cannot be read" % invalid)
	_cleanup_case(invalid_repository)

func _test_first_write_and_overwrite() -> void:
	var repository: RefCounted = _new_repository("overwrite")
	assert_eq(repository.call("write_slot", &"slot_1", _snapshot("slot_1", 10.0)), OK, "first write publishes current")
	var first: Dictionary = repository.call("read_slot", &"slot_1")
	assert_true(first.get("ok", false), "first current reads")
	assert_eq(first.get("data", {}).get("meta", {}).get("play_time_seconds"), 10.0, "first payload round-trips")
	assert_eq(repository.call("write_slot", &"slot_1", _snapshot("slot_1", 20.0)), OK, "overwrite publishes new current")
	var current: Dictionary = repository.call("read_slot", &"slot_1")
	assert_eq(current.get("data", {}).get("meta", {}).get("play_time_seconds"), 20.0, "overwrite returns newest payload")
	var backup := _read_json_file(_path(repository, "slot_1.json.bak"))
	assert_eq(backup.get("meta", {}).get("play_time_seconds"), 10.0, "valid old current rotates to one backup")
	assert_true(_is_valid_file(_path(repository, "slot_1.json.bak")), "rotated backup remains byte-valid")
	_cleanup_case(repository)

func _test_temp_is_verified_before_rotation() -> void:
	var repository: RefCounted = _new_repository("temp_verification")
	assert_eq(repository.call("write_slot", &"slot_1", _snapshot("slot_1", 1.0)), OK, "seed current writes")
	repository.set("stage_observer", Callable(self, "_corrupt_temp_on_reread"))
	assert_eq(repository.call("write_slot", &"slot_1", _snapshot("slot_1", 2.0)), ERR_FILE_CORRUPT, "corrupt reread temp fails before rotation")
	repository.set("stage_observer", Callable())
	var retained: Dictionary = repository.call("read_slot", &"slot_1")
	assert_eq(retained.get("data", {}).get("meta", {}).get("play_time_seconds"), 1.0, "temp verification failure retains current")
	_cleanup_case(repository)

func _test_corrupt_current_preserves_valid_backup_on_write() -> void:
	var repository: RefCounted = _new_repository("preserve_backup")
	repository.call("write_slot", &"slot_1", _snapshot("slot_1", 1.0))
	repository.call("write_slot", &"slot_1", _snapshot("slot_1", 2.0))
	var backup_path := _path(repository, "slot_1.json.bak")
	var backup_before := FileAccess.get_file_as_bytes(backup_path)
	_write_text(_path(repository, "slot_1.json"), "{corrupt current")
	assert_eq(repository.call("write_slot", &"slot_1", _snapshot("slot_1", 3.0)), OK, "new current publishes beside the valid backup")
	assert_eq(FileAccess.get_file_as_bytes(backup_path), backup_before, "valid backup is left byte-for-byte untouched")
	assert_eq(repository.call("read_slot", &"slot_1").get("data", {}).get("meta", {}).get("play_time_seconds"), 3.0, "published current is the new snapshot")
	_cleanup_case(repository)

func _test_backup_recovery_for_corrupt_and_missing_current() -> void:
	var repository: RefCounted = _new_repository("recovery")
	repository.call("write_slot", &"slot_1", _snapshot("slot_1", 1.0))
	repository.call("write_slot", &"slot_1", _snapshot("slot_1", 2.0))
	var backup_path := _path(repository, "slot_1.json.bak")
	var backup_before := FileAccess.get_file_as_bytes(backup_path)
	_write_text(_path(repository, "slot_1.json"), "broken")
	var recovered: Dictionary = repository.call("read_slot", &"slot_1")
	assert_true(recovered.get("ok", false), "valid backup recovers a corrupt current")
	assert_true(recovered.get("recovered", false), "corrupt-current recovery is reported")
	assert_eq(recovered.get("data", {}).get("meta", {}).get("play_time_seconds"), 1.0, "recovery returns backup payload")
	assert_eq(recovered.get("diagnostic", {}).get("current", {}).get("reason"), "malformed_json", "recovery diagnostic preserves the corrupt-current reason")
	assert_false(recovered.get("diagnostic", {}).has("data"), "recovery diagnostic excludes save payloads")
	assert_eq(FileAccess.get_file_as_bytes(backup_path), backup_before, "recovery retains the original backup")
	assert_true(_is_valid_file(_path(repository, "slot_1.json")), "recovery publishes a verified current")
	DirAccess.remove_absolute(_path(repository, "slot_1.json"))
	var missing_recovered: Dictionary = repository.call("read_slot", &"slot_1")
	assert_true(missing_recovered.get("ok", false) and missing_recovered.get("recovered", false), "valid backup also recovers a missing current")
	assert_eq(FileAccess.get_file_as_bytes(backup_path), backup_before, "missing-current recovery retains backup")
	_cleanup_case(repository)

func _test_closed_failures_and_stale_temp() -> void:
	var repository: RefCounted = _new_repository("closed_corrupt")
	_write_text(_path(repository, "slot_1.json"), "not-json")
	_write_text(_path(repository, "slot_1.json.bak"), "also-not-json")
	var closed: Dictionary = repository.call("read_slot", &"slot_1")
	assert_false(closed.get("ok", true), "two corrupt copies fail closed")
	assert_eq(closed.get("data", {}), {}, "closed failure includes no save payload")
	assert_false(closed.get("diagnostic", {}).has("data"), "diagnostic excludes save payloads")
	_cleanup_case(repository)
	for case_data in [
		{"name": "malformed", "text": "{"},
		{"name": "array_root", "text": "[]"},
		{"name": "scalar_root", "text": "42"},
	]:
		var invalid_repository: RefCounted = _new_repository(case_data["name"])
		_write_text(_path(invalid_repository, "slot_1.json"), case_data["text"])
		assert_false(invalid_repository.call("read_slot", &"slot_1").get("ok", true), "%s root fails closed" % case_data["name"])
		_cleanup_case(invalid_repository)
	var mismatch_repository: RefCounted = _new_repository("checksum_mismatch")
	mismatch_repository.call("write_slot", &"slot_1", _snapshot("slot_1", 1.0))
	var mismatched := _read_json_file(_path(mismatch_repository, "slot_1.json"))
	mismatched["meta"]["play_time_seconds"] = 99.0
	_write_text(_path(mismatch_repository, "slot_1.json"), JSON.stringify(mismatched))
	assert_false(mismatch_repository.call("read_slot", &"slot_1").get("ok", true), "checksum mismatch fails closed")
	_cleanup_case(mismatch_repository)
	var stale_repository: RefCounted = _new_repository("stale_temp")
	_write_text(_path(stale_repository, "slot_1.json.tmp"), JSON.stringify(_snapshot("slot_1", 1.0)))
	assert_false(stale_repository.call("slot_exists", &"slot_1"), "stale temp is not a slot")
	assert_false(stale_repository.call("read_slot", &"slot_1").get("ok", true), "stale temp cannot be loaded")
	_cleanup_case(stale_repository)

func _test_metadata_is_read_only_and_recoverable() -> void:
	var repository: RefCounted = _new_repository("metadata")
	repository.call("write_slot", &"slot_1", _snapshot("slot_1", 1.0))
	repository.call("write_slot", &"slot_1", _snapshot("slot_1", 2.0))
	var current_path := _path(repository, "slot_1.json")
	_write_text(current_path, "corrupt-current")
	var current_before := FileAccess.get_file_as_bytes(current_path)
	var metadata: Dictionary = repository.call("read_metadata", &"slot_1")
	assert_eq(metadata.get("play_time_seconds"), 1.0, "metadata falls back to valid backup fields")
	assert_true(metadata.get("recoverable", false), "backup metadata advertises recoverability")
	assert_eq(FileAccess.get_file_as_bytes(current_path), current_before, "metadata read does not repair or mutate current")
	assert_false(FileAccess.file_exists(_path(repository, "slot_1.json.tmp")), "metadata read creates no temp")
	assert_true(repository.call("slot_exists", &"slot_1"), "slot exists when backup alone is valid")
	_cleanup_case(repository)

func _test_injected_transaction_stage_failures() -> void:
	var cases: Array[Dictionary] = [
		{"stage": &"write_temp", "seed_count": 1},
		{"stage": &"temp_reread", "seed_count": 1},
		{"stage": &"old_backup_cleanup", "seed_count": 2},
		{"stage": &"current_to_backup_rename", "seed_count": 2},
		{"stage": &"temp_to_current_rename", "seed_count": 1},
		{"stage": &"final_reread", "seed_count": 1},
	]
	for case_data in cases:
		var repository: RefCounted = _new_repository("failure_%s" % case_data["stage"])
		for seed_index in range(case_data["seed_count"]):
			assert_eq(repository.call("write_slot", &"slot_1", _snapshot("slot_1", float(seed_index + 1))), OK, "seed for %s writes" % case_data["stage"])
		var observed: Array[StringName] = []
		repository.set("stage_observer", Callable(self, "_fail_selected_stage").bind(case_data["stage"], observed))
		assert_eq(repository.call("write_slot", &"slot_1", _snapshot("slot_1", 99.0)), ERR_CANT_CREATE, "%s failure is returned" % case_data["stage"])
		assert_true(case_data["stage"] in observed, "%s observer was reached" % case_data["stage"])
		repository.set("stage_observer", Callable())
		assert_true(repository.call("slot_exists", &"slot_1"), "%s failure retains a byte-valid last-known-good copy" % case_data["stage"])
		var retained: Dictionary = repository.call("read_slot", &"slot_1")
		assert_true(retained.get("ok", false), "%s last-known-good copy remains loadable" % case_data["stage"])
		_cleanup_case(repository)

func _test_candidates_are_bound_to_slot_and_intended_write() -> void:
	var wrong_current: RefCounted = _new_repository("wrong_slot_current")
	_write_signed(_path(wrong_current, "slot_1.json"), _snapshot("slot_2", 2.0))
	assert_false(wrong_current.call("read_slot", &"slot_1").get("ok", true), "current signed for another slot fails closed")
	assert_false(wrong_current.call("slot_exists", &"slot_1"), "wrong-slot current does not make the requested slot exist")
	_cleanup_case(wrong_current)
	var wrong_backup: RefCounted = _new_repository("wrong_slot_backup")
	_write_text(_path(wrong_backup, "slot_1.json"), "corrupt")
	_write_signed(_path(wrong_backup, "slot_1.json.bak"), _snapshot("slot_2", 2.0))
	assert_false(wrong_backup.call("read_slot", &"slot_1").get("ok", true), "backup signed for another slot cannot recover current")
	assert_eq(wrong_backup.call("read_metadata", &"slot_1"), {}, "wrong-slot backup cannot advertise recoverable metadata")
	_cleanup_case(wrong_backup)
	var temp_substitution: RefCounted = _new_repository("temp_substitution")
	temp_substitution.call("write_slot", &"slot_1", _snapshot("slot_1", 1.0))
	temp_substitution.set("stage_observer", Callable(self, "_substitute_candidate").bind(&"temp_reread", &"slot_2", 77.0))
	assert_eq(temp_substitution.call("write_slot", &"slot_1", _snapshot("slot_1", 2.0)), ERR_FILE_CORRUPT, "valid wrong-slot temp is rejected")
	temp_substitution.set("stage_observer", Callable())
	assert_eq(temp_substitution.call("read_slot", &"slot_1").get("data", {}).get("meta", {}).get("play_time_seconds"), 1.0, "wrong-slot temp substitution retains current")
	_cleanup_case(temp_substitution)
	var final_substitution: RefCounted = _new_repository("final_substitution")
	final_substitution.call("write_slot", &"slot_1", _snapshot("slot_1", 1.0))
	final_substitution.set("stage_observer", Callable(self, "_substitute_candidate").bind(&"final_reread", &"slot_1", 77.0))
	assert_eq(final_substitution.call("write_slot", &"slot_1", _snapshot("slot_1", 2.0)), ERR_FILE_CORRUPT, "final reread rejects a different valid snapshot")
	final_substitution.set("stage_observer", Callable())
	assert_true(_is_valid_file(_path(final_substitution, "slot_1.json.bak")), "final substitution retains the prior valid backup")
	assert_false(FileAccess.file_exists(_path(final_substitution, "slot_1.json")), "rejected final substitution is not left as current")
	var rolled_back: Dictionary = final_substitution.call("read_slot", &"slot_1")
	assert_true(rolled_back.get("ok", false) and rolled_back.get("recovered", false), "backup remains recoverable after final substitution rejection")
	assert_eq(rolled_back.get("data", {}).get("meta", {}).get("play_time_seconds"), 1.0, "rejected final substitution can never become the loaded payload")
	_cleanup_case(final_substitution)
	var first_write_substitution: RefCounted = _new_repository("first_write_final_substitution")
	first_write_substitution.set("stage_observer", Callable(self, "_substitute_candidate").bind(&"final_reread", &"slot_1", 77.0))
	assert_eq(first_write_substitution.call("write_slot", &"slot_1", _snapshot("slot_1", 2.0)), ERR_FILE_CORRUPT, "first write rejects a different valid final snapshot")
	first_write_substitution.set("stage_observer", Callable())
	assert_false(FileAccess.file_exists(_path(first_write_substitution, "slot_1.json")), "failed first-write substitution is removed from current")
	assert_false(first_write_substitution.call("slot_exists", &"slot_1"), "failed first-write substitution cannot make a live slot")
	assert_false(first_write_substitution.call("read_slot", &"slot_1").get("ok", true), "failed first-write substitution cannot be loaded afterward")
	_cleanup_case(first_write_substitution)
	var recovery_substitution: RefCounted = _new_repository("recovery_final_substitution")
	recovery_substitution.call("write_slot", &"slot_1", _snapshot("slot_1", 1.0))
	recovery_substitution.call("write_slot", &"slot_1", _snapshot("slot_1", 2.0))
	_write_text(_path(recovery_substitution, "slot_1.json"), "corrupt")
	recovery_substitution.set("stage_observer", Callable(self, "_substitute_candidate").bind(&"final_reread", &"slot_1", 77.0))
	assert_false(recovery_substitution.call("read_slot", &"slot_1").get("ok", true), "recovery rejects a different valid final snapshot")
	recovery_substitution.set("stage_observer", Callable())
	assert_false(FileAccess.file_exists(_path(recovery_substitution, "slot_1.json")), "rejected recovery substitution is not left as current")
	var retried_recovery: Dictionary = recovery_substitution.call("read_slot", &"slot_1")
	assert_true(retried_recovery.get("ok", false) and retried_recovery.get("recovered", false), "backup can recover after a rejected recovery substitution")
	assert_eq(retried_recovery.get("data", {}).get("meta", {}).get("play_time_seconds"), 1.0, "rejected recovery substitution can never become the loaded payload")
	_cleanup_case(recovery_substitution)

func _test_injected_recovery_stage_failures() -> void:
	for stage in [&"recovery_copy", &"temp_reread", &"invalid_current_cleanup", &"temp_to_current_rename", &"final_reread"]:
		var repository: RefCounted = _new_repository("recovery_failure_%s" % stage)
		repository.call("write_slot", &"slot_1", _snapshot("slot_1", 1.0))
		repository.call("write_slot", &"slot_1", _snapshot("slot_1", 2.0))
		var backup_before := FileAccess.get_file_as_bytes(_path(repository, "slot_1.json.bak"))
		_write_text(_path(repository, "slot_1.json"), "corrupt")
		var observed: Array[StringName] = []
		repository.set("stage_observer", Callable(self, "_fail_selected_stage").bind(stage, observed))
		var result: Dictionary = repository.call("read_slot", &"slot_1")
		assert_false(result.get("ok", true), "%s recovery failure is closed" % stage)
		assert_true(stage in observed, "%s recovery observer was reached" % stage)
		assert_eq(FileAccess.get_file_as_bytes(_path(repository, "slot_1.json.bak")), backup_before, "%s recovery failure preserves backup bytes" % stage)
		repository.set("stage_observer", Callable())
		assert_true(repository.call("slot_exists", &"slot_1"), "%s recovery failure leaves a byte-valid copy" % stage)
		_cleanup_case(repository)

func _new_repository(case_name: String) -> RefCounted:
	var repository: RefCounted = _repository_script.new()
	repository.set("base_directory", "%s/save_repository_%s_%s" % [TEST_ROOT, case_name, _run_suffix])
	_cleanup_case(repository)
	return repository

func _cleanup_case(repository: RefCounted) -> void:
	var resolved := ProjectSettings.globalize_path(String(repository.get("base_directory"))).simplify_path().replace("\\", "/").trim_suffix("/")
	var root := ProjectSettings.globalize_path(TEST_ROOT).simplify_path().replace("\\", "/").trim_suffix("/")
	if resolved == root or resolved.get_base_dir() != root:
		failures.append("cleanup refused path outside resolved test root: %s" % resolved)
		return
	if not DirAccess.dir_exists_absolute(resolved):
		return
	var directory := DirAccess.open(resolved)
	if directory == null:
		failures.append("cleanup could not open exact case directory: %s" % resolved)
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	var found_nested_directory := false
	while not entry.is_empty():
		if directory.current_is_dir():
			failures.append("cleanup refused unexpected nested directory: %s/%s" % [resolved, entry])
			found_nested_directory = true
		else:
			assert_eq(DirAccess.remove_absolute("%s/%s" % [resolved, entry]), OK, "cleanup removes only exact case file")
		entry = directory.get_next()
	directory.list_dir_end()
	directory = null
	if not found_nested_directory:
		assert_eq(DirAccess.remove_absolute(resolved), OK, "cleanup removes only exact resolved case directory")

func _snapshot(slot_id: String, play_time: float) -> Dictionary:
	return {
		"schema_version": 1,
		"meta": {"slot_id": slot_id, "saved_at": "2026-08-16T12:34:56Z", "play_time_seconds": play_time, "location_name": "기초 방"},
		"player": {"map_id": "foundation_room", "spawn_id": "start", "position": {"x": 120.0, "y": 88.0}, "facing": "down"},
		"narrative": {"flags": {}, "stats": {}, "inventory": {}, "quests": {}, "collectibles": {}},
		"world": {"maps": {}},
		"dialogue": {"active": false, "bundle_key": "", "trigger_key": "", "node_id": "", "boundary": ""},
	}

func _path(repository: RefCounted, filename: String) -> String:
	return "%s/%s" % [String(repository.get("base_directory")).trim_suffix("/"), filename]

func _write_text(path: String, text: String) -> void:
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	assert_true(directory_error == OK or directory_error == ERR_ALREADY_EXISTS, "fixture directory is created")
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file, "fixture file opens: %s" % path)
	if file != null:
		file.store_string(text)
		file.close()

func _write_signed(path: String, snapshot: Dictionary) -> void:
	var save_data := load("res://app/save/save_data.gd") as Script
	_write_text(path, JSON.stringify(save_data.call("with_checksum", snapshot), "", true, true))

func _read_json_file(path: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if typeof(value) == TYPE_DICTIONARY else {}

func _is_valid_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var save_data := load("res://app/save/save_data.gd") as Script
	var snapshot := _read_json_file(path)
	return not snapshot.is_empty() and save_data.call("validate", snapshot).is_empty() and save_data.call("verify_checksum", snapshot)

func _corrupt_temp_on_reread(stage: StringName, context: Dictionary) -> Error:
	if stage == &"temp_reread":
		_write_text(String(context.get("temp_path", "")), "corrupt temp")
	return OK

func _fail_selected_stage(stage: StringName, _context: Dictionary, target: StringName, observed: Array[StringName]) -> Error:
	observed.append(stage)
	return ERR_CANT_CREATE if stage == target else OK

func _substitute_candidate(stage: StringName, context: Dictionary, target: StringName, slot_id: StringName, play_time: float) -> Error:
	if stage == target:
		var path := String(context.get("temp_path" if stage == &"temp_reread" else "current_path", ""))
		_write_signed(path, _snapshot(String(slot_id), play_time))
	return OK
