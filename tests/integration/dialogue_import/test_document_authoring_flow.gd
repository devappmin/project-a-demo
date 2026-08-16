extends "res://tests/support/test_case.gd"

const Cli = preload("res://tools/dialogue_import/dialogue_import_cli.gd")
const EventIndex = preload("res://game/narrative/dialogue/dialogue_event_index.gd")
const EventResolver = preload("res://game/narrative/dialogue/dialogue_event_resolver.gd")
const AUTHORING_DIR := "res://data/dialogues/authoring"
const PAGE_COMMENT := "페이지 전체의 연출 방향을 논의하는 댓글이며 게임 데이터에는 들어가지 않는다."
const LINE_COMMENT := "빛의 색은 배경 원화가 정해진 뒤 다시 논의한다."

var _test_root := ""

func run() -> void:
	_test_root = "user://test-output/document-authoring-flow-%s" % Time.get_ticks_usec()
	var input_dir := _test_root.path_join("authoring")
	var output_dir := _test_root.path_join("generated")
	_assert_production_contract()
	_copy_authoring_directory(input_dir)
	var dry_run: Dictionary = Cli.run_import(input_dir, output_dir, true)
	assert_true(dry_run.get("ok", false), "tracked document authoring dry-run succeeds")
	assert_false(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output_dir)), "dry-run does not publish runtime files")
	var published: Dictionary = Cli.run_import(input_dir, output_dir, false)
	assert_true(published.get("ok", false), "tracked document authoring publishes to an isolated snapshot")
	for filename: String in ["foundation_inspect.json", "events.json", "source_map.json", "manifest.json"]:
		assert_true(FileAccess.file_exists(output_dir.path_join(filename)), "isolated publish contains %s" % filename)
	if published.get("ok", false):
		await _drive_published_dialogue(output_dir)
	_remove_tree(_test_root)

func _assert_production_contract() -> void:
	var packed := load("res://content/interactables/sample_inspectable.tscn") as PackedScene
	assert_not_null(packed, "production mirror scene loads")
	if packed != null:
		var target := packed.instantiate() as InteractionTarget
		assert_not_null(target, "production mirror target instantiates")
		if target != null:
			assert_eq(target.payload.get("dialogue_bundle_key"), &"foundation.inspect", "mirror uses a document bundle")
			assert_eq(target.payload.get("dialogue_trigger_key"), &"mirror.inspect", "mirror uses a trigger key")
			assert_false(target.payload.has("scene_key"), "legacy direct scene payload is removed")
			target.free()
	var removed_plugin_path := "res://tools/" + "notion_sync/plugin.cfg"
	assert_false(ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray()).has(removed_plugin_path), "live sync plugin is disabled")
	assert_true(FileAccess.file_exists("res://data/generated/dialogues/events.json"), "production event index is tracked")

