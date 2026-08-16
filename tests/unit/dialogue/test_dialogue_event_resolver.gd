extends "res://tests/support/test_case.gd"

const INDEX_PATH := "res://game/narrative/dialogue/dialogue_event_index.gd"
const RESOLVER_PATH := "res://game/narrative/dialogue/dialogue_event_resolver.gd"
const STATE_PATH := "res://game/narrative/state/narrative_state.gd"

func run() -> void:
	assert_true(ResourceLoader.exists(INDEX_PATH, "Script"), "dialogue event index script exists")
	assert_true(ResourceLoader.exists(RESOLVER_PATH, "Script"), "dialogue event resolver script exists")
	if not ResourceLoader.exists(INDEX_PATH, "Script") or not ResourceLoader.exists(RESOLVER_PATH, "Script"):
		return
	var index_script: Script = load(INDEX_PATH)
	var resolver_script: Script = load(RESOLVER_PATH)
	var state_script: Script = load(STATE_PATH)
	_test_first_matching_event_wins(index_script, resolver_script, state_script)
	_test_resolution_failures_do_not_mutate(index_script, resolver_script, state_script)
	_test_malformed_index_fails_closed(index_script, resolver_script, state_script)
	_test_index_loading_and_candidate_ownership(index_script)

func _test_first_matching_event_wins(index_script: Script, resolver_script: Script, state_script: Script) -> void:
	var resolver: RefCounted = resolver_script.new()
	resolver.event_index = index_script.from_dictionary(_event_index())
	var state: RefCounted = state_script.new()
	var first: Dictionary = resolver.resolve(&"foundation.inspect", &"mirror.inspect", state)
	assert_true(first.get("ok", false), "fallback resolution succeeds")
	assert_eq(first.get("scene_key"), &"foundation.inspect", "resolution returns the bundle scene key")
	assert_eq(first.get("node_id"), &"default.start.line_01", "fallback returns its entry node")
	assert_eq(first.get("event_key"), &"default", "fallback runs before the flag is set")
	state.set_flag(&"mirror_seen", true)
	var specific: Dictionary = resolver.resolve(&"foundation.inspect", &"mirror.inspect", state)
	assert_true(specific.get("ok", false), "specific resolution succeeds")
	assert_eq(specific.get("event_key"), &"seen", "first matching specific event wins")
	assert_eq(specific.get("node_id"), &"seen.start.line_01", "specific event keeps its entry node")

func _test_resolution_failures_do_not_mutate(index_script: Script, resolver_script: Script, state_script: Script) -> void:
	var resolver: RefCounted = resolver_script.new()
	resolver.event_index = index_script.from_dictionary(_event_index(false))
	var state: RefCounted = state_script.new()
	state.set_stat(&"jellyppo_trust", 3.0)
	var before: Dictionary = state.snapshot()
	var unknown_bundle: Dictionary = resolver.resolve(&"missing.bundle", &"mirror.inspect", state)
	assert_false(unknown_bundle.get("ok", true), "unknown bundle is rejected")
	assert_eq(unknown_bundle.get("code"), "unknown_bundle", "unknown bundle has a stable code")
	assert_eq(state.snapshot(), before, "unknown bundle cannot mutate state")
	var unknown_trigger: Dictionary = resolver.resolve(&"foundation.inspect", &"missing.trigger", state)
	assert_false(unknown_trigger.get("ok", true), "unknown trigger is rejected")
	assert_eq(unknown_trigger.get("code"), "unknown_trigger", "unknown trigger has a stable code")
	assert_eq(state.snapshot(), before, "unknown trigger cannot mutate state")
	var no_match: Dictionary = resolver.resolve(&"foundation.inspect", &"mirror.inspect", state)
	assert_false(no_match.get("ok", true), "no matching event is observable")
	assert_eq(no_match.get("code"), "no_matching_event", "no-match has a stable code")
	assert_eq(no_match.get("error"), ERR_DOES_NOT_EXIST, "no-match returns a real Error")
	assert_eq(state.snapshot(), before, "failed condition checks cannot mutate state")
	var missing_state: Dictionary = resolver.resolve(&"foundation.inspect", &"mirror.inspect", null)
	assert_false(missing_state.get("ok", true), "missing state is rejected")
	assert_eq(missing_state.get("code"), "missing_state", "missing state has a stable code")

