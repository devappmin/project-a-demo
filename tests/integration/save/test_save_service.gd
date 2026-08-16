extends "res://tests/support/test_case.gd"

const GameModeResource = preload("res://app/session/game_mode.gd")
const SaveDataResource = preload("res://app/save/save_data.gd")
const SaveRepositoryResource = preload("res://app/save/save_repository.gd")
const SceneDirectorResource = preload("res://app/scene_flow/scene_director.gd")
const ScreenFadeResource = preload("res://ui/transitions/screen_fade.gd")

class FakePlayer:
	extends Node2D
	var facing := Vector2.DOWN

class FakeDirector:
	extends Node
	signal stable_checkpoint(kind: StringName)
	var player := FakePlayer.new()
	var map_id: StringName = &"foundation_room"
	var spawn_id: StringName = &"start"
	var location_name := "기초 방"
	var world_snapshot := {"maps": {}}
	var player_holder := Node2D.new()
	var prepare_error: Error = OK
	var commit_error: Error = OK
	var prepare_modes: Array[int] = []
	var committed := false
	var finalized := false
	var rolled_back := false
	var emit_checkpoint_on_commit := false
	var _previous := {}

	func _ready() -> void:
		add_child(player_holder)
		player_holder.position = Vector2(10.0, 20.0)
		player_holder.add_child(player)

	func capture_save_context() -> Dictionary:
		return {
			"ok": true,
			"map_id": map_id,
			"spawn_id": spawn_id,
			"location_name": location_name,
			"position": player.global_position,
			"facing": player.facing,
			"world": world_snapshot.duplicate(true),
		}

	func prepare_restore(next_map_id: StringName, next_spawn_id: StringName) -> Dictionary:
		prepare_modes.append(GameSession.current_mode)
		if prepare_error != OK:
			return {"ok": false, "error": prepare_error}
		return {"ok": true, "map_id": next_map_id, "spawn_id": next_spawn_id, "candidate": {}}

	func commit_restore(plan: Dictionary) -> Error:
		if commit_error != OK:
			return commit_error
		_previous = {"map_id": map_id, "spawn_id": spawn_id, "position": player.global_position, "facing": player.facing}
		map_id = plan["map_id"]
		spawn_id = plan["spawn_id"]
		committed = true
		if emit_checkpoint_on_commit:
			stable_checkpoint.emit(&"map_transition")
		return OK

	func finalize_restore() -> Error:
		finalized = true
		return OK

	func rollback_restore() -> Error:
		rolled_back = true
		if not _previous.is_empty():
			map_id = _previous["map_id"]
			spawn_id = _previous["spawn_id"]
			player.global_position = _previous["position"]
			player.facing = _previous["facing"]
		return OK

class FakeDialogue:
	extends DialogueService
	var checkpoint := {"active": false}
	var validation_error: Error = OK
	var resume_error: Error = OK
	var refresh_error: Error = OK
	var refresh_errors: Array[Error] = []
	var resumed: Array[Dictionary] = []

	func get_checkpoint() -> Dictionary:
		return checkpoint.duplicate(true)

	func validate_checkpoint(_checkpoint_value: Dictionary) -> Error:
		return validation_error

	func resume_checkpoint(checkpoint_value: Dictionary) -> Error:
		if resume_error != OK:
			return resume_error
		resumed.append(checkpoint_value.duplicate(true))
		GameSession.change_mode(GameModeResource.Value.DIALOGUE)
		return OK

	func refresh_session_state() -> Error:
		if not refresh_errors.is_empty():
			return refresh_errors.pop_front()
		return refresh_error if refresh_error != OK else super.refresh_session_state()

class FakeRepository:
	extends SaveRepositoryResource
	var writes: Array[Dictionary] = []
	var results := {}
	var write_error: Error = OK
	var write_hook: Callable
	var read_modes: Array[int] = []

	func write_slot(slot_id: StringName, snapshot: Dictionary) -> Error:
		writes.append({"slot_id": slot_id, "snapshot": snapshot.duplicate(true)})
		if write_hook.is_valid():
			write_hook.call()
		return write_error

	func read_slot(slot_id: StringName) -> Dictionary:
		read_modes.append(GameSession.current_mode)
		return results.get(slot_id, {"ok": false, "error": ERR_FILE_NOT_FOUND, "data": {}, "recovered": false, "diagnostic": {}}).duplicate(true)

	func read_metadata(slot_id: StringName) -> Dictionary:
		var result: Dictionary = results.get(StringName("metadata_%s" % slot_id), {})
		return result.duplicate(true)

