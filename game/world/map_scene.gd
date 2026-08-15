extends Node2D
class_name MapScene

@export var map_id: StringName
@export var room_bounds := Rect2()

func _ready() -> void:
	var camera := get_node_or_null("Player/Camera2D") as Camera2D
	if camera == null or room_bounds.size == Vector2.ZERO:
		return
	camera.limit_left = int(room_bounds.position.x)
	camera.limit_top = int(room_bounds.position.y)
	camera.limit_right = int(room_bounds.end.x)
	camera.limit_bottom = int(room_bounds.end.y)
