class_name PlayerInput

const GameMode = preload("res://app/session/game_mode.gd")

static func movement_direction() -> Vector2:
	if not GameSession.can(GameMode.ACTION_MOVE):
		return Vector2.ZERO
	return Input.get_vector(&"move_left", &"move_right", &"move_up", &"move_down")

static func is_sprinting() -> bool:
	return GameSession.can(GameMode.ACTION_SPRINT) and Input.is_action_pressed(&"sprint")

static func is_interacting() -> bool:
	return GameSession.can(GameMode.ACTION_INTERACT) and Input.is_action_pressed(&"interact")
