extends "res://tests/support/test_case.gd"

const GameModeResource = preload("res://app/session/game_mode.gd")

class UnhandledInputProbe extends Node:
	var interact_press_count := 0

	func _unhandled_input(event: InputEvent) -> void:
		if event.is_action_pressed(&"interact", false):
			interact_press_count += 1

func run() -> void:
	var previous_mode: int = GameSession.current_mode
	var previous_state: Dictionary = GameSession.narrative_state.snapshot()
	GameSession.change_mode(GameModeResource.Value.EXPLORATION)
	GameSession.narrative_state = NarrativeState.new()

	var probe := UnhandledInputProbe.new()
	probe.name = "UnhandledInputProbe"
	get_tree().root.add_child(probe)
	var app_scene := load("res://app/bootstrap/app_root.tscn") as PackedScene
	var app := app_scene.instantiate()
	get_tree().root.add_child(app)
	await get_tree().process_frame

	var router := app.get_node("WorldHost/FoundationRoom/Player/InteractionRouter") as InteractionRouter
	var dialogue := app.get_node("ServiceLayer/DialogueService") as DialogueService
	var view := app.get_node("UILayer/DialogueView") as DialogueView
	var adapter := app.get_node_or_null("ServiceLayer/DialogueActionAdapter")
	_test_single_app_composition(router, dialogue, adapter)
	_test_production_fixture_is_immutable()
	_test_invalid_adapter_payloads_are_ignored(router, dialogue)
	_test_talk_payload_starts_and_abort_restores(router, dialogue, view)
	await _test_visible_mirror_keyboard_flow(app, router, dialogue, view, probe)

	if dialogue.current_graph != null:
		dialogue.abort_dialogue(&"test_cleanup")
	app.queue_free()
	probe.queue_free()
	await get_tree().process_frame
	GameSession.narrative_state.restore(previous_state)
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
	var choice := graph.get_node(&"choice_1")
	choice["items"][0]["text"] = "mutated"
	choice["items"][0]["effects"][0]["value"] = false
	var unchanged := graph.get_node(&"choice_1")
	assert_eq(unchanged["items"][0]["text"], "자세히 본다", "fixture choices are returned as deep copies")
	assert_eq(unchanged["items"][0]["effects"][0]["value"], true, "fixture effects remain immutable during play")

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
	router.action_requested.emit(&"talk", {"scene_key":&"foundation.inspect", "node_id":&"line_1"})
	assert_eq(GameSession.current_mode, GameModeResource.Value.DIALOGUE, "talk payload enters dialogue")
	assert_eq(dialogue.current_node_id, &"line_1", "talk payload forwards its entry node")
	dialogue.abort_dialogue(&"test_cleanup")
	assert_eq(GameSession.current_mode, GameModeResource.Value.EXPLORATION, "abort restores exploration")
	assert_false(view.visible, "abort hides the dialogue view")

func _test_visible_mirror_keyboard_flow(app: Node, router: InteractionRouter, dialogue: DialogueService, view: DialogueView, probe: UnhandledInputProbe) -> void:
	var room := app.get_node("WorldHost/FoundationRoom") as MapScene
	var player := room.get_node("Player") as PlayerController
	var detector := player.get_node("InteractionDetector") as InteractionDetector
	var mirror := room.get_node("VisualSort/SampleInspectable") as InteractionTarget
	var prompt := app.get_node("UILayer/InteractionPrompt") as InteractionPrompt
	var interaction := mirror.get_interaction()
	assert_eq(interaction.kind, &"inspect", "mirror requests inspection")
	assert_eq(interaction.payload, {"scene_key":&"foundation.inspect", "node_id":&"line_1"}, "mirror exposes the dialogue payload contract")

	player.position = mirror.position - Vector2(32, 0)
	player.facing = Vector2.RIGHT
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(detector.current_target, mirror, "front-facing mirror becomes the current target")
	assert_true(prompt.visible, "front-facing mirror shows its prompt")
	assert_eq(prompt.get_node("PanelContainer/PromptLabel").text, "거울 조사하기 [E]", "mirror prompt names the interaction key")

	probe.interact_press_count = 0
	_send_action(&"interact", true)
	await get_tree().process_frame
	_send_action(&"interact", false)
	await get_tree().process_frame
	assert_eq(GameSession.current_mode, GameModeResource.Value.DIALOGUE, "real E input opens the mirror dialogue")
	assert_eq(probe.interact_press_count, 0, "a synchronous mode-changing interaction cannot be reused by another unhandled-input consumer")
	assert_false(GameSession.can(GameModeResource.ACTION_MOVE), "dialogue blocks movement through session permissions")
	assert_false(GameSession.can(GameModeResource.ACTION_INTERACT), "dialogue blocks world interaction through session permissions")
	assert_eq(router.execute_target(mirror), ERR_UNAUTHORIZED, "router continues to enforce session interaction permissions")
	assert_false(prompt.visible, "dialogue mode hides the world interaction prompt")
	assert_true(view.visible, "dialogue view is visible after mirror interaction")
	assert_eq(view.get_node("Panel/Margin/Layout/Content/NameLabel").text, "레티", "mirror line resolves the speaker name")
	assert_eq(view.get_node("Panel/Margin/Layout/Content/TextLabel").text, "낯선 거울이다.", "mirror line renders its uneasy text")
	var retti: Resource = load("res://data/characters/retti.tres")
	assert_eq(view.get_node("Panel/Margin/Layout/Portrait").texture, retti.resolve_portrait(&"uneasy"), "mirror line renders the uneasy portrait")

	_send_action(&"ui_accept", true)
	await get_tree().process_frame
	_send_action(&"ui_accept", false)
	await get_tree().process_frame
	assert_eq(dialogue.current_node_id, &"choice_1", "keyboard advance reaches the choice")
	var choices := view.get_node("Panel/Margin/Layout/Content/ChoiceContainer") as VBoxContainer
	assert_eq(choices.get_child_count(), 2, "mirror dialogue renders both choices")
	if choices.get_child_count() == 2:
		assert_eq(choices.get_child(0).text, "자세히 본다", "first keyboard choice keeps fixture order")
		assert_eq(choices.get_child(1).text, "뒤로 물러난다", "second keyboard choice keeps fixture order")
		assert_true(choices.get_child(0).has_focus(), "keyboard focus begins on the first mirror choice")

	_send_action(&"ui_accept", true)
	await get_tree().process_frame
	_send_action(&"ui_accept", false)
	await get_tree().process_frame
	assert_true(GameSession.narrative_state.get_flag(&"mirror_seen"), "keyboard choice applies mirror_seen")
	assert_eq(GameSession.current_mode, GameModeResource.Value.EXPLORATION, "dialogue end restores exploration")
	assert_false(view.visible, "dialogue end hides the view")
	assert_true(prompt.visible, "exploration restoration shows the still-facing mirror prompt")

func _send_action(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	event.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(event)
