extends "res://tests/support/test_case.gd"

const CATALOG_PATH := "res://game/narrative/catalog/narrative_catalog.gd"

func run() -> void:
	assert_true(ResourceLoader.exists(CATALOG_PATH, "Script"), "narrative catalog script exists")
	if not ResourceLoader.exists(CATALOG_PATH, "Script"):
		return
	var catalog_script: Script = load(CATALOG_PATH)
	var catalog: RefCounted = catalog_script.from_dictionary(_catalog_data())
	assert_eq(catalog.validate_catalog(), [], "valid catalog has no issues")
	assert_true(catalog.has_trigger(&"mirror.inspect"), "registered trigger resolves")
	var exact: Dictionary = catalog.validate_condition({"source_text":"거울을 자세히 봄", "term_name":"거울을 자세히 봄", "mapping_status":"exact", "kind":"flag", "key":"mirror_seen", "operator":"eq", "value":true})
	assert_true(exact["ok"], "exact flag mapping validates")
	var proposed: Dictionary = catalog.validate_effect({"source_text":"신뢰가 조금 오름", "term_name":"젤리뽀의 신뢰", "mapping_status":"proposed", "kind":"stat_add", "key":"jellyppo_trust", "value":1})
	assert_false(proposed["ok"], "unapproved proposal fails closed")
	assert_eq(proposed["code"], "mapping_not_approved", "proposal has stable diagnostic")
	var invented: Dictionary = catalog.validate_condition({"source_text":"마음이 열림", "term_name":"마음이 열림", "mapping_status":"exact", "kind":"flag", "key":"invented_flag", "operator":"eq", "value":true})
	assert_false(invented["ok"], "unknown key is never invented")
	var contained: Dictionary = catalog.validate_condition({"source_text":"열쇠를 가짐", "term_name":"열쇠", "mapping_status":"exact", "kind":"inventory", "key":"diary_key", "operator":"contains", "value":true})
	assert_true(contained["ok"], "inventory contains condition accepts a boolean")
	_test_required_authoring_metadata(catalog_script)

func _test_required_authoring_metadata(catalog_script: Script) -> void:
	var missing_term_description := _catalog_data()
	_term(missing_term_description, 0).erase("description")
	_assert_invalid_catalog(catalog_script, missing_term_description, "term description is required")
	var wrong_term_description := _catalog_data()
	_term(wrong_term_description, 0)["description"] = true
	_assert_invalid_catalog(catalog_script, wrong_term_description, "term description must be text")
	var missing_term_aliases := _catalog_data()
	_term(missing_term_aliases, 0).erase("aliases")
	_assert_invalid_catalog(catalog_script, missing_term_aliases, "term aliases are required")
	var wrong_term_aliases := _catalog_data()
	_term(wrong_term_aliases, 0)["aliases"] = "거울을 봄"
	_assert_invalid_catalog(catalog_script, wrong_term_aliases, "term aliases must be an array")
	var missing_default := _catalog_data()
	_term(missing_default, 0).erase("default")
	_assert_invalid_catalog(catalog_script, missing_default, "term default is required")
	var wrong_default := _catalog_data()
	_term(wrong_default, 0)["default"] = "false"
	_assert_invalid_catalog(catalog_script, wrong_default, "term default must match its kind")
	var stat_without_minimum := _catalog_data()
	_term(stat_without_minimum, 1).erase("minimum")
	_assert_invalid_catalog(catalog_script, stat_without_minimum, "stat bounds are required")
	var inventory_with_negative_minimum := _catalog_data()
	_term(inventory_with_negative_minimum, 2)["minimum"] = -1
	_assert_invalid_catalog(catalog_script, inventory_with_negative_minimum, "inventory minimum cannot be negative")
	var trigger_without_description := _catalog_data()
	_record(trigger_without_description, "triggers", 0).erase("description")
	_assert_invalid_catalog(catalog_script, trigger_without_description, "trigger description is required")
	var trigger_with_wrong_aliases := _catalog_data()
	_record(trigger_with_wrong_aliases, "triggers", 0)["aliases"] = "거울 조사"
	_assert_invalid_catalog(catalog_script, trigger_with_wrong_aliases, "trigger aliases must be an array")
	var command_with_wrong_description := _catalog_data()
	_record(command_with_wrong_description, "commands", 0)["description"] = 1
	_assert_invalid_catalog(catalog_script, command_with_wrong_description, "command description must be text")
	var command_without_aliases := _catalog_data()
	_record(command_without_aliases, "commands", 0).erase("aliases")
	_assert_invalid_catalog(catalog_script, command_without_aliases, "command aliases are required")

func _assert_invalid_catalog(catalog_script: Script, data: Dictionary, message: String) -> void:
	var malformed_catalog: RefCounted = catalog_script.from_dictionary(data)
	var issues: Array = malformed_catalog.validate_catalog()
	assert_false(issues.is_empty(), message)

func _term(data: Dictionary, index: int) -> Dictionary:
	var terms: Array = data["terms"]
	return terms[index]

func _record(data: Dictionary, section: String, index: int) -> Dictionary:
	var records: Array = data[section]
	return records[index]

func _catalog_data() -> Dictionary:
	return {"schema_version":1, "terms":[
		{"kind":"flag", "key":"mirror_seen", "display_name":"거울을 자세히 봄", "description":"거울을 조사했는지 나타냅니다.", "aliases":["거울을 봄"], "default":false},
		{"kind":"stat", "key":"jellyppo_trust", "display_name":"젤리뽀의 신뢰", "description":"신뢰도입니다.", "aliases":[], "default":0, "minimum":-10, "maximum":10},
		{"kind":"inventory", "key":"diary_key", "display_name":"열쇠", "description":"일기를 여는 열쇠입니다.", "aliases":[], "default":0, "minimum":0, "maximum":1}
	], "triggers":[{"key":"mirror.inspect", "display_name":"거울 조사", "description":"거울을 조사합니다.", "aliases":[]}], "commands":[{"key":"dialogue.advance", "display_name":"대화 진행", "description":"다음 대사로 진행합니다.", "aliases":[]}]}
