extends RefCounted
class_name EffectExecutor

const NarrativeStateResource = preload("res://game/narrative/state/narrative_state.gd")

static func apply(effect: Dictionary, state: NarrativeStateResource) -> Error:
	if state == null or not _has_valid_shape(effect):
		return ERR_INVALID_DATA
	var kind: String = effect["kind"]
	var key: String = effect["key"]
	var value: Variant = effect["value"]
	match kind:
		"flag_set":
			if typeof(value) != TYPE_BOOL:
				return ERR_INVALID_DATA
			state.set_flag(StringName(key), value)
		"stat_set":
			if not _is_number(value):
				return ERR_INVALID_DATA
			state.set_stat(StringName(key), value)
		"stat_add":
			if not _is_number(value) or not _is_number(state.stats.get(key, 0.0)):
				return ERR_INVALID_DATA
			state.set_stat(StringName(key), state.get_stat(StringName(key)) + float(value))
		"inventory_add":
			if not _is_non_negative_number(value) or not _is_number(state.inventory.get(key, 0.0)):
				return ERR_INVALID_DATA
			state.inventory[key] = float(state.inventory.get(key, 0.0)) + float(value)
		"inventory_remove":
			if not _is_non_negative_number(value) or not _is_number(state.inventory.get(key, 0.0)):
				return ERR_INVALID_DATA
			state.inventory[key] = maxf(0.0, float(state.inventory.get(key, 0.0)) - float(value))
		"quest_set":
			if typeof(value) != TYPE_STRING:
				return ERR_INVALID_DATA
			state.quests[key] = value
		"collectible_add":
			if not _is_non_negative_number(value) or not _is_number(state.collectibles.get(key, 0.0)):
				return ERR_INVALID_DATA
			state.collectibles[key] = float(state.collectibles.get(key, 0.0)) + float(value)
		_:
			return ERR_INVALID_DATA
	return OK

static func _has_valid_shape(effect: Dictionary) -> bool:
	return effect.has_all(["kind", "key", "value"]) \
		and typeof(effect["kind"]) == TYPE_STRING \
		and not String(effect["kind"]).is_empty() \
		and typeof(effect["key"]) == TYPE_STRING \
		and not String(effect["key"]).is_empty()

static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT

static func _is_non_negative_number(value: Variant) -> bool:
	return _is_number(value) and value >= 0.0
