extends Node
class_name DoorActionAdapter

var scene_director: Node

func handle_action(kind: StringName, payload: Dictionary) -> Error:
	if kind != &"door":
		return ERR_INVALID_PARAMETER
	if scene_director == null:
		return ERR_UNCONFIGURED
	var map_value: Variant = payload.get("map_id")
	var spawn_value: Variant = payload.get("spawn_id")
	if not _is_name(map_value) or not _is_name(spawn_value):
		return ERR_INVALID_PARAMETER
	return await scene_director.change_map(StringName(map_value), StringName(spawn_value))

func _is_name(value: Variant) -> bool:
	return (typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME) and not String(value).strip_edges().is_empty()
