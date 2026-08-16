# Project Handoff Portability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 저장소만 clone해도 사람, Codex, Claude Code가 현재 Godot 프로젝트를 이해하고 Windows, macOS, Linux에서 같은 명령으로 검증한 뒤 다음 조건 분기 마일스톤을 시작할 수 있게 한다.

**Architecture:** 추적 문서는 README, 현재 상태, 로드맵, 아키텍처, 에이전트 규칙으로 책임을 나누고 서로 링크한다. Python 표준 라이브러리 실행기 `tools/project.py`가 Godot 탐색, 테스트, 에디터 스캔, 오프라인 부팅과 script-load 오류 승격을 운영체제 독립적으로 제공한다. 저장소 스킬은 프로젝트 사실을 복제하지 않고 작업 종류에 맞는 추적 문서를 읽게 하는 라우터로 유지한다.

**Tech Stack:** Godot 4.7, GDScript, Python 3.9+ 표준 라이브러리, Markdown, Codex agent skills, Claude Code `CLAUDE.md` import

## Global Constraints

- 작업 대상은 `project-a-demo`뿐이며 deprecated `project-a`는 읽거나 수정하지 않는다.
- 사용자 요청 없이 브랜치, worktree, PR을 만들지 않고 현재 `main`에서 의미 단위 커밋을 남긴다.
- Python 실행기는 Windows, macOS, Linux에서 동작하고 외부 Python 패키지를 사용하지 않는다.
- 사용자 전역 환경, shell profile, 레지스트리, 로컬 경로 설정 파일을 만들거나 변경하지 않는다.
- Godot 탐색 우선순위는 `--godot`, `PROJECT_A_GODOT_BIN`, PATH의 `godot`, PATH의 `godot4`다.
- 런타임과 기본 검증은 Notion, 토큰, 네트워크에 의존하지 않는다.
- 실제 파일 시스템 심링크를 만들지 않고 `CLAUDE.md`의 `@AGENTS.md` import를 사용한다.
- `.superpowers`의 ignored 보고서에 새 컴퓨터가 알아야 할 사실을 단독으로 남기지 않는다.
- 기존 `tools/run_godot.ps1`, 역사적 specs/plans, 대화 작성 가이드는 보존한다.
- 모든 새 추적 텍스트 파일은 UTF-8, LF를 사용한다.
- 설계 원본은 `docs/superpowers/specs/2026-08-16-project-handoff-portability-design.md`다.

---

## File Structure

### New files

- `tools/project.py`: 운영체제 독립 Godot 탐색과 doctor/test/editor/boot/check CLI.
- `tests/python/test_project_tool.py`: 실행기 순수 단위 테스트와 실제 broken fixture 회귀.
- `tests/python/test_handoff_docs.py`: 필수 문서, 링크, 문서 책임, 절대 경로 금지 계약.
- `tests/python/test_agent_workflow.py`: AGENTS/CLAUDE/저장소 스킬 구조와 참조 계약.
- `README.md`: 처음 온 사람을 위한 실행·조작·문서 입구.
- `AGENTS.md`: Codex와 Claude Code가 공유하는 프로젝트 작업 규칙 원본.
- `CLAUDE.md`: `@AGENTS.md` 한 줄 import.
- `docs/PROJECT_STATUS.md`: 현재 검증된 기능과 구현되지 않은 기능.
- `docs/ROADMAP.md`: 완료·예정 마일스톤과 플레이어 관점 승인 조건.
- `docs/ARCHITECTURE.md`: 런타임과 authoring 데이터 흐름 및 책임 경계.
- `.agents/skills/project-a-workflow/SKILL.md`: 프로젝트 작업 문서 라우팅 절차.
- `.agents/skills/project-a-workflow/agents/openai.yaml`: 스킬 UI 메타데이터.

### Existing files intentionally retained

- `tools/run_godot.ps1`: Windows 기존 호출 호환성과 기존 회귀 증거를 위해 유지한다.
- `tests/integration/test_script_error_wrapper.ps1`: 기존 PowerShell wrapper 회귀를 유지한다.
- `tests/integration/test_pristine_editor_scan.ps1`: 기존 PowerShell editor 회귀를 유지한다.
- `tests/integration/test_clean_wrapper_bootstrap.ps1`: 기존 PowerShell class-cache 회귀를 유지한다.
- `docs/dialogue-authoring-guide.md`: 공동 대화 작성법 원본으로 유지한다.
- `docs/narrative-state-reference.md`: 내러티브 키와 한국어 매핑 참조로 유지한다.

