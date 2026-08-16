extends "res://tests/support/test_case.gd"

const CLI_PATH := "res://tools/dialogue_import/dialogue_import_cli.gd"
const HARNESS_PATH := "res://tests/support/dialogue_import_cli_harness.gd"
const FIXTURE_FACTORY_PATH := "res://tests/fixtures/dialogue_import/dialogue_bundle_fixture_factory.gd"
const COMPILER_PATH := "res://tools/dialogue_import/document_dialogue_compiler.gd"

var _test_root := ""

func run() -> void:
	assert_true(ResourceLoader.exists(CLI_PATH, "Script"), "manual dialogue import CLI exists")
	if not ResourceLoader.exists(CLI_PATH, "Script"):
		return
	var cli: Script = load(CLI_PATH)
	var fixture_factory: Script = load(FIXTURE_FACTORY_PATH)
	var compiler: Script = load(COMPILER_PATH)
	assert_not_null(cli, "manual dialogue import CLI loads")
	assert_not_null(fixture_factory, "document dialogue fixture factory loads")
	assert_not_null(compiler, "document dialogue compiler loads")
	if cli == null or fixture_factory == null or compiler == null:
		return
	_test_root = "user://test-output/dialogue-import-cli-%s" % Time.get_ticks_usec()
	assert_true(_test_root.begins_with("user://test-output/dialogue-import-cli-"), "CLI test root is uniquely confined")
	_test_input_failures(cli, fixture_factory)
	_test_dry_run_and_publish(cli, fixture_factory, compiler)
	_test_comments_do_not_affect_artifacts(cli, fixture_factory)
	_test_warning_confirmation(cli, fixture_factory)
	_test_failed_second_import_preserves_snapshot(cli, fixture_factory)
	_test_korean_result_formatting(cli, fixture_factory)
	_test_process_exit_seams(fixture_factory)
	_cleanup_exact_test_root()

func _test_input_failures(cli: Script, fixture_factory: Script) -> void:
	var missing: Dictionary = cli.run_import(_test_root.path_join("missing"), _test_root.path_join("missing-output"), true)
	assert_false(missing.get("ok", true), "missing input directory fails closed")
	assert_eq(missing.get("code"), "input_directory_missing", "missing input has a stable diagnostic")
	var empty_dir := _test_root.path_join("empty")
	_make_dir(empty_dir)
	var empty: Dictionary = cli.run_import(empty_dir, _test_root.path_join("empty-output"), true)
	assert_false(empty.get("ok", true), "empty input directory fails closed")
	assert_eq(empty.get("code"), "empty_input", "empty input has a stable diagnostic")
	var malformed_dir := _test_root.path_join("malformed")
	_make_dir(malformed_dir)
	_write_text(malformed_dir.path_join("broken.json"), "{")
	var malformed: Dictionary = cli.run_import(malformed_dir, _test_root.path_join("malformed-output"), true)
	assert_false(malformed.get("ok", true), "malformed JSON fails closed")
	assert_eq(malformed.get("code"), "parse_failed", "malformed JSON has a stable diagnostic")
	var root_dir := _test_root.path_join("invalid-root")
	_make_dir(root_dir)
	_write_text(root_dir.path_join("array.json"), "[]")
	var invalid_root: Dictionary = cli.run_import(root_dir, _test_root.path_join("root-output"), true)
	assert_false(invalid_root.get("ok", true), "non-dictionary JSON root fails closed")
	assert_eq(invalid_root.get("code"), "invalid_root", "non-dictionary root has a stable diagnostic")
	var duplicate_dir := _test_root.path_join("duplicate")
	_make_dir(duplicate_dir)
	_write_json(duplicate_dir.path_join("one.json"), _importable_bundle(fixture_factory))
	_write_json(duplicate_dir.path_join("two.json"), _importable_bundle(fixture_factory))
	var duplicate: Dictionary = cli.run_import(duplicate_dir, _test_root.path_join("duplicate-output"), true)
	assert_false(duplicate.get("ok", true), "duplicate bundle keys fail closed")
	assert_eq(duplicate.get("code"), "duplicate_bundle_key", "duplicate bundle key has a stable diagnostic")
	var overlap_parent := _test_root.path_join("overlap-parent")
	var overlap_input := overlap_parent.path_join("input")
	_make_dir(overlap_input)
	_write_json(overlap_input.path_join("bundle.json"), _importable_bundle(fixture_factory))
	var before_overlap := _snapshot_bytes(overlap_parent)
	var same_path: Dictionary = cli.run_import(overlap_input, overlap_input, false)
	assert_false(same_path.get("ok", true), "input directory cannot also be the publish directory")
	assert_eq(same_path.get("code"), "unsafe_output_overlap", "same input/output path has a stable safety diagnostic")
	assert_eq(_snapshot_bytes(overlap_parent), before_overlap, "same-path rejection preserves normalized authoring bytes")
	var parent_output: Dictionary = cli.run_import(overlap_input, overlap_parent, false)
	assert_false(parent_output.get("ok", true), "publish directory cannot contain the input directory")
	assert_eq(parent_output.get("code"), "unsafe_output_overlap", "parent output overlap has a stable safety diagnostic")
	assert_eq(_snapshot_bytes(overlap_parent), before_overlap, "parent-overlap rejection preserves normalized authoring bytes")
	var nested_output := overlap_input.path_join("generated")
	var child_output: Dictionary = cli.run_import(overlap_input, nested_output, false)
	assert_false(child_output.get("ok", true), "publish directory cannot be nested inside the input directory")
	assert_eq(child_output.get("code"), "unsafe_output_overlap", "child output overlap has a stable safety diagnostic")
	assert_eq(_snapshot_bytes(overlap_parent), before_overlap, "child-overlap rejection creates no generated files in authoring input")

