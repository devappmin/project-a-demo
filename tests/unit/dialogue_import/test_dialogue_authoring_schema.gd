extends "res://tests/support/test_case.gd"

const IDENTITY_PATH := "res://tools/dialogue_import/dialogue_identity.gd"
const SCHEMA_PATH := "res://tools/dialogue_import/dialogue_authoring_schema.gd"
const FIXTURE_PATH := "res://tests/fixtures/dialogue_import/dialogue_bundle_fixture_factory.gd"

func run() -> void:
	assert_true(ResourceLoader.exists(IDENTITY_PATH, "Script"), "dialogue identity script exists")
	assert_true(ResourceLoader.exists(SCHEMA_PATH, "Script"), "dialogue authoring schema script exists")
	if not ResourceLoader.exists(IDENTITY_PATH, "Script") or not ResourceLoader.exists(SCHEMA_PATH, "Script"):
		return
	var identity: Script = load(IDENTITY_PATH)
	var schema: Script = load(SCHEMA_PATH)
	var fixture: Script = load(FIXTURE_PATH)
	var catalog := NarrativeCatalog.from_dictionary(_catalog_data())
	var characters: Resource = load("res://data/characters/character_registry.tres")
	var bundle: Dictionary = fixture.valid_bundle()
	assert_eq(schema.validate_bundle(bundle, catalog, characters), [], "complete normalized bundle validates")
	var json_bundle: Dictionary = bundle.duplicate(true)
	json_bundle["schema_version"] = 1.0
	assert_eq(schema.validate_bundle(json_bundle, catalog, characters), [], "JSON numeric schema version 1 validates")
	_test_identity(identity)
	_test_stable_identity_through_comments_and_renames(identity, schema, fixture, catalog, characters)
	_test_choice_autosave_contract(schema, fixture, catalog, characters)
	_test_contract_failures(schema, fixture, catalog, characters)
	_test_fail_closed_shapes(schema, fixture, catalog, characters)
	_test_field_type_contract(schema, fixture, catalog, characters)
	_test_same_bundle_cross_trigger_event_target(schema, fixture, characters)
	_test_command_argument_contract(schema, fixture, characters)

func _test_identity(identity: Script) -> void:
	assert_eq(identity.stable_key("flow", "notion-flow-start", "start"), "start", "safe retained key wins")
	assert_eq(identity.stable_key("flow", "notion-flow-start", "bad key"), identity.stable_key("flow", "notion-flow-start"), "unsafe retained key falls back to source identity")
	assert_eq(identity.stable_key("flow", "", ""), "", "missing durable identity cannot make a stable key")
	for unsafe_key: String in ["", "manifest", "events", "source_map", "CON", "path/name", "space key"]:
		assert_eq(identity.stable_key("flow", "notion-flow-start", unsafe_key), identity.stable_key("flow", "notion-flow-start"), "unsafe key is never retained: %s" % unsafe_key)
	assert_eq(identity.node_id("default", "start", "notion-block-start-1"), "default.start.notion-block-start-1", "node identity preserves ordered authoring identity")

func _test_stable_identity_through_comments_and_renames(identity: Script, schema: Script, fixture: Script, catalog: NarrativeCatalog, characters: Resource) -> void:
	var before: Dictionary = fixture.valid_bundle()
	var after: Dictionary = before.duplicate(true)
	after["comments"] = [{"text":"다른 메모"}]
	after["triggers"][0]["comments"] = [{"text":"트리거 메모"}]
	var event: Dictionary = after["triggers"][0]["events"][1]
	event["name"] = "바뀐 사건 이름"
	event["comments"] = [{"text":"사건 메모"}]
	event["flows"][1]["name"] = "바뀐 흐름 이름"
	event["flows"][1]["comments"] = [{"text":"숨은 메모"}]
	event["flows"][1]["blocks"][2]["comments"] = [{"text":"블록 메모"}]
	event["flows"][1]["blocks"][2]["items"][0]["comments"] = [{"text":"선택지 메모"}]
	assert_eq(schema.validate_bundle(after, catalog, characters), [], "comments and Korean labels are ignored by the normalized contract")
	assert_eq(identity.stable_key("event", String(event["source_id"]), String(event["event_key"])), identity.stable_key("event", String(before["triggers"][0]["events"][1]["source_id"]), String(before["triggers"][0]["events"][1]["event_key"])), "retained event key survives Korean rename")
	event.erase("event_key")
	assert_eq(identity.stable_key("event", String(event["source_id"])), identity.stable_key("event", String(before["triggers"][0]["events"][1]["source_id"])), "source-derived event key survives title rename")

