extends RefCounted
class_name SaveData

const SCHEMA_VERSION := 1
const SLOT_IDS := [&"auto", &"slot_1", &"slot_2", &"slot_3", &"slot_4", &"slot_5"]
const MAP_REGISTRY_PATH := "res://data/maps/map_registry.tres"

const _TOP_LEVEL_KEYS := ["schema_version", "checksum", "meta", "player", "narrative", "world", "dialogue"]
const _META_KEYS := ["slot_id", "saved_at", "play_time_seconds", "location_name"]
const _PLAYER_KEYS := ["map_id", "spawn_id", "position", "facing"]
const _POSITION_KEYS := ["x", "y"]
const _NARRATIVE_KEYS := ["flags", "stats", "inventory", "quests", "collectibles"]
const _WORLD_KEYS := ["maps"]
const _DIALOGUE_KEYS := ["active", "bundle_key", "trigger_key", "node_id", "boundary"]
const _FACINGS := ["up", "down", "left", "right"]
const _BOUNDARIES := ["line", "choice"]
const _MAX_SAFE_INTEGER := 9007199254740991

static func validate(snapshot: Dictionary) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	_validate_exact_keys(snapshot, _TOP_LEVEL_KEYS, "$", issues)
	if not _is_current_schema_version(snapshot.get("schema_version")):
		_add_issue(issues, "unsupported_schema", "schema_version")
	var checksum_value: Variant = snapshot.get("checksum")
	if typeof(checksum_value) != TYPE_STRING or not _is_sha256(String(checksum_value)):
		_add_issue(issues, "invalid_checksum", "checksum")
	_validate_meta(snapshot.get("meta"), issues)
	_validate_player(snapshot.get("player"), issues)
	_validate_narrative(snapshot.get("narrative"), issues)
	_validate_world(snapshot.get("world"), issues)
	_validate_dialogue(snapshot.get("dialogue"), issues)
	if not _is_json_value(snapshot):
		_add_issue(issues, "unsupported_variant", "$")
	return issues

static func encode(snapshot_without_checksum: Dictionary) -> PackedByteArray:
	if snapshot_without_checksum.has("checksum") or not _is_json_value(snapshot_without_checksum):
		return PackedByteArray()
	var canonical: Variant = _canonicalize(snapshot_without_checksum)
	return JSON.stringify(canonical, "", false, true).to_utf8_buffer()

static func with_checksum(snapshot: Dictionary) -> Dictionary:
	var unsigned := snapshot.duplicate(true)
	unsigned.erase("checksum")
	if not _validate_unsigned(unsigned).is_empty():
		return {}
	var bytes := encode(unsigned)
	if bytes.is_empty():
		return {}
	var signed := unsigned.duplicate(true)
	signed["checksum"] = _sha256(bytes)
	return signed

static func verify_checksum(snapshot: Dictionary) -> bool:
	var checksum_value: Variant = snapshot.get("checksum")
	if typeof(checksum_value) != TYPE_STRING or not _is_sha256(String(checksum_value)):
		return false
	var unsigned := snapshot.duplicate(true)
	unsigned.erase("checksum")
	var bytes := encode(unsigned)
	return not bytes.is_empty() and _sha256(bytes) == checksum_value

static func migrate(snapshot: Dictionary) -> Dictionary:
	if not _is_current_schema_version(snapshot.get("schema_version")) or not _is_json_value(snapshot):
		return {}
	return snapshot.duplicate(true)

static func metadata(snapshot: Dictionary) -> Dictionary:
	if not validate(snapshot).is_empty() or not verify_checksum(snapshot):
		return {}
	var result: Dictionary = snapshot["meta"].duplicate(true)
	result["schema_version"] = snapshot["schema_version"]
	return result

static func _validate_unsigned(snapshot: Dictionary) -> Array[Dictionary]:
	var candidate := snapshot.duplicate(true)
	candidate["checksum"] = "0000000000000000000000000000000000000000000000000000000000000000"
	return validate(candidate)

