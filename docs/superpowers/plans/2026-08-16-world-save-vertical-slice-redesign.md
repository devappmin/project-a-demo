# World, Save, and Vertical Slice Redesign Implementation Plan

> **For Codex implementers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (same-session task agents) or `superpowers:executing-plans` (separate execution session). Apply `superpowers:test-driven-development` for every production change, `superpowers:systematic-debugging` for unexpected failures, and `superpowers:verification-before-completion` before every completion claim.

**Goal:** Deliver the first complete Project A vertical slice with transactional room-to-room travel, persistent world state, one autosave plus five manual slots, corruption recovery, stable dialogue continuation after important choices, and title/in-game save UI.

**Architecture:** Keep exactly three autoloads. `GameSession` owns serializable play state, `SceneDirector` owns persistent player and transactional map lifetime, and `SaveService` orchestrates pure-data capture/restore through a non-global atomic `SaveRepository`. `AppRoot` owns local gameplay services and UI, rebinding them whenever `SceneDirector` commits a map. Dialogue imports mark important choice blocks, and `DialogueService` emits an autosave request only after the choice transaction reaches a stable line/choice/end boundary.

**Tech stack:** Godot 4.7, GDScript 2.0, JSON schema v1, SHA-256, built-in `FileAccess`/`DirAccess`, existing project-local headless test runner, document-first dialogue import.

**Approved design:** `docs/superpowers/specs/2026-08-16-world-save-vertical-slice-redesign-design.md`

---

## Global execution constraints

- Work directly on `main`; do not create a branch, worktree, or PR.
- Commit each task with the exact semantic intent shown below. Review findings get separate fix commits.
- Never modify `D:/Project/project-a`.
- Keep exactly these autoloads at completion: `GameSession`, `SceneDirector`, `SaveService`.
- Never write saves under `res://`; production saves live only in `user://saves`.
- Never serialize a `Node`, `Resource`, `Callable`, `Object`, or live scene reference.
- Preserve the document-first `dialogue_bundle_key + dialogue_trigger_key` interaction payload.
- Preserve existing normalized authoring source except for the approved `autosave` metadata addition.
- Track one unique `.gd.uid` sidecar for every new tracked script; generate them through a Godot editor scan rather than inventing values.
- Use tabs in GDScript and run `git diff --check` before every commit.
- Every qualifying RED must be a normal test-runner exit code 1 with expected assertion failures, not a parser error or hung process.
- Run tests through the hardened wrapper:

```powershell
$env:PROJECT_A_GODOT_BIN = 'D:\Project\project-a-demo\.superpowers\runtime\godot-4.7-stable\Godot_v4.7-stable_win64_console.exe'
pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter <filter>
```

- Inspect all output for `SCRIPT ERROR`, `Failed to load script`, assertion failures, and missing resources even when an engine exit code is zero.
- Preserve user-owned saves during manual tests. Use a unique `user://test-saves/<case>` repository root for automated tests.

## Target file map

### Session and world

- Modify: `app/session/game_session.gd`
- Create: `game/world/world_state.gd`
- Create: `game/world/persistent_world_object.gd`
- Modify: `game/world/map_scene.gd`
- Create: `game/world/map_definition.gd`
- Create: `game/world/map_registry.gd`
- Create: `data/maps/foundation_room.tres`
- Create: `data/maps/foundation_hall.tres`
- Create: `data/maps/map_registry.tres`

### Map flow

- Create: `app/scene_flow/scene_director.gd`
- Create: `game/interaction/door_action_adapter.gd`
- Create: `ui/transitions/screen_fade.gd`
- Create: `ui/transitions/screen_fade.tscn`
- Modify: `game/actors/player/player_controller.gd`
- Modify: `content/maps/foundation_room.tscn`
- Create: `content/maps/foundation_hall.tscn`
- Modify: `app/bootstrap/app_root.gd`
- Modify: `app/bootstrap/app_root.tscn`
- Modify: `project.godot`

### Saves

- Create: `app/save/save_data.gd`
- Create: `app/save/save_repository.gd`
- Create: `app/save/save_service.gd`

### Dialogue checkpoints

- Modify: `tools/dialogue_import/dialogue_authoring_schema.gd`
- Modify: `tools/dialogue_import/document_dialogue_compiler.gd`
- Modify: `tools/dialogue_import/narrative_reference_writer.gd`
- Modify: `game/narrative/dialogue/dialogue_graph_validator.gd`
- Modify: `game/narrative/dialogue/dialogue_service.gd`
- Modify: `game/interaction/dialogue_action_adapter.gd`
- Modify: `data/dialogues/authoring/foundation_inspect.json`
- Regenerate: `data/generated/dialogues/foundation_inspect.json`
- Regenerate: `data/generated/dialogues/events.json`
- Regenerate: `data/generated/dialogues/source_map.json`
- Regenerate: `data/generated/dialogues/manifest.json`
- Modify: `docs/dialogue-authoring-guide.md`
- Modify: `docs/narrative-state-reference.md`

