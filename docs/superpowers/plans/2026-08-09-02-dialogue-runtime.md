# Dialogue Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a plugin-independent narrative state, validated dialogue graph runner, portrait-aware bottom dialogue UI, choices, effects, and interaction integration using a local compiled fixture.

**Architecture:** `GameSession` owns a serializable `NarrativeState`. `DialogueService` runs immutable compiled JSON through explicit `line`, `choice`, `effect`, `command`, `jump`, and `end` nodes; `DialogueView` only renders requests and emits user intent. Conditions and effects operate on structured dictionaries and never execute arbitrary GDScript.

**Tech Stack:** Godot 4.7, GDScript 2.0, Godot JSON, project-local headless tests, existing Plan 1 services and input actions.

## Global Constraints

- Complete `2026-08-09-01-godot-gameplay-foundation.md` first.
- Do not install Dialogic or another dialogue plugin.
- Runtime must never access Notion or require network connectivity.
- Use the approved bottom dialogue box, one left portrait, speaker name, expression changes, and keyboard choices.
- Dialogue mode must block movement, sprint, and world interaction through `GameSession.can()` only.
- Keep generated dialogue JSON immutable during play; all mutable values belong to `NarrativeState`.
- Use tabs for GDScript indentation and follow TDD with focused and full test runs.

---

## File Map

- `game/narrative/state/narrative_state.gd`: flags, stats, inventory, quests, collectibles, and dictionary snapshots.
- `game/narrative/conditions/condition_evaluator.gd`: structured predicate evaluation.
- `game/narrative/effects/effect_executor.gd`: structured state mutation.
- `game/narrative/dialogue/dialogue_graph.gd`: immutable scene key, entry node, and node dictionary.
- `game/narrative/dialogue/dialogue_graph_loader.gd`: reads compiled JSON by scene key.
- `game/narrative/dialogue/dialogue_graph_validator.gd`: schema and graph reference validation.
- `game/narrative/dialogue/dialogue_service.gd`: runtime cursor and node dispatch.
- `data/characters/character_definition.gd`: character key, display name, default expression, portrait map.
- `data/characters/retti.tres` and `jellyppo.tres`: first character resources.
- `ui/dialogue/dialogue_view.gd` and `.tscn`: bottom dialogue UI.
- `data/generated/dialogues/foundation_inspect.json`: local fixture later replaced by Notion sync.
- `game/interaction/dialogue_action_adapter.gd`: routes `talk` and `inspect` actions into `DialogueService`.

### Task 1: NarrativeState, Conditions, and Effects

**Files:**
- Create: `game/narrative/state/narrative_state.gd`
- Create: `game/narrative/conditions/condition_evaluator.gd`
- Create: `game/narrative/effects/effect_executor.gd`
- Create: `tests/unit/narrative/test_narrative_state.gd`
- Create: `tests/unit/narrative/test_conditions_and_effects.gd`
- Modify: `app/session/game_session.gd`

**Interfaces:**
- Produces: `NarrativeState.snapshot() -> Dictionary` and `NarrativeState.restore(data: Dictionary) -> Error`.
- Produces: `ConditionEvaluator.matches(condition: Dictionary, state: NarrativeState) -> bool`.
- Produces: `EffectExecutor.apply(effect: Dictionary, state: NarrativeState) -> Error`.
- Modifies: `GameSession.narrative_state: NarrativeState`.

- [ ] **Step 1: Write failing state and rule tests**

```gdscript
extends "res://tests/support/test_case.gd"

func run() -> void:
	var state := NarrativeState.new()
	state.set_flag(&"sandwich_more", true)
	state.set_stat(&"corruption", 2.0)
	assert_true(ConditionEvaluator.matches({"kind":"flag", "key":"sandwich_more", "operator":"eq", "value":true}, state), "flag condition")
	assert_true(ConditionEvaluator.matches({"kind":"stat", "key":"corruption", "operator":"gte", "value":2}, state), "numeric condition")
	assert_eq(EffectExecutor.apply({"kind":"stat_add", "key":"corruption", "value":1}, state), OK, "effect succeeds")
	assert_eq(state.get_stat(&"corruption"), 3.0, "effect mutates state")
	var restored := NarrativeState.new()
	assert_eq(restored.restore(state.snapshot()), OK, "snapshot restores")
	assert_eq(restored.snapshot(), state.snapshot(), "round trip is exact")
```

