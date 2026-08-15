extends "res://tests/support/test_case.gd"

const COMPILER_PATH := "res://tools/notion_sync/dialogue_compiler.gd"
const CLI_PATH := "res://tools/notion_sync/notion_sync_cli.gd"
const FIXTURE_FACTORY_PATH := "res://tests/fixtures/notion/notion_fixture_factory.gd"

var _request_count := 0

func run() -> void:
	assert_true(ResourceLoader.exists(COMPILER_PATH, "Script"), "dialogue compiler script exists")
	assert_true(ResourceLoader.exists(CLI_PATH, "Script"), "Notion sync CLI script exists")
	assert_true(ResourceLoader.exists(FIXTURE_FACTORY_PATH, "Script"), "Notion fixture factory exists")
	if not ResourceLoader.exists(COMPILER_PATH, "Script") or not ResourceLoader.exists(CLI_PATH, "Script") or not ResourceLoader.exists(FIXTURE_FACTORY_PATH, "Script"):
		return
	var compiler: Variant = load(COMPILER_PATH)
	var cli: Variant = load(CLI_PATH)
	var fixture_factory: Variant = load(FIXTURE_FACTORY_PATH)
	assert_not_null(compiler, "dialogue compiler loads")
	assert_not_null(cli, "Notion sync CLI loads")
	assert_not_null(fixture_factory, "Notion fixture factory loads")
	if compiler == null or cli == null or fixture_factory == null:
		return
	_test_deterministic_graph_compilation(compiler, fixture_factory)
	_test_source_linked_expression_policy(compiler, fixture_factory)
	_test_existing_validator_reports_graph_errors(compiler, fixture_factory)
	_test_flow_prerequisites_are_source_linked(compiler, fixture_factory)
	_test_grouped_choice_and_character_provenance(compiler, fixture_factory)
	_test_cross_platform_filename_namespace(compiler, fixture_factory)
	_test_automatic_node_shapes_and_tiebreaking(compiler, fixture_factory)
	await _test_cli_boundaries(cli, fixture_factory)

func _test_deterministic_graph_compilation(compiler: Variant, fixture_factory: Variant) -> void:
	var input: Dictionary = fixture_factory.valid_dialogue_input()
	input["scenes"].append({"scene_key":"alpha.end", "status":"Draft", "start_flow":"end", "notion_page_id":"scene0", "source_url":"https://notion.so/scene0"})
	input["blocks"].append({"notion_page_id":"alpha-end", "source_url":"https://notion.so/alpha-end", "scene_key":"alpha.end", "flow":"end", "order":1.0, "type":"end", "speaker":"", "expression":"", "text":"", "target_flow":"", "conditions":[], "effects":[], "command":{}})
	input["blocks"].append({"notion_page_id":"line0", "source_url":"https://notion.so/line0", "scene_key":"foundation.inspect", "flow":"main", "order":0.0, "type":"line", "speaker":"retti", "expression":"neutral", "text":"먼저 본다.", "target_flow":"", "conditions":[], "effects":[], "command":{}})
	input["blocks"].append({"notion_page_id":"choice2", "source_url":"https://notion.so/choice2", "scene_key":"foundation.inspect", "flow":"choice", "order":2.0, "type":"choice", "speaker":"", "expression":"", "text":"뒤로 물러난다", "target_flow":"end", "conditions":[], "effects":[], "command":{}})
	input["scenes"].reverse()
	input["blocks"].reverse()
	var result: Dictionary = compiler.compile(input)
	assert_true(result["ok"], "valid mapped Notion data compiles")
	assert_eq(result["issues"], [], "valid compile has no issues")
	assert_true(result["graphs"].has("foundation.inspect"), "scene graph is emitted")
	if not result["graphs"].has("foundation.inspect"):
		return
	var graph: Dictionary = result["graphs"]["foundation.inspect"]
	assert_eq(graph["schema_version"], 1, "compiled graph uses Plan 2 schema version")
	assert_eq(graph["entry_node"], "line0", "start flow resolves to its first sorted node")
	assert_eq(graph["nodes"]["line0"]["next"], "line1", "a row without an explicit target falls through in flow order")
	assert_eq(graph["nodes"]["line1"]["next"], "choice1", "target flow resolves to its first compiled node")
	assert_eq(graph["nodes"]["choice1"]["items"].size(), 2, "consecutive choice rows compile into one choice node")
	assert_eq(graph["nodes"]["choice1"]["items"][0]["text"], "자세히 본다", "choice items retain order and page-ID tiebreaking")
	assert_eq(graph["nodes"]["choice1"]["items"][1]["text"], "뒤로 물러난다", "later choice items retain their text")
	assert_eq(graph["nodes"]["choice1"]["items"][1]["next"], "end1", "choice targets resolve to the target flow entry")
	var manifest: Dictionary = result["manifest"]
	assert_eq(manifest["schema_version"], 1, "manifest schema version is one")
	assert_eq(manifest["scenes"], ["alpha.end", "foundation.inspect"], "manifest scene keys are sorted")
	assert_true(String(manifest["generated_at"]).ends_with("Z"), "manifest generation time is UTC")
	assert_eq(manifest["files"]["foundation_inspect.json"], compiler.stable_json(graph).sha256_text(), "manifest records the graph file SHA-256")
	assert_true(_has_source(manifest["sources"], "scene1", "https://notion.so/scene1"), "manifest records source page IDs and URLs")
	assert_eq(compiler.scene_filename("foundation.inspect"), "foundation_inspect.json", "dotted scene keys map to runtime filenames")