### Menus

- Create: `ui/menus/save_slot_row.gd`
- Create: `ui/menus/save_slot_row.tscn`
- Create: `ui/menus/save_slot_menu.gd`
- Create: `ui/menus/save_slot_menu.tscn`
- Create: `ui/menus/title_menu.gd`
- Create: `ui/menus/title_menu.tscn`
- Create: `ui/menus/pause_menu.gd`
- Create: `ui/menus/pause_menu.tscn`
- Create: `ui/menus/confirm_panel.gd`
- Create: `ui/menus/confirm_panel.tscn`
- Create: `ui/hud/toast_layer.gd`
- Create: `ui/hud/toast_layer.tscn`

### Tests

- Create: `tests/unit/world/test_world_state.gd`
- Create: `tests/integration/test_persistent_world_object.gd`
- Modify: `tests/unit/world/test_map_scene.gd`
- Create: `tests/unit/world/test_map_registry.gd`
- Create: `tests/integration/test_scene_director.gd`
- Create: `tests/unit/save/test_save_data.gd`
- Create: `tests/integration/save/test_save_repository.gd`
- Create: `tests/integration/save/test_save_service.gd`
- Modify: `tests/unit/dialogue_import/test_dialogue_authoring_schema.gd`
- Modify: `tests/unit/dialogue_import/test_document_dialogue_compiler.gd`
- Modify: `tests/unit/dialogue_import/test_narrative_reference_writer.gd`
- Modify: `tests/unit/dialogue/test_dialogue_graph_validator.gd`
- Modify: `tests/unit/dialogue/test_dialogue_service.gd`
- Modify: `tests/integration/dialogue_import/test_document_authoring_flow.gd`
- Modify: `tests/integration/test_dialogue_interaction.gd`
- Create: `tests/unit/ui/test_save_slot_menu.gd`
- Create: `tests/integration/test_game_menus.gd`
- Create: `tests/support/vertical_slice_harness.gd`
- Create: `tests/integration/test_vertical_slice.gd`

---

## Task 1: Add pure persistent world state

**Files:**

- Create: `game/world/world_state.gd`
- Create: `game/world/persistent_world_object.gd`
- Modify: `app/session/game_session.gd`
- Modify: `content/interactables/sample_inspectable.tscn`
- Create: `tests/unit/world/test_world_state.gd`
- Create: `tests/integration/test_persistent_world_object.gd`

**Interfaces:**

```gdscript
class_name WorldState

func set_object(map_id: StringName, object_id: StringName, state: Dictionary) -> Error
func get_object(map_id: StringName, object_id: StringName) -> Dictionary
func snapshot() -> Dictionary
func restore(data: Dictionary) -> Error
func clear() -> void
```

```gdscript
class_name PersistentWorldObject

@export var object_id: StringName
func capture_persisted_state() -> Dictionary
func apply_persisted_state(state: Dictionary) -> Error
```

`GameSession` gains `world_state`, `play_time_seconds`, `reset_new_game()`, `snapshot_session()`, and fail-closed restore helpers. `reset_new_game()` replaces state with fresh instances rather than mutating an old object that tests or services may still reference.

### Step 1: Write focused failing tests

Write table-driven assertions covering:

- nonempty `map_id` and `object_id` requirement;
- collision-free map/object nesting;
- deep-copy input, lookup, snapshot, and restore;
- exact round trip for nested primitive arrays/dictionaries;
- rejection of missing sections, non-dictionaries, `Node`, `Resource`, `Callable`, and non-finite floats;
- invalid restore leaves the previous state byte-for-byte equivalent;
- `PersistentWorldObject` rejects an empty ID and duplicate registration;
- the mirror captures/applies its `inspected` state without mutating `NarrativeState`.

Run:

```powershell
pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter world_state
pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter persistent_world_object
```

Expected: normal exit 1 because the classes/contracts do not exist.

### Step 2: Implement the smallest pure state model

- Store `maps[map_id][object_id]` using plain String keys.
- Validate recursively before committing any input.
- Duplicate nested values on every boundary.
- Make restore transactional by validating into a candidate dictionary first.
- Let persistent objects locate their parent `MapScene` and register there, but do not make them autoloads.
- Keep mirror dialogue truth (`mirror_seen`) in `NarrativeState`; use `WorldState` only for the mirror object's visual/inspection persistence sample.

### Step 3: Verify GREEN and regressions

Run both focused filters, then:

```powershell
pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd
pwsh -File tools/run_godot.ps1 --headless --path . --editor --quit
git diff --check
```

Expected: focused and full suite exit 0; new scripts parse and have generated unique UIDs.

### Step 4: Commit

```powershell
git add -- app/session/game_session.gd game/world/world_state.gd* game/world/persistent_world_object.gd* content/interactables/sample_inspectable.tscn tests/unit/world/test_world_state.gd* tests/integration/test_persistent_world_object.gd*
git commit -m "feat: add persistent world state"
```

