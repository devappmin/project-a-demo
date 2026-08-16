extends Node
class_name VerticalSliceHarness

const AppRootScene = preload("res://app/bootstrap/app_root.tscn")
const GameModeResource = preload("res://app/session/game_mode.gd")
const SaveDataResource = preload("res://app/save/save_data.gd")
const SaveRepositoryResource = preload("res://app/save/save_repository.gd")
const TEST_ROOT := "user://test-saves"

var app: AppRoot
var repository: SaveRepository
var case_directory := ""

func boot(case_name: String) -> Error:
	case_directory = "%s/vertical_slice_%s_%s" % [TEST_ROOT, case_name, Time.get_ticks_usec()]
	if not _is_exact_case_directory():
		return ERR_INVALID_PARAMETER
	var cleanup_error := _cleanup_case_directory()
	if cleanup_error != OK:
		return cleanup_error
	repository = SaveRepositoryResource.new()
	repository.base_directory = case_directory
	SaveService.repository = repository
	GameSession.reset_new_game()
	var mode_error := GameSession.restore_mode_context({"mode": GameModeResource.Value.MENU, "menu_origin_mode": -1})
	if mode_error != OK:
		return mode_error
	app = AppRootScene.instantiate() as AppRoot
	if app == null:
		return ERR_CANT_CREATE
	get_tree().root.add_child(app)
	app.screen_fade.duration = 0.0
	await wait_frames(2)
	return OK

func cleanup() -> Error:
	_release_all_actions()
	if app != null and is_instance_valid(app):
		if app.dialogue_service.current_graph != null:
			app.dialogue_service.abort_dialogue(&"vertical_slice_cleanup")
		app.queue_free()
		await wait_frames(3)
	app = null
	SaveService.repository = SaveRepositoryResource.new()
	GameSession.reset_new_game()
	GameSession.restore_mode_context({"mode": GameModeResource.Value.MENU, "menu_origin_mode": -1})
	return _cleanup_case_directory()

func current_map() -> MapScene:
	return SceneDirector.call("get_current_map") as MapScene

func player() -> PlayerController:
	return SceneDirector.call("get_player") as PlayerController

func detector() -> InteractionDetector:
	return SceneDirector.call("get_interaction_detector") as InteractionDetector

func router() -> InteractionRouter:
	return SceneDirector.call("get_interaction_router") as InteractionRouter

func dialogue() -> DialogueService:
	return app.dialogue_service if app != null else null

func dialogue_view() -> DialogueView:
	return app.dialogue_view as DialogueView if app != null else null

func title_menu() -> TitleMenu:
	return app.title_menu as TitleMenu if app != null else null

func pause_menu() -> PauseMenu:
	return app.pause_menu as PauseMenu if app != null else null

func slot_menu() -> SaveSlotMenu:
	return app.slot_menu as SaveSlotMenu if app != null else null

func toast_layer() -> ToastLayer:
	return app.toast_layer as ToastLayer if app != null else null

func wait_frames(count: int) -> void:
	for _index: int in count:
		await get_tree().process_frame

func wait_until(predicate: Callable, max_frames := 240) -> bool:
	for _index: int in max_frames:
		if predicate.call() == true:
			return true
		await get_tree().process_frame
	return predicate.call() == true

func press_action(action: StringName) -> void:
	_send_action(action, true)
	await get_tree().process_frame
	_send_action(action, false)
	await get_tree().process_frame

func press_key(keycode: Key) -> void:
	_send_key(keycode, true)
	await get_tree().process_frame
	_send_key(keycode, false)
	await get_tree().process_frame

func move_for(action: StringName, physics_frames: int, sprint := false) -> void:
	_send_action(action, true)
	if sprint:
		_send_action(&"sprint", true)
	for _index: int in physics_frames:
		await get_tree().physics_frame
	_send_action(action, false)
	if sprint:
		_send_action(&"sprint", false)
	await get_tree().physics_frame

func move_until_target(action: StringName, kind: StringName, max_physics_frames := 180, sprint := true) -> InteractionTarget:
	_send_action(action, true)
	if sprint:
		_send_action(&"sprint", true)
	var found: InteractionTarget
	for _index: int in max_physics_frames:
		await get_tree().physics_frame
		var current_detector := detector()
		var candidate := current_detector.current_target if current_detector != null else null
		if candidate != null and candidate.action_kind == kind:
			found = candidate
			break
	_send_action(action, false)
	if sprint:
		_send_action(&"sprint", false)
	await get_tree().physics_frame
	return found

func interact_current_target() -> void:
	await press_key(KEY_E)

func read_slot(slot_id: StringName) -> Dictionary:
	return repository.read_slot(slot_id) if repository != null else {}

func publish_fixture(slot_id: StringName, snapshot: Dictionary) -> Error:
	if repository == null:
		return ERR_UNCONFIGURED
	return repository.write_slot(slot_id, snapshot.duplicate(true))

func rotate_current_to_backup(slot_id: StringName) -> Error:
	var result := read_slot(slot_id)
	if not result.get("ok", false):
		return result.get("error", ERR_FILE_CORRUPT)
	return publish_fixture(slot_id, result["data"])

func corrupt_current(slot_id: StringName) -> Error:
	if slot_id not in SaveDataResource.SLOT_IDS or repository == null or not _is_exact_case_directory():
		return ERR_INVALID_PARAMETER
	var path := case_directory.path_join("%s.json" % String(slot_id))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string("{corrupt-current")
	file.close()
	return OK

func current_path(slot_id: StringName) -> String:
	return case_directory.path_join("%s.json" % String(slot_id))

func backup_path(slot_id: StringName) -> String:
	return case_directory.path_join("%s.json.bak" % String(slot_id))

func _send_action(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(event)

func _send_key(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)

func _release_all_actions() -> void:
	for action: StringName in [&"move_left", &"move_right", &"move_up", &"move_down", &"sprint", &"interact", &"ui_accept", &"menu"]:
		if Input.is_action_pressed(action):
			Input.action_release(action)

func _is_exact_case_directory() -> bool:
	if case_directory.is_empty():
		return false
	var resolved := ProjectSettings.globalize_path(case_directory).simplify_path().replace("\\", "/").trim_suffix("/")
	var root := ProjectSettings.globalize_path(TEST_ROOT).simplify_path().replace("\\", "/").trim_suffix("/")
	return resolved != root and resolved.get_base_dir() == root

func _cleanup_case_directory() -> Error:
	if case_directory.is_empty():
		return OK
	if not _is_exact_case_directory():
		return ERR_INVALID_PARAMETER
	var resolved := ProjectSettings.globalize_path(case_directory).simplify_path().replace("\\", "/").trim_suffix("/")
	if not DirAccess.dir_exists_absolute(resolved):
		return OK
	var directory := DirAccess.open(resolved)
	if directory == null:
		return DirAccess.get_open_error()
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if directory.current_is_dir():
			directory.list_dir_end()
			return ERR_INVALID_DATA
		var remove_error := DirAccess.remove_absolute("%s/%s" % [resolved, entry])
		if remove_error != OK:
			directory.list_dir_end()
			return remove_error
		entry = directory.get_next()
	directory.list_dir_end()
	directory = null
	return DirAccess.remove_absolute(resolved)
