#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
PBX = ROOT / "ios" / "BeautyConcierge.xcodeproj" / "project.pbxproj"
SCHEME = ROOT / "ios" / "BeautyConcierge.xcodeproj" / "xcshareddata" / "xcschemes" / "BeautyConcierge.xcscheme"

SECRET_PATTERNS = [
    re.compile(r"sk-or-v1-[A-Za-z0-9_-]{20,}"),
    re.compile(r"OPENROUTER_API_KEY[ \t]*=[ \t]*(?!$)(?!replace_with_secret_from_secret_manager)(?!replace-with-secret-manager-value)[A-Za-z0-9._/-]{12,}"),
]


def text_files():
    for path in ROOT.rglob("*"):
        if path.is_dir() or ".git" in path.parts or path.suffix.lower() in {".png", ".jpg", ".jpeg", ".zip", ".sqlite3"}:
            continue
        yield path


def main() -> int:
    pbx = PBX.read_text(errors="ignore")
    swift_files = sorted((ROOT / "ios" / "BeautyConcierge").rglob("*.swift"))
    missing = [str(path.relative_to(ROOT)) for path in swift_files if path.name not in pbx]
    ios_secret_refs = []
    for path in (ROOT / "ios").rglob("*"):
        if path.is_file() and path.suffix.lower() not in {".png", ".jpg", ".jpeg", ".md"}:
            text = path.read_text(errors="ignore")
            if "OPENROUTER_API_KEY" in text or "openrouter.ai" in text.lower():
                ios_secret_refs.append(str(path.relative_to(ROOT)))
    secret_hits = []
    for path in text_files():
        text = path.read_text(errors="ignore")
        for pattern in SECRET_PATTERNS:
            if pattern.search(text):
                secret_hits.append(str(path.relative_to(ROOT)))
                break
    print(f"swift_files={len(swift_files)}")
    print(f"missing_from_pbxproj={missing}")
    print(f"shared_scheme={SCHEME.exists()}")
    print(f"ios_openrouter_refs={ios_secret_refs}")
    print(f"secret_hits={secret_hits}")
    ok = not missing and SCHEME.exists() and not ios_secret_refs and not secret_hits
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
