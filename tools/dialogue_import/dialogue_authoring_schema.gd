extends RefCounted
class_name DialogueAuthoringSchema

static func validate_bundle(bundle: Dictionary, catalog: NarrativeCatalog, characters: Resource) -> Array[Dictionary]:
	var issues: Array[Dictionary] = []
	var context := _context(bundle)
	_validate_allowed_fields(bundle, ["schema_version", "source_id", "source_url", "bundle_key", "title", "comments", "triggers"], "invalid_bundle", "bundle", context, issues)
	var schema_version: Variant = bundle.get("schema_version", null)
	if typeof(schema_version) not in [TYPE_INT, TYPE_FLOAT] or float(schema_version) != 1.0:
		_add_issue(issues, "error", "unsupported_schema_version", "bundle schema_version must be numeric 1", context)
	_validate_required_text(bundle, "source_id", context, issues)
	_validate_required_text(bundle, "source_url", context, issues)
	_validate_required_text(bundle, "bundle_key", context, issues)
	var triggers_value: Variant = bundle.get("triggers", null)
	if typeof(triggers_value) != TYPE_ARRAY or triggers_value.is_empty():
		_add_issue(issues, "error", "missing_triggers", "bundle requires one or more triggers", context)
		return issues
	var event_keys := _bundle_event_keys(triggers_value, context, issues)
	for trigger_value: Variant in triggers_value:
		if typeof(trigger_value) != TYPE_DICTIONARY:
			_add_issue(issues, "error", "invalid_trigger", "trigger must be a dictionary", context)
			continue
		_validate_trigger(trigger_value, event_keys, catalog, characters, context, issues)
	return issues

static func _bundle_event_keys(triggers: Array, bundle_context: Dictionary, issues: Array[Dictionary]) -> Dictionary:
	var event_keys: Dictionary = {}
	for trigger_value: Variant in triggers:
		if typeof(trigger_value) != TYPE_DICTIONARY:
			continue
		var trigger_context := _context(trigger_value, bundle_context)
		var events_value: Variant = (trigger_value as Dictionary).get("events", null)
		if typeof(events_value) != TYPE_ARRAY:
			continue
		for event_value: Variant in events_value:
			if typeof(event_value) != TYPE_DICTIONARY:
				continue
			var event_key := String((event_value as Dictionary).get("event_key", ""))
			if event_key.is_empty():
				continue
			if event_keys.has(event_key):
				_add_issue(issues, "error", "duplicate_event_key", "event_key must be unique within its bundle", _context(event_value, trigger_context))
			else:
				event_keys[event_key] = true
	return event_keys

static func _validate_trigger(trigger: Dictionary, event_keys: Dictionary, catalog: NarrativeCatalog, characters: Resource, bundle_context: Dictionary, issues: Array[Dictionary]) -> void:
	var context := _context(trigger, bundle_context)
	_validate_allowed_fields(trigger, ["source_id", "source_url", "trigger_key", "name", "comments", "events"], "invalid_trigger", "trigger", context, issues)
	_validate_required_text(trigger, "source_id", context, issues)
	var trigger_key := String(trigger.get("trigger_key", ""))
	if trigger_key.is_empty():
		_add_issue(issues, "error", "missing_trigger_key", "trigger requires trigger_key", context)
	elif catalog == null or not catalog.has_trigger(StringName(trigger_key)):
		_add_issue(issues, "error", "unknown_trigger", "trigger is not registered in the narrative catalog", context)
	var events_value: Variant = trigger.get("events", null)
	if typeof(events_value) != TYPE_ARRAY or events_value.is_empty():
		_add_issue(issues, "error", "missing_events", "trigger requires one or more events", context)
		return
	for event_index: int in events_value.size():
		var event_value: Variant = events_value[event_index]
		if typeof(event_value) == TYPE_DICTIONARY:
			_validate_event(event_value, event_keys, catalog, characters, context, issues)
		else:
			_add_issue(issues, "error", "invalid_event", "event must be a dictionary", context)
	if typeof(events_value[events_value.size() - 1]) == TYPE_DICTIONARY:
		var final_event: Dictionary = events_value[events_value.size() - 1]
		var final_conditions: Variant = final_event.get("conditions", null)
		if typeof(final_conditions) == TYPE_ARRAY and not (final_conditions as Array).is_empty():
			_add_issue(issues, "warning", "missing_fallback", "the final event should be an unconditional fallback", _context(final_event, context))

