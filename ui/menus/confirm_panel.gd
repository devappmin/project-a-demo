extends Control
class_name ConfirmPanel

signal confirmed
signal cancelled

@onready var message_label: Label = $Panel/Margin/Layout/Message
@onready var confirm_button: Button = $Panel/Margin/Layout/Actions/Confirm
@onready var cancel_button: Button = $Panel/Margin/Layout/Actions/Cancel

func _ready() -> void:
	confirm_button.pressed.connect(func() -> void: confirmed.emit())
	cancel_button.pressed.connect(func() -> void: cancelled.emit())

func open(text: String) -> void:
	message_label.text = text
	visible = true
	confirm_button.call_deferred("grab_focus")

func close() -> void:
	visible = false

func message() -> String:
	return message_label.text

func set_busy(busy: bool) -> void:
	confirm_button.disabled = busy
	cancel_button.disabled = busy

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel") and not cancel_button.disabled:
		cancelled.emit()
		get_viewport().set_input_as_handled()
