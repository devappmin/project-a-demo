extends RefCounted
class_name NotionPropertyReader

static func title(page: Dictionary, property_name: String) -> Dictionary:
	var property_result := _property(page, property_name, "title")
	if not property_result["ok"]:
		return property_result
	return _text_value(property_result["value"], "title", property_name)

static func rich_text(page: Dictionary, property_name: String) -> Dictionary:
	var property_result := _property(page, property_name, "rich_text")
	if not property_result["ok"]:
		return property_result
	return _text_value(property_result["value"], "rich_text", property_name)

static func number(page: Dictionary, property_name: String) -> Dictionary:
	var property_result := _property(page, property_name, "number")
	if not property_result["ok"]:
		return property_result
	return _ok(property_result["value"].get("number"))

static func select(page: Dictionary, property_name: String) -> Dictionary:
	var property_result := _property(page, property_name, "select")
	if not property_result["ok"]:
		return property_result
	var selection: Variant = property_result["value"].get("select")
	if selection == null:
		return _ok("")
	if typeof(selection) != TYPE_DICTIONARY:
		return _error("property %s has an invalid select value" % property_name)
	return _ok(String(selection.get("name", "")))

static func multi_select(page: Dictionary, property_name: String) -> Dictionary:
	var property_result := _property(page, property_name, "multi_select")
	if not property_result["ok"]:
		return property_result
	var selections: Variant = property_result["value"].get("multi_select")
	if typeof(selections) != TYPE_ARRAY:
		return _error("property %s has an invalid multi-select value" % property_name)
	var names: Array[String] = []
	for selection: Variant in selections:
		if typeof(selection) != TYPE_DICTIONARY:
			return _error("property %s has an invalid multi-select item" % property_name)
		names.append(String(selection.get("name", "")))
	return _ok(names)

static func relation(page: Dictionary, property_name: String) -> Dictionary:
	var property_result := _property(page, property_name, "relation")
	if not property_result["ok"]:
		return property_result
	var relations: Variant = property_result["value"].get("relation")
	if typeof(relations) != TYPE_ARRAY:
		return _error("property %s has an invalid relation value" % property_name)
	var relation_ids: Array[String] = []
	for relation_value: Variant in relations:
		if typeof(relation_value) != TYPE_DICTIONARY or not relation_value.has("id"):
			return _error("property %s has an invalid relation item" % property_name)
		relation_ids.append(String(relation_value["id"]))
	return _ok(relation_ids)

static func json(page: Dictionary, property_name: String, empty_value: Variant) -> Dictionary:
	var text_result := rich_text(page, property_name)
	if not text_result["ok"]:
		return text_result
	var text := String(text_result["value"])
	if text.is_empty():
		return _ok(_duplicate_value(empty_value))
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return _error("property %s contains invalid JSON" % property_name)
	return _ok(parser.data)

static func _property(page: Dictionary, property_name: String, expected_type: String) -> Dictionary:
	var properties: Variant = page.get("properties")
	if typeof(properties) != TYPE_DICTIONARY or not properties.has(property_name):
		return _error("missing property %s" % property_name)
	var property_value: Variant = properties[property_name]
	if typeof(property_value) != TYPE_DICTIONARY:
		return _error("property %s is not an object" % property_name)
	if String(property_value.get("type", "")) != expected_type:
		return _error("property %s must be %s" % [property_name, expected_type])
	return _ok(property_value)

static func _text_value(property_value: Dictionary, field_name: String, property_name: String) -> Dictionary:
	var fragments: Variant = property_value.get(field_name)
	if typeof(fragments) != TYPE_ARRAY:
		return _error("property %s has an invalid %s value" % [property_name, field_name])
	var text := ""
	for fragment: Variant in fragments:
		if typeof(fragment) != TYPE_DICTIONARY:
			return _error("property %s has an invalid text item" % property_name)
		text += String(fragment.get("plain_text", ""))
	return _ok(text)

static func _duplicate_value(value: Variant) -> Variant:
	if typeof(value) == TYPE_ARRAY or typeof(value) == TYPE_DICTIONARY:
		return value.duplicate(true)
	return value

static func _ok(value: Variant) -> Dictionary:
	return {"ok":true, "value":value, "message":""}

static func _error(message: String) -> Dictionary:
	return {"ok":false, "value":null, "message":message}
