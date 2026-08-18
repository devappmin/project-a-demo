extends SceneTree

const TestDiscovery = preload("res://tests/support/test_discovery.gd")

func _initialize() -> void:
	call_deferred("_run")

func _filter_value() -> String:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--filter")
	return args[index + 1] if index >= 0 and index + 1 < args.size() else ""

func _run() -> void:
	var failures: Array[String] = []
	var selected_filter := _filter_value()
	var discovery := TestDiscovery.new()
	var selected_paths := discovery.select_tests(discovery.collect_tests("res://tests"), selected_filter)
	print("Selected %d test suite(s)." % selected_paths.size())
	if not selected_filter.is_empty() and selected_paths.is_empty():
		printerr("No test suites matched filter: %s" % selected_filter)
		quit(1)
		return
	for path in selected_paths:
		var suite_result := discovery.instantiate_suite(path)
		var suite := suite_result.suite as TestCase
		if suite == null:
			failures.append(String(suite_result.error))
			continue
		root.add_child(suite)
		await suite.run()
		for failure in suite.failures:
			failures.append(path + ": " + failure)
		suite.queue_free()
	for failure in failures:
		printerr("TEST FAILURE: %s" % failure)
	print("Completed %d test suite(s)." % selected_paths.size())
	quit(1 if not failures.is_empty() else 0)
