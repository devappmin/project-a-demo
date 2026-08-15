# Godot Gameplay Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a bootable Godot 4.7 top-down sample room with mode-gated keyboard input, pixel-correct movement, deterministic directional interaction, and a project-local headless test runner.

**Architecture:** A persistent `AppRoot` hosts the current world and UI. `GameSession` is the only autoload introduced in this plan; player movement and interaction depend on its public mode gate instead of dialogue/plugin state or a global event bus. Each component exposes deterministic pure methods so its rules can be tested without running a full level.

**Tech Stack:** Godot 4.7, GDScript 2.0, PowerShell 7 wrapper, Godot headless execution, built-in JSON and assertion helpers only.

## Global Constraints

- Modify only `D:/Project/project-a-demo`; never modify deprecated `D:/Project/project-a`.
- Target Windows PC and keyboard input first; preserve InputMap-based gamepad extensibility.
- Use a 640×360 logical canvas, 16:9 aspect, nearest filtering, integer scaling, and 16×16 base tiles.
- Keep the current 48×48 character frames and use a Camera2D zoom starting value of 2×.
- Do not install Dialogic, Phantom Camera, a global EventBus, or an external test framework.
- Use tabs for GDScript indentation and LF line endings.
- Follow TDD for every behavior and commit only after the task's focused and full tests pass.

---

## File Map

- `tools/run_godot.ps1`: resolves `PROJECT_A_GODOT_BIN`, `godot`, or `godot4` and forwards exact CLI arguments.
- `tests/support/test_case.gd`: assertion collection and failure formatting.
- `tests/run_all.gd`: discovers `test_*.gd`, supports `--filter`, and exits nonzero on failure.
- `app/bootstrap/app_root.gd`: owns stable `WorldHost`, `ServiceLayer`, and `UILayer` nodes.
- `app/bootstrap/app_root.tscn`: project main scene.
- `app/session/game_mode.gd`: shared mode enum and allowed action constants.
- `app/session/game_session.gd`: mode transitions and input permission gate.
- `game/actors/player/player_input.gd`: converts InputMap state into movement/sprint/interact requests.
- `game/actors/player/player_controller.gd`: velocity, facing, physics movement, and animation selection.
- `game/actors/player/player.tscn`: player collision, sprite, detector, and camera composition.
- `game/interaction/interaction_target.gd`: reusable target contract and exported prompt/action data.
- `game/interaction/interaction_detector.gd`: directional target ranking.
- `game/interaction/interaction_router.gd`: emits one typed action request for the selected target.
- `ui/hud/interaction_prompt.gd` and `.tscn`: displays the current target prompt.
- `game/world/map_scene.gd`: validates a map ID and entry-point contract.
- `content/maps/foundation_room.tscn`: sample map using existing tiles and assets.
- `content/interactables/sample_inspectable.tscn`: first inspect target.

### Task 1: Baseline, Bootstrap, and Headless Test Runner

**Files:**
- Create: `tools/run_godot.ps1`
- Create: `tests/support/test_case.gd`
- Create: `tests/run_all.gd`
- Create: `tests/unit/app/test_bootstrap.gd`
- Create: `app/bootstrap/app_root.gd`
- Create: `app/bootstrap/app_root.tscn`
- Modify: `project.godot`
- Track: `.editorconfig`, `.gitattributes`, `assets/**`, `icon.svg`, `icon.svg.import`

**Interfaces:**
- Produces: `AppRoot.get_world_host() -> Node`, `AppRoot.get_service_layer() -> Node`, `AppRoot.get_ui_layer() -> CanvasLayer`.
- Produces: `pwsh -File tools/run_godot.ps1 <godot arguments>` as the only documented local Godot command.

- [ ] **Step 1: Write the failing bootstrap test**

```gdscript
extends "res://tests/support/test_case.gd"

func run() -> void:
	var scene := load("res://app/bootstrap/app_root.tscn") as PackedScene
	assert_not_null(scene, "AppRoot scene must exist")
	if scene == null:
		return
	var root := scene.instantiate()
	assert_not_null(root.get_node_or_null("WorldHost"), "WorldHost must exist")
	assert_not_null(root.get_node_or_null("ServiceLayer"), "ServiceLayer must exist")
	assert_not_null(root.get_node_or_null("UILayer"), "UILayer must exist")
	root.free()
```

- [ ] **Step 2: Add the runner wrapper and verify the test fails**

