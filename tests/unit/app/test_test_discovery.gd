extends "res://tests/support/test_case.gd"

func run() -> void:
	var discovery_script := load("res://tests/support/test_discovery.gd") as Script
	assert_not_null(discovery_script, "test discovery support exists")
	if discovery_script == null:
		return
	var discovery := discovery_script.new() as RefCounted
	var paths: PackedStringArray = discovery.call("collect_tests", "res://tests")
	var sorted_paths := paths.duplicate()
	sorted_paths.sort()
	assert_eq(paths, sorted_paths, "test suites are returned in deterministic sorted path order")
	for path in paths:
		assert_false(path.begins_with("res://tests/support/"), "support helpers are excluded from suite discovery")
	var selected: PackedStringArray = discovery.call("select_tests", paths, "map_scene")
	assert_eq(selected, PackedStringArray(["res://tests/unit/world/test_map_scene.gd"]), "filtering selects only matching suites")
	assert_eq(discovery.call("select_tests", paths, "definitely_missing_suite"), PackedStringArray(), "an unmatched filter selects zero suites")
	var invalid_result: Dictionary = discovery.call("instantiate_suite", "res://tests/fixtures/not_a_suite.gd")
	assert_eq(invalid_result.suite, null, "a script that is not a TestCase is rejected")
	assert_false(String(invalid_result.error).is_empty(), "an invalid suite returns a clear diagnostic instead of hanging")
