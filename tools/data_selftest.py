"""Red-path self-tests for the `data audit` legs that gate ADR 0196 and ADR 0190.

Separate from `tools/data.py` because a validator is shipped code and a test of it
is not: `data.py` is imported by `tools check` on every run, and importing it must
not register test cases. `tools/selftest_cases.py` imports this module for the
same reason it imports `tools/acquisition/selftest_case.py` — one line, so the
registration stays greppable (INC-0016).

## Every fixture is a temp tree, and every case asserts BOTH directions

Two properties are independent and only the pair is worth anything: a check that
fires on everything satisfies every red case, and a check that fires on nothing
satisfies every green one. So each case below builds a corpus that differs from a
correct one by exactly the property under test and asserts that the difference is
what moves the verdict.

The vocabulary and the catalogs are the REAL ones — `FateDef.TAGS` out of
`game/src/modules/destiny/fate_def.gd`, the fate ids out of the shipped
`game/data/destiny/fates/`, the race ids out of the shipped `game/data/races/` — and
the fixture writes the FATES AND RACES too, beside the defect. A fixture that
supplied its own vocabulary would let a gate that stopped reading `FateDef.TAGS`
pass every case here, which is the one bug this file exists to catch.
"""

from __future__ import annotations

import contextlib
import io
import tempfile
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path

from . import data as data_tool
from .selftest import case, expect, write

# A `.tres` a reader can mistake for nothing. `ExtResource` in particular is the
# shape a composite gate shares — an event's `trigger` and a destiny's
# `requires_fates` are BOTH sub-resources — so a walk that only looks at the main
# resource finds no gate at all and passes for the wrong reason.
_FIXTURE_PROSE = "A fixture gate. Nothing here is real content."


def _array(values: tuple[str, ...]) -> str:
    return "Array[StringName]([" + ", ".join(f'&"{value}"' for value in values) + "])"


def _resource(script_class: str, resource_id: str, body: str) -> str:
    return (
        f'[gd_resource type="Resource" script_class="{script_class}" format=3]\n\n'
        "[resource]\n"
        f'id = &"{resource_id}"\n'
        f"{body}"
    )


def _fate(fate_id: str, tags: tuple[str, ...] = ()) -> str:
    return _resource(
        "FateDef",
        fate_id,
        f'display_name = "Fixture"\ncategory = &"fixture"\ntags = {_array(tags)}\n',
    )


def _gate(verb: str, gate_id: str) -> str:
    return f'{{"verb": &"{verb}", "id": &"{gate_id}"}}'


def _gate_with_requirement(verb: str, requirement: str) -> str:
    """A `{verb: X}` row that carries a NESTED requirement rather than an `id`.

    A destiny authors `requires_fates = Array[Dictionary]([...])`, which is how
    `tagged` is reached in practice; an event authors its `trigger` the same way.
    """
    return f'{{"verb": &"{verb}", "of": [{requirement}]}}'


def _arrival(arrival_id: str, marks: tuple[str, ...], race_id: str) -> str:
    return _resource(
        "SoulDef",
        arrival_id,
        f'race_id = &"{race_id}"\norder = 0\nmarks = {_array(marks)}\n',
    )


def _event(event_id: str, trigger: str) -> str:
    """One event whose `trigger` is a composite, exactly as `.tres` authors it."""
    body = (
        f'[sub_resource type="Resource" id="trigger"]\n'
        f"trigger = {trigger}\n\n"
        "[resource]\n"
        f'id = &"{event_id}"\n'
        'kind = &"fixture"\n'
        f"{_FIXTURE_PROSE}\n"
    )
    return f'[gd_resource type="Resource" script_class="EventDef" format=3]\n\n{body}'


def _destiny(destiny_id: str, requirement: str) -> str:
    return _resource(
        "DestinyDef",
        destiny_id,
        f"requires_fates = Array[Dictionary]([{requirement}])\n",
    )


def _destiny_with_aliases(destiny_id: str, aliases: tuple[str, ...]) -> str:
    """A `DestinyDef` that DECLARES `gate_aliases`, so the alias is authored here.

    The alias feature is ADR 0113's whole reason to exist — story may name a
    destiny before the `.tres` for it ships — so a fixture asserting that an alias
    is a legal gate id has to author the alias on a REAL record. A fixture that
    passed an alias no definition claims would be testing "an id that resolves
    against nothing", which is the bug, not the feature.
    """
    return _resource(
        "DestinyDef",
        destiny_id,
        f"gate_aliases = {_array(aliases)}\nrequires_fates = Array[Dictionary]([])\n",
    )


def _race(race_id: str) -> str:
    return _resource(
        "RaceDef", race_id, 'display_name = "Fixture race"\ntags = Array[StringName]([])\n'
    )


# A coined lineage, and the name ADR 0196 itself uses for one. `defensive` is the
# engine-shaped token `FateDef.TAGS` explicitly excludes, so it is out of
# vocabulary by the shipped source's own account rather than by this file's.
COINED_TAG = "defensive"


def _write_tags(root: Path, tags: tuple[str, ...]) -> None:
    """Point `FateDef.TAGS` at a fixture with exactly these members."""
    listing = ",\n".join(f'\t&"{tag}"' for tag in tags)
    write(
        root / "fate_def.gd",
        "class_name FateDef\nextends Resource\n\n"
        f"const TAGS: Array[StringName] = [\n{listing},\n]\n\n"
        "@export var tags: Array[StringName] = []\n",
    )


@contextmanager
def _fixture(tags: tuple[str, ...], files: dict[str, str]) -> Iterator[tuple[Path, data_tool]]:
    """Run the gates over a corpus this module owns, with a fixture vocabulary.

    The vocabulary is redirected rather than shipped so a case can prove the
    converse — that removing a member turns the SAME fate red — and so nothing here
    depends on how many tags the tree happens to declare today. Nothing about the
    fates or the races is invented: the defect under test is a dangling reference,
    and a fixture whose catalog were invented alongside it would make every
    reference resolve. Each case writes the fates and races it needs, and asserts
    that the reader it exercises actually loaded them.
    """
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw)
        module = root / "data"
        _write_tags(root, tags)
        for relative, text in files.items():
            write(module / relative, text)
        original = data_tool.FATE_DEF
        data_tool.FATE_DEF = root / "fate_def.gd"
        try:
            yield module, data_tool
        finally:
            data_tool.FATE_DEF = original


def _records(root: Path) -> dict:
    return data_tool._load(root)[0]  # noqa: SLF001


def _shipped_fate_ids() -> set[str]:
    return set(_records(data_tool.DATA_ROOT).get("fate", {}))


def _shipped_race_ids() -> set[str]:
    return data_tool._authored_race_ids()


