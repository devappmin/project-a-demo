extends "res://tests/support/test_case.gd"

const GameModeResource = preload("res://app/session/game_mode.gd")
const SaveDataResource = preload("res://app/save/save_data.gd")
const SaveRepositoryResource = preload("res://app/save/save_repository.gd")
const REQUIRED_SCENES := [
	"res://ui/menus/title_menu.tscn",
	"res://ui/menus/pause_menu.tscn",
	"res://ui/menus/confirm_panel.tscn",
	"res://ui/hud/toast_layer.tscn",
]

class FakeRepository:
	extends SaveRepositoryResource
	var metadata_by_slot := {}
	var writes: Array[StringName] = []
	var read_results := {}
	var write_error: Error = OK

	func read_metadata(slot_id: StringName) -> Dictionary:
		return (metadata_by_slot.get(slot_id, {}) as Dictionary).duplicate(true)

	func write_slot(slot_id: StringName, snapshot: Dictionary) -> Error:
		writes.append(slot_id)
		if write_error != OK:
			return write_error
		var meta: Dictionary = snapshot.get("meta", {}).duplicate(true)
		meta["recoverable"] = false
		metadata_by_slot[slot_id] = meta
		return OK

	func read_slot(slot_id: StringName) -> Dictionary:
		return (read_results.get(slot_id, {"ok": false, "error": ERR_FILE_NOT_FOUND, "data": {}, "recovered": false, "diagnostic": {}}) as Dictionary).duplicate(true)

func run() -> void:
	for scene_path: String in REQUIRED_SCENES:
		assert_true(ResourceLoader.exists(scene_path), "%s exists" % scene_path)
	if REQUIRED_SCENES.any(func(path: String) -> bool: return not ResourceLoader.exists(path)):
		return
	assert_true(InputMap.has_action("menu"), "the menu input action exists")
	assert_true(InputMap.action_get_events("menu").any(func(event: InputEvent) -> bool: return event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE), "the menu action is bound to Escape")
	await _test_complete_title_pause_and_service_flow()
	await _test_successful_title_and_ingame_load_orchestration()

