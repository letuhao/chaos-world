"""`uv run python -m tools selftest` — regression tests for the guards that live in Python.

## Why this exists

Every guard in `tools/` is a Python module, and CI runs exactly `uv run python -m tools
check`. That means a guard shipped here has no test of its own: the GDScript suite cannot
reach it, and nothing asserts that it still goes RED. The failure this leaves open is the
worst kind for a validator — a guard that has been quietly loosened. `gate_reach` is the
proof: it was blind to a producer shape for long enough to report four shipped event
triggers as permanently dead, and every gate in the repo stayed green while it did
(INC-0012).

So each test here asserts a **red path**, not a happy path. "The guard passes on today's
tree" proves nothing, because today's tree is the input it was written against. What
matters is that a guard still fails when it should, so these build a broken fixture, point
the guard at it, and assert a non-zero verdict.

## What this deliberately does not do

It does not replace `tools check`. It runs first and fast, needs no engine and no network,
and touches nothing on disk outside `tempfile`. Fixtures are written to a temporary
directory and the real repository is never modified — a test that edits the working tree to
prove a point is the stranded-mutation hazard wearing a different hat.
"""

from __future__ import annotations

import argparse
import traceback
from collections.abc import Callable
from dataclasses import dataclass, field
from pathlib import Path

from .common import fail, ok

CASES: list[tuple[str, Callable[[], None]]] = []

## Validators in `tools/` that have no red-path case yet.
##
## INC-0016: adding a validator here means adding its red path, because "it passes
## on today's tree" is what `check` already does and proves nothing. This is the
## receipt for the ones that have not paid that cost yet, so the gap is stated
## rather than implied — the previous wording claimed *every* guard was covered
## while `boot` was not, which is a guard overstating its own coverage.
##
## Named explicitly rather than derived from the command table: deciding which
## subcommands are guards is itself a fact, and deriving a second copy of it here
## is the ADR 0066 failure mode.
UNCOVERED_GUARDS: tuple[str, ...] = ("boot",)


def _gap_note() -> str:
    """Name the validators still owing a red path, or "" when there are none."""
    if not UNCOVERED_GUARDS:
        return ""
    return "; no red-path case yet for: " + ", ".join(UNCOVERED_GUARDS)


def case(name: str) -> Callable[[Callable[[], None]], Callable[[], None]]:
    """Register a test. The name is what a failure reports, so make it say the claim."""

    def wrap(fn: Callable[[], None]) -> Callable[[], None]:
        CASES.append((name, fn))
        return fn

    return wrap


class Failure(AssertionError):
    """A test's own assertion failed. Distinct from an exception, which is a bug in the
    guard rather than a guard declining to fire."""


def expect(condition: bool, message: str) -> None:
    if not condition:
        raise Failure(message)


def write(path: Path, text: str) -> Path:
    """Write `text` to `path`, creating parents. Returns the path so a caller can keep it."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return path


@dataclass
class Report:
    passed: int = 0
    failures: list[tuple[str, str]] = field(default_factory=list)
    errors: list[tuple[str, str]] = field(default_factory=list)


def run_all() -> Report:
    report = Report()
    for name, fn in CASES:
        try:
            fn()
        except Failure as exc:
            report.failures.append((name, str(exc)))
        except Exception:  # noqa: BLE001 - an exception is a defect in the guard
            report.errors.append((name, traceback.format_exc(limit=4)))
        else:
            report.passed += 1
    return report


def register(subparsers: argparse._SubParsersAction) -> None:
    parser = subparsers.add_parser(
        "selftest", help="regression tests for the guards that live in Python"
    )
    actions = parser.add_subparsers(dest="action", required=True)
    actions.add_parser("run", help="run every self-test (default)")


def run(args: argparse.Namespace) -> int:
    if args.action != "run":
        from .common import ToolError

        raise ToolError(f"unknown action {args.action}")

    report = run_all()
    for name, detail in report.failures:
        fail(f"{name}\n      {detail}")
    for name, detail in report.errors:
        fail(f"{name}\n      raised instead of asserting\n      {detail}")

    if report.failures or report.errors:
        fail(
            f"{len(report.failures)} assertion(s) and {len(report.errors)} error(s) "
            f"across {len(CASES)} self-tests"
        )
        return 1

    ok(f"{report.passed} guard self-tests still go red when they should{_gap_note()}")
    return 0
