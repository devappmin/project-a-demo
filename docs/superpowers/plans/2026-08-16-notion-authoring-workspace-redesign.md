# Notion Authoring Workspace Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the old three-database dialogue workspace with two Korean-first authoring databases, migrate the mirror sample into one readable scene document, verify reusable templates, and retire the per-block database safely.

**Architecture:** Keep the existing `Characters` and `Dialogue Scenes` database identities so links and history survive, but rename and simplify their schemas to `캐릭터 설정` and `장소 대화 문서`. Migrate legacy technical property values into collapsed page sections before dropping those properties. Only after content and template verification, move the single-source `Dialogue Blocks` database to Notion trash. Notion remains an authoring surface only; no token, live sync, or runtime dependency returns to the Godot project.

**Tech Stack:** Notion connector for semantic reads/writes, authenticated in-app browser for database-template UI and visual checks, repository Markdown documentation, Git.

## Global Constraints

- Work only in the current Project A Notion `기획안` page and `D:/Project/project-a-demo`; never modify deprecated `D:/Project/project-a`.
- Do not recreate Notion integration tokens, live sync, relation-driven dialogue, per-line pages, order numbers, or JSON authoring fields.
- Preserve all existing character and mirror-dialogue meaning before dropping properties or trashing a database.
- Move `Dialogue Blocks` to Notion trash only after a recorded migration audit passes; do not permanently delete it.
- The active authoring UI must be Korean-first. Internal keys live in the repository and may appear only inside a collapsed legacy reference copied from old data.
- Conditions and results use Notion quote blocks; creative discussion uses Notion comments.
- Use the Notion connector for semantic page/schema mutations. Use the authenticated browser only for template-specific UI that the connector cannot express and for visible acceptance.
- Read `notion://docs/enhanced-markdown-spec` before writing page content.
- Keep external-operation evidence in `.superpowers/sdd/2026-08-16-notion-authoring-workspace/`; do not commit credentials or raw private exports.
- Make repository commits on the current `main`; no branch, worktree, PR, or external Notion API token.

---

### Task 1: Convert `Characters` into `캐릭터 설정`

**Files:**
- Create ignored report: `.superpowers/sdd/2026-08-16-notion-authoring-workspace/task-1-report.md`
- No tracked production-code changes

**Notion entities:**
- Database: `409d6730-2c9b-44e2-8fbc-541b62ec9d75`
- Data source: `collection://627ad240-959e-4a61-9c32-e02a043ad7c6`
- Existing page: `레티`, `3bdc036f-f8fe-810e-99b2-e26c06868c01`

**Interfaces:**
- Produces active properties: `캐릭터 이름` TITLE, `역할` RICH_TEXT, `상태` SELECT(`초안`, `검토`, `확정`), `담당자` PEOPLE.
- Produces database template: `캐릭터 설정 템플릿`.
- Preserves prior `character_key`, `default_expression`, and `expressions` values inside the existing page before removing those schema fields.

- [ ] **Step 1: Capture a read-only preflight record**

Fetch the database, data source, `레티` page, enhanced Markdown specification, and all current rows. Record only entity IDs, property names, row count, and the exact legacy values needed for migration in the ignored Task 1 report. Expected current row count is 1; stop if the database or row count has changed and re-audit scope.

- [ ] **Step 2: Write the migrated `레티` page before schema removal**

Update the existing page body with Korean authoring sections:

```markdown
## 핵심 한 문장

레티의 역할과 핵심 인상을 함께 정리합니다.

## 성격과 욕망

- 아직 합의되지 않은 내용은 비워 두고 댓글로 논의합니다.

## 말투와 자주 쓰는 표현

- 실제 대사에서 확인된 말투를 기록합니다.

## 다른 인물과의 관계

- 관계가 확정되면 인물 이름과 현재 관계를 기록합니다.

## 표정과 감정 표현

- 무표정: 평온하거나 감정 변화가 크지 않은 기본 표정
- 불안: 걱정하거나 당황한 표정

## 이야기에서의 역할

- 주요 사건과 변화가 합의되면 기록합니다.

<details>
<summary>이전 구조 참고</summary>

- character_key: retti
- default_expression: neutral
- expressions: neutral, uneasy

</details>
```

Do not invent personality or plot facts that were not present in the old data.

- [ ] **Step 3: Verify content preservation**

Fetch the page again and assert the three legacy values and both Korean expression descriptions are present before any column is removed.

- [ ] **Step 4: Change the active schema**

Use `notion_update_data_source` to rename the data source to `캐릭터 설정`, rename `Name` to `캐릭터 이름`, add `역할`, `상태`, and `담당자`, then remove `character_key`, `default_expression`, and `expressions` only after Step 3 passes. Use Korean select options with gray/yellow/green colors.