def _authors(records: dict, root: Path, tool: data_tool) -> None:
    """Assert the fixture wrote the catalogs the gate resolves against.

    Without this, a fixture that named an id it never authored would fail for a
    SECOND reason, the first assertion would never run, and the case would read as
    a pass for the wrong cause. `race_id` resolves against `root` while a mark
    resolves against the fate records the loader built, so both are checked
    separately — they are two different readers, and one of them reading the wrong
    tree is exactly the bug class these cases exist for.
    """
    authored = set(records.get("fate", {}))
    races = tool._authored_race_ids(root)  # noqa: SLF001
    for arrival in records.get("soul", {}).values():
        where = arrival["path"]
        for mark in arrival["arrays"].get("marks", []):
            if mark.startswith("no_such_"):
                expect(
                    mark not in authored,
                    f"{where}: the fixture's own dangling mark {mark!r} IS authored, so it "
                    "cannot be the dangling half of this case",
                )
            else:
                expect(
                    mark in authored,
                    f"{where}: the fixture's resolvable mark {mark!r} is not in the fate "
                    "catalog the gate reads, so the clean half of this case proves nothing",
                )
        race_id = arrival["scalars"].get("race_id", "")
        if race_id.startswith("no_such_"):
            expect(
                race_id not in races,
                f"{where}: the fixture's own dangling race {race_id!r} IS authored, so it "
                "cannot be the dangling half of this case",
            )
        else:
            expect(
                race_id in races,
                f"{where}: the fixture's resolvable race {race_id!r} is not in the race "
                f"catalog the gate reads ({sorted(races)!r}), so the clean half proves nothing",
            )


def _verdict(root: Path) -> tuple[int, str]:
    """`(returncode, output)` of the real `data audit` entry point over `root`.

    Asserting on the FUNCTION is not enough: a leg wired into `_destiny_findings`
    and never reached from `_audit_command` would satisfy every other case here and
    still ship a gate nobody runs. This is the path `tools check` takes, so the
    number that decides the build is the number asserted.
    """
    buffer = io.StringIO()
    with contextlib.redirect_stdout(buffer), contextlib.redirect_stderr(buffer):
        code = data_tool._audit_command(root)  # noqa: SLF001
    return code, buffer.getvalue()


# --- Gate 1: the closed fate-tag vocabulary (ADR 0196) ------------------------


@case("data audit: a fate carrying a coined tag FAILS, and carrying none is clean")
def _coined_fate_tag_fails_and_a_clean_one_passes() -> None:
    """The red path for the seventh verb's vocabulary, and its counterweight.

    Both fixtures differ by exactly one array. A check that reported every fate, or
    none, satisfies the first and fails the second.
    """
    good_tag = "oath"
    files = {
        "destiny/fates/ok_fate.tres": _fate("ok_fate", (good_tag,)),
        "destiny/fates/coined_fate.tres": _fate("coined_fate", (COINED_TAG,)),
    }
    with _fixture((good_tag,), files) as (root, tool):
        expect(
            tool._fate_tags() == {good_tag},  # noqa: SLF001
            f"the fixture vocabulary did not read back, so this case proves nothing: "
            f"{tool._fate_tags()!r}",  # noqa: SLF001
        )
        findings = tool._tag_findings(_records(root)["fate"])  # noqa: SLF001
        coined = [f for f in findings if COINED_TAG in f]
        expect(
            len(coined) == 1,
            f"a fate carrying the coined tag {COINED_TAG!r} produced {len(coined)} findings "
            f"({findings!r}); the gate must fail exactly the coined one, so a fixture with one "
            "bad array and one good one tells the two readings apart",
        )
        expect(
            "ok_fate" not in "\n".join(coined),
            f"the finding about the coined tag named the wrong fate: {coined}",
        )
        expect(
            not [f for f in findings if "ok_fate" in f],
            f"a fate carrying only the vocabulary member {good_tag!r} was reported: {findings!r}. "
            "A gate that refused the closed vocabulary itself would be red for a correct tree",
        )


@case("data audit: a member REMOVED from the vocabulary turns the fate red")
def _removing_a_vocabulary_member_turns_the_fate_red() -> None:
    """The half that proves the vocabulary is READ rather than restated.

    A guard holding its own list of legal tags passes the case above for the wrong
    reason: it would accept `oath` because `oath` is in the list, with nothing
    connecting that list to `FateDef.TAGS`. Same fate, same `.tres`, vocabulary
    fixture differing by one member — and the verdict moves. That is the only
    evidence that the shipped declaration is what decides.
    """
    fate = {"destiny/fates/one_fate.tres": _fate("one_fate", ("oath", "duel"))}
    verdicts: dict[str, list[str]] = {}
    for tags in (("oath", "duel"), ("oath",)):
        with _fixture(tags, fate) as (root, tool):
            verdicts[",".join(tags)] = tool._tag_findings(_records(root)["fate"])  # noqa: SLF001
    expect(
        not verdicts["oath,duel"],
        f"a fate carrying two vocabulary members was reported: {verdicts['oath,duel']!r}",
    )
    expect(
        len(verdicts["oath"]) == 1 and "duel" in verdicts["oath"][0],
        f"removing `duel` from the vocabulary did not turn the fate carrying it red: "
        f"{verdicts['oath']!r}. Either the gate holds its own copy of the tags, or it reads "
        "a vocabulary fixture it was not pointed at — and ADR 0196 makes adding a tag a "
        "change to the closed vocabulary, not an edit in the gate",
    )


@case("data audit: an UNREADABLE vocabulary refuses rather than passing every tag")
def _unreadable_vocabulary_is_not_vacuous() -> None:
    """The anti-vacuity term, and the failure it is aimed at.

    An absent `const TAGS` reads as "no tag is legal" under the obvious
    implementation, which fails every authored fate on a correct tree; the other
    obvious implementation returns the empty set and passes every one, which is a
    gate that reports ok on a tree it never checked. Either way a moved or renamed
    `fate_def.gd` silently changes what the audit means. So this asserts the
    fixture really is unreadable AND that it produces a finding.
    """
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw) / "data"
        write(root / "destiny/fates/one_fate.tres", _fate("one_fate", ("oath",)))
        original = data_tool.FATE_DEF
        data_tool.FATE_DEF = Path(raw) / "no_such_fate_def.gd"
        try:
            expect(
                data_tool._fate_tags() is None,  # noqa: SLF001
                "a missing FateDef read as an empty vocabulary rather than as 'unknown'",
            )
            findings = data_tool._tag_findings(_records(root)["fate"])  # noqa: SLF001
            expect(
                len(findings) == 1 and "could not be read" in findings[0],
                f"an unreadable FateDef.TAGS produced {findings!r}; the gate must REFUSE, "
                "because the alternative is a build that passes every authored tag while "
                "checking nothing (INC-0016)",
            )
        finally:
            data_tool.FATE_DEF = original


