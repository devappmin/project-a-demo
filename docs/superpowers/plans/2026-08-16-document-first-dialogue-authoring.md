# Document-First Dialogue Authoring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the row-per-line Notion sync workflow with a document-first, Korean authoring workflow that Codex or Claude can normalize into catalog-checked, atomically published Godot dialogue bundles.

**Architecture:** Notion remains the collaborative prose source, but the project never queries it directly. Codex or Claude writes tracked normalized bundle JSON; a deterministic catalog validator and bundle compiler turn every tracked bundle into one schema-v1 `DialogueGraph`, an ordered event index selects the first matching event at runtime, and the existing atomic writer publishes the complete local snapshot only after all validation passes.

**Tech Stack:** Godot 4.7, GDScript 2.0, JSON authoring artifacts, existing `DialogueGraph`/`DialogueService` runtime, project-local headless tests, PowerShell launcher.

## Global Constraints

- Work directly on `main`; do not create a branch, worktree, pull request, or external fork.
- Commit after every task with the exact semantic commit shown in that task.
- Modify only `D:/Project/project-a-demo`; never modify deprecated `D:/Project/project-a`.
- Godot remains pinned to 4.7 and the game remains a 640×360 nearest-filtered integer-scale 2D project.
- Notion is the collaborative authoring source; tracked normalized JSON and generated JSON are the code-review and runtime sources.
- Do not implement real-time sync, runtime network access, Notion REST transport, or an AI API call inside the game or editor.
- Authors write Korean page, trigger, event, flow, condition, and result names; internal keys exist only in normalized/codebase artifacts.
- Conditions and results come from Notion quote blocks; Notion comments are optional context and never affect deterministic output.
- The codebase catalog is the only authority for characters, expressions, flags, stats, inventory, quests, collectibles, triggers, effects, and commands.
- An exact or user-approved catalog mapping may compile; a proposed, ambiguous, or missing mapping must fail closed.
- A publish failure must preserve the previous `data/generated/dialogues` snapshot byte-for-byte.
- Use tabs for GDScript indentation, track every generated `.gd.uid`, and use strict RED→GREEN TDD.
- Do not archive, delete, or edit the three existing Notion databases; their final external disposition requires separate user approval.

Source design: `docs/superpowers/specs/2026-08-16-dialogue-authoring-redesign-design.md`.

---

## File Map

### New catalog files

- `game/narrative/catalog/narrative_catalog.gd`: loads the machine-readable catalog and validates normalized conditions/effects.
- `data/narrative/narrative_catalog.json`: canonical keys, Korean display names, aliases, defaults, ranges, quest stages, triggers, and commands.
- `tools/dialogue_import/narrative_reference_writer.gd`: renders the catalog plus the existing character registry into Korean Markdown.
- `docs/narrative-state-reference.md`: generated writer/developer reference; never hand-edited.

### New authoring/import files

- `tools/dialogue_import/dialogue_authoring_schema.gd`: validates normalized bundle structure and authoring-only mapping provenance.
- `tools/dialogue_import/dialogue_identity.gd`: derives hidden stable IDs from durable source IDs and retained keys.
- `tools/dialogue_import/document_dialogue_compiler.gd`: compiles bundles into runtime graphs, event index, source map, issues, and manifest.
- `tools/dialogue_import/dialogue_snapshot_writer.gd`: generalized atomic JSON artifact writer moved from the old Notion tool.
- `tools/dialogue_import/dialogue_import_cli.gd`: loads every approved bundle from a directory, dry-runs, publishes, and prints Korean diagnostics.
- `data/dialogues/authoring/foundation_inspect.json`: tracked normalized sample corresponding to the current mirror dialogue.

### New runtime files

- `game/narrative/dialogue/dialogue_event_index.gd`: loads and validates `events.json` without network access.
- `game/narrative/dialogue/dialogue_event_resolver.gd`: selects the first event whose conditions all match.

### Modified runtime/content files

- `game/interaction/dialogue_action_adapter.gd`: resolves `dialogue_bundle_key` + `dialogue_trigger_key` before starting dialogue.
- `content/interactables/sample_inspectable.tscn`: uses the new bundle/trigger payload.
- `data/generated/dialogues/foundation_inspect.json`: regenerated one-bundle graph containing all sample event entries.
- `data/generated/dialogues/events.json`: ordered runtime event candidates.
- `data/generated/dialogues/source_map.json`: hidden source-to-runtime identity audit.
- `data/generated/dialogues/manifest.json`: hashes every generated artifact.

### Migrated or removed legacy files

- Move `tools/notion_sync/dialogue_snapshot_writer.gd` and its UID to `tools/dialogue_import/` in Task 5.
- Move `tests/integration/test_snapshot_writer.gd` and its UID to `tests/integration/dialogue_import/` in Task 5.
- Remove the remaining `tools/notion_sync/`, `tests/unit/notion_sync/`, `tests/fixtures/notion/`, `tests/support/notion_sync_cli_harness.gd`, and `tests/integration/test_notion_sync_editor_plugin.gd` files in Task 6.
- Remove `res://tools/notion_sync/plugin.cfg` from `project.godot` in Task 6.
- Replace `docs/dialogue-authoring-guide.md` with the document-first workflow in Task 6.

---

### Task 1: Canonical Narrative Catalog and Generated Korean Reference

**Files:**
- Create: `game/narrative/catalog/narrative_catalog.gd`
- Create: `game/narrative/catalog/narrative_catalog.gd.uid`
- Create: `data/narrative/narrative_catalog.json`
- Create: `tools/dialogue_import/narrative_reference_writer.gd`
- Create: `tools/dialogue_import/narrative_reference_writer.gd.uid`
- Create: `tests/unit/narrative/test_narrative_catalog.gd`
- Create: `tests/unit/narrative/test_narrative_catalog.gd.uid`
- Create: `tests/unit/dialogue_import/test_narrative_reference_writer.gd`
- Create: `tests/unit/dialogue_import/test_narrative_reference_writer.gd.uid`
- Create: `docs/narrative-state-reference.md`

