extends Node
class_name AppRoot

const GameMode = preload("res://app/session/game_mode.gd")

signal quit_requested

@onready var world_host: Node = $WorldHost
@onready var service_layer: Node = $ServiceLayer
@onready var ui_layer: CanvasLayer = $UILayer
@onready var prompt: InteractionPrompt = $UILayer/InteractionPrompt
@onready var dialogue_adapter: DialogueActionAdapter = $ServiceLayer/DialogueActionAdapter
@onready var door_adapter: DoorActionAdapter = $ServiceLayer/DoorActionAdapter
@onready var screen_fade: ScreenFade = $UILayer/ScreenFade
@onready var dialogue_service: DialogueService = $ServiceLayer/DialogueService
@onready var dialogue_view: Control = $UILayer/DialogueView
@onready var title_menu: Control = $UILayer/TitleMenu
@onready var pause_menu: Control = $UILayer/PauseMenu
@onready var slot_menu: Control = $UILayer/SlotMenu
@onready var confirm_panel: Control = $UILayer/ConfirmPanel
@onready var toast_layer: Control = $UILayer/ToastLayer

var _slot_invoker: StringName = &""
var _confirm_action: StringName = &""
var _confirm_slot: StringName = &""
var _confirm_return_focus: Control
var _quit_handler: Callable

func _ready() -> void:
	if SceneDirector.configure(world_host as Node2D, screen_fade) != OK:
		return
	SceneDirector.set_map_rebinder(_rebind_player)
	if SaveService.configure(SceneDirector, dialogue_service) != OK:
		return
	_connect_menus()
	_connect_save_service()
	_quit_handler = Callable(get_tree(), "quit")
	GameSession.change_mode(GameMode.Value.MENU)
	_show_title()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("menu"):
		handle_menu_action()
		get_viewport().set_input_as_handled()

func handle_menu_action() -> void:
	if GameSession.current_mode == GameMode.Value.EXPLORATION:
		if GameSession.enter_menu():
			pause_menu.call("open")
		return
	if GameSession.is_menu_from_exploration() and pause_menu.visible and not slot_menu.visible and not confirm_panel.visible:
		_resume_game()

func set_quit_handler(handler: Callable) -> void:
	_quit_handler = handler

func _connect_menus() -> void:
	title_menu.connect("new_game_requested", _on_new_game_requested)
	title_menu.connect("load_requested", _open_title_load)
	title_menu.connect("quit_requested", _on_quit_requested)
	pause_menu.connect("continue_requested", _resume_game)
	pause_menu.connect("save_requested", _open_pause_save)
	pause_menu.connect("load_requested", _open_pause_load)
	pause_menu.connect("title_requested", _confirm_title_return)
	slot_menu.connect("slot_requested", _on_slot_requested)
	slot_menu.connect("back_requested", _on_slots_back)
	confirm_panel.connect("confirmed", _on_confirmed)
	confirm_panel.connect("cancelled", _on_confirmation_cancelled)

func _connect_save_service() -> void:
	SaveService.save_started.connect(_on_save_started)
	SaveService.save_completed.connect(_on_save_completed)
	SaveService.save_failed.connect(_on_save_failed)
	SaveService.load_completed.connect(_on_load_completed)
	SaveService.load_failed.connect(_on_load_failed)
	SaveService.backup_recovered.connect(_on_backup_recovered)
	SaveService.slots_changed.connect(_refresh_visible_slots)

func _show_title() -> void:
	world_host.visible = false
	prompt.visible = false
	dialogue_view.visible = false
	pause_menu.call("close")
	slot_menu.call("close")
	confirm_panel.call("close")
	title_menu.call("open")
	_slot_invoker = &""

func _on_new_game_requested() -> void:
	var auto_metadata := _metadata_for(&"auto")
	if auto_metadata.get("exists", false) or auto_metadata.get("recoverable", false):
		_show_confirmation("새 게임을 시작하면 자동 저장이 교체됩니다", &"new_game", &"", title_menu.get_node("Panel/Margin/Buttons/NewGame") as Control)
		return
	_start_new_game()

