extends RefCounted
class_name DocumentDialogueCompiler

const AuthoringSchema = preload("res://tools/dialogue_import/dialogue_authoring_schema.gd")
const Identity = preload("res://tools/dialogue_import/dialogue_identity.gd")
const GraphValidator = preload("res://game/narrative/dialogue/dialogue_graph_validator.gd")
const DefaultCatalog = preload("res://game/narrative/catalog/narrative_catalog.gd")
const DefaultCharacters = preload("res://data/characters/character_registry.tres")
const RESERVED_ARTIFACT_FILENAMES := ["manifest.json", "events.json", "source_map.json"]

static func compile_bundles(bundles: Array[Dictionary], catalog: NarrativeCatalog = null, characters: Resource = null) -> Dictionary:
	var local_catalog: NarrativeCatalog = catalog if catalog != null else DefaultCatalog.load_default()
	var local_characters: Resource = characters if characters != null else DefaultCharacters
	var issues: Array[Dictionary] = []
	var graphs: Dictionary = {}
	var event_bundles: Dictionary = {}
	var source_entries: Array[Dictionary] = []
	var filenames: Dictionary = {}
	var ordered_bundles: Array[Dictionary] = bundles.duplicate(true)
	for catalog_issue: Dictionary in local_catalog.validate_catalog():
		issues.append(_issue("error", String(catalog_issue.get("code", "invalid_catalog")), String(catalog_issue.get("message", "narrative catalog is invalid")), {}, ""))
	if local_characters == null or not local_characters.has_method("validate_authoring_metadata"):
		issues.append(_issue("error", "invalid_character_metadata", "character registry cannot validate Korean authoring metadata", {}, ""))
	else:
		for character_issue_value: Variant in local_characters.call("validate_authoring_metadata"):
			var character_issue: Dictionary = character_issue_value
			issues.append(_issue("error", String(character_issue.get("code", "invalid_character_metadata")), String(character_issue.get("message", "character authoring metadata is invalid")), {}, ""))
	if _has_errors(issues):
		return _compile_result(graphs, event_bundles, source_entries, issues)
	ordered_bundles.sort_custom(_bundle_less)
	_validate_source_identity_uniqueness(ordered_bundles, issues)
	if _has_errors(issues):
		return _compile_result(graphs, event_bundles, source_entries, issues)
	for bundle: Dictionary in ordered_bundles:
		var schema_issues: Array[Dictionary] = AuthoringSchema.validate_bundle(bundle, local_catalog, local_characters)
		issues.append_array(schema_issues)
		if _has_errors(schema_issues):
			continue
		var bundle_key := String(bundle.get("bundle_key", ""))
		var source_id := String(bundle.get("source_id", ""))
		if Identity.stable_key("bundle", source_id, bundle_key) != bundle_key:
			issues.append(_issue("error", "unsafe_bundle_key", "bundle_key cannot produce a safe runtime artifact", _context(bundle), ""))
			continue
		if graphs.has(bundle_key):
			issues.append(_issue("error", "duplicate_bundle_key", "bundle_key must be unique", _context(bundle), ""))
			continue
		var filename := _bundle_filename(bundle_key)
		var filename_identity := filename.to_lower()
		if filename_identity in RESERVED_ARTIFACT_FILENAMES:
			issues.append(_issue("error", "reserved_artifact_filename", "bundle_key collides with a reserved runtime artifact", _context(bundle), ""))
			continue
		if filenames.has(filename_identity):
			issues.append(_issue("error", "duplicate_artifact_filename", "bundle_key collides with another artifact filename", _context(bundle), ""))
			continue
		filenames[filename_identity] = bundle_key
		var compiled := _compile_bundle(bundle, local_catalog)
		issues.append_array(compiled["issues"])
		var graph: Dictionary = compiled["graph"]
		var character_keys: Array[StringName] = local_characters.character_keys() if local_characters != null and local_characters.has_method("character_keys") else []
		var entry_nodes: Array[StringName] = compiled["entry_nodes"]
		var unreachable_flows: Dictionary = {}
		for validator_issue: Dictionary in GraphValidator.validate(graph, character_keys, entry_nodes):
			var node_id := String(validator_issue.get("node_id", ""))
			var source_context: Dictionary = compiled["node_contexts"].get(node_id, _context(bundle))
			var issue_code := String(validator_issue.get("code", "graph_validation_failed"))
			var issue_message := String(validator_issue.get("message", "graph validation failed"))
			if issue_code == "unreachable_node" and not String(source_context.get("flow_key", "")).is_empty():
				var flow_identity := "%s\n%s" % [source_context.get("event_key", ""), source_context.get("flow_key", "")]
				if unreachable_flows.has(flow_identity):
					continue
				unreachable_flows[flow_identity] = true
				source_context = compiled["flow_contexts"].get(flow_identity, source_context)
				issue_code = "unreachable_flow"
				issue_message = "flow cannot be reached from any dialogue event entry"
			issues.append(_issue(String(validator_issue.get("severity", "error")), issue_code, issue_message, source_context, node_id))
		graphs[bundle_key] = graph
		event_bundles[bundle_key] = {"triggers":compiled["triggers"]}
		source_entries.append_array(compiled["sources"])
	return _compile_result(graphs, event_bundles, source_entries, issues)