func _test_source_linked_expression_policy(compiler: Variant, fixture_factory: Variant) -> void:
	var final_input: Dictionary = fixture_factory.valid_dialogue_input()
	final_input["blocks"][0]["expression"] = "missing_expression"
	var final_result: Dictionary = compiler.compile(final_input)
	assert_false(final_result["ok"], "an unknown expression blocks a Final scene")
	assert_true(not final_result["issues"].is_empty(), "unknown expression produces an issue")
	if not final_result["issues"].is_empty():
		assert_eq(final_result["issues"][0]["code"], "unknown_expression", "compiler identifies a catalog mismatch")
		assert_eq(final_result["issues"][0]["severity"], "warning", "catalog mismatch is a review warning")
		assert_eq(final_result["issues"][0]["source_url"], final_input["blocks"][0]["source_url"], "issue links to the source block")
	var draft_input: Dictionary = fixture_factory.valid_dialogue_input()
	draft_input["scenes"][0]["status"] = "Draft"
	draft_input["blocks"][0]["expression"] = "missing_expression"
	var draft_result: Dictionary = compiler.compile(draft_input)
	assert_true(draft_result["ok"], "Draft scenes may retain expression warnings")
	assert_eq(draft_result["issues"][0]["severity"], "warning", "Draft catalog issue remains visible")
	var review_input: Dictionary = fixture_factory.valid_dialogue_input()
	review_input["scenes"][0]["status"] = "Review"
	review_input["blocks"][0]["expression"] = "missing_expression"
	var review_result: Dictionary = compiler.compile(review_input)
	assert_true(review_result["ok"], "Review scenes retain nonblocking warnings because only Final warnings fail")

func _test_existing_validator_reports_graph_errors(compiler: Variant, fixture_factory: Variant) -> void:
	var input: Dictionary = fixture_factory.valid_dialogue_input()
	input["blocks"][1]["effects"] = [{"kind":"unsafe_call", "key":"bad", "value":"run()"}]
	var result: Dictionary = compiler.compile(input)
	assert_false(result["ok"], "Plan 2 graph validation errors block compilation")
	assert_true(_has_issue(result["issues"], "invalid_effect", input["blocks"][1]["source_url"]), "validator issue is source-linked by the compiler")

