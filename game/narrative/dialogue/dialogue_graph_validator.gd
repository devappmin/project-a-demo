extends RefCounted
class_name DialogueGraphValidator

const DialogueRuntimeContractResource = preload("res://game/narrative/dialogue/dialogue_runtime_contract.gd")
const SUPPORTED_NODE_TYPES := ["line", "choice", "effect", "command", "jump", "end"]
const CONDITION_KINDS := ["flag", "stat", "inventory", "quest", "collectible"]
const EFFECT_KINDS := ["flag_set", "stat_set", "stat_add", "inventory_add", "inventory_remove", "quest_set", "collectible_add"]
const COMPARISON_OPERATORS := ["eq", "neq", "gt", "gte", "lt", "lte"]

static func validate(data: Dictionary, character_keys: Array[StringName], entry_nodes: Array[StringName] = []) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	var scene_key := _scene_key(data)
	_validate_schema(data, scene_key, issues)
	var characters := _validate_character_keys(character_keys, scene_key, issues)
	var nodes_value: Variant = data.get("nodes")
	if typeof(nodes_value) != TYPE_DICTIONARY:
		_add_issue(issues, "invalid_nodes", scene_key, "", "nodes must be a nonempty dictionary")
		return issues
	var nodes: Dictionary = nodes_value
	if nodes.is_empty():
		_add_issue(issues, "invalid_nodes", scene_key, "", "nodes must be a nonempty dictionary")
	var node_ids := _sorted_node_ids(nodes, scene_key, issues)
	_validate_entry(data, nodes, scene_key, issues)
	_validate_event_entries(entry_nodes, nodes, scene_key, issues)
	var adjacency := _empty_adjacency(node_ids)
	for node_id: String in node_ids:
		_validate_node(node_id, nodes[node_id], nodes, characters, scene_key, adjacency, issues)
	_validate_cycle_exits(adjacency, scene_key, issues)
	_validate_automatic_path_lengths(nodes, node_ids, scene_key, issues)
	_validate_reachability(data, entry_nodes, node_ids, nodes, adjacency, scene_key, issues)
	return issues

static func _scene_key(data: Dictionary) -> String:
	var value: Variant = data.get("scene_key", "")
	return String(value) if _is_string(value) else ""

static func _validate_schema(data: Dictionary, scene_key: String, issues: Array[Dictionary]) -> void:
	var schema_version: Variant = data.get("schema_version")
	if not _is_number(schema_version) or float(schema_version) != 1.0:
		_add_issue(issues, "invalid_schema_version", scene_key, "", "schema_version must be numeric 1")
	var scene_value: Variant = data.get("scene_key")
	if not _is_nonempty_string(scene_value):
		_add_issue(issues, "invalid_scene_key", scene_key, "", "scene_key must be a nonempty string")

static func _validate_character_keys(character_keys: Array[StringName], scene_key: String, issues: Array[Dictionary]) -> Dictionary:
	var characters := {}
	for character_key: StringName in character_keys:
		var key := String(character_key)
		if key.is_empty() or characters.has(key):
			_add_issue(issues, "invalid_character_key", scene_key, "", "character keys must be unique and nonempty")
			continue
		characters[key] = true
	return characters

static func _sorted_node_ids(nodes: Dictionary, scene_key: String, issues: Array[Dictionary]) -> Array[String]:
	var node_ids: Array[String] = []
	for raw_node_id: Variant in nodes:
		if not _is_nonempty_string(raw_node_id):
			_add_issue(issues, "invalid_node_id", scene_key, String(raw_node_id), "node ids must be nonempty strings")
			continue
		node_ids.append(String(raw_node_id))
	node_ids.sort()
	return node_ids

static func _validate_entry(data: Dictionary, nodes: Dictionary, scene_key: String, issues: Array[Dictionary]) -> void:
	var entry: Variant = data.get("entry_node")
	if not _is_nonempty_string(entry):
		_add_issue(issues, "invalid_entry_node", scene_key, "", "entry_node must be a nonempty string")
	elif not nodes.has(String(entry)):
		_add_issue(issues, "missing_entry_node", scene_key, String(entry), "entry_node does not reference a node")

static func _validate_event_entries(entry_nodes: Array[StringName], nodes: Dictionary, scene_key: String, issues: Array[Dictionary]) -> void:
	for entry_node: StringName in entry_nodes:
		var entry := String(entry_node)
		if entry.is_empty() or not nodes.has(entry):
			_add_issue(issues, "invalid_event_entry", scene_key, entry, "event entry does not reference a node")

