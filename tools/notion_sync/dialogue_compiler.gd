@tool
extends RefCounted
class_name DialogueCompiler

const Validator = preload("res://game/narrative/dialogue/dialogue_graph_validator.gd")

static func compile(input: Dictionary) -> Dictionary:
	var issues: Array[Dictionary] = []
	var scenes := _dictionary_array(input.get("scenes"), "scenes", issues)
	var blocks := _dictionary_array(input.get("blocks"), "blocks", issues)
	var characters := _dictionary_array(input.get("characters"), "characters", issues)
	scenes.sort_custom(_scene_less)
	blocks.sort_custom(_block_less)
	characters.sort_custom(_character_less)
	_collect_mapping_errors(scenes, issues)
	_collect_mapping_errors(blocks, issues)
	_collect_mapping_errors(characters, issues)
	if scenes.is_empty():
		issues.append(_issue("error", "empty_source", "", "", "dialogue source must contain at least one scene", {}))
	var character_keys: Array[StringName] = []
	var expression_catalog := {}
	for character: Dictionary in characters:
		var character_key := String(character.get("character_key", ""))
		character_keys.append(StringName(character_key))
		expression_catalog[character_key] = character.get("expressions", []).duplicate(true) if typeof(character.get("expressions")) == TYPE_ARRAY else []
	var invalid_character_sources := _invalid_character_sources(characters)
	var graphs := {}
	var scene_statuses := {}
	var filenames := {}
	for scene: Dictionary in scenes:
		var scene_key := String(scene.get("scene_key", ""))
		var scene_status := String(scene.get("status", ""))
		scene_statuses[scene_key] = scene_status
		if scene_key.strip_edges().is_empty():
			issues.append(_issue("error", "invalid_scene_key", scene_key, "", "scene_key must be a nonblank string", scene))
		if String(scene.get("start_flow", "")).strip_edges().is_empty():
			issues.append(_issue("error", "invalid_start_flow", scene_key, "", "start_flow must be a nonempty flow name", scene))
		if graphs.has(scene_key):
			issues.append(_issue("error", "duplicate_scene_key", scene_key, "", "scene_key must be unique", scene))
			continue
		var filename := scene_filename(scene_key)
		var filename_identity := filename.to_lower()
		if not is_safe_scene_key(scene_key):
			issues.append(_issue("error", "unsafe_scene_filename", scene_key, "", "scene_key cannot produce a safe cross-platform JSON filename", scene))
		if filenames.has(filename_identity):
			issues.append(_issue("error", "duplicate_scene_filename", scene_key, "", "scene_key collides with another generated filename", scene))
		else:
			filenames[filename_identity] = scene_key
		var scene_blocks: Array[Dictionary] = []
		for block: Dictionary in blocks:
			if String(block.get("scene_key", "")) == scene_key:
				scene_blocks.append(block)
		var compiled := _compile_scene(scene, scene_blocks, expression_catalog, issues)
		var graph: Dictionary = compiled["graph"]
		graphs[scene_key] = graph
		var validator_issues: Array[Dictionary] = Validator.validate(graph, character_keys)
		var invalid_character_index := 0
		for validator_issue: Dictionary in validator_issues:
			var source: Dictionary
			if String(validator_issue.get("code", "")) == "invalid_character_key" and invalid_character_index < invalid_character_sources.size():
				source = invalid_character_sources[invalid_character_index]
				invalid_character_index += 1
			else:
				source = _validator_issue_source(validator_issue, compiled, scene)
			var linked_issue := validator_issue.duplicate(true)
			linked_issue["notion_page_id"] = String(source.get("notion_page_id", ""))
			linked_issue["source_url"] = String(source.get("source_url", ""))
			issues.append(linked_issue)
	for block: Dictionary in blocks:
		var block_scene_key := String(block.get("scene_key", ""))
		if not scene_statuses.has(block_scene_key):
			issues.append(_issue("error", "unknown_scene", block_scene_key, _node_id(block), "block references an unknown scene", block))
	var manifest := _manifest(graphs, scenes, blocks, characters)
	var ok := true
	for issue: Dictionary in issues:
		var severity := String(issue.get("severity", "error"))
		if severity == "error" or (severity == "warning" and String(scene_statuses.get(String(issue.get("scene_key", "")), "")) == "Final"):
			ok = false
	return {"ok":ok, "graphs":graphs, "issues":issues, "manifest":manifest}

