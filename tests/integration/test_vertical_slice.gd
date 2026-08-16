extends "res://tests/support/test_case.gd"

const GameModeResource = preload("res://app/session/game_mode.gd")
const HarnessResource = preload("res://tests/support/vertical_slice_harness.gd")

class CountingEventResolver extends DialogueEventResolver:
	var resolve_count := 0

	func resolve(bundle_key: StringName, trigger_key: StringName, state: NarrativeState) -> Dictionary:
		resolve_count += 1
		return super.resolve(bundle_key, trigger_key, state)

var harness

func run() -> void:
	var required_scene_director_apis := [
		&"get_current_map",
		&"get_player",
		&"get_interaction_detector",
		&"get_interaction_router",
	]
	for method: StringName in required_scene_director_apis:
		assert_true(SceneDirector.has_method(method), "SceneDirector exposes %s for path-independent gameplay rebinding" % method)
	if required_scene_director_apis.any(func(method: StringName) -> bool: return not SceneDirector.has_method(method)):
		return
	harness = HarnessResource.new()
	add_child(harness)
	var boot_error: Error = await harness.boot("complete_flow")
	assert_eq(boot_error, OK, "vertical slice boots with an isolated real save repository")
	if boot_error == OK:
		await _drive_complete_vertical_slice()
	var cleanup_error: Error = await harness.cleanup()
	assert_eq(cleanup_error, OK, "vertical slice removes only its verified exact save directory")
	harness.queue_free()
	await get_tree().process_frame

func _drive_complete_vertical_slice() -> void:
	assert_true(harness.title_menu().visible, "step 1 boots the real AppRoot at title")
	assert_eq(harness.current_map(), null, "step 1 title has no active map")
	assert_eq(harness.app.get_world_host().get_child_count(), 0, "step 1 title keeps WorldHost empty")

	var initial_save := await _observe_save(&"auto", func() -> void:
		(harness.title_menu().get_node("Panel/Margin/Buttons/NewGame") as Button).pressed.emit()
	)
	assert_eq(initial_save, {"completed": &"auto"}, "step 2 title new game reaches the initial autosave")
	var room: MapScene = harness.current_map()
	var player: PlayerController = harness.player()
	assert_not_null(room, "step 3 new game commits a real map")
	assert_not_null(player, "step 3 new game creates the persistent player")
	if room == null or player == null:
		return
	assert_eq(room.map_id, &"foundation_room", "step 3 starts in the foundation room")
	assert_eq(player.global_position, room.get_spawn(&"start").global_position, "step 3 places the player at the exact start spawn")
	assert_true(GameSession.can(GameModeResource.ACTION_MOVE), "step 3 grants movement permission after placement")
	assert_eq(player.get_parent(), room.get_actor_root(), "step 3 attaches the player body to the room actor root")
	assert_eq(player.presentation.get_parent(), room.get_visual_root(), "step 3 attaches PlayerVisual to the room visual root")
	var persistent_mirror := room.get_node_or_null("VisualSort/SampleInspectable/PersistentWorldObject") as PersistentWorldObject
	assert_not_null(persistent_mirror, "step 3 room contains the persistent mirror object")
	if persistent_mirror == null:
		return
	assert_eq(persistent_mirror.object_id, &"mirror", "step 3 registers the mirror under the stable foundation_room/mirror identity")

	var mirror: InteractionTarget = await harness.move_until_target(&"move_up", &"inspect", 8, false)
	assert_not_null(mirror, "step 4 parsed movement faces the live mirror target")
	if mirror == null:
		return
	assert_eq(mirror.action_kind, &"inspect", "step 4 detector selects the mirror interaction")
	assert_eq(mirror.get_interaction().payload, {"dialogue_bundle_key": &"foundation.inspect", "dialogue_trigger_key": &"mirror.inspect"}, "step 4 mirror preserves document-first provenance")
	await harness.interact_current_target()
	assert_true(await harness.wait_until(func() -> bool: return harness.dialogue().current_graph != null), "step 4 parsed E input routes through the live interaction router")
	assert_eq(GameSession.current_mode, GameModeResource.Value.DIALOGUE, "step 4 mirror interaction enters dialogue")
	assert_eq(persistent_mirror.apply_persisted_state({"inspected": true}), OK, "step 4 updates the live interacted mirror through its public persistence API")
	assert_eq(persistent_mirror.capture_persisted_state(), {"inspected": true}, "step 4 live mirror holds a non-default persisted state")

	assert_true(await _advance_to_node_type("choice"), "step 5 real dialogue reaches its first choice")
	assert_eq(harness.dialogue().current_node_id, &"default.start.choice_93440f2bd8ca", "step 5 reaches the marked important choice")
	var choice_node: Dictionary = harness.dialogue().current_graph.get_node(harness.dialogue().current_node_id)
	assert_eq(choice_node.get("autosave", false), true, "step 5 production choice carries important autosave metadata")
	var effect_choice := _choice_index_with_effect(choice_node, &"mirror_seen")
	assert_true(effect_choice >= 0, "step 6 exposes the effect-bearing mirror choice")
	if effect_choice < 0:
		return
	var important_save := await _observe_save(&"auto", func() -> void:
		_activate_choice(effect_choice)
	)
	assert_eq(important_save, {"completed": &"auto"}, "step 6 effect-bearing choice reaches its autosave completion")
	var important_checkpoint := {
		"active": true,
		"bundle_key": "foundation.inspect",
		"trigger_key": "mirror.inspect",
		"node_id": "default.inspect.line_e5b0e4bd5f23",
		"boundary": "line",
	}
	assert_true(GameSession.narrative_state.get_flag(&"mirror_seen"), "step 7 important choice applies mirror_seen")
	assert_eq(harness.dialogue().get_checkpoint(), important_checkpoint, "step 7 reaches the exact next stable line")
	var important_read: Dictionary = harness.read_slot(&"auto")
	assert_true(important_read.get("ok", false), "step 7 important autosave is byte-valid on disk")
	if not important_read.get("ok", false):
		return
	var important_fixture: Dictionary = important_read["data"].duplicate(true)
	assert_eq(important_fixture["dialogue"], important_checkpoint, "step 7 important autosave stores the active checkpoint")
	assert_eq(important_fixture["world"]["maps"]["foundation_room"]["mirror"], {"inspected": true}, "step 7 important autosave captures the live mirror's non-default persisted state")
	assert_eq(important_fixture["meta"]["location_name"], "기초 방", "step 7 autosave metadata uses the room display name")

	assert_true(await _advance_to_node_type("choice"), "step 8 chosen branch reaches its later choice")
	assert_true(await _choose_by_text("조사를 마친다"), "step 8 selects the real finish branch")
	assert_true(await _advance_until_dialogue_ends(), "step 8 finishes the real dialogue")
	assert_eq(GameSession.current_mode, GameModeResource.Value.EXPLORATION, "step 8 dialogue finish restores exploration")
	var room_door: InteractionTarget = await harness.move_until_target(&"move_right", &"door")
	assert_not_null(room_door, "step 8 parsed movement reaches the room door")
	if room_door == null:
		return
	assert_eq(room_door.get_interaction().payload, {"map_id": &"foundation_hall", "spawn_id": &"from_room", "object_id": &"to_hall"}, "step 8 room door has its stable ID and exact destination")
	var persistent_player_id: int = player.get_instance_id()
	var room_to_hall_started := [0]
	var committed_rebind_cleared_target := [false]
	var transition_counter := func(from_map: StringName, to_map: StringName) -> void:
		if from_map == &"foundation_room" and to_map == &"foundation_hall":
			room_to_hall_started[0] += 1
	var commit_observer := func(map_id: StringName, spawn_id: StringName, _committed_player: PlayerController) -> void:
		if map_id == &"foundation_hall" and spawn_id == &"from_room":
			var committed_detector := SceneDirector.get_interaction_detector()
			committed_rebind_cleared_target[0] = committed_detector != null and committed_detector.current_target == null
	SceneDirector.transition_started.connect(transition_counter)
	SceneDirector.map_committed.connect(commit_observer)
	var hall_save := await _observe_save(&"auto", func() -> void:
		harness.interact_current_target()
	)
	if SceneDirector.transition_started.is_connected(transition_counter):
		SceneDirector.transition_started.disconnect(transition_counter)
	if SceneDirector.map_committed.is_connected(commit_observer):
		SceneDirector.map_committed.disconnect(commit_observer)
	assert_eq(hall_save, {"completed": &"auto"}, "step 9 room-to-hall placement updates autosave")
	assert_eq(room_to_hall_started[0], 1, "step 9 room door dispatches one transition")
	assert_true(committed_rebind_cleared_target[0], "step 9 map commit clears the previous-map detector target synchronously")
	if not committed_rebind_cleared_target[0]:
		return
	var hall: MapScene = harness.current_map()
	player = harness.player()
	assert_not_null(hall, "step 9 commits the foundation hall")
	if hall == null or player == null:
		return
	assert_eq(hall.map_id, &"foundation_hall", "step 9 arrives in the hall")
	assert_eq(SceneDirector.capture_save_context().get("spawn_id"), &"from_room", "step 9 records the reciprocal hall spawn")
	assert_eq(player.get_instance_id(), persistent_player_id, "step 9 preserves one player instance")
	assert_eq(player.get_parent(), hall.get_actor_root(), "step 9 reparents the player body to hall Actors")
	assert_eq(player.presentation.get_parent(), hall.get_visual_root(), "step 9 reparents PlayerVisual to hall VisualSort")
	var hall_camera := player.get_node_or_null("Camera2D") as Camera2D
	assert_not_null(hall_camera, "step 9 persistent player keeps its camera")
	if hall_camera != null:
		assert_eq(
			Rect2(hall_camera.limit_left, hall_camera.limit_top, hall_camera.limit_right - hall_camera.limit_left, hall_camera.limit_bottom - hall_camera.limit_top),
			hall.room_bounds,
			"step 9 camera limits match the committed map bounds at edge spawns"
		)
	var top_boundary := hall.get_node_or_null("Boundaries/Top") as StaticBody2D
	var bottom_boundary := hall.get_node_or_null("Boundaries/Bottom") as StaticBody2D
	assert_not_null(top_boundary, "step 9 hall provides a top physics boundary")
	assert_not_null(bottom_boundary, "step 9 hall provides a bottom physics boundary")
	if top_boundary != null and bottom_boundary != null:
		assert_eq(top_boundary.position, Vector2(160, 8), "step 9 top boundary lies on the exact room edge")
		assert_eq(bottom_boundary.position, Vector2(160, 184), "step 9 bottom boundary lies on the exact room edge")
		assert_eq(_boundary_size(top_boundary), Vector2(320, 16), "step 9 top boundary spans the exact room width")
		assert_eq(_boundary_size(bottom_boundary), Vector2(320, 16), "step 9 bottom boundary spans the exact room width")
	await harness.move_for(&"move_up", 120, true)
	assert_true(hall.room_bounds.encloses(_player_collision_bounds(player)), "step 9 parsed move_up cannot move the player body beyond the hall top edge")
	await harness.move_for(&"move_down", 160, true)
	assert_true(hall.room_bounds.encloses(_player_collision_bounds(player)), "step 9 parsed move_down cannot move the player body beyond the hall bottom edge")
	await harness.move_for(&"move_up", 20, true)
	var hall_auto: Dictionary = harness.read_slot(&"auto")
	assert_true(hall_auto.get("ok", false), "step 9 updated hall autosave is valid")
	if hall_auto.get("ok", false):
		assert_eq(hall_auto["data"]["player"]["map_id"], "foundation_hall", "step 9 autosave captures the committed hall")
		assert_eq(hall_auto["data"]["meta"]["location_name"], "기초 홀", "step 9 autosave metadata uses the hall display name")

	await harness.press_key(KEY_ESCAPE)
	assert_true(harness.pause_menu().visible, "step 10 Escape opens the real pause menu")
	(harness.pause_menu().get_node("Panel/Margin/Buttons/Save") as Button).pressed.emit()
	await harness.wait_frames(2)
	assert_true(harness.slot_menu().visible, "step 10 pause save opens the shared slot UI")
	var manual_save := await _observe_save(&"slot_1", func() -> void:
		(harness.slot_menu().get_rows()[1] as SaveSlotRow).activate()
	)
	assert_eq(manual_save, {"completed": &"slot_1"}, "step 10 UI saves manual slot 1")
	var manual_read: Dictionary = harness.read_slot(&"slot_1")
	assert_true(manual_read.get("ok", false), "step 10 manual slot 1 is valid real I/O")
	if not manual_read.get("ok", false):
		return
	var manual_snapshot: Dictionary = manual_read["data"].duplicate(true)
	assert_eq(manual_snapshot["world"]["maps"]["foundation_room"]["mirror"], {"inspected": true}, "step 10 transition captured the interacted foundation_room/mirror state through its stable identity")

	harness.slot_menu().back_requested.emit()
	await harness.wait_frames(2)
	(harness.pause_menu().get_node("Panel/Margin/Buttons/Continue") as Button).pressed.emit()
	await harness.wait_frames(2)
	await harness.move_for(&"move_down", 4)
	GameSession.narrative_state.set_flag(&"mirror_seen", false)
	GameSession.narrative_state.set_flag(&"vertical_slice_mutation", true)
	assert_eq(GameSession.world_state.set_object(&"foundation_room", &"mirror", {"inspected": false}), OK, "step 11 mutates the mirror through the public WorldState API")
	assert_false(GameSession.narrative_state.get_flag(&"mirror_seen"), "step 11 mutates narrative through its public API")
	assert_true(player.global_position != _snapshot_position(manual_snapshot), "step 11 parsed movement mutates player position")
	assert_true(player.facing != _snapshot_facing(manual_snapshot), "step 11 parsed movement mutates player facing")

	await harness.press_key(KEY_ESCAPE)
	(harness.pause_menu().get_node("Panel/Margin/Buttons/Load") as Button).pressed.emit()
	await harness.wait_frames(2)
	var manual_load := await _observe_load(&"slot_1", func() -> void:
		(harness.slot_menu().get_rows()[1] as SaveSlotRow).activate()
	)
	assert_eq(manual_load, {"completed": &"slot_1"}, "step 12 UI loads manual slot 1")
	assert_eq(harness.current_map().map_id, &"foundation_hall", "step 12 restores the exact hall map")
	assert_eq(harness.player().global_position, _snapshot_position(manual_snapshot), "step 12 restores exact player position")
	assert_eq(harness.player().facing, _snapshot_facing(manual_snapshot), "step 12 restores exact player facing")
	assert_eq(GameSession.narrative_state.snapshot(), manual_snapshot["narrative"], "step 12 restores exact NarrativeState")
	assert_eq(GameSession.world_state.snapshot(), manual_snapshot["world"], "step 12 restores exact WorldState")
	assert_eq(GameSession.current_mode, GameModeResource.Value.EXPLORATION, "step 12 inactive manual load resumes exploration")
	assert_false(harness.slot_menu().visible, "step 12 successful UI load closes the slot menu")

	assert_eq(harness.publish_fixture(&"auto", important_fixture), OK, "step 13 republishes the observed important-choice autosave fixture")
	var resolver := CountingEventResolver.new()
	harness.app.dialogue_adapter.event_resolver = resolver
	await harness.press_key(KEY_ESCAPE)
	(harness.pause_menu().get_node("Panel/Margin/Buttons/Load") as Button).pressed.emit()
	await harness.wait_frames(2)
	var important_load := await _observe_load(&"auto", func() -> void:
		(harness.slot_menu().get_rows()[0] as SaveSlotRow).activate()
	)
	assert_eq(important_load, {"completed": &"auto"}, "step 13 loads the important-choice autosave through UI")
	assert_eq(resolver.resolve_count, 0, "step 13 checkpoint resume does not re-run event resolution")
	assert_eq(harness.current_map().map_id, &"foundation_room", "step 13 restores the checkpoint room")
	var restored_mirror := harness.current_map().get_node_or_null("VisualSort/SampleInspectable/PersistentWorldObject") as PersistentWorldObject
	assert_not_null(restored_mirror, "step 13 restores a live persistent mirror object")
	if restored_mirror != null:
		assert_eq(restored_mirror.capture_persisted_state(), {"inspected": true}, "step 13 applies the saved non-default state to the live foundation_room/mirror object")
	assert_eq(harness.dialogue().get_checkpoint(), important_checkpoint, "step 13 resumes the exact active checkpoint")
	assert_eq(harness.dialogue().current_node_id, &"default.inspect.line_e5b0e4bd5f23", "step 13 resumes directly at the saved next line")
	assert_eq((harness.dialogue_view().get_node("Panel/Margin/Layout/Content/TextLabel") as Label).text, "거울 속에는 이 방과 조금 다른 방이 비친다.", "step 13 renders the exact resumed line")
	assert_true(await _advance_to_node_type("choice"), "step 13 resumed dialogue can continue to its next choice")
	assert_true(await _choose_by_text("조사를 마친다"), "step 13 resumed dialogue chooses its finish branch")
	assert_true(await _advance_until_dialogue_ends(), "step 13 resumed dialogue finishes normally")

	assert_eq(harness.rotate_current_to_backup(&"slot_1"), OK, "step 14 creates a valid slot 1 backup through the real repository transaction")
	assert_true(FileAccess.file_exists(harness.backup_path(&"slot_1")), "step 14 retains a byte-valid backup before corruption")
	assert_eq(harness.corrupt_current(&"slot_1"), OK, "step 14 corrupts only the isolated current slot 1")
	var recovery_count := [0]
	var recovery_handler := func(slot_id: StringName) -> void:
		if slot_id == &"slot_1":
			recovery_count[0] += 1
	SaveService.backup_recovered.connect(recovery_handler)
	await harness.press_key(KEY_ESCAPE)
	(harness.pause_menu().get_node("Panel/Margin/Buttons/Load") as Button).pressed.emit()
	await harness.wait_frames(2)
	var recovered_load := await _observe_load(&"slot_1", func() -> void:
		(harness.slot_menu().get_rows()[1] as SaveSlotRow).activate()
	)
	if SaveService.backup_recovered.is_connected(recovery_handler):
		SaveService.backup_recovered.disconnect(recovery_handler)
	assert_eq(recovered_load, {"completed": &"slot_1"}, "step 14 loads slot 1 through verified backup recovery")
	assert_eq(recovery_count[0], 1, "step 14 reports backup recovery exactly once")
	assert_eq(harness.toast_layer().current_message(), "백업 저장을 복구했습니다", "step 14 shows the exact Korean recovery toast")
	assert_eq(harness.current_map().map_id, &"foundation_hall", "step 14 recovery restores the saved hall")
	assert_eq(harness.player().global_position, _snapshot_position(manual_snapshot), "step 14 recovery restores the backed-up player state")

	var hall_door: InteractionTarget = await harness.move_until_target(&"move_left", &"door", 60, false)
	assert_not_null(hall_door, "step 15 parsed movement faces the hall return door")
	if hall_door == null:
		return
	assert_eq(hall_door.get_interaction().payload, {"map_id": &"foundation_room", "spawn_id": &"from_hall", "object_id": &"to_room"}, "step 15 hall door has its stable ID and exact reciprocal destination")
	assert_eq(_adapter_connection_count(harness.router(), harness.app.door_adapter), 1, "step 15 return door begins with one adapter connection")
	var return_transitions := [0]
	var return_handler := func(from_map: StringName, to_map: StringName) -> void:
		if from_map == &"foundation_hall" and to_map == &"foundation_room":
			return_transitions[0] += 1
	SceneDirector.transition_started.connect(return_handler)
	await harness.interact_current_target()
	assert_true(await harness.wait_until(func() -> bool:
		var current: MapScene = harness.current_map()
		return current != null and current.map_id == &"foundation_room" and GameSession.current_mode == GameModeResource.Value.EXPLORATION
	), "step 15 hall return door completes the reciprocal transition")
	await harness.wait_frames(4)
	if SceneDirector.transition_started.is_connected(return_handler):
		SceneDirector.transition_started.disconnect(return_handler)
	assert_eq(return_transitions[0], 1, "step 15 return-door wiring executes exactly once")
	assert_eq(SceneDirector.capture_save_context().get("spawn_id"), &"from_hall", "step 15 returns at the exact room spawn")
	assert_eq(harness.player().get_instance_id(), persistent_player_id, "step 15 round trip preserves the persistent player")
	assert_eq(_adapter_connection_count(harness.router(), harness.app.door_adapter), 1, "step 15 rebind keeps one door adapter connection")

func _observe_save(slot_id: StringName, action: Callable) -> Dictionary:
	var outcome := {}
	var completed_handler := func(completed_slot: StringName) -> void:
		if completed_slot == slot_id:
			outcome["completed"] = completed_slot
	var failed_handler := func(failed_slot: StringName, context: Dictionary) -> void:
		if failed_slot == slot_id:
			outcome["failed"] = {"slot_id": failed_slot, "context": context.duplicate(true)}
	SaveService.save_completed.connect(completed_handler)
	SaveService.save_failed.connect(failed_handler)
	action.call()
	await harness.wait_until(func() -> bool: return not outcome.is_empty())
	if SaveService.save_completed.is_connected(completed_handler):
		SaveService.save_completed.disconnect(completed_handler)
	if SaveService.save_failed.is_connected(failed_handler):
		SaveService.save_failed.disconnect(failed_handler)
	return outcome.duplicate(true)

func _observe_load(slot_id: StringName, action: Callable) -> Dictionary:
	var outcome := {}
	var completed_handler := func(completed_slot: StringName) -> void:
		if completed_slot == slot_id:
			outcome["completed"] = completed_slot
	var failed_handler := func(failed_slot: StringName, context: Dictionary) -> void:
		if failed_slot == slot_id:
			outcome["failed"] = {"slot_id": failed_slot, "context": context.duplicate(true)}
	SaveService.load_completed.connect(completed_handler)
	SaveService.load_failed.connect(failed_handler)
	action.call()
	await harness.wait_until(func() -> bool: return not outcome.is_empty())
	if SaveService.load_completed.is_connected(completed_handler):
		SaveService.load_completed.disconnect(completed_handler)
	if SaveService.load_failed.is_connected(failed_handler):
		SaveService.load_failed.disconnect(failed_handler)
	return outcome.duplicate(true)

func _advance_to_node_type(node_type: String) -> bool:
	for _step: int in 32:
		var dialogue: DialogueService = harness.dialogue()
		if dialogue.current_graph == null:
			return false
		if String(dialogue.current_graph.get_node(dialogue.current_node_id).get("type", "")) == node_type:
			return true
		await harness.press_action(&"ui_accept")
	return false

func _advance_until_dialogue_ends() -> bool:
	for _step: int in 32:
		if harness.dialogue().current_graph == null:
			return true
		var node_type := String(harness.dialogue().current_graph.get_node(harness.dialogue().current_node_id).get("type", ""))
		if node_type != "line":
			return false
		await harness.press_action(&"ui_accept")
	return harness.dialogue().current_graph == null

func _choice_index_with_effect(choice_node: Dictionary, effect_key: StringName) -> int:
	var items_value: Variant = choice_node.get("items", [])
	if typeof(items_value) != TYPE_ARRAY:
		return -1
	var items: Array = items_value
	for index: int in items.size():
		var item_value: Variant = items[index]
		if typeof(item_value) != TYPE_DICTIONARY:
			continue
		var effects_value: Variant = (item_value as Dictionary).get("effects", [])
		if typeof(effects_value) != TYPE_ARRAY:
			continue
		for effect_value: Variant in effects_value:
			if typeof(effect_value) == TYPE_DICTIONARY and String(effect_value.get("key", "")) == String(effect_key):
				return index
	return -1

func _activate_choice(index: int) -> void:
	var container: VBoxContainer = harness.dialogue_view().choice_container
	if index < 0 or index >= container.get_child_count():
		return
	var button := container.get_child(index) as Button
	if button != null:
		button.grab_focus()
		button.pressed.emit()

func _choose_by_text(text: String) -> bool:
	var container: VBoxContainer = harness.dialogue_view().choice_container
	for child: Node in container.get_children():
		if child is Button and (child as Button).text == text:
			(child as Button).pressed.emit()
			await harness.wait_frames(2)
			return true
	return false

func _snapshot_position(snapshot: Dictionary) -> Vector2:
	var position: Dictionary = snapshot["player"]["position"]
	return Vector2(float(position["x"]), float(position["y"]))

func _snapshot_facing(snapshot: Dictionary) -> Vector2:
	match String(snapshot["player"]["facing"]):
		"left": return Vector2.LEFT
		"right": return Vector2.RIGHT
		"up": return Vector2.UP
		_: return Vector2.DOWN

func _player_collision_bounds(player: PlayerController) -> Rect2:
	var collision := player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null or not collision.shape is RectangleShape2D:
		return Rect2()
	var rectangle := collision.shape as RectangleShape2D
	return Rect2(collision.global_position - rectangle.size * 0.5, rectangle.size)

func _boundary_size(boundary: StaticBody2D) -> Vector2:
	var collision := boundary.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision == null or not collision.shape is RectangleShape2D:
		return Vector2.ZERO
	return (collision.shape as RectangleShape2D).size

func _adapter_connection_count(router: InteractionRouter, adapter: Node) -> int:
	var count := 0
	for connection: Dictionary in router.action_requested.get_connections():
		var callable: Callable = connection.get("callable", Callable())
		if callable.get_object() == adapter and callable.get_method() == &"handle_action":
			count += 1
	return count