---

## Task 2: Add transactional map flow and a persistent player

**Files:**

- Create: `game/world/map_definition.gd`
- Create: `game/world/map_registry.gd`
- Create: `data/maps/foundation_room.tres`
- Create: `data/maps/foundation_hall.tres`
- Create: `data/maps/map_registry.tres`
- Modify: `game/world/map_scene.gd`
- Create: `app/scene_flow/scene_director.gd`
- Create: `game/interaction/door_action_adapter.gd`
- Create: `ui/transitions/screen_fade.gd`
- Create: `ui/transitions/screen_fade.tscn`
- Modify: `game/actors/player/player_controller.gd`
- Modify: `content/maps/foundation_room.tscn`
- Create: `content/maps/foundation_hall.tscn`
- Modify: `app/bootstrap/app_root.gd`
- Modify: `app/bootstrap/app_root.tscn`
- Modify: `project.godot`
- Modify: `tests/unit/world/test_map_scene.gd`
- Create: `tests/unit/world/test_map_registry.gd`
- Create: `tests/integration/test_scene_director.gd`
- Modify: `tests/integration/test_dialogue_interaction.gd`
- Modify: `tests/unit/app/test_bootstrap.gd`

**Interfaces:**

```gdscript
class_name MapDefinition
@export var map_id: StringName
@export_file("*.tscn") var scene_path: String
@export var default_spawn: StringName = &"start"
@export var display_name: String = ""
```

```gdscript
class_name MapRegistry
func definition(map_id: StringName) -> MapDefinition
func validate_registry() -> PackedStringArray
```

```gdscript
class_name MapScene
func get_spawn(spawn_id: StringName) -> Marker2D
func get_actor_root() -> Node2D
func get_visual_root() -> Node2D
func capture_world_objects(world_state: WorldState) -> Error
func apply_world_objects(world_state: WorldState) -> Error
```

```gdscript
# SceneDirector autoload
signal transition_started(from_map: StringName, to_map: StringName)
signal map_committed(map_id: StringName, spawn_id: StringName, player: PlayerController)
signal transition_failed(context: Dictionary)
signal stable_checkpoint(kind: StringName)

func configure(world_host: Node2D, fade: ScreenFade) -> Error
func start_new_game(map_id := &"foundation_room", spawn_id := &"start") -> Error
func change_map(map_id: StringName, spawn_id: StringName) -> Error
func prepare_restore(map_id: StringName, spawn_id: StringName) -> Dictionary
func commit_restore(plan: Dictionary) -> Error
```

`prepare_restore` creates and validates an off-tree candidate without touching the current map. `commit_restore` keeps the old map detached but alive until world application, player reparenting, and AppRoot rebinding all succeed.

### Step 1: Write map/registry RED tests

Extend `test_map_scene.gd` and add `test_map_registry.gd` for:

- stable spawn lookup and missing spawn;
- required direct `Actors`, `VisualSort`, and `EntryPoints` children;
- map ID mismatch between resource and instantiated scene;
- duplicate registry IDs, missing scene, wrong scene root, and missing default spawn;
- display name lookup for save metadata.

Run filters `map_scene` and `map_registry`; observe normal exit 1.

### Step 2: Write SceneDirector RED tests

Use tiny in-memory/test scenes and zero-duration fade to assert:

- candidate validation happens before current map mutation;
- missing map/spawn preserves current map, player transform, visual parent, mode, and signals one failure;
- successful room→hall→room places at exact spawns;
- there is one persistent player instance across both transitions;
- physics body parent is the new actor root;
- `PlayerVisual` parent is the new visual root and follows player feet;
- old map remains recoverable until commit and is freed only after success;
- transition reentry is rejected;
- restore preparation does not emit autosave checkpoint;
- normal transition emits one `stable_checkpoint(&"map_transition")` after placement.

Run `--filter scene_director`; observe normal exit 1.

### Step 3: Implement registry, maps, and two-phase transition

- Remove the embedded player from `foundation_room.tscn`.
- Give both maps direct `Actors`, `VisualSort`, `EntryPoints`, collisions, and round-trip door targets.
- Instantiate the player scene once in `SceneDirector` and reparent its body/visual explicitly.
- Replace `presentation_parent_path` coupling with `PlayerController.attach_presentation(parent: Node2D)` and a matching detach/rebind contract.
- Make `ScreenFade` awaitable and inject a zero-duration implementation in tests.
- Add `SceneDirector` as the second autoload.
- Let `AppRoot` configure the director and rebind detector/prompt/router/adapters from the `map_committed` signal. Disconnect old signal connections before connecting new ones.
- Preserve document interaction payloads; do not reintroduce direct scene/node IDs.
- Keep `WorldHost` empty at boot. Tests that need gameplay explicitly call `start_new_game()`.
- Set `GameSession` to `MENU` after boot configuration and to `EXPLORATION` only after successful new-game placement.

