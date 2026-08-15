extends "res://tests/support/test_case.gd"

const SERVICE_PATH := "res://game/narrative/dialogue/dialogue_service.gd"
const CHARACTER_PATH := "res://data/characters/character_definition.gd"
const VIEW_SCENE_PATH := "res://ui/dialogue/dialogue_view.tscn"
const GameModeResource = preload("res://app/session/game_mode.gd")
const GameSessionResource = preload("res://app/session/game_session.gd")

class GraphLoaderStub extends DialogueGraphLoader:
	var graph_to_return: DialogueGraph
	var failure_to_return: Dictionary = {}

	func load_scene(_scene_key: StringName) -> DialogueGraph:
		last_failure = failure_to_return.duplicate(true)
		return graph_to_return

var _lines: Array[Dictionary] = []
var _choices: Array[Array] = []
var _commands: Array[Dictionary] = []
var _failures: Array[Dictionary] = []
var _finished_count := 0
var _requested_choice_indices: Array[int] = []

func run() -> void:
	var service_script: Variant = load(SERVICE_PATH)
	assert_not_null(service_script, "dialogue service script exists")
	if service_script == null or not service_script.can_instantiate():
		assert_true(false, "dialogue service script parses and can instantiate")
		return
	assert_not_null(load(CHARACTER_PATH), "character definition script exists")
	assert_not_null(load(VIEW_SCENE_PATH), "dialogue view scene exists")
	if load(CHARACTER_PATH) == null or load(VIEW_SCENE_PATH) == null:
		return
	_test_valid_branch(service_script)
	_test_load_and_entry_failures_preserve_mode(service_script)
	_test_end_and_abort_restore_exact_mode(service_script)
	_test_automatic_dispatch_and_guard(service_script)
	_test_choice_filtering_index_stability_and_checkpoint(service_script)
	_test_zero_visible_choices_fail_safely(service_script)
	_test_runtime_failure_rolls_back_choice_effects(service_script)
	_test_downstream_choice_failure_rolls_back_before_publication(service_script)
	await _test_character_resources_and_view_scene()

func _test_valid_branch(service_script: Variant) -> void:
	_reset_captures()
	var session := _session_in_mode(GameModeResource.Value.EXPLORATION)
	var loader := DialogueGraphLoader.new()
	loader.base_directory = "res://tests/fixtures/dialogues"
	var service: Variant = _configured_service(service_script, loader, session)
	assert_eq(service.start_dialogue(&"valid.branch"), OK, "dialogue starts")
	assert_eq(session.current_mode, GameModeResource.Value.DIALOGUE, "successful load enters dialogue mode")
	assert_eq(service.current_node_id, &"line_1", "entry line selected")
	assert_eq(_lines.size(), 1, "entry line is requested once")
	service.advance()
	assert_eq(service.current_node_id, &"choice_1", "advance reaches choice")
	assert_eq(_choices.size(), 1, "choice boundary requests visible choices")
	assert_eq(service.choose(0), OK, "choice accepted")
	assert_true(session.narrative_state.get_flag(&"mirror_seen"), "choice effect applied")
	assert_eq(session.current_mode, GameModeResource.Value.EXPLORATION, "end restores exploration")
	assert_eq(_finished_count, 1, "end emits finished")
	service.free()
	session.free()

func _test_load_and_entry_failures_preserve_mode(service_script: Variant) -> void:
	_reset_captures()
	var session := _session_in_mode(GameModeResource.Value.PAUSED)
	var missing_loader := DialogueGraphLoader.new()
	missing_loader.base_directory = "res://tests/fixtures/dialogues"
	var service: Variant = _configured_service(service_script, missing_loader, session)
	assert_eq(service.start_dialogue(&"missing"), ERR_CANT_OPEN, "load failure is returned")
	assert_eq(session.current_mode, GameModeResource.Value.PAUSED, "load failure never enters dialogue")
	assert_eq(_failures[-1].get("reason"), &"load_failed", "load failure has stable context")
	service.free()

	_reset_captures()
	var valid_loader := DialogueGraphLoader.new()
	valid_loader.base_directory = "res://tests/fixtures/dialogues"
	service = _configured_service(service_script, valid_loader, session)
	assert_eq(service.start_dialogue(&"valid.branch", &"missing_node"), ERR_INVALID_PARAMETER, "invalid entry override is rejected")
	assert_eq(session.current_mode, GameModeResource.Value.PAUSED, "invalid entry override preserves mode")
	assert_eq(service.current_graph, null, "invalid start leaves no active graph")
	service.free()
	session.free()

