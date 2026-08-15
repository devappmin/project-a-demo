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
	var snapshot_inventory_value: Variant = snapshot.get("inventory", {})
	assert_true(typeof(snapshot_inventory_value) == TYPE_DICTIONARY, "snapshot contains an inventory dictionary")
	if typeof(snapshot_inventory_value) != TYPE_DICTIONARY:
		return
	assert_true(snapshot_inventory_value.has("lunch"), "snapshot inventory contains the required lunch entry")
	if not snapshot_inventory_value.has("lunch"):
		return
	var snapshot_lunch_value: Variant = snapshot_inventory_value.get("lunch")
	assert_true(typeof(snapshot_lunch_value) == TYPE_DICTIONARY, "snapshot lunch entry is a dictionary")
	if typeof(snapshot_lunch_value) != TYPE_DICTIONARY:
		return
	snapshot_lunch_value["sandwich"] = 2
	var state_lunch_value: Variant = state.inventory.get("lunch", {})
	assert_true(typeof(state_lunch_value) == TYPE_DICTIONARY, "state retains its nested lunch inventory")
	if typeof(state_lunch_value) == TYPE_DICTIONARY:
		assert_eq(state_lunch_value.get("sandwich", 0), 1, "snapshot does not share nested inventory data")
	var restored := NarrativeState.new()
	assert_eq(restored.restore(state.snapshot()), OK, "snapshot restores")
	assert_eq(restored.snapshot(), state.snapshot(), "round trip is exact")
	var restore_source := state.snapshot()
	var isolated_restore := NarrativeState.new()
	assert_eq(isolated_restore.restore(restore_source), OK, "restore accepts a valid snapshot")
	var restore_inventory_value: Variant = restore_source.get("inventory", {})
	assert_true(typeof(restore_inventory_value) == TYPE_DICTIONARY, "restore source contains an inventory dictionary")
	if typeof(restore_inventory_value) != TYPE_DICTIONARY:
		return
	assert_true(restore_inventory_value.has("lunch"), "restore source inventory contains the required lunch entry")
	if not restore_inventory_value.has("lunch"):
		return
	var restore_lunch_value: Variant = restore_inventory_value.get("lunch")
	assert_true(typeof(restore_lunch_value) == TYPE_DICTIONARY, "restore source lunch entry is a dictionary")
	if typeof(restore_lunch_value) != TYPE_DICTIONARY:
		return
	restore_lunch_value["sandwich"] = 3
	var isolated_lunch_value: Variant = isolated_restore.inventory.get("lunch", {})
	assert_true(typeof(isolated_lunch_value) == TYPE_DICTIONARY, "restored state contains its nested lunch inventory")
	if typeof(isolated_lunch_value) == TYPE_DICTIONARY:
		assert_eq(isolated_lunch_value.get("sandwich", 0), 1, "restore does not share nested input data")
	var before_invalid_restore := restored.snapshot()
	assert_eq(restored.restore({"flags": {}, "stats": [], "inventory": {}, "quests": {}, "collectibles": {}}), ERR_INVALID_DATA, "restore rejects a non-dictionary section")
	assert_eq(restored.snapshot(), before_invalid_restore, "invalid restore leaves state unchanged")
	assert_eq(restored.restore({"flags": {}, "stats": {}, "inventory": {}, "quests": {}}), ERR_INVALID_DATA, "restore rejects a missing section")
	var session := GameSessionService.new()
	assert_not_null(session.narrative_state, "game session owns narrative state")
	session.free()
