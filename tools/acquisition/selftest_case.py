"""Red-path self-tests for the DEF-0210 sole-route rule.

Separate from `tools/acquisition/validate.py` because a validator is shipped code
and a test of it is not: `validate.py` is imported by `tools check` on every run,
and importing it must not register test cases. `tools/selftest_cases.py` imports
this module for the same reason it imports the other case modules — one line, so
the registration stays greppable (INC-0016).

## The red path is proven against content this file owns

The first version of the red case asserted that `validate` reports a problem of the
shape `is obtainable only by a draw`, sourced from the **shipped corpus** — and it
went red within a day. A commit closed all 41 findings, so the corpus stopped
containing the defect, the validator correctly reported nothing, and the case
declared the rule dead. It had not stopped firing; the guard had proved itself
against the tree it was supposed to be independent of.

So every red case here builds a **fixture**: a minimal corpus in a temporary
directory that this module writes and `tempfile` deletes. The shipped corpus is
used for exactly one assertion, and it is the other half — that the rule now
reports **zero** sole-route problems. Both are asserted because they are
independent: a rule that fires on nothing and a rule that fires on everything are
the same broken guard, and only a fixture plus a clean corpus tells them apart.

The fixture is injected by pointing `chain.DATA_ROOT` and `chain.ENCOUNTER_DIR` at
it and restoring them in a `finally` — the redirect `tools/selftest_cases.py`
already uses for `lore` and `gate_reach`, so it needs no refactor of the validator
and writes nothing inside the repository. If `Graph` ever stops reading those two
roots the redirect goes quiet, so each case also asserts a **fixture-only** shape
(a count of exactly one, an id this file invented), which a silent fallback to the
real corpus cannot satisfy.
"""

from __future__ import annotations

import tempfile
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path

from ..selftest import case, expect, write
from . import chain
from .chain import Graph
from .validate import validate

MARKER = "is obtainable only by a draw"
# The two fixture reagents differ in exactly the property the rule asks about, and
# both declare no `craft:` route, so the pair is a control: a predicate answering
# `None` for everything and one answering a blocker for everything both fail it.
GUARANTEED_REAGENT = "st_qi_refining_core"
ROLLED_REAGENT = "st_qi_refining_herb"
# What `sole_route_blocker` says about an item that is neither gathered nor crafted:
# the two routes the report has to name, so a reader knows which one to author.
ABSENT_ROUTE_REASON = "no craft route and no guaranteed drop"
# The seed's three roles. Only the recovery one consumes the rolled reagent, so
# exactly one consumable in the fixture is obtainable only by a draw.
CLEAN_CONSUMABLES = ("st_qi_refining_pill", "st_qi_refining_elixir")
SOLE_CONSUMABLE = "st_qi_refining_recovery"
TRIAL_REALM = "qi_refining"
# `chain.TRIAL_PREFIX` for this path and realm, and the prefix requirement is
# load-bearing rather than cosmetic: a ladder trial resolves its domain through a
# reagent's `boss:` source, so a boss outside the prefix is in no trial at all and
# `_sole_route_problems` — the rule under test — is never reached.
FIXTURE_BOSS = "qi_qi_refining_selftest_guardian"
FIXTURE_DOMAIN = "st_qi_refining_trial"
FIXTURE_TABLE = "loot_st_qi_refining_guardian"
FIXTURE_ENCOUNTER = "loot_st_qi_refining_trial"
# The recipe graph the termination cases walk: authored rather than monkeypatched
# onto a real `Graph`, so the walk is exercised through the same `sources`/`inputs`
# vocabulary the shipped corpus uses.
CYCLE_A = "st_cycle_a"
CYCLE_B = "st_cycle_b"
CHAIN_HEAD = "st_deep_0"
# Fixed by construction: `MAX_RECIPE_DEPTH + 4`, four past the cap, so the cap is
# what stops the walk rather than the end of the chain. Nothing below grows the
# container it also walks (INC-0002).
CHAIN_LENGTH = chain.MAX_RECIPE_DEPTH + 4


