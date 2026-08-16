extends "res://tests/support/test_case.gd"

const PLUGIN_PATH := "res://tools/notion_sync/plugin.gd"
const PLUGIN_CONFIG_PATH := "res://tools/notion_sync/plugin.cfg"
const GENERATED_DIRECTORY := "res://data/generated/dialogues"

func run() -> void:
	_test_project_enables_the_plugin()
	await _test_plugin_loads_and_unloads_one_dock()
	_test_generated_dialogue_is_playable_without_credentials()
	await _test_offline_game_boot()

func _test_project_enables_the_plugin() -> void:
	var enabled: PackedStringArray = ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray())
	assert_true(PLUGIN_CONFIG_PATH in enabled, "project enables the Notion dialogue editor plugin")

func _test_plugin_loads_and_unloads_one_dock() -> void:
	assert_true(ResourceLoader.exists(PLUGIN_PATH, "Script"), "Notion sync editor plugin script exists")
	if not ResourceLoader.exists(PLUGIN_PATH, "Script"):
		return
	var godot_binary := OS.get_environment("PROJECT_A_GODOT_BIN")
	assert_true(FileAccess.file_exists(godot_binary), "editor plugin lifecycle test has the pinned Godot binary")
	if not FileAccess.file_exists(godot_binary):
		return
	var output: Array = []
	var exit_code := OS.execute(godot_binary, PackedStringArray(["--headless", "--editor", "--verbose", "--path", ProjectSettings.globalize_path("res://"), "--quit-after", "2"]), output, true)
	var combined := "\n".join(output)
	assert_eq(exit_code, 0, "enabled editor plugin loads and the editor exits normally")
	assert_true(combined.contains("Notion dialogue sync dock registered."), "actual editor plugin registers its dock on enter")
	assert_true(combined.contains("Notion dialogue sync dock removed."), "actual editor plugin removes its dock on exit")
	assert_false(combined.contains("Failed loading resource") or combined.contains("SCRIPT ERROR"), "editor plugin lifecycle has no resource or script failure")

func _test_generated_dialogue_is_playable_without_credentials() -> void:
	var saved_token := OS.get_environment("PROJECT_A_NOTION_TOKEN")
	OS.set_environment("PROJECT_A_NOTION_TOKEN", "")
	var loader := DialogueGraphLoader.new()
	loader.base_directory = GENERATED_DIRECTORY
	var graph := loader.load_scene(&"foundation.inspect")
	OS.set_environment("PROJECT_A_NOTION_TOKEN", saved_token)
	assert_not_null(graph, "generated foundation dialogue loads with no Notion credentials")
	if graph != null:
		assert_eq(graph.get_node(graph.entry_node).get("type", ""), "line", "offline dialogue reaches its first playable line")

func _test_offline_game_boot() -> void:
	var godot_binary := OS.get_environment("PROJECT_A_GODOT_BIN")
	assert_true(FileAccess.file_exists(godot_binary), "offline boot test has the pinned Godot binary")
	if not FileAccess.file_exists(godot_binary):
		return
	var variable_names := ["PROJECT_A_NOTION_TOKEN", "PROJECT_A_NOTION_SCENES_DATA_SOURCE", "PROJECT_A_NOTION_BLOCKS_DATA_SOURCE", "PROJECT_A_NOTION_CHARACTERS_DATA_SOURCE"]
	var saved_values := {}
	for variable_name: String in variable_names:
		saved_values[variable_name] = OS.get_environment(variable_name)
		OS.set_environment(variable_name, "")
	var output: Array = []
	var exit_code := OS.execute(godot_binary, PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--quit-after", "2"]), output, true)
	for variable_name: String in variable_names:
		OS.set_environment(variable_name, String(saved_values[variable_name]))
	assert_eq(exit_code, 0, "game boots offline without any Notion environment variables")
	assert_false("PROJECT_A_NOTION_TOKEN" in "\n".join(output), "offline gameplay never tries to initialize Notion sync")