**Interfaces:**
- Produces: `NarrativeCatalog.load_default() -> NarrativeCatalog`.
- Produces: `NarrativeCatalog.from_dictionary(data: Dictionary) -> NarrativeCatalog`.
- Produces: `catalog.validate_catalog() -> Array[Dictionary]`.
- Produces: `catalog.validate_condition(record: Dictionary) -> Dictionary` with `ok`, `code`, `message`, and normalized `value`.
- Produces: `catalog.validate_effect(record: Dictionary) -> Dictionary` with the same result shape.
- Produces: `catalog.has_trigger(trigger_key: StringName) -> bool`.
- Produces: `NarrativeReferenceWriter.render(catalog: NarrativeCatalog, characters: Resource) -> String`.

- [ ] **Step 1: Write the catalog RED tests**

Create `test_narrative_catalog.gd` with an injected dictionary so the tests do not depend on file I/O:

```gdscript
extends "res://tests/support/test_case.gd"

const CATALOG_PATH := "res://game/narrative/catalog/narrative_catalog.gd"

func run() -> void:
	assert_true(ResourceLoader.exists(CATALOG_PATH, "Script"), "narrative catalog script exists")
	if not ResourceLoader.exists(CATALOG_PATH, "Script"):
		return
	var catalog_script: Script = load(CATALOG_PATH)
	var catalog: RefCounted = catalog_script.from_dictionary(_catalog_data())
	assert_eq(catalog.validate_catalog(), [], "valid catalog has no issues")
	assert_true(catalog.has_trigger(&"mirror.inspect"), "registered trigger resolves")
	var exact := catalog.validate_condition({"source_text":"거울을 자세히 봄", "term_name":"거울을 자세히 봄", "mapping_status":"exact", "kind":"flag", "key":"mirror_seen", "operator":"eq", "value":true})
	assert_true(exact["ok"], "exact flag mapping validates")
	var proposed := catalog.validate_effect({"source_text":"신뢰가 조금 오름", "term_name":"젤리뽀의 신뢰", "mapping_status":"proposed", "kind":"stat_add", "key":"jellyppo_trust", "value":1})
	assert_false(proposed["ok"], "unapproved proposal fails closed")
	assert_eq(proposed["code"], "mapping_not_approved", "proposal has stable diagnostic")
	var invented := catalog.validate_condition({"source_text":"마음이 열림", "term_name":"마음이 열림", "mapping_status":"exact", "kind":"flag", "key":"invented_flag", "operator":"eq", "value":true})
	assert_false(invented["ok"], "unknown key is never invented")

func _catalog_data() -> Dictionary:
	return {"schema_version":1, "terms":[
		{"kind":"flag", "key":"mirror_seen", "display_name":"거울을 자세히 봄", "aliases":["거울을 봄"], "default":false},
		{"kind":"stat", "key":"jellyppo_trust", "display_name":"젤리뽀의 신뢰", "aliases":[], "default":0, "minimum":-10, "maximum":10}
	], "triggers":[{"key":"mirror.inspect", "display_name":"거울 조사"}], "commands":[]}
```

- [ ] **Step 2: Run the catalog RED**

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter narrative_catalog`

Expected: normal exit 1 because `narrative_catalog.gd` does not exist.

- [ ] **Step 3: Implement catalog loading and strict validation**

Implement the public shape below; keep category/operator/type checks in focused private functions rather than embedding them in the compiler:

```gdscript
extends RefCounted
class_name NarrativeCatalog

const DEFAULT_PATH := "res://data/narrative/narrative_catalog.json"
const CONDITION_KINDS := [&"flag", &"stat", &"inventory", &"quest", &"collectible"]
const MAPPING_STATUSES := [&"exact", &"approved"]

var _terms_by_identity: Dictionary = {}
var _triggers: Dictionary = {}
var _commands: Dictionary = {}

static func load_default() -> NarrativeCatalog:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DEFAULT_PATH))
	return from_dictionary(parsed if typeof(parsed) == TYPE_DICTIONARY else {})

static func from_dictionary(data: Dictionary) -> NarrativeCatalog:
	var catalog := NarrativeCatalog.new()
	catalog._install(data)
	return catalog

func has_trigger(trigger_key: StringName) -> bool:
	return _triggers.has(String(trigger_key))

func validate_condition(record: Dictionary) -> Dictionary:
	return _validate_mapping(record, true)

func validate_effect(record: Dictionary) -> Dictionary:
	return _validate_mapping(record, false)
```

`exact` requires `term_name` to equal the registered Korean display name or alias. `approved` requires an existing catalog key but may retain the writer's original phrase. Conditions use state kinds (`flag`, `stat`, `inventory`, `quest`, `collectible`); effects map `flag_set` to `flag`, `stat_set`/`stat_add` to `stat`, `inventory_add`/`inventory_remove` to `inventory`, `quest_set` to `quest`, and `collectible_add` to `collectible` before catalog lookup. Validate booleans, numeric ranges, non-negative inventory/collectible quantities, quest stages, condition operators, and supported effect kinds. Return the runtime condition/effect dictionary in `value`; never copy `source_text`, `term_name`, `mapping_status`, or comments into runtime data.

Seed `narrative_catalog.json` with the current `mirror_seen` flag, `jellyppo_trust` stat, `exchange_diary_key` inventory item, `showed_diary_key` flag, `truth_investigation` quest stages, `mirror.inspect` trigger, and an empty `commands` array. Each entry must include a Korean display name, description, default, aliases, and category-specific constraints.

- [ ] **Step 4: Write and run the reference-writer RED**

Create `test_narrative_reference_writer.gd` and assert exact stable sections:

```gdscript
var markdown := writer.render(catalog, load("res://data/characters/character_registry.tres"))
assert_true(markdown.begins_with("# 서사 상태·대화 용어 참고서\n"), "reference has Korean title")
assert_true(markdown.contains("## 사건 상태") and markdown.contains("`mirror_seen`"), "reference includes flags")
assert_true(markdown.contains("## 등장인물과 표정") and markdown.contains("레티"), "reference includes character registry")
assert_false(markdown.contains("PROJECT_A_NOTION_TOKEN"), "reference never contains old credentials")
```

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter narrative_reference_writer`