var _save_service_script: Script

func run() -> void:
	_save_service_script = load("res://app/save/save_service.gd") as Script
	assert_not_null(_save_service_script, "SaveService script exists")
	if _save_service_script == null:
		return
	await _test_manual_save_capture_and_mode_gate()
	await _test_autosave_coalescing_and_signals()
	await _test_restore_preflight_success_and_rollback()
	await _test_real_restore_lock_and_checkpoint_boundaries()
	await _test_real_post_mutation_failures_restore_context()
	await _test_real_title_empty_world_rollback()
	_test_slot_metadata_is_ordered_and_copied()

func _test_manual_save_capture_and_mode_gate() -> void:
	var harness := await _make_harness()
	var service: Node = harness.service
	var director: FakeDirector = harness.director
	var dialogue: FakeDialogue = harness.dialogue
	var repository: FakeRepository = harness.repository
	GameSession.reset_new_game()
	GameSession.narrative_state.set_flag(&"mirror_seen", true)
	GameSession.world_state.set_object(&"foundation_room", &"mirror", {"inspected": true})
	GameSession.play_time_seconds = 42.5
	director.player.global_position = Vector2(12.5, 34.25)
	director.player.facing = Vector2.LEFT
	director.world_snapshot = GameSession.world_state.snapshot()
	dialogue.checkpoint = {"active": true, "bundle_key": "foundation.inspect", "trigger_key": "mirror.inspect", "node_id": "mirror_after_choice", "boundary": "line"}
	GameSession.change_mode(GameModeResource.Value.EXPLORATION)
	assert_eq(service.call("save_manual_slot", &"slot_1"), OK, "manual save is permitted during exploration")
	assert_eq(repository.writes.size(), 1, "a valid manual save writes exactly once")
	if repository.writes.is_empty():
		await _cleanup_harness(harness)
		return
	var saved: Dictionary = repository.writes[0].snapshot
	assert_eq(saved.get("meta", {}).get("slot_id"), "slot_1", "snapshot contains the requested manual slot")
	assert_eq(saved.get("meta", {}).get("location_name"), "기초 방", "snapshot contains the map display name")
	assert_eq(saved.get("meta", {}).get("play_time_seconds"), 42.5, "snapshot contains exact play time")
	assert_eq(saved.get("player"), {"map_id": "foundation_room", "spawn_id": "start", "position": {"x": 12.5, "y": 34.25}, "facing": "left"}, "snapshot contains exact player restore data")
	assert_eq(saved.get("narrative"), GameSession.narrative_state.snapshot(), "snapshot contains exact NarrativeState")
	assert_eq(saved.get("world"), GameSession.world_state.snapshot(), "snapshot contains exact WorldState")
	assert_eq(saved.get("dialogue"), dialogue.checkpoint, "snapshot contains the exact active dialogue checkpoint")
	assert_eq(service.call("save_manual_slot", &"auto"), ERR_INVALID_PARAMETER, "manual save API never accepts the autosave slot")
	for blocked_mode in [GameModeResource.Value.DIALOGUE, GameModeResource.Value.CUTSCENE, GameModeResource.Value.TRANSITION, GameModeResource.Value.PAUSED]:
		GameSession.change_mode(blocked_mode)
		assert_eq(service.call("save_manual_slot", &"slot_2"), ERR_UNAVAILABLE, "manual save is rejected in mode %s" % blocked_mode)
	GameSession.change_mode(GameModeResource.Value.MENU)
	assert_eq(service.call("save_manual_slot", &"slot_2"), ERR_UNAVAILABLE, "title-only menu cannot manually save")
	GameSession.change_mode(GameModeResource.Value.EXPLORATION)
	assert_true(GameSession.enter_menu(), "test opens a menu through the explicit exploration-origin API")
	assert_eq(service.call("save_manual_slot", &"slot_2"), OK, "menu opened from exploration can manually save")
	GameSession.change_mode(GameModeResource.Value.EXPLORATION)
	var nested_result := [OK]
	var nested_load_result := [OK]
	repository.write_hook = func() -> void:
		nested_result[0] = service.call("save_manual_slot", &"slot_3")
		nested_load_result[0] = service.call("load_slot", &"slot_3")
		assert_true(service.call("is_busy"), "service reports busy while repository write is active")
	assert_eq(service.call("save_manual_slot", &"slot_3"), OK, "outer manual save completes")
	assert_eq(nested_result[0], ERR_BUSY, "service-busy state rejects manual save reentry")
	assert_eq(nested_load_result[0], ERR_BUSY, "service-busy state rejects load reentry")
	repository.write_hook = Callable()
	var writes_before_invalid := repository.writes.size()
	director.player.global_position = Vector2(INF, 0.0)
	assert_eq(service.call("save_manual_slot", &"slot_4"), ERR_INVALID_DATA, "non-finite player state fails closed")
	assert_eq(repository.writes.size(), writes_before_invalid, "invalid capture fails before repository write")
	director.player.global_position = Vector2(12.0, 34.0)
	for invalid_facing: Vector2 in [Vector2.ZERO, Vector2.ONE, Vector2(0.5, 0.0), Vector2(INF, 0.0), Vector2(NAN, 0.0)]:
		var writes_before_facing := repository.writes.size()
		director.player.facing = invalid_facing
		assert_eq(service.call("save_manual_slot", &"slot_4"), ERR_INVALID_DATA, "non-cardinal facing %s fails closed" % invalid_facing)
		assert_eq(repository.writes.size(), writes_before_facing, "invalid facing %s is rejected before repository write" % invalid_facing)
	await _cleanup_harness(harness)

