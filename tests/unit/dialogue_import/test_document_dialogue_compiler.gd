extends "res://tests/support/test_case.gd"

const COMPILER_PATH := "res://tools/dialogue_import/document_dialogue_compiler.gd"
const FIXTURE_PATH := "res://tests/fixtures/dialogue_import/dialogue_bundle_fixture_factory.gd"
const CATALOG_PATH := "res://game/narrative/catalog/narrative_catalog.gd"
const CHARACTERS_PATH := "res://data/characters/character_registry.tres"

func run() -> void:
	assert_true(ResourceLoader.exists(COMPILER_PATH, "Script"), "document dialogue compiler script exists")
	if not ResourceLoader.exists(COMPILER_PATH, "Script"):
		return
	var compiler: Variant = load(COMPILER_PATH)
	var fixture: Variant = load(FIXTURE_PATH)
	var catalog_script: Variant = load(CATALOG_PATH)
	var catalog: Variant = catalog_script.from_dictionary(_catalog_data())
	var characters: Resource = load(CHARACTERS_PATH)
	_validate_complete_graph(compiler, fixture, catalog, characters)
	_validate_result_timing(compiler, fixture, catalog, characters)
	_validate_loops_rejoins_and_later_choices(compiler, fixture, catalog, characters)
	_validate_comment_invariance(compiler, fixture, catalog, characters)
	_validate_nondefault_event_graph_errors(compiler, fixture, catalog, characters)

func _validate_complete_graph(compiler: Variant, fixture: Variant, catalog: Variant, characters: Resource) -> void:
	var result: Dictionary = _compile(compiler, fixture.valid_bundle(), catalog, characters)
	assert_true(result.get("ok", false), "valid document bundle compiles")
	if not result.get("ok", false):
		return
	var graph: Dictionary = result["graphs"]["foundation.inspect"]
	assert_eq(graph["schema_version"], 1, "runtime graph schema remains compatible")
	assert_true(graph["nodes"].size() > 6, "all event flows share one bundle graph")
	var candidates: Array = result["events"]["bundles"]["foundation.inspect"]["triggers"]["mirror.inspect"]
	assert_eq(candidates.size(), 2, "trigger retains both ordered events")
	assert_eq(candidates[0]["event_key"], "seen", "specific event remains first")
	assert_eq(candidates[1]["event_key"], "default", "fallback remains last")
	assert_eq(candidates[0]["conditions"], [{"kind":"flag", "key":"mirror_seen", "operator":"eq", "value":true}], "authoring provenance is stripped from runtime conditions")
	assert_eq(graph["entry_node"], candidates[0]["entry_node"], "default graph entry is the first trigger's first event")
	assert_true(graph["nodes"].has(candidates[1]["entry_node"]), "fallback event entry is part of the same graph")
	assert_eq(result["artifacts"]["foundation_inspect.json"], graph, "bundle graph is exposed as an artifact")
	assert_eq(result["artifacts"]["events.json"], result["events"], "ordered event index is exposed as an artifact")
	assert_eq(result["artifacts"]["source_map.json"], result["source_map"], "source map is exposed as an artifact")
	assert_false(result["artifacts"].has("manifest.json"), "manifest is not duplicated in artifacts")
	assert_eq(result["manifest"]["files"]["foundation_inspect.json"], compiler.stable_json(graph).sha256_text(), "manifest hashes stable graph bytes")
	var repeated: Dictionary = _compile(compiler, fixture.valid_bundle(), catalog, characters)
	for field: String in ["graphs", "events", "source_map", "artifacts"]:
		assert_eq(compiler.stable_json(result[field]), compiler.stable_json(repeated[field]), "%s compilation is byte-identical" % field)
	var first_manifest: Dictionary = result["manifest"].duplicate(true)
	var second_manifest: Dictionary = repeated["manifest"].duplicate(true)
	first_manifest.erase("generated_at")
	second_manifest.erase("generated_at")
	assert_eq(compiler.stable_json(first_manifest), compiler.stable_json(second_manifest), "manifest is deterministic apart from generated_at")
	var source_json: String = compiler.stable_json(result["source_map"])
	assert_true(source_json.contains("notion-block-start-1") and source_json.contains("https://www.notion.so/foundation"), "source map preserves normalized source identity and URL")
	assert_false(source_json.contains("이 메모는 출력에 영향을 주지 않는다"), "source map excludes comment text")