@case("data audit: a `tagged` gate naming a coined tag FAILS the whole audit")
def _coined_tag_gate_is_named_by_the_audit() -> None:
    """The red path end to end, through the command `tools check` runs.

    `data audit` walks the WHOLE content tree for gate rows, because a gate is
    authored on quests, events and destinies alike and no one catalog exposes them
    all. A scan limited to `game/data/destiny/` finds nothing here and returns a
    clean tree for the wrong reason, so the fixture authors the gate on an EVENT —
    outside the destiny directory — and the returning exit code is the proof.
    """
    good_tag = "oath"
    files = {
        "destiny/fates/ok_fate.tres": _fate("ok_fate", (good_tag,)),
        "races/ok_race.tres": _race("ok_race"),
        "event/events/fixture_event.tres": _event(
            "fixture_event", _gate_with_requirement("tagged", _gate("tagged", COINED_TAG))
        ),
    }
    with _fixture((good_tag,), files) as (root, tool):
        authored = tool._authored_tagged_gates(root)  # noqa: SLF001
        expect(
            len(authored) == 1 and authored[0][1] == COINED_TAG,
            f"the whole-tree walk missed the authored gate, or reported it under the wrong "
            f"name: {authored!r}. The walk is the census every `tagged` verdict rests on",
        )
        code, output = _verdict(root)
        expect(
            code == 1,
            f"`data audit` exited {code} over a `tagged` gate naming the coined tag "
            f"{COINED_TAG!r}. Output:\n{output}",
        )
        expect(
            COINED_TAG in output,
            (
                "the failing audit never named the coined tag, so an author cannot act on it:"
                f"\n{output}"
            ),
        )


@case("data audit: a `tagged` gate naming a VOCABULARY tag is clean")
def _in_vocabulary_tag_gate_passes() -> None:
    """The counterweight for the case above, and the half that can go stale.

    Same fixture with one string changed. A whole-tree walk that reported every
    `tagged` row would satisfy the red case and be useless — and the walk is
    shared with the counter census, so a drift in one is a drift in both.
    """
    good_tag = "oath"
    files = {
        "destiny/fates/ok_fate.tres": _fate("ok_fate", (good_tag,)),
        "races/ok_race.tres": _race("ok_race"),
        "event/events/fixture_event.tres": _event(
            "fixture_event", _gate_with_requirement("tagged", _gate("tagged", good_tag))
        ),
    }
    with _fixture((good_tag,), files) as (root, tool):
        gaps = tool._tag_gate_findings(root)  # noqa: SLF001
        expect(not gaps, f"a gate naming a vocabulary member was reported: {gaps!r}")
        code, output = _verdict(root)
        expect(
            code == 0,
            f"`data audit` exited {code} over a correct tree. The whole-fixture verdict, not "
            f"just this leg, so a leg that leaks into a neighbouring one shows up:\n{output}",
        )


@case("data audit: a `tagged` row inside `none_of` is a NOTE, never a failure")
def _tagged_under_none_of_is_a_note_only() -> None:
    """The severity split, asserted from both sides.

    `none_of` is satisfied while none of its children hold, and fates are never
    removed (ADR 0065) while no gate consumes a tag — so the row is true for a
    player carrying no fate of that lineage and stays true for one carrying all of
    them. That is a legitimate composition and only a NOTE: failing it would be red
    for a tree behaving correctly, which is how `_counter_findings` keeps the
    unwired `counter` GATE a failure and the unwired `FateDef.counters`
    DECLARATION a warning.
    """
    good_tag = "oath"
    files = {
        "destiny/fates/ok_fate.tres": _fate("ok_fate", (good_tag,)),
        "races/ok_race.tres": _race("ok_race"),
        "event/events/door.tres": _event(
            "door", _gate_with_requirement("none_of", _gate("tagged", good_tag))
        ),
    }
    with _fixture((good_tag,), files) as (root, tool):
        doors = tool._none_of_tagged_gates(root)  # noqa: SLF001
        expect(
            len(doors) == 1 and doors[0][1] == good_tag,
            f"the composite walk did not see the nested `tagged` row: {doors!r}. A gate that "
            "cannot see the door cannot report it, and the note is the only thing an author "
            "gets to see it at all",
        )
        expect(
            not tool._tag_gate_findings(root),  # noqa: SLF001
            "the nested row was also reported as a vocabulary failure; a `tagged` row inside "
            "`none_of` is in the SAME closed vocabulary as one outside it",
        )
        notes = tool._tag_notes(root)  # noqa: SLF001
        expect(
            len(notes) == 1 and good_tag in notes[0] and "door" in notes[0],
            f"the one-way door was not reported as a note naming it: {notes!r}. The note is "
            "the whole deliverable of this leg",
        )
        code, output = _verdict(root)
        expect(
            code == 0,
            f"`data audit` exited {code} over a `none_of` composite holding one `tagged` row. "
            f"A note must not fail the build:\n{output}",
        )
        expect(
            "one-way door" in output,
            f"the door was not surfaced to the author at all:\n{output}",
        )


@case("data audit: a `tagged` row in an `all_of` composite is NOT a one-way door")
def _tagged_under_all_of_is_not_a_door() -> None:
    """The half that tells the composite walk from a blanket `tagged` scan.

    `all_of:[{tagged}]` is satisfied while a fate of that lineage IS held, and
    holding one is exactly what opens it — the opposite of the `none_of` case. A
    note that fired on both would tell every author their `all_of` gate is a door
    that can never open, which is wrong and would be a reason to delete the note.
    """
    good_tag = "oath"
    files = {
        "destiny/fates/ok_fate.tres": _fate("ok_fate", (good_tag,)),
        "races/ok_race.tres": _race("ok_race"),
        "event/events/opener.tres": _event(
            "opener", _gate_with_requirement("all_of", _gate("tagged", good_tag))
        ),
    }
    with _fixture((good_tag,), files) as (root, tool):
        expect(
            not tool._none_of_tagged_gates(root),  # noqa: SLF001
            "an `all_of` composite was reported as a one-way door. `all_of:[{tagged}]` OPENS "
            "when a fate of that lineage is held, so calling it a door that can never open "
            "would be a false claim about shipped content",
        )
        expect(
            not tool._tag_notes(root),  # noqa: SLF001
            "a note was raised for a gate that opens normally",
        )


@case("data audit: the composite walk finds a gate in a SIBLING `of` entry, not the first")
def _composite_walk_reads_the_entry_it_is_about() -> None:
    """The window that would otherwise silently narrow the reader.

    `_NONE_OF_GATE` cannot count brackets, so it stops at the first `]` after `of`.
    An `all_of` child whose own requirements sit inside a `Array[Dictionary]` puts
    another `]` there. A composite holding such a child FIRST and a `tagged` row
    second is exactly where that boundary has to be proved, because a reader that
    stopped early would report the second row as a bare top-level gate and miss
    the door it is.
    """
    good_tag = "oath"
    files = {
        "destiny/fates/ok_fate.tres": _fate("ok_fate", (good_tag,)),
        "races/ok_race.tres": _race("ok_race"),
        "event/events/door.tres": _event(
            "door",
            _gate_with_requirement(
                "none_of",
                '{verb: &"all_of", "of": Array[Dictionary]([])} , ' + _gate("tagged", good_tag),
            ),
        ),
    }
    with _fixture((good_tag,), files) as (root, tool):
        authored = tool._authored_tagged_gates(root)  # noqa: SLF001
        doors = tool._none_of_tagged_gates(root)  # noqa: SLF001
        expect(
            len(authored) == 1,
            f"the whole-tree walk found {len(authored)} gate(s) {authored!r}, wanted one. The "
            "fixture no longer describes the shape the reader is matched against",
        )
        expect(
            len(doors) == 1,
            f"the nested `tagged` row was not read out of its composite: {doors!r}. It was "
            "probably taken for a top-level gate, which would report the door as an ordinary "
            "gate and never mention that it can only ever close",
        )


