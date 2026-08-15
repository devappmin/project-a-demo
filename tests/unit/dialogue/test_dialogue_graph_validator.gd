extends "res://tests/support/test_case.gd"

const VALIDATOR_PATH := "res://game/narrative/dialogue/dialogue_graph_validator.gd"
const GRAPH_PATH := "res://game/narrative/dialogue/dialogue_graph.gd"
const LOADER_PATH := "res://game/narrative/dialogue/dialogue_graph_loader.gd"

func run() -> void:
	var validator: Variant = load(VALIDATOR_PATH)
	assert_not_null(validator, "dialogue graph validator script exists")
	if validator == null:
		return
	var graph_script: Variant = load(GRAPH_PATH)
	var loader_script: Variant = load(LOADER_PATH)
	assert_not_null(graph_script, "dialogue graph script exists")
	assert_not_null(loader_script, "dialogue graph loader script exists")
	if graph_script == null or loader_script == null:
		return
	_validate_fixture_contract(validator)
	_validate_schema_and_node_contract(validator)
	_validate_rule_shapes(validator)
	_validate_reachable_cycles(validator)
	_validate_automatic_path_limit(validator)
	_validate_graph_immutability(graph_script)
	_validate_loader(loader_script)
	_validate_loader_control_flow_contract(loader_script)

func _validate_fixture_contract(validator: Variant) -> void:
	var valid: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/dialogues/valid_branch.json"))
	assert_eq(_validate(validator, valid, [&"retti", &"jellyppo"]), [], "valid graph has no issues")
	var broken: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/dialogues/dangling_target.json"))
	var issues: Array = _validate(validator, broken, [&"retti"])
	assert_true(not issues.is_empty(), "broken fixture produces at least one issue")
	if issues.is_empty():
		return
	assert_eq(issues[0]["code"], "dangling_target", "broken target is reported first")
	assert_eq(issues[0]["node_id"], "line_1", "broken target identifies its node")
	for issue: Dictionary in issues:
		var public_keys: Array = issue.keys()
		public_keys.sort()
		assert_eq(public_keys, ["code", "message", "node_id", "scene_key", "severity"], "every issue has the deterministic public shape")
	assert_eq(issues, _validate(validator, broken, [&"retti"]), "validation issue order and content are deterministic")

func _validate_schema_and_node_contract(validator: Variant) -> void:
	var invalid_schema := {
		"schema_version": 2,
		"scene_key": "",
		"entry_node": "missing",
		"nodes": {
			"": {"type":"end"},
			"bad": {"type":"script", "next":"missing"},
			"line": {"type":"line", "speaker":"ghost", "expression":"", "text":7}
		}
	}
	var issues: Array = _validate(validator, invalid_schema, [&"retti"])
	assert_true(_has_code(issues, "invalid_schema_version"), "unsupported schema versions are rejected")
	assert_true(_has_code(issues, "invalid_scene_key"), "empty scene keys are rejected")
	assert_true(_has_code(issues, "invalid_node_id"), "empty node ids are rejected")
	assert_true(_has_code(issues, "missing_entry_node"), "missing entry references are rejected")
	assert_true(_has_code_at(issues, "unsupported_node_type", "bad"), "unsupported node types are rejected")
	assert_true(_has_code_at(issues, "unknown_character", "line"), "unknown character keys are rejected")
	assert_true(_has_code_at(issues, "invalid_expression", "line"), "expressions must be nonempty strings")
	assert_true(_has_code_at(issues, "invalid_field", "line"), "required fields have validated types")
	var duplicate_characters: Array[StringName] = [&"retti", &"retti", &""]
	var valid: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/dialogues/valid_branch.json"))
	var character_issues: Array = _validate(validator, valid, duplicate_characters)
	assert_true(_has_code(character_issues, "invalid_character_key"), "character catalogs require unique nonempty keys")

