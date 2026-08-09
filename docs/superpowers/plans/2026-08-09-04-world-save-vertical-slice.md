# World, Save, and Vertical Slice Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the vertical slice with safe map transitions, stable world-object state, manual slots, autosave checkpoints, corruption recovery, and one end-to-end room→dialogue→choice→door→load flow.

**Architecture:** `SceneDirector` is the sole owner of `WorldHost` map replacement and spawn placement. `GameSession` owns serializable narrative and world state, while `SaveService` captures pure dictionaries and delegates atomic files to `SaveRepository`; neither service serializes live Nodes or Resources. Dialogue and door events request autosaves only after reaching stable checkpoints.

**Tech Stack:** Godot 4.7, GDScript 2.0, JSON save schema v1, SHA-256 checksums, project-local headless tests, completed Plans 1–3.

## Global Constraints

- Complete Plans 1, 2, and 3 first.
- Keep exactly three autoloads: `GameSession`, `SceneDirector`, and `SaveService`.
- Store saves only under `user://saves`; never write save data into `res://`.
- Save only pure versioned data: meta, player, narrative, progress, world, and dialogue checkpoint.
- Use temporary-write→reread→checksum→backup→replace; never truncate a known-good slot in place.
- Map transition order is input lock, fade out, map replace, spawn, autosave, fade in, exploration.
- Missing map/spawn must keep the previous map and restore the prior safe mode.
- Use tabs for GDScript indentation and follow TDD.

---

## File Map

- `game/world/map_scene.gd`: map ID and stable spawn lookup.
- `game/world/map_definition.gd`: map ID to scene path and default spawn.
- `data/maps/map_registry.tres`: registered map definitions.
- `app/scene_flow/scene_director.gd`: transition state machine and WorldHost ownership.
- `game/interaction/door_action_adapter.gd`: converts validated door payloads into scene-change requests.
- `ui/transitions/screen_fade.gd` and `.tscn`: fade request/finished contract.
- `game/world/world_state.gd`: `map_id/object_id` state dictionaries.
- `game/world/persistent_world_object.gd`: load/apply/capture object state contract.
- `app/save/save_data.gd`: schema v1 validation and migration entrypoint.
- `app/save/save_repository.gd`: atomic files and one backup per slot.
- `app/save/save_service.gd`: capture/restore orchestration and slot metadata.
- `ui/menus/save_menu.gd` and `.tscn`: manual save/load UI.
- `content/maps/foundation_hall.tscn`: second map and return door.
- `tests/support/vertical_slice_harness.gd`: drives public interaction/dialogue/transition APIs in the end-to-end test.
- `tests/integration/test_vertical_slice.gd`: complete accepted flow.

### Task 1: Map Registry and Safe SceneDirector

**Files:**
- Create: `game/world/map_definition.gd`
- Create: `data/maps/foundation_room.tres`
- Create: `data/maps/foundation_hall.tres`
- Create: `data/maps/map_registry.tres`
- Create: `app/scene_flow/scene_director.gd`
- Create: `game/interaction/door_action_adapter.gd`
- Create: `ui/transitions/screen_fade.gd`
- Create: `ui/transitions/screen_fade.tscn`
- Create: `content/maps/foundation_hall.tscn`
- Create: `tests/unit/world/test_map_scene.gd`
- Create: `tests/integration/test_scene_director.gd`
- Modify: `game/world/map_scene.gd`
- Modify: `content/maps/foundation_room.tscn`
- Modify: `app/bootstrap/app_root.tscn`
- Modify: `project.godot`

