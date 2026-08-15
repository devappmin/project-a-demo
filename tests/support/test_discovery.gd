extends RefCounted

func collect_tests(path: String) -> PackedStringArray:
	var result := PackedStringArray()
	var normalized_path := path.trim_suffix("/")
	if normalized_path == "res://tests/support" or normalized_path.begins_with("res://tests/support/"):
		return result
	var directory := DirAccess.open(path)
	if directory == null:
		return result
	for child in directory.get_directories():
		result.append_array(collect_tests(path.path_join(child)))
	for file_name in directory.get_files():
		if file_name.begins_with("test_") and file_name.ends_with(".gd"):
			result.append(path.path_join(file_name))
	result.sort()
	return result

func select_tests(paths: PackedStringArray, selected_filter: String) -> PackedStringArray:
	if selected_filter.is_empty():
		return paths.duplicate()
	var selected := PackedStringArray()
	for path in paths:
		if path.contains(selected_filter):
			selected.append(path)
	return selected

func instantiate_suite(path: String) -> Dictionary:
	if not ResourceLoader.exists(path, "Script"):
		return {"suite": null, "error": "Unable to load test suite script: %s" % path}
	var suite_script := ResourceLoader.load(path, "Script", ResourceLoader.CACHE_MODE_IGNORE) as Script
	if suite_script == null:
		return {"suite": null, "error": "Unable to load test suite script: %s" % path}
	var candidate: Variant = suite_script.new()
	var suite := candidate as TestCase
	if suite == null:
		if candidate is Node:
			candidate.free()
		return {"suite": null, "error": "Test suite must extend TestCase: %s" % path}
	return {"suite": suite, "error": ""}
