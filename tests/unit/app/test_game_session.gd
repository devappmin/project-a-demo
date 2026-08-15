extends "res://tests/support/test_case.gd"

const GameMode = preload("res://app/session/game_mode.gd")
const GameSessionService = preload("res://app/session/game_session.gd")

func run() -> void:
	var session := GameSessionService.new()
	session.initialize()
	assert_true(session.can(GameMode.ACTION_MOVE), "exploration permits movement")
	assert_true(session.change_mode(GameMode.Value.DIALOGUE), "dialogue transition is valid")
	assert_false(session.can(GameMode.ACTION_MOVE), "dialogue blocks movement")
	assert_true(session.can(GameMode.ACTION_DIALOGUE_ADVANCE), "dialogue permits advance")
	assert_false(session.change_mode(GameMode.Value.BOOT), "runtime cannot return to boot")
	session.free()