static func _empty_adjacency(node_ids: Array[String]) -> Dictionary:
	var adjacency := {}
	for node_id: String in node_ids:
		adjacency[node_id] = []
	return adjacency

static func _validate_node(node_id: String, node_value: Variant, nodes: Dictionary, characters: Dictionary, scene_key: String, adjacency: Dictionary, issues: Array[Dictionary]) -> void:
	if typeof(node_value) != TYPE_DICTIONARY:
		_add_issue(issues, "invalid_node", scene_key, node_id, "node must be a dictionary")
		return
	var node: Dictionary = node_value
	var type_value: Variant = node.get("type")
	if not _is_nonempty_string(type_value):
		_add_issue(issues, "invalid_field", scene_key, node_id, "node type must be a nonempty string")
		return
	var node_type := String(type_value)
	if node_type not in SUPPORTED_NODE_TYPES:
		_add_issue(issues, "unsupported_node_type", scene_key, node_id, "unsupported node type: %s" % node_type)
		_validate_next(node, node_id, nodes, scene_key, adjacency, issues)
		return
	match node_type:
		"line":
			_validate_line(node, node_id, nodes, characters, scene_key, adjacency, issues)
		"choice":
			_validate_choice(node, node_id, nodes, scene_key, adjacency, issues)
		"effect":
			_validate_effect_node(node, node_id, nodes, scene_key, adjacency, issues)
		"command":
			_validate_command(node, node_id, nodes, scene_key, adjacency, issues)
		"jump":
			_validate_next(node, node_id, nodes, scene_key, adjacency, issues)
		"end":
			pass

static func _validate_line(node: Dictionary, node_id: String, nodes: Dictionary, characters: Dictionary, scene_key: String, adjacency: Dictionary, issues: Array[Dictionary]) -> void:
	var speaker: Variant = node.get("speaker")
	if not _is_nonempty_string(speaker):
		_add_issue(issues, "invalid_field", scene_key, node_id, "line speaker must be a nonempty string")
	elif not characters.has(String(speaker)):
		_add_issue(issues, "unknown_character", scene_key, node_id, "line speaker is not in the character catalog")
	if not _is_nonempty_string(node.get("expression")):
		_add_issue(issues, "invalid_expression", scene_key, node_id, "line expression must be a nonempty string")
	if not _is_nonempty_string(node.get("text")):
		_add_issue(issues, "invalid_field", scene_key, node_id, "line text must be a nonempty string")
	_validate_next(node, node_id, nodes, scene_key, adjacency, issues)

static func _validate_choice(node: Dictionary, node_id: String, nodes: Dictionary, scene_key: String, adjacency: Dictionary, issues: Array[Dictionary]) -> void:
	var items_value: Variant = node.get("items")
	if typeof(items_value) != TYPE_ARRAY or items_value.is_empty():
		_add_issue(issues, "invalid_field", scene_key, node_id, "choice items must be a nonempty array")
		return
	var items: Array = items_value
	for index: int in items.size():
		var item_value: Variant = items[index]
		if typeof(item_value) != TYPE_DICTIONARY:
			_add_issue(issues, "invalid_field", scene_key, node_id, "choice item %d must be a dictionary" % index)
			continue
		var item: Dictionary = item_value
		if not _is_nonempty_string(item.get("text")):
			_add_issue(issues, "invalid_field", scene_key, node_id, "choice item %d text must be a nonempty string" % index)
		_validate_conditions(item.get("conditions"), node_id, "choice item %d" % index, scene_key, issues)
		_validate_effects(item.get("effects"), node_id, "choice item %d" % index, scene_key, issues)
		_validate_target(item.get("next"), node_id, nodes, scene_key, adjacency, issues, "choice item %d next" % index)

static func _validate_effect_node(node: Dictionary, node_id: String, nodes: Dictionary, scene_key: String, adjacency: Dictionary, issues: Array[Dictionary]) -> void:
	_validate_effects(node.get("effects"), node_id, "effect node", scene_key, issues)
	_validate_next(node, node_id, nodes, scene_key, adjacency, issues)