static func scene_filename(scene_key: String) -> String:
	return scene_key.replace(".", "_") + ".json"

static func is_safe_scene_key(scene_key: String) -> bool:
	if scene_key.is_empty() or scene_key != scene_key.strip_edges():
		return false
	for forbidden: String in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
		if scene_key.contains(forbidden):
			return false
	for index: int in scene_key.length():
		var codepoint := scene_key.unicode_at(index)
		if codepoint < 32 or codepoint == 127:
			return false
	var filename := scene_filename(scene_key)
	if filename.to_lower() == "manifest.json":
		return false
	var basename := filename.get_basename().to_upper()
	if basename in ["CON", "PRN", "AUX", "NUL"]:
		return false
	for prefix: String in ["COM", "LPT"]:
		for suffix: int in range(1, 10):
			if basename == prefix + str(suffix):
				return false
	return true

static func stable_json(data: Variant) -> String:
	return JSON.stringify(data, "\t", true, true)

static func _compile_scene(scene: Dictionary, blocks: Array[Dictionary], expression_catalog: Dictionary, issues: Array[Dictionary]) -> Dictionary:
	blocks.sort_custom(_block_less)
	var flow_blocks := {}
	var flows: Array[String] = []
	for block: Dictionary in blocks:
		var flow := String(block.get("flow", ""))
		if flow.strip_edges().is_empty():
			issues.append(_issue("error", "invalid_flow", String(block.get("scene_key", "")), _node_id(block), "block flow must be a nonempty name", block))
		if not flow_blocks.has(flow):
			flow_blocks[flow] = []
			flows.append(flow)
		var members: Array = flow_blocks[flow]
		members.append(block)
	flows.sort()
	var flow_units := {}
	var flow_entries := {}
	var node_sources := {}
	var choice_sources := {}
	for flow: String in flows:
		var units: Array[Dictionary] = []
		var members: Array = flow_blocks[flow]
		var index := 0
		while index < members.size():
			var block: Dictionary = members[index]
			var unit_blocks: Array[Dictionary] = [block]
			if String(block.get("type", "")) == "choice":
				index += 1
				while index < members.size() and String(members[index].get("type", "")) == "choice":
					unit_blocks.append(members[index])
					index += 1
			else:
				index += 1
			var node_id := _node_id(block)
			units.append({"node_id":node_id, "blocks":unit_blocks})
			node_sources[node_id] = block
			if String(block.get("type", "")) == "choice":
				choice_sources[node_id] = unit_blocks.duplicate()
		if not units.is_empty():
			flow_entries[flow] = String(units[0]["node_id"])
		flow_units[flow] = units
	var nodes := {}
	for flow: String in flows:
		var units: Array = flow_units[flow]
		for unit_index: int in units.size():
			var unit: Dictionary = units[unit_index]
			var unit_blocks: Array = unit["blocks"]
			var block: Dictionary = unit_blocks[0]
			var node_id := String(unit["node_id"])
			if nodes.has(node_id):
				issues.append(_issue("error", "duplicate_node_id", String(scene.get("scene_key", "")), node_id, "compiled node IDs must be unique", block))
				continue
			var fallthrough := String(units[unit_index + 1]["node_id"]) if unit_index + 1 < units.size() else ""
			_validate_targets(unit_blocks, fallthrough, flow_entries, issues)
			nodes[node_id] = _compile_node(block, unit_blocks, fallthrough, flow_entries)
			if String(block.get("type", "")) == "line":
				_validate_expression(block, expression_catalog, issues)
	var scene_key := String(scene.get("scene_key", ""))
	var start_flow := String(scene.get("start_flow", ""))
	var entry_node := String(flow_entries.get(start_flow, "__missing_flow__" + start_flow))
	return {
		"graph":{"schema_version":1, "scene_key":scene_key, "entry_node":entry_node, "nodes":nodes},
		"node_sources":node_sources,
		"choice_sources":choice_sources
	}