Expected: normal exit 1 because the writer does not exist.

- [ ] **Step 5: Implement deterministic Markdown rendering and generate the file**

Sort categories in `flag`, `stat`, `inventory`, `quest`, `collectible`, `trigger`, `command` order; sort terms by internal key; render Korean name, internal key, description, default/range/stages, and aliases. Append characters sorted by `character_key`, with display name and sorted expression names from the existing registry.

Add a script entry method that writes only the requested path:

```gdscript
static func write_default(output_path := "res://docs/narrative-state-reference.md") -> Error:
	var text := render(NarrativeCatalog.load_default(), load("res://data/characters/character_registry.tres"))
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	return file.get_error()
```

Generate `docs/narrative-state-reference.md` through the writer, not by hand.

- [ ] **Step 6: Run focused and full GREEN verification**

Run:

```powershell
pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter narrative_catalog
pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter narrative_reference_writer
pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd
```

Expected: both focused suites and the full suite exit 0; a second render of the reference is byte-identical.

- [ ] **Step 7: Commit Task 1**

```powershell
git add game/narrative/catalog data/narrative tools/dialogue_import/narrative_reference_writer.gd* tests/unit/narrative/test_narrative_catalog.gd* tests/unit/dialogue_import/test_narrative_reference_writer.gd* docs/narrative-state-reference.md
git commit -m "feat: add canonical narrative catalog"
```

---

### Task 2: Normalized Bundle Contract and Stable Hidden Identity

**Files:**
- Create: `tools/dialogue_import/dialogue_identity.gd`
- Create: `tools/dialogue_import/dialogue_identity.gd.uid`
- Create: `tools/dialogue_import/dialogue_authoring_schema.gd`
- Create: `tools/dialogue_import/dialogue_authoring_schema.gd.uid`
- Create: `tests/fixtures/dialogue_import/dialogue_bundle_fixture_factory.gd`
- Create: `tests/fixtures/dialogue_import/dialogue_bundle_fixture_factory.gd.uid`
- Create: `tests/unit/dialogue_import/test_dialogue_authoring_schema.gd`
- Create: `tests/unit/dialogue_import/test_dialogue_authoring_schema.gd.uid`

**Interfaces:**
- Consumes: `NarrativeCatalog` and the existing `CharacterRegistry`.
- Produces: `DialogueIdentity.stable_key(kind: String, source_id: String, retained_key := "") -> String`.
- Produces: `DialogueAuthoringSchema.validate_bundle(bundle: Dictionary, catalog: NarrativeCatalog, characters: Resource) -> Array[Dictionary]`.
- Produces fixture: `DialogueBundleFixtureFactory.valid_bundle() -> Dictionary`.
- Issue shape: `severity`, `code`, `message`, `source_id`, `source_url`, `bundle_key`, `event_key`, `flow_key`.

- [ ] **Step 1: Write the normalized-contract RED**

The fixture must model one page, one trigger, two ordered events, Korean labels, a fallback, multiple paragraphs, a two-choice branch, a later second choice, a rejoin, event/flow/choice results, and ignored comments:

```gdscript
static func valid_bundle() -> Dictionary:
	return {
		"schema_version":1,
		"source_id":"notion-page-foundation",
		"source_url":"https://www.notion.so/foundation",
		"bundle_key":"foundation.inspect",
		"title":"기초 방",
		"comments":[{"text":"이 메모는 출력에 영향을 주지 않는다"}],
		"triggers":[{
			"source_id":"notion-heading-mirror",
			"trigger_key":"mirror.inspect",
			"name":"거울 조사",
			"events":[
				{"source_id":"notion-event-seen", "event_key":"seen", "name":"이미 본 거울", "conditions":[_condition("거울을 자세히 봄", "flag", "mirror_seen", "eq", true)], "effects":[], "flows":[_seen_flow()]},
				{"source_id":"notion-event-default", "event_key":"default", "name":"그 외", "conditions":[], "effects":[], "flows":[_default_start(), _inspect_flow(), _leave_flow(), _rejoin_flow()]}
			]
		}]
	}
```

Each flow has `source_id`, `flow_key`, `name`, `effects`, and ordered `blocks`. A line block has `type`, `source_id`, `speaker`, `expression`, `text`; a choice has `items` with `source_id`, Korean `text`, `conditions`, `effects`, `target_kind` (`flow` or `event`), and `target_key`; a jump has `target_kind` and `target_key`; a command has `command_key` plus a dictionary of `arguments`; an end has only `type` and `source_id`. Optional `comments` may appear at every level but are ignored.

Assert duplicate flow names, duplicate retained keys, missing source IDs, unknown characters/expressions/triggers, cross-page targets, unapproved mappings, dangling targets, missing `흐름 · 시작`, and a path with no choice/jump/end all produce stable errors. Assert a missing fallback produces only `missing_fallback` warning.

- [ ] **Step 2: Run the authoring-schema RED**

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter dialogue_authoring_schema`

Expected: normal exit 1 because schema and identity scripts do not exist.

- [ ] **Step 3: Implement stable identity**

Use the retained codebase key when it is safe; otherwise derive a hidden deterministic key from durable source identity:

```gdscript
extends RefCounted
class_name DialogueIdentity

static func stable_key(kind: String, source_id: String, retained_key := "") -> String:
	if _is_safe_key(retained_key):
		return retained_key
	if kind.is_empty() or source_id.strip_edges().is_empty():
		return ""
	return "%s_%s" % [kind, (kind + ":" + source_id).sha256_text().left(12)]

static func node_id(event_key: String, flow_key: String, block_key: String) -> String:
	return "%s.%s.%s" % [event_key, flow_key, block_key]
