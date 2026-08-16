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
CHECK_ORDER = ("doctor", "python-tests", "test", "editor", "boot")


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
    try:
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
    except OSError as error:
        return CommandResult(1, "", f"Could not start Godot: {error.__class__.__name__}.")
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