static func stable_json(data: Variant) -> String:
	return JSON.stringify(data, "\t", true, true)

static func _compile_bundle(bundle: Dictionary, catalog: NarrativeCatalog) -> Dictionary:
	var issues: Array[Dictionary] = []
	var nodes: Dictionary = {}
	var node_contexts: Dictionary = {}
	var sources: Array[Dictionary] = []
	var block_ids: Dictionary = {}
	var block_entries: Dictionary = {}
	var flow_entries: Dictionary = {}
	var event_entries: Dictionary = {}
	var event_records: Dictionary = {}
	var flow_records: Dictionary = {}
	var blocks_by_flow: Dictionary = {}
	var event_source_indices: Dictionary = {}
	var flow_source_indices: Dictionary = {}
	var flow_contexts: Dictionary = {}
	var bundle_context := _context(bundle)
	_add_source(sources, bundle, bundle_context, "bundle", String(bundle.get("bundle_key", "")), "")
	for trigger_value: Variant in bundle.get("triggers", []):
		var trigger: Dictionary = trigger_value
		var trigger_context := _context(trigger, bundle_context)
		_add_source(sources, trigger, trigger_context, "trigger", String(trigger.get("trigger_key", "")), "")
		for event_value: Variant in trigger.get("events", []):
			var event: Dictionary = event_value
			var event_key := String(event.get("event_key", ""))
			var event_context := _context(event, trigger_context)
			event_records[event_key] = event
			event_source_indices[event_key] = sources.size()
			_add_source(sources, event, event_context, "event", event_key, "")
			for flow_value: Variant in event.get("flows", []):
				var flow: Dictionary = flow_value
				var flow_key := String(flow.get("flow_key", ""))
				var flow_identity := _flow_identity(event_key, flow_key)
				var flow_context := _context(flow, event_context)
				flow_contexts[flow_identity] = flow_context
				flow_records[flow_identity] = flow
				blocks_by_flow[flow_identity] = flow.get("blocks", [])
				flow_source_indices[flow_identity] = sources.size()
				_add_source(sources, flow, flow_context, "flow", flow_key, "")
				var block_index := 0
				for block_value: Variant in flow.get("blocks", []):
					var block: Dictionary = block_value
					var block_key := _block_key(block, block_index)
					var node_id := Identity.node_id(event_key, flow_key, block_key)
					var block_identity := _block_identity(flow_identity, block_index)
					block_ids[block_identity] = node_id
					block_entries[block_identity] = node_id
					var block_context := _context(block, flow_context)
					node_contexts[node_id] = block_context
					_add_source(sources, block, block_context, "block", block_key, node_id)
					if nodes.has(node_id):
						issues.append(_issue("error", "duplicate_node_id", "generated node IDs must be unique", block_context, node_id))
					else:
						nodes[node_id] = {"type":String(block.get("type", ""))}
					if String(block.get("type", "")) == "choice":
						var item_index := 0
						for item_value: Variant in block.get("items", []):
							var item: Dictionary = item_value
							var item_key := Identity.stable_key("choice", String(item.get("source_id", "")), String(item.get("choice_key", "")))
							_add_source(sources, item, _context(item, block_context), "choice", item_key, node_id)
							item_index += 1
					block_index += 1
	# End block entries include both enclosing result scopes before their real end node.
	for flow_identity_value: Variant in blocks_by_flow.keys():
		var flow_identity := String(flow_identity_value)
		var event_key := flow_identity.get_slice("\n", 0)
		var flow: Dictionary = flow_records[flow_identity]
		var event: Dictionary = event_records[event_key]
		var blocks: Array = blocks_by_flow[flow_identity]
		for block_index: int in blocks.size():
			var block: Dictionary = blocks[block_index]
			if String(block.get("type", "")) != "end":
				continue
			var identity := _block_identity(flow_identity, block_index)
			var node_id := String(block_ids[identity])
			nodes[node_id] = {"type":"end"}
			var route_context: Dictionary = node_contexts.get(node_id, _context(bundle))
			var target := _route_effects(nodes, node_contexts, node_id + ".event_results", _normalize_effects(event.get("effects", []), catalog), node_id, issues, route_context)
			target = _route_effects(nodes, node_contexts, node_id + ".flow_results", _normalize_effects(flow.get("effects", []), catalog), target, issues, route_context)
			block_entries[identity] = target
	# Flow and event entries are known after end wrappers exist.
	for flow_identity_value: Variant in blocks_by_flow.keys():
		var flow_identity := String(flow_identity_value)
		var blocks: Array = blocks_by_flow[flow_identity]
		if not blocks.is_empty():
			flow_entries[flow_identity] = block_entries[_block_identity(flow_identity, 0)]
			_set_source_node(sources, int(flow_source_indices.get(flow_identity, -1)), String(flow_entries[flow_identity]))
	for event_key_value: Variant in event_records.keys():
		var event_key := String(event_key_value)
		event_entries[event_key] = String(flow_entries.get(_flow_identity(event_key, "start"), ""))
		_set_source_node(sources, int(event_source_indices.get(event_key, -1)), String(event_entries[event_key]))
	# Compile executable block payloads and route every flow exit through its results.
	for flow_identity_value: Variant in blocks_by_flow.keys():
		var flow_identity := String(flow_identity_value)
		var event_key := flow_identity.get_slice("\n", 0)
		var flow: Dictionary = flow_records[flow_identity]
		var event: Dictionary = event_records[event_key]
		var blocks: Array = blocks_by_flow[flow_identity]
		for block_index: int in blocks.size():
			var block: Dictionary = blocks[block_index]
			var identity := _block_identity(flow_identity, block_index)
			var node_id := String(block_ids[identity])
			var block_type := String(block.get("type", ""))
			match block_type:
				"line":
					nodes[node_id] = {"type":"line", "speaker":String(block.get("speaker", "")), "expression":String(block.get("expression", "")), "text":String(block.get("text", "")), "next":String(block_entries.get(_block_identity(flow_identity, block_index + 1), ""))}
				"command":
					nodes[node_id] = {"type":"command", "command":{"key":String(block.get("command_key", "")), "arguments":_dictionary_copy(block.get("arguments", {}))}, "next":String(block_entries.get(_block_identity(flow_identity, block_index + 1), ""))}
				"choice":
					var items: Array[Dictionary] = []
					var item_index := 0
					for item_value: Variant in block.get("items", []):
						var item: Dictionary = item_value
						var target := _target_entry(item, event_key, flow_entries, event_entries)
						var route_id := "%s.choice_%d" % [node_id, item_index]
						var route_context := _context(item, node_contexts.get(node_id, _context(bundle)))
						if String(item.get("target_kind", "")) == "event":
							target = _route_effects(nodes, node_contexts, route_id + ".event_results", _normalize_effects(event.get("effects", []), catalog), target, issues, route_context)
						target = _route_effects(nodes, node_contexts, route_id + ".flow_results", _normalize_effects(flow.get("effects", []), catalog), target, issues, route_context)
						items.append({"text":String(item.get("text", "")), "conditions":_normalize_conditions(item.get("conditions", []), catalog), "effects":_normalize_effects(item.get("effects", []), catalog), "next":target})
						item_index += 1
					nodes[node_id] = {"type":"choice", "items":items}
				"jump":
					var target := _target_entry(block, event_key, flow_entries, event_entries)
					var route_context: Dictionary = node_contexts.get(node_id, _context(bundle))
					if String(block.get("target_kind", "")) == "event":
						target = _route_effects(nodes, node_contexts, node_id + ".event_results", _normalize_effects(event.get("effects", []), catalog), target, issues, route_context)
					target = _route_effects(nodes, node_contexts, node_id + ".flow_results", _normalize_effects(flow.get("effects", []), catalog), target, issues, route_context)
					nodes[node_id] = {"type":"jump", "next":target}
				"end":
					pass
	var trigger_index: Dictionary = {}
	var entry_nodes: Array[StringName] = []
	for trigger_value: Variant in bundle.get("triggers", []):
		var trigger: Dictionary = trigger_value
		var candidates: Array[Dictionary] = []
		for event_value: Variant in trigger.get("events", []):
			var event: Dictionary = event_value
			var event_key := String(event.get("event_key", ""))
			var entry_node := String(event_entries.get(event_key, ""))
			candidates.append({"event_key":event_key, "entry_node":entry_node, "conditions":_normalize_conditions(event.get("conditions", []), catalog)})
			entry_nodes.append(StringName(entry_node))
		trigger_index[String(trigger.get("trigger_key", ""))] = candidates
	var default_entry := ""
	if not bundle.get("triggers", []).is_empty():
		var first_trigger: Dictionary = bundle["triggers"][0]
		if not first_trigger.get("events", []).is_empty():
			default_entry = String(event_entries.get(String(first_trigger["events"][0].get("event_key", "")), ""))
	return {
		"graph":{"schema_version":1, "scene_key":String(bundle.get("bundle_key", "")), "entry_node":default_entry, "nodes":nodes},
		"triggers":trigger_index,
		"entry_nodes":entry_nodes,
		"sources":sources,
		"node_contexts":node_contexts,
		"flow_contexts":flow_contexts,
		"issues":issues,
	}

