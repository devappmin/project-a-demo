@tool
extends RefCounted
class_name DialogueSnapshotWriter

const Compiler = preload("res://tools/notion_sync/dialogue_compiler.gd")

var _operation_guard: Callable

func _init(operation_guard: Callable = Callable()) -> void:
	_operation_guard = operation_guard

func replace_snapshot(output_dir: String, graphs: Dictionary, manifest: Dictionary) -> Error:
	var normalized_output := output_dir.simplify_path()
	if not _is_safe_output_directory(normalized_output):
		return ERR_INVALID_PARAMETER
	var output_absolute := ProjectSettings.globalize_path(normalized_output)
	var temporary_absolute := output_absolute + ".tmp"
	var backup_absolute := output_absolute + ".bak"
	if DirAccess.dir_exists_absolute(backup_absolute) or FileAccess.file_exists(backup_absolute):
		return ERR_ALREADY_EXISTS
	var cleanup_error := _remove_tree(temporary_absolute)
	if cleanup_error != OK:
		return cleanup_error
	var contents_result := _snapshot_contents(graphs, manifest)
	if not contents_result["ok"]:
		return contents_result["error"]
	var contents: Dictionary = contents_result["contents"]
	var create_error := DirAccess.make_dir_recursive_absolute(temporary_absolute)
	if create_error != OK:
		return create_error
	var guarded_error := _guard("write", temporary_absolute)
	if guarded_error != OK:
		_remove_tree(temporary_absolute)
		return guarded_error
	for filename: String in _sorted_keys(contents):
		var write_error := _write_text(temporary_absolute.path_join(filename), String(contents[filename]))
		if write_error != OK:
			_remove_tree(temporary_absolute)
			return write_error
	guarded_error = _guard("verify", temporary_absolute)
	if guarded_error != OK:
		_remove_tree(temporary_absolute)
		return guarded_error
	var verify_error := _verify_snapshot(temporary_absolute, contents, manifest)
	if verify_error != OK:
		_remove_tree(temporary_absolute)
		return verify_error
	guarded_error = _guard("backup_swap", output_absolute)
	if guarded_error != OK:
		_remove_tree(temporary_absolute)
		return guarded_error
	var had_previous := DirAccess.dir_exists_absolute(output_absolute)
	if had_previous:
		var backup_error := DirAccess.rename_absolute(output_absolute, backup_absolute)
		if backup_error != OK:
			_remove_tree(temporary_absolute)
			return backup_error
	guarded_error = _guard("publish_swap", temporary_absolute)
	if guarded_error != OK:
		if had_previous:
			_restore_from_backup(backup_absolute, output_absolute)
		_remove_tree(temporary_absolute)
		return guarded_error
	var publish_error := DirAccess.rename_absolute(temporary_absolute, output_absolute)
	if publish_error != OK:
		if had_previous:
			_restore_from_backup(backup_absolute, output_absolute)
		_remove_tree(temporary_absolute)
		return publish_error
	if had_previous:
		var backup_cleanup_error := _remove_tree(backup_absolute)
		if backup_cleanup_error != OK:
			return backup_cleanup_error
	return OK

func _snapshot_contents(graphs: Dictionary, manifest: Dictionary) -> Dictionary:
	if int(manifest.get("schema_version", 0)) != 1 or typeof(manifest.get("files")) != TYPE_DICTIONARY:
		return {"ok":false, "error":ERR_INVALID_DATA, "contents":{}}
	var contents := {}
	var expected_hashes: Dictionary = manifest["files"]
	for scene_key: String in _sorted_keys(graphs):
		if scene_key.is_empty() or scene_key.contains("/") or scene_key.contains("\\"):
			return {"ok":false, "error":ERR_INVALID_PARAMETER, "contents":{}}
		if typeof(graphs[scene_key]) != TYPE_DICTIONARY:
			return {"ok":false, "error":ERR_INVALID_DATA, "contents":{}}
		var filename := Compiler.scene_filename(scene_key)
		if contents.has(filename):
			return {"ok":false, "error":ERR_ALREADY_EXISTS, "contents":{}}
		var graph_json := Compiler.stable_json(graphs[scene_key])
		if String(expected_hashes.get(filename, "")) != graph_json.sha256_text():
			return {"ok":false, "error":ERR_FILE_CORRUPT, "contents":{}}
		contents[filename] = graph_json
	if expected_hashes.size() != contents.size():
		return {"ok":false, "error":ERR_INVALID_DATA, "contents":{}}
	contents["manifest.json"] = Compiler.stable_json(manifest)
	return {"ok":true, "error":OK, "contents":contents}

