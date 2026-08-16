extends "res://tests/support/test_case.gd"

const GameModeResource = preload("res://app/session/game_mode.gd")

func run() -> void:
	var director_script := load("res://app/scene_flow/scene_director.gd") as Script
	var fade_script := load("res://ui/transitions/screen_fade.gd") as Script
	assert_not_null(director_script, "SceneDirector script exists")
	assert_not_null(fade_script, "ScreenFade script exists")
	if director_script == null or fade_script == null:
		return
	var harness := await _make_harness(director_script, fade_script)
	if harness.is_empty():
		return
	var director: Variant = harness["director"]
	var host: Node2D = harness["host"]
	var fade: ScreenFade = harness["fade"]

	var failures: Array[Dictionary] = []
	director.transition_failed.connect(func(context: Dictionary) -> void: failures.append(context))
	var committed_maps: Array[StringName] = []
	var initial_commit: Array[StringName] = [&"foundation_room"]
	var room_and_hall_commits: Array[StringName] = [&"foundation_room", &"foundation_hall"]
	director.map_committed.connect(func(map_id: StringName, _spawn_id: StringName, _player: PlayerController) -> void: committed_maps.append(map_id))
	var title_restore_plan: Dictionary = director.prepare_restore(&"foundation_room", &"start")
	title_restore_plan["defer_finalize"] = true
	assert_eq(await director.commit_restore(title_restore_plan), OK, "title restore can stage its first candidate transactionally")
	assert_eq(await director.rollback_restore(), OK, "failed title restore can roll back to an empty world")
	await get_tree().process_frame
	assert_eq(host.get_child_count(), 0, "title restore rollback leaves WorldHost empty")
	assert_false(is_instance_valid(director.player), "title restore rollback retains no candidate player")
	assert_eq(GameSession.current_mode, GameModeResource.Value.MENU, "title restore rollback returns to title menu mode")
	committed_maps.clear()
	assert_eq(await director.start_new_game(&"foundation_room", &"start"), OK, "new game commits its first validated map")
	assert_eq(committed_maps, initial_commit, "initial placement publishes one committed map")
	var first_map := host.get_child(0) as MapScene
	var player: PlayerController = director.player
	assert_not_null(first_map, "new game creates a current map")
	assert_not_null(player, "new game creates one persistent player")
	if first_map == null or player == null:
		await _cleanup_harness(harness)
		return
	assert_eq(GameSession.current_mode, GameModeResource.Value.EXPLORATION, "exploration begins only after successful placement")
	assert_eq(player.global_position, Vector2(160, 112), "new game places the player at the requested room spawn")

	var visual_parent := player.presentation.get_parent()
	var failed_error: Error = await director.change_map(&"not_registered", &"start")
	assert_eq(failed_error, ERR_DOES_NOT_EXIST, "unknown maps are rejected before changing the world")
	assert_eq(host.get_child(0), first_map, "failed validation preserves the active map")
	assert_eq(player.global_position, Vector2(160, 112), "failed validation preserves the player transform")
	assert_eq(player.presentation.get_parent(), visual_parent, "failed validation preserves the player visual parent")
	assert_eq(GameSession.current_mode, GameModeResource.Value.EXPLORATION, "failed validation preserves exploration mode")
	assert_eq(failures.size(), 1, "failed validation emits exactly one transition failure")
	assert_eq(await director.change_map(&"foundation_hall", &"missing_spawn"), ERR_INVALID_DATA, "missing spawns are rejected before changing the world")
	assert_eq(host.get_child(0), first_map, "missing spawns preserve the active map")
	assert_eq(player.global_position, Vector2(160, 112), "missing spawns preserve the player transform")
	assert_eq(player.presentation.get_parent(), visual_parent, "missing spawns preserve the player visual parent")
	assert_eq(GameSession.current_mode, GameModeResource.Value.EXPLORATION, "missing spawns preserve exploration mode")
	assert_eq(failures.size(), 2, "missing spawns emit exactly one additional failure")
	assert_true(director.has_method("set_player_placement_hook"), "SceneDirector exposes an injectable player-placement failure seam")
	assert_true(director.has_method("set_map_rebinder"), "SceneDirector exposes a rollback-capable map rebinding seam")
	if director.has_method("set_player_placement_hook"):
		director.call("set_player_placement_hook", func(_map: MapScene, _spawn: StringName) -> Error: return ERR_CANT_CREATE)
		assert_eq(await director.change_map(&"foundation_hall", &"start"), ERR_CANT_CREATE, "placement failure rolls back after the old map is detached")
		assert_eq(host.get_child(0), first_map, "placement failure restores the detached map")
		assert_eq(player.get_parent(), first_map.get_actor_root(), "placement failure restores the player body parent")
		assert_eq(player.presentation.get_parent(), visual_parent, "placement failure restores the player visual parent")
		assert_eq(GameSession.current_mode, GameModeResource.Value.EXPLORATION, "placement failure restores exploration mode")
		assert_eq(failures.size(), 3, "placement failure emits exactly one transition failure")
		assert_eq(committed_maps.size(), 1, "placement rollback does not publish a map commit")
		director.call("set_player_placement_hook", Callable())
	if director.has_method("set_map_rebinder"):
		director.call("set_map_rebinder", func(_player: PlayerController) -> Error: return ERR_CANT_CONNECT)
		assert_eq(await director.change_map(&"foundation_hall", &"start"), ERR_CANT_CONNECT, "rebinding failure rolls back after placement")
		assert_eq(host.get_child(0), first_map, "rebinding failure restores the detached map")
		assert_eq(player.get_parent(), first_map.get_actor_root(), "rebinding failure restores the player body parent")
		assert_eq(player.presentation.get_parent(), visual_parent, "rebinding failure restores the player visual parent")
		assert_eq(GameSession.current_mode, GameModeResource.Value.EXPLORATION, "rebinding failure restores exploration mode")
		assert_eq(failures.size(), 4, "rebinding failure emits exactly one transition failure")
		assert_eq(committed_maps.size(), 1, "rebinding rollback does not publish a map commit")
		director.call("set_map_rebinder", Callable())

	var checkpoints := [0]
	director.stable_checkpoint.connect(func(kind: StringName) -> void:
		if kind == &"map_transition":
			checkpoints[0] += 1
	)
	var plan: Dictionary = director.prepare_restore(&"foundation_hall", &"start")
	assert_true(plan.get("ok", false), "restore preparation builds an off-tree valid candidate")
	assert_eq(host.get_child(0), first_map, "restore preparation does not mutate the current map")
	assert_eq(checkpoints[0], 0, "restore preparation does not emit an autosave checkpoint")
	plan.get("map").free()
	assert_eq(await director.change_map(&"foundation_hall", &"start"), OK, "normal room to hall transition succeeds through change_map")
	await get_tree().process_frame
	var hall := host.get_child(0) as MapScene
	assert_not_null(hall, "restore commit replaces the current map")
	if hall != null:
		assert_eq(hall.map_id, &"foundation_hall", "room to hall transition commits the requested map")
		assert_eq(player.get_parent(), hall.get_actor_root(), "player body is reparented to the new actor root")
		assert_eq(player.presentation.get_parent(), hall.get_visual_root(), "player visual is reparented to the new visual root")
		assert_eq(player.global_position, hall.get_spawn(&"start").global_position, "room to hall transition uses the exact spawn")
	assert_false(is_instance_valid(first_map), "old map is freed only after a successful commit")
	assert_eq(checkpoints[0], 1, "normal room to hall transition emits one stable checkpoint")
	assert_eq(committed_maps, room_and_hall_commits, "map commit publishes only after successful rebinding")

	assert_eq(await director.change_map(&"foundation_room", &"from_hall"), OK, "normal hall to room transition succeeds")
	await get_tree().process_frame
	var returned_room := host.get_child(0) as MapScene
	assert_not_null(returned_room, "normal transition replaces the hall")
	if returned_room != null:
		assert_eq(player.global_position, returned_room.get_spawn(&"from_hall").global_position, "hall to room uses the return spawn")
		assert_eq(player.presentation.get_parent(), returned_room.get_visual_root(), "persistent visual follows player feet after round trip")
	assert_eq(checkpoints[0], 2, "normal transitions emit one stable map checkpoint after placement")
	assert_eq(director.player, player, "both transitions retain the exact same player instance")
	var invalid_world_plan: Dictionary = director.prepare_restore(&"foundation_hall", &"start")
	invalid_world_plan["world"] = {}
	var map_before_invalid_world := host.get_child(0)
	var mode_before_invalid_world := GameSession.current_mode
	assert_eq(await director.commit_restore(invalid_world_plan), ERR_INVALID_DATA, "invalid restore world is rejected before transition mutation")
	assert_eq(host.get_child(0), map_before_invalid_world, "invalid restore world preserves the active map")
	assert_eq(GameSession.current_mode, mode_before_invalid_world, "invalid restore world preserves the current mode")
	assert_true(director.has_method("has_pending_restore"), "SceneDirector exposes pending restore state")
	assert_true(director.has_method("rollback_restore"), "SceneDirector exposes exact restore rollback")
	assert_true(director.has_method("finalize_restore"), "SceneDirector exposes explicit restore finalization")
	if not director.has_method("has_pending_restore") or not director.has_method("rollback_restore") or not director.has_method("finalize_restore"):
		await _cleanup_harness(harness)
		return
	var restore_plan: Dictionary = director.prepare_restore(&"foundation_hall", &"start")
	restore_plan["defer_finalize"] = true
	var map_before_deferred_restore := host.get_child(0) as MapScene
	var position_before_deferred_restore := player.global_position
	var facing_before_deferred_restore := player.facing
	assert_eq(await director.commit_restore(restore_plan), OK, "deferred restore commits a candidate without destroying rollback state")
	assert_true(director.has_pending_restore(), "deferred restore keeps an explicit pending transaction")
	assert_true(is_instance_valid(map_before_deferred_restore), "deferred restore keeps the old map alive")
	player.facing = Vector2.RIGHT if facing_before_deferred_restore != Vector2.RIGHT else Vector2.LEFT
	assert_eq(director.rollback_restore(), OK, "deferred restore can roll back exactly")
	await get_tree().process_frame
	assert_eq(host.get_child(0), map_before_deferred_restore, "rollback reattaches the exact old map instance")
	assert_eq(player.global_position, position_before_deferred_restore, "rollback restores the exact player position")
	assert_eq(player.facing, facing_before_deferred_restore, "rollback restores the exact player facing")
	assert_eq(director.capture_save_context().get("spawn_id"), &"from_hall", "rollback restores the old stable spawn ID")
	assert_false(director.has_pending_restore(), "rollback closes the pending restore transaction")
	var finalize_plan: Dictionary = director.prepare_restore(&"foundation_hall", &"start")
	finalize_plan["defer_finalize"] = true
	var old_map_for_finalize := host.get_child(0) as MapScene
	assert_eq(await director.commit_restore(finalize_plan), OK, "a second deferred restore can commit")
	fade.duration = 0.03
	director.call_deferred("finalize_restore")
	var locked_finalize_frames := 0
	for _frame in range(30):
		await get_tree().process_frame
		if not director.has_pending_restore():
			break
		locked_finalize_frames += 1
		assert_eq(GameSession.current_mode, GameModeResource.Value.TRANSITION, "deferred restore remains input-locked through non-zero fade-in")
		assert_eq(await director.change_map(&"foundation_room", &"start"), ERR_BUSY, "map reentry stays locked through final fade-in")
	assert_true(locked_finalize_frames > 0, "non-zero final fade retains pending restore state for observable frames")
	fade.duration = 0.0
	await get_tree().process_frame
	assert_false(is_instance_valid(old_map_for_finalize), "finalize frees the retained old map only after restore success")
	assert_false(director.has_pending_restore(), "finalize closes the pending restore transaction")
	var rollback_rebind_calls := [0]
	director.set_map_rebinder(func(_restored_player: PlayerController) -> Error:
		rollback_rebind_calls[0] += 1
		return OK if rollback_rebind_calls[0] == 1 else ERR_CANT_CONNECT
	)
	var rollback_failure_plan: Dictionary = director.prepare_restore(&"foundation_room", &"from_hall")
	rollback_failure_plan["defer_finalize"] = true
	assert_eq(await director.commit_restore(rollback_failure_plan), OK, "rollback-failure test mutates to a real committed candidate")
	assert_eq(await director.rollback_restore(), ERR_CANT_CONNECT, "rollback propagates a real old-map rebinding failure")
	assert_true(director.has_method("restore_failure_context"), "SceneDirector exposes structured restore failure context")
	if director.has_method("restore_failure_context"):
		var rollback_context: Dictionary = director.restore_failure_context()
		assert_eq(rollback_context.get("stage"), &"map_rebind", "rollback failure context identifies the failing restoration stage")
		assert_eq(rollback_context.get("error"), ERR_CANT_CONNECT, "rollback failure context includes the exact Godot error")
	director.set_map_rebinder(Callable())
	assert_true(director.has_method("set_transition_hook"), "SceneDirector exposes a reentry seam that runs after the transition lock")
	if director.has_method("set_transition_hook") and returned_room != null:
		assert_eq(returned_room.capture_world_objects(GameSession.world_state), OK, "reentry baseline captures the current world state")
		GameSession.narrative_state.set_flag(&"reentry_flag", true)
		GameSession.play_time_seconds = 91.0
		var narrative_before := GameSession.narrative_state.snapshot()
		var world_before := GameSession.world_state.snapshot()
		var play_time_before := GameSession.play_time_seconds
		var reentry_results: Array[Variant] = []
		director.call("set_transition_hook", func() -> void:
			var reentry_result: Variant = director.start_new_game(&"foundation_room", &"start")
			reentry_results.append(reentry_result)
		)
		assert_eq(await director.change_map(&"foundation_hall", &"start"), OK, "outer transition remains valid while a reentry request is rejected")
		assert_eq(reentry_results.size(), 1, "one reentry request is observed during the active transaction")
		if reentry_results.size() == 1:
			assert_eq(reentry_results[0], ERR_BUSY, "reentrant new game is rejected before it resets session state")
		assert_eq(GameSession.narrative_state.snapshot(), narrative_before, "reentrant new game preserves narrative state")
		assert_eq(GameSession.world_state.snapshot(), world_before, "reentrant new game preserves world state")
		assert_eq(GameSession.play_time_seconds, play_time_before, "reentrant new game preserves play time")
		director.call("set_transition_hook", Callable())
	var player_restore_failure_plan: Dictionary = director.prepare_restore(&"foundation_room", &"from_hall")
	player_restore_failure_plan["defer_finalize"] = true
	assert_eq(await director.commit_restore(player_restore_failure_plan), OK, "player-restore failure test mutates to a real committed candidate")
	player.presentation = null
	assert_eq(await director.rollback_restore(), ERR_DOES_NOT_EXIST, "rollback propagates the first real player restoration error")
	var player_restore_context: Dictionary = director.restore_failure_context()
	assert_eq(player_restore_context.get("stage"), &"player_detach", "player rollback context identifies detach as the first failed stage")
	assert_eq(player_restore_context.get("error"), ERR_DOES_NOT_EXIST, "player rollback context preserves the exact detach error")
	assert_eq(player_restore_context.get("failures"), [
		{"stage": &"player_detach", "error": ERR_DOES_NOT_EXIST},
		{"stage": &"player_attach", "error": ERR_INVALID_PARAMETER},
	], "player rollback context preserves both detach and attach failures")
	await _cleanup_harness(harness)

func _make_harness(director_script: Script, fade_script: Script) -> Dictionary:
	var container := Node.new()
	get_tree().root.add_child(container)
	var host := Node2D.new()
	container.add_child(host)
	var fade: Variant = fade_script.new()
	fade.duration = 0.0
	var curtain := ColorRect.new()
	curtain.name = "Curtain"
	fade.add_child(curtain)
	container.add_child(fade)
	var director: Variant = director_script.new()
	container.add_child(director)
	var configure_error: Error = director.configure(host, fade)
	assert_eq(configure_error, OK, "SceneDirector configures a world host and fade")
	if configure_error != OK:
		container.queue_free()
		await get_tree().process_frame
		return {}
	GameSession.reset_new_game()
	GameSession.change_mode(GameModeResource.Value.MENU)
	return {"container": container, "director": director, "host": host, "fade": fade}

func _cleanup_harness(harness: Dictionary) -> void:
	var container := harness.get("container") as Node
	if is_instance_valid(container):
		container.queue_free()
		await get_tree().process_frame
