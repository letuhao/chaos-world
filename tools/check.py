"""Run the full gate in order: fmt --check, lint, arch, test."""

from __future__ import annotations

import subprocess
import sys

from .common import ADR_DIR, REPO_ROOT, fail, info, ok
from .new_adr import _numbered

STEPS: tuple[tuple[str, list[str]], ...] = (
    ("fmt", ["--check"]),
    ("lint", []),
    ("arch", []),
    ("deferred", ["validate"]),
    ("backlog", ["validate"]),
    ("data", ["audit"]),
    # The authored per-realm power table: one entry per realm, R1 at 1.0, strictly
    # rising, finite and readable. It replaced the one power ladder's guard (ADR 0050).
    ("realm_power", ["check"]),
    # The technique magnitude ladder (ADR 0055): a third per-realm table, bounded
    # by the work-budget floor on EVERY consecutive ratio rather than at its
    # endpoints, plus the learning-cost step that spends player progress. It runs
    # beside the power table because it must never be derived from it.
    ("technique_power", ["check"]),
    # Fast catalog checks: the projection must match the master JSONL, and every
    # registered option target must have an implemented consumer (ADR 0025/0033).
    ("data", ["options", "derive", "--check"]),
    ("data", ["options", "coverage", "--fail-on", "error"]),
    # The Python option generator's magnitude window must match the Godot runtime,
    # or the gate validates content against numbers the game never rolls. The
    # GDScript suite asserts the runtime side.
    ("data", ["options", "parity", "--check"]),
    # The body realm ladder's generation contract (30 realms, 60 acupoints, 20
    # meridians). Its guards live here rather than in a test so a hand-edited seed
    # cannot quietly desync from the ladder it is checked against.
    ("cultivation", ["validate"]),
    # ...and a guard nobody has seen fire is not a guard. Nine deliberate
    # mutations on a throwaway copy of the seeds, each asserted to be caught, so a
    # rule that goes vacuous fails the gate instead of waiting for the next
    # balance change to expose it.
    ("cultivation", ["mutate"]),
    # The acquisition graph: every realm's catalysts must resolve through authored
    # loot encounters and no domain may carry two encounters. Content that no
    # player can reach is still a green suite.
    ("acquisition", ["validate"]),
    ("test", []),
)


def register(subparsers) -> None:
    parser = subparsers.add_parser("check", help="run fmt --check, lint, arch, test in order")
    parser.add_argument("--keep-going", action="store_true", help="run all steps after a failure")


def _check_adr_numbers() -> bool:
    """One number per ADR. A shared number makes "ADR NNNN" ambiguous, and an
    agent following that citation cannot tell which decision it points at."""
    ok_flag = True
    for number, names in sorted(_numbered(ADR_DIR).items()):
        if len(names) > 1:
            ok_flag = False
            fail(f"ADR {number:04d} is shared by {len(names)} files: {', '.join(sorted(names))}")
    if ok_flag:
        ok("adr numbers unique")
    return ok_flag


def run(args) -> int:
    failed: list[str] = []
    info("== adr ==")
    if not _check_adr_numbers():
        failed.append("adr")
        if not args.keep_going:
            fail("gate failed: " + ", ".join(failed))
            return 1
    for name, extra in STEPS:
        info(f"== {name} ==")
        result = subprocess.run(
            [sys.executable, "-m", "tools", name, *extra],
            cwd=str(REPO_ROOT),
        )
        if result.returncode != 0:
            failed.append(name)
            if not args.keep_going:
                break
    if failed:
        fail("gate failed: " + ", ".join(failed))
        return 1
    ok("all checks passed")
    return 0
