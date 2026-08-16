@tool
extends SceneTree
class_name DialogueImportCli

const Compiler = preload("res://tools/dialogue_import/document_dialogue_compiler.gd")
const SnapshotWriter = preload("res://tools/dialogue_import/dialogue_snapshot_writer.gd")
const DEFAULT_INPUT_DIR := "res://data/dialogues/authoring"
const DEFAULT_OUTPUT_DIR := "res://data/generated/dialogues"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := _get_arguments()
	var dry_run := "--dry-run" in args
	var allow_warnings := "--allow-warnings" in args
	var input_dir := _argument_value(args, "--input-dir", DEFAULT_INPUT_DIR)
	var output_dir := _argument_value(args, "--output-dir", DEFAULT_OUTPUT_DIR)
	var result := run_import(input_dir, output_dir, dry_run, allow_warnings)
	_present_result(result, dry_run)
	_terminate(exit_code_for(result))

func _get_arguments() -> PackedStringArray:
	return OS.get_cmdline_user_args()

func _terminate(exit_code: int) -> void:
	quit(exit_code)

func _present_result(result: Dictionary, dry_run: bool) -> void:
	var lines := format_result_lines(result, dry_run)
	for line: String in lines["stdout"]:
		print(line)
	for line: String in lines["stderr"]:
		printerr(line)

static func run_import(input_dir: String, output_dir: String, dry_run: bool, allow_warnings := false) -> Dictionary:
	if _paths_overlap(input_dir, output_dir):
		return _input_failure("unsafe_output_overlap", "입력 폴더와 게시 폴더는 서로 같거나 포함 관계일 수 없습니다.", output_dir, ERR_INVALID_PARAMETER)
	var loaded := _load_bundles(input_dir)
	if not loaded.get("ok", false):
		return loaded
	var bundles: Array[Dictionary] = loaded["bundles"]
	var compiled := Compiler.compile_bundles(bundles)
	compiled["counts"] = _count_bundles(bundles)
	compiled["error"] = OK if compiled.get("ok", false) else ERR_INVALID_DATA
	compiled["code"] = "validated" if compiled.get("ok", false) else "compilation_failed"
	compiled["message"] = "대화 문서 검증이 완료되었습니다." if compiled.get("ok", false) else "대화 문서 검증에 실패했습니다. 오류를 수정한 뒤 다시 시도하세요."
	if not compiled.get("ok", false) or dry_run:
		return compiled
	if _has_warnings(compiled.get("issues", [])) and not allow_warnings:
		var blocked := compiled.duplicate(true)
		blocked["ok"] = false
		blocked["error"] = ERR_INVALID_DATA
		blocked["code"] = "warning_confirmation_required"
		blocked["message"] = "경고를 확인한 뒤 게시하려면 --allow-warnings를 명시하세요."
		return blocked
	var writer := SnapshotWriter.new()
	var error: Error = writer.replace_artifacts(output_dir, compiled["artifacts"], compiled["manifest"])
	compiled["ok"] = error == OK
	compiled["error"] = error
	compiled["recovery"] = writer.last_recovery.duplicate(true)
	compiled["code"] = "published" if error == OK else "publish_failed"
	compiled["message"] = _publish_message(error, writer.last_recovery)
	return compiled