```powershell
$GodotArgs = $args
$ErrorActionPreference = "Stop"
$projectAGodotExe = $env:PROJECT_A_GODOT_BIN
if ([string]::IsNullOrWhiteSpace($projectAGodotExe)) {
	$found = Get-Command godot, godot4 -ErrorAction SilentlyContinue | Select-Object -First 1
	if ($null -ne $found) { $projectAGodotExe = $found.Source }
}
if ([string]::IsNullOrWhiteSpace($projectAGodotExe) -or -not (Test-Path -LiteralPath $projectAGodotExe)) {
	throw "Set PROJECT_A_GODOT_BIN to the absolute Godot 4.7 executable path."
}
& $projectAGodotExe @GodotArgs
exit $LASTEXITCODE
```

Create `tests/support/test_case.gd` with the exact shared assertions:

```gdscript
extends Node
class_name TestCase

var failures: Array[String] = []

func run() -> void:
	pass

func assert_true(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func assert_false(value: bool, message: String) -> void:
	assert_true(not value, message)

func assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [message, str(expected), str(actual)])

func assert_almost_eq(actual: float, expected: float, tolerance: float, message: String) -> void:
	if abs(actual - expected) > tolerance:
		failures.append("%s: expected %s ± %s, got %s" % [message, expected, tolerance, actual])

func assert_not_null(value: Variant, message: String) -> void:
	assert_true(value != null, message)
```

Create `tests/run_all.gd` as a recursive runner. User arguments follow Godot's `--` separator.

```gdscript
extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _collect_tests(path: String) -> PackedStringArray:
	var result := PackedStringArray()
	var directory := DirAccess.open(path)
	if directory == null:
		return result
	for child in directory.get_directories():
		result.append_array(_collect_tests(path.path_join(child)))
	for file_name in directory.get_files():
		if file_name.begins_with("test_") and file_name.ends_with(".gd"):
			result.append(path.path_join(file_name))
	return result

func _filter_value() -> String:
	var args := OS.get_cmdline_user_args()
	var index := args.find("--filter")
	return args[index + 1] if index >= 0 and index + 1 < args.size() else ""

func _run() -> void:
	var failures: Array[String] = []
	var selected_filter := _filter_value()
	for path in _collect_tests("res://tests"):
		if not selected_filter.is_empty() and not path.contains(selected_filter):
			continue
		var suite := (load(path) as Script).new() as TestCase
		root.add_child(suite)
		await suite.run()
		for failure in suite.failures:
			failures.append(path + ": " + failure)
		suite.queue_free()
	for failure in failures:
		printerr(failure)
	quit(1 if not failures.is_empty() else 0)
```

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter bootstrap`

Expected: nonzero exit with `AppRoot scene must exist`.

- [ ] **Step 3: Implement the minimal AppRoot**

```gdscript
extends Node
class_name AppRoot

@onready var world_host: Node = $WorldHost
@onready var service_layer: Node = $ServiceLayer
@onready var ui_layer: CanvasLayer = $UILayer

func get_world_host() -> Node:
	return world_host

func get_service_layer() -> Node:
	return service_layer

func get_ui_layer() -> CanvasLayer:
	return ui_layer
```

Create `app_root.tscn` with root `AppRoot`, children `WorldHost:Node2D`, `ServiceLayer:Node`, and `UILayer:CanvasLayer`. Set it as `run/main_scene`. Set viewport width/height to `640/360`, stretch mode to `canvas_items`, aspect to `keep`, integer scale mode, and default texture filter to nearest in `project.godot`.

- [ ] **Step 4: Run focused and smoke tests**

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter bootstrap`

Expected: PASS and exit code 0.

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --quit-after 3`

Expected: project boots without parser, missing-resource, or main-scene errors.

- [ ] **Step 5: Commit the tracked baseline and bootstrap**

```bash
git add .editorconfig .gitattributes assets icon.svg icon.svg.import project.godot tools tests app
git commit -m "chore: bootstrap Godot gameplay foundation"
```

### Task 2: GameSession Mode Gate

**Files:**
- Create: `app/session/game_mode.gd`
- Create: `app/session/game_session.gd`
- Create: `tests/unit/app/test_game_session.gd`
- Modify: `project.godot`

**Interfaces:**
- Produces: `GameSessionService.initialize() -> void` and singleton `GameSession.change_mode(next_mode: int) -> bool`.
- Produces: `GameSession.can(action: StringName) -> bool`.
- Produces signals: `mode_changed(previous: int, current: int)` and `mode_change_rejected(previous: int, requested: int)`.

- [ ] **Step 1: Write the failing permission test**

```gdscript
extends "res://tests/support/test_case.gd"