func _test_end_and_abort_restore_exact_mode(service_script: Variant) -> void:
	_reset_captures()
	var session := _session_in_mode(GameModeResource.Value.PAUSED)
	var service: Variant = _service_for_graph(service_script, _graph("instant", "end", {"end":{"type":"end"}}), session)
	var transitions: Array[int] = []
	session.mode_changed.connect(func(_previous: int, current: int) -> void: transitions.append(current))
	assert_eq(service.start_dialogue(&"instant"), OK, "end-only dialogue starts")
	assert_true(GameModeResource.Value.DIALOGUE in transitions, "end-only dialogue enters dialogue after load")
	assert_eq(session.current_mode, GameModeResource.Value.PAUSED, "end restores exact prior paused mode")
	service.free()
	session.free()

	_reset_captures()
	session = _session_in_mode(GameModeResource.Value.MENU)
	service = _service_for_graph(service_script, _line_graph("abortable"), session)
	assert_eq(service.start_dialogue(&"abortable"), OK, "abortable dialogue starts")
	service.abort_dialogue(&"test_cleanup")
	assert_eq(session.current_mode, GameModeResource.Value.MENU, "abort restores exact prior menu mode")
	assert_eq(_failures[-1].get("reason"), &"test_cleanup", "abort reports its reason")
	assert_eq(service.get_checkpoint(), {}, "abort clears the active checkpoint")
	service.free()
	session.free()

func _test_automatic_dispatch_and_guard(service_script: Variant) -> void:
	_reset_captures()
	var nodes := {
		"command":{"type":"command", "command":{"kind":"camera", "payload":{"shake":1}}, "next":"effect"},
		"effect":{"type":"effect", "effects":[{"kind":"flag_set", "key":"chain_seen", "value":true}], "next":"jump"},
		"jump":{"type":"jump", "next":"line"},
		"line":{"type":"line", "speaker":"retti", "expression":"neutral", "text":"chain complete", "next":"end"},
		"end":{"type":"end"},
	}
	var session := _session_in_mode(GameModeResource.Value.CUTSCENE)
	var graph := _graph("chain", "command", nodes)
	var service: Variant = _service_for_graph(service_script, graph, session)
	assert_eq(service.start_dialogue(&"chain"), OK, "automatic chain starts")
	assert_eq(service.current_node_id, &"line", "command effect and jump chain to line boundary")
	assert_true(session.narrative_state.get_flag(&"chain_seen"), "automatic effect is applied")
	assert_eq(_commands.size(), 1, "automatic command is requested")
	assert_eq(graph.get_node(&"command")["command"]["payload"]["shake"], 1, "command signal mutation cannot alter graph data")
	service.advance()
	assert_eq(session.current_mode, GameModeResource.Value.CUTSCENE, "automatic chain end restores cutscene")
	service.free()
	session.free()

	_reset_captures()
	session = _session_in_mode(GameModeResource.Value.PAUSED)
	var guard_nodes := {}
	for index: int in 257:
		guard_nodes["jump_%d" % index] = {"type":"jump", "next":"line" if index == 256 else "jump_%d" % (index + 1)}
	guard_nodes["line"] = {"type":"line", "speaker":"retti", "expression":"neutral", "text":"too far", "next":"end"}
	guard_nodes["end"] = {"type":"end"}
	service = _service_for_graph(service_script, _graph("guard", "jump_0", guard_nodes), session)
	assert_eq(service.start_dialogue(&"guard"), ERR_CYCLIC_LINK, "257 automatic nodes trip the dispatch guard")
	assert_eq(session.current_mode, GameModeResource.Value.PAUSED, "guard failure restores prior mode")
	assert_eq(_failures[-1].get("reason"), &"dispatch_guard", "guard failure has stable context")
	service.free()
	session.free()

	_reset_captures()
	session = _session_in_mode(GameModeResource.Value.PAUSED)
	guard_nodes = {}
	for index: int in 256:
		guard_nodes["jump_%d" % index] = {"type":"jump", "next":"line" if index == 255 else "jump_%d" % (index + 1)}
	guard_nodes["line"] = {"type":"line", "speaker":"retti", "expression":"neutral", "text":"boundary", "next":"end"}
	guard_nodes["end"] = {"type":"end"}
	service = _service_for_graph(service_script, _graph("guard_boundary", "jump_0", guard_nodes), session)
	assert_eq(service.start_dialogue(&"guard_boundary"), OK, "256 automatic nodes reach a stable boundary")
	assert_eq(service.current_node_id, &"line", "guard permits the 256-step boundary")
	service.abort_dialogue(&"test_cleanup")
	service.free()
	session.free()