```

Safe keys allow ASCII lowercase letters, digits, underscores, dots, and hyphens; reject path separators, whitespace, empty keys, Windows device names, and `manifest`, `events`, `source_map`. A normalized artifact without a Notion block ID must retain a generated `local:<uuid>` source ID on every later AI update.

- [ ] **Step 4: Implement structural and catalog validation**

`DialogueAuthoringSchema` validates types before indexing arrays, collects all issues without script errors, and preserves source provenance. It must:

- Require one or more triggers, events, flows, and blocks.
- Require a unique `흐름 · 시작` semantic entry represented by `flow_key == "start"` in every event.
- Treat event order in the input array as authoritative.
- Require every non-end path to fall through to another block or provide a valid flow/event target.
- Allow event targets only inside the same bundle.
- Validate event, flow, and choice condition/effect records through `NarrativeCatalog`.
- Validate every command block against the catalog command list and copy only its key and allowed arguments to runtime data.
- Validate speakers/expressions through `CharacterRegistry`.
- Ignore `comments` at every depth and never report their text as a rule.
- Emit `missing_fallback` warning when the final event has conditions; all other contract problems are errors.

- [ ] **Step 5: Prove comments and Korean renames do not change identity**

Add tests that duplicate the fixture, replace every comment, and rename Korean event/flow titles while keeping `source_id` and retained keys. Assert validation remains clean and every `DialogueIdentity.stable_key()` result stays equal. Then remove a retained key and assert the source-derived key remains stable across title changes.

- [ ] **Step 6: Run focused and full GREEN verification**

Run:

```powershell
pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter dialogue_authoring_schema
pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd
```

Expected: focused and full suites exit 0 with no `SCRIPT ERROR` output.

- [ ] **Step 7: Commit Task 2**

```powershell
git add tools/dialogue_import/dialogue_identity.gd* tools/dialogue_import/dialogue_authoring_schema.gd* tests/fixtures/dialogue_import tests/unit/dialogue_import/test_dialogue_authoring_schema.gd*
git commit -m "feat: define document dialogue contract"
```

---

### Task 3: Bundle Compiler, Ordered Event Index, and Result Timing

**Files:**
- Create: `tools/dialogue_import/document_dialogue_compiler.gd`
- Create: `tools/dialogue_import/document_dialogue_compiler.gd.uid`
- Create: `tests/unit/dialogue_import/test_document_dialogue_compiler.gd`
- Create: `tests/unit/dialogue_import/test_document_dialogue_compiler.gd.uid`
- Modify: `game/narrative/dialogue/dialogue_graph_validator.gd`
- Modify: `tests/unit/dialogue/test_dialogue_graph_validator.gd`

**Interfaces:**
- Consumes: validated normalized bundles, `NarrativeCatalog`, `CharacterRegistry`, `DialogueIdentity`, and `DialogueGraphValidator`.
- Produces: `DocumentDialogueCompiler.compile_bundles(bundles: Array[Dictionary], catalog: NarrativeCatalog = null, characters: Resource = null) -> Dictionary`.
- Result shape: `ok`, `graphs`, `events`, `source_map`, `issues`, `manifest`, and `artifacts`.
- `graphs` maps `bundle_key` to schema-v1 `DialogueGraph` dictionaries.
- `events` shape: `{"schema_version":1,"bundles":{bundle_key:{"triggers":{trigger_key:[candidate...]}}}}`.
- `artifacts` maps safe relative JSON filenames to dictionaries, excluding `manifest.json`.

- [ ] **Step 1: Write compiler RED tests for the complete graph shape**

Compile the Task 2 fixture and assert:

```gdscript
var result: Dictionary = compiler.compile_bundles([fixture_factory.valid_bundle()])
assert_true(result["ok"], "valid document bundle compiles")
var graph: Dictionary = result["graphs"]["foundation.inspect"]
assert_eq(graph["schema_version"], 1, "runtime graph schema remains compatible")
assert_true(graph["nodes"].size() > 6, "all event flows share one bundle graph")
var candidates: Array = result["events"]["bundles"]["foundation.inspect"]["triggers"]["mirror.inspect"]
assert_eq(candidates.size(), 2, "trigger retains both ordered events")
assert_eq(candidates[0]["event_key"], "seen", "specific event remains first")
assert_eq(candidates[1]["event_key"], "default", "fallback remains last")
assert_eq(candidates[0]["conditions"], [{"kind":"flag", "key":"mirror_seen", "operator":"eq", "value":true}], "authoring provenance is stripped from runtime conditions")
```

Assert repeated compilation produces byte-identical `graphs`, `events`, `source_map`, and `artifacts`. Ignore only `manifest.generated_at` when comparing manifests.

- [ ] **Step 2: Run the compiler RED**

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter document_dialogue_compiler`

Expected: normal exit 1 because the document compiler does not exist.

- [ ] **Step 3: Compile flat flows and arbitrary-depth choices into one graph per page**

Use stable node IDs composed from retained event/flow/block keys. Lines and commands fall through in document order. Choice and jump targets resolve to the target flow entry or same-bundle event entry. Create one real `end` node for each authored end. Set the graph's required default `entry_node` to the first trigger's first event start; normal gameplay uses the event index entry selected at runtime.

Core routing helper:

```gdscript
static func _route_effects(nodes: Dictionary, route_id: String, effects: Array[Dictionary], target: String) -> String:
	if effects.is_empty():
		return target
	var effect_id := route_id + ".effects"
	nodes[effect_id] = {"type":"effect", "effects":effects.duplicate(true), "next":target}
	return effect_id
```

For every edge leaving a flow, route through that flow's normalized results. For `end` and same-page event transitions, then route through the current event's normalized results. Choice-specific effects remain on the choice item and execute before the destination. This ordering implements `choice result → flow result → event result → destination`. Aborted dialogue relies on the existing `DialogueService` transaction rollback and must not retain unfinished synthetic effects.

- [ ] **Step 4: Build the ordered event index and source map**

Each event candidate contains only stable runtime fields:

