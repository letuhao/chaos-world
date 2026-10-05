"""Red-path self-tests for `tools race_from_lore`.

A guard shipped in Python is unreachable from the GDScript suite, so nothing asserts it still
goes RED unless its cases are loaded (INC-0016). This is a separate case module beside
`adr_cite_selftest` and `data_selftest` rather than a block appended to `tools/selftest_cases.py`,
because that file is shared and busy: an append there cannot be committed without sweeping another
session's in-flight cases (INC-0041), and a red path that cannot be committed is not a red path.

## What each case proves

Not "the transcription passes on today's Bible" — `tools check` already does that, and it proves
nothing. Each case builds a species entity that violates one rule and asserts the rule fires:

- a species naming a stat `contracts/stat.gd` does NOT declare, which would emit a modifier the
  game silently ignores — exactly the defect the free-text `race:` tags in `character-index.jsonl`
  already are
- a kebab-case lore tag, which as a `StringName` would never match a `has_trait` gate
- a species the Bible leaves UNSPECIFIED, refused rather than defaulted — a `RaceDef` default is the
  CLASS's idea of an ordinary body, not this species's
- a body that CANNOT STRIKE, by either route: no physique, or an authored `attack_physical: -1.0`

Each case also asserts the compliant species is NOT refused, so the rules discriminate rather than
rejecting everything — a guard that fails on all input measures nothing.

No case writes to the repository: every fixture is a dictionary handed to `transcribe`.
"""

from __future__ import annotations

from . import race_from_lore as rfl
from .selftest import case, expect


def _full_scalars() -> dict[str, float]:
    """A species the Bible specifies completely, so the refusal rules are not what fires."""
    return {field: 1.0 for field in rfl.SCALAR_FIELDS}


@case("race_from_lore: a species naming a stat contracts/stat.gd does NOT declare is REJECTED")
def _undeclared_stat_is_rejected() -> None:
    """A transcribed modifier the game cannot read is the defect ADR 0253 exists to prevent.

    The Lore Bible is free text. If it names `luck` in `percent_modifiers` and `contracts/stat.gd`
    never declares `luck`, transcription happily emits a RaceDef carrying a modifier the game
    silently ignores — a species whose authored balance quietly does nothing. Nothing downstream
    reports that, which is precisely the shape of the free-text `race:` tags already sitting in
    `character-index.jsonl` that the game ignores.

    So an undeclared stat must be a HARD failure naming the offending key and the FIELD it came
    from, and the check has to read the real `contracts/stat.gd` rather than a hardcoded list, or
    it would pass while the contract itself changed underneath it.
    """
    declared = rfl.declared_stats()
    expect(
        "physique" in declared and "will" in declared,
        f"contracts/stat.gd yielded {len(declared)} key(s) and neither stat this "
        "case relies on, so the read is wrong rather than the guard",
    )

    entity = {
        "name": "Selftest Kin",
        "summary": "A species invented by this case.",
        "tags": ["Cold-Adapted"],
        "attributes": {
            **_full_scalars(),
            "percent_modifiers": {"luck": 0.4},
            "base_attributes": {"physique": 2.0},
        },
    }
    _body, problems, _omitted, _refusal = rfl.transcribe("races.selftest_kin", entity, declared)
    joined = " | ".join(problems)
    expect(
        any("luck" in problem for problem in problems),
        f"an undeclared stat was transcribed without complaint; it reported {joined!r}",
    )
    expect(
        any("percent_modifiers" in problem for problem in problems),
        f"the problem named the key but not the FIELD it came from; it reported {joined!r}",
    )
    expect(
        any("contracts/stat.gd" in problem for problem in problems),
        f"the problem named the key but not the CONTRACT that would have to declare it; "
        f"it reported {joined!r}",
    )

    # The same entity with a DECLARED key transcribes clean, so the guard discriminates.
    good = {
        "name": "Selftest Kin",
        "summary": "A species invented by this case.",
        "tags": [],
        "attributes": {**_full_scalars(), "percent_modifiers": {"physique": 0.4}},
    }
    body, good_problems, _omitted, _refusal = rfl.transcribe("races.selftest_kin", good, declared)
    expect(
        not good_problems,
        f"a species using a declared stat still reported {good_problems!r}, so the guard rejects "
        "everything and measures nothing",
    )
    expect(
        'percent_modifiers = {"physique": 0.4}' in body,
        f"the declared key was not emitted verbatim; the body was {body!r}",
    )


