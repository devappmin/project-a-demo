extends RefCounted
class_name NarrativeCatalog

const DEFAULT_PATH := "res://data/narrative/narrative_catalog.json"
const CONDITION_KINDS := [&"flag", &"stat", &"inventory", &"quest", &"collectible"]
const MAPPING_STATUSES := [&"exact", &"approved"]

var _terms_by_identity: Dictionary = {}
var _triggers: Dictionary = {}
var _commands: Dictionary = {}
var _catalog_issues: Array[Dictionary] = []

static func load_default() -> NarrativeCatalog:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DEFAULT_PATH))
	return from_dictionary(parsed if typeof(parsed) == TYPE_DICTIONARY else {})

static func from_dictionary(data: Dictionary) -> NarrativeCatalog:
	var catalog := NarrativeCatalog.new()
	catalog._install(data)
	return catalog

func has_trigger(trigger_key: StringName) -> bool:
	return _triggers.has(String(trigger_key))

func validate_catalog() -> Array[Dictionary]:
	return _catalog_issues.duplicate(true)

func validate_condition(record: Dictionary) -> Dictionary:
	return _validate_mapping(record, true)

func validate_effect(record: Dictionary) -> Dictionary:
	return _validate_mapping(record, false)

func terms_for_kind(kind: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for term: Dictionary in _terms_by_identity.values():
		if StringName(term.get("kind", "")) == kind:
			result.append(term.duplicate(true))
	result.sort_custom(_record_key_less)
	return result

func triggers() -> Array[Dictionary]:
	return _sorted_records(_triggers)

func commands() -> Array[Dictionary]:
	return _sorted_records(_commands)

func _install(data: Dictionary) -> void:
	if int(data.get("schema_version", 0)) != 1:
		_catalog_issues.append(_issue("unsupported_schema", "schema_version must be 1"))
	_install_terms(data.get("terms", null))
	_install_records(data.get("triggers", null), _triggers, "trigger")
	_install_records(data.get("commands", null), _commands, "command")

func _install_terms(value: Variant) -> void:
	if typeof(value) != TYPE_ARRAY:
		_catalog_issues.append(_issue("invalid_terms", "terms must be an array"))
		return
	for term_value: Variant in value:
		if typeof(term_value) != TYPE_DICTIONARY:
			_catalog_issues.append(_issue("invalid_term", "term must be a dictionary"))
			continue
		var term: Dictionary = term_value
		var kind := String(term.get("kind", ""))
		var key := String(term.get("key", ""))
		var display_name := String(term.get("display_name", ""))
		if StringName(kind) not in CONDITION_KINDS or key.is_empty() or display_name.is_empty():
			_catalog_issues.append(_issue("invalid_term", "term requires a supported kind, key, and display_name"))
			continue
		if not _has_required_term_metadata(term):
			_catalog_issues.append(_issue("invalid_term_metadata", "term requires a text description, aliases, and default"))
			continue
		if not _has_valid_term_constraints(term, kind):
			_catalog_issues.append(_issue("invalid_term_constraints", "term constraints do not match its kind"))
			continue
		var identity := _identity(kind, key)
		if _terms_by_identity.has(identity):
			_catalog_issues.append(_issue("duplicate_term", "term key is duplicated for its kind"))
			continue
		_terms_by_identity[identity] = term.duplicate(true)

func _install_records(value: Variant, destination: Dictionary, label: String) -> void:
	if typeof(value) != TYPE_ARRAY:
		_catalog_issues.append(_issue("invalid_%ss" % label, "%ss must be an array" % label))
		return
	for record_value: Variant in value:
		if typeof(record_value) != TYPE_DICTIONARY:
			_catalog_issues.append(_issue("invalid_%s" % label, "%s must be a dictionary" % label))
			continue
		var record: Dictionary = record_value
		var key := String(record.get("key", ""))
		var display_name := String(record.get("display_name", ""))
		if key.is_empty() or display_name.is_empty():
			_catalog_issues.append(_issue("invalid_%s" % label, "%s requires a key and display_name" % label))
			continue
		if not _has_required_record_metadata(record):
			_catalog_issues.append(_issue("invalid_%s_metadata" % label, "%s requires a text description and aliases" % label))
			continue
		if destination.has(key):
			_catalog_issues.append(_issue("duplicate_%s" % label, "%s key is duplicated" % label))
			continue
		destination[key] = record.duplicate(true)

func _validate_mapping(record: Dictionary, is_condition: bool) -> Dictionary:
	var mapping_status := String(record.get("mapping_status", ""))
	if StringName(mapping_status) not in MAPPING_STATUSES:
		return _validation_failure("mapping_not_approved", "mapping_status must be exact or approved")
	var runtime_kind := String(record.get("kind", ""))
	var catalog_kind := runtime_kind if is_condition else _effect_catalog_kind(runtime_kind)
	if catalog_kind.is_empty():
		return _validation_failure("unsupported_kind", "kind is not supported")
	var key := String(record.get("key", ""))
	var term_value: Variant = _terms_by_identity.get(_identity(catalog_kind, key))
	if typeof(term_value) != TYPE_DICTIONARY:
		return _validation_failure("unknown_catalog_key", "key is not registered for this kind")
	var term: Dictionary = term_value
	if mapping_status == "exact" and not _matches_registered_name(String(record.get("term_name", "")), term):
		return _validation_failure("term_name_mismatch", "term_name must match the registered Korean name or alias")
	var input_value: Variant = record.get("value", null)
	if is_condition:
		var operator_name := String(record.get("operator", ""))
		if not _has_valid_condition_operator(catalog_kind, operator_name):
			return _validation_failure("unsupported_operator", "operator is not supported for this kind")
		if operator_name == "contains" and (catalog_kind == "inventory" or catalog_kind == "collectible"):
			if typeof(input_value) != TYPE_BOOL:
				return _validation_failure("invalid_value", "value does not satisfy the registered constraints")
		elif not _has_valid_value(term, catalog_kind, input_value):
			return _validation_failure("invalid_value", "value does not satisfy the registered constraints")
		return _validation_success({"kind":catalog_kind, "key":key, "operator":operator_name, "value":input_value})
	if not _has_valid_effect_value(term, runtime_kind, input_value):
		return _validation_failure("invalid_value", "value does not satisfy the registered constraints")
	return _validation_success({"kind":runtime_kind, "key":key, "value":input_value})

func _has_valid_term_constraints(term: Dictionary, kind: String) -> bool:
	var default_value: Variant = term.get("default", null)
	match kind:
		"flag":
			return typeof(default_value) == TYPE_BOOL
		"stat":
			return _is_number(default_value) and _has_valid_numeric_bounds(term) and _is_within_bounds(default_value, term)
		"inventory", "collectible":
			return _is_number(default_value) and default_value >= 0.0 and _has_non_negative_numeric_bounds(term) and _is_within_bounds(default_value, term)
		"quest":
			return typeof(default_value) == TYPE_STRING and _has_valid_stages(term) and String(default_value) in term["stages"]
	return false

func _has_valid_value(term: Dictionary, kind: String, value: Variant) -> bool:
	match kind:
		"flag":
			return typeof(value) == TYPE_BOOL
		"stat":
			return _is_number(value) and _is_within_bounds(value, term)
		"inventory", "collectible":
			return _is_number(value) and value >= 0.0 and _is_within_bounds(value, term)
		"quest":
			return typeof(value) == TYPE_STRING and String(value) in term.get("stages", [])
	return false

func _has_valid_effect_value(term: Dictionary, effect_kind: String, value: Variant) -> bool:
	match effect_kind:
		"flag_set":
			return typeof(value) == TYPE_BOOL
		"stat_set", "stat_add":
			return _is_number(value) and _is_within_bounds(value, term)
		"inventory_add", "inventory_remove", "collectible_add":
			return _is_number(value) and value >= 0.0 and _is_within_bounds(value, term)
		"quest_set":
			return typeof(value) == TYPE_STRING and String(value) in term.get("stages", [])
	return false

func _has_valid_condition_operator(kind: String, operator_name: String) -> bool:
	match kind:
		"flag", "quest":
			return operator_name in ["eq", "neq"]
		"stat":
			return operator_name in ["eq", "neq", "gt", "gte", "lt", "lte"]
		"inventory", "collectible":
			return operator_name in ["eq", "neq", "gt", "gte", "lt", "lte", "contains"]
	return false

func _effect_catalog_kind(effect_kind: String) -> String:
	match effect_kind:
		"flag_set":
			return "flag"
		"stat_set", "stat_add":
			return "stat"
		"inventory_add", "inventory_remove":
			return "inventory"
		"quest_set":
			return "quest"
		"collectible_add":
			return "collectible"
	return ""

func _has_valid_aliases(value: Variant) -> bool:
	if typeof(value) != TYPE_ARRAY:
		return false
	for alias: Variant in value:
		if typeof(alias) != TYPE_STRING or String(alias).is_empty():
			return false
	return true

func _has_required_term_metadata(term: Dictionary) -> bool:
	return term.has("description") and typeof(term["description"]) == TYPE_STRING and not String(term["description"]).is_empty() \
		and term.has("aliases") and _has_valid_aliases(term["aliases"]) and term.has("default")

func _has_required_record_metadata(record: Dictionary) -> bool:
	return record.has("description") and typeof(record["description"]) == TYPE_STRING and not String(record["description"]).is_empty() \
		and record.has("aliases") and _has_valid_aliases(record["aliases"])

func _has_valid_numeric_bounds(term: Dictionary) -> bool:
	var minimum: Variant = term.get("minimum", null)
	var maximum: Variant = term.get("maximum", null)
	return _is_number(minimum) and _is_number(maximum) and minimum <= maximum

func _has_non_negative_numeric_bounds(term: Dictionary) -> bool:
	return _has_valid_numeric_bounds(term) and term["minimum"] >= 0.0

func _has_valid_stages(term: Dictionary) -> bool:
	var stages: Variant = term.get("stages", null)
	if typeof(stages) != TYPE_ARRAY or stages.is_empty():
		return false
	for stage: Variant in stages:
		if typeof(stage) != TYPE_STRING or String(stage).is_empty():
			return false
	return true

func _is_within_bounds(value: Variant, term: Dictionary) -> bool:
	return value >= term.get("minimum", value) and value <= term.get("maximum", value)

func _matches_registered_name(term_name: String, term: Dictionary) -> bool:
	if term_name == String(term.get("display_name", "")):
		return true
	for alias: Variant in term.get("aliases", []):
		if term_name == String(alias):
			return true
	return false

func _sorted_records(records: Dictionary) -> Array[Dictionary]:
	var keys := records.keys()
	keys.sort()
	var result: Array[Dictionary] = []
	for key: Variant in keys:
		result.append((records[key] as Dictionary).duplicate(true))
	return result

func _record_key_less(left: Dictionary, right: Dictionary) -> bool:
	return String(left.get("key", "")) < String(right.get("key", ""))

func _identity(kind: String, key: String) -> String:
	return "%s:%s" % [kind, key]

func _validation_success(value: Dictionary) -> Dictionary:
	return {"ok":true, "code":"", "message":"", "value":value}

func _validation_failure(code: String, message: String) -> Dictionary:
	return {"ok":false, "code":code, "message":message, "value":{}}

func _issue(code: String, message: String) -> Dictionary:
	return {"code":code, "message":message}

func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
