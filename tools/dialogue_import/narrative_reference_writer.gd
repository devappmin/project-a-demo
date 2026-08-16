extends RefCounted
class_name NarrativeReferenceWriter

const CATEGORY_ORDER := [
	{"kind":&"flag", "heading":"사건 상태"},
	{"kind":&"stat", "heading":"수치 상태"},
	{"kind":&"inventory", "heading":"소지품"},
	{"kind":&"quest", "heading":"퀘스트"},
	{"kind":&"collectible", "heading":"수집품"},
	{"kind":&"trigger", "heading":"대화 트리거"},
	{"kind":&"command", "heading":"명령"}
]

static func render(catalog: NarrativeCatalog, characters: Resource) -> String:
	var lines := PackedStringArray(["# 서사 상태·대화 용어 참고서", ""])
	for category: Dictionary in CATEGORY_ORDER:
		lines.append("## %s" % category["heading"])
		var records := _records_for_category(catalog, category["kind"])
		if records.is_empty():
			lines.append("- 등록된 항목이 없습니다.")
		else:
			for record: Dictionary in records:
				_append_record(lines, record, String(category["kind"]))
		lines.append("")
	lines.append("## 등장인물과 표정")
	_append_characters(lines, characters)
	return "\n".join(lines) + "\n"

static func write_default(output_path := "res://docs/narrative-state-reference.md") -> Error:
	var text := render(NarrativeCatalog.load_default(), load("res://data/characters/character_registry.tres"))
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	return file.get_error()

static func _records_for_category(catalog: NarrativeCatalog, kind: StringName) -> Array[Dictionary]:
	if catalog == null:
		return []
	if kind == &"trigger":
		return catalog.triggers()
	if kind == &"command":
		return catalog.commands()
	return catalog.terms_for_kind(kind)

static func _append_record(lines: PackedStringArray, record: Dictionary, category: String) -> void:
	lines.append("### %s (`%s`)" % [String(record.get("display_name", "")), String(record.get("key", ""))])
	lines.append(String(record.get("description", "")))
	var details := _record_details(record, category)
	if not details.is_empty():
		lines.append("- %s" % "; ".join(details))
	var aliases: Array = record.get("aliases", [])
	if not aliases.is_empty():
		var alias_text: Array[String] = []
		for alias: Variant in aliases:
			alias_text.append(String(alias))
		alias_text.sort()
		lines.append("- 별칭: %s" % ", ".join(alias_text))
	lines.append("")

static func _record_details(record: Dictionary, category: String) -> Array[String]:
	var details: Array[String] = []
	if record.has("default"):
		details.append("기본값: %s" % _value_text(record["default"]))
	if category == "stat" or category == "inventory" or category == "collectible":
		details.append("범위: %s ~ %s" % [_value_text(record.get("minimum", "")), _value_text(record.get("maximum", ""))])
	if category == "quest":
		var stages: Array = record.get("stages", [])
		var stage_text: Array[String] = []
		for stage: Variant in stages:
			stage_text.append(String(stage))
		details.append("단계: %s" % ", ".join(stage_text))
	return details

static func _append_characters(lines: PackedStringArray, characters: Resource) -> void:
	if characters == null or not characters.has_method("character_keys") or not characters.has_method("get_definition"):
		lines.append("- 등록된 등장인물이 없습니다.")
		return
	var character_keys: Array = characters.call("character_keys")
	var sortable_keys: Array[String] = []
	for character_key: Variant in character_keys:
		sortable_keys.append(String(character_key))
	sortable_keys.sort()
	for character_key: String in sortable_keys:
		var definition: Resource = characters.call("get_definition", StringName(character_key))
		if definition == null:
			continue
		var expressions := _expression_names(definition)
		lines.append("- %s (`%s`): %s" % [String(definition.get("display_name")), character_key, ", ".join(expressions)])
	if sortable_keys.is_empty():
		lines.append("- 등록된 등장인물이 없습니다.")

static func _expression_names(definition: Resource) -> Array[String]:
	var portraits: Variant = definition.get("portraits")
	if typeof(portraits) != TYPE_DICTIONARY:
		return []
	var names: Array[String] = []
	for expression: Variant in portraits.keys():
		names.append(String(expression))
	names.sort()
	return names

static func _value_text(value: Variant) -> String:
	if typeof(value) == TYPE_BOOL:
		return "참" if value else "거짓"
	return str(value)
