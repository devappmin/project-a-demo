extends Node
class_name SceneDirectorService

const GameMode = preload("res://app/session/game_mode.gd")
const PlayerScene = preload("res://game/actors/player/player.tscn")
const DefaultRegistry = preload("res://data/maps/map_registry.tres")

signal transition_started(from_map: StringName, to_map: StringName)
signal map_committed(map_id: StringName, spawn_id: StringName, player: PlayerController)
signal transition_failed(context: Dictionary)
signal stable_checkpoint(kind: StringName)

@export var map_registry: MapRegistry = DefaultRegistry

var player: PlayerController
var _world_host: Node2D
var _fade: ScreenFade
var _current_map: MapScene
var _current_spawn_id: StringName = &""
var _transition_in_progress := false
var _pending_restore := {}
var _map_rebinder: Callable
var _player_placement_hook: Callable
var _transition_hook: Callable
var _restore_finalize_hook: Callable
var _last_restore_failure_context := {}

func configure(world_host: Node2D, fade: ScreenFade) -> Error:
	if world_host == null or fade == null:
		return ERR_INVALID_PARAMETER
	_world_host = world_host
	_fade = fade
	if not is_instance_valid(_current_map):
		_current_map = null
	if not is_instance_valid(player):
		player = null
	return OK

func start_new_game(map_id: StringName = &"foundation_room", spawn_id: StringName = &"start") -> Error:
	if _transition_in_progress:
		return ERR_BUSY
	var plan := prepare_restore(map_id, spawn_id)
	if not plan.get("ok", false):
		_emit_failure(map_id, spawn_id, plan.get("error", ERR_INVALID_DATA))
		return plan.get("error", ERR_INVALID_DATA)
	GameSession.reset_new_game()
	var transition_error := await commit_restore(plan)
	if transition_error != OK:
		_emit_failure(map_id, spawn_id, transition_error)
		return transition_error
	stable_checkpoint.emit(&"map_transition")
	return OK

func set_map_rebinder(rebinder: Callable) -> void:
	_map_rebinder = rebinder

func get_current_map() -> MapScene:
	return _current_map if is_instance_valid(_current_map) else null

func get_player() -> PlayerController:
	return player if is_instance_valid(player) else null

func get_interaction_detector() -> InteractionDetector:
	var current_player := get_player()
	return current_player.get_node_or_null("InteractionDetector") as InteractionDetector if current_player != null else null

func get_interaction_router() -> InteractionRouter:
	var current_player := get_player()
	return current_player.get_node_or_null("InteractionRouter") as InteractionRouter if current_player != null else null

func set_player_placement_hook(hook: Callable) -> void:
	_player_placement_hook = hook

func set_transition_hook(hook: Callable) -> void:
	_transition_hook = hook

func set_restore_finalize_hook(hook: Callable) -> void:
	_restore_finalize_hook = hook

func restore_failure_context() -> Dictionary:
	return _last_restore_failure_context.duplicate(true)

func change_map(map_id: StringName, spawn_id: StringName) -> Error:
	if _transition_in_progress:
		return ERR_BUSY
	var plan := prepare_restore(map_id, spawn_id)
	if not plan.get("ok", false):
		_emit_failure(map_id, spawn_id, plan.get("error", ERR_INVALID_DATA))
		return plan.get("error", ERR_INVALID_DATA)
	if _current_map != null:
		var capture_error := _current_map.capture_world_objects(GameSession.world_state)
		if capture_error != OK:
			_free_plan_candidate(plan)
			_emit_failure(map_id, spawn_id, capture_error)
			return capture_error
	var transition_error := await commit_restore(plan)
	if transition_error != OK:
		_emit_failure(map_id, spawn_id, transition_error)
		return transition_error
	stable_checkpoint.emit(&"map_transition")
	return OK