func _validate_result_timing(compiler: Variant, fixture: Variant, catalog: Variant, characters: Resource) -> void:
	var bundle: Dictionary = fixture.valid_bundle()
	var default_event: Dictionary = bundle["triggers"][0]["events"][1]
	default_event["flows"][0]["effects"] = [_effect("젤리뽀의 신뢰", "stat_add", "jellyppo_trust", 2)]
	default_event["flows"][0]["blocks"][2]["items"][0]["effects"] = [_effect("거울을 자세히 봄", "flag_set", "mirror_seen", true)]
	var result: Dictionary = _compile(compiler, bundle, catalog, characters)
	assert_true(result.get("ok", false), "timing fixture compiles")
	if not result.get("ok", false):
		return
	var graph: Dictionary = result["graphs"]["foundation.inspect"]
	var source_map: Dictionary = result["source_map"]
	var first_choice_id := _node_for_source(source_map, "notion-block-choice-1")
	var inspect_entry := _node_for_source(source_map, "notion-block-inspect")
	var choice_node: Dictionary = graph["nodes"][first_choice_id]
	var inspect_item: Dictionary = choice_node["items"][0]
	assert_eq(inspect_item["effects"], [{"kind":"flag_set", "key":"mirror_seen", "value":true}], "choice result stays on its choice item")
	var flow_effect_id := String(inspect_item["next"])
	assert_eq(graph["nodes"][flow_effect_id]["effects"], [{"kind":"stat_add", "key":"jellyppo_trust", "value":2}], "flow result executes after the choice result")
	assert_eq(graph["nodes"][flow_effect_id]["next"], inspect_entry, "flow transition does not apply event results")
	var event_transition: Dictionary = bundle.duplicate(true)
	var transition_event: Dictionary = event_transition["triggers"][0]["events"][1]
	transition_event["flows"][0]["effects"] = [_effect("거울을 자세히 봄", "flag_set", "mirror_seen", true)]
	transition_event["flows"][0]["blocks"][2]["items"][0]["target_kind"] = "event"
	transition_event["flows"][0]["blocks"][2]["items"][0]["target_key"] = "seen"
	var transitioned: Dictionary = _compile(compiler, event_transition, catalog, characters)
	assert_true(transitioned.get("ok", false), "same-page event transition compiles")
	if not transitioned.get("ok", false):
		return
	var transitioned_graph: Dictionary = transitioned["graphs"]["foundation.inspect"]
	var transitioned_choice_id := _node_for_source(transitioned["source_map"], "notion-block-choice-1")
	var transitioned_item: Dictionary = transitioned_graph["nodes"][transitioned_choice_id]["items"][0]
	var transition_flow_effect := String(transitioned_item["next"])
	var transition_event_effect := String(transitioned_graph["nodes"][transition_flow_effect]["next"])
	assert_eq(transitioned_graph["nodes"][transition_flow_effect]["effects"], [{"kind":"flag_set", "key":"mirror_seen", "value":true}], "event transition applies the current flow result first")
	assert_eq(transitioned_graph["nodes"][transition_event_effect]["effects"], [{"kind":"stat_add", "key":"jellyppo_trust", "value":1}], "event transition applies the current event result second")
	assert_eq(transitioned_graph["nodes"][transition_event_effect]["next"], transitioned["events"]["bundles"]["foundation.inspect"]["triggers"]["mirror.inspect"][0]["entry_node"], "event result leads to the destination event")
	var rejoin_line_id := _node_for_source(source_map, "notion-block-rejoin")
	var rejoin_flow_effect := String(graph["nodes"][rejoin_line_id]["next"])
	var rejoin_event_effect := String(graph["nodes"][rejoin_flow_effect]["next"])
	var authored_end := String(graph["nodes"][rejoin_event_effect]["next"])
	assert_eq(graph["nodes"][rejoin_flow_effect]["effects"], [{"kind":"flag_set", "key":"mirror_seen", "value":true}], "normal end applies flow results")
	assert_eq(graph["nodes"][rejoin_event_effect]["effects"], [{"kind":"stat_add", "key":"jellyppo_trust", "value":1}], "normal end applies event results after flow results")
	assert_eq(graph["nodes"][authored_end]["type"], "end", "authored end remains a real end node")

func _validate_loops_rejoins_and_later_choices(compiler: Variant, fixture: Variant, catalog: Variant, characters: Resource) -> void:
	var bundle: Dictionary = fixture.valid_bundle()
	bundle["triggers"][0]["events"][1]["flows"][2]["blocks"][1]["target_key"] = "start"
	var result: Dictionary = _compile(compiler, bundle, catalog, characters)
	assert_true(result.get("ok", false), "a branch may loop back to a previous flow when the cycle has an exit")
	if not result.get("ok", false):
		return
	var graph: Dictionary = result["graphs"]["foundation.inspect"]
	var source_map: Dictionary = result["source_map"]
	var jump_id := _node_for_source(source_map, "notion-block-jump")
	var start_entry := _node_for_source(source_map, "notion-block-start-1")
	assert_eq(graph["nodes"][jump_id]["next"], start_entry, "jump can return to a prior flow")
	var later_choice_id := _node_for_source(source_map, "notion-block-choice-2")
	var inspect_line_id := _node_for_source(source_map, "notion-block-inspect")
	var command_id := _node_for_source(source_map, "notion-block-command")
	assert_eq(graph["nodes"][inspect_line_id]["next"], command_id, "later choice follows preceding dialogue")
	assert_eq(graph["nodes"][command_id]["next"], later_choice_id, "later choice follows intervening command")
	var later_choice: Dictionary = graph["nodes"][later_choice_id]
	var rejoin_entry := _node_for_source(source_map, "notion-block-rejoin")
	assert_eq(later_choice["items"][0]["next"], rejoin_entry, "one branch enters the shared rejoin flow")