static func _route_effects(nodes: Dictionary, node_contexts: Dictionary, route_id: String, effects: Array[Dictionary], target: String, issues: Array[Dictionary], context: Dictionary) -> String:
	if effects.is_empty():
		return target
	if nodes.has(route_id):
		issues.append(_issue("error", "generated_node_collision", "synthetic result node collides with an existing generated node", context, route_id))
		return target
	nodes[route_id] = {"type":"effect", "effects":effects.duplicate(true), "next":target}
	node_contexts[route_id] = context.duplicate(true)
	return route_id

static func _compile_result(graphs: Dictionary, event_bundles: Dictionary, source_entries: Array[Dictionary], issues: Array[Dictionary]) -> Dictionary:
	source_entries.sort_custom(_source_less)
	var events := {"schema_version":1, "bundles":event_bundles}
	var source_map := {"schema_version":1, "sources":source_entries}
	var artifacts := _build_artifacts(graphs, events, source_map)
	var manifest := _build_manifest(artifacts, graphs.keys())
	return {"ok":not _has_errors(issues), "graphs":graphs, "events":events, "source_map":source_map, "issues":issues, "manifest":manifest, "artifacts":artifacts}

static func _set_source_node(sources: Array[Dictionary], source_index: int, node_id: String) -> void:
	if source_index < 0 or source_index >= sources.size() or node_id.is_empty():
		return
	var entry: Dictionary = sources[source_index]
	entry["node_id"] = node_id

