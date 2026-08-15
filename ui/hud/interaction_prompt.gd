extends MarginContainer
class_name InteractionPrompt

@export var detector_path: NodePath

@onready var prompt_label: Label = $PanelContainer/PromptLabel

var detector: InteractionDetector

func _ready() -> void:
	detector = get_node_or_null(detector_path) as InteractionDetector
	if detector == null:
		_update_target(null)
		return
	detector.target_changed.connect(_update_target)
	_update_target(detector.current_target)

func _update_target(target: InteractionTarget) -> void:
	visible = target != null
	prompt_label.text = target.prompt if target != null else ""