# --- Gate 2: the soul arrivals, which had NO audit at all (ADR 0190) ----------


def _real_fates() -> set[str]:
    """The REAL shipped fate ids, read from the repository rather than invented.

    `FateCatalog` keys `res://data/destiny/fates` by the ids in the shipped tree,
    so only an id from that tree can stand for a mark that resolves. Inventing one
    would make a fixture pass for the wrong reason, and the point of the fixture is
    that the SAME reader resolves it.
    """
    fates = _shipped_fate_ids()
    expect(bool(fates), "the shipped fate catalog is empty, so the marks cases prove nothing")
    return fates


def _real_races() -> set[str]:
    races = _shipped_race_ids()
    expect(bool(races), "no authored race was found, so the race_id cases prove nothing")
    return races


def _arrival_fixture(
    marks: tuple[str, ...],
    race_id: str | None = None,
    *,
    fate_id: str | None = None,
) -> dict[str, str]:
    """One arrival, beside the fates and races the gate will resolve it against.

    `fate_id` and `race_id` default to a real SHIPPED id, and the matching `.tres`
    is written under the fixture's own tree — so `_load` (which reads what is on
    disk) and `_authored_race_ids` (which reads `root`) agree with each other. A
    fixture naming an id it did not write would fail for a second reason and hide
    the one under test.
    """
    marks = (fate_id,) + marks if fate_id is not None else marks
    # Same rule as `race_id` below: the default must be the id this fixture
    # WRITES. The tree holds only `destiny/fates/ok_fate.tres`, so a shipped
    # default named a fate the gate could not resolve, and the "a real one is
    # clean" half of the mark case failed for a second reason that hid the one
    # under test.
    if not marks:
        marks = ("ok_fate",)
    # The default must be the id this fixture WRITES, not a shipped one. The tree
    # below contains `races/ok_race.tres` and nothing else, so defaulting to
    # `sorted(_real_races())[0]` handed the arrival a race the fixture never
    # authored — and the audit correctly reported it as unresolvable, so the
    # "a distinct id is clean" half of the duplicate case failed for a second
    # reason and hid the one under test. The docblock above already warns that a
    # fixture naming an id it did not write fails for a second reason; this is
    # that mistake. Every caller now passes its own `race_id`, so this default
    # only has to agree with the `ok_race.tres` written below.
    race_id = race_id if race_id is not None else "ok_race"
    return {
        "destiny/fates/ok_fate.tres": _fate("ok_fate"),
        "races/ok_race.tres": _race("ok_race"),
        "soul/arrivals/fixture_arrival.tres": _arrival("fixture_arrival", marks, race_id),
    }


@case("data audit: the shipped arrivals tree is no longer INVISIBLE to the audit")
def _soul_arrivals_are_parsed_at_all() -> None:
    """The finding this whole leg exists for, asserted before anything else.

    `_load` skips any file whose folder has no `TYPE_BY_FOLDER` entry, so before
    the `soul` key landed a mark naming a fate nobody defines, a duplicated
    arrival id and a `race_id` naming no race were all INVISIBLE — every gate in
    the repo called the tree clean. Asserting the count is what the loader returns
    is the receipt; a later reader that mistook "no arrivals" for "no defects"
    would satisfy every other case in this file.
    """
    records, malformed = _records(data_tool.DATA_ROOT), []
    arrivals = records.get("soul", {})
    expect(
        arrivals,
        "the shipped game/data/soul/arrivals tree loaded zero records, so it is still "
        "un-audited and a mark naming no FateDef would ship green (ADR 0190)",
    )
    expect(not malformed, f"shipped arrivals loaded as malformed: {malformed!r}")
    expect(
        all(arrival["arrays"].get("marks") is not None for arrival in arrivals.values()),
        "an arrival loaded without its `marks` array, so a mark naming no FateDef could "
        "not be checked even though the file is now visible",
    )


@case("data audit: a mark naming no FateDef FAILS, and a real one is clean")
def _unresolvable_mark_fails_and_a_real_one_passes() -> None:
    """ADR 0135's rule, extended to the arrival that authors the grant.

    `earn_fate` refuses an unknown fate id with the same empty return it gives an
    already-held one, so an unresolvable mark grants nothing, says nothing, and
    is worse than an absent mark: it reads as a ladder rung that is really there.
    """
    # The resolvable half must be a fate THIS fixture writes. Passing a shipped id
    # made the arrival carry `ancestral_debt_unpaid` while the fixture tree holds
    # only `destiny/fates/ok_fate.tres`, so the assertion below — that the clean
    # mark resolves — failed for a second reason and the case proved nothing.
    # `_real_fates()` is exercised by the audit cases that read the shipped tree.
    fate_id = "ok_fate"
    files = _arrival_fixture(("no_such_fate_for_this_gate",), fate_id=fate_id)
    with _fixture((), files) as (root, tool):
        expect(
            "ok_fate" in _records(root)["fate"],
            "the fixture's resolvable mark is not in the fate catalog the gate reads, so the "
            "clean half of this case cannot be telling the two findings apart",
        )
        records = _records(root)
        _authors(records, root, tool)
        findings = tool._soul_findings(records, root)  # noqa: SLF001
        dangling = [f for f in findings if "no_such_fate_for_this_gate" in f]
        expect(
            len(dangling) == 1,
            f"an arrival marking a fate no FateDef defines produced {len(dangling)} finding(s) "
            f"({findings!r}); exactly one is wanted, so a fixture with one resolvable mark and "
            "one dangling one tells the two apart",
        )
        expect(
            not [f for f in findings if "'ok_fate'" in f],
            f"the mark naming the fixture's own authored fate 'ok_fate' was reported: "
            f"{findings!r}. A gate that failed every mark would be red for a correct tree",
        )


@case("data audit: a `race_id` naming no RaceDef FAILS, and a real one is clean")
def _unauthored_race_fails_and_a_real_one_passes() -> None:
    """The body is authored on the arrival precisely so nothing maps it in code.

    `CharacterCreationFlow.build_forced` reads `SoulDef.race_id` and builds the
    body from it, so an id no `RaceDef` defines means a returning soul arrives in
    no body at all — and the same empty return the module already gives a blank
    field, so nothing says which of the two happened.
    """
    files = _arrival_fixture((), race_id="ok_race", fate_id="ok_fate")
    with _fixture((), files) as (root, tool):
        records = _records(root)
        _authors(records, root, tool)
        findings = tool._soul_findings(records, root)  # noqa: SLF001
        expect(
            not findings,
            f"an arrival naming the race its own fixture authored was reported: {findings!r}",
        )
    files = _arrival_fixture((), race_id="no_such_race_for_this_gate", fate_id="ok_fate")
    with _fixture((), files) as (root, tool):
        records = _records(root)
        _authors(records, root, tool)
        findings = tool._soul_findings(records, root)  # noqa: SLF001
        expect(
            len(findings) == 1 and "no_such_race_for_this_gate" in findings[0],
            f"an arrival arriving in an unauthored race produced {findings!r}; exactly one "
            "finding naming it is wanted",
        )


