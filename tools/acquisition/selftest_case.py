"""Red-path self-tests for the DEF-0210 sole-route rule.

Separate from `tools/acquisition/validate.py` because a validator is shipped code
and a test of it is not: `validate.py` is imported by `tools check` on every run,
and importing it must not register test cases. `tools/selftest_cases.py` imports
this module for the same reason it imports the other case modules — one line, so
the registration stays greppable (INC-0016).

Every case here asserts that the rule still goes **RED**, or that its own loop guard
still fires. "The validator passes on today's tree" is what `tools check` already
does and proves nothing; what matters is that it fails when the world is broken.
"""

from __future__ import annotations

from ..selftest import case, expect
from .chain import MAX_RECIPE_DEPTH, Graph
from .validate import validate

# A reagent the shipped corpus has already closed (fe10aa17 guaranteed the nesting
# entry of its pool) and a reagent it has not. The pair is the control: a predicate
# that answered `None` for everything would satisfy the red case on its own.
CLOSED_REAGENT = "qi_dao_ancestor_guardian_core"
SOLE_ROUTED_REAGENT = "qi_qi_refining_cultivation_herb"
SOLE_ROUTED_CONSUMABLE = "qi_qi_refining_recovery_elixir"
MARKER = "is obtainable only by a draw"


@case("acquisition: a realm seed consumable with no unconditional route is NAMED")
def _sole_route_consumable_is_named() -> None:
    graph = Graph().require()
    problems = [problem for problem in validate(graph) if MARKER in problem]
    expect(
        bool(problems),
        f"no '{MARKER}' problem: the sole-route rule has stopped firing",
    )
    hits = [problem for problem in problems if SOLE_ROUTED_REAGENT in problem]
    expect(
        len(hits) == 1,
        f"expected exactly one problem naming {SOLE_ROUTED_REAGENT}, got {len(hits)}",
    )
    expect(
        SOLE_ROUTED_CONSUMABLE in hits[0],
        f"the problem names the blocker but not the consumable it blocks: {hits[0]}",
    )
    expect(
        "cleared band grants no second run" in hits[0],
        f"the problem does not name the hazard it exists for: {hits[0]}",
    )


@case("acquisition: an already-guaranteed reagent is NOT reported as sole-routed")
def _closed_reagent_is_not_reported() -> None:
    graph = Graph().require()
    expect(
        graph.sole_route_blocker(CLOSED_REAGENT) is None,
        f"{CLOSED_REAGENT} is reported sole-routed although its pool entry is "
        f"guaranteed; the rule over-reports",
    )
    expect(
        bool(graph.delivers_unconditionally(CLOSED_REAGENT)),
        f"{CLOSED_REAGENT} has no guaranteed delivery, so the control is not a control",
    )


@case("acquisition: an id no content declares is refused, not waved through")
def _unknown_id_is_not_green() -> None:
    graph = Graph().require()
    found = graph.sole_route_blocker("no_such_item_id")
    expect(found is not None, "an undeclared id reads as obtainable; the predicate is vacuous")
    expect(
        found is not None and found[0] == "no_such_item_id",
        f"the refusal does not name what it refused: {found}",
    )


@case("acquisition: a `craft:` cycle terminates instead of recursing forever")
def _recipe_cycle_terminates() -> None:
    """The bound the walk relies on, proved rather than asserted in a comment.

    `sole_route_blocker` recurses over recipe inputs and nothing in `game/data`
    forbids a cycle, so the walk carries a `seen` set of recipe ids and a depth cap.
    This case installs a two-recipe cycle over a real `Graph` — the corpus is never
    edited — and requires the call to return. An uncapped walk over `a -> b -> a`
    never returns, which is the INC-0002 shape.
    """
    graph = Graph().require()
    recipes = {"cyc_a": ("cyc_b",), "cyc_b": ("cyc_a",)}
    graph._craft_recipe = lambda item_id: item_id if item_id in recipes else ""  # noqa: SLF001
    graph._reagents = lambda recipe_id: recipes.get(recipe_id, ())  # noqa: SLF001
    found = graph.sole_route_blocker("cyc_a")
    expect(found is not None, "a recipe cycle reads as obtainable; the walk waved it through")
    expect("cycle" in found[1], f"the walk did not name the cycle it found: {found}")

    # And the depth cap on its own, with no cycle to trip the `seen` guard. The
    # chain is longer than the cap and nothing repeats, so `seen` never fires.
    chain = {f"deep_{index}": (f"deep_{index + 1}",) for index in range(MAX_RECIPE_DEPTH + 4)}
    graph._craft_recipe = lambda item_id: item_id if item_id in chain else ""  # noqa: SLF001
    graph._reagents = lambda recipe_id: chain.get(recipe_id, ())  # noqa: SLF001
    found = graph.sole_route_blocker("deep_0")
    expect(found is not None, "an over-deep recipe chain reads as obtainable")
    expect("depth cap" in found[1], f"the walk did not name the cap it hit: {found}")
