extends "res://tests/support/test_case.gd"

func run() -> void:
	var map := MapScene.new()
	assert_true(map.has_method("validate_contract"), "MapScene exposes runtime contract validation")
	if not map.has_method("validate_contract"):
		map.free()
		return
	assert_eq(map.validate_contract().size(), 5, "an empty map reports map ID, all required roots, and entry marker violations")
	map.map_id = &"test_room"
	assert_eq(map.validate_contract().size(), 4, "a map ID resolves only the map ID violation")
	var actors := Node2D.new()
	actors.name = "Actors"
	map.add_child(actors)
	var visual_sort := Node2D.new()
	visual_sort.name = "VisualSort"
	map.add_child(visual_sort)
	var entry_points := Node2D.new()
	entry_points.name = "EntryPoints"
	map.add_child(entry_points)
	assert_eq(map.validate_contract().size(), 1, "EntryPoints without a direct marker remains invalid")
	var nested := Node2D.new()
	nested.name = "Nested"
	entry_points.add_child(nested)
	var nested_marker := Marker2D.new()
	nested_marker.name = "nested_start"
	nested.add_child(nested_marker)
	assert_eq(map.validate_contract().size(), 1, "nested markers do not satisfy the direct entry marker contract")
	var start := Marker2D.new()
	start.name = "start"
	entry_points.add_child(start)
	assert_eq(map.validate_contract(), PackedStringArray(), "a named direct Marker2D satisfies the map contract")
	assert_true(map.has_method("get_spawn"), "MapScene exposes stable spawn lookup")
	if map.has_method("get_spawn"):
		assert_eq(map.call("get_spawn", &"start"), start, "spawn lookup returns the stable direct marker")
		assert_eq(map.call("get_spawn", &"missing"), null, "missing spawns return null")
	assert_true(map.has_method("get_actor_root"), "MapScene exposes its direct actor root")
	if map.has_method("get_actor_root"):
		assert_eq(map.call("get_actor_root"), actors, "map exposes its direct actor root")
	assert_true(map.has_method("get_visual_root"), "MapScene exposes its direct visual root")
	if map.has_method("get_visual_root"):
		assert_eq(map.call("get_visual_root"), visual_sort, "map exposes its direct visual root")
	assert_true(map.has_method("validate_entry_names"), "MapScene exposes entry-name validation for editor tooling")
	if map.has_method("validate_entry_names"):
		var name_warnings: PackedStringArray = map.call("validate_entry_names", PackedStringArray(["", "start", "start"]))
		assert_eq(name_warnings.size(), 2, "empty and duplicate entry marker names are both rejected")
	var first_object := PersistentWorldObject.new()
	first_object.object_id = &" mirror "
	visual_sort.add_child(first_object)
	var duplicate_object := PersistentWorldObject.new()
	duplicate_object.object_id = &"mirror"
	visual_sort.add_child(duplicate_object)
	var duplicate_warnings := map.validate_contract()
	assert_eq(duplicate_warnings.size(), 1, "off-tree map validation rejects trimmed duplicate persistent object IDs")
	if not duplicate_warnings.is_empty():
		assert_true(duplicate_warnings[0].contains("mirror"), "duplicate persistent object warning identifies the normalized ID")
	assert_eq(map._get_configuration_warnings(), duplicate_warnings, "editor validation surfaces duplicate persistent object IDs")
	var world_state := WorldState.new()
	assert_eq(world_state.set_object(&"test_room", &"mirror", {"inspected": true}), OK, "duplicate fail-closed test seeds a literal world state")
	var world_before := world_state.snapshot()
	assert_eq(map.capture_world_objects(world_state), ERR_ALREADY_EXISTS, "capture rejects duplicate persistent object IDs before writing WorldState")
	assert_eq(world_state.snapshot(), world_before, "duplicate capture leaves WorldState byte-equivalent")
	assert_eq(map.apply_world_objects(world_state), ERR_ALREADY_EXISTS, "apply rejects duplicate persistent object IDs before mutating live objects")
	assert_eq(first_object.capture_persisted_state(), {"inspected": false}, "duplicate apply leaves the first live object unchanged")
	visual_sort.remove_child(duplicate_object)
	duplicate_object.free()
	first_object.object_id = &"  "
	var empty_id_warnings := map.validate_contract()
	assert_eq(empty_id_warnings.size(), 1, "off-tree map validation rejects a whitespace-only persistent object ID")
	map.free()

	var room_scene := load("res://content/maps/foundation_room.tscn") as PackedScene
	var room := room_scene.instantiate() as MapScene
	assert_eq(room.validate_contract(), PackedStringArray(), "the shipped foundation room validates cleanly")
	assert_eq(room._get_configuration_warnings(), PackedStringArray(), "the editor warning contract matches runtime validation")
	if room.has_method("get_actor_root"):
		assert_not_null(room.call("get_actor_root"), "the shipped room has a direct actor root")
	if room.has_method("get_visual_root"):
		assert_not_null(room.call("get_visual_root"), "the shipped room has a direct visual root")
	room.free()
