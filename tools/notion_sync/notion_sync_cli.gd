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
	var args := OS.get_cmdline_user_args()
	var dry_run := "--dry-run" in args
	var output_dir := _argument_value(args, "--output-dir", DEFAULT_OUTPUT_DIR)
	var config := SyncConfig.from_environment(true)
	if not config["ok"]:
		printerr(config["message"])
		quit(1)
		return
	var result: Dictionary = await sync(config, output_dir, dry_run)
	if not result["ok"]:
		for issue: Dictionary in result.get("issues", []):
			printerr("%s %s %s" % [issue.get("severity", "error"), issue.get("code", "sync_failed"), issue.get("source_url", "")])
		if not String(result.get("message", "")).is_empty():
			printerr(result["message"])
		quit(1)
		return
	if not String(result.get("message", "")).is_empty():
		print(result["message"])
	var counts: Dictionary = result.get("counts", {})
	print("Notion dialogue sync %s: %d scene(s), %d block(s), %d character(s)." % ["dry run" if dry_run else "complete", counts.get("scenes", 0), counts.get("blocks", 0), counts.get("characters", 0)])
	quit(0)

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
	elif String(recovery.get("code", "")) == "backup_cleanup_failed":
		message = "Snapshot committed; recovery backup remains at %s." % recovery.get("backup_path", "")
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

func _argument_value(args: PackedStringArray, name: String, fallback: String) -> String:
	var index := args.find(name)
	return args[index + 1] if index >= 0 and index + 1 < args.size() else fallback