func _test_dry_run_and_publish(cli: Script, fixture_factory: Script, compiler: Script) -> void:
	var input_dir := _test_root.path_join("valid-input")
	var output_dir := _test_root.path_join("published")
	_make_dir(input_dir)
	_write_json(input_dir.path_join("foundation.json"), _importable_bundle(fixture_factory))
	_write_json(input_dir.path_join("zeta.json"), _second_bundle(fixture_factory))
	var dry: Dictionary = cli.run_import(input_dir, output_dir, true)
	assert_true(dry.get("ok", false), "manual dry run validates every tracked bundle")
	assert_false(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output_dir)), "dry run writes nothing")
	assert_eq(dry.get("counts", {}), {"bundles":2, "events":4, "flows":10, "lines":12, "choices":8}, "dry run reports every tracked bundle as one transaction")
	var published: Dictionary = cli.run_import(input_dir, output_dir, false)
	assert_true(published.get("ok", false), "manual import publishes validated artifacts")
	for filename: String in ["foundation_inspect.json", "zeta_room.json", "events.json", "source_map.json", "manifest.json"]:
		assert_true(FileAccess.file_exists(output_dir.path_join(filename)), "manual import publishes %s" % filename)
	var artifacts: Dictionary = published.get("artifacts", {})
	var manifest: Dictionary = published.get("manifest", {})
	for filename_value: Variant in artifacts:
		var filename := String(filename_value)
		var bytes := FileAccess.get_file_as_bytes(output_dir.path_join(filename))
		assert_eq(bytes.get_string_from_utf8(), compiler.stable_json(artifacts[filename]), "published artifact uses deterministic stable JSON: %s" % filename)
		assert_eq(bytes.get_string_from_utf8().sha256_text(), String((manifest.get("files", {}) as Dictionary).get(filename, "")), "manifest hashes published bytes: %s" % filename)

