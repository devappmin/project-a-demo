extends "res://tests/support/test_case.gd"

const GameMode = preload("res://app/session/game_mode.gd")

func run() -> void:
	_test_directional_ranking()
	_test_target_payload_is_immutable()
	_test_router_honors_current_target_and_session_permission()
	_test_foundation_room_contract()
	await _test_scene_detector_query()
	await _test_edge_triggered_input_and_prompt_updates()

func _test_directional_ranking() -> void:
	var detector := InteractionDetector.new()
	var front := InteractionTarget.new()
	front.position = Vector2(16, 0)
	front.priority = 0
	var behind := InteractionTarget.new()
	behind.position = Vector2(-4, 0)
	behind.priority = 10
	var candidates: Array[InteractionTarget] = [behind, front]
	assert_eq(detector.choose_target(candidates, Vector2.ZERO, Vector2.RIGHT), front, "targets behind the facing direction are excluded")

	var high_priority := InteractionTarget.new()
	high_priority.position = Vector2(16, 12)
	high_priority.priority = 2
	candidates = [front, high_priority]
	assert_eq(detector.choose_target(candidates, Vector2.ZERO, Vector2.RIGHT), high_priority, "priority ranks before alignment and distance")

	var well_aligned := InteractionTarget.new()
	well_aligned.position = Vector2(24, 4)
	well_aligned.priority = 2
	candidates = [high_priority, well_aligned]
	assert_eq(detector.choose_target(candidates, Vector2.ZERO, Vector2.RIGHT), well_aligned, "alignment breaks equal-priority ties")

	var near := InteractionTarget.new()
	near.position = Vector2(8, 0)
	var far := InteractionTarget.new()
	far.position = Vector2(24, 0)
	candidates = [far, near]
	assert_eq(detector.choose_target(candidates, Vector2.ZERO, Vector2.RIGHT), near, "distance breaks equal-priority equal-alignment ties")

	var first_created := InteractionTarget.new()
	first_created.position = Vector2(12, 0)
	var second_created := InteractionTarget.new()
	second_created.position = Vector2(12, 0)
	candidates = [second_created, first_created]
	assert_eq(detector.choose_target(candidates, Vector2.ZERO, Vector2.RIGHT), first_created, "instance ID is the final deterministic tie-breaker")

	var strictly_aligned := InteractionTarget.new()
	strictly_aligned.position = Vector2(16, 0)
	var almost_aligned := InteractionTarget.new()
	almost_aligned.position = Vector2(8, 0.008)
	candidates = [almost_aligned, strictly_aligned]
	assert_eq(detector.choose_target(candidates, Vector2.ZERO, Vector2.RIGHT), strictly_aligned, "any distinct dot value ranks strictly before distance")

	for target in [front, behind, high_priority, well_aligned, near, far, first_created, second_created, strictly_aligned, almost_aligned]:
		target.free()
	detector.free()

func _test_target_payload_is_immutable() -> void:
	var target := InteractionTarget.new()
	target.action_kind = &"inspect"
	target.prompt = "조사하기"
	target.payload = {"nested": {"text": "낯선 거울이다."}}
	var interaction := target.get_interaction()
	assert_eq(interaction.kind, &"inspect", "interaction exposes its action kind")
	assert_eq(interaction.prompt, "조사하기", "interaction exposes its prompt")
	interaction.payload.nested.text = "changed"
	assert_eq(target.payload.nested.text, "낯선 거울이다.", "interaction payload is returned as a deep copy")
	target.free()

func _test_router_honors_current_target_and_session_permission() -> void:
	var detector := InteractionDetector.new()
	var router := InteractionRouter.new()
	var current := InteractionTarget.new()
	current.action_kind = &"inspect"
	current.payload = {"text": "낯선 거울이다."}
	var other := InteractionTarget.new()
	detector.current_target = current
	router.detector = detector
	var requested: Array[Dictionary] = []
	router.action_requested.connect(func(kind: StringName, payload: Dictionary) -> void:
		requested.append({"kind": kind, "payload": payload})
	)

	GameSession.change_mode(GameMode.Value.EXPLORATION)
	assert_eq(router.execute_target(other), ERR_INVALID_PARAMETER, "router rejects a target other than the detector's current target")
	assert_eq(requested.size(), 0, "rejected targets emit no action")
	assert_eq(router.execute_target(current), OK, "router executes the detector's current target")
	assert_eq(requested.size(), 1, "one execution emits one action")
	assert_eq(requested[0].kind, &"inspect", "router emits the target action kind")
	requested[0].payload.text = "changed"
	assert_eq(current.payload.text, "낯선 거울이다.", "router emits an immutable payload copy")

	GameSession.change_mode(GameMode.Value.DIALOGUE)
	assert_eq(router.execute_target(current), ERR_UNAUTHORIZED, "router honors the session interaction permission")
	assert_eq(requested.size(), 1, "unauthorized execution emits no action")
	GameSession.change_mode(GameMode.Value.EXPLORATION)

	current.free()
	other.free()
	router.free()
	detector.free()

