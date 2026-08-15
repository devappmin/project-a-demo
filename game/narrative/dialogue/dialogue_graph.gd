extends RefCounted
class_name DialogueGraph

var _scene_key: StringName = &""
var _entry_node: StringName = &""
var _nodes: Dictionary = {}

var scene_key: StringName:
	get:
		return _scene_key

var entry_node: StringName:
	get:
		return _entry_node

var nodes: Dictionary:
	get:
		return _nodes.duplicate(true)

static func from_dictionary(data: Dictionary) -> DialogueGraph:
	var graph := DialogueGraph.new()
	graph._scene_key = StringName(data.get("scene_key", ""))
	graph._entry_node = StringName(data.get("entry_node", ""))
	var source_nodes: Variant = data.get("nodes", {})
	if typeof(source_nodes) == TYPE_DICTIONARY:
		graph._nodes = source_nodes.duplicate(true)
	return graph

func get_node(node_id: StringName) -> Dictionary:
	var node: Variant = _nodes.get(String(node_id), {})
	return node.duplicate(true) if typeof(node) == TYPE_DICTIONARY else {}