static func _validate_command(node: Dictionary, node_id: String, nodes: Dictionary, scene_key: String, adjacency: Dictionary, issues: Array[Dictionary]) -> void:
	var command: Variant = node.get("command")
	if typeof(command) != TYPE_DICTIONARY or command.is_empty():
		_add_issue(issues, "invalid_field", scene_key, node_id, "command must be a nonempty dictionary")
	_validate_next(node, node_id, nodes, scene_key, adjacency, issues)

static func _validate_next(node: Dictionary, node_id: String, nodes: Dictionary, scene_key: String, adjacency: Dictionary, issues: Array[Dictionary]) -> void:
	_validate_target(node.get("next"), node_id, nodes, scene_key, adjacency, issues, "next")

static func _validate_target(target: Variant, node_id: String, nodes: Dictionary, scene_key: String, adjacency: Dictionary, issues: Array[Dictionary], field_name: String) -> void:
	if not _is_nonempty_string(target):
		_add_issue(issues, "invalid_field", scene_key, node_id, "%s must be a nonempty string" % field_name)
		return
	var target_id := String(target)
	if not nodes.has(target_id):
		_add_issue(issues, "dangling_target", scene_key, node_id, "%s references missing node %s" % [field_name, target_id])
		return
	if adjacency.has(node_id):
		var targets: Array = adjacency[node_id]
		if target_id not in targets:
			targets.append(target_id)
			targets.sort()

static func _validate_conditions(value: Variant, node_id: String, context: String, scene_key: String, issues: Array[Dictionary]) -> void:
	if typeof(value) != TYPE_ARRAY:
		_add_issue(issues, "invalid_condition", scene_key, node_id, "%s conditions must be an array" % context)
		return
	for index: int in value.size():
		if not _condition_is_valid(value[index]):
			_add_issue(issues, "invalid_condition", scene_key, node_id, "%s condition %d has an unsupported shape" % [context, index])

