@tool
extends RefCounted
class_name DialogueSnapshotWriter

const Compiler = preload("res://tools/notion_sync/dialogue_compiler.gd")
const ERR_ROLLBACK_FAILED := ERR_CANT_RESOLVE

var last_recovery: Dictionary = {}
var _transaction_observer: Callable

func _init(transaction_observer: Callable = Callable()) -> void:
	_transaction_observer = transaction_observer

func replace_snapshot(output_dir: String, graphs: Dictionary, manifest: Dictionary) -> Error:
	last_recovery = {}
	var normalized_output := output_dir.simplify_path()
	if not _is_safe_output_directory(normalized_output):
		return ERR_INVALID_PARAMETER
	var output_absolute := ProjectSettings.globalize_path(normalized_output)
	var temporary_absolute := output_absolute + ".tmp"
	var paths := {"output":output_absolute, "temporary":temporary_absolute, "publish":temporary_absolute.path_join("publish"), "recovery":temporary_absolute.path_join("recovery"), "backup":output_absolute + ".bak"}
	if _path_exists(paths["backup"]):
		last_recovery = {"code":"backup_artifact_present", "backup_path":paths["backup"], "recoverable":false}
		return ERR_ALREADY_EXISTS
	var cleanup_error := _remove_tree(paths["temporary"])
	if cleanup_error != OK:
		return cleanup_error
	var contents_result := _snapshot_contents(graphs, manifest)
	if not contents_result["ok"]:
		return contents_result["error"]
	var contents: Dictionary = contents_result["contents"]
	var create_error := DirAccess.make_dir_recursive_absolute(paths["publish"])
	if create_error != OK:
		return create_error
	_observe("before_write", paths)
	for filename: String in _sorted_keys(contents):
		var write_error := _write_text(String(paths["publish"]).path_join(filename), String(contents[filename]))
		if write_error != OK:
			_remove_tree(paths["temporary"])
			return write_error
	_observe("after_write", paths)
	var verify_error := _verify_snapshot(paths["publish"], contents, manifest)
	if verify_error != OK:
		_remove_tree(paths["temporary"])
		return verify_error
	var had_previous := DirAccess.dir_exists_absolute(paths["output"])
	if had_previous:
		var recovery_copy_error := _copy_tree_verified(paths["output"], paths["recovery"])
		if recovery_copy_error != OK:
			_remove_tree(paths["temporary"])
			return recovery_copy_error
	_observe("before_backup_rename", paths)
	if had_previous:
		var backup_error := DirAccess.rename_absolute(paths["output"], paths["backup"])
		if backup_error != OK:
			_remove_tree(paths["temporary"])
			return backup_error
	_observe("before_publish_rename", paths)
	var publish_error := DirAccess.rename_absolute(paths["publish"], paths["output"])
	if publish_error != OK:
		if had_previous:
			var rollback_error := _rollback_by_rename(paths)
			var temporary_cleanup_error := OK
			if rollback_error != OK:
				if _path_exists(paths["backup"]):
					temporary_cleanup_error = _remove_tree(paths["temporary"])
				last_recovery = {"code":"rollback_failed", "backup_path":paths["backup"], "temporary_path":paths["temporary"], "rollback_error":rollback_error, "publish_error":publish_error, "recoverable":_path_exists(paths["backup"])}
				return ERR_ROLLBACK_FAILED
			temporary_cleanup_error = _remove_tree(paths["temporary"])
			if temporary_cleanup_error != OK:
				return temporary_cleanup_error
		else:
			_remove_tree(paths["temporary"])
		return publish_error
	var transaction_cleanup_error := _remove_tree(paths["temporary"])
	if transaction_cleanup_error != OK:
		last_recovery = {"code":"transaction_cleanup_residue", "backup_path":paths["backup"], "temporary_path":paths["temporary"], "recoverable":had_previous, "cleanup_error":transaction_cleanup_error}
		return OK
	if had_previous:
		_observe("before_backup_cleanup", paths)
		var backup_cleanup_error := _remove_tree(paths["backup"])
		if backup_cleanup_error != OK:
			last_recovery = {"code":"backup_cleanup_residue", "backup_path":paths["backup"], "recoverable":false, "cleanup_error":backup_cleanup_error}
			return OK
	return OK

