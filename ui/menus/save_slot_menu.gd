extends Control
class_name SaveSlotMenu

signal slot_requested(slot_id: StringName)
signal back_requested

const SaveSlotRowScene = preload("res://ui/menus/save_slot_row.tscn")
const SLOT_IDS := [&"auto", &"slot_1", &"slot_2", &"slot_3", &"slot_4", &"slot_5"]

@onready var title_label: Label = $Panel/Margin/Layout/Title
@onready var rows_container: VBoxContainer = $Panel/Margin/Layout/Rows
@onready var back_button: Button = $Panel/Margin/Layout/Back

var _mode: StringName = &"load"
var _metadata: Array[Dictionary] = []
var _rows: Array[Button] = []
var _focus_before_busy: StringName = &""

func _ready() -> void:
	_ensure_rows()
	back_button.pressed.connect(_request_back)

func open(mode: StringName, metadata: Array[Dictionary]) -> Error:
	if mode not in [&"load", &"save"]:
		return ERR_INVALID_PARAMETER
	_mode = mode
	_focus_before_busy = &""
	title_label.text = "불러오기" if mode == &"load" else "저장"
	visible = true
	return refresh(metadata)

func refresh(metadata: Array[Dictionary]) -> Error:
	_ensure_rows()
	var focused_slot := _focused_slot_id()
	if focused_slot.is_empty():
		focused_slot = _focus_before_busy
	_metadata = []
	var by_id := {}
	for item: Dictionary in metadata:
		var slot_id: StringName = StringName(item.get("slot_id", ""))
		if slot_id in SLOT_IDS:
			by_id[slot_id] = item.duplicate(true)
	for index: int in SLOT_IDS.size():
		var slot_id: StringName = SLOT_IDS[index]
		var item: Dictionary = by_id.get(slot_id, {"slot_id": slot_id, "exists": false}).duplicate(true)
		item["slot_id"] = slot_id
		item["label"] = "자동 저장" if index == 0 else "슬롯 %d" % index
		item["read_only"] = index == 0
		item["exists"] = item.get("exists", false) == true
		item["recoverable"] = item.get("recoverable", false) == true
		item["enabled"] = item.get("enabled", item["exists"] or item["recoverable"]) == true
		_metadata.append(item.duplicate(true))
		_rows[index].configure(item, _mode)
	_update_focus_neighbors()
	call_deferred("_restore_focus", focused_slot)
	return OK

func close() -> void:
	visible = false

func set_busy(busy: bool) -> void:
	if busy:
		var focused_slot := _focused_slot_id()
		if not focused_slot.is_empty():
			_focus_before_busy = focused_slot
	for row: Button in _rows:
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE if busy else Control.MOUSE_FILTER_STOP
		row.disabled = busy or not _row_enabled(row.slot_id)
		row.focus_mode = Control.FOCUS_NONE if row.disabled else Control.FOCUS_ALL
	back_button.disabled = busy
	_update_focus_neighbors()
	if not busy:
		call_deferred("_restore_focus", _focus_before_busy)

func get_rows() -> Array:
	return _rows.duplicate()

func mode() -> StringName:
	return _mode

func metadata_for(slot_id: StringName) -> Dictionary:
	for item: Dictionary in _metadata:
		if item.get("slot_id") == slot_id:
			return item.duplicate(true)
	return {}

func focus_first_available() -> void:
	_restore_focus(&"")

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_request_back()
		get_viewport().set_input_as_handled()

func _ensure_rows() -> void:
	if not _rows.is_empty() or rows_container == null:
		return
	for slot_id: StringName in SLOT_IDS:
		var row := SaveSlotRowScene.instantiate() as Button
		if row == null:
			continue
		row.name = String(slot_id)
		row.slot_activated.connect(_on_slot_activated)
		rows_container.add_child(row)
		_rows.append(row)

func _on_slot_activated(slot_id: StringName) -> void:
	if slot_id in SLOT_IDS and not _rows[SLOT_IDS.find(slot_id)].disabled:
		slot_requested.emit(slot_id)

func _request_back() -> void:
	if not back_button.disabled:
		back_requested.emit()

func _focused_slot_id() -> StringName:
	var focus := get_viewport().gui_get_focus_owner()
	if focus is Button and focus in _rows:
		return focus.slot_id
	return &""

func _restore_focus(preferred: StringName) -> void:
	if not visible:
		return
	if preferred in SLOT_IDS:
		var preferred_row: Button = _rows[SLOT_IDS.find(preferred)]
		if not preferred_row.disabled:
			preferred_row.grab_focus()
			return
	for row: Button in _rows:
		if not row.disabled:
			row.grab_focus()
			return
	back_button.grab_focus()

func _row_enabled(slot_id: StringName) -> bool:
	var item: Dictionary = metadata_for(slot_id)
	if _mode == &"save":
		return slot_id != &"auto"
	return item.get("enabled", false) and (item.get("exists", false) or item.get("recoverable", false))

func _update_focus_neighbors() -> void:
	var enabled_rows: Array[Button] = []
	for row: Button in _rows:
		if not row.disabled:
			enabled_rows.append(row)
	for index: int in enabled_rows.size():
		var row: Button = enabled_rows[index]
		row.focus_neighbor_top = row.get_path_to(enabled_rows[maxi(0, index - 1)])
		row.focus_neighbor_bottom = row.get_path_to(enabled_rows[mini(enabled_rows.size() - 1, index + 1)])
	if not enabled_rows.is_empty():
		back_button.focus_neighbor_top = back_button.get_path_to(enabled_rows[-1])
		enabled_rows[-1].focus_neighbor_bottom = enabled_rows[-1].get_path_to(back_button)
		back_button.focus_neighbor_bottom = back_button.get_path_to(enabled_rows[0])
