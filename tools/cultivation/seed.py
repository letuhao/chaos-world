"""Bootstrap missing resources; preserve existing authored seeds."""

from __future__ import annotations

import re
from decimal import ROUND_HALF_UP, Decimal

from .. import data
from ..common import REPO_ROOT, ok
from ..realm_power import read_multipliers

# `minf`/`maxf` mirror GDScript's clamp helpers so the Python generator and the
# runtime read the same intent.
minf = min
maxf = max

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


def resource(class_name: str, script: str, lines: list[str]) -> str:
    return (
        f'[gd_resource type="Resource" script_class="{class_name}" load_steps=2 format=3]\n\n'
        f'[ext_resource type="Script" path="{script}" id="1"]\n\n'
        '[resource]\nscript = ExtResource("1")\n' + "\n".join(lines) + "\n"
    )


def run() -> int:
    files: dict[str, str] = {}
    channels: list[tuple[str, int]] = []
    realm_power = read_multipliers()
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
            ("physique", 2.0),
            (("organ_vitality", "muscle_fiber", "bone_density")[index % 3], 1.0),
        ]
        # Profile factors: P is the realm's AUTHORED multiplier from
        # core/realm_power_table.tres, and C = P^0.85, F = P^0.40, T = P^0.55.
        # Previously P was a read of the one power ladder (ADR 0042); that ladder is
        # gone (ADR 0050) and the table replaced it. Before the ladder, this was a
        # private per-tier geometric (base * growth^(local-1)) reaching 601x at R30.
        t_factor = realm_power[index] ** 0.55
        # Quality/integrity targets: Q(R) = 0.40 + 0.015*(R-1), U(R) = 0.45 + 0.015*(R-1)
        quality_target = 0.40 + 0.015 * index
        integrity_target = 0.45 + 0.015 * index
        # Work requirements. These are the prices of the three training verbs, in
        # labour units, where one labour tick is one `cultivate(actor, 1.0)` call.
        # The realm budget is what a cultivator must spend to be ready for the
        # NEXT realm; the two sub-budgets price a full pass of one huyệt and one
        # channel step. They are cut from T, not from (R-1)^1.45, so that reward
        # per unit of labour is constant across the ladder instead of peaking at
        # R9 and collapsing by 15x at R30.
        labour_per_realm = round(40.0 * t_factor)
        work_required = float(labour_per_realm)
        # Round half away from zero so the Python generator and GDScript's
        # roundf() agree; banker's rounding disagrees on exact .5 and produced a
        # one-off mismatch at R24.
        acupoint_work = float(_round_half_up(labour_per_realm / max(1, 4 * (source_index + 1))))
        meridian_work = float(_round_half_up(labour_per_realm / max(1, 4 * (index + 1))))
        # Insight floor: 10 + 6*(R-1) + 2*(R-1)^2
        insight_required = 10.0 + 6.0 * index + 2.0 * index * index
        # Resonance rank (realms 19-30): R19=1, R20=2, ..., R30=12
        resonance_rank = max(0, index - 17) if index >= 18 else 0
        # Breakthrough risk. Comprehension is the entry GATE, so it must not also
        # decide the roll: 0.1 + 0.01*insight_required exceeds the 0.95 clamp
        # from R5 on, which made 26 of 29 attempts certain successes. The realm
        # offers a floor and a ceiling instead; acupoint quality buys certainty
        # between them, so the failure rate stays meaningful (about 20% at R1
        # rising to about 28% at R30) instead of reaching zero.
        chance_base = minf(0.55 + 0.008 * index, 0.80)
        chance_cap = maxf(0.95 - 0.008 * index, 0.70)
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
                # The gate is a labour budget, matching `work_required` so the two authored
                # numbers describe one thing instead of diverging by up to 4.6x.
                f"progress_required = {float(work_required)}",
                # Physique comes from the milestone bonus plus the seed reward, so
                # it must stay below what the ladder actually grants by R.
                f"physique_required = {10.0 + 2.0 * max(0, index - 1)}",
                # The entry gate must be reachable with one realm of training: it is
                # exactly the previous realm's quality target Q(R-1). Anything
                # higher makes the realm unreachable through the public actions,
                # because training caps at the current realm's Q.
                f"quality_required = {0.40 + 0.015 * source_index:.6f}",
                # Q(R)/U(R) are asserted against the exact formula (epsilon 1e-4),
                # so 2dp rounding is not enough: 0.835 would be written as 0.83.
                f"quality_target = {quality_target:.6f}",
                f"integrity_target = {integrity_target:.6f}",
                f"required_meridians = {data._array_literal(required)}",
                f"required_refinement = {max(1, index)}",
                f"refinement_cap = {index + 1}",
                f"integrity_maximum = {100.0 * (1.0 + index * 0.1):.1f}",
                f"rewards = {data._dict_literal(rewards)}",
                # Deliberately NOT emitted: `power_budget`, `capacity_factor`,
                # `throughput_factor`, `technique_factor`. Those four were a second,
                # private power scale; they went with the shared ladder (ADR 0050) and
                # no realm seed carries them. Writing them here would silently
                # resurrect the fields the migration deleted, and the generation
                # validator no longer asks for them.
                # These four are already floats; appending `.0` emitted malformed
                # literals like `118.0.0`, which abort Godot's parser and silently
                # drop every property after it (resonance_rank, channel_training).
                f"work_required = {float(work_required)}",
                f"acupoint_work = {float(acupoint_work)}",
                f"meridian_work = {float(meridian_work)}",
                f"insight_required = {float(insight_required)}",
                f"resonance_rank = {resonance_rank}",
                f"chance_base = {chance_base:.2f}",
                f"chance_cap = {chance_cap:.2f}",
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