def _array(values: tuple[str, ...]) -> str:
    return "Array[StringName]([" + ", ".join(f'&"{value}"' for value in values) + "])"


def _item(item_id: str, category: str, sources: tuple[str, ...]) -> str:
    return (
        '[gd_resource type="Resource" script_class="ItemDef" format=3]\n\n'
        "[resource]\n"
        f'id = &"{item_id}"\n'
        f'display_name = "{item_id.replace("_", " ").title()}"\n'
        f'category = &"{category}"\n'
        f'realm = &"{TRIAL_REALM}"\n'
        f"sources = {_array(sources)}\n"
    )


def _recipe(recipe_id: str, inputs: tuple[str, ...], outputs: tuple[str, ...]) -> str:
    return (
        '[gd_resource type="Resource" script_class="RecipeDef" format=3]\n\n'
        "[resource]\n"
        f'id = &"{recipe_id}"\n'
        'station = &"alchemy"\n'
        f"inputs = {_array(inputs)}\n"
        f"outputs = {_array(outputs)}\n"
    )


def _seed() -> str:
    return (
        '[gd_resource type="Resource" script_class="QiRealmSeed" format=3]\n\n'
        "[resource]\n"
        f'id = &"{TRIAL_REALM}"\n'
        f'breakthrough_item = &"{CLEAN_CONSUMABLES[0]}"\n'
        f'training_item = &"{CLEAN_CONSUMABLES[1]}"\n'
        f'recovery_item = &"{SOLE_CONSUMABLE}"\n'
    )


def _table() -> str:
    """One table: the core guaranteed on every resolve, the herb rolled."""
    return (
        '[gd_resource type="Resource" script_class="LootTableDef" format=3]\n\n'
        '[sub_resource type="Resource" id="entry_guaranteed"]\n'
        f'item_id = &"{GUARANTEED_REAGENT}"\n'
        'table_id = &""\n'
        "guaranteed = true\n"
        "quantity = 3\n\n"
        '[sub_resource type="Resource" id="entry_rolled"]\n'
        f'item_id = &"{ROLLED_REAGENT}"\n'
        'table_id = &""\n'
        "guaranteed = false\n\n"
        "[resource]\n"
        f'id = &"{FIXTURE_TABLE}"\n'
        f'realm = &"{TRIAL_REALM}"\n'
    )


def _encounter() -> str:
    """Two bands, both binding the boss to the one table.

    Two, because `_trial_problems` reports a single-band encounter and returns before
    the rule under test — and because rule E2 only makes a draw permanent on a band
    that is cleared rather than re-run.
    """
    bands = "".join(
        f'[sub_resource type="Resource" id="tier_{index}"]\n'
        f"tier = {index}\n"
        f'realm = &"{TRIAL_REALM}"\n'
        'rarity = &"common"\n'
        f"vitality = {40.0 * index}\n"
        "boss_tables = Array[Dictionary]([\n"
        f'\t{{"boss_id": &"{FIXTURE_BOSS}", "table_id": &"{FIXTURE_TABLE}"}},\n'
        "])\n\n"
        for index in (1, 2)
    )
    return (
        '[gd_resource type="Resource" script_class="LootEncounterDef" format=3]\n\n'
        f"{bands}"
        "[resource]\n"
        f'id = &"{FIXTURE_ENCOUNTER}"\n'
        f'domain_id = &"{FIXTURE_DOMAIN}"\n'
        f"boss_ids = {_array((FIXTURE_BOSS,))}\n"
        'tiers = Array[LootTier]([\n\tSubResource("tier_1"),\n\tSubResource("tier_2")\n])\n'
    )