### Step 4: Focused/full verification

Run:

```powershell
pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter map_scene
pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter map_registry
pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter scene_director
pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter dialogue_interaction
pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd
pwsh -File tools/run_godot.ps1 --headless --path . --editor --quit
pwsh -File tools/run_godot.ps1 --headless --path . --quit-after 3
git diff --check
```

### Step 5: Commit

```powershell
git add -- game/world game/actors/player app/scene_flow game/interaction/door_action_adapter.gd* ui/transitions data/maps content/maps app/bootstrap project.godot tests/unit/world tests/integration/test_scene_director.gd* tests/integration/test_dialogue_interaction.gd tests/unit/app/test_bootstrap.gd
git commit -m "feat: add safe persistent map transitions"
```

---

## Task 3: Add versioned atomic save files

**Files:**

- Create: `app/save/save_data.gd`
- Create: `app/save/save_repository.gd`
- Create: `tests/unit/save/test_save_data.gd`
- Create: `tests/integration/save/test_save_repository.gd`

**Interfaces:**

```gdscript
class_name SaveData
const SCHEMA_VERSION := 1
const SLOT_IDS := [&"auto", &"slot_1", &"slot_2", &"slot_3", &"slot_4", &"slot_5"]

static func validate(snapshot: Dictionary) -> Array[Dictionary]
static func encode(snapshot_without_checksum: Dictionary) -> PackedByteArray
static func with_checksum(snapshot: Dictionary) -> Dictionary
static func verify_checksum(snapshot: Dictionary) -> bool
static func migrate(snapshot: Dictionary) -> Dictionary
static func metadata(snapshot: Dictionary) -> Dictionary
```

```gdscript
class_name SaveRepository

var base_directory := "user://saves"
var stage_observer: Callable

func write_slot(slot_id: StringName, snapshot: Dictionary) -> Error
func read_slot(slot_id: StringName) -> Dictionary
func read_metadata(slot_id: StringName) -> Dictionary
func slot_exists(slot_id: StringName) -> bool
```

`read_slot` returns a closed result such as:

```gdscript
{
  "ok": true,
  "error": OK,
  "data": snapshot,
  "recovered": false,
  "diagnostic": {}
}
```

### Step 1: Write SaveData RED tests

Cover every field and type in schema v1:

- exact allowed top-level sections;
- required `meta`, `player`, `narrative`, `world`, `dialogue` dictionaries;
- fixed six slot IDs;
- ISO timestamp string, nonnegative finite play time, nonempty display location;
- registered map/spawn strings, finite position, four facing values;
- complete `NarrativeState` and `WorldState` shapes;
- inactive dialogue requires no dangling context;
- active dialogue requires bundle, trigger, node, and `line|choice` boundary;
- recursive rejection of unsupported Variant types and non-finite numbers;
- canonical recursive key sorting, stable Array order, deterministic bytes/checksum;
- checksum mutation detection;
- unsupported schema version fails without coercion.

Run `--filter save_data`; expect normal exit 1.

### Step 2: Implement SaveData and verify focused GREEN

Do not use plain `JSON.stringify(dictionary)` as the checksum contract unless dictionary keys have already been recursively sorted. Checksum calculation must omit only the checksum field itself.

Run `--filter save_data`; expect exit 0.

### Step 3: Write repository RED tests with real files

Every test uses a unique directory under `user://test-saves/` and cleans only that exact resolved directory.

Cover:

- all six filenames and invalid/path-like slot IDs;
- first write and overwrite;
- temp reread and checksum verification;
- valid current rotates to one valid backup;
- corrupt current plus valid backup keeps backup while publishing a new current;
- current corrupt/missing plus valid backup restores through verified temp copy and reports `recovered = true`;
- current and backup corrupt returns a closed failure;
- injected write, temp reread, old-backup cleanup, current→backup rename, temp→current rename, final reread failures;
- every failure retains at least one byte-valid last-known-good copy;
- no stale temp is mistaken for a slot;
- metadata reads never mutate/recover a slot implicitly, but may report valid backup metadata with `recoverable = true` when current is invalid so the UI can still offer the load action;
- `slot_exists` is true when either current or backup is valid, not merely when the current filename exists;
- malformed JSON, arrays/scalars at root, and checksum mismatch fail closed.

Run `--filter save_repository`; expect normal exit 1.

### Step 4: Implement repository transaction

- Resolve only exact filenames under the configured base directory.
- Validate existing current and backup separately before rotation.
- Write, reread, validate, and hash temp before any destructive step.
- When current is valid, rotate it to backup before publishing temp.
- When only backup is valid, leave backup untouched and replace only the invalid current.
- On load recovery, copy backup to temp, validate temp, publish current, and retain backup.
- Return structured diagnostics without including save payloads.
- Make stage failure injection test-only through the observer, not global flags.

### Step 5: Verify and commit

Run focused filters, full suite, editor scan, `git diff --check`, then:

