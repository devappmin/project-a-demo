extends Node2D
class_name MapScene

@export var map_id: StringName
@export var room_bounds := Rect2()

func validate_contract() -> PackedStringArray:
	var warnings := PackedStringArray()
	if String(map_id).strip_edges().is_empty():
		warnings.append("map_id must be nonempty.")
	if get_actor_root() == null:
		warnings.append("MapScene requires an Actors child.")
	if get_visual_root() == null:
		warnings.append("MapScene requires a VisualSort child.")
	var entry_points := get_node_or_null("EntryPoints")
	if entry_points == null:
		warnings.append("MapScene requires an EntryPoints child.")
	var entry_names := PackedStringArray()
	var direct_marker_count := 0
	if entry_points != null:
		for child in entry_points.get_children():
			if not child is Marker2D:
				continue
			direct_marker_count += 1
			entry_names.append(String(child.name))
	warnings.append_array(validate_entry_names(entry_names))
	if direct_marker_count == 0:
		warnings.append("EntryPoints requires at least one direct Marker2D child.")
	var persistent_registry := _persistent_world_object_registry()
	warnings.append_array(persistent_registry["warnings"] as PackedStringArray)
	return warnings

func get_spawn(spawn_id: StringName) -> Marker2D:
	var entry_points := get_node_or_null("EntryPoints")
	if entry_points == null:
		return null
	for child in entry_points.get_children():
		if child is Marker2D and child.name == spawn_id:
			return child as Marker2D
	return null

func get_actor_root() -> Node2D:
	return get_node_or_null("Actors") as Node2D

func get_visual_root() -> Node2D:
	return get_node_or_null("VisualSort") as Node2D

func capture_world_objects(world_state: WorldState) -> Error:
	if world_state == null:
		return ERR_INVALID_PARAMETER
	var persistent_registry := _persistent_world_object_registry()
	if not persistent_registry.get("ok", false):
		return persistent_registry.get("error", ERR_INVALID_DATA)
	var objects: Dictionary = persistent_registry["objects"]
	var object_ids := objects.keys()
	object_ids.sort()
	for object_id_value: Variant in object_ids:
		var object_id := String(object_id_value)
		var persistent_object := objects[object_id] as PersistentWorldObject
		var error := world_state.set_object(map_id, StringName(object_id), persistent_object.capture_persisted_state())
		if error != OK:
			return error
	return OK

func apply_world_objects(world_state: WorldState) -> Error:
	if world_state == null:
		return ERR_INVALID_PARAMETER
	var persistent_registry := _persistent_world_object_registry()
	if not persistent_registry.get("ok", false):
		return persistent_registry.get("error", ERR_INVALID_DATA)
	var objects: Dictionary = persistent_registry["objects"]
	var object_ids := objects.keys()
	object_ids.sort()
	for object_id_value: Variant in object_ids:
		var object_id := String(object_id_value)
		var persistent_object := objects[object_id] as PersistentWorldObject
		var state := world_state.get_object(map_id, StringName(object_id))
		if state.is_empty():
			continue
		var error := persistent_object.apply_persisted_state(state)
		if error != OK:
			return error
	return OK

func _persistent_world_object_registry() -> Dictionary:
	var objects := {}
	var warnings := PackedStringArray()
	var error: Error = OK
	for node in find_children("*", "PersistentWorldObject", true, false):
		var persistent_object := node as PersistentWorldObject
		if persistent_object == null:
			continue
		var object_id := String(persistent_object.object_id).strip_edges()
		if object_id.is_empty():
			warnings.append("Persistent objects require a nonempty object_id.")
			if error == OK:
				error = ERR_INVALID_PARAMETER
		elif objects.has(object_id):
			warnings.append("Persistent object IDs must be unique: %s." % object_id)
			if error == OK:
				error = ERR_ALREADY_EXISTS
		else:
			objects[object_id] = persistent_object
	return {"ok": error == OK, "error": error, "objects": objects, "warnings": warnings}

func validate_entry_names(entry_names: PackedStringArray) -> PackedStringArray:
	var warnings := PackedStringArray()
	var seen_names := {}
	for raw_name in entry_names:
		var entry_name := raw_name.strip_edges()
		if entry_name.is_empty():
			warnings.append("Direct entry markers must have nonempty names.")
		elif seen_names.has(entry_name):
			warnings.append("Direct entry marker names must be unique: %s." % entry_name)
		else:
			seen_names[entry_name] = true
	return warnings

func _get_configuration_warnings() -> PackedStringArray:
	return validate_contract()