---

### Task 1: Cross-platform project command

**Files:**
- Create: `tools/project.py`
- Create: `tests/python/test_project_tool.py`
- Read: `tools/run_godot.ps1`
- Read: `tests/run_all.gd`
- Reuse: `tests/fixtures/broken_script_project/*.fixture`
- Reuse: `tests/fixtures/fresh_project/*`

**Interfaces:**
- Consumes: Godot 4.7 executable, repository root derived from `Path(__file__)`, existing `tests/run_all.gd`.
- Produces: `main(argv: Optional[Sequence[str]] = None) -> int`, `resolve_godot(explicit: Optional[str], environ: Mapping[str, str], which: Callable[[str], Optional[str]]) -> str`, `run_checked(godot: str, arguments: Sequence[str], cwd: Path, require_test_selection: bool = False, process_runner: Callable = subprocess.run) -> CommandResult`, `needs_class_scan(project_root: Path) -> bool`.
- Produces CLI: `doctor`, `test [--filter TEXT]`, `editor`, `boot`, `check`; every subcommand accepts `--godot PATH_OR_COMMAND`.

- [ ] **Step 1: Write pure discovery, version, output-classification, and command-shape tests**

Create `tests/python/test_project_tool.py` with these imports and initial cases:

```python
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
```

- [ ] **Step 2: Run the focused Python tests to verify RED**

Run:

```bash
python -m unittest tests/python/test_project_tool.py -v
```

Expected: FAIL because `tools/project.py` does not exist.

- [ ] **Step 3: Implement the minimal project command core**

Create `tools/project.py` around these exact contracts:

```python
#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, List, Mapping, Optional, Sequence, Tuple

REPO_ROOT = Path(__file__).resolve().parents[1]
MIN_PYTHON = (3, 9)
REQUIRED_FILES = (
    Path("project.godot"),
    Path("tests/run_all.gd"),
    Path("app/bootstrap/app_root.tscn"),
)
FAILURE_PATTERNS = (
    re.compile(r"SCRIPT ERROR:"),
    re.compile(r"ERROR:\s+(?:Failed to load script|Cannot load source code)"),
    re.compile(r"Detected another project\.godot"),
)
SELECTED_PATTERN = re.compile(r"Selected\s+([1-9][0-9]*)\s+test suite\(s\)\.")


class ProjectToolError(RuntimeError):
    pass


@dataclass(frozen=True)
class CommandResult:
    returncode: int
    output: str
    reason: str = ""


def _resolve_candidate(value: Optional[str], which: Callable[[str], Optional[str]]) -> Optional[str]:
    if value is None or not value.strip():
        return None
    candidate = Path(value).expanduser()
    if candidate.is_file():
        return str(candidate.resolve())
    return which(value)


def resolve_godot(
    explicit: Optional[str],
    environ: Mapping[str, str] = os.environ,
    which: Callable[[str], Optional[str]] = shutil.which,
) -> str:
    for value in (explicit, environ.get("PROJECT_A_GODOT_BIN"), "godot", "godot4"):
        resolved = _resolve_candidate(value, which)
        if resolved is not None:
            return resolved
    raise ProjectToolError(
        "Godot 4.7 executable not found. Pass --godot, set PROJECT_A_GODOT_BIN, "
        "or add godot/godot4 to PATH."
    )


def parse_godot_version(output: str) -> Tuple[int, int]:
    match = re.search(r"(?:Godot Engine v)?([0-9]+)\.([0-9]+)", output)
    if match is None:
        raise ProjectToolError("Could not parse the Godot version output.")
    return int(match.group(1)), int(match.group(2))


def require_supported_godot(output: str) -> Tuple[int, int]:
    version = parse_godot_version(output)
    if version != (4, 7):
        raise ProjectToolError(f"Godot 4.7 is required; detected {version[0]}.{version[1]}.")
    return version


def run_checked(
    godot: str,
    arguments: Sequence[str],
    cwd: Path,
    require_test_selection: bool = False,
    process_runner: Callable = subprocess.run,
) -> CommandResult:
    completed = process_runner(
        [godot, *arguments],
        cwd=str(cwd),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    output = completed.stdout or ""
    if completed.returncode != 0:
        return CommandResult(completed.returncode, output, "Godot returned a nonzero exit code.")
    for pattern in FAILURE_PATTERNS:
        match = pattern.search(output)
        if match is not None:
            return CommandResult(1, output, match.group(0))
    if require_test_selection and SELECTED_PATTERN.search(output) is None:
        return CommandResult(1, output, "Missing a nonzero 'Selected N test suite(s).' line.")
    return CommandResult(0, output)


def needs_class_scan(project_root: Path) -> bool:
    cache = project_root / ".godot" / "global_script_class_cache.cfg"
    if not cache.is_file():
        return True
    return cache.read_text(encoding="utf-8").strip() == "list=[]"


def test_arguments(project_root: Path, selected_filter: str) -> List[str]:
    args = ["--headless", "--path", str(project_root), "--script", "res://tests/run_all.gd"]
    if selected_filter:
        args.extend(["--", "--filter", selected_filter])
    return args
```

