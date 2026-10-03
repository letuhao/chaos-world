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

import subprocess
import tempfile
from pathlib import Path

from . import gate_reach, map_theme, mutation_history, unique_characters
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

        expect(
            not _carried_in(root),
            "a machine-local recovery ref gated the build, so the verdict depends on invisible "
            "local state and differs between this machine and every clone",
        )


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
