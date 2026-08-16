extends Button
class_name SaveSlotRow

signal slot_activated(slot_id: StringName)

const SLOT_IDS := [&"auto", &"slot_1", &"slot_2", &"slot_3", &"slot_4", &"slot_5"]
const _TIMESTAMP_PATTERN := "^(\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2})(?:\\.\\d+)?(Z|([+-])(\\d{2}):(\\d{2}))$"

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
	var regex := RegEx.new()
	if regex.compile(_TIMESTAMP_PATTERN) != OK:
		return ""
	var match_result := regex.search(value)
	if match_result == null:
		return ""
	var source := Time.get_datetime_dict_from_datetime_string(match_result.get_string(1), false)
	if not _valid_datetime(source):
		return ""
	var source_offset_minutes := 0
	if match_result.get_string(2) != "Z":
		var offset_hours := int(match_result.get_string(4))
		var offset_minutes := int(match_result.get_string(5))
		if offset_hours > 23 or offset_minutes > 59:
			return ""
		source_offset_minutes = offset_hours * 60 + offset_minutes
		if match_result.get_string(3) == "-":
			source_offset_minutes = -source_offset_minutes
	var utc_unix := Time.get_unix_time_from_datetime_dict(source) - source_offset_minutes * 60
	var local_unix := utc_unix + int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var local := Time.get_datetime_dict_from_unix_time(local_unix)
	return "%04d-%02d-%02d %02d:%02d" % [local.year, local.month, local.day, local.hour, local.minute]

func _valid_datetime(value: Dictionary) -> bool:
	var year := int(value.get("year", 0))
	var month := int(value.get("month", 0))
	var day := int(value.get("day", 0))
	var hour := int(value.get("hour", -1))
	var minute := int(value.get("minute", -1))
	var second := int(value.get("second", -1))
	if year <= 0 or month < 1 or month > 12 or day < 1 or day > _days_in_month(year, month):
		return false
	return hour >= 0 and hour <= 23 and minute >= 0 and minute <= 59 and second >= 0 and second <= 59

func _days_in_month(year: int, month: int) -> int:
	if month == 2:
		return 29 if year % 400 == 0 or (year % 4 == 0 and year % 100 != 0) else 28
	return 30 if month in [4, 6, 9, 11] else 31