- [ ] **Step 2: Run and verify failure**

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter narrative`

Expected: FAIL because the narrative classes do not exist.

- [ ] **Step 3: Implement the minimal typed state API**

```gdscript
extends RefCounted
class_name NarrativeState

var flags: Dictionary = {}
var stats: Dictionary = {}
var inventory: Dictionary = {}
var quests: Dictionary = {}
var collectibles: Dictionary = {}

func set_flag(key: StringName, value: bool) -> void:
	flags[String(key)] = value

func get_flag(key: StringName, fallback := false) -> bool:
	return bool(flags.get(String(key), fallback))

func set_stat(key: StringName, value: float) -> void:
	stats[String(key)] = value

func get_stat(key: StringName, fallback := 0.0) -> float:
	return float(stats.get(String(key), fallback))

func snapshot() -> Dictionary:
	return {"flags": flags.duplicate(true), "stats": stats.duplicate(true), "inventory": inventory.duplicate(true), "quests": quests.duplicate(true), "collectibles": collectibles.duplicate(true)}
```

Implement `restore()` with exact dictionary type checks before replacing state. `ConditionEvaluator` supports `flag`, `stat`, `inventory`, `quest`, and `collectible`; operators are `eq`, `neq`, `gt`, `gte`, `lt`, `lte`, and `contains` where valid. `EffectExecutor` supports `flag_set`, `stat_set`, `stat_add`, `inventory_add`, `inventory_remove`, `quest_set`, and `collectible_add`; return `ERR_INVALID_DATA` for unsupported combinations.

- [ ] **Step 4: Run focused and full tests**

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter narrative`

Expected: PASS.

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd`

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add game/narrative app/session tests/unit/narrative
git commit -m "feat: add serializable narrative state"
```

### Task 2: Compiled Dialogue Graph and Validation

**Files:**
- Create: `game/narrative/dialogue/dialogue_graph.gd`
- Create: `game/narrative/dialogue/dialogue_graph_loader.gd`
- Create: `game/narrative/dialogue/dialogue_graph_validator.gd`
- Create: `tests/unit/dialogue/test_dialogue_graph_validator.gd`
- Create: `tests/fixtures/dialogues/valid_branch.json`
- Create: `tests/fixtures/dialogues/dangling_target.json`

**Interfaces:**
- Produces: `DialogueGraph.from_dictionary(data: Dictionary) -> DialogueGraph`.
- Produces: `DialogueGraph.get_node(node_id: StringName) -> Dictionary`.
- Produces: `DialogueGraphValidator.validate(data: Dictionary, character_keys: Array[StringName]) -> Array[Dictionary]` where each issue has `severity`, `code`, `scene_key`, `node_id`, and `message`.
- Produces: `DialogueGraphLoader.base_directory: String = "res://data/generated/dialogues"` and `load_scene(scene_key: StringName) -> DialogueGraph`.

- [ ] **Step 1: Write failing graph validation tests**

```gdscript
extends "res://tests/support/test_case.gd"

func run() -> void:
	var valid := JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/dialogues/valid_branch.json"))
	assert_eq(DialogueGraphValidator.validate(valid, [&"retti", &"jellyppo"]), [], "valid graph has no issues")
	var broken := JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/dialogues/dangling_target.json"))
	var issues := DialogueGraphValidator.validate(broken, [&"retti"])
	assert_eq(issues[0]["code"], "dangling_target", "broken target is reported")
```

