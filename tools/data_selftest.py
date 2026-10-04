"""Red-path self-tests for the `data audit` legs that gate ADR 0189 and ADR 0190.

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


def _race(race_id: str) -> str:
    return _resource(
        "RaceDef", race_id, 'display_name = "Fixture race"\ntags = Array[StringName]([])\n'
    )


# A coined lineage, and the name ADR 0189 itself uses for one. `defensive` is the
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


# --- Gate 1: the closed fate-tag vocabulary (ADR 0189) ------------------------


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
        "a vocabulary fixture it was not pointed at — and ADR 0189 makes adding a tag a "
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
    files = {"destiny/fates/one_fate.tres": _fate("one_fate", ("oath",))}
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
            f"the failing audit never named the coined tag, so an author cannot act on it:\n{output}",
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
