"""`uv run python -m tools path_guard` — fail before a long path blocks a peer.

## Why this exists

INC-0031 recorded a commit failing with `Filename too long`, attributed to a
peer's asset path. **Measured, that attribution is wrong.** Windows MAX_PATH is 260
for the whole ABSOLUTE path, so what matters is `len(repo root) + len(relative)`.
This root is 27 characters, leaving 233. The longest tracked path is 182 absolute;
the file INC-0031 names is 77. A throwaway repo reproduces the boundary: a path
shaped like the named file (101) commits, one shaped like this tree's longest
(206) commits, and the first length that FAILS is 264.

So `core.longpaths` would not have prevented it, and the entry told a reader to go
looking for a shorter name for their own paths, which were never the problem.

The hazard is still real, though: paths accumulate without bound, and the first
symptom is a PEER's commit failing with a message that names their file and not
yours. That is the shape of a limit that arrives as a global side effect.

## What this does

It measures, and it reports the headroom. Nothing in the tree is renamed, and no
global config is set — both are decisions that belong to whoever owns the asset
pipeline, not to a guard. What a guard can do is make the margin VISIBLE while
there is still time to act on it, instead of after a peer is blocked.

The ceiling is the absolute path length, and the failure margin is deliberately
loose: git's own boundary measured 264 here, and Windows reports a path
operation as failing at a length that varies with what is being done to it. This
warns well before either, and fails only where the tree genuinely cannot commit.
"""

from __future__ import annotations

import argparse
import subprocess
import sys

from .common import REPO_ROOT, ToolError, fail, info, ok, warn

#: The absolute length beyond which a commit is at risk. Measured, not quoted: a
#: throwaway repo at this root length committed 254 and failed at 264.
CEILING = 260

#: Warn this far out. A path is easy to rename while it is a warning and awkward
#: once it is a peer's blocked commit.
MARGIN = 200


def longest_paths(limit: int = 8) -> list[tuple[int, str]]:
    """(absolute length, repo-relative path) for the longest tracked paths."""
    try:
        raw = subprocess.run(
            ["git", "ls-files", "-z"],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            timeout=120,
            check=False,
        ).stdout
    except (OSError, subprocess.SubprocessError) as exc:
        raise ToolError(f"could not list tracked paths: {exc}") from exc
    if not raw:
        raise ToolError("git ls-files returned nothing; run this from the repository")
    root = len(str(REPO_ROOT))
    entries = [(root + len(rel), rel) for rel in raw.split("\0") if rel.strip()]
    entries.sort(reverse=True)
    return entries[:limit]


def headroom() -> int:
    return CEILING - len(str(REPO_ROOT))


def register(subparsers) -> None:
    parser = subparsers.add_parser(
        "path_guard", help="report how much MAX_PATH headroom the tree has left"
    )
    parser.add_argument(
        "--limit", type=int, default=8, help="how many of the longest paths to print"
    )
    actions = parser.add_subparsers(dest="path_guard_action", required=True)
    check = actions.add_parser("check", help="fail if a tracked path is too long")
    check.add_argument("--limit", type=int, default=8)
    actions.add_parser("report", help="print the longest paths and the margin")


def _run_check(args: argparse.Namespace) -> int:
    entries = longest_paths(args.limit)
    if not entries:
        fail("no tracked paths found, so the measurement is vacuous")
        return 1
    over = [(n, rel) for n, rel in entries if n >= CEILING]
    near = [(n, rel) for n, rel in entries if MARGIN <= n < CEILING]

    for n, rel in near:
        warn(f"  {n:4} chars  {rel}")
    if near:
        warn(
            f"{len(near)} path(s) are past the {MARGIN}-char warning line and "
            f"{CEILING - len(str(REPO_ROOT))} from the limit."
        )

    if over:
        for n, rel in over:
            fail(f"  {n:4} chars  {rel}")
        fail(
            f"{len(over)} tracked path(s) are at or over MAX_PATH ({CEILING} absolute "
            "chars). A commit containing one of these will fail, and it will fail for "
            "whoever commits next rather than for whoever added the path — INC-0031."
        )
        return 1

    worst, worst_rel = entries[0]
    ok(
        f"longest tracked path is {worst} absolute chars, {CEILING - worst} from the "
        f"{CEILING} limit ({headroom()} available for a relative path)"
    )
    info(f"    {worst_rel[-90:]}")
    return 0


def _run_report(args: argparse.Namespace) -> int:
    print(f"repo root: {REPO_ROOT} ({len(str(REPO_ROOT))} chars)")
    print(f"MAX_PATH:  {CEILING} absolute chars")
    print(f"room left for a relative path: {headroom()}")
    print()
    for n, rel in longest_paths(args.limit):
        mark = "OVER" if n >= CEILING else ("near" if n >= MARGIN else "ok  ")
        print(f"  {n:4} {mark}  {rel}")
    return 0


def run(args) -> int:
    if args.path_guard_action == "check":
        return _run_check(args)
    if args.path_guard_action == "report":
        return _run_report(args)
    raise ToolError(f"unknown path_guard action: {args.path_guard_action}")


if __name__ == "__main__":  # pragma: no cover - the dispatcher owns this
    print("run me as: uv run python -m tools path_guard check", file=sys.stderr)
