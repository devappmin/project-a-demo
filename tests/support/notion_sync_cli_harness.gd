extends "res://tools/notion_sync/notion_sync_cli.gd"

var captured_exit_code := -1
var _arguments := PackedStringArray()
var _configuration := {}

func _initialize() -> void:
	pass

func install(arguments: PackedStringArray, configuration: Dictionary) -> void:
	_arguments = arguments
	_configuration = configuration

func _get_arguments() -> PackedStringArray:
	return _arguments

func _get_configuration() -> Dictionary:
	return _configuration

func _terminate(exit_code: int) -> void:
	captured_exit_code = exit_code
