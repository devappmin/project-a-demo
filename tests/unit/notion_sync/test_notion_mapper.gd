extends "res://tests/support/test_case.gd"

const NotionMapper = preload("res://tools/notion_sync/notion_mapper.gd")
const NotionPropertyReader = preload("res://tools/notion_sync/notion_property_reader.gd")
const DialogueCompiler = preload("res://tools/notion_sync/dialogue_compiler.gd")

func run() -> void:
	var scene_page := _page_fixture("scenes_page.json")
	var block_page := _page_fixture("blocks_page.json")
	var character_page := _page_fixture("characters_page.json")
	assert_true(not scene_page.is_empty(), "scene fixture parses")
	assert_true(not block_page.is_empty(), "block fixture parses")
	assert_true(not character_page.is_empty(), "character fixture parses")
	if scene_page.is_empty() or block_page.is_empty() or character_page.is_empty():
		return
	NotionMapper.configure_relation_lookups(
		{String(character_page["id"]): "retti"},
		{String(scene_page["id"]): "foundation.inspect"}
	)
	_test_scene_mapping(scene_page)
	_test_block_mapping(block_page)
	_test_character_mapping(character_page)
	_test_property_reader(block_page)
	_test_hidden_json_root_types(scene_page, block_page, character_page)

func _test_scene_mapping(page: Dictionary) -> void:
	var scene := NotionMapper.map_scene(page)
	assert_eq(scene["scene_key"], "foundation.inspect", "scene key maps")
	assert_eq(scene["status"], "Final", "status maps")
	assert_eq(scene["start_flow"], "main", "scene start flow maps")
	assert_eq(scene["notion_page_id"], page["id"], "scene retains page ID")
	assert_eq(scene["source_url"], page["url"], "scene retains source URL")

func _test_block_mapping(page: Dictionary) -> void:
	var block := NotionMapper.map_block(page)
	assert_eq(block["node_id"], String(page["id"]).replace("-", ""), "Notion page ID is the stable node ID")
	assert_eq(block["scene_key"], "foundation.inspect", "scene relation maps through lookup")
	assert_eq(block["speaker"], "retti", "speaker relation maps to character key")
	assert_eq(block["order"], 1.0, "number property maps")
	assert_eq(block["effects"], [{"kind":"flag_set", "key":"mirror_seen", "value":true}], "hidden effects JSON maps")
	assert_eq(block["notes"], "", "empty optional rich text remains distinguishable from missing input")
	assert_eq(block["notion_page_id"], page["id"], "block retains page ID")
	assert_eq(block["source_url"], page["url"], "block retains source URL")

func _test_character_mapping(page: Dictionary) -> void:
	var character := NotionMapper.map_character(page)
	assert_eq(character["character_key"], "retti", "character key maps")
	assert_eq(character["expressions"], ["neutral", "uneasy"], "multi-select expressions map")
	assert_eq(character["notion_page_id"], page["id"], "character retains page ID")
	assert_eq(character["source_url"], page["url"], "character retains source URL")

func _test_property_reader(page: Dictionary) -> void:
	var empty_notes := NotionPropertyReader.rich_text(page, "notes")
	assert_true(empty_notes["ok"], "empty optional property reads successfully")
	assert_eq(empty_notes["value"], "", "empty optional property has an empty value")
	var missing := NotionPropertyReader.rich_text(page, "missing")
	assert_false(missing["ok"], "missing property is not treated as an empty optional property")
	assert_true(String(missing["message"]).contains("missing"), "missing property message names the property")
	var invalid_json_page := page.duplicate(true)
	invalid_json_page["properties"]["effects_json"]["rich_text"][0]["plain_text"] = "not json"
	var invalid_json := NotionPropertyReader.json(invalid_json_page, "effects_json", [])
	assert_false(invalid_json["ok"], "invalid hidden JSON fails safely")
	assert_true(String(invalid_json["message"]).contains("effects_json"), "invalid JSON message names the property")

func _test_hidden_json_root_types(scene_page: Dictionary, block_page: Dictionary, character_page: Dictionary) -> void:
	var cases: Array[Dictionary] = [
		{"property":"conditions_json", "block_type":"choice", "value":{}, "expected_type":"array"},
		{"property":"conditions_json", "block_type":"choice", "value":17, "expected_type":"array"},
		{"property":"conditions_json", "block_type":"choice", "value":null, "expected_type":"array"},
		{"property":"effects_json", "block_type":"effect", "value":{}, "expected_type":"array"},
		{"property":"effects_json", "block_type":"effect", "value":17, "expected_type":"array"},
		{"property":"effects_json", "block_type":"effect", "value":null, "expected_type":"array"},
		{"property":"command_json", "block_type":"command", "value":[], "expected_type":"object"},
		{"property":"command_json", "block_type":"command", "value":17, "expected_type":"object"},
		{"property":"command_json", "block_type":"command", "value":null, "expected_type":"object"}
	]
	for case: Dictionary in cases:
		var page := block_page.duplicate(true)
		page["properties"]["type"]["select"]["name"] = case["block_type"]
		page["properties"][case["property"]]["rich_text"] = [{"plain_text":JSON.stringify(case["value"])}]
		var mapped_block := NotionMapper.map_block(page)
		assert_true(_errors_contain(mapped_block.get("errors", []), String(case["property"])), "%s wrong root is retained as a mapping error" % case["property"])
		assert_true(_errors_contain(mapped_block.get("errors", []), String(case["expected_type"])), "%s wrong root names the required %s root" % [case["property"], case["expected_type"]])
		var compiled := DialogueCompiler.compile({
			"scenes":[NotionMapper.map_scene(scene_page)],
			"blocks":[mapped_block],
			"characters":[NotionMapper.map_character(character_page)]
		})
		assert_false(compiled["ok"], "%s wrong root blocks compilation" % case["property"])
		assert_true(_has_mapping_issue(compiled.get("issues", []), String(page["url"]), String(case["property"])), "%s wrong root remains source-linked" % case["property"])

func _page_fixture(filename: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/notion/" + filename))
	return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}

func _errors_contain(errors: Variant, text: String) -> bool:
	if typeof(errors) != TYPE_ARRAY:
		return false
	for error: Variant in errors:
		if String(error).contains(text):
			return true
	return false

func _has_mapping_issue(issues: Variant, source_url: String, text: String) -> bool:
	if typeof(issues) != TYPE_ARRAY:
		return false
	for issue_value: Variant in issues:
		if typeof(issue_value) == TYPE_DICTIONARY and issue_value.get("code", "") == "mapping_error" and issue_value.get("source_url", "") == source_url and String(issue_value.get("message", "")).contains(text):
			return true
	return false
