"""Create the next ADR with consistent numbering, slug, and format."""

from __future__ import annotations

import re
from datetime import date
from pathlib import Path

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


# Concurrent `new_adr` in a shared tree is a real race, not a theoretical one. Two
# sessions both scan, both compute `max(used) + 1`, and both pick the same N. The old
# guard could not see that: `path.exists()` only refuses when the SLUG collides too, and
# two different titles never produce the same slug - so both files landed and the number
# was shared. 0183 and 0189 were both shared on disk before this was fixed.
# Both have since been renumbered (0183 -> 0194, 0189 -> 0196).
#
# There is no lock in `tools/common.py`, so uniqueness is established by REPAIR rather
# than by prevention: write with an exclusive create, then RE-READ the directory and, if
# someone else took the number in the gap between our scan and our write, delete our own
# brand-new file and allocate again. The re-read is what detects the loser - the scan we
# already did cannot, because it is the scan that raced.
MAX_ALLOCATE_ATTEMPTS = 5


def _write_exclusive(path: Path, text: str) -> None:
    """Create `path`, failing if it already exists. `x` never truncates, so a
    concurrent creator's file is never overwritten and a partial write is impossible."""
    with path.open("x", encoding="utf-8") as handle:
        handle.write(text)


def _display(path: Path) -> str:
    """The repo-relative path when the file lives in the repo, else its name.

    The obvious `path.relative_to(REPO_ROOT)` raises on any `ADR_DIR` outside the
    repository, which turns a *successful* allocation into a traceback and a non-zero
    exit — the file is on disk and the caller is told it failed, which is the one
    outcome worse than either. The allocator must not crash after doing its job.
    """
    try:
        return path.relative_to(REPO_ROOT).as_posix()
    except ValueError:
        return path.name


def run(args) -> int:
    title = " ".join(args.title).strip()
    if not title:
        raise ToolError("ADR title is required")
    ADR_DIR.mkdir(parents=True, exist_ok=True)
    slug = _slugify(title) or "decision"
    for _ in range(MAX_ALLOCATE_ATTEMPTS):
        used = _numbered(ADR_DIR)
        for number, names in sorted(used.items()):
            if len(names) > 1:
                warn(f"ADR {number:04d} is already shared by {', '.join(sorted(names))}")
        number = _next_number(used)
        path = ADR_DIR / f"{number:04d}-{slug}.md"
        # The same title twice is the author repeating themselves, not a race, so it
        # stays an error. Checked before the exclusive create so the two cases stay
        # distinguishable: this one is the caller's mistake, the other is contention.
        if path.exists():
            raise ToolError(f"ADR already exists: {path}")
        try:
            _write_exclusive(
                path, TEMPLATE.format(number=number, title=title, date=date.today().isoformat())
            )
        except FileExistsError:
            # A concurrent creator wrote this exact path between the check and the open.
            continue
        rivals = sorted(n for n in _numbered(ADR_DIR).get(number, ()) if n != path.name)
        if not rivals:
            ok(f"created {_display(path)}")
            return 0
        # We lost the allocation race. Remove OUR own brand-new file - ours alone, by
        # construction, since `x` created it microseconds ago - and try again against a
        # fresh scan, rather than leaving two files under one "ADR NNNN" citation.
        path.unlink()
    raise ToolError(
        f"no free ADR number after {MAX_ALLOCATE_ATTEMPTS} attempts; another session is "
        "creating ADRs faster than one can be allocated"
    )