**Interfaces:**
- Produces: `MapScene.register_spawn(spawn_id: StringName, marker: Marker2D) -> void`.
- Produces: `MapScene.get_spawn(spawn_id: StringName) -> Marker2D`.
- Produces async: `SceneDirector.change_map(map_id: StringName, spawn_id: StringName) -> Error`.
- Produces: `SceneDirector.current_map_id: StringName`, `current_map: MapScene`, and `player: PlayerController`.
- Produces signals: `transition_started(from_map, to_map)`, `map_changed(map_id, spawn_id)`, `transition_failed(context)`, `stable_checkpoint(kind)`.
- Consumes door payload: `{"map_id": StringName, "spawn_id": StringName, "object_id": StringName}`.

- [ ] **Step 1: Write failing map and transition tests**

```gdscript
extends "res://tests/support/test_case.gd"

func run() -> void:
	var map := MapScene.new()
	map.map_id = &"room"
	var marker := Marker2D.new()
	marker.name = "start"
	map.add_child(marker)
	map.register_spawn(&"start", marker)
	assert_eq(map.get_spawn(&"start"), marker, "registered spawn resolves")
	assert_eq(map.get_spawn(&"missing"), null, "missing spawn is explicit")
	map.free()
```

- [ ] **Step 2: Run and verify failure**

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter map_scene`

Expected: FAIL because registry and director do not exist.

- [ ] **Step 3: Implement registry-driven transactional transitions**

```gdscript
extends Resource
class_name MapDefinition

@export var map_id: StringName
@export_file("*.tscn") var scene_path: String
@export var default_spawn: StringName = &"start"
```

`SceneDirector.configure(world_host: Node, fade: ScreenFade)` is called by `AppRoot`. `change_map()` validates the registry, preloads/instantiates the new scene off-tree, verifies `MapScene.map_id` and spawn before freeing the old map, changes mode to `TRANSITION`, fades out, swaps, reparents the persistent player, places it at the marker, emits `map_changed` and `stable_checkpoint(&"map_transition")`, fades in, then returns to `EXPLORATION`. On failure, free only the candidate map, preserve the old map/player, restore the previous safe mode, emit context, and return a non-OK Error.

`DoorActionAdapter` subscribes to `InteractionRouter.action_requested`, accepts only `door`, rejects missing/empty keys, and awaits `SceneDirector.change_map()`. Add `SceneDirector="*res://app/scene_flow/scene_director.gd"` to autoloads. Create `foundation_hall` and bidirectional door targets using payload `{"map_id":"foundation_hall","spawn_id":"from_room","object_id":"to_hall"}` and the inverse payload with `object_id:"to_room"`.

- [ ] **Step 4: Run tests and manual round trip**

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter map_scene`

Expected: PASS.

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter scene_director`

Expected: PASS, including missing-map and missing-spawn preservation tests.

Run: `pwsh -File tools/run_godot.ps1 --path .`

Expected: door fades, loads the hall at `from_room`, returns to room at `from_hall`, and never accepts movement during transition.

- [ ] **Step 5: Commit**

```bash
git add game/world game/interaction/door_action_adapter.gd data/maps app/scene_flow ui/transitions content/maps app/bootstrap project.godot tests/unit/world tests/integration
git commit -m "feat: add safe map transitions"
```

### Task 2: Stable World Object State

**Files:**
- Create: `game/world/world_state.gd`
- Create: `game/world/persistent_world_object.gd`
- Create: `tests/unit/world/test_world_state.gd`
- Create: `tests/integration/test_persistent_world_object.gd`
- Modify: `app/session/game_session.gd`
- Modify: `content/interactables/sample_inspectable.tscn`

**Interfaces:**
- Produces: `WorldState.set_object(map_id, object_id, state: Dictionary) -> void`.
- Produces: `WorldState.get_object(map_id, object_id) -> Dictionary`.
- Produces: `WorldState.snapshot() -> Dictionary` and `restore(data: Dictionary) -> Error`.
- Produces: `PersistentWorldObject.apply_persisted_state(state: Dictionary) -> void` and `capture_persisted_state() -> Dictionary`.
- Modifies: `GameSession.world_state: WorldState`.

- [ ] **Step 1: Write failing stable-key round-trip test**

```gdscript
extends "res://tests/support/test_case.gd"

