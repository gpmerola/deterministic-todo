#!/usr/bin/env python3
"""Fail when a repository-local Markdown link points to a missing target."""

from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import unquote


ROOT = Path(__file__).resolve().parents[1]
LINK = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
REMOTE_SCHEMES = ("http://", "https://", "mailto:", "app://")


def local_target(document: Path, raw_target: str) -> Path | None:
    target = raw_target.strip()
    if target.startswith("<") and target.endswith(">"):
        target = target[1:-1]
    if not target or target.startswith("#") or target.startswith(REMOTE_SCHEMES):
        return None
    target = unquote(target.split("#", 1)[0])
    if not target:
        return None
    return (document.parent / target).resolve()


def broken_links() -> list[str]:
    failures: list[str] = []
    for document in sorted(ROOT.rglob("*.md")):
        if any(part in {".dart_tool", "build", ".git"} for part in document.parts):
            continue
        text = document.read_text(encoding="utf-8")
        for match in LINK.finditer(text):
            target = local_target(document, match.group(1))
            if target is not None and not target.exists():
                failures.append(
                    f"{document.relative_to(ROOT)}: missing {match.group(1)}"
                )
    return failures


def main() -> int:
    failures = broken_links()
    if failures:
        print("Broken local Markdown links:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1
    print("Documentation links: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
