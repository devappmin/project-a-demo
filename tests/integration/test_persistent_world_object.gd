extends "res://tests/support/test_case.gd"

const MAP_SCENE = preload("res://game/world/map_scene.gd")
const PERSISTENT_WORLD_OBJECT_PATH := "res://game/world/persistent_world_object.gd"
const SAMPLE_INSPECTABLE = preload("res://content/interactables/sample_inspectable.tscn")
const NARRATIVE_STATE = preload("res://game/narrative/state/narrative_state.gd")

func run() -> void:
	var script := load(PERSISTENT_WORLD_OBJECT_PATH) as Script
	assert_not_null(script, "PersistentWorldObject script exists")
	if script == null:
		return
	await _test_registration(script)
	_test_mirror_state(script)

func _test_registration(script: Script) -> void:
	var map := MAP_SCENE.new()
	map.map_id = &"foundation"
	var empty: Node = script.new()
	map.add_child(empty)
	get_tree().root.add_child(map)
	await get_tree().process_frame
	assert_eq(empty.get("registration_error"), ERR_INVALID_PARAMETER, "persistent object rejects an empty ID")
	var first: Node = script.new()
	first.set("object_id", &"mirror")
	map.add_child(first)
	await get_tree().process_frame
	assert_eq(first.get("registration_error"), OK, "persistent object registers with its parent map")
	var duplicate: Node = script.new()
	duplicate.set("object_id", &"mirror")
	map.add_child(duplicate)
	await get_tree().process_frame
	assert_eq(duplicate.get("registration_error"), ERR_ALREADY_EXISTS, "duplicate object registration is rejected")
	map.queue_free()
	await get_tree().process_frame

func _test_mirror_state(script: Script) -> void:
	var inspectable := SAMPLE_INSPECTABLE.instantiate()
	var mirror := inspectable.get_node_or_null("PersistentWorldObject") as Node
	assert_not_null(mirror, "sample mirror owns a PersistentWorldObject")
	if mirror == null:
		inspectable.free()
		return
	assert_eq(mirror.get_script(), script, "sample mirror uses the persistent-world-object contract")
	assert_eq(mirror.get("object_id"), &"mirror", "sample mirror has a stable persistent object ID")
	var narrative_state := NARRATIVE_STATE.new()
	narrative_state.set_flag(&"mirror_seen", false)
	assert_eq(mirror.call("capture_persisted_state"), {"inspected": false}, "mirror captures its initial visual inspection state")
	assert_eq(mirror.call("apply_persisted_state", {"inspected": true}), OK, "mirror accepts persisted inspection state")
	assert_eq(mirror.call("capture_persisted_state"), {"inspected": true}, "mirror applies persisted inspection state")
	assert_eq(mirror.call("apply_persisted_state", {"inspected": "true"}), ERR_INVALID_DATA, "mirror rejects an invalid inspection value")
	assert_false(narrative_state.get_flag(&"mirror_seen"), "mirror visual persistence does not mutate NarrativeState dialogue truth")
	inspectable.free()
