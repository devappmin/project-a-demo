extends "res://tests/support/test_case.gd"

const PlayerController = preload("res://game/actors/player/player_controller.gd")

func run() -> void:
	var player := PlayerController.new()
	player.walk_speed = 48.0
	player.sprint_speed = 72.0
	assert_eq(player.calculate_velocity(Vector2.RIGHT, false), Vector2(48.0, 0.0), "walk speed")
	assert_almost_eq(player.calculate_velocity(Vector2(1, 1), true).length(), 72.0, 0.001, "diagonal sprint is normalized")
	player.update_facing(Vector2(-0.2, 1.0))
	assert_eq(player.facing, Vector2.DOWN, "dominant axis controls facing")
	player.free()