func _test_malformed_index_fails_closed(index_script: Script, resolver_script: Script, state_script: Script) -> void:
	var malformed := _event_index()
	malformed["bundles"]["foundation.inspect"]["triggers"]["mirror.inspect"][0]["conditions"] = [{"kind":"flag"}]
	var index: RefCounted = index_script.from_dictionary(malformed)
	assert_false(index.is_valid(), "malformed candidate condition invalidates the entire index")
	assert_eq(index.last_failure.get("code"), "invalid_condition", "malformed condition has a stable loader failure")
	assert_eq(index.candidates(&"foundation.inspect", &"mirror.inspect"), [], "malformed roots are never partially accepted")
	var resolver: RefCounted = resolver_script.new()
	resolver.event_index = index
	var state: RefCounted = state_script.new()
	var before: Dictionary = state.snapshot()
	var result: Dictionary = resolver.resolve(&"foundation.inspect", &"mirror.inspect", state)
	assert_false(result.get("ok", true), "malformed event index blocks resolution")
	assert_eq(result.get("code"), "malformed_event_index", "malformed index has a stable resolver code")
	assert_eq(result.get("error"), ERR_INVALID_DATA, "malformed index returns a real Error")
	assert_eq(state.snapshot(), before, "malformed index cannot mutate state")

func _test_index_loading_and_candidate_ownership(index_script: Script) -> void:
	var blank: RefCounted = index_script.new()
	assert_false(blank.is_valid(), "an index is invalid until validated data is installed")
	var invalid_schema: RefCounted = index_script.from_dictionary({"schema_version":2, "bundles":{}})
	assert_false(invalid_schema.is_valid(), "unsupported event index schema is rejected")
	assert_eq(invalid_schema.last_failure.get("code"), "unsupported_schema", "schema rejection has a stable code")
	var index: RefCounted = index_script.from_dictionary(_event_index())
	var first_copy: Array[Dictionary] = index.candidates(&"foundation.inspect", &"mirror.inspect")
	first_copy[0]["conditions"][0]["value"] = false
	first_copy[0]["event_key"] = "mutated"
	var second_copy: Array[Dictionary] = index.candidates(&"foundation.inspect", &"mirror.inspect")
	assert_eq(second_copy[0]["event_key"], "seen", "candidate dictionaries are returned as copies")
	assert_eq(second_copy[0]["conditions"][0]["value"], true, "nested candidate data is returned as a deep copy")
	var output_dir := "user://test-output/dialogue-event-index-%s" % Time.get_ticks_usec()
	var absolute_dir := ProjectSettings.globalize_path(output_dir)
	assert_eq(DirAccess.make_dir_recursive_absolute(absolute_dir), OK, "temporary event index directory is created")
	var path := output_dir.path_join("events.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file, "temporary event index opens for writing")
	if file != null:
		file.store_string(JSON.stringify(_event_index()))
		file.close()
		var loaded: RefCounted = index_script.load_path(path)
		assert_true(loaded.is_valid(), "event index loads from an injected local path")
		assert_eq(loaded.candidates(&"foundation.inspect", &"mirror.inspect").size(), 2, "loaded index preserves candidate order")
	var absolute_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(absolute_path):
		DirAccess.remove_absolute(absolute_path)
	if DirAccess.dir_exists_absolute(absolute_dir):
		DirAccess.remove_absolute(absolute_dir)

func _event_index(with_fallback := true) -> Dictionary:
	var candidates: Array[Dictionary] = [{
		"event_key":"seen",
		"entry_node":"seen.start.line_01",
		"conditions":[{"kind":"flag", "key":"mirror_seen", "operator":"eq", "value":true}],
	}]
	if with_fallback:
		candidates.append({"event_key":"default", "entry_node":"default.start.line_01", "conditions":[]})
	return {
		"schema_version":1,
		"bundles":{
			"foundation.inspect":{
				"triggers":{
					"mirror.inspect":candidates,
				},
			},
		},
	}