- [ ] **Step 2: Run and verify failure**

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter dialogue_graph_validator`

Expected: FAIL because graph classes do not exist.

- [ ] **Step 3: Implement the graph schema and validator**

```json
{
  "schema_version": 1,
  "scene_key": "valid.branch",
  "entry_node": "line_1",
  "nodes": {
    "line_1": {"type":"line", "speaker":"retti", "expression":"uneasy", "text":"낯선 거울이다.", "next":"choice_1"},
    "choice_1": {"type":"choice", "items":[
      {"text":"자세히 본다", "conditions":[], "effects":[{"kind":"flag_set", "key":"mirror_seen", "value":true}], "next":"end_1"},
      {"text":"뒤로 물러난다", "conditions":[], "effects":[], "next":"end_1"}
    ]},
    "end_1": {"type":"end"}
  }
}
```

Validate schema version, unique nonempty keys, entry existence, supported node types, required fields, character keys, expression strings, every `next`, every choice target, condition/effect shapes, and an explicit exit from every reachable cycle. `DialogueGraphLoader.base_directory` defaults to `res://data/generated/dialogues`; it resolves `<scene_key with dots replaced by underscores>.json` below that directory so tests can inject `res://tests/fixtures/dialogues` without a fake class.

- [ ] **Step 4: Run focused and full tests**

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter dialogue_graph_validator`

Expected: PASS.

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd`

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add game/narrative/dialogue tests/unit/dialogue tests/fixtures/dialogues
git commit -m "feat: validate compiled dialogue graphs"
```

### Task 3: DialogueService and Bottom DialogueView

**Files:**
- Create: `game/narrative/dialogue/dialogue_service.gd`
- Create: `tests/unit/dialogue/test_dialogue_service.gd`
- Create: `data/characters/character_definition.gd`
- Create: `data/characters/retti.tres`
- Create: `data/characters/jellyppo.tres`
- Create: `ui/dialogue/dialogue_view.gd`
- Create: `ui/dialogue/dialogue_view.tscn`
- Modify: `app/bootstrap/app_root.tscn`

**Interfaces:**
- Consumes: `DialogueGraphLoader`, `GameSession.narrative_state`, `ConditionEvaluator`, and `EffectExecutor`.
- Produces: `DialogueService.start_dialogue(scene_key: StringName, node_id := &"") -> Error`.
- Produces: `DialogueService.advance() -> void`, `choose(index: int) -> Error`, and `get_checkpoint() -> Dictionary`.
- Produces signals: `line_requested(character_key, expression, text)`, `choices_requested(items)`, `command_requested(command)`, `finished()`, and `failed(context)`.
- Produces UI signals: `advance_requested()` and `choice_requested(index)`.

- [ ] **Step 1: Write failing service branch test**

```gdscript
extends "res://tests/support/test_case.gd"

func run() -> void:
	var service := DialogueService.new()
	var loader := DialogueGraphLoader.new()
	loader.base_directory = "res://tests/fixtures/dialogues"
	service.graph_loader = loader
	service.narrative_state = NarrativeState.new()
	assert_eq(service.start_dialogue(&"valid.branch"), OK, "dialogue starts")
	assert_eq(service.current_node_id, &"line_1", "entry line selected")
	service.advance()
	assert_eq(service.current_node_id, &"choice_1", "advance reaches choice")
	assert_eq(service.choose(0), OK, "choice accepted")
	assert_true(service.narrative_state.get_flag(&"mirror_seen"), "choice effect applied")
```

- [ ] **Step 2: Run and verify failure**

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter dialogue_service`

Expected: FAIL because `DialogueService` does not exist.

- [ ] **Step 3: Implement service dispatch and UI contract**

```gdscript
extends Node
class_name DialogueService

signal line_requested(character_key: StringName, expression: StringName, text: String)
signal choices_requested(items: Array[Dictionary])
signal command_requested(command: Dictionary)
signal finished
signal failed(context: Dictionary)

var graph_loader: DialogueGraphLoader
var narrative_state: NarrativeState
var current_graph: DialogueGraph
var current_node_id: StringName
```

`start_dialogue()` changes mode to `DIALOGUE` only after a valid graph loads. Node dispatch loops through `effect`, `jump`, and `command` until reaching `line`, `choice`, or `end`, with a 256-step guard. Always restore the previous mode on `end` or error. Filter choices before emitting them; reject invalid indices without changing state.

Build `DialogueView` as a bottom `Control` with left `TextureRect`, `NameLabel`, `TextLabel`, advance indicator, and vertical choice container. Resolve `character_key/expression` through `CharacterDefinition`; unknown expressions use the default portrait in draft/dev data and log an error. Keyboard focus begins on the first choice.

