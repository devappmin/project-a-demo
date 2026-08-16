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
	_test_menu_origin_is_explicit(session)
	_test_mode_context_round_trip(session)
	_test_reset_replaces_narrative_state(session)
	_test_restore_rejects_live_narrative_values(session)
	session.free()

func _test_menu_origin_is_explicit(session: GameSessionService) -> void:
	assert_true(session.has_method("enter_menu"), "GameSession exposes an explicit menu entry API")
	assert_true(session.has_method("is_menu_from_exploration"), "GameSession exposes its safe menu origin")
	if not session.has_method("enter_menu") or not session.has_method("is_menu_from_exploration"):
		return
	assert_true(session.change_mode(GameMode.Value.EXPLORATION), "menu-origin test starts in exploration")
	assert_true(session.enter_menu(), "exploration can open a menu")
	assert_true(session.is_menu_from_exploration(), "an explicitly opened exploration menu remembers its origin")
	assert_true(session.change_mode(GameMode.Value.TRANSITION), "load can temporarily lock an exploration-origin menu")
	assert_true(session.change_mode(GameMode.Value.MENU), "failed load can return to its menu")
	assert_true(session.is_menu_from_exploration(), "temporary transition rollback preserves the exploration menu origin")
	assert_true(session.change_mode(GameMode.Value.EXPLORATION), "exploration menu can close")
	assert_false(session.is_menu_from_exploration(), "leaving menu clears its remembered origin")
	assert_true(session.change_mode(GameMode.Value.MENU), "title can enter menu mode directly")
	assert_false(session.is_menu_from_exploration(), "direct menu mode does not impersonate an exploration menu")

func _test_mode_context_round_trip(session: GameSessionService) -> void:
	assert_true(session.has_method("snapshot_mode_context"), "GameSession exposes complete mode-context snapshots")
	assert_true(session.has_method("restore_mode_context"), "GameSession exposes exact mode-context restore")
	if not session.has_method("snapshot_mode_context") or not session.has_method("restore_mode_context"):
		return
	assert_true(session.change_mode(GameMode.Value.EXPLORATION), "mode-context test starts in exploration")
	assert_true(session.enter_menu(), "mode-context test opens an exploration-origin menu")
	var menu_context: Dictionary = session.snapshot_mode_context()
	assert_eq(menu_context, {"mode": GameMode.Value.MENU, "menu_origin_mode": GameMode.Value.EXPLORATION}, "mode snapshot includes the exploration menu origin")
	assert_true(session.change_mode(GameMode.Value.TRANSITION), "mode-context test mutates into transition")
	assert_true(session.change_mode(GameMode.Value.EXPLORATION), "mode-context test mutates away from the saved menu")
	assert_eq(session.restore_mode_context(menu_context), OK, "complete mode context restores exactly")
	assert_true(session.is_menu_from_exploration(), "mode-context restore reinstates manual-save-safe menu provenance")
	var before_invalid: Dictionary = session.snapshot_mode_context()
	assert_eq(session.restore_mode_context({"mode": GameMode.Value.MENU, "menu_origin_mode": GameMode.Value.DIALOGUE}), ERR_INVALID_DATA, "invalid menu origin fails closed")
	assert_eq(session.snapshot_mode_context(), before_invalid, "invalid mode-context restore leaves current context unchanged")

func _test_restore_rejects_live_narrative_values(session: GameSessionService) -> void:
	session.narrative_state.set_flag(&"preserved", true)
	var before := session.snapshot_session()
	var invalid_restore := session.snapshot_session()
	var forbidden_node := Node.new()
	invalid_restore["narrative_state"]["flags"]["forbidden"] = forbidden_node
	assert_eq(session.restore_session(invalid_restore), ERR_INVALID_DATA, "session restore rejects live values nested in NarrativeState")
	assert_eq(session.snapshot_session(), before, "rejected narrative restore preserves the complete session")
	forbidden_node.free()

func _test_reset_replaces_narrative_state(session: GameSessionService) -> void:
	var previous_narrative_state := session.narrative_state
	previous_narrative_state.set_flag(&"retained_before_reset", true)
	session.reset_new_game()
	assert_true(session.narrative_state != previous_narrative_state, "new-game reset replaces NarrativeState instead of mutating retained references")
	assert_true(previous_narrative_state.get_flag(&"retained_before_reset"), "new-game reset leaves the old NarrativeState reference unchanged")
	assert_false(session.narrative_state.get_flag(&"retained_before_reset"), "new-game reset begins with a clean NarrativeState")
