"""Red-path self-tests for the qi gate-ladder guard.

Separate from `audit.py` because a validator is shipped code and a test of it is
not: `audit` is imported by `tools check` on every run, and importing it must not
register test cases. `tools/selftest_cases.py` imports this module for the same
reason it imports the other case modules — one line, so the registration stays
greppable (INC-0016).

## What is asserted, and why both halves

`cultivation mutate` already proves the guard fires on a break, but a gate nobody
has seen red is indistinguishable from a gate that cannot fire (INC-0016), and the
defect this guard exists for was invisible precisely because every test asked
whether the gate was ENFORCED and none asked whether it could be MET. So each case
here asserts one of two independent things, and both are needed:

- the FIXTURE half: a synthetic ladder, invented here and authored to be breakable,
  where each mutation must produce its named finding. Never the shipped corpus —
  a red case sourced from live content declares the rule dead the day somebody
  fixes the content, which is how the acquisition selftest died.
- the CORPUS half: the shipped ladder produces ZERO findings. A rule that fires on
  everything is the same broken guard as one that fires on nothing, and only a
  fixture plus a clean corpus tells them apart.

The fixture builder is shared with `mutate.py` on purpose — one definition of "a
clean synthetic ladder" — but the mutations are written here rather than read from
`mutate.py`'s probe table, so a probe table that silently loses a row cannot make
these cases pass by losing the assertion with it.
"""

from __future__ import annotations

import shutil
from pathlib import Path

from ..selftest import case, expect
from . import audit
from . import ladder as ladder_module
from .mutate import _stage_qi_fixture
from .seed_write_selftest import *  # noqa: F403  registers the DEF-0033 drift cases

# The fixture this module owns. Asserting the shape keeps a fixture that drifts
# into reporting findings from turning these cases into a tautology: if the
# "clean" baseline stopped being clean, every red case below would be proving
# nothing about the rule it names.
CLEAN_BASELINE = "zero findings"


def _fixture_findings(realm_dir, meridian_source, rows, items) -> list[str]:
    return audit.qi_gate_ladder_findings(
        rows, realm_dir=realm_dir, meridian_source=meridian_source, items=items
    )


def _break(realm_dir, realm_id: str, target: str, replacement: str) -> None:
    """Rewrite one line (or adjacent block) of one fixture seed."""
    seed = realm_dir / f"{realm_id}.tres"
    text = seed.read_text(encoding="utf-8")
    expect(text.count(target) == 1, f"fixture {realm_id} must contain exactly one {target!r}")
    seed.write_text(text.replace(target, replacement), encoding="utf-8")


@case("qi gate ladder: the synthetic ladder is CLEAN before anything is broken")
def qi_ladder_fixture_is_clean() -> None:
    realm_dir, meridian_source, rows, items = _stage_qi_fixture()
    try:
        findings = _fixture_findings(realm_dir, meridian_source, rows, items)
        expect(
            findings == [],
            f"a clean synthetic ladder must report {CLEAN_BASELINE}, got: {'; '.join(findings)}",
        )
    finally:
        shutil.rmtree(realm_dir.parent.parent, ignore_errors=True)


@case("qi gate ladder: depth the realm below cannot train IS reported (the shipped defect)")
def qi_ladder_depth_past_the_standing_cap_is_reported() -> None:
    realm_dir, meridian_source, rows, items = _stage_qi_fixture()
    try:
        # st_two's cap is 2. One step past it is a gate no elixir count reaches,
        # which is exactly what shipped: a depth ladder read as a flat `open`
        # demand, `refine_meridian` unreachable, and every test green because
        # every test went through the facade.
        _break(
            realm_dir,
            "st_three",
            "required_channel_refinement = 2",
            "required_channel_refinement = 3",
        )
        findings = _fixture_findings(realm_dir, meridian_source, rows, items)
        expect(
            any("qi_gate_demands_more_depth_than_the_realm_below_offers" in f for f in findings),
            f"a boundary 1 step past the standing cap must be reported: {findings}",
        )
    finally:
        shutil.rmtree(realm_dir.parent.parent, ignore_errors=True)


@case("qi gate ladder: depth demanded below `strengthened` IS reported")
def qi_ladder_depth_needs_a_strengthened_channel() -> None:
    realm_dir, meridian_source, rows, items = _stage_qi_fixture()
    try:
        # `MeridianNetwork.refine_meridian` refuses a channel that is not
        # strengthened, so this depth is unreachable by construction, not by tuning.
        _break(
            realm_dir,
            "st_two",
            'required_channel_state = &"strengthened"',
            'required_channel_state = &"expanded"',
        )
        findings = _fixture_findings(realm_dir, meridian_source, rows, items)
        expect(
            any("qi_gate_depth_below_strengthened" in f for f in findings),
            f"depth demanded below strengthened must be reported: {findings}",
        )
    finally:
        shutil.rmtree(realm_dir.parent.parent, ignore_errors=True)


@case("qi gate ladder: a gate a bare actor already passes IS reported")
def qi_ladder_vacuous_gate_is_reported() -> None:
    realm_dir, meridian_source, rows, items = _stage_qi_fixture()
    try:
        # State and depth are independent halves: lowering one alone leaves the
        # other binding, so this is one edit and not two probes.
        _break(
            realm_dir,
            "st_two",
            'required_channel_state = &"strengthened"\nrequired_channel_refinement = 1',
            'required_channel_state = &"closed"\nrequired_channel_refinement = 0',
        )
        findings = _fixture_findings(realm_dir, meridian_source, rows, items)
        expect(
            any("qi_gate_vacuous_for_a_bare_actor" in f for f in findings),
            f"a gate an actor that has done nothing passes must be reported: {findings}",
        )
    finally:
        shutil.rmtree(realm_dir.parent.parent, ignore_errors=True)


@case("qi gate ladder: a gate with no verb behind it IS reported")
def qi_ladder_missing_item_is_reported() -> None:
    realm_dir, meridian_source, rows, items = _stage_qi_fixture()
    try:
        # `train_channel` refuses on `has_item` before it advances anything, so an
        # unresolvable elixir leaves every boundary above with no verb to press.
        _break(
            realm_dir,
            "st_four",
            'training_item = &"st_four_channel_elixir"',
            'training_item = &"st_absent_elixir"',
        )
        findings = _fixture_findings(realm_dir, meridian_source, rows, items)
        expect(
            any("qi_gate_item_missing" in f for f in findings),
            f"an unresolvable elixir must be reported: {findings}",
        )
    finally:
        shutil.rmtree(realm_dir.parent.parent, ignore_errors=True)


@case("qi gate ladder: a MeridianDefaults with no readable tiers IS reported")
def qi_ladder_unreadable_tier_premise_is_reported() -> None:
    realm_dir, _meridian_source, rows, items = _stage_qi_fixture()
    try:
        # BL-0755. The guard used to read tiers out of `game/data/meridians/*.tres`,
        # which nothing loads, so it graded a corpus the player never receives and a
        # retune of `_build()` would have left it green. It reads `_build()` now; this
        # case is what stops that reader degrading into an empty map, because an empty
        # map raises NO finding and the ladder reads as perfectly clean.
        empty = realm_dir.parent / "empty_defaults.gd"
        empty.write_text("class_name MeridianDefaults\nextends RefCounted\n", encoding="utf-8")
        saved = ladder_module.MERIDIAN_DEFAULTS
        ladder_module.MERIDIAN_DEFAULTS = empty
        try:
            # No `meridian_source`: the module default is the premise under test.
            findings = audit.qi_gate_ladder_findings(rows, realm_dir=realm_dir, items=items)
        finally:
            ladder_module.MERIDIAN_DEFAULTS = saved
        expect(
            any("gate_ladder_premise_unreadable" in f for f in findings),
            f"a MeridianDefaults that no longer declares tiers must be reported: {findings}",
        )
    finally:
        shutil.rmtree(realm_dir.parent.parent, ignore_errors=True)


@case("qi gate ladder: the tiers come from the MeridianDefaults it is given, not a .tres")
def qi_ladder_tiers_follow_the_runtime_source() -> None:
    # THE BL-0755 PROOF. A retune of `_build()` that pushes a channel above the ladder
    # is the defect the old reader was blind to: it graded `game/data/meridians/*.tres`,
    # which nothing loads, so the retune moved the gates and left every finding green.
    # Here the injected source is the only tier table in play, so a channel moved above
    # the ladder must be reported. Nothing in `game/data/meridians` takes part, which is
    # the point: before the fix this case had nothing to aim at.
    realm_dir, meridian_source, rows, items = _stage_qi_fixture()
    try:
        text = Path(meridian_source).read_text(encoding="utf-8")
        expect(
            text.count('_make(&"st_b", "st_b", PRIMARY, 0,') == 1,
            "the fixture must place st_b at tier 0 before this case means anything",
        )
        Path(meridian_source).write_text(
            text.replace(
                '_make(&"st_b", "st_b", PRIMARY, 0,', '_make(&"st_b", "st_b", PRIMARY, 9,'
            ),
            encoding="utf-8",
        )
        findings = _fixture_findings(realm_dir, meridian_source, rows, items)
        expect(
            any("qi_gate_channel_never_unlocks" in f and "st_b" in f for f in findings),
            f"a channel the runtime unlocks above the ladder must be reported: {findings}",
        )
    finally:
        shutil.rmtree(realm_dir.parent.parent, ignore_errors=True)


@case("qi gate ladder: a tier that disagrees between the runtime and the corpus IS reported")
def qi_ladder_meridian_tier_divergence_is_reported() -> None:
    # Two invented dicts, never the shipped pair. The red half must not be sourced from
    # live content: the shipped corpus agrees with the runtime today, and a case that
    # asserted today's agreement goes red the day somebody repairs one side (29b97f04).
    runtime = {"st_a": 0, "st_b": 1, "st_deep": 9}
    findings = audit.meridian_tier_divergence_findings(
        runtime, {"st_a": 0, "st_b": 0, "st_deep": 9}
    )
    expect(
        any("qi_meridian_tier_diverges" in f and "st_b" in f for f in findings),
        f"a meridian unlocking at a different tier in each copy must be reported: {findings}",
    )
    findings = audit.meridian_tier_divergence_findings(
        runtime, {"st_a": 0, "st_b": 1, "st_ghost": 9}
    )
    expect(
        any("qi_meridian_tier_diverges" in f and "st_ghost" in f for f in findings),
        f"a meridian the runtime does not define must be reported: {findings}",
    )
    findings = audit.meridian_tier_divergence_findings(runtime, dict(runtime))
    expect(findings == [], f"two agreeing copies must report nothing, got: {findings}")


@case("qi gate ladder: the SHIPPED ladder reports zero findings")
def qi_ladder_shipped_ladder_is_clean() -> None:
    # The other half, and the only assertion here that reads live content. It can
    # go red only when the ladder BREAKS, never when it is repaired — which is the
    # direction a corpus-sourced red case is not safe in.
    findings = audit.qi_gate_ladder_findings(audit.ladder_realms())
    expect(findings == [], f"the shipped qi ladder must satisfy every gate rule: {findings}")


@case("qi gate ladder: the shipped MeridianDefaults tiers are read AND agree with the corpus")
def qi_ladder_shipped_meridian_tiers_agree() -> None:
    # Two facts in one case, and both can only go red when the world BREAKS. The count
    # first: `meridian_tier_divergence_findings` reports nothing when the runtime map is
    # unreadable, so "the shipped pair agrees" is also true of a reader that read
    # nothing — which is precisely the silent false green BL-0755 was. Then the
    # divergence, so a `.tres` retuned away from `_build()` is loud.
    tiers = ladder_module.meridian_tiers()
    expect(tiers is not None, "MeridianDefaults._build() must still declare its tiers")
    expect(
        len(tiers) == 20,
        f"the runtime declares every meridian, read {len(tiers)}",
    )
    corpus = audit._meridian_tiers(audit.MERIDIAN_DIR)
    findings = audit.meridian_tier_divergence_findings(tiers, corpus)
    expect(
        findings == [],
        f"MeridianDefaults._build() and {audit.MERIDIAN_DIR} must agree: {findings}",
    )