func _test_choice_filtering_index_stability_and_checkpoint(service_script: Variant) -> void:
	_reset_captures()
	var items := [
		{"text":"hidden", "conditions":[{"kind":"flag", "key":"show_hidden", "operator":"eq", "value":true}], "effects":[{"kind":"flag_set", "key":"hidden_chosen", "value":true}], "next":"after"},
		{"text":"first visible", "conditions":[], "effects":[{"kind":"flag_set", "key":"first_chosen", "value":true}], "next":"after"},
		{"text":"second visible", "conditions":[], "effects":[{"kind":"flag_set", "key":"second_chosen", "value":true}], "next":"after"},
	]
	var nodes := {
		"choice":{"type":"choice", "items":items},
		"after":{"type":"line", "speaker":"jellyppo", "expression":"uneasy", "text":"after", "next":"end"},
		"end":{"type":"end"},
	}
	var session := _session_in_mode(GameModeResource.Value.EXPLORATION)
	var service: Variant = _service_for_graph(service_script, _graph("choices", "choice", nodes), session)
	assert_eq(service.start_dialogue(&"choices"), OK, "choice-first dialogue starts")
	assert_eq(_choices[-1].map(func(item: Dictionary) -> String: return item["text"]), ["first visible", "second visible"], "filtered choices preserve visible order")
	var before_invalid: Dictionary = session.narrative_state.snapshot()
	var checkpoint_before: Dictionary = service.get_checkpoint()
	assert_eq(service.choose(-1), ERR_INVALID_PARAMETER, "negative filtered choice index is rejected")
	assert_eq(service.choose(2), ERR_INVALID_PARAMETER, "past-end filtered choice index is rejected")
	assert_eq(session.narrative_state.snapshot(), before_invalid, "invalid choice cannot mutate narrative state")
	assert_eq(service.get_checkpoint(), checkpoint_before, "invalid choice cannot move the cursor")
	service.advance()
	assert_eq(service.get_checkpoint(), checkpoint_before, "advance cannot cross a choice boundary")
	assert_eq(service.choose(0), OK, "first filtered choice is accepted")
	assert_true(session.narrative_state.get_flag(&"first_chosen"), "filtered index maps to its original item")
	assert_false(session.narrative_state.get_flag(&"hidden_chosen"), "filtered index never selects hidden item")
	assert_false(session.narrative_state.get_flag(&"second_chosen"), "filtered index remains stable")
	var checkpoint: Dictionary = service.get_checkpoint()
	assert_eq(checkpoint, {"scene_key":"choices", "next_node_id":"after"}, "checkpoint identifies active scene and stable node")
	checkpoint["next_node_id"] = "mutated"
	assert_eq(service.get_checkpoint()["next_node_id"], "after", "checkpoint callers cannot mutate service state")
	service.abort_dialogue(&"test_cleanup")
	service.free()
	session.free()

