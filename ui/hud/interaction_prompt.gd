extends MarginContainer
class_name InteractionPrompt

const GameMode = preload("res://app/session/game_mode.gd")

@export var detector_path: NodePath

@onready var prompt_label: Label = $PanelContainer/PromptLabel

var detector: InteractionDetector

func _ready() -> void:
	if not GameSession.mode_changed.is_connected(_on_mode_changed):
		GameSession.mode_changed.connect(_on_mode_changed)
	detector = get_node_or_null(detector_path) as InteractionDetector
	if detector == null:
		_update_target(null)
		return
	detector.target_changed.connect(_update_target)
	_update_target(detector.current_target)

func _exit_tree() -> void:
	if is_instance_valid(detector) and detector.target_changed.is_connected(_update_target):
		detector.target_changed.disconnect(_update_target)
	if GameSession.mode_changed.is_connected(_on_mode_changed):
		GameSession.mode_changed.disconnect(_on_mode_changed)

func _update_target(target: InteractionTarget) -> void:
	visible = target != null and GameSession.can(GameMode.ACTION_INTERACT)
	prompt_label.text = target.prompt if target != null else ""

func _on_mode_changed(_previous: int, _current: int) -> void:
	_update_target(detector.current_target if is_instance_valid(detector) else null)
