"""Red-path self-tests for the ADR number allocator.

Separate from `tools/new_adr.py` for the reason `tools/data_selftest.py` gives for
separating itself from `tools/data.py`: a tool is shipped code and a test of it is
not. `tools/selftest_cases.py` imports this module for the same reason it imports
`tools/data_selftest.py` — one line, so the registration stays greppable (INC-0016).

## The defect these exist for

`new_adr` allocated `max(used) + 1` and then guarded with `path.exists()`. That guard
only refuses when the *slug* collides too, and two agents writing two different titles
never produce the same slug — so both agents got the same number and both files landed.
"ADR NNNN" then cited two different decisions and neither reader could tell which.
0183 and 0189 were both shared on disk before this was fixed. Both have since been
renumbered (0183 -> 0194, 0189 -> 0196 on the fate-tag file, which kept the
number); the allocator fix is what stops the next one.

The fix cannot prevent the race — there is no lock in `tools/common.py` — so it repairs
afterwards: an exclusive create, then a RE-READ of the directory, and if a rival took the
number in the gap between our scan and our write, remove our own brand-new file and
allocate again. Only the re-read can see the loser; the scan that raced cannot.

## Every case asserts the INVARIANT, not the implementation

The property worth anything is "no number is held by two files", checked with the real
`_numbered` against real files on disk. Asserting that a particular warning was printed
would pass just as happily against a broken allocator that happened to be chatty.
"""

from __future__ import annotations

import argparse
import contextlib
import io
import tempfile
from collections.abc import Iterator
from pathlib import Path

from . import new_adr
from .common import ToolError
from .selftest import case, expect


@contextlib.contextmanager
def _redirect() -> Iterator[io.StringIO]:
    """Swallow the allocator's progress output so the harness reads only verdicts."""
    sink = io.StringIO()
    with contextlib.redirect_stdout(sink):
        yield sink


def _title(text: str) -> argparse.Namespace:
    return argparse.Namespace(title=text.split())


# An independent ceiling, not a read-back of the constant. Asserting
# `MAX_ALLOCATE_ATTEMPTS <= MAX_ALLOCATE_ATTEMPTS` would pass against any value at all,
# which is the vacuous guard INC-0016 is about. Deliberately well above the shipped 5
# so the case grades the property ("small") rather than the current number.
_MAX_ATTEMPTS_CEILING = 10


@contextlib.contextmanager
def _adr_dir_at(path: Path) -> Iterator[None]:
    """Point the allocator at a temp tree and put the real one back.

    Restoring in a `finally` is the whole point: a case that raised mid-assertion would
    otherwise leave the shipped `docs/adr/` pointing at a deleted temp directory, and the
    next `new_adr` in this process would write its ADR into the void.
    """
    original = new_adr.ADR_DIR
    new_adr.ADR_DIR = path
    try:
        yield
    finally:
        new_adr.ADR_DIR = original


@case("new_adr: a number another session took mid-flight is NOT left shared")
def _concurrent_allocation_repairs_itself() -> None:
    with tempfile.TemporaryDirectory() as raw:
        adr_dir = Path(raw)
        real_numbered = new_adr._numbered
        calls: list[int] = []

        def _rival_lands_on_the_second_scan(directory: Path) -> dict[int, list[str]]:
            """The real scan, with a concurrent creator landing between our two calls.

            Models the exact interleaving the old code could not survive. `run` scans to
            choose a number, writes, then re-reads; the rival appears in that gap, so
            only the second scan can see it. Creating the file for real (rather than
            returning a scripted dict) keeps the assertion honest — the invariant is
            then checked against actual filesystem state.
            """
            calls.append(1)
            if len(calls) == 2:
                (directory / "0001-a-concurrent-decision.md").write_text(
                    "# 0001 a concurrent decision\n", encoding="utf-8"
                )
            return real_numbered(directory)

        new_adr._numbered = _rival_lands_on_the_second_scan
        try:
            with _adr_dir_at(adr_dir), _redirect():
                new_adr.run(_title("a decision of ours"))
        finally:
            new_adr._numbered = real_numbered

        used = real_numbered(adr_dir)
        shared = sorted(n for n, names in used.items() if len(names) > 1)
        expect(
            len(calls) >= 2,
            "the allocator never re-read the directory after writing, so it cannot detect "
            "that another session claimed the number in the gap between our scan and our "
            "write; the rival in this fixture is created BY that re-read, so without it "
            "there is nothing here for the invariant below to catch",
        )
        expect(
            not shared,
            "the allocator left number "
            + ", ".join(f"{n:04d}" for n in shared)
            + " held by more than one file, so a citation to that ADR is ambiguous",
        )
        expect(
            (adr_dir / "0001-a-decision-of-ours.md").exists() is False,
            "our own file survived at the number the rival took; the repair must move us "
            "out rather than leave two files under one citation",
        )
        expect(
            (adr_dir / "0002-a-decision-of-ours.md").exists(),
            "after losing the race our file was deleted but never re-allocated, so the "
            "decision was lost outright",
        )


