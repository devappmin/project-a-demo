extends Node
class_name SaveServiceService

const GameModeResource = preload("res://app/session/game_mode.gd")
const GameSessionResource = preload("res://app/session/game_session.gd")
const SaveDataResource = preload("res://app/save/save_data.gd")
const SaveRepositoryResource = preload("res://app/save/save_repository.gd")

signal save_started(slot_id: StringName)
signal save_completed(slot_id: StringName)
signal save_failed(slot_id: StringName, context: Dictionary)
signal load_completed(slot_id: StringName)
signal load_failed(slot_id: StringName, context: Dictionary)
signal backup_recovered(slot_id: StringName)
signal slots_changed

var repository: SaveRepository = SaveRepositoryResource.new()

var _scene_director: Node
var _dialogue_service: DialogueService
var _busy := false
var _restoring := false
var _autosave_flush_queued := false
var _pending_autosave_snapshot := {}

func configure(scene_director: Node, dialogue_service: DialogueService) -> Error:
	if scene_director == null or dialogue_service == null:
		return ERR_INVALID_PARAMETER
	if not scene_director.has_signal("stable_checkpoint"):
		return ERR_INVALID_PARAMETER
	if _scene_director != null and _scene_director.has_signal("stable_checkpoint"):
		var old_director_handler := Callable(self, "_on_scene_checkpoint")
		if _scene_director.is_connected("stable_checkpoint", old_director_handler):
			_scene_director.disconnect("stable_checkpoint", old_director_handler)
	if _dialogue_service != null:
		var old_dialogue_handler := Callable(self, "_on_dialogue_checkpoint")
		if _dialogue_service.stable_checkpoint_reached.is_connected(old_dialogue_handler):
			_dialogue_service.stable_checkpoint_reached.disconnect(old_dialogue_handler)
	_scene_director = scene_director
	_dialogue_service = dialogue_service
	var director_handler := Callable(self, "_on_scene_checkpoint")
	if not _scene_director.is_connected("stable_checkpoint", director_handler):
		_scene_director.connect("stable_checkpoint", director_handler)
	var dialogue_handler := Callable(self, "_on_dialogue_checkpoint")
	if not _dialogue_service.stable_checkpoint_reached.is_connected(dialogue_handler):
		_dialogue_service.stable_checkpoint_reached.connect(dialogue_handler)
	return OK

func save_manual_slot(slot_id: StringName) -> Error:
	if slot_id == &"auto" or slot_id not in SaveDataResource.SLOT_IDS:
		return ERR_INVALID_PARAMETER
	if _busy:
		return ERR_BUSY
	if not _manual_save_allowed():
		return ERR_UNAVAILABLE
	var capture := _capture_snapshot(slot_id, {})
	if not capture.get("ok", false):
		return capture.get("error", ERR_INVALID_DATA)
	return _write_snapshot(slot_id, capture["snapshot"])

func request_autosave(kind: StringName, checkpoint := {}) -> void:
	if _restoring or kind not in [&"map_transition", &"important_choice"] or typeof(checkpoint) != TYPE_DICTIONARY:
		return
	var capture := _capture_snapshot(&"auto", checkpoint)
	if not capture.get("ok", false):
		save_failed.emit(&"auto", {"error": capture.get("error", ERR_INVALID_DATA), "stage": &"capture", "kind": kind})
		return
	_pending_autosave_snapshot = (capture["snapshot"] as Dictionary).duplicate(true)
	if not _autosave_flush_queued:
		_autosave_flush_queued = true
		call_deferred("_flush_autosave")