func prepare_restore(map_id: StringName, spawn_id: StringName) -> Dictionary:
	if _world_host == null or map_registry == null:
		return {"ok": false, "error": ERR_UNCONFIGURED}
	var definition := map_registry.definition(map_id)
	if definition == null:
		return {"ok": false, "error": ERR_DOES_NOT_EXIST}
	var packed_scene := load(definition.scene_path) as PackedScene
	if packed_scene == null:
		return {"ok": false, "error": ERR_FILE_NOT_FOUND}
	var candidate := packed_scene.instantiate()
	if not candidate is MapScene:
		candidate.free()
		return {"ok": false, "error": ERR_INVALID_DATA}
	var map := candidate as MapScene
	if map.map_id != definition.map_id or not map.validate_contract().is_empty() or map.get_spawn(spawn_id) == null:
		map.free()
		return {"ok": false, "error": ERR_INVALID_DATA}
	return {"ok": true, "map": map, "map_id": map_id, "spawn_id": spawn_id}

func commit_restore(plan: Dictionary) -> Error:
	if _transition_in_progress:
		return ERR_BUSY
	if not plan.get("ok", false):
		return plan.get("error", ERR_INVALID_DATA)
	var candidate := plan.get("map") as MapScene
	if candidate == null or _world_host == null:
		return ERR_INVALID_PARAMETER
	if not candidate.validate_contract().is_empty():
		if candidate != _current_map and candidate.get_parent() == null:
			candidate.free()
		return ERR_INVALID_DATA
	_last_restore_failure_context.clear()
	var previous_mode_context := GameSession.snapshot_mode_context()
	var old_map := _current_map
	var old_spawn_id := _current_spawn_id
	var from_map := old_map.map_id if old_map != null else StringName()
	var target_map: StringName = plan.get("map_id", candidate.map_id)
	var spawn_id: StringName = plan.get("spawn_id", StringName())
	var defer_finalize: bool = plan.get("defer_finalize", false) == true
	var restore_world_state := GameSession.world_state
	if plan.has("world"):
		if typeof(plan["world"]) != TYPE_DICTIONARY:
			candidate.free()
			return ERR_INVALID_DATA
		restore_world_state = WorldState.new()
		if restore_world_state.restore(plan["world"]) != OK:
			candidate.free()
			return ERR_INVALID_DATA
	_transition_in_progress = true
	transition_started.emit(from_map, target_map)
	GameSession.change_mode(GameMode.Value.TRANSITION)
	if _transition_hook.is_valid():
		_transition_hook.call()
	await _fade.fade_out()

	var old_body_parent: Node = player.get_parent() if player != null else null
	var old_visual_parent: Node = player.presentation.get_parent() if player != null and player.presentation != null else null
	var old_position := player.global_position if player != null else Vector2.ZERO
	var old_facing := player.facing if player != null else Vector2.DOWN
	var error: Error = OK
	if old_map != null:
		_world_host.remove_child(old_map)
	_world_host.add_child(candidate)
	var world_error := candidate.apply_world_objects(restore_world_state)
	if world_error != OK:
		error = world_error
	else:
		var placement_error: Error = int(_player_placement_hook.call(candidate, spawn_id)) if _player_placement_hook.is_valid() else _place_player(candidate, spawn_id)
		if placement_error != OK:
			error = placement_error
		elif _map_rebinder.is_valid():
			error = int(_map_rebinder.call(player))
	if error != OK:
		_world_host.remove_child(candidate)
		candidate.queue_free()
		if old_map != null:
			_world_host.add_child(old_map)
		var rollback_failures := _restore_player(old_body_parent, old_visual_parent, old_position, old_facing)
		if old_map != null:
			_append_restore_failure(rollback_failures, &"camera", _configure_player_camera(old_map))
		if old_map != null and _map_rebinder.is_valid() and player != null:
			var rebind_error: Error = int(_map_rebinder.call(player))
			_append_restore_failure(rollback_failures, &"map_rebind", rebind_error)
		await _fade.fade_in()
		var mode_error := GameSession.restore_mode_context(previous_mode_context)
		_append_restore_failure(rollback_failures, &"mode_context", mode_error)
		_transition_in_progress = false
		if not rollback_failures.is_empty():
			_last_restore_failure_context = _restore_failure_context(rollback_failures, error)
			return _last_restore_failure_context["error"]
		return error

	_current_map = candidate
	_current_spawn_id = spawn_id
	map_committed.emit(target_map, spawn_id, player)
	if defer_finalize:
		_pending_restore = {
			"old_map": old_map,
			"old_spawn_id": old_spawn_id,
			"old_body_parent": old_body_parent,
			"old_visual_parent": old_visual_parent,
			"old_position": old_position,
			"old_facing": old_facing,
			"previous_mode_context": previous_mode_context,
			"candidate": candidate,
		}
	else:
		if old_map != null:
			old_map.queue_free()
		await _fade.fade_in()
		GameSession.change_mode(GameMode.Value.EXPLORATION)
		_transition_in_progress = false
	return OK