static func _target_entry(target: Dictionary, event_key: String, flow_entries: Dictionary, event_entries: Dictionary) -> String:
	if String(target.get("target_kind", "")) == "event":
		return String(event_entries.get(String(target.get("target_key", "")), ""))
	return String(flow_entries.get(_flow_identity(event_key, String(target.get("target_key", ""))), ""))

static func _normalize_conditions(value: Variant, catalog: NarrativeCatalog) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if typeof(value) != TYPE_ARRAY or catalog == null:
		return result
	for record_value: Variant in value:
		if typeof(record_value) != TYPE_DICTIONARY:
			continue
		var normalized: Dictionary = catalog.validate_condition(record_value)
		if normalized.get("ok", false):
			result.append((normalized.get("value", {}) as Dictionary).duplicate(true))
	return result

static func _normalize_effects(value: Variant, catalog: NarrativeCatalog) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if typeof(value) != TYPE_ARRAY or catalog == null:
		return result
	for record_value: Variant in value:
		if typeof(record_value) != TYPE_DICTIONARY:
			continue
		var normalized: Dictionary = catalog.validate_effect(record_value)
		if normalized.get("ok", false):
			result.append((normalized.get("value", {}) as Dictionary).duplicate(true))
	return result

static func _build_artifacts(graphs: Dictionary, events: Dictionary, source_map: Dictionary) -> Dictionary:
	var artifacts: Dictionary = {}
	var bundle_keys: Array = graphs.keys()
	bundle_keys.sort()
	for bundle_key_value: Variant in bundle_keys:
		var bundle_key := String(bundle_key_value)
		artifacts[_bundle_filename(bundle_key)] = (graphs[bundle_key] as Dictionary).duplicate(true)
	artifacts["events.json"] = events.duplicate(true)
	artifacts["source_map.json"] = source_map.duplicate(true)
	return artifacts