func _test_comments_do_not_affect_artifacts(cli: Script, fixture_factory: Script) -> void:
	var first_dir := _test_root.path_join("comments-first")
	var second_dir := _test_root.path_join("comments-second")
	_make_dir(first_dir)
	_make_dir(second_dir)
	var first: Dictionary = _importable_bundle(fixture_factory)
	var second: Dictionary = first.duplicate(true)
	second["comments"] = [{"text":"완전히 다른 페이지 댓글"}]
	second["triggers"][0]["events"][1]["flows"][0]["blocks"][0]["comments"] = [{"text":"본문 규칙이 아닌 줄 댓글"}]
	_write_json(first_dir.path_join("bundle.json"), first)
	_write_json(second_dir.path_join("bundle.json"), second)
	var first_result: Dictionary = cli.run_import(first_dir, _test_root.path_join("comments-output-a"), true)
	var second_result: Dictionary = cli.run_import(second_dir, _test_root.path_join("comments-output-b"), true)
	assert_true(first_result.get("ok", false) and second_result.get("ok", false), "comment variants both validate")
	assert_eq(first_result.get("artifacts", {}), second_result.get("artifacts", {}), "comments never affect deterministic runtime artifacts")
	assert_eq(first_result.get("preview", {}), second_result.get("preview", {}), "comments never affect deterministic mapping/change previews")

func _test_warning_confirmation(cli: Script, fixture_factory: Script) -> void:
	var input_dir := _test_root.path_join("warning-input")
	var output_dir := _test_root.path_join("warning-output")
	_make_dir(input_dir)
	var bundle: Dictionary = _importable_bundle(fixture_factory)
	bundle["triggers"][0]["events"].pop_back()
	_write_json(input_dir.path_join("warning.json"), bundle)
	var dry: Dictionary = cli.run_import(input_dir, output_dir, true)
	assert_true(dry.get("ok", false), "dry run succeeds while surfacing warnings")
	assert_true(_has_issue(dry, "missing_fallback"), "dry run retains compiler warnings")
	var blocked: Dictionary = cli.run_import(input_dir, output_dir, false)
	assert_false(blocked.get("ok", true), "publish with unconfirmed warnings fails closed")
	assert_eq(blocked.get("code"), "warning_confirmation_required", "unconfirmed warning has a stable diagnostic")
	assert_false(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output_dir)), "unconfirmed warnings write nothing")
	var blocked_lines: Dictionary = cli.format_result_lines(blocked, false)
	var blocked_output := "\n".join(blocked_lines.get("stdout", [])) + "\n" + "\n".join(blocked_lines.get("stderr", []))
	assert_true(blocked_output.contains("대화 가져오기 검증 결과") and blocked_output.contains("묶음 1개") and blocked_output.contains("manifest SHA-256"), "warning confirmation failure still prints the complete review summary")
	var approved: Dictionary = cli.run_import(input_dir, output_dir, false, true)
	assert_true(approved.get("ok", false), "explicit warning approval permits publication")
	assert_true(FileAccess.file_exists(output_dir.path_join("manifest.json")), "approved warning publication writes the complete snapshot")

func _test_failed_second_import_preserves_snapshot(cli: Script, fixture_factory: Script) -> void:
	var input_dir := _test_root.path_join("preserve-input")
	var output_dir := _test_root.path_join("preserve-output")
	_make_dir(input_dir)
	_write_json(input_dir.path_join("bundle.json"), _importable_bundle(fixture_factory))
	var first: Dictionary = cli.run_import(input_dir, output_dir, false)
	assert_true(first.get("ok", false), "known-good snapshot is published before failure injection")
	var before := _snapshot_bytes(output_dir)
	_write_text(input_dir.path_join("bundle.json"), "{")
	var failed: Dictionary = cli.run_import(input_dir, output_dir, false)
	assert_false(failed.get("ok", true), "failed second import is reported")
	assert_eq(_snapshot_bytes(output_dir), before, "failed second import preserves every previous output byte")
	assert_eq(_snapshot_bytes(output_dir + ".tmp"), {}, "failed second import leaves no transaction residue")

