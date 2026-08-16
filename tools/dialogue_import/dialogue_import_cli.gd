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
	var parsed := _parse_arguments(args)
	if not parsed.get("ok", false):
		_present_result(parsed, false)
		_terminate(1)
		return
	var dry_run: bool = parsed["dry_run"]
	var result := run_import(String(parsed["input_dir"]), String(parsed["output_dir"]), dry_run, bool(parsed["allow_warnings"]))
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
	compiled["preview"] = _build_preview(bundles, compiled, output_dir) if compiled.get("ok", false) else {"mappings":[], "changes":[]}
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
	var preview_value: Variant = result.get("preview", {})
	if typeof(preview_value) == TYPE_DICTIONARY:
		for mapping_value: Variant in (preview_value as Dictionary).get("mappings", []):
			if typeof(mapping_value) != TYPE_DICTIONARY:
				continue
			var mapping: Dictionary = mapping_value
			stdout.append("연결 · %s → %s (%s · %s; 범위: %s)" % [mapping.get("source_text", ""), mapping.get("key", ""), mapping.get("category", ""), mapping.get("role", ""), mapping.get("scope", "")])
		for change_value: Variant in (preview_value as Dictionary).get("changes", []):
			if typeof(change_value) != TYPE_DICTIONARY:
				continue
			var change: Dictionary = change_value
			var change_line := "변경 · %s · %s (`%s`) — %s" % [change.get("kind", ""), change.get("name", ""), change.get("key", ""), change.get("status", "")]
			var scope := String(change.get("scope", ""))
			if not scope.is_empty():
				change_line += " (범위: %s)" % scope
			stdout.append(change_line)
	return {"stdout":stdout, "stderr":stderr}

static func exit_code_for(result: Dictionary) -> int:
	return 0 if bool(result.get("ok", false)) else 1

static func _parse_arguments(args: PackedStringArray) -> Dictionary:
	var result := {"ok":true, "input_dir":DEFAULT_INPUT_DIR, "output_dir":DEFAULT_OUTPUT_DIR, "dry_run":false, "allow_warnings":false}
	var seen: Dictionary = {}
	var index := 0
	while index < args.size():
		var option := args[index]
		if option not in ["--input-dir", "--output-dir", "--dry-run", "--allow-warnings"] or seen.has(option):
			return _argument_failure()
		seen[option] = true
		if option in ["--dry-run", "--allow-warnings"]:
			result["dry_run" if option == "--dry-run" else "allow_warnings"] = true
			index += 1
			continue
		if index + 1 >= args.size():
			return _argument_failure()
		var value := String(args[index + 1])
		if value.is_empty() or value.begins_with("--"):
			return _argument_failure()
		result["input_dir" if option == "--input-dir" else "output_dir"] = value
		index += 2
	return result

static func _argument_failure() -> Dictionary:
	var message := "명령줄 인수가 올바르지 않습니다. 지원되는 옵션과 값을 확인하세요."
	var issue := {"severity":"error", "code":"invalid_arguments", "message":message, "source_id":"", "source_url":"", "bundle_key":"", "event_key":"", "flow_key":"", "node_id":""}
	return {"ok":false, "graphs":{}, "events":{}, "source_map":{}, "artifacts":{}, "manifest":{}, "issues":[issue], "counts":{}, "error":ERR_INVALID_PARAMETER, "code":"invalid_arguments", "message":message}

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

