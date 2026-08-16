extends Control
class_name ToastLayer

@export var display_seconds := 2.4

@onready var message_label: Label = $Toast/Message
@onready var timer: Timer = $Timer

var _current_message := ""

func _ready() -> void:
	timer.timeout.connect(hide_toast)
	hide_toast()

func show_toast(text: String) -> void:
	_current_message = text
	message_label.text = text
	visible = not text.is_empty()
	if visible and display_seconds > 0.0:
		timer.start(display_seconds)

func hide_toast() -> void:
	_current_message = ""
	message_label.text = ""
	visible = false

func current_message() -> String:
	return _current_message
