extends Control
class_name DialogueView

const GameModeResource = preload("res://app/session/game_mode.gd")
const DefaultCharacterRegistry = preload("res://data/characters/character_registry.tres")

signal advance_requested
signal choice_requested(index: int)

@export var character_registry: Resource = DefaultCharacterRegistry

@onready var portrait: TextureRect = $Panel/Margin/Layout/Portrait
@onready var name_label: Label = $Panel/Margin/Layout/Content/NameLabel
@onready var text_label: Label = $Panel/Margin/Layout/Content/TextLabel
@onready var advance_indicator: Label = $Panel/Margin/Layout/Content/AdvanceIndicator
@onready var choice_scroll: ScrollContainer = $Panel/Margin/Layout/Content/ChoiceScroll
@onready var choice_container: VBoxContainer = $Panel/Margin/Layout/Content/ChoiceScroll/ChoiceContainer

var _characters: Dictionary = {}

func _ready() -> void:
	_characters.clear()
	if character_registry != null:
		for character_key: StringName in character_registry.character_keys():
			_characters[character_key] = character_registry.get_definition(character_key)
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
	choice_scroll.visible = false
	text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	advance_indicator.visible = true
	visible = true

func show_choices(items: Array[Dictionary]) -> void:
	_clear_choices()
	choice_scroll.visible = true
	text_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	advance_indicator.visible = false
	for index: int in items.size():
		var button := Button.new()
		button.text = String(items[index].get("text", ""))
		button.focus_mode = Control.FOCUS_ALL
		button.custom_minimum_size.y = 24.0
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.add_theme_font_size_override("font_size", 14)
		button.pressed.connect(_on_choice_pressed.bind(index))
		button.focus_entered.connect(_on_choice_focused.bind(button))
		choice_container.add_child(button)
	visible = true
	if choice_container.get_child_count() > 0:
		var first_button := choice_container.get_child(0) as Control
		first_button.call_deferred("grab_focus")
		call_deferred("_ensure_choice_visible", first_button)

func hide_dialogue(_context: Variant = null) -> void:
	visible = false
	_clear_choices()
	choice_scroll.visible = false
	text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	portrait.texture = null
	name_label.text = ""
	text_label.text = ""
	advance_indicator.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not visible or choice_container.get_child_count() > 0:
		return
	if event.is_action_pressed("ui_accept") and _session_can(GameModeResource.ACTION_DIALOGUE_ADVANCE):
		advance_requested.emit()
		get_viewport().set_input_as_handled()

func _on_choice_pressed(index: int) -> void:
	if _session_can(GameModeResource.ACTION_DIALOGUE_CHOOSE):
		choice_requested.emit(index)

func _on_choice_focused(button: Control) -> void:
	call_deferred("_ensure_choice_visible", button)

func _ensure_choice_visible(button: Control) -> void:
	if is_instance_valid(button) and choice_scroll.is_ancestor_of(button):
		choice_scroll.ensure_control_visible(button)

func _session_can(action: StringName) -> bool:
	var session := get_node_or_null("/root/GameSession")
	return session != null and session.can(action)

func _clear_choices() -> void:
	choice_scroll.scroll_vertical = 0
	for child: Node in choice_container.get_children():
		choice_container.remove_child(child)
		child.queue_free()
