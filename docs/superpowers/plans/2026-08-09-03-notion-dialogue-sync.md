# Notion Dialogue Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the two-person team a readable Notion scene-page workflow that compiles validated dialogue snapshots into the existing Godot runtime without runtime network access.

**Architecture:** Three Notion data sources hold scenes, ordered dialogue blocks, and character-facing expression catalogs. An editor-only transport queries those sources with Notion API `2026-03-11`, a pure mapper converts API pages into the Plan 2 graph schema, and an atomic compiler replaces generated JSON only when the entire import succeeds.

**Tech Stack:** Godot 4.7 editor plugin, GDScript 2.0, `HTTPRequest`, Notion REST API `2026-03-11`, data-source query endpoint, project-local headless tests.

## Global Constraints

- Complete Plans 1 and 2 first.
- Notion is the collaborative source; generated JSON in Git is the runtime source.
- Never commit `PROJECT_A_NOTION_TOKEN` or data-source IDs in a tracked file.
- Read Notion only from the editor/plugin or explicit headless sync command, never from gameplay or export runtime.
- Use `Authorization: Bearer <token>`, `Notion-Version: 2026-03-11`, and `Content-Type: application/json`.
- Query `/v1/data_sources/{data_source_id}/query` with pagination and explicit `order` sorting; never rely on unspecified API order.
- A failed import must leave the previous `data/generated/dialogues` directory byte-for-byte intact.
- Use tabs for GDScript indentation and follow TDD.

Official references:

