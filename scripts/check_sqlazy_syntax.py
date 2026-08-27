#!/usr/bin/env python3
"""Fail when an NSPL conditional aggregate uses the deprecated prefix form."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
DEPRECATED = re.compile(r"\bcondition\b.*\bsum\b.*\bas\b", re.IGNORECASE)
TRAILING_CONDITION = re.compile(r"^\s*condition\b", re.IGNORECASE)
SUM_ALIAS = re.compile(r"\bsum\b.*\bas\b", re.IGNORECASE)


def split_top_level_clauses(text: str) -> list[str]:
    clauses: list[str] = []
    current: list[str] = []
    depth = 0
    quote: str | None = None
    escaped = False

    for char in text:
        if quote is not None:
            current.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = None
            continue

        if char in {'"', "'"}:
            quote = char
            current.append(char)
        elif char == "(":
            depth += 1
            current.append(char)
        elif char == ")":
            depth = max(0, depth - 1)
            current.append(char)
        elif depth == 0 and char in {",", ";", "\n"}:
            clauses.append("".join(current).strip())
            current = []
        else:
            current.append(char)

    clauses.append("".join(current).strip())
    return [clause for clause in clauses if clause]


def main() -> int:
    failures: list[str] = []

    for path in sorted(ROOT.rglob("*.nspl")):
        relative = path.relative_to(ROOT)
        clauses = split_top_level_clauses(path.read_text(encoding="utf-8"))
        for index, clause in enumerate(clauses):
            if DEPRECATED.search(clause):
                failures.append(f"{relative}: deprecated conditional aggregate: {clause}")
            if TRAILING_CONDITION.search(clause):
                previous = clauses[index - 1] if index else ""
                if not SUM_ALIAS.search(previous):
                    failures.append(
                        f"{relative}: trailing condition is not preceded by a named sum: {clause}"
                    )

    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1

    print("Current SQLazy trailing-condition syntax: PASS")
    print("Deprecated syntax remaining: 0")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
