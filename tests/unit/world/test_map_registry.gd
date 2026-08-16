extends "res://tests/support/test_case.gd"

func run() -> void:
	var registry_script := load("res://game/world/map_registry.gd") as Script
	assert_not_null(registry_script, "MapRegistry script exists")
	if registry_script == null:
		return
	var registry: Variant = registry_script.new()
	var definition_script := load("res://game/world/map_definition.gd") as Script
	assert_not_null(definition_script, "MapDefinition script exists")
	if definition_script == null:
		return

	var room: Variant = definition_script.new()
	room.map_id = &"foundation_room"
	room.scene_path = "res://content/maps/foundation_room.tscn"
	room.default_spawn = &"start"
	room.display_name = "Foundation Room"
	var duplicate: Variant = definition_script.new()
	duplicate.map_id = &"foundation_room"
	duplicate.scene_path = "res://content/maps/foundation_hall.tscn"
	duplicate.default_spawn = &"start"
	var missing_scene: Variant = definition_script.new()
	missing_scene.map_id = &"missing_scene"
	missing_scene.scene_path = "res://content/maps/not_here.tscn"
	missing_scene.default_spawn = &"start"
	var wrong_root: Variant = definition_script.new()
	wrong_root.map_id = &"wrong_root"
	wrong_root.scene_path = "res://game/actors/player/player.tscn"
	wrong_root.default_spawn = &"start"
	var missing_spawn: Variant = definition_script.new()
	missing_spawn.map_id = &"foundation_hall"
	missing_spawn.scene_path = "res://content/maps/foundation_hall.tscn"
	missing_spawn.default_spawn = &"not_here"

	var definitions: Array[MapDefinition] = [room as MapDefinition, duplicate as MapDefinition, missing_scene as MapDefinition, wrong_root as MapDefinition, missing_spawn as MapDefinition]
	registry.definitions = definitions
	var warnings: PackedStringArray = registry.validate_registry()
	assert_eq(warnings.size(), 5, "registry rejects duplicate IDs, missing scenes, wrong roots, scene ID mismatches, and missing default spawns")
	assert_eq(registry.definition(&"foundation_room"), room, "definition lookup returns the registered resource")
	assert_eq(registry.definition(&"not_registered"), null, "unknown definitions return null")

	var shipped_registry := load("res://data/maps/map_registry.tres")
	assert_not_null(shipped_registry, "the shipped map registry loads")
	if shipped_registry != null:
		assert_eq(shipped_registry.validate_registry(), PackedStringArray(), "the shipped registry validates its scenes and spawns")
		var shipped_room = shipped_registry.definition(&"foundation_room")
		assert_not_null(shipped_room, "the shipped registry resolves foundation room")
		if shipped_room != null:
			assert_eq(shipped_room.display_name, "기초 방", "room display name matches shipped Korean slot metadata")
		var shipped_hall = shipped_registry.definition(&"foundation_hall")
		assert_not_null(shipped_hall, "the shipped registry resolves foundation hall")
		if shipped_hall != null:
			assert_eq(shipped_hall.display_name, "기초 홀", "hall display name matches shipped Korean slot metadata")
