extends "res://tests/support/test_case.gd"

const MENU_PATH := "res://ui/menus/save_slot_menu.tscn"

func run() -> void:
	assert_true(ResourceLoader.exists(MENU_PATH), "the reusable save-slot menu scene exists")
	if not ResourceLoader.exists(MENU_PATH):
		return
	await _test_six_ordered_rows_fit_the_pixel_viewport()
	await _test_load_and_save_enablement_routes_only_fixed_slot_ids()
	await _test_populated_metadata_formatting_and_clipping()
	await _test_refresh_copies_metadata_and_keeps_focus()
	await _test_keyboard_navigation_skips_disabled_rows()
	await _test_recovery_toast_does_not_overlap_back_action()

func _test_six_ordered_rows_fit_the_pixel_viewport() -> void:
	var menu := await _make_menu(&"load", _metadata_fixture())
	var rows: Array = menu.call("get_rows")
	assert_eq(rows.size(), 6, "the list always renders exactly six rows")
	var slot_ids: Array[StringName] = []
	for row: Control in rows:
		slot_ids.append(row.get("slot_id"))
	assert_eq(slot_ids, [&"auto", &"slot_1", &"slot_2", &"slot_3", &"slot_4", &"slot_5"], "rows are ordered autosave then manual slots 1 through 5")
	assert_false(_contains_type(menu, "ScrollContainer"), "the six-row list does not use scrolling")
	assert_false(_contains_named_control(menu, "screenshot"), "slot UI has no screenshot control")
	for row: Control in rows:
		var row_rect := row.get_global_rect()
		assert_true(row_rect.position.y >= 52.0, "each row starts inside the approved safe UI area")
		assert_true(row_rect.end.y <= 300.0, "each row ends inside the approved 300px safe boundary")
		assert_true(row_rect.end.x <= 612.0, "each row fits the 640px logical viewport")
	await _free_menu(menu)

func _test_load_and_save_enablement_routes_only_fixed_slot_ids() -> void:
	var load_menu := await _make_menu(&"load", _metadata_fixture())
	var load_rows: Array = load_menu.call("get_rows")
	var requested: Array[StringName] = []
	load_menu.connect("slot_requested", func(slot_id: StringName) -> void: requested.append(slot_id))
	assert_false((load_rows[0] as Button).disabled, "an existing autosave is loadable")
	assert_true((load_rows[2] as Button).disabled, "an empty load slot is disabled")
	(load_rows[2] as Node).call("activate")
	assert_true(requested.is_empty(), "an empty load slot cannot emit a load request")
	(load_rows[0] as Node).call("activate")
	assert_eq(requested, [&"auto"], "a load action carries only the fixed autosave ID")
	await _free_menu(load_menu)

	var save_menu := await _make_menu(&"save", _metadata_fixture())
	var save_rows: Array = save_menu.call("get_rows")
	requested.clear()
	save_menu.connect("slot_requested", func(slot_id: StringName) -> void: requested.append(slot_id))
	assert_true((save_rows[0] as Button).disabled, "autosave is read-only in save mode")
	assert_false((save_rows[1] as Button).disabled, "a populated manual row is saveable")
	assert_false((save_rows[2] as Button).disabled, "an empty manual row is saveable")
	(save_rows[0] as Node).call("activate")
	(save_rows[2] as Node).call("activate")
	assert_eq(requested, [&"slot_2"], "save mode emits only a selected manual slot ID")
	await _free_menu(save_menu)

func _test_populated_metadata_formatting_and_clipping() -> void:
	var metadata := _metadata_fixture()
	metadata[1]["location_name"] = "기초 연구동의 아주 길고 긴 보존 회랑과 절대로 행을 밀어내면 안 되는 장소 이름"
	var menu := await _make_menu(&"load", metadata)
	var rows: Array = menu.call("get_rows")
	var auto_row := rows[0] as Control
	assert_eq(auto_row.get_node("Content/Location").text, "기초 홀", "a populated row renders its location")
	assert_eq(auto_row.get_node("Content/PlayTime").text, "00:20:34", "play time renders as HH:MM:SS")
	var timestamp_cases := [
		{"value": "2026-08-16T12:34:56Z", "expected": "2026-08-16 21:34", "label": "UTC Z"},
		{"value": "2026-08-16T21:34:56+09:00", "expected": "2026-08-16 21:34", "label": "positive source offset"},
		{"value": "2026-08-16T08:34:56-04:00", "expected": "2026-08-16 21:34", "label": "negative source offset"},
		{"value": "not-a-timestamp", "expected": "", "label": "malformed timestamp"},
	]
	for case_data: Dictionary in timestamp_cases:
		var item: Dictionary = metadata[0].duplicate(true)
		item["saved_at"] = case_data["value"]
		assert_eq(auto_row.call("configure", item, &"load"), OK, "%s timestamp fixture configures" % case_data["label"])
		assert_eq(auto_row.get_node("Content/SavedAt").text, case_data["expected"], "%s is interpreted as an instant and rendered in Korea local time" % case_data["label"])
	var long_row := rows[1] as Control
	var location := long_row.get_node("Content/Location") as Label
	assert_true(location.clip_text, "long locations are clipped within the location cell")
	assert_true(location.get_global_rect().end.x <= long_row.get_global_rect().end.x, "long location content stays within its row")
	assert_eq(long_row.size.y, auto_row.size.y, "long locations never change row height")
	await _free_menu(menu)