def _write_fixture(root: Path) -> None:
    """The smallest corpus that exercises the rule: one seed, one boss, one table."""
    for consumable, reagent in (
        (CLEAN_CONSUMABLES[0], GUARANTEED_REAGENT),
        (CLEAN_CONSUMABLES[1], GUARANTEED_REAGENT),
        (SOLE_CONSUMABLE, ROLLED_REAGENT),
    ):
        recipe_id = f"{consumable}_recipe"
        write(
            root / f"items/consumables/{consumable}.tres",
            _item(consumable, "consumable", (f"craft:{recipe_id}",)),
        )
        write(
            root / f"recipes/{recipe_id}.tres",
            _recipe(recipe_id, (reagent,), (consumable,)),
        )
    for reagent in (GUARANTEED_REAGENT, ROLLED_REAGENT):
        write(
            root / f"items/material/{reagent}.tres",
            _item(reagent, "material", (f"boss:{FIXTURE_BOSS}",)),
        )

    # A two-recipe cycle and a chain past the depth cap, both authored. Nothing in
    # `game/data` forbids either, which is why the walk carries `seen` and a cap; this
    # is the fixture that trips both, over the real readers rather than a patched one.
    for left, right in ((CYCLE_A, CYCLE_B), (CYCLE_B, CYCLE_A)):
        recipe_id = f"{left}_recipe"
        write(
            root / f"items/material/{left}.tres",
            _item(left, "material", (f"craft:{recipe_id}",)),
        )
        write(root / f"recipes/{recipe_id}.tres", _recipe(recipe_id, (right,), (left,)))
    for index in range(CHAIN_LENGTH):
        item_id = f"st_deep_{index}"
        recipe_id = f"{item_id}_recipe"
        inputs = (f"st_deep_{index + 1}",) if index + 1 < CHAIN_LENGTH else ()
        write(
            root / f"items/material/{item_id}.tres",
            _item(item_id, "material", (f"craft:{recipe_id}",)),
        )
        write(root / f"recipes/{recipe_id}.tres", _recipe(recipe_id, inputs, (item_id,)))

    write(root / "qi_cultivation/realms/qi_refining.tres", _seed())
    write(
        root / f"bosses/{FIXTURE_BOSS}.tres",
        '[gd_resource type="Resource" script_class="BossDef" format=3]\n\n[resource]\n'
        f'id = &"{FIXTURE_BOSS}"\ndomain_id = &"{FIXTURE_DOMAIN}"\n'
        "loot = Array[StringName]([])\n",
    )
    write(
        root / f"domains/{FIXTURE_DOMAIN}.tres",
        '[gd_resource type="Resource" script_class="DomainDef" format=3]\n\n[resource]\n'
        f'id = &"{FIXTURE_DOMAIN}"\n'
        f"boss_ids = {_array((FIXTURE_BOSS,))}\n",
    )
    write(root / f"loot/tables/{FIXTURE_TABLE}.tres", _table())
    write(root / f"loot/encounters/{FIXTURE_ENCOUNTER}.tres", _encounter())


@contextmanager
def _fixture() -> Iterator[Graph]:
    """The shipped rules over a corpus this module owns, in a directory tempfile deletes."""
    with tempfile.TemporaryDirectory() as raw:
        root = Path(raw) / "data"
        _write_fixture(root)
        original_root, original_encounters = chain.DATA_ROOT, chain.ENCOUNTER_DIR
        chain.DATA_ROOT, chain.ENCOUNTER_DIR = root, root / "loot" / "encounters"
        try:
            # Passed explicitly: the parameter default was bound at import time, so
            # redirecting the module constant would not have moved it.
            yield Graph(root).require()
        finally:
            chain.DATA_ROOT, chain.ENCOUNTER_DIR = original_root, original_encounters


@case("acquisition: a realm seed consumable whose reagent has no route at all IS NAMED")
def _sole_route_consumable_is_named() -> None:
    with _fixture() as graph:
        hits = [problem for problem in validate(graph) if MARKER in problem]
        expect(
            len(hits) == 1,
            f"a fixture holding exactly one sole-routed consumable reported {len(hits)}: "
            f"{hits}. Either the rule has stopped firing or the fixture no longer "
            "describes the defect, and both mean this case proves nothing",
        )
        hit = hits[0]
        expect(
            ROLLED_REAGENT in hit,
            f"the report names the consumable but not the reagent blocking it: {hit}",
        )
        expect(
            SOLE_CONSUMABLE in hit,
            f"the report names the blocker but not the consumable it blocks: {hit}",
        )
        expect(
            ABSENT_ROUTE_REASON in hit,
            f"the report does not name the two absent routes, so a reader cannot act: {hit}",
        )
        expect(
            f"rolled on {FIXTURE_BOSS}@{FIXTURE_TABLE}" in hit,
            f"the report does not name the band that pays it only by a draw: {hit}",
        )
        expect(
            "cleared band grants no second run" in hit,
            f"the report does not name the hazard it exists for: {hit}",
        )