func _test_foundation_room_contract() -> void:
	var room_scene := load("res://content/maps/foundation_room.tscn") as PackedScene
	assert_not_null(room_scene, "foundation room scene exists")
	if room_scene == null:
		return
	var room := room_scene.instantiate()
	assert_eq(room.map_id, &"foundation_room", "foundation room has a stable map ID")
	assert_not_null(room.get_node_or_null("EntryPoints/start"), "foundation room exposes the start entry point")
	assert_not_null(room.get_node_or_null("TileLayer"), "foundation room has a visible tile layer")
	assert_not_null(room.get_node_or_null("PropLayer"), "foundation room has a prop layer")
	assert_not_null(room.get_node_or_null("Boundaries"), "foundation room has collision boundaries")
	var player := room.get_node_or_null("Player")
	assert_not_null(player, "foundation room contains the player")
	if player != null:
		assert_not_null(player.get_node_or_null("InteractionDetector/CollisionShape2D"), "player detector has a query shape")
		assert_not_null(player.get_node_or_null("InteractionRouter"), "player has an interaction router")
	var mirror := room.get_node_or_null("PropLayer/SampleInspectable") as InteractionTarget
	assert_not_null(mirror, "foundation room contains the sample inspectable")
	if mirror != null:
		assert_eq(mirror.get_interaction().payload, {"text": "낯선 거울이다."}, "sample inspectable exposes the required payload")
	room.free()

	var app_scene := load("res://app/bootstrap/app_root.tscn") as PackedScene
	var app_root := app_scene.instantiate()
	assert_not_null(app_root.get_node_or_null("WorldHost/FoundationRoom"), "AppRoot instances the foundation room under WorldHost")
	assert_not_null(app_root.get_node_or_null("UILayer/InteractionPrompt"), "AppRoot keeps the interaction prompt under the UI layer")
	app_root.free()

func _test_scene_detector_query() -> void:
	var app_scene := load("res://app/bootstrap/app_root.tscn") as PackedScene
	var app_root := app_scene.instantiate()
	add_child(app_root)
	var room := app_root.get_node("WorldHost/FoundationRoom") as MapScene
	var player := room.get_node("Player") as PlayerController
	var detector := player.get_node("InteractionDetector") as InteractionDetector
	var camera := player.get_node("Camera2D") as Camera2D
	var mirror := room.get_node("PropLayer/SampleInspectable") as InteractionTarget
	var prompt := app_root.get_node("UILayer/InteractionPrompt") as InteractionPrompt
	assert_eq(camera.limit_left, 0, "foundation room clamps the camera to its left edge")
	assert_eq(camera.limit_top, 0, "foundation room clamps the camera to its top edge")
	assert_eq(camera.limit_right, 320, "foundation room clamps the camera to its right edge")
	assert_eq(camera.limit_bottom, 192, "foundation room includes twelve 16-pixel rows and clamps the camera to its bottom edge")
	player.position = mirror.position - Vector2(32, 0)
	player.facing = Vector2.RIGHT
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(detector.current_target, mirror, "the player detector discovers a target inside its query shape and facing cone")
	assert_true(prompt.visible, "the AppRoot prompt wiring reflects the detector's current target")
	assert_eq(prompt.get_node("PanelContainer/PromptLabel").text, mirror.prompt, "the wired AppRoot prompt displays the detected target's prompt")

	player.position = mirror.position + Vector2(32, 0)
	player.facing = Vector2.RIGHT
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_eq(detector.current_target, null, "the live detector drops a target after it moves behind the player's facing")
	assert_false(prompt.visible, "the wired AppRoot prompt hides after the target moves behind the player")
	app_root.queue_free()
	await get_tree().process_frame

func _test_edge_triggered_input_and_prompt_updates() -> void:
	var host := Node.new()
	var detector := InteractionDetector.new()
	detector.name = "Detector"
	host.add_child(detector)
	var router := InteractionRouter.new()
	router.detector = detector
	host.add_child(router)
	var prompt_scene := load("res://ui/hud/interaction_prompt.tscn") as PackedScene
	var prompt := prompt_scene.instantiate() as InteractionPrompt
	prompt.detector_path = ^"../Detector"
	host.add_child(prompt)
	add_child(host)
	await get_tree().process_frame

	var target := InteractionTarget.new()
	target.prompt = "거울 조사하기 [E]"
	detector.current_target = target
	assert_true(prompt.visible, "prompt becomes visible when the detector acquires a target")
	assert_eq(prompt.get_node("PanelContainer/PromptLabel").text, "거울 조사하기 [E]", "prompt shows the current target text")

	var requested: Array[Dictionary] = []
	router.action_requested.connect(func(_kind: StringName, _payload: Dictionary) -> void:
		requested.append({"kind": _kind, "payload": _payload})
	)
	assert_true(router.has_method("_unhandled_input"), "router handles interaction through edge-triggered input events")
	if router.has_method("_unhandled_input"):
		var press := InputEventKey.new()
		press.keycode = KEY_E
		press.pressed = true
		router._unhandled_input(press)
		var echo := InputEventKey.new()
		echo.keycode = KEY_E
		echo.pressed = true
		echo.echo = true
		router._unhandled_input(echo)
	assert_eq(requested.size(), 1, "one E press emits at most one action even when a key echo follows")

	detector.current_target = null
	assert_false(prompt.visible, "prompt hides when the detector loses its target")
	target.free()
	host.queue_free()
	await get_tree().process_frame