func _test_runtime_failure_rolls_back_choice_effects(service_script: Variant) -> void:
	_reset_captures()
	var nodes := {
		"choice":{"type":"choice", "items":[{
			"text":"broken", "conditions":[],
			"effects":[
				{"kind":"flag_set", "key":"must_rollback", "value":true},
				{"kind":"unsupported", "key":"bad", "value":true},
			],
			"next":"end",
		}]},
		"end":{"type":"end"},
	}
	var session := _session_in_mode(GameModeResource.Value.MENU)
	var service: Variant = _service_for_graph(service_script, _graph("broken_effect", "choice", nodes), session)
	assert_eq(service.start_dialogue(&"broken_effect"), OK, "handcrafted runtime graph reaches choice")
	assert_eq(service.choose(0), ERR_INVALID_DATA, "invalid runtime effect fails the choice")
	assert_false(session.narrative_state.get_flag(&"must_rollback"), "failed choice rolls back earlier effects")
	assert_eq(session.current_mode, GameModeResource.Value.MENU, "effect failure restores exact prior mode")
	assert_eq(service.current_graph, null, "runtime failure clears the graph")
	service.free()
	session.free()

func _test_zero_visible_choices_fail_safely(service_script: Variant) -> void:
	_reset_captures()
	var nodes := {
		"choice":{"type":"choice", "items":[{
			"text":"hidden", "conditions":[{"kind":"flag", "key":"show_choice", "operator":"eq", "value":true}],
			"effects":[{"kind":"flag_set", "key":"hidden_effect", "value":true}], "next":"end",
		}]},
		"end":{"type":"end"},
	}
	var session := _session_in_mode(GameModeResource.Value.CUTSCENE)
	session.narrative_state.set_flag(&"preserved", true)
	var before: Dictionary = session.narrative_state.snapshot()
	var service: Variant = _service_for_graph(service_script, _graph("no_visible_choices", "choice", nodes), session)
	assert_eq(service.start_dialogue(&"no_visible_choices"), ERR_UNAVAILABLE, "choice boundary without visible items fails")
	assert_eq(session.current_mode, GameModeResource.Value.CUTSCENE, "empty filtered choice restores exact prior mode")
	assert_eq(session.narrative_state.snapshot(), before, "empty filtered choice cannot mutate narrative state")
	assert_eq(_choices.size(), 0, "empty filtered choice is not published to the view")
	assert_eq(_failures.size(), 1, "empty filtered choice emits one failure")
	if not _failures.is_empty():
		assert_eq(_failures[-1].get("reason"), &"no_visible_choices", "empty filtered choice has stable failure context")
	assert_eq(_finished_count, 0, "empty filtered choice is not reported as finished")
	assert_eq(service.get_checkpoint(), {}, "empty filtered choice clears active dialogue")
	service.free()
	session.free()

func _test_downstream_choice_failure_rolls_back_before_publication(service_script: Variant) -> void:
	_reset_captures()
	var nodes := {
		"choice":{"type":"choice", "items":[{
			"text":"continue", "conditions":[],
			"effects":[{"kind":"flag_set", "key":"choice_transient", "value":true}],
			"next":"automatic_effect",
		}]},
		"automatic_effect":{"type":"effect", "effects":[{"kind":"flag_set", "key":"auto_transient", "value":true}], "next":"broken_jump"},
		"broken_jump":{"type":"jump", "next":"missing"},
	}
	var session := _session_in_mode(GameModeResource.Value.MENU)
	session.narrative_state.set_flag(&"base_preserved", true)
	var loader := GraphLoaderStub.new()
	loader.graph_to_return = _graph("downstream_failure", "choice", nodes)
	var service: Variant = service_script.new()
	service.graph_loader = loader
	service.game_session = session
	service.narrative_state = session.narrative_state
	var observation := {"count":0, "saw_rollback":false, "restart_error":FAILED}
	service.failed.connect(func(context: Dictionary) -> void:
		if context.get("reason") != &"invalid_next":
			return
		observation["count"] += 1
		observation["saw_rollback"] = not session.narrative_state.get_flag(&"choice_transient") \
			and not session.narrative_state.get_flag(&"auto_transient") \
			and session.narrative_state.get_flag(&"base_preserved")
		session.narrative_state.set_flag(&"listener_mutation", true)
		loader.graph_to_return = _line_graph("reentrant")
		observation["restart_error"] = service.start_dialogue(&"reentrant")
	)
	assert_eq(service.start_dialogue(&"downstream_failure"), OK, "downstream failure graph reaches choice")
	assert_eq(service.choose(0), ERR_INVALID_DATA, "downstream automatic failure is returned from choose")
	assert_eq(observation["count"], 1, "downstream failure emits once")
	assert_true(observation["saw_rollback"], "failure listener observes the rolled-back transaction")
	assert_eq(observation["restart_error"], OK, "failure listener may start a replacement dialogue")
	assert_true(session.narrative_state.get_flag(&"listener_mutation"), "post-failure listener mutation is retained")
	assert_true(session.narrative_state.get_flag(&"base_preserved"), "pre-choice state survives rollback")
	assert_false(session.narrative_state.get_flag(&"choice_transient"), "choice effect is rolled back")
	assert_false(session.narrative_state.get_flag(&"auto_transient"), "downstream automatic effect is rolled back")
	assert_eq(service.current_node_id, &"line", "outer choose cleanup cannot erase reentrant dialogue")
	assert_eq(session.current_mode, GameModeResource.Value.DIALOGUE, "reentrant dialogue retains dialogue mode")
	service.abort_dialogue(&"test_cleanup")
	assert_eq(session.current_mode, GameModeResource.Value.MENU, "reentrant dialogue restores its own prior mode")
	service.free()
	session.free()

