#!/usr/bin/env python3
from __future__ import annotations

import argparse
import locale
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
PYTHON_OUTPUT_ENCODING = locale.getpreferredencoding(False) or "utf-8"
REQUIRED_FILES = (
    Path("project.godot"),
    Path("tests/run_all.gd"),
    Path("app/bootstrap/app_root.tscn"),
)
FAILURE_PATTERNS = (
    re.compile(r"SCRIPT ERROR:"),
    re.compile(r"ERROR:\s+(?:Failed to load script|Cannot load source code)"),
    re.compile(r"Detected another project\.godot"),
    re.compile(r"^TEST FAILURE:", re.MULTILINE),
)
SELECTED_PATTERN = re.compile(r"Selected\s+([1-9][0-9]*)\s+test suite\(s\)\.")
COMPLETED_PATTERN = re.compile(r"Completed\s+([1-9][0-9]*)\s+test suite\(s\)\.")
VERSION_PATTERN = re.compile(
    r"^(?:Godot Engine v)?([0-9]+)\.([0-9]+)(?:\.[0-9A-Za-z][0-9A-Za-z._-]*)?$"
)
CHECK_ORDER = ("doctor", "python-tests", "test", "editor", "boot")


class ProjectToolError(RuntimeError):
    pass


@dataclass(frozen=True)
class CommandResult:
    returncode: int
    output: str
    reason: str = ""
    stage: str = "godot"
    arguments: Tuple[str, ...] = ()
    original_returncode: Optional[int] = None


def _resolve_configured_candidate(
    value: Optional[str], which: Callable[[str], Optional[str]]
) -> Optional[str]:
    if value is None or not value.strip():
        return None
    configured = value.strip()
    candidate = Path(configured).expanduser()
    separators = tuple(separator for separator in (os.sep, os.altsep) if separator)
    if candidate.is_absolute() or any(separator in configured for separator in separators):
        return str(candidate.resolve()) if candidate.is_file() else None
    return which(configured)


def resolve_godot(
    explicit: Optional[str],
    environ: Mapping[str, str] = os.environ,
    which: Callable[[str], Optional[str]] = shutil.which,
) -> str:
    for value in (explicit, environ.get("PROJECT_A_GODOT_BIN")):
        resolved = _resolve_configured_candidate(value, which)
        if resolved is not None:
            return resolved
    for command in ("godot", "godot4"):
        resolved = which(command)
        if resolved is not None:
            return resolved
    raise ProjectToolError(
        "Godot 4.7 executable not found. Pass --godot, set PROJECT_A_GODOT_BIN, "
        "or add godot/godot4 to PATH."
    )


def parse_godot_version(output: str) -> Tuple[int, int]:
    first_line = next((line.strip() for line in output.splitlines() if line.strip()), "")
    match = VERSION_PATTERN.fullmatch(first_line)
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
    stage: str = "godot",
) -> CommandResult:
    command_arguments = tuple(str(argument) for argument in arguments)
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
        return CommandResult(
            1,
            "",
            f"Could not start Godot: {error.__class__.__name__}.",
            stage,
            command_arguments,
            None,
        )
    output = completed.stdout or ""
    failure_reason = ""
    for pattern in FAILURE_PATTERNS:
        match = pattern.search(output)
        if match is not None:
            failure_reason = match.group(0)
            break
    if completed.returncode != 0:
        return CommandResult(
            completed.returncode,
            output,
            failure_reason or "Process returned a nonzero exit code.",
            stage,
            command_arguments,
            completed.returncode,
        )
    if failure_reason:
        return CommandResult(1, output, failure_reason, stage, command_arguments, 0)
    if require_test_selection:
        selected = SELECTED_PATTERN.search(output)
        completed_count = COMPLETED_PATTERN.search(output)
        if selected is None:
            return CommandResult(
                1,
                output,
                "Missing a nonzero 'Selected N test suite(s).' line.",
                stage,
                command_arguments,
                0,
            )
        if completed_count is None:
            return CommandResult(
                1,
                output,
                "Missing a nonzero 'Completed N test suite(s).' line.",
                stage,
                command_arguments,
                0,
            )
        if selected.group(1) != completed_count.group(1):
            return CommandResult(
                1,
                output,
                "Selected and Completed test suite counts do not match.",
                stage,
                command_arguments,
                0,
            )
    return CommandResult(0, output, stage=stage, arguments=command_arguments, original_returncode=0)