func _test_choice_autosave_contract(schema: Script, fixture: Script, catalog: NarrativeCatalog, characters: Resource) -> void:
	var absent: Dictionary = fixture.valid_bundle()
	assert_eq(schema.validate_bundle(absent, catalog, characters), [], "choice autosave is optional and absent means false")
	var enabled: Dictionary = fixture.valid_bundle()
	enabled["triggers"][0]["events"][1]["flows"][0]["blocks"][2]["autosave"] = true
	assert_eq(schema.validate_bundle(enabled, catalog, characters), [], "choice autosave accepts a Boolean")
	for invalid_value: Variant in ["true", 1]:
		var invalid: Dictionary = fixture.valid_bundle()
		invalid["triggers"][0]["events"][1]["flows"][0]["blocks"][2]["autosave"] = invalid_value
		assert_true(_has_issue(schema.validate_bundle(invalid, catalog, characters), "invalid_autosave", "error"), "choice autosave rejects non-Boolean values")
	var unrelated: Dictionary = fixture.valid_bundle()
	unrelated["triggers"][0]["events"][1]["flows"][0]["blocks"][0]["autosave"] = true
	assert_true(_has_issue(schema.validate_bundle(unrelated, catalog, characters), "invalid_line_block", "error"), "line blocks reject choice-only autosave")

func _test_contract_failures(schema: Script, fixture: Script, catalog: NarrativeCatalog, characters: Resource) -> void:
	_assert_issue(schema, fixture, catalog, characters, func(bundle: Dictionary): bundle.erase("schema_version"), "unsupported_schema_version")
	_assert_issue(schema, fixture, catalog, characters, func(bundle: Dictionary): bundle["schema_version"] = "1", "unsupported_schema_version")
	_assert_issue(schema, fixture, catalog, characters, func(bundle: Dictionary): bundle["schema_version"] = 2, "unsupported_schema_version")
	_assert_issue(schema, fixture, catalog, characters, func(bundle: Dictionary): bundle["triggers"][0]["events"][1]["flows"][2]["name"] = bundle["triggers"][0]["events"][1]["flows"][1]["name"], "duplicate_flow_name")
	_assert_issue(schema, fixture, catalog, characters, func(bundle: Dictionary): bundle["triggers"][0]["events"][1]["flows"][2]["flow_key"] = "inspect", "duplicate_flow_key")
	_assert_issue(schema, fixture, catalog, characters, func(bundle: Dictionary): bundle["triggers"][0]["events"][1]["event_key"] = " ", "missing_event_key")
	_assert_issue(schema, fixture, catalog, characters, func(bundle: Dictionary): bundle.erase("source_id"), "missing_source_id")
	_assert_issue(schema, fixture, catalog, characters, func(bundle: Dictionary): bundle["triggers"][0]["events"][1]["flows"][0]["blocks"][0]["speaker"] = "ghost", "unknown_character")
	_assert_issue(schema, fixture, catalog, characters, func(bundle: Dictionary): bundle["triggers"][0]["events"][1]["flows"][0]["blocks"][0]["expression"] = "ghost", "unknown_expression")
	_assert_issue(schema, fixture, catalog, characters, func(bundle: Dictionary): bundle["triggers"][0]["trigger_key"] = "missing.trigger", "unknown_trigger")
	_assert_issue(schema, fixture, catalog, characters, func(bundle: Dictionary): bundle["triggers"][0]["events"][1]["flows"][0]["blocks"][2]["items"][0]["target_kind"] = "event"; bundle["triggers"][0]["events"][1]["flows"][0]["blocks"][2]["items"][0]["target_key"] = "other.bundle:event", "cross_bundle_target")
	_assert_issue(schema, fixture, catalog, characters, func(bundle: Dictionary): bundle["triggers"][0]["events"][0]["conditions"][0]["mapping_status"] = "proposed", "mapping_not_approved")
	_assert_issue(schema, fixture, catalog, characters, func(bundle: Dictionary): bundle["triggers"][0]["events"][1]["flows"][0]["blocks"][2]["items"][0]["target_key"] = "missing", "dangling_target")
	_assert_issue(schema, fixture, catalog, characters, func(bundle: Dictionary): bundle["triggers"][0]["events"][1]["flows"][0]["flow_key"] = "opening", "missing_start_flow")
	_assert_issue(schema, fixture, catalog, characters, func(bundle: Dictionary): bundle["triggers"][0]["events"][1]["flows"][3]["blocks"] = [_line_without_exit()], "unterminated_path")
	_assert_issue(schema, fixture, catalog, characters, func(bundle: Dictionary): bundle["triggers"][0]["events"][1]["flows"][1]["blocks"][1]["arguments"]["speed"] = "fast", "invalid_command_argument_type")
	_assert_issue(schema, fixture, catalog, characters, func(bundle: Dictionary): bundle["triggers"][0]["events"][1]["flows"][3]["blocks"][1]["text"] = "forbidden", "invalid_end_block")
	var no_fallback: Dictionary = fixture.valid_bundle()
	no_fallback["triggers"][0]["events"][1]["conditions"] = [no_fallback["triggers"][0]["events"][0]["conditions"][0]]
	var warnings: Array = schema.validate_bundle(no_fallback, catalog, characters)
	assert_true(_has_issue(warnings, "missing_fallback", "warning"), "final conditional event produces a missing-fallback warning")
	assert_false(_has_error(warnings), "missing fallback is not an error")

