extends RefCounted
class_name SaveRepository

const SaveDataResource = preload("res://app/save/save_data.gd")

var base_directory := "user://saves"
var stage_observer: Callable

func write_slot(slot_id: StringName, snapshot: Dictionary) -> Error:
	if not _valid_slot(slot_id):
		return ERR_INVALID_PARAMETER
	var signed := SaveDataResource.with_checksum(snapshot)
	if signed.is_empty() or StringName(signed.get("meta", {}).get("slot_id", "")) != slot_id:
		return ERR_INVALID_DATA
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base_directory))
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return directory_error
	var paths := _paths(slot_id)
	var current := _read_candidate(paths.current, slot_id)
	var _backup := _read_candidate(paths.backup, slot_id)
	var stage_error := _observe(&"write_temp", paths)
	if stage_error != OK:
		return stage_error
	var write_error := _write_bytes(paths.temp, JSON.stringify(signed, "", true, true).to_utf8_buffer())
	if write_error != OK:
		return write_error
	stage_error = _observe(&"temp_reread", paths)
	if stage_error != OK:
		return stage_error
	var verified_temp := _read_candidate(paths.temp, slot_id)
	if not verified_temp.ok or verified_temp.data.get("checksum") != signed.get("checksum"):
		return ERR_FILE_CORRUPT
	if current.ok:
		if FileAccess.file_exists(paths.backup):
			stage_error = _observe(&"old_backup_cleanup", paths)
			if stage_error != OK:
				return stage_error
			var cleanup_error := DirAccess.remove_absolute(paths.backup)
			if cleanup_error != OK:
				return cleanup_error
		stage_error = _observe(&"current_to_backup_rename", paths)
		if stage_error != OK:
			return stage_error
		var rotation_error := DirAccess.rename_absolute(paths.current, paths.backup)
		if rotation_error != OK:
			return rotation_error
	elif FileAccess.file_exists(paths.current):
		stage_error = _observe(&"invalid_current_cleanup", paths)
		if stage_error != OK:
			return stage_error
		var invalid_cleanup_error := DirAccess.remove_absolute(paths.current)
		if invalid_cleanup_error != OK:
			return invalid_cleanup_error
	stage_error = _observe(&"temp_to_current_rename", paths)
	if stage_error != OK:
		return stage_error
	var publish_error := DirAccess.rename_absolute(paths.temp, paths.current)
	if publish_error != OK:
		return publish_error
	stage_error = _observe(&"final_reread", paths)
	if stage_error != OK:
		return stage_error
	var final_current := _read_candidate(paths.current, slot_id)
	if final_current.ok and final_current.data.get("checksum") == signed.get("checksum"):
		return OK
	var quarantine_error := _quarantine_rejected_current(paths)
	return ERR_FILE_CORRUPT if quarantine_error == OK else quarantine_error

func read_slot(slot_id: StringName) -> Dictionary:
	if not _valid_slot(slot_id):
		return _failure(ERR_INVALID_PARAMETER, {"reason": "invalid_slot", "slot_id": String(slot_id)})
	var paths := _paths(slot_id)
	var current := _read_candidate(paths.current, slot_id)
	if current.ok:
		return _success(current.data, false, {})
	var backup := _read_candidate(paths.backup, slot_id)
	if not backup.ok:
		return _failure(ERR_FILE_CORRUPT, _copy_diagnostic(paths, current, backup, &"read"))
	var recovery_error := _recover_backup(paths, current, backup)
	if recovery_error != OK:
		return _failure(recovery_error, _copy_diagnostic(paths, current, backup, &"recovery"))
	var recovered := _read_candidate(paths.current, slot_id)
	if not recovered.ok:
		return _failure(ERR_FILE_CORRUPT, _copy_diagnostic(paths, current, backup, &"recovery_final"))
	return _success(recovered.data, true, _copy_diagnostic(paths, current, backup, &"recovered"))

func read_metadata(slot_id: StringName) -> Dictionary:
	if not _valid_slot(slot_id):
		return {}
	var paths := _paths(slot_id)
	var current := _read_candidate(paths.current, slot_id)
	if current.ok:
		var current_metadata := SaveDataResource.metadata(current.data)
		current_metadata["recoverable"] = false
		return current_metadata
	var backup := _read_candidate(paths.backup, slot_id)
	if backup.ok:
		var backup_metadata := SaveDataResource.metadata(backup.data)
		backup_metadata["recoverable"] = true
		return backup_metadata
	return {}

func slot_exists(slot_id: StringName) -> bool:
	if not _valid_slot(slot_id):
		return false
	var paths := _paths(slot_id)
	return _read_candidate(paths.current, slot_id).ok or _read_candidate(paths.backup, slot_id).ok

