extends RefCounted
class_name WorldState

var maps: Dictionary = {}

func set_object(map_id: StringName, object_id: StringName, state: Dictionary) -> Error:
	var map_key := String(map_id).strip_edges()
	var object_key := String(object_id).strip_edges()
	if map_key.is_empty() or object_key.is_empty():
		return ERR_INVALID_PARAMETER
	if not _is_persistable_dictionary(state):
		return ERR_INVALID_DATA
	if not maps.has(map_key):
		maps[map_key] = {}
	maps[map_key][object_key] = state.duplicate(true)
	return OK

func get_object(map_id: StringName, object_id: StringName) -> Dictionary:
	var map_key := String(map_id).strip_edges()
	var object_key := String(object_id).strip_edges()
	if map_key.is_empty() or object_key.is_empty() or not maps.has(map_key):
		return {}
	var objects: Variant = maps[map_key]
	if typeof(objects) != TYPE_DICTIONARY or not objects.has(object_key):
		return {}
	var state: Variant = objects[object_key]
	return state.duplicate(true) if typeof(state) == TYPE_DICTIONARY else {}

func snapshot() -> Dictionary:
	return {"maps": maps.duplicate(true)}

func restore(data: Dictionary) -> Error:
	if not data.has("maps") or typeof(data["maps"]) != TYPE_DICTIONARY:
		return ERR_INVALID_DATA
	var candidate: Dictionary = data["maps"]
	if not _is_valid_maps(candidate):
		return ERR_INVALID_DATA
	maps = _normalized_maps(candidate)
	return OK

func clear() -> void:
	maps = {}

func _is_valid_maps(candidate: Dictionary) -> bool:
	var seen_maps := {}
	for raw_map_id in candidate:
		if not _is_nonempty_string(raw_map_id) or typeof(candidate[raw_map_id]) != TYPE_DICTIONARY:
			return false
		var map_key := String(raw_map_id).strip_edges()
		if seen_maps.has(map_key):
			return false
		seen_maps[map_key] = true
		var objects: Dictionary = candidate[raw_map_id]
		var seen_objects := {}
		for raw_object_id in objects:
			if not _is_nonempty_string(raw_object_id) or typeof(objects[raw_object_id]) != TYPE_DICTIONARY:
				return false
			var object_key := String(raw_object_id).strip_edges()
			if seen_objects.has(object_key):
				return false
			seen_objects[object_key] = true
			if not _is_persistable_dictionary(objects[raw_object_id]):
				return false
	return true

func _normalized_maps(candidate: Dictionary) -> Dictionary:
	var normalized := {}
	for raw_map_id in candidate:
		var map_key := String(raw_map_id).strip_edges()
		var normalized_objects := {}
		var objects: Dictionary = candidate[raw_map_id]
		for raw_object_id in objects:
			normalized_objects[String(raw_object_id).strip_edges()] = objects[raw_object_id].duplicate(true)
		normalized[map_key] = normalized_objects
	return normalized

func _is_persistable_dictionary(value: Dictionary) -> bool:
	for key in value:
		if not _is_persistable_value(key) or not _is_persistable_value(value[key]):
			return false
	return true

func _is_persistable_value(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING, TYPE_STRING_NAME:
			return true
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_ARRAY:
			for item in value:
				if not _is_persistable_value(item):
					return false
			return true
		TYPE_DICTIONARY:
			return _is_persistable_dictionary(value)
		_:
			return false

func _is_nonempty_string(value: Variant) -> bool:
	return (typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME) and not String(value).strip_edges().is_empty()
