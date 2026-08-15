extends RefCounted
class_name NotionMapper

const Schema = preload("res://tools/notion_sync/notion_schema.gd")
const Reader = preload("res://tools/notion_sync/notion_property_reader.gd")

static var _character_lookup: Dictionary = {}
static var _scene_lookup: Dictionary = {}

static func configure_relation_lookups(character_lookup: Dictionary, scene_lookup: Dictionary) -> void:
	_character_lookup = character_lookup.duplicate(true)
	_scene_lookup = scene_lookup.duplicate(true)

static func map_scene(page: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	return {
		"name": _string(Reader.title(page, Schema.SCENE_PROPERTIES["name"]), errors),
		"scene_key": _string(Reader.rich_text(page, Schema.SCENE_PROPERTIES["scene_key"]), errors),
		"location": _string(Reader.select(page, Schema.SCENE_PROPERTIES["location"]), errors),
		"status": _string(Reader.select(page, Schema.SCENE_PROPERTIES["status"]), errors),
		"start_flow": _string(Reader.rich_text(page, Schema.SCENE_PROPERTIES["start_flow"]), errors),
		"notion_page_id": String(page.get("id", "")),
		"source_url": String(page.get("url", "")),
		"errors": errors
	}

static func map_block(page: Dictionary, character_lookup: Dictionary = {}, scene_lookup: Dictionary = {}) -> Dictionary:
	var errors: Array[String] = []
	var active_character_lookup := character_lookup if not character_lookup.is_empty() else _character_lookup
	var active_scene_lookup := scene_lookup if not scene_lookup.is_empty() else _scene_lookup
	var order_result := Reader.number(page, Schema.BLOCK_PROPERTIES["order"])
	var order_value: Variant = order_result["value"] if order_result["ok"] else 0.0
	if not order_result["ok"]:
		errors.append(String(order_result["message"]))
	return {
		"node_id": String(page.get("id", "")).replace("-", ""),
		"text": _string(Reader.title(page, Schema.BLOCK_PROPERTIES["text"]), errors),
		"scene_key": _related_key(page, Schema.BLOCK_PROPERTIES["scene"], active_scene_lookup, errors),
		"flow": _string(Reader.rich_text(page, Schema.BLOCK_PROPERTIES["flow"]), errors),
		"order": float(order_value) if order_value != null else 0.0,
		"type": _string(Reader.select(page, Schema.BLOCK_PROPERTIES["type"]), errors),
		"speaker": _related_key(page, Schema.BLOCK_PROPERTIES["speaker"], active_character_lookup, errors),
		"expression": _string(Reader.select(page, Schema.BLOCK_PROPERTIES["expression"]), errors),
		"target_flow": _string(Reader.rich_text(page, Schema.BLOCK_PROPERTIES["target_flow"]), errors),
		"conditions": _value(Reader.json(page, Schema.BLOCK_PROPERTIES["conditions"], []), [], errors),
		"effects": _value(Reader.json(page, Schema.BLOCK_PROPERTIES["effects"], []), [], errors),
		"command": _value(Reader.json(page, Schema.BLOCK_PROPERTIES["command"], {}), {}, errors),
		"notes": _string(Reader.rich_text(page, Schema.BLOCK_PROPERTIES["notes"]), errors),
		"notion_page_id": String(page.get("id", "")),
		"source_url": String(page.get("url", "")),
		"errors": errors
	}

static func map_character(page: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	return {
		"name": _string(Reader.title(page, Schema.CHARACTER_PROPERTIES["name"]), errors),
		"character_key": _string(Reader.rich_text(page, Schema.CHARACTER_PROPERTIES["character_key"]), errors),
		"default_expression": _string(Reader.select(page, Schema.CHARACTER_PROPERTIES["default_expression"]), errors),
		"expressions": _value(Reader.multi_select(page, Schema.CHARACTER_PROPERTIES["expressions"]), [], errors),
		"notion_page_id": String(page.get("id", "")),
		"source_url": String(page.get("url", "")),
		"errors": errors
	}

static func _related_key(page: Dictionary, property_name: String, lookup: Dictionary, errors: Array[String]) -> String:
	var relation_result := Reader.relation(page, property_name)
	if not relation_result["ok"]:
		errors.append(String(relation_result["message"]))
		return ""
	var relation_ids: Array = relation_result["value"]
	if relation_ids.is_empty():
		return ""
	var relation_id := String(relation_ids[0])
	if not lookup.has(relation_id):
		errors.append("property %s references unmapped page %s" % [property_name, relation_id])
		return ""
	return String(lookup[relation_id])

static func _string(result: Dictionary, errors: Array[String]) -> String:
	if not result["ok"]:
		errors.append(String(result["message"]))
		return ""
	return String(result["value"])

static func _value(result: Dictionary, fallback: Variant, errors: Array[String]) -> Variant:
	if not result["ok"]:
		errors.append(String(result["message"]))
		return fallback.duplicate(true) if typeof(fallback) == TYPE_ARRAY or typeof(fallback) == TYPE_DICTIONARY else fallback
	return result["value"]