func _test_flow_prerequisites_are_source_linked(compiler: Variant, fixture_factory: Variant) -> void:
	var cases: Array[Dictionary] = [
		{"name":"blank scene key", "code":"invalid_scene_key", "source":"scene", "mutate":func(input: Dictionary) -> void: input["scenes"][0]["scene_key"] = ""},
		{"name":"whitespace scene key", "code":"invalid_scene_key", "source":"scene", "mutate":func(input: Dictionary) -> void: input["scenes"][0]["scene_key"] = " \t"},
		{"name":"missing start flow", "code":"invalid_start_flow", "source":"scene", "mutate":func(input: Dictionary) -> void: input["scenes"][0].erase("start_flow")},
		{"name":"whitespace start flow", "code":"invalid_start_flow", "source":"scene", "mutate":func(input: Dictionary) -> void: input["scenes"][0]["start_flow"] = "  "},
		{"name":"blank block flow", "code":"invalid_flow", "source":"block0", "mutate":func(input: Dictionary) -> void: input["blocks"][0]["flow"] = ""},
		{"name":"whitespace block flow", "code":"invalid_flow", "source":"block0", "mutate":func(input: Dictionary) -> void: input["blocks"][0]["flow"] = " \t"},
		{"name":"missing terminal target flow", "code":"missing_target_flow", "source":"block1", "mutate":func(input: Dictionary) -> void: input["blocks"][1].erase("target_flow")},
		{"name":"whitespace terminal target flow", "code":"missing_target_flow", "source":"block1", "mutate":func(input: Dictionary) -> void: input["blocks"][1]["target_flow"] = "  "},
		{"name":"unknown target flow", "code":"unknown_target_flow", "source":"block0", "mutate":func(input: Dictionary) -> void: input["blocks"][0]["target_flow"] = "missing"}
	]
	for case: Dictionary in cases:
		var input: Dictionary = fixture_factory.valid_dialogue_input()
		var expected_url := String(input["scenes"][0]["source_url"]) if case["source"] == "scene" else String(input["blocks"][0 if case["source"] == "block0" else 1]["source_url"])
		case["mutate"].call(input)
		var result: Dictionary = compiler.compile(input)
		assert_false(result["ok"], "%s blocks graph success" % case["name"])
		assert_true(_has_issue(result["issues"], String(case["code"]), expected_url), "%s issue links to its actual Notion page" % case["name"])

func _test_grouped_choice_and_character_provenance(compiler: Variant, fixture_factory: Variant) -> void:
	var input: Dictionary = fixture_factory.valid_dialogue_input()
	var later_choice: Dictionary = input["blocks"][1].duplicate(true)
	later_choice["notion_page_id"] = "choice2"
	later_choice["source_url"] = "https://notion.so/choice2"
	later_choice["order"] = 2.0
	later_choice["conditions"] = [{"kind":"stat", "key":"score", "operator":"contains", "value":1}]
	later_choice["effects"] = [{"kind":"unsafe_call", "key":"bad", "value":"run()"}]
	input["blocks"].append(later_choice)
	var duplicate_character: Dictionary = input["characters"][0].duplicate(true)
	duplicate_character["notion_page_id"] = "char2"
	duplicate_character["source_url"] = "https://notion.so/char2"
	input["characters"].append(duplicate_character)
	input["characters"].append({"character_key":"", "default_expression":"neutral", "expressions":["neutral"], "notion_page_id":"char-empty", "source_url":"https://notion.so/char-empty"})
	var result: Dictionary = compiler.compile(input)
	assert_false(result["ok"], "grouped choice and character catalog validation errors fail")
	assert_true(_has_issue(result["issues"], "invalid_condition", later_choice["source_url"]), "later grouped choice condition links to its own page")
	assert_true(_has_issue(result["issues"], "invalid_effect", later_choice["source_url"]), "later grouped choice effect links to its own page")
	assert_true(_has_issue(result["issues"], "invalid_character_key", duplicate_character["source_url"]), "duplicate character issue links to the duplicate page")
	assert_true(_has_issue(result["issues"], "invalid_character_key", "https://notion.so/char-empty"), "empty character issue links to the empty-key page")