func _snapshot_contents(graphs: Dictionary, manifest: Dictionary) -> Dictionary:
	if int(manifest.get("schema_version", 0)) != 1 or typeof(manifest.get("files")) != TYPE_DICTIONARY:
		return {"ok":false, "error":ERR_INVALID_DATA, "contents":{}}
	var contents := {}
	var filename_identities := {}
	var expected_hashes: Dictionary = manifest["files"]
	for scene_key: String in _sorted_keys(graphs):
		if not Compiler.is_safe_scene_key(scene_key):
			return {"ok":false, "error":ERR_INVALID_PARAMETER, "contents":{}}
		var filename := Compiler.scene_filename(scene_key)
		var filename_identity := filename.to_lower()
		if filename_identities.has(filename_identity):
			return {"ok":false, "error":ERR_ALREADY_EXISTS, "contents":{}}
		filename_identities[filename_identity] = true
	for scene_key: String in _sorted_keys(graphs):
		if typeof(graphs[scene_key]) != TYPE_DICTIONARY:
			return {"ok":false, "error":ERR_INVALID_DATA, "contents":{}}
		var filename := Compiler.scene_filename(scene_key)
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

func _rollback_by_rename(paths: Dictionary) -> Error:
	var output := String(paths["output"])
	var publish := String(paths["publish"])
	var recovery := String(paths["recovery"])
	var backup := String(paths["backup"])
	if not _path_exists(backup):
		return ERR_FILE_NOT_FOUND
	if _path_exists(output):
		if _path_exists(publish):
			return ERR_ALREADY_EXISTS
		var vacate_error := DirAccess.rename_absolute(output, publish)
		if vacate_error != OK:
			return vacate_error
	var restore_error := DirAccess.rename_absolute(backup, output)
	if restore_error != OK:
		return restore_error
	var retain_backup_error := DirAccess.rename_absolute(recovery, backup)
	if retain_backup_error != OK:
		return retain_backup_error
	return OK

func _copy_tree_verified(source: String, destination: String) -> Error:
	var copy_error := _copy_tree(source, destination)
	if copy_error != OK:
		return copy_error
	return OK if _tree_fingerprint(source) == _tree_fingerprint(destination) else ERR_FILE_CORRUPT

func _copy_tree(source: String, destination: String) -> Error:
	var create_error := DirAccess.make_dir_recursive_absolute(destination)
	if create_error != OK:
		return create_error
	var directory := DirAccess.open(source)
	if directory == null:
		return DirAccess.get_open_error()
	var directories := directory.get_directories()
	directories.sort()
	for child_dir: String in directories:
		var child_error := _copy_tree(source.path_join(child_dir), destination.path_join(child_dir))
		if child_error != OK:
			return child_error
	var files := directory.get_files()
	files.sort()
	for filename: String in files:
		var file_error := DirAccess.copy_absolute(source.path_join(filename), destination.path_join(filename))
		if file_error != OK:
			return file_error
	return OK

func _tree_fingerprint(root: String) -> Dictionary:
	var result := {"directories":[], "files":{}}
	_collect_fingerprint(root, "", result)
	return result

func _collect_fingerprint(root: String, relative: String, result: Dictionary) -> void:
	var current := root if relative.is_empty() else root.path_join(relative)
	var directory := DirAccess.open(current)
	if directory == null:
		return
	var directories := directory.get_directories()
	directories.sort()
	for child_dir: String in directories:
		var child_relative := child_dir if relative.is_empty() else relative.path_join(child_dir)
		result["directories"].append(child_relative)
		_collect_fingerprint(root, child_relative, result)
	var files := directory.get_files()
	files.sort()
	for filename: String in files:
		var file_relative := filename if relative.is_empty() else relative.path_join(filename)
		result["files"][file_relative] = FileAccess.get_file_as_bytes(root.path_join(file_relative)).hex_encode()

func _remove_tree(path: String) -> Error:
	var normalized := path.simplify_path()
	if normalized.is_empty() or normalized in ["/", "res://", "user://"] or normalized.get_base_dir() == normalized:
		return ERR_INVALID_PARAMETER
	if not DirAccess.dir_exists_absolute(normalized):
		if FileAccess.file_exists(normalized):
			return DirAccess.remove_absolute(normalized)
		return OK
	var directory := DirAccess.open(normalized)
	if directory == null:
		return DirAccess.get_open_error()
	var directories := directory.get_directories()
	directories.sort()
	for child_dir: String in directories:
		var child_error := _remove_tree(normalized.path_join(child_dir))
		if child_error != OK:
			return child_error
	var files := directory.get_files()
	files.sort()
	for filename: String in files:
		var remove_error := DirAccess.remove_absolute(normalized.path_join(filename))
		if remove_error != OK:
			return remove_error
	return DirAccess.remove_absolute(normalized)

func _observe(stage: String, paths: Dictionary) -> void:
	if _transaction_observer.is_valid():
		_transaction_observer.call(stage, paths.duplicate(true))

func _path_exists(path: String) -> bool:
	return DirAccess.dir_exists_absolute(path) or FileAccess.file_exists(path)

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
