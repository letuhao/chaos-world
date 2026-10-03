"""Bootstrap missing resources; preserve existing authored seeds.

The realm seeds under `game/data/body_cultivation/realms/` are AUTHORED DATA. This
module is the bootstrap that writes one if it is missing, not the source the balance
is read from - the runtime and the tests read the `.tres`, and `cultivation seed`
never overwrites one. That is a deliberate ruling, and it comes with an obligation:
a bootstrap mirror nobody checks is how 24 of 30 realms ended up carrying a work
budget from a deleted curve. `balance.seed_drift` is that check.
"""

from __future__ import annotations

import re
from decimal import ROUND_HALF_UP, Decimal

from .. import data
from ..common import REPO_ROOT, ToolError, ok
from .ladder import (
    PHYSIQUE_REWARD,
    chance_base,
    chance_cap,
    integrity_maximum,
    integrity_target,
    milestone_physique_ratio,
    physique_required,
    quality_ceiling,
    quality_gate,
)

ROOT = REPO_ROOT / "game" / "data"
PRIMARY = (
    "lung",
    "large_intestine",
    "stomach",
    "spleen",
    "heart",
    "small_intestine",
    "bladder",
    "kidney",
    "pericardium",
    "triple_burner",
    "gallbladder",
    "liver",
)
EXTRAORDINARY = (
    "du_mai",
    "ren_mai",
    "chong_mai",
    "dai_mai",
    "yin_qiao",
    "yang_qiao",
    "yin_wei",
    "yang_wei",
)


def realms() -> list[tuple[str, str, int]]:
    text = (REPO_ROOT / "game/src/core/realm_defaults.gd").read_text(encoding="utf-8")
    return [
        (realm_id, name, {"MORTAL": 1, "SPIRIT": 2, "IMMORTAL": 3, "TRANSCENDENT": 4}[tier])
        for realm_id, name, tier in re.findall(r'_make\(&"([^"]+)", "([^"]+)", (\w+)\)', text)
    ]


def stages() -> list[str]:
    text = (REPO_ROOT / "game/src/modules/body_cultivation/body_path.gd").read_text(
        encoding="utf-8"
    )
    return re.findall(r'^\s*"([^"]+)",$', text, re.M)


def _round_half_up(value: float) -> int:
    """Round half away from zero, matching GDScript `roundf()`.

    Python's `round()` uses banker's rounding, so an exact .5 rounds to even
    while GDScript rounds away from zero. The generator and the runtime assert
    against each other, so they must agree.
    """
    return int(Decimal(str(value)).quantize(Decimal("1"), rounding=ROUND_HALF_UP))


# The authored body labour budget, in labour units per realm, R1..R30.
#
# DEF-0084: this used to be computed as `round(40 * P**0.55)` against the power
# table, which no longer reproduces the shipped seeds - the table tops out at
# 551.46x while these numbers imply a 4328.76x ladder, and 27 of 30 realms
# disagreed. The data is the shipped balance (18k+ tests pass against it), so the
# generator is corrected to match the data, not the reverse.
#
# It is an explicit table rather than a curve on purpose. The growth RATE itself
# grows here: `ln(work/40)/i` climbs from 0.049 at R2 to 0.159 at R30. The best
# log-quadratic fit, `40 * exp(-0.0017 + 0.04402*i + 0.003959*i^2)`, stays within
# 0.69% of every authored value but still rounds to the wrong integer at 5 realms
# (R17, R23, R28, R29, R30), and an approximation that is 0.7% off changes the
# per-realm step ratio the technique ladder is sized against. A designer
# retuning a realm edits one number here; the runtime never recomputes it.
#
# DEF-0130: the DEF-0130 retune left this table untouched. It moved the quality
# ladders, the chance band and the physique floor (all now in `ladder.py`), and
# deleted the three derived lines the seeds used to carry, but every labour budget
# still reads from here. The R1 -> R2 step is +2 and stays +2.
BODY_WORK_REQUIRED: tuple[int, ...] = (
    40,
    42,
    44,
    47,
    51,
    55,
    60,
    66,
    73,
    82,
    92,
    105,
    120,
    138,
    161,
    188,
    222,
    265,
    318,
    385,
    469,
    577,
    714,
    892,
    1123,
    1425,
    1823,
    2350,
    3054,
    4000,
)