static func _validate_event(event: Dictionary, event_keys: Dictionary, catalog: NarrativeCatalog, characters: Resource, trigger_context: Dictionary, issues: Array[Dictionary]) -> void:
	var context := _context(event, trigger_context)
	_validate_allowed_fields(event, ["source_id", "source_url", "event_key", "name", "comments", "conditions", "effects", "flows"], "invalid_event", "event", context, issues)
	_validate_required_text(event, "source_id", context, issues)
	_validate_required_text(event, "event_key", context, issues)
	_validate_mappings(event.get("conditions", null), true, catalog, context, issues)
	_validate_mappings(event.get("effects", null), false, catalog, context, issues)
	var flows_value: Variant = event.get("flows", null)
	if typeof(flows_value) != TYPE_ARRAY or flows_value.is_empty():
		_add_issue(issues, "error", "missing_flows", "event requires one or more flows", context)
		return
	var flow_keys: Dictionary = {}
	var flow_names: Dictionary = {}
	for flow_value: Variant in flows_value:
		if typeof(flow_value) != TYPE_DICTIONARY:
			_add_issue(issues, "error", "invalid_flow", "flow must be a dictionary", context)
			continue
		var flow_context := _context(flow_value, context)
		var flow_key := String(flow_value.get("flow_key", ""))
		var flow_name := String(flow_value.get("name", ""))
		if flow_key.is_empty():
			_add_issue(issues, "error", "missing_flow_key", "flow requires flow_key", flow_context)
		elif flow_keys.has(flow_key):
			_add_issue(issues, "error", "duplicate_flow_key", "flow_key must be unique within its event", flow_context)
		else:
			flow_keys[flow_key] = true
		if flow_name.is_empty():
			_add_issue(issues, "error", "missing_flow_name", "flow requires name", flow_context)
		elif flow_names.has(flow_name):
			_add_issue(issues, "error", "duplicate_flow_name", "flow name must be unique within its event", flow_context)
		else:
			flow_names[flow_name] = true
	if not flow_keys.has("start"):
		_add_issue(issues, "error", "missing_start_flow", "event requires a 흐름 · 시작 flow with flow_key start", context)
	for flow_value: Variant in flows_value:
		if typeof(flow_value) == TYPE_DICTIONARY:
			_validate_flow(flow_value, flow_keys, event_keys, catalog, characters, context, issues)

static func _validate_flow(flow: Dictionary, flow_keys: Dictionary, event_keys: Dictionary, catalog: NarrativeCatalog, characters: Resource, event_context: Dictionary, issues: Array[Dictionary]) -> void:
	var context := _context(flow, event_context)
	_validate_allowed_fields(flow, ["source_id", "source_url", "flow_key", "name", "comments", "effects", "blocks"], "invalid_flow", "flow", context, issues)
	_validate_required_text(flow, "source_id", context, issues)
	_validate_mappings(flow.get("effects", null), false, catalog, context, issues)
	var blocks_value: Variant = flow.get("blocks", null)
	if typeof(blocks_value) != TYPE_ARRAY or blocks_value.is_empty():
		_add_issue(issues, "error", "missing_blocks", "flow requires one or more ordered blocks", context)
		return
	for block_index: int in blocks_value.size():
		var block_value: Variant = blocks_value[block_index]
		if typeof(block_value) != TYPE_DICTIONARY:
			_add_issue(issues, "error", "invalid_block", "block must be a dictionary", context)
			continue
		_validate_block(block_value, block_index, blocks_value.size(), flow_keys, event_keys, catalog, characters, context, issues)

static func _validate_block(block: Dictionary, block_index: int, block_count: int, flow_keys: Dictionary, event_keys: Dictionary, catalog: NarrativeCatalog, characters: Resource, flow_context: Dictionary, issues: Array[Dictionary]) -> void:
	var context := _context(block, flow_context)
	_validate_required_text(block, "source_id", context, issues)
	var type := String(block.get("type", ""))
	match type:
		"line":
			_validate_allowed_fields(block, ["type", "source_id", "source_url", "block_key", "speaker", "expression", "text", "comments"], "invalid_line_block", "line block", context, issues)
			_validate_line(block, characters, context, issues)
			if block_index == block_count - 1:
				_add_issue(issues, "error", "unterminated_path", "line must fall through to another block", context)
		"command":
			_validate_allowed_fields(block, ["type", "source_id", "source_url", "block_key", "command_key", "arguments", "comments"], "invalid_command_block", "command block", context, issues)
			_validate_command(block, catalog, context, issues)
			if block_index == block_count - 1:
				_add_issue(issues, "error", "unterminated_path", "command must fall through to another block", context)
		"choice":
			_validate_allowed_fields(block, ["type", "source_id", "source_url", "block_key", "items", "comments"], "invalid_choice_block", "choice block", context, issues)
			_validate_choice(block, flow_keys, event_keys, catalog, context, issues)
		"jump":
			_validate_allowed_fields(block, ["type", "source_id", "source_url", "block_key", "target_kind", "target_key", "comments"], "invalid_jump_block", "jump block", context, issues)
			_validate_target(block, flow_keys, event_keys, context, issues)
		"end":
			_validate_end(block, context, issues)
		_:
			_add_issue(issues, "error", "unsupported_block_type", "block type is not supported", context)

