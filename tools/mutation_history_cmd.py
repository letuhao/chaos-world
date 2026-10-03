"""`uv run python -m tools mutation_history check|report`.

`check` is the gate: it fails when a SHIPPED REF'S TIP carries a mutation probe marker in
`game/src` or `game/tests`, which is the one thing the working-tree half
(`tests/arch_rules/test_no_stranded_mutation.gd`) structurally cannot see. `report` is the
forensic half: it lists commits that once introduced a probe, which is useful and can never
be a gate, because history is immutable.

See `tools/mutation_history.py` for why this cannot live in GDScript (git is unreachable from
a test at runtime, INC-0013), and for why the gate is about tip state rather than history.
"""

from __future__ import annotations

import argparse

from . import mutation_history
from .common import ToolError, fail, info, ok


def register(subparsers: argparse._SubParsersAction) -> None:
    parser = subparsers.add_parser(
        "mutation_history",
        help="fail if a shipped ref's tip carries a probe the tree guard cannot see",
    )
    actions = parser.add_subparsers(dest="action", required=True)

    check = actions.add_parser(
        "check", help="fail if any shipped ref tip carries a probe marker (the gate)"
    )
    check.add_argument(
        "--fail-on",
        choices=("warn", "error"),
        default="error",
        help="'warn' reports without failing (default: error)",
    )

    actions.add_parser(
        "report",
        help="list commits that once introduced a probe; never gates, history is immutable",
    )


def _run_check(args: argparse.Namespace) -> int:
    if not mutation_history.readable():
        # Refusing to report `ok` here is the point. Every function in the module returns an
        # empty result when git fails, so an unreadable repository is indistinguishable from
        # a clean one - and a guard that says ok because it looked at nothing is the exact
        # shape of bug this file was first written with.
        fail(
            "cannot read the git repository, so the probe guard cannot prove anything. "
            "A guard that reports ok because it looked at nothing is not a guard."
        )
        return 1

    skipped = mutation_history.skipped_ref_namespaces()
    probes = mutation_history.carried()
    if skipped:
        # Printed rather than assumed: these are local-only refs, deliberately excluded so
        # the verdict is identical on every clone. Naming them keeps that a decision someone
        # can see rather than a silent blind spot.
        info(
            f"note: skipping {len(skipped)} agent-local ref namespace(s) "
            f"({', '.join(skipped)}); they are machine-local and not part of the repository"
        )

    if not probes:
        ok("no shipped ref tip carries a mutation probe in game/src or game/tests (INC-0013)")
        return 0

    info(f"{len(probes)} probe marker(s) carried by a shipped ref tip:")
    for probe in probes[: mutation_history.MAX_REPORTED]:
        info(f"  {probe.describe()}")
    detail = (
        "A carried probe is invisible to test_no_stranded_mutation.gd, which reads the "
        "working tree, so nothing else in the build can see it - that is how BL-0615 "
        "shipped a Mind breakthrough with no progress gate while the working tree stayed "
        "correct. Restore the intended line BY HAND in the working tree, then commit the "
        "repair: `git restore` and `git checkout` take every other agent's uncommitted work "
        "with them and have destroyed finished work here. This check goes green the moment "
        "the tip is clean, which is what makes it usable every commit."
    )
    if args.fail_on == "error":
        fail(f"{detail} INC-0013: {len(probes)} carried probe(s)")
        return 1
    info(detail)
    return 0


def _run_report() -> int:
    probes = mutation_history.sweep()
    if not probes:
        ok("no commit ever introduced a probe marker into game/src or game/tests")
        return 0
    info(f"{len(probes)} commit(s) once introduced a probe marker into a guarded path:")
    for probe in probes:
        info(f"  {probe.commit[:12]}  {probe.path}  ({probe.shape})")
    info(
        "This is history, so it cannot be a gate: once a probe is committed the answer is "
        "yes forever, and a permanently-red gate is a gate people learn to ignore. The gate "
        "is `check`, which asks whether a tip carries one RIGHT NOW."
    )
    return 0


def run(args: argparse.Namespace) -> int:
    if args.action == "check":
        return _run_check(args)
    if args.action == "report":
        return _run_report()
    raise ToolError(f"unknown action {args.action}")