func _test_complete_title_pause_and_service_flow() -> void:
	var fake_repository := FakeRepository.new()
	fake_repository.metadata_by_slot = {
		&"auto": _metadata(&"auto", "기초 홀"),
		&"slot_1": _metadata(&"slot_1", "젤리뽀 집"),
	}
	SaveService.repository = fake_repository
	var root := await _make_root()
	var title := root.get_node("UILayer/TitleMenu") as Control
	var pause := root.get_node("UILayer/PauseMenu") as Control
	var slots := root.get_node("UILayer/SlotMenu") as Control
	var confirm := root.get_node("UILayer/ConfirmPanel") as Control
	var toast := root.get_node("UILayer/ToastLayer") as Control
	assert_eq(_button_texts(title), ["새 게임", "불러오기", "종료"], "title shows only the three approved actions and no continue action")
	assert_eq(_button_texts(pause), ["계속", "저장", "불러오기", "타이틀로"], "pause shows the four approved actions")
	assert_true(title.visible, "the title is visible at boot")
	assert_eq(root.get_node("WorldHost").get_child_count(), 0, "title boots with an empty WorldHost")
	assert_false(root.get_node("UILayer/InteractionPrompt").visible, "world prompt stays hidden under title")
	assert_false(root.get_node("UILayer/DialogueView").visible, "dialogue stays hidden under title")

	var title_load := title.get_node("Panel/Margin/Buttons/Load") as Button
	title_load.pressed.emit()
	await _wait_frames(2)
	assert_true(slots.visible, "title load opens the shared slot menu")
	assert_eq(slots.call("mode"), &"load", "title uses the shared list in load mode")
	slots.emit_signal("back_requested")
	await _wait_frames(2)
	assert_true(title.visible, "back from title load restores the title")
	assert_eq(root.get_viewport().gui_get_focus_owner(), title_load, "back from slots restores focus to the invoking title action")

	var new_game := title.get_node("Panel/Margin/Buttons/NewGame") as Button
	var manual_before: Dictionary = fake_repository.metadata_by_slot[&"slot_1"].duplicate(true)
	new_game.pressed.emit()
	await _wait_frames(2)
	assert_true(confirm.visible, "an existing autosave requires new-game confirmation")
	assert_eq(confirm.call("message"), "새 게임을 시작하면 자동 저장이 교체됩니다", "new-game confirmation explains autosave replacement")
	assert_true(fake_repository.writes.is_empty(), "new game does not write before confirmation")
	(confirm.get_node("Panel/Margin/Layout/Actions/Confirm") as Button).pressed.emit()
	await _wait_frames(6)
	assert_eq(root.get_node("WorldHost").get_child_count(), 1, "confirmed new game places the starting map")
	assert_eq(fake_repository.writes, [&"auto"], "successful initial placement creates or replaces only autosave")
	assert_eq(fake_repository.metadata_by_slot[&"slot_1"], manual_before, "new game preserves every manual slot")

	for blocked_mode in [GameModeResource.Value.DIALOGUE, GameModeResource.Value.CUTSCENE, GameModeResource.Value.TRANSITION]:
		GameSession.restore_mode_context({"mode": blocked_mode, "menu_origin_mode": -1})
		root.call("_unhandled_input", _menu_event())
		assert_false(pause.visible, "menu input is blocked outside exploration (mode %s)" % blocked_mode)
	GameSession.restore_mode_context({"mode": GameModeResource.Value.EXPLORATION, "menu_origin_mode": -1})
	root.call("_unhandled_input", _menu_event())
	await _wait_frames(2)
	assert_true(pause.visible, "Escape/menu opens pause from exploration")
	assert_true(GameSession.is_menu_from_exploration(), "pause records the exact exploration origin")

	var save_button := pause.get_node("Panel/Margin/Buttons/Save") as Button
	save_button.pressed.emit()
	await _wait_frames(2)
	assert_true(slots.visible, "pause save opens the shared slot menu")
	assert_eq(slots.call("mode"), &"save", "pause uses the shared list in save mode")
	var rows: Array = slots.call("get_rows")
	(rows[1] as Node).call("activate")
	await _wait_frames(2)
	assert_true(confirm.visible, "only a populated manual slot asks for overwrite confirmation")
	assert_eq(confirm.call("message"), "이 슬롯을 덮어쓰시겠습니까?", "overwrite confirmation is explicit")
	(confirm.get_node("Panel/Margin/Layout/Actions/Cancel") as Button).pressed.emit()
	await _wait_frames(2)
	assert_true(slots.visible, "cancelling overwrite returns to the slot list")
	assert_eq((root.get_viewport().gui_get_focus_owner() as Node).get("slot_id"), &"slot_1", "cancelling overwrite restores the invoking row focus")
	toast.set("display_seconds", 0.01)
	var player := SceneDirector.get("player") as Node
	player.set("facing", Vector2.ZERO)
	(rows[2] as Node).call("activate")
	await _wait_frames(1)
	assert_true(toast.visible, "a capture-stage manual-save failure shows feedback through AppRoot")
	assert_eq(toast.call("current_message"), "저장할 수 없습니다", "capture-stage failure uses the generic save notice")
	await get_tree().create_timer(0.05).timeout
	await _wait_frames(1)
	assert_false(toast.visible, "the failure toast expires through its real Timer")
	assert_eq(toast.call("current_message"), "", "an expired toast does not retain a stale visible-message identity")
	(rows[2] as Node).call("activate")
	await _wait_frames(1)
	assert_true(toast.visible, "retrying the same capture-stage failure after expiry shows feedback again")
	assert_eq(toast.call("current_message"), "저장할 수 없습니다", "the repeated failure restores the exact generic notice")
	player.set("facing", Vector2.DOWN)
	toast.call("hide_toast")
	toast.set("display_seconds", 2.4)
	(rows[2] as Node).call("activate")
	await _wait_frames(3)
	assert_false(confirm.visible, "an empty manual slot saves without overwrite confirmation")
	assert_true(&"slot_2" in fake_repository.writes, "empty manual slot action routes through AppRoot to SaveService")
	assert_eq(toast.call("current_message"), "저장했습니다", "successful manual save shows non-blocking feedback")

	(rows[3] as Control).grab_focus()
	await _wait_frames(1)
	SaveService.set("_busy", true)
	SaveService.save_started.emit(&"slot_3")
	await _wait_frames(1)
	rows = slots.call("get_rows")
	assert_true((rows[3] as Button).disabled, "service busy state disables duplicate slot actions")
	var writes_while_busy := fake_repository.writes.size()
	(rows[3] as Node).call("activate")
	assert_eq(fake_repository.writes.size(), writes_while_busy, "disabled busy rows cannot dispatch duplicate writes")
	SaveService.set("_busy", false)
	SaveService.save_failed.emit(&"slot_3", {"error": ERR_BUSY, "stage": &"repository"})
	await _wait_frames(1)
	assert_eq(toast.call("current_message"), "저장할 수 없습니다", "save failures use the generic Korean toast")
	assert_true(slots.visible, "failed save keeps the invoking menu interactive")
	assert_false((slots.call("get_rows")[3] as Button).disabled, "failed save releases the busy lock")
	var focus_after_busy := root.get_viewport().gui_get_focus_owner()
	assert_not_null(focus_after_busy, "busy completion restores keyboard focus")
	if focus_after_busy != null:
		assert_eq(focus_after_busy.get("slot_id"), &"slot_3", "busy completion restores the slot that invoked the action")

	SaveService.backup_recovered.emit(&"slot_1")
	await _wait_frames(1)
	assert_eq(toast.call("current_message"), "백업 저장을 복구했습니다", "backup recovery uses the exact required notice")
	slots.emit_signal("back_requested")
	await _wait_frames(2)
	assert_true(pause.visible, "back from pause slots restores pause")
	assert_eq(root.get_viewport().gui_get_focus_owner(), save_button, "back from pause slots restores invoking-menu focus")

	var to_title := pause.get_node("Panel/Margin/Buttons/Title") as Button
	to_title.pressed.emit()
	await _wait_frames(1)
	assert_true(confirm.visible, "returning to title requires confirmation")
	(confirm.get_node("Panel/Margin/Layout/Actions/Confirm") as Button).pressed.emit()
	await _wait_frames(3)
	assert_true(title.visible, "confirmed title return restores the title")
	assert_eq(root.get_node("WorldHost").get_child_count(), 0, "confirmed title return empties WorldHost")
	assert_eq(GameSession.current_mode, GameModeResource.Value.MENU, "title return leaves the session in menu mode")
	assert_false(GameSession.is_menu_from_exploration(), "title has no active gameplay menu origin")
	title_load.pressed.emit()
	await _wait_frames(2)
	rows = slots.call("get_rows")
	(rows[0] as Node).call("activate")
	await _wait_frames(3)
	assert_true(slots.visible, "failed title load leaves the slot menu open")
	assert_false((slots.call("get_rows")[0] as Button).disabled, "failed load restores slot-menu interactivity")
	assert_eq(toast.call("current_message"), "불러올 수 없습니다", "load failures use the generic Korean toast")
	slots.emit_signal("back_requested")
	await _wait_frames(2)

	var quit_requests := [0]
	root.connect("quit_requested", func() -> void: quit_requests[0] += 1)
	root.call("set_quit_handler", func() -> void: pass)
	(title.get_node("Panel/Margin/Buttons/Quit") as Button).pressed.emit()
	assert_eq(quit_requests[0], 1, "quit uses a testable request seam instead of terminating the test runner")
	await _free_root(root)

func _test_successful_title_and_ingame_load_orchestration() -> void:
	GameSession.reset_new_game()
	var fake_repository := FakeRepository.new()
	fake_repository.metadata_by_slot = {&"slot_1": _metadata(&"slot_1", "기초 방")}
	SaveService.repository = fake_repository
	var root := await _make_root()
	var title := root.get_node("UILayer/TitleMenu") as Control
	var pause := root.get_node("UILayer/PauseMenu") as Control
	var slots := root.get_node("UILayer/SlotMenu") as Control
	var confirm := root.get_node("UILayer/ConfirmPanel") as Control
	var world_host := root.get_node("WorldHost") as Node2D
	var dialogue_view := root.get_node("UILayer/DialogueView") as Control
	var inactive_dialogue := {"active": false, "bundle_key": "", "trigger_key": "", "node_id": "", "boundary": ""}
	fake_repository.read_results[&"slot_1"] = _successful_read(_signed_snapshot(&"slot_1", inactive_dialogue))
	(title.get_node("Panel/Margin/Buttons/Load") as Button).pressed.emit()
	await _wait_frames(2)
	var rows: Array = slots.call("get_rows")
	var title_load_result: Dictionary = await _activate_and_wait_for_load(rows[1] as Node)
	assert_eq(title_load_result, {"completed": &"slot_1"}, "title load completes through the real SaveService orchestration")
	assert_false(title.visible, "successful title load closes the title menu")
	assert_false(pause.visible, "successful title load leaves pause closed")
	assert_false(slots.visible, "successful title load closes the shared slot menu")
	assert_false(confirm.visible, "successful title load leaves confirmation closed")
	assert_true(world_host.visible and world_host.get_child_count() == 1, "successful title load reveals exactly one restored world")
	assert_false(dialogue_view.visible, "an inactive-dialogue title load keeps dialogue UI hidden")
	assert_eq(GameSession.current_mode, GameModeResource.Value.EXPLORATION, "inactive title load resumes exploration")

	root.call("handle_menu_action")
	await _wait_frames(2)
	assert_true(pause.visible, "the restored title-load game can open pause from exploration")
	var active_dialogue := {
		"active": true,
		"bundle_key": "foundation.inspect",
		"trigger_key": "mirror.inspect",
		"node_id": "default.inspect.line_e5b0e4bd5f23",
		"boundary": "line",
	}
	fake_repository.read_results[&"slot_1"] = _successful_read(_signed_snapshot(&"slot_1", active_dialogue))
	(pause.get_node("Panel/Margin/Buttons/Load") as Button).pressed.emit()
	await _wait_frames(2)
	rows = slots.call("get_rows")
	var ingame_load_result: Dictionary = await _activate_and_wait_for_load(rows[1] as Node)
	assert_eq(ingame_load_result, {"completed": &"slot_1"}, "in-game load completes through the real SaveService orchestration")
	assert_false(title.visible, "successful in-game load keeps title closed")
	assert_false(pause.visible, "successful in-game load closes pause")
	assert_false(slots.visible, "successful in-game load closes the shared slot menu")
	assert_false(confirm.visible, "successful in-game load closes confirmation")
	assert_true(world_host.visible and world_host.get_child_count() == 1, "successful in-game load keeps the restored world visible")
	assert_true(dialogue_view.visible, "an active checkpoint load restores dialogue UI visibility")
	assert_eq(root.get_node("ServiceLayer/DialogueService").call("get_checkpoint"), active_dialogue, "in-game load resumes the exact saved active checkpoint")
	assert_eq(GameSession.current_mode, GameModeResource.Value.DIALOGUE, "active checkpoint load restores dialogue mode")
	await _free_root(root)

