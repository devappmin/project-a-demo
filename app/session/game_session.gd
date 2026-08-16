extends Node
class_name GameSessionService

const GameMode = preload("res://app/session/game_mode.gd")
const NarrativeStateResource = preload("res://game/narrative/state/narrative_state.gd")
const WorldStateResource = preload("res://game/world/world_state.gd")

signal mode_changed(previous: int, current: int)
signal mode_change_rejected(previous: int, requested: int)

var _permissions := {
	GameMode.Value.BOOT: [],
	GameMode.Value.EXPLORATION: [
		GameMode.ACTION_MOVE,
		GameMode.ACTION_SPRINT,
		GameMode.ACTION_INTERACT,
		GameMode.ACTION_MENU,
	],
	GameMode.Value.DIALOGUE: [
		GameMode.ACTION_DIALOGUE_ADVANCE,
		GameMode.ACTION_DIALOGUE_CHOOSE,
	],
	GameMode.Value.CUTSCENE: [],
	GameMode.Value.MENU: [GameMode.ACTION_MENU],
	GameMode.Value.TRANSITION: [],
	GameMode.Value.PAUSED: [GameMode.ACTION_MENU],
}

var current_mode: int = GameMode.Value.BOOT
var narrative_state: NarrativeStateResource = NarrativeStateResource.new()
var world_state: WorldStateResource = WorldStateResource.new()
var play_time_seconds := 0.0
var _initialized := false

func _ready() -> void:
	initialize()

func initialize() -> void:
	if _initialized:
		return
	_initialized = true
	change_mode(GameMode.Value.EXPLORATION)

func change_mode(next_mode: int) -> bool:
	var previous := current_mode
	if not _permissions.has(next_mode) or (_initialized and next_mode == GameMode.Value.BOOT) or (current_mode == GameMode.Value.TRANSITION and next_mode == GameMode.Value.TRANSITION):
		mode_change_rejected.emit(previous, next_mode)
		return false
	current_mode = next_mode
	mode_changed.emit(previous, current_mode)
	return true

func can(action: StringName) -> bool:
	return action in _permissions[current_mode]

func reset_new_game() -> void:
	narrative_state = NarrativeStateResource.new()
	world_state = WorldStateResource.new()
	play_time_seconds = 0.0

func snapshot_session() -> Dictionary:
	return {
		"narrative_state": narrative_state.snapshot(),
		"world_state": world_state.snapshot(),
		"play_time_seconds": play_time_seconds,
	}

func restore_session(data: Dictionary) -> Error:
	if not data.has("narrative_state") or not data.has("world_state") or not data.has("play_time_seconds"):
		return ERR_INVALID_DATA
	if typeof(data["narrative_state"]) != TYPE_DICTIONARY or typeof(data["world_state"]) != TYPE_DICTIONARY or typeof(data["play_time_seconds"]) != TYPE_FLOAT:
		return ERR_INVALID_DATA
	if not is_finite(data["play_time_seconds"]) or data["play_time_seconds"] < 0.0:
		return ERR_INVALID_DATA
	var restored_narrative_state := NarrativeStateResource.new()
	var restored_world_state := WorldStateResource.new()
	if restored_narrative_state.restore(data["narrative_state"]) != OK or restored_world_state.restore(data["world_state"]) != OK:
		return ERR_INVALID_DATA
	narrative_state = restored_narrative_state
	world_state = restored_world_state
	play_time_seconds = data["play_time_seconds"]
	return OK