```gdscript
{
	"event_key":"seen",
	"entry_node":"seen.start.line_01",
	"conditions":[{"kind":"flag", "key":"mirror_seen", "operator":"eq", "value":true}]
}
```

`source_map.json` records each normalized `source_id`, source URL, kind, retained/generated key, and generated node ID where applicable. It contains no comment text. `events.json` preserves input event order; all other dictionary keys and source-map entries are sorted before stable JSON encoding.

- [ ] **Step 5: Generalize graph validation without changing schema version**

Keep `DialogueGraphValidator.validate(data, character_keys)` source-compatible. Add optional `entry_nodes: Array[StringName] = []`; validate every supplied event entry exists in `nodes` and include all event entries as reachability roots. Continue validating every node for cycles and the 256 automatic-step limit even when unreachable from the graph's default entry.

```gdscript
static func validate(data: Dictionary, character_keys: Array[StringName], entry_nodes: Array[StringName] = []) -> Array[Dictionary]:
	# Existing schema/node validation stays intact.
	# Add stable invalid_event_entry issues for missing supplied roots.
```

Compiler validation passes all event entry nodes to the graph validator so a valid non-default event cannot hide a bad cycle.

- [ ] **Step 6: Add result-timing, loop, rejoin, and comment-invariance tests**

Assert graph edges execute choice effects before flow effects, event results only on end/event transition, a branch can return to a previous flow, two branches can rejoin one flow, and a second choice may appear after several lines. Compile fixtures with comments removed/replaced and assert runtime artifacts are byte-identical.

- [ ] **Step 7: Run focused and full GREEN verification**

Run:

```powershell
pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter document_dialogue_compiler
pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter dialogue_graph_validator
pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd
```

Expected: all commands exit 0; compiler issues retain normalized source URLs and stable codes.

- [ ] **Step 8: Commit Task 3**

```powershell
git add tools/dialogue_import/document_dialogue_compiler.gd* tests/unit/dialogue_import/test_document_dialogue_compiler.gd* game/narrative/dialogue/dialogue_graph_validator.gd tests/unit/dialogue/test_dialogue_graph_validator.gd
git commit -m "feat: compile document dialogue bundles"
```

---

### Task 4: Runtime First-Match Event Resolution

**Files:**
- Create: `game/narrative/dialogue/dialogue_event_index.gd`
- Create: `game/narrative/dialogue/dialogue_event_index.gd.uid`
- Create: `game/narrative/dialogue/dialogue_event_resolver.gd`
- Create: `game/narrative/dialogue/dialogue_event_resolver.gd.uid`
- Create: `tests/unit/dialogue/test_dialogue_event_resolver.gd`
- Create: `tests/unit/dialogue/test_dialogue_event_resolver.gd.uid`
- Modify: `game/interaction/dialogue_action_adapter.gd`
- Modify: `tests/integration/test_dialogue_interaction.gd`

**Interfaces:**
- Produces: `DialogueEventIndex.load_default() -> DialogueEventIndex`.
- Produces: `DialogueEventIndex.load_path(path: String) -> DialogueEventIndex` for generated-output integration tests.
- Produces: `DialogueEventIndex.from_dictionary(data: Dictionary) -> DialogueEventIndex`.
- Produces: `index.is_valid() -> bool` and read-only `index.last_failure: Dictionary`.
- Produces: `index.candidates(bundle_key: StringName, trigger_key: StringName) -> Array[Dictionary]`.
- Produces: `DialogueEventResolver.resolve(bundle_key: StringName, trigger_key: StringName, state: NarrativeState) -> Dictionary`.
- Provides injectable property: `resolver.event_index: DialogueEventIndex` for tests; production lazily uses `DialogueEventIndex.load_default()`.
- Resolver result on success: `ok`, `scene_key`, `node_id`, `event_key`; on failure: `ok=false`, `error`, `code`.
- `DialogueActionAdapter.handle_action(kind: StringName, payload: Dictionary) -> Error`.

- [ ] **Step 1: Write the event-resolution RED**

Use an injected in-memory index with a specific `mirror_seen == true` event followed by an unconditional fallback:

```gdscript
var resolver := resolver_script.new()
resolver.event_index = index_script.from_dictionary(_event_index())
var state := NarrativeState.new()
var first := resolver.resolve(&"foundation.inspect", &"mirror.inspect", state)
assert_eq(first["event_key"], &"default", "fallback runs before the flag is set")
state.set_flag(&"mirror_seen", true)
var specific := resolver.resolve(&"foundation.inspect", &"mirror.inspect", state)
assert_eq(specific["event_key"], &"seen", "first matching specific event wins")
```

Also assert unknown bundle, unknown trigger, malformed conditions, and no matching event return stable non-OK results without mutating state.

- [ ] **Step 2: Run the resolver RED**

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter dialogue_event_resolver`

Expected: normal exit 1 because event index and resolver scripts do not exist.

- [ ] **Step 3: Implement strict local index loading and first-match resolution**

`DialogueEventIndex` loads `res://data/generated/dialogues/events.json`, requires schema version 1, copies returned candidates deeply, and reports malformed roots through `last_failure` without partial acceptance. `DialogueEventResolver` returns `malformed_event_index` when `is_valid()` is false; otherwise it iterates candidates in stored order and requires every condition to match through `ConditionEvaluator`:

```gdscript
func resolve(bundle_key: StringName, trigger_key: StringName, state: NarrativeState) -> Dictionary:
	if state == null:
		return _failure(ERR_UNCONFIGURED, "missing_state")
	for candidate: Dictionary in event_index.candidates(bundle_key, trigger_key):
		if _all_conditions_match(candidate.get("conditions", []), state):
			return {"ok":true, "scene_key":bundle_key, "node_id":StringName(candidate["entry_node"]), "event_key":StringName(candidate["event_key"])}
	return _failure(ERR_DOES_NOT_EXIST, "no_matching_event")
```

- [ ] **Step 4: Integrate the adapter while retaining temporary legacy compatibility**