func _make_root() -> Node:
	GameSession.restore_mode_context({"mode": GameModeResource.Value.MENU, "menu_origin_mode": -1})
	var scene := load("res://app/bootstrap/app_root.tscn") as PackedScene
	var root := scene.instantiate()
	get_tree().root.add_child(root)
	(root.get_node("UILayer/ScreenFade") as ScreenFade).duration = 0.0
	await _wait_frames(2)
	return root

func _free_root(root: Node) -> void:
	root.queue_free()
	await _wait_frames(3)
	SaveService.repository = SaveRepositoryResource.new()

func _metadata(slot_id: StringName, location: String) -> Dictionary:
	return {
		"slot_id": String(slot_id),
		"saved_at": "2026-08-16T12:34:56Z",
		"play_time_seconds": 42.0,
		"location_name": location,
		"recoverable": false,
	}

func _signed_snapshot(slot_id: StringName, dialogue: Dictionary) -> Dictionary:
	var session := GameSession.snapshot_session()
	return SaveDataResource.with_checksum({
		"schema_version": 1,
		"meta": {"slot_id": String(slot_id), "saved_at": "2026-08-16T12:34:56Z", "play_time_seconds": 42.0, "location_name": "기초 방"},
		"player": {"map_id": "foundation_room", "spawn_id": "start", "position": {"x": 120.0, "y": 88.0}, "facing": "down"},
		"narrative": session["narrative_state"].duplicate(true),
		"world": session["world_state"].duplicate(true),
		"dialogue": dialogue.duplicate(true),
	})

func _successful_read(snapshot: Dictionary) -> Dictionary:
	return {"ok": true, "error": OK, "data": snapshot.duplicate(true), "recovered": false, "diagnostic": {}}

func _activate_and_wait_for_load(row: Node) -> Dictionary:
	var outcome := {}
	var completed_handler := func(slot_id: StringName) -> void:
		outcome["completed"] = slot_id
	var failed_handler := func(slot_id: StringName, context: Dictionary) -> void:
		outcome["failed"] = {"slot_id": slot_id, "context": context.duplicate(true)}
	SaveService.load_completed.connect(completed_handler)
	SaveService.load_failed.connect(failed_handler)
	row.call("activate")
	for _frame: int in 120:
		if not outcome.is_empty():
			break
		await get_tree().process_frame
	if SaveService.load_completed.is_connected(completed_handler):
		SaveService.load_completed.disconnect(completed_handler)
	if SaveService.load_failed.is_connected(failed_handler):
		SaveService.load_failed.disconnect(failed_handler)
	return outcome.duplicate(true)

func _button_texts(control: Control) -> Array[String]:
	var texts: Array[String] = []
	_collect_button_texts(control, texts)
	return texts

func _collect_button_texts(node: Node, texts: Array[String]) -> void:
	if node is Button:
		texts.append((node as Button).text)
	for child: Node in node.get_children():
		_collect_button_texts(child, texts)

func _wait_frames(count: int) -> void:
	for _index: int in count:
		await get_tree().process_frame

func _menu_event() -> InputEventAction:
	var event := InputEventAction.new()
	event.action = &"menu"
	event.pressed = true
	return event