func run() -> void:
	var session := GameSessionService.new()
	session.initialize()
	assert_true(session.can(GameMode.ACTION_MOVE), "exploration permits movement")
	assert_true(session.change_mode(GameMode.Value.DIALOGUE), "dialogue transition is valid")
	assert_false(session.can(GameMode.ACTION_MOVE), "dialogue blocks movement")
	assert_true(session.can(GameMode.ACTION_DIALOGUE_ADVANCE), "dialogue permits advance")
	assert_false(session.change_mode(GameMode.Value.BOOT), "runtime cannot return to boot")
```

- [ ] **Step 2: Run the focused test and verify failure**

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter game_session`

Expected: FAIL because `GameMode` and `GameSession` do not exist.

- [ ] **Step 3: Implement explicit modes and permissions**

```gdscript
extends RefCounted
class_name GameMode

enum Value { BOOT, EXPLORATION, DIALOGUE, CUTSCENE, MENU, TRANSITION, PAUSED }
const ACTION_MOVE := &"move"
const ACTION_SPRINT := &"sprint"
const ACTION_INTERACT := &"interact"
const ACTION_DIALOGUE_ADVANCE := &"dialogue_advance"
const ACTION_DIALOGUE_CHOOSE := &"dialogue_choose"
const ACTION_MENU := &"menu"
```

Implement `class_name GameSessionService`. It starts in `BOOT`; `initialize()` changes it once to `EXPLORATION`, and `_ready()` calls `initialize()` for the autoload instance. Store an explicit permission map keyed by integer enum values; reject `BOOT` after initialization and reject re-entrant `TRANSITION`. Add the script as autoload `GameSession="*res://app/session/game_session.gd"` so the singleton name does not collide with the class name.

- [ ] **Step 4: Run focused and full tests**

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter game_session`

Expected: PASS.

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd`

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add app/session tests/unit/app project.godot
git commit -m "feat: add game mode input gate"
```

### Task 3: Player Movement, Facing, and Animation

**Files:**
- Create: `game/actors/player/player_input.gd`
- Create: `game/actors/player/player_controller.gd`
- Create: `game/actors/player/player.tscn`
- Create: `tests/unit/player/test_player_controller.gd`
- Modify: `project.godot`

**Interfaces:**
- Consumes: `GameSession.can(action: StringName) -> bool`.
- Produces: `PlayerController.calculate_velocity(direction: Vector2, sprinting: bool) -> Vector2`.
- Produces: `PlayerController.facing: Vector2` constrained to four cardinal directions.

- [ ] **Step 1: Write failing movement tests**

```gdscript
extends "res://tests/support/test_case.gd"

func run() -> void:
	var player := PlayerController.new()
	player.walk_speed = 48.0
	player.sprint_speed = 72.0
	assert_eq(player.calculate_velocity(Vector2.RIGHT, false), Vector2(48.0, 0.0), "walk speed")
	assert_almost_eq(player.calculate_velocity(Vector2(1, 1), true).length(), 72.0, 0.001, "diagonal sprint is normalized")
	player.update_facing(Vector2(-0.2, 1.0))
	assert_eq(player.facing, Vector2.DOWN, "dominant axis controls facing")
```

- [ ] **Step 2: Run and verify failure**

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter player_controller`

Expected: FAIL because `PlayerController` does not exist.

- [ ] **Step 3: Implement movement and compose the player scene**

```gdscript
extends CharacterBody2D
class_name PlayerController

@export var walk_speed := 48.0
@export var sprint_speed := 72.0
var facing := Vector2.DOWN

func calculate_velocity(direction: Vector2, sprinting: bool) -> Vector2:
	var speed := sprint_speed if sprinting else walk_speed
	return direction.normalized() * speed if direction != Vector2.ZERO else Vector2.ZERO

func update_facing(direction: Vector2) -> void:
	if direction == Vector2.ZERO:
		return
	facing = Vector2(sign(direction.x), 0.0) if abs(direction.x) > abs(direction.y) else Vector2(0.0, sign(direction.y))
```

`PlayerInput` reads `move_left/right/up/down`, `sprint`, and `interact` only when the matching `GameSession.can()` permission is true. `PlayerController._physics_process()` sets velocity, calls `move_and_slide()` every physics tick, updates facing, and selects `idle_*` or `walk_*` animation names. Build `player.tscn` with `AnimatedSprite2D`, feet-centered `CollisionShape2D`, `InteractionDetector`, and `Camera2D` zoom `Vector2(2, 2)`.