Complete `tools/project.py` with these exact orchestration functions. They print captured output with the user home replaced by `~`, validate the version for every command, bootstrap the class cache only when needed, and never invoke a shell:

```python
CHECK_ORDER = ("doctor", "python-tests", "test", "editor", "boot")


def redact(text: str) -> str:
    home = str(Path.home())
    return text.replace(home, "~") if home else text


def emit(result: CommandResult) -> int:
    if result.output:
        output = redact(result.output)
        sys.stdout.write(output)
        if not output.endswith("\n"):
            sys.stdout.write("\n")
    if result.returncode != 0 and result.reason:
        print(f"Project check failed: {redact(result.reason)}", file=sys.stderr)
    return result.returncode


def validate_environment(godot: str, project_root: Path = REPO_ROOT) -> None:
    if sys.version_info < MIN_PYTHON:
        raise ProjectToolError("Python 3.9 or newer is required.")
    missing = [str(path) for path in REQUIRED_FILES if not (project_root / path).is_file()]
    if missing:
        raise ProjectToolError("Missing required project files: " + ", ".join(missing))
    try:
        completed = subprocess.run(
            [godot, "--version"],
            cwd=str(project_root),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
    except OSError as error:
        raise ProjectToolError(f"Could not start Godot: {error.__class__.__name__}.") from error
    if completed.returncode != 0:
        raise ProjectToolError(f"Godot --version returned exit code {completed.returncode}.")
    require_supported_godot(completed.stdout or "")


def doctor(godot: str, project_root: Path = REPO_ROOT) -> int:
    validate_environment(godot, project_root)
    print(f"Python: {sys.version_info.major}.{sys.version_info.minor}")
    print("Godot: 4.7")
    print(f"Repository: {project_root.name}")
    return 0


def ensure_class_cache(godot: str, project_root: Path = REPO_ROOT) -> int:
    if not needs_class_scan(project_root):
        return 0
    result = run_checked(
        godot,
        ["--headless", "--path", str(project_root), "--editor", "--quit"],
        project_root,
    )
    return emit(result)


def run_tests(godot: str, selected_filter: str = "", project_root: Path = REPO_ROOT) -> int:
    cache_exit = ensure_class_cache(godot, project_root)
    if cache_exit != 0:
        return cache_exit
    return emit(
        run_checked(
            godot,
            test_arguments(project_root, selected_filter),
            project_root,
            require_test_selection=True,
        )
    )


def run_editor(godot: str, project_root: Path = REPO_ROOT) -> int:
    return emit(
        run_checked(
            godot,
            ["--headless", "--path", str(project_root), "--editor", "--quit"],
            project_root,
        )
    )


def run_boot(godot: str, project_root: Path = REPO_ROOT) -> int:
    return emit(
        run_checked(
            godot,
            ["--headless", "--path", str(project_root), "--quit-after", "3"],
            project_root,
        )
    )


def run_python_tests(godot: str, project_root: Path = REPO_ROOT) -> int:
    environment = dict(os.environ)
    environment["PROJECT_A_TEST_GODOT_BIN"] = godot
    completed = subprocess.run(
        [
            sys.executable,
            "-m",
            "unittest",
            "discover",
            "-s",
            "tests/python",
            "-p",
            "test_*.py",
            "-v",
        ],
        cwd=str(project_root),
        env=environment,
        check=False,
    )
    return completed.returncode


def _add_godot_argument(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--godot", help="Godot 4.7 executable path or command")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Project A development commands")
    subparsers = parser.add_subparsers(dest="command", required=True)
    for name in ("doctor", "editor", "boot", "check"):
        command_parser = subparsers.add_parser(name)
        _add_godot_argument(command_parser)
    test_parser = subparsers.add_parser("test")
    _add_godot_argument(test_parser)
    test_parser.add_argument("--filter", default="", help="Godot test suite path filter")
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    arguments = build_parser().parse_args(argv)
    try:
        godot = resolve_godot(arguments.godot)
        doctor(godot)
        if arguments.command == "doctor":
            return 0
        if arguments.command == "test":
            return run_tests(godot, arguments.filter)
        if arguments.command == "editor":
            return run_editor(godot)
        if arguments.command == "boot":
            return run_boot(godot)
        for action in (
            lambda: run_python_tests(godot),
            lambda: run_tests(godot),
            lambda: run_editor(godot),
            lambda: run_boot(godot),
        ):
            exit_code = action()
            if exit_code != 0:
                return exit_code
        return 0
    except ProjectToolError as error:
        print(f"Project check failed: {redact(str(error))}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
```