- [ ] **Step 5: Create the real database template in the authenticated browser**

Open the renamed database, choose the database template menu, create `캐릭터 설정 템플릿`, and insert the same six Korean sections without the legacy details block. Set the template default `상태` to `초안` if the UI supports it without affecting existing rows.

- [ ] **Step 6: Prove template duplication**

Create `템플릿 복제 검증 · 캐릭터` from the actual template. Fetch it through the connector and verify all six headings and `상태=초안`. Move only this verification page to trash through the UI. Record its page ID and successful cleanup in the ignored report.

- [ ] **Step 7: Verify Task 1**

Fetch the database and assert exactly the four active property names, the `캐릭터 설정 템플릿` entry, the preserved `레티` row, and no legacy technical property in the active schema.

---

### Task 2: Convert `Dialogue Scenes` into `장소 대화 문서`

**Files:**
- Create ignored report: `.superpowers/sdd/2026-08-16-notion-authoring-workspace/task-2-report.md`
- No tracked production-code changes

**Notion entities:**
- Database: `ac3c223e-d1d9-4b5b-b464-fbd77f999635`
- Data source: `collection://aef7c938-abc2-4898-a3b9-021886eebc76`
- Existing scene: `거울 조사`, `3bdc036f-f8fe-8168-8344-d538aa3d3504`
- Existing template: `새 페이지`, `3bec036f-f8fe-8056-8fe8-f87ad751305e`
- Source blocks: data source `collection://90a4e9dc-fff5-4aaa-a593-ff2feb7ca1dc`

**Interfaces:**
- Produces active properties: `장소·장면` TITLE, `장소 태그` SELECT, `상태` SELECT(`초안`, `검토`, `확정`), `담당자` PEOPLE.
- Produces reusable template: `장소 대화 템플릿`.
- Produces one readable `거울 조사` page containing every old dialogue block.

- [ ] **Step 1: Capture every legacy mirror block**

Query all six `Dialogue Blocks` rows related to `거울 조사`, including `Text`, `type`, `flow`, `order`, `speaker`, `expression`, `target_flow`, `conditions_json`, `effects_json`, `command_json`, and `notes`. Fetch each source page if a queried property is incomplete. Record a six-row semantic inventory in the ignored report; stop if the count or relation target differs.

- [ ] **Step 2: Draft the one-page mirror migration**

Translate the six rows into the approved heading hierarchy without inventing dialogue. Preserve line order, speaker, Korean expression name, choice destinations, the mirror-seen effect timing, and `끝`. Use a quote block for the effect/condition metadata. Include a collapsed `이전 구조 참고` section containing the old `scene_key=foundation.inspect` and `start_flow=main` before those columns are removed.

- [ ] **Step 3: Replace the existing `거울 조사` body and verify semantics**

Update the existing scene page rather than creating another scene row. Fetch it afterward and assert all six source texts or their exact structural equivalents, both choices, both registered expression meanings, the result, every destination, and `끝` are present. The page must contain `트리거 ·`, `이벤트 ·`, and `흐름 · 시작` headings.

- [ ] **Step 4: Change the active scene schema**

Rename the data source to `장소 대화 문서`; rename `Name`→`장소·장면`, `location`→`장소 태그`, `owner`→`담당자`, and `status`→`상태`. Replace the status options with `초안`, `검토`, `확정`, preserving the existing row as `확정`. Remove `scene_key` and `start_flow` only after Step 3 succeeds.

- [ ] **Step 5: Replace the old blank template**

In the authenticated browser, rename the existing `새 페이지` template to `장소 대화 템플릿` and install the approved body:

```text
장소 개요
트리거 · 장소 입장
이벤트 · 특정 조건 충족
인용 블록: 발생 / 조건 / 결과
흐름 · 시작
대사
첫 선택지 → 두 흐름
한 흐름의 후속 대사와 두 번째 선택
다른 흐름
합류 흐름
끝
이벤트 · 그 외
흐름 · 시작
끝
```

Use real Notion headings, quote blocks, bullets, and ordinary paragraphs. Add a short top callout explaining the hierarchy and that discussion belongs in comments. Do not include English IDs or JSON.

- [ ] **Step 6: Prove template duplication and cleanup**

Create `템플릿 복제 검증 · 장소` from the actual template. Fetch it and verify the callout, heading hierarchy, quote metadata, first choice, later choice, rejoin, fallback event, and `상태=초안`. Move only the verification page to trash after the check.

- [ ] **Step 7: Verify Task 2**

Fetch the data source, template, and `거울 조사`. Assert exactly four active properties, one production scene row, one reusable template, no old technical fields, and no English IDs/JSON in the template body.

---

### Task 3: Retire `Dialogue Blocks` and clean the `기획안` page

