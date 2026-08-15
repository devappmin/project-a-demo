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
	_validate_graph_immutability(graph_script)
	_validate_loader(loader_script)

func _validate_fixture_contract(validator: Variant) -> void:
	var valid: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/dialogues/valid_branch.json"))
	assert_eq(_validate(validator, valid, [&"retti", &"jellyppo"]), [], "valid graph has no issues")
	var broken: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/dialogues/dangling_target.json"))
	var issues: Array = _validate(validator, broken, [&"retti"])
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
	assert_false(_has_code(_validate(validator, unreachable, [&"retti"]), "cycle_without_exit"), "unreachable cycles do not block the graph")

func _validate_graph_immutability(graph_script: Variant) -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/dialogues/valid_branch.json"))
	var graph: Variant = graph_script.from_dictionary(source)
	source["nodes"]["line_1"]["text"] = "mutated source"
	var node: Dictionary = graph.get_node(&"line_1")
	assert_eq(node["text"], "낯선 거울이다.", "graph deep-copies its source")
	node["text"] = "mutated getter"
	graph.nodes["line_1"]["text"] = "mutated property"
	assert_eq(graph.get_node(&"line_1")["text"], "낯선 거울이다.", "graph never exposes mutable node storage")
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
	assert_eq(graph.scene_key, &"valid.branch", "loaded graph retains the requested scene key")
	var unicode_graph: Variant = loader.load_scene(StringName(".장면."))
	assert_not_null(unicode_graph, "loader accepts confined Unicode scene keys with safe edge dots")
	if unicode_graph != null:
		assert_eq(unicode_graph.scene_key, StringName(".장면."), "loader preserves the Unicode scene key while mapping dots in its filename")
	assert_eq(loader.load_scene(&"dangling.target"), null, "loader never returns a graph that failed validation")
	assert_eq(loader.last_failure["code"], "validation_failed", "loader reports validation failure")
	assert_eq(loader.load_scene(&"malformed"), null, "loader rejects malformed JSON")
	assert_eq(loader.last_failure["code"], "parse_failed", "loader reports parse failure")
	assert_eq(loader.load_scene(&"mismatched"), null, "loader rejects a payload for a different requested scene")
	assert_eq(loader.last_failure.get("code", ""), "validation_failed", "loader reports scene identity validation failure")
	assert_eq(loader.load_scene(&"missing"), null, "loader rejects missing scene files")
	assert_eq(loader.last_failure["code"], "load_failed", "loader reports load failure")
	assert_eq(loader.load_scene(StringName("../valid.branch")), null, "loader rejects path separators in scene keys")
	assert_eq(loader.last_failure["code"], "unsafe_scene_key", "loader reports unsafe scene keys")
	assert_eq(loader.load_scene(StringName("..\\valid.branch")), null, "loader rejects Windows path separators in scene keys")
	assert_eq(loader.last_failure["code"], "unsafe_scene_key", "loader reports unsafe Windows scene keys")

func _minimal_graph() -> Dictionary:
	return {
		"schema_version": 1,
		"scene_key": "minimal",
		"entry_node": "end",
		"nodes": {"end": {"type":"end"}}
	}

func _validate(validator: Variant, data: Dictionary, characters: Array[StringName]) -> Array:
	return validator.validate(data, characters)

func _has_code(issues: Array, code: String) -> bool:
	for issue: Dictionary in issues:
		if issue["code"] == code:
			return true
	return false

func _count_code(issues: Array, code: String) -> int:
	var count := 0
	for issue: Dictionary in issues:
		if issue["code"] == code:
			count += 1
	return count

func _has_code_at(issues: Array, code: String, node_id: String) -> bool:
	for issue: Dictionary in issues:
		if issue["code"] == code and issue["node_id"] == node_id:
			return true
	return false