func _start_new_game() -> void:
	_set_all_busy(true)
	var error: Error = await SceneDirector.start_new_game()
	_set_all_busy(false)
	if error != OK:
		toast_layer.call("show_toast", "시작할 수 없습니다")
		_show_title()
		return
	title_menu.call("close")
	pause_menu.call("close")
	slot_menu.call("close")
	world_host.visible = true
	prompt.visible = false

func _open_title_load() -> void:
	_slot_invoker = &"title_load"
	title_menu.call("close")
	slot_menu.call("open", &"load", SaveService.slot_metadata())
	slot_menu.call("set_busy", SaveService.is_busy())

func _open_pause_save() -> void:
	if not GameSession.is_menu_from_exploration():
		return
	_slot_invoker = &"pause_save"
	pause_menu.call("close")
	slot_menu.call("open", &"save", SaveService.slot_metadata())
	slot_menu.call("set_busy", SaveService.is_busy())

func _open_pause_load() -> void:
	if not GameSession.is_menu_from_exploration():
		return
	_slot_invoker = &"pause_load"
	pause_menu.call("close")
	slot_menu.call("open", &"load", SaveService.slot_metadata())
	slot_menu.call("set_busy", SaveService.is_busy())

func _on_slots_back() -> void:
	if SaveService.is_busy():
		return
	slot_menu.call("close")
	match _slot_invoker:
		&"title_load":
			title_menu.call("open")
			title_menu.call("focus_load")
		&"pause_save":
			pause_menu.call("open")
			pause_menu.call("focus_save")
		&"pause_load":
			pause_menu.call("open")
			pause_menu.call("focus_load")
	_slot_invoker = &""

func _on_slot_requested(slot_id: StringName) -> void:
	if SaveService.is_busy():
		return
	if slot_menu.call("mode") == &"save":
		var item: Dictionary = slot_menu.call("metadata_for", slot_id)
		if item.get("exists", false) or item.get("recoverable", false):
			_show_confirmation("이 슬롯을 덮어쓰시겠습니까?", &"overwrite", slot_id, _row_for(slot_id))
		else:
			_save_manual_slot(slot_id)
		return
	_load_slot(slot_id)

func _save_manual_slot(slot_id: StringName) -> void:
	var error := SaveService.save_manual_slot(slot_id)
	if error != OK and not SaveService.is_busy() and toast_layer.call("current_message") != "저장할 수 없습니다":
		toast_layer.call("show_toast", "저장할 수 없습니다")

func _load_slot(slot_id: StringName) -> void:
	slot_menu.call("set_busy", true)
	var error: Error = await SaveService.load_slot(slot_id)
	if error != OK:
		slot_menu.call("set_busy", false)

func _confirm_title_return() -> void:
	if not GameSession.is_menu_from_exploration():
		return
	_show_confirmation("타이틀로 돌아가시겠습니까?", &"title_return", &"", pause_menu.get_node("Panel/Margin/Buttons/Title") as Control)

func _show_confirmation(text: String, action: StringName, slot_id: StringName, return_focus: Control) -> void:
	_confirm_action = action
	_confirm_slot = slot_id
	_confirm_return_focus = return_focus
	confirm_panel.call("open", text)

func _on_confirmed() -> void:
	var action := _confirm_action
	var slot_id := _confirm_slot
	confirm_panel.call("close")
	_clear_confirmation()
	match action:
		&"new_game": _start_new_game()
		&"overwrite": _save_manual_slot(slot_id)
		&"title_return": _return_to_title()

func _on_confirmation_cancelled() -> void:
	confirm_panel.call("close")
	var return_focus := _confirm_return_focus
	_clear_confirmation()
	if is_instance_valid(return_focus):
		return_focus.call_deferred("grab_focus")

func _clear_confirmation() -> void:
	_confirm_action = &""
	_confirm_slot = &""
	_confirm_return_focus = null

func _resume_game() -> void:
	if not GameSession.is_menu_from_exploration():
		return
	pause_menu.call("close")
	slot_menu.call("close")
	confirm_panel.call("close")
	GameSession.change_mode(GameMode.Value.EXPLORATION)

func _return_to_title() -> void:
	prompt.visible = false
	dialogue_service.abort_dialogue(&"title_return")
	dialogue_view.visible = false
	for child: Node in world_host.get_children():
		world_host.remove_child(child)
		child.free()
	SceneDirector.configure(world_host as Node2D, screen_fade)
	GameSession.reset_new_game()
	GameSession.change_mode(GameMode.Value.MENU)
	_show_title()

func _on_quit_requested() -> void:
	quit_requested.emit()
	if _quit_handler.is_valid():
		_quit_handler.call()

func _on_save_started(_slot_id: StringName) -> void:
	_set_all_busy(true)

func _on_save_completed(slot_id: StringName) -> void:
	_set_all_busy(false)
	toast_layer.call("show_toast", "자동 저장했습니다" if slot_id == &"auto" else "저장했습니다")
	_refresh_visible_slots()

func _on_save_failed(_slot_id: StringName, _context: Dictionary) -> void:
	_set_all_busy(false)
	toast_layer.call("show_toast", "저장할 수 없습니다")

func _on_load_completed(_slot_id: StringName) -> void:
	_set_all_busy(false)
	title_menu.call("close")
	pause_menu.call("close")
	slot_menu.call("close")
	confirm_panel.call("close")
	world_host.visible = true
	_slot_invoker = &""

func _on_load_failed(_slot_id: StringName, _context: Dictionary) -> void:
	_set_all_busy(false)
	toast_layer.call("show_toast", "불러올 수 없습니다")

func _on_backup_recovered(_slot_id: StringName) -> void:
	toast_layer.call("show_toast", "백업 저장을 복구했습니다")

func _refresh_visible_slots() -> void:
	if slot_menu.visible:
		slot_menu.call("refresh", SaveService.slot_metadata())

func _set_all_busy(busy: bool) -> void:
	title_menu.call("set_busy", busy)
	pause_menu.call("set_busy", busy)
	slot_menu.call("set_busy", busy)
	confirm_panel.call("set_busy", busy)

func _metadata_for(slot_id: StringName) -> Dictionary:
	for item: Dictionary in SaveService.slot_metadata():
		if item.get("slot_id") == slot_id:
			return item.duplicate(true)
	return {}

func _row_for(slot_id: StringName) -> Control:
	for row: Control in slot_menu.call("get_rows"):
		if row.get("slot_id") == slot_id:
			return row
	return null

func _rebind_player(player: PlayerController) -> Error:
	if player == null or SceneDirector.get_player() != player:
		return ERR_INVALID_PARAMETER
	var detector := SceneDirector.get_interaction_detector()
	var router := SceneDirector.get_interaction_router()
	if detector == null or router == null:
		return ERR_DOES_NOT_EXIST
	router.detector = detector
	_disconnect_adapter(router, dialogue_adapter.handle_action)
	_disconnect_adapter(router, door_adapter.handle_action)
	detector.current_target = null
	router.action_requested.connect(dialogue_adapter.handle_action)
	door_adapter.scene_director = SceneDirector
	router.action_requested.connect(door_adapter.handle_action)
	prompt.bind_detector(detector)
	return OK

func _disconnect_adapter(router: InteractionRouter, handler: Callable) -> void:
	if router.action_requested.is_connected(handler):
		router.action_requested.disconnect(handler)

func get_world_host() -> Node:
	return world_host

func get_service_layer() -> Node:
	return service_layer

func get_ui_layer() -> CanvasLayer:
	return ui_layer
