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

	var failures: Array[Dictionary] = []
	director.transition_failed.connect(func(context: Dictionary) -> void: failures.append(context))
	assert_eq(await director.start_new_game(&"foundation_room", &"start"), OK, "new game commits its first validated map")
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

	var checkpoints := [0]
	director.stable_checkpoint.connect(func(kind: StringName) -> void:
		if kind == &"map_transition":
			checkpoints[0] += 1
	)
	var plan: Dictionary = director.prepare_restore(&"foundation_hall", &"start")
	assert_true(plan.get("ok", false), "restore preparation builds an off-tree valid candidate")
	assert_eq(host.get_child(0), first_map, "restore preparation does not mutate the current map")
	assert_eq(checkpoints[0], 0, "restore preparation does not emit an autosave checkpoint")
	assert_eq(await director.commit_restore(plan), OK, "restore commit accepts the validated candidate")
	await get_tree().process_frame
	var hall := host.get_child(0) as MapScene
	assert_not_null(hall, "restore commit replaces the current map")
	if hall != null:
		assert_eq(hall.map_id, &"foundation_hall", "room to hall transition commits the requested map")
		assert_eq(player.get_parent(), hall.get_actor_root(), "player body is reparented to the new actor root")
		assert_eq(player.presentation.get_parent(), hall.get_visual_root(), "player visual is reparented to the new visual root")
		assert_eq(player.global_position, hall.get_spawn(&"start").global_position, "room to hall transition uses the exact spawn")
	assert_false(is_instance_valid(first_map), "old map is freed only after a successful commit")
	assert_eq(checkpoints[0], 0, "restore commit itself remains checkpoint-free")

	assert_eq(await director.change_map(&"foundation_room", &"from_hall"), OK, "normal hall to room transition succeeds")
	await get_tree().process_frame
	var returned_room := host.get_child(0) as MapScene
	assert_not_null(returned_room, "normal transition replaces the hall")
	if returned_room != null:
		assert_eq(player.global_position, returned_room.get_spawn(&"from_hall").global_position, "hall to room uses the return spawn")
		assert_eq(player.presentation.get_parent(), returned_room.get_visual_root(), "persistent visual follows player feet after round trip")
	assert_eq(checkpoints[0], 1, "normal transitions emit one stable map checkpoint after placement")
	assert_eq(director.player, player, "both transitions retain the exact same player instance")
	await _cleanup_harness(harness)

func _make_harness(director_script: Script, fade_script: Script) -> Dictionary:
	var container := Node.new()
	get_tree().root.add_child(container)
	var host := Node2D.new()
	container.add_child(host)
	var fade: Variant = fade_script.new()
	fade.duration = 0.0
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
	return {"container": container, "director": director, "host": host}

func _cleanup_harness(harness: Dictionary) -> void:
	var container := harness.get("container") as Node
	if is_instance_valid(container):
		container.queue_free()
		await get_tree().process_frame
