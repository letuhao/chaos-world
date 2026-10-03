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
    # A hazard we hit and did not guard is a hazard waiting to repeat, so an
    # incident claiming to be handled must name the guard that handles it.
    ("incident", ["validate"]),
    ("backlog", ["validate"]),
    ("data", ["audit"]),
    # Can the authored world satisfy the gate it declares? A content census over
    # game/data, judged against the total every authored beat offers. Two event
    # stages asked for `need: 2` on a fact one beat supplies, and `EventApi.advance`
    # offers a stage's beats once on entry, so both ladders were dead while every
    # other gate validated clean. Needs no engine, so it runs with the other content
    # audits rather than after the suite. The writer set this census assumes is
    # pinned by tests/arch_rules/test_fact_ledger_writers.gd.
    ("gate_reach", ["check"]),
    # A mutation probe that reached a COMMIT. The working-tree half lives in
    # tests/arch_rules/test_no_stranded_mutation.gd and cannot see history, because git
    # is unreachable from GDScript at test time (INC-0013). Two real committed probes
    # were found the moment this shipped, so it is not theoretical. Needs no engine, so
    # it runs with the other content audits.
    ("mutation_history", ["check"]),
    # The authored per-realm power table: one entry per realm, R1 at 1.0, strictly
    # rising, finite and readable. It replaced the one power ladder's guard (ADR 0050).
    ("realm_power", ["check"]),
    # The technique magnitude ladder (ADR 0055): a third per-realm table, bounded
    # by the work-budget floor on EVERY consecutive ratio rather than at its
    # endpoints, plus the learning-cost step that spends player progress. It runs
    # beside the power table because it must never be derived from it.
    ("technique_power", ["check"]),
    # The difficulty preset table (ADR 0129): a CLOSED set of five scalars per preset, all
    # bounded, with the shipped default row exactly 1.0 so choosing the middle option is a
    # no-op. Shape only, and it runs beside the other two power-shaped guards because a sixth
    # column would be a fourth power curve wearing a difficulty label. A malformed preset must
    # fail in seconds rather than after the full suite.
    ("difficulty", ["check"]),
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
    # The entry point boots. `tools test` calls `_ready()` by hand and runs no
    # frame, so it cannot see a fault that needs the engine to deliver one: the
    # shell killed itself on frame 1 while the whole suite was green (BL-0359).
    # Placed before `test` so a shell that cannot start fails in two seconds
    # rather than after the full suite.
    ("boot", []),
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
    # The runaway guards run BEFORE every other stage, not as part of `test`.
    #
    # This loop breaks on the first failing stage, so anything ordered after a
    # stage that routine work can red-flag is a stage that does not run. Those guards
    # live in `arch_rules` and cover the two hazards that actually cost this machine
    # time: the disk flood and the 67 GB leak (INC-0001, INC-0002). Under the old
    # order a single unformatted string in tools/ stopped the gate before either
    # executed, which is how a cosmetic failure silently disarmed both.
    #
    # The cost is honest and deliberate: a red tree now starts Godot before failing
    # fast on `fmt`. A guard that an unrelated lint error can switch off is not a
    # guard, and ~40s is cheaper than a 10 GB log or a power-cycle.
    info("== guards (arch_rules) ==")
    guard = subprocess.run(
        [sys.executable, "-m", "tools", "test", "--suite", "arch_rules"],
        cwd=str(REPO_ROOT),
    )
    if guard.returncode != 0:
        failed.append("guards")
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