func _test_korean_result_formatting(cli: Script, fixture_factory: Script) -> void:
	var input_dir := _test_root.path_join("format-input")
	var output_dir := _test_root.path_join("format-output")
	_make_dir(input_dir)
	var formatted_bundle: Dictionary = _importable_bundle(fixture_factory)
	formatted_bundle["comments"] = [{"text":"PROJECT_A_NOTION_TOKEN=super-secret-comment"}]
	_write_json(input_dir.path_join("bundle.json"), formatted_bundle)
	var result: Dictionary = cli.run_import(input_dir, output_dir, true)
	var lines: Dictionary = cli.format_result_lines(result, true)
	var combined := "\n".join(lines.get("stdout", [])) + "\n" + "\n".join(lines.get("stderr", []))
	assert_true(combined.contains("대화 가져오기 미리보기") and combined.contains("묶음 1개") and combined.contains("선택지 4개"), "CLI prints a Korean document summary")
	assert_true(combined.contains("manifest SHA-256"), "CLI prints the deterministic manifest digest")
	assert_true(combined.contains("연결 · 거울을 자세히 봄 → mirror_seen") and combined.contains("사건 상태 · 조건"), "dry run explains successful Korean-to-runtime mappings")
	assert_true(combined.contains("범위: 기초 방 / 거울 조사 / 이미 본 거울"), "mapping preview includes a concise human-facing scope")
	assert_true(combined.contains("변경 · 묶음 · 기초 방 (`foundation.inspect`) — 추가"), "dry run identifies a new dialogue bundle")
	assert_true(combined.contains("변경 · 이벤트 · 그 외 (`default`) — 추가"), "dry run identifies event-level changes")
	assert_true(combined.contains("변경 · 흐름 · 흐름 · 시작 (`start`) — 추가"), "dry run identifies flow-level changes")
	assert_false(combined.contains("super-secret-comment") or combined.contains("PROJECT_A_NOTION_TOKEN"), "mapping/change preview never prints comments or secret-shaped comment text")
	assert_eq(lines, cli.format_result_lines(result, true), "mapping/change preview formatting is deterministic")
	var published: Dictionary = cli.run_import(input_dir, output_dir, false)
	assert_true(published.get("ok", false), "preview baseline publishes for change comparison")
	var unchanged: Dictionary = cli.run_import(input_dir, output_dir, true)
	var unchanged_lines: Dictionary = cli.format_result_lines(unchanged, true)
	var unchanged_output := "\n".join(unchanged_lines.get("stdout", []))
	assert_true(unchanged_output.contains("변경 · 묶음 · 기초 방 (`foundation.inspect`) — 변경 없음"), "dry run reports an unchanged bundle against the published snapshot")
	formatted_bundle["triggers"][0]["events"][1]["flows"][0]["blocks"][0]["text"] = "바뀐 대사"
	_write_json(input_dir.path_join("bundle.json"), formatted_bundle)
	var changed: Dictionary = cli.run_import(input_dir, output_dir, true)
	var changed_lines: Dictionary = cli.format_result_lines(changed, true)
	var changed_output := "\n".join(changed_lines.get("stdout", []))
	assert_true(changed_output.contains("변경 · 묶음 · 기초 방 (`foundation.inspect`) — 변경"), "dry run reports a changed bundle")
	assert_true(changed_output.contains("변경 · 이벤트 · 그 외 (`default`) — 변경"), "dry run reports the changed event")
	assert_true(changed_output.contains("변경 · 흐름 · 흐름 · 시작 (`start`) — 변경"), "dry run reports the changed flow")
	var warning_bundle: Dictionary = _importable_bundle(fixture_factory)
	warning_bundle["triggers"][0]["events"].pop_back()
	_write_json(input_dir.path_join("bundle.json"), warning_bundle)
	var warning_result: Dictionary = cli.run_import(input_dir, _test_root.path_join("format-warning-output"), true)
	var warning_lines: Dictionary = cli.format_result_lines(warning_result, true)
	var warning_combined := "\n".join(warning_lines.get("stdout", [])) + "\n" + "\n".join(warning_lines.get("stderr", []))
	assert_true(warning_combined.contains("경고") and warning_combined.contains("missing_fallback"), "Korean preview includes stable warning diagnostics")
	assert_true(warning_combined.contains("https://www.notion.so/foundation"), "diagnostics include the source URL")
	assert_false(combined.contains("이 메모는 출력에 영향을 주지 않는다") or warning_combined.contains("이 메모는 출력에 영향을 주지 않는다"), "CLI never echoes comment bodies")
	var recovery_message: String = cli._publish_message(ERR_CANT_RESOLVE, {"code":"rollback_failed", "backup_path":"safe/dialogues.bak", "recovery_path":"safe/dialogues.tmp/recovery"})
	assert_true(recovery_message.contains("자동 복구") and recovery_message.contains("safe/dialogues.bak") and recovery_message.contains("safe/dialogues.tmp/recovery"), "rollback failure diagnostic identifies both preserved recovery artifacts")