static func format_result_lines(result: Dictionary, dry_run: bool) -> Dictionary:
	var stdout: Array[String] = []
	var stderr: Array[String] = []
	var issues_value: Variant = result.get("issues", [])
	if typeof(issues_value) == TYPE_ARRAY:
		for issue_value: Variant in issues_value:
			if typeof(issue_value) != TYPE_DICTIONARY:
				continue
			var issue: Dictionary = issue_value
			var severity := String(issue.get("severity", "error"))
			var label := "경고" if severity == "warning" else "오류"
			var diagnostic := "%s [%s] %s" % [label, issue.get("code", "import_failed"), issue.get("message", "")]
			var source_url := String(issue.get("source_url", "")).strip_edges()
			if not source_url.is_empty():
				diagnostic += " (%s)" % source_url
			(stdout if severity == "warning" else stderr).append(diagnostic.strip_edges())
	var message := String(result.get("message", "")).strip_edges()
	if not message.is_empty():
		(stdout if result.get("ok", false) else stderr).append(message)
	var counts_value: Variant = result.get("counts", {})
	if typeof(counts_value) == TYPE_DICTIONARY and not (counts_value as Dictionary).is_empty():
		var counts: Dictionary = counts_value
		var status := "미리보기" if dry_run else ("게시 완료" if result.get("ok", false) else "검증 결과")
		stdout.append("대화 가져오기 %s: 묶음 %d개, 이벤트 %d개, 흐름 %d개, 대사 %d줄, 선택지 %d개." % [status, counts.get("bundles", 0), counts.get("events", 0), counts.get("flows", 0), counts.get("lines", 0), counts.get("choices", 0)])
	var manifest_value: Variant = result.get("manifest", {})
	if typeof(manifest_value) == TYPE_DICTIONARY and not (manifest_value as Dictionary).is_empty():
		stdout.append("manifest SHA-256: %s" % Compiler.stable_json(manifest_value).sha256_text())
	return {"stdout":stdout, "stderr":stderr}

static func exit_code_for(result: Dictionary) -> int:
	return 0 if bool(result.get("ok", false)) else 1

static func _load_bundles(input_dir: String) -> Dictionary:
	var directory := DirAccess.open(input_dir)
	if directory == null:
		return _input_failure("input_directory_missing", "입력 폴더를 열 수 없습니다: %s" % input_dir, input_dir, DirAccess.get_open_error())
	var filenames: Array[String] = []
	for filename: String in directory.get_files():
		if filename.ends_with(".json"):
			filenames.append(filename)
	filenames.sort()
	if filenames.is_empty():
		return _input_failure("empty_input", "입력 폴더에 대화 묶음 JSON이 없습니다: %s" % input_dir, input_dir, ERR_FILE_NOT_FOUND)
	var bundles: Array[Dictionary] = []
	var bundle_keys: Dictionary = {}
	for filename: String in filenames:
		var path := input_dir.path_join(filename)
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return _input_failure("load_failed", "대화 묶음 파일을 열 수 없습니다: %s" % path, path, FileAccess.get_open_error())
		var parser := JSON.new()
		var parse_error := parser.parse(file.get_as_text())
		file.close()
		if parse_error != OK:
			return _input_failure("parse_failed", "대화 묶음 JSON을 해석할 수 없습니다(%d행): %s" % [parser.get_error_line(), path], path, parse_error)
		if typeof(parser.data) != TYPE_DICTIONARY:
			return _input_failure("invalid_root", "대화 묶음 JSON의 최상위 값은 사전이어야 합니다: %s" % path, path, ERR_INVALID_DATA)
		var bundle: Dictionary = parser.data
		var bundle_key_value: Variant = bundle.get("bundle_key")
		if typeof(bundle_key_value) == TYPE_STRING and not String(bundle_key_value).is_empty():
			var bundle_key := String(bundle_key_value)
			if bundle_keys.has(bundle_key):
				return _input_failure("duplicate_bundle_key", "서로 다른 파일에 같은 대화 묶음 키가 있습니다: %s" % bundle_key, String(bundle.get("source_url", path)), ERR_ALREADY_EXISTS)
			bundle_keys[bundle_key] = path
		bundles.append(bundle)
	return {"ok":true, "bundles":bundles, "issues":[], "error":OK, "code":"loaded", "message":""}

static func _input_failure(code: String, message: String, source: String, error: Error) -> Dictionary:
	var issue := {"severity":"error", "code":code, "message":message, "source_id":"", "source_url":source, "bundle_key":"", "event_key":"", "flow_key":"", "node_id":""}
	return {"ok":false, "bundles":[], "graphs":{}, "events":{}, "source_map":{}, "artifacts":{}, "manifest":{}, "issues":[issue], "counts":{}, "error":error, "code":code, "message":message}

