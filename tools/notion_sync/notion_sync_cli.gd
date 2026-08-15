@tool
extends SceneTree
class_name NotionSyncCli

const SyncConfig = preload("res://tools/notion_sync/notion_sync_config.gd")
const Transport = preload("res://tools/notion_sync/notion_transport.gd")
const Mapper = preload("res://tools/notion_sync/notion_mapper.gd")
const Compiler = preload("res://tools/notion_sync/dialogue_compiler.gd")
const SnapshotWriter = preload("res://tools/notion_sync/dialogue_snapshot_writer.gd")
const DEFAULT_OUTPUT_DIR := "res://data/generated/dialogues"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := _get_arguments()
	var dry_run := "--dry-run" in args
	var output_dir := _argument_value(args, "--output-dir", DEFAULT_OUTPUT_DIR)
	var mapped_input_path := _argument_value(args, "--mapped-input", "")
	var result: Dictionary
	if mapped_input_path.is_empty():
		var config := _get_configuration()
		result = await sync(config, output_dir, dry_run) if config["ok"] else _configuration_failure(config)
	elif not is_authorized_for(Engine.is_editor_hint(), OS.has_feature("editor"), _is_headless(), true):
		result = {"ok":false, "issues":[], "message":"Mapped-input sync requires an explicitly authorized editor binary running headless.", "counts":{}}
	else:
		result = _run_mapped_file(mapped_input_path, output_dir, dry_run)
	_present_result(result, dry_run)
	_terminate(exit_code_for(result))

func _get_arguments() -> PackedStringArray:
	return OS.get_cmdline_user_args()

func _get_configuration() -> Dictionary:
	return SyncConfig.from_environment(true)

func _terminate(exit_code: int) -> void:
	quit(exit_code)

func _present_result(result: Dictionary, dry_run: bool) -> void:
	if not result["ok"]:
		for issue: Dictionary in result.get("issues", []):
			printerr("%s %s %s" % [issue.get("severity", "error"), issue.get("code", "sync_failed"), issue.get("source_url", "")])
		if not String(result.get("message", "")).is_empty():
			printerr(result["message"])
		return
	if not String(result.get("message", "")).is_empty():
		print(result["message"])
	var counts: Dictionary = result.get("counts", {})
	print("Notion dialogue sync %s: %d scene(s), %d block(s), %d character(s)." % ["dry run" if dry_run else "complete", counts.get("scenes", 0), counts.get("blocks", 0), counts.get("characters", 0)])

static func _run_mapped_file(path: String, output_dir: String, dry_run: bool) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok":false, "issues":[], "message":"Mapped dialogue input file does not exist.", "counts":{}}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok":false, "issues":[], "message":"Mapped dialogue input must be a JSON dictionary.", "counts":{}}
	var input: Dictionary = parsed
	var result := run_mapped_input(input, output_dir, dry_run)
	result["counts"] = {"scenes":_array_size(input.get("scenes")), "blocks":_array_size(input.get("blocks")), "characters":_array_size(input.get("characters"))}
	return result

static func sync(config: Dictionary, output_dir: String = DEFAULT_OUTPUT_DIR, dry_run: bool = false, request_executor: Callable = Callable()) -> Dictionary:
	var validated := SyncConfig.validate_values(config)
	if not validated["ok"]:
		return {"ok":false, "issues":[], "message":validated["message"], "counts":{}}
	var transport := Transport.new(String(validated["token"]), request_executor, true)
	var scenes_response: Dictionary = await transport.query_all(String(validated["scenes_data_source"]), _scene_sorts())
	if not scenes_response["ok"]:
		return _transport_failure(scenes_response)
	var characters_response: Dictionary = await transport.query_all(String(validated["characters_data_source"]), _character_sorts())
	if not characters_response["ok"]:
		return _transport_failure(characters_response)
	var scenes: Array[Dictionary] = []
	var characters: Array[Dictionary] = []
	var scene_lookup := {}
	var character_lookup := {}
	for page: Dictionary in scenes_response["pages"]:
		var scene := Mapper.map_scene(page)
		scenes.append(scene)
		scene_lookup[String(page.get("id", ""))] = String(scene.get("scene_key", ""))
	for page: Dictionary in characters_response["pages"]:
		var character := Mapper.map_character(page)
		characters.append(character)
		character_lookup[String(page.get("id", ""))] = String(character.get("character_key", ""))
	var blocks_response: Dictionary = await transport.query_all(String(validated["blocks_data_source"]), _block_sorts())
	if not blocks_response["ok"]:
		return _transport_failure(blocks_response)
	var blocks: Array[Dictionary] = []
	for page: Dictionary in blocks_response["pages"]:
		blocks.append(Mapper.map_block(page, character_lookup, scene_lookup))
	var result := run_mapped_input({"scenes":scenes, "blocks":blocks, "characters":characters}, output_dir, dry_run)
	result["counts"] = {"scenes":scenes.size(), "blocks":blocks.size(), "characters":characters.size()}
	return result

