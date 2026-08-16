extends "res://tests/support/test_case.gd"

const REGISTRY_SCRIPT_PATH := "res://data/characters/character_registry.gd"
const REGISTRY_RESOURCE_PATH := "res://data/characters/character_registry.tres"
const LOADER_PATH := "res://game/narrative/dialogue/dialogue_graph_loader.gd"
const VIEW_SCENE_PATH := "res://ui/dialogue/dialogue_view.tscn"
const COMPILER_PATH := "res://tools/dialogue_import/document_dialogue_compiler.gd"
const FIXTURE_FACTORY_PATH := "res://tests/fixtures/dialogue_import/dialogue_bundle_fixture_factory.gd"

func run() -> void:
	assert_true(ResourceLoader.exists(REGISTRY_SCRIPT_PATH, "Script"), "shared character registry script exists")
	assert_true(ResourceLoader.exists(REGISTRY_RESOURCE_PATH), "shared production character registry resource exists")
	if not ResourceLoader.exists(REGISTRY_SCRIPT_PATH, "Script") or not ResourceLoader.exists(REGISTRY_RESOURCE_PATH):
		return
	var registry_script: Script = load(REGISTRY_SCRIPT_PATH)
	var production_registry: Resource = load(REGISTRY_RESOURCE_PATH)
	assert_not_null(registry_script, "shared character registry script loads")
	assert_not_null(production_registry, "shared production character registry loads")
	if registry_script == null or production_registry == null:
		return
	assert_eq(production_registry.call("character_keys"), [&"jellyppo", &"retti"], "production registry is the single sorted retti/jellyppo catalog")
	var injected_registry: Resource = _injected_registry(registry_script)
	assert_not_null(injected_registry, "test registry can be injected")
	if injected_registry == null:
		return
	var injected_definitions: Array = injected_registry.get("definitions")
	assert_eq(injected_definitions.size(), 1, "injected registry retains one definition")
	if not injected_definitions.is_empty():
		assert_eq(injected_definitions[0].get("character_key"), &"test_hero", "injected definition retains its character key")
	assert_not_null(injected_registry.call("get_definition", &"test_hero"), "injected registry resolves its definition")
	assert_eq(injected_registry.call("character_keys"), [&"test_hero"], "injected registry exposes its test character")
	assert_true(injected_registry.call("has_expression", &"test_hero", &"neutral"), "injected registry exposes its test expression")
	await _test_loader_uses_registry(production_registry, injected_registry)
	await _test_view_uses_registry(production_registry, injected_registry)
	_test_compiler_validates_character_registry(production_registry, injected_registry)