**Files:**
- Create ignored report: `.superpowers/sdd/2026-08-16-notion-authoring-workspace/task-3-report.md`
- No tracked production-code changes

**Notion entities:**
- Legacy database: `5463da1e-e618-449e-b91f-07a9eeb43c3f`
- Legacy data source: `collection://90a4e9dc-fff5-4aaa-a593-ff2feb7ca1dc`
- Parent page: `기획안`, `2c9c036f-f8fe-8069-83dc-d92c5c31cb9c`

- [ ] **Step 1: Run the destructive-action preflight**

Re-query the legacy block data source and compare all rows with the Task 2 semantic inventory and migrated `거울 조사` page. Confirm the active scene page and both reusable templates remain accessible. Record the exact database/data-source IDs and `6/6 migrated` in the report.

- [ ] **Step 2: Move the legacy database to trash**

After Step 1 passes, call `notion_update_data_source` with `in_trash: true` for the exact legacy data source. This is the only destructive operation. Do not trash the parent page, either active database, their templates, or any production row.

- [ ] **Step 3: Verify recoverable retirement**

Refresh the `기획안` page in the browser and verify `Dialogue Blocks` is absent from the active workspace. Open Notion Trash and confirm the database title is present and restorable; do not permanently delete it.

- [ ] **Step 4: Clean the parent page presentation**

Ensure the `기획안` page visibly presents only `캐릭터 설정` and `장소 대화 문서` as active authoring databases, with one short Korean paragraph explaining that dialogue is written per location page. Preserve unrelated planning content and child pages.

- [ ] **Step 5: Verify Task 3**

Fetch/search the parent and both active databases. Assert active titles, templates, production rows, and absence of the block database from the active page. Record that Trash—not permanent deletion—contains the retired database.

---

### Task 4: Align the Repository Guide and Complete Acceptance

**Files:**
- Modify: `docs/dialogue-authoring-guide.md`
- Create ignored report: `.superpowers/sdd/2026-08-16-notion-authoring-workspace/final-report.md`

**Interfaces:**
- Consumes the verified external Notion layout from Tasks 1–3.
- Produces repository guidance matching the active two-database workspace.

- [ ] **Step 1: Write the failing documentation contract check**

Run:

```powershell
rg -n "기존 `Characters`, `Dialogue Scenes`, `Dialogue Blocks`|현행 작업 공간이 아닙니다|데이터베이스를 수정.*않습니다" docs/dialogue-authoring-guide.md
```

Expected: the command finds the obsolete read-only three-database guidance.

- [ ] **Step 2: Update the guide**

Replace the obsolete `기존 데이터베이스의 상태` section with an `현재 Notion 작업 공간` section that documents:

- `캐릭터 설정`: one Korean prose page per character
- `장소 대화 문서`: one page per location or tightly coupled story bundle
- `장소 대화 템플릿` duplication as the starting point
- no `Dialogue Blocks`, relations, order numbers, English IDs, JSON, token, or live sync
- Notion comments are discussion only; agreed rules move into body/quote blocks
- Codex/Claude normalization and existing manual dry-run/publish commands

- [ ] **Step 3: Run documentation and repository checks**

Run:

```powershell
rg -n "캐릭터 설정|장소 대화 문서|장소 대화 템플릿" docs/dialogue-authoring-guide.md
rg -n "PROJECT_A_NOTION|tools/notion_sync|Dialogue Blocks에서 수정|conditions_json|effects_json|command_json" docs game app tools data project.godot
git diff --check
```

Expected: active workspace terms are present; no live-sync/runtime legacy reference is reintroduced; `git diff --check` exits 0. Historical plans/specs may mention the retired architecture and must not be rewritten as runtime instructions.

- [ ] **Step 4: Perform visible end-to-end acceptance**

In the authenticated browser:

1. Open `기획안` and enter both active databases.
2. Create one temporary page from each template.
3. Confirm the designer-facing fields and body are Korean and require no internal key.
4. Confirm `거울 조사` is readable without opening a second database.
5. Confirm `Dialogue Blocks` is only in Trash and is restorable.
6. Trash both temporary verification pages.

Capture screenshots or a concise evidence record under the ignored SDD workspace; do not commit private browser captures unless explicitly approved.

- [ ] **Step 5: Commit the repository guide**

```powershell
git add -- docs/dialogue-authoring-guide.md
git diff --cached --check
git commit -m "docs: align Notion dialogue workspace"
git status --short
```

Expected: semantic commit succeeds and tracked status is clean.

- [ ] **Step 6: Final verification and handoff**

Fetch both active databases and production pages one final time. Record exact active schema, template names, row names, trash disposition, repository commit, and any Notion UI limitation in `final-report.md`. The next independent project is revising `2026-08-09-04-world-save-vertical-slice.md` against the document-first runtime; do not implement Plan 4 inside this migration plan.
