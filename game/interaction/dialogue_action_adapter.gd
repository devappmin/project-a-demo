extends Node
class_name DialogueActionAdapter

const DialogueEventResolverResource = preload("res://game/narrative/dialogue/dialogue_event_resolver.gd")

@export var dialogue_service_path: NodePath

@onready var dialogue_service := get_node_or_null(dialogue_service_path) as DialogueService
var event_resolver: DialogueEventResolverResource

func handle_action(kind: StringName, payload: Dictionary) -> Error:
	if kind not in [&"talk", &"inspect"]:
		return ERR_INVALID_PARAMETER
	if dialogue_service == null:
		return ERR_UNCONFIGURED
	if payload.has("dialogue_bundle_key") or payload.has("dialogue_trigger_key"):
		return _handle_document_dialogue(payload)
	return _handle_legacy_dialogue(payload)

func _handle_document_dialogue(payload: Dictionary) -> Error:
	var bundle_value: Variant = payload.get("dialogue_bundle_key")
	var trigger_value: Variant = payload.get("dialogue_trigger_key")
	if not _is_string_value(bundle_value) or not _is_string_value(trigger_value):
		return ERR_INVALID_PARAMETER
	var bundle_key := StringName(bundle_value)
	var trigger_key := StringName(trigger_value)
	if bundle_key.is_empty() or trigger_key.is_empty():
		return ERR_INVALID_PARAMETER
	if event_resolver == null:
		event_resolver = DialogueEventResolverResource.new()
	var resolved: Dictionary = event_resolver.resolve(bundle_key, trigger_key, dialogue_service.narrative_state)
	if not resolved.get("ok", false):
		return resolved.get("error", ERR_INVALID_DATA)
	return dialogue_service.start_dialogue(resolved["scene_key"], resolved["node_id"])

func _handle_legacy_dialogue(payload: Dictionary) -> Error:
	var scene_value: Variant = payload.get("scene_key")
	var node_value: Variant = payload.get("node_id", &"")
	if not _is_string_value(scene_value) or not _is_string_value(node_value):
		return ERR_INVALID_PARAMETER
	var scene_key := StringName(scene_value)
	if scene_key.is_empty():
		return ERR_INVALID_PARAMETER
	return dialogue_service.start_dialogue(scene_key, StringName(node_value))

func _is_string_value(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME
