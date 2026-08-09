extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _collect_tests(path: String) -> PackedStringArray:
	var result := PackedStringArray()
	var directory := DirAccess.open(path)
	if directory == null:
		return result
	for child in directory.get_directories():
		result.append_array(_collect_tests(path.path_join(child)))
	for file_name in directory.get_files():
		if file_name.begins_with("test_") and file_name.ends_with(".gd"):
			result.append(path.path_join(file_name))
	return result

func _filter_value() -> String:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--filter")
	return args[index + 1] if index >= 0 and index + 1 < args.size() else ""

func _run() -> void:
	var failures: Array[String] = []
	var selected_filter := _filter_value()
	for path in _collect_tests("res://tests"):
		if not selected_filter.is_empty() and not path.contains(selected_filter):
			continue
		var suite := (load(path) as Script).new() as TestCase
		root.add_child(suite)
		await suite.run()
		for failure in suite.failures:
			failures.append(path + ": " + failure)
		suite.queue_free()
	for failure in failures:
		printerr(failure)
	quit(1 if not failures.is_empty() else 0)
