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

from ..selftest import case, expect
from . import audit
from .mutate import _stage_qi_fixture

# The fixture this module owns. Asserting the shape keeps a fixture that drifts
# into reporting findings from turning these cases into a tautology: if the
# "clean" baseline stopped being clean, every red case below would be proving
# nothing about the rule it names.
CLEAN_BASELINE = "zero findings"


def _fixture_findings(realm_dir, meridian_dir, rows, items) -> list[str]:
    return audit.qi_gate_ladder_findings(
        rows, realm_dir=realm_dir, meridian_dir=meridian_dir, items=items
    )


def _break(realm_dir, realm_id: str, target: str, replacement: str) -> None:
    """Rewrite one line (or adjacent block) of one fixture seed."""
    seed = realm_dir / f"{realm_id}.tres"
    text = seed.read_text(encoding="utf-8")
    expect(text.count(target) == 1, f"fixture {realm_id} must contain exactly one {target!r}")
    seed.write_text(text.replace(target, replacement), encoding="utf-8")


@case("qi gate ladder: the synthetic ladder is CLEAN before anything is broken")
def qi_ladder_fixture_is_clean() -> None:
    realm_dir, meridian_dir, rows, items = _stage_qi_fixture()
    try:
        findings = _fixture_findings(realm_dir, meridian_dir, rows, items)
        expect(
            findings == [],
            f"a clean synthetic ladder must report {CLEAN_BASELINE}, got: {'; '.join(findings)}",
        )
    finally:
        shutil.rmtree(realm_dir.parent.parent, ignore_errors=True)


@case("qi gate ladder: depth the realm below cannot train IS reported (the shipped defect)")
def qi_ladder_depth_past_the_standing_cap_is_reported() -> None:
    realm_dir, meridian_dir, rows, items = _stage_qi_fixture()
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
        findings = _fixture_findings(realm_dir, meridian_dir, rows, items)
        expect(
            any("qi_gate_demands_more_depth_than_the_realm_below_offers" in f for f in findings),
            f"a boundary 1 step past the standing cap must be reported: {findings}",
        )
    finally:
        shutil.rmtree(realm_dir.parent.parent, ignore_errors=True)


@case("qi gate ladder: depth demanded below `strengthened` IS reported")
def qi_ladder_depth_needs_a_strengthened_channel() -> None:
    realm_dir, meridian_dir, rows, items = _stage_qi_fixture()
    try:
        # `MeridianNetwork.refine_meridian` refuses a channel that is not
        # strengthened, so this depth is unreachable by construction, not by tuning.
        _break(
            realm_dir,
            "st_two",
            'required_channel_state = &"strengthened"',
            'required_channel_state = &"expanded"',
        )
        findings = _fixture_findings(realm_dir, meridian_dir, rows, items)
        expect(
            any("qi_gate_depth_below_strengthened" in f for f in findings),
            f"depth demanded below strengthened must be reported: {findings}",
        )
    finally:
        shutil.rmtree(realm_dir.parent.parent, ignore_errors=True)


@case("qi gate ladder: a gate a bare actor already passes IS reported")
def qi_ladder_vacuous_gate_is_reported() -> None:
    realm_dir, meridian_dir, rows, items = _stage_qi_fixture()
    try:
        # State and depth are independent halves: lowering one alone leaves the
        # other binding, so this is one edit and not two probes.
        _break(
            realm_dir,
            "st_two",
            'required_channel_state = &"strengthened"\nrequired_channel_refinement = 1',
            'required_channel_state = &"closed"\nrequired_channel_refinement = 0',
        )
        findings = _fixture_findings(realm_dir, meridian_dir, rows, items)
        expect(
            any("qi_gate_vacuous_for_a_bare_actor" in f for f in findings),
            f"a gate an actor that has done nothing passes must be reported: {findings}",
        )
    finally:
        shutil.rmtree(realm_dir.parent.parent, ignore_errors=True)


@case("qi gate ladder: a gate with no verb behind it IS reported")
def qi_ladder_missing_item_is_reported() -> None:
    realm_dir, meridian_dir, rows, items = _stage_qi_fixture()
    try:
        # `train_channel` refuses on `has_item` before it advances anything, so an
        # unresolvable elixir leaves every boundary above with no verb to press.
        _break(
            realm_dir,
            "st_four",
            'training_item = &"st_four_channel_elixir"',
            'training_item = &"st_absent_elixir"',
        )
        findings = _fixture_findings(realm_dir, meridian_dir, rows, items)
        expect(
            any("qi_gate_item_missing" in f for f in findings),
            f"an unresolvable elixir must be reported: {findings}",
        )
    finally:
        shutil.rmtree(realm_dir.parent.parent, ignore_errors=True)


@case("qi gate ladder: the SHIPPED ladder reports zero findings")
def qi_ladder_shipped_ladder_is_clean() -> None:
    # The other half, and the only assertion here that reads live content. It can
    # go red only when the ladder BREAKS, never when it is repaired — which is the
    # direction a corpus-sourced red case is not safe in.
    findings = audit.qi_gate_ladder_findings(audit.ladder_realms())
    expect(findings == [], f"the shipped qi ladder must satisfy every gate rule: {findings}")