func _test_autosave_coalescing_and_signals() -> void:
	var harness := await _make_harness()
	var service: Node = harness.service
	var director: FakeDirector = harness.director
	var repository: FakeRepository = harness.repository
	GameSession.reset_new_game()
	GameSession.change_mode(GameModeResource.Value.EXPLORATION)
	var completed := [0]
	var failed := [0]
	service.save_completed.connect(func(slot_id: StringName) -> void:
		if slot_id == &"auto": completed[0] += 1
	)
	service.save_failed.connect(func(slot_id: StringName, _context: Dictionary) -> void:
		if slot_id == &"auto": failed[0] += 1
	)
	GameSession.play_time_seconds = 1.0
	director.stable_checkpoint.emit(&"map_transition")
	GameSession.play_time_seconds = 2.0
	var mutable_checkpoint := {"active": true, "bundle_key": "foundation.inspect", "trigger_key": "mirror.inspect", "node_id": "mirror_after_choice", "boundary": "line"}
	harness.dialogue.stable_checkpoint_reached.emit(&"important_choice", mutable_checkpoint)
	mutable_checkpoint["node_id"] = "mutated_by_caller"
	await get_tree().process_frame
	assert_eq(repository.writes.size(), 1, "same-frame autosave requests coalesce into one write")
	if repository.writes.is_empty():
		await _cleanup_harness(harness)
		return
	assert_eq(repository.writes[0].snapshot.meta.play_time_seconds, 2.0, "same-frame coalescing keeps the newest stable snapshot")
	assert_eq(repository.writes[0].snapshot.dialogue.node_id, "mirror_after_choice", "queued autosave freezes caller-owned checkpoint data")
	assert_eq(completed[0], 1, "successful autosave emits completion exactly once")
	assert_eq(failed[0], 0, "successful autosave emits no failure")
	var requested_during_write := [false]
	repository.write_hook = func() -> void:
		if requested_during_write[0]: return
		requested_during_write[0] = true
		GameSession.play_time_seconds = 3.0
		service.call("request_autosave", &"map_transition", {})
		GameSession.play_time_seconds = 4.0
		service.call("request_autosave", &"important_choice", {"active": false})
	service.call("request_autosave", &"map_transition", {})
	await get_tree().process_frame
	assert_eq(repository.writes.size(), 3, "a request during a write serializes one newest pending write")
	assert_eq(repository.writes[2].snapshot.meta.play_time_seconds, 4.0, "write-time coalescing keeps only the newest pending stable snapshot")
	assert_eq(repository.writes[2].snapshot.dialogue, {"active": false, "bundle_key": "", "trigger_key": "", "node_id": "", "boundary": ""}, "important choice ending dialogue saves inactive context")
	repository.write_hook = Callable()
	repository.write_error = ERR_CANT_CREATE
	service.call("request_autosave", &"map_transition", {})
	await get_tree().process_frame
	assert_eq(failed[0], 1, "failed autosave emits failure exactly once")
	var writes_before_failed_events := repository.writes.size()
	service.call("request_autosave", &"failed_transition", {})
	await get_tree().process_frame
	assert_eq(repository.writes.size(), writes_before_failed_events, "failed transition or choice kinds never produce autosaves")
	await _cleanup_harness(harness)

