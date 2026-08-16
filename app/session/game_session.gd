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
var _menu_origin_mode := -1

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
	if next_mode == GameMode.Value.MENU:
		if previous != GameMode.Value.TRANSITION:
			_menu_origin_mode = -1
	elif next_mode != GameMode.Value.TRANSITION:
		_menu_origin_mode = -1
	mode_changed.emit(previous, current_mode)
	return true

func enter_menu() -> bool:
	if current_mode != GameMode.Value.EXPLORATION:
		return false
	var origin := current_mode
	if not change_mode(GameMode.Value.MENU):
		return false
	_menu_origin_mode = origin
	return true

func is_menu_from_exploration() -> bool:
	return current_mode == GameMode.Value.MENU and _menu_origin_mode == GameMode.Value.EXPLORATION

func can(action: StringName) -> bool:
	return action in _permissions[current_mode]

func reset_new_game() -> void:
	narrative_state = NarrativeStateResource.new()
	world_state = WorldStateResource.new()
	play_time_seconds = 0.0
	_menu_origin_mode = -1

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
	if not _is_persistable_dictionary(data):
		return ERR_INVALID_DATA
	var restored_narrative_state := NarrativeStateResource.new()
	var restored_world_state := WorldStateResource.new()
	if restored_narrative_state.restore(data["narrative_state"]) != OK or restored_world_state.restore(data["world_state"]) != OK:
		return ERR_INVALID_DATA
	narrative_state = restored_narrative_state
	world_state = restored_world_state
	play_time_seconds = data["play_time_seconds"]
	return OK

func _is_persistable_dictionary(value: Dictionary) -> bool:
	for key in value:
		if not _is_persistable_value(key) or not _is_persistable_value(value[key]):
			return false
	return true

func _is_persistable_value(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING, TYPE_STRING_NAME:
			return true
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_ARRAY:
			for item in value:
				if not _is_persistable_value(item):
					return false
			return true
		TYPE_DICTIONARY:
			return _is_persistable_dictionary(value)
		_:
			return false
