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

func _catalog_data() -> Dictionary:
	return {"schema_version":1, "terms":[
		{"kind":"flag", "key":"mirror_seen", "display_name":"거울을 자세히 봄", "aliases":["거울을 봄"], "default":false},
		{"kind":"stat", "key":"jellyppo_trust", "display_name":"젤리뽀의 신뢰", "aliases":[], "default":0, "minimum":-10, "maximum":10},
		{"kind":"inventory", "key":"diary_key", "display_name":"열쇠", "aliases":[], "default":0, "minimum":0, "maximum":1}
	], "triggers":[{"key":"mirror.inspect", "display_name":"거울 조사"}], "commands":[]}