func _test_restore_preflight_success_and_rollback() -> void:
	var harness := await _make_harness()
	var service: Node = harness.service
	var director: FakeDirector = harness.director
	var dialogue: FakeDialogue = harness.dialogue
	var repository: FakeRepository = harness.repository
	GameSession.reset_new_game()
	GameSession.narrative_state.set_flag(&"before", true)
	GameSession.play_time_seconds = 9.0
	director.player.global_position = Vector2(1.0, 2.0)
	GameSession.change_mode(GameModeResource.Value.EXPLORATION)
	var before := _complete_current_state(director)
	assert_eq(await service.call("load_slot", &"slot_1"), ERR_FILE_NOT_FOUND, "missing slot fails closed")
	assert_eq(_complete_current_state(director), before, "missing slot preserves map, session, player, and mode exactly")
	assert_eq(repository.read_modes, [GameModeResource.Value.EXPLORATION], "repository validation happens before mode mutation")
	repository.results[&"slot_1"] = {"ok": true, "error": OK, "data": _snapshot("slot_1", false), "recovered": false, "diagnostic": {}}
	director.prepare_error = ERR_DOES_NOT_EXIST
	assert_eq(await service.call("load_slot", &"slot_1"), ERR_DOES_NOT_EXIST, "invalid map or spawn fails during preflight")
	assert_eq(_complete_current_state(director), before, "map preflight failure leaves current state identical")
	if not director.prepare_modes.is_empty():
		assert_eq(director.prepare_modes[-1], GameModeResource.Value.EXPLORATION, "candidate map is prepared before transition mode")
	director.prepare_error = OK
	dialogue.validation_error = ERR_INVALID_PARAMETER
	repository.results[&"slot_1"] = {"ok": true, "error": OK, "data": _snapshot("slot_1", true), "recovered": false, "diagnostic": {}}
	assert_eq(await service.call("load_slot", &"slot_1"), ERR_INVALID_PARAMETER, "invalid dialogue checkpoint fails during preflight")
	assert_eq(_complete_current_state(director), before, "checkpoint preflight failure leaves current state identical")
	dialogue.validation_error = OK
	var recovered_count := [0]
	var loaded_count := [0]
	service.backup_recovered.connect(func(_slot_id: StringName) -> void: recovered_count[0] += 1)
	service.load_completed.connect(func(_slot_id: StringName) -> void: loaded_count[0] += 1)
	repository.results[&"slot_1"] = {"ok": true, "error": OK, "data": _snapshot("slot_1", true), "recovered": true, "diagnostic": {}}
	director.emit_checkpoint_on_commit = true
	service.call("request_autosave", &"map_transition", {})
	assert_eq(await service.call("load_slot", &"slot_1"), OK, "validated recovered slot loads successfully")
	await get_tree().process_frame
	assert_true(director.committed and director.finalized, "load commits candidate then finalizes retained rollback state")
	assert_eq(GameSession.play_time_seconds, 77.0, "load restores exact play time")
	assert_true(GameSession.narrative_state.get_flag(&"loaded"), "load restores exact narrative state")
	assert_eq(GameSession.world_state.get_object(&"foundation_room", &"mirror"), {"inspected": true}, "load restores exact world state")
	assert_eq(director.player.global_position, Vector2(80.0, 90.0), "load restores exact player position")
	assert_eq(director.player.facing, Vector2.RIGHT, "load restores exact player facing")
	assert_eq(dialogue.resumed.size(), 1, "active checkpoint resumes exactly once without event resolution")
	assert_eq(GameSession.current_mode, GameModeResource.Value.DIALOGUE, "active checkpoint finishes load in dialogue mode")
	assert_eq(recovered_count[0], 1, "backup recovery emits exactly one recovery signal")
	assert_eq(loaded_count[0], 1, "recovered load still completes exactly once")
	assert_eq(repository.writes.size(), 0, "load success cancels queued and restore-generated autosaves")
	repository.results[&"slot_1"] = {"ok": true, "error": OK, "data": _snapshot("slot_1", false), "recovered": false, "diagnostic": {}}
	GameSession.change_mode(GameModeResource.Value.MENU)
	assert_eq(await service.call("load_slot", &"slot_1"), OK, "inactive dialogue checkpoint loads successfully")
	assert_eq(GameSession.current_mode, GameModeResource.Value.EXPLORATION, "inactive checkpoint returns to exploration")
	assert_eq(dialogue.resumed.size(), 1, "inactive checkpoint does not invoke dialogue resume")
	await _cleanup_harness(harness)