func _validate_rule_shapes(validator: Variant) -> void:
	var data := _minimal_graph()
	data["nodes"] = {
		"choice": {"type":"choice", "items":[
			{"text":"bad condition", "conditions":[{"kind":"stat", "key":"score", "operator":"contains", "value":"1"}], "effects":[], "next":"end"},
			{"text":"bad effect", "conditions":[], "effects":[{"kind":"call", "key":"unsafe", "value":"run()"}], "next":"end"}
		]},
		"effect": {"type":"effect", "effects":[{"kind":"inventory_add", "key":"coin", "value":-1}], "next":"end"},
		"command": {"type":"command", "command":[], "next":"end"},
		"jump": {"type":"jump", "next":"end"},
		"end": {"type":"end"}
	}
	data["entry_node"] = "choice"
	var issues: Array = _validate(validator, data, [&"retti"])
	assert_true(_has_code_at(issues, "invalid_condition", "choice"), "invalid condition shapes are rejected")
	assert_true(_has_code_at(issues, "invalid_effect", "choice"), "unsupported effect kinds are rejected")
	assert_true(_has_code_at(issues, "invalid_effect", "effect"), "effect node values are validated")
	assert_true(_has_code_at(issues, "invalid_field", "command"), "command nodes require a dictionary payload")
	var runtime_mismatch := _minimal_graph()
	runtime_mismatch["entry_node"] = "choice"
	runtime_mismatch["nodes"] = {
		"choice": {"type":"choice", "items":[{
			"text":"runtime type mismatch",
			"conditions":[
				{"kind":&"flag", "key":"flag_key", "operator":"eq", "value":true},
				{"kind":"flag", "key":&"flag_key", "operator":"eq", "value":true},
				{"kind":"flag", "key":"flag_key", "operator":&"eq", "value":true},
				{"kind":"quest", "key":"quest_key", "operator":"eq", "value":&"started"}
			],
			"effects":[
				{"kind":&"flag_set", "key":"flag_key", "value":true},
				{"kind":"flag_set", "key":&"flag_key", "value":true},
				{"kind":"quest_set", "key":"quest_key", "value":&"started"}
			],
			"next":"end"
		}]},
		"end": {"type":"end"}
	}
	var mismatch_issues: Array = _validate(validator, runtime_mismatch, [&"retti"])
	assert_eq(_count_code(mismatch_issues, "invalid_condition"), 4, "validator rejects every condition StringName that runtime rejects")
	assert_eq(_count_code(mismatch_issues, "invalid_effect"), 3, "validator rejects every effect StringName that runtime rejects")

func _validate_reachable_cycles(validator: Variant) -> void:
	var trapped := _minimal_graph()
	trapped["entry_node"] = "loop_a"
	trapped["nodes"] = {
		"loop_a": {"type":"jump", "next":"loop_b"},
		"loop_b": {"type":"jump", "next":"loop_a"}
	}
	assert_true(_has_code(_validate(validator, trapped, [&"retti"]), "cycle_without_exit"), "reachable cycles without an exit are rejected")
	var escapable := _minimal_graph()
	escapable["entry_node"] = "loop"
	escapable["nodes"] = {
		"loop": {"type":"choice", "items":[
			{"text":"again", "conditions":[], "effects":[], "next":"loop"},
			{"text":"leave", "conditions":[], "effects":[], "next":"end"}
		]},
		"end": {"type":"end"}
	}
	assert_false(_has_code(_validate(validator, escapable, [&"retti"]), "cycle_without_exit"), "a reachable cycle with an explicit exit is valid")
	var unreachable := _minimal_graph()
	unreachable["nodes"]["orphan"] = {"type":"jump", "next":"orphan"}
	assert_true(_has_code_at(_validate(validator, unreachable, [&"retti"]), "cycle_without_exit", "orphan"), "orphan cycles are rejected because public entry overrides can reach them")

func _validate_automatic_path_limit(validator: Variant) -> void:
	var allowed := _automatic_graph("automatic.allowed", 256)
	assert_false(_has_code(_validate(validator, allowed, [&"retti"]), "automatic_path_too_long"), "256 automatic nodes may reach a stable boundary")
	var rejected := _automatic_graph("automatic.rejected", 257)
	assert_true(_has_code_at(_validate(validator, rejected, [&"retti"]), "automatic_path_too_long", "jump_0"), "257 automatic nodes are rejected from their possible entry override")