static func _validate_meta(value: Variant, issues: Array[Dictionary]) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		_add_issue(issues, "invalid_type", "meta")
		return
	var meta: Dictionary = value
	_validate_exact_keys(meta, _META_KEYS, "meta", issues)
	if typeof(meta.get("slot_id")) != TYPE_STRING or StringName(meta.get("slot_id", "")) not in SLOT_IDS:
		_add_issue(issues, "invalid_slot", "meta.slot_id")
	if typeof(meta.get("saved_at")) != TYPE_STRING or not _is_iso_timestamp(String(meta.get("saved_at", ""))):
		_add_issue(issues, "invalid_timestamp", "meta.saved_at")
	var play_time: Variant = meta.get("play_time_seconds")
	if (typeof(play_time) != TYPE_FLOAT and typeof(play_time) != TYPE_INT) or not is_finite(float(play_time)) or float(play_time) < 0.0:
		_add_issue(issues, "invalid_play_time", "meta.play_time_seconds")
	if not _is_nonempty_string(meta.get("location_name")):
		_add_issue(issues, "invalid_location", "meta.location_name")

static func _validate_player(value: Variant, issues: Array[Dictionary]) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		_add_issue(issues, "invalid_type", "player")
		return
	var player: Dictionary = value
	_validate_exact_keys(player, _PLAYER_KEYS, "player", issues)
	var map_value: Variant = player.get("map_id")
	var spawn_value: Variant = player.get("spawn_id")
	if typeof(map_value) != TYPE_STRING or typeof(spawn_value) != TYPE_STRING or not _registered_spawn(String(map_value), String(spawn_value)):
		_add_issue(issues, "invalid_restore_point", "player")
	var position_value: Variant = player.get("position")
	if typeof(position_value) != TYPE_DICTIONARY:
		_add_issue(issues, "invalid_type", "player.position")
	else:
		var position: Dictionary = position_value
		_validate_exact_keys(position, _POSITION_KEYS, "player.position", issues)
		for axis in _POSITION_KEYS:
			var coordinate: Variant = position.get(axis)
			if (typeof(coordinate) != TYPE_FLOAT and typeof(coordinate) != TYPE_INT) or not is_finite(float(coordinate)):
				_add_issue(issues, "invalid_position", "player.position.%s" % axis)
	if typeof(player.get("facing")) != TYPE_STRING or String(player.get("facing", "")) not in _FACINGS:
		_add_issue(issues, "invalid_facing", "player.facing")

static func _validate_narrative(value: Variant, issues: Array[Dictionary]) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		_add_issue(issues, "invalid_type", "narrative")
		return
	var narrative: Dictionary = value
	_validate_exact_keys(narrative, _NARRATIVE_KEYS, "narrative", issues)
	for section in _NARRATIVE_KEYS:
		if typeof(narrative.get(section)) != TYPE_DICTIONARY:
			_add_issue(issues, "invalid_type", "narrative.%s" % section)

static func _validate_world(value: Variant, issues: Array[Dictionary]) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		_add_issue(issues, "invalid_type", "world")
		return
	var world: Dictionary = value
	_validate_exact_keys(world, _WORLD_KEYS, "world", issues)
	var maps_value: Variant = world.get("maps")
	if typeof(maps_value) != TYPE_DICTIONARY:
		_add_issue(issues, "invalid_type", "world.maps")
		return
	var maps: Dictionary = maps_value
	for map_id in maps:
		if typeof(map_id) != TYPE_STRING or not _is_nonempty_string(map_id) or typeof(maps[map_id]) != TYPE_DICTIONARY:
			_add_issue(issues, "invalid_world_map", "world.maps")
			continue
		var objects: Dictionary = maps[map_id]
		for object_id in objects:
			if typeof(object_id) != TYPE_STRING or not _is_nonempty_string(object_id) or typeof(objects[object_id]) != TYPE_DICTIONARY:
				_add_issue(issues, "invalid_world_object", "world.maps.%s" % map_id)

static func _validate_dialogue(value: Variant, issues: Array[Dictionary]) -> void:
	if typeof(value) != TYPE_DICTIONARY:
		_add_issue(issues, "invalid_type", "dialogue")
		return
	var dialogue: Dictionary = value
	_validate_exact_keys(dialogue, _DIALOGUE_KEYS, "dialogue", issues)
	if typeof(dialogue.get("active")) != TYPE_BOOL:
		_add_issue(issues, "invalid_type", "dialogue.active")
		return
	for key in ["bundle_key", "trigger_key", "node_id", "boundary"]:
		if typeof(dialogue.get(key)) != TYPE_STRING:
			_add_issue(issues, "invalid_type", "dialogue.%s" % key)
	if dialogue.get("active", false):
		for key in ["bundle_key", "trigger_key", "node_id"]:
			if not _is_nonempty_string(dialogue.get(key)):
				_add_issue(issues, "missing_dialogue_context", "dialogue.%s" % key)
		if dialogue.get("boundary") not in _BOUNDARIES:
			_add_issue(issues, "invalid_boundary", "dialogue.boundary")
	else:
		for key in ["bundle_key", "trigger_key", "node_id", "boundary"]:
			if typeof(dialogue.get(key)) != TYPE_STRING or String(dialogue.get(key, "")) != "":
				_add_issue(issues, "dangling_dialogue_context", "dialogue.%s" % key)