func run() -> void:
	var state := WorldState.new()
	state.set_object(&"foundation_room", &"mirror", {"inspected":true})
	assert_eq(state.get_object(&"foundation_room", &"mirror"), {"inspected":true}, "object state resolves")
	var restored := WorldState.new()
	assert_eq(restored.restore(state.snapshot()), OK, "world state restores")
	assert_eq(restored.snapshot(), state.snapshot(), "world round trip is exact")
```

- [ ] **Step 2: Run and verify failure**

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter world_state`

Expected: FAIL because `WorldState` does not exist.

- [ ] **Step 3: Implement collision-free stable keys and object lifecycle**

```gdscript
extends RefCounted
class_name WorldState

var maps: Dictionary = {}

func set_object(map_id: StringName, object_id: StringName, state: Dictionary) -> void:
	var map_key := String(map_id)
	if not maps.has(map_key):
		maps[map_key] = {}
	maps[map_key][String(object_id)] = state.duplicate(true)

func get_object(map_id: StringName, object_id: StringName) -> Dictionary:
	return maps.get(String(map_id), {}).get(String(object_id), {}).duplicate(true)

func snapshot() -> Dictionary:
	return maps.duplicate(true)
```

`PersistentWorldObject` exports nonempty `object_id`. On `_ready()`, find parent `MapScene.map_id`, reject duplicate IDs in development builds, and apply stored state. After a successful interaction effect, capture and write state. The sample mirror stores `inspected`; re-entering the room must show an alternate already-inspected line through NarrativeState/interaction payload selection.

- [ ] **Step 4: Run focused and full tests**

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter world_state`

Expected: PASS.

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd`

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add game/world app/session content/interactables tests/unit/world tests/integration
git commit -m "feat: persist stable world object state"
```

### Task 3: Versioned SaveData and Atomic SaveRepository

**Files:**
- Create: `app/save/save_data.gd`
- Create: `app/save/save_repository.gd`
- Create: `app/save/save_service.gd`
- Create: `tests/unit/save/test_save_data.gd`
- Create: `tests/integration/test_save_repository.gd`
- Modify: `project.godot`

**Interfaces:**
- Produces: `SaveData.create_snapshot(slot_id: StringName, context: Dictionary) -> Dictionary`.
- Produces: `SaveData.validate(data: Dictionary) -> Array[String]`.
- Produces: `SaveData.migrate(data: Dictionary) -> Dictionary`.
- Produces: `SaveRepository.write_slot(slot_id: StringName, data: Dictionary) -> Error`, `read_slot(slot_id) -> Dictionary`, and `recover_backup(slot_id) -> Error`.
- Produces: `SaveService.save_slot(slot_id: StringName, dialogue_checkpoint := {}) -> Error`, `slot_exists(slot_id: StringName) -> bool`, and async `load_slot(slot_id) -> Error`.

- [ ] **Step 1: Write failing save schema and corruption tests**

```gdscript
extends "res://tests/support/test_case.gd"

func run() -> void:
	var data := {"schema_version":1,"meta":{},"player":{},"narrative":{},"progress":{},"world":{},"dialogue":{}}
	assert_eq(SaveData.validate(data), [], "schema v1 accepts all sections")
	data.erase("world")
	assert_true(SaveData.validate(data).has("missing section: world"), "missing world is rejected")
```

- [ ] **Step 2: Run and verify failure**

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter save_`

Expected: FAIL because save classes do not exist.

- [ ] **Step 3: Implement schema v1 and exact atomic file sequence**

```gdscript
extends RefCounted
class_name SaveData

const SCHEMA_VERSION := 1
const REQUIRED_SECTIONS := ["meta", "player", "narrative", "progress", "world", "dialogue"]

static func validate(data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if int(data.get("schema_version", -1)) != SCHEMA_VERSION:
		errors.append("unsupported schema_version")
	for section in REQUIRED_SECTIONS:
		if not data.has(section):
			errors.append("missing section: " + section)
	return errors
```

