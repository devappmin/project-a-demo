extends Node
class_name AppRoot

@onready var world_host: Node = $WorldHost
@onready var service_layer: Node = $ServiceLayer
@onready var ui_layer: CanvasLayer = $UILayer

func get_world_host() -> Node:
	return world_host

func get_service_layer() -> Node:
	return service_layer

func get_ui_layer() -> CanvasLayer:
	return ui_layer