func _validate_comment_invariance(compiler: Variant, fixture: Variant, catalog: Variant, characters: Resource) -> void:
	var replaced: Dictionary = fixture.valid_bundle()
	_replace_comments(replaced)
	var removed: Dictionary = fixture.valid_bundle()
	_remove_comments(removed)
	var replaced_result: Dictionary = _compile(compiler, replaced, catalog, characters)
	var removed_result: Dictionary = _compile(compiler, removed, catalog, characters)
	assert_true(replaced_result.get("ok", false) and removed_result.get("ok", false), "comment variants compile")
	assert_eq(compiler.stable_json(replaced_result.get("artifacts", {})), compiler.stable_json(removed_result.get("artifacts", {})), "comments never change runtime artifacts")

func _validate_nondefault_event_graph_errors(compiler: Variant, fixture: Variant, catalog: Variant, characters: Resource) -> void:
	var bundle: Dictionary = fixture.valid_bundle()
	var seen_flow: Dictionary = bundle["triggers"][0]["events"][0]["flows"][0]
	seen_flow["blocks"] = [{"type":"jump", "source_id":"notion-block-hidden-loop", "target_kind":"flow", "target_key":"start"}]
	var result: Dictionary = _compile(compiler, bundle, catalog, characters)
	assert_false(result.get("ok", true), "a bad non-default event invalidates the bundle graph")
	var issue := _issue_with_code(result.get("issues", []), "cycle_without_exit")
	assert_false(issue.is_empty(), "compiler passes every event entry through graph validation")
	assert_eq(issue.get("source_url", ""), "https://www.notion.so/foundation", "compiler graph issues retain the normalized source URL")

func _node_for_source(source_map: Dictionary, source_id: String) -> String:
	for entry_value: Variant in source_map.get("sources", []):
		if typeof(entry_value) == TYPE_DICTIONARY and entry_value.get("source_id", "") == source_id:
			return String(entry_value.get("node_id", ""))
	return ""

func _compile(compiler: Variant, bundle: Dictionary, catalog: Variant, characters: Resource) -> Dictionary:
	var bundles: Array[Dictionary] = [bundle]
	return compiler.compile_bundles(bundles, catalog, characters)

func _issue_with_code(issues: Array, code: String) -> Dictionary:
	for issue_value: Variant in issues:
		if typeof(issue_value) == TYPE_DICTIONARY and issue_value.get("code", "") == code:
			return issue_value
	return {}

func _replace_comments(value: Variant) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		var dictionary: Dictionary = value
		var had_comments := dictionary.has("comments")
		for key: Variant in dictionary.keys():
			if key != "comments":
				_replace_comments(dictionary[key])
		if had_comments:
			dictionary["comments"] = [{"text":"완전히 다른 논의"}]
	elif typeof(value) == TYPE_ARRAY:
		for child: Variant in value:
			_replace_comments(child)

func _remove_comments(value: Variant) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		(value as Dictionary).erase("comments")
		for child: Variant in (value as Dictionary).values():
			_remove_comments(child)
	elif typeof(value) == TYPE_ARRAY:
		for child: Variant in value:
			_remove_comments(child)

func _effect(term_name: String, kind: String, key: String, value: Variant) -> Dictionary:
	return {"source_text":term_name, "term_name":term_name, "mapping_status":"exact", "kind":kind, "key":key, "value":value}

func _catalog_data() -> Dictionary:
	return {"schema_version":1, "terms":[
		{"kind":"flag", "key":"mirror_seen", "display_name":"거울을 자세히 봄", "description":"거울 상태", "aliases":[], "default":false},
		{"kind":"stat", "key":"jellyppo_trust", "display_name":"젤리뽀의 신뢰", "description":"신뢰", "aliases":[], "default":0, "minimum":-10, "maximum":10}
	], "triggers":[{"key":"mirror.inspect", "display_name":"거울 조사", "description":"거울", "aliases":[]}], "commands":[{"key":"dialogue.advance", "display_name":"대화 진행", "description":"대화", "aliases":[], "arguments":{"speed":"int"}}]}
