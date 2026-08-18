from __future__ import annotations

import re
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
HANDOFF_FILES = (
    Path("README.md"),
    Path("docs/PROJECT_STATUS.md"),
    Path("docs/ROADMAP.md"),
    Path("docs/ARCHITECTURE.md"),
)


class HandoffDocumentTests(unittest.TestCase):
    def test_required_handoff_documents_exist(self):
        for relative in HANDOFF_FILES:
            with self.subTest(path=relative):
                self.assertTrue((REPO_ROOT / relative).is_file())

    def test_readme_links_resolve(self):
        readme = (REPO_ROOT / "README.md").read_text(encoding="utf-8")
        relative_links = re.findall(r"\[[^]]+\]\((?!https?://|#)([^)]+)\)", readme)
        self.assertGreaterEqual(len(relative_links), 4)
        for target in relative_links:
            with self.subTest(target=target):
                self.assertTrue((REPO_ROOT / target).exists())

    def test_status_separates_complete_and_missing_capabilities(self):
        status = (REPO_ROOT / "docs/PROJECT_STATUS.md").read_text(encoding="utf-8")
        self.assertIn("## 현재 플레이 가능 범위", status)
        self.assertIn("## 구현 완료", status)
        self.assertIn("## 아직 구현되지 않음", status)
        self.assertIn("실제 키보드", status)
        self.assertIn("인벤토리", status)

    def test_roadmap_names_the_next_conditional_gameplay_milestone(self):
        roadmap = (REPO_ROOT / "docs/ROADMAP.md").read_text(encoding="utf-8")
        self.assertIn("조건 분기 플레이 기반", roadmap)
        self.assertIn("젤리뽀의 집 플레이어블 시나리오", roadmap)
        self.assertLess(roadmap.index("조건 분기 플레이 기반"), roadmap.index("젤리뽀의 집 플레이어블 시나리오"))

    def test_handoff_docs_do_not_embed_machine_paths_or_secrets(self):
        forbidden = (r"[A-Za-z]:\\", r"/Users/", r"/home/", r"PROJECT_A_NOTION_TOKEN=")
        for relative in HANDOFF_FILES:
            text = (REPO_ROOT / relative).read_text(encoding="utf-8")
            for pattern in forbidden:
                with self.subTest(path=relative, pattern=pattern):
                    self.assertIsNone(re.search(pattern, text))

    def test_gitignore_ignores_python_bytecode_caches_repository_wide(self):
        gitignore = (REPO_ROOT / ".gitignore").read_text(encoding="utf-8")
        self.assertIn("__pycache__/", gitignore.splitlines())

    def test_readme_covers_new_computer_setup_without_machine_specific_paths(self):
        readme = (REPO_ROOT / "README.md").read_text(encoding="utf-8")
        for required in ("Git", "clone", "project-a-demo", "PROJECT_A_GODOT_BIN", "project.godot"):
            with self.subTest(required=required):
                self.assertIn(required, readme)
        self.assertNotIn("<repository-url>", readme)