func _validate_graph_immutability(graph_script: Variant) -> void:
	var source_value: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/dialogues/valid_branch.json"))
	assert_true(typeof(source_value) == TYPE_DICTIONARY, "immutable graph fixture parses as a dictionary")
	if typeof(source_value) != TYPE_DICTIONARY:
		return
	var source: Dictionary = source_value
	var graph: Variant = graph_script.from_dictionary(source)
	assert_not_null(graph, "immutable graph can be constructed")
	if graph == null:
		return
	source["nodes"]["line_1"]["text"] = "mutated source"
	var node: Dictionary = graph.get_node(&"line_1")
	assert_eq(node.get("text", ""), "낯선 거울이다.", "graph deep-copies its source")
	node["text"] = "mutated getter"
	var public_nodes: Dictionary = graph.nodes
	var public_line_value: Variant = public_nodes.get("line_1", {})
	assert_true(typeof(public_line_value) == TYPE_DICTIONARY, "graph node property contains the fixture line")
	if typeof(public_line_value) == TYPE_DICTIONARY:
		public_line_value["text"] = "mutated property"
	assert_eq(graph.get_node(&"line_1").get("text", ""), "낯선 거울이다.", "graph never exposes mutable node storage")
	graph.scene_key = &"mutated"
	graph.entry_node = &"mutated"
	assert_eq(graph.scene_key, &"valid.branch", "graph scene keys are immutable")
	assert_eq(graph.entry_node, &"line_1", "graph entry nodes are immutable")
	assert_eq(graph.get_node(&"missing"), {}, "missing graph nodes return an empty dictionary")

func _validate_loader(loader_script: Variant) -> void:
	var loader: Variant = loader_script.new()
	assert_eq(loader.base_directory, "res://data/generated/dialogues", "loader has the generated dialogue default")
	loader.base_directory = "res://tests/fixtures/dialogues"
	var loader_characters: Array[StringName] = [&"retti", &"jellyppo"]
	loader.character_keys = loader_characters
	var graph: Variant = loader.load_scene(&"valid.branch")
	assert_not_null(graph, "loader resolves dotted scene keys below its base directory")
	if graph != null:
		assert_eq(graph.scene_key, &"valid.branch", "loaded graph retains the requested scene key")
	var unicode_graph: Variant = loader.load_scene(StringName(".장면."))
	assert_not_null(unicode_graph, "loader accepts confined Unicode scene keys with safe edge dots")
	if unicode_graph != null:
		assert_eq(unicode_graph.scene_key, StringName(".장면."), "loader preserves the Unicode scene key while mapping dots in its filename")
	assert_eq(loader.load_scene(&"dangling.target"), null, "loader never returns a graph that failed validation")
	assert_eq(loader.last_failure.get("code", ""), "validation_failed", "loader reports validation failure")
	assert_eq(loader.load_scene(&"malformed"), null, "loader rejects malformed JSON")
	assert_eq(loader.last_failure.get("code", ""), "parse_failed", "loader reports parse failure")
	assert_eq(loader.load_scene(&"mismatched"), null, "loader rejects a payload for a different requested scene")
	assert_eq(loader.last_failure.get("code", ""), "validation_failed", "loader reports scene identity validation failure")
	assert_eq(loader.load_scene(&"missing"), null, "loader rejects missing scene files")
	assert_eq(loader.last_failure.get("code", ""), "load_failed", "loader reports load failure")
	assert_eq(loader.load_scene(StringName("../valid.branch")), null, "loader rejects path separators in scene keys")
	assert_eq(loader.last_failure.get("code", ""), "unsafe_scene_key", "loader reports unsafe scene keys")
	assert_eq(loader.load_scene(StringName("..\\valid.branch")), null, "loader rejects Windows path separators in scene keys")
	assert_eq(loader.last_failure.get("code", ""), "unsafe_scene_key", "loader reports unsafe Windows scene keys")

