extends RefCounted
class_name DialogueEventIndex

const DEFAULT_PATH := "res://data/generated/dialogues/events.json"

var _bundles: Dictionary = {}
var _last_failure: Dictionary = {}
var _valid := false

var last_failure: Dictionary:
	get:
		return _last_failure.duplicate(true)

static func load_default() -> DialogueEventIndex:
	return load_path(DEFAULT_PATH)

static func load_path(path: String) -> DialogueEventIndex:
	var index := DialogueEventIndex.new()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		index._fail("load_failed", "dialogue event index could not be opened", path)
		return index
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	if parse_error != OK:
		index._fail("parse_failed", "dialogue event index JSON is malformed at line %d: %s" % [parser.get_error_line(), parser.get_error_message()], path)
		return index
	if typeof(parser.data) != TYPE_DICTIONARY:
		index._fail("invalid_root", "dialogue event index root must be a dictionary", path)
		return index
	index._install(parser.data)
	if not index.is_valid() and not path.is_empty():
		index._last_failure["path"] = path
	return index

static func from_dictionary(data: Dictionary) -> DialogueEventIndex:
	var index := DialogueEventIndex.new()
	index._install(data)
	return index

func is_valid() -> bool:
	return _valid

func has_bundle(bundle_key: StringName) -> bool:
	return is_valid() and _bundles.has(String(bundle_key))

func has_trigger(bundle_key: StringName, trigger_key: StringName) -> bool:
	if not has_bundle(bundle_key):
		return false
	var bundle: Dictionary = _bundles[String(bundle_key)]
	return (bundle["triggers"] as Dictionary).has(String(trigger_key))

func candidates(bundle_key: StringName, trigger_key: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not has_trigger(bundle_key, trigger_key):
		return result
	var bundle: Dictionary = _bundles[String(bundle_key)]
	var triggers: Dictionary = bundle["triggers"]
	for candidate_value: Variant in triggers[String(trigger_key)]:
		result.append((candidate_value as Dictionary).duplicate(true))
	return result

func _install(data: Dictionary) -> void:
	_bundles = {}
	_last_failure = {}
	_valid = false
	if data.get("schema_version") != 1:
		_fail("unsupported_schema", "dialogue event index requires schema version 1")
		return
	var bundles_value: Variant = data.get("bundles")
	if typeof(bundles_value) != TYPE_DICTIONARY:
		_fail("invalid_bundles", "dialogue event index bundles must be a dictionary")
		return
	var candidate_bundles: Dictionary = bundles_value
	for bundle_key_value: Variant in candidate_bundles:
		if typeof(bundle_key_value) != TYPE_STRING or String(bundle_key_value).is_empty():
			_fail("invalid_bundle_key", "dialogue event bundle keys must be non-empty strings")
			return
		var bundle_value: Variant = candidate_bundles[bundle_key_value]
		if typeof(bundle_value) != TYPE_DICTIONARY:
			_fail("invalid_bundle", "dialogue event bundle must be a dictionary")
			return
		var bundle: Dictionary = bundle_value
		var triggers_value: Variant = bundle.get("triggers")
		if typeof(triggers_value) != TYPE_DICTIONARY:
			_fail("invalid_triggers", "dialogue event bundle triggers must be a dictionary")
			return
		var triggers: Dictionary = triggers_value
		for trigger_key_value: Variant in triggers:
			if typeof(trigger_key_value) != TYPE_STRING or String(trigger_key_value).is_empty():
				_fail("invalid_trigger_key", "dialogue event trigger keys must be non-empty strings")
				return
			var candidates_value: Variant = triggers[trigger_key_value]
			if typeof(candidates_value) != TYPE_ARRAY or candidates_value.is_empty():
				_fail("invalid_candidates", "dialogue event candidates must be a non-empty array")
				return
			for candidate_value: Variant in candidates_value:
				if typeof(candidate_value) != TYPE_DICTIONARY:
					_fail("invalid_candidate", "dialogue event candidate must be a dictionary")
					return
				var candidate: Dictionary = candidate_value
				if not _candidate_is_valid(candidate):
					return
	_bundles = candidate_bundles.duplicate(true)
	_valid = true

func _candidate_is_valid(candidate: Dictionary) -> bool:
	if not _has_non_empty_string(candidate, "event_key") or not _has_non_empty_string(candidate, "entry_node"):
		_fail("invalid_candidate", "dialogue event candidate requires event_key and entry_node")
		return false
	var conditions_value: Variant = candidate.get("conditions")
	if typeof(conditions_value) != TYPE_ARRAY:
		_fail("invalid_conditions", "dialogue event candidate conditions must be an array")
		return false
	for condition_value: Variant in conditions_value:
		if typeof(condition_value) != TYPE_DICTIONARY or not _condition_is_valid(condition_value):
			_fail("invalid_condition", "dialogue event condition is malformed")
			return false
	return true

func _condition_is_valid(condition: Dictionary) -> bool:
	if not _has_non_empty_string(condition, "kind") \
		or not _has_non_empty_string(condition, "key") \
		or not _has_non_empty_string(condition, "operator") \
		or not condition.has("value"):
		return false
	var kind := String(condition["kind"])
	var operator_name := String(condition["operator"])
	var value: Variant = condition["value"]
	match kind:
		"flag":
			return operator_name in ["eq", "neq"] and typeof(value) == TYPE_BOOL
		"stat":
			return operator_name in ["eq", "neq", "gt", "gte", "lt", "lte"] and _is_number(value)
		"inventory", "collectible":
			if operator_name == "contains":
				return typeof(value) == TYPE_BOOL
			return operator_name in ["eq", "neq", "gt", "gte", "lt", "lte"] and _is_number(value)
		"quest":
			return operator_name in ["eq", "neq"] and typeof(value) == TYPE_STRING
		_:
			return false

func _has_non_empty_string(value: Dictionary, key: String) -> bool:
	return value.has(key) and typeof(value[key]) == TYPE_STRING and not String(value[key]).is_empty()

func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT

func _fail(code: String, message: String, path := "") -> void:
	_valid = false
	_last_failure = {"code":code, "message":message, "path":path}
