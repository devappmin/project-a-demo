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
	var world_host := root.get_node_or_null("WorldHost")
	assert_not_null(world_host, "WorldHost is available for SceneDirector configuration")
	if world_host != null:
		assert_eq(world_host.get_child_count(), 0, "WorldHost is empty at boot until gameplay explicitly starts")
	assert_true(ProjectSettings.has_setting("autoload/SceneDirector"), "SceneDirector is registered as the second autoload")
	assert_true(ProjectSettings.has_setting("autoload/SaveService"), "SaveService is registered as the third autoload")
	assert_eq(_autoload_names(), ["GameSession", "SceneDirector", "SaveService"], "the project has exactly the three approved autoloads in order")
	assert_not_null(root.get_node_or_null("ServiceLayer/DialogueService"), "AppRoot owns the local DialogueService injected into SaveService")
	root.free()

func _autoload_names() -> Array[String]:
	var names: Array[String] = []
	for property in ProjectSettings.get_property_list():
		var property_name := String(property.get("name", ""))
		if property_name.begins_with("autoload/"):
			names.append(property_name.trim_prefix("autoload/"))
	return names