func has_pending_restore() -> bool:
	return not _pending_restore.is_empty()

func finalize_restore() -> Error:
	if _pending_restore.is_empty():
		return ERR_UNCONFIGURED
	await _fade.fade_in()
	if _restore_finalize_hook.is_valid():
		var hook_error: Error = int(_restore_finalize_hook.call())
		if hook_error != OK:
			_last_restore_failure_context = {"stage": &"finalize", "error": hook_error}
			return hook_error
	var old_map := _pending_restore.get("old_map") as MapScene
	if old_map != null:
		old_map.queue_free()
	_pending_restore.clear()
	_transition_in_progress = false
	return OK

func rollback_restore() -> Error:
	if _pending_restore.is_empty():
		return ERR_UNCONFIGURED
	_last_restore_failure_context.clear()
	var candidate := _pending_restore.get("candidate") as MapScene
	var old_map := _pending_restore.get("old_map") as MapScene
	var old_body_parent := _pending_restore.get("old_body_parent") as Node
	if candidate != null and candidate.get_parent() == _world_host:
		_world_host.remove_child(candidate)
		candidate.queue_free()
	if old_map != null and old_map.get_parent() == null:
		_world_host.add_child(old_map)
	var rollback_failures := _restore_player(
		old_body_parent,
		_pending_restore.get("old_visual_parent") as Node,
		_pending_restore.get("old_position", Vector2.ZERO),
		_pending_restore.get("old_facing", Vector2.DOWN)
	)
	_current_map = old_map
	_current_spawn_id = _pending_restore.get("old_spawn_id", &"")
	if old_map != null:
		_append_restore_failure(rollback_failures, &"camera", _configure_player_camera(old_map))
	if old_map != null and _map_rebinder.is_valid() and player != null:
		var rebind_error: Error = int(_map_rebinder.call(player))
		_append_restore_failure(rollback_failures, &"map_rebind", rebind_error)
	await _fade.fade_in()
	var mode_context_value: Variant = _pending_restore.get("previous_mode_context", {})
	var mode_error := ERR_INVALID_DATA
	if typeof(mode_context_value) == TYPE_DICTIONARY:
		mode_error = GameSession.restore_mode_context(mode_context_value)
	_append_restore_failure(rollback_failures, &"mode_context", mode_error)
	if old_body_parent == null:
		player = null
	_pending_restore.clear()
	_transition_in_progress = false
	if not rollback_failures.is_empty():
		_last_restore_failure_context = _restore_failure_context(rollback_failures)
		return _last_restore_failure_context["error"]
	return OK

