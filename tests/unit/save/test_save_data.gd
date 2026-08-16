extends "res://tests/support/test_case.gd"

const SAVE_DATA_PATH := "res://app/save/save_data.gd"

func run() -> void:
	var script := load(SAVE_DATA_PATH) as Script
	assert_not_null(script, "SaveData script exists")
	if script == null:
		return
	_test_schema_contract(script)
	_test_dialogue_contract(script)
	_test_json_domain(script)
	_test_canonical_checksum(script)
	_test_schema_version(script)

func _test_schema_contract(script: Script) -> void:
	var valid: Dictionary = script.call("with_checksum", _snapshot_without_checksum())
	assert_eq(script.call("validate", valid), [], "schema v1 accepts every required section and field")
	assert_eq(script.get("SLOT_IDS"), [&"auto", &"slot_1", &"slot_2", &"slot_3", &"slot_4", &"slot_5"], "the six supported slots are fixed")
	for section in ["schema_version", "checksum", "meta", "player", "narrative", "world", "dialogue"]:
		var missing := valid.duplicate(true)
		missing.erase(section)
		assert_false(script.call("validate", missing).is_empty(), "missing top-level %s is rejected" % section)
		var wrong_type := valid.duplicate(true)
		wrong_type[section] = []
		assert_false(script.call("validate", wrong_type).is_empty(), "top-level %s type is enforced" % section)
	var extra_top := valid.duplicate(true)
	extra_top["inventory"] = {}
	assert_false(script.call("validate", extra_top).is_empty(), "unknown top-level sections are rejected")
	for mutation in [
		{"path": ["meta", "slot_id"], "value": "slot_6", "label": "unknown slot"},
		{"path": ["meta", "saved_at"], "value": "16 August", "label": "non-ISO timestamp"},
		{"path": ["meta", "saved_at"], "value": "2026-99-99T25:61:61Z", "label": "impossible ISO timestamp"},
		{"path": ["meta", "play_time_seconds"], "value": -0.1, "label": "negative play time"},
		{"path": ["meta", "play_time_seconds"], "value": INF, "label": "non-finite play time"},
		{"path": ["meta", "location_name"], "value": "  ", "label": "empty display location"},
		{"path": ["player", "map_id"], "value": "missing_map", "label": "unregistered map"},
		{"path": ["player", "spawn_id"], "value": "missing_spawn", "label": "unregistered spawn"},
		{"path": ["player", "position", "x"], "value": NAN, "label": "non-finite position"},
		{"path": ["player", "facing"], "value": "diagonal", "label": "non-cardinal facing"},
	]:
		var candidate := valid.duplicate(true)
		_set_nested(candidate, mutation["path"], mutation["value"])
		assert_false(script.call("validate", candidate).is_empty(), "%s is rejected" % mutation["label"])
	for facing in ["up", "down", "left", "right"]:
		var candidate := valid.duplicate(true)
		candidate["player"]["facing"] = facing
		candidate = script.call("with_checksum", _without_checksum(candidate))
		assert_eq(script.call("validate", candidate), [], "%s is a supported facing" % facing)
	var incomplete_narrative := valid.duplicate(true)
	incomplete_narrative["narrative"].erase("collectibles")
	assert_false(script.call("validate", incomplete_narrative).is_empty(), "NarrativeState shape must be complete")
	var incomplete_world := valid.duplicate(true)
	incomplete_world["world"] = {}
	assert_false(script.call("validate", incomplete_world).is_empty(), "WorldState shape must contain maps")
	for case_data in [
		{"path": ["schema_version"], "value": "1", "label": "schema version type"},
		{"path": ["checksum"], "value": 123, "label": "checksum type"},
		{"path": ["meta", "slot_id"], "value": &"slot_1", "label": "slot type"},
		{"path": ["meta", "play_time_seconds"], "value": "1", "label": "play time type"},
		{"path": ["player", "position"], "value": [], "label": "position type"},
		{"path": ["narrative", "flags"], "value": [], "label": "narrative section type"},
		{"path": ["world", "maps"], "value": [], "label": "world maps type"},
		{"path": ["dialogue", "active"], "value": 1, "label": "dialogue active type"},
		{"path": ["dialogue", "bundle_key"], "value": 1, "label": "inactive dialogue context type"},
	]:
		var wrong_type := valid.duplicate(true)
		_set_nested(wrong_type, case_data["path"], case_data["value"])
		assert_false(script.call("validate", wrong_type).is_empty(), "%s is enforced" % case_data["label"])
	for section in ["meta", "player", "narrative", "world", "dialogue"]:
		var extra_field := valid.duplicate(true)
		extra_field[section]["unexpected"] = true
		assert_false(script.call("validate", extra_field).is_empty(), "%s rejects unknown fields" % section)