func _test_process_exit_seams(fixture_factory: Script) -> void:
	assert_true(ResourceLoader.exists(HARNESS_PATH, "Script"), "CLI harness exists")
	if not ResourceLoader.exists(HARNESS_PATH, "Script"):
		return
	var harness_script: Script = load(HARNESS_PATH)
	assert_not_null(harness_script, "CLI harness loads")
	if harness_script == null:
		return
	var valid_dir := _test_root.path_join("harness-valid")
	var warning_dir := _test_root.path_join("harness-warning")
	_make_dir(valid_dir)
	_make_dir(warning_dir)
	_write_json(valid_dir.path_join("bundle.json"), _importable_bundle(fixture_factory))
	var warning_bundle: Dictionary = _importable_bundle(fixture_factory)
	warning_bundle["triggers"][0]["events"].pop_back()
	_write_json(warning_dir.path_join("bundle.json"), warning_bundle)
	var success_harness: SceneTree = harness_script.new()
	success_harness.install(PackedStringArray(["--input-dir", valid_dir, "--output-dir", _test_root.path_join("harness-dry-output"), "--dry-run"]))
	success_harness._run()
	assert_eq(success_harness.captured_exit_code, 0, "production _run terminates with zero on successful dry run")
	success_harness.free()
	var failure_harness: SceneTree = harness_script.new()
	failure_harness.install(PackedStringArray(["--input-dir", _test_root.path_join("missing-harness-input"), "--dry-run"]))
	failure_harness._run()
	assert_eq(failure_harness.captured_exit_code, 1, "production _run terminates nonzero on import errors")
	failure_harness.free()
	var warning_harness: SceneTree = harness_script.new()
	warning_harness.install(PackedStringArray(["--input-dir", warning_dir, "--output-dir", _test_root.path_join("harness-warning-output")]))
	warning_harness._run()
	assert_eq(warning_harness.captured_exit_code, 1, "production _run terminates nonzero for unconfirmed warnings")
	warning_harness.free()
	_test_malformed_argument_rejection(harness_script, valid_dir)