func capture_save_context() -> Dictionary:
	if _current_map == null or player == null or map_registry == null:
		return {"ok": false, "error": ERR_UNCONFIGURED}
	var captured_world := WorldState.new()
	if captured_world.restore(GameSession.world_state.snapshot()) != OK:
		return {"ok": false, "error": ERR_INVALID_DATA}
	var capture_error := _current_map.capture_world_objects(captured_world)
	if capture_error != OK:
		return {"ok": false, "error": capture_error}
	var definition := map_registry.definition(_current_map.map_id)
	if definition == null or definition.display_name.strip_edges().is_empty():
		return {"ok": false, "error": ERR_INVALID_DATA}
	return {
		"ok": true,
		"map_id": _current_map.map_id,
		"spawn_id": _current_spawn_id,
		"location_name": definition.display_name,
		"position": player.global_position,
		"facing": player.facing,
		"world": captured_world.snapshot(),
	}

func _place_player(map: MapScene, spawn_id: StringName) -> Error:
	var actor_root := map.get_actor_root()
	var visual_root := map.get_visual_root()
	var spawn := map.get_spawn(spawn_id)
	if actor_root == null or visual_root == null or spawn == null:
		return ERR_INVALID_DATA
	if player == null:
		player = PlayerScene.instantiate() as PlayerController
	if player == null:
		return ERR_CANT_CREATE
	if player.get_parent() == null:
		actor_root.add_child(player)
	var detach_error := player.detach_presentation()
	if detach_error != OK:
		return detach_error
	if player.get_parent() != actor_root:
		actor_root.add_child(player) if player.get_parent() == null else player.reparent(actor_root, true)
	player.global_position = spawn.global_position
	var presentation_error := player.attach_presentation(visual_root)
	if presentation_error != OK:
		return presentation_error
	return _configure_player_camera(map)

func _configure_player_camera(map: MapScene) -> Error:
	if player == null or map == null or map.room_bounds.size.x <= 0.0 or map.room_bounds.size.y <= 0.0:
		return ERR_INVALID_DATA
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	if camera == null:
		return ERR_DOES_NOT_EXIST
	camera.limit_left = floori(map.room_bounds.position.x)
	camera.limit_top = floori(map.room_bounds.position.y)
	camera.limit_right = ceili(map.room_bounds.end.x)
	camera.limit_bottom = ceili(map.room_bounds.end.y)
	return OK

func _restore_player(body_parent: Node, visual_parent: Node, previous_position: Vector2, previous_facing: Vector2) -> Array[Dictionary]:
	var failures: Array[Dictionary] = []
	if player == null:
		if body_parent != null or visual_parent != null:
			failures.append({"stage": &"player", "error": ERR_DOES_NOT_EXIST})
		return failures
	_append_restore_failure(failures, &"player_detach", player.detach_presentation())
	if body_parent != null:
		body_parent.add_child(player) if player.get_parent() == null else player.reparent(body_parent, true)
	player.global_position = previous_position
	player.facing = previous_facing
	if visual_parent is Node2D:
		_append_restore_failure(failures, &"player_attach", player.attach_presentation(visual_parent as Node2D))
	elif body_parent != null:
		failures.append({"stage": &"player_attach", "error": ERR_DOES_NOT_EXIST})
	return failures

func _append_restore_failure(failures: Array[Dictionary], stage: StringName, error: Error) -> void:
	if error != OK:
		failures.append({"stage": stage, "error": error})

func _restore_failure_context(failures: Array[Dictionary], primary_error: Error = OK) -> Dictionary:
	var first_failure: Dictionary = failures[0]
	var context := {
		"stage": first_failure.get("stage", &"rollback"),
		"error": first_failure.get("error", ERR_CANT_RESOLVE),
		"failures": failures.duplicate(true),
	}
	if primary_error != OK:
		context["primary_error"] = primary_error
	return context

func _free_plan_candidate(plan: Dictionary) -> void:
	var candidate := plan.get("map") as MapScene
	if candidate != null:
		candidate.free()

func _emit_failure(map_id: StringName, spawn_id: StringName, error: Error) -> void:
	transition_failed.emit({"map_id": map_id, "spawn_id": spawn_id, "error": error})