@case("data audit: a DUPLICATE arrival id FAILS, and a distinct one is clean")
def _duplicate_arrival_id_fails_and_a_distinct_one_passes() -> None:
    """The silent last-wins, named.

    `SoulCatalog._ensure_loaded` writes `_arrivals[String(def.id)] = def`, so two
    files carrying one id leaves one arrival unreachable and nothing anywhere says
    so. The loader keys by id too and overwrites the loser, so this is the case
    that proves the gate looked for it rather than inheriting it.
    """
    files = _arrival_fixture((), fate_id="ok_fate")
    # The two rows are otherwise IDENTICAL, so the ONLY way the gate can find
    # exactly one duplicate is if it keys on the id rather than on differing
    # content. A second arrival with its own id and its own mark is the
    # counterweight below.
    files["soul/arrivals/fixture_arrival_copy.tres"] = _arrival(
        "fixture_arrival", ("ok_fate",), "ok_race"
    )
    with _fixture((), files) as (root, tool):
        records = _records(root)
        _authors(records, root, tool)
        findings = tool._soul_findings(records, root)  # noqa: SLF001
        duplicated = [f for f in findings if "duplicate arrival id" in f]
        expect(
            len(duplicated) == 1,
            f"two arrivals sharing one id produced {len(duplicated)} duplicate finding(s) "
            f"({findings!r}); exactly one is wanted, and it must name BOTH files so an author "
            "knows which row to rename",
        )
        expect(
            "fixture_arrival.tres" in duplicated[0]
            and "fixture_arrival_copy.tres" in duplicated[0],
            f"the duplicate finding does not name both files, so it cannot be acted on: "
            f"{duplicated!r}",
        )
    files = _arrival_fixture((), fate_id="ok_fate")
    files["soul/arrivals/second_arrival.tres"] = _arrival("second_arrival", ("ok_fate",), "ok_race")
    with _fixture((), files) as (root, tool):
        records = _records(root)
        _authors(records, root, tool)
        findings = tool._soul_findings(records, root)  # noqa: SLF001
        expect(
            not findings,
            f"two arrivals with DISTINCT ids were reported as duplicates: {findings!r}",
        )


@case("data audit: a bad arrival makes the AUDIT exit non-zero, and a good one does not")
def _soul_leg_fails_the_audit_exit_code() -> None:
    """The exit code is the deliverable; the leg returning a list is not.

    `tools check` runs `data audit` and reads nothing else, so a `_soul_findings`
    that returns findings but is never wired in would satisfy every case above.
    Asserting the return code, for the broken fixture AND the clean one, is the
    proof that it is reached.
    """
    files = _arrival_fixture(
        ("no_such_fate_for_this_gate",), race_id="no_such_race_for_this_gate", fate_id="ok_fate"
    )
    files["soul/arrivals/fixture_arrival_copy.tres"] = _arrival(
        "fixture_arrival", ("ok_fate",), "no_such_race_for_this_gate"
    )
    with _fixture((), files) as (root, tool):
        code, output = _verdict(root)
        expect(
            code == 1,
            f"`data audit` exited {code} over an arrival with an unresolvable mark, an "
            f"unauthored race AND a duplicated id. Output:\n{output}",
        )
        for expected in ("no_such_fate_for_this_gate", "no_such_race_for_this_gate"):
            expect(
                expected in output,
                f"the failing audit never named {expected!r}, so an author cannot act:\n{output}",
            )
    with _fixture((), _arrival_fixture((), fate_id="ok_fate")) as (root, tool):
        code, output = _verdict(root)
        expect(
            code == 0,
            f"`data audit` exited {code} over one arrival whose mark and race both resolve:\n"
            f"{output}",
        )


@case("data audit: an arrivals-only tree is still audited (no early return)")
def _arrivals_without_fates_are_audited() -> None:
    """The vacuous-green shape, which a natural early return would reintroduce.

    `_destiny_findings` opens with a "nothing to check" return. A reader that kept
    it keyed on fates and destinies alone would return `[]` for a tree holding only
    arrivals — and that tree is precisely the one whose every mark is dangling,
    because a tree with no fates resolves nothing. This fixture has no fates at all
    and must still fail.
    """
    files = {
        "races/ok_race.tres": _race("ok_race"),
        "soul/arrivals/orphaned_arrival.tres": _arrival(
            "orphaned_arrival", ("no_such_fate_for_this_gate",), "ok_race"
        ),
    }
    with _fixture((), files) as (root, tool):
        records = _records(root)
        expect(
            not records.get("fate") and records.get("soul"),
            f"the fixture is not arrivals-only: fate={records.get('fate')!r} "
            f"soul={list(records.get('soul', {}))!r}",
        )
        gaps, _notes = tool._destiny_findings(records, root)  # noqa: SLF001
        expect(
            any("no_such_fate_for_this_gate" in gap for gap in gaps),
            f"a tree holding arrivals and no fates reported {gaps!r}. Every mark in it is "
            "dangling by construction, so an early return keyed on the fate catalog makes "
            "the audit pass for the wrong reason",
        )


@case("data audit: an UNDECLARED content family FAILS, and a declared one is clean")
def _undeclared_family_fails_and_a_declared_one_passes() -> None:
    """ADR 0184's registry cut: an unknown folder is a hard error, never a skip.

    A mod adding `game/data/<prefix>/` content is a new family, and a folder the
    registry does not name has no gate to vouch for it — so it must fail loudly
    rather than be silently skipped (ADR 0184 decision 9). The red half builds a
    folder the registry does not declare and asserts the audit names it; the
    green half runs the SAME tree minus that folder and asserts the finding is
    gone, so a check that reported every folder (or none) cannot pass.
    """
    prefix = "no_such_family_for_this_gate"
    expect(
        prefix not in data_tool.DECLARED_DIRS,
        f"{prefix!r} is now a declared content family, so this fixture no longer tests "
        "the undeclared path — pick a new name",
    )
    # A real declared tree (fate + race + arrival) already proven clean by
    # `_soul_leg_fails_the_audit_exit_code`, so the green half is a real tree and
    # not a vacuous pass.
    clean = _arrival_fixture((), fate_id="ok_fate")
    # The red half: same tree plus one file in a folder the registry does not
    # declare. The content is irrelevant — `_load` skips the file before parsing
    # it — but it must exist for the walk to find it.
    broken = dict(clean)
    broken[f"{prefix}/stray.tres"] = '[gd_resource type="Resource" format=3]\n\n[resource]\n'
    with _fixture((), broken) as (root, tool):
        code, output = _verdict(root)
        expect(
            code == 1,
            f"`data audit` exited {code} over an undeclared content family {prefix!r}. "
            f"Output:\n{output}",
        )
        expect(
            prefix in output,
            f"the failing audit never named the undeclared family, so an author cannot "
            f"act on it:\n{output}",
        )
        expect(
            "undeclared content family" in output,
            f"the finding did not say WHY the folder is a problem:\n{output}",
        )
    with _fixture((), clean) as (root, tool):
        code, output = _verdict(root)
        expect(
            code == 0,
            f"`data audit` exited {code} over a tree holding only declared content. "
            f"The undeclared finding must be gone:\n{output}",
        )
        expect(
            "undeclared content family" not in output,
            f"a declared-only tree still reported an undeclared family:\n{output}",
        )