func _test_fail_closed_shapes(schema: Script, fixture: Script, catalog: NarrativeCatalog, characters: Resource) -> void:
	var malformed_fallback: Dictionary = fixture.valid_bundle()
	malformed_fallback["triggers"][0]["events"][1]["conditions"] = {"not":"an array"}
	var fallback_issues: Array = schema.validate_bundle(malformed_fallback, catalog, characters)
	assert_true(_has_issue(fallback_issues, "invalid_conditions", "error"), "non-array final-event conditions fail closed")
	assert_false(_has_issue(fallback_issues, "missing_fallback", "warning"), "malformed conditions are never interpreted as a conditional fallback")

	_assert_issue(schema, fixture, catalog, characters, func(bundle: Dictionary): bundle["effects"] = [], "invalid_bundle")
	_assert_issue(schema, fixture, catalog, characters, func(bundle: Dictionary): bundle["triggers"][0]["effects"] = [], "invalid_trigger")
	_assert_issue(schema, fixture, catalog, characters, func(bundle: Dictionary): bundle["triggers"][0]["events"][0]["arguments"] = {}, "invalid_event")
	_assert_issue(schema, fixture, catalog, characters, func(bundle: Dictionary): bundle["triggers"][0]["events"][0]["flows"][0]["conditions"] = [], "invalid_flow")
	_assert_issue(schema, fixture, catalog, characters, func(bundle: Dictionary): bundle["triggers"][0]["events"][0]["flows"][0]["blocks"][0]["effects"] = [], "invalid_line_block")
	_assert_issue(schema, fixture, catalog, characters, func(bundle: Dictionary): bundle["triggers"][0]["events"][1]["flows"][1]["blocks"][1]["effects"] = [], "invalid_command_block")
	_assert_issue(schema, fixture, catalog, characters, func(bundle: Dictionary): bundle["triggers"][0]["events"][1]["flows"][0]["blocks"][2]["effects"] = [], "invalid_choice_block")
	_assert_issue(schema, fixture, catalog, characters, func(bundle: Dictionary): bundle["triggers"][0]["events"][1]["flows"][2]["blocks"][1]["effects"] = [], "invalid_jump_block")
	_assert_issue(schema, fixture, catalog, characters, func(bundle: Dictionary): bundle["triggers"][0]["events"][1]["flows"][0]["blocks"][2]["items"][0]["speaker"] = "retti", "invalid_choice_item")
	_assert_issue(schema, fixture, catalog, characters, func(bundle: Dictionary): bundle["triggers"][0]["events"][0]["conditions"][0]["target_key"] = "start", "invalid_condition")
	_assert_issue(schema, fixture, catalog, characters, func(bundle: Dictionary): bundle["triggers"][0]["events"][0]["conditions"][0]["source_id"] = "mapping-source", "invalid_condition")
	_assert_issue(schema, fixture, catalog, characters, func(bundle: Dictionary): bundle["triggers"][0]["events"][1]["effects"][0]["operator"] = "eq", "invalid_effect")
	_assert_issue(schema, fixture, catalog, characters, func(bundle: Dictionary): bundle["triggers"][0]["events"][1]["effects"][0]["source_id"] = "mapping-source", "invalid_effect")