static func _condition_is_valid(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var condition: Dictionary = value
	if not condition.has_all(["kind", "key", "operator", "value"]):
		return false
	if not _is_nonempty_runtime_string(condition["kind"]) or not _is_nonempty_runtime_string(condition["key"]) or typeof(condition["operator"]) != TYPE_STRING:
		return false
	var kind := String(condition["kind"])
	var operator_name := String(condition["operator"])
	var expected: Variant = condition["value"]
	if kind not in CONDITION_KINDS:
		return false
	match kind:
		"flag":
			return operator_name in ["eq", "neq"] and typeof(expected) == TYPE_BOOL
		"stat":
			return operator_name in COMPARISON_OPERATORS and _is_number(expected)
		"inventory", "collectible":
			if operator_name == "contains":
				return typeof(expected) == TYPE_BOOL
			return operator_name in COMPARISON_OPERATORS and _is_number(expected)
		"quest":
			return operator_name in ["eq", "neq"] and typeof(expected) == TYPE_STRING
	return false

static func _validate_effects(value: Variant, node_id: String, context: String, scene_key: String, issues: Array[Dictionary]) -> void:
	if typeof(value) != TYPE_ARRAY:
		_add_issue(issues, "invalid_effect", scene_key, node_id, "%s effects must be an array" % context)
		return
	for index: int in value.size():
		if not _effect_is_valid(value[index]):
			_add_issue(issues, "invalid_effect", scene_key, node_id, "%s effect %d has an unsupported shape" % [context, index])

static func _effect_is_valid(value: Variant) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var effect: Dictionary = value
	if not effect.has_all(["kind", "key", "value"]):
		return false
	if not _is_nonempty_runtime_string(effect["kind"]) or not _is_nonempty_runtime_string(effect["key"]):
		return false
	var kind := String(effect["kind"])
	var effect_value: Variant = effect["value"]
	if kind not in EFFECT_KINDS:
		return false
	match kind:
		"flag_set":
			return typeof(effect_value) == TYPE_BOOL
		"stat_set", "stat_add":
			return _is_number(effect_value)
		"inventory_add", "inventory_remove", "collectible_add":
			return _is_number(effect_value) and effect_value >= 0.0
		"quest_set":
			return typeof(effect_value) == TYPE_STRING
	return false

static func _validate_cycle_exits(adjacency: Dictionary, scene_key: String, issues: Array[Dictionary]) -> void:
	var reverse := {}
	var node_ids: Array[String] = []
	for node_id: String in adjacency:
		node_ids.append(node_id)
		reverse[node_id] = []
	node_ids.sort()
	for from_id: String in node_ids:
		for target: String in adjacency.get(from_id, []):
			if reverse.has(target):
				reverse[target].append(from_id)
	var assigned := {}
	for seed: String in node_ids:
		if assigned.has(seed):
			continue
		var forward := _reachable_from(seed, adjacency, {})
		var backward := _reachable_from(seed, reverse, {})
		var component: Array[String] = []
		for candidate: String in node_ids:
			if forward.has(candidate) and backward.has(candidate):
				component.append(candidate)
				assigned[candidate] = true
		var seed_targets: Array = adjacency.get(seed, [])
		var cyclic: bool = component.size() > 1 or seed in seed_targets
		if not cyclic:
			continue
		var member_set := {}
		for member: String in component:
			member_set[member] = true
		var has_exit := false
		for member: String in component:
			for target: String in adjacency.get(member, []):
				if not member_set.has(target):
					has_exit = true
					break
			if has_exit:
				break
		if not has_exit:
			_add_issue(issues, "cycle_without_exit", scene_key, component[0], "cycle has no edge to a node outside the cycle")

static func _validate_automatic_path_lengths(nodes: Dictionary, node_ids: Array[String], scene_key: String, issues: Array[Dictionary]) -> void:
	for start_id: String in node_ids:
		var current_id := start_id
		var visited := {}
		var automatic_steps := 0
		while nodes.has(current_id) and not visited.has(current_id):
			var node_value: Variant = nodes[current_id]
			if typeof(node_value) != TYPE_DICTIONARY:
				break
			var node: Dictionary = node_value
			var node_type := String(node.get("type", ""))
			if node_type not in ["effect", "command", "jump"]:
				break
			visited[current_id] = true
			automatic_steps += 1
			if automatic_steps > DialogueRuntimeContractResource.MAX_AUTOMATIC_STEPS:
				_add_issue(issues, "automatic_path_too_long", scene_key, start_id, "automatic path exceeds %d nodes before a stable boundary" % DialogueRuntimeContractResource.MAX_AUTOMATIC_STEPS)
				break
			var next_value: Variant = node.get("next", "")
			if not _is_nonempty_string(next_value) or not nodes.has(String(next_value)):
				break
			current_id = String(next_value)

static func _validate_reachability(data: Dictionary, entry_nodes: Array[StringName], node_ids: Array[String], nodes: Dictionary, adjacency: Dictionary, scene_key: String, issues: Array[Dictionary]) -> void:
	if entry_nodes.is_empty():
		return
	var roots: Array[String] = []
	var default_entry := String(data.get("entry_node", ""))
	if nodes.has(default_entry):
		roots.append(default_entry)
	for event_entry: StringName in entry_nodes:
		var entry := String(event_entry)
		if nodes.has(entry) and entry not in roots:
			roots.append(entry)
	var reachable: Dictionary = {}
	for root: String in roots:
		var from_root := _reachable_from(root, adjacency, {})
		for node_id: Variant in from_root.keys():
			reachable[node_id] = true
	for node_id: String in node_ids:
		if not reachable.has(node_id):
			_add_warning(issues, "unreachable_node", scene_key, node_id, "node cannot be reached from the default or supplied event entries")

static func _reachable_from(start: String, adjacency: Dictionary, allowed: Dictionary) -> Dictionary:
	var visited := {}
	var pending: Array[String] = [start]
	while not pending.is_empty():
		var current: String = pending.pop_back()
		if visited.has(current) or not adjacency.has(current):
			continue
		if not allowed.is_empty() and not allowed.has(current):
			continue
		visited[current] = true
		var targets: Array = adjacency.get(current, [])
		for index: int in range(targets.size() - 1, -1, -1):
			pending.append(String(targets[index]))
	return visited

static func _add_issue(issues: Array[Dictionary], code: String, scene_key: String, node_id: String, message: String) -> void:
	issues.append({
		"severity": "error",
		"code": code,
		"scene_key": scene_key,
		"node_id": node_id,
		"message": message
	})

static func _add_warning(issues: Array[Dictionary], code: String, scene_key: String, node_id: String, message: String) -> void:
	issues.append({
		"severity": "warning",
		"code": code,
		"scene_key": scene_key,
		"node_id": node_id,
		"message": message
	})

static func _is_string(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME

static func _is_nonempty_string(value: Variant) -> bool:
	return _is_string(value) and not String(value).is_empty()

static func _is_nonempty_runtime_string(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not String(value).is_empty()

static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