# --- Gate 3: `has_fate`/`has_destiny` ids must RESOLVE (DEF-0284) --------------
#
# The whole-tree property is the load-bearing one, so every red fixture here puts
# its gate on an EVENT or a QUEST — never on a destiny. A destiny-scoped fixture
# would pass even from a reader that scanned only `game/data/destiny/`, which is
# the wrong-reason pass `_authored_counter_gates`' docstring warns about. The
# shipped tree measures 6 such gates: 2 on events, 4 on quests.


def _has_fixture(gate_id: str, *, verb: str = "has_fate") -> dict[str, str]:
    """An event carrying one `has_fate`/`has_destiny` gate on `gate_id`.

    `ok_fate` is written by the fixture and `the_kept_destiny` is written with a
    DECLARED alias, so the clean half of each case resolves through the real
    catalog and the red half differs by exactly one id.
    """
    return {
        "destiny/fates/ok_fate.tres": _fate("ok_fate", ("oath",)),
        "destiny/destinies/the_kept_destiny.tres": _destiny_with_aliases(
            "the_kept_destiny", ("the_returned",)
        ),
        "races/ok_race.tres": _race("ok_race"),
        "event/events/fixture_event.tres": _event(
            "fixture_event", _gate_with_requirement("all_of", _gate(verb, gate_id))
        ),
    }


@case("data audit: a `has_fate` gate naming an id no FateDef defines FAILS")
def _dangling_has_fate_fails_the_audit() -> None:
    """The red path for the verb that had NO Python-side gate at all (DEF-0284).

    `DestinyGate._has_fate` looks the id up in the ledger, finds nothing, and
    returns an ordinary `unmet` — indistinguishable from "you have not earned it
    yet". Nothing can ever earn an id no definition declares, so the quest
    silently never offers and no reader anywhere says why.

    The gate is authored on an EVENT, outside `game/data/destiny/`, because a
    destiny-scoped fixture would be satisfied by a reader that scans one
    directory — and would then pass for the wrong reason. The whole-tree census
    is the property under test, so the fixture has to defeat a single-directory
    reader rather than merely agree with a correct one.
    """
    dangling = "first_blood_duell"  # the real id is `first_blood_duel`: one l.
    files = _has_fixture(dangling)
    with _fixture(("oath",), files) as (root, tool):
        authored = tool._authored_has_gates(root)  # noqa: SLF001
        expect(
            len(authored) == 1 and authored[0][1] == dangling,
            f"the whole-tree walk missed the authored gate, or reported it under the wrong "
            f"name: {authored!r}. The walk is the census every `has_fate` verdict rests on",
        )
        gaps = tool._has_gate_findings(_records(root), root)  # noqa: SLF001
        expect(
            len(gaps) == 1 and dangling in gaps[0],
            f"a `has_fate` gate naming the dangling id {dangling!r} produced {gaps!r}; "
            "exactly one finding naming it is wanted, so a fixture with one resolvable "
            "authored catalog and one dangling id tells the two readings apart",
        )
        code, output = _verdict(root)
        expect(
            code == 1,
            f"`data audit` exited {code} over a `has_fate` gate naming {dangling!r}. "
            f"Output:\n{output}",
        )
        expect(
            dangling in output,
            f"the failing audit never named the dangling id, so an author cannot act on "
            f"it:\n{output}",
        )


@case("data audit: a `has_fate` gate naming an authored FateDef is clean")
def _resolvable_has_fate_passes() -> None:
    """The counterweight, and the half that can go stale.

    Same fixture with one string changed. A walk or resolver that reported every
    authored id satisfies the red case and is useless — and this is the half that
    catches a resolver that forgot to consult the fate catalog at all.
    """
    files = _has_fixture("ok_fate")
    with _fixture(("oath",), files) as (root, tool):
        gaps = tool._has_gate_findings(_records(root), root)  # noqa: SLF001
        expect(
            not gaps,
            f"a gate naming this fixture's OWN authored fate 'ok_fate' was reported: {gaps!r}. "
            "A resolver that refused the catalog itself would be red for a correct tree",
        )
        code, output = _verdict(root)
        expect(
            code == 0,
            f"`data audit` exited {code} over a gate naming an authored fate. The "
            f"whole-fixture verdict, not just this leg:\n{output}",
        )


@case("data audit: a `has_destiny` gate naming an AUTHORED ALIAS is clean")
def _authored_alias_is_a_legal_gate_id() -> None:
    """ADR 0113's rule, which is the one direction a naive resolver gets WRONG.

    `DestinyDef.gate_aliases` exists so story can be authored before the destiny
    it answers for ships, and `DestinyGate.holds_destiny` resolves an alias in
    BOTH directions. So a gate naming the alias is a SATISFIABLE prerequisite, and
    a resolver that checks only the `.tres` records would FAIL it — making the
    audit and the runtime disagree about whether a content author may write
    something, which is how a gate loses its readers for good.

    The fixture DECLARES the alias on a real record, so this asserts the alias
    route and not merely "an id that resolves against nothing". Measured: the
    shipped tree really does carry `the_returned` as an alias of
    `the_one_who_returned`, so this is live content and not a shape nobody uses.
    """
    files = _has_fixture("the_returned", verb="has_destiny")
    with _fixture(("oath",), files) as (root, tool):
        records = _records(root)
        authored = {
            alias
            for destiny in records.get("destiny", {}).values()
            for alias in destiny["arrays"].get("gate_aliases", [])
        }
        expect(
            "the_returned" in authored,
            f"the fixture's alias did not read back off the DestinyDef record, so this "
            f"case would be testing a dangling id rather than an alias: {authored!r}",
        )
        gaps = tool._has_gate_findings(records, root)  # noqa: SLF001
        expect(
            not gaps,
            f"a gate naming an AUTHORED alias was reported as dangling: {gaps!r}. An alias "
            "is a legal authored id (ADR 0113); refusing it turns the audit red for a tree "
            "the runtime answers correctly",
        )
        code, output = _verdict(root)
        expect(
            code == 0,
            f"`data audit` exited {code} over a gate naming a declared alias:\n{output}",
        )


@case("data audit: a `has_destiny` gate naming a DANGLING id FAILS (alias ≠ anything)")
def _dangling_has_destiny_fails_the_audit() -> None:
    """The alias case's converse, and the anti-vacuity term for it.

    An author may NOT coin a destiny gate id the way a `has_fate` typo looks like
    one: `holds_destiny` resolves an alias only when some definition DECLARES it,
    and `_alias_target` refuses to widen to a CONTESTED alias rather than picking
    a winner. So `the_severed` on the shipped tree resolves and
    `the_severedd` does not, and nothing between them is legal. Without this case
    a resolver that waved EVERY `has_destiny` id through would pass the alias case
    above.
    """
    dangling = "the_severedd"
    files = _has_fixture(dangling, verb="has_destiny")
    with _fixture(("oath",), files) as (root, tool):
        gaps = tool._has_gate_findings(_records(root), root)  # noqa: SLF001
        expect(
            len(gaps) == 1 and dangling in gaps[0],
            f"a `has_destiny` gate naming the dangling id {dangling!r} produced {gaps!r}; "
            "exactly one finding naming it is wanted",
        )
        code, output = _verdict(root)
        expect(
            code == 1,
            f"`data audit` exited {code} over a dangling `has_destiny` id {dangling!r}. "
            f"Output:\n{output}",
        )


