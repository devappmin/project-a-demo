extends "res://tests/support/test_case.gd"

const CATALOG_PATH := "res://game/narrative/catalog/narrative_catalog.gd"
const WRITER_PATH := "res://tools/dialogue_import/narrative_reference_writer.gd"
const CHARACTER_REGISTRY_PATH := "res://data/characters/character_registry.tres"

func run() -> void:
	assert_true(ResourceLoader.exists(WRITER_PATH, "Script"), "narrative reference writer script exists")
	if not ResourceLoader.exists(WRITER_PATH, "Script"):
		return
	var catalog_script: Script = load(CATALOG_PATH)
	var catalog: RefCounted = catalog_script.load_default()
	var writer: Script = load(WRITER_PATH)
	var markdown: String = writer.render(catalog, load(CHARACTER_REGISTRY_PATH))
	assert_true(markdown.begins_with("# 서사 상태·대화 용어 참고서\n"), "reference has Korean title")
	assert_true(markdown.contains("## 사건 상태") and markdown.contains("`mirror_seen`"), "reference includes flags")
	assert_true(markdown.contains("## 등장인물과 표정") and markdown.contains("레티"), "reference includes character registry")
	assert_true(markdown.contains("무표정 (`neutral`)") and markdown.contains("불안 (`uneasy`)"), "reference presents expressions with Korean names")
	assert_true(markdown.contains("시작 전 (`not_started`)") and markdown.contains("조사 완료 (`resolved`)"), "reference presents quest stages with Korean names")
	assert_false(markdown.contains("PROJECT_A_" + "NOTION_TOKEN"), "reference never contains old credentials")
	assert_eq(markdown, writer.render(catalog, load(CHARACTER_REGISTRY_PATH)), "second render is byte-identical")
	var unordered_catalog: RefCounted = catalog_script.from_dictionary(_unordered_catalog_data())
	var unordered_markdown: String = writer.render(unordered_catalog, load(CHARACTER_REGISTRY_PATH))
	assert_true(unordered_markdown.find("`alpha_flag`") < unordered_markdown.find("`zeta_flag`"), "terms sort by internal key")

func _unordered_catalog_data() -> Dictionary:
	return {"schema_version":1, "terms":[
		{"kind":"flag", "key":"zeta_flag", "display_name":"제타", "description":"제타 상태입니다.", "aliases":[], "default":false},
		{"kind":"flag", "key":"alpha_flag", "display_name":"알파", "description":"알파 상태입니다.", "aliases":[], "default":false}
	], "triggers":[], "commands":[]}
