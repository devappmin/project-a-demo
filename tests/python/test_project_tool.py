from __future__ import annotations

import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import Mock

REPO_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO_ROOT / "tools" / "project.py"


def load_project_tool():
    spec = importlib.util.spec_from_file_location("project_tool", MODULE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("Cannot load tools/project.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class ProjectToolTests(unittest.TestCase):
    def test_explicit_godot_precedes_environment_and_path(self):
        tool = load_project_tool()
        which = Mock(side_effect=lambda value: {"explicit": "/bin/explicit", "godot": "/bin/path"}.get(value))
        result = tool.resolve_godot("explicit", {"PROJECT_A_GODOT_BIN": "environment"}, which)
        self.assertEqual(result, "/bin/explicit")

    def test_environment_precedes_godot_and_godot4_on_path(self):
        tool = load_project_tool()
        which = Mock(side_effect=lambda value: {"environment": "/bin/environment", "godot": "/bin/godot", "godot4": "/bin/godot4"}.get(value))
        result = tool.resolve_godot(None, {"PROJECT_A_GODOT_BIN": "environment"}, which)
        self.assertEqual(result, "/bin/environment")

    def test_missing_godot_is_a_clear_error(self):
        tool = load_project_tool()
        with self.assertRaisesRegex(tool.ProjectToolError, "Godot 4.7"):
            tool.resolve_godot(None, {}, lambda _value: None)

    def test_version_parser_accepts_47_and_rejects_other_minor(self):
        tool = load_project_tool()
        self.assertEqual(tool.parse_godot_version("4.7.stable.official"), (4, 7))
        with self.assertRaisesRegex(tool.ProjectToolError, "4.7"):
            tool.require_supported_godot("4.8.stable.official")

    def test_zero_exit_with_script_error_is_promoted_to_failure(self):
        tool = load_project_tool()
        runner = Mock(return_value=subprocess.CompletedProcess([], 0, "SCRIPT ERROR: Parse Error\n"))
        result = tool.run_checked("godot", ["--headless"], REPO_ROOT, process_runner=runner)
        self.assertEqual(result.returncode, 1)
        self.assertIn("SCRIPT ERROR", result.reason)

    def test_nonzero_engine_exit_is_preserved(self):
        tool = load_project_tool()
        runner = Mock(return_value=subprocess.CompletedProcess([], 7, "engine failure\n"))
        result = tool.run_checked("godot", ["--headless"], REPO_ROOT, process_runner=runner)
        self.assertEqual(result.returncode, 7)

    def test_test_command_requires_a_nonzero_selected_suite_count(self):
        tool = load_project_tool()
        runner = Mock(return_value=subprocess.CompletedProcess([], 0, "Godot Engine v4.7\n"))
        result = tool.run_checked("godot", [], REPO_ROOT, require_test_selection=True, process_runner=runner)
        self.assertEqual(result.returncode, 1)
        self.assertIn("Selected", result.reason)

    def test_filter_is_after_the_godot_user_argument_separator(self):
        tool = load_project_tool()
        args = tool.test_arguments(REPO_ROOT, "dialogue")
        self.assertEqual(args[-3:], ["--", "--filter", "dialogue"])

    def test_empty_or_missing_class_cache_needs_scan(self):
        tool = load_project_tool()
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            self.assertTrue(tool.needs_class_scan(root))
            cache = root / ".godot" / "global_script_class_cache.cfg"
            cache.parent.mkdir()
            cache.write_text("list=[]\n", encoding="utf-8")
            self.assertTrue(tool.needs_class_scan(root))
            cache.write_text('list=[{ "class": &"FreshBase" }]\n', encoding="utf-8")
            self.assertFalse(tool.needs_class_scan(root))

    def test_real_broken_fixture_is_nonzero_even_when_runner_quits_zero(self):
        tool = load_project_tool()
        godot = os.environ.get("PROJECT_A_TEST_GODOT_BIN")
        if not godot:
            self.skipTest("PROJECT_A_TEST_GODOT_BIN is required for the real Godot fixture")
        fixture = REPO_ROOT / "tests" / "fixtures" / "broken_script_project"
        with tempfile.TemporaryDirectory(prefix="project-a-broken-") as temp:
            root = Path(temp)
            shutil.copy2(fixture / "project.godot.fixture", root / "project.godot")
            shutil.copy2(fixture / "broken_runner.gd.fixture", root / "broken_runner.gd")
            shutil.copy2(fixture / "broken_dependency.gd.fixture", root / "broken_dependency.gd")
            result = tool.run_checked(
                godot,
                ["--headless", "--path", str(root), "--script", "res://broken_runner.gd"],
                root,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertRegex(result.output, r"SCRIPT ERROR:|Failed to load script")

    def test_real_fresh_project_builds_class_cache(self):
        tool = load_project_tool()
        godot = os.environ.get("PROJECT_A_TEST_GODOT_BIN")
        if not godot:
            self.skipTest("PROJECT_A_TEST_GODOT_BIN is required for the real Godot fixture")
        fixture = REPO_ROOT / "tests" / "fixtures" / "fresh_project"
        with tempfile.TemporaryDirectory(prefix="project-a-fresh-") as temp:
            root = Path(temp)
            shutil.copy2(fixture / "project.godot.fixture", root / "project.godot")
            shutil.copy2(fixture / "fresh_base.gd", root / "fresh_base.gd")
            shutil.copy2(fixture / "runner.gd", root / "runner.gd")
            self.assertTrue(tool.needs_class_scan(root))
            self.assertEqual(tool.ensure_class_cache(godot, root), 0)
            cache = root / ".godot" / "global_script_class_cache.cfg"
            self.assertTrue(cache.is_file())
            self.assertIn('"class": &"FreshBase"', cache.read_text(encoding="utf-8"))