static func _validate_targets(unit_blocks: Array, fallthrough: String, flow_entries: Dictionary, issues: Array[Dictionary]) -> void:
	for block_value: Variant in unit_blocks:
		var block: Dictionary = block_value
		if String(block.get("type", "")) == "end":
			continue
		var target_flow := String(block.get("target_flow", "")).strip_edges()
		if target_flow.is_empty() and fallthrough.is_empty():
			issues.append(_issue("error", "missing_target_flow", String(block.get("scene_key", "")), _node_id(block), "a terminal non-end block requires target_flow", block))
		elif not target_flow.is_empty() and not flow_entries.has(target_flow):
			issues.append(_issue("error", "unknown_target_flow", String(block.get("scene_key", "")), _node_id(block), "target_flow does not name a compiled flow", block))

static func _compile_node(block: Dictionary, unit_blocks: Array, fallthrough: String, flow_entries: Dictionary) -> Dictionary:
	var block_type := String(block.get("type", ""))
	match block_type:
		"line":
			return {"type":"line", "speaker":String(block.get("speaker", "")), "expression":String(block.get("expression", "")), "text":String(block.get("text", "")), "next":_target_node(block, fallthrough, flow_entries)}
		"choice":
			var items: Array[Dictionary] = []
			for choice_value: Variant in unit_blocks:
				var choice: Dictionary = choice_value
				items.append({"text":String(choice.get("text", "")), "conditions":_array_copy(choice.get("conditions")), "effects":_array_copy(choice.get("effects")), "next":_target_node(choice, fallthrough, flow_entries)})
			return {"type":"choice", "items":items}
		"effect":
			return {"type":"effect", "effects":_array_copy(block.get("effects")), "next":_target_node(block, fallthrough, flow_entries)}
		"command":
			return {"type":"command", "command":_dictionary_copy(block.get("command")), "next":_target_node(block, fallthrough, flow_entries)}
		"jump":
			return {"type":"jump", "next":_target_node(block, fallthrough, flow_entries)}
		"end":
			return {"type":"end"}
	return {"type":block_type, "next":_target_node(block, fallthrough, flow_entries)}

static func _target_node(block: Dictionary, fallthrough: String, flow_entries: Dictionary) -> String:
	var target_flow := String(block.get("target_flow", ""))
	if target_flow.is_empty():
		return fallthrough
	return String(flow_entries.get(target_flow, "__missing_flow__" + target_flow))

static func _validate_expression(block: Dictionary, expression_catalog: Dictionary, issues: Array[Dictionary]) -> void:
	var speaker := String(block.get("speaker", ""))
	if not expression_catalog.has(speaker):
		return
	var expressions: Array = expression_catalog[speaker]
	var expression := String(block.get("expression", ""))
	if expression not in expressions:
		issues.append(_issue("warning", "unknown_expression", String(block.get("scene_key", "")), _node_id(block), "expression is not in the character catalog", block))

static func _manifest(graphs: Dictionary, scenes: Array[Dictionary], blocks: Array[Dictionary], characters: Array[Dictionary]) -> Dictionary:
	var scene_keys: Array[String] = []
	var files := {}
	for scene_key_value: Variant in graphs:
		scene_keys.append(String(scene_key_value))
	scene_keys.sort()
	for scene_key: String in scene_keys:
		var filename := scene_filename(scene_key)
		files[filename] = stable_json(graphs[scene_key]).sha256_text()
	var sources: Array[Dictionary] = []
	var seen_sources := {}
	for source_group: Array[Dictionary] in [scenes, blocks, characters]:
		for item: Dictionary in source_group:
			var source := {"notion_page_id":String(item.get("notion_page_id", "")), "source_url":String(item.get("source_url", ""))}
			var identity := String(source["notion_page_id"]) + "\n" + String(source["source_url"])
			if not seen_sources.has(identity):
				seen_sources[identity] = true
				sources.append(source)
	sources.sort_custom(_source_less)
	var generated_at := Time.get_datetime_string_from_system(true, true).replace(" ", "T")
	if not generated_at.ends_with("Z"):
		generated_at += "Z"
	return {"schema_version":1, "generated_at":generated_at, "sources":sources, "files":files, "scenes":scene_keys}

