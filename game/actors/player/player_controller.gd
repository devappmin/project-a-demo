extends CharacterBody2D
class_name PlayerController

const PlayerInput = preload("res://game/actors/player/player_input.gd")

@export var walk_speed := 48.0
@export var sprint_speed := 72.0
@export var presentation_parent_path: NodePath

var facing := Vector2.DOWN

@onready var presentation: Node2D = $PlayerVisual
@onready var animated_sprite: AnimatedSprite2D = $PlayerVisual/AnimatedSprite2D

func _ready() -> void:
	_attach_presentation()
	_sync_presentation()
	_update_animation(false)

func _process(_delta: float) -> void:
	_sync_presentation()

func _physics_process(_delta: float) -> void:
	var direction := PlayerInput.movement_direction()
	velocity = calculate_velocity(direction, PlayerInput.is_sprinting())
	update_facing(direction)
	move_and_slide()
	_update_animation(direction != Vector2.ZERO)

func calculate_velocity(direction: Vector2, sprinting: bool) -> Vector2:
	var speed := sprint_speed if sprinting else walk_speed
	return direction.normalized() * speed if direction != Vector2.ZERO else Vector2.ZERO

func update_facing(direction: Vector2) -> void:
	if direction == Vector2.ZERO:
		return
	facing = Vector2(sign(direction.x), 0.0) if abs(direction.x) > abs(direction.y) else Vector2(0.0, sign(direction.y))

func _update_animation(moving: bool) -> void:
	var prefix := "walk_" if moving else "idle_"
	var animation_name := StringName(prefix + _facing_name())
	if animated_sprite.sprite_frames.has_animation(animation_name):
		animated_sprite.play(animation_name)

func _facing_name() -> String:
	if facing == Vector2.LEFT:
		return "left"
	if facing == Vector2.RIGHT:
		return "right"
	if facing == Vector2.UP:
		return "up"
	return "down"

func _attach_presentation() -> void:
	if presentation_parent_path.is_empty():
		return
	var presentation_parent := get_node_or_null(presentation_parent_path) as Node2D
	if presentation_parent == null:
		return
	presentation.reparent(presentation_parent)

func _sync_presentation() -> void:
	if presentation != null and presentation.get_parent() != self:
		presentation.global_position = global_position + Vector2(0.0, 17.0)
