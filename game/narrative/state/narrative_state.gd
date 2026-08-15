extends RefCounted
class_name NarrativeState

var flags: Dictionary = {}
var stats: Dictionary = {}
var inventory: Dictionary = {}
var quests: Dictionary = {}
var collectibles: Dictionary = {}

func set_flag(key: StringName, value: bool) -> void:
	flags[String(key)] = value

func get_flag(key: StringName, fallback := false) -> bool:
	return bool(flags.get(String(key), fallback))

func set_stat(key: StringName, value: float) -> void:
	stats[String(key)] = value

func get_stat(key: StringName, fallback := 0.0) -> float:
	return float(stats.get(String(key), fallback))

func snapshot() -> Dictionary:
	return {
		"flags": flags.duplicate(true),
		"stats": stats.duplicate(true),
		"inventory": inventory.duplicate(true),
		"quests": quests.duplicate(true),
		"collectibles": collectibles.duplicate(true),
	}

func restore(data: Dictionary) -> Error:
	for section in ["flags", "stats", "inventory", "quests", "collectibles"]:
		if not data.has(section) or typeof(data[section]) != TYPE_DICTIONARY:
			return ERR_INVALID_DATA
	flags = data["flags"].duplicate(true)
	stats = data["stats"].duplicate(true)
	inventory = data["inventory"].duplicate(true)
	quests = data["quests"].duplicate(true)
	collectibles = data["collectibles"].duplicate(true)
	return OK
