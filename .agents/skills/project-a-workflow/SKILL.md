---
name: project-a-workflow
description: Use when working on gameplay, dialogue and branching content, save/map/interaction systems, tests, project verification, milestones, documentation, or handoff in the Project A Godot 4.7 project-a-demo repository. Do not use for the deprecated project-a repository.
---

# Project A Workflow

## Establish context

1. Read `docs/PROJECT_STATUS.md` and `docs/ROADMAP.md` completely.
2. Inspect `git status --short`; preserve unrelated user changes.
3. Confirm the task targets `project-a-demo`, never deprecated `project-a`.

## Load only relevant detail

- For runtime or architecture work, read `docs/ARCHITECTURE.md` and the related tests.
- For dialogue or branching content, also read `docs/dialogue-authoring-guide.md` and `docs/narrative-state-reference.md`.
- For a previously approved feature, read its current spec and implementation plan linked from the task or roadmap.
- Treat historical `docs/superpowers/specs` and `plans` as decision records, not current status.

## Work

1. Follow `AGENTS.md`.
2. Design before creative implementation and use tests first for code changes.
3. Keep runtime behavior offline and independent of Notion credentials or network access.
4. Preserve writer-facing Korean terminology and keep internal keys out of authoring prose.
5. Commit meaningful units directly on `main` unless the user requests another workflow.

## Verify and hand off

1. For Godot code or scenes, run the narrowest `python tools/project.py test --filter ...`: use `dialogue` for dialogue work and `save_` for save work.
2. For Python tooling or documentation, run the relevant `python -m unittest tests/python/test_file.py -v` module instead of a Godot filter.
3. Run `python tools/project.py check` before claiming completion.
4. Update the tracked source that owns any changed fact: status, roadmap, architecture, or authoring guide.
5. Report the commit, verification result, and any manual acceptance still required.
