extends "res://tests/support/test_case.gd"

const Cli = preload("res://tools/dialogue_import/dialogue_import_cli.gd")
const EventIndex = preload("res://game/narrative/dialogue/dialogue_event_index.gd")
const EventResolver = preload("res://game/narrative/dialogue/dialogue_event_resolver.gd")
const AUTHORING_DIR := "res://data/dialogues/authoring"
const AUTHORING_FILE := "res://data/dialogues/authoring/foundation_inspect.json"

var _test_root := ""

func run() -> void:
	_test_root = "user://test-output/document-authoring-flow-%s" % Time.get_ticks_usec()
	var input_dir := _test_root.path_join("authoring")
	var output_dir := _test_root.path_join("generated")
	_assert_production_contract()
	var bundle := _read_dictionary(AUTHORING_FILE)
	_assert_local_provenance(bundle)
	_copy_authoring_directory(input_dir)
	var dry_run: Dictionary = Cli.run_import(input_dir, output_dir, true)
	assert_true(dry_run.get("ok", false), "tracked document authoring dry-run succeeds")
	assert_false(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output_dir)), "dry-run does not publish runtime files")
	var published: Dictionary = Cli.run_import(input_dir, output_dir, false)
	assert_true(published.get("ok", false), "tracked document authoring publishes to an isolated snapshot")
	for filename: String in ["foundation_inspect.json", "events.json", "source_map.json", "manifest.json"]:
		assert_true(FileAccess.file_exists(output_dir.path_join(filename)), "isolated publish contains %s" % filename)
	if published.get("ok", false):
		await _assert_published_semantics(bundle, output_dir)
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

func _assert_local_provenance(bundle: Dictionary) -> void:
	assert_eq(bundle.get("source_url"), AUTHORING_FILE, "local sample names its honest tracked source path")
	var source_ids: Array[String] = []
	_collect_source_ids(bundle, source_ids)
	assert_true(not source_ids.is_empty(), "local authoring contains durable source identities")
	var unique_ids := {}
	var local_uuid := RegEx.create_from_string("^local:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")
	for source_id: String in source_ids:
		assert_true(local_uuid.search(source_id) != null, "source identity is a durable local UUID: %s" % source_id)
		assert_false(unique_ids.has(source_id), "source identity is unique: %s" % source_id)
		unique_ids[source_id] = true

func _assert_published_semantics(bundle: Dictionary, output_dir: String) -> void:
	var comments: Array[String] = []
	_collect_comment_texts(bundle, comments)
	assert_true(not comments.is_empty(), "tracked authoring contains native-comment context")
	var generated_text := ""
	for filename: String in ["foundation_inspect.json", "events.json", "source_map.json"]:
		generated_text += FileAccess.get_file_as_string(output_dir.path_join(filename))
	for comment: String in comments:
		assert_false(generated_text.contains(comment), "current fixture comments never enter generated artifacts")
	_assert_single_important_choice(_read_dictionary(output_dir.path_join("foundation_inspect.json")))
	_assert_source_map_is_one_to_one(bundle, _read_dictionary(output_dir.path_join("source_map.json")))
	var event_index := EventIndex.load_path(output_dir.path_join("events.json"))
	assert_true(event_index.is_valid(), "published event index loads")
	if not event_index.is_valid():
		return
	var previous_mode: int = GameSession.current_mode
	var previous_state: NarrativeState = GameSession.narrative_state
	var inspect_route: Dictionary = await _play_default_route(output_dir, event_index, "default.inspect.", true)
	var hesitate_route: Dictionary = await _play_default_route(output_dir, event_index, "default.hesitate.", false)
	assert_false(String(inspect_route.get("rejoin_node", "")).is_empty(), "inspect branch reaches the shared rejoin flow")
	assert_eq(hesitate_route.get("rejoin_node"), inspect_route.get("rejoin_node"), "hesitate and inspect branches independently reach the same rejoin node")
	var inspect_state := inspect_route.get("state") as NarrativeState
	if inspect_state != null:
		var resolver := EventResolver.new()
		resolver.event_index = event_index
		var specific: Dictionary = resolver.resolve(&"foundation.inspect", &"mirror.inspect", inspect_state)
		assert_true(specific.get("ok", false), "updated state resolves another event")
		assert_eq(specific.get("event_key"), &"seen", "specific event wins after the choice result")
	GameSession.narrative_state = previous_state
	GameSession.change_mode(previous_mode)

