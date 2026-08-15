extends "res://tests/support/test_case.gd"

const GameMode = preload("res://app/session/game_mode.gd")
const PlayerInput = preload("res://game/actors/player/player_input.gd")

func _key_event(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	return event

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
	assert_true(InputMap.event_is_action(_key_event(KEY_A), &"move_left", true), "A moves left")
	assert_true(InputMap.event_is_action(_key_event(KEY_LEFT), &"move_left", true), "left arrow moves left")
	assert_true(InputMap.event_is_action(_key_event(KEY_D), &"move_right", true), "D moves right")
	assert_true(InputMap.event_is_action(_key_event(KEY_RIGHT), &"move_right", true), "right arrow moves right")
	assert_true(InputMap.event_is_action(_key_event(KEY_W), &"move_up", true), "W moves up")
	assert_true(InputMap.event_is_action(_key_event(KEY_UP), &"move_up", true), "up arrow moves up")
	assert_true(InputMap.event_is_action(_key_event(KEY_S), &"move_down", true), "S moves down")
	assert_true(InputMap.event_is_action(_key_event(KEY_DOWN), &"move_down", true), "down arrow moves down")
	assert_true(InputMap.event_is_action(_key_event(KEY_SHIFT), &"sprint", true), "Shift sprints")
	assert_true(InputMap.event_is_action(_key_event(KEY_E), &"interact", true), "E interacts")