@case("acquisition: a reagent the band GUARANTEES is NOT reported as sole-routed")
def _guaranteed_reagent_is_not_reported() -> None:
    """The negative half, and the half a broadened rule breaks first.

    Same fixture, same table, same boss: only the `guaranteed` flag on the entry
    differs. A rule that reported every no-`craft:`-route reagent would pass the case
    above and be useless, so the pair is the test.
    """
    with _fixture() as graph:
        expect(
            bool(graph.delivers_unconditionally(GUARANTEED_REAGENT)),
            f"{GUARANTEED_REAGENT} has no guaranteed delivery in the fixture, so the "
            "control is not a control",
        )
        expect(
            graph.sole_route_blocker(GUARANTEED_REAGENT) is None,
            f"{GUARANTEED_REAGENT} is reported sole-routed although the fixture band "
            "guarantees it; the rule over-reports",
        )
        expect(
            bool(graph.rolled_deliveries(ROLLED_REAGENT)),
            f"{ROLLED_REAGENT} has no rolled delivery in the fixture, so the pair does "
            "not differ in the property the rule reads",
        )
        hits = [problem for problem in validate(graph) if MARKER in problem]
        for consumable in CLEAN_CONSUMABLES:
            expect(
                not [problem for problem in hits if consumable in problem],
                f"{consumable} crafts from the guaranteed reagent and was still reported: "
                f"{[problem for problem in hits if consumable in problem]}",
            )


@case("acquisition: the shipped corpus reports NO consumable obtainable only by a draw")
def _shipped_corpus_is_clean() -> None:
    """The other half, and the fact the fixture alone cannot establish.

    Independent of the two cases above: a rule that fires on nothing and a tree with
    nothing to fire on look identical from inside a fixture. `6ca5cbd8` closed all 41
    findings, so this is the receipt for that fix and the alarm if it regresses.
    """
    hits = [problem for problem in validate(Graph().require()) if MARKER in problem]
    expect(
        not hits,
        f"{len(hits)} shipped consumable(s) are obtainable only by a draw, which was "
        f"fixed in 6ca5cbd8: {hits[:3]}",
    )


@case("acquisition: an id no content declares is refused, not waved through")
def _unknown_id_is_not_green() -> None:
    with _fixture() as graph:
        found = graph.sole_route_blocker("no_such_item_id")
        expect(found is not None, "an undeclared id reads as obtainable; the predicate is vacuous")
        expect(
            found is not None and found[0] == "no_such_item_id",
            f"the refusal does not name what it refused: {found}",
        )


@case("acquisition: a `craft:` cycle and an over-deep chain both TERMINATE")
def _recipe_walk_terminates() -> None:
    """The bounds the walk relies on, proved over authored content rather than asserted.

    `sole_route_blocker` recurses over recipe inputs and nothing in `game/data`
    forbids a cycle or an over-deep chain, so the walk carries a `seen` set of recipe
    ids and a depth cap. Both bounds are on values read from the corpus, never on a
    container the walk grows — that is what makes them terminate, and a mutation that
    drops either one hangs this case rather than failing it.
    """
    with _fixture() as graph:
        found = graph.sole_route_blocker(CYCLE_A)
        expect(found is not None, "a recipe cycle reads as obtainable; the walk waved it through")
        expect("cycle" in found[1], f"the walk did not name the cycle it found: {found}")

        # The depth cap on its own, with no cycle to trip the `seen` guard. The chain
        # is longer than the cap and nothing repeats, so `seen` never fires.
        found = graph.sole_route_blocker(CHAIN_HEAD)
        expect(found is not None, "an over-deep recipe chain reads as obtainable")
        expect(
            "depth cap" in found[1],
            f"the walk did not name the cap it hit: {found}",
        )
