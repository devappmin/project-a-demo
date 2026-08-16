extends RefCounted
class_name DialogueEventResolver

const EventIndexResource = preload("res://game/narrative/dialogue/dialogue_event_index.gd")
const ConditionEvaluatorResource = preload("res://game/narrative/conditions/condition_evaluator.gd")

var event_index: EventIndexResource

func resolve(bundle_key: StringName, trigger_key: StringName, state: NarrativeState) -> Dictionary:
	if state == null:
		return _failure(ERR_UNCONFIGURED, "missing_state")
	var index: EventIndexResource = _resolved_index()
	if index == null or not index.is_valid():
		return _failure(ERR_INVALID_DATA, "malformed_event_index")
	if not index.has_bundle(bundle_key):
		return _failure(ERR_DOES_NOT_EXIST, "unknown_bundle")
	if not index.has_trigger(bundle_key, trigger_key):
		return _failure(ERR_DOES_NOT_EXIST, "unknown_trigger")
	for candidate: Dictionary in index.candidates(bundle_key, trigger_key):
		if _all_conditions_match(candidate.get("conditions", []), state):
			return {
				"ok":true,
				"scene_key":bundle_key,
				"node_id":StringName(candidate["entry_node"]),
				"event_key":StringName(candidate["event_key"]),
			}
	return _failure(ERR_DOES_NOT_EXIST, "no_matching_event")

func _resolved_index() -> EventIndexResource:
	if event_index == null:
		event_index = EventIndexResource.load_default()
	return event_index

func _all_conditions_match(conditions_value: Variant, state: NarrativeState) -> bool:
	if typeof(conditions_value) != TYPE_ARRAY:
		return false
	for condition_value: Variant in conditions_value:
		if typeof(condition_value) != TYPE_DICTIONARY or not ConditionEvaluatorResource.matches(condition_value, state):
			return false
	return true

func _failure(error: Error, code: String) -> Dictionary:
	return {"ok":false, "error":error, "code":code}