func _play_default_route(output_dir: String, event_index: RefCounted, first_target_prefix: String, inspect_route: bool) -> Dictionary:
	var state := NarrativeState.new()
	var resolver := EventResolver.new()
	resolver.event_index = event_index
	var fallback: Dictionary = resolver.resolve(&"foundation.inspect", &"mirror.inspect", state)
	assert_true(fallback.get("ok", false), "fresh state resolves the fallback event")
	assert_eq(fallback.get("event_key"), &"default", "fresh state selects the final fallback")
	if not fallback.get("ok", false):
		return {"state":state, "rejoin_node":&""}
	GameSession.change_mode(GameMode.Value.EXPLORATION)
	GameSession.narrative_state = state
	var service := DialogueService.new()
	var loader := DialogueGraphLoader.new()
	loader.base_directory = output_dir
	service.graph_loader = loader
	service.narrative_state = state
	service.game_session = GameSession
	var choice_count := [0]
	var stable_count := [0]
	service.choices_requested.connect(func(_items: Array[Dictionary]) -> void: choice_count[0] += 1)
	service.stable_checkpoint_reached.connect(func(kind: StringName, _checkpoint: Dictionary) -> void:
		if kind == &"important_choice":
			stable_count[0] += 1
	)
	get_tree().root.add_child(service)
	assert_eq(service.start_dialogue(fallback["scene_key"], fallback["node_id"]), OK, "fallback starts at its resolved entry")
	assert_eq(_current_node_type(service), "line", "fallback starts on a semantic line boundary")
	var first_line_node := service.current_node_id
	service.advance()
	assert_eq(_current_node_type(service), "line", "fallback contains a second line before choosing")
	assert_true(service.current_node_id != first_line_node, "consecutive authored lines compile to distinct nodes")
	service.advance()
	assert_eq(_current_node_type(service), "choice", "fallback reaches its first semantic choice")
	assert_eq(choice_count[0], 1, "first choice boundary is emitted once")
	var first_choice_index := _choice_index_for_target(service, first_target_prefix)
	assert_true(first_choice_index >= 0, "first choice exposes the expected semantic destination")
	if first_choice_index < 0:
		return await _cleanup_route(service, state, &"")
	assert_eq(service.choose(first_choice_index), OK, "selected first branch starts")
	assert_eq(stable_count[0], 1, "generated important choice emits one stable checkpoint")
	var rejoin_node := &""
	if inspect_route:
		assert_true(state.get_flag(&"mirror_seen"), "inspect choice applies its catalog effect before the destination")
		assert_true(String(service.current_node_id).begins_with("default.inspect."), "inspect choice enters its retained flow destination")
		assert_eq(_current_node_type(service), "line", "inspect branch begins with a later line")
		var later_line_node := service.current_node_id
		service.advance()
		assert_eq(_current_node_type(service), "line", "inspect branch contains multiple later lines")
		assert_true(service.current_node_id != later_line_node, "later branch lines remain distinct")
		service.advance()
		assert_eq(_current_node_type(service), "choice", "inspect branch reaches a second choice")
		assert_eq(choice_count[0], 2, "second choice boundary is emitted independently")
		assert_true(_choice_index_for_target(service, "default.start.") >= 0, "second choice retains its return-to-previous-flow route")
		var rejoin_index := _choice_index_for_target(service, "default.rejoin.")
		assert_true(rejoin_index >= 0, "second choice exposes the shared rejoin destination")
		if rejoin_index >= 0:
			assert_eq(service.choose(rejoin_index), OK, "inspect branch selects its rejoin route")
			assert_eq(stable_count[0], 1, "ordinary later choice emits no additional stable checkpoint")
	else:
		assert_false(state.get_flag(&"mirror_seen"), "hesitate branch does not apply the inspect choice effect")
		assert_true(String(service.current_node_id).begins_with("default.hesitate."), "hesitate choice enters its retained flow destination")
		assert_eq(_current_node_type(service), "line", "hesitate branch exposes its line boundary")
		service.advance()
	assert_eq(_current_node_type(service), "line", "selected branch reaches the shared rejoin line")
	assert_true(String(service.current_node_id).begins_with("default.rejoin."), "selected branch enters the retained rejoin flow")
	rejoin_node = service.current_node_id
	service.advance()
	assert_eq(service.current_graph, null, "shared rejoin flow reaches its authored end")
	return await _cleanup_route(service, state, rejoin_node)