@case("race_from_lore: a kebab-case lore tag becomes a snake_case StringName")
def _kebab_tags_become_snake_case() -> None:
    """`cold-adapted` cannot match a `has_trait` gate; a hyphenated tag is a dead tag.

    Transcribed rather than copied, and asserted on the EMITTED text rather than on the `snake()`
    helper, so the case fails if the conversion is ever dropped from `transcribe` — a change that
    would otherwise leave every other case in this file passing while unusable tags ship.
    """
    expect(
        rfl.snake("cold-adapted") == "cold_adapted",
        f"snake() returned {rfl.snake('cold-adapted')!r} for a kebab-case tag",
    )
    expect(
        rfl.snake("path-complete") == "path_complete",
        f"snake() returned {rfl.snake('path-complete')!r} for a second kebab-case tag",
    )
    body, _problems, _omitted, _refusal = rfl.transcribe(
        "races.selftest_kin",
        {
            "name": "K",
            "summary": "s",
            "tags": ["cold-adapted"],
            "attributes": _full_scalars(),
        },
        rfl.declared_stats(),
    )
    expect(
        'tags = Array[StringName]([&"cold_adapted"])' in body,
        f"the tag was not emitted as a snake_case StringName; the body was {body!r}",
    )


@case("race_from_lore: a species the Bible leaves UNSPECIFIED is refused, not defaulted")
def _unspecified_species_is_refused() -> None:
    """A `RaceDef` default is the CLASS's idea of an ordinary body, not this species's.

    An earlier version wrote `SCALAR_DEFAULTS` for any scalar the Bible omitted. Five lore species
    (`emberborn`, `hearthborn`, `tideborn`, `tideculled`, `voidborn`) omit ALL eight, so every
    number in those five files would have been invented — a balance decision attributed to the Lore
    Bible and never made by anyone. Worse, the invented zeros failed
    `test_every_authored_race_carries_a_fertility_fraction` and the gestation check, so the guess
    did not even pass: it produced a species that is not born and cannot be played.

    So an omitted scalar is a REFUSAL. The refusal must NAME the missing scalars, because one that
    says only "cannot transcribe" leaves the author no idea what to write.
    """
    bare = {"dominance": 0.5}
    _body, _problems, omitted, refusal = rfl.transcribe(
        "races.selftest_kin",
        {"name": "K", "summary": "s", "tags": [], "attributes": dict(bare)},
        rfl.declared_stats(),
    )
    expect(
        refusal is not None,
        "a species specifying 1 of 8 balance scalars was transcribed anyway; it invents 7 numbers",
    )
    expect(
        "gestation_days" in (refusal or ""),
        f"the refusal did not name a missing scalar: {refusal!r}",
    )
    expect(
        set(omitted) == set(rfl.SCALAR_FIELDS) - set(bare),
        f"omitted reported {sorted(omitted)}, which is not every scalar the Bible left out",
    )

    # A fully-specified species is NOT refused, so the rule discriminates on presence.
    body, _problems, omitted, refusal = rfl.transcribe(
        "races.selftest_kin",
        {"name": "K", "summary": "s", "tags": [], "attributes": _full_scalars()},
        rfl.declared_stats(),
    )
    expect(
        refusal is None and not omitted,
        f"a fully-specified species was still refused ({refusal!r}, omitted={omitted})",
    )
    expect(
        "gestation_days = 1.0" in body,
        f"a specified scalar was not transcribed verbatim; the body was {body!r}",
    )


@case("race_from_lore: a species that CANNOT STRIKE is refused, not shipped")
def _body_that_cannot_hit_is_refused() -> None:
    """A race that deals no damage is a resource that passes every check and cannot play.

    `test_every_shipped_race_is_born_with_a_physique_and_can_strike` fails the build on a shipped
    race whose derived `ATTACK_PHYSICAL` is 0.0, and `tidecaller.tres` says why in prose: "an
    omitted grant is a grant of 0.0 ... Omitting it does not make this body even-framed, it makes it
    unable to hit anything." TWO routes reach that state — no physique, and an authored
    `attack_physical: -1.0`, which is exactly what the real `wake` entity carries.

    Both routes are pinned, because fixing only the missing-physique one leaves the
    `attack_physical: -1.0` species shipping as a corpse, and a refusal naming only one cause sends
    the author to fix the wrong field.
    """
    for percent, expect_text in ((None, "physique"), (-1.0, "attack_physical")):
        base = {"physique": 1.0 if percent is not None else 0.0}
        attributes: dict[str, object] = {**_full_scalars(), "base_attributes": base}
        if percent is not None:
            attributes["percent_modifiers"] = {"attack_physical": percent}
        _body, _problems, _omitted, refusal = rfl.transcribe(
            "races.selftest_kin",
            {"name": "K", "summary": "s", "tags": [], "attributes": attributes},
            rfl.declared_stats(),
        )
        expect(
            refusal is not None,
            f"a body with percent_modifiers={percent} was shipped even though it cannot strike",
        )
        expect(
            expect_text in (refusal or ""),
            f"the refusal did not name the offending field {expect_text!r}: {refusal!r}",
        )

    # A body that can strike is not refused, so the rule is not "refuse everything".
    _body, _problems, _omitted, refusal = rfl.transcribe(
        "races.selftest_kin",
        {
            "name": "K",
            "summary": "s",
            "tags": [],
            "attributes": {**_full_scalars(), "base_attributes": {"physique": 2.0}},
        },
        rfl.declared_stats(),
    )
    expect(refusal is None, f"a body with a physique of 2.0 was refused anyway: {refusal!r}")