func _test_real_restore_lock_and_checkpoint_boundaries() -> void:
	var harness := await _make_real_restore_harness(true)
	var service: Node = harness.service
	var director: SceneDirectorService = harness.director
	var dialogue: DialogueService = harness.dialogue
	var repository: FakeRepository = harness.repository
	var fade: ScreenFade = harness.fade
	fade.duration = 0.04
	assert_true(GameSession.enter_menu(), "real lock test loads from an exploration-origin menu")
	var line_checkpoint := {
		"active": true,
		"bundle_key": "foundation.inspect",
		"trigger_key": "mirror.inspect",
		"node_id": "default.inspect.line_e5b0e4bd5f23",
		"boundary": "line",
	}
	repository.results[&"slot_1"] = {"ok": true, "error": OK, "data": _restore_snapshot("slot_1", &"foundation_hall", &"start", line_checkpoint), "recovered": false, "diagnostic": {}}
	var completed := [false]
	var failed := [false]
	var lines: Array[Dictionary] = []
	service.load_completed.connect(func(_slot_id: StringName) -> void: completed[0] = true, CONNECT_ONE_SHOT)
	service.load_failed.connect(func(_slot_id: StringName, _context: Dictionary) -> void: failed[0] = true, CONNECT_ONE_SHOT)
	dialogue.line_requested.connect(func(character: StringName, expression: StringName, text: String) -> void:
		lines.append({"character": character, "expression": expression, "text": text})
	)
	service.call_deferred("load_slot", &"slot_1")
	var locked_frames := 0
	for _frame in range(120):
		await get_tree().process_frame
		if completed[0] or failed[0]:
			break
		if service.is_busy():
			locked_frames += 1
			assert_eq(GameSession.current_mode, GameModeResource.Value.TRANSITION, "every observable load frame remains transition-locked")
			assert_false(GameSession.can(GameModeResource.ACTION_MOVE), "movement stays locked before load completion")
			assert_false(GameSession.can(GameModeResource.ACTION_DIALOGUE_ADVANCE), "dialogue advance stays locked before load completion")
			if GameSession.can(GameModeResource.ACTION_MOVE):
				director.player.global_position += Vector2(5.0, 0.0)
			if GameSession.can(GameModeResource.ACTION_DIALOGUE_ADVANCE):
				dialogue.advance()
	assert_true(completed[0] and not failed[0], "non-zero-fade restore completes successfully")
	assert_true(locked_frames > 0, "non-zero fade exposes at least one locked frame")
	assert_eq(director.player.global_position, Vector2(80.0, 90.0), "restored player position cannot change before load completion")
	assert_eq(dialogue.get_checkpoint(), line_checkpoint, "exact active line checkpoint cannot advance before load completion")
	assert_eq(lines, [{"character": &"retti", "expression": &"uneasy", "text": "거울 속에는 이 방과 조금 다른 방이 비친다."}], "line restore publishes the exact saved boundary once")
	assert_eq(GameSession.current_mode, GameModeResource.Value.DIALOGUE, "active line restore unlocks into dialogue only at completion")
	dialogue.abort_dialogue(&"test_cleanup")
	assert_true(GameSession.enter_menu(), "choice restore re-enters from exploration menu")
	var choice_checkpoint := {
		"active": true,
		"bundle_key": "foundation.inspect",
		"trigger_key": "mirror.inspect",
		"node_id": "default.start.choice_93440f2bd8ca",
		"boundary": "choice",
	}
	repository.results[&"slot_2"] = {"ok": true, "error": OK, "data": _restore_snapshot("slot_2", &"foundation_room", &"start", choice_checkpoint), "recovered": false, "diagnostic": {}}
	var choices: Array[Array] = []
	dialogue.choices_requested.connect(func(items: Array[Dictionary]) -> void: choices.append(items.duplicate(true)))
	assert_eq(await service.call("load_slot", &"slot_2"), OK, "exact choice-boundary checkpoint restores")
	assert_eq(dialogue.get_checkpoint(), choice_checkpoint, "choice restore retains the exact active checkpoint payload")
	assert_eq(choices.size(), 1, "choice restore publishes one exact choice boundary")
	if not choices.is_empty():
		assert_eq(choices[0].map(func(item: Dictionary) -> String: return String(item.get("text", ""))), ["거울을 자세히 본다", "한 걸음 물러난다"], "choice restore publishes saved-node choices without resolver selection")
	dialogue.abort_dialogue(&"test_cleanup")
	await _cleanup_harness(harness)