func _test_field_type_contract(schema: Script, fixture: Script, catalog: NarrativeCatalog, characters: Resource) -> void:
	var cases := [
		{"name":"bundle source_id", "code":"invalid_source_id", "mutate":func(bundle: Dictionary): bundle["source_id"] = 7},
		{"name":"bundle source_url", "code":"invalid_source_url", "mutate":func(bundle: Dictionary): bundle["source_url"] = []},
		{"name":"bundle key", "code":"invalid_bundle_key", "mutate":func(bundle: Dictionary): bundle["bundle_key"] = 7},
		{"name":"bundle title", "code":"invalid_title", "mutate":func(bundle: Dictionary): bundle["title"] = 7},
		{"name":"bundle comments", "code":"invalid_comments", "mutate":func(bundle: Dictionary): bundle["comments"] = {}},
		{"name":"triggers container", "code":"invalid_triggers", "mutate":func(bundle: Dictionary): bundle["triggers"] = {}},
		{"name":"trigger source_id", "code":"invalid_source_id", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["source_id"] = 7},
		{"name":"trigger source_url", "code":"invalid_source_url", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["source_url"] = 7},
		{"name":"trigger key", "code":"invalid_trigger_key", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["trigger_key"] = 7},
		{"name":"trigger name", "code":"invalid_name", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["name"] = 7},
		{"name":"trigger comments", "code":"invalid_comments", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["comments"] = {}},
		{"name":"events container", "code":"invalid_events", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"] = {}},
		{"name":"event source_id", "code":"invalid_source_id", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][0]["source_id"] = 7},
		{"name":"event source_url", "code":"invalid_source_url", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][0]["source_url"] = 7},
		{"name":"event key", "code":"invalid_event_key", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][0]["event_key"] = 7},
		{"name":"event name", "code":"invalid_name", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][0]["name"] = 7},
		{"name":"event comments", "code":"invalid_comments", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][0]["comments"] = {}},
		{"name":"event conditions", "code":"invalid_conditions", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][0]["conditions"] = {}},
		{"name":"event effects", "code":"invalid_effects", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][0]["effects"] = {}},
		{"name":"flows container", "code":"invalid_flows", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][0]["flows"] = {}},
		{"name":"flow source_id", "code":"invalid_source_id", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][1]["flows"][1]["source_id"] = 7},
		{"name":"flow source_url", "code":"invalid_source_url", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][1]["flows"][1]["source_url"] = 7},
		{"name":"flow key", "code":"invalid_flow_key", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][1]["flows"][1]["flow_key"] = 7},
		{"name":"flow name", "code":"invalid_flow_name", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][1]["flows"][1]["name"] = 7},
		{"name":"flow comments", "code":"invalid_comments", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][1]["flows"][1]["comments"] = {}},
		{"name":"flow effects", "code":"invalid_effects", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][1]["flows"][1]["effects"] = {}},
		{"name":"blocks container", "code":"invalid_blocks", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][1]["flows"][1]["blocks"] = {}},
		{"name":"block type", "code":"invalid_block_type", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][0]["flows"][0]["blocks"][0]["type"] = 7},
		{"name":"block source_id", "code":"invalid_source_id", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][0]["flows"][0]["blocks"][0]["source_id"] = 7},
		{"name":"block source_url", "code":"invalid_source_url", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][0]["flows"][0]["blocks"][0]["source_url"] = 7},
		{"name":"optional block key", "code":"invalid_block_key", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][0]["flows"][0]["blocks"][0]["block_key"] = 7},
		{"name":"block comments", "code":"invalid_comments", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][0]["flows"][0]["blocks"][0]["comments"] = {}},
		{"name":"line speaker", "code":"invalid_speaker", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][0]["flows"][0]["blocks"][0]["speaker"] = 7},
		{"name":"line expression", "code":"invalid_expression", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][0]["flows"][0]["blocks"][0]["expression"] = 7},
		{"name":"line text", "code":"invalid_line_text", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][0]["flows"][0]["blocks"][0]["text"] = 7},
		{"name":"command key", "code":"invalid_command_key", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][1]["flows"][1]["blocks"][1]["command_key"] = 7},
		{"name":"choice items", "code":"invalid_choice_items", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][1]["flows"][0]["blocks"][2]["items"] = {}},
		{"name":"choice source_id", "code":"invalid_source_id", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][1]["flows"][0]["blocks"][2]["items"][0]["source_id"] = 7},
		{"name":"choice source_url", "code":"invalid_source_url", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][1]["flows"][0]["blocks"][2]["items"][0]["source_url"] = 7},
		{"name":"choice text", "code":"invalid_choice_text", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][1]["flows"][0]["blocks"][2]["items"][0]["text"] = 7},
		{"name":"optional choice key", "code":"invalid_choice_key", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][1]["flows"][0]["blocks"][2]["items"][0]["choice_key"] = 7},
		{"name":"choice comments", "code":"invalid_comments", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][1]["flows"][0]["blocks"][2]["items"][0]["comments"] = {}},
		{"name":"target kind", "code":"invalid_target_kind_type", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][1]["flows"][2]["blocks"][1]["target_kind"] = 7},
		{"name":"target key", "code":"invalid_target_key", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][1]["flows"][2]["blocks"][1]["target_key"] = 7},
		{"name":"mapping source_text", "code":"invalid_source_text", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][0]["conditions"][0]["source_text"] = 7},
		{"name":"missing mapping source_text", "code":"missing_source_text", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][0]["conditions"][0].erase("source_text")},
		{"name":"mapping term_name", "code":"invalid_term_name", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][0]["conditions"][0]["term_name"] = 7},
		{"name":"mapping status", "code":"invalid_mapping_status", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][0]["conditions"][0]["mapping_status"] = 7},
		{"name":"mapping kind", "code":"invalid_kind", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][0]["conditions"][0]["kind"] = 7},
		{"name":"mapping key", "code":"invalid_key", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][0]["conditions"][0]["key"] = 7},
		{"name":"mapping operator", "code":"invalid_operator", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][0]["conditions"][0]["operator"] = 7},
		{"name":"mapping comments", "code":"invalid_comments", "mutate":func(bundle: Dictionary): bundle["triggers"][0]["events"][0]["conditions"][0]["comments"] = {}},
	]
	for case_value: Variant in cases:
		var case_data: Dictionary = case_value
		var bundle: Dictionary = fixture.valid_bundle()
		(case_data["mutate"] as Callable).call(bundle)
		var issues: Array = schema.validate_bundle(bundle, catalog, characters)
		assert_true(_has_issue(issues, String(case_data["code"]), "error"), "wrong-type %s fails with %s" % [case_data["name"], case_data["code"]])