Add injectable `event_resolver` and make `handle_action` return the real error. New payloads use `dialogue_bundle_key` and `dialogue_trigger_key`; the old `scene_key` path remains only until Task 6 so the existing sample keeps working during this task.

```gdscript
var resolved := event_resolver.resolve(StringName(bundle_value), StringName(trigger_value), dialogue_service.narrative_state)
if not resolved["ok"]:
	return resolved["error"]
return dialogue_service.start_dialogue(resolved["scene_key"], resolved["node_id"])
```

The existing router continues to consume the input after a valid target emits its action signal. The adapter return value is intentionally ignored by that signal connection, but direct integration tests call `handle_action` and assert its real `Error` so no-match and malformed payload behavior remain observable.

- [ ] **Step 5: Add runtime integration for ordered selection and state effects**

Inject a temporary graph loader plus event index. Execute the interaction once with `mirror_seen=false`, drive the fallback dialogue through its first choice until its result sets the flag, exit dialogue, interact again, and assert the specific event entry is selected. Verify no-match returns to exploration without opening `DialogueView` and does not mutate `NarrativeState`.

- [ ] **Step 6: Run focused and full GREEN verification**

Run:

```powershell
pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter dialogue_event_resolver
pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter dialogue_interaction
pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd
```

Expected: focused and full suites exit 0; state snapshots before failed resolution remain equal afterward.

- [ ] **Step 7: Commit Task 4**

```powershell
git add game/narrative/dialogue/dialogue_event_index.gd* game/narrative/dialogue/dialogue_event_resolver.gd* game/interaction/dialogue_action_adapter.gd tests/unit/dialogue/test_dialogue_event_resolver.gd* tests/integration/test_dialogue_interaction.gd
git commit -m "feat: resolve conditional dialogue events"
```

---

### Task 5: Manual Import CLI and Generalized Atomic Artifact Publishing

**Files:**
- Move: `tools/notion_sync/dialogue_snapshot_writer.gd` → `tools/dialogue_import/dialogue_snapshot_writer.gd`
- Move: `tools/notion_sync/dialogue_snapshot_writer.gd.uid` → `tools/dialogue_import/dialogue_snapshot_writer.gd.uid`
- Create: `tools/dialogue_import/dialogue_import_cli.gd`
- Create: `tools/dialogue_import/dialogue_import_cli.gd.uid`
- Create: `tests/support/dialogue_import_cli_harness.gd`
- Create: `tests/support/dialogue_import_cli_harness.gd.uid`
- Move: `tests/integration/test_snapshot_writer.gd` → `tests/integration/dialogue_import/test_snapshot_writer.gd`
- Move: `tests/integration/test_snapshot_writer.gd.uid` → `tests/integration/dialogue_import/test_snapshot_writer.gd.uid`
- Create: `tests/integration/dialogue_import/test_dialogue_import_cli.gd`
- Create: `tests/integration/dialogue_import/test_dialogue_import_cli.gd.uid`
- Modify temporarily: `tools/notion_sync/notion_sync_cli.gd`

**Interfaces:**
- Produces: `DialogueSnapshotWriter.replace_artifacts(output_dir: String, artifacts: Dictionary, manifest: Dictionary) -> Error`.
- Retains until Task 6: `replace_snapshot(output_dir: String, graphs: Dictionary, manifest: Dictionary) -> Error` as a compatibility wrapper.
- Produces: `DialogueImportCli.run_import(input_dir: String, output_dir: String, dry_run: bool, allow_warnings := false) -> Dictionary`.
- CLI defaults: input `res://data/dialogues/authoring`, output `res://data/generated/dialogues`.
- CLI arguments: `--input-dir <path>`, `--output-dir <path>`, `--dry-run`, `--allow-warnings`.

- [ ] **Step 1: Write the generalized-writer RED**

Extend the moved writer suite with `events.json` and `source_map.json` artifacts. Assert all files and manifest hashes publish together, and each injected write/verify/backup-rename/publish-rename/rollback failure preserves the previous output bytes and existing recovery guarantees.

```gdscript
var artifacts := {
	"foundation_inspect.json": graph,
	"events.json": event_index,
	"source_map.json": source_map,
}
var error := writer.replace_artifacts(output_dir, artifacts, manifest)
assert_eq(error, OK, "all dialogue artifacts publish atomically")
assert_eq(_snapshot_bytes(output_dir)["events.json"], compiler.stable_json(event_index).to_utf8_buffer(), "event index is in the same transaction")
```

- [ ] **Step 2: Run the writer RED**

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter snapshot_writer`

Expected: normal exit 1 because the moved writer lacks `replace_artifacts` and test paths have changed.

- [ ] **Step 3: Move and generalize the writer without weakening recovery**

`replace_artifacts` accepts only flat `.json` filenames whose base names are not `manifest`, rejects case-insensitive collisions, stable-encodes each dictionary, checks every manifest SHA-256, writes/rereads all artifacts, and uses the existing sibling `.tmp/{publish,recovery}` plus `.bak` transaction. Keep the rollback-failure recovery fingerprint and fail-closed residue behavior unchanged.

Compatibility wrapper:

```gdscript
func replace_snapshot(output_dir: String, graphs: Dictionary, manifest: Dictionary) -> Error:
	var artifacts := {}
	for scene_key: String in graphs:
		artifacts[scene_key.replace(".", "_") + ".json"] = graphs[scene_key]
	return replace_artifacts(output_dir, artifacts, manifest)
```

Temporarily update the old CLI preload to the moved writer so the full suite remains green before Task 6 deletes it.

- [ ] **Step 4: Write the import-CLI RED**

The CLI suite copies one or more normalized fixture bundles to a unique `user://` input directory, then asserts dry-run does not write, normal import publishes all artifacts, malformed/empty inputs fail, comments do not affect artifacts, and a failed second import preserves prior bytes.