func _test_loader_uses_registry(production_registry: Resource, injected_registry: Resource) -> void:
	var loader_script: Script = load(LOADER_PATH)
	var loader: Variant = loader_script.new()
	assert_true(_has_property(loader, "character_registry"), "loader exposes registry injection")
	assert_false(_has_property(loader, "character_keys"), "loader has no independent character-key list")
	if not _has_property(loader, "character_registry"):
		return
	assert_eq(loader.get("character_registry"), production_registry, "loader defaults to the shared production registry")
	var root := "user://test-output/character-registry-%s" % Time.get_ticks_usec()
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root))
	assert_eq(directory_error, OK, "registry loader fixture directory is created")
	if directory_error != OK:
		return
	var graph := {"schema_version":1, "scene_key":"registry.test", "entry_node":"line1", "nodes":{"line1":{"type":"line", "speaker":"test_hero", "expression":"neutral", "text":"hello", "next":"end1"}, "end1":{"type":"end"}}}
	var path := root.path_join("registry_test.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file, "registry loader fixture opens")
	if file != null:
		file.store_string(JSON.stringify(graph))
		file.close()
	loader.set("base_directory", root)
	loader.set("character_registry", injected_registry)
	assert_not_null(loader.call("load_scene", &"registry.test"), "loader validates with the injected registry")
	var default_loader: Variant = loader_script.new()
	default_loader.set("base_directory", root)
	assert_eq(default_loader.call("load_scene", &"registry.test"), null, "loader rejects a speaker absent from the shared production registry")
	_remove_exact_tree(root)

func _test_view_uses_registry(production_registry: Resource, injected_registry: Resource) -> void:
	var packed := load(VIEW_SCENE_PATH) as PackedScene
	var view: Control = packed.instantiate()
	assert_true(_has_property(view, "character_registry"), "dialogue view exposes registry injection")
	assert_false(_has_property(view, "character_definitions"), "dialogue view has no independent character-definition list")
	if not _has_property(view, "character_registry"):
		view.free()
		return
	assert_eq(view.get("character_registry"), production_registry, "dialogue view defaults to the shared production registry")
	view.set("character_registry", injected_registry)
	add_child(view)
	await get_tree().process_frame
	view.call("show_line", &"test_hero", &"neutral", "hello")
	assert_eq((view.get_node("Panel/Margin/Layout/Content/NameLabel") as Label).text, "테스트 영웅", "view resolves names through an injected registry")
	assert_true(view.visible, "view renders a line accepted by the injected registry")
	view.queue_free()
	await get_tree().process_frame

func _test_compiler_validates_character_registry(production_registry: Resource, injected_registry: Resource) -> void:
	var compiler: Script = load(COMPILER_PATH)
	var compile_method := _method(compiler, "compile_bundles")
	assert_true(compile_method.get("args", []).size() >= 3, "document compiler exposes registry injection")
	if compile_method.get("args", []).size() < 3:
		return
	var fixture_factory: Script = load(FIXTURE_FACTORY_PATH)
	var injected_bundle: Dictionary = _importable_bundle(fixture_factory)
	_replace_line_identity(injected_bundle, "test_hero", "neutral")
	var injected_bundles: Array[Dictionary] = [injected_bundle]
	var injected_result: Dictionary = compiler.call("compile_bundles", injected_bundles, null, injected_registry)
	assert_true(injected_result["ok"], "document compiler validates against the injected local registry: %s" % [str(injected_result.get("issues", []))])
	var unknown_result: Dictionary = compiler.call("compile_bundles", injected_bundles, null, production_registry)
	assert_false(unknown_result["ok"], "authoring character absent from the local registry blocks publication")
	assert_true(_has_issue(unknown_result["issues"], "unknown_character", injected_bundle["source_url"]), "unknown authoring character mismatch is source-linked")
	var unknown_expression_bundle: Dictionary = _importable_bundle(fixture_factory)
	_replace_line_identity(unknown_expression_bundle, "retti", "missing")
	var unknown_expression_bundles: Array[Dictionary] = [unknown_expression_bundle]
	var unknown_expression_result: Dictionary = compiler.call("compile_bundles", unknown_expression_bundles, null, production_registry)
	assert_false(unknown_expression_result["ok"], "authoring expression absent locally blocks publication")
	assert_true(_has_issue(unknown_expression_result["issues"], "unknown_expression", unknown_expression_bundle["source_url"]), "unknown authoring expression mismatch is source-linked")
	var production_bundle: Dictionary = _importable_bundle(fixture_factory)
	var production_bundles: Array[Dictionary] = [production_bundle]
	var production_result: Dictionary = compiler.call("compile_bundles", production_bundles, null, production_registry)
	assert_true(production_result["ok"], "shared production registry accepts the tracked authoring characters")

func _importable_bundle(fixture_factory: Script) -> Dictionary:
	var bundle: Dictionary = fixture_factory.call("valid_bundle")
	var inspect_blocks: Array = bundle["triggers"][0]["events"][1]["flows"][1]["blocks"]
	inspect_blocks.remove_at(1)
	return bundle

func _replace_line_identity(value: Variant, character_key: String, expression: String) -> void:
	if typeof(value) == TYPE_DICTIONARY:
		var dictionary: Dictionary = value
		if String(dictionary.get("type", "")) == "line":
			dictionary["speaker"] = character_key
			dictionary["expression"] = expression
		for child: Variant in dictionary.values():
			_replace_line_identity(child, character_key, expression)
	elif typeof(value) == TYPE_ARRAY:
		for child: Variant in value:
			_replace_line_identity(child, character_key, expression)

func _injected_registry(registry_script: Script) -> Resource:
	var definition_script: Script = load("res://data/characters/character_definition.gd")
	var definition: Resource = definition_script.new()
	definition.set("character_key", &"test_hero")
	definition.set("display_name", "테스트 영웅")
	definition.set("default_expression", &"neutral")
	definition.set("portraits", {&"neutral":null, &"uneasy":null})
	var registry: Resource = registry_script.new()
	var definitions: Array[Resource] = [definition]
	registry.set("definitions", definitions)
	return registry

func _has_property(object: Object, property_name: String) -> bool:
	for property: Dictionary in object.get_property_list():
		if String(property.get("name", "")) == property_name:
			return true
	return false

func _method(script: Script, method_name: String) -> Dictionary:
	for method: Dictionary in script.get_script_method_list():
		if String(method.get("name", "")) == method_name:
			return method
	return {}

func _has_issue(issues: Variant, code: String, source_url: String) -> bool:
	if typeof(issues) != TYPE_ARRAY:
		return false
	for issue_value: Variant in issues:
		if typeof(issue_value) == TYPE_DICTIONARY and issue_value.get("code", "") == code and issue_value.get("source_url", "") == source_url:
			return true
	return false

func _remove_exact_tree(path: String) -> void:
	if not path.begins_with("user://test-output/character-registry-"):
		return
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for filename: String in directory.get_files():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path.path_join(filename)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
