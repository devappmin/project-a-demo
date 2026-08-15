extends Node
class_name GameSessionService

const GameMode = preload("res://app/session/game_mode.gd")

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