static func _build_manifest(artifacts: Dictionary, bundle_key_values: Array) -> Dictionary:
	var files: Dictionary = {}
	var filenames: Array = artifacts.keys()
	filenames.sort()
	for filename_value: Variant in filenames:
		var filename := String(filename_value)
		files[filename] = stable_json(artifacts[filename]).sha256_text()
	var bundles: Array[String] = []
	for bundle_key_value: Variant in bundle_key_values:
		bundles.append(String(bundle_key_value))
	bundles.sort()
	var generated_at := Time.get_datetime_string_from_system(true, true).replace(" ", "T")
	if not generated_at.ends_with("Z"):
		generated_at += "Z"
	return {"schema_version":1, "generated_at":generated_at, "bundles":bundles, "files":files}

static func _add_source(sources: Array[Dictionary], value: Dictionary, context: Dictionary, kind: String, key: String, node_id: String) -> void:
	var entry := {"source_id":String(value.get("source_id", "")), "source_url":String(value.get("source_url", context.get("source_url", ""))), "kind":kind, "key":key}
	if not node_id.is_empty():
		entry["node_id"] = node_id
	sources.append(entry)

static func _validate_source_identity_uniqueness(bundles: Array[Dictionary], issues: Array[Dictionary]) -> void:
	var identities: Dictionary = {}
	for bundle: Dictionary in bundles:
		for record: Dictionary in _source_records(bundle):
			var source_value: Variant = record.get("source_id", null)
			if typeof(source_value) != TYPE_STRING:
				continue
			var source_id := String(source_value).strip_edges()
			if source_id.is_empty():
				continue
			if identities.has(source_id):
				issues.append(_issue("error", "duplicate_source_id", "source_id must be unique across the complete compile batch", _context(record, _context(bundle)), ""))
			else:
				identities[source_id] = true