func _test_character_resources_and_view_scene() -> void:
	var retti: Variant = load("res://data/characters/retti.tres")
	var jellyppo: Variant = load("res://data/characters/jellyppo.tres")
	assert_not_null(retti, "retti character definition loads")
	assert_not_null(jellyppo, "jellyppo character definition loads")
	if retti == null or jellyppo == null:
		return
	assert_eq(retti.character_key, &"retti", "retti resource has a stable key")
	assert_eq(jellyppo.character_key, &"jellyppo", "jellyppo resource has a stable key")
	assert_true(retti.resolve_portrait(&"neutral") is AtlasTexture, "draft neutral portrait is a nondestructive atlas crop")
	assert_eq(retti.resolve_portrait(&"missing"), retti.resolve_portrait(retti.default_expression), "unknown expression falls back to default portrait")
	var view_scene := load(VIEW_SCENE_PATH) as PackedScene
	var view: Variant = view_scene.instantiate()
	add_child(view)
	await get_tree().process_frame
	assert_true(view.anchor_left == 0.0 and view.anchor_right == 1.0 and view.anchor_top == 1.0 and view.anchor_bottom == 1.0, "dialogue view is bottom anchored")
	view.show_line(&"retti", &"uneasy", "A line that must not overlap the portrait.")
	await get_tree().process_frame
	var portrait := view.get_node("Panel/Margin/Layout/Portrait") as TextureRect
	var name_label := view.get_node("Panel/Margin/Layout/Content/NameLabel") as Label
	var text_label := view.get_node("Panel/Margin/Layout/Content/TextLabel") as Label
	assert_eq(name_label.text, retti.display_name, "view resolves speaker display name")
	assert_eq(portrait.texture, retti.resolve_portrait(&"uneasy"), "view resolves the requested expression")
	assert_true(portrait.get_global_rect().end.x <= name_label.get_global_rect().position.x, "portrait does not overlap dialogue text")
	assert_true(view.get_global_rect().position.y >= 200.0 and view.get_global_rect().end.y <= 360.0, "dialogue panel fits a 640 by 360 viewport")
	assert_true(text_label.get_global_rect().end.x <= 640.0, "dialogue text stays inside the viewport")
	view.choice_requested.connect(func(index: int) -> void: _requested_choice_indices.append(index))
	var view_items: Array[Dictionary] = [{"text":"First"}, {"text":"Second"}]
	view.show_choices(view_items)
	await get_tree().process_frame
	var choice_container := view.get_node("Panel/Margin/Layout/Content/ChoiceContainer") as VBoxContainer
	assert_eq(choice_container.get_child_count(), 2, "choices render vertically")
	assert_true(choice_container.get_child(0) is Button and choice_container.get_child(1) is Button, "choices are keyboard focus controls")
	assert_true(choice_container.get_child(0).has_focus(), "keyboard focus begins on the first choice")
	var global_previous: int = GameSession.current_mode
	GameSession.change_mode(GameModeResource.Value.DIALOGUE)
	choice_container.get_child(0).pressed.emit()
	GameSession.change_mode(global_previous)
	assert_eq(_requested_choice_indices, [0], "view emits only the selected visible index")
	view.hide_dialogue()
	var choice_first_items: Array[Dictionary] = [{"text":"Choice-first boundary"}]
	view.show_choices(choice_first_items)
	await get_tree().process_frame
	assert_eq(portrait.texture, null, "choice-first presentation after hide has no stale portrait")
	assert_eq(name_label.text, "", "choice-first presentation after hide has no stale speaker")
	assert_eq(text_label.text, "", "choice-first presentation after hide has no stale line")
	view.queue_free()
	await get_tree().process_frame

	var app_scene := load("res://app/bootstrap/app_root.tscn") as PackedScene
	var app := app_scene.instantiate()
	var service := app.get_node_or_null("ServiceLayer/DialogueService")
	var app_view := app.get_node_or_null("UILayer/DialogueView")
	assert_not_null(service, "AppRoot owns the dialogue service without an autoload")
	assert_not_null(app_view, "AppRoot owns the dialogue view")
	if service != null and app_view != null:
		assert_true(app_view.advance_requested.is_connected(Callable(service, "advance")), "AppRoot connects advance intent to the service")
		assert_true(app_view.choice_requested.is_connected(Callable(service, "choose")), "AppRoot connects choice intent to the service")
	app.free()

