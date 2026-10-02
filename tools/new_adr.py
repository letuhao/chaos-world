"""Create the next ADR with consistent numbering, slug, and format."""

from __future__ import annotations

import re
from datetime import date

from .common import ADR_DIR, REPO_ROOT, ToolError, ok, warn

## The number an ADR file carries. Shared with the duplicate check in `tools check`
## so both agree on what counts as a number.
ADR_NUMBER_RE = re.compile(r"^(\d{4})-")

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


def _numbered(directory) -> dict[int, list[str]]:
    """Map every ADR number in use to the file names holding it.

    Two ADRs sharing a number is the failure this guards: an agent citing
    "ADR NNNN" then points at two different decisions, and neither reader can
    tell which one was meant.
    """
    used: dict[int, list[str]] = {}
    for path in directory.glob("*.md"):
        match = ADR_NUMBER_RE.match(path.name)
        if match:
            used.setdefault(int(match.group(1)), []).append(path.name)
    return used


def _next_number(used: dict[int, list[str]]) -> int:
    return max(used, default=0) + 1


def _slugify(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def run(args) -> int:
    title = " ".join(args.title).strip()
    if not title:
        raise ToolError("ADR title is required")
    ADR_DIR.mkdir(parents=True, exist_ok=True)
    used = _numbered(ADR_DIR)
    for number, names in sorted(used.items()):
        if len(names) > 1:
            warn(f"ADR {number:04d} is already shared by {', '.join(sorted(names))}")
    number = _next_number(used)
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