def needs_class_scan(project_root: Path) -> bool:
    cache = project_root / ".godot" / "global_script_class_cache.cfg"
    if not cache.is_file():
        return True
    try:
        content = cache.read_text(encoding="utf-8").strip()
    except (OSError, UnicodeError):
        return True
    if not content or content == "list=[]":
        return True
    entries = re.findall(r"\{(.*?)\}", content, re.DOTALL)
    structure = re.sub(r"\{.*?\}", "{}", content, flags=re.DOTALL)
    if not entries or re.fullmatch(r"list\s*=\s*\[\s*\{\}(?:\s*,\s*\{\})*\s*\]", structure) is None:
        return True
    for entry in entries:
        if re.search(r'"class"\s*:\s*&"[^"]+"', entry) is None:
            return True
        if re.search(r'"path"\s*:\s*"res://[^"]+"', entry) is None:
            return True
    return False


def test_arguments(project_root: Path, selected_filter: str) -> List[str]:
    args = ["--headless", "--path", str(project_root), "--script", "res://tests/run_all.gd"]
    if selected_filter:
        args.extend(["--", "--filter", selected_filter])
    return args


def redact(text: str) -> str:
    home = str(Path.home())
    return text.replace(home, "~") if home else text


def safe_arguments(arguments: Sequence[str]) -> Tuple[str, ...]:
    safe: List[str] = []
    redact_next = False
    for argument in arguments:
        value = str(argument)
        if redact_next:
            safe.append("<redacted>")
            redact_next = False
            continue
        normalized = value.lower().lstrip("-")
        sensitive = any(word in normalized for word in ("token", "secret", "password"))
        if sensitive and "=" in value:
            safe.append(redact(value.split("=", 1)[0]) + "=<redacted>")
            continue
        safe.append(redact(value))
        redact_next = sensitive
    return tuple(safe)


def write_terminal(stream, text: str) -> None:
    try:
        stream.write(text)
    except UnicodeEncodeError:
        encoding = getattr(stream, "encoding", None) or "utf-8"
        stream.write(text.encode(encoding, errors="replace").decode(encoding))


def emit(result: CommandResult) -> int:
    if result.output:
        output = redact(result.output)
        write_terminal(sys.stdout, output)
        if not output.endswith("\n"):
            write_terminal(sys.stdout, "\n")
    if result.returncode != 0 and result.reason:
        original = "unavailable" if result.original_returncode is None else str(result.original_returncode)
        diagnostic = (
            "Project check failed:\n"
            f"  Stage: {result.stage}\n"
            f"  Arguments: {safe_arguments(result.arguments)}\n"
            f"  Original exit code: {original}\n"
            f"  Reason: {redact(result.reason)}\n"
        )
        write_terminal(sys.stderr, diagnostic)
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
        stage="class-cache",
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
            stage="godot-tests",
        )
    )


def run_editor(godot: str, project_root: Path = REPO_ROOT) -> int:
    return emit(
        run_checked(
            godot,
            ["--headless", "--path", str(project_root), "--editor", "--quit"],
            project_root,
            stage="editor",
        )
    )


def run_boot(godot: str, project_root: Path = REPO_ROOT) -> int:
    return emit(
        run_checked(
            godot,
            ["--headless", "--path", str(project_root), "--quit-after", "3"],
            project_root,
            stage="boot",
        )
    )


def run_python_tests(
    godot: str,
    project_root: Path = REPO_ROOT,
    process_runner: Callable = subprocess.run,
) -> int:
    environment = dict(os.environ)
    environment["PROJECT_A_TEST_GODOT_BIN"] = godot
    arguments = [
        sys.executable,
        "-m",
        "unittest",
        "discover",
        "-s",
        "tests/python",
        "-p",
        "test_*.py",
        "-v",
    ]
    try:
        completed = process_runner(
            arguments,
            cwd=str(project_root),
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            encoding=PYTHON_OUTPUT_ENCODING,
            errors="replace",
            check=False,
        )
    except OSError as error:
        return emit(
            CommandResult(
                1,
                "",
                f"Could not start Python tests: {error.__class__.__name__}.",
                "python-tests",
                tuple(arguments),
                None,
            )
        )
    reason = "" if completed.returncode == 0 else "Python tests returned a nonzero exit code."
    return emit(
        CommandResult(
            completed.returncode,
            completed.stdout or "",
            reason,
            "python-tests",
            tuple(arguments),
            completed.returncode,
        )
    )


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
        return emit(CommandResult(2, "", str(error), "doctor", (), None))


if __name__ == "__main__":
    raise SystemExit(main())
