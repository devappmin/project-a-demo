extends Node
class_name DialogueActionAdapter

@export var dialogue_service_path: NodePath

@onready var dialogue_service := get_node_or_null(dialogue_service_path) as DialogueService

func handle_action(kind: StringName, payload: Dictionary) -> void:
	if kind not in [&"talk", &"inspect"] or dialogue_service == null:
		return
	var scene_value: Variant = payload.get("scene_key")
	var node_value: Variant = payload.get("node_id", &"")
	if not _is_string_value(scene_value) or not _is_string_value(node_value):
		return
	var scene_key := StringName(scene_value)
	if scene_key.is_empty():
		return
	dialogue_service.start_dialogue(scene_key, StringName(node_value))

func _is_string_value(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME
