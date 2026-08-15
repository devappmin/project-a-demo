extends "res://tests/support/test_case.gd"

const GameModeResource = preload("res://app/session/game_mode.gd")

class UnhandledInputProbe extends Node:
	var interact_press_count := 0

	func _unhandled_input(event: InputEvent) -> void:
		if event.is_action_pressed(&"interact", false):
			interact_press_count += 1

func run() -> void:
	var previous_mode: int = GameSession.current_mode
	var previous_state: NarrativeState = GameSession.narrative_state
	GameSession.change_mode(GameModeResource.Value.EXPLORATION)
	GameSession.narrative_state = NarrativeState.new()

	var probe := UnhandledInputProbe.new()
	probe.name = "UnhandledInputProbe"
	get_tree().root.add_child(probe)
	var app_scene := load("res://app/bootstrap/app_root.tscn") as PackedScene
	assert_not_null(app_scene, "AppRoot scene loads for dialogue integration")
	if app_scene == null:
		probe.queue_free()
		await get_tree().process_frame
		GameSession.narrative_state = previous_state
		GameSession.change_mode(previous_mode)
		return
	var app := app_scene.instantiate()
	assert_not_null(app, "AppRoot scene instantiates for dialogue integration")
	if app == null:
		probe.queue_free()
		await get_tree().process_frame
		GameSession.narrative_state = previous_state
		GameSession.change_mode(previous_mode)
		return
	get_tree().root.add_child(app)
	await get_tree().process_frame

	var router := app.get_node_or_null("WorldHost/FoundationRoom/Player/InteractionRouter") as InteractionRouter
	var dialogue := app.get_node_or_null("ServiceLayer/DialogueService") as DialogueService
	var view := app.get_node_or_null("UILayer/DialogueView") as DialogueView
	assert_not_null(router, "real AppRoot exposes its player interaction router")
	assert_not_null(dialogue, "real AppRoot exposes its dialogue service")
	assert_not_null(view, "real AppRoot exposes its dialogue view")
	if router == null or dialogue == null or view == null:
		app.queue_free()
		probe.queue_free()
		await get_tree().process_frame
		GameSession.narrative_state = previous_state
		GameSession.change_mode(previous_mode)
		return
	var adapter := app.get_node_or_null("ServiceLayer/DialogueActionAdapter")
	_test_single_app_composition(router, dialogue, adapter)
	_test_production_fixture_is_immutable()
	_test_invalid_adapter_payloads_are_ignored(router, dialogue)
	_test_talk_payload_starts_and_abort_restores(router, dialogue, view)
	await _test_visible_mirror_keyboard_flow(app, router, dialogue, view, probe)
	await _test_plan3_replacement_snapshot(app, dialogue, view, probe)

	if dialogue.current_graph != null:
		dialogue.abort_dialogue(&"test_cleanup")
	app.queue_free()
	probe.queue_free()
	await get_tree().process_frame
	GameSession.narrative_state = previous_state
	GameSession.change_mode(previous_mode)

func _test_single_app_composition(router: InteractionRouter, dialogue: DialogueService, adapter: Node) -> void:
	assert_not_null(adapter, "AppRoot owns one dialogue action adapter")
	if adapter == null:
		return
	assert_eq(adapter.get("dialogue_service"), dialogue, "adapter uses the existing AppRoot dialogue service")
	var matching_connections := 0
	for connection: Dictionary in router.action_requested.get_connections():
		var callable: Callable = connection.get("callable", Callable())
		if callable.get_object() == adapter and callable.get_method() == &"handle_action":
			matching_connections += 1
	assert_eq(matching_connections, 1, "AppRoot connects its router to the adapter exactly once")

func _test_production_fixture_is_immutable() -> void:
	var loader := DialogueGraphLoader.new()
	var graph := loader.load_scene(&"foundation.inspect")
	assert_not_null(graph, "production foundation dialogue loads")
	if graph == null:
		return
	assert_eq(graph.scene_key, &"foundation.inspect", "production graph keeps its internal scene key")
	var choice_id := _first_node_of_type(graph, "choice")
	assert_false(choice_id.is_empty(), "production graph contains a choice boundary")
	if choice_id.is_empty():
		return
	var choice := graph.get_node(choice_id)
	var items_value: Variant = choice.get("items", [])
	assert_true(typeof(items_value) == TYPE_ARRAY and not items_value.is_empty(), "production choice contains items")
	if typeof(items_value) != TYPE_ARRAY or items_value.is_empty():
		return
	var items: Array = items_value
	var original_text := String(items[0].get("text", "")) if typeof(items[0]) == TYPE_DICTIONARY else ""
	assert_false(original_text.is_empty(), "production choice item has text")
	if typeof(items[0]) != TYPE_DICTIONARY or original_text.is_empty():
		return
	items[0]["text"] = "mutated"
	var unchanged := graph.get_node(choice_id)
	var unchanged_items_value: Variant = unchanged.get("items", [])
	assert_true(typeof(unchanged_items_value) == TYPE_ARRAY and not unchanged_items_value.is_empty(), "immutable graph still returns its choice items")
	if typeof(unchanged_items_value) == TYPE_ARRAY and not unchanged_items_value.is_empty() and typeof(unchanged_items_value[0]) == TYPE_DICTIONARY:
		assert_eq(unchanged_items_value[0].get("text", ""), original_text, "fixture choices are returned as deep copies")

func _test_invalid_adapter_payloads_are_ignored(router: InteractionRouter, dialogue: DialogueService) -> void:
	var invalid_requests: Array[Dictionary] = [
		{"kind":&"use", "payload":{"scene_key":&"foundation.inspect", "node_id":&"line_1"}},
		{"kind":&"inspect", "payload":{}},
		{"kind":&"inspect", "payload":{"scene_key":&"", "node_id":&"line_1"}},
		{"kind":&"inspect", "payload":{"scene_key":17, "node_id":&"line_1"}},
		{"kind":&"talk", "payload":{"scene_key":&"foundation.inspect", "node_id":17}},
	]
	for request: Dictionary in invalid_requests:
		router.action_requested.emit(request["kind"], request["payload"])
		assert_eq(GameSession.current_mode, GameModeResource.Value.EXPLORATION, "unsupported or malformed action preserves exploration")
		assert_eq(dialogue.current_graph, null, "unsupported or malformed action does not start dialogue")

func _test_talk_payload_starts_and_abort_restores(router: InteractionRouter, dialogue: DialogueService, view: DialogueView) -> void:
	router.action_requested.emit(&"talk", {"scene_key":&"foundation.inspect"})
	assert_eq(GameSession.current_mode, GameModeResource.Value.DIALOGUE, "talk payload enters dialogue")
	assert_not_null(dialogue.current_graph, "talk payload loads the production graph")
	if dialogue.current_graph != null:
		assert_eq(dialogue.current_node_id, dialogue.current_graph.entry_node, "missing node override uses the loaded graph entry")
	dialogue.abort_dialogue(&"test_cleanup")
	assert_eq(GameSession.current_mode, GameModeResource.Value.EXPLORATION, "abort restores exploration")
	assert_false(view.visible, "abort hides the dialogue view")

func _test_visible_mirror_keyboard_flow(app: Node, router: InteractionRouter, dialogue: DialogueService, view: DialogueView, probe: UnhandledInputProbe) -> void:
	var room := app.get_node_or_null("WorldHost/FoundationRoom") as MapScene
	var prompt := app.get_node_or_null("UILayer/InteractionPrompt") as InteractionPrompt
	assert_not_null(room, "AppRoot exposes the foundation room")
	assert_not_null(prompt, "AppRoot exposes the interaction prompt")
	if room == null or prompt == null:
		return
	var player := room.get_node_or_null("Player") as PlayerController
	var mirror := room.get_node_or_null("VisualSort/SampleInspectable") as InteractionTarget
	assert_not_null(player, "foundation room exposes its player")
	assert_not_null(mirror, "foundation room exposes its mirror")
	if player == null or mirror == null:
		return
	var detector := player.get_node_or_null("InteractionDetector") as InteractionDetector
	assert_not_null(detector, "player exposes its interaction detector")
	if detector == null:
		return
	var interaction := mirror.get_interaction()
	assert_eq(interaction.kind, &"inspect", "mirror requests inspection")
	assert_eq(interaction.payload, {"scene_key":&"foundation.inspect"}, "mirror defers normal entry to the compiled graph")

	player.position = mirror.position - Vector2(32, 0)
	player.facing = Vector2.RIGHT
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(detector.current_target, mirror, "front-facing mirror becomes the current target")
	assert_true(prompt.visible, "front-facing mirror shows its prompt")
	var prompt_label := prompt.get_node_or_null("PanelContainer/PromptLabel") as Label
	assert_not_null(prompt_label, "interaction prompt exposes its label")
	if prompt_label != null:
		assert_eq(prompt_label.text, "거울 조사하기 [E]", "mirror prompt names the interaction key")

	probe.interact_press_count = 0
	_send_key(KEY_E, true)
	await get_tree().process_frame
	_send_key(KEY_E, false)
	await get_tree().process_frame
	assert_eq(GameSession.current_mode, GameModeResource.Value.DIALOGUE, "parsed E key input opens the mirror dialogue")
	assert_eq(probe.interact_press_count, 0, "a synchronous mode-changing interaction cannot be reused by another unhandled-input consumer")
	assert_false(GameSession.can(GameModeResource.ACTION_MOVE), "dialogue blocks movement through session permissions")
	assert_false(GameSession.can(GameModeResource.ACTION_INTERACT), "dialogue blocks world interaction through session permissions")
	assert_eq(router.execute_target(mirror), ERR_UNAUTHORIZED, "router continues to enforce session interaction permissions")
	assert_false(prompt.visible, "dialogue mode hides the world interaction prompt")
	assert_true(view.visible, "dialogue view is visible after mirror interaction")
	var name_label := view.get_node_or_null("Panel/Margin/Layout/Content/NameLabel") as Label
	var text_label := view.get_node_or_null("Panel/Margin/Layout/Content/TextLabel") as Label
	var portrait := view.get_node_or_null("Panel/Margin/Layout/Portrait") as TextureRect
	assert_not_null(name_label, "dialogue view exposes its name label")
	assert_not_null(text_label, "dialogue view exposes its text label")
	assert_not_null(portrait, "dialogue view exposes its portrait")
	if name_label != null:
		assert_eq(name_label.text, "레티", "mirror line resolves the speaker name")
	if text_label != null:
		assert_false(text_label.text.is_empty(), "mirror entry renders line text")
	var retti: Resource = load("res://data/characters/retti.tres")
	assert_not_null(retti, "retti character resource loads for the mirror line")
	if retti != null and portrait != null:
		assert_not_null(portrait.texture, "mirror line renders a portrait")

	var line_count := await _advance_to_choice(dialogue)
	assert_true(line_count >= 1, "mirror flow presents at least one line before choices")
	assert_eq(_current_node_type(dialogue), "choice", "keyboard advance reaches a semantic choice boundary")
	var choices := view.get_node_or_null("Panel/Margin/Layout/Content/ChoiceScroll/ChoiceContainer") as VBoxContainer
	assert_not_null(choices, "dialogue view exposes its choice container")
	if choices == null:
		dialogue.abort_dialogue(&"test_cleanup")
		return
	assert_true(choices.get_child_count() >= 1, "mirror dialogue renders visible choices")
	if choices.get_child_count() >= 1:
		assert_true(choices.get_child(0).has_focus(), "keyboard focus begins on the first mirror choice")
	var mirror_seen_index := _visible_choice_index_with_effect(dialogue, choices, &"mirror_seen")
	assert_true(mirror_seen_index >= 0, "a visible mirror choice applies mirror_seen")
	if mirror_seen_index < 0:
		dialogue.abort_dialogue(&"test_cleanup")
		return
	choices.get_child(mirror_seen_index).grab_focus()
	await get_tree().process_frame
	_send_action(&"ui_accept", true)
	await get_tree().process_frame
	_send_action(&"ui_accept", false)
	await get_tree().process_frame
	assert_true(GameSession.narrative_state.get_flag(&"mirror_seen"), "keyboard choice applies mirror_seen")
	assert_eq(GameSession.current_mode, GameModeResource.Value.EXPLORATION, "dialogue end restores exploration")
	assert_false(view.visible, "dialogue end hides the view")
	assert_true(prompt.visible, "exploration restoration shows the still-facing mirror prompt")

func _test_plan3_replacement_snapshot(app: Node, dialogue: DialogueService, view: DialogueView, probe: UnhandledInputProbe) -> void:
	var output_directory := "user://test-output/dialogue-plan3-%s" % Time.get_ticks_usec()
	var absolute_directory := ProjectSettings.globalize_path(output_directory)
	assert_eq(DirAccess.make_dir_recursive_absolute(absolute_directory), OK, "replacement snapshot directory is created")
	var replacement := {
		"schema_version":1,
		"scene_key":"foundation.inspect",
		"entry_node":"4f5a0d43b83e4fdcb7db9c506f24cbee",
		"nodes":{
			"4f5a0d43b83e4fdcb7db9c506f24cbee":{"type":"line", "speaker":"retti", "expression":"neutral", "text":"첫 번째 동기화 대사", "next":"8d3fc4991c214ae6a3b7e762f8be1ea2"},
			"8d3fc4991c214ae6a3b7e762f8be1ea2":{"type":"line", "speaker":"retti", "expression":"uneasy", "text":"두 번째 동기화 대사", "next":"d2348c911c6d4239a26e5f91ad8aa462"},
			"d2348c911c6d4239a26e5f91ad8aa462":{"type":"choice", "items":[
				{"text":"동기화된 거울을 본다", "conditions":[], "effects":[{"kind":"flag_set", "key":"mirror_seen", "value":true}], "next":"f6bb116187bd4cf69c09f002fb07c9d8"},
				{"text":"물러난다", "conditions":[], "effects":[], "next":"f6bb116187bd4cf69c09f002fb07c9d8"}
			]},
			"f6bb116187bd4cf69c09f002fb07c9d8":{"type":"end"}
		}
	}
	var snapshot_path := output_directory.path_join("foundation_inspect.json")
	var file := FileAccess.open(snapshot_path, FileAccess.WRITE)
	assert_not_null(file, "replacement snapshot file opens")
	if file == null:
		DirAccess.remove_absolute(absolute_directory)
		return
	file.store_string(JSON.stringify(replacement))
	file.close()
	var loader := DialogueGraphLoader.new()
	loader.base_directory = output_directory
	dialogue.graph_loader = loader
	GameSession.narrative_state.set_flag(&"mirror_seen", false)
	var room := app.get_node_or_null("WorldHost/FoundationRoom") as MapScene
	assert_not_null(room, "replacement snapshot uses the real foundation room")
	if room == null:
		return
	var player := room.get_node_or_null("Player") as PlayerController
	var mirror := room.get_node_or_null("VisualSort/SampleInspectable") as InteractionTarget
	assert_not_null(player, "replacement snapshot uses the real player")
	assert_not_null(mirror, "replacement snapshot uses the real mirror")
	if player == null or mirror == null:
		return
	player.position = mirror.position - Vector2(32, 0)
	player.facing = Vector2.RIGHT
	await get_tree().physics_frame
	await get_tree().physics_frame
	probe.interact_press_count = 0
	_send_key(KEY_E, true)
	await get_tree().process_frame
	_send_key(KEY_E, false)
	await get_tree().process_frame
	assert_eq(dialogue.current_node_id, StringName(replacement["entry_node"]), "mirror uses the replacement graph entry instead of a stale local node id")
	assert_eq(await _advance_to_choice(dialogue), 2, "replacement snapshot can contain multiple lines before its choice")
	var choices := view.get_node_or_null("Panel/Margin/Layout/Content/ChoiceScroll/ChoiceContainer") as VBoxContainer
	assert_not_null(choices, "replacement snapshot reaches the real choice container")
	if choices == null:
		if dialogue.current_graph != null:
			dialogue.abort_dialogue(&"test_cleanup")
		dialogue.graph_loader = DialogueGraphLoader.new()
		DirAccess.remove_absolute(ProjectSettings.globalize_path(snapshot_path))
		DirAccess.remove_absolute(absolute_directory)
		return
	assert_eq(choices.get_child_count(), 2, "replacement snapshot publishes its choices")
	if choices.get_child_count() == 2:
		choices.get_child(0).pressed.emit()
	assert_true(GameSession.narrative_state.get_flag(&"mirror_seen"), "replacement snapshot choice applies mirror_seen offline")
	assert_eq(GameSession.current_mode, GameModeResource.Value.EXPLORATION, "replacement snapshot restores exploration")
	dialogue.graph_loader = DialogueGraphLoader.new()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(snapshot_path))
	DirAccess.remove_absolute(absolute_directory)

func _advance_to_choice(dialogue: DialogueService) -> int:
	var line_count := 0
	while dialogue.current_graph != null and _current_node_type(dialogue) == "line" and line_count < 32:
		line_count += 1
		_send_action(&"ui_accept", true)
		await get_tree().process_frame
		_send_action(&"ui_accept", false)
		await get_tree().process_frame
	return line_count

func _current_node_type(dialogue: DialogueService) -> String:
	if dialogue.current_graph == null:
		return ""
	return String(dialogue.current_graph.get_node(dialogue.current_node_id).get("type", ""))

func _first_node_of_type(graph: DialogueGraph, node_type: String) -> StringName:
	var node_ids: Array = graph.nodes.keys()
	node_ids.sort()
	for node_id: Variant in node_ids:
		if String(graph.get_node(StringName(node_id)).get("type", "")) == node_type:
			return StringName(node_id)
	return &""

func _visible_choice_index_with_effect(dialogue: DialogueService, choices: VBoxContainer, effect_key: StringName) -> int:
	if dialogue.current_graph == null:
		return -1
	var node := dialogue.current_graph.get_node(dialogue.current_node_id)
	var items_value: Variant = node.get("items", [])
	if typeof(items_value) != TYPE_ARRAY:
		return -1
	for item_value: Variant in items_value:
		if typeof(item_value) != TYPE_DICTIONARY:
			continue
		var effects_value: Variant = item_value.get("effects", [])
		if typeof(effects_value) != TYPE_ARRAY:
			continue
		for effect_value: Variant in effects_value:
			if typeof(effect_value) == TYPE_DICTIONARY and String(effect_value.get("key", "")) == String(effect_key):
				for index: int in choices.get_child_count():
					if choices.get_child(index) is Button and choices.get_child(index).text == String(item_value.get("text", "")):
						return index
	return -1

func _send_key(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)

func _send_action(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(event)