In `run_checked`, wrap the `process_runner` call in `try/except OSError` and return `CommandResult(1, "", f"Could not start Godot: {error.__class__.__name__}.")` so a bad executable cannot produce a traceback containing a machine path.

- [ ] **Step 4: Run focused tests and verify GREEN**

Run:

```bash
python -m unittest tests/python/test_project_tool.py -v
python tools/project.py doctor --godot "$PROJECT_A_GODOT_BIN"
python tools/project.py test --godot "$PROJECT_A_GODOT_BIN" --filter game_session
```

On PowerShell, substitute `$env:PROJECT_A_GODOT_BIN` for the shell variable. Expected: all Python tests pass, doctor reports Python/Godot compatibility, and Godot selects one `game_session` suite with exit 0.

- [ ] **Step 5: Add real broken-fixture and fresh-cache regressions**

Append tests that use `PROJECT_A_TEST_GODOT_BIN` when provided and otherwise skip only these real-process cases:

```python
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
```

Add this fresh-project case to the same class:

```python
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
```

- [ ] **Step 6: Verify the complete command and inspect diagnostics**

Run:

```bash
python tools/project.py check --godot "$PROJECT_A_GODOT_BIN"
```

Expected: Python tests, full Godot suite, editor load, and offline boot all exit 0; the deliberately broken fixture is reported as an expected passing regression and no `SCRIPT ERROR` leaks from the production project.

- [ ] **Step 7: Commit Task 1**

```bash
git add tools/project.py tests/python/test_project_tool.py
git diff --cached --check
git commit -m "feat: add cross-platform project checks"
```

---

### Task 2: Human-readable project handoff documents

**Files:**
- Create: `README.md`
- Create: `docs/PROJECT_STATUS.md`
- Create: `docs/ROADMAP.md`
- Create: `docs/ARCHITECTURE.md`
- Create: `tests/python/test_handoff_docs.py`
- Read: `project.godot`
- Read: `docs/dialogue-authoring-guide.md`
- Read: `docs/narrative-state-reference.md`
- Read: `docs/superpowers/specs/2026-08-16-world-save-vertical-slice-redesign-design.md`

**Interfaces:**
- Consumes: Task 1 CLI commands and the current verified vertical slice.
- Produces: stable human entry point and three single-purpose tracked sources used by Task 3's agent skill.
- Produces exact links: `README.md` -> `docs/PROJECT_STATUS.md`, `docs/ROADMAP.md`, `docs/ARCHITECTURE.md`, `docs/dialogue-authoring-guide.md`. Task 3 adds the AGENTS link when that target exists.

- [ ] **Step 1: Write the failing document contract test**

Create `tests/python/test_handoff_docs.py`:

```python
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
```

- [ ] **Step 2: Run the document test to verify RED**

Run:

```bash
python -m unittest tests/python/test_handoff_docs.py -v
```

Expected: FAIL because the four handoff documents do not exist.

- [ ] **Step 3: Create the concise README entry point**

Create `README.md` with this exact section order:

```markdown
# Project A Demo

Godot 4.7 기반 2D 픽셀 탑다운 어드벤처 게임입니다. 이동과 상호작용보다 대화, 선택, 조건에 따른 이야기 변화가 중심입니다.

## 현재 플레이 가능 범위
## 요구 사항
## 처음 실행하기
## 조작법
## 프로젝트 검증
## 대화 작성
## 프로젝트 문서
## 현재 작업 방향
```

Use these canonical commands:

```bash
python tools/project.py doctor
python tools/project.py check
python tools/project.py test --filter dialogue
```

State that `python3` can replace `python`, and show a single optional example `python tools/project.py check --godot /path/to/godot`. Do not add OS-specific installation steps or a Notion token setup section.

- [ ] **Step 4: Create the evidence-based status document**

Create `docs/PROJECT_STATUS.md` with these headings and facts:

```markdown
# 프로젝트 현재 상태

## 기준
- 엔진: Godot 4.7
- 메인 씬: `res://app/bootstrap/app_root.tscn`
- 화면: 640×360, 정수 스케일, nearest filtering
- 런타임 네트워크 의존성: 없음

## 현재 플레이 가능 범위
- 타이틀에서 새 게임 또는 6행 불러오기
- 기초 방과 기초 홀 이동
- 거울 상호작용과 이름·초상화·표정·선택지 대화
- 중요 선택 자동 저장과 정확한 대화 재개
- 자동 저장 1개, 수동 슬롯 5개, 백업 복구

## 구현 완료
### 플레이어와 월드
### 대화와 작성 데이터
### 저장과 메뉴
### 검증

## 현재 콘텐츠
- 맵: `foundation_room`, `foundation_hall`
- 상호작용: 거울, 왕복 문
- 캐릭터 정의: 레티, 젤리뽀

## 아직 구현되지 않음
- 범용 아이템과 인벤토리
- 아이템 획득과 사용
- 완전한 NPC·장소 조건 이벤트 규칙
- 플레이어용 퀘스트 진행 표시
- 오디오, 설정, 게임패드, 배포 자동화

## 알려진 제약
- 현재 콘텐츠는 기반 검증용 수직 슬라이스 규모다.
- 실제 맵 아트와 오디오는 데모 완성도 마일스톤 범위다.

## 표준 검증
```

Record that the user completed the real keyboard-operated 13-step acceptance, including slot restore/resave, active autosave dialogue resume, backup recovery, offline restart/load, and autosave metadata inspection.

- [ ] **Step 5: Create the player-outcome roadmap**

Create `docs/ROADMAP.md` with exactly these ordered milestones:

```markdown
# 프로젝트 로드맵

## 운영 규칙
## 완료: 게임플레이 기반과 대화 런타임
## 완료: 문서 우선 대화 작성
## 완료: 월드·저장 수직 슬라이스
## 진행 중: 문서·인수인계 이식성
## 다음: 조건 분기 플레이 기반
## 이후: 젤리뽀의 집 플레이어블 시나리오
## 이후: 콘텐츠 제작 확장
## 이후: 데모 완성도와 배포
```

For every milestone include 목표, 플레이어 결과, 완료 조건, 제외 범위. The next milestone must name inventory state, item acquire/use/consume, quest stage transitions, conditional event selection, dialogue conditions/effects, save/load round-trip, and failure atomicity. The Jellyppo milestone must explicitly cover first visit, item-held visit, requirement-met visit, multiple paragraphs after choices, later choices, and rejoin.

- [ ] **Step 6: Create the responsibility-focused architecture guide**

Create `docs/ARCHITECTURE.md` with these top-level sections:

```markdown
# 프로젝트 아키텍처

