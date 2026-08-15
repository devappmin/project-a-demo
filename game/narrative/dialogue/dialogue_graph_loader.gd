extends RefCounted
class_name DialogueGraphLoader

const DialogueGraphResource = preload("res://game/narrative/dialogue/dialogue_graph.gd")
const DialogueGraphValidatorResource = preload("res://game/narrative/dialogue/dialogue_graph_validator.gd")

var base_directory: String = "res://data/generated/dialogues"
var character_keys: Array[StringName] = [&"retti", &"jellyppo"]
var last_failure: Dictionary = {}
var last_issues: Array[Dictionary] = []

func load_scene(scene_key: StringName) -> DialogueGraphResource:
	last_failure = {}
	last_issues = []
	var requested_key := String(scene_key)
	if not _scene_key_is_safe(requested_key):
		_fail("unsafe_scene_key", "scene key contains unsafe filename characters")
		return null
	var path := _scene_path(requested_key)
	if path.is_empty():
		_fail("unsafe_base_directory", "dialogue base directory cannot contain the scene file safely")
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("load_failed", "dialogue scene file could not be opened", path)
		return null
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	if parse_error != OK:
		_fail("parse_failed", "dialogue scene JSON is malformed at line %d: %s" % [parser.get_error_line(), parser.get_error_message()], path)
		return null
	var data_value: Variant = parser.data
	if typeof(data_value) != TYPE_DICTIONARY:
		_fail("parse_failed", "dialogue scene JSON root must be a dictionary", path)
		return null
	var data: Dictionary = data_value
	last_issues = DialogueGraphValidatorResource.validate(data, character_keys)
	if String(data.get("scene_key", "")) != requested_key:
		last_issues.append({
			"severity": "error",
			"code": "scene_key_mismatch",
			"scene_key": String(data.get("scene_key", "")),
			"node_id": "",
			"message": "loaded scene_key does not match the requested scene"
		})
	if not last_issues.is_empty():
		_fail("validation_failed", "dialogue scene failed validation", path)
		return null
	return DialogueGraphResource.from_dictionary(data)

func _scene_path(scene_key: String) -> String:
	var normalized_base := base_directory.replace("\\", "/").trim_suffix("/").simplify_path()
	if normalized_base.is_empty():
		return ""
	var filename := scene_key.replace(".", "_") + ".json"
	var path := normalized_base.path_join(filename).simplify_path()
	if path.get_base_dir() != normalized_base:
		return ""
	return path

func _scene_key_is_safe(scene_key: String) -> bool:
	return not scene_key.is_empty() \
		and not scene_key.contains("/") \
		and not scene_key.contains("\\")

func _fail(code: String, message: String, path := "") -> void:
	last_failure = {"code": code, "message": message, "path": path}
