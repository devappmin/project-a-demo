extends "res://tests/support/test_case.gd"

func run() -> void:
	var scene := load("res://game/actors/player/player.tscn") as PackedScene
	assert_not_null(scene, "player scene must exist")
	if scene == null:
		return
	var player := scene.instantiate()
	assert_not_null(player.get_node_or_null("AnimatedSprite2D"), "player has an animated sprite")
	assert_not_null(player.get_node_or_null("CollisionShape2D"), "player has a collision shape")
	assert_not_null(player.get_node_or_null("InteractionDetector"), "player exposes an interaction detector")
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	assert_not_null(camera, "player has a camera")
	if camera != null:
		assert_eq(camera.zoom, Vector2(2, 2), "camera starts at two-times zoom")
	var sprite := player.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite != null:
		assert_true(sprite.sprite_frames.has_animation(&"idle_down"), "sprite has a down idle animation")
		assert_true(sprite.sprite_frames.has_animation(&"walk_right"), "sprite has a right walk animation")
	player.free()