- [ ] **Step 4: Run tests and inspect the UI scene at 640×360**

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd`

Expected: all tests PASS.

Run: `pwsh -File tools/run_godot.ps1 --path . --editor`

Expected: dialogue UI anchors to the bottom, portrait and text do not overlap, and controls fit at 640×360.

- [ ] **Step 5: Commit**

```bash
git add game/narrative/dialogue data/characters ui/dialogue app/bootstrap tests/unit/dialogue
git commit -m "feat: add portrait dialogue runtime"
```

### Task 4: Interaction Integration and Local Vertical Dialogue Fixture

**Files:**
- Create: `game/interaction/dialogue_action_adapter.gd`
- Create: `data/generated/dialogues/foundation_inspect.json`
- Create: `data/generated/dialogues/manifest.json`
- Create: `tests/integration/test_dialogue_interaction.gd`
- Modify: `content/interactables/sample_inspectable.tscn`
- Modify: `app/bootstrap/app_root.tscn`

**Interfaces:**
- Consumes: `InteractionRouter.action_requested(kind, payload)` and `DialogueService.start_dialogue()`.
- Produces: payload contract `{"scene_key": StringName, "node_id": StringName}` for `talk` and `inspect`.

- [ ] **Step 1: Write the failing integration test**

```gdscript
extends "res://tests/support/test_case.gd"

func run() -> void:
	var app := load("res://app/bootstrap/app_root.tscn").instantiate()
	get_tree().root.add_child(app)
	var router := app.get_node("WorldHost/FoundationRoom/Player/InteractionRouter")
	var dialogue := app.get_node("ServiceLayer/DialogueService") as DialogueService
	router.action_requested.emit(&"inspect", {"scene_key": &"foundation.inspect", "node_id": &"line_1"})
	await get_tree().process_frame
	assert_eq(GameSession.current_mode, GameMode.Value.DIALOGUE, "interaction enters dialogue")
	assert_false(GameSession.can(GameMode.ACTION_MOVE), "movement is blocked")
	dialogue.abort_dialogue(&"test_cleanup")
	assert_eq(GameSession.current_mode, GameMode.Value.EXPLORATION, "dialogue restores exploration")
	app.queue_free()
```

- [ ] **Step 2: Run and verify failure**

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter dialogue_interaction`

Expected: FAIL because the action adapter and generated fixture are absent.

- [ ] **Step 3: Connect the adapter and add immutable fixture data**

```gdscript
extends Node
class_name DialogueActionAdapter

@export var dialogue_service_path: NodePath
@onready var dialogue_service := get_node(dialogue_service_path) as DialogueService

func handle_action(kind: StringName, payload: Dictionary) -> void:
	if kind not in [&"talk", &"inspect"]:
		return
	dialogue_service.start_dialogue(StringName(payload["scene_key"]), StringName(payload.get("node_id", "")))
```

Use the exact validated graph from Task 2 as `foundation_inspect.json`. Set `sample_inspectable` to `action_kind=&"inspect"` with the scene payload. Wire the router to `DialogueActionAdapter.handle_action` in the player/AppRoot composition. Manifest schema is `{"schema_version":1,"generated_at":"2026-08-09T00:00:00Z","source":"local_fixture","scenes":["foundation.inspect"]}` until Plan 3 replaces it.

- [ ] **Step 4: Verify complete local dialogue flow**

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd`

Expected: all tests PASS.

Run: `pwsh -File tools/run_godot.ps1 --path .`

Expected: face the mirror, press E, see name/portrait/text, navigate choices by keyboard, apply `mirror_seen`, close dialogue, and regain movement.

- [ ] **Step 5: Commit**

```bash
git add game/interaction data/generated content/interactables app/bootstrap tests/integration
git commit -m "feat: connect interaction to dialogue choices"
```

## Plan 2 Completion Gate

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd`

Expected: all tests PASS.

Manual acceptance: the local fixture displays the approved bottom UI, changes expressions, filters keyboard choices, updates narrative state, blocks world input, and restores exploration without Dialogic.
