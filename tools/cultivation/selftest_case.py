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
        # BL-0272. The loader reads `game/data/meridians/*.tres` through its own `DIR`
        # constant; a loader that stops declaring one loads nothing, and an empty map
        # raises NO finding — the ladder would read as perfectly clean. This case is
        # what stops that silent false green.
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


@case("qi gate ladder: the tiers come from the corpus the MeridianDefaults loader reads")
def qi_ladder_tiers_follow_the_runtime_source() -> None:
    # THE BL-0272 PROOF. A retune of the loaded corpus that pushes a channel above the
    # ladder is the defect the old reader was blind to: it graded
    # `game/data/meridians/*.tres` while `_build()` hardcoded its own list, so the
    # retune moved the gates and left every finding green. Here the injected corpus is
    # the only tier table in play, so a channel moved above the ladder must be reported.
    realm_dir, meridian_source, rows, items = _stage_qi_fixture()
    try:
        corpus = ladder_module.meridian_loader_dir(meridian_source)
        expect(corpus is not None, "the fixture loader must declare a DIR to aim at")
        tres = corpus / "st_b.tres"
        text = tres.read_text(encoding="utf-8")
        expect(
            text.count("tier = 0") == 1,
            "the fixture must place st_b at tier 0 before this case means anything",
        )
        tres.write_text(text.replace("tier = 0", "tier = 9"), encoding="utf-8")
        findings = _fixture_findings(realm_dir, meridian_source, rows, items)
        expect(
            any("qi_gate_channel_never_unlocks" in f and "st_b" in f for f in findings),
            f"a channel the runtime unlocks above the ladder must be reported: {findings}",
        )
    finally:
        shutil.rmtree(realm_dir.parent.parent, ignore_errors=True)


@case("qi gate ladder: a loader pointed away from the graded corpus IS reported")
def qi_ladder_meridian_loader_binding_is_reported() -> None:
    # Synthetic directories, never the shipped pair. The red half must not be sourced
    # from live content: the shipped loader points at the shipped corpus today, and a
    # case that asserted today's agreement goes red the day somebody moves either.
    mismatched = audit.meridian_loader_findings(Path("/tmp/elsewhere"), Path("/tmp/corpus"))
    expect(
        any("qi_meridian_loader_misdirected" in f for f in mismatched),
        f"a loader reading a different tree must be reported: {mismatched}",
    )
    missing = audit.meridian_loader_findings(None, Path("/tmp/corpus"))
    expect(
        any("qi_meridian_loader_unreadable" in f for f in missing),
        f"a loader that declares no DIR must be reported: {missing}",
    )
    agreeing = audit.meridian_loader_findings(Path("/tmp/corpus"), Path("/tmp/corpus"))
    expect(agreeing == [], f"a loader bound to the graded corpus reports nothing, got: {agreeing}")


@case("qi gate ladder: the SHIPPED ladder reports zero findings")
def qi_ladder_shipped_ladder_is_clean() -> None:
    # The other half, and the only assertion here that reads live content. It can
    # go red only when the ladder BREAKS, never when it is repaired — which is the
    # direction a corpus-sourced red case is not safe in.
    findings = audit.qi_gate_ladder_findings(audit.ladder_realms())
    expect(findings == [], f"the shipped qi ladder must satisfy every gate rule: {findings}")


@case("qi gate ladder: the shipped MeridianDefaults loads AND is bound to the graded corpus")
def qi_ladder_shipped_meridian_tiers_agree() -> None:
    # Three facts, all of which can only go red when the world BREAKS. The count
    # first: `meridian_tiers` answers None for an unreadable loader and the audit
    # skips the count, so "the shipped set is complete" is also true of a reader that
    # read nothing — precisely the silent false green BL-0755 was. Then the binding:
    # the loader's own DIR must be the tree the audit grades. Then the single-source
    # claim itself: the data lives in the files, never re-hardcoded in the loader.
    tiers = ladder_module.meridian_tiers()
    expect(tiers is not None, "MeridianDefaults must declare a readable DIR")
    expect(len(tiers) == 20, f"the loader reads every meridian, read {len(tiers)}")
    findings = audit.meridian_loader_findings(
        ladder_module.meridian_loader_dir(), audit.MERIDIAN_DIR
    )
    expect(findings == [], f"the loader must be bound to {audit.MERIDIAN_DIR}: {findings}")
    text = ladder_module.MERIDIAN_DEFAULTS.read_text(encoding="utf-8", errors="replace")
    expect("_make(" not in text, "the loader must not re-hardcode its own data (BL-0272)")
