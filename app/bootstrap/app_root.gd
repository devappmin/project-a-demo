extends Node
class_name AppRoot

const GameMode = preload("res://app/session/game_mode.gd")

@onready var world_host: Node = $WorldHost
@onready var service_layer: Node = $ServiceLayer
@onready var ui_layer: CanvasLayer = $UILayer
@onready var prompt: InteractionPrompt = $UILayer/InteractionPrompt
@onready var dialogue_adapter: DialogueActionAdapter = $ServiceLayer/DialogueActionAdapter
@onready var door_adapter: DoorActionAdapter = $ServiceLayer/DoorActionAdapter
@onready var screen_fade: ScreenFade = $UILayer/ScreenFade

func _ready() -> void:
	if SceneDirector.configure(world_host as Node2D, screen_fade) != OK:
		return
	SceneDirector.set_map_rebinder(_rebind_player)
	GameSession.change_mode(GameMode.Value.MENU)

func _rebind_player(player: PlayerController) -> Error:
	if player == null:
		return ERR_INVALID_PARAMETER
	var detector := player.get_node_or_null("InteractionDetector") as InteractionDetector
	var router := player.get_node_or_null("InteractionRouter") as InteractionRouter
	if detector == null or router == null:
		return ERR_DOES_NOT_EXIST
	router.detector = detector
	_disconnect_adapter(router, dialogue_adapter.handle_action)
	_disconnect_adapter(router, door_adapter.handle_action)
	router.action_requested.connect(dialogue_adapter.handle_action)
	door_adapter.scene_director = SceneDirector
	router.action_requested.connect(door_adapter.handle_action)
	prompt.bind_detector(detector)
	return OK

func _disconnect_adapter(router: InteractionRouter, handler: Callable) -> void:
	if router.action_requested.is_connected(handler):
		router.action_requested.disconnect(handler)

func get_world_host() -> Node:
	return world_host

func get_service_layer() -> Node:
	return service_layer

func get_ui_layer() -> CanvasLayer:
	return ui_layer
