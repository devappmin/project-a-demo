extends Node
class_name DialogueService

const GameModeResource = preload("res://app/session/game_mode.gd")
const DialogueRuntimeContractResource = preload("res://game/narrative/dialogue/dialogue_runtime_contract.gd")
const MAX_AUTOMATIC_STEPS := DialogueRuntimeContractResource.MAX_AUTOMATIC_STEPS

signal line_requested(character_key: StringName, expression: StringName, text: String)
signal choices_requested(items: Array[Dictionary])
signal command_requested(command: Dictionary)
signal finished
signal failed(context: Dictionary)

var graph_loader: DialogueGraphLoader
var narrative_state: NarrativeState
var game_session: Node
var current_graph: DialogueGraph
var current_node_id: StringName = &""

var _active := false
var _previous_mode := GameModeResource.Value.EXPLORATION
var _available_choices: Array[Dictionary] = []
var _deferred_failure_reason: StringName = &""
var _run_generation := 0
var _dispatch_state_by_generation: Dictionary = {}

func _ready() -> void:
	if graph_loader == null:
		graph_loader = DialogueGraphLoader.new()
	if game_session == null:
		game_session = get_node_or_null("/root/GameSession")
	if game_session != null:
		narrative_state = game_session.narrative_state

func _exit_tree() -> void:
	if not _active:
		return
	_rollback_dispatch_segment(_run_generation)
	_restore_previous_mode()
	_clear_active_state()

func start_dialogue(scene_key: StringName, node_id := &"") -> Error:
	if _active:
		return ERR_ALREADY_IN_USE
	if graph_loader == null:
		graph_loader = DialogueGraphLoader.new()
	var loaded_graph := graph_loader.load_scene(scene_key)
	if loaded_graph == null:
		_emit_failure({
			"reason": &"load_failed",
			"scene_key": scene_key,
			"node_id": node_id,
			"loader_failure": graph_loader.last_failure.duplicate(true),
		})
		return ERR_CANT_OPEN
	var entry_id: StringName = node_id if not node_id.is_empty() else loaded_graph.entry_node
	if loaded_graph.get_node(entry_id).is_empty():
		_emit_failure({"reason":&"invalid_entry", "scene_key":scene_key, "node_id":entry_id})
		return ERR_INVALID_PARAMETER
	if game_session == null:
		game_session = get_node_or_null("/root/GameSession")
	if game_session != null:
		narrative_state = game_session.narrative_state
	if game_session == null or narrative_state == null:
		_emit_failure({"reason":&"missing_dependency", "scene_key":scene_key, "node_id":entry_id})
		return ERR_UNCONFIGURED
	_previous_mode = game_session.current_mode
	if not game_session.change_mode(GameModeResource.Value.DIALOGUE):
		_emit_failure({"reason":&"mode_rejected", "scene_key":scene_key, "node_id":entry_id})
		return ERR_UNAVAILABLE
	_run_generation += 1
	current_graph = loaded_graph
	current_node_id = entry_id
	_available_choices.clear()
	_active = true
	return _dispatch_until_boundary()

func advance() -> void:
	if not _active or current_graph == null:
		return
	var node := current_graph.get_node(current_node_id)
	if String(node.get("type", "")) != "line":
		return
	var next_id := _next_node_id(node)
	if next_id.is_empty():
		_runtime_failure(ERR_INVALID_DATA, &"invalid_next")
		return
	current_node_id = next_id
	_dispatch_until_boundary()

func choose(index: int) -> Error:
	if not _active or current_graph == null:
		return ERR_UNAVAILABLE
	var node := current_graph.get_node(current_node_id)
	if String(node.get("type", "")) != "choice":
		return ERR_UNAVAILABLE
	if index < 0 or index >= _available_choices.size():
		return ERR_INVALID_PARAMETER
	var choice := _available_choices[index].duplicate(true)
	var state_before := narrative_state.snapshot()
	var effect_error := _apply_effects(choice.get("effects", []))
	if effect_error != OK:
		narrative_state.restore(state_before)
		return _runtime_failure(effect_error, &"effect_failed")
	var next_id := _next_node_id(choice)
	if next_id.is_empty():
		narrative_state.restore(state_before)
		return _runtime_failure(ERR_INVALID_DATA, &"invalid_next")
	_available_choices.clear()
	current_node_id = next_id
	_deferred_failure_reason = &""
	var dispatch_error := _dispatch_until_boundary(false, state_before)
	if dispatch_error != OK:
		narrative_state.restore(state_before)
		var failure_reason := _deferred_failure_reason if not _deferred_failure_reason.is_empty() else &"dispatch_failed"
		return _runtime_failure(dispatch_error, failure_reason)
	return dispatch_error

func abort_dialogue(reason: StringName) -> void:
	if not _active:
		return
	_runtime_failure(ERR_SKIP, reason)

func get_checkpoint() -> Dictionary:
	if not _active or current_graph == null:
		return {}
	return {
		"scene_key": String(current_graph.scene_key),
		"next_node_id": String(current_node_id),
	}.duplicate(true)