func _test_same_bundle_cross_trigger_event_target(schema: Script, fixture: Script, characters: Resource) -> void:
	var bundle: Dictionary = fixture.valid_bundle()
	var second_trigger: Dictionary = bundle["triggers"][0].duplicate(true)
	second_trigger["source_id"] = "notion-heading-door"
	second_trigger["trigger_key"] = "door.inspect"
	second_trigger["name"] = "문 조사"
	second_trigger["events"] = [{"source_id":"notion-event-door", "event_key":"door_default", "name":"문 앞", "conditions":[], "effects":[], "flows":[{"source_id":"notion-flow-door", "flow_key":"start", "name":"흐름 · 시작", "effects":[], "blocks":[{"type":"end", "source_id":"notion-block-door-end"}]}]}]
	bundle["triggers"].append(second_trigger)
	bundle["triggers"][0]["events"][1]["flows"][0]["blocks"][2]["items"][0]["target_kind"] = "event"
	bundle["triggers"][0]["events"][1]["flows"][0]["blocks"][2]["items"][0]["target_key"] = "door_default"
	assert_eq(schema.validate_bundle(bundle, NarrativeCatalog.from_dictionary(_catalog_data()), characters), [], "event target may resolve to another trigger in the same bundle")
	var duplicate_key_bundle: Dictionary = bundle.duplicate(true)
	duplicate_key_bundle["triggers"][1]["events"][0]["event_key"] = "default"
	assert_true(_has_issue(schema.validate_bundle(duplicate_key_bundle, NarrativeCatalog.from_dictionary(_catalog_data()), characters), "duplicate_event_key", "error"), "event keys remain unique across the complete bundle")