func load_slot(slot_id: StringName) -> Error:
	if slot_id not in SaveDataResource.SLOT_IDS:
		return ERR_INVALID_PARAMETER
	if _busy:
		return ERR_BUSY
	_busy = true
	var read_result: Dictionary = repository.read_slot(slot_id)
	if not read_result.get("ok", false):
		return _finish_load_failure(slot_id, read_result.get("error", ERR_FILE_CORRUPT), &"repository", read_result.get("diagnostic", {}))
	var snapshot_value: Variant = read_result.get("data")
	if typeof(snapshot_value) != TYPE_DICTIONARY:
		return _finish_load_failure(slot_id, ERR_INVALID_DATA, &"schema")
	var snapshot: Dictionary = snapshot_value.duplicate(true)
	if not SaveDataResource.validate(snapshot).is_empty() or not SaveDataResource.verify_checksum(snapshot):
		return _finish_load_failure(slot_id, ERR_INVALID_DATA, &"schema")
	if StringName(snapshot.get("meta", {}).get("slot_id", "")) != slot_id:
		return _finish_load_failure(slot_id, ERR_INVALID_DATA, &"slot_binding")
	if read_result.get("recovered", false):
		backup_recovered.emit(slot_id)
	var restore_plan_result := _build_restore_plan(snapshot)
	if not restore_plan_result.get("ok", false):
		return _finish_load_failure(slot_id, restore_plan_result.get("error", ERR_INVALID_DATA), restore_plan_result.get("stage", &"preflight"))
	var old_session := GameSession.snapshot_session()
	var old_mode := GameSession.current_mode
	_pending_autosave_snapshot.clear()
	_restoring = true
	var director_plan: Dictionary = restore_plan_result["director_plan"]
	director_plan["defer_finalize"] = true
	director_plan["world"] = snapshot["world"].duplicate(true)
	var commit_error: Error = await _scene_director.call("commit_restore", director_plan)
	if commit_error != OK:
		_restoring = false
		return _finish_load_failure(slot_id, commit_error, &"commit")
	var session_data := {
		"narrative_state": snapshot["narrative"].duplicate(true),
		"world_state": snapshot["world"].duplicate(true),
		"play_time_seconds": float(snapshot["meta"]["play_time_seconds"]),
	}
	var apply_error := GameSession.restore_session(session_data)
	if apply_error == OK:
		apply_error = _apply_player(snapshot["player"])
	if apply_error == OK:
		GameSession.change_mode(GameModeResource.Value.EXPLORATION)
		if _dialogue_service.has_method("refresh_session_state"):
			apply_error = _dialogue_service.refresh_session_state()
	if apply_error == OK and snapshot["dialogue"].get("active", false):
		apply_error = _dialogue_service.resume_checkpoint(snapshot["dialogue"].duplicate(true))
	if apply_error != OK:
		GameSession.restore_session(old_session)
		GameSession.change_mode(old_mode)
		await _scene_director.call("rollback_restore")
		if _dialogue_service.has_method("refresh_session_state"):
			_dialogue_service.refresh_session_state()
		_restoring = false
		return _finish_load_failure(slot_id, apply_error, &"apply")
	var finalize_error: Error = await _scene_director.call("finalize_restore")
	if finalize_error != OK:
		GameSession.restore_session(old_session)
		GameSession.change_mode(old_mode)
		await _scene_director.call("rollback_restore")
		_restoring = false
		return _finish_load_failure(slot_id, finalize_error, &"finalize")
	_restoring = false
	_busy = false
	load_completed.emit(slot_id)
	if read_result.get("recovered", false):
		slots_changed.emit()
	return OK

func slot_metadata() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot_id in SaveDataResource.SLOT_IDS:
		var metadata := repository.read_metadata(slot_id).duplicate(true)
		var exists := not metadata.is_empty()
		metadata["slot_id"] = slot_id
		metadata["exists"] = exists
		result.append(metadata)
	return result

func is_busy() -> bool:
	return _busy

func _manual_save_allowed() -> bool:
	return GameSession.current_mode == GameModeResource.Value.EXPLORATION or GameSession.is_menu_from_exploration()

func _capture_snapshot(slot_id: StringName, checkpoint_override: Dictionary) -> Dictionary:
	if _scene_director == null or _dialogue_service == null or not _scene_director.has_method("capture_save_context"):
		return {"ok": false, "error": ERR_UNCONFIGURED}
	var context_value: Variant = _scene_director.call("capture_save_context")
	if typeof(context_value) != TYPE_DICTIONARY:
		return {"ok": false, "error": ERR_INVALID_DATA}
	var context: Dictionary = context_value
	if not context.get("ok", false):
		return {"ok": false, "error": context.get("error", ERR_INVALID_DATA)}
	var session := GameSession.snapshot_session()
	var dialogue := checkpoint_override.duplicate(true) if not checkpoint_override.is_empty() else _dialogue_service.get_checkpoint()
	dialogue = _normalized_dialogue_checkpoint(dialogue)
	var position_value: Variant = context.get("position")
	var facing_value: Variant = context.get("facing")
	if typeof(position_value) != TYPE_VECTOR2 or typeof(facing_value) != TYPE_VECTOR2:
		return {"ok": false, "error": ERR_INVALID_DATA}
	var position: Vector2 = position_value
	if not is_finite(position.x) or not is_finite(position.y):
		return {"ok": false, "error": ERR_INVALID_DATA}
	var snapshot := {
		"schema_version": SaveDataResource.SCHEMA_VERSION,
		"meta": {
			"slot_id": String(slot_id),
			"saved_at": Time.get_datetime_string_from_system(true, false) + "Z",
			"play_time_seconds": float(session["play_time_seconds"]),
			"location_name": String(context.get("location_name", "")),
		},
		"player": {
			"map_id": String(context.get("map_id", "")),
			"spawn_id": String(context.get("spawn_id", "")),
			"position": {"x": position.x, "y": position.y},
			"facing": _facing_name(facing_value),
		},
		"narrative": session["narrative_state"].duplicate(true),
		"world": context.get("world", session["world_state"]).duplicate(true),
		"dialogue": dialogue,
	}
	if SaveDataResource.with_checksum(snapshot).is_empty():
		return {"ok": false, "error": ERR_INVALID_DATA}
	return {"ok": true, "snapshot": snapshot.duplicate(true)}