static func _build_preview(bundles: Array[Dictionary], compiled: Dictionary, output_dir: String) -> Dictionary:
	var mappings: Array[Dictionary] = []
	var changes: Array[Dictionary] = []
	var old_events := _read_json_dictionary(output_dir.path_join("events.json"))
	var ordered_bundles: Array[Dictionary] = bundles.duplicate(true)
	ordered_bundles.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return String(left.get("bundle_key", "")) < String(right.get("bundle_key", "")))
	for bundle: Dictionary in ordered_bundles:
		var bundle_key := String(bundle.get("bundle_key", ""))
		var bundle_name := String(bundle.get("title", bundle_key))
		var graph: Dictionary = compiled.get("graphs", {}).get(bundle_key, {})
		var old_graph := _read_json_dictionary(output_dir.path_join(_bundle_filename(bundle_key)))
		changes.append(_change_record("묶음", bundle_name, bundle_key, _change_status(old_graph, graph), "", "0|%s" % bundle_key))
		for trigger_value: Variant in bundle.get("triggers", []):
			if typeof(trigger_value) != TYPE_DICTIONARY:
				continue
			var trigger: Dictionary = trigger_value
			var trigger_key := String(trigger.get("trigger_key", ""))
			var trigger_name := String(trigger.get("name", trigger_key))
			for event_value: Variant in trigger.get("events", []):
				if typeof(event_value) != TYPE_DICTIONARY:
					continue
				var event: Dictionary = event_value
				var event_key := String(event.get("event_key", ""))
				var event_name := String(event.get("name", event_key))
				var event_scope := " / ".join(PackedStringArray([bundle_name, trigger_name]))
				var event_signature := {"candidate":_event_candidate(compiled.get("events", {}), bundle_key, trigger_key, event_key), "nodes":_node_subset(graph, event_key + ".")}
				var old_event_signature := {"candidate":_event_candidate(old_events, bundle_key, trigger_key, event_key), "nodes":_node_subset(old_graph, event_key + ".")}
				changes.append(_change_record("이벤트", event_name, event_key, _change_status(old_event_signature if not old_graph.is_empty() else {}, event_signature), event_scope, "1|%s|%s|%s" % [bundle_key, trigger_key, event_key]))
				var base_scope := " / ".join(PackedStringArray([bundle_name, trigger_name, event_name]))
				_append_mapping_records(mappings, event.get("conditions", []), "조건", base_scope)
				_append_mapping_records(mappings, event.get("effects", []), "이벤트 결과", base_scope)
				for flow_value: Variant in event.get("flows", []):
					if typeof(flow_value) != TYPE_DICTIONARY:
						continue
					var flow: Dictionary = flow_value
					var flow_key := String(flow.get("flow_key", ""))
					var flow_name := String(flow.get("name", flow_key))
					var flow_scope := base_scope
					var flow_prefix := "%s.%s." % [event_key, flow_key]
					changes.append(_change_record("흐름", flow_name, flow_key, _change_status(_node_subset(old_graph, flow_prefix), _node_subset(graph, flow_prefix)), flow_scope, "2|%s|%s|%s|%s" % [bundle_key, trigger_key, event_key, flow_key]))
					var mapping_scope := "%s / %s" % [base_scope, flow_name]
					_append_mapping_records(mappings, flow.get("effects", []), "흐름 결과", mapping_scope)
					for block_value: Variant in flow.get("blocks", []):
						if typeof(block_value) != TYPE_DICTIONARY or String((block_value as Dictionary).get("type", "")) != "choice":
							continue
						for item_value: Variant in (block_value as Dictionary).get("items", []):
							if typeof(item_value) != TYPE_DICTIONARY:
								continue
							var item: Dictionary = item_value
							var choice_scope := "%s / 선택지 · %s" % [mapping_scope, String(item.get("text", ""))]
							_append_mapping_records(mappings, item.get("conditions", []), "선택지 조건", choice_scope)
							_append_mapping_records(mappings, item.get("effects", []), "선택지 결과", choice_scope)
	mappings.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return String(left.get("sort_key", "")) < String(right.get("sort_key", "")))
	changes.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return String(left.get("sort_key", "")) < String(right.get("sort_key", "")))
	for mapping: Dictionary in mappings:
		mapping.erase("sort_key")
	for change: Dictionary in changes:
		change.erase("sort_key")
	return {"mappings":mappings, "changes":changes}

static func _append_mapping_records(result: Array[Dictionary], records_value: Variant, role: String, scope: String) -> void:
	if typeof(records_value) != TYPE_ARRAY:
		return
	for record_value: Variant in records_value:
		if typeof(record_value) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = record_value
		var source_text := String(record.get("source_text", "")).strip_edges()
		var key := String(record.get("key", "")).strip_edges()
		if source_text.is_empty() or key.is_empty():
			continue
		result.append({"source_text":source_text, "key":key, "category":_mapping_category(String(record.get("kind", ""))), "role":role, "scope":scope, "sort_key":"%s|%s|%s|%s" % [scope, role, source_text, key]})

static func _mapping_category(kind: String) -> String:
	if kind.begins_with("flag"):
		return "사건 상태"
	if kind.begins_with("stat"):
		return "수치 상태"
	if kind.begins_with("inventory"):
		return "소지품"
	if kind.begins_with("quest"):
		return "퀘스트"
	if kind.begins_with("collectible"):
		return "수집품"
	return "서사 상태"

static func _change_record(kind: String, name: String, key: String, status: String, scope: String, sort_key: String) -> Dictionary:
	return {"kind":kind, "name":name, "key":key, "status":status, "scope":scope, "sort_key":sort_key}

static func _change_status(previous: Dictionary, current: Dictionary) -> String:
	if previous.is_empty():
		return "추가"
	return "변경 없음" if Compiler.stable_json(_canonical_compare(previous)) == Compiler.stable_json(_canonical_compare(current)) else "변경"

static func _canonical_compare(value: Variant) -> Variant:
	if typeof(value) == TYPE_FLOAT and float(value) == floor(float(value)):
		return int(value)
	if typeof(value) == TYPE_DICTIONARY:
		var dictionary: Dictionary = {}
		for key: Variant in (value as Dictionary).keys():
			dictionary[key] = _canonical_compare((value as Dictionary)[key])
		return dictionary
	if typeof(value) == TYPE_ARRAY:
		var array: Array = []
		for child: Variant in value:
			array.append(_canonical_compare(child))
		return array
	return value

static func _read_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

static func _bundle_filename(bundle_key: String) -> String:
	return bundle_key.replace(".", "_") + ".json"

static func _event_candidate(events: Dictionary, bundle_key: String, trigger_key: String, event_key: String) -> Dictionary:
	var candidates_value: Variant = events.get("bundles", {}).get(bundle_key, {}).get("triggers", {}).get(trigger_key, [])
	if typeof(candidates_value) != TYPE_ARRAY:
		return {}
	for candidate_value: Variant in candidates_value:
		if typeof(candidate_value) == TYPE_DICTIONARY and String((candidate_value as Dictionary).get("event_key", "")) == event_key:
			return (candidate_value as Dictionary).duplicate(true)
	return {}

static func _node_subset(graph: Dictionary, prefix: String) -> Dictionary:
	var subset: Dictionary = {}
	var nodes_value: Variant = graph.get("nodes", {})
	if typeof(nodes_value) != TYPE_DICTIONARY:
		return subset
	for node_id_value: Variant in (nodes_value as Dictionary).keys():
		var node_id := String(node_id_value)
		if node_id.begins_with(prefix):
			subset[node_id] = (nodes_value as Dictionary)[node_id_value]
	return subset

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