func _validate_loader_control_flow_contract(loader_script: Variant) -> void:
	var output_directory := "user://test-output/dialogue-validator-%s" % Time.get_ticks_usec()
	var absolute_directory := ProjectSettings.globalize_path(output_directory)
	assert_eq(DirAccess.make_dir_recursive_absolute(absolute_directory), OK, "loader control-flow fixture directory is created")
	var fixtures: Array[Dictionary] = [
		_automatic_graph("loader.allowed", 256),
		_automatic_graph("loader.rejected", 257),
		{
			"schema_version":1,
			"scene_key":"loader.orphan",
			"entry_node":"end",
			"nodes":{"end":{"type":"end"}, "orphan":{"type":"jump", "next":"orphan"}}
		},
	]
	for fixture: Dictionary in fixtures:
		var scene_key := String(fixture["scene_key"])
		var path := output_directory.path_join(scene_key.replace(".", "_") + ".json")
		var file := FileAccess.open(path, FileAccess.WRITE)
		assert_not_null(file, "loader control-flow fixture opens for %s" % scene_key)
		if file == null:
			continue
		file.store_string(JSON.stringify(fixture))
		file.close()
	var loader: Variant = loader_script.new()
	loader.base_directory = output_directory
	var loader_characters: Array[StringName] = [&"retti"]
	loader.character_keys = loader_characters
	var allowed: Variant = loader.load_scene(&"loader.allowed")
	assert_not_null(allowed, "loader accepts the exact 256 automatic-node boundary")
	assert_eq(loader.load_scene(&"loader.rejected"), null, "loader rejects a 257 automatic-node segment")
	assert_eq(loader.last_failure.get("code", ""), "validation_failed", "long automatic path fails at validation")
	assert_true(_has_code(loader.last_issues, "automatic_path_too_long"), "loader exposes the automatic path issue")
	assert_eq(loader.load_scene(&"loader.orphan"), null, "loader rejects an orphan override cycle")
	assert_true(_has_code(loader.last_issues, "cycle_without_exit"), "loader exposes the orphan cycle issue")
	for fixture: Dictionary in fixtures:
		var scene_key := String(fixture["scene_key"])
		DirAccess.remove_absolute(ProjectSettings.globalize_path(output_directory.path_join(scene_key.replace(".", "_") + ".json")))
	DirAccess.remove_absolute(absolute_directory)

func _minimal_graph() -> Dictionary:
	return {
		"schema_version": 1,
		"scene_key": "minimal",
		"entry_node": "end",
		"nodes": {"end": {"type":"end"}}
	}

func _automatic_graph(scene_key: String, automatic_count: int) -> Dictionary:
	var nodes := {}
	for index: int in automatic_count:
		nodes["jump_%d" % index] = {"type":"jump", "next":"line" if index == automatic_count - 1 else "jump_%d" % (index + 1)}
	nodes["line"] = {"type":"line", "speaker":"retti", "expression":"neutral", "text":"boundary", "next":"end"}
	nodes["end"] = {"type":"end"}
	return {"schema_version":1, "scene_key":scene_key, "entry_node":"jump_0", "nodes":nodes}

func _validate(validator: Variant, data: Dictionary, characters: Array[StringName]) -> Array:
	return validator.validate(data, characters)

func _has_code(issues: Array, code: String) -> bool:
	for issue_value: Variant in issues:
		if typeof(issue_value) == TYPE_DICTIONARY and issue_value.get("code", "") == code:
			return true
	return false

func _count_code(issues: Array, code: String) -> int:
	var count := 0
	for issue_value: Variant in issues:
		if typeof(issue_value) == TYPE_DICTIONARY and issue_value.get("code", "") == code:
			count += 1
	return count

func _has_code_at(issues: Array, code: String, node_id: String) -> bool:
	for issue_value: Variant in issues:
		if typeof(issue_value) == TYPE_DICTIONARY and issue_value.get("code", "") == code and issue_value.get("node_id", "") == node_id:
			return true
	return false