Repository filename rules are `user://saves/<slot>.json`, `<slot>.json.tmp`, and `<slot>.json.bak`; accept slot IDs matching `^(auto|slot_[1-9][0-9]*)$`. Write deterministic JSON containing a `checksum` computed over the same dictionary without the checksum field. Reread and validate temp, rename current to backup, rename temp to current, and retain one backup. If final rename fails, restore backup. Tests inject a repository base directory under `user://test-saves/<unique-id>` and a failure hook at each filesystem stage.

`SaveService` captures `SceneDirector.current_map_id`, player position/facing, `NarrativeState.snapshot()`, progress collections, `WorldState.snapshot()`, and dialogue checkpoint. Loading validates/migrates, changes map first, then restores player, world, narrative, and dialogue state. Add `SaveService="*res://app/save/save_service.gd"` as the third and final autoload.

- [ ] **Step 4: Run focused and full tests**

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter save_`

Expected: PASS, including checksum mismatch, failed replacement, and backup recovery.

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd`

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add app/save project.godot tests/unit/save tests/integration
git commit -m "feat: add atomic versioned save slots"
```

### Task 4: Save Menu, Autosave Hooks, and End-to-End Vertical Slice

**Files:**
- Create: `ui/menus/save_menu.gd`
- Create: `ui/menus/save_menu.tscn`
- Create: `tests/support/vertical_slice_harness.gd`
- Create: `tests/integration/test_vertical_slice.gd`
- Modify: `app/bootstrap/app_root.tscn`
- Modify: `game/narrative/dialogue/dialogue_service.gd`
- Modify: `app/scene_flow/scene_director.gd`
- Modify: `app/session/game_session.gd`
- Modify: `project.godot`

**Interfaces:**
- Consumes: `SceneDirector.stable_checkpoint`, `DialogueService.get_checkpoint()`, and `SaveService.save_slot()`.
- Produces: manual slots `slot_1`, `slot_2`, `slot_3`, `slot_4`, `slot_5` and autosave `auto`.
- Produces signal: `SaveService.save_completed(slot_id)` and `save_failed(slot_id, message)` for UI feedback.

- [ ] **Step 1: Write the failing end-to-end test**

```gdscript
extends "res://tests/support/test_case.gd"

func run() -> void:
	var harness := await VerticalSliceHarness.start()
	assert_eq(await harness.interact_with(&"mirror"), OK, "mirror interaction starts")
	harness.advance_dialogue()
	assert_eq(harness.choose_dialogue_option(0), OK, "dialogue choice succeeds")
	assert_true(GameSession.narrative_state.get_flag(&"mirror_seen"), "choice state applied")
	assert_eq(await harness.use_door(&"to_hall"), OK, "door interaction succeeds")
	assert_eq(SceneDirector.current_map_id, &"foundation_hall", "door changes map")
	assert_true(SaveService.slot_exists(&"auto"), "map checkpoint autosaves")
	GameSession.narrative_state.set_flag(&"mirror_seen", false)
	assert_eq(await SaveService.load_slot(&"auto"), OK, "autosave loads")
	assert_true(GameSession.narrative_state.get_flag(&"mirror_seen"), "choice state restored")
	assert_eq(SceneDirector.current_map_id, &"foundation_hall", "map restored")
	harness.finish()
```

- [ ] **Step 2: Run and verify failure**

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter vertical_slice`

Expected: FAIL because autosave hooks, menu, and harness do not exist.

- [ ] **Step 3: Implement debounced stable-checkpoint autosave and menu**

```gdscript
func _on_stable_checkpoint(kind: StringName) -> void:
	if kind not in [&"map_transition", &"important_choice"]:
		return
	var checkpoint := dialogue_service.get_checkpoint() if kind == &"important_choice" else {}
	SaveService.save_slot(&"auto", checkpoint)
```

