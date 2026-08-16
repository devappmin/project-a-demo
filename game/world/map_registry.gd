extends Resource
class_name MapRegistry

@export var definitions: Array[MapDefinition] = []

func definition(map_id: StringName) -> MapDefinition:
	for candidate in definitions:
		if candidate != null and candidate.map_id == map_id:
			return candidate
	return null

func validate_registry() -> PackedStringArray:
	var warnings := PackedStringArray()
	var seen_ids := {}
	for candidate in definitions:
		if candidate == null:
			warnings.append("Map registry contains an empty definition.")
			continue
		var id := String(candidate.map_id).strip_edges()
		if id.is_empty():
			warnings.append("Map definition requires a nonempty map_id.")
		elif seen_ids.has(id):
			warnings.append("Map registry IDs must be unique: %s." % id)
		else:
			seen_ids[id] = true
		if candidate.scene_path.is_empty() or not ResourceLoader.exists(candidate.scene_path):
			warnings.append("Map definition scene is missing: %s." % candidate.scene_path)
			continue
		var packed_scene := load(candidate.scene_path) as PackedScene
		if packed_scene == null:
			warnings.append("Map definition scene is missing: %s." % candidate.scene_path)
			continue
		var map := packed_scene.instantiate()
		if not map is MapScene:
			warnings.append("Map definition scene root must be MapScene: %s." % candidate.scene_path)
			map.free()
			continue
		var map_scene := map as MapScene
		if map_scene.map_id != candidate.map_id:
			warnings.append("Map definition ID does not match its scene: %s." % id)
		if map_scene.get_spawn(candidate.default_spawn) == null:
			warnings.append("Map definition default spawn is missing: %s." % candidate.default_spawn)
		map_scene.free()
	return warnings