## 전체 흐름
## 디렉터리 책임
## 런타임 소유권
## 플레이어와 맵 수명 주기
## 상호작용에서 대화까지
## 상태와 저장 경계
## 문서에서 런타임 데이터까지
## 테스트 계층
## 변경할 때 함께 확인할 문서
```

Use the approved ASCII flow and document these exact ownership rules:

- `GameSession`: mode, `NarrativeState`, `WorldState`, play time.
- `SceneDirector`: current map, persistent player, transition transaction.
- `SaveService`: six-slot capture, repository orchestration, transactional restore.
- `AppRoot`: local service wiring and UI, not persistent state ownership.
- Interaction: detector -> router -> event resolver -> dialogue service.
- Authoring: Korean document -> normalized authoring JSON -> schema/compiler -> graph/events/source map/manifest.
- State split: story facts and quest stages in NarrativeState; visual/object-local facts in WorldState.

- [ ] **Step 7: Run document tests and the project check**

Run:

```bash
python -m unittest tests/python/test_handoff_docs.py -v
python tools/project.py check --godot "$PROJECT_A_GODOT_BIN"
git diff --check
```

Expected: document tests pass, the complete project check exits 0, and no script-load diagnostics appear.

- [ ] **Step 8: Commit Task 2**

```bash
git add README.md docs/PROJECT_STATUS.md docs/ROADMAP.md docs/ARCHITECTURE.md tests/python/test_handoff_docs.py
git diff --cached --check
git commit -m "docs: add portable project handoff"
```

---

### Task 3: Shared agent rules and repository skill

**Files:**
- Create: `AGENTS.md`
- Create: `CLAUDE.md`
- Create: `.agents/skills/project-a-workflow/SKILL.md`
- Create: `.agents/skills/project-a-workflow/agents/openai.yaml`
- Create: `tests/python/test_agent_workflow.py`
- Modify: `README.md`
- Read: `docs/PROJECT_STATUS.md`
- Read: `docs/ROADMAP.md`
- Read: `docs/ARCHITECTURE.md`
- Read: `docs/dialogue-authoring-guide.md`
- Read: `docs/narrative-state-reference.md`

**Interfaces:**
- Consumes: Task 2 tracked sources and Task 1 `tools/project.py`.
- Produces: one shared `AGENTS.md`, Claude import proxy, Codex repo skill named `project-a-workflow`.
- Produces skill routing contract: always status+roadmap; architecture for code; authoring guide+state reference for dialogue/content.

- [ ] **Step 1: Write failing agent and skill contract tests**

Create `tests/python/test_agent_workflow.py`:

```python
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

    def test_readme_links_the_shared_agent_rules(self):
        text = (REPO_ROOT / "README.md").read_text(encoding="utf-8")
        self.assertIn("(AGENTS.md)", text)

    def test_skill_routes_to_tracked_sources_without_copying_status(self):
        text = (REPO_ROOT / ".agents/skills/project-a-workflow/SKILL.md").read_text(encoding="utf-8")
        self.assertIn("name: project-a-workflow", text)
        for required in ("docs/PROJECT_STATUS.md", "docs/ROADMAP.md", "docs/ARCHITECTURE.md", "docs/dialogue-authoring-guide.md", "docs/narrative-state-reference.md", "tools/project.py"):
            with self.subTest(required=required):
                self.assertIn(required, text)
        self.assertNotIn("foundation_room", text)
        self.assertNotIn("자동 저장 1개", text)

    def test_skill_ui_metadata_is_minimal_and_stable(self):
        text = (REPO_ROOT / ".agents/skills/project-a-workflow/agents/openai.yaml").read_text(encoding="utf-8")
        self.assertIn('display_name: "Project A Workflow"', text)
        self.assertIn('short_description: "Work safely in the Project A Godot repository"', text)
        self.assertIn('default_prompt: "Use the Project A workflow and tracked project documents to complete this task."', text)
        self.assertNotIn("dependencies:", text)
        self.assertNotIn("allow_implicit_invocation:", text)
```

- [ ] **Step 2: Run the focused test to verify RED**

Run:

```bash
python -m unittest tests/python/test_agent_workflow.py -v
```

Expected: FAIL because AGENTS, CLAUDE, and the repo skill do not exist.

- [ ] **Step 3: Create the single-source agent rules**

Create `AGENTS.md` with this structure and imperative rules:

```markdown
# Project A 작업 규칙

## 시작할 때
1. `docs/PROJECT_STATUS.md`와 `docs/ROADMAP.md`를 읽는다.
2. `git status --short`로 기존 변경을 확인하고 보존한다.
3. 작업 범위와 관련 테스트를 확인한다.

## 저장소 범위
- `project-a-demo`만 수정한다.
- deprecated `project-a`는 수정하지 않는다.