func _test_refresh_copies_metadata_and_keeps_focus() -> void:
	var metadata := _metadata_fixture()
	var menu := await _make_menu(&"load", metadata)
	var rows: Array = menu.call("get_rows")
	var slot_one := rows[1] as Control
	slot_one.grab_focus()
	await get_tree().process_frame
	metadata[1]["location_name"] = "외부에서 바뀐 이름"
	assert_eq(slot_one.get_node("Content/Location").text, "젤리뽀 집", "rendered metadata is isolated from caller mutation")
	var refreshed := _metadata_fixture()
	refreshed[1]["location_name"] = "기초 홀"
	menu.call("refresh", refreshed)
	await get_tree().process_frame
	rows = menu.call("get_rows")
	assert_eq((menu.get_viewport().gui_get_focus_owner() as Node).get("slot_id"), &"slot_1", "refresh retains the focused slot when it remains enabled")
	refreshed[1]["location_name"] = "새 외부 변경"
	assert_eq((rows[1] as Control).get_node("Content/Location").text, "기초 홀", "refresh deep-copies incoming metadata")
	await _free_menu(menu)

func _test_keyboard_navigation_skips_disabled_rows() -> void:
	var menu := await _make_menu(&"load", _metadata_fixture())
	var rows: Array = menu.call("get_rows")
	(rows[0] as Control).grab_focus()
	await get_tree().process_frame
	var down := InputEventAction.new()
	down.action = &"ui_down"
	down.pressed = true
	menu.get_viewport().push_input(down)
	await get_tree().process_frame
	assert_eq((menu.get_viewport().gui_get_focus_owner() as Node).get("slot_id"), &"slot_1", "down moves from autosave to the next enabled manual row")
	menu.get_viewport().push_input(down)
	await get_tree().process_frame
	assert_eq((menu.get_viewport().gui_get_focus_owner() as Node).get("slot_id"), &"slot_4", "down skips consecutive disabled rows predictably")
	var up := InputEventAction.new()
	up.action = &"ui_up"
	up.pressed = true
	menu.get_viewport().push_input(up)
	await get_tree().process_frame
	assert_eq((menu.get_viewport().gui_get_focus_owner() as Node).get("slot_id"), &"slot_1", "up skips disabled rows in reverse")
	await _free_menu(menu)

func _test_recovery_toast_does_not_overlap_back_action() -> void:
	var menu := await _make_menu(&"load", _metadata_fixture())
	var toast_scene := load("res://ui/hud/toast_layer.tscn") as PackedScene
	var toast := toast_scene.instantiate() as Control
	toast.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	toast.set("display_seconds", 0.0)
	get_tree().root.add_child(toast)
	toast.call("show_toast", "백업 저장을 복구했습니다")
	await get_tree().process_frame
	var back_rect := (menu.get_node("Panel/Margin/Layout/Back") as Control).get_global_rect()
	var toast_rect := (toast.get_node("Toast") as Control).get_global_rect()
	assert_eq(menu.get_viewport_rect().size, Vector2(640, 360), "toast geometry is measured in the real 640x360 viewport")
	assert_false(back_rect.intersects(toast_rect), "the recovery toast never overlaps the bottom back action")
	assert_true(back_rect.end.y <= toast_rect.position.y, "the slot menu reserves a vertical band above the recovery toast")
	assert_true(toast_rect.position.y >= 0.0 and toast_rect.end.y <= 360.0, "the recovery toast remains fully visible inside the viewport")
	toast.queue_free()
	await get_tree().process_frame
	await _free_menu(menu)

func _make_menu(mode: StringName, metadata: Array[Dictionary]) -> Control:
	var scene := load(MENU_PATH) as PackedScene
	var menu := scene.instantiate() as Control
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child(menu)
	menu.call("open", mode, metadata)
	await get_tree().process_frame
	return menu

func _free_menu(menu: Control) -> void:
	menu.queue_free()
	await get_tree().process_frame

func _metadata_fixture() -> Array[Dictionary]:
	return [
		{"slot_id": &"auto", "label": "자동 저장", "exists": true, "enabled": true, "read_only": true, "recoverable": false, "location_name": "기초 홀", "play_time_seconds": 1234.0, "saved_at": "2026-08-16T12:34:56Z"},
		{"slot_id": &"slot_1", "label": "슬롯 1", "exists": true, "enabled": true, "read_only": false, "recoverable": false, "location_name": "젤리뽀 집", "play_time_seconds": 1082.0, "saved_at": "2026-08-16T11:22:33Z"},
		{"slot_id": &"slot_2", "label": "슬롯 2", "exists": false, "enabled": false, "read_only": false, "recoverable": false},
		{"slot_id": &"slot_3", "label": "슬롯 3", "exists": false, "enabled": false, "read_only": false, "recoverable": false},
		{"slot_id": &"slot_4", "label": "슬롯 4", "exists": true, "enabled": true, "read_only": false, "recoverable": false, "location_name": "기초 방", "play_time_seconds": 7.0, "saved_at": "2026-08-16T01:02:03Z"},
		{"slot_id": &"slot_5", "label": "슬롯 5", "exists": false, "enabled": false, "read_only": false, "recoverable": false},
	]

func _contains_type(node: Node, type_name: String) -> bool:
	if node.is_class(type_name):
		return true
	for child: Node in node.get_children():
		if _contains_type(child, type_name):
			return true
	return false

func _contains_named_control(node: Node, fragment: String) -> bool:
	if node is Control and String(node.name).to_lower().contains(fragment):
		return true
	for child: Node in node.get_children():
		if _contains_named_control(child, fragment):
			return true
	return false
