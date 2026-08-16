extends Control
class_name PauseMenu

signal continue_requested
signal save_requested
signal load_requested
signal title_requested

@onready var continue_button: Button = $Panel/Margin/Buttons/Continue
@onready var save_button: Button = $Panel/Margin/Buttons/Save
@onready var load_button: Button = $Panel/Margin/Buttons/Load
@onready var title_button: Button = $Panel/Margin/Buttons/Title

func _ready() -> void:
	continue_button.pressed.connect(func() -> void: continue_requested.emit())
	save_button.pressed.connect(func() -> void: save_requested.emit())
	load_button.pressed.connect(func() -> void: load_requested.emit())
	title_button.pressed.connect(func() -> void: title_requested.emit())

func open() -> void:
	visible = true
	set_busy(false)
	continue_button.call_deferred("grab_focus")

func close() -> void:
	visible = false

func set_busy(busy: bool) -> void:
	continue_button.disabled = busy
	save_button.disabled = busy
	load_button.disabled = busy
	title_button.disabled = busy

func focus_save() -> void:
	save_button.call_deferred("grab_focus")

func focus_load() -> void:
	load_button.call_deferred("grab_focus")
