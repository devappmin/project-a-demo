extends Area2D
class_name InteractionDetector

signal target_changed(target: InteractionTarget)

@export var player_path: NodePath = ^".."

var current_target: InteractionTarget:
	set(value):
		if current_target == value:
			return
		current_target = value
		target_changed.emit(current_target)

@onready var player: PlayerController = get_node_or_null(player_path) as PlayerController

func _physics_process(_delta: float) -> void:
	if player == null:
		return
	var candidates: Array[InteractionTarget] = []
	for area in get_overlapping_areas():
		var target := area as InteractionTarget
		if target != null:
			candidates.append(target)
	current_target = choose_target(candidates, global_position, player.facing)

func choose_target(candidates: Array[InteractionTarget], origin: Vector2, facing: Vector2) -> InteractionTarget:
	if facing.is_zero_approx():
		return null
	var normalized_facing := facing.normalized()
	var ranked: Array[InteractionTarget] = []
	for candidate in candidates:
		if candidate == null or not is_instance_valid(candidate):
			continue
		var direction := candidate.global_position - origin
		if direction.is_zero_approx() or direction.normalized().dot(normalized_facing) <= 0.35:
			continue
		ranked.append(candidate)
	ranked.sort_custom(_ranks_before.bind(origin, normalized_facing))
	return ranked[0] if not ranked.is_empty() else null

func _ranks_before(left: InteractionTarget, right: InteractionTarget, origin: Vector2, facing: Vector2) -> bool:
	if left.priority != right.priority:
		return left.priority > right.priority
	var left_offset := left.global_position - origin
	var right_offset := right.global_position - origin
	var left_dot := left_offset.normalized().dot(facing)
	var right_dot := right_offset.normalized().dot(facing)
	if left_dot != right_dot:
		return left_dot > right_dot
	var left_distance := left_offset.length_squared()
	var right_distance := right_offset.length_squared()
	if left_distance != right_distance:
		return left_distance < right_distance
	return left.get_instance_id() < right.get_instance_id()