## Git 작업 방식
- 기본적으로 현재 `main`에서 작업한다.
- 요청 없이는 branch, worktree, PR을 만들지 않는다.
- 의미 있는 단위마다 semantic commit을 남긴다.

## 구현 방식
- 기능과 버그 수정은 테스트를 먼저 작성한다.
- 실패 원인을 확인한 뒤 최소 변경으로 GREEN을 만든다.
- 사용자의 기존 변경과 무관한 파일을 정리하거나 되돌리지 않는다.

## 표준 검증
## Godot 프로젝트 불변조건
## 대화와 콘텐츠 작성
## 문서 갱신
## 완료할 때
```

Under standard verification, require the narrowest relevant `python tools/project.py test --filter ...` followed by `python tools/project.py check` before completion. Under invariants, record Godot 4.7, 640x360 integer pixel rendering, exactly three autoloads, offline runtime, and no runtime Notion/token/network dependency. Under documentation updates, map status changes to PROJECT_STATUS, roadmap changes to ROADMAP, architecture changes to ARCHITECTURE, and authoring UX changes to the dialogue guide.

Create `CLAUDE.md` with exactly:

```markdown
@AGENTS.md
```

Add one `AGENTS.md` link under README's project documents section after the file exists. Do not copy agent rules into README.

- [ ] **Step 4: Initialize and author the repository skill**

Read the active `skill-creator`'s `SKILL.md` and `references/openai_yaml.md` completely. Then use its `scripts/init_skill.py` to initialize `project-a-workflow` under `.agents/skills` with no scripts, references, examples, or assets. Pass these interface values:

```text
display_name=Project A Workflow
short_description=Work safely in the Project A Godot repository
default_prompt=Use the Project A workflow and tracked project documents to complete this task.
```

Replace the generated `SKILL.md` with:

```markdown
---
name: project-a-workflow
description: Work safely in the Project A Godot 4.7 repository. Use for gameplay code, dialogue and branching content, save/map/interaction systems, tests, project verification, milestones, documentation, or handoff work in project-a-demo. Do not use for the deprecated project-a repository.
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

1. Run the narrowest relevant filter: use `--filter dialogue` for dialogue work, `--filter save_` for save work, or the changed test filename stem for another subsystem.
2. Run `python tools/project.py check` before claiming completion.
3. Update the tracked source that owns any changed fact: status, roadmap, architecture, or authoring guide.
4. Report the commit, verification result, and any manual acceptance still required.
```

Set `agents/openai.yaml` to exactly:

```yaml
interface:
  display_name: "Project A Workflow"
  short_description: "Work safely in the Project A Godot repository"
  default_prompt: "Use the Project A workflow and tracked project documents to complete this task."