func _configured_service(service_script: Variant, loader: DialogueGraphLoader, session: Node) -> Variant:
	var service: Variant = service_script.new()
	service.graph_loader = loader
	service.game_session = session
	service.narrative_state = session.narrative_state
	service.line_requested.connect(_capture_line)
	service.choices_requested.connect(_capture_choices)
	service.command_requested.connect(_capture_command_and_mutate)
	service.failed.connect(_capture_failure)
	service.finished.connect(func() -> void: _finished_count += 1)
	return service

func _service_for_graph(service_script: Variant, graph: DialogueGraph, session: Node) -> Variant:
	var loader := GraphLoaderStub.new()
	loader.graph_to_return = graph
	return _configured_service(service_script, loader, session)

func _session_in_mode(mode: int) -> Node:
	var session := GameSessionResource.new()
	session.initialize()
	if session.current_mode != mode:
		assert_true(session.change_mode(mode), "test session enters requested prior mode")
	return session

func _graph(scene_key: String, entry: String, nodes: Dictionary) -> DialogueGraph:
	return DialogueGraph.from_dictionary({"scene_key":scene_key, "entry_node":entry, "nodes":nodes})

func _line_graph(scene_key: String) -> DialogueGraph:
	return _graph(scene_key, "line", {
		"line":{"type":"line", "speaker":"retti", "expression":"neutral", "text":"line", "next":"end"},
		"end":{"type":"end"},
	})

func _capture_line(character_key: StringName, expression: StringName, text: String) -> void:
	_lines.append({"character_key":character_key, "expression":expression, "text":text})

func _capture_choices(items: Array[Dictionary]) -> void:
	_choices.append(items.duplicate(true))
	if not items.is_empty():
		items[0]["text"] = "listener mutation"

func _capture_command_and_mutate(command: Dictionary) -> void:
	_commands.append(command.duplicate(true))
	if command.has("payload") and typeof(command["payload"]) == TYPE_DICTIONARY:
		command["payload"]["shake"] = 999

func _capture_failure(context: Dictionary) -> void:
	_failures.append(context.duplicate(true))
	context["reason"] = &"listener_mutation"

func _reset_captures() -> void:
	_lines.clear()
	_choices.clear()
	_commands.clear()
	_failures.clear()
	_finished_count = 0
	_requested_choice_indices.clear()