@case("new_adr: an uncontended directory still allocates the first number")
def _uncontended_allocation_starts_at_one() -> None:
    with tempfile.TemporaryDirectory() as raw:
        adr_dir = Path(raw)
        with _adr_dir_at(adr_dir), _redirect():
            new_adr.run(_title("the first decision"))

        expect(
            (adr_dir / "0001-the-first-decision.md").exists(),
            "a fresh directory must allocate 0001; anything else means the repair path "
            "changed the ordinary case",
        )


@case("new_adr: allocation never overwrites an ADR that is already there")
def _allocation_does_not_clobber_an_existing_file() -> None:
    with tempfile.TemporaryDirectory() as raw:
        adr_dir = Path(raw)
        existing = adr_dir / "0001-an-earlier-decision.md"
        existing.write_text("# 0001 an earlier decision\n", encoding="utf-8")
        with _adr_dir_at(adr_dir), _redirect():
            new_adr.run(_title("an unrelated decision"))

        expect(
            existing.read_text(encoding="utf-8") == "# 0001 an earlier decision\n",
            "creating an ADR overwrote a file that was already in the directory; the "
            "exclusive create is what makes that impossible",
        )
        expect(
            (adr_dir / "0002-an-unrelated-decision.md").exists(),
            "the new ADR did not land, so the previous assertion passed for the wrong "
            "reason — nothing was created at all",
        )


@case("new_adr: losing the race every time FAILS LOUDLY instead of spinning")
def _endless_contention_fails_within_its_budget() -> None:
    with tempfile.TemporaryDirectory() as raw:
        adr_dir = Path(raw)
        real_numbered = new_adr._numbered
        rival = 0

        def _a_rival_always_lands(directory: Path) -> dict[int, list[str]]:
            """A creator that claims our number on EVERY re-read, forever.

            The shape an unbounded repair loop would take: each attempt loses, so a
            version without `MAX_ALLOCATE_ATTEMPTS` never returns. What matters is that
            it stops and says so — AGENTS.md's rule is that a loop which cannot succeed
            must fail loudly, never spin.

            The rival is filed under OUR number, found by our slug. Filing it at the
            next free number instead would be a rival we beat every time, and the case
            would pass against a loop that never terminates.
            """
            nonlocal rival
            rival += 1
            ours = sorted(directory.glob("*-a-decision-nobody-can-place.md"))
            if ours:
                number = int(ours[-1].name[:4])
                (directory / f"{number:04d}-rival-{rival}.md").write_text("r\n", encoding="utf-8")
            return real_numbered(directory)

        new_adr._numbered = _a_rival_always_lands
        try:
            with _adr_dir_at(adr_dir), _redirect():
                failed = False
                try:
                    new_adr.run(_title("a decision nobody can place"))
                except ToolError:
                    failed = True
        finally:
            new_adr._numbered = real_numbered

        expect(
            failed,
            "contention that never clears was absorbed instead of raised, so the caller "
            "would believe an ADR was written when none was",
        )
        expect(
            new_adr.MAX_ALLOCATE_ATTEMPTS <= _MAX_ATTEMPTS_CEILING,
            f"the allocation budget is {new_adr.MAX_ALLOCATE_ATTEMPTS} attempts; AGENTS.md "
            f"requires a bounded, SMALL cap that names what failed to converge, so the "
            f"ceiling here is {_MAX_ATTEMPTS_CEILING}. A bound large enough to be worth "
            "raising is not a bound.",
        )
        expect(
            rival <= 2 * new_adr.MAX_ALLOCATE_ATTEMPTS,
            f"the allocator made {rival} scans against a budget of "
            f"{new_adr.MAX_ALLOCATE_ATTEMPTS} attempts (two scans each); the cap is not "
            "bounding anything",
        )
