"""Create the next ADR with consistent numbering, slug, and format."""

from __future__ import annotations

import re
from datetime import date

from .common import ADR_DIR, REPO_ROOT, ToolError, ok

TEMPLATE = """# {number:04d} {title}

- Status: Proposed
- Date: {date}

## Context

## Decision

## Consequences
"""


def register(subparsers) -> None:
    parser = subparsers.add_parser("new_adr", help="create the next numbered ADR")
    parser.add_argument("title", nargs="+", help="ADR title")


def _next_number(directory) -> int:
    highest = 0
    for path in directory.glob("*.md"):
        match = re.match(r"^(\d{4})-", path.name)
        if match:
            highest = max(highest, int(match.group(1)))
    return highest + 1


def _slugify(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def run(args) -> int:
    title = " ".join(args.title).strip()
    if not title:
        raise ToolError("ADR title is required")
    ADR_DIR.mkdir(parents=True, exist_ok=True)
    number = _next_number(ADR_DIR)
    slug = _slugify(title) or "decision"
    path = ADR_DIR / f"{number:04d}-{slug}.md"
    if path.exists():
        raise ToolError(f"ADR already exists: {path}")
    path.write_text(
        TEMPLATE.format(number=number, title=title, date=date.today().isoformat()),
        encoding="utf-8",
    )
    ok(f"created {path.relative_to(REPO_ROOT).as_posix()}")
    return 0
