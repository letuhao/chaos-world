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
    # A guard shipped in Python has no test of its own: the GDScript suite cannot reach it,
    # and nothing asserts it still goes RED. That is how gate_reach stayed blind to a
    # producer shape long enough to report four shipped triggers as dead with every gate
    # green (INC-0012). Each case asserts a RED path, because "the guard passes on today's
    # tree" is what check already does and proves nothing. Needs no engine, so it runs
    # first among the content audits.
    ("selftest", ["run"]),
    # Every environment_theme the map index ships must still have its prose in
    # map_assets.py. The prose is pasted verbatim into ComfyUI prompts and `migrate`
    # cannot refresh an existing value, so a shortened string leaves rows rendering
    # text the generator no longer holds - which is what 7bf3e4bc did to 260 rows with
    # every gate green (INC-0015). Needs no engine, so it runs with the content audits.
    ("map_theme", ["check"]),
    # The named cast (ADR 0138): one JSONL record per unique character, carrying
    # lore, personality, and a prose stat read. It is reference data the game never
    # reads, so the only thing that can go wrong is a malformed record or an image
    # that is gone — and the stat guard here is what stops a number entering a
    # prose block that no other gate can see. Needs no engine.
    ("unique_characters", ["check"]),
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

# Engine-free safety guards that must run BEFORE any stage a routine edit can red-flag.
#
# Same reasoning as the arch_rules hoist below, for the same reason: the STEPS loop breaks on
# the first failing stage, so a guard sitting after `fmt --check` is a guard one stray space
# can switch off. `mutation_history` used to live in STEPS, where a lint error in tools/
# skipped it silently - a committed mutation probe ships behaviour that is wrong while the
# whole build is green (BL-0615). It runs in the hoisted phase instead, and it costs ~150ms.
#
# ORDER within the hoisted phase is deliberate: the runaway guards go FIRST because machine
# damage (a 10 GB log, a 67 GB leak) is worse than wrong shipped behaviour, so a cheap
# engine-free failure must never be what stops them from running.
PREAMBLE_STEPS: tuple[tuple[str, list[str]], ...] = (
    # A mutation probe that reached a COMMIT. The working-tree half lives in
    # tests/arch_rules/test_no_stranded_mutation.gd and cannot see a ref, because git is
    # unreachable from GDScript at test time (INC-0013). Its gate is ref-TIP state, not
    # history: history is immutable, so an event-shaped gate is permanently red once a probe
    # is ever committed, and a permanently-red gate is a gate people learn to ignore.
    ("mutation_history", ["check"]),
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

    def _gate(name: str, passed: bool) -> bool:
        """Record a hoisted stage. Returns False when the gate must stop here.

        Every hoisted stage routes through this so the stop condition is stated once:
        a stage runs to completion before anything decides whether to bail out.
        """
        if passed:
            return True
        failed.append(name)
        if args.keep_going:
            return True
        fail("gate failed: " + ", ".join(failed))
        return False

    # ORDER is by blast radius, not by cost, and every stage here is engine-free.
    #
    # These guards cover the hazards that actually cost this machine time: the disk
    # flood and the 67 GB leak (INC-0001, INC-0002). Each loop below breaks on the
    # first failing stage, so anything ordered after a stage that routine work can
    # red-flag is a stage that does not run. Under the old order a single unformatted
    # string in tools/ stopped the gate before either guard executed, which is how a
    # cosmetic failure silently disarmed both (BL-0398).
    #
    # The ADR-number check ran FIRST here, and that reopened the same hole one level
    # up: a duplicate ADR number is doc hygiene, yet it returned 1 before either
    # runaway guard had spawned, so editing a filename could disarm the disk and leak
    # guards (BL-0632). Hygiene now goes LAST among the hoisted stages.
    #
    # The cost is honest and deliberate: a red tree now starts Godot before failing
    # fast on `fmt`. A guard that an unrelated lint error can switch off is not a
    # guard, and ~40s is cheaper than a 10 GB log or a power-cycle.
    info("== guards (arch_rules) ==")
    guard = subprocess.run(
        [sys.executable, "-m", "tools", "test", "--suite", "arch_rules"],
        cwd=str(REPO_ROOT),
    )
    if not _gate("guards", guard.returncode == 0):
        return 1
    for name, extra in PREAMBLE_STEPS:
        info(f"== {name} ==")
        preamble = subprocess.run(
            [sys.executable, "-m", "tools", name, *extra],
            cwd=str(REPO_ROOT),
        )
        if not _gate(name, preamble.returncode == 0):
            return 1
    info("== adr ==")
    if not _gate("adr", _check_adr_numbers()):
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
