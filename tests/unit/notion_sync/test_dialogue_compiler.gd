extends "res://tests/support/test_case.gd"

const COMPILER_PATH := "res://tools/notion_sync/dialogue_compiler.gd"
const CLI_PATH := "res://tools/notion_sync/notion_sync_cli.gd"
const FIXTURE_FACTORY_PATH := "res://tests/fixtures/notion/notion_fixture_factory.gd"

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
	_test_cli_dry_run_is_local_only(cli, fixture_factory)

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

func _test_existing_validator_reports_graph_errors(compiler: Variant, fixture_factory: Variant) -> void:
	var input: Dictionary = fixture_factory.valid_dialogue_input()
	input["blocks"][1]["effects"] = [{"kind":"unsafe_call", "key":"bad", "value":"run()"}]
	var result: Dictionary = compiler.compile(input)
	assert_false(result["ok"], "Plan 2 graph validation errors block compilation")
	assert_true(_has_issue(result["issues"], "invalid_effect", input["blocks"][1]["source_url"]), "validator issue is source-linked by the compiler")

func _test_cli_dry_run_is_local_only(cli: Variant, fixture_factory: Variant) -> void:
	var output_dir := "user://test-output/dialogue-cli-%s/dialogues" % Time.get_ticks_usec()
	var result: Dictionary = cli.run_mapped_input(fixture_factory.valid_dialogue_input(), output_dir, true)
	assert_true(result["ok"], "CLI dry run compiles mapped input without transport")
	assert_false(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output_dir)), "CLI dry run does not create a snapshot")

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