func _test_real_post_mutation_failures_restore_context() -> void:
	var harness := await _make_real_restore_harness(true)
	var service: Node = harness.service
	var director: SceneDirectorService = harness.director
	var repository: FakeRepository = harness.repository
	assert_true(service.has_method("set_restore_apply_hook"), "SaveService exposes a post-mutation apply failure seam")
	assert_true(director.has_method("set_restore_finalize_hook"), "SceneDirector exposes a post-mutation finalize failure seam")
	if not service.has_method("set_restore_apply_hook") or not director.has_method("set_restore_finalize_hook"):
		await _cleanup_harness(harness)
		return
	director.player.global_position = Vector2(11.0, 22.0)
	director.player.facing = Vector2.LEFT
	GameSession.narrative_state.set_flag(&"preserved", true)
	GameSession.play_time_seconds = 12.0
	assert_true(GameSession.enter_menu(), "post-mutation failure starts from an exploration-origin menu")
	var old_map: Node = harness.host.get_child(0)
	var old_state := _real_current_state(harness)
	repository.results[&"slot_3"] = {"ok": true, "error": OK, "data": _restore_snapshot("slot_3", &"foundation_hall", &"start", {"active": false}), "recovered": false, "diagnostic": {}}
	var observed_apply_mutation := [false]
	service.set_restore_apply_hook(func() -> Error:
		observed_apply_mutation[0] = GameSession.narrative_state.get_flag(&"loaded") and director.player.global_position == Vector2(80.0, 90.0) and harness.host.get_child(0) != old_map
		return ERR_CANT_CREATE
	)
	assert_eq(await service.call("load_slot", &"slot_3"), ERR_CANT_CREATE, "failure after real session/map/player mutation is reported")
	assert_true(observed_apply_mutation[0], "apply failure seam runs only after real restore mutation")
	assert_eq(_real_current_state(harness), old_state, "post-apply failure restores exact map/session/player/mode context")
	assert_true(GameSession.is_menu_from_exploration(), "post-apply failure restores exploration-origin menu provenance")
	service.set_restore_apply_hook(Callable())
	var observed_finalize_mutation := [false]
	director.set_restore_finalize_hook(func() -> Error:
		observed_finalize_mutation[0] = GameSession.narrative_state.get_flag(&"loaded") and director.player.global_position == Vector2(80.0, 90.0) and harness.host.get_child(0) != old_map
		return ERR_CANT_CREATE
	)
	assert_eq(await service.call("load_slot", &"slot_3"), ERR_CANT_CREATE, "failure after real finalize-stage mutation is reported")
	assert_true(observed_finalize_mutation[0], "finalize failure seam observes the committed restored state")
	assert_eq(_real_current_state(harness), old_state, "finalize failure rolls back exact map/session/player/mode context")
	assert_true(GameSession.is_menu_from_exploration(), "finalize failure restores exploration-origin menu provenance")
	director.set_restore_finalize_hook(Callable())
	var rebind_calls := [0]
	director.set_map_rebinder(func(_player: PlayerController) -> Error:
		rebind_calls[0] += 1
		return OK if rebind_calls[0] == 1 else ERR_CANT_CONNECT
	)
	service.set_restore_apply_hook(func() -> Error: return ERR_CANT_CREATE)
	var failure_contexts: Array[Dictionary] = []
	service.load_failed.connect(func(_slot_id: StringName, context: Dictionary) -> void: failure_contexts.append(context.duplicate(true)))
	assert_eq(await service.call("load_slot", &"slot_3"), ERR_CANT_CONNECT, "rollback error supersedes and propagates the triggering apply error")
	assert_false(failure_contexts.is_empty(), "rollback failure emits structured load failure context")
	if not failure_contexts.is_empty():
		assert_eq(failure_contexts[-1].get("primary_error"), ERR_CANT_CREATE, "structured failure retains the primary apply error")
		assert_eq(failure_contexts[-1].get("rollback", {}).get("stage"), &"map_rebind", "structured failure identifies rollback stage")
		assert_eq(failure_contexts[-1].get("rollback", {}).get("error"), ERR_CANT_CONNECT, "structured failure contains exact rollback error")
	director.set_map_rebinder(Callable())
	service.set_restore_apply_hook(Callable())
	var failing_dialogue := FakeDialogue.new()
	failing_dialogue.refresh_errors = [OK, ERR_CANT_CONNECT]
	harness.container.add_child(failing_dialogue)
	assert_eq(service.configure(director, failing_dialogue), OK, "rollback refresh test injects only the dialogue refresh boundary")
	service.set_restore_apply_hook(func() -> Error: return ERR_CANT_CREATE)
	failure_contexts.clear()
	assert_eq(await service.call("load_slot", &"slot_3"), ERR_CANT_CONNECT, "rollback dialogue refresh error is propagated")
	assert_false(failure_contexts.is_empty(), "rollback refresh failure emits structured context")
	if not failure_contexts.is_empty():
		assert_eq(failure_contexts[-1].get("primary_error"), ERR_CANT_CREATE, "refresh failure context retains the triggering apply error")
		assert_eq(failure_contexts[-1].get("rollback", {}).get("stage"), &"dialogue_refresh", "refresh failure context identifies dialogue refresh rollback stage")
		assert_eq(failure_contexts[-1].get("rollback", {}).get("error"), ERR_CANT_CONNECT, "refresh failure context contains exact refresh error")
	service.set_restore_apply_hook(Callable())
	await _cleanup_harness(harness)

