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
	_test_restore_rejects_live_narrative_values(session)
	session.free()

func _test_restore_rejects_live_narrative_values(session: GameSessionService) -> void:
	session.narrative_state.set_flag(&"preserved", true)
	var before := session.snapshot_session()
	var invalid_restore := session.snapshot_session()
	var forbidden_node := Node.new()
	invalid_restore["narrative_state"]["flags"]["forbidden"] = forbidden_node
	assert_eq(session.restore_session(invalid_restore), ERR_INVALID_DATA, "session restore rejects live values nested in NarrativeState")
	assert_eq(session.snapshot_session(), before, "rejected narrative restore preserves the complete session")
	forbidden_node.free()