func _test_dialogue_contract(script: Script) -> void:
	var inactive: Dictionary = script.call("with_checksum", _snapshot_without_checksum())
	assert_eq(script.call("validate", inactive), [], "inactive dialogue accepts empty context")
	for key in ["bundle_key", "trigger_key", "node_id", "boundary"]:
		var dangling := inactive.duplicate(true)
		dangling["dialogue"][key] = "dangling"
		assert_false(script.call("validate", dangling).is_empty(), "inactive dialogue rejects dangling %s" % key)
	var active_source := _snapshot_without_checksum()
	active_source["dialogue"] = {
		"active": true,
		"bundle_key": "foundation.inspect",
		"trigger_key": "mirror.inspect",
		"node_id": "default.start.line_01",
		"boundary": "line",
	}
	for boundary in ["line", "choice"]:
		active_source["dialogue"]["boundary"] = boundary
		var active: Dictionary = script.call("with_checksum", active_source)
		assert_eq(script.call("validate", active), [], "active dialogue accepts a %s boundary" % boundary)
	for key in ["bundle_key", "trigger_key", "node_id"]:
		var missing := active_source.duplicate(true)
		missing["dialogue"][key] = ""
		var candidate: Dictionary = script.call("with_checksum", missing)
		assert_false(script.call("validate", candidate).is_empty(), "active dialogue requires %s" % key)
	active_source["dialogue"]["boundary"] = "end"
	assert_false(script.call("validate", script.call("with_checksum", active_source)).is_empty(), "active dialogue rejects an unstable boundary")

func _test_json_domain(script: Script) -> void:
	var forbidden_node := Node.new()
	var unsupported: Array = [forbidden_node, Resource.new(), Callable(), Vector2.ONE, StringName("named")]
	for value in unsupported:
		var candidate := _snapshot_without_checksum()
		candidate["narrative"]["inventory"] = {"nested": [value]}
		assert_eq(script.call("with_checksum", candidate), {}, "unsupported nested Variant type is rejected")
	for number in [NAN, INF, -INF]:
		var candidate := _snapshot_without_checksum()
		candidate["world"]["maps"] = {"foundation_room": {"mirror": {"value": number}}}
		assert_eq(script.call("with_checksum", candidate), {}, "non-finite nested number is rejected")
	for unsafe_integer in [9007199254740992, -9007199254740992]:
		var candidate := _snapshot_without_checksum()
		candidate["narrative"]["inventory"] = {"unsafe": unsafe_integer}
		assert_eq(script.call("with_checksum", candidate), {}, "integer outside exact JSON float range is rejected")
	forbidden_node.free()

func _test_canonical_checksum(script: Script) -> void:
	var literal_bytes: PackedByteArray = script.call("encode", {"z": 1, "a": {"b": 2, "a": [3, 1]}})
	assert_eq(literal_bytes.get_string_from_utf8(), "{\"a\":{\"a\":[3.0,1.0],\"b\":2.0},\"z\":1.0}", "canonical bytes use recursive key order and stable array order")
	var first := _snapshot_without_checksum()
	first["narrative"]["inventory"] = {"z": {"b": 2, "a": 1}, "a": [3, 2, 1]}
	var second := _snapshot_without_checksum()
	second["narrative"]["inventory"] = {"a": [3, 2, 1], "z": {"a": 1, "b": 2}}
	assert_eq(script.call("encode", first), script.call("encode", second), "dictionary keys are recursively sorted into deterministic bytes")
	var signed_first: Dictionary = script.call("with_checksum", first)
	var signed_second: Dictionary = script.call("with_checksum", second)
	assert_eq(signed_first["checksum"], signed_second["checksum"], "equivalent nested dictionaries have a stable checksum")
	assert_true(script.call("verify_checksum", signed_first), "checksum verifies before mutation")
	signed_first["narrative"]["inventory"]["a"] = [1, 2, 3]
	assert_false(script.call("verify_checksum", signed_first), "array order mutation is detected")
	var nested_checksum_source := _snapshot_without_checksum()
	nested_checksum_source["narrative"]["inventory"] = {"checksum": "nested-value"}
	var nested_checksum: Dictionary = script.call("with_checksum", nested_checksum_source)
	nested_checksum["narrative"]["inventory"]["checksum"] = "mutated"
	assert_false(script.call("verify_checksum", nested_checksum), "only the top-level checksum field is omitted")

func _test_schema_version(script: Script) -> void:
	var unsupported := _snapshot_without_checksum()
	unsupported["schema_version"] = 2
	assert_eq(script.call("migrate", unsupported), {}, "unsupported schema versions are not coerced")
	assert_eq(script.call("with_checksum", unsupported), {}, "unsupported schema versions cannot be signed")

func _snapshot_without_checksum(slot_id := "slot_1") -> Dictionary:
	return {
		"schema_version": 1,
		"meta": {
			"slot_id": slot_id,
			"saved_at": "2026-08-16T12:34:56Z",
			"play_time_seconds": 1234.0,
			"location_name": "기초 방",
		},
		"player": {
			"map_id": "foundation_room",
			"spawn_id": "start",
			"position": {"x": 120.0, "y": 88.0},
			"facing": "down",
		},
		"narrative": {
			"flags": {},
			"stats": {},
			"inventory": {},
			"quests": {},
			"collectibles": {},
		},
		"world": {"maps": {}},
		"dialogue": {
			"active": false,
			"bundle_key": "",
			"trigger_key": "",
			"node_id": "",
			"boundary": "",
		},
	}

func _without_checksum(snapshot: Dictionary) -> Dictionary:
	var result := snapshot.duplicate(true)
	result.erase("checksum")
	return result

func _set_nested(target: Dictionary, path: Array, value: Variant) -> void:
	var cursor := target
	for index in range(path.size() - 1):
		cursor = cursor[path[index]]
	cursor[path[-1]] = value