func _test_real_title_empty_world_rollback() -> void:
	var harness := await _make_real_restore_harness(false)
	var service: Node = harness.service
	var director: SceneDirectorService = harness.director
	var repository: FakeRepository = harness.repository
	assert_true(director.has_method("set_restore_finalize_hook"), "title rollback uses the real finalize failure seam")
	if not director.has_method("set_restore_finalize_hook"):
		await _cleanup_harness(harness)
		return
	GameSession.reset_new_game()
	GameSession.change_mode(GameModeResource.Value.MENU)
	var title_state := _real_current_state(harness)
	repository.results[&"slot_4"] = {"ok": true, "error": OK, "data": _restore_snapshot("slot_4", &"foundation_hall", &"start", {"active": false}), "recovered": false, "diagnostic": {}}
	director.set_restore_finalize_hook(func() -> Error: return ERR_CANT_CREATE)
	assert_eq(await service.call("load_slot", &"slot_4"), ERR_CANT_CREATE, "title post-commit finalize failure is reported")
	await get_tree().process_frame
	assert_eq(_real_current_state(harness), title_state, "title post-commit failure restores exact empty-world state")
	assert_eq(harness.host.get_child_count(), 0, "real title rollback leaves WorldHost empty")
	assert_false(is_instance_valid(director.player), "real title rollback retains no candidate player")
	assert_eq(GameSession.current_mode, GameModeResource.Value.MENU, "real title rollback remains in title menu")
	assert_false(GameSession.is_menu_from_exploration(), "real title rollback does not invent gameplay menu provenance")
	await _cleanup_harness(harness)

func _test_slot_metadata_is_ordered_and_copied() -> void:
	var repository := FakeRepository.new()
	repository.results[&"metadata_slot_2"] = {"location_name": "기초 홀", "play_time_seconds": 12.0, "saved_at": "2026-08-16T12:34:56Z", "recoverable": false}
	var service: Node = _save_service_script.new()
	service.set("repository", repository)
	var metadata: Array[Dictionary] = service.call("slot_metadata")
	assert_eq(metadata.size(), 6, "slot metadata always returns the fixed six slots")
	var ids: Array[StringName] = []
	for row in metadata:
		ids.append(row.get("slot_id", &""))
	assert_eq(ids, [&"auto", &"slot_1", &"slot_2", &"slot_3", &"slot_4", &"slot_5"], "slot metadata preserves canonical slot order")
	assert_false(metadata[0].get("exists", true), "empty autosave metadata is marked missing")
	assert_true(metadata[2].get("exists", false), "populated manual metadata is marked present")
	metadata[2]["location_name"] = "caller mutation"
	assert_eq(repository.results[&"metadata_slot_2"]["location_name"], "기초 홀", "slot metadata callers receive deep copies")
	service.free()

func _make_harness() -> Dictionary:
	var container := Node.new()
	get_tree().root.add_child(container)
	var director := FakeDirector.new()
	var dialogue := FakeDialogue.new()
	var repository := FakeRepository.new()
	var service: Node = _save_service_script.new()
	container.add_child(director)
	container.add_child(dialogue)
	container.add_child(service)
	service.set("repository", repository)
	assert_eq(service.call("configure", director, dialogue), OK, "SaveService configures injected director and dialogue dependencies")
	return {"container": container, "service": service, "director": director, "dialogue": dialogue, "repository": repository}