func _test_cross_platform_filename_namespace(compiler: Variant, fixture_factory: Variant) -> void:
	for scene_key: String in ["manifest", "CON", "bad:name", "bad*name", "bad/name"]:
		var input: Dictionary = fixture_factory.valid_dialogue_input()
		input["scenes"][0]["scene_key"] = scene_key
		for block: Dictionary in input["blocks"]:
			block["scene_key"] = scene_key
		var result: Dictionary = compiler.compile(input)
		assert_false(result["ok"], "unsafe scene key %s fails compilation" % scene_key)
		assert_true(_has_issue(result["issues"], "unsafe_scene_filename", input["scenes"][0]["source_url"]), "unsafe scene key %s is source-linked" % scene_key)
	var collision_input: Dictionary = fixture_factory.valid_dialogue_input()
	collision_input["scenes"].append({"scene_key":"foundation_inspect", "status":"Draft", "start_flow":"end", "notion_page_id":"collision-scene", "source_url":"https://notion.so/collision-scene"})
	collision_input["blocks"].append(_block("collision-end", "https://notion.so/collision-end", "foundation_inspect", "end", 1.0, "end", ""))
	var collision: Dictionary = compiler.compile(collision_input)
	assert_false(collision["ok"], "dot-to-underscore filename collision fails compilation")
	assert_true(_has_issue(collision["issues"], "duplicate_scene_filename", "https://notion.so/collision-scene"), "filename collision links to the later scene page")

func _test_automatic_node_shapes_and_tiebreaking(compiler: Variant, fixture_factory: Variant) -> void:
	var input: Dictionary = fixture_factory.valid_dialogue_input()
	input["scenes"][0]["start_flow"] = "main"
	input["blocks"] = [
		_block("line-b", "https://notion.so/line-b", "foundation.inspect", "main", 1.0, "line", "effects", {"speaker":"retti", "expression":"neutral", "text":"B"}),
		_block("line-a", "https://notion.so/line-a", "foundation.inspect", "main", 1.0, "line", "", {"speaker":"retti", "expression":"neutral", "text":"A"}),
		_block("effect1", "https://notion.so/effect1", "foundation.inspect", "effects", 1.0, "effect", "commands", {"effects":[{"kind":"flag_set", "key":"seen", "value":true}]}),
		_block("command1", "https://notion.so/command1", "foundation.inspect", "commands", 1.0, "command", "jumps", {"command":{"kind":"camera", "name":"shake"}}),
		_block("jump1", "https://notion.so/jump1", "foundation.inspect", "jumps", 1.0, "jump", "end"),
		_block("end1", "https://notion.so/end1", "foundation.inspect", "end", 1.0, "end", "")
	]
	var result: Dictionary = compiler.compile(input)
	assert_true(result["ok"], "line/effect/command/jump/end compilation is valid")
	var nodes: Dictionary = result["graphs"]["foundation.inspect"]["nodes"]
	assert_eq(result["graphs"]["foundation.inspect"]["entry_node"], "linea", "equal-order rows use notion_page_id as the real tiebreak")
	assert_eq(nodes["linea"]["next"], "lineb", "same-flow duplicate membership falls through deterministically")
	assert_eq(nodes["effect1"]["type"], "effect", "effect block compiles")
	assert_eq(nodes["command1"]["type"], "command", "command block compiles")
	assert_eq(nodes["jump1"]["type"], "jump", "jump block compiles")
	var duplicate_input: Dictionary = fixture_factory.valid_dialogue_input()
	var duplicate_block: Dictionary = duplicate_input["blocks"][2].duplicate(true)
	duplicate_block["flow"] = "other"
	duplicate_block["source_url"] = "https://notion.so/duplicate-node"
	duplicate_input["blocks"].append(duplicate_block)
	var duplicate_result: Dictionary = compiler.compile(duplicate_input)
	assert_false(duplicate_result["ok"], "duplicate stable node IDs fail compilation")
	assert_true(_has_issue(duplicate_result["issues"], "duplicate_node_id", duplicate_block["source_url"]), "duplicate node ID links to the duplicate block")

