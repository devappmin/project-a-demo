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
	_test_contract_failures(schema, fixture, catalog, characters)
	_test_fail_closed_shapes(schema, fixture, catalog, characters)
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
