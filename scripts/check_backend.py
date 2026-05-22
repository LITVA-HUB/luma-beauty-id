#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import re
import subprocess
import sys
from typing import NamedTuple


OPENROUTER_KEY_PATTERNS = (
    re.compile(r"sk-or-v1-[A-Za-z0-9_-]{20,}"),
    re.compile(r"OPENROUTER_API_KEY[ \t]*=[ \t]*(?!$)(?!replace_with_secret_from_secret_manager)(?!replace-with-secret-manager-value)[A-Za-z0-9._/-]{12,}"),
)

SKIP_TEXT_SUFFIXES = {".png", ".jpg", ".jpeg", ".zip", ".sqlite3", ".pyc", ".DS_Store"}


class CheckCommand(NamedTuple):
    label: str
    argv: list[str]
    cwd: pathlib.Path


def project_root() -> pathlib.Path:
    return pathlib.Path(__file__).resolve().parents[1]


def command_plan(root: pathlib.Path, python: str) -> list[CheckCommand]:
    backend = root / "backend"
    return [
        CheckCommand("pytest", [python, "-m", "pytest", "-q"], backend),
        CheckCommand("compileall", [python, "-m", "compileall", "app"], backend),
    ]


def _read_text(path: pathlib.Path) -> str:
    return path.read_text(errors="ignore")


def scan_ios_openrouter_refs(root: pathlib.Path) -> list[str]:
    ios_root = root / "ios"
    if not ios_root.exists():
        return []
    hits: list[str] = []
    for path in ios_root.rglob("*"):
        if not path.is_file() or path.suffix.lower() in {".png", ".jpg", ".jpeg", ".md"}:
            continue
        text = _read_text(path)
        if "OPENROUTER_API_KEY" in text or "openrouter.ai" in text.lower():
            hits.append(str(path.relative_to(root)))
    return sorted(hits)


def tracked_text_files(root: pathlib.Path) -> list[pathlib.Path]:
    result = subprocess.run(["git", "ls-files"], cwd=root, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode != 0:
        print(result.stderr.strip(), file=sys.stderr)
        return []
    paths: list[pathlib.Path] = []
    for raw in result.stdout.splitlines():
        path = root / raw
        if path.is_file() and path.suffix.lower() not in SKIP_TEXT_SUFFIXES:
            paths.append(path)
    return paths


def scan_openrouter_key_patterns(paths: list[pathlib.Path], root: pathlib.Path) -> list[str]:
    hits: list[str] = []
    for path in paths:
        text = _read_text(path)
        if any(pattern.search(text) for pattern in OPENROUTER_KEY_PATTERNS):
            hits.append(str(path.relative_to(root)))
    return sorted(hits)


def run_command(command: CheckCommand) -> int:
    print(f"==> {command.label}: {' '.join(command.argv)}")
    result = subprocess.run(command.argv, cwd=command.cwd)
    if result.returncode:
        print(f"FAIL {command.label}: exit {result.returncode}")
    else:
        print(f"OK {command.label}")
    return result.returncode


def run_sanity_checks(root: pathlib.Path) -> int:
    ios_hits = scan_ios_openrouter_refs(root)
    secret_hits = scan_openrouter_key_patterns(tracked_text_files(root), root)
    if ios_hits:
        print(f"FAIL ios_openrouter_refs: {ios_hits}")
    else:
        print("OK ios_openrouter_refs")
    if secret_hits:
        print(f"FAIL openrouter_secret_patterns: {secret_hits}")
    else:
        print("OK openrouter_secret_patterns")
    return 1 if ios_hits or secret_hits else 0


def main() -> int:
    root = project_root()
    failures = 0
    for command in command_plan(root, sys.executable):
        failures += 1 if run_command(command) else 0
    failures += run_sanity_checks(root)
    if failures:
        print(f"Backend QA failed: {failures} check(s) failed.")
        return 1
    print("Backend QA passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
