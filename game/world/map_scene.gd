extends Node2D
class_name MapScene

@export var map_id: StringName
@export var room_bounds := Rect2()

func validate_contract() -> PackedStringArray:
	var warnings := PackedStringArray()
	if String(map_id).strip_edges().is_empty():
		warnings.append("map_id must be nonempty.")
	var entry_points := get_node_or_null("EntryPoints")
	if entry_points == null:
		warnings.append("MapScene requires an EntryPoints child.")
	var entry_names := PackedStringArray()
	var direct_marker_count := 0
	if entry_points != null:
		for child in entry_points.get_children():
			if not child is Marker2D:
				continue
			direct_marker_count += 1
			entry_names.append(String(child.name))
	warnings.append_array(validate_entry_names(entry_names))
	if direct_marker_count == 0:
		warnings.append("EntryPoints requires at least one direct Marker2D child.")
	return warnings

func validate_entry_names(entry_names: PackedStringArray) -> PackedStringArray:
	var warnings := PackedStringArray()
	var seen_names := {}
	for raw_name in entry_names:
		var entry_name := raw_name.strip_edges()
		if entry_name.is_empty():
			warnings.append("Direct entry markers must have nonempty names.")
		elif seen_names.has(entry_name):
			warnings.append("Direct entry marker names must be unique: %s." % entry_name)
		else:
			seen_names[entry_name] = true
	return warnings

func _get_configuration_warnings() -> PackedStringArray:
	return validate_contract()

func _ready() -> void:
	var camera := get_node_or_null("Player/Camera2D") as Camera2D
	if camera == null or room_bounds.size == Vector2.ZERO:
		return
	camera.limit_left = int(room_bounds.position.x)
	camera.limit_top = int(room_bounds.position.y)
	camera.limit_right = int(room_bounds.end.x)
	camera.limit_bottom = int(room_bounds.end.y)
