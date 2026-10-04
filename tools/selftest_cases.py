"""The self-test cases themselves: one per guard, each asserting that guard still goes RED.

Kept apart from `tools/selftest.py` so the harness stays readable and the claims stay
greppable. Every case builds a fixture in a temporary directory and points the guard at it;
none of them edits the repository.

A happy-path test here would be worth very little. "map_theme check passes" is asserted by
`tools check` on every run. What nobody was checking is the part that matters: that the
guard still FAILS when the world is broken. A validator that has been loosened does not
announce itself — it reports `ok` on a tree it should have rejected, which is the ADR 0066
quiet lie with a non-zero exit code attached.
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import subprocess
import tempfile
from datetime import UTC, datetime, timedelta
from pathlib import Path

from . import (
    boot,
    claim_guard,
    common,
    gate_reach,
    godot,
    godot_bypass,
    loop_guard,
    lore,
    map_theme,
    mutation_history,
    mutation_history_cmd,
    unique_characters,
)
from .acquisition import selftest_case  # noqa: F401  registers its cases on import
from .common import ToolError
from .cultivation import selftest_case as cultivation_selftest_case  # noqa: F401  same
from .lore.context import character_draft, readiness_gaps, resolve_context
from .selftest import case, expect, write

# A roster class that hands its ids onward, and one that declares a table nothing reads.
_DISPATCHING_ROSTER = """
class_name FixtureAmbient
extends RefCounted

const ROSTER: Array[Dictionary] = [
	{{"fact": &"one_sighted", "at_period": 1}},
	{{"fact": &"two_sounded", "at_period": 2}},
]