```

Do not add tool dependencies, icons, brand colors, or invocation policy.

- [ ] **Step 5: Validate the skill and run focused tests**

Run the active skill creator's `scripts/quick_validate.py` against `.agents/skills/project-a-workflow`, then run:

```bash
python -m unittest tests/python/test_agent_workflow.py -v
python tools/project.py check --godot "$PROJECT_A_GODOT_BIN"
```

Expected: skill validation passes, agent workflow tests pass, and the full project check exits 0.

- [ ] **Step 6: Forward-test discovery without changing the repository**

Start a fresh Codex context at the repository root and invoke `$project-a-workflow` with this read-only request:

```text
현재 구현된 기능과 다음 마일스톤, 전체 검증 명령을 알려줘. 파일은 수정하지 마.
```

Verify the answer uses `PROJECT_STATUS.md`, identifies `조건 분기 플레이 기반`, gives `python tools/project.py check`, and does not claim inventory is implemented. Do not let the forward test edit files or create commits.

- [ ] **Step 7: Commit Task 3**

```bash
git add README.md AGENTS.md CLAUDE.md .agents/skills/project-a-workflow tests/python/test_agent_workflow.py
git diff --cached --check
git commit -m "chore: add shared project agent workflow"
```

---

### Task 4: Integrated handoff acceptance and milestone closure

**Files:**
- Modify: `docs/PROJECT_STATUS.md`
- Modify: `docs/ROADMAP.md`
- Test: `tests/python/test_project_tool.py`
- Test: `tests/python/test_handoff_docs.py`
- Test: `tests/python/test_agent_workflow.py`
- Verify: all tracked files from Tasks 1-3

**Interfaces:**
- Consumes: Tasks 1-3 complete portable handoff package.
- Produces: documentation milestone marked complete only after repository-level verification; next milestone remains `조건 분기 플레이 기반`.

- [ ] **Step 1: Run the three focused Python suites from outside the repository directory**

From the repository parent, run using an absolute script path but no working-directory assumption:

```bash
python project-a-demo/tools/project.py doctor --godot "$PROJECT_A_GODOT_BIN"
python -m unittest discover -s project-a-demo/tests/python -p "test_*.py" -v
```

Expected: the script derives the repository root from its own location, doctor passes, and all Python tests pass.

- [ ] **Step 2: Run the standard command from the repository root**

Run:

```bash
python tools/project.py check --godot "$PROJECT_A_GODOT_BIN"
```

Expected order and result:

```text
doctor       PASS
python-tests PASS
test         PASS with a nonzero selected suite count
editor       PASS with no nested-project or script-load warning
boot         PASS offline
```

- [ ] **Step 3: Verify the legacy Windows wrapper remains compatible**

On the current Windows development machine, run:

```powershell
pwsh -NoProfile -File tests/integration/test_script_error_wrapper.ps1
pwsh -NoProfile -File tests/integration/test_pristine_editor_scan.ps1
pwsh -NoProfile -File tests/integration/test_clean_wrapper_bootstrap.ps1
```

Expected: all three exit 0. These are compatibility checks only and are not referenced by the portable README command.

- [ ] **Step 4: Run static portability and integrity checks**

Run:

```bash
git diff --check
git status --short
```

Search the handoff package and require zero matches for machine-specific or secret assignments:

```text
[A-Za-z]:\\
/Users/
/home/
PROJECT_A_NOTION_TOKEN=
PROJECT_A_NOTION_CHARACTERS_SOURCE=
PROJECT_A_NOTION_SCENES_SOURCE=
PROJECT_A_NOTION_BLOCKS_SOURCE=
```

Confirm `.agents/skills/project-a-workflow/SKILL.md` is below 500 lines and all README relative links resolve through `test_handoff_docs.py`.

- [ ] **Step 5: Mark the documentation milestone complete**

In `docs/ROADMAP.md`, change only:

```markdown
## 진행 중: 문서·인수인계 이식성
```

to:

```markdown
## 완료: 문서·인수인계 이식성
```

Add a short evidence list naming README onboarding, `tools/project.py check`, shared AGENTS/CLAUDE rules, repo skill validation, and cross-directory invocation. In `docs/PROJECT_STATUS.md`, add the portable handoff package under implemented tooling and keep inventory/quest work under not implemented.

- [ ] **Step 6: Re-run final verification after the status update**

Run:

```bash
python -m unittest discover -s tests/python -p "test_*.py" -v
python tools/project.py check --godot "$PROJECT_A_GODOT_BIN"
git diff --check
```

Expected: all Python tests and the complete project check pass after the final tracked document edits.

- [ ] **Step 7: Commit Task 4**

```bash
git add docs/PROJECT_STATUS.md docs/ROADMAP.md
git diff --cached --check
git commit -m "docs: complete project handoff milestone"
git status --short
```

Expected: commit succeeds and tracked status is empty.

---

## Final Review Checklist

- [ ] The README starts a new human at the portable Python command and links every source document.
- [ ] AGENTS is the only detailed agent-rule source; CLAUDE contains exactly `@AGENTS.md`.
- [ ] The Codex skill routes to tracked documents instead of copying volatile project status.
- [ ] `tools/project.py` has no non-stdlib imports and never uses `shell=True`.
- [ ] Godot discovery order and 4.7 version enforcement match the design.
- [ ] A zero-exit Godot script-load failure becomes a nonzero project command result.
- [ ] Fresh class-cache bootstrap and the deliberately broken fixture work on the Python path.
- [ ] `check` runs Python tests, full Godot tests, editor load, and offline boot.
- [ ] PROJECT_STATUS records only verified completion and retains missing inventory/quest systems.
- [ ] ROADMAP marks handoff complete and condition-driven gameplay next.
- [ ] No tracked handoff file contains a machine-specific absolute path, token assignment, or runtime network setup.
- [ ] Existing PowerShell wrapper and historical docs remain intact.
- [ ] The final tracked worktree is clean and every task has its own semantic commit.
