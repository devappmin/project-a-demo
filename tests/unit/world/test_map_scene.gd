extends "res://tests/support/test_case.gd"

func run() -> void:
	var map := MapScene.new()
	assert_true(map.has_method("validate_contract"), "MapScene exposes runtime contract validation")
	if not map.has_method("validate_contract"):
		map.free()
		return
	assert_eq(map.validate_contract().size(), 3, "an empty map reports map ID, EntryPoints, and entry marker violations")
	map.map_id = &"test_room"
	assert_eq(map.validate_contract().size(), 2, "a map ID resolves only the map ID violation")
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
	assert_true(map.has_method("validate_entry_names"), "MapScene exposes entry-name validation for editor tooling")
	if map.has_method("validate_entry_names"):
		var name_warnings: PackedStringArray = map.call("validate_entry_names", PackedStringArray(["", "start", "start"]))
		assert_eq(name_warnings.size(), 2, "empty and duplicate entry marker names are both rejected")
	map.free()

	var room_scene := load("res://content/maps/foundation_room.tscn") as PackedScene
	var room := room_scene.instantiate() as MapScene
	assert_eq(room.validate_contract(), PackedStringArray(), "the shipped foundation room validates cleanly")
	assert_eq(room._get_configuration_warnings(), PackedStringArray(), "the editor warning contract matches runtime validation")
	room.free()
