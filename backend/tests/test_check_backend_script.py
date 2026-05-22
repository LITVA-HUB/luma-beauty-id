from __future__ import annotations

import importlib.util
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def load_check_backend():
    spec = importlib.util.spec_from_file_location("check_backend", ROOT / "scripts" / "check_backend.py")
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_check_backend_command_plan_runs_pytest_then_compileall():
    check_backend = load_check_backend()
    commands = check_backend.command_plan(Path("/repo"), "python3")

    assert [command.label for command in commands] == ["pytest", "compileall"]
    assert commands[0].argv == ["python3", "-m", "pytest", "-q"]
    assert commands[0].cwd == Path("/repo") / "backend"
    assert commands[1].argv == ["python3", "-m", "compileall", "app"]
    assert commands[1].cwd == Path("/repo") / "backend"


def test_check_backend_lightweight_openrouter_scans(tmp_path):
    check_backend = load_check_backend()
    root = tmp_path
    ios = root / "ios" / "BeautyConcierge"
    docs = root / "ios" / "README.md"
    ios.mkdir(parents=True)
    docs.parent.mkdir(parents=True, exist_ok=True)
    (ios / "APIClient.swift").write_text("let url = \"https://openrouter.ai/api/v1\"\n")
    docs.write_text("Docs can mention openrouter.ai safely.\n")

    ios_hits = check_backend.scan_ios_openrouter_refs(root)
    assert ios_hits == ["ios/BeautyConcierge/APIClient.swift"]

    safe = root / "backend" / ".env.example"
    unsafe = root / "backend" / "config.txt"
    safe.parent.mkdir(parents=True)
    safe.write_text("OPENROUTER_API_KEY=\n")
    unsafe.write_text("OPENROUTER_API_KEY=" + "sk-or-v1-" + "abcdefghijklmnopqrstuvwxyz123456\n")

    secret_hits = check_backend.scan_openrouter_key_patterns([safe, unsafe], root)
    assert secret_hits == ["backend/config.txt"]