```gdscript
var dry := cli.run_import(input_dir, output_dir, true)
assert_true(dry["ok"], "manual dry run validates every tracked bundle")
assert_false(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output_dir)), "dry run writes nothing")
var published := cli.run_import(input_dir, output_dir, false)
assert_true(published["ok"], "manual import publishes validated artifacts")
assert_true(FileAccess.file_exists(output_dir.path_join("events.json")), "runtime event index is published")
```

- [ ] **Step 5: Implement a credential-free directory importer and Korean result formatting**

Load sorted `.json` files from `input_dir`; reject an empty directory, non-dictionary root, duplicate bundle key, or any invalid bundle. Compile all tracked bundles as one transaction. Do not read environment variables or contact Notion.

```gdscript
static func run_import(input_dir: String, output_dir: String, dry_run: bool, allow_warnings := false) -> Dictionary:
	var loaded := _load_bundles(input_dir)
	if not loaded["ok"]:
		return loaded
	var compiled := DocumentDialogueCompiler.compile_bundles(loaded["bundles"])
	if not compiled["ok"] or dry_run:
		return compiled
	if _has_warnings(compiled["issues"]) and not allow_warnings:
		return _warning_confirmation_failure(compiled)
	var writer := DialogueSnapshotWriter.new()
	var error := writer.replace_artifacts(output_dir, compiled["artifacts"], compiled["manifest"])
	return _publish_result(compiled, writer, error)
```

Output Korean summary lines with bundle/event/flow/line/choice counts, artifact manifest SHA-256, warnings, errors, and source URLs. Never echo whole source documents or comment bodies. A dry-run with warnings succeeds and prints them; a real publish with warnings returns `warning_confirmation_required` without writing unless the user explicitly passes `--allow-warnings`. `_run()` must expose `_get_arguments()` and `_terminate(code)` seams; the harness verifies process exit 0 on success and 1 on errors or unconfirmed warnings.

- [ ] **Step 6: Run writer, CLI, and full GREEN verification**

Run:

```powershell
pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter snapshot_writer
pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter dialogue_import_cli
pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd
```

Expected: all commands exit 0; atomic failure cases leave exact prior hashes and no unclassified temporary residue.

- [ ] **Step 7: Commit Task 5**

```powershell
git add tools/dialogue_import/dialogue_snapshot_writer.gd* tools/dialogue_import/dialogue_import_cli.gd* tools/notion_sync/notion_sync_cli.gd tests/support/dialogue_import_cli_harness.gd* tests/integration/dialogue_import
git add -u tools/notion_sync/dialogue_snapshot_writer.gd tests/integration/test_snapshot_writer.gd
git commit -m "feat: publish manual dialogue imports"
```

---

### Task 6: Migrate the Sample, Remove Live Sync, and Replace the Writer Guide

**Files:**
- Create: `data/dialogues/authoring/foundation_inspect.json`
- Modify: `content/interactables/sample_inspectable.tscn`
- Modify: `docs/dialogue-authoring-guide.md`
- Modify: `project.godot`
- Regenerate: `data/generated/dialogues/foundation_inspect.json`
- Create: `data/generated/dialogues/events.json`
- Create: `data/generated/dialogues/source_map.json`
- Regenerate: `data/generated/dialogues/manifest.json`
- Modify: `tests/integration/test_dialogue_interaction.gd`
- Create: `tests/integration/dialogue_import/test_document_authoring_flow.gd`
- Create: `tests/integration/dialogue_import/test_document_authoring_flow.gd.uid`
- Remove: remaining files under `tools/notion_sync/`
- Remove: remaining files under `tests/unit/notion_sync/`
- Remove: `tests/fixtures/notion/`
- Remove: `tests/support/notion_sync_cli_harness.gd` and UID
- Remove: `tests/integration/test_notion_sync_editor_plugin.gd` and UID

**Interfaces:**
- Production interaction payload becomes `{"dialogue_bundle_key": &"foundation.inspect", "dialogue_trigger_key": &"mirror.inspect"}`.
- Production import command becomes `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tools/dialogue_import/dialogue_import_cli.gd`.
- The old token, three data-source IDs, editor dock, and direct `scene_key` authoring payload are no longer production interfaces.

- [ ] **Step 1: Write the migration RED**

Create the production authoring fixture from the document model and update integration expectations before changing production payload/plugin registration. The test must assert:

```gdscript
assert_eq(target.payload.get("dialogue_bundle_key"), &"foundation.inspect", "mirror uses a document bundle")
assert_eq(target.payload.get("dialogue_trigger_key"), &"mirror.inspect", "mirror uses a trigger key")
assert_false(target.payload.has("scene_key"), "legacy direct scene payload is removed")
assert_false(ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray()).has("res://tools/notion_sync/plugin.cfg"), "live sync plugin is disabled")
```

The new end-to-end suite copies the tracked authoring directory, dry-runs, publishes to unique `user://`, loads the graph/event index from that output, resolves the fallback, drives line → choice → later lines → second choice → rejoin → end, then resolves the now-specific event using the resulting `NarrativeState`.

- [ ] **Step 2: Run the migration RED**

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter document_authoring_flow`

Expected: normal exit 1 because the production authoring fixture, payload, and generated event index do not exist.

- [ ] **Step 3: Add the tracked normalized sample and publish generated artifacts**

The sample must contain:

- Trigger `mirror.inspect` / `거울 조사`.
- First event `seen` conditioned on `mirror_seen == true`.
- Final unconditional `default` event.
- At least two lines before a choice.
- A branch with multiple lines and a second choice.
- One branch that returns to a previous flow.
- Two branches that rejoin.
- A choice result that sets `mirror_seen=true`.
- Comments at page and line level that do not appear in generated artifacts.

Dry-run and publish with:

```powershell
pwsh -File tools/run_godot.ps1 --headless --path . --script res://tools/dialogue_import/dialogue_import_cli.gd -- --dry-run
pwsh -File tools/run_godot.ps1 --headless --path . --script res://tools/dialogue_import/dialogue_import_cli.gd
```

Both commands must exit 0; the second updates all four generated JSON files in one transaction.

- [ ] **Step 4: Switch production interaction and remove temporary legacy routing**

Change `sample_inspectable.tscn` to the new payload. Remove the Task 4 `scene_key` fallback from `DialogueActionAdapter`; malformed, missing, unknown, or no-match bundle/trigger payloads return a non-OK error and never open dialogue.

- [ ] **Step 5: Remove the obsolete live-sync implementation and tests**

Delete the listed Notion transport/mapper/compiler/config/dock/plugin/CLI files and their UIDs, old Notion fixtures/tests/harness, and the plugin registration from `project.godot`. Use `git rm` only on the exact listed tracked paths. Do not modify or delete anything in external Notion. Scan tracked files for `PROJECT_A_NOTION_`, `/v1/data_sources/`, `Notion Dialogue Sync`, and `res://tools/notion_sync`; only historical design/plan documentation may retain those strings.

