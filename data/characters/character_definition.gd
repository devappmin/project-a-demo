extends Resource
class_name CharacterDefinition

@export var character_key: StringName = &""
@export var display_name := ""
@export var default_expression: StringName = &"neutral"
@export var portraits: Dictionary = {}
@export var expression_metadata: Dictionary = {}

func has_expression(expression: StringName) -> bool:
	return portraits.has(expression) or portraits.has(String(expression))

func resolve_portrait(expression: StringName) -> Texture2D:
	var portrait: Variant = portraits.get(expression, portraits.get(String(expression)))
	if portrait is Texture2D:
		return portrait
	portrait = portraits.get(default_expression, portraits.get(String(default_expression)))
	return portrait as Texture2D

func expression_records() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for expression_value: Variant in portraits.keys():
		var expression := String(expression_value)
		var metadata_value: Variant = expression_metadata.get(expression_value, expression_metadata.get(expression, {}))
		if typeof(metadata_value) != TYPE_DICTIONARY:
			continue
		var record: Dictionary = (metadata_value as Dictionary).duplicate(true)
		record["key"] = expression
		records.append(record)
	records.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return String(left.get("key", "")) < String(right.get("key", "")))
	return records

func validate_authoring_metadata() -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	var phrases: Dictionary = {}
	for expression_value: Variant in portraits.keys():
		var expression := String(expression_value)
		var metadata_value: Variant = expression_metadata.get(expression_value, expression_metadata.get(expression, null))
		if typeof(metadata_value) != TYPE_DICTIONARY:
			issues.append({"code":"missing_expression_metadata", "message":"every portrait expression requires Korean authoring metadata"})
			continue
		var metadata: Dictionary = metadata_value
		var display_name_value: Variant = metadata.get("display_name", null)
		var aliases_value: Variant = metadata.get("aliases", null)
		if typeof(display_name_value) != TYPE_STRING or String(display_name_value).is_empty() or typeof(aliases_value) != TYPE_ARRAY:
			issues.append({"code":"invalid_expression_metadata", "message":"expression metadata requires a Korean display_name and aliases array"})
			continue
		var expression_phrases: Array[String] = [String(display_name_value)]
		var aliases_valid := true
		for alias: Variant in aliases_value:
			if typeof(alias) != TYPE_STRING or String(alias).is_empty():
				aliases_valid = false
				break
			expression_phrases.append(String(alias))
		if not aliases_valid:
			issues.append({"code":"invalid_expression_metadata", "message":"expression aliases must be nonempty Korean strings"})
			continue
		for phrase: String in expression_phrases:
			if phrases.has(phrase):
				issues.append({"code":"ambiguous_expression_phrase", "message":"expression display names and aliases must be unique within one character"})
				break
			phrases[phrase] = expression
	for metadata_key: Variant in expression_metadata.keys():
		if not portraits.has(metadata_key) and not portraits.has(String(metadata_key)) and not portraits.has(StringName(String(metadata_key))):
			issues.append({"code":"unknown_expression_metadata", "message":"expression metadata must reference an existing portrait expression"})
	return issues