func _cleanup_route(service: DialogueService, state: NarrativeState, rejoin_node: StringName) -> Dictionary:
	if service.current_graph != null:
		service.abort_dialogue(&"test_cleanup")
	service.queue_free()
	await get_tree().process_frame
	return {"state":state, "rejoin_node":rejoin_node}

func _choice_index_for_target(service: DialogueService, target_prefix: String) -> int:
	if service.current_graph == null or _current_node_type(service) != "choice":
		return -1
	var node := service.current_graph.get_node(service.current_node_id)
	var items_value: Variant = node.get("items", [])
	if typeof(items_value) != TYPE_ARRAY:
		return -1
	var items: Array = items_value
	for index: int in items.size():
		var item_value: Variant = items[index]
		if typeof(item_value) == TYPE_DICTIONARY and String((item_value as Dictionary).get("next", "")).begins_with(target_prefix):
			return index
	return -1

func _current_node_type(service: DialogueService) -> String:
	if service.current_graph == null:
		return ""
	return String(service.current_graph.get_node(service.current_node_id).get("type", ""))

func _assert_source_map_is_one_to_one(bundle: Dictionary, source_map: Dictionary) -> void:
	var source_ids: Array[String] = []
	_collect_source_ids(bundle, source_ids)
	var mapped_counts := {}
	var sources_value: Variant = source_map.get("sources", [])
	assert_true(typeof(sources_value) == TYPE_ARRAY, "source map exposes its source entries")
	if typeof(sources_value) != TYPE_ARRAY:
		return
	for source_value: Variant in sources_value:
		if typeof(source_value) != TYPE_DICTIONARY:
			continue
		var source: Dictionary = source_value
		var source_id := String(source.get("source_id", ""))
		mapped_counts[source_id] = int(mapped_counts.get(source_id, 0)) + 1
		assert_eq(source.get("source_url"), AUTHORING_FILE, "source map retains honest local provenance")
	assert_eq(mapped_counts.size(), source_ids.size(), "source map has one entry for every authoring identity and no extras")
	for source_id: String in source_ids:
		assert_eq(mapped_counts.get(source_id, 0), 1, "authoring identity maps exactly once: %s" % source_id)

func _assert_single_important_choice(graph: Dictionary) -> void:
	var important_count := 0
	for node_value: Variant in graph.get("nodes", {}).values():
		if typeof(node_value) != TYPE_DICTIONARY:
			continue
		var node: Dictionary = node_value
		if String(node.get("type", "")) != "choice" or node.get("autosave", false) != true:
			continue
		important_count += 1
		for item_value: Variant in node.get("items", []):
			assert_false((item_value as Dictionary).has("autosave"), "important metadata stays on the choice block instead of its items")
	assert_eq(important_count, 1, "tracked authoring publishes exactly its first mirror choice as important")

func _collect_source_ids(value: Variant, result: Array[String]) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		var dictionary: Dictionary = value
		if dictionary.has("source_id"):
			result.append(String(dictionary["source_id"]))
		for child: Variant in dictionary.values():
			_collect_source_ids(child, result)
	elif typeof(value) == TYPE_ARRAY:
		for child: Variant in value:
			_collect_source_ids(child, result)

func _collect_comment_texts(value: Variant, result: Array[String]) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		var dictionary: Dictionary = value
		var comments_value: Variant = dictionary.get("comments", [])
		if typeof(comments_value) == TYPE_ARRAY:
			for comment_value: Variant in comments_value:
				if typeof(comment_value) == TYPE_DICTIONARY:
					var text := String((comment_value as Dictionary).get("text", ""))
					if not text.is_empty():
						result.append(text)
		for child: Variant in dictionary.values():
			_collect_comment_texts(child, result)
	elif typeof(value) == TYPE_ARRAY:
		for child: Variant in value:
			_collect_comment_texts(child, result)

func _read_dictionary(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true(typeof(parsed) == TYPE_DICTIONARY, "JSON dictionary loads: %s" % path)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

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