```powershell
git add -- app/save/save_data.gd* app/save/save_repository.gd* tests/unit/save/test_save_data.gd* tests/integration/save/test_save_repository.gd*
git commit -m "feat: add atomic versioned save files"
```

---

## Task 4: Mark important choices and expose stable dialogue checkpoints

**Files:**

- Modify: `tools/dialogue_import/dialogue_authoring_schema.gd`
- Modify: `tools/dialogue_import/document_dialogue_compiler.gd`
- Modify: `tools/dialogue_import/narrative_reference_writer.gd`
- Modify: `game/narrative/dialogue/dialogue_graph_validator.gd`
- Modify: `game/narrative/dialogue/dialogue_service.gd`
- Modify: `game/interaction/dialogue_action_adapter.gd`
- Modify: `data/dialogues/authoring/foundation_inspect.json`
- Regenerate: `data/generated/dialogues/*.json`
- Modify: `docs/dialogue-authoring-guide.md`
- Modify: `docs/narrative-state-reference.md`
- Modify: `tests/unit/dialogue_import/test_dialogue_authoring_schema.gd`
- Modify: `tests/unit/dialogue_import/test_document_dialogue_compiler.gd`
- Modify: `tests/unit/dialogue_import/test_narrative_reference_writer.gd`
- Modify: `tests/unit/dialogue/test_dialogue_graph_validator.gd`
- Modify: `tests/unit/dialogue/test_dialogue_service.gd`
- Modify: `tests/integration/dialogue_import/test_document_authoring_flow.gd`
- Modify: `tests/integration/test_dialogue_interaction.gd`

**Runtime contract:**

```gdscript
# compiled choice node
{
  "type": "choice",
  "autosave": true,
  "items": []
}
```

```gdscript
signal stable_checkpoint_reached(kind: StringName, checkpoint: Dictionary)

func start_dialogue(scene_key: StringName, node_id := &"", context := {}) -> Error
func resume_checkpoint(checkpoint: Dictionary) -> Error
func validate_checkpoint(checkpoint: Dictionary) -> Error
func get_checkpoint() -> Dictionary
```

The adapter passes provenance context:

```gdscript
{
  "bundle_key": String(bundle_key),
  "trigger_key": String(trigger_key)
}
```

### Step 1: Write authoring/compiler RED tests

Add tests proving:

- choice block `autosave` is optional and defaults false;
- only a Boolean is accepted;
- unrelated block types reject the field;
- comments still never reach runtime output;
- compiled important choice has exactly `autosave: true`;
- ordinary choice omits the key or has canonical false consistently;
- graph validator accepts Boolean autosave and rejects string/number values;
- source maps and manifest hashes remain coherent.

Run filters `dialogue_authoring_schema`, `document_dialogue_compiler`, and `dialogue_graph_validator`; observe normal exit 1.

### Step 2: Implement metadata and update authoring docs

- Add `autosave` to the closed choice-block authoring shape.
- Normalize the approved document quote `자동 저장: 중요 선택` to Boolean true in the tracked JSON workflow.
- Explain that absent means false and unknown Korean values are import errors.
- Mark the first mirror choice block important in `foundation_inspect.json`.
- Compile the flag onto the choice node, never onto individual visible-choice indices.
- Generate the important-choice authoring note through `NarrativeReferenceWriter`; update its test to assert the tracked `docs/narrative-state-reference.md` is exactly the rendered output rather than a hand-edited drift.

Dry-run and publish:

```powershell
pwsh -File tools/run_godot.ps1 --headless --path . --script res://tools/dialogue_import/dialogue_import_cli.gd -- --dry-run
pwsh -File tools/run_godot.ps1 --headless --path . --script res://tools/dialogue_import/dialogue_import_cli.gd
```

Verify generated graph/event/source-map bytes and manifest hashes match.

### Step 3: Write DialogueService RED tests

Cover:

- `get_checkpoint()` includes exact `bundle_key`, `trigger_key`, `node_id`, and `line|choice` boundary;
- checkpoint callers receive a deep copy;
- `validate_checkpoint` rejects missing graph/node and automatic/end nodes;
- `resume_checkpoint` publishes the saved boundary without reevaluating event conditions;
- resume uses exploration as the post-dialogue return mode, not transition;
- non-important choices emit no stable checkpoint;
- important choices emit exactly once only after effects and automatic nodes reach a line/choice;
- important choice followed by end emits an inactive checkpoint after successful finish;
- effect/dispatch failure rolls back state and emits no autosave checkpoint;
- filtered choice index still maps to the original item;
- reentrant failure/restart protections remain intact.

Run `--filter dialogue_service`; expect normal exit 1.

### Step 4: Implement stable checkpoint publication