@case("data audit: a `has_fate` row NESTED in a composite is still resolved")
def _nested_has_gate_inside_a_composite_is_resolved() -> None:
    """Composites are what a gate really looks like, so a top-level-only reader is wrong.

    `has_fate` nests inside `all_of`/`any_of`/`none_of`, and a descendant reader
    is what finds it. Measured on the shipped tree: `the_severed_calling.tres`
    authors `all_of:[{has_destiny: the_severed}, {has_fate: oath_breaker}]` — both
    rows nested, both real.

    The fixture nests the dangling row inside an `all_of` whose FIRST child holds
    its own empty `Array[Dictionary]`, which puts a `]` inside the outer list. A
    non-greedy `"of": \[(.*?)\]` stops there and never sees the row at all — the
    exact false negative that cost `_NONE_OF_GATE` its original reading, and the
    reason the descent COUNTS brackets instead. Sibling-first is deliberate.
    """
    dangling = "no_such_fate_in_a_composite"
    files = {
        "destiny/fates/ok_fate.tres": _fate("ok_fate", ("oath",)),
        "races/ok_race.tres": _race("ok_race"),
        "event/events/nested.tres": _event(
            "nested",
            _gate_with_requirement(
                "all_of",
                '{verb: &"all_of", "of": Array[Dictionary]([])}, ' + _gate("has_fate", dangling),
            ),
        ),
    }
    with _fixture(("oath",), files) as (root, tool):
        authored = tool._authored_has_gates(root)  # noqa: SLF001
        expect(
            len(authored) == 1 and authored[0][1] == dangling,
            f"a `has_fate` row nested in an `all_of` was not read out of its composite: "
            f"{authored!r}. A reader that only saw top-level rows under-reports, and an "
            "under-reported gate is a gate nobody reads the output of",
        )
        gaps = tool._has_gate_findings(_records(root), root)  # noqa: SLF001
        expect(
            len(gaps) == 1 and dangling in gaps[0],
            f"the nested dangling id was not reported: {gaps!r}",
        )
        code, output = _verdict(root)
        expect(
            code == 1,
            f"`data audit` exited {code} over a dangling id nested inside an `all_of`. "
            f"Output:\n{output}",
        )


@case("data audit: a TOP-LEVEL `has_fate` row is resolved (no composite needed)")
def _top_level_has_gate_is_resolved() -> None:
    """The half that proves the census is the UNION of both readers, not one of them.

    Measured on the shipped tree, the two halves of `_authored_has_gates` do not
    find the same rows: `the_returned_instrument.tres` and
    `the_terms_you_drafted.tres` each author their gate at the TOP level, so the
    composite descent returns `[]` for them, while the nested case above is found
    only by the descent's sibling structure. A reader built on either half alone
    under-reports on real content.

    A reader that dropped the composite half would pass the nested case for the
    wrong reason here (the flat regex searches the whole file regardless of
    nesting), and a reader that dropped the flat half would fail this one. Both
    are in the file because both are real.
    """
    dangling = "no_such_fate_at_top_level"
    files = {
        "destiny/fates/ok_fate.tres": _fate("ok_fate", ("oath",)),
        "races/ok_race.tres": _race("ok_race"),
        "event/events/bare.tres": _event("bare", _gate("has_fate", dangling)),
    }
    with _fixture(("oath",), files) as (root, tool):
        expect(
            len(tool._authored_has_gates(root)) == 1,  # noqa: SLF001
            "the top-level gate was missed; the flat half of the census is the one that "
            "finds a row authored without a composite wrapper",
        )
        gaps = tool._has_gate_findings(_records(root), root)  # noqa: SLF001
        expect(
            len(gaps) == 1 and dangling in gaps[0],
            f"a top-level dangling id was not reported: {gaps!r}",
        )


# --- Gate 4: the counter guards, which had NO red path at all (DEF-0283) -------
#
# `_counter_findings` and `_counter_notes` are called from `_destiny_findings`
# and were exercised by NOTHING in this file. A reader returning `[]` from both
# passes every other case here AND leaves `data audit`'s output byte-identical —
# which is INC-0016, a green guard that is not a tested guard.
#
# The SEVERITY SPLIT is the point of the pair, and each half is tested at its OWN
# severity: a `counter` GATE closes a player door and FAILS; a COUNTER_FACTS row
# naming a fact no producer can record is a CENSUS and WARNS (`breakthroughs` is
# deliberately in that list, DEF-0105/DEF-0106 lineage, and failing it would be
# red for a correct tree).


@case("data audit: a `counter` gate naming an unwired id FAILS the whole audit")
def _counter_gate_on_an_unwired_id_fails() -> None:
    """The red path for `_counter_findings` (ADR 0149's owed check, DEF-0283).

    An unwired counter id is not "a gate that is hard to open" — it is a gate
    NOTHING can open, because only the ids one `COUNTER_FACTS` row names are ever
    moved. It FAILS rather than warns because the door is closed to the player.

    The gate is authored on an EVENT. The walk is whole-tree, so a fate-scoped
    fixture would pass even against a reader that scanned only
    `game/data/destiny/` — satisfying this case for the wrong reason, which is
    the exact mistake the fixture shape exists to rule out.
    """
    unwired = "no_such_counter"
    files = {
        "destiny/fates/ok_fate.tres": _fate("ok_fate", ("oath",)),
        "races/ok_race.tres": _race("ok_race"),
        "event/events/counter_door.tres": _event(
            "counter_door", _gate_with_requirement("all_of", _gate("counter", unwired))
        ),
    }
    with _fixture(("oath",), files) as (root, tool):
        authored = tool._authored_counter_gates(root)  # noqa: SLF001
        expect(
            len(authored) == 1 and authored[0][1] == unwired,
            f"the whole-tree counter walk missed the gate, or named it wrong: {authored!r}",
        )
        gaps = tool._counter_findings(root)  # noqa: SLF001
        expect(
            len(gaps) == 1 and unwired in gaps[0],
            f"a `counter` gate on the unwired id {unwired!r} produced {gaps!r}; exactly one "
            "finding naming it is wanted, because a check that failed every counter gate "
            "would be red for a correct tree",
        )
        code, output = _verdict(root)
        expect(
            code == 1,
            f"`data audit` exited {code} over a `counter` gate on {unwired!r}. An unwired "
            f"id is a closed door, so it FAILS (ADR 0149). Output:\n{output}",
        )
        expect(
            unwired in output,
            f"the failing audit never named the unwired counter id, so an author cannot act "
            f"on it:\n{output}",
        )


