from __future__ import annotations

import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]


class AgentWorkflowTests(unittest.TestCase):
    def test_shared_agent_files_exist(self):
        for relative in ("AGENTS.md", "CLAUDE.md", ".agents/skills/project-a-workflow/SKILL.md", ".agents/skills/project-a-workflow/agents/openai.yaml"):
            with self.subTest(path=relative):
                self.assertTrue((REPO_ROOT / relative).is_file())

    def test_claude_file_is_only_the_agents_import(self):
        text = (REPO_ROOT / "CLAUDE.md").read_text(encoding="utf-8")
        self.assertEqual(text, "@AGENTS.md\n")

    def test_agents_declares_scope_workflow_and_sources(self):
        text = (REPO_ROOT / "AGENTS.md").read_text(encoding="utf-8")
        for required in ("project-a-demo", "project-a", "main", "tools/project.py", "PROJECT_STATUS.md", "ROADMAP.md", "ARCHITECTURE.md", "dialogue-authoring-guide.md"):
            with self.subTest(required=required):
                self.assertIn(required, text)

    def test_agent_rules_distinguish_godot_filters_from_python_tests(self):
        agents = (REPO_ROOT / "AGENTS.md").read_text(encoding="utf-8")
        skill = (REPO_ROOT / ".agents/skills/project-a-workflow/SKILL.md").read_text(encoding="utf-8")
        for text in (agents, skill):
            with self.subTest(source="AGENTS" if text is agents else "skill"):
                self.assertIn("python tools/project.py test --filter", text)
                self.assertIn("python -m unittest", text)
                self.assertIn("Godot", text)
                self.assertIn("Python", text)

    def test_readme_links_the_shared_agent_rules(self):
        text = (REPO_ROOT / "README.md").read_text(encoding="utf-8")
        self.assertIn("(AGENTS.md)", text)

    def test_skill_routes_to_tracked_sources_without_copying_status(self):
        text = (REPO_ROOT / ".agents/skills/project-a-workflow/SKILL.md").read_text(encoding="utf-8")
        self.assertIn("name: project-a-workflow", text)
        self.assertIn("description: Use when", text)
        for required in ("docs/PROJECT_STATUS.md", "docs/ROADMAP.md", "docs/ARCHITECTURE.md", "docs/dialogue-authoring-guide.md", "docs/narrative-state-reference.md", "tools/project.py"):
            with self.subTest(required=required):
                self.assertIn(required, text)
        self.assertNotIn("foundation_room", text)
        self.assertNotIn("자동 저장 1개", text)

    def test_skill_ui_metadata_is_minimal_and_stable(self):
        text = (REPO_ROOT / ".agents/skills/project-a-workflow/agents/openai.yaml").read_text(encoding="utf-8")
        self.assertIn('display_name: "Project A Workflow"', text)
        self.assertIn('short_description: "Work safely in the Project A Godot repository"', text)
        self.assertIn('default_prompt: "Use $project-a-workflow and tracked project documents to complete this task."', text)
        self.assertNotIn("dependencies:", text)
        self.assertNotIn("allow_implicit_invocation:", text)
