extends "res://tests/support/test_case.gd"

const GameSessionService = preload("res://app/session/game_session.gd")
const NarrativeState = preload("res://game/narrative/state/narrative_state.gd")

func run() -> void:
	var state := NarrativeState.new()
	state.set_flag(&"sandwich_more", true)
	state.set_stat(&"corruption", 2.0)
	assert_eq(state.get_flag(&"sandwich_more"), true, "flag is stored by key")
	assert_eq(state.get_stat(&"corruption"), 2.0, "stat is stored by key")
	state.inventory["lunch"] = {"sandwich": 1}
	var snapshot := state.snapshot()
	snapshot["inventory"]["lunch"]["sandwich"] = 2
	assert_eq(state.inventory["lunch"]["sandwich"], 1, "snapshot does not share nested inventory data")
	var restored := NarrativeState.new()
	assert_eq(restored.restore(state.snapshot()), OK, "snapshot restores")
	assert_eq(restored.snapshot(), state.snapshot(), "round trip is exact")
	var restore_source := state.snapshot()
	var isolated_restore := NarrativeState.new()
	assert_eq(isolated_restore.restore(restore_source), OK, "restore accepts a valid snapshot")
	restore_source["inventory"]["lunch"]["sandwich"] = 3
	assert_eq(isolated_restore.inventory["lunch"]["sandwich"], 1, "restore does not share nested input data")
	var before_invalid_restore := restored.snapshot()
	assert_eq(restored.restore({"flags": {}, "stats": [], "inventory": {}, "quests": {}, "collectibles": {}}), ERR_INVALID_DATA, "restore rejects a non-dictionary section")
	assert_eq(restored.snapshot(), before_invalid_restore, "invalid restore leaves state unchanged")
	assert_eq(restored.restore({"flags": {}, "stats": {}, "inventory": {}, "quests": {}}), ERR_INVALID_DATA, "restore rejects a missing section")
	var session := GameSessionService.new()
	assert_not_null(session.narrative_state, "game session owns narrative state")
	session.free()