- Capture the current choice node's `autosave` before applying the selected item.
- Preserve the complete choice transaction already used by `DialogueService`.
- Emit only after `_dispatch_until_boundary` succeeds.
- Track provenance in service state; clear it on terminal cleanup.
- For an end boundary, publish `{active:false}` only after effects and finish succeed.
- Keep existing `scene_key/next_node_id` callers compatible during the task or update every caller in the same commit; do not leave two ambiguous checkpoint schemas.
- Add a direct resume method that loads the stored graph and exact boundary without calling `DialogueEventResolver`.

### Step 5: Verify and commit

Run all focused filters above plus `narrative_reference_writer`, `document_authoring_flow`, `dialogue_interaction`, the full suite, editor scan, offline boot, source-map/manifest hash checks, and `git diff --check`.

```powershell
git add -- tools/dialogue_import game/narrative/dialogue game/interaction/dialogue_action_adapter.gd data/dialogues/authoring data/generated/dialogues docs/dialogue-authoring-guide.md docs/narrative-state-reference.md tests/unit/dialogue_import tests/unit/dialogue tests/integration/dialogue_import/test_document_authoring_flow.gd tests/integration/test_dialogue_interaction.gd
git commit -m "feat: add stable dialogue autosave checkpoints"
```

---

## Task 5: Orchestrate save, autosave, and transactional restore

**Files:**

- Create: `app/save/save_service.gd`
- Modify: `app/session/game_session.gd`
- Modify: `app/scene_flow/scene_director.gd`
- Modify: `app/bootstrap/app_root.gd`
- Modify: `project.godot`
- Create: `tests/integration/save/test_save_service.gd`
- Modify: `tests/unit/app/test_game_session.gd`
- Modify: `tests/unit/app/test_bootstrap.gd`

**Interfaces:**

```gdscript
# SaveService autoload
signal save_started(slot_id: StringName)
signal save_completed(slot_id: StringName)
signal save_failed(slot_id: StringName, context: Dictionary)
signal load_completed(slot_id: StringName)
signal load_failed(slot_id: StringName, context: Dictionary)
signal backup_recovered(slot_id: StringName)
signal slots_changed

func configure(scene_director: Node, dialogue_service: DialogueService) -> Error
func save_manual_slot(slot_id: StringName) -> Error
func request_autosave(kind: StringName, checkpoint := {}) -> void
func load_slot(slot_id: StringName) -> Error
func slot_metadata() -> Array[Dictionary]
func is_busy() -> bool
```

### Step 1: Write capture and mode-gate RED tests

Build injected fake director/dialogue/player dependencies and cover:

- manual save permitted only in exploration or a menu opened from exploration;
- dialogue, cutscene, transition, paused, title-only menu, and service-busy states reject manual save;
- snapshot contains exact map/display name, spawn, finite position, facing, playtime, NarrativeState, WorldState, and dialogue checkpoint;
- autosave slot is never accepted by the manual-save API;
- invalid state fails before repository write;
- caller mutation cannot alter a queued snapshot.

Run `--filter save_service`; expect normal exit 1.

### Step 2: Write autosave RED tests

Cover:

- normal map transition stable point saves `auto` after placement;
- restore-map commit does not autosave;
- important-choice checkpoint saves `auto` with active dialogue context;
- important-choice end saves inactive dialogue context;
- same-frame duplicate requests coalesce;
- request during a write keeps only the newest pending stable snapshot;
- failed choice/transition produces no save;
- autosave completion/failure signals fire exactly once.

### Step 3: Write restore RED tests

Cover both title and in-game loads:

- repository validation and backup recovery happen before mode/map mutation;
- missing slot fails with identical current state;
- invalid map/spawn/checkpoint fails during preflight with identical current state;
- candidate map is prepared before current map detach;
- narrative/world/player/playtime restore exactly;
- active checkpoint resumes exact line/choice without resolver selection;
- inactive checkpoint returns to exploration;
- active checkpoint eventually ends back in exploration;
- unexpected commit failure restores the old map and session;
- load success does not trigger autosave;
- title failure stays in menu with empty world;
- backup recovery emits one recovery signal and still completes load.

### Step 4: Implement SaveService and restore plan

- Add `SaveService` as the third and final autoload.
- Let `AppRoot` inject its local `DialogueService` after both nodes are ready.
- Capture pure dictionaries only; freeze a deep copy per queued request.
- Track the menu origin in `GameSession` rather than trusting `current_mode == MENU` alone.
- Build and validate a `RestorePlan` before entering transition.
- Keep old session snapshots and the old map instance until all candidate restore steps succeed.
- On dialogue restore, return to exploration first, then call `resume_checkpoint` so the dialogue's previous mode is correct.
- Suppress normal map checkpoint autosave while applying a restore plan.

### Step 5: Verify and commit

Run `save_service`, `scene_director`, `dialogue_service`, full suite, editor, offline boot, UID audit, and `git diff --check`.

```powershell
git add -- app/save/save_service.gd* app/session/game_session.gd app/scene_flow/scene_director.gd app/bootstrap/app_root.gd project.godot tests/integration/save/test_save_service.gd* tests/unit/app
git commit -m "feat: orchestrate safe game saves and restores"
```