Emit `important_choice` only after all choice effects succeed and `current_node_id` has advanced to the next stable node. Coalesce multiple checkpoint requests in one frame. The save menu opens only in `EXPLORATION` or `MENU`, lists five manual slots plus read-only autosave metadata, asks confirmation before overwriting, and never permits a manual save during dialogue, cutscene, or transition. Loading changes mode to `TRANSITION` until restore finishes.

Build `VerticalSliceHarness` with exact helpers used by the test; helpers find stable object IDs and emit the same public inputs as gameplay rather than directly mutating service internals.

```gdscript
extends RefCounted
class_name VerticalSliceHarness

var app: AppRoot
var router: InteractionRouter
var dialogue: DialogueService

static func start() -> VerticalSliceHarness:
	var harness := VerticalSliceHarness.new()
	var tree := Engine.get_main_loop() as SceneTree
	harness.app = load("res://app/bootstrap/app_root.tscn").instantiate() as AppRoot
	tree.root.add_child(harness.app)
	await tree.process_frame
	harness.router = harness.app.get_node("WorldHost/FoundationRoom/Player/InteractionRouter") as InteractionRouter
	harness.dialogue = harness.app.get_node("ServiceLayer/DialogueService") as DialogueService
	return harness

func _find_target(object_id: StringName) -> InteractionTarget:
	for node in app.find_children("*", "InteractionTarget", true, false):
		var target := node as InteractionTarget
		if StringName(target.payload.get("object_id", "")) == object_id:
			return target
	return null

func interact_with(object_id: StringName) -> Error:
	var target := _find_target(object_id)
	if target == null:
		return ERR_DOES_NOT_EXIST
	var error := router.execute_target(target)
	await (Engine.get_main_loop() as SceneTree).process_frame
	return error

func advance_dialogue() -> void:
	dialogue.advance()

func choose_dialogue_option(index: int) -> Error:
	return dialogue.choose(index)

func use_door(object_id: StringName) -> Error:
	var target := _find_target(object_id)
	if target == null:
		return ERR_DOES_NOT_EXIST
	var map_changed := SceneDirector.map_changed
	var error := router.execute_target(target)
	if error != OK:
		return error
	await map_changed
	await (Engine.get_main_loop() as SceneTree).process_frame
	router = SceneDirector.player.get_node("InteractionRouter") as InteractionRouter
	return OK

func finish() -> void:
	app.queue_free()
```

Add `object_id:"mirror"` to the mirror interaction payload. After every map replacement, `AppRoot` rebinds the harness-independent gameplay router/adapters; the harness refreshes its `router` from `SceneDirector.player` before a later interaction.

- [ ] **Step 4: Verify all automated and manual acceptance criteria**

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd`

Expected: all tests PASS.

Run: `pwsh -File tools/run_godot.ps1 --path .`

Expected manual sequence: move/sprint/collide, inspect mirror, see name/portrait/expression, choose branch, regain movement, cross door, observe autosave feedback, save to `slot_1`, change state, load `slot_1`, and recover exact map/player/narrative/world/dialogue state. Disconnect network and repeat boot/load successfully.

- [ ] **Step 5: Commit**

```bash
git add ui/menus app game project.godot tests/integration
git commit -m "feat: complete Project A vertical slice"
```

## Plan 4 Completion Gate

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd`

Expected: all unit and integration tests PASS with exit code 0.

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --quit-after 3`

Expected: clean offline boot with no parser, missing-resource, autoload, or generated-dialogue errors.

The vertical slice is complete only when all nine acceptance criteria in `docs/superpowers/specs/2026-08-09-project-a-foundation-design.md` pass manually and the save corruption tests prove that the last known-good slot and dialogue snapshot survive failed writes/imports.