static func _source_records(bundle: Dictionary) -> Array[Dictionary]:
	var records: Array[Dictionary] = [bundle]
	var triggers_value: Variant = bundle.get("triggers", [])
	if typeof(triggers_value) != TYPE_ARRAY:
		return records
	for trigger_value: Variant in triggers_value:
		if typeof(trigger_value) != TYPE_DICTIONARY:
			continue
		var trigger: Dictionary = trigger_value
		records.append(trigger)
		var events_value: Variant = trigger.get("events", [])
		if typeof(events_value) != TYPE_ARRAY:
			continue
		for event_value: Variant in events_value:
			if typeof(event_value) != TYPE_DICTIONARY:
				continue
			var event: Dictionary = event_value
			records.append(event)
			var flows_value: Variant = event.get("flows", [])
			if typeof(flows_value) != TYPE_ARRAY:
				continue
			for flow_value: Variant in flows_value:
				if typeof(flow_value) != TYPE_DICTIONARY:
					continue
				var flow: Dictionary = flow_value
				records.append(flow)
				var blocks_value: Variant = flow.get("blocks", [])
				if typeof(blocks_value) != TYPE_ARRAY:
					continue
				for block_value: Variant in blocks_value:
					if typeof(block_value) != TYPE_DICTIONARY:
						continue
					var block: Dictionary = block_value
					records.append(block)
					var items_value: Variant = block.get("items", [])
					if typeof(items_value) != TYPE_ARRAY:
						continue
					for item_value: Variant in items_value:
						if typeof(item_value) == TYPE_DICTIONARY:
							records.append(item_value)
	return records

static func _context(value: Dictionary, parent := {}) -> Dictionary:
	return {
		"source_id":String(value.get("source_id", parent.get("source_id", ""))),
		"source_url":String(value.get("source_url", parent.get("source_url", ""))),
		"bundle_key":String(value.get("bundle_key", parent.get("bundle_key", ""))),
		"event_key":String(value.get("event_key", parent.get("event_key", ""))),
		"flow_key":String(value.get("flow_key", parent.get("flow_key", ""))),
	}

static func _issue(severity: String, code: String, message: String, context: Dictionary, node_id: String) -> Dictionary:
	return {"severity":severity, "code":code, "message":message, "source_id":String(context.get("source_id", "")), "source_url":String(context.get("source_url", "")), "bundle_key":String(context.get("bundle_key", "")), "event_key":String(context.get("event_key", "")), "flow_key":String(context.get("flow_key", "")), "node_id":node_id}

static func _has_errors(issues: Array[Dictionary]) -> bool:
	for issue: Dictionary in issues:
		if String(issue.get("severity", "error")) == "error":
			return true
	return false

static func _block_key(block: Dictionary, index: int) -> String:
	var retained := String(block.get("block_key", ""))
	var generated := Identity.stable_key(String(block.get("type", "block")), String(block.get("source_id", "")), retained)
	return generated if not generated.is_empty() else "block_%03d" % index

static func _flow_identity(event_key: String, flow_key: String) -> String:
	return event_key + "\n" + flow_key

static func _block_identity(flow_identity: String, block_index: int) -> String:
	return "%s\n%d" % [flow_identity, block_index]

static func _bundle_filename(bundle_key: String) -> String:
	return bundle_key.replace(".", "_") + ".json"

static func _dictionary_copy(value: Variant) -> Dictionary:
	return value.duplicate(true) if typeof(value) == TYPE_DICTIONARY else {}

static func _bundle_less(left: Dictionary, right: Dictionary) -> bool:
	var left_key := String(left.get("bundle_key", ""))
	var right_key := String(right.get("bundle_key", ""))
	return left_key < right_key if left_key != right_key else String(left.get("source_id", "")) < String(right.get("source_id", ""))

static func _source_less(left: Dictionary, right: Dictionary) -> bool:
	for field: String in ["source_id", "kind", "key", "node_id", "source_url"]:
		var left_value := String(left.get(field, ""))
		var right_value := String(right.get(field, ""))
		if left_value != right_value:
			return left_value < right_value
	return false