---

## Task 6: Build title, pause, and six-row slot UI

**Files:**

- Create: `ui/menus/save_slot_row.gd`
- Create: `ui/menus/save_slot_row.tscn`
- Create: `ui/menus/save_slot_menu.gd`
- Create: `ui/menus/save_slot_menu.tscn`
- Create: `ui/menus/title_menu.gd`
- Create: `ui/menus/title_menu.tscn`
- Create: `ui/menus/pause_menu.gd`
- Create: `ui/menus/pause_menu.tscn`
- Create: `ui/menus/confirm_panel.gd`
- Create: `ui/menus/confirm_panel.tscn`
- Create: `ui/hud/toast_layer.gd`
- Create: `ui/hud/toast_layer.tscn`
- Modify: `app/bootstrap/app_root.gd`
- Modify: `app/bootstrap/app_root.tscn`
- Modify: `app/session/game_mode.gd`
- Modify: `app/session/game_session.gd`
- Modify: `project.godot`
- Create: `tests/unit/ui/test_save_slot_menu.gd`
- Create: `tests/integration/test_game_menus.gd`

**Shared slot model:**

```gdscript
{
  "slot_id": &"auto",
  "label": "자동 저장",
  "exists": true,
  "enabled": true,
  "read_only": true,
  "recoverable": false,
  "location_name": "기초 홀",
  "play_time_seconds": 1234.0,
  "saved_at": "2026-08-16T12:34:56Z"
}
```

### Step 1: Write slot UI RED tests

Instantiate the real 640×360 scene and assert:

- exactly six ordered rows: auto then slot 1–5;
- all six rows fit without a scroll container or viewport overflow;
- each populated row renders location, `HH:MM:SS`, and localized timestamp;
- no screenshot control exists;
- empty load rows are disabled and cannot emit load;
- autosave is loadable but read-only in save mode;
- manual rows are saveable in save mode;
- keyboard up/down skips disabled rows predictably;
- long location names clip within the row;
- refresh uses deep-copied metadata and keeps stable focus when possible.

Run `--filter save_slot_menu`; expect normal exit 1.

### Step 2: Implement reusable rows and slot menu

- Use one row scene and one list scene for title load, pause save, and pause load.
- Keep all rows visible within the 152–300px safe UI area chosen during visual brainstorming.
- Use nearest-friendly integer offsets and existing project font/theme defaults.
- Make slot action signals carry only the fixed slot ID.
- Do not perform save/load inside row scripts; route requests through `AppRoot` to `SaveService`.

### Step 3: Write title/pause RED tests

Cover:

- title shows only `새 게임`, `불러오기`, `종료` and never `이어하기`;
- new game with existing autosave asks confirmation and preserves all manual slots;
- new game successful placement creates/replaces autosave;
- title load opens the same six-row list;
- Esc opens pause only from exploration;
- dialogue/cutscene/transition cannot open pause;
- pause has `계속`, `저장`, `불러오기`, `타이틀로`;
- overwrite confirmation occurs only for populated manual slots;
- title-return confirmation restores title with empty WorldHost;
- failed save/load leaves menu interactive and displays a generic toast;
- backup recovery shows `백업 저장을 복구했습니다`;
- busy service disables duplicate actions;
- cancel/back returns focus to the invoking menu.

Run `--filter game_menus`; expect normal exit 1.

### Step 4: Implement menu orchestration

- Add a `menu` input action bound to Escape.
- Keep title in `MENU` with no active gameplay origin.
- Record exploration-origin menus explicitly in `GameSession`.
- Route SaveService signals to ToastLayer and slot refresh.
- Confirm auto replacement on new game when auto exists; never delete manual slots.
- Hide world prompt/dialogue under title and restore correct UI visibility after load.
- Handle application quit through a testable signal/callback seam rather than terminating the test runner.

### Step 5: Visual and automated verification

Run both focused tests and full suite. Then run a visible 640×360 renderer flow and capture:

- title menu;
- load screen with six rows;
- pause menu;
- save screen with auto read-only and one populated manual slot;
- overwrite confirmation;
- backup recovery toast.

Inspect that all six rows fit, keyboard focus is visible, long labels do not move the layout, and dialogue UI is unaffected.

### Step 6: Commit

```powershell
git add -- ui/menus ui/hud/toast_layer.gd* ui/hud/toast_layer.tscn app/bootstrap app/session project.godot tests/unit/ui tests/integration/test_game_menus.gd*
git commit -m "feat: add title and six-slot save menus"
```

---

## Task 7: Complete and verify the vertical slice

**Files:**

- Modify: `content/maps/foundation_room.tscn`
- Modify: `content/maps/foundation_hall.tscn`
- Modify: `content/interactables/sample_inspectable.tscn`
- Modify: `app/bootstrap/app_root.gd`
- Create: `tests/support/vertical_slice_harness.gd`
- Create: `tests/integration/test_vertical_slice.gd`
- Modify: `tests/integration/test_dialogue_interaction.gd`
- Modify as needed: existing test fixtures only when they encode intentionally replaced AppRoot paths