static func _count_bundles(bundles: Array[Dictionary]) -> Dictionary:
	var counts := {"bundles":bundles.size(), "events":0, "flows":0, "lines":0, "choices":0}
	for bundle: Dictionary in bundles:
		var triggers_value: Variant = bundle.get("triggers", [])
		if typeof(triggers_value) != TYPE_ARRAY:
			continue
		for trigger_value: Variant in triggers_value:
			if typeof(trigger_value) != TYPE_DICTIONARY:
				continue
			var events_value: Variant = (trigger_value as Dictionary).get("events", [])
			if typeof(events_value) != TYPE_ARRAY:
				continue
			counts["events"] += events_value.size()
			for event_value: Variant in events_value:
				if typeof(event_value) != TYPE_DICTIONARY:
					continue
				var flows_value: Variant = (event_value as Dictionary).get("flows", [])
				if typeof(flows_value) != TYPE_ARRAY:
					continue
				counts["flows"] += flows_value.size()
				for flow_value: Variant in flows_value:
					if typeof(flow_value) != TYPE_DICTIONARY:
						continue
					var blocks_value: Variant = (flow_value as Dictionary).get("blocks", [])
					if typeof(blocks_value) != TYPE_ARRAY:
						continue
					for block_value: Variant in blocks_value:
						if typeof(block_value) != TYPE_DICTIONARY:
							continue
						var block: Dictionary = block_value
						if String(block.get("type", "")) == "line":
							counts["lines"] += 1
						elif String(block.get("type", "")) == "choice" and typeof(block.get("items")) == TYPE_ARRAY:
							counts["choices"] += (block.get("items") as Array).size()
	return counts

static func _has_warnings(issues_value: Variant) -> bool:
	if typeof(issues_value) != TYPE_ARRAY:
		return false
	for issue_value: Variant in issues_value:
		if typeof(issue_value) == TYPE_DICTIONARY and String((issue_value as Dictionary).get("severity", "error")) == "warning":
			return true
	return false

static func _paths_overlap(left: String, right: String) -> bool:
	var left_absolute := ProjectSettings.globalize_path(left.simplify_path()).replace("\\", "/").trim_suffix("/").to_lower()
	var right_absolute := ProjectSettings.globalize_path(right.simplify_path()).replace("\\", "/").trim_suffix("/").to_lower()
	if left_absolute.is_empty() or right_absolute.is_empty():
		return false
	return left_absolute == right_absolute or left_absolute.begins_with(right_absolute + "/") or right_absolute.begins_with(left_absolute + "/")

static func _publish_message(error: Error, recovery: Dictionary) -> String:
	if error != OK:
		if String(recovery.get("code", "")) == "rollback_failed":
			return "대화 게시와 자동 복구에 실패했습니다(%d). 보존된 백업(%s)과 검증 복구본(%s)을 확인하세요." % [error, recovery.get("backup_path", ""), recovery.get("recovery_path", "")]
		if not String(recovery.get("backup_path", "")).is_empty():
			return "대화 게시에 실패했습니다(%d). 보존된 백업 또는 차단 잔여물을 확인하세요: %s" % [error, recovery.get("backup_path", "")]
		return "대화 게시에 실패했습니다(%d). 마지막 정상 스냅샷은 교체되지 않았습니다." % error
	match String(recovery.get("code", "")):
		"backup_cleanup_residue":
			return "대화 게시를 완료했지만 백업 정리 잔여물이 남았습니다. 다음 게시 전에 확인하세요: %s" % recovery.get("backup_path", "")
		"transaction_cleanup_residue":
			return "대화 게시를 완료했지만 임시 정리 잔여물이 남았습니다. 확인하세요: %s" % recovery.get("temporary_path", "")
		_:
			return "검증된 대화 스냅샷을 게시했습니다."

func _argument_value(args: PackedStringArray, name: String, fallback: String) -> String:
	var index := args.find(name)
	return args[index + 1] if index >= 0 and index + 1 < args.size() else fallback
