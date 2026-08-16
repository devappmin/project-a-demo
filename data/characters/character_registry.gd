extends Resource
class_name CharacterRegistry

@export var definitions: Array[Resource] = []

func character_keys() -> Array[StringName]:
	var result: Array[StringName] = []
	for definition: Resource in definitions:
		if definition == null:
			continue
		var character_key := StringName(definition.get("character_key"))
		if not character_key.is_empty() and character_key not in result:
			result.append(character_key)
	result.sort_custom(func(left: StringName, right: StringName) -> bool: return String(left) < String(right))
	return result

func get_definition(character_key: StringName) -> Resource:
	for definition: Resource in definitions:
		if definition != null and StringName(definition.get("character_key")) == character_key:
			return definition
	return null

func has_character(character_key: StringName) -> bool:
	return get_definition(character_key) != null

func has_expression(character_key: StringName, expression: StringName) -> bool:
	var definition := get_definition(character_key)
	return definition != null and definition.call("has_expression", expression)

func default_expression(character_key: StringName) -> StringName:
	var definition := get_definition(character_key)
	return StringName(definition.get("default_expression")) if definition != null else &""

func validate_authoring_metadata() -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	var character_names: Dictionary = {}
	for definition: Resource in definitions:
		if definition == null:
			issues.append({"code":"invalid_character_metadata", "message":"character definition cannot be null", "character_key":""})
			continue
		var character_key := String(definition.get("character_key"))
		var display_name_value: Variant = definition.get("display_name")
		if character_key.is_empty() or typeof(display_name_value) != TYPE_STRING or String(display_name_value).is_empty():
			issues.append({"code":"invalid_character_metadata", "message":"character requires a key and Korean display name", "character_key":character_key})
			continue
		var display_name := String(display_name_value)
		if character_names.has(display_name):
			issues.append({"code":"ambiguous_character_phrase", "message":"character display names must be unique", "character_key":character_key})
		else:
			character_names[display_name] = character_key
		if not definition.has_method("validate_authoring_metadata"):
			issues.append({"code":"invalid_character_metadata", "message":"character definition cannot validate expression metadata", "character_key":character_key})
			continue
		for issue_value: Variant in definition.call("validate_authoring_metadata"):
			var issue: Dictionary = issue_value
			issue["character_key"] = character_key
			issues.append(issue)
	return issues
