extends Area2D
class_name InteractionTarget

@export var prompt := "조사하기"
@export var action_kind: StringName = &"inspect"
@export var payload: Dictionary = {}

func get_interaction() -> Dictionary:
	return {
		"kind": action_kind,
		"prompt": prompt,
		"payload": payload.duplicate(true),
	}
