"""`uv run python -m tools mutation_history check` — the history half of the probe guard.

See `tools/mutation_history.py` for why this cannot live in GDScript: git is unreachable
from a test at runtime, and `test_no_stranded_mutation.gd` reads the working tree only.
INC-0013 is the gap this closes.
"""

from __future__ import annotations

import argparse

from . import mutation_history
from .common import ToolError, fail, info, ok


def register(subparsers: argparse._SubParsersAction) -> None:
    parser = subparsers.add_parser(
        "mutation_history",
        help="find a mutation probe that reached a COMMIT, which the tree guard cannot see",
    )
    actions = parser.add_subparsers(dest="action", required=True)

    check = actions.add_parser("check", help="fail if any commit introduced a probe marker")
    check.add_argument(
        "--fail-on",
        choices=("warn", "error"),
        default="error",
        help="'warn' reports without failing (default: error)",
    )


def run(args: argparse.Namespace) -> int:
    if args.action != "check":
        raise ToolError(f"unknown action {args.action}")

    probes = mutation_history.sweep()
    if not probes:
        ok("no commit introduced a mutation probe into game/src or game/tests (INC-0013)")
        return 0

    info(f"{len(probes)} commit(s) introduced a probe marker into a guarded path:")
    for probe in probes:
        info(f"  {probe.commit[:12]}  {probe.path}  ({probe.shape})")
    detail = (
        "A committed probe is invisible to test_no_stranded_mutation.gd, which reads the "
        "working tree, so nothing else in the build can see it. Revert the marker and "
        "restore the intended line by hand - git restore and git checkout take every other "
        "agent's uncommitted work with them and have destroyed finished work here."
    )
    if args.fail_on == "error":
        fail(f"{detail} INC-0013: {len(probes)} committed probe(s)")
        return 1
    info(detail)
    return 0
