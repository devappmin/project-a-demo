extends "res://tools/dialogue_import/dialogue_import_cli.gd"

var captured_exit_code := -1
var captured_result: Dictionary = {}
var captured_lines: Dictionary = {}
var _arguments := PackedStringArray()

func _initialize() -> void:
	pass

func install(arguments: PackedStringArray) -> void:
	_arguments = arguments

func _get_arguments() -> PackedStringArray:
	return _arguments

func _present_result(result: Dictionary, dry_run: bool) -> void:
	captured_result = result.duplicate(true)
	captured_lines = format_result_lines(result, dry_run)

func _terminate(exit_code: int) -> void:
	captured_exit_code = exit_code
