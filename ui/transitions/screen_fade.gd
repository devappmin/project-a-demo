extends Control
class_name ScreenFade

@export var duration := 0.2

@onready var curtain: ColorRect = get_node_or_null("Curtain") as ColorRect

func fade_out() -> void:
	await _fade_to(1.0)

func fade_in() -> void:
	await _fade_to(0.0)

func _fade_to(target_opacity: float) -> void:
	if curtain == null:
		return
	if duration <= 0.0:
		curtain.modulate.a = target_opacity
		return
	var tween := create_tween()
	tween.tween_property(curtain, "modulate:a", target_opacity, duration)
	await tween.finished