static func _validate_line(block: Dictionary, characters: Resource, context: Dictionary, issues: Array[Dictionary]) -> void:
	var speaker := String(block.get("speaker", ""))
	var expression := String(block.get("expression", ""))
	if speaker.is_empty() or characters == null or not characters.has_method("has_character") or not characters.call("has_character", StringName(speaker)):
		_add_issue(issues, "error", "unknown_character", "line speaker is not registered", context)
	elif expression.is_empty() or not characters.has_method("has_expression") or not characters.call("has_expression", StringName(speaker), StringName(expression)):
		_add_issue(issues, "error", "unknown_expression", "line expression is not registered for its speaker", context)
	if typeof(block.get("text", null)) != TYPE_STRING or String(block.get("text", "")).is_empty():
		_add_issue(issues, "error", "missing_line_text", "line requires text", context)

static func _validate_end(block: Dictionary, context: Dictionary, issues: Array[Dictionary]) -> void:
	for field: Variant in block.keys():
		if field not in ["type", "source_id", "comments"]:
			_add_issue(issues, "error", "invalid_end_block", "end blocks allow only type, source_id, and comments", context)
			return

static func _validate_choice(block: Dictionary, flow_keys: Dictionary, event_keys: Dictionary, catalog: NarrativeCatalog, context: Dictionary, issues: Array[Dictionary]) -> void:
	var items_value: Variant = block.get("items", null)
	if typeof(items_value) != TYPE_ARRAY or items_value.is_empty():
		_add_issue(issues, "error", "missing_choice_items", "choice requires one or more items", context)
		return
	for item_value: Variant in items_value:
		if typeof(item_value) != TYPE_DICTIONARY:
			_add_issue(issues, "error", "invalid_choice_item", "choice item must be a dictionary", context)
			continue
		var item_context := _context(item_value, context)
		_validate_allowed_fields(item_value, ["source_id", "source_url", "choice_key", "text", "comments", "conditions", "effects", "target_kind", "target_key"], "invalid_choice_item", "choice item", item_context, issues)
		_validate_required_text(item_value, "source_id", item_context, issues)
		if typeof(item_value.get("text", null)) != TYPE_STRING or String(item_value.get("text", "")).is_empty():
			_add_issue(issues, "error", "missing_choice_text", "choice item requires text", item_context)
		_validate_mappings(item_value.get("conditions", null), true, catalog, item_context, issues)
		_validate_mappings(item_value.get("effects", null), false, catalog, item_context, issues)
		_validate_target(item_value, flow_keys, event_keys, item_context, issues)

static func _validate_target(value: Dictionary, flow_keys: Dictionary, event_keys: Dictionary, context: Dictionary, issues: Array[Dictionary]) -> void:
	var target_kind := String(value.get("target_kind", ""))
	var target_key := String(value.get("target_key", ""))
	if target_kind == "event" and target_key.contains(":"):
		_add_issue(issues, "error", "cross_bundle_target", "event targets must stay inside this bundle", context)
		return
	if target_kind == "flow":
		if not flow_keys.has(target_key):
			_add_issue(issues, "error", "dangling_target", "flow target does not exist in this event", context)
	elif target_kind == "event":
		if not event_keys.has(target_key):
			_add_issue(issues, "error", "dangling_target", "event target does not exist in this bundle", context)
	else:
		_add_issue(issues, "error", "invalid_target_kind", "target_kind must be flow or event", context)