func _drive_published_dialogue(output_dir: String) -> void:
	var graph_text := FileAccess.get_file_as_string(output_dir.path_join("foundation_inspect.json"))
	var events_text := FileAccess.get_file_as_string(output_dir.path_join("events.json"))
	var source_map_text := FileAccess.get_file_as_string(output_dir.path_join("source_map.json"))
	var generated_text := graph_text + events_text + source_map_text
	assert_false(generated_text.contains(PAGE_COMMENT), "page comments never enter generated artifacts")
	assert_false(generated_text.contains(LINE_COMMENT), "line comments never enter generated artifacts")
	var event_index := EventIndex.load_path(output_dir.path_join("events.json"))
	assert_true(event_index.is_valid(), "published event index loads")
	var state := NarrativeState.new()
	var resolver := EventResolver.new()
	resolver.event_index = event_index
	var fallback: Dictionary = resolver.resolve(&"foundation.inspect", &"mirror.inspect", state)
	assert_true(fallback.get("ok", false), "unseen mirror resolves an event")
	assert_eq(fallback.get("event_key"), &"default", "unseen mirror resolves the final fallback")
	if not fallback.get("ok", false):
		return
	var previous_mode: int = GameSession.current_mode
	var previous_state: NarrativeState = GameSession.narrative_state
	GameSession.change_mode(GameMode.Value.EXPLORATION)
	GameSession.narrative_state = state
	var service := DialogueService.new()
	var loader := DialogueGraphLoader.new()
	loader.base_directory = output_dir
	service.graph_loader = loader
	service.narrative_state = state
	service.game_session = GameSession
	var lines: Array[String] = []
	var choice_batches: Array[Array] = []
	service.line_requested.connect(func(_character_key: StringName, _expression: StringName, text: String) -> void: lines.append(text))
	service.choices_requested.connect(func(items: Array[Dictionary]) -> void: choice_batches.append(items.duplicate(true)))
	get_tree().root.add_child(service)
	assert_eq(service.start_dialogue(fallback["scene_key"], fallback["node_id"]), OK, "fallback graph starts from the resolved event entry")
	assert_eq(lines, ["낯선 거울이다."], "fallback begins with its first line")
	service.advance()
	assert_eq(lines.back(), "표면 안쪽에서 희미한 빛이 흔들린다.", "a second line appears before the first choice")
	service.advance()
	assert_eq(choice_batches.size(), 1, "first choice appears after multiple lines")
	assert_eq(service.choose(0), OK, "first choice enters the long inspect branch")
	assert_true(state.get_flag(&"mirror_seen"), "named choice result is applied immediately")
	assert_eq(lines.back(), "거울 속에는 이 방과 조금 다른 방이 비친다.", "branch begins with its first later line")
	service.advance()
	assert_eq(lines.back(), "조금 더 살펴볼까?", "branch continues for multiple lines")
	service.advance()
	assert_eq(choice_batches.size(), 2, "a second choice appears later in the branch")
	assert_eq(service.choose(1), OK, "second choice takes the rejoin route")
	assert_eq(lines.back(), "거울은 다시 조용해졌다.", "two authored branches share the rejoin flow")
	service.advance()
	assert_eq(service.current_graph, null, "rejoined dialogue reaches its authored end")
	var specific: Dictionary = resolver.resolve(&"foundation.inspect", &"mirror.inspect", state)
	assert_true(specific.get("ok", false), "updated state resolves another event")
	assert_eq(specific.get("event_key"), &"seen", "specific event wins after the choice result")
	service.queue_free()
	await get_tree().process_frame
	GameSession.narrative_state = previous_state
	GameSession.change_mode(previous_mode)

func _copy_authoring_directory(destination: String) -> void:
	assert_eq(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(destination)), OK, "isolated authoring directory is created")
	var source := DirAccess.open(AUTHORING_DIR)
	assert_not_null(source, "tracked authoring directory opens")
	if source == null:
		return
	var filenames := source.get_files()
	filenames.sort()
	for filename: String in filenames:
		if not filename.ends_with(".json"):
			continue
		var target := FileAccess.open(destination.path_join(filename), FileAccess.WRITE)
		assert_not_null(target, "tracked authoring file copies: %s" % filename)
		if target != null:
			target.store_buffer(FileAccess.get_file_as_bytes(AUTHORING_DIR.path_join(filename)))
			target.close()

func _remove_tree(path: String) -> Error:
	var absolute := ProjectSettings.globalize_path(path)
	if not DirAccess.dir_exists_absolute(absolute):
		return OK
	var directory := DirAccess.open(path)
	if directory == null:
		return DirAccess.get_open_error()
	for child_dir: String in directory.get_directories():
		var child_error := _remove_tree(path.path_join(child_dir))
		if child_error != OK:
			return child_error
	for filename: String in directory.get_files():
		var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path.path_join(filename)))
		if remove_error != OK:
			return remove_error
	return DirAccess.remove_absolute(absolute)
