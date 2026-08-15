@tool
extends RefCounted
class_name NotionSyncConfig

const TOKEN_ENV := "PROJECT_A_NOTION_TOKEN"
const SCENES_DATA_SOURCE_ENV := "PROJECT_A_NOTION_SCENES_DATA_SOURCE"
const BLOCKS_DATA_SOURCE_ENV := "PROJECT_A_NOTION_BLOCKS_DATA_SOURCE"
const CHARACTERS_DATA_SOURCE_ENV := "PROJECT_A_NOTION_CHARACTERS_DATA_SOURCE"

static func from_environment(allow_headless_sync: bool = false) -> Dictionary:
	if not is_available_for(Engine.is_editor_hint(), OS.has_feature("editor"), _is_headless(), allow_headless_sync):
		return _error("Notion sync configuration is only available in editor or explicitly authorized editor CLI tooling.")
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

static func is_available_for(editor_hint: bool, editor_binary: bool, headless: bool, allow_headless_sync: bool) -> bool:
	return editor_hint or (editor_binary and headless and allow_headless_sync)

static func _is_headless() -> bool:
	return OS.has_feature("headless") or DisplayServer.get_name() == "headless"
