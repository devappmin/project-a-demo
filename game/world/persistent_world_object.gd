extends Node
class_name PersistentWorldObject

@export var object_id: StringName
var inspected := false
var registration_error: Error = OK

func _ready() -> void:
	registration_error = _register_with_map()

func capture_persisted_state() -> Dictionary:
	return {"inspected": inspected}

func apply_persisted_state(state: Dictionary) -> Error:
	if not state.has("inspected") or typeof(state["inspected"]) != TYPE_BOOL:
		return ERR_INVALID_DATA
	inspected = state["inspected"]
	return OK

func _register_with_map() -> Error:
	if String(object_id).strip_edges().is_empty():
		return ERR_INVALID_PARAMETER
	var map := _find_map_scene()
	if map == null:
		return ERR_DOES_NOT_EXIST
	var registry: Dictionary = map.get_meta("_persistent_world_objects", {})
	var object_key := String(object_id).strip_edges()
	if registry.has(object_key):
		return ERR_ALREADY_EXISTS
	registry[object_key] = self
	map.set_meta("_persistent_world_objects", registry)
	return OK

func _find_map_scene() -> MapScene:
	var current := get_parent()
	while current != null:
		if current is MapScene:
			return current as MapScene
		current = current.get_parent()
	return null
