"""Bootstrap missing resources; preserve existing authored seeds."""

from __future__ import annotations

import re

from .. import data
from ..common import REPO_ROOT, ok

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


def resource(class_name: str, script: str, lines: list[str]) -> str:
    return (
        f'[gd_resource type="Resource" script_class="{class_name}" load_steps=2 format=3]\n\n'
        f'[ext_resource type="Script" path="{script}" id="1"]\n\n'
        '[resource]\nscript = ExtResource("1")\n' + "\n".join(lines) + "\n"
    )


def run() -> int:
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
        herb, core = f"{prefix}_tempering_herb", f"{prefix}_guardian_core"
        boss, domain = f"{prefix}_guardian", f"{prefix}_trial"
        source_index = max(0, index - 1)
        required = [channel for channel, unlock in channels if unlock <= source_index]
        rewards = [
            ("physique", 2.0),
            (("organ_vitality", "muscle_fiber", "bone_density")[index % 3], 1.0),
        ]
        # Profile factors: P = base * growth^(local-1), C = P^0.85, F = P^0.40, T = P^0.55
        tier_base = (1.0, 8.0, 55.0, 330.0)[tier - 1]
        tier_growth = (1.25, 1.22, 1.20, 1.35)[tier - 1]
        local = (
            index + 1
            if tier == 1
            else (index - 8 if tier == 2 else (index - 17 if tier == 3 else index - 26))
        )
        p = tier_base * (tier_growth ** (local - 1))
        c_factor = p**0.85
        f_factor = p**0.40
        t_factor = p**0.55
        # Quality/integrity targets: Q(R) = 0.40 + 0.015*(R-1), U(R) = 0.45 + 0.015*(R-1)
        quality_target = 0.40 + 0.015 * index
        integrity_target = 0.45 + 0.015 * index
        # Work requirements
        work_required = round(100.0 * max(1, index) ** 1.45) if index > 0 else 0.0
        acupoint_work = round(20.0 * (index + 1) ** 1.4)
        meridian_work = round(15.0 * (index + 1) ** 1.4)
        # Insight floor: 10 + 6*(R-1) + 2*(R-1)^2
        insight_required = 10.0 + 6.0 * index + 2.0 * index * index
        # Resonance rank (realms 19-30): R19=1, R20=2, ..., R30=12
        resonance_rank = max(0, index - 17) if index >= 18 else 0
        # Channel training after entry
        channel_training = [ch for ch, unlock in channels if unlock == index + 1]
        files[f"body_cultivation/realms/{realm_id}.tres"] = resource(
            "BodyRealmSeed",
            "res://src/modules/body_cultivation/realm_seed.gd",
            [
                f'id = &"{realm_id}"',
                f'breakthrough_item = &"{pill}"',
                f'strengthening_item = &"{elixir}"',
                f"progress_required = {100.0 * max(1, index)}",
                f"physique_required = {10.0 + 2.0 * max(0, index - 1)}",
                f"quality_required = {0.5 + 0.01 * source_index:.2f}",
                # Q(R)/U(R) are asserted against the exact formula (epsilon 1e-4),
                # so 2dp rounding is not enough: 0.835 would be written as 0.83.
                f"quality_target = {quality_target:.6f}",
                f"integrity_target = {integrity_target:.6f}",
                f"required_meridians = {data._array_literal(required)}",
                f"required_refinement = {max(1, index)}",
                f"refinement_cap = {index + 1}",
                f"integrity_maximum = {100.0 * (1.0 + index * 0.1):.1f}",
                f"rewards = {data._dict_literal(rewards)}",
                f"power_budget = {p:.2f}",
                f"capacity_factor = {c_factor:.2f}",
                f"throughput_factor = {f_factor:.2f}",
                f"technique_factor = {t_factor:.2f}",
                # These four are already floats; appending `.0` emitted malformed
                # literals like `118.0.0`, which abort Godot's parser and silently
                # drop every property after it (resonance_rank, channel_training).
                f"work_required = {float(work_required)}",
                f"acupoint_work = {float(acupoint_work)}",
                f"meridian_work = {float(meridian_work)}",
                f"insight_required = {float(insight_required)}",
                f"resonance_rank = {resonance_rank}",
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
        for suffix, output in (("pill", pill), ("elixir", elixir)):
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