### Step 1: Write the end-to-end RED test

The harness must use public gameplay APIs and real scene instances. It may inject an isolated save directory and zero-duration fade, but it must not set narrative/world state to simulate the action under test.

Drive this sequence:

1. Instantiate real `AppRoot` at title.
2. Choose new game and wait for initial auto save.
3. Verify movement permission and foundation room placement.
4. Face and interact with the mirror through parsed input/router.
5. Advance real dialogue to the marked important choice.
6. Choose the effect-bearing branch.
7. Verify `mirror_seen`, next stable line, and active autosave checkpoint.
8. Finish dialogue and use the room door.
9. Verify hall map/spawn, persistent player identity, visual parent, and updated autosave.
10. Open pause and save manual slot 1 through UI.
11. Mutate position, facing, narrative, and a world object through public APIs.
12. Load slot 1 through UI and verify exact restoration.
13. Load the important-choice autosave fixture and verify direct resume at its next line/choice.
14. Corrupt current slot 1 while retaining backup, load it, and verify recovery toast plus restored state.
15. Return through the hall door and verify interaction wiring still executes once.

Run `--filter vertical_slice`; expect normal exit 1 until the remaining content/integration gaps are closed.

### Step 2: Close only observed integration gaps

- Give doors stable object IDs and exact reciprocal destinations.
- Ensure the mirror is registered as `foundation_room/mirror`.
- Ensure map display names match slot metadata.
- Remove every hardcoded `WorldHost/FoundationRoom/Player` test and production path.
- Refresh existing dialogue integration helpers from `SceneDirector.player` and current map.
- Do not weaken assertions to accommodate asynchronous timing; wait on public completion signals.

### Step 3: Run the complete automated gate

Run:

```powershell
pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter vertical_slice
pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter scene_director
pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter save_
pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter dialogue_service
pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter game_menus
pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd
pwsh -File tools/run_godot.ps1 --headless --path . --editor --quit
pwsh -File tools/run_godot.ps1 --headless --path . --quit-after 3
git diff --check
git status --short
```

Expected: all filters/full suite exit 0, no script-load diagnostics, editor/class cache clean, offline boot clean, diff check clean.

### Step 4: Run manual 640×360 acceptance

Using a disposable test save root or backed-up user data, verify all 13 steps from the approved design:

1. title new game;
2. move/sprint/collision/animation;
3. mirror inspect;
4. name/portrait/expression/dialogue;
5. important choice to next line;
6. autosave metadata;
7. room→hall door and spawn;
8. manual slot 1 save;
9. state mutation;
10. exact slot 1 restore;
11. autosave dialogue continuation;
12. corrupt-current backup recovery and toast;
13. offline reboot and load.

Capture representative title, six-row load, dialogue checkpoint, hall, pause/save, restored room, and recovery-toast frames. Check 640×360 integer scaling, pixel snap, nearest filtering, feet Y-sort, and keyboard-only navigation.

### Step 5: Integrity audit

- Confirm only three autoloads in `project.godot`.
- Confirm runtime paths contain no Notion, token, HTTP, or credential references.
- Confirm no save path points into `res://`.
- Confirm generated dialogue manifest hashes match artifact bytes.
- Confirm normalized authoring source changed only by the approved autosave field.
- Confirm every tracked `.gd` has one unique `.gd.uid`.
- Confirm source art hashes are unchanged.
- Confirm worktree contains no test saves, screenshots outside ignored report folders, temp files, or generated cache dirt.

### Step 6: Commit

```powershell
git add -- content app/bootstrap tests/support/vertical_slice_harness.gd* tests/integration/test_vertical_slice.gd* tests/integration/test_dialogue_interaction.gd
git commit -m "feat: complete world save vertical slice"
```

---

## Whole-plan review and completion gate

After Task 7:

1. Request a whole-plan code review against the approved design and all task reports.
2. Classify every finding as Critical, Important, or Minor with exact file/line evidence.
3. Use a separate final-fix wave for accepted findings; every behavior fix requires its own RED→GREEN evidence and semantic commit.
4. Re-run the complete automated, editor, offline, visible-render, corruption-recovery, manifest, UID, source-art, and clean-worktree gates.
5. Do not mark the plan complete without a real keyboard-operated manual acceptance. Automated input and render captures may supplement but not replace that gate.

The repository is ready for the next plan only when:

- all automated tests pass through `tools/run_godot.ps1`;
- the manual 13-step slice passes;
- current-save corruption recovers from a valid backup with the Korean notice;
- an important-choice autosave resumes at the exact next stable dialogue boundary;
- room↔hall round trips preserve one player and correct visual/interaction parents;
- title/load/pause/save UI matches the approved six-row layout;
- only three autoloads exist;
- offline boot/load works;
- tracked worktree is clean at the final reviewed HEAD.