func _test_command_argument_contract(schema: Script, fixture: Script, characters: Resource) -> void:
	var valid_catalog := NarrativeCatalog.from_dictionary(_catalog_data())
	assert_eq(schema.validate_bundle(fixture.valid_bundle(), valid_catalog, characters), [], "complete typed command arguments validate")
	_assert_issue(schema, fixture, valid_catalog, characters, func(bundle: Dictionary): bundle["triggers"][0]["events"][1]["flows"][1]["blocks"][1]["arguments"].erase("speed"), "missing_command_argument")
	_assert_issue(schema, fixture, valid_catalog, characters, func(bundle: Dictionary): bundle["triggers"][0]["events"][1]["flows"][1]["blocks"][1]["arguments"]["extra"] = true, "unapproved_command_argument")
	_assert_issue(schema, fixture, valid_catalog, characters, func(bundle: Dictionary): bundle["triggers"][0]["events"][1]["flows"][1]["blocks"][1]["arguments"]["speed"] = "fast", "invalid_command_argument_type")

func _line_without_exit() -> Dictionary:
	return {"type":"line", "source_id":"notion-block-unterminated", "speaker":"retti", "expression":"neutral", "text":"끝나지 않는 말"}

func _assert_issue(schema: Script, fixture: Script, catalog: NarrativeCatalog, characters: Resource, mutate: Callable, code: String) -> void:
	var bundle: Dictionary = fixture.valid_bundle()
	mutate.call(bundle)
	var issues: Array = schema.validate_bundle(bundle, catalog, characters)
	assert_true(_has_issue(issues, code, "error"), "invalid normalized bundle reports %s" % code)
	if not issues.is_empty():
		assert_true(issues[0].has_all(["severity", "code", "message", "source_id", "source_url", "bundle_key", "event_key", "flow_key"]), "issue preserves the complete authoring provenance shape")

func _has_issue(issues: Array, code: String, severity: String) -> bool:
	for issue: Variant in issues:
		if typeof(issue) == TYPE_DICTIONARY and issue.get("code", "") == code and issue.get("severity", "") == severity:
			return true
	return false

func _has_error(issues: Array) -> bool:
	for issue: Variant in issues:
		if typeof(issue) == TYPE_DICTIONARY and issue.get("severity", "") == "error":
			return true
	return false

func _catalog_data() -> Dictionary:
	return {"schema_version":1, "terms":[{"kind":"flag", "key":"mirror_seen", "display_name":"거울을 자세히 봄", "description":"거울 상태", "aliases":[], "default":false}, {"kind":"stat", "key":"jellyppo_trust", "display_name":"젤리뽀의 신뢰", "description":"신뢰", "aliases":[], "default":0, "minimum":-10, "maximum":10}], "triggers":[{"key":"mirror.inspect", "display_name":"거울 조사", "description":"거울", "aliases":[]}, {"key":"door.inspect", "display_name":"문 조사", "description":"문", "aliases":[]}], "commands":[{"key":"dialogue.advance", "display_name":"대화 진행", "description":"대화", "aliases":[], "arguments":{"speed":"int"}}]}