- [ ] **Step 6: Replace the writer-facing guide**

`docs/dialogue-authoring-guide.md` must cover, in Korean:

- One ordinary Notion page per location/story bundle.
- Heading hierarchy `트리거 ·`, `이벤트 ·`, `흐름 ·`.
- Top-to-bottom event priority and optional final `그 외`.
- `캐릭터 [표정]: 대사`, choice arrows, `→ 이벤트 ·`, and `끝`.
- Quote blocks for occurrence/conditions/results, including named choice metadata.
- Native Notion comments for notes/discussion; confirmed rules move into the body.
- Korean-only authoring; no English IDs, order columns, relations, or JSON.
- How to ask Codex/Claude to normalize one edited page and run dry-run.
- Exact/error/proposed mapping behavior and the generated narrative reference.
- Warning review followed by an explicit `--allow-warnings` publish when the user accepts every warning.
- Git review of normalized and generated diffs.
- Recovery rule: errors never replace the known-good runtime snapshot.

Do not mention the old three-database workflow as a current option. State that the old databases remain external read-only references until the user separately chooses to archive or delete them.

- [ ] **Step 7: Run migration, offline boot, editor, and full GREEN verification**

Run:

```powershell
pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter document_authoring_flow
pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter dialogue_interaction
pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd
pwsh -File tools/run_godot.ps1 --headless --path . --editor --quit
pwsh -File tools/run_godot.ps1 --headless --path . --quit-after 3
```

Expected: all exit 0; editor output has no missing tracked UID or plugin error; the game boots with every `PROJECT_A_NOTION_*` variable unset.

- [ ] **Step 8: Commit Task 6**

```powershell
git add data/dialogues content/interactables/sample_inspectable.tscn docs/dialogue-authoring-guide.md project.godot game/interaction/dialogue_action_adapter.gd tests/integration/dialogue_import tests/integration/test_dialogue_interaction.gd
git add -u tools/notion_sync tests/unit/notion_sync tests/fixtures/notion tests/support/notion_sync_cli_harness.gd tests/integration/test_notion_sync_editor_plugin.gd
git commit -m "feat: adopt document-first dialogue authoring"
```

---

## Completion Gate

### Spec coverage matrix

| Approved design requirement | Implemented by |
|---|---|
| One ordinary page per place/story bundle; Korean heading/quote/choice grammar | Tasks 2 and 6 |
| Multiple ordered conditional events plus optional `그 외` | Tasks 2, 3, and 4 |
| Arbitrary-depth dialogue, later choices, loops, rejoin, same-page event transition | Tasks 2, 3, and 6 |
| Native comments as non-authoritative context | Tasks 2, 3, 5, and 6 |
| Catalog-only conditions, results, characters, expressions, triggers, commands | Tasks 1, 2, and 3 |
| Hidden stable IDs that survive Korean title changes | Tasks 2 and 3 |
| User-invoked Codex/Claude normalization with no live sync | Tasks 5 and 6 |
| Korean preview, explicit warning approval, fail-closed ambiguity | Tasks 1, 2, and 5 |
| Atomic all-or-nothing local publication and offline runtime | Tasks 5 and 6 |
| Existing three databases preserved externally; old plugin removed locally | Task 6 and manual acceptance |
| Writer-facing guide, generated reference, and end-to-end validation | Tasks 1 and 6 |

### Automated verification

Run fresh from `D:/Project/project-a-demo`:

```powershell
pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd
pwsh -File tools/run_godot.ps1 --headless --path . --editor --quit
pwsh -File tools/run_godot.ps1 --headless --path . --quit-after 3
git diff --check
git status --short
```

Required results:

- Full suite exits 0 with no assertion or `SCRIPT ERROR` output.
- Editor/class-cache scan exits 0 with no missing tracked script UID or old plugin error.
- Offline game boot exits 0 without Notion credentials.
- `git diff --check` exits 0.
- `git status --short` is empty after the final commit.
- Every tracked `.gd` file has one unique tracked `.gd.uid` sidecar.
- `data/generated/dialogues/manifest.json` hashes match `foundation_inspect.json`, `events.json`, and `source_map.json` byte-for-byte.
- Tracked production code has no `PROJECT_A_NOTION_`, Notion API endpoint, bearer-token handling, or `res://tools/notion_sync` runtime reference.

### Manual authoring acceptance

Create one ordinary Notion page named `장소 대화 템플릿` under the Project A planning area. It contains one sample trigger, a specific event above `그 외`, quote-block conditions/results, `흐름 · 시작`, a choice leading to two flows, one rejoin, `끝`, and native comments attached to a line and choice. Do not create database rows or expose internal keys.

Duplicate the template once and confirm the user/designer can:

1. Write and reorder Korean dialogue as normal paragraphs.
2. Add a later second choice without nested indentation.
3. Add a conditional event above the fallback.
4. Discuss a line through native Notion comments.
5. Ask Codex or Claude to update the normalized bundle without manually editing JSON.
6. Review the dry-run mapping report before publishing.
7. Play the same dialogue offline after credentials and browser access are absent.

Do not alter, archive, or delete the old `Characters`, `Dialogue Scenes`, or `Dialogue Blocks` databases during this acceptance check.