func _test_malformed_argument_rejection(harness_script: Script, valid_dir: String) -> void:
	var cases := [
		{"name":"missing value"},
		{"name":"flag-shaped value"},
		{"name":"unknown option"},
		{"name":"duplicate value option"},
		{"name":"duplicate boolean option"},
	]
	var case_index := 0
	for case_value: Variant in cases:
		var case_data: Dictionary = case_value
		var output_dir := _test_root.path_join("malformed-args-%d" % case_index)
		var args := PackedStringArray()
		match String(case_data["name"]):
			"missing value":
				args = PackedStringArray(["--output-dir", output_dir, "--input-dir"])
			"flag-shaped value":
				args = PackedStringArray(["--input-dir", "--dry-run", "--output-dir", output_dir])
			"unknown option":
				args = PackedStringArray(["--input-dir", valid_dir, "--output-dir", output_dir, "--unknown=super-secret-cli-value"])
			"duplicate value option":
				args = PackedStringArray(["--input-dir", valid_dir, "--input-dir", valid_dir, "--output-dir", output_dir])
			"duplicate boolean option":
				args = PackedStringArray(["--input-dir", valid_dir, "--output-dir", output_dir, "--dry-run", "--dry-run"])
		var harness: SceneTree = harness_script.new()
		harness.install(args)
		harness._run()
		assert_eq(harness.captured_exit_code, 1, "%s exits nonzero before import" % case_data["name"])
		assert_eq(harness.captured_result.get("code"), "invalid_arguments", "%s has a stable argument diagnostic" % case_data["name"])
		var combined := "\n".join(harness.captured_lines.get("stdout", [])) + "\n" + "\n".join(harness.captured_lines.get("stderr", []))
		assert_true(combined.contains("명령줄 인수가 올바르지 않습니다"), "%s reports a Korean argument diagnostic" % case_data["name"])
		assert_false(combined.contains("super-secret-cli-value"), "%s does not echo arbitrary argument values" % case_data["name"])
		assert_false(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output_dir)), "%s cannot publish any output" % case_data["name"])
		harness.free()
		case_index += 1

func _has_issue(result: Dictionary, code: String) -> bool:
	for issue_value: Variant in result.get("issues", []):
		if typeof(issue_value) == TYPE_DICTIONARY and String((issue_value as Dictionary).get("code", "")) == code:
			return true
	return false

func _importable_bundle(fixture_factory: Script) -> Dictionary:
	var bundle: Dictionary = fixture_factory.valid_bundle()
	var inspect_blocks: Array = bundle["triggers"][0]["events"][1]["flows"][1]["blocks"]
	inspect_blocks.remove_at(1)
	return bundle

func _second_bundle(fixture_factory: Script) -> Dictionary:
	var bundle := _importable_bundle(fixture_factory)
	bundle["bundle_key"] = "zeta.room"
	bundle["title"] = "두 번째 방"
	bundle["source_url"] = "https://www.notion.so/zeta-room"
	_prefix_source_ids(bundle, "zeta-")
	return bundle

func _prefix_source_ids(value: Variant, prefix: String) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		var dictionary: Dictionary = value
		if dictionary.has("source_id") and typeof(dictionary["source_id"]) == TYPE_STRING:
			dictionary["source_id"] = prefix + String(dictionary["source_id"])
		for child: Variant in dictionary.values():
			_prefix_source_ids(child, prefix)
	elif typeof(value) == TYPE_ARRAY:
		for child: Variant in value:
			_prefix_source_ids(child, prefix)

func _make_dir(path: String) -> void:
	assert_eq(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path)), OK, "test directory is created: %s" % path)

func _write_json(path: String, value: Variant) -> void:
	_write_text(path, JSON.stringify(value, "\t", true, true))

func _write_text(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file, "test fixture opens: %s" % path)
	if file != null:
		file.store_string(content)
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
	if _test_root.is_empty() or not _test_root.begins_with("user://test-output/dialogue-import-cli-"):
		return
	_remove_tree(_test_root)

func _remove_tree(path: String) -> Error:
	var absolute := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(absolute):
		return DirAccess.remove_absolute(absolute)
	if not DirAccess.dir_exists_absolute(absolute):
		return OK
	var directory := DirAccess.open(path)
	if directory == null:
		return DirAccess.get_open_error()
	for child_dir: String in directory.get_directories():
		var child_error := _remove_tree(path.path_join(child_dir))
		if child_error != OK:
			return child_error
	for filename: String in directory.get_files():
		var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path.path_join(filename)))
		if remove_error != OK:
			return remove_error
	return DirAccess.remove_absolute(absolute)