func _test_cli_boundaries(cli: Variant, fixture_factory: Variant) -> void:
	assert_true(_script_has_method(cli, "is_authorized_for"), "CLI exposes its explicit editor-binary authorization predicate")
	assert_true(_script_has_method(cli, "exit_code_for"), "CLI exposes deterministic process-exit mapping")
	if not _script_has_method(cli, "is_authorized_for") or not _script_has_method(cli, "exit_code_for"):
		return
	assert_false(cli.is_authorized_for(false, false, true, true), "CLI denies exported headless execution even with opt-in")
	assert_true(cli.is_authorized_for(false, true, true, true), "CLI allows explicit editor-binary headless execution")
	var test_root := "user://test-output/dialogue-cli-%s" % Time.get_ticks_usec()
	var output_dir := test_root.path_join("dialogues")
	var dry_run: Dictionary = cli.run_mapped_input(fixture_factory.valid_dialogue_input(), output_dir, true)
	assert_true(dry_run["ok"], "CLI dry run compiles mapped input without transport")
	assert_false(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output_dir)), "CLI dry run does not create a snapshot")
	var write_result: Dictionary = cli.run_mapped_input(fixture_factory.valid_dialogue_input(), output_dir, false)
	assert_true(write_result["ok"], "CLI mapped-input write path publishes a snapshot")
	assert_true(FileAccess.file_exists(output_dir.path_join("manifest.json")), "CLI write path publishes the manifest")
	_request_count = 0
	var transport_failure: Dictionary = await cli.sync({"token":"test-token", "scenes_data_source":"scene-source", "blocks_data_source":"block-source", "characters_data_source":"character-source"}, output_dir, true, Callable(self, "_service_failure"))
	assert_false(transport_failure["ok"], "CLI returns a recorded transport failure")
	assert_eq(_request_count, 1, "CLI stops after the first transport failure")
	assert_eq(cli.exit_code_for(transport_failure), 1, "CLI maps transport failure to process failure")
	_remove_exact_tree(test_root)

func _service_failure(_url: String, _headers: PackedStringArray, _body: String) -> Dictionary:
	_request_count += 1
	return {"status_code":503, "body":"{}"}

func _block(page_id: String, source_url: String, scene_key: String, flow: String, order: float, block_type: String, target_flow: String, overrides: Dictionary = {}) -> Dictionary:
	var block := {"notion_page_id":page_id, "source_url":source_url, "scene_key":scene_key, "flow":flow, "order":order, "type":block_type, "speaker":"", "expression":"", "text":"", "target_flow":target_flow, "conditions":[], "effects":[], "command":{}}
	block.merge(overrides, true)
	return block

func _remove_exact_tree(path: String) -> Error:
	if not path.begins_with("user://test-output/dialogue-cli-"):
		return ERR_INVALID_PARAMETER
	var absolute := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return OK
	var directory := DirAccess.open(path)
	if directory == null:
		return DirAccess.get_open_error()
	for child_dir: String in directory.get_directories():
		var child_error := _remove_exact_tree(path.path_join(child_dir))
		if child_error != OK:
			return child_error
	for filename: String in directory.get_files():
		var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path.path_join(filename)))
		if remove_error != OK:
			return remove_error
	return DirAccess.remove_absolute(absolute)

func _has_issue(issues: Array, code: String, source_url: String) -> bool:
	for issue_value: Variant in issues:
		if typeof(issue_value) == TYPE_DICTIONARY and issue_value.get("code", "") == code and issue_value.get("source_url", "") == source_url:
			return true
	return false

func _has_source(sources: Array, page_id: String, source_url: String) -> bool:
	for source_value: Variant in sources:
		if typeof(source_value) == TYPE_DICTIONARY and source_value.get("notion_page_id", "") == page_id and source_value.get("source_url", "") == source_url:
			return true
	return false

func _script_has_method(script: Script, method_name: String) -> bool:
	for method: Dictionary in script.get_script_method_list():
		if String(method.get("name", "")) == method_name:
			return true
	return false
