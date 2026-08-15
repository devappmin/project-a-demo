extends Resource
class_name CharacterDefinition

@export var character_key: StringName = &""
@export var display_name := ""
@export var default_expression: StringName = &"neutral"
@export var portraits: Dictionary = {}

func has_expression(expression: StringName) -> bool:
	return portraits.has(expression) or portraits.has(String(expression))

func resolve_portrait(expression: StringName) -> Texture2D:
	var portrait: Variant = portraits.get(expression, portraits.get(String(expression)))
	if portrait is Texture2D:
		return portrait
	portrait = portraits.get(default_expression, portraits.get(String(default_expression)))
	return portrait as Texture2D
