extends Control
class_name TitleMenu

signal new_game_requested
signal load_requested
signal quit_requested

@onready var new_game_button: Button = $Panel/Margin/Buttons/NewGame
@onready var load_button: Button = $Panel/Margin/Buttons/Load
@onready var quit_button: Button = $Panel/Margin/Buttons/Quit

func _ready() -> void:
	new_game_button.pressed.connect(func() -> void: new_game_requested.emit())
	load_button.pressed.connect(func() -> void: load_requested.emit())
	quit_button.pressed.connect(func() -> void: quit_requested.emit())

func open() -> void:
	visible = true
	set_busy(false)
	new_game_button.call_deferred("grab_focus")

func close() -> void:
	visible = false

func set_busy(busy: bool) -> void:
	new_game_button.disabled = busy
	load_button.disabled = busy
	quit_button.disabled = busy

func focus_load() -> void:
	load_button.call_deferred("grab_focus")
