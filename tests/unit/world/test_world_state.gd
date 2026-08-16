extends "res://tests/support/test_case.gd"

const WORLD_STATE_PATH := "res://game/world/world_state.gd"
const GAME_SESSION_PATH := "res://app/session/game_session.gd"

func run() -> void:
	var script := load(WORLD_STATE_PATH) as Script
	assert_not_null(script, "WorldState script exists")
	if script == null:
		return
	var state: Variant = script.new()
	_test_backing_state_is_private(state)
	_test_identifiers_and_nesting(state)
	_test_deep_copy_boundaries(state)
	_test_round_trip_and_rejections(state)
	_test_session_replacement(script)

func _test_backing_state_is_private(state: Variant) -> void:
	var public_property_names := PackedStringArray()
	for property_data: Dictionary in state.get_property_list():
		public_property_names.append(property_data["name"])
	assert_false(&"maps" in public_property_names, "WorldState does not expose its backing dictionary for unvalidated mutation")

func _test_identifiers_and_nesting(state: Variant) -> void:
	for case_data: Dictionary in [
		{"map_id": &"", "object_id": &"mirror", "want": ERR_INVALID_PARAMETER},
		{"map_id": &"foundation", "object_id": &"", "want": ERR_INVALID_PARAMETER},
		{"map_id": &"   ", "object_id": &"mirror", "want": ERR_INVALID_PARAMETER},
		{"map_id": &"foundation", "object_id": &"mirror", "want": OK},
	]:
		assert_eq(state.call("set_object", case_data["map_id"], case_data["object_id"], {"inspected": true}), case_data["want"], "set_object validates nonempty map and object IDs")
	state.call("clear")
	assert_eq(state.call("set_object", &"a.b", &"c", {"value": 1}), OK, "first nested object is stored")
	assert_eq(state.call("set_object", &"a", &"b.c", {"value": 2}), OK, "punctuation cannot collide across map and object IDs")
	assert_eq(state.call("get_object", &"a.b", &"c"), {"value": 1}, "first nested object remains addressable")
	assert_eq(state.call("get_object", &"a", &"b.c"), {"value": 2}, "second nested object remains addressable")

func _test_deep_copy_boundaries(state: Variant) -> void:
	state.call("clear")
	var input := {"nested": {"values": [1, {"seen": false}]}}
	assert_eq(state.call("set_object", &"foundation", &"mirror", input), OK, "nested state is accepted")
	input["nested"]["values"][1]["seen"] = true
	var lookup: Dictionary = state.call("get_object", &"foundation", &"mirror")
	assert_eq(lookup, {"nested": {"values": [1, {"seen": false}]}}, "set_object deep-copies its input")
	lookup["nested"]["values"][1]["seen"] = true
	assert_eq(state.call("get_object", &"foundation", &"mirror"), {"nested": {"values": [1, {"seen": false}]}}, "get_object returns a deep copy")
	var snapshot: Dictionary = state.call("snapshot")
	snapshot["maps"]["foundation"]["mirror"]["nested"]["values"][1]["seen"] = true
	assert_eq(state.call("get_object", &"foundation", &"mirror"), {"nested": {"values": [1, {"seen": false}]}}, "snapshot returns a deep copy")

func _test_round_trip_and_rejections(state: Variant) -> void:
	state.call("clear")
	var exact := {"maps": {"foundation": {"mirror": {"inspected": true, "tags": ["first", {"level": 2}], "details": {"reflective": false}}}}}
	assert_eq(state.call("restore", exact), OK, "restore accepts the persisted maps section")
	assert_eq(state.call("snapshot"), exact, "nested primitive arrays and dictionaries round-trip exactly")
	exact["maps"]["foundation"]["mirror"]["tags"][1]["level"] = 9
	assert_eq(state.call("snapshot"), {"maps": {"foundation": {"mirror": {"inspected": true, "tags": ["first", {"level": 2}], "details": {"reflective": false}}}}}, "restore deep-copies its input")
	var string_name_keys := {"maps": {&"foundation": {&"mirror": {"inspected": true}}}}
	assert_eq(state.call("restore", string_name_keys), OK, "restore accepts StringName map and object IDs")
	var normalized_snapshot: Dictionary = state.call("snapshot")
	var restored_map_key: Variant = normalized_snapshot["maps"].keys()[0]
	var restored_object_key: Variant = normalized_snapshot["maps"][restored_map_key].keys()[0]
	assert_eq(typeof(restored_map_key), TYPE_STRING, "restore normalizes map keys to plain Strings")
	assert_eq(typeof(restored_object_key), TYPE_STRING, "restore normalizes object keys to plain Strings")
	var before: Dictionary = state.call("snapshot")
	var forbidden_node := Node.new()
	var forbidden_resource := Resource.new()
	var invalid_values: Array[Dictionary] = [
		{},
		{"maps": []},
		{"maps": {"foundation": []}},
		{"maps": {"foundation": {"mirror": []}}},
		{"maps": {"foundation": {"mirror": {"node": forbidden_node}}}},
		{"maps": {"foundation": {"mirror": {"resource": forbidden_resource}}}},
		{"maps": {"foundation": {"mirror": {"callable": Callable()}}}},
		{"maps": {"foundation": {"mirror": {"nan": NAN}}}},
		{"maps": {"foundation": {"mirror": {"infinity": INF}}}},
	]
	for invalid_data in invalid_values:
		assert_eq(state.call("restore", invalid_data), ERR_INVALID_DATA, "restore rejects invalid persisted values")
		assert_eq(state.call("snapshot"), before, "invalid restore is transactional")
	forbidden_node.free()

func _test_session_replacement(world_state_script: Script) -> void:
	var session_script := load(GAME_SESSION_PATH) as Script
	var session: Node = session_script.new()
	assert_true(session.has_method("reset_new_game"), "GameSession exposes new-game reset")
	assert_true(session.has_method("snapshot_session"), "GameSession exposes session snapshots")
	assert_true(session.has_method("restore_session"), "GameSession restores session snapshots")
	if not session.has_method("reset_new_game") or not session.has_method("snapshot_session") or not session.has_method("restore_session"):
		session.free()
		return
	var previous_world_state: Variant = session.get("world_state")
	previous_world_state.call("set_object", &"foundation", &"mirror", {"inspected": true})
	session.set("play_time_seconds", 42.5)
	session.call("reset_new_game")
	assert_true(session.get("world_state") != previous_world_state, "new-game reset replaces world state instead of mutating references")
	assert_eq(previous_world_state.call("get_object", &"foundation", &"mirror"), {"inspected": true}, "old world-state references remain unchanged")
	assert_eq(session.get("world_state").get_script(), world_state_script, "new-game reset creates a WorldState")
	assert_eq(session.get("play_time_seconds"), 0.0, "new-game reset clears play time")
	var snapshot: Dictionary = session.call("snapshot_session")
	assert_eq(session.call("restore_session", snapshot), OK, "session restores its own snapshot")
	var before: Dictionary = session.call("snapshot_session")
	assert_eq(session.call("restore_session", {"narrative_state": {}, "world_state": {}, "play_time_seconds": 1.0}), ERR_INVALID_DATA, "session rejects an incomplete world snapshot")
	assert_eq(session.call("snapshot_session"), before, "failed session restore preserves every session field")
	session.free()