static func _dictionary_array(value: Variant, field_name: String, issues: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if typeof(value) != TYPE_ARRAY:
		issues.append(_issue("error", "invalid_input", "", "", "%s must be an array" % field_name, {}))
		return result
	for item: Variant in value:
		if typeof(item) != TYPE_DICTIONARY:
			issues.append(_issue("error", "invalid_input", "", "", "%s entries must be dictionaries" % field_name, {}))
		else:
			result.append(item)
	return result

static func _collect_mapping_errors(items: Array[Dictionary], issues: Array[Dictionary]) -> void:
	for item: Dictionary in items:
		var errors: Variant = item.get("errors", [])
		if typeof(errors) != TYPE_ARRAY:
			issues.append(_issue("error", "mapping_error", String(item.get("scene_key", "")), _node_id(item), "mapped errors must be an array", item))
			continue
		for message: Variant in errors:
			issues.append(_issue("error", "mapping_error", String(item.get("scene_key", "")), _node_id(item), String(message), item))

static func _invalid_character_sources(characters: Array[Dictionary]) -> Array[Dictionary]:
	var invalid: Array[Dictionary] = []
	var seen := {}
	for character: Dictionary in characters:
		var character_key := String(character.get("character_key", ""))
		if character_key.is_empty() or seen.has(character_key):
			invalid.append(character)
		else:
			seen[character_key] = true
	return invalid

static func _validator_issue_source(validator_issue: Dictionary, compiled: Dictionary, scene: Dictionary) -> Dictionary:
	var node_id := String(validator_issue.get("node_id", ""))
	var item_index := _choice_item_index(String(validator_issue.get("message", "")))
	var choice_sources: Dictionary = compiled["choice_sources"]
	if item_index >= 0 and choice_sources.has(node_id):
		var sources: Array = choice_sources[node_id]
		if item_index < sources.size():
			return sources[item_index]
	var node_sources: Dictionary = compiled["node_sources"]
	return node_sources.get(node_id, scene)

static func _choice_item_index(message: String) -> int:
	if not message.begins_with("choice item "):
		return -1
	var value := message.trim_prefix("choice item ").get_slice(" ", 0)
	return value.to_int() if value.is_valid_int() else -1

static func _issue(severity: String, code: String, scene_key: String, node_id: String, message: String, source: Dictionary) -> Dictionary:
	return {"severity":severity, "code":code, "scene_key":scene_key, "node_id":node_id, "message":message, "notion_page_id":String(source.get("notion_page_id", "")), "source_url":String(source.get("source_url", ""))}

static func _node_id(block: Dictionary) -> String:
	var explicit := String(block.get("node_id", ""))
	return explicit if not explicit.is_empty() else String(block.get("notion_page_id", "")).replace("-", "")

static func _array_copy(value: Variant) -> Array:
	return value.duplicate(true) if typeof(value) == TYPE_ARRAY else []

static func _dictionary_copy(value: Variant) -> Dictionary:
	return value.duplicate(true) if typeof(value) == TYPE_DICTIONARY else {}

static func _scene_less(left: Dictionary, right: Dictionary) -> bool:
	return String(left.get("scene_key", "")) < String(right.get("scene_key", ""))

static func _character_less(left: Dictionary, right: Dictionary) -> bool:
	var left_key := String(left.get("character_key", ""))
	var right_key := String(right.get("character_key", ""))
	return left_key < right_key if left_key != right_key else String(left.get("notion_page_id", "")) < String(right.get("notion_page_id", ""))

static func _block_less(left: Dictionary, right: Dictionary) -> bool:
	var left_flow := String(left.get("flow", ""))
	var right_flow := String(right.get("flow", ""))
	if left_flow != right_flow:
		return left_flow < right_flow
	var left_order := float(left.get("order", 0.0))
	var right_order := float(right.get("order", 0.0))
	if left_order != right_order:
		return left_order < right_order
	return String(left.get("notion_page_id", "")) < String(right.get("notion_page_id", ""))

static func _source_less(left: Dictionary, right: Dictionary) -> bool:
	var left_id := String(left.get("notion_page_id", ""))
	var right_id := String(right.get("notion_page_id", ""))
	return left_id < right_id if left_id != right_id else String(left.get("source_url", "")) < String(right.get("source_url", ""))