func _normalized_dialogue_checkpoint(checkpoint: Dictionary) -> Dictionary:
	if checkpoint.get("active", false) == true:
		return {
			"active": true,
			"bundle_key": String(checkpoint.get("bundle_key", "")),
			"trigger_key": String(checkpoint.get("trigger_key", "")),
			"node_id": String(checkpoint.get("node_id", "")),
			"boundary": String(checkpoint.get("boundary", "")),
		}
	return {"active": false, "bundle_key": "", "trigger_key": "", "node_id": "", "boundary": ""}

func _write_snapshot(slot_id: StringName, snapshot: Dictionary) -> Error:
	if _busy:
		return ERR_BUSY
	_busy = true
	save_started.emit(slot_id)
	var error := repository.write_slot(slot_id, snapshot.duplicate(true))
	_busy = false
	if error == OK:
		save_completed.emit(slot_id)
		slots_changed.emit()
	else:
		save_failed.emit(slot_id, {"error": error, "stage": &"repository"})
	return error

func _flush_autosave() -> void:
	_autosave_flush_queued = false
	if _pending_autosave_snapshot.is_empty() or _restoring:
		return
	if _busy:
		_autosave_flush_queued = true
		call_deferred("_flush_autosave")
		return
	var snapshot := _pending_autosave_snapshot.duplicate(true)
	_pending_autosave_snapshot.clear()
	_write_snapshot(&"auto", snapshot)
	if not _pending_autosave_snapshot.is_empty() and not _autosave_flush_queued:
		_autosave_flush_queued = true
		call_deferred("_flush_autosave")

func _build_restore_plan(snapshot: Dictionary) -> Dictionary:
	var session_candidate := GameSessionResource.new()
	var session_error := session_candidate.restore_session({
		"narrative_state": snapshot["narrative"].duplicate(true),
		"world_state": snapshot["world"].duplicate(true),
		"play_time_seconds": float(snapshot["meta"]["play_time_seconds"]),
	})
	session_candidate.free()
	if session_error != OK:
		return {"ok": false, "error": session_error, "stage": &"session_preflight"}
	if snapshot["dialogue"].get("active", false):
		var checkpoint_error := _dialogue_service.validate_checkpoint(snapshot["dialogue"])
		if checkpoint_error != OK:
			return {"ok": false, "error": checkpoint_error, "stage": &"dialogue_preflight"}
	var director_plan_value: Variant = _scene_director.call("prepare_restore", StringName(snapshot["player"]["map_id"]), StringName(snapshot["player"]["spawn_id"]))
	if typeof(director_plan_value) != TYPE_DICTIONARY:
		return {"ok": false, "error": ERR_INVALID_DATA, "stage": &"map_preflight"}
	var director_plan: Dictionary = director_plan_value
	if not director_plan.get("ok", false):
		return {"ok": false, "error": director_plan.get("error", ERR_INVALID_DATA), "stage": &"map_preflight"}
	return {"ok": true, "director_plan": director_plan}

func _apply_player(player_data: Dictionary) -> Error:
	var player_value: Variant = _scene_director.get("player")
	if not player_value is Node2D:
		return ERR_UNCONFIGURED
	var player := player_value as Node2D
	var position: Dictionary = player_data["position"]
	player.global_position = Vector2(float(position["x"]), float(position["y"]))
	player.set("facing", _facing_vector(String(player_data["facing"])))
	return OK

func _finish_load_failure(slot_id: StringName, error: Error, stage: StringName, diagnostic := {}) -> Error:
	_busy = false
	load_failed.emit(slot_id, {"error": error, "stage": stage, "diagnostic": diagnostic.duplicate(true)})
	return error

func _on_scene_checkpoint(kind: StringName) -> void:
	request_autosave(kind, {})

func _on_dialogue_checkpoint(kind: StringName, checkpoint: Dictionary) -> void:
	request_autosave(kind, checkpoint)

func _facing_name(facing: Vector2) -> String:
	if facing == Vector2.LEFT:
		return "left"
	if facing == Vector2.RIGHT:
		return "right"
	if facing == Vector2.UP:
		return "up"
	return "down"

func _facing_vector(facing: String) -> Vector2:
	match facing:
		"left": return Vector2.LEFT
		"right": return Vector2.RIGHT
		"up": return Vector2.UP
		_: return Vector2.DOWN
