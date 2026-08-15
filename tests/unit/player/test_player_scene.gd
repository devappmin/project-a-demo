extends "res://tests/support/test_case.gd"

func run() -> void:
	_test_rendering_snaps_to_logical_pixels_without_rounding_physics()

	var scene := load("res://game/actors/player/player.tscn") as PackedScene
	assert_not_null(scene, "player scene must exist")
	if scene == null:
		return
	var player := scene.instantiate()
	assert_not_null(player.get_node_or_null("PlayerVisual/AnimatedSprite2D"), "player has an animated sprite")
	assert_not_null(player.get_node_or_null("CollisionShape2D"), "player has a collision shape")
	assert_not_null(player.get_node_or_null("InteractionDetector"), "player exposes an interaction detector")
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	assert_not_null(camera, "player has a camera")
	if camera != null:
		assert_eq(camera.zoom, Vector2(2, 2), "camera starts at two-times zoom")
	var sprite := player.get_node_or_null("PlayerVisual/AnimatedSprite2D") as AnimatedSprite2D
	if sprite != null:
		assert_true(sprite.sprite_frames.has_animation(&"idle_down"), "sprite has a down idle animation")
		assert_true(sprite.sprite_frames.has_animation(&"walk_right"), "sprite has a right walk animation")
	player.free()

func _test_rendering_snaps_to_logical_pixels_without_rounding_physics() -> void:
	assert_true(
		ProjectSettings.get_setting("rendering/2d/snap/snap_2d_transforms_to_pixel", false),
		"2D presentation snaps transforms to logical pixel boundaries"
	)
	assert_true(get_viewport().is_snap_2d_transforms_to_pixel_enabled(), "the running viewport applies 2D transform snapping")
	var player := PlayerController.new()
	player.position = Vector2(12.25, 31.75)
	assert_eq(player.position, Vector2(12.25, 31.75), "render snapping preserves fractional physics coordinates")
	var diagonal_velocity := player.calculate_velocity(Vector2.ONE, false)
	assert_false(diagonal_velocity.x == roundf(diagonal_velocity.x), "render snapping preserves fractional diagonal velocity")
	player.free()
