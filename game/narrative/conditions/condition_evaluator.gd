extends RefCounted
class_name ConditionEvaluator

const NarrativeStateResource = preload("res://game/narrative/state/narrative_state.gd")

static func matches(condition: Dictionary, state: NarrativeStateResource) -> bool:
	if state == null or not _has_valid_shape(condition):
		return false
	var kind: String = condition["kind"]
	var key: String = condition["key"]
	var operator_name: String = condition["operator"]
	var expected: Variant = condition["value"]
	match kind:
		"flag":
			return _matches_flag(operator_name, expected, state.flags.get(key, false))
		"stat":
			return _matches_number(operator_name, expected, state.stats.get(key, 0.0))
		"inventory":
			return _matches_quantity(operator_name, expected, state.inventory.get(key, 0.0))
		"quest":
			return _matches_quest(operator_name, expected, state.quests.get(key, ""))
		"collectible":
			return _matches_quantity(operator_name, expected, state.collectibles.get(key, 0.0))
		_:
			return false

static func _has_valid_shape(condition: Dictionary) -> bool:
	return condition.has_all(["kind", "key", "operator", "value"]) \
		and typeof(condition["kind"]) == TYPE_STRING \
		and not String(condition["kind"]).is_empty() \
		and typeof(condition["key"]) == TYPE_STRING \
		and not String(condition["key"]).is_empty() \
		and typeof(condition["operator"]) == TYPE_STRING

static func _matches_flag(operator_name: String, expected: Variant, actual: Variant) -> bool:
	if typeof(expected) != TYPE_BOOL or typeof(actual) != TYPE_BOOL:
		return false
	if operator_name == "eq":
		return actual == expected
	if operator_name == "neq":
		return actual != expected
	return false

static func _matches_number(operator_name: String, expected: Variant, actual: Variant) -> bool:
	if not _is_number(expected) or not _is_number(actual):
		return false
	match operator_name:
		"eq":
			return actual == expected
		"neq":
			return actual != expected
		"gt":
			return actual > expected
		"gte":
			return actual >= expected
		"lt":
			return actual < expected
		"lte":
			return actual <= expected
		_:
			return false

static func _matches_quantity(operator_name: String, expected: Variant, actual: Variant) -> bool:
	if operator_name == "contains":
		return typeof(expected) == TYPE_BOOL and _is_number(actual) and (actual > 0.0) == expected
	return _matches_number(operator_name, expected, actual)

static func _matches_quest(operator_name: String, expected: Variant, actual: Variant) -> bool:
	if typeof(expected) != TYPE_STRING or typeof(actual) != TYPE_STRING:
		return false
	if operator_name == "eq":
		return actual == expected
	if operator_name == "neq":
		return actual != expected
	return false

static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
