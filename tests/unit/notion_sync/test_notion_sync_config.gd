extends "res://tests/support/test_case.gd"

const NotionSyncConfig = preload("res://tools/notion_sync/notion_sync_config.gd")

func run() -> void:
	_test_tooling_authorization()
	var valid := NotionSyncConfig.validate_values({
		"token":"test-token",
		"scenes_data_source":"scene-source",
		"blocks_data_source":"block-source",
		"characters_data_source":"character-source"
	})
	assert_true(valid["ok"], "complete Notion configuration is accepted")
	assert_eq(valid["characters_data_source"], "character-source", "validated configuration returns each data source")
	var result := NotionSyncConfig.validate_values({
		"token":"",
		"scenes_data_source":"a",
		"blocks_data_source":"b",
		"characters_data_source":"c"
	})
	assert_false(result["ok"], "empty token is rejected")
	assert_true(String(result["message"]).contains("PROJECT_A_NOTION_TOKEN"), "error names the missing variable")
	var missing_source := NotionSyncConfig.validate_values({
		"token":"test-token",
		"scenes_data_source":"",
		"blocks_data_source":"b",
		"characters_data_source":"c"
	})
	assert_false(missing_source["ok"], "empty scene data source is rejected")
	assert_true(String(missing_source["message"]).contains("PROJECT_A_NOTION_SCENES_DATA_SOURCE"), "error names the missing scene source variable")

func _test_tooling_authorization() -> void:
	assert_false(NotionSyncConfig.is_available_for(false, false, true, false), "generic headless execution is denied")
	assert_false(NotionSyncConfig.is_available_for(false, false, true, true), "export-shaped headless opt-in is denied")
	assert_true(NotionSyncConfig.is_available_for(false, true, true, true), "explicit editor-binary CLI authorization is allowed")
	assert_true(NotionSyncConfig.is_available_for(true, false, false, false), "editor dock execution is allowed")
	var denied_config := NotionSyncConfig.from_environment()
	assert_false(denied_config["ok"], "headless configuration requires explicit authorization")
	assert_eq(denied_config["token"], "", "denied configuration never returns an environment token")
	assert_true(String(denied_config["message"]).contains("explicitly authorized"), "denied configuration explains the CLI authorization requirement")
