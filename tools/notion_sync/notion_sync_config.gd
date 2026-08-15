@tool
extends RefCounted
class_name NotionSyncConfig

const TOKEN_ENV := "PROJECT_A_NOTION_TOKEN"
const SCENES_DATA_SOURCE_ENV := "PROJECT_A_NOTION_SCENES_DATA_SOURCE"
const BLOCKS_DATA_SOURCE_ENV := "PROJECT_A_NOTION_BLOCKS_DATA_SOURCE"
const CHARACTERS_DATA_SOURCE_ENV := "PROJECT_A_NOTION_CHARACTERS_DATA_SOURCE"

static func from_environment() -> Dictionary:
	if not _is_editor_or_headless():
		return _error("Notion sync configuration is only available in editor or headless tooling.")
	return validate_values({
		"token": OS.get_environment(TOKEN_ENV),
		"scenes_data_source": OS.get_environment(SCENES_DATA_SOURCE_ENV),
		"blocks_data_source": OS.get_environment(BLOCKS_DATA_SOURCE_ENV),
		"characters_data_source": OS.get_environment(CHARACTERS_DATA_SOURCE_ENV)
	})

static func validate_values(values: Dictionary) -> Dictionary:
	var required_values := [
		["token", TOKEN_ENV],
		["scenes_data_source", SCENES_DATA_SOURCE_ENV],
		["blocks_data_source", BLOCKS_DATA_SOURCE_ENV],
		["characters_data_source", CHARACTERS_DATA_SOURCE_ENV]
	]
	for required_value: Array in required_values:
		var key := String(required_value[0])
		var environment_variable := String(required_value[1])
		if String(values.get(key, "")).strip_edges().is_empty():
			return _error("Missing required environment variable %s." % environment_variable)
	return {
		"ok": true,
		"token": String(values["token"]).strip_edges(),
		"scenes_data_source": String(values["scenes_data_source"]).strip_edges(),
		"blocks_data_source": String(values["blocks_data_source"]).strip_edges(),
		"characters_data_source": String(values["characters_data_source"]).strip_edges(),
		"message": ""
	}

static func _error(message: String) -> Dictionary:
	return {
		"ok": false,
		"token": "",
		"scenes_data_source": "",
		"blocks_data_source": "",
		"characters_data_source": "",
		"message": message
	}

static func _is_editor_or_headless() -> bool:
	return Engine.is_editor_hint() or OS.has_feature("headless") or DisplayServer.get_name() == "headless"