def labour_budget(index: int) -> int:
    """The realm's authored labour budget in labour units.

    One labour tick is one `cultivate(actor, 1.0)` call; the budget is what a
    cultivator must spend to be ready for the NEXT realm. `RealmRate.factor`
    is the rate that work converts at; the budget is the price. They are only
    meaningful as a pair, and neither is a magnitude.
    """
    return BODY_WORK_REQUIRED[index]


def resource(class_name: str, script: str, lines: list[str]) -> str:
    return (
        f'[gd_resource type="Resource" script_class="{class_name}" load_steps=2 format=3]\n\n'
        f'[ext_resource type="Script" path="{script}" id="1"]\n\n'
        '[resource]\nscript = ExtResource("1")\n' + "\n".join(lines) + "\n"
    )


def run() -> int:
    # The physique floor is derived from what the ladder grants for itself, and the
    # milestone bonus is a runtime constant. Reading it here means the bootstrap and
    # `BodyProgress` cannot price the floor against different numbers.
    ratio = milestone_physique_ratio()
    if ratio is None:
        raise ToolError(
            "cannot read MILESTONE_PHYSIQUE_RATIO from BodyProgress; the physique floor is"
            " derived from the ladder's own grants and has no defensible default"
        )
    files: dict[str, str] = {}
    channels: list[tuple[str, int]] = []
    for index, channel in enumerate(PRIMARY + EXTRAORDINARY):
        primary = index < 12
        unlock = (index // 4) * 3 if primary else 9 + max(0, (index - 14) // 2) * 3
        channels.append((channel, unlock))
        files[f"meridians/{channel}.tres"] = resource(
            "MeridianDef",
            "res://src/core/meridian_def.gd",
            [
                f'id = &"{channel}"',
                f'display_name = "{data._display_name(channel)}"',
                f'type = &"{"primary" if primary else "extraordinary"}"',
                f"tier = {unlock}",
                "capacity_bonus = 0.05",
                "flow_bonus = 0.1",
                "power_bonus = 0.05",
            ],
        )
    for tier, count, capacity, unlock in (
        ("minor", 36, 50.0, 0),
        ("major", 12, 200.0, 9),
        ("celestial", 12, 800.0, 18),
    ):
        for index in range(count):
            channel = PRIMARY[index % 12] if tier == "minor" else EXTRAORDINARY[index % 8]
            point_id = f"{tier}_{index}"
            point_unlock = 27 if tier == "celestial" and index >= 9 else unlock
            files[f"body_cultivation/acupoints/{point_id}.tres"] = resource(
                "AcupointDef",
                "res://src/modules/body_cultivation/acupoint_def.gd",
                [
                    f'id = &"{point_id}"',
                    (
                        f'display_name = "{data._display_name(channel)}'
                        f' {tier.title()} Node {index + 1:02d}"'
                    ),
                    f'tier = &"{tier}"',
                    f"unlock_index = {point_unlock}",
                    f'meridian_id = &"{channel}"',
                    f"base_capacity = {capacity}",
                ],
            )
    for index, ((realm_id, _name, tier), stage) in enumerate(zip(realms(), stages(), strict=True)):
        prefix = f"body_{realm_id}"
        grade = ("mortal", "spirit", "immortal", "divine")[tier - 1]
        pill, elixir = f"{prefix}_breakthrough_pill", f"{prefix}_channel_elixir"
        # Third consumable role. A failed breakthrough jams a huyệt and tears a
        # channel; without a realm-authored repair item that damage would be
        # permanent, which the design forbids.
        recovery = f"{prefix}_recovery_elixir"
        herb, core = f"{prefix}_tempering_herb", f"{prefix}_guardian_core"
        boss, domain = f"{prefix}_guardian", f"{prefix}_trial"
        source_index = max(0, index - 1)
        required = [channel for channel, unlock in channels if unlock <= source_index]
        rewards = [
            ("physique", PHYSIQUE_REWARD),
            (("organ_vitality", "muscle_fiber", "bone_density")[index % 3], 1.0),
        ]
        # The quality ceiling, the entry gate and the reservoir target. The gate sits
        # a fixed headroom BELOW the ceiling rather than exactly on it: that gap is
        # what a breakthrough roll is buying, and pinning the gate to the ceiling
        # (as `0.40 + 0.015*(R-1)` did) made average huyệt quality at the moment of
        # an attempt a single number on every realm.
        ceiling = quality_ceiling(index)
        gate = quality_gate(index)
        # The labour budget is the PRICE of a breakthrough; `RealmRate.factor`
        # is the RATE it converts at. The two sub-budgets that used to be emitted here
        # (`acupoint_work`, `meridian_work`) are now derived in `BodyRealmSeed` from
        # this one figure, and `work_required` is an alias of the gate below.
        budget = float(labour_budget(index))
        # Insight floor: 10 + 6*(R-1) + 2*(R-1)^2
        insight_required = 10.0 + 6.0 * index + 2.0 * index * index
        # Resonance rank (realms 19-30): R19=1, R20=2, ..., R30=12
        resonance_rank = max(0, index - 17) if index >= 18 else 0
        # Breakthrough risk. Comprehension is the entry GATE, so it must not also
        # decide the roll: 0.1 + 0.01*insight_required exceeds the 0.95 clamp
        # from R5 on, which made 26 of 29 attempts certain successes. The realm
        # offers a floor and a ceiling instead; acupoint quality buys certainty
        # between them, so the failure rate stays meaningful (24% at R1 rising to
        # 32% at R30) instead of reaching zero.
        #
        # The floor DECLINES with depth, which is what makes the ceiling meaningful.
        # A floor that rises into a falling ceiling (the old `0.55 + 0.008i` against
        # `0.95 - 0.008i`) crossed at R26 and left five realms with `base >= cap`.
        # Channel training after entry. The generator names channels with
        # `unlock_index == index`, i.e. the ones that unlock ON entering this
        # realm. The previous `index + 1` named the NEXT realm's channels, which
        # do not exist yet and could not be trained.
        channel_training = [ch for ch, unlock in channels if unlock == index]
        files[f"body_cultivation/realms/{realm_id}.tres"] = resource(
            "BodyRealmSeed",
            "res://src/modules/body_cultivation/realm_seed.gd",
            [
                f'id = &"{realm_id}"',
                f'breakthrough_item = &"{pill}"',
                f'strengthening_item = &"{elixir}"',
                f'recovery_item = &"{recovery}"',
                # The one labour budget. `BodyRealmSeed.work_required` and its two
                # sub-budgets are DERIVED from this, not authored beside it: they were
                # byte-identical copies of the same quantity in all 30 seeds, free to
                # diverge the first time anyone edited one of the three.
                f"progress_required = {budget}",
                # The ladder grants base physique for itself: this realm's reward plus
                # every earlier realm's milestone. The floor sits a margin ABOVE that,
                # so it is a gate the player has to act on rather than a formality the
                # ladder has already paid.
                f"physique_required = {physique_required(index, ratio):.1f}",
                f"quality_required = {gate:.6f}",
                f"quality_target = {ceiling:.6f}",
                f"integrity_target = {integrity_target(index):.6f}",
                f"required_meridians = {data._array_literal(required)}",
                f"required_refinement = {max(1, index)}",
                f"refinement_cap = {index + 1}",
                f"integrity_maximum = {integrity_maximum(index):.1f}",
                f"rewards = {data._dict_literal(rewards)}",
                # Deliberately NOT emitted: `power_budget`, `capacity_factor`,
                # `throughput_factor`, `technique_factor`. Those four were a second,
                # private power scale; they went with the shared ladder (ADR 0050) and
                # no realm seed carries them. Writing them here would silently
                # resurrect the fields the migration deleted, and the generation
                # validator no longer asks for them.
                # These floats are already formatted; appending `.0` emitted malformed
                # literals like `118.0.0`, which abort Godot's parser and silently
                # drop every property after it (resonance_rank, channel_training).
                f"insight_required = {float(insight_required)}",
                f"resonance_rank = {resonance_rank}",
                f"chance_base = {chance_base(index):.4f}",
                f"chance_cap = {chance_cap(index):.4f}",
                f"channel_training = {data._array_literal(channel_training)}",
            ],
        )
        for item_id, category, subtype, source, name, description in (
            (
                pill,
                "consumable",
                "pill",
                f"craft:{prefix}_pill_recipe",
                f"{stage} Tempering Pill",
                (
                    f"Consumed by the Body Cultivation attempt entering {stage};"
                    " no equipment modifier."
                ),
            ),
            (
                elixir,
                "consumable",
                "elixir",
                f"craft:{prefix}_elixir_recipe",
                f"{stage} Channel Elixir",
                (
                    "Restores one damaged channel or trains one channel step"
                    " and its linked acupoint quality."
                ),
            ),
            (
                recovery,
                "consumable",
                "elixir",
                f"craft:{prefix}_recovery_recipe",
                f"{stage} Mending Elixir",
                (
                    "Clears a blocked huyệt and repairs one damaged channel after a"
                    " failed breakthrough."
                ),
            ),
            (
                herb,
                "material",
                "herb",
                "gather",
                f"{stage} Tempering Herb",
                "Gathered tempering reagent.",
            ),
            (
                core,
                "material",
                "beast_core",
                f"boss:{boss}",
                f"{stage} Guardian Core",
                "Boss-only channel catalyst.",
            ),
        ):
            files[f"items/{category}/{item_id}.tres"] = data._tres(
                "item",
                [
                    f'id = &"{item_id}"',
                    f'display_name = "{name}"',
                    f'category = &"{category}"',
                    f'subcategory = &"{subtype}"',
                    f'grade = &"{grade}"',
                    f"sources = {data._array_literal([source])}",
                    f'description = "{description}"',
                ],
            )
        for suffix, output in (
            ("pill", pill),
            ("elixir", elixir),
            ("recovery", recovery),
        ):
            recipe = f"{prefix}_{suffix}_recipe"
            files[f"recipes/{recipe}.tres"] = data._tres(
                "recipe",
                [
                    f'id = &"{recipe}"',
                    f'display_name = "{stage} {suffix.title()} Formula"',
                    'station = &"alchemy"',
                    f"inputs = {data._array_literal([herb, core])}",
                    f"outputs = {data._array_literal([output])}",
                ],
            )
        files[f"bosses/{boss}.tres"] = data._tres(
            "boss",
            [
                f'id = &"{boss}"',
                f'display_name = "{stage} Guardian"',
                f'domain_id = &"{domain}"',
                f"loot = {data._array_literal([core])}",
            ],
        )
        files[f"domains/{domain}.tres"] = data._tres(
            "domain",
            [
                f'id = &"{domain}"',
                f'display_name = "{stage} Trial"',
                f"boss_ids = {data._array_literal([boss])}",
            ],
        )
    created = 0
    for relative, content in sorted(files.items()):
        path = ROOT / relative
        if path.exists():
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        created += 1
    ok(f"created {created} cultivation resources; existing authored resources preserved")
    return 0