static func _validate_command(block: Dictionary, catalog: NarrativeCatalog, context: Dictionary, issues: Array[Dictionary]) -> void:
	var command_key := String(block.get("command_key", ""))
	var command: Dictionary = _command(catalog, command_key)
	if command.is_empty():
		_add_issue(issues, "error", "unknown_command", "command is not registered in the narrative catalog", context)
		return
	var arguments: Variant = block.get("arguments", null)
	if typeof(arguments) != TYPE_DICTIONARY:
		_add_issue(issues, "error", "invalid_command_arguments", "command arguments must be a dictionary", context)
		return
	var allowed: Variant = command.get("arguments", {})
	if typeof(allowed) != TYPE_DICTIONARY:
		allowed = {}
	for argument_key: Variant in (arguments as Dictionary).keys():
		if not (allowed as Dictionary).has(argument_key):
			_add_issue(issues, "error", "unapproved_command_argument", "command argument is not allowed by the narrative catalog", context)
		elif not _matches_argument_type((arguments as Dictionary)[argument_key], String((allowed as Dictionary)[argument_key])):
			_add_issue(issues, "error", "invalid_command_argument_type", "command argument does not match the narrative catalog type", context)
	for allowed_key: Variant in (allowed as Dictionary).keys():
		if not (arguments as Dictionary).has(allowed_key):
			_add_issue(issues, "error", "missing_command_argument", "command argument required by the narrative catalog is missing", context)

static func _matches_argument_type(value: Variant, type_name: String) -> bool:
	match type_name:
		"bool":
			return typeof(value) == TYPE_BOOL
		"int":
			return typeof(value) == TYPE_INT
		"float":
			return typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT
		"string":
			return typeof(value) == TYPE_STRING
		"dictionary":
			return typeof(value) == TYPE_DICTIONARY
		"array":
			return typeof(value) == TYPE_ARRAY
	return false

static func _command(catalog: NarrativeCatalog, command_key: String) -> Dictionary:
	if catalog == null:
		return {}
	for command: Dictionary in catalog.commands():
		if String(command.get("key", "")) == command_key:
			return command
	return {}

static func _validate_mappings(value: Variant, condition: bool, catalog: NarrativeCatalog, context: Dictionary, issues: Array[Dictionary]) -> void:
	if typeof(value) != TYPE_ARRAY:
		_add_issue(issues, "error", "invalid_%s" % ("conditions" if condition else "effects"), "%s must be an array" % ("conditions" if condition else "effects"), context)
		return
	for record_value: Variant in value:
		if typeof(record_value) != TYPE_DICTIONARY:
			_add_issue(issues, "error", "invalid_mapping", "condition or effect must be a dictionary", context)
			continue
		_validate_allowed_fields(record_value, ["source_id", "source_url", "source_text", "term_name", "mapping_status", "kind", "key", "operator", "value", "comments"] if condition else ["source_id", "source_url", "source_text", "term_name", "mapping_status", "kind", "key", "value", "comments"], "invalid_condition" if condition else "invalid_effect", "condition" if condition else "effect", _context(record_value, context), issues)
		var result := catalog.validate_condition(record_value) if condition and catalog != null else catalog.validate_effect(record_value) if catalog != null else {"ok":false, "code":"invalid_catalog", "message":"narrative catalog is unavailable"}
		if not result.get("ok", false):
			_add_issue(issues, "error", String(result.get("code", "invalid_mapping")), String(result.get("message", "mapping is invalid")), context)

static func _validate_required_text(value: Dictionary, field: String, context: Dictionary, issues: Array[Dictionary]) -> void:
	if typeof(value.get(field, null)) != TYPE_STRING or String(value.get(field, "")).strip_edges().is_empty():
		_add_issue(issues, "error", "missing_%s" % field, "%s is required" % field, context)

static func _validate_allowed_fields(value: Dictionary, allowed_fields: Array, code: String, record_name: String, context: Dictionary, issues: Array[Dictionary]) -> void:
	for field: Variant in value.keys():
		if field not in allowed_fields:
			_add_issue(issues, "error", code, "%s contains unsupported field: %s" % [record_name, String(field)], context)

static func _context(value: Dictionary, parent := {}) -> Dictionary:
	return {"source_id":String(value.get("source_id", parent.get("source_id", ""))), "source_url":String(value.get("source_url", parent.get("source_url", ""))), "bundle_key":String(value.get("bundle_key", parent.get("bundle_key", ""))), "event_key":String(value.get("event_key", parent.get("event_key", ""))), "flow_key":String(value.get("flow_key", parent.get("flow_key", "")))}

static func _add_issue(issues: Array[Dictionary], severity: String, code: String, message: String, context: Dictionary) -> void:
	issues.append({"severity":severity, "code":code, "message":message, "source_id":context.get("source_id", ""), "source_url":context.get("source_url", ""), "bundle_key":context.get("bundle_key", ""), "event_key":context.get("event_key", ""), "flow_key":context.get("flow_key", "")})
