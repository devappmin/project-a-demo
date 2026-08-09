extends "res://tests/support/test_case.gd"

func run() -> void:
	var scene := load("res://app/bootstrap/app_root.tscn") as PackedScene
	assert_not_null(scene, "AppRoot scene must exist")
	if scene == null:
		return
	var root := scene.instantiate()
	assert_not_null(root.get_node_or_null("WorldHost"), "WorldHost must exist")
	assert_not_null(root.get_node_or_null("ServiceLayer"), "ServiceLayer must exist")
	assert_not_null(root.get_node_or_null("UILayer"), "UILayer must exist")
	root.free()
