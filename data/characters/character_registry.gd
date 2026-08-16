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
	result.sort()
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