func _make_real_restore_harness(start_game: bool) -> Dictionary:
	var container := Node.new()
	get_tree().root.add_child(container)
	var host := Node2D.new()
	container.add_child(host)
	var fade := ScreenFadeResource.new()
	var curtain := ColorRect.new()
	curtain.name = "Curtain"
	fade.add_child(curtain)
	fade.duration = 0.0
	container.add_child(fade)
	var director := SceneDirectorResource.new()
	container.add_child(director)
	assert_eq(director.configure(host, fade), OK, "real restore director configures")
	GameSession.reset_new_game()
	GameSession.change_mode(GameModeResource.Value.MENU)
	if start_game:
		assert_eq(await director.start_new_game(&"foundation_room", &"start"), OK, "real restore harness starts an initial map")
	var dialogue := DialogueService.new()
	dialogue.game_session = GameSession
	container.add_child(dialogue)
	var repository := FakeRepository.new()
	var service: Node = _save_service_script.new()
	container.add_child(service)
	service.set("repository", repository)
	assert_eq(service.call("configure", director, dialogue), OK, "real restore harness configures SaveService")
	return {"container": container, "host": host, "fade": fade, "director": director, "dialogue": dialogue, "repository": repository, "service": service}

func _cleanup_harness(harness: Dictionary) -> void:
	var container: Node = harness.container
	container.queue_free()
	await get_tree().process_frame

func _snapshot(slot_id: String, active_dialogue: bool) -> Dictionary:
	return SaveDataResource.with_checksum({
		"schema_version": 1,
		"meta": {"slot_id": slot_id, "saved_at": "2026-08-16T12:34:56Z", "play_time_seconds": 77.0, "location_name": "기초 방"},
		"player": {"map_id": "foundation_room", "spawn_id": "start", "position": {"x": 80.0, "y": 90.0}, "facing": "right"},
		"narrative": {"flags": {"loaded": true}, "stats": {}, "inventory": {}, "quests": {}, "collectibles": {}},
		"world": {"maps": {"foundation_room": {"mirror": {"inspected": true}}}},
		"dialogue": {"active": active_dialogue, "bundle_key": "foundation.inspect" if active_dialogue else "", "trigger_key": "mirror.inspect" if active_dialogue else "", "node_id": "mirror_after_choice" if active_dialogue else "", "boundary": "line" if active_dialogue else ""},
	})

func _restore_snapshot(slot_id: String, map_id: StringName, spawn_id: StringName, checkpoint: Dictionary) -> Dictionary:
	var dialogue_checkpoint := checkpoint.duplicate(true)
	if dialogue_checkpoint.get("active", false) != true:
		dialogue_checkpoint = {"active": false, "bundle_key": "", "trigger_key": "", "node_id": "", "boundary": ""}
	return SaveDataResource.with_checksum({
		"schema_version": 1,
		"meta": {"slot_id": slot_id, "saved_at": "2026-08-16T12:34:56Z", "play_time_seconds": 77.0, "location_name": "기초 홀" if map_id == &"foundation_hall" else "기초 방"},
		"player": {"map_id": String(map_id), "spawn_id": String(spawn_id), "position": {"x": 80.0, "y": 90.0}, "facing": "right"},
		"narrative": {"flags": {"loaded": true}, "stats": {}, "inventory": {}, "quests": {}, "collectibles": {}},
		"world": {"maps": {"foundation_room": {"mirror": {"inspected": true}}}},
		"dialogue": dialogue_checkpoint,
	})

func _real_current_state(harness: Dictionary) -> Dictionary:
	var director: SceneDirectorService = harness.director
	return {
		"session": GameSession.snapshot_session(),
		"mode_context": GameSession.snapshot_mode_context(),
		"map": harness.host.get_child(0) if harness.host.get_child_count() > 0 else null,
		"player_valid": is_instance_valid(director.player),
		"position": director.player.global_position if is_instance_valid(director.player) else Vector2.ZERO,
		"facing": director.player.facing if is_instance_valid(director.player) else Vector2.ZERO,
	}

func _complete_current_state(director: FakeDirector) -> Dictionary:
	return {
		"session": GameSession.snapshot_session(),
		"mode": GameSession.current_mode,
		"map_id": director.map_id,
		"spawn_id": director.spawn_id,
		"position": director.player.global_position,
		"facing": director.player.facing,
	}
