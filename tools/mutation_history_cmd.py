"""`uv run python -m tools mutation_history check|report`.

`check` is the gate: it fails when the git INDEX - staged, or left unmerged by a rejected merge -
or a SHIPPED REF'S TIP carries a mutation probe marker in `game/src` or `game/tests`. Those are
the two things the working-tree half (`tests/arch_rules/test_no_stranded_mutation.gd`)
structurally cannot see, because it opens files on disk. `report` is the forensic half: it lists
commits that once introduced a probe, which is useful and can never be a gate, because history
is immutable.

See `tools/mutation_history.py` for why this cannot live in GDScript (git is unreachable from
a test at runtime, INC-0013), for why the gate is about current state rather than history, and
for the two index states `git grep --cached` cannot see (INC-0024).
"""

from __future__ import annotations

import argparse

from . import mutation_history
from .common import ToolError, fail, info, ok


def register(subparsers: argparse._SubParsersAction) -> None:
    parser = subparsers.add_parser(
        "mutation_history",
        help="fail if the index or a shipped ref tip carries a probe the tree guard cannot see",
    )
    actions = parser.add_subparsers(dest="action", required=True)

    check = actions.add_parser(
        "check",
        help="fail if the git index or any shipped ref tip carries a probe marker (the gate)",
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


def _is_shipped_ref(label: str) -> bool:
    """True when `label` names a ref that was actually resolved, rather than the index.

    An INDEX finding's label is the literal `INDEX_REF`, or `INDEX(conflict stage=N)`, so it
    starts with `INDEX_REF`; a real ref does not, because git names them `refs/heads/x` or
    `HEAD`. That prefix test is the whole classifier, and it is deliberately conservative in the
    direction that cannot lose a finding: anything unrecognised is reported as NOT a ref, so a
    label nobody anticipated still shows up under the "staged, not yet committed" headline,
    where a reader goes and looks at `git diff --cached` and finds it.

    The classifier lives here rather than in `mutation_history` because it is a REPORTING
    question. `mutation_history` must never decide a finding is a ref: an unresolvable label
    there would be a bug that silently drops a probe out of the report, which is the one
    outcome this whole module exists to prevent.
    """
    return not label.startswith(mutation_history.INDEX_REF)


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
        ok(
            "no staged or shipped probe marker in game/src or game/tests "
            "(index and ref tips, INC-0013/INC-0024)"
        )
        return 0

    staged_probes = [probe for probe in probes if not _is_shipped_ref(probe.ref)]
    ship_probes = [probe for probe in probes if _is_shipped_ref(probe.ref)]
    # The two are reported under their own headlines. A single "carried by a shipped ref tip"
    # line told the reader that an INDEX finding had already been committed, which is the
    # opposite of what it is: it is the one finding that has NOT been committed yet, and the one
    # with the cheapest repair. INC-0024 was caught by reading `git diff --cached`, by a human
    # who knew to look - the report has to tell the next reader which layer they are looking at,
    # or the layer that matters is the one that never gets mentioned.
    if staged_probes:
        info(
            f"{len(staged_probes)} probe marker(s) STAGED in the index, not yet committed. "
            f"Restage the file to clear this:"
        )
        for probe in staged_probes[: mutation_history.MAX_REPORTED]:
            info(f"  {probe.describe()}")
        if len(staged_probes) > mutation_history.MAX_REPORTED:
            info(f"  ...and {len(staged_probes) - mutation_history.MAX_REPORTED} more")
    if ship_probes:
        info(f"{len(ship_probes)} probe marker(s) carried by a shipped ref tip:")
        for probe in ship_probes[: mutation_history.MAX_REPORTED]:
            info(f"  {probe.describe()}")
        if len(ship_probes) > mutation_history.MAX_REPORTED:
            info(f"  ...and {len(ship_probes) - mutation_history.MAX_REPORTED} more")
    detail = (
        "A staged probe is invisible to test_no_stranded_mutation.gd, which reads the working "
        "tree, and to every ref reader, because the marker is in the index and not on disk and "
        "not in history yet - INC-0024 is exactly this: a fix-forward revert repaired the file "
        "and left the staged copy holding the probe, so `git diff` showed the repair and every "
        "reader looked at the repair. Restore the intended line BY HAND in the working tree and "
        "stage it again (`git add <that one path>`); `git restore`, `git checkout .` and "
        "`git reset` take every other agent's uncommitted work with them and have destroyed "
        "finished work here. A carried probe has the same fix, plus the repair has to reach a "
        "ref. Prose that NAMES a mutation is not a finding: only code in front of the marker, or "
        "a marker that is the first content of its comment, counts (see "
        "mutation_history.is_documentation)."
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