static func due(actor, horizon: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for row in ROSTER:
		if int((row as Dictionary).get("at_period", 0)) > horizon:
			continue
		out.append(StringName((row as Dictionary).get("fact", &"")))
	return out
"""

_ORPHAN_ROSTER = """
class_name FixtureOrphan
extends RefCounted

const ROSTER: Array[Dictionary] = [
	{{"fact": &"never_produced", "at_period": 1}},
]
"""

# The dispatcher: iterates the roster class's answer into `offer`, which is the shipped
# reachability shape (world_pulse -> BeatDirector -> WorldFact.record).
_DISPATCHER = """
class_name FixturePulse
extends RefCounted

var _actor = null

func _offer_ambient(horizon: int) -> void:
	for fact in FixtureAmbient.due(_actor, horizon):
		offer(fact, 1, "fixture")


func offer(fact: StringName, amount: int = 1, source: String = "") -> Dictionary:
	var report := _director.offer(_actor, fact)
	return report
"""


def _git(root: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ("git", *args),
        cwd=root,
        check=True,
        capture_output=True,
        text=True,
    )


def _sweep_in(root: Path) -> list:
    """Sweep `root`'s history instead of the repository's."""
    original = mutation_history.REPO
    mutation_history.REPO = root
    try:
        return mutation_history.sweep()
    finally:
        mutation_history.REPO = original


def _supply_against(src: Path) -> dict:
    """Run `code_owned_supply` over a fixture tree instead of the repository.

    Both roots are redirected: `SRC_DIR` decides which files are read and `GAME_DIR` is
    what each hit is reported relative to, so patching only one leaves the walk resolving
    paths outside the real tree and raises rather than reporting.
    """
    supply: dict = {}
    original = gate_reach.SRC_DIR, gate_reach.GAME_DIR
    gate_reach.SRC_DIR, gate_reach.GAME_DIR = src, src.parent
    try:
        gate_reach.code_owned_supply(supply)
    finally:
        gate_reach.SRC_DIR, gate_reach.GAME_DIR = original
    return supply


@case("gate_reach: a roster nothing dispatches is NOT counted as supply")
def _roster_without_a_dispatcher_is_not_supply() -> None:
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        src = root / "src"
        write(src / "app" / "fixture_ambient.gd", _ORPHAN_ROSTER)
        write(src / "app" / "fixture_pulse.gd", _DISPATCHER)

        supply = _supply_against(src)
        expect(
            "never_produced" not in supply,
            "a table of fact ids that no dispatcher reads was counted as supply, so a "
            "gate nothing satisfies would report as satisfiable",
        )


@case("gate_reach: a roster a dispatcher DOES reach IS counted as supply")
def _dispatched_roster_is_supply() -> None:
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        src = root / "src"
        write(src / "app" / "fixture_ambient.gd", _DISPATCHING_ROSTER)
        write(src / "app" / "fixture_pulse.gd", _DISPATCHER)

        supply = _supply_against(src)
        for fact in ("one_sighted", "two_sounded"):
            expect(
                fact in supply,
                f"{fact} is produced by a dispatched roster but the census cannot see it, "
                "which is INC-0012: a gate reported dead while its producer was running",
            )


@case("gate_reach: an UNREACHABLE code writer keeps its gate red")
def _unreachable_code_writer_stays_red() -> None:
    """The property `REPEATABLE` exists to protect.

    A code-owned producer is a verb, so its ceiling depends on how many times the game can
    call it — but only if something calls it. `SectDuty.serve` discharged obligations
    correctly with zero production callers, and a census that counted its three terms would
    report a `need: 3` gate satisfiable by a verb nothing drives.
    """
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        src = root / "src"
        write(
            src / "modules" / "sect" / "sect_facts.gd",
            "class_name SectFacts\nextends RefCounted\n\n"
            'const FACT := &"oaths"\n\n\n'
            "static func record(actor: Actor) -> Dictionary:\n"
            "\treturn WorldFact.record(actor, FACT, 1)\n",
        )

        supply = _supply_against(src)
        row = supply.get("oaths")
        expect(row is not None, "the code-owned writer was not counted at all")
        expect(
            not row.repeatable,
            "a writer nothing outside its own module calls was marked repeatable, so a "
            "need:3 gate would read satisfiable by a verb nobody drives",
        )


@case("gate_reach: a REACHABLE code writer has no ceiling")
def _reachable_code_writer_is_repeatable() -> None:
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        src = root / "src"
        write(
            src / "modules" / "sect" / "sect_facts.gd",
            "class_name SectFacts\nextends RefCounted\n\n"
            'const FACT := &"oaths"\n\n\n'
            "static func record(actor: Actor) -> Dictionary:\n"
            "\treturn WorldFact.record(actor, FACT, 1)\n",
        )
        # The driver lives OUTSIDE modules/sect/, which is the whole condition.
        write(src / "app" / "tick.gd", "SectFacts.record(actor)\n")

        supply = _supply_against(src)
        row = supply.get("oaths")
        expect(row is not None, "the code-owned writer was not counted at all")
        expect(
            row.repeatable,
            "a writer the composition root drives was still capped at one occurrence, so a "
            "need:3 gate would read dead while the game can plainly discharge three terms",
        )


@case("map_theme: a shipped theme with no authored prose FAILS the check")
def _shipped_theme_without_prose_fails() -> None:
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        index = write(root / "assets" / "map-asset-index.jsonl", "")
        index.write_text(
            '{"environment": "mortal_plains", "environment_theme": "A theme nobody authored."}\n',
            encoding="utf-8",
        )

        original_index, original_themes = map_theme.INDEX, map_theme.ENVIRONMENT_THEMES
        map_theme.INDEX = index
        map_theme.ENVIRONMENT_THEMES = {"mortal_plains": "The prose that IS authored."}
        try:
            # Call the guard's own comparison, and let it build `authored` itself. Passing
            # the set in was the earlier mistake: it let MUTATION-S2 (values() -> keys())
            # pass, because the test supplied the very value under test.
            missing = map_theme.unbacked(map_theme.index_themes())
        finally:
            map_theme.INDEX, map_theme.ENVIRONMENT_THEMES = original_index, original_themes
        expect(
            "A theme nobody authored." in missing,
            "a theme shipped in the index with no matching prose in map_assets.py was "
            "accepted, which is how 7bf3e4bc desynced 260 rows with every gate green",
        )


@case("map_theme: a row whose theme IS the environment key is still unbacked")
def _key_shaped_theme_is_unbacked() -> None:
    """The only fixture that can tell `values()` from keys.

    The first version of this suite asserted a row whose `environment_theme` was prose
    absent from the source. That fixture passes under BOTH readings, because the key
    (`mortal_plains`) is not the row's text either way - so MUTATION-S2, swapping the
    guard's `values()` for the dict itself, left all seven self-tests green. A guard test
    whose fixture cannot distinguish the two readings tests nothing about the reading.

    Here the row's theme text is deliberately the KEY. Under `values()` it is unbacked,
    because the generator can only ever emit the prose; under keys() it looks satisfied.
    A theme equal to its own name is the one case where "a name is not the text a
    renderer receives" is actually load-bearing.
    """
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        index = write(root / "assets" / "map-asset-index.jsonl", "")
        index.write_text(
            '{"environment": "mortal_plains", "environment_theme": "mortal_plains"}\n',
            encoding="utf-8",
        )

        original_index, original_themes = map_theme.INDEX, map_theme.ENVIRONMENT_THEMES
        map_theme.INDEX = index
        map_theme.ENVIRONMENT_THEMES = {"mortal_plains": "Warm ochre loam and worn farm roads."}
        try:
            missing = map_theme.unbacked(map_theme.index_themes())
        finally:
            map_theme.INDEX, map_theme.ENVIRONMENT_THEMES = original_index, original_themes

        expect(
            "mortal_plains" in missing,
            "a row holding the environment KEY rather than the authored prose was accepted, "
            "so the guard compared names instead of the text a renderer receives - the "
            "exact mistake that reports all 19 themes missing when it happens in reverse",
        )


@case("map_theme: a vacuous index FAILS rather than passing empty")
def _vacuous_index_fails() -> None:
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        index = write(root / "assets" / "map-asset-index.jsonl", '{"environment": "x"}\n')
        original = map_theme.INDEX
        map_theme.INDEX = index
        try:
            counts = map_theme.index_themes()
        finally:
            map_theme.INDEX = original

        expect(
            not counts,
            "an index naming no environment_theme produced a non-empty count, so the "
            "guard's own vacuity check cannot work",
        )


@case("mutation_history: a committed probe is found by content, not by name")
def _committed_probe_is_found() -> None:
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        _git(root, "init", "-q")
        _git(root, "config", "user.email", "selftest@local")
        _git(root, "config", "user.name", "selftest")
        write(
            root / "game" / "src" / "thing.gd",
            "extends RefCounted\n\n\nfunc ok() -> bool:\n\treturn true\n",
        )
        _git(root, "add", "-A")
        _git(root, "commit", "-qm", "base")
        probe = write(
            root / "game" / "src" / "thing.gd",
            "extends RefCounted\n\n\nfunc ok() -> bool:\n\treturn true\n\n# MUTATION-SELFTEST\n",
        )
        _git(root, "add", "-A")
        _git(root, "commit", "-qm", "probe")
        head = _git(root, "rev-parse", "HEAD").stdout.strip()
        # Hand the probe back, the way the real tree would be handed it.
        write(
            root / "game" / "src" / "thing.gd",
            probe.read_text(encoding="utf-8").replace("# MUTATION-SELFTEST\n", ""),
        )

        found = _sweep_in(root)
        expect(
            any(p.commit == head for p in found),
            "a probe committed to a guarded path was not reported, so a mutation that "
            "reached history would be invisible forever (INC-0013)",
        )


@case("mutation_history: the tree's prose about mutation survives")
def _prose_is_not_a_probe() -> None:
    prose = [
        "MUTATE-PROVE deliberately break the implementation",
        "the mutations that survived, which are the findings",
        "const MUTATING_VERBS := [",
        "the bare MUTATE in spine.gd",
    ]
    for text in prose:
        expect(
            mutation_history._marker_in(text) is None,
            f"legitimate prose was flagged as a probe: {text!r}. The shapes are "
            "deliberately narrow so the tree's own writing about mutation survives",
        )


@case("mutation_history: every real marker shape is caught")
def _every_shape_is_caught() -> None:
    shapes = [
        "# MUTATION-SELFTEST",
        "// MUTATION-SELFTEST",
        "MUTATION-SELFTEST",
        "MUTATION PROBE",
        "XXX MUTAT",
    ]
    for text in shapes:
        expect(
            mutation_history._marker_in(text) is not None,
            f"a real marker shape was missed: {text!r}. A shape that stops matching is a "
            "guard that has gone blind while still reporting ok",
        )


def _carried_in(root: Path) -> list:
    """Sweep `root`'s ref tips instead of the repository's."""
    original = mutation_history.REPO
    mutation_history.REPO = root
    try:
        return mutation_history.carried()
    finally:
        mutation_history.REPO = original


def _probe_repo(root: Path) -> tuple[Path, Path]:
    """A repository whose HEAD tip carries a probe marker. Returns (root, the file)."""
    _git(root, "init", "-q")
    _git(root, "config", "user.email", "selftest@local")
    _git(root, "config", "user.name", "selftest")
    thing = root / "game" / "src" / "thing.gd"
    write(thing, "extends RefCounted\n\n\nfunc ok() -> bool:\n\treturn true\n")
    _git(root, "add", "-A")
    _git(root, "commit", "-qm", "base")
    write(
        thing,
        "extends RefCounted\n\n\nfunc ok() -> bool:\n\treturn true\n\n# MUTATION-SELFTEST\n",
    )
    _git(root, "add", "-A")
    _git(root, "commit", "-qm", "probe")
    return root, thing


@case("mutation_history: a probe carried by a ref TIP is found")
def _carried_probe_is_found() -> None:
    with tempfile.TemporaryDirectory() as raw:
        root, _ = _probe_repo(Path(raw))

        found = _carried_in(root)
        expect(
            bool(found),
            "a ref tip carrying a probe was reported clean, so a probe that reached a commit "
            "stays invisible forever (BL-0615: the working tree was correct the whole time, "
            "which is exactly why nobody noticed HEAD was broken)",
        )
        expect(
            all(probe.path == "game/src/thing.gd" for probe in found),
            f"the finding named the wrong path, so it cannot be acted on: {found}",
        )


@case("mutation_history: a REPAIRED tip is clean, so the gate can go green")
def _repaired_tip_is_clean() -> None:
    # The property the gate depends on, and the reason it is not `git log -S`. History is
    # immutable, so "did any commit ever carry a probe" is permanently yes once true - the
    # first version of this guard shipped exactly that way and `tools check` could never pass
    # again, which is worth less than no guard at all. State is what can go green.
    with tempfile.TemporaryDirectory() as raw:
        root, thing = _probe_repo(Path(raw))
        expect(bool(_carried_in(root)), "fixture did not start dirty, so this case proves nothing")
        write(
            thing,
            "extends RefCounted\n\n\nfunc ok() -> bool:\n\treturn true\n",
        )
        _git(root, "add", "-A")
        _git(root, "commit", "-qm", "repair")

        expect(
            not _carried_in(root),
            "a tip whose probe was repaired still reads as dirty, so the gate is permanently "
            "red and a guard that can never pass is a guard people learn to ignore",
        )
        expect(
            bool(_sweep_in(root)),
            "the probe left no forensic trace once repaired, so there is no way to learn which "
            "commit introduced it - `report` exists for exactly that question",
        )


@case("mutation_history: a probe reachable only from an AGENT-LOCAL ref is ignored")
def _agent_local_refs_do_not_gate() -> None:
    # `refs/stash`, `refs/recovery/*` and `refs/codex/*` are one machine's transient state
    # and exist in no clone, so a guard that reads them is not reproducible: the same commit
    # is red here and green for a colleague. INC-0013's second probe was a dropped stash,
    # reachable only through refs/recovery, and it is what pinned the old gate red forever.
    with tempfile.TemporaryDirectory() as raw:
        root, _ = _probe_repo(Path(raw))
        probe_commit = _git(root, "rev-parse", "HEAD").stdout.strip()
        base = _git(root, "rev-parse", "HEAD~1").stdout.strip()
        _git(root, "update-ref", "refs/recovery/stash-selftest", probe_commit)
        _git(root, "update-ref", "refs/heads/master", base)

        # The index is excluded from that claim on purpose, and reporting it is CORRECT: moving
        # HEAD back to the base commit left the probe staged against nothing shipped, which is
        # precisely the one-commit-from-history state the index half exists to catch.
        expect(
            not [p for p in _carried_in(root) if p.ref != mutation_history.INDEX_REF],
            "a machine-local recovery ref gated the build, so the verdict depends on invisible "
            "local state and differs between this machine and every clone",
        )


# --- The documentation cut. The gate was permanently red on FALSE POSITIVES: three shipped
# --- lines that NAME a mutation id in the middle of a sentence, while the tree was correct.

#: Transcribed from game/tests/modules/mind_cultivation/test_mind_stat_reachability.gd, which
#: is where the gate actually went red. Every one is a whole-line comment naming a mutation
#: that was applied and reverted; none is a probe.
PROSE_ABOUT_MUTATIONS: tuple[str, ...] = (
    "## assertion about the mechanism still passes. MUTATION-B (the defence published",
    "## regression MUTATION-A below reproduces.",
    "\t# and leaves the defence this module published. MUTATION-A (meridian_power",
)

#: A probe as BL-0615 wrote it: real code, then the marker. The one line that must stay red.
PROBE_TRAILING_CODE = "\tif not is_bound() and false:  # MUTATION-M6"

PROBE_PATH = "game/src/modules/techniques/technique_delivery.gd"
PROSE_PATH = "game/tests/modules/mind_cultivation/test_mind_stat_reachability.gd"


def _tip_holding(root: Path, *files: tuple[str, str]) -> Path:
    """A repository whose ONE commit holds exactly `files`, each `(repo path, content)`."""
    _git(root, "init", "-q")
    _git(root, "config", "user.email", "selftest@local")
    _git(root, "config", "user.name", "selftest")
    for path, text in files:
        write(root / path, text)
    _git(root, "add", "-A")
    _git(root, "commit", "-qm", "fixture")
    return root


@case("mutation_history: a marker trailing CODE is live; prose naming one is not")
def _prose_is_not_carried_and_code_still_is() -> None:
    """The red path for the documentation cut, and both halves in ONE tip on purpose.

    A fixture holding only the prose passes under a guard with no filter at all - it reports
    nothing and there is no claim left to fail. A fixture holding only the probe passes under
    a filter that dropped every line. Only a tip holding both can tell the two readings apart,
    and only the real cut returns exactly one finding.
    """
    with tempfile.TemporaryDirectory() as raw:
        root = _tip_holding(
            Path(raw),
            (PROBE_PATH, f"func is_bound() -> bool:\n\treturn true\n{PROBE_TRAILING_CODE}\n"),
            (PROSE_PATH, "\n".join(PROSE_ABOUT_MUTATIONS) + "\n"),
        )
        found = _carried_in(root)

        # One finding per LAYER, not one overall. This fixture COMMITS the probe, so the index
        # holds the same live line and both readers report it - two facts about one tree, not a
        # duplicate. Collapsing them to one would leave the index's cut untested here, and two
        # layers classifying one line differently is the drift this module's design rules out.
        staged = [p for p in found if p.ref == mutation_history.INDEX_REF]
        tips = [p for p in found if p.ref != mutation_history.INDEX_REF]
        expect(
            len(staged) == 1 and len(tips) == 1,
            f"a tip holding one live probe and three prose lines returned {len(staged)} index "
            f"and {len(tips)} tip finding(s): {[probe.describe() for probe in found]}. The gate "
            "must separate a marker trailing code from a sentence that NAMES a mutation, in BOTH "
            "layers: one report per layer is the guard working, and any other count is a filter "
            "that was never installed",
        )
        expect(
            all(probe.path == PROBE_PATH for probe in found),
            f"the wrong line was reported: {[probe.describe() for probe in found]}",
        )


@case("mutation_history: a marker that IS its comment's first content is still live")
def _labelled_probe_comment_is_live() -> None:
    """The half of the cut a blanket comment exemption would over-reach.

    `is_documentation` reads "no code in front of the marker" as documentation, so the
    obvious failure is exempting every comment: the incident's own `#MUTATION-M1` and the
    tree guard's `# MUTATION-M4 removed` would both read as prose. These are the shapes an
    agent actually writes, because a probe's comment exists to be found by grepping it -
    which is why the marker comes FIRST.

    `var x := 1  # MUTATION-M4` is here too, and it is the case that makes this a cut rather
    than a comment exemption: a comment before the marker, and code before the comment.
    """
    for line in (
        "#MUTATION-SELFTEST",
        "# MUTATION-SELFTEST",
        "## MUTATION-SELFTEST",
        "###   MUTATION PROBE",
        "// MUTATION-SELFTEST",
        "\t# XXX MUTAT",
        "var x := 1  # MUTATION-SELFTEST",
        PROBE_TRAILING_CODE,
    ):
        expect(
            mutation_history._live_marker(line) is not None,
            f"a live probe shape was read as documentation: {line!r}. The filter exempts a "
            "comment that TALKS ABOUT a mutation; a comment that IS the probe stays red",
        )

    for line in ("MUTATION-SELFTEST", "\t\tMUTATION-SELFTEST", "\t\tMUTATION PROBE"):
        expect(
            mutation_history._live_marker(line) is None,
            f"a bare marker with nothing but whitespace before it was read as a live probe: "
            f"{line!r}. In GDScript that offset is the first line of a multi-line string, and "
            "a tombstone string is documentation - pinning it keeps the cut from growing a "
            "second, looser reading later",
        )


@case("mutation_history: each shipped prose line is documentation, on its own")
def _shipped_prose_lines_are_documentation() -> None:
    for line in PROSE_ABOUT_MUTATIONS:
        expect(
            mutation_history._live_marker(line) is None,
            f"a shipped line that NAMES a mutation was read as a live probe: {line!r}. The "
            "gate was red on these while the tree was correct, which is the state-not-history "
            "failure arriving by the other door - a permanently-red gate is a gate people "
            "learn to ignore, and the next agent to hit it deletes it",
        )


# --- The INDEX. One commit from history, and invisible to every reader that opens the file ---


def _staged_in(root: Path) -> list:
    """Read `root`'s git index instead of the repository's."""
    original = mutation_history.REPO
    mutation_history.REPO = root
    try:
        return mutation_history.staged()
    finally:
        mutation_history.REPO = original


_CLEAN_PROBE_FILE = "func is_bound() -> bool:\n\treturn true\n"
_CLEAN_PROSE_FILE = "## the defence this module published is asserted below.\n"


def _staged_probe_repo(root: Path) -> Path:
    """A repository whose INDEX holds a live probe while its worktree and every tip are clean.

    The incident's shape, reproduced step for step rather than approximated: commit a clean file,
    write the probe over it, `git add` it the way a second agent's routine staging did, then put
    the clean text back in the FILE ONLY. That is what a fix-forward revert leaves behind - the
    staged copy keeps the probe, `git status` reads `MM` where the author's own edit predicted `M`,
    and `git diff` shows the fix, so the tree looks repaired to every worktree reader.

    A probe file and a prose file are both staged dirty on purpose, for the same reason
    `_prose_is_not_carried_and_code_still_is` holds both in one tip: a fixture holding only the
    probe passes under a classifier with no filter installed, and only holding both can tell the
    two readings apart.
    """
    _git(root, "init", "-q")
    _git(root, "config", "user.email", "selftest@local")
    _git(root, "config", "user.name", "selftest")
    write(root / PROBE_PATH, _CLEAN_PROBE_FILE)
    write(root / PROSE_PATH, _CLEAN_PROSE_FILE)
    _git(root, "add", "-A")
    _git(root, "commit", "-qm", "base")
    write(root / PROBE_PATH, _CLEAN_PROBE_FILE + PROBE_TRAILING_CODE + "\n")
    write(root / PROSE_PATH, "\n".join(PROSE_ABOUT_MUTATIONS) + "\n")
    _git(root, "add", "-A")
    write(root / PROBE_PATH, _CLEAN_PROBE_FILE)
    write(root / PROSE_PATH, _CLEAN_PROSE_FILE)
    return root


@case("mutation_history: a probe STAGED in the index is found while the worktree is clean")
def _staged_probe_is_found() -> None:
    with tempfile.TemporaryDirectory() as raw:
        root = _staged_probe_repo(Path(raw))

        found = _staged_in(root)
        expect(
            len(found) == 1,
            f"an index holding one live probe and three prose lines returned {len(found)} "
            f"finding(s): {[probe.describe() for probe in found]}. The index must be read "
            "through the same documentation cut as the ref half, or the false positives that "
            "once pinned this gate red arrive through the new door instead",
        )
        expect(
            found[0].path == PROBE_PATH,
            f"the wrong staged line was reported: {found[0].describe()}",
        )
        # The fixture has to be the state it claims, or a green result proves nothing.
        expect(
            PROBE_TRAILING_CODE not in (root / PROBE_PATH).read_text(encoding="utf-8"),
            "the fixture left the probe in the WORKING TREE, so this case would be passing on "
            "the ref half's work or on any reader that opens the file",
        )
        expect(
            "MM" in _git(root, "status", "--porcelain").stdout,
            "the fixture did not reach the `MM` state the incident was caught in, so it is not "
            "the shape the index reader exists for",
        )
        expect(
            not [p for p in _carried_in(root) if p.ref != mutation_history.INDEX_REF],
            "a tip carried the probe, so this case does not isolate the index layer",
        )


@case("mutation_history: restaging the repair clears the INDEX, and the gate can go green")
def _repaired_index_is_clean() -> None:
    """The same fixture in the other direction, and the property that makes the layer usable.

    A guard that can never pass is worth less than none, so the repair has to be demonstrable -
    and here the repair is a second `git add`, which is the whole trap: the file was already
    correct in the first case and the index still carried the probe.
    """
    with tempfile.TemporaryDirectory() as raw:
        root = _staged_probe_repo(Path(raw))
        expect(
            bool(_staged_in(root)),
            "fixture did not start dirty, so a clean verdict below would prove nothing",
        )

        _git(root, "add", "-A")

        expect(
            not _staged_in(root),
            "an index restaged from a repaired worktree still reads as dirty, so the gate is "
            "permanently red and a guard that can never pass is one people learn to ignore",
        )
        expect(
            not _carried_in(root),
            "`carried()` does not clear when the index is repaired, so `tools check` never goes "
            "green and the guard gets deleted on its first trip",
        )
        expect(
            not _sweep_in(root),
            "the probe was committed at some point, so the index half is not strictly earlier "
            "than the ref half and the cheap failure to catch was never the cheap one",
        )


@case("mutation_history: an index finding is surfaced by `carried()`, which is what check gates")
def _carried_surfaces_the_index() -> None:
    # The wiring, and the reason `staged()` is not a separate command. A classifier nothing
    # calls is a function, not a guard: `tools check` reaches this module through `carried()`
    # and nowhere else, so a staged probe has to appear there or it never fails a build.
    with tempfile.TemporaryDirectory() as raw:
        root = _staged_probe_repo(Path(raw))

        found = [p for p in _carried_in(root) if p.ref == mutation_history.INDEX_REF]

        expect(
            len(found) == 1,
            f"`carried()` reported {len(found)} index finding(s); a staged probe must fail "
            f"`mutation_history check` before it is committed, not after. Findings: "
            f"{[probe.describe() for probe in _carried_in(root)]}",
        )
        expect(
            found[0].path == PROBE_PATH,
            f"the index finding named the wrong path: {found[0].describe()}",
        )


# --- The index's SECOND shape: an UNMERGED path. `git grep --cached` cannot see it ---


def _unmerged_in(root: Path) -> list:
    """Read `root`'s unmerged index entries instead of the repository's."""
    original = mutation_history.REPO
    mutation_history.REPO = root
    try:
        return mutation_history.conflicted()
    finally:
        mutation_history.REPO = original


def _unmerged_repo(root: Path, *, probe_on_theirs: bool) -> tuple[Path, Path]:
    """A repository whose index holds a REJECTED MERGE, optionally carrying a probe.

    The shape, built rather than simulated: one file, edited on both branches, merged, rejected.
    `git ls-files -u` then records stages 1/2/3 and the path stays unmerged until somebody runs
    `git add`. With `probe_on_theirs` the marker is in stage 3 - the side an author is about to
    keep, and the one a commit would write.

    The conflict is forced by BOTH branches rewriting the file's last line, which is what makes
    git reject the merge rather than auto-merge it. That was found the hard way: an earlier
    fixture edited a line in the middle and appended below it, git merged that without complaint,
    the path never went unmerged, and the case passed for the wrong reason. The trailing line is
    what makes the two sides genuinely incompatible.

    Every stage is read rather than just "theirs", which is why the fixture is built with the
    probe on ONE side: a guard that only ever looked at stage 1 (the base) or only at stage 2
    would report nothing here, and the clean-direction case below cannot tell those apart.

    `git merge` is run WITHOUT `check`: exit 1 is the REJECTED merge this fixture exists to
    produce, so asserting it succeeded would assert the opposite of the state being tested. The
    caller checks `git status --porcelain` for `UU` instead, which is the property that matters -
    and checking the outcome rather than the exit code is what stops this fixture from passing
    when git silently auto-merges instead of rejecting.
    """
    _git(root, "init", "-q", "-b", "main")
    _git(root, "config", "user.email", "selftest@local")
    _git(root, "config", "user.name", "selftest")
    thing = write(root / PROBE_PATH, _CLEAN_PROBE_FILE)
    _git(root, "add", "-A")
    _git(root, "commit", "-qm", "base")
    _git(root, "checkout", "-q", "-b", "feature")
    write(
        thing, _CLEAN_PROBE_FILE + (PROBE_TRAILING_CODE + "\n" if probe_on_theirs else "# edit\n")
    )
    _git(root, "add", "-A")
    _git(root, "commit", "-qm", "feature")
    _git(root, "checkout", "-q", "main")
    write(thing, _CLEAN_PROBE_FILE.replace("true", "false"))
    _git(root, "add", "-A")
    _git(root, "commit", "-qm", "main edits the same region")
    subprocess.run(  # noqa: S603 - fixed argv, no shell
        ("git", "merge", "feature"),
        cwd=str(root),
        capture_output=True,
        text=True,
        check=False,
    )
    return root, thing


@case("mutation_history: a probe in an UNMERGED index entry is found")
def _unmerged_probe_is_found() -> None:
    with tempfile.TemporaryDirectory() as raw:
        root, thing = _unmerged_repo(Path(raw), probe_on_theirs=True)

        # The fixture has to BE the state it claims, and the working tree is part of that claim.
        # A rejected merge leaves CONFLICT MARKERS in the file, which means the probe is
        # visible on disk here too - so this case does NOT isolate the index. What it isolates
        # is asserted directly instead: the probe must be in stage 3, and `git grep --cached`
        # must miss it. That is the reader-level statement of the gap, and it holds whatever the
        # conflict-marker worktree looks like on any git version.
        expect(
            "UU" in _git(root, "status", "--porcelain").stdout,
            "the fixture did not reach an unmerged state, so it does not test the stage reader",
        )
        staged = subprocess.run(  # noqa: S603 - fixed argv, no shell
            ("git", "show", f":3:{PROBE_PATH}"),
            cwd=str(root),
            capture_output=True,
            text=True,
            check=False,
        )
        expect(
            PROBE_TRAILING_CODE in staged.stdout,
            "the probe is not in stage 3, so the fixture does not hold what it claims",
        )
        # `git grep --cached` is the reader that DOES exist, and it sees nothing here. If that
        # ever starts working, this fixture stops being a gap and the reader can be simplified -
        # asserted so the reason this code exists stays true rather than assumed.
        grep = subprocess.run(  # noqa: S603 - fixed argv, no shell
            (
                "git",
                "grep",
                "--cached",
                "-n",
                "-I",
                "-E",
                mutation_history.MARKER,
                "--",
                *mutation_history.GUARDED,
            ),
            cwd=str(root),
            capture_output=True,
            text=True,
            check=False,
        )
        expect(
            grep.returncode != 0 or not grep.stdout.strip(),
            f"`git grep --cached` now reports unmerged paths ({grep.returncode}/"
            f"{grep.stdout!r}), so the stage reader is redundant; confirm before deleting it",
        )
        # The stage-0 reader on its own - `staged()` also returns the conflict findings now, and
        # this assertion is about ISOLATION, so it asks about the stage-0 half specifically.
        stage_zero = [p for p in _staged_in(root) if p.ref == mutation_history.INDEX_REF]
        expect(
            not stage_zero,
            f"the stage-0 reader found the probe too ({[p.describe() for p in stage_zero]}), so "
            "this case is no longer isolated to the stage reader",
        )

        found = _unmerged_in(root)

        expect(
            bool(found),
            "an index holding an unmerged path whose 'theirs' side is a probe reported clean. "
            "A rejected merge is the ORDINARY state of ~20 agents working at once, `git grep "
            "--cached` walks stage 0 only, and a path left unmerged has no stage 0 - so a probe "
            "one `git add` away from a commit is invisible to every other reader here",
        )
        expect(
            all(probe.path == PROBE_PATH for probe in found),
            f"the wrong line was reported: {[probe.describe() for probe in found]}",
        )
        expect(
            any("stage=3" in probe.ref for probe in found),
            f"the finding did not say WHICH stage held it: "
            f"{[probe.describe() for probe in found]}. 'ours' and 'theirs' are different "
            "repairs, and a report that cannot tell them apart sends the reader to guess",
        )


@case("mutation_history: an unmerged index holding NO probe is clean")
def _unmerged_without_a_probe_is_clean() -> None:
    # The false-positive direction, and the case the reader is most at risk of: it reads three
    # blobs per conflict and reports the first marker-shaped line in any of them. A guard that
    # reported every conflict would fail this.
    #
    # The PROSE lines are staged too, deliberately, for the reason
    # `_prose_is_not_carried_and_code_still_is` holds both in one tip: a fixture holding only
    # clean conflict content passes under a classifier with no filter installed, and only
    # holding both can tell the two readings apart. Staging the prose resolves it as a normal
    # stage-0 entry - the prose file is a NEW file git can add, which leaves the conflicted path
    # the only unmerged one.
    with tempfile.TemporaryDirectory() as raw:
        root = _unmerged_repo(Path(raw), probe_on_theirs=False)[0]
        write(
            root / PROSE_PATH,
            "extends TestCase\n\n\nfunc it() -> void:\n\tassert(true)\n"
            + "\n".join(PROSE_ABOUT_MUTATIONS)
            + "\n",
        )
        # ONLY the prose path is staged. `git add -A` would also stage the conflicted file,
        # which RESOLVES it, and then there is no unmerged index left to test - which is
        # exactly what the first version of this fixture did, and it silently tested nothing.
        _git(root, "add", "--", PROSE_PATH)
        merged = _git(root, "status", "--porcelain").stdout
        expect("UU" in merged, f"the fixture resolved itself, so it tests nothing: {merged!r}")

        found = _unmerged_in(root)

        expect(
            not found,
            f"an unmerged index holding no probe was reported as dirty: "
            f"{[probe.describe() for probe in found]}. A conflict is not a finding, and a guard "
            "that fires on every merge in a 20-agent repo gets deleted on its first trip",
        )
        expect(
            not _staged_in(root),
            f"the staged reader flagged the prose file: "
            f"{[p.describe() for p in _staged_in(root)]}. The documentation cut has to hold in "
            "the index layer too, or a committed file's own prose becomes a permanent red",
        )


@case("mutation_history: an UNREADABLE index fails `readable()`, so it cannot read as clean")
def _unreadable_index_is_not_readable() -> None:
    # The anti-vacuity term, pointed at the layer that lacked one. `_git` maps every non-zero
    # exit code to "", so "git grep matched nothing" and "git grep fell over" are the same value;
    # before this, `readable()` only asked `rev-parse --git-dir`, which stays perfectly happy
    # about a corrupt index.
    #
    # The fixture carries a probe on the `feature` REF as well as in the unmerged index, so the
    # damage is visible: a corrupt index silences the INDEX layer completely while the ref
    # layer keeps reporting. Before this, `readable()` said True and `check` would have reported
    # "1 probe carried by refs/heads/feature" - a true statement that quietly omits the one
    # about to be committed.
    with tempfile.TemporaryDirectory() as raw:
        root = _unmerged_repo(Path(raw), probe_on_theirs=True)[0]
        original = mutation_history.REPO
        mutation_history.REPO = root
        try:
            expect(
                mutation_history.readable(),
                "fixture did not start readable, so a False below would prove nothing",
            )
            expect(
                bool(mutation_history.staged()) or bool(mutation_history.conflicted()),
                "fixture started with a silent index layer, so it does not exercise the failure",
            )
            junk = Path(raw) / "corrupt-index"
            junk.write_bytes(b"DIRC this is not an index" + bytes(64))
            os.environ["GIT_INDEX_FILE"] = str(junk)
            try:
                expect(
                    not mutation_history.readable(),
                    "a corrupt index still reads as `readable()`, so `tools check` reports only "
                    "what the REFS carry and silently drops every staged finding - a guard that "
                    "says ok because it looked at nothing is not a guard",
                )
                expect(
                    mutation_history.staged() == [] and mutation_history.conflicted() == [],
                    "the index layer is still reporting through a corrupt index, so this fixture "
                    "is not the failure it claims to be",
                )
                expect(
                    any("refs/heads/feature" == ref for ref in mutation_history.shipped_refs()),
                    "the ref half is broken too, so this fixture cannot isolate the index layer: "
                    f"shipped_refs()={mutation_history.shipped_refs()}",
                )
            finally:
                os.environ.pop("GIT_INDEX_FILE", None)
        finally:
            mutation_history.REPO = original


@case("mutation_history: an INDEX finding is never reported as a shipped ref tip")
def _index_findings_are_not_reported_as_refs() -> None:
    # The reporting half, and the reason `_is_shipped_ref` exists. Every finding used to print
    # under one "carried by a shipped ref tip" headline, which told the reader an index finding
    # had ALREADY been committed - the opposite of what it is. It is the finding with the
    # cheapest repair (stage the fixed line), and the one a reader would skip past.
    for label, want_ref in (
        (mutation_history.INDEX_REF, False),
        (mutation_history.CONFLICT_LABEL.format(stage=3), False),
        ("refs/heads/main", True),
        ("refs/remotes/origin/main", True),
        ("HEAD", True),
    ):
        expect(
            mutation_history_cmd._is_shipped_ref(label) is want_ref,
            f"the layer classifier called {label!r} a shipped ref = "
            f"{mutation_history_cmd._is_shipped_ref(label)}, wanted {want_ref}. A finding "
            "reported as already-committed sends the reader looking in history for something that "
            "has not been written yet",
        )


@case("mutation_history: a conflicted index is readable, so the gate does not refuse it")
def _conflicted_index_is_still_readable() -> None:
    # The anti-vacuity term must not over-reach into "a conflict is a failure". `git ls-files`
    # exits 0 on an unmerged index, so `readable()` stays True and `check` reports the PROBE
    # rather than refusing the repository - which is the only useful verdict.
    with tempfile.TemporaryDirectory() as raw:
        root = _unmerged_repo(Path(raw), probe_on_theirs=True)[0]
        original = mutation_history.REPO
        mutation_history.REPO = root
        try:
            expect(
                mutation_history.readable(),
                "an unmerged index read as unreadable, so `check` would refuse the repository "
                "instead of reporting the probe sitting in it",
            )
            expect(
                bool(
                    [
                        p
                        for p in mutation_history.carried()
                        if p.ref.startswith(mutation_history.INDEX_REF)
                    ]
                ),
                "the probe in a conflicted index did not reach `carried()`, which is the only "
                "entry point `tools check` uses - a reader nothing calls is a function, not a "
                "guard",
            )
        finally:
            mutation_history.REPO = original


# --- ADR 0138: reference_stats is prose, and the guard has to mean that precisely ---


def _stat_findings(block: object) -> list[str]:
    """Run the guard against a block, with the REAL authored stat vocabulary.

    The vocabulary is read from `contracts/stat.gd` rather than supplied by the
    fixture, for the same reason `map_theme` builds `authored` itself: a test that
    hands the guard the value under test cannot tell a working guard from a
    loosened one.
    """
    return unique_characters._no_stat_numbers(
        block, "reference_stats", unique_characters._authored_stat_ids()
    )


# --- the nine required prompts: a canon claim that the art set is complete ---


def _prompt_gaps(shots: list[dict]) -> list[str]:
    """Run the prompt-set guard against a shot list, with the REAL vocabulary.

    The slot list and the set minimums are read from the module rather than
    restated here, for the reason `_stat_findings` reads `contracts/stat.gd`: a
    fixture that supplies the value under test cannot tell a working guard from
    a loosened one. Copying the nine slots into this file would let someone
    delete a slot from `PROMPT_SLOTS` and leave the whole suite green.
    """
    return unique_characters._prompt_set_gaps({"shots": shots})


def _shot(slot: str, expression: str = "", pose: str = "standing, weight settled", **overrides):
    """One structurally valid shot filling `slot`, for prompt-set fixtures."""
    shot = {
        "id": f"{slot}-1",
        "kind": unique_characters.SLOT_KIND.get(slot, "portrait"),
        "slot": slot,
        "pose": pose,
        "framing": "waist up",
        "expression": expression,
        "scene": "",
        "status": "planned",
        "canvas": [1024, 1024],
    }
    shot.update(overrides)
    return shot


def _complete_shots() -> list[dict]:
    """A shot list satisfying every required prompt, derived from the tool.

    Built from `PROMPT_SLOTS` and `SET_SLOT_MINIMUMS` so that ADDING a slot does
    not silently turn this fixture red. The failing direction is the other case:
    removing one from the tool must leave this green and the removal case red, or
    the guard has been loosened rather than exercised.

    Each member varies on the field that actually distinguishes it for that set,
    read from `SET_SLOT_MEMBER_FIELD`. Writing `expression` for both sets is the
    mistake this fixture is built to avoid.
    """
    shots = []
    for slot in unique_characters.PROMPT_SLOTS:
        needed = unique_characters.SET_SLOT_MINIMUMS.get(slot, 1)
        field = unique_characters.SET_SLOT_MEMBER_FIELD.get(slot, "expression")
        for index in range(needed):
            shot = _shot(slot, id=f"{slot}-{index}")
            shot[field] = f"{field} {index}"
            shots.append(shot)
    return shots


@case("unique_characters: a canon character with no shots FAILS every required prompt")
def _empty_prompt_set_fails() -> None:
    """The obvious hole, asserted closed.

    `unique_characters add` writes a draft with an empty shot list, so "no art
    planned" is a state the catalog reaches by its normal first step. Only the
    canon gate stands between that and a character asserted to be fully
    specified, and this is that gate seen from the empty side.
    """
    gaps = _prompt_gaps([])
    expect(
        len(gaps) == len(unique_characters.PROMPT_SLOTS),
        f"an empty shot list reported {len(gaps)} prompt gaps for "
        f"{len(unique_characters.PROMPT_SLOTS)} required prompts, so a canon character "
        f"with no art at all would pass the promotion gate",
    )


@case("unique_characters: nine copies of ONE expression do not satisfy expression_set")
def _duplicated_expressions_do_not_satisfy_a_set() -> None:
    """The fixture that tells a set guard from a count guard.

    `SET_SLOT_MINIMUMS` is a count, so the obvious implementation is
    `len(shots_in_slot) >= minimum` — and that implementation passes this
    fixture, which is exactly why this fixture exists. Nine expression shots that
    all read "composed" is a prompt set by cardinality and a single picture by
    content, and it is the shape an agent produces when it satisfies a count
    instead of writing nine emotions. Mutating `_prompt_set_gaps` to count shots
    rather than distinct expression text has to turn THIS case red.
    """
    needed = unique_characters.SET_SLOT_MINIMUMS["expression_set"]
    duplicated = [
        _shot("expression_set", expression="composed", id=f"expr-{index}")
        for index in range(needed)
    ]
    distinct = [
        _shot("expression_set", expression=f"emotion {index}", id=f"expr-{index}")
        for index in range(needed)
    ]
    expect(
        _prompt_gaps(duplicated) != _prompt_gaps(distinct),
        "duplicating one expression across the set changed nothing, so the guard "
        "counts shots rather than distinct emotions and `expression_set` can be "
        "satisfied by one picture described nine times",
    )
    expect(
        any("expression_set" in gap for gap in _prompt_gaps(duplicated)),
        f"the duplicated set was reported as a problem somewhere other than "
        f"expression_set: {_prompt_gaps(duplicated)!r}, so the author is told to "
        f"fix a slot that is already correct",
    )


@case("unique_characters: a complete nine-prompt set is clean")
def _complete_prompt_set_is_clean() -> None:
    """The counterweight to the two cases above.

    A guard that refuses everything satisfies both red paths. This is what
    distinguishes "the guard rejects a bad prompt set" from "the guard rejects a
    prompt set", and it is the half of the pair a green-only test would omit.
    """
    expect(
        not _prompt_gaps(_complete_shots()),
        f"a shot list covering every required prompt was still reported incomplete: "
        f"{_prompt_gaps(_complete_shots())!r}",
    )


@case("unique_characters: a pose_set is counted on POSE, not on expression")
def _pose_set_is_counted_on_pose() -> None:
    """The two sets do not share a distinguishing field, and assuming they do is
    a requirement no author can meet.

    `expression_set` is nine shots differing in `expression`; `pose_set` is nine
    shots differing in `pose`. A guard that counts both on `expression` demands
    nine distinct emotions from a character being asked for nine stances, which
    pushes an author to restate the stance in the emotion field - a prompt set
    that satisfies the count while saying the same thing twice.

    The second expectation is the direction that matters: nine poses sharing one
    `expression` must still be a complete pose_set, because nothing about the
    stances is missing. A guard that failed that would be requiring the emotion
    field as a duplicate of the pose.
    """
    needed = unique_characters.SET_SLOT_MINIMUMS["pose_set"]
    varying_pose = [
        _shot("pose_set", pose=f"stance {index}", expression="composed", id=f"pose-{index}")
        for index in range(needed)
    ]
    # Scoped to the one slot, because this fixture fills no other slot and the
    # other eight are SUPPOSED to report. Asserting `_prompt_gaps(varying_pose)`
    # is empty would test the whole prompt set while claiming to test one slot,
    # and would fail for correct behaviour.
    pose_gaps = [gap for gap in _prompt_gaps(varying_pose) if "pose_set" in gap]
    expect(
        not pose_gaps,
        f"nine shots differing in pose were rejected, so pose_set is being counted on "
        f"the wrong field: {pose_gaps!r}",
    )
    shared_pose = [
        _shot("pose_set", pose="stance 0", expression=f"emotion {index}", id=f"pose-{index}")
        for index in range(needed)
    ]
    shared_gaps = [gap for gap in _prompt_gaps(shared_pose) if "pose_set" in gap]
    expect(
        bool(shared_gaps),
        "nine shots sharing one pose were accepted, so pose_set can be satisfied by "
        "one stance described nine times",
    )


@case("unique_characters: a prompt slot rendered by the wrong kind FAILS")
def _slot_kind_mismatch_fails() -> None:
    """The slot is a claim about the render graph, so it is checked, not noted.

    The failure this catches is a `map_sprite` slot holding a 1024px waist-up
    portrait: the catalog validates, the count is right, and the small-scale
    exploration representation the brief requires is simply absent. The second
    expectation is the fixture that matters — a correctly paired slot produces
    no such finding, so mutating the check into "always complain" fails here.
    """
    wrong = unique_characters._validate_shot(
        _shot("map_sprite", kind="portrait"), "shot[0]", False, set()
    )
    right = unique_characters._validate_shot(_shot("map_sprite"), "shot[0]", False, set())
    expect(
        any("renders as kind" in issue for issue in wrong),
        f"a map_sprite slot routed to the portrait graph passed validation: {wrong!r}",
    )
    expect(
        not any("renders as kind" in issue for issue in right),
        f"the correct slot/kind pairing was reported as a mismatch: {right!r}, so the "
        f"check cannot tell a wrong route from a right one",
    )


def _cast_record(
    character_id: str,
    name: str,
    lore: str,
    *,
    role: str = "npc",
    path: str = "qi",
    race: str = "emberblood",
    faction: str = "nine_seats",
) -> dict:
    """A minimal record carrying only the fields the duplicate audit reads."""
    return {
        "id": character_id,
        "name": name,
        "identity": {"role": role, "path": path, "faction": faction},
        "appearance": {"race": race},
        "canon": {"role_in_story": "", "lore": lore, "first_appearance": ""},
    }


@case("unique_characters: an identical background is refused as a duplicate")
def _identical_backgrounds_are_duplicates() -> None:
    """The core defect, asserted closed.

    Two agents independently authoring "a qi disciple of the Nine Seats Court from
    the ashfall belt" produce different names, different appearance fields and
    different art, and pass every per-record check. The defect is a RELATIONSHIP
    between two rows, so it is only discoverable pairwise - which is why it lives
    in `_validate` over the whole catalog rather than in a per-record check.
    """
    prose = (
        "A qi disciple of the Nine Seats Court who trains in the ashfall belt to outrun "
        "a contract her clan cannot pay."
    )
    findings = unique_characters._duplicate_findings(
        [
            _cast_record("unique-0001", "Ashkeeper", prose),
            _cast_record("unique-0002", "Ninefold", prose),
        ]
    )
    expect(
        any("duplicate of" in finding for finding in findings),
        f"two characters with byte-identical background text were accepted as distinct: "
        f"{findings!r}. Renaming is the cheapest way to look original and it defeats "
        f"every per-record check, which is why uniqueness is judged on prose",
    )


@case("unique_characters: a same-slot near-copy is refused as a shallow variant")
def _same_slot_near_copies_are_variants() -> None:
    """The 0.55 line, and the condition that makes it safe.

    Two characters may legitimately write similar sentences about the same world.
    What makes it a monoculture is the SLOT as well: same role, same cultivation
    path, same race, same faction, saying substantially the same thing. Drop the
    slot condition and this guard would refuse a cast of neighbours, friends and
    rivals in the same city - which is the shape a good cast actually has.
    """
    base = (
        "A qi disciple of the Nine Seats Court who trains in the ashfall belt to outrun "
        "a contract her clan cannot pay, and files the shortfall every season."
    )
    # Candidate A measures 0.71: inside the BAND (0.55-0.80), not above it. A
    # one-word swap scored 0.92 and hit the duplicate line, passing this case for
    # the wrong reason; a fully rewritten background scored 0.12 and fell under the
    # threshold. Same frame, same situation, same vocabulary of obligation and
    # shortfall, different sentence structure. That overlap IS the defect being
    # guarded - two agents independently reaching for the same situation - and it
    # is why the variant line needs a same-slot condition to be safe at all.
    near = (
        "A qi disciple of the Nine Seats Court trains in the ashfall belt, and each "
        "season files the shortfall of a contract her clan signed and cannot honour."
    )
    same_slot = unique_characters._duplicate_findings(
        [
            _cast_record("unique-0001", "Ashkeeper", base),
            _cast_record("unique-0002", "Ninefold", near),
        ]
    )
    other_slot = unique_characters._duplicate_findings(
        [
            _cast_record("unique-0001", "Ashkeeper", base),
            _cast_record(
                "unique-0003", "Ferrous", near, path="body", race="ashwalker", faction="iron_ring"
            ),
        ]
    )
    expect(
        any("shallow variant" in finding for finding in same_slot),
        f"two near-identical characters in the same structural slot were accepted: "
        f"{same_slot!r}. Same role, path, race and faction with the same story IS the "
        f"monoculture the catalog exists to prevent, whatever they are called",
    )
    expect(
        not any("shallow variant" in finding for finding in other_slot),
        f"the same prose in a DIFFERENT slot was refused: {other_slot!r}. Without the "
        f"slot condition this guard would fail any cast of people who share a city",
    )


@case("unique_characters: reuse of a NAME is refused even when the prose differs")
def _duplicate_names_are_refused() -> None:
    """Name collision is a separate defect from duplicate prose.

    A name is the one field a player reads, so two characters sharing it is a
    defect even when the backgrounds are unrelated - and it is invisible to the
    Jaccard check, which is why it is checked separately.
    """
    findings = unique_characters._duplicate_findings(
        [
            _cast_record("unique-0001", "The Warden", "A smith on the terrace ring."),
            _cast_record("unique-0002", "The Warden", "A ferryman on the saltpan basin."),
        ]
    )
    expect(
        any("already used by" in finding for finding in findings),
        f"two characters share the name 'The Warden' with unrelated backgrounds: "
        f"{findings!r}. The name is the field a reader sees, and no two of them may "
        f"share it",
    )


@case("unique_characters: a monoculture on a structural axis is REPORTED")
def _monoculture_is_reported() -> None:
    """A concentration is a fact about the cast, not a defect in a row.

    It is reported and never failed by default, because a ten-character catalog is
    legitimately concentrated and a gate that fires there would be ignored. The
    counterweight matters as much as the warning: distinct characters on the same
    path are a perfectly good cast, and a guard that fired on them would be
    teaching authors to invent pointless variety.
    """
    records = [
        _cast_record(
            f"unique-{index:04d}",
            f"Name{index}",
            f"A distinct account number {index} of salt wages, ferry fares and a "
            f"gate that closes at dusk.",
        )
        for index in range(1, 5)
    ]
    warnings = unique_characters._concentration_warnings(records)
    expect(
        any("race=emberblood" in warning for warning in warnings),
        f"four characters of one race out of four produced no monoculture warning: "
        f"{warnings!r}. At 1000 records a structural axis can absorb a whole cast "
        f"silently, and this is the only signal that says so",
    )
    # The counterweight has to be unconcentrated on EVERY structural axis, including
    # `role`. Four NPCs is the normal shape of a small cast, so leaving role=npc at
    # 4/4 tests nothing - and failing it would push an author toward inventing
    # pointless variety to satisfy a linter. The threshold is a share, so a four
    # character cast needs at most one character per value on each axis.
    spread = [
        _cast_record(
            "unique-0001",
            "One",
            "A smith who lost her hand and files it into a tool she cannot stop mending.",
            role="pc",
            path="qi",
            race="emberblood",
        ),
        _cast_record(
            "unique-0002",
            "Two",
            "A ferryman whose boat never came back and whose fare is still collected.",
            role="boss",
            path="body",
            race="ashwalker",
        ),
        _cast_record(
            "unique-0003",
            "Three",
            "A window-washer on the terrace ring who answers only to the weather.",
            role="npc",
            path="mind",
            race="cairnborn",
        ),
        _cast_record(
            "unique-0004",
            "Four",
            "A scribe who falsified a deed to keep a mill alive through one winter.",
            role="pc",
            path="unaffiliated",
            race="lanternfolk",
        ),
    ]
    # `role` cannot be unconcentrated in a four-record cast: the vocabulary has
    # three values, so one repeats and one value reaches 2/4 = 50%. That is
    # arithmetic, not a defect, and it is why the guard is scoped to `path` and
    # `race` - the two axes whose vocabularies are open-ended. Firing on `role`
    # would fail every small cast and push authors toward meaningless roles.
    expect(
        not [w for w in unique_characters._concentration_warnings(spread) if "role=" in w],
        f"role concentration was reported as a monoculture: "
        f"{unique_characters._concentration_warnings(spread)!r}. `role` has three values "
        f"and a four-record cast must repeat one, so this guard would fire on every "
        f"small catalog and teach authors to invent roles to silence a linter",
    )
    expect(
        not unique_characters._concentration_warnings(spread),
        f"a cast spread across every path and race was still reported as a "
        f"monoculture: {unique_characters._concentration_warnings(spread)!r}. The "
        f"open-ended axes are the ones that carry structural meaning",
    )


@case("loop_guard: INC-0021's exact command is REFUSED")
def _inc_0021_command_is_refused() -> None:
    """The verbatim shape that burned 11.6 GB, asserted still caught.

    A red path, not a happy path: the guard passing on a harmless command proves
    nothing, because a harmless command is what it was written against. What
    matters is that the real runaway is still recognised.
    """
    command = (
        "uv run python -c \"import sys,base64,pathlib; print('READY',flush=True); "
        "data=b''.join(iter(lambda:sys.stdin.readline().strip().encode(),"
        "b'END_IMAGE_DATA')); "
        "p=pathlib.Path('build/void_shoal_shallow_water_source.png'); "
        'p.write_bytes(base64.b64decode(data)); print(p.resolve(),flush=True)"'
    )
    found = loop_guard.check_command([command])
    expect(
        bool(found),
        "the exact command from INC-0021 was reported clean, so the shape that "
        "reached 11.6 GB resident and 42 GB commit is not refused",
    )
    expect(
        any(f[2] == "iter-sentinel-unreachable" for f in found),
        f"the runaway was caught under an unrelated rule id: {[f[2] for f in found]}",
    )


@case("loop_guard: a sentinel the callable CAN return is not flagged")
def _reachable_sentinel_is_not_flagged() -> None:
    """The fixture that tells this guard from a blanket `iter(callable, x)` ban.

    `iter(lambda: sys.stdin.buffer.readline(), b'')` is the same shape with an
    EMPTY sentinel — and ''.encode() IS b'', so EOF does satisfy it and the loop
    terminates. Refusing this would drive authors away from the one safe spelling.
    A generator that yields the sentinel terminates too, transform and all.
    """
    for command, why in (
        (
            "python -c \"import sys; d=b''.join(iter(lambda: sys.stdin.buffer.readline(), b''))\"",
            "an empty-bytes sentinel IS reachable at EOF, so this loop terminates",
        ),
        (
            'python -c "import sys\ndef lines():\n    for l in sys.stdin:\n'
            "        if l.rstrip()==b'END': return\n        yield l\nd=b''.join(lines())\"",
            "a generator yields the sentinel itself, so iter() stops on it",
        ),
        (
            'python -c "import sys; d=sys.stdin.read()"',
            "plain read() to EOF cannot overrun its own input",
        ),
    ):
        expect(
            not loop_guard.check_command([command]),
            f"a TERMINATING loop was refused: {why}",
        )


@case("loop_guard: a while-True reading stdin with no EOF test is REFUSED")
def _unbounded_stdin_while_is_refused() -> None:
    """The same runaway, different spelling.

    `while True:` around `readline()` has no EOF test, and at EOF `readline()`
    returns '' forever — so the condition never flips and nothing is ever written.
    This is INC-0019's shape in a command string, where `test_no_unbounded_wait.gd`
    cannot see it at all because the loop does not live in a file.
    """
    command = (
        'python -c "import sys\nbuf=[]\nwhile True:\n    line=sys.stdin.readline()\n'
        '    buf.append(line)\nprint(len(buf))"'
    )
    expect(
        any(f[2] == "unbounded-stdin-while" for f in loop_guard.check_command([command])),
        "a while-True readline loop with no EOF test was reported clean, so the "
        "runaway that INC-0019 describes is not refused when it is typed inline",
    )


@case("unique_characters: a number in reference_stats FAILS the check")
def _numbers_in_reference_stats_fail() -> None:
    """The two ways a number gets into a prose block.

    A bare JSON number is the obvious one. The second is the one that actually
    matters: `{"summary": "physique: 40"}` is a stat assignment wearing prose as
    a disguise, and it is exactly how a reference document becomes a balance
    surface without any guard seeing it.
    """
    for block in (
        {"summary": "", "strengths": [40]},
        {"summary": "a bruiser", "physique": 18},
        {"summary": "physique: 40, and slow", "strengths": []},
        {"summary": "", "notes": "18"},
    ):
        expect(
            _stat_findings(block),
            f"a number entered reference_stats and was accepted: {block!r}. ADR 0138 "
            "keeps this block prose precisely because no other gate can see a JSONL row",
        )


@case("unique_characters: prose that merely contains a digit still PASSES")
def _prose_digits_are_not_stats() -> None:
    """The fixture that tells the stat guard from a blanket digit ban.

    The first version of this suite asserted only that a number is refused. That
    fixture passes under a guard which rejects EVERY string containing a digit —
    so mutating `stat_ids` out of the pattern and replacing it with `\\d` left the
    whole suite green while making the block unwriteable. A guard test whose
    fixture cannot distinguish the two readings tests nothing about the reading.

    Names, ordinals, and ages are prose. "the 9th Brother", "sixty years", and
    "three gates" carry digits and are not stats; refusing them would drive an
    author to write worse lore to satisfy the linter.
    """
    for block in (
        {"summary": "the 9th Brother of the Ash Gate"},
        {"summary": "sixty years old and counting"},
        {"summary": "one of three gate wardens, sworn in 3rd month"},
        {"summary": "", "strengths": ["outlasts anyone in a stand", "hits like 3 oxen"]},
    ):
        expect(
            not _stat_findings(block),
            f"ordinary prose was refused as a stat: {block!r}. The guard matches the "
            "authored stat ids, not digits, so a name with a numeral is still writable",
        )


# --- ADR 0139: the lore bible's guards must go RED, and the Bible must be importable ---


def _lore_bible(root: Path) -> lore.model.Bible:
    """A Bible loaded from a fixture tree instead of the repository.

    The registry is copied in rather than hand-written: it is the vocabulary every
    guard reads, so a miniature one would let a fixture pass under relations the
    real registry does not have.

    LORE_ROOT alone is not enough. The first version moved only LORE_ROOT, and
    `load_bible` resolved the registry through a module constant captured at import
    time - so the fixture read the REPOSITORY's 528 entities while its own edges
    pointed at two of them. Every dangling-edge assertion passed because the real
    bible already contained the targets it was checking for. A test that reads the
    wrong tree is worse than no test, because it looks like coverage.
    """
    source = lore.model.registry_path()
    lore_root = root / "lore"
    (lore_root).mkdir(parents=True, exist_ok=True)
    # The registry lives AT the lore root, next to bible/ and edges/, so the
    # fixture writes it to `root/lore/registry.json` - the same relative position
    # it occupies in the repository. The first version put it at `root/`, which
    # made every fixture raise `lore registry missing` once the importer tests
    # started redirecting LORE_ROOT correctly, and eleven assertions "errored"
    # rather than testing anything.
    (lore_root / "registry.json").write_text(source.read_text(encoding="utf-8"), encoding="utf-8")
    original_root = lore.model.LORE_ROOT
    lore.model.LORE_ROOT = lore_root
    try:
        return lore.model.load_bible()
    finally:
        lore.model.LORE_ROOT = original_root


def _write_lore(root: Path, entities: dict[str, list[dict]], edges: dict[str, list[dict]]) -> None:
    """Write fixture entities and edges under the SAME root the loader reads.

    `_lore_bible` points `LORE_ROOT` at `root/lore`, so writing to `root/bible`
    leaves the loader reading an empty directory and every assertion below
    "passes" against a bible with no entities in it - or raises. The fixture and
    the loader have to agree on the path or the test measures nothing.
    """
    lore_root = root / "lore"
    for domain, rows in entities.items():
        write(lore_root / "bible" / f"{domain}.jsonl", "".join(json.dumps(r) + "\n" for r in rows))
    for name, rows in edges.items():
        write(lore_root / "edges" / f"{name}.jsonl", "".join(json.dumps(r) + "\n" for r in rows))


def _entity(domain: str, slug: str, **over: object) -> dict:
    record = {
        "id": f"{domain}.{slug}",
        "domain": domain,
        "type": "thing",
        "name": slug.replace("_", " ").title(),
        "summary": "A thing that exists for a reason.",
        "tags": ["sample"],
        "status": "active",
        "provenance": {"author": "fixture"},
        "attributes": {},
    }
    record.update(over)
    return record


@case("lore: a dangling edge reference FAILS validation")
def _dangling_edge_fails() -> None:
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        _write_lore(
            root,
            {"geography": [_entity("geography", "somewhere")]},
            {
                "batch": [
                    {"from": "geography.somewhere", "rel": "located_in", "to": "geography.nowhere"}
                ]
            },
        )
        findings = lore.run_audit(_lore_bible(root))
        expect(
            any("geography.nowhere" in finding for finding in findings),
            "an edge pointing at an entity that does not exist was accepted, so a bible "
            "can grow references to worlds and people nobody ever wrote",
        )


@case("lore: two exclusive relations on one pair FAILS validation")
def _exclusive_relations_fail() -> None:
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        _write_lore(
            root,
            {
                "organizations": [
                    _entity("organizations", "alpha"),
                    _entity("organizations", "beta"),
                ]
            },
            {
                "batch": [
                    {
                        "from": "organizations.alpha",
                        "rel": "allied_with",
                        "to": "organizations.beta",
                    },
                    {"from": "organizations.beta", "rel": "enemy_of", "to": "organizations.alpha"},
                ]
            },
        )
        findings = lore.run_audit(_lore_bible(root))
        expect(
            any("exclusive" in finding for finding in findings),
            "two parties were recorded as both allied and at war with no complaint, which "
            "is the contradiction a lore audit exists to catch",
        )


@case("lore: a self-referential entity FAILS validation")
def _self_reference_fails() -> None:
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        _write_lore(
            root,
            {"cosmology": [_entity("cosmology", " Ouroboros")]},
            {
                "batch": [
                    {"from": "cosmology.ouroboros", "rel": "part_of", "to": "cosmology.ouroboros"}
                ]
            },
        )
        findings = lore.run_audit(_lore_bible(root))
        expect(
            any("cannot bear a relation to itself" in finding for finding in findings),
            "an entity related to itself was accepted, so every traversal from it loops",
        )


@case("lore: an id with no domain prefix FAILS validation")
def _bare_id_fails() -> None:
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        _write_lore(root, {"geography": [_entity("geography", "x", id="bare_name")]}, {})
        findings = lore.run_audit(_lore_bible(root))
        expect(
            any("namespaced" in finding for finding in findings),
            "a bare id with no domain prefix was accepted, which is how a lore id and a "
            "game id end up colliding with no namespace to tell them apart",
        )


@case("lore: an over-long summary FAILS validation")
def _long_summary_fails() -> None:
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        _write_lore(root, {"geography": [_entity("geography", "x", summary="w" * 900)]}, {})
        findings = lore.run_audit(_lore_bible(root))
        expect(
            any("index ceiling" in finding for finding in findings),
            "a summary far over the index ceiling was accepted, so the domain file stops "
            "being greppable by an agent working in a bounded window",
        )


@case("lore: a missing authored counterpart FAILS validation")
def _missing_external_ref_fails() -> None:
    # An external_ref resolves against the REPOSITORY root, not the fixture tree,
    # because `game/data` only exists there. So the fixture names a path that is
    # genuinely absent rather than one it invented: the first version pointed at a
    # real race file, the guard correctly stayed silent, and the test was wrong
    # about its own subject.
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        record = _entity(
            "races",
            "emberblood",
            external_ref={
                "game_id": "emberborn_via_rename",
                "path": "game/data/races/no_such_race.tres",
            },
        )
        _write_lore(root, {"races": [record]}, {})
        findings = lore.run_audit(_lore_bible(root))
        expect(
            any("external_ref path does not exist" in finding for finding in findings),
            "a lore record claimed an authored counterpart that is not on disk, so the "
            "correspondence between the bible and the game became unverifiable",
        )


@case("lore: an external_ref that DOES exist is NOT reported")
def _present_external_ref_is_silent() -> None:
    """The negative half, and the half a loosened guard breaks first.

    A guard that reported every external_ref would pass the case above while being
    useless: it fires on all 528 imported records, and a reader learns to ignore it
    within one run. This is what INC-0016's shape looks like in practice.
    """
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        record = _entity(
            "races",
            "emberblood",
            external_ref={"game_id": "emberblood", "path": "game/data/races/emberblood.tres"},
        )
        _write_lore(root, {"races": [record]}, {})
        findings = lore.run_audit(_lore_bible(root))
        expect(
            not [finding for finding in findings if "external_ref" in finding],
            "an external_ref pointing at a real authored resource was reported as broken, so "
            "the guard fires on correct data and stops being read",
        )


@case("lore: the game import is deterministic and flags stubs, not invents lore")
def _ingest_is_deterministic() -> None:
    """The importer runs against the real repository twice.

    Two properties matter and neither is visible from the record count: the second
    run must produce identical output (so a re-import cannot churn the bible), and
    a content-free authored resource must import as an explicit stub whose summary
    says so. An importer that invents plausible prose for the 331 bosses would
    leave the bible looking authored where nothing is authored.
    """
    first_domains, first_edges, _counts = lore.ingest.build_import()
    second_domains, second_edges, _counts2 = lore.ingest.build_import()
    expect(
        json.dumps(first_domains, sort_keys=True) == json.dumps(second_domains, sort_keys=True),
        "two imports of the same authored tree produced different records, so re-running "
        "the ingest silently rewrites lore",
    )
    expect(
        json.dumps(first_edges, sort_keys=True) == json.dumps(second_edges, sort_keys=True),
        "two imports produced different edges, so the graph is not reproducible",
    )
    bosses = first_domains.get("people", [])
    expect(bosses, "the importer found no named figures, so it cannot be absorbing game/data")
    for record in bosses:
        if record["attributes"].get("lore_depth") == "stub":
            expect(
                "gap" in record["summary"].lower(),
                f"{record['id']} imported as a stub but its summary does not say so, so an "
                "agent reading it cannot tell a hole from a finished entry",
            )
            break
    else:
        expect(False, "no named figure imported as a stub, so the stub flag is untested")


@case("unique_characters: a species that CLOSES a path cannot carry it")
def _closed_path_cannot_be_carried() -> None:
    """Two characters were self-refuting and `check` was silent about both.

    `unique-0023` wrote "a rootmarch has no heart-kidney channel and never gets past
    the fourth realm" and carried `path: body`. `races.rootmarch` closes body.
    `unique-0058` carried `path: mind` on `races.lanternfolk`, which closes mind.
    Nothing compared the two fields, so a record could state a fact and contradict it
    in the next breath and validate perfectly.

    Fifteen species close a path. Two of those closures are not in `attributes` at all
    and come only from the `no-cultivation` TAG - `races.echoless` is "qi-bearing in
    none of them" and `races.wake` "cannot cultivate", with nothing in their attributes
    saying so. A rule reading only the attribute would miss them and would then look
    like it had verified path legality.

    The counterweight matters as much as the rule: a species that closes nothing must
    be permitted on every path, or the guard would refuse the entire cast. Both
    directions are asserted, and the no-cultivation path is asserted separately
    because it is the one the attribute alone would miss.
    """
    entries = unique_characters._lore_entries()
    expect(entries is not None, "the Lore Bible could not be read, so the rule is untested")
    if entries is None:
        return

    closed = unique_characters.species_closed_paths(entries)
    expect(
        len(closed) >= 10,
        f"only {len(closed)} species close a cultivation path. If the taxonomy changed "
        f"this case is stale; if it did not, the rule is reading the wrong field",
    )

    for race_id, paths in closed.items():
        entity = entries[race_id]
        tags = entity.get("tags") or []
        if "no-cultivation" in tags:
            expect(
                {"qi", "body", "mind"} <= paths,
                f"{race_id} is tagged no-cultivation but closes only {sorted(paths)}. "
                f"The tag is the ONLY source for some species, so a rule reading just "
                f"attributes would pass this and report full coverage",
            )
            break
    else:
        expect(False, "no species carries the no-cultivation tag, so that path is untested")

    def record(character_id: str, race: str, path: str) -> dict:
        return {
            "id": character_id,
            "name": character_id,
            "status": "canon",
            "identity": {
                "role": "npc",
                "path": path,
                "faction": "",
                "home": "",
                "realm": "",
            },
            "appearance": {key: "" for key in unique_characters.APPEARANCE_KEYS} | {"race": race},
            "tags": [],
            "canon": {
                "role_in_story": "a role",
                "first_appearance": "an appearance",
                "lore": "some lore",
                "history": [],
                "personality": {
                    "summary": "s",
                    "traits": [],
                    "mannerisms": [],
                    "motivations": [],
                    "flaws": [],
                    "voice": "v",
                    "taboos": [],
                },
                "relationships": [],
            },
            "reference_stats": {
                "summary": "s",
                "strengths": [],
                "weaknesses": [],
                "combat_read": "",
                "notes": "",
            },
            "art": {"style": "s", "palette_notes": "", "shots": []},
            "published_as": {"portrait_id": "", "def_path": ""},
        }

    restrictive = next(race_id for race_id, paths in sorted(closed.items()) if "qi" in paths)
    blocked = unique_characters._validate(
        [record("unique-0001", restrictive, "qi")], check_files=False
    )
    expect(
        any("closes" in issue for issue in blocked),
        f"{restrictive} closes the qi path but a qi character on it validated cleanly, so "
        f"the rule is not reading the bible's own closure",
    )

    # The counterweight. A species that closes nothing must be allowed everywhere, or
    # the guard would refuse most of a legitimate cast.
    open_species = next(
        race_id
        for race_id, entity in sorted(entries.items())
        if isinstance(entity, dict) and entity.get("domain") == "races" and race_id not in closed
    )
    for candidate in sorted(unique_characters.VALID_PATHS):
        issues = [
            issue
            for issue in unique_characters._validate(
                [record(f"unique-{candidate}", open_species, candidate)], check_files=False
            )
            if "closes" in issue
        ]
        expect(
            not issues,
            f"{open_species} closes no path but was refused on {candidate}: {issues}. A "
            f"guard that refuses a legal pairing is worse than none, because agents "
            f"learn to work around it",
        )


@case("unique_characters: a bloodline is a DESCENT, so canon needs a species named")
def _bloodline_race_requires_a_species() -> None:
    """Ten characters named a bloodline as their race and no species anywhere.

    The bible's `races` domain is not homogeneous: `type` runs species, hybrid, clade,
    symbiote, ectospecies and `bloodline`. A bloodline is a CONCENTRATION carried by a
    body, and the authored records say so in their own words - hearthborn is "averaged
    with whatever else the household took in", tideculled "crosses races freely - the
    cull was a political act, never an anatomical one".

    So `appearance.race: races.tideborn` names a descent. A character whose only racial
    statement is that has no lifespan, no senses and no anatomy anywhere in the
    catalog, and `check` passed every one of them because a non-empty string is a valid
    race. Six characters are affected.

    The rule searches the WHOLE record, not just `appearance.race`. An author who wrote
    "a stonebound by way of the emberborn line" has grounded the character and must not
    be forced to relocate the fact into another field to satisfy a linter - four
    characters do exactly that and pass.

    The bloodline set is read from the bible rather than hardcoded: the concentrations
    grow, and a hardcoded list is exactly the kind of thing that goes stale here.
    """
    entries = unique_characters._lore_entries()
    expect(entries is not None, "the Lore Bible could not be read, so the rule is untested")
    if entries is None:
        return

    bloodlines = unique_characters.bloodline_races(entries)
    expect(
        bool(bloodlines),
        "no race in the bible has type `bloodline`, so the descent rule has nothing to "
        "fire on. Either the taxonomy changed or this case is stale",
    )

    def record(character_id: str, race: str, lore: str, age: str = "forty") -> dict:
        return {
            "id": character_id,
            "name": character_id,
            "status": "canon",
            "identity": {"role": "npc", "path": "qi", "faction": "", "home": "", "realm": ""},
            "appearance": {key: "" for key in unique_characters.APPEARANCE_KEYS}
            | {"race": race, "age": age},
            "tags": [],
            "canon": {
                "role_in_story": "",
                "first_appearance": "",
                "lore": lore,
                "history": [],
                "personality": {
                    k: [] if isinstance(v, list) else v
                    for k, v in (
                        ("summary", ""),
                        ("traits", []),
                        ("mannerisms", []),
                        ("motivations", []),
                        ("flaws", []),
                        ("voice", ""),
                        ("taboos", []),
                    )
                },
                "relationships": [],
            },
            "reference_stats": {
                "summary": "",
                "strengths": [],
                "weaknesses": [],
                "combat_read": "",
                "notes": "",
            },
            "art": {"style": "s", "palette_notes": "", "shots": []},
            "published_as": {"portrait_id": "", "def_path": ""},
        }

    a_bloodline = sorted(bloodlines)[0]
    a_species = next(
        race_id
        for race_id, entity in entries.items()
        if isinstance(entity, dict)
        and entity.get("domain") == "races"
        and entity.get("type") not in unique_characters.BLOODLINE_RACE_TYPES
    )
    species_name = a_species.split(".")[-1]

    ungrounded = record(
        "unique-0001",
        a_bloodline,
        "Carries the line. The household kept it carefully for generations.",
    )
    issues = [
        issue
        for issue in unique_characters._validate([ungrounded], check_files=False)
        if "bloodline" in issue
    ]
    expect(
        bool(issues),
        "a character whose only race is a bloodline passed validation, so it has no "
        "species anywhere and therefore no lifespan, senses or anatomy",
    )

    grounded = record(
        "unique-0002",
        a_bloodline,
        f"A {species_name} by way of the line, and the record says so plainly.",
    )
    clean = [
        issue
        for issue in unique_characters._validate([grounded], check_files=False)
        if "bloodline" in issue
    ]
    expect(
        not clean,
        f"a character that names the species carrying the line was still refused: {clean}. "
        f"The search must cover the narrative fields, or an author is forced to move the "
        f"fact into a different field to satisfy a linter",
    )

    # A MENTION is not a claim. Three real characters were passing for the wrong
    # reason: one linked `races.stonebound` as a relationship (which says connected,
    # not identical), one linked `races.echoless` deliberately as its mirror-opposite,
    # and one carried the tag `gift:unwritten-ledger` while its race field named a
    # bloodline. A substring search over the whole record accepts all three.
    incidental = record(
        "unique-0003",
        a_bloodline,
        "Carries the line. Her whole training is a discipline of not writing.",
    )
    incidental["tags"] = [f"gift:{species_name}-ledger"]
    incidental["canon"]["relationships"] = [
        {"to": f"races.{species_name}", "kind": "knows_about", "note": "a connection"}
    ]
    leaked = [
        issue
        for issue in unique_characters._validate([incidental], check_files=False)
        if "bloodline" in issue
    ]
    expect(
        bool(leaked),
        "a character passed on a species name that appeared only in a tag and a "
        "relationship, neither of which asserts what the character IS. A mention is "
        "not a claim, and a guard that accepts one lets a record stay unspecified",
    )


@case("unique_characters: one agent's torn shard must not block ANOTHER agent's add")
def _torn_shard_does_not_block_writers() -> None:
    """The failure that made agents hand-write rows, which caused the next torn shard.

    `_add` validated the whole catalog through the strict reader, so one agent's
    half-written shard made `unique_characters add` unusable for everyone. An agent
    reported being unable to use the tool for three of its four batches and writing
    its rows by hand instead - which is precisely how the torn shard arose in the
    first place, so the strict validation was not protecting anything; it was
    manufacturing the next incident.

    The distinction that resolves it: the CLOBBER risk lives in WRITING a partial
    view, not in validating one. `add` writes one record to one shard through a
    merging `_atomic_write`, so a foreign unreadable shard cannot cost anyone their
    rows - proven here by the valid neighbour still being present afterwards.

    The trade is deliberate and worth stating: while another shard is torn, this
    agent's own duplicate check is slightly weaker, because the torn rows are
    invisible to it. That is the right way round. `check` still fails loudly and
    names the file, so nothing is lost silently - it is only `add` that proceeds.

    The fixture uses a REAL `_blank_character` record. An earlier version of this
    probe used `{"id","name"}`, which the validator rejects for a missing `status`,
    so the block under test was indistinguishable from a bad fixture.
    """
    original = unique_characters.INDEX_PATH
    with tempfile.TemporaryDirectory() as raw:
        root = pathlib.Path(raw).resolve()
        unique_characters.INDEX_PATH = root / "unique-index.jsonl"
        try:
            good = unique_characters._shard_path("good")
            neighbour = unique_characters._blank_character("unique-0001", "Valid", "npc", "qi", "")
            unique_characters._atomic_write([neighbour], good)
            torn = unique_characters._shard_path("bad")
            torn.write_text('{"id":"unique-0002","name":"torn\n', encoding="utf-8")

            class _Args:
                character_id = "unique-0003"
                name = "Probe"
                role = "npc"
                path = "qi"
                style = ""
                shard = "probe"

            added = True
            try:
                unique_characters._add(_Args())
            except Exception as exc:  # noqa: BLE001 - the message is the assertion
                added = False
                detail = f"{type(exc).__name__}: {exc}"
            expect(
                added,
                f"`add` was blocked by another agent's torn shard ({detail if not added else ''}). "
                f"Strict validation here does not protect the catalog - it pushes agents to "
                f"hand-write rows, which is what creates torn shards",
            )

            survivors = {r["id"] for r in unique_characters.readable_catalog()}
            expect(
                {"unique-0001", "unique-0003"} <= survivors,
                f"the add did not survive alongside its neighbour: {sorted(survivors)}. "
                f"Writing through a merging _atomic_write must never cost a foreign shard "
                f"its rows",
            )
        finally:
            unique_characters.INDEX_PATH = original


@case("unique_characters: a TORN shard blocks writers but never blocks readers")
def _torn_shard_is_skipped_not_fatal() -> None:
    """A half-written shard blocked three agents for four minutes before this.

    An agent writing a shard directly, instead of through `unique_characters add`,
    produces a file whose last line is incomplete. `_atomic_write` does not prevent
    this - it only guarantees files IT writes are never partial - and the observed
    case was a shard growing 72KB -> 117KB while every reader raised
    `invalid JSON`.

    The two requirements pull opposite ways and both are asserted here. A concurrent
    READER must proceed, or one agent's typing blocks everyone. A broken shard must
    still be REPORTED, or the fix turns a loud defect into an invisible one - which is
    why `check` names the torn file rather than skipping it quietly.

    `_load_index` stays strict. A write built on a partial view would drop the rows
    it could not see, which is the clobber the shard flag exists to prevent.
    """
    original = unique_characters.INDEX_PATH
    with tempfile.TemporaryDirectory() as raw:
        root = pathlib.Path(raw).resolve()
        unique_characters.INDEX_PATH = root / "unique-index.jsonl"
        try:
            good = unique_characters._shard_path("good")
            torn = unique_characters._shard_path("torn")
            unique_characters._atomic_write([{"id": "unique-0001", "name": "ok"}], good)
            with torn.open("w", encoding="utf-8", newline="\n") as handle:
                handle.write('{"id":"unique-0002","name":"partial')

            expect(
                unique_characters._shard_is_complete(good)
                and not unique_characters._shard_is_complete(torn),
                "a torn shard must be detectable, or `readable_catalog` cannot skip it",
            )

            readable = unique_characters.readable_catalog()
            expect(
                [r["id"] for r in readable] == ["unique-0001"],
                f"a torn shard changed what a concurrent reader sees: "
                f"{[r['id'] for r in readable]}. One agent's in-progress write must not "
                f"block every other agent",
            )

            raised = False
            try:
                unique_characters._load_index()
            except Exception:
                raised = True
            expect(
                raised,
                "_load_index accepted a torn shard. It is the strict reader used by "
                "writers, and a write built on a partial view drops the rows it could "
                "not see - the exact clobber sharding exists to prevent",
            )
        finally:
            unique_characters.INDEX_PATH = original


@case("unique_characters: `add` reports the file it WROTE, not the primary index")
def _add_reports_the_real_output_path() -> None:
    """A sharded write reported the wrong file, so an author could not verify its work.

    `add` printed `INDEX_PATH` unconditionally. With `--shard wave-1` the record
    went to `unique-index-wave-1.jsonl` and the confirmation named
    `unique-index.jsonl`. An agent checking where its character landed would look
    in the wrong file and conclude the record was lost - which is the exact
    reasoning that leads someone to re-add it and create a duplicate.

    A tool that misreports its own output path is the same hazard class as the
    clobber it was introduced alongside: a confident message about the wrong thing.

    The assertion reads the message off a real sharded add, and also pins the
    catalog-outside-the-repo case, because `relative_to(REPO_ROOT)` raises there and
    turned this very message into a crash.
    """
    original = unique_characters.INDEX_PATH
    original_root = unique_characters.REPO_ROOT
    with tempfile.TemporaryDirectory() as raw:
        unique_characters.INDEX_PATH = pathlib.Path(raw).resolve() / "unique-index.jsonl"
        try:

            class _Args:
                character_id = "unique-0001"
                name = "Probe"
                role = "npc"
                path = "qi"
                style = ""
                shard = "wave-99"

            messages: list[str] = []
            original_ok = unique_characters.ok
            try:
                unique_characters.ok = messages.append
                unique_characters._add(_Args())
            finally:
                unique_characters.ok = original_ok

            written = {path.name for path in pathlib.Path(raw).iterdir()}
            expect(
                written == {"unique-index-wave-99.jsonl"},
                f"the sharded add wrote {sorted(written)}; expected only the shard",
            )
            expect(
                bool(messages) and "unique-index-wave-99.jsonl" in messages[0],
                f"the confirmation did not name the shard that received the record: "
                f"{messages!r}. An agent verifying its own write would look in the wrong "
                f"file and conclude the character was lost",
            )
            expect(
                bool(messages) and not messages[0].endswith("unique-index.jsonl; fill"),
                f"the confirmation named the primary index for a sharded write: {messages!r}",
            )
        finally:
            unique_characters.INDEX_PATH = original
            unique_characters.REPO_ROOT = original_root


@case("unique_characters: a concurrent writer CANNOT delete another agent's characters")
def _concurrent_write_cannot_clobber() -> None:
    """The hazard that would have destroyed most of a 1000-character cast.

    `_atomic_write` originally rewrote the whole file from the caller's in-memory
    list. Two agents therefore load the catalog, agent A writes its id range, and
    agent B - still holding a pre-A snapshot - writes its own range and deletes A's
    characters. No error, no warning, exit 0.

    Measured before the fix, in this same harness: A wrote 2 rows, B wrote 2 rows,
    and A's rows were gone. Two concurrent character waves would have done exactly
    that, and the loss would have looked like an agent forgetting to save.

    Three scenarios are covered because two mitigations are claimed and they fail
    differently. Separate SHARDS mean the writers never touch the same file.
    MERGE-ON-WRITE means even a same-file writer that only knows its own rows
    preserves the others - which is what covers a third agent that forgot to shard.
    """
    original_index = unique_characters.INDEX_PATH
    original_exists = unique_characters.INDEX_PATH.is_file()
    with tempfile.TemporaryDirectory() as raw:
        unique_characters.INDEX_PATH = pathlib.Path(raw) / "unique-index.jsonl"
        try:

            def row(cid: str) -> dict:
                return {"id": cid, "name": cid}

            shard_a = unique_characters._shard_path("wave-01")
            shard_b = unique_characters._shard_path("wave-02")
            unique_characters._atomic_write([row("unique-0001"), row("unique-0002")], shard_a)
            unique_characters._atomic_write([row("unique-0011"), row("unique-0012")], shard_b)
            sharded = {r["id"] for r in unique_characters._load_index()}
            expect(
                {"unique-0001", "unique-0002", "unique-0011", "unique-0012"} <= sharded,
                f"two agents writing separate shards lost characters: {sorted(sharded)}. "
                f"Distinct shards are supposed to make collision impossible",
            )

            # Same file, and each writer only knows its OWN rows - the case a
            # third agent hits by forgetting --shard entirely.
            unique_characters.INDEX_PATH = pathlib.Path(raw) / "single.jsonl"
            unique_characters._atomic_write([row("unique-0003")], None)
            unique_characters._atomic_write([row("unique-0004")], None)
            merged = {r["id"] for r in unique_characters._load_index()}
            expect(
                {"unique-0003", "unique-0004"} <= merged,
                f"a writer that knew only its own row deleted the other: {sorted(merged)}. "
                f"Merge-on-write is what covers an agent that forgot to shard",
            )

            # The original hazard exactly: a stale full snapshot, written twice.
            unique_characters.INDEX_PATH = pathlib.Path(raw) / "stale.jsonl"
            unique_characters._atomic_write([row("unique-0005"), row("unique-0006")], None)
            stale = unique_characters._load_index()
            unique_characters._atomic_write([*stale, row("unique-0007")], None)
            unique_characters._atomic_write([*stale, row("unique-0008")], None)
            survived = {r["id"] for r in unique_characters._load_index()}
            expect(
                {"unique-0005", "unique-0006", "unique-0007", "unique-0008"} <= survived,
                f"a stale snapshot still deletes rows: {sorted(survived)}. This is the "
                f"exact shape that destroyed two characters when measured",
            )
        finally:
            unique_characters.INDEX_PATH = original_index
            if not original_exists:
                unique_characters.INDEX_PATH.unlink(missing_ok=True)


@case("unique_characters: a tag may NOT overwrite a structural diversity axis")
def _tag_cannot_replace_a_structural_axis() -> None:
    """A tag named `path:` used to REPLACE the `identity.path` counter.

    `axes.setdefault(axis, Counter())` meant a character carrying `path:body-path`
    as a tag handed the structural axis its own vocabulary. `diversity` then
    reported `path` as six distinct values including `none` and `body-path` - which
    are not in `VALID_PATHS` at all - while the real paths went uncounted.

    That is worse than a cosmetic mislabel, because the axis read as MORE diverse
    than it was. A cast of four reported six path values; the truth was three. At
    1000 characters a swapped axis is a monoculture that reports as diversity, and
    nothing else in the tool would catch it.

    The structural axes are counted from their own fields and a colliding tag axis
    is counted under `tag:<name>`, so the collision stays visible.
    """
    plain = {
        "id": "unique-0001",
        "name": "One",
        "identity": {"role": "npc", "path": "qi"},
        "appearance": {"race": "races.emberblood"},
        "tags": [],
    }
    tagged = {
        **plain,
        "id": "unique-0002",
        "tags": ["path:body-path", "path:none"],
    }
    axes = dict(unique_characters._diversity_axes([plain, tagged]))
    path_counts = axes["path"]

    expect(
        set(path_counts) == {"qi"},
        f"the structural path axis reads {dict(path_counts)}; a tag named `path:` must not "
        f"replace it, or the distribution reports values outside VALID_PATHS and a "
        f"monoculture reads as diversity",
    )
    expect(
        "tag:path" in axes,
        f"the colliding tag axis vanished instead of being reported: {sorted(axes)}. "
        f"Renaming it to `tag:path` keeps the collision visible rather than silently "
        f"swapping one measurement for another",
    )
    expect(
        axes["tag:path"]["body-path"] == 1,
        f"the tag's own values were not counted under tag:path: {dict(axes.get('tag:path', {}))}",
    )


@case("lore: CONTEXT_HOPS relations are mostly UNREACHABLE inbound, and that is reported")
def _hop_inbound_asymmetry_is_reported() -> None:
    """The trap that cost several agent waves, asserted so it cannot be rediscovered.

    `_incident` follows an outbound edge whose relation is in the hop list, or an
    INBOUND edge whose registry inverse is in it. `CONTEXT_HOPS` names 20 relations
    and 18 of their inverses are not among them - only `conflicts_with` and
    `trades_with` are symmetric. So for `people` and `families`, ZERO inbound
    relations work.

    The consequence is that `people.X member_of organizations.Y` is invisible when
    walking from `organizations.Y`: the edge exists, its endpoints resolve, and
    `validate` is green, but the walk cannot follow it. An agent can write a
    hundred such edges and move nothing, which is exactly what happened - one
    families shard took degree from 0.0 to 11.8 with all 41 families still
    unreachable.

    The second expectation is the counterweight: the report must not claim more
    than the registry supports. If it asserted every domain had some inbound
    relation, it would be reassuring and wrong.
    """
    bible = lore.model.load_bible()
    registry = bible.registry
    accepted = {rel for _domain, rels, _purpose in lore.context.CONTEXT_HOPS for rel in rels}

    asymmetric = []
    for rel in sorted(accepted):
        inverse = registry.inverse(rel)
        if inverse and inverse not in accepted:
            asymmetric.append((rel, inverse))
    expect(
        len(asymmetric) >= 15,
        f"only {len(asymmetric)} of {len(accepted)} accepted relations have an unnamed "
        f"inverse; the inbound trap this asserts is a property of the registry, and if it "
        f"has been fixed this case must be revisited rather than deleted",
    )

    for domain in ("people", "families"):
        _outbound, inbound = lore.context._hop_reachable_relations(bible, domain)
        expect(
            inbound == (),
            f"{domain} now reports inbound relations {inbound!r}; if the hop list was "
            f"widened this assertion is stale, and until someone checks which is true, "
            f"briefs will keep telling agents the wrong direction",
        )

    # The counterweight: a domain whose relations ARE symmetric must report them,
    # so the helper is not simply returning () for everything.
    _out, conflicts_inbound = lore.context._hop_reachable_relations(bible, "conflicts")
    expect(
        "conflicts_with" in conflicts_inbound,
        f"conflicts reports inbound {conflicts_inbound!r}, but conflicts_with is its own "
        f"inverse so it must work from both sides. A helper that returned () everywhere "
        f"would pass the two assertions above while describing nothing",
    )


@case("lore: character context names the domains it could not reach")
def _context_reports_gaps() -> None:
    """The half that matters most, because a silent omission is worse than a gap.

    A resolver that quietly returns the little it found looks identical to one that
    found everything, so a character gets written against invented background and
    nothing in the pipeline says so. This asserts the missing half is REPORTED, and
    that a connected domain IS counted - otherwise a resolver that always returns
    "everything is missing" would pass.
    """
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        _write_lore(
            root,
            {
                "races": [_entity("races", "emberblood")],
                "geography": [_entity("geography", "ash_flats")],
            },
            {
                "batch": [
                    {"from": "races.emberblood", "rel": "native_to", "to": "geography.ash_flats"}
                ]
            },
        )
        context = resolve_context(_lore_bible(root), "races.emberblood", depth=1)
        expect(
            context["ready"] is False,
            "an anchor with one of seventeen character domains reachable was called ready",
        )
        missing = {gap["domain"] for gap in context["gaps"]}
        expect(
            "cultures" in missing and "history" in missing,
            "context claimed to be complete while cultures and history were never "
            "reached; those are the two domains that make a character a product of a "
            "world rather than an invention",
        )
        expect(
            "geography" not in missing,
            f"a domain that WAS reached was reported as missing: {sorted(missing)}",
        )


@case("lore: character context is bounded, not an unbounded walk")
def _context_is_bounded() -> None:
    """A lore bible is a graph with no natural smallness.

    A well-connected cosmology node reaches most of the book, so an unbounded walk
    hangs on the HEALTHIEST bible rather than the broken one - backwards. This builds
    a chain deeper than any sane depth and asserts the walk returns and says it was
    truncated.
    """
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        entities = [_entity("races", "root")]
        edges = []
        for index in range(40):
            slug = f"culture_{index:02d}"
            entities.append(_entity("cultures", slug))
            parent = f"cultures.culture_{index - 1:02d}" if index else "races.root"
            edges.append({"from": f"cultures.{slug}", "rel": "influenced_by", "to": parent})
        _write_lore(root, {"races": entities[:1], "cultures": entities[1:]}, {"batch": edges})
        context = resolve_context(_lore_bible(root), "races.root", depth=4)
        pulled = len(context["inherited"].get("cultures", []))
        expect(
            pulled <= 12,
            f"a single anchor pulled in {pulled} culture records; an unbounded walk would "
            "make this command unusable on a well-built bible, because a well-connected "
            "node reaches most of the book",
        )


@case("lore: a character draft carries NO numbers in reference_stats")
def _draft_is_prose_only() -> None:
    """The seam between two ADRs, asserted.

    ADR 0138 made `reference_stats` prose and `unique_characters check` refuses a
    number there. The resolver feeds that block, so a resolver that emitted stat
    values would push every author straight through a guard the project spent real
    effort building - and it would do it silently, since the numbers would look
    like useful output.
    """
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        _write_lore(
            root,
            {"races": [_entity("races", "emberblood")]},
            {},
        )
        bible = _lore_bible(root)
        context = resolve_context(bible, "races.emberblood", depth=1)
        draft = character_draft(context, name="Test Subject", path="qi")
        findings = unique_characters._no_stat_numbers(
            draft["reference_stats"], "reference_stats", unique_characters._authored_stat_ids()
        )
        expect(
            not findings,
            "the resolver emitted numbers into a prose-only block: " + "; ".join(findings),
        )
        expect(
            draft["status"] == "draft",
            f"the resolver set status to {draft['status']!r}; 'the world's background "
            "exists' is not the same claim as 'this person is written', and only a human "
            "judgement about the lore may promote a record to canon",
        )


@case("lore: character readiness reports 0% rather than passing on an empty sample")
def _character_ready_is_not_vacuous() -> None:
    """The guard-shape hazard this repo has hit repeatedly.

    A readiness check over zero anchors divides by nothing and reports nothing, which
    reads as "no problems found". It has to fail, because a bible with no species has
    no character to describe and that is the opposite of ready.
    """
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        _write_lore(root, {"geography": [_entity("geography", "ash_flats")]}, {})
        payload = readiness_gaps(_lore_bible(root))
        expect(
            payload["sampled"] == 0,
            f"readiness sampled {payload['sampled']} anchors from a bible with no races; a "
            "sampler that reports 0 sampled must not be read as 0 failures",
        )
        expect(
            payload["ready"] == 0 and payload["readiness_ratio"] == 0.0,
            "an empty sample reported non-zero readiness",
        )


@case("lore: re-ingest does NOT revert an enriched stub (it did, destructively)")
def _ingest_preserves_agent_work() -> None:
    """A regression test for a real loss of authored work.

    `lore ingest` originally assigned over every record it imported, so re-running
    it reverted each enriched stub to the content-free placeholder the importer
    generates. It cost the cosmology batch seven records and 359 characters of
    prose in a single command that printed `ok` - the entity count was unchanged,
    so nothing looked wrong.

    This asserts the merge respects an agent's curation: a record whose summary and
    `lore_depth` were written by hand survives a re-import, while the fields the
    game data actually owns still refresh.
    """
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        original = lore.model.REPO_ROOT
        original_game = lore.ingest.GAME_DIR
        original_repo = lore.ingest.REPO_ROOT
        original_lore = lore.model.LORE_ROOT
        lore.model.REPO_ROOT = root
        lore.ingest.REPO_ROOT = root
        lore.ingest.GAME_DIR = root / "game"
        lore.model.LORE_ROOT = root / "lore"
        try:
            game = root / "game" / "data" / "races"
            game.mkdir(parents=True)
            (game / "emberblood.tres").write_text(
                '[gd_resource type="Resource" script_class="RaceDef" format=3]\n\n[resource]\n'
                'id = &"emberblood"\n'
                'display_name = "Emberblood"\n'
                'description = "A body that runs hot."\n'
                "realm_ceiling = 8\n",
                encoding="utf-8",
            )
            bible_dir = root / "lore" / "bible"
            bible_dir.mkdir(parents=True)
            domains, _edges, _counts = lore.ingest.build_import()
            enriched = {
                "id": "races.emberblood",
                "domain": "races",
                "type": "race",
                "name": "Emberblood",
                "summary": "AGENT AUTHORED PROSE that explains why this body exists.",
                "tags": ["agent-written"],
                "status": "active",
                "provenance": {"author": "an-agent"},
                "attributes": {"lore_depth": "authored", "realm_ceiling": 99},
            }
            for domain, records in domains.items():
                merged = {r["id"]: r for r in records}
                if "races.emberblood" in merged:
                    merged["races.emberblood"] = enriched
                (bible_dir / f"{domain}.jsonl").write_text(
                    "".join(
                        json.dumps(r, ensure_ascii=False, separators=(",", ":")) + "\n"
                        for r in sorted(merged.values(), key=lambda item: item["id"])
                    ),
                    encoding="utf-8",
                )
            lore.ingest.write_import(force=False)
            rows = [
                json.loads(line)
                for line in (bible_dir / "races.jsonl").read_text(encoding="utf-8").splitlines()
                if line.strip()
            ]
            after = next(r for r in rows if r["id"] == "races.emberblood")
        finally:
            lore.model.REPO_ROOT = original
            lore.ingest.GAME_DIR = original_game
            lore.ingest.REPO_ROOT = original_repo
            lore.model.LORE_ROOT = original_lore

    expect(
        after["summary"] == enriched["summary"],
        "re-ingest overwrote an agent-authored summary: "
        f"{after['summary'][:70]!r}. `ok` was printed and the entity count was unchanged, "
        "so the loss was invisible - see INC-0007's shape in a different tool",
    )
    expect(
        after["attributes"]["lore_depth"] == "authored",
        f"re-ingest reverted lore_depth to {after['attributes']['lore_depth']!r}, undoing an "
        "agent's promotion of a stub",
    )
    expect(
        after["attributes"]["realm_ceiling"] == 8,
        f"re-ingest did not refresh a game-owned scalar: "
        f"{after['attributes']['realm_ceiling']!r} should have become 8, the value the "
        "authored .tres states. The merge exempts only AGENT_OWNED_FIELDS and "
        "attributes.lore_depth, so an authored scalar must still track the game data - "
        "and a scalar that never refreshed would let the bible drift from the game "
        "silently, which is the coupling this index exists to keep honest",
    )


@case("lore: re-ingest MERGES provenance instead of reassigning it")
def _reingest_merges_provenance() -> None:
    """The merge tested summary, lore_depth and the game scalars, and never provenance.

    The fixture for the case above has always contained `"provenance": {"author":
    "an-agent"}` and has never asserted on it - so the field that actually broke
    was sitting in the test unwritten, which is the whole of INC-0016. Prose
    survived a re-import while `author`, `created` and the `abstract-pattern:`
    basis entries were overwritten, and the command still printed "agent-authored
    records preserved". The half that records WHO wrote a record and WHY was the
    half being eaten, and it is the half every later agent reads.

    Two shapes are asserted, because they fail differently:

    - an agent AUTHORED the record, so `author` must survive over the importer's.
    - the IMPORTER authored it and an agent later EXTENDED it, so `author` is
      still the importer but `extended_by` must survive. That second shape is the
      one the substring dedup killed: `_is_import_line` tested the raw line for
      `"tools lore ingest"`, so any record mentioning the importer anywhere was
      dropped from `existing` and replaced wholesale, taking the extension with
      it. An agent extending an imported record is the NORMAL way this bible
      grows, so the common case was the broken one.
    """
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        original = lore.model.REPO_ROOT
        original_game = lore.ingest.GAME_DIR
        original_repo = lore.ingest.REPO_ROOT
        original_lore = lore.model.LORE_ROOT
        lore.model.REPO_ROOT = root
        lore.ingest.REPO_ROOT = root
        lore.ingest.GAME_DIR = root / "game"
        lore.model.LORE_ROOT = root / "lore"
        try:
            game = root / "game" / "data" / "races"
            game.mkdir(parents=True)
            (game / "emberblood.tres").write_text(
                '[gd_resource type="Resource" script_class="RaceDef" format=3]\n\n[resource]\n'
                'id = &"emberblood"\n'
                'display_name = "Emberblood"\n'
                'description = "A body that runs hot."\n'
                "realm_ceiling = 8\n",
                encoding="utf-8",
            )
            (game / "ashwalker.tres").write_text(
                '[gd_resource type="Resource" script_class="RaceDef" format=3]\n\n[resource]\n'
                'id = &"ashwalker"\n'
                'display_name = "Ashwalker"\n'
                'description = "Grey-skinned and patient."\n'
                "realm_ceiling = 5\n",
                encoding="utf-8",
            )
            bible_dir = root / "lore" / "bible"
            bible_dir.mkdir(parents=True)
            domains, _edges, _counts = lore.ingest.build_import()
            authored = {
                "id": "races.emberblood",
                "domain": "races",
                "type": "race",
                "name": "Emberblood",
                "summary": "AGENT AUTHORED PROSE.",
                "tags": ["agent-written"],
                "status": "active",
                "provenance": {
                    "author": "w1-races",
                    "created": "2026-01-01",
                    "basis": [
                        "authored-game-data:game/data/races/emberblood.tres",
                        "abstract-pattern:a-reading-needs-the-smallest-budget-that-holds-it",
                    ],
                },
                "attributes": {"lore_depth": "authored"},
            }
            extended = {
                "id": "races.ashwalker",
                "domain": "races",
                "type": "race",
                "name": "Ashwalker",
                "summary": "IMPORT PROSE, later enriched.",
                "tags": ["race"],
                "status": "active",
                "provenance": {
                    "author": "tools lore ingest",
                    "created": "2026-01-01",
                    "basis": ["authored-game-data"],
                    "schema_version": lore.ingest.SCHEMA_VERSION,
                    "extended_by": "w1-races",
                },
                "attributes": {"lore_depth": "stub"},
            }
            for domain, records in domains.items():
                merged = {r["id"]: r for r in records}
                if "races.emberblood" in merged:
                    merged["races.emberblood"] = authored
                if "races.ashwalker" in merged:
                    merged["races.ashwalker"] = extended
                (bible_dir / f"{domain}.jsonl").write_text(
                    "".join(
                        json.dumps(r, ensure_ascii=False, separators=(",", ":")) + "\n"
                        for r in sorted(merged.values(), key=lambda item: item["id"])
                    ),
                    encoding="utf-8",
                )
            lore.ingest.write_import(force=False)
            rows = {
                r["id"]: r
                for r in (
                    json.loads(line)
                    for line in (bible_dir / "races.jsonl").read_text(encoding="utf-8").splitlines()
                    if line.strip()
                )
            }
            got_authored = rows["races.emberblood"]["provenance"]
            got_extended = rows["races.ashwalker"]["provenance"]
        finally:
            lore.model.REPO_ROOT = original
            lore.ingest.GAME_DIR = original_game
            lore.ingest.REPO_ROOT = original_repo
            lore.model.LORE_ROOT = original_lore

    expect(
        got_authored.get("author") == "w1-races",
        f"re-ingest replaced an agent's provenance author with "
        f"{got_authored.get('author')!r}. Prose survives the merge and authorship does "
        f"not, so the bible keeps WHAT was written and loses WHY - and the run still "
        f"reported agent-authored records preserved",
    )
    expect(
        got_authored.get("created") == "2026-01-01",
        f"re-ingest restamped an agent-authored record's created date as "
        f"{got_authored.get('created')!r}, erasing when the reasoning was written",
    )
    expect(
        "abstract-pattern:a-reading-needs-the-smallest-budget-that-holds-it"
        in (got_authored.get("basis") or []),
        f"re-ingest dropped the abstract-pattern basis entry: {got_authored.get('basis')!r}. "
        f"That entry is the only record of the reasoning behind the entry, and no other "
        f"field holds it",
    )
    expect(
        got_extended.get("extended_by") == "w1-races",
        f"re-ingest dropped extended_by from a record it had authored and an agent had "
        f"extended: {got_extended!r}. This is the common growth path - an agent enriching "
        f"an imported record - and a substring test for the importer's author string "
        f"classified exactly those records as replaceable",
    )


@case("lore: re-ingest still refreshes a record NO agent has touched")
def _reingest_still_refreshes_untouched() -> None:
    """The counterweight to the case above.

    "Preserve the agent's work" is satisfiable by never overwriting anything, and
    that fix would pass the provenance case while silently breaking the coupling
    this index exists to keep honest: a `.tres` edited in the game must reach the
    bible. A guard test whose fixture cannot distinguish preserving from disabling
    tests nothing about the preserving (INC-0016), so this asserts the importer
    still does its one job.
    """
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        original = lore.model.REPO_ROOT
        original_game = lore.ingest.GAME_DIR
        original_repo = lore.ingest.REPO_ROOT
        original_lore = lore.model.LORE_ROOT
        lore.model.REPO_ROOT = root
        lore.ingest.REPO_ROOT = root
        lore.ingest.GAME_DIR = root / "game"
        lore.model.LORE_ROOT = root / "lore"
        try:
            game = root / "game" / "data" / "races"
            game.mkdir(parents=True)
            (game / "emberblood.tres").write_text(
                '[gd_resource type="Resource" script_class="RaceDef" format=3]\n\n[resource]\n'
                'id = &"emberblood"\n'
                'display_name = "Emberblood"\n'
                'description = "A body that runs hot."\n'
                "realm_ceiling = 8\n",
                encoding="utf-8",
            )
            bible_dir = root / "lore" / "bible"
            bible_dir.mkdir(parents=True)
            domains, _edges, _counts = lore.ingest.build_import()
            for domain, records in domains.items():
                (bible_dir / f"{domain}.jsonl").write_text(
                    "".join(
                        json.dumps(r, ensure_ascii=False, separators=(",", ":")) + "\n"
                        for r in sorted(records, key=lambda item: item["id"])
                    ),
                    encoding="utf-8",
                )
            lore.ingest.write_import(force=False)
            first_pass = {
                r["id"]: r
                for r in (
                    json.loads(line)
                    for line in (bible_dir / "races.jsonl").read_text(encoding="utf-8").splitlines()
                    if line.strip()
                )
            }
            # The depth the IMPORT produced, not a guess: this fixture's .tres
            # carries a real description, so the honest invariant is "a record no
            # agent touched comes back unchanged", not a hardcoded "stub".
            imported_depth = first_pass["races.emberblood"]["attributes"]["lore_depth"]
            lore.ingest.write_import(force=False)
            rows = {
                r["id"]: r
                for r in (
                    json.loads(line)
                    for line in (bible_dir / "races.jsonl").read_text(encoding="utf-8").splitlines()
                    if line.strip()
                )
            }
            untouched = rows["races.emberblood"]
            untouched_depth = untouched["attributes"]["lore_depth"]
            untouched_provenance = dict(untouched["provenance"])
        finally:
            lore.model.REPO_ROOT = original
            lore.ingest.GAME_DIR = original_game
            lore.ingest.REPO_ROOT = original_repo
            lore.model.LORE_ROOT = original_lore

    expect(
        untouched["attributes"]["realm_ceiling"] == 8,
        f"an untouched imported record lost its game-owned scalar: "
        f"{untouched['attributes']['realm_ceiling']!r}. If re-ingest stopped refreshing "
        f"game-owned fields it would satisfy the preservation case while letting the "
        f"bible drift from the authored .tres with nothing reporting it",
    )
    expect(
        untouched_depth == imported_depth,
        f"an untouched record's lore_depth drifted from {imported_depth!r} to "
        f"{untouched_depth!r} across a re-ingest, so the importer is now rewriting "
        f"curation on records no agent has touched",
    )
    expect(
        untouched_provenance.get("schema_version") == lore.ingest.SCHEMA_VERSION,
        f"the importer stopped stamping its own schema_version: {untouched_provenance!r}. "
        f"schema_version is the one provenance field the importer owns, so losing it "
        f"means the merge stopped merging rather than preserving",
    )


@case("lore: --force IS destructive, and says so")
def _force_is_destructive() -> None:
    """The opt-out has to actually opt out, or the safe default is the only path.

    Without this, `force` could be wired to nothing and the default path would look
    deliberate while being the only behaviour anyone can reach.
    """
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        original = lore.model.REPO_ROOT
        original_game = lore.ingest.GAME_DIR
        original_repo = lore.ingest.REPO_ROOT
        original_lore = lore.model.LORE_ROOT
        lore.model.REPO_ROOT = root
        lore.ingest.REPO_ROOT = root
        lore.ingest.GAME_DIR = root / "game"
        lore.model.LORE_ROOT = root / "lore"
        try:
            game = root / "game" / "data" / "races"
            game.mkdir(parents=True)
            (game / "emberblood.tres").write_text(
                '[gd_resource type="Resource" format=3]\n\n[resource]\n'
                'id = &"emberblood"\ndisplay_name = "Emberblood"\n'
                'description = "A body."\n',
                encoding="utf-8",
            )
            bible_dir = root / "lore" / "bible"
            bible_dir.mkdir(parents=True)
            lore.ingest.write_import(force=False)
            domains, _edges, _counts = lore.ingest.build_import()
            merged = {r["id"]: r for r in domains.get("races", [])}
            if "races.emberblood" in merged:
                merged["races.emberblood"]["summary"] = "HAND WRITTEN"
            (bible_dir / "races.jsonl").write_text(
                "".join(
                    json.dumps(r, ensure_ascii=False, separators=(",", ":")) + "\n"
                    for r in sorted(merged.values(), key=lambda item: item["id"])
                ),
                encoding="utf-8",
            )
            lore.ingest.write_import(force=True)
            rows = [
                json.loads(line)
                for line in (bible_dir / "races.jsonl").read_text(encoding="utf-8").splitlines()
                if line.strip()
            ]
            # Look the record up by id. Reading `splitlines()[0]` assumed the
            # fixture held exactly one race and would silently assert on the wrong
            # record the moment it held two.
            after = next(r for r in rows if r["id"] == "races.emberblood")
        finally:
            lore.model.REPO_ROOT = original
            lore.ingest.GAME_DIR = original_game
            lore.ingest.REPO_ROOT = original_repo
            lore.model.LORE_ROOT = original_lore

    expect(
        after["summary"] != "HAND WRITTEN",
        "--force did not discard the hand-written summary, so the flag that warns about "
        "data loss is wired to nothing and the safe default is the only reachable path",
    )


@case("lore: the importer states no law SEATS in a tier it never reads that fact from")
def _ingest_does_not_assert_seating() -> None:
    """Two author agents independently reported this contradiction, unprompted.

    `WorldLawDef.tier_ids` lists every tier a law may hold force in - APPLICABILITY.
    Emitting one `applies_in` edge per tier therefore asserted "all six laws govern
    all four tiers equally", which contradicts the authored `law_slots` of 3/6/10/15
    against six laws AND the material each tier lists. Both the cosmology and the
    history batch flagged it as incoherent, from opposite directions.

    The importer must not resolve a question it has no data for: seating is a
    per-world fact no `.tres` states.
    """
    domains, edges, _counts = lore.ingest.build_import()
    seating = [edge for edge in edges if edge["rel"] == "applies_in"]
    expect(
        not seating,
        f"the importer emitted {len(seating)} applies_in edges asserting every law "
        "governs every tier, which contradicts the seat budget the same importer "
        "reads from law_slots",
    )
    laws = domains.get("cosmology", [])
    mortal = next((r for r in laws if r["id"] == "cosmology.mortal_world"), None)
    expect(
        mortal is not None and "tier_ids" not in mortal.get("attributes", {}),
        "tier_ids on a tier record is applicability metadata on the wrong entity",
    )


# --- INC-0018: an expired lock wait must name WHO holds it and how long, or say that
# --- nobody has. The two cases used to be one sentence, and the only safe response to an
# --- ambiguous lock is to WAIT, so an agent that cannot tell them apart eventually
# --- deletes godot.lock - which is BL-0424 on a lock with a live owner.


def _expiry_against(root: Path) -> str:
    """`_lock_expiry` over a fixture sidecar rather than the repository's.

    Both paths are redirected, not just the lock. `PROJECT_LOCK` is read back into the
    message ("do not delete godot.lock"), so leaving it pointed at the real file would
    report a name the fixture never asserted - and a guard test that checks a real
    path for a real file's contents is the wrong-tree bug `lore.context` already paid
    for once.

    The message is built with NO holder rather than by driving `project_lock()` at an
    expired clock. That is deliberate: a wait expiry needs an *other* live process to
    race for the lock, and this repo has been reset twice by runaway processes. A test
    suite that hangs is worse than the bug it covers, so the message is exercised where
    the incident lives - in what it says - and the acquire/release contract is asserted
    separately, in-process, with no contention and no engine.
    """
    original = godot.PROJECT_LOCK, godot.PROJECT_LOCK_OWNER
    godot.PROJECT_LOCK = root / godot.PROJECT_LOCK.name
    godot.PROJECT_LOCK_OWNER = root / godot.PROJECT_LOCK_OWNER.name
    try:
        return godot._lock_expiry(f"another Godot run still held {godot.PROJECT_LOCK.name}")
    finally:
        godot.PROJECT_LOCK, godot.PROJECT_LOCK_OWNER = original


def _owner_sidecar(root: Path, pid: int, seconds_ago: float) -> Path:
    """A fixture sidecar naming `pid` as holding the lock `seconds_ago`."""
    since = datetime.now(UTC) - timedelta(seconds=seconds_ago)
    return write(
        root / godot.PROJECT_LOCK_OWNER.name,
        json.dumps({"pid": pid, "since": since.isoformat(timespec="seconds")}) + "\n",
    )


@case("godot: an expired lock wait NAMES the holder pid and how long it has held it")
def _lock_expiry_names_the_holder() -> None:
    """The case INC-0018 actually reported, and the reason the sidecar exists.

    The old message was `another Godot run has held godot.lock for more than 900s`. An
    agent reading that learns nothing actionable: it cannot tell a run that started two
    seconds ago from one that wedged at the same moment it did, and it cannot tell
    either from a holder that died mid-lock. So it waits, and then it deletes the file,
    because waiting has stopped being a plan.
    """
    holder = 71564
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        _owner_sidecar(root, holder, seconds_ago=95)

        message = _expiry_against(root)

        expect(
            str(holder) in message,
            f"the expiry message names no holder pid, so a blocked agent cannot find "
            f"out who to wait for: {message}",
        )
        expect(
            "1m" in message,
            f"the expiry message reports no hold duration; a lock taken 95s ago has to "
            f"read as 1m so the number is comparable to the 900s ceiling: {message}",
        )
        expect(
            "since" in message and "WAIT" in message,
            "the expiry message gives neither the moment the lock was taken nor the "
            f"action to take next, which is the whole content of the fix: {message}",
        )


@case("godot: an expired lock wait with NO sidecar says the holder never recorded itself")
def _lock_expiry_without_a_sidecar_says_so() -> None:
    """The branch that matters most, and the one the old message could not express.

    A missing sidecar while the lock is demonstrably held is not an absence of
    information, it IS the information: the process that took the lock never reached
    its own cleanup. That is the case INC-0018's reporter would otherwise have had to
    resolve by deleting a live lock file - it looked exactly like the 22-hour-old empty
    stale lock they were staring at.
    """
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)

        message = _expiry_against(root)

        expect(
            godot.PROJECT_LOCK_OWNER.name in message
            and "no holder has ever recorded itself there" in message,
            "the expiry message does not say that no holder recorded itself, so the "
            "dead-holder case still reads as an ordinary queue: " + message,
        )
        expect(
            "WAITING CANNOT HELP" in message and "re-run the same command" in message,
            "the no-sidecar branch does not name the action that can work. Waiting is "
            "provably futile here - the process that holds the lock is not running to "
            "release it - so the message has to say so: " + message,
        )
        expect(
            "do not delete the file" in message,
            "the no-sidecar branch leaves an agent with no safe instruction, which is "
            "precisely how the lock file gets deleted: " + message,
        )


@case("godot: holding the project lock publishes its holder, and releases clear it")
def _lock_publishes_and_clears_its_holder() -> None:
    """The other half of the contract, and the half that keeps the two cases apart.

    If the sidecar were written before the lock was taken, or cleared after it was
    given up, it would describe a holder that does not have the lock - which is how a
    diagnostic turns into a lie. And if it is never cleared at all, every expiry would
    name the last agent to run and none of them would ever look dead.

    No contention and no engine: this only needs one process entering and leaving the
    critical section, which is what the sidecar's lifecycle is defined against.
    """
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        original = godot.PROJECT_LOCK, godot.PROJECT_LOCK_OWNER
        godot.PROJECT_LOCK = root / godot.PROJECT_LOCK.name
        godot.PROJECT_LOCK_OWNER = root / godot.PROJECT_LOCK_OWNER.name
        try:
            expect(
                not godot.PROJECT_LOCK_OWNER.exists(),
                f"fixture did not start clean: {godot.PROJECT_LOCK_OWNER} already exists, "
                "so nothing below can distinguish writing from finding",
            )
            with godot.project_lock():
                record = json.loads(godot.PROJECT_LOCK_OWNER.read_text(encoding="utf-8"))
                expect(
                    record.get("pid") == os.getpid(),
                    f"the sidecar inside the critical section names pid "
                    f"{record.get('pid')!r} rather than the process holding the lock, so a "
                    "blocked agent would be sent to wait on someone else",
                )
                expect(
                    isinstance(record.get("since"), str),
                    f"the sidecar records no `since`: {record!r}. Without a start time a "
                    "blocked agent can see WHO but not HOW LONG, which is half the fix",
                )
            expect(
                not godot.PROJECT_LOCK_OWNER.exists(),
                f"the sidecar outlived the lock: {godot.PROJECT_LOCK_OWNER} is still there "
                "after release, so every future expiry names a holder who has already "
                "let go",
            )
            expect(
                godot.PROJECT_LOCK.exists(),
                f"{godot.PROJECT_LOCK} was removed by the critical section. The advisory "
                "lock IS the mutual exclusion; unlinking the file hands the next arriving "
                "process one nobody holds, and that is BL-0424",
            )
        finally:
            godot.PROJECT_LOCK, godot.PROJECT_LOCK_OWNER = original


# --- INC-0009: a committed script that starts the engine by path has NO ceiling. The two
# --- cases below are a PAIR on purpose, and the pair is the guard. One asserts the red
# --- path; the other asserts `tools/godot.py` itself is still exempt. A guard with no
# --- second half passes the first while flagging the only file that is allowed to name the
# --- binary, and a guard that fires on the real tree stops being read within a run.


#: INC-0009's six invocations, spelled as PowerShell — the exact one-liner an agent
#: composes to "see the error the tool swallowed".
_POWERSHELL_BYPASS = r"""
$g = (Get-Content .godot-bin).Trim()
& $g --headless --path game -s res://tests/_probe.gd
"""


def _bypass_findings(*pairs: tuple[str, str]) -> list[godot_bypass.Finding]:
    """Scan fixture files through the guard's own `scan_text`, keyed by path and text.

    `scan_text` rather than `scan`, on purpose: `scan` lists files through `git ls-files`,
    and building a temporary repository would make these cases depend on git being
    configured — so the first version of this suite "passed" a deleted git as a clean
    tree. What is actually under test is the RULE, and the rule reads text.
    """
    findings: list[godot_bypass.Finding] = []
    for path, text in pairs:
        if godot_bypass.exempt(path):
            continue
        findings.extend(godot_bypass.scan_text(path, text))
    return findings


@case("godot_bypass: a script that resolves .godot-bin and runs the binary FAILS")
def _power_shell_bypass_is_reported() -> None:
    """The red path: INC-0009's own mechanism, still refused.

    Both halves are asserted because the shape has two halves and a guard that only
    matched one would still catch the obvious case while letting a probe that hard-codes
    the config file's name — or a script that finds the binary on PATH — through.
    """
    findings = _bypass_findings(("scratchpad/probe.ps1", _POWERSHELL_BYPASS))
    rules = {finding.rule for finding in findings}
    expect(
        rules,
        "a PowerShell script that reads .godot-bin and launches the engine by path was "
        "reported clean. That is INC-0009's verbatim one-liner, and a run it starts has "
        "no --log-file redirect, no RAM_CEILING_BYTES, no wall-clock ceiling, no log-byte "
        "ceiling and no silence ceiling",
    )
    expect(
        "godot-bypass:config-path" in rules,
        f"the `.godot-bin` read was not reported, so a probe can still resolve the binary "
        f"through the config file the resolver owns: {sorted(rules)}",
    )
    expect(
        "godot-bypass:bare-invocation" in rules,
        f"the direct invocation was not reported, so a path invocation with no flag on "
        f"the same line would sail through: {sorted(rules)}",
    )
    for finding in findings:
        expect(
            finding.path == "scratchpad/probe.ps1" and finding.line > 0,
            f"the finding does not name a file and line, so it is not attributable and "
            f"cannot be found in a 19000-file tree: {finding!r}",
        )


@case("godot_bypass: a script that shells out to godot/godot4 directly FAILS")
def _bare_executable_invocations_are_reported() -> None:
    """The committed-script half of the task, one shape at a time.

    Each pair below is a spelling that has actually been used here or is the obvious
    next one, and none of them mentions `.godot-bin` — so a guard that only watched the
    config file would report all of these clean.
    """
    for path, text, rule in (
        (
            "scratchpad/probe.py",
            'subprocess.run(["godot", "--headless", "--path", "game"])\n',
            "godot-bypass:bare-invocation",
        ),
        (
            "scratchpad/import.py",
            'subprocess.Popen(["godot4", "--headless", "--import"])\n',
            "godot-bypass:bare-invocation",
        ),
        (
            "scratchpad/sweep.bat",
            "@echo off\r\nGodot_v4.7.2-stable_win64_console.exe --headless --path game\r\n",
            "godot-bypass:bare-invocation",
        ),
        (
            "scratchpad/which.py",
            'found = shutil.which("godot")\n',
            "godot-bypass:execution-context",
        ),
        (
            "scratchpad/env.sh",
            "GODOT_BIN=/opt/godot/godot ./suite.sh\n",
            "godot-bypass:env-resolve",
        ),
    ):
        rules = {finding.rule for finding in _bypass_findings((path, text))}
        expect(
            rule in rules,
            f"{path} was reported clean for {rule!r}. A script that starts the engine "
            f"outside tools/godot.py opts out of every ceiling at once, and a silent "
            f"allocating loop passes all of them because they measure output",
        )


@case("godot_bypass: tools/godot.py itself is EXEMPT, and a doc may NAME the rule")
def _resolver_and_naming_prose_are_not_findings() -> None:
    """The half that decides whether the guard above is usable at all.

    `tools/godot.py` reads `.godot-bin`, reads `GODOT_BIN` and searches PATH for
    `godot`/`godot4` — it trips all four rules and is exempt by exact path. Flagging it
    would make `tools check` permanently red over the file that is the fix.

    The prose below is taken from the repository's own committed documentation: AGENTS.md
    and `docs/handoff-foundation-gaps.md` both NAME the resolver and its sources while
    forbidding the bypass. A doc that says so must be silent; a doc that instead ships a
    runnable command line must not be.
    """
    resolver = godot_bypass.exempt(godot_bypass.RESOLVER)
    expect(
        resolver is not None,
        "tools/godot.py is no longer exempt, so the guard fires on the only file in the "
        "repository that is allowed to read .godot-bin and GODOT_BIN. A permanently-red "
        "gate is a gate people learn to ignore",
    )
    findings = _bypass_findings((godot_bypass.RESOLVER, godot.GODOT_BYPASS_EXEMPT_PROBE))
    expect(
        not findings,
        "tools/godot.py was flagged despite its exemption; findings were "
        f"{[f.describe() for f in findings]}",
    )

    for name, text in (
        (
            "AGENTS.md",
            "**Never invoke the Godot binary directly:** go through `tools/godot.py` "
            "(`tools test`, `run`, `ui`, `export`), which passes `--log-file "
            "build/godot.log` and enforces a 900 s ceiling. `tools/godot.py` resolves it "
            "from `GODOT_BIN`, else the gitignored `.godot-bin` file, else `PATH`.\n",
        ),
        (
            "docs/handoff-foundation-gaps.md",
            "`tools/godot.py` does not export anything, and it does not log. It resolves "
            "Godot via `GODOT_BIN`, the gitignored `.godot-bin`, or `PATH`. None is "
            "exported, so none lands in the build directory.\n",
        ),
    ):
        findings = _bypass_findings((name, text))
        expect(
            not findings,
            f"{name} was flagged for NAMING the rule, which is what the documentation is "
            f"supposed to do: {[f.describe() for f in findings]}. Refusing prose would "
            "force this project to delete the rule it keeps re-learning",
        )

    # And the other side of the same distinction, asserted on the real text: a doc that
    # HANDS the next agent a runnable direct invocation is a finding, whatever its tone.
    findings = _bypass_findings(
        (
            "docs/quickstart.md",
            "To run the suite:\n\n    godot --headless --path game --import\n\n",
        )
    )
    expect(
        any(finding.rule == "godot-bypass:bare-invocation" for finding in findings),
        "a document shipping a runnable `godot --headless` line was accepted. Prose that "
        "names the rule is allowed; prose that hands over the bypass is the same hazard "
        "in a different file extension",
    )


# --- BL-0635: `boot` was the last gate with no case proving it goes RED.
# ---
# --- `tools boot` is the only check that can see a fault which fires once the engine
# --- actually delivers frames, so a loosened `boot` is the most expensive kind of quiet
# --- lie in the gate. It went uncovered because every earlier attempt asserted that a
# --- BROKEN world is rejected, and `boot` is red on the shipped tree for a content
# --- reason — so such an assertion would have passed for the wrong reason and proved
# --- nothing. These two cases break the two halves against a fixture world that reports
# --- success and does nothing, which is the shape no shipped tree has and therefore the
# --- only fixture where a red verdict can only mean the guard works.


def _boot_verdict(probe_stdout: str, engine_exit: int = 0) -> int:
    """`boot.run`'s exit code against a fixture project, with the engine replaced.

    Three things the verdict reads are redirected, and all three matter.
    `boot.GAME_DIR` is what `main_scene()` opens; `common.GAME_DIR` is what
    `game_exists()` checks, and it is a SEPARATE binding — patching only the first
    leaves the fixture passing because the real project happens to exist, which is the
    wrong-tree bug `gate_reach` already paid for. `run_godot` is the only thing that
    starts the engine.

    The stub answers by ARGUMENT, not by call order: `--quit-after` is phase one and
    `-s` is phase two. Deciding that way means the fixture cannot accidentally encode
    "the engine was launched" as the thing under test.
    """
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        game = root / "game"
        write(
            game / "project.godot",
            '[application]\n\nrun/main_scene="res://scenes/main.tscn"\n',
        )
        original_dir = boot.GAME_DIR
        original_common = common.GAME_DIR
        original_run = boot.godot.run_godot
        boot.GAME_DIR = game
        common.GAME_DIR = game

        def _stub(argv, **_kwargs):
            probe = any(arg.startswith("-s") for arg in argv)
            return subprocess.CompletedProcess(
                argv,
                engine_exit,
                stdout=(probe_stdout if probe else ""),
                stderr="",
            )

        boot.godot.run_godot = _stub
        try:
            return boot.run(argparse.Namespace(frames=boot.BOOT_FRAMES))
        finally:
            boot.GAME_DIR = original_dir
            common.GAME_DIR = original_common
            boot.godot.run_godot = original_run


@case("boot: a probe that reports an empty shell FAILS the gate")
def _boot_rejects_an_empty_shell() -> None:
    """The half that is not about crashing: surviving is not arriving.

    `ItemWorkbenchApp._ready` returns quietly when it cannot find `%ScreenStack`, and a
    blank window still exits 0 — the exact failure BL-0359's neighbourhood looked like.
    A probe that says `ok: false` must therefore make the gate exit non-zero, or the one
    check that can see a boot come up empty would report success on an empty boot.
    """
    code = _boot_verdict('BOOTJSON {"ok": false, "why": "the shell mounted no screen"}\n')
    expect(
        code != 0,
        "a probe reporting an empty shell still exited 0, so `tools boot` would report a "
        "game that launches to a blank window as healthy",
    )


@case("boot: a probe that prints NO report at all FAILS the gate")
def _boot_rejects_a_silent_probe() -> None:
    """The other direction: silence is not a pass.

    A probe that crashed before `_emit`, or whose line lost its prefix, produces no
    `BOOTJSON`. Reading that as "no complaints" is the failure mode where a gate goes
    green because the thing it measures stopped running — the guard reports `ok` on a
    tree it should have rejected, which is the ADR 0066 quiet lie.
    """
    code = _boot_verdict("")
    expect(
        code != 0,
        "a probe that printed no BOOTJSON line still exited 0, so a probe that died before "
        "reporting would read as a healthy boot",
    )


# --- INC-0023: two live sessions claiming one path. ---
# --- The collision is a DISPATCH, not an edit, so the GDScript suite cannot see it and the
# --- ledger has to carry it. Two sessions claimed `game/src/modules/loot/loot_drop_row.gd`
# --- at once because an empty tool result was misread as a failed launch; nothing was
# --- written, but the window is the write-write collision INC-0003 exists to prevent.
# --- Three cases, and the pair below is the one that matters: the same three-session
# --- ledger is RED when two of them overlap and GREEN when the third is merely stale. A
# --- guard that cannot tell those two apart is testing nothing.


def _claim_verdict(ledger: Path) -> int:
    """`claim_guard.run`'s exit code for `check` against a fixture ledger.

    The verdict path is `run`, not the internals, so what is asserted is what CI sees. The
    ledger is passed through `--ledger` rather than by patching `CLAIMS_PATH`, because that
    is the seam the CLI actually uses and patching the global cannot catch a `run` that
    forgets to forward it — which is exactly what the first version of this case did, and it
    measured the repository's own `docs/claims.jsonl` four times while asserting a fixture.
    """
    return claim_guard.run(
        argparse.Namespace(claim_action="check", ledger=str(ledger), fail_on="error")
    )


def _stamp(hours_ago: float) -> str:
    return (datetime.now(UTC) - timedelta(hours=hours_ago)).isoformat()


def _loot_ledger(root: Path, *, second_session_hours_ago: float) -> Path:
    """INC-0023's three-session ledger, with ONE number deciding whether it is red.

    Below the staleness ceiling the second session is LIVE and holds a file inside the first
    session's directory: a collision. Above the ceiling the same session is STALE and holds
    the same path, which is a crashed agent rather than a second owner. Identical sessions,
    identical paths, identical bytes — only the heartbeat differs — so any verdict
    difference between the two is the guard separating "two live owners" from "one owner and
    a dead one", which is the only distinction the gate may make (INC-0017: a question with
    a permanently-yes answer is not a gate).

    The third session is the neighbour `loot2`, on its own sibling module. It must never
    overlap: `game/src/modules/loot` is a byte prefix of `game/src/modules/loot2`, so a
    `str.startswith` comparison reports an unrelated module as a collision and makes every
    pair of sibling modules unusable.
    """
    return write(
        root / "claims.jsonl",
        "\n".join(
            json.dumps(entry)
            for entry in (
                {
                    "session": "loot-A",
                    "owner": "coordinator",
                    "paths": ["game/src/modules/loot"],
                    "heartbeat": _stamp(0.1),
                },
                {
                    "session": "loot-B",
                    "owner": "coordinator",
                    "paths": ["game/src/modules/loot/loot_drop_row.gd"],
                    "heartbeat": _stamp(second_session_hours_ago),
                },
                {
                    "session": "loot2-A",
                    "owner": "coordinator",
                    "paths": ["game/src/modules/loot2/loot_state.gd"],
                    "heartbeat": _stamp(0.2),
                },
            )
        )
        + "\n",
    )


@case("claim_guard: TWO live sessions over one path FAILS the gate")
def _overlapping_live_claims_are_red() -> None:
    """The red path: INC-0023's own ledger, still refused.

    Session A holds the module DIRECTORY and session B holds one FILE inside it, which is
    the shape a coordinator produces by re-sending a prompt whose path list was spelled the
    second time as individual files. Asserting the containment direction is the point: a
    guard that only compared paths for equality would report this clean.
    """
    with tempfile.TemporaryDirectory() as raw:
        ledger = _loot_ledger(Path(raw), second_session_hours_ago=0.3)
        code = _claim_verdict(ledger)
        found = claim_guard.conflicts(claim_guard.read_claims(ledger))

    expect(
        code != 0,
        "two live sessions holding game/src/modules/loot and a file inside it exited 0. That "
        "is INC-0023 verbatim: the dispatch returned an empty body, the coordinator resent "
        "the identical prompt, and two agents owned the same two files until one was stood "
        "down. A gate that reports ok there is the ADR 0066 quiet lie with an exit code "
        "attached",
    )
    expect(
        len(found) == 1,
        f"the overlapping pair was not reported as one conflict; got {found}. The whole guard "
        "is this comparison, and `loot-B` must be named against `loot-A` so somebody can "
        "stand one of them down",
    )
    expect(
        found and {"loot-A", "loot-B"} == {found[0].left.session, found[0].right.session},
        f"the conflict named {found and found[0].describe()!r} instead of the two colliding "
        "sessions. `loot2-A` holds a sibling module and must not appear in the pair",
    )
    expect(
        found and "game/src/modules/loot/loot_drop_row.gd" in found[0].shared,
        f"the finding named {found and found[0].shared!r} rather than the file both sessions "
        "are fighting over, so the reader has to re-derive the collision",
    )
    expect(
        found and "game/src/modules/loot" in found[0].shared,
        f"the finding named only one side of the overlap ({found and found[0].shared!r}). A "
        "directory claim and the file claimed inside it are one collision written two ways, "
        "and the reader standing one session down needs to see both spellings",
    )


@case("claim_guard: two DISJOINT claims plus one STALE claim PASS the gate")
def _disjoint_and_stale_claims_are_green() -> None:
    """The green side of the same ledger, and the INC-0017 half.

    Two sessions on unrelated modules are the normal state of a shared tree with ~20 live
    agents; failing on them would make every dispatch a collision. The second claim here is
    past `STALE_AFTER` and holds a path the first session ALREADY held — so the staleness
    rule is the only thing standing between this ledger and red. A stale claim is REPORTED
    and not counted: a session that died without releasing its paths must not pin this gate
    red forever, because a gate that cannot go green is a gate the first agent to meet it
    downgrades or deletes.
    """
    with tempfile.TemporaryDirectory() as raw:
        ledger = _loot_ledger(
            Path(raw),
            second_session_hours_ago=claim_guard.STALE_AFTER.total_seconds() / 3600 + 1,
        )
        code = _claim_verdict(ledger)
        live, stale = claim_guard.split_stale(claim_guard.read_claims(ledger))

    expect(
        code == 0,
        "a ledger whose only overlap involves a STALE claim still exited non-zero. A claim "
        "nobody can clear pins the gate red forever: that is INC-0017, where my own "
        "mutation_history guard asked whether a probe was EVER committed and made tools check "
        "unsatisfiable, and the fix was to gate on current state instead",
    )
    expect(
        [claim.session for claim in stale] == ["loot-B"],
        f"the over-age claim was not reported stale (stale={stale}, live={live}); it is the "
        "crashed agent, not a second owner, and reporting it as a conflict sends a reader to "
        "stand down a session that stopped answering hours ago",
    )
    expect(
        sorted(claim.session for claim in live) == ["loot-A", "loot2-A"],
        f"the two live claims were not the survivors of split_stale: live={live}",
    )
    expect(
        not claim_guard.conflicts(live),
        "the two surviving live claims overlap, so a stale claim was masking a real collision "
        "instead of being the only thing keeping the gate green",
    )
    expect(
        not claim_guard.overlaps("game/src/modules/loot", "game/src/modules/loot2"),
        "a byte prefix was accepted as an overlap: `loot2` is a DIFFERENT module, and a naive "
        "startswith here makes every pair of sibling modules a write-write collision",
    )
    expect(
        claim_guard.overlaps("game/src/modules/loot", "game/src/modules/loot/loot_drop_row.gd"),
        "a directory claim no longer covers a file claimed inside it, which is the half of "
        "the comparison INC-0023 actually turned on",
    )


@case("claim_guard: a claim that cannot be read FAISES rather than reporting a clean ledger")
def _unreadable_ledger_is_not_clean() -> None:
    """The INC-0013 half, in the one place this guard can still be too generous.

    Every function here returns an empty result when something goes wrong, so an unreadable
    ledger is indistinguishable from an empty one — and an empty one is green. A torn write
    on a shared tree, or a heartbeat someone typed as a date, would therefore read as "no
    two sessions claim the same path", which is the guard reporting `ok` because it looked
    at nothing.

    Only the MESSAGE changes with the shape; the exit code does not. `ToolError` is turned
    into `fail(...)` and exit 1 by `tools/__main__.main`, which is the non-zero CI depends on
    and the same wiring `incident._validate` and `deferred._validate` already rely on.

    The three fixtures are read INSIDE the temporary directory: read one after the block
    closes and the name resolves to nothing, which this case asserted as a clean ledger on
    the first run — a guard test that passes because its fixture vanished.
    """
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        torn = write(root / "torn.jsonl", '{"session": "a", "paths": ["x"], "heartbeat": ')
        dateless = write(
            root / "dateless.jsonl",
            json.dumps({"session": "a", "paths": ["game/src"], "heartbeat": "2026-10-04"}) + "\n",
        )
        naked = write(root / "naked.jsonl", json.dumps({"session": "a", "paths": []}) + "\n")
        hollow = write(
            root / "hollow.jsonl",
            json.dumps({"session": "a", "paths": "game/src/modules/loot", "heartbeat": _stamp(0.1)})
            + "\n",
        )

        for name, ledger, shape in (
            ("a torn write", torn, "invalid JSON"),
            ("a heartbeat with no time", dateless, "not ISO 8601"),
            # A line with NO `paths` key is caught by the missing-field check, and so is an
            # EMPTY list — both falsy, both reported as "missing", which is the same defect to
            # a reader. A `paths` value that is present but not a list is the input that
            # reaches the type check, so each of the three pins a different line of the parse.
            ("a claim with no paths key", naked, "missing ['paths', 'heartbeat']"),
            ("a claim whose paths is a bare string", hollow, "is a list"),
        ):
            try:
                _claim_verdict(ledger)
            except ToolError as exc:
                expect(
                    shape in str(exc),
                    f"{name} was refused for the wrong reason: {exc}. The message has to say "
                    "what is wrong with the line, not just that something is",
                )
            else:
                expect(
                    False,
                    f"{name} was reported as a clean ledger. A claim the guard cannot parse is "
                    "a claim it cannot see, and seeing no claims is green",
                )


@case("claim_guard: claiming an already-held path FAILS, and releasing makes it clean")
def _claim_then_release_is_the_repair() -> None:
    """The round trip, which is the only repair an operator has.

    A finding nobody can clear is a gate that eventually gets deleted. So the second
    dispatch has to have somewhere to go: `claim` records and reports the overlap,
    `release` takes the line back out, and `check` goes green on the SAME ledger. Without
    this, the honest response to a red gate is editing JSON by hand in a file twenty agents
    are writing at once.
    """
    with tempfile.TemporaryDirectory() as raw:
        ledger = Path(raw) / "claims.jsonl"
        first = argparse.Namespace(
            claim_action="claim",
            session="loot-A",
            paths="game/src/modules/loot",
            ledger=str(ledger),
        )
        expect(
            claim_guard.run(first) == 0,
            "the first claim of a path was refused. Nothing holds it, so this is a false red, "
            "and a false red on the first dispatch teaches every agent to ignore the guard",
        )
        bump = argparse.Namespace(
            claim_action="claim",
            session="loot-A",
            paths="game/src/modules/loot/loot_drop_row.gd",
            ledger=str(ledger),
        )
        expect(
            claim_guard.run(bump) == 0,
            "one session naming its own directory AND a file inside it was refused. That is "
            "one holder being precise about its own work, not two holders colliding",
        )
        steal = argparse.Namespace(
            claim_action="claim",
            session="loot-B",
            paths="game/src/modules/loot/loot_drop_row.gd",
            ledger=str(ledger),
        )
        expect(
            claim_guard.run(steal) != 0,
            "a second session claimed an already live-held path and was told nothing. The gate "
            "catches the same overlap later, but the ledger recording it silently is what made "
            "the coordinator's second dispatch invisible in the first place",
        )
        expect(
            _claim_verdict(ledger) != 0,
            "the ledger holds an overlap and `check` exited 0, so the collision INC-0023 "
            "describes would ship through the gate",
        )

        drop = argparse.Namespace(
            claim_action="release",
            session="loot-B",
            paths="",
            ledger=str(ledger),
        )
        claim_guard.run(drop)
        expect(
            _claim_verdict(ledger) == 0,
            "standing the second session down and releasing its paths did not make the gate "
            "green. That is the only repair an operator has, and a gate whose repair is "
            "impossible gets deleted on its first trip (INC-0017)",
        )
        expect(
            "loot-A" in ledger.read_text(encoding="utf-8"),
            "releasing one session took the OTHER session's live claim with it. On a shared "
            "tree that hands the paths back while the real owner is still working on them",
        )
