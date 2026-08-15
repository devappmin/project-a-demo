extends Control
class_name DialogueView

const GameModeResource = preload("res://app/session/game_mode.gd")

signal advance_requested
signal choice_requested(index: int)

@export var character_definitions: Array[Resource] = []

@onready var portrait: TextureRect = $Panel/Margin/Layout/Portrait
@onready var name_label: Label = $Panel/Margin/Layout/Content/NameLabel
@onready var text_label: Label = $Panel/Margin/Layout/Content/TextLabel
@onready var advance_indicator: Label = $Panel/Margin/Layout/Content/AdvanceIndicator
@onready var choice_container: VBoxContainer = $Panel/Margin/Layout/Content/ChoiceContainer

var _characters: Dictionary = {}

func _ready() -> void:
	for definition: Resource in character_definitions:
		if definition != null and not definition.character_key.is_empty():
			_characters[definition.character_key] = definition
	hide_dialogue()

func show_line(character_key: StringName, expression: StringName, text: String) -> void:
	var definition: Resource = _characters.get(character_key)
	if definition == null:
		push_error("DialogueView: unknown character '%s'" % character_key)
		hide_dialogue()
		return
	if not definition.has_expression(expression):
		push_error("DialogueView: character '%s' has no expression '%s'; using '%s'" % [character_key, expression, definition.default_expression])
	portrait.texture = definition.resolve_portrait(expression)
	name_label.text = definition.display_name
	text_label.text = text
	_clear_choices()
	advance_indicator.visible = true
	visible = true

func show_choices(items: Array[Dictionary]) -> void:
	_clear_choices()
	advance_indicator.visible = false
	for index: int in items.size():
		var button := Button.new()
		button.text = String(items[index].get("text", ""))
		button.focus_mode = Control.FOCUS_ALL
		button.custom_minimum_size.y = 24.0
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_choice_pressed.bind(index))
		choice_container.add_child(button)
	visible = true
	if choice_container.get_child_count() > 0:
		choice_container.get_child(0).call_deferred("grab_focus")

func hide_dialogue(_context: Variant = null) -> void:
	visible = false
	_clear_choices()

func _unhandled_input(event: InputEvent) -> void:
	if not visible or choice_container.get_child_count() > 0:
		return
	if event.is_action_pressed("ui_accept") and _session_can(GameModeResource.ACTION_DIALOGUE_ADVANCE):
		advance_requested.emit()
		get_viewport().set_input_as_handled()

func _on_choice_pressed(index: int) -> void:
	if _session_can(GameModeResource.ACTION_DIALOGUE_CHOOSE):
		choice_requested.emit(index)

func _session_can(action: StringName) -> bool:
	var session := get_node_or_null("/root/GameSession")
	return session != null and session.can(action)

func _clear_choices() -> void:
	for child: Node in choice_container.get_children():
		choice_container.remove_child(child)
		child.queue_free()