- [Notion authentication](https://developers.notion.com/reference/authentication)
- [Query a data source](https://developers.notion.com/reference/query-a-data-source)
- [Notion API changes by version](https://developers.notion.com/reference/changes-by-version)

---

## File Map

- `tools/notion_sync/notion_schema.gd`: exact source property names and accepted enum values.
- `tools/notion_sync/notion_property_reader.gd`: safe title, rich text, number, select, multi-select, and relation extraction.
- `tools/notion_sync/notion_mapper.gd`: maps API pages to scene, block, and character dictionaries.
- `tools/notion_sync/notion_transport.gd`: authenticated, paginated data-source reads.
- `tools/notion_sync/notion_sync_config.gd`: reads four task-specific environment variables.
- `tools/notion_sync/dialogue_compiler.gd`: grouping, validation, and graph JSON generation.
- `tools/notion_sync/dialogue_snapshot_writer.gd`: temporary output, verification, backup, and atomic replacement.
- `tools/notion_sync/notion_sync_cli.gd`: headless sync entrypoint.
- `tools/notion_sync/plugin.cfg`, `plugin.gd`, `notion_sync_dock.tscn`, `notion_sync_dock.gd`: editor button and diagnostics.
- `tests/fixtures/notion/*.json`: redacted Notion response fixtures.
- `tests/fixtures/notion/notion_fixture_factory.gd`: reusable mapped-model fixture for compiler tests.
- `docs/dialogue-authoring-guide.md`: writer-facing Notion workflow.

### Task 1: Pure Notion Property Reader and Mapper

**Files:**
- Create: `tools/notion_sync/notion_schema.gd`
- Create: `tools/notion_sync/notion_property_reader.gd`
- Create: `tools/notion_sync/notion_mapper.gd`
- Create: `tests/fixtures/notion/scenes_page.json`
- Create: `tests/fixtures/notion/blocks_page.json`
- Create: `tests/fixtures/notion/characters_page.json`
- Create: `tests/fixtures/notion/notion_fixture_factory.gd`
- Create: `tests/unit/notion_sync/test_notion_mapper.gd`

**Interfaces:**
- Produces: `NotionMapper.map_scene(page: Dictionary) -> Dictionary`.
- Produces: `NotionMapper.map_block(page: Dictionary) -> Dictionary`.
- Produces: `NotionMapper.map_character(page: Dictionary) -> Dictionary`.
- Every mapped dictionary includes `notion_page_id` and `source_url` for diagnostics.

- [ ] **Step 1: Write failing mapper tests**

```gdscript
extends "res://tests/support/test_case.gd"

func run() -> void:
	var scene_page := JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/notion/scenes_page.json"))
	var scene := NotionMapper.map_scene(scene_page)
	assert_eq(scene["scene_key"], "foundation.inspect", "scene key maps")
	assert_eq(scene["status"], "Final", "status maps")
	var block_page := JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/notion/blocks_page.json"))
	var block := NotionMapper.map_block(block_page)
	assert_eq(block["node_id"], block_page["id"].replace("-", ""), "Notion page ID is the stable node ID")
	assert_eq(block["speaker"], "retti", "speaker relation maps to character key")
```

- [ ] **Step 2: Run and verify failure**

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter notion_mapper`

Expected: FAIL because mapper classes do not exist.

- [ ] **Step 3: Implement exact schema constants and safe property reads**

```gdscript
extends RefCounted
class_name NotionSchema

const SCENE_PROPERTIES := {"name":"Name", "scene_key":"scene_key", "location":"location", "status":"status", "start_flow":"start_flow"}
const BLOCK_PROPERTIES := {"text":"Text", "scene":"scene", "flow":"flow", "order":"order", "type":"type", "speaker":"speaker", "expression":"expression", "target_flow":"target_flow", "conditions":"conditions_json", "effects":"effects_json", "command":"command_json", "notes":"notes"}
const CHARACTER_PROPERTIES := {"name":"Name", "character_key":"character_key", "default_expression":"default_expression", "expressions":"expressions"}
const SCENE_STATUSES := ["Draft", "Review", "Final"]
const BLOCK_TYPES := ["line", "choice", "effect", "command", "jump", "end"]
```

`NotionPropertyReader` returns `Result` dictionaries shaped as `{"ok":bool,"value":Variant,"message":String}`; it must distinguish a missing property from an empty optional value. Parse hidden JSON fields with `JSON.parse_string()` and report the property name on invalid JSON. Map relation IDs through the character and scene lookup passed to `NotionMapper`; do not assume relation display text is present.

Create the mapped-model fixture used by Task 3:

```gdscript
extends RefCounted
class_name NotionFixtureFactory

static func valid_dialogue_input() -> Dictionary:
	return {
		"scenes": [{"scene_key":"foundation.inspect", "status":"Final", "start_flow":"main", "notion_page_id":"scene1", "source_url":"https://notion.so/scene1"}],
		"blocks": [
			{"notion_page_id":"line1", "source_url":"https://notion.so/line1", "scene_key":"foundation.inspect", "flow":"main", "order":1.0, "type":"line", "speaker":"retti", "expression":"uneasy", "text":"낯선 거울이다.", "target_flow":"choice", "conditions":[], "effects":[], "command":{}},
			{"notion_page_id":"choice1", "source_url":"https://notion.so/choice1", "scene_key":"foundation.inspect", "flow":"choice", "order":1.0, "type":"choice", "speaker":"", "expression":"", "text":"자세히 본다", "target_flow":"end", "conditions":[], "effects":[{"kind":"flag_set", "key":"mirror_seen", "value":true}], "command":{}},
			{"notion_page_id":"end1", "source_url":"https://notion.so/end1", "scene_key":"foundation.inspect", "flow":"end", "order":1.0, "type":"end", "speaker":"", "expression":"", "text":"", "target_flow":"", "conditions":[], "effects":[], "command":{}}
		],
		"characters": [{"character_key":"retti", "default_expression":"neutral", "expressions":["neutral", "uneasy"], "notion_page_id":"char1", "source_url":"https://notion.so/char1"}]
	}
```

- [ ] **Step 4: Run focused and full tests**

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter notion_mapper`

Expected: PASS.

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd`

Expected: all tests PASS and fixtures contain no live workspace token.

- [ ] **Step 5: Commit**

```bash
git add tools/notion_sync tests/fixtures/notion tests/unit/notion_sync
git commit -m "feat: map Notion dialogue properties"
```

### Task 2: Authenticated Paginated Notion Transport

**Files:**
- Create: `tools/notion_sync/notion_sync_config.gd`
- Create: `tools/notion_sync/notion_transport.gd`
- Create: `tests/unit/notion_sync/test_notion_sync_config.gd`
- Create: `tests/unit/notion_sync/test_notion_transport.gd`
- Modify: `.gitignore`

**Interfaces:**
- Produces: `NotionSyncConfig.from_environment() -> Dictionary` with `ok`, `token`, `scenes_data_source`, `blocks_data_source`, `characters_data_source`, and `message`.
- Produces async: `NotionTransport.query_all(data_source_id: String, sorts: Array[Dictionary]) -> Dictionary` with `ok`, `pages`, `status_code`, and `message`.
- Produces: `NotionTransport.build_query_body(sorts: Array[Dictionary], cursor := "") -> Dictionary` for deterministic pagination tests.

- [ ] **Step 1: Write failing configuration tests**

```gdscript
extends "res://tests/support/test_case.gd"

func run() -> void:
	var result := NotionSyncConfig.validate_values({"token":"", "scenes_data_source":"a", "blocks_data_source":"b", "characters_data_source":"c"})
	assert_false(result["ok"], "empty token is rejected")
	assert_true(String(result["message"]).contains("PROJECT_A_NOTION_TOKEN"), "error names the missing variable")
	var body := NotionTransport.build_query_body([{"property":"order", "direction":"ascending"}], "cursor-1")
	assert_eq(body["page_size"], 100, "query uses maximum page size")
	assert_eq(body["start_cursor"], "cursor-1", "next request carries cursor")
	assert_eq(body["sorts"][0]["property"], "order", "explicit order sort is retained")
```

- [ ] **Step 2: Run and verify failure**

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter notion_sync`

Expected: FAIL because the config class does not exist.

- [ ] **Step 3: Implement environment validation and paginated POST requests**

```gdscript
const API_VERSION := "2026-03-11"
const API_ROOT := "https://api.notion.com/v1/data_sources/"

func _headers(token: String) -> PackedStringArray:
	return PackedStringArray([
		"Authorization: Bearer " + token,
		"Notion-Version: " + API_VERSION,
		"Content-Type: application/json"
	])
```

Read `PROJECT_A_NOTION_TOKEN`, `PROJECT_A_NOTION_SCENES_DATA_SOURCE`, `PROJECT_A_NOTION_BLOCKS_DATA_SOURCE`, and `PROJECT_A_NOTION_CHARACTERS_DATA_SOURCE`. `query_all()` sends `POST <API_ROOT><id>/query` with `page_size:100`, supplied sorts, and `start_cursor` until `has_more` is false. Return actionable messages for 401, 403, 404, 429, 5xx, malformed JSON, and missing relation sharing. Never log headers or token values. Add `/tools/notion_sync/*.local.cfg` to `.gitignore` as defense in depth.

- [ ] **Step 4: Run deterministic transport tests**

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter notion_sync`

Expected: PASS.

Run the transport suite with recorded HTTP responses for two pages, 401, 429, and malformed JSON. Assert that pagination stops when `has_more=false`, preserves explicit sorts, and no failure message contains the configured token. The first live `--dry-run` is deferred to Task 4 because its data sources do not exist yet.

- [ ] **Step 5: Commit**

```bash
git add tools/notion_sync tests/unit/notion_sync .gitignore
git commit -m "feat: add secure Notion data transport"
```

### Task 3: Dialogue Compiler and Atomic Snapshot Writer

**Files:**
- Create: `tools/notion_sync/dialogue_compiler.gd`
- Create: `tools/notion_sync/dialogue_snapshot_writer.gd`
- Create: `tools/notion_sync/notion_sync_cli.gd`
- Create: `tests/unit/notion_sync/test_dialogue_compiler.gd`
- Create: `tests/integration/test_snapshot_writer.gd`

**Interfaces:**
- Consumes: mapped scenes, blocks, characters and `DialogueGraphValidator.validate()`.
- Produces: `DialogueCompiler.compile(input: Dictionary) -> Dictionary` with `ok`, `graphs`, `issues`, and `manifest`.
- Produces: `DialogueSnapshotWriter.replace_snapshot(output_dir: String, graphs: Dictionary, manifest: Dictionary) -> Error`.

- [ ] **Step 1: Write failing compiler and preservation tests**

```gdscript
extends "res://tests/support/test_case.gd"

func run() -> void:
	var input := NotionFixtureFactory.valid_dialogue_input()
	var result := DialogueCompiler.compile(input)
	assert_true(result["ok"], "valid Notion model compiles")
	assert_true(result["graphs"].has("foundation.inspect"), "scene graph emitted")
	input["blocks"][0]["expression"] = "missing_expression"
	var broken := DialogueCompiler.compile(input)
	assert_false(broken["ok"], "invalid expression blocks replacement")
	assert_eq(broken["issues"][0]["source_url"], input["blocks"][0]["source_url"], "issue links to source")
```

- [ ] **Step 2: Run and verify failure**

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter dialogue_compiler`

Expected: FAIL because compiler and fixture factory do not exist.

- [ ] **Step 3: Implement deterministic compile and replace**

```gdscript
func scene_filename(scene_key: String) -> String:
	return scene_key.replace(".", "_") + ".json"

func stable_json(data: Variant) -> String:
	return JSON.stringify(data, "\t", true, true)
```

Sort scenes by `scene_key`, blocks by `flow`, `order`, then `notion_page_id`. Resolve flow targets to first node IDs. Draft scenes may retain warnings; any issue with severity `error`, or any warning in a Final scene, sets `ok=false`. Manifest contains schema version 1, UTC generation time, source page IDs/URLs, SHA-256 of each output, and sorted scene keys.

Writer creates sibling `<output>.tmp`, writes and rereads every JSON file, validates hashes, renames current output to `<output>.bak`, renames temp to output, then deletes backup only after success. On any error, remove only the temp directory and keep the current output and backup. Tests must use `user://test-output/<unique-id>` and clean only that exact directory.

- [ ] **Step 4: Run focused and full tests**

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd -- --filter notion_sync`

Expected: PASS, including a simulated write failure that preserves the prior snapshot.

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd`

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add tools/notion_sync tests/unit/notion_sync tests/integration
git commit -m "feat: compile atomic dialogue snapshots"
```

### Task 4: Provision Authoring Databases, Editor Dock, and Writer Guide

**Files:**
- Create: `tools/notion_sync/plugin.cfg`
- Create: `tools/notion_sync/plugin.gd`
- Create: `tools/notion_sync/notion_sync_dock.gd`
- Create: `tools/notion_sync/notion_sync_dock.tscn`
- Create: `docs/dialogue-authoring-guide.md`
- Modify: `project.godot`
- External: create `Dialogue Scenes`, `Dialogue Blocks`, and `Characters` data sources under the Project A planning area in Notion.

**Interfaces:**
- Consumes: `DialogueCompiler`, `DialogueSnapshotWriter`, `NotionTransport`, and four environment variables.
- Produces: one `Sync Dialogues` editor action and a diagnostics list whose rows open `source_url`.

- [ ] **Step 1: Create the exact Notion schemas and one approved sample**

Use these exact properties:

```text
Dialogue Scenes: Name(title), scene_key(rich_text), location(select), status(select: Draft|Review|Final), start_flow(rich_text), owner(people)
Dialogue Blocks: Text(title), scene(relation), flow(rich_text), order(number), type(select: line|choice|effect|command|jump|end), speaker(relation), expression(select), target_flow(rich_text), conditions_json(rich_text), effects_json(rich_text), command_json(rich_text), notes(rich_text)
Characters: Name(title), character_key(rich_text), default_expression(select), expressions(multi_select)
```

Create `foundation.inspect` with a main flow, two lines, one two-option choice, one `flag_set mirror_seen=true` effect, and an end node. Create a scene template whose linked blocks view is filtered to the current scene, grouped by `flow`, sorted by `order` ascending, and hides all logic JSON properties in the writer view.

- [ ] **Step 2: Write a failing editor-plugin load check**

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --editor --quit-after 3`

Expected before implementation: plugin is absent from `editor_plugins/enabled` and no dock registers.

- [ ] **Step 3: Implement the dock and exact writer guide**

```gdscript
@tool
extends EditorPlugin

var dock: Control

func _enter_tree() -> void:
	dock = preload("res://tools/notion_sync/notion_sync_dock.tscn").instantiate()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)

func _exit_tree() -> void:
	remove_control_from_docks(dock)
	dock.queue_free()
```

The dock has `Sync Dialogues`, `Dry Run`, status text, page counts, and an issue list. Disable buttons while a request is active. A successful sync calls `EditorFileSystem.scan_sources()` and displays generated scene count and manifest hash. The guide must show how to add/reorder a line, make a choice flow, select an allowed expression, leave logic notes for the developer, change Draft→Review→Final, run sync, and resolve each validator code.

- [ ] **Step 4: Verify real sync, offline runtime, and docs**

Run with environment variables: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tools/notion_sync/notion_sync_cli.gd -- --dry-run`

Expected: prints redacted page counts and validation diagnostics without replacing `data/generated/dialogues`; output contains no bearer token.

Run with environment variables: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tools/notion_sync/notion_sync_cli.gd`

Expected: exits 0, replaces the local fixture with Notion-generated `foundation_inspect.json`, and writes a manifest containing the source page URL.

Unset `PROJECT_A_NOTION_TOKEN`, then run: `pwsh -File tools/run_godot.ps1 --headless --path . --quit-after 3`

Expected: game boots and dialogue remains playable offline.

- [ ] **Step 5: Commit generated snapshot, plugin, and guide**

```bash
git add tools/notion_sync docs/dialogue-authoring-guide.md data/generated/dialogues project.godot
git commit -m "feat: sync readable Notion dialogue scenes"
```

## Plan 3 Completion Gate

Run: `pwsh -File tools/run_godot.ps1 --headless --path . --script res://tests/run_all.gd`

Expected: all tests PASS.

Manual acceptance: the designer can edit the sample dialogue in Notion without repository access; the developer can dry-run, see source-linked errors, sync once, commit deterministic JSON, remove credentials, and play the same dialogue offline.