- [ ] **Step 4: Run automated tests and manual physics smoke check**

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd`

Expected: all tests PASS.

Run: `pwsh -File tools/run_godot.ps1 --path . --editor`

Expected: player scene has no missing animation or collision resources; diagonal velocity is not faster than cardinal velocity.

- [ ] **Step 5: Commit**

```bash
git add game/actors/player tests/unit/player project.godot
git commit -m "feat: add mode-gated top-down player"
```

### Task 4: Directional Interaction and Foundation Room

**Files:**
- Create: `game/interaction/interaction_target.gd`
- Create: `game/interaction/interaction_detector.gd`
- Create: `game/interaction/interaction_router.gd`
- Create: `tests/unit/interaction/test_interaction_detector.gd`
- Create: `ui/hud/interaction_prompt.gd`
- Create: `ui/hud/interaction_prompt.tscn`
- Create: `game/world/map_scene.gd`
- Create: `content/interactables/sample_inspectable.tscn`
- Create: `content/maps/foundation_room.tscn`
- Modify: `app/bootstrap/app_root.tscn`

**Interfaces:**
- Consumes: `PlayerController.facing` and `GameSession.can(GameMode.ACTION_INTERACT)`.
- Produces: `InteractionTarget.get_interaction() -> Dictionary` with keys `kind:StringName`, `prompt:String`, and `payload:Dictionary`.
- Produces: `InteractionDetector.choose_target(candidates: Array[InteractionTarget], origin: Vector2, facing: Vector2) -> InteractionTarget`.
- Produces: `InteractionRouter.execute_target(target: InteractionTarget) -> Error`.
- Produces signal: `InteractionRouter.action_requested(kind: StringName, payload: Dictionary)`.

- [ ] **Step 1: Write failing ranking tests**

```gdscript
extends "res://tests/support/test_case.gd"

func run() -> void:
	var detector := InteractionDetector.new()
	var front := InteractionTarget.new()
	front.position = Vector2(16, 0)
	front.priority = 0
	var behind := InteractionTarget.new()
	behind.position = Vector2(-4, 0)
	behind.priority = 10
	var chosen := detector.choose_target([behind, front], Vector2.ZERO, Vector2.RIGHT)
	assert_eq(chosen, front, "targets behind the facing direction are excluded")
	front.free()
	behind.free()
	detector.free()
```

- [ ] **Step 2: Run and verify failure**

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter interaction_detector`

Expected: FAIL because interaction classes do not exist.

- [ ] **Step 3: Implement deterministic target selection**

```gdscript
extends Area2D
class_name InteractionTarget

@export var priority := 0
@export var prompt := "조사하기"
@export var action_kind: StringName = &"inspect"
@export var payload: Dictionary = {}

func get_interaction() -> Dictionary:
	return {"kind": action_kind, "prompt": prompt, "payload": payload.duplicate(true)}
```

`choose_target()` must reject candidates whose normalized direction has `dot(facing) <= 0.35`, then sort by priority descending, dot descending, distance ascending, and instance ID ascending. `InteractionRouter` executes only the detector's current target and emits one `action_requested` signal. The prompt subscribes to `target_changed` and shows the target's prompt.

Create `foundation_room.tscn` with `MapScene(map_id=&"foundation_room")`, tile/prop layers, `EntryPoints/start`, one player, and one `sample_inspectable` whose payload is `{"text": "낯선 거울이다."}`. Instance the map under `AppRoot/WorldHost`.

- [ ] **Step 4: Verify tests and the playable room**

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd`

Expected: all tests PASS.

Run: `pwsh -File tools/run_godot.ps1 --path .`

Expected: WASD/arrow movement, Shift sprint, collision, four-direction facing, E interaction, and prompt behavior work; targets behind the player do not trigger.

- [ ] **Step 5: Commit**

```bash
git add game/interaction game/world ui/hud content app/bootstrap tests/unit/interaction
git commit -m "feat: add directional interaction room"
```

## Plan 1 Completion Gate

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd`

Expected: all tests PASS.

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --quit-after 3`

Expected: clean boot and exit code 0.

Manual acceptance: the foundation room supports movement, sprint, collision, facing, deterministic interaction, and a prompt with no Dialogic or global EventBus dependency.