func _verify_snapshot(directory: String, contents: Dictionary, manifest: Dictionary) -> Error:
	for filename: String in _sorted_keys(contents):
		var path := directory.path_join(filename)
		if not FileAccess.file_exists(path):
			return ERR_FILE_NOT_FOUND
		var reread := FileAccess.get_file_as_string(path)
		if reread.sha256_text() != String(contents[filename]).sha256_text():
			return ERR_FILE_CORRUPT
		var parsed: Variant = JSON.parse_string(reread)
		if typeof(parsed) != TYPE_DICTIONARY:
			return ERR_PARSE_ERROR
	var expected_hashes: Dictionary = manifest["files"]
	for filename_value: Variant in expected_hashes:
		var filename := String(filename_value)
		if FileAccess.get_file_as_string(directory.path_join(filename)).sha256_text() != String(expected_hashes[filename]):
			return ERR_FILE_CORRUPT
	return OK

func _write_text(path: String, content: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(content)
	var error := file.get_error()
	file.close()
	return error

func _restore_from_backup(backup: String, output: String) -> Error:
	if not DirAccess.dir_exists_absolute(backup):
		return ERR_FILE_NOT_FOUND
	var cleanup_error := _remove_tree(output)
	if cleanup_error != OK:
		return cleanup_error
	return _copy_tree(backup, output)

func _copy_tree(source: String, destination: String) -> Error:
	var create_error := DirAccess.make_dir_recursive_absolute(destination)
	if create_error != OK:
		return create_error
	var directory := DirAccess.open(source)
	if directory == null:
		return DirAccess.get_open_error()
	for child_dir: String in directory.get_directories():
		var child_error := _copy_tree(source.path_join(child_dir), destination.path_join(child_dir))
		if child_error != OK:
			return child_error
	for filename: String in directory.get_files():
		var copy_error := DirAccess.copy_absolute(source.path_join(filename), destination.path_join(filename))
		if copy_error != OK:
			return copy_error
	return OK

func _remove_tree(path: String) -> Error:
	if path.is_empty() or path in ["/", "res://", "user://"]:
		return ERR_INVALID_PARAMETER
	if not DirAccess.dir_exists_absolute(path):
		if FileAccess.file_exists(path):
			return DirAccess.remove_absolute(path)
		return OK
	var directory := DirAccess.open(path)
	if directory == null:
		return DirAccess.get_open_error()
	for child_dir: String in directory.get_directories():
		var child_error := _remove_tree(path.path_join(child_dir))
		if child_error != OK:
			return child_error
	for filename: String in directory.get_files():
		var remove_error := DirAccess.remove_absolute(path.path_join(filename))
		if remove_error != OK:
			return remove_error
	return DirAccess.remove_absolute(path)

func _guard(stage: String, path: String) -> Error:
	if not _operation_guard.is_valid():
		return OK
	var result: Variant = _operation_guard.call(stage, path)
	return int(result) as Error if typeof(result) == TYPE_INT else ERR_INVALID_DATA

func _is_safe_output_directory(path: String) -> bool:
	if path.is_empty() or path in ["/", "res://", "user://"] or path.ends_with(".tmp") or path.ends_with(".bak"):
		return false
	var absolute := ProjectSettings.globalize_path(path)
	if absolute.is_empty() or absolute.get_base_dir() == absolute:
		return false
	return path.begins_with("res://") or path.begins_with("user://") or path.is_absolute_path()

func _sorted_keys(dictionary: Dictionary) -> Array[String]:
	var keys: Array[String] = []
	for key: Variant in dictionary:
		keys.append(String(key))
	keys.sort()
	return keys