func _dispatch_until_boundary(publish_failure := true, transaction_state: Dictionary = {}) -> Error:
	var dispatch_generation := _run_generation
	var state_before: Dictionary = transaction_state.duplicate(true) if not transaction_state.is_empty() else narrative_state.snapshot()
	_dispatch_state_by_generation[dispatch_generation] = state_before.duplicate(true)
	var automatic_steps := 0
	while _active and _run_generation == dispatch_generation:
		var node := current_graph.get_node(current_node_id)
		if node.is_empty():
			return _dispatch_failure(ERR_INVALID_DATA, &"missing_node", publish_failure, state_before, dispatch_generation)
		var node_type := String(node.get("type", ""))
		match node_type:
			"line":
				_available_choices.clear()
				_complete_dispatch_segment(dispatch_generation)
				line_requested.emit(
					StringName(node.get("speaker", "")),
					StringName(node.get("expression", "")),
					String(node.get("text", ""))
				)
				return OK
			"choice":
				_available_choices = _filtered_choices(node.get("items", []))
				if _available_choices.is_empty():
					return _dispatch_failure(ERR_UNAVAILABLE, &"no_visible_choices", publish_failure, state_before, dispatch_generation)
				var public_items: Array[Dictionary] = []
				for item: Dictionary in _available_choices:
					public_items.append({"text":String(item.get("text", ""))})
				_complete_dispatch_segment(dispatch_generation)
				choices_requested.emit(public_items.duplicate(true))
				return OK
			"end":
				_complete_dispatch_segment(dispatch_generation)
				_finish_dialogue()
				return OK
			"effect", "command", "jump":
				if automatic_steps >= MAX_AUTOMATIC_STEPS:
					return _dispatch_failure(ERR_CYCLIC_LINK, &"dispatch_guard", publish_failure, state_before, dispatch_generation)
				automatic_steps += 1
				if node_type == "effect":
					var effect_error := _apply_effects(node.get("effects", []))
					if effect_error != OK:
						return _dispatch_failure(effect_error, &"effect_failed", publish_failure, state_before, dispatch_generation)
				elif node_type == "command":
					var command_value: Variant = node.get("command", {})
					if typeof(command_value) != TYPE_DICTIONARY:
						return _dispatch_failure(ERR_INVALID_DATA, &"invalid_command", publish_failure, state_before, dispatch_generation)
					var command: Dictionary = command_value
					command_requested.emit(command.duplicate(true))
					if not _active or _run_generation != dispatch_generation:
						_complete_dispatch_segment(dispatch_generation)
						return OK
				var next_id := _next_node_id(node)
				if next_id.is_empty():
					return _dispatch_failure(ERR_INVALID_DATA, &"invalid_next", publish_failure, state_before, dispatch_generation)
				current_node_id = next_id
			_:
				return _dispatch_failure(ERR_INVALID_DATA, &"unsupported_node", publish_failure, state_before, dispatch_generation)
	_complete_dispatch_segment(dispatch_generation)
	return OK

func _dispatch_failure(error: Error, reason: StringName, publish_failure: bool, state_before: Dictionary, dispatch_generation: int) -> Error:
	narrative_state.restore(state_before)
	_complete_dispatch_segment(dispatch_generation)
	if publish_failure:
		return _runtime_failure(error, reason)
	_deferred_failure_reason = reason
	return error

func _filtered_choices(items_value: Variant) -> Array[Dictionary]:
	var visible: Array[Dictionary] = []
	if typeof(items_value) != TYPE_ARRAY:
		return visible
	for item_value: Variant in items_value:
		if typeof(item_value) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = item_value
		var conditions_value: Variant = item.get("conditions", [])
		if typeof(conditions_value) != TYPE_ARRAY:
			continue
		var matches := true
		for condition_value: Variant in conditions_value:
			if typeof(condition_value) != TYPE_DICTIONARY or not ConditionEvaluator.matches(condition_value, narrative_state):
				matches = false
				break
		if matches:
			visible.append(item.duplicate(true))
	return visible

func _apply_effects(effects_value: Variant) -> Error:
	if typeof(effects_value) != TYPE_ARRAY:
		return ERR_INVALID_DATA
	for effect_value: Variant in effects_value:
		if typeof(effect_value) != TYPE_DICTIONARY:
			return ERR_INVALID_DATA
		var error := EffectExecutor.apply(effect_value, narrative_state)
		if error != OK:
			return error
	return OK

func _next_node_id(node: Dictionary) -> StringName:
	var next_value: Variant = node.get("next", "")
	if typeof(next_value) != TYPE_STRING and typeof(next_value) != TYPE_STRING_NAME:
		return &""
	var next_id := StringName(next_value)
	if next_id.is_empty() or current_graph == null or current_graph.get_node(next_id).is_empty():
		return &""
	return next_id

func _finish_dialogue() -> void:
	_restore_previous_mode()
	_clear_active_state()
	finished.emit()

func _runtime_failure(error: Error, reason: StringName) -> Error:
	_rollback_dispatch_segment(_run_generation)
	var context := {
		"reason": reason,
		"scene_key": current_graph.scene_key if current_graph != null else &"",
		"node_id": current_node_id,
		"error": error,
	}
	_restore_previous_mode()
	_clear_active_state()
	_emit_failure(context)
	return error

func _restore_previous_mode() -> void:
	if _active and game_session != null:
		game_session.change_mode(_previous_mode)

func _clear_active_state() -> void:
	_dispatch_state_by_generation.erase(_run_generation)
	_active = false
	current_graph = null
	current_node_id = &""
	_available_choices.clear()
	_deferred_failure_reason = &""
	_run_generation += 1

func _complete_dispatch_segment(generation: int) -> void:
	_dispatch_state_by_generation.erase(generation)

func _rollback_dispatch_segment(generation: int) -> void:
	var state_value: Variant = _dispatch_state_by_generation.get(generation)
	if narrative_state != null and typeof(state_value) == TYPE_DICTIONARY:
		narrative_state.restore(state_value)
	_dispatch_state_by_generation.erase(generation)

func _emit_failure(context: Dictionary) -> void:
	failed.emit(context.duplicate(true))
