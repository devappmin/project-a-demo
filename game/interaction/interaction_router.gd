extends Node
class_name InteractionRouter

const GameMode = preload("res://app/session/game_mode.gd")

signal action_requested(kind: StringName, payload: Dictionary)

@export var detector_path: NodePath = ^"../InteractionDetector"

var detector: InteractionDetector

func _ready() -> void:
	if detector == null:
		detector = get_node_or_null(detector_path) as InteractionDetector

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"interact", false):
		var error := execute_target(detector.current_target if detector != null else null)
		if error == OK:
			get_viewport().set_input_as_handled()

func execute_target(target: InteractionTarget) -> Error:
	if detector == null or target == null or not is_instance_valid(target) or target != detector.current_target:
		return ERR_INVALID_PARAMETER
	if not GameSession.can(GameMode.ACTION_INTERACT):
		return ERR_UNAUTHORIZED
	var interaction := target.get_interaction()
	action_requested.emit(interaction.kind, interaction.payload)
	return OK
