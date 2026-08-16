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
	if not SceneDirector.map_committed.is_connected(_on_map_committed):
		SceneDirector.map_committed.connect(_on_map_committed)
	GameSession.change_mode(GameMode.Value.MENU)

func _exit_tree() -> void:
	if SceneDirector.map_committed.is_connected(_on_map_committed):
		SceneDirector.map_committed.disconnect(_on_map_committed)

func _on_map_committed(_map_id: StringName, _spawn_id: StringName, player: PlayerController) -> void:
	var detector := player.get_node_or_null("InteractionDetector") as InteractionDetector
	var router := player.get_node_or_null("InteractionRouter") as InteractionRouter
	prompt.bind_detector(detector)
	if router == null:
		return
	router.detector = detector
	_disconnect_adapter(router, dialogue_adapter.handle_action)
	_disconnect_adapter(router, door_adapter.handle_action)
	router.action_requested.connect(dialogue_adapter.handle_action)
	door_adapter.scene_director = SceneDirector
	router.action_requested.connect(door_adapter.handle_action)

func _disconnect_adapter(router: InteractionRouter, handler: Callable) -> void:
	if router.action_requested.is_connected(handler):
		router.action_requested.disconnect(handler)

func get_world_host() -> Node:
	return world_host

func get_service_layer() -> Node:
	return service_layer

func get_ui_layer() -> CanvasLayer:
	return ui_layer
