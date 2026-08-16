extends Button
class_name SaveSlotRow

signal slot_activated(slot_id: StringName)

const SLOT_IDS := [&"auto", &"slot_1", &"slot_2", &"slot_3", &"slot_4", &"slot_5"]

@onready var slot_label: Label = $Content/SlotLabel
@onready var location_label: Label = $Content/Location
@onready var play_time_label: Label = $Content/PlayTime
@onready var saved_at_label: Label = $Content/SavedAt

var slot_id: StringName = &""
var _metadata := {}

func _ready() -> void:
	pressed.connect(activate)

func configure(metadata: Dictionary, mode: StringName) -> Error:
	var candidate_id := StringName(metadata.get("slot_id", ""))
	if candidate_id not in SLOT_IDS or mode not in [&"load", &"save"]:
		return ERR_INVALID_PARAMETER
	slot_id = candidate_id
	_metadata = metadata.duplicate(true)
	var exists: bool = _metadata.get("exists", false) == true
	var recoverable: bool = _metadata.get("recoverable", false) == true
	var read_only: bool = _metadata.get("read_only", slot_id == &"auto") == true
	var metadata_enabled: bool = _metadata.get("enabled", exists or recoverable) == true
	var can_activate: bool = metadata_enabled and (exists or recoverable) if mode == &"load" else not read_only
	disabled = not can_activate
	focus_mode = Control.FOCUS_NONE if disabled else Control.FOCUS_ALL
	slot_label.text = String(_metadata.get("label", _default_label(slot_id)))
	if exists or recoverable:
		location_label.text = String(_metadata.get("location_name", "알 수 없음"))
		play_time_label.text = _format_play_time(float(_metadata.get("play_time_seconds", 0.0)))
		saved_at_label.text = _format_timestamp(String(_metadata.get("saved_at", "")))
	else:
		location_label.text = "비어 있음"
		play_time_label.text = ""
		saved_at_label.text = ""
	tooltip_text = location_label.text
	return OK

func activate() -> void:
	if disabled or slot_id not in SLOT_IDS:
		return
	slot_activated.emit(slot_id)

func metadata() -> Dictionary:
	return _metadata.duplicate(true)

func _default_label(id: StringName) -> String:
	if id == &"auto":
		return "자동 저장"
	return "슬롯 %d" % (SLOT_IDS.find(id))

func _format_play_time(seconds: float) -> String:
	var total := maxi(0, int(floor(seconds)))
	return "%02d:%02d:%02d" % [total / 3600, (total % 3600) / 60, total % 60]

func _format_timestamp(value: String) -> String:
	var utc := Time.get_datetime_dict_from_datetime_string(value, false)
	if utc.is_empty():
		return ""
	var local_unix := Time.get_unix_time_from_datetime_dict(utc) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var local := Time.get_datetime_dict_from_unix_time(local_unix)
	return "%04d-%02d-%02d %02d:%02d" % [local.year, local.month, local.day, local.hour, local.minute]
