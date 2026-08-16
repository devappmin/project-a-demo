extends Resource
class_name MapDefinition

@export var map_id: StringName
@export_file("*.tscn") var scene_path: String
@export var default_spawn: StringName = &"start"
@export var display_name: String = ""