func _recover_backup(paths: Dictionary, _current: Dictionary, backup: Dictionary) -> Error:
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(base_directory))
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return directory_error
	var stage_error := _observe(&"recovery_copy", paths)
	if stage_error != OK:
		return stage_error
	var copy_error := _write_bytes(paths.temp, FileAccess.get_file_as_bytes(paths.backup))
	if copy_error != OK:
		return copy_error
	stage_error = _observe(&"temp_reread", paths)
	if stage_error != OK:
		return stage_error
	var temp := _read_candidate(paths.temp, paths.slot_id)
	if not temp.ok or temp.data.get("checksum") != backup.data.get("checksum"):
		return ERR_FILE_CORRUPT
	if FileAccess.file_exists(paths.current):
		stage_error = _observe(&"invalid_current_cleanup", paths)
		if stage_error != OK:
			return stage_error
		var cleanup_error := DirAccess.remove_absolute(paths.current)
		if cleanup_error != OK:
			return cleanup_error
	stage_error = _observe(&"temp_to_current_rename", paths)
	if stage_error != OK:
		return stage_error
	var publish_error := DirAccess.rename_absolute(paths.temp, paths.current)
	if publish_error != OK:
		return publish_error
	stage_error = _observe(&"final_reread", paths)
	if stage_error != OK:
		return stage_error
	var final_current := _read_candidate(paths.current, paths.slot_id)
	if not final_current.ok or final_current.data.get("checksum") != backup.data.get("checksum"):
		var quarantine_error := _quarantine_rejected_current(paths)
		return ERR_FILE_CORRUPT if quarantine_error == OK else quarantine_error
	return OK

func _quarantine_rejected_current(paths: Dictionary) -> Error:
	if not FileAccess.file_exists(paths.current):
		return OK
	if FileAccess.file_exists(paths.temp):
		var temp_cleanup_error := DirAccess.remove_absolute(paths.temp)
		if temp_cleanup_error != OK:
			return temp_cleanup_error
	var quarantine_error := DirAccess.rename_absolute(paths.current, paths.temp)
	if quarantine_error == OK:
		return OK
	return DirAccess.remove_absolute(paths.current)

func _read_candidate(path: String, expected_slot_id: StringName) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": ERR_FILE_NOT_FOUND, "reason": "missing"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": FileAccess.get_open_error(), "reason": "open_failed"}
	var bytes := file.get_buffer(file.get_length())
	file.close()
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK:
		return {"ok": false, "error": ERR_PARSE_ERROR, "reason": "malformed_json"}
	var value: Variant = json.data
	if typeof(value) != TYPE_DICTIONARY:
		return {"ok": false, "error": ERR_INVALID_DATA, "reason": "invalid_root"}
	var migrated := SaveDataResource.migrate(value)
	if migrated.is_empty():
		return {"ok": false, "error": ERR_INVALID_DATA, "reason": "unsupported_schema"}
	var validation_issues := SaveDataResource.validate(migrated)
	if not validation_issues.is_empty():
		return {"ok": false, "error": ERR_INVALID_DATA, "reason": "invalid_schema"}
	if not SaveDataResource.verify_checksum(migrated):
		return {"ok": false, "error": ERR_FILE_CORRUPT, "reason": "checksum_mismatch"}
	if StringName(migrated.get("meta", {}).get("slot_id", "")) != expected_slot_id:
		return {"ok": false, "error": ERR_INVALID_DATA, "reason": "slot_mismatch"}
	return {"ok": true, "error": OK, "reason": "valid", "data": migrated}

func _write_bytes(path: String, bytes: PackedByteArray) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(bytes)
	var error := file.get_error()
	file.close()
	return error

func _observe(stage: StringName, paths: Dictionary) -> Error:
	if not stage_observer.is_valid():
		return OK
	var context := {
		"current_path": paths.current,
		"backup_path": paths.backup,
		"temp_path": paths.temp,
	}
	var result: Variant = stage_observer.call(stage, context)
	return int(result) as Error if typeof(result) == TYPE_INT else OK

func _paths(slot_id: StringName) -> Dictionary:
	var stem := "%s/%s.json" % [base_directory.trim_suffix("/"), String(slot_id)]
	return {"slot_id": slot_id, "current": stem, "temp": stem + ".tmp", "backup": stem + ".bak"}

func _valid_slot(slot_id: StringName) -> bool:
	return slot_id in SaveDataResource.SLOT_IDS

func _success(data: Dictionary, recovered: bool, diagnostic: Dictionary) -> Dictionary:
	return {"ok": true, "error": OK, "data": data.duplicate(true), "recovered": recovered, "diagnostic": diagnostic.duplicate(true)}

func _failure(error: Error, diagnostic: Dictionary) -> Dictionary:
	return {"ok": false, "error": error, "data": {}, "recovered": false, "diagnostic": diagnostic.duplicate(true)}

func _copy_diagnostic(paths: Dictionary, current: Dictionary, backup: Dictionary, stage: StringName) -> Dictionary:
	return {
		"stage": String(stage),
		"current": {"path": paths.current, "error": current.get("error", ERR_BUG), "reason": current.get("reason", "unknown")},
		"backup": {"path": paths.backup, "error": backup.get("error", ERR_BUG), "reason": backup.get("reason", "unknown")},
	}