@case("data audit: a `counter` gate naming a WIRED id is clean")
def _wired_counter_gate_passes() -> None:
    """The counterweight for `_counter_findings`, and the half that catches a blanket FAIL.

    The id is chosen from the REAL `COUNTER_FACTS` rows so the green half resolves
    through the shipped projection rather than a fixture's invention — a fixture
    inventing a counter id would be asserting against a vocabulary the fixture
    itself defined, which is the ADR 0066 shape in a test.
    """
    wired = sorted(data_tool._counter_facts())[0]
    files = {
        "destiny/fates/ok_fate.tres": _fate("ok_fate", ("oath",)),
        "races/ok_race.tres": _race("ok_race"),
        "event/events/counter_door.tres": _event(
            "counter_door", _gate_with_requirement("all_of", _gate("counter", wired))
        ),
    }
    with _fixture(("oath",), files) as (root, tool):
        expect(
            wired in data_tool._counter_facts(),
            f"{wired!r} is no longer a COUNTER_FACTS id, so this green half is no longer "
            "testing a resolvable counter — pick a new one",
        )
        gaps = tool._counter_findings(root)  # noqa: SLF001
        expect(
            not gaps,
            f"a gate naming the SHIPPED wired counter {wired!r} was reported: {gaps!r}. A "
            "check that refused the wired vocabulary would be red for a correct tree",
        )
        code, output = _verdict(root)
        expect(
            code == 0,
            f"`data audit` exited {code} over a gate naming a wired counter id:\n{output}",
        )


@case("data audit: an UNPRODUCED COUNTER_FACTS row is a NOTE, never a failure")
def _unproduced_counter_fact_is_a_note_only() -> None:
    """The severity split's other half, asserted at its OWN severity (DEF-0283).

    `_counter_notes` WARNS where `_counter_findings` FAILS, and the difference is
    real rather than stylistic: a `COUNTER_FACTS` row naming a fact no shipped
    producer can record is a recorded gap in ANOTHER module's content
    (DEF-0105/DEF-0106 — `breakthroughs` is deliberately still in that list), so
    hard-failing would be red for a tree behaving correctly. It is a CENSUS.

    So this asserts BOTH directions and they are different: the note is raised AND
    the exit code is still 0. A test that only asserted the note would pass a
    reader that raised it as a failure; one that only asserted exit 0 would pass a
    reader that said nothing.
    """
    facts = data_tool._counter_facts()
    expect(bool(facts), "COUNTER_FACTS could not be read, so the census case proves nothing")
    # The shipped unproduced rows, if any, are the honest subject: this asserts
    # against the REAL census rather than a fixture-invented fact, for the reason
    # the wired-counter case above gives.
    unproduced = data_tool._unproduced_counter_facts(facts)
    if not unproduced:
        return
    fact = sorted(unproduced)[0]
    files = {
        "destiny/fates/ok_fate.tres": _fate("ok_fate", ("oath",)),
        "races/ok_race.tres": _race("ok_race"),
    }
    with _fixture(("oath",), files) as (root, tool):
        notes = tool._counter_notes(_records(root)["fate"], root)  # noqa: SLF001
        census = [n for n in notes if "no shipped producer can record" in n]
        expect(
            len(census) == 1 and fact in census[0],
            f"the unproduced fact {fact!r} was not reported as a census note naming it: "
            f"{notes!r}. Naming per-id rather than counting is what stops a fourth orphan "
            "arriving quietly",
        )
        code, output = _verdict(root)
        expect(
            code == 0,
            f"`data audit` exited {code} over an unproduced COUNTER_FACTS row. A census "
            f"must NOT fail the build — the rows in this list are a recorded gap in other "
            f"modules' content (DEF-0105/DEF-0106):\n{output}",
        )
        expect(
            fact in output,
            f"the note was never surfaced to the author, so the census exists but is "
            f"unread:\n{output}",
        )


@case("data audit: a FateDef.counters id with NO row is a NOTE, never a failure")
def _unwired_fate_counter_declaration_is_a_note_only() -> None:
    """`FateDef.counters` is read by NO production code (DEF-0168) — so it is a NOTE.

    This is the split stated from the other side of the same file: the same
    unwired-id question, the same missing `COUNTER_FACTS` row, and the opposite
    severity, because nothing a player can reach is closed by a declaration
    nothing reads. A gate and a declaration are not the same check, which is why
    both live in the audit with different severities rather than one swallowing
    the other.

    The fixture DECLARES `counters` on a fate, because a fixture that did not
    would reach the note through the COUNTER_FACTS half instead and prove nothing
    about this one.
    """
    unwired = "no_such_declared_counter"
    files = {
        "destiny/fates/declaring_fate.tres": _resource(
            "FateDef",
            "declaring_fate",
            'display_name = "Fixture"\ncategory = &"fixture"\n'
            f"tags = {_array(('oath',))}\ncounters = {_array((unwired,))}\n",
        ),
        "races/ok_race.tres": _race("ok_race"),
    }
    with _fixture(("oath",), files) as (root, tool):
        fates = _records(root)["fate"]
        expect(
            unwired in fates["declaring_fate"]["arrays"].get("counters", []),
            "the fixture's `counters` declaration did not read back, so this case would be "
            "reaching the note through some other path and proving nothing",
        )
        notes = tool._counter_notes(fates, root)  # noqa: SLF001
        declaration = [n for n in notes if "FateDef.counters id(s)" in n]
        expect(
            len(declaration) == 1 and unwired in declaration[0],
            f"an unwired `FateDef.counters` declaration produced {notes!r}; exactly one "
            "declaration note naming it is wanted",
        )
        code, output = _verdict(root)
        expect(
            code == 0,
            f"`data audit` exited {code} over an unwired `FateDef.counters` declaration. "
            "Nothing reads that field (DEF-0168), so it costs no player a door and must "
            f"NOT fail the build:\n{output}",
        )


@case("data audit: a stat id that exists only in a DOCSTRING is refused, a declared one is kept")
def _case_valid_stats_reads_declarations_not_prose() -> None:
    """DEF-0334: `_valid_stats` must read DECLARATIONS, and prose is not one.

    The measured defect: `contracts/stat.gd`'s own docstring carries
    `MindVocabulary.offence_id(&"slow")`, the bare-id regex matched it, and a mod
    declaring stat `slow` passed the Python audit while the GDScript declaration
    reader — one id stricter — refuses it. Both directions are asserted, because a
    scan that returned nothing would satisfy the refusal half alone.
    """
    with tempfile.TemporaryDirectory() as raw:
        fixture = write(
            Path(raw) / "stat.gd",
            "class_name Stat\n\n"
            '## The obvious spelling is `MindVocabulary.offence_id(&"prose_only")` and it\n'
            "## cannot be used: a static call is not a constant expression.\n"
            'const REAL_STAT := &"real_stat"\n',
        )
        original = data_tool.STAT_DEFS
        data_tool.STAT_DEFS = fixture
        try:
            found = data_tool._valid_stats()  # noqa: SLF001
        finally:
            data_tool.STAT_DEFS = original
    expect(
        "real_stat" in found,
        "the declared id is kept, so the refusal below is not emptiness passing",
    )
    expect(
        "prose_only" not in found,
        "an id that exists only in a docstring is not a declaration and must not validate",
    )