static func run_mapped_input(input: Dictionary, output_dir: String = DEFAULT_OUTPUT_DIR, dry_run: bool = false) -> Dictionary:
	var compiled := Compiler.compile(input)
	if not compiled["ok"]:
		return {"ok":false, "issues":compiled["issues"], "manifest":compiled["manifest"], "graphs":compiled["graphs"], "error":ERR_INVALID_DATA, "message":"Dialogue compilation failed."}
	if dry_run:
		return {"ok":true, "issues":compiled["issues"], "manifest":compiled["manifest"], "graphs":compiled["graphs"], "error":OK, "message":""}
	var writer := SnapshotWriter.new()
	var error: Error = writer.replace_snapshot(output_dir, compiled["graphs"], compiled["manifest"])
	var recovery: Dictionary = writer.last_recovery.duplicate(true)
	var message := ""
	if error != OK:
		message = "Unable to replace the generated dialogue snapshot (%d)." % error
	elif String(recovery.get("code", "")) == "backup_cleanup_residue":
		message = "Snapshot committed; a possibly partial cleanup residue blocks future sync at %s. Inspect and remove it manually." % recovery.get("backup_path", "")
	elif String(recovery.get("code", "")) == "transaction_cleanup_residue":
		message = "Snapshot committed; transaction cleanup residue remains at %s." % recovery.get("temporary_path", "")
	return {"ok":error == OK, "issues":compiled["issues"], "manifest":compiled["manifest"], "graphs":compiled["graphs"], "error":error, "recovery":recovery, "message":message}

static func is_authorized_for(editor_hint: bool, editor_binary: bool, headless: bool, allow_headless_sync: bool) -> bool:
	return SyncConfig.is_available_for(editor_hint, editor_binary, headless, allow_headless_sync)

static func exit_code_for(result: Dictionary) -> int:
	return 0 if bool(result.get("ok", false)) else 1

static func _scene_sorts() -> Array[Dictionary]:
	return [{"property":"scene_key", "direction":"ascending"}]

static func _block_sorts() -> Array[Dictionary]:
	return [{"property":"flow", "direction":"ascending"}, {"property":"order", "direction":"ascending"}]

static func _character_sorts() -> Array[Dictionary]:
	return [{"property":"character_key", "direction":"ascending"}]

static func _transport_failure(response: Dictionary) -> Dictionary:
	return {"ok":false, "issues":[], "message":String(response.get("message", "Notion query failed.")), "counts":{}}

static func _configuration_failure(config: Dictionary) -> Dictionary:
	return {"ok":false, "issues":[], "message":String(config.get("message", "Notion sync configuration failed.")), "counts":{}}

static func _array_size(value: Variant) -> int:
	return value.size() if typeof(value) == TYPE_ARRAY else 0

static func _is_headless() -> bool:
	return OS.has_feature("headless") or DisplayServer.get_name() == "headless"

func _argument_value(args: PackedStringArray, name: String, fallback: String) -> String:
	var index := args.find(name)
	return args[index + 1] if index >= 0 and index + 1 < args.size() else fallback