static func _validate_exact_keys(value: Dictionary, expected: Array, path: String, issues: Array[Dictionary]) -> void:
	var actual := value.keys()
	for key in actual:
		if typeof(key) != TYPE_STRING:
			_add_issue(issues, "invalid_keys", path)
			return
	actual.sort()
	var wanted := expected.duplicate()
	wanted.sort()
	if actual != wanted:
		_add_issue(issues, "invalid_keys", path)

static func _registered_spawn(map_id: String, spawn_id: String) -> bool:
	if map_id.strip_edges().is_empty() or spawn_id.strip_edges().is_empty():
		return false
	var registry := load(MAP_REGISTRY_PATH) as MapRegistry
	if registry == null:
		return false
	var definition := registry.definition(StringName(map_id))
	if definition == null or definition.scene_path.is_empty():
		return false
	var packed := load(definition.scene_path) as PackedScene
	if packed == null:
		return false
	var map := packed.instantiate()
	var valid := map is MapScene and map.get_spawn(StringName(spawn_id)) != null
	map.free()
	return valid

static func _is_json_value(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return true
		TYPE_INT:
			return value >= -_MAX_SAFE_INTEGER and value <= _MAX_SAFE_INTEGER
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_ARRAY:
			for item in value:
				if not _is_json_value(item):
					return false
			return true
		TYPE_DICTIONARY:
			for key in value:
				if typeof(key) != TYPE_STRING or not _is_json_value(value[key]):
					return false
			return true
		_:
			return false

static func _canonicalize(value: Variant) -> Variant:
	if typeof(value) == TYPE_INT:
		return float(value)
	if typeof(value) == TYPE_ARRAY:
		var normalized_array: Array = []
		for item in value:
			normalized_array.append(_canonicalize(item))
		return normalized_array
	if typeof(value) == TYPE_DICTIONARY:
		var normalized_dictionary := {}
		var dictionary: Dictionary = value
		var keys: Array = dictionary.keys()
		keys.sort()
		for key in keys:
			normalized_dictionary[key] = _canonicalize(dictionary[key])
		return normalized_dictionary
	return value

static func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(bytes) != OK:
		return ""
	return context.finish().hex_encode()

static func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for character in value:
		if character not in "0123456789abcdef":
			return false
	return true

static func _is_iso_timestamp(value: String) -> bool:
	var regex := RegEx.new()
	if regex.compile("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(?:\\.\\d+)?(?:Z|[+-]\\d{2}:\\d{2})$") != OK:
		return false
	if regex.search(value) == null:
		return false
	var year := int(value.substr(0, 4))
	var month := int(value.substr(5, 2))
	var day := int(value.substr(8, 2))
	var hour := int(value.substr(11, 2))
	var minute := int(value.substr(14, 2))
	var second := int(value.substr(17, 2))
	if year <= 0 or month < 1 or month > 12 or day < 1 or day > _days_in_month(year, month):
		return false
	if hour > 23 or minute > 59 or second > 59:
		return false
	if not value.ends_with("Z"):
		var offset_hour := int(value.substr(value.length() - 5, 2))
		var offset_minute := int(value.substr(value.length() - 2, 2))
		if offset_hour > 23 or offset_minute > 59:
			return false
	return true

static func _days_in_month(year: int, month: int) -> int:
	if month == 2:
		return 29 if year % 400 == 0 or (year % 4 == 0 and year % 100 != 0) else 28
	return 30 if month in [4, 6, 9, 11] else 31

static func _is_current_schema_version(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value)) and float(value) == float(SCHEMA_VERSION)

static func _is_nonempty_string(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not String(value).strip_edges().is_empty()

static func _add_issue(issues: Array[Dictionary], code: String, path: String) -> void:
	issues.append({"code": code, "path": path})
