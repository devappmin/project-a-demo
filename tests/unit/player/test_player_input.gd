extends "res://tests/support/test_case.gd"

const GameMode = preload("res://app/session/game_mode.gd")
const PlayerInput = preload("res://game/actors/player/player_input.gd")

func run() -> void:
	GameSession.change_mode(GameMode.Value.EXPLORATION)
	Input.action_press(&"move_right")
	Input.action_press(&"sprint")
	Input.action_press(&"interact")
	assert_eq(PlayerInput.movement_direction(), Vector2.RIGHT, "exploration permits movement input")
	assert_true(PlayerInput.is_sprinting(), "exploration permits sprint input")
	assert_true(PlayerInput.is_interacting(), "exploration permits interaction input")
	GameSession.change_mode(GameMode.Value.DIALOGUE)
	assert_eq(PlayerInput.movement_direction(), Vector2.ZERO, "dialogue blocks movement input")
	assert_false(PlayerInput.is_sprinting(), "dialogue blocks sprint input")
	assert_false(PlayerInput.is_interacting(), "dialogue blocks interaction input")
	Input.action_release(&"move_right")
	Input.action_release(&"sprint")
	Input.action_release(&"interact")
	GameSession.change_mode(GameMode.Value.EXPLORATION)
