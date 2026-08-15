extends "res://tests/support/test_case.gd"

const NotionSyncConfig = preload("res://tools/notion_sync/notion_sync_config.gd")

func run() -> void:
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
