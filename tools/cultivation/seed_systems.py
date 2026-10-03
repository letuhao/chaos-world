"""Seed the qi_cultivation and mind_cultivation realm contracts.

Mirrors the body-cultivation seed contract (ADR 0023) for the other two major
systems: one `.tres` per realm plus the consumables, materials, recipe, boss,
and domain each realm's contract references. Existing authored resources are
never overwritten.
"""

from __future__ import annotations

import re

from .. import data
from ..common import REPO_ROOT, ok

ROOT = REPO_ROOT / "game" / "data"
TIER_GRADE = ("mortal", "spirit", "immortal", "divine")

# Meridian unlock index, mirroring MeridianDefaults in core.
CHANNELS = (
    ("lung", 0),
    ("large_intestine", 0),
    ("stomach", 0),
    ("spleen", 0),
    ("heart", 3),
    ("small_intestine", 3),
    ("bladder", 3),
    ("kidney", 3),
    ("pericardium", 6),
    ("triple_burner", 6),
    ("gallbladder", 6),
    ("liver", 6),
    ("du_mai", 9),
    ("ren_mai", 9),
    ("chong_mai", 9),
    ("dai_mai", 9),
    ("yin_qiao", 12),
    ("yang_qiao", 12),
    ("yin_wei", 15),
    ("yang_wei", 15),
)

# Qi stores in a dantian that opens across the first two tiers; the mind keeps a
# sea of consciousness (ADR 0014/0016).
QI_TIERS = ((0, "lower"), (9, "middle"), (18, "upper"))
MIND_TIERS = ((0, "shallow"), (9, "deep"), (18, "vast"))

SYSTEMS = {
    "qi": {
        "dir": "qi_cultivation",
        "class": "QiRealmSeed",
        "script": "res://src/modules/qi_cultivation/realm_seed.gd",
        "path": "qi_cultivation/qi_path.gd",
        "prefix": "qi",
        "pill_noun": "Refinement Pill",
        "elixir_noun": "Channel Elixir",
        "herb_noun": "Qi Herb",
        "core_noun": "Warden Core",
        "tiers": QI_TIERS,
        "channel_state": "open",
        "reward": "spirit",
    },
    "mind": {
        "dir": "mind_cultivation",
        "class": "MindRealmSeed",
        "script": "res://src/modules/mind_cultivation/realm_seed.gd",
        "path": "mind_cultivation/mind_path.gd",
        "prefix": "mind",
        "pill_noun": "Insight Pill",
        "elixir_noun": "Lucidity Elixir",
        "herb_noun": "Mind Herb",
        "core_noun": "Oracle Core",
        "tiers": MIND_TIERS,
        "channel_state": "strengthened",
        "reward": "will",
    },
}


def realms() -> list[tuple[str, str, int]]:
    text = (REPO_ROOT / "game/src/core/realm_defaults.gd").read_text(encoding="utf-8")
    return [
        (realm_id, name, {"MORTAL": 1, "SPIRIT": 2, "IMMORTAL": 3, "TRANSCENDENT": 4}[tier])
        for realm_id, name, tier in re.findall(r'_make\(&"([^"]+)", "([^"]+)", (\w+)\)', text)
    ]


def stages(path: str) -> list[str]:
    text = (REPO_ROOT / "game/src/modules" / path).read_text(encoding="utf-8")
    return re.findall(r'^\s*"([^"]+)",$', text, re.M)


def tier_for(index: int, tiers: tuple[tuple[int, str], ...]) -> str:
    chosen = tiers[0][1]
    for unlock, name in tiers:
        if index >= unlock:
            chosen = name
    return chosen


# DEF-0084: the qi and mind seeds drifted from this generator. The authored
# `.tres` files are the shipped balance, so the formulas below are corrected to
# reproduce them exactly rather than the other way round.
#
# The qi ladder is flat across the first step in two independent fields:
# `progress_required` is 100 at both R1 and R2, and `dantian_quality_required`
# is 0.50 at both. The `max(0, index - 1)` clamp is what encodes that flat, and
# dropping it silently shifts every qi realm by one step of the ladder.
def qi_progress(index: int) -> float:
    """qi `progress_required`: exactly linear, 100 labour units per realm."""
    return 100.0 * max(1, index)


def qi_comprehension(index: int) -> float:
    """qi `comprehension_required`: +2 per realm, flat across the R1->R2 step."""
    return 10.0 + 2.0 * max(0, index - 1)


def qi_dantian_quality(index: int) -> float:
    """qi `dantian_quality_required`: +0.01 per realm, flat across R1->R2."""
    return 0.50 + 0.01 * max(0, index - 1)


def mind_comprehension(index: int) -> float:
    """mind `comprehension_required` == body `insight_required`: 10 + 6i + 2i^2."""
    return 10.0 + 6.0 * index + 2.0 * index * index


def resource(class_name: str, script: str, lines: list[str]) -> str:
    return (
        f'[gd_resource type="Resource" script_class="{class_name}" load_steps=2 format=3]\n\n'
        f'[ext_resource type="Script" path="{script}" id="1"]\n\n'
        '[resource]\nscript = ExtResource("1")\n' + "\n".join(lines) + "\n"
    )


def run() -> int:
    files: dict[str, str] = {}
    for key, spec in SYSTEMS.items():
        _seed_system(files, key, spec)
    created = 0
    for relative, content in sorted(files.items()):
        path = ROOT / relative
        if path.exists():
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        created += 1
    ok(f"created {created} qi/mind cultivation resources; existing resources preserved")
    return 0


def _seed_system(files: dict[str, str], key: str, spec: dict) -> None:
    ladder = realms()
    names = stages(spec["path"])
    tiers = spec["tiers"]
    for index, ((realm_id, _name, tier), stage) in enumerate(zip(ladder, names, strict=True)):
        prefix = f"{spec['prefix']}_{realm_id}"
        grade = TIER_GRADE[tier - 1]
        pill = f"{prefix}_breakthrough_pill"
        elixir = f"{prefix}_channel_elixir"
        sea_catalyst = f"{prefix}_sea_catalyst"
        recovery = f"{prefix}_recovery_elixir"
        herb = f"{prefix}_{spec['prefix']}_herb"
        core = f"{prefix}_warden_core"
        boss = f"{prefix}_warden"
        domain = f"{prefix}_trial"
        # Channel requirements use the *previous* realm's unlock set: never demand
        # a channel that only unlocks later. Storage tier, by contrast, follows the
        # realm being entered, because that is the vessel cultivated afterwards.
        source_index = max(0, index - 1)
        required = [channel for channel, unlock in CHANNELS if unlock <= source_index]
        # The storage vessel grows by a quarter of its base capacity per realm and
        # is authored identically for the dantian and the sea, so both systems read
        # the same expression.
        storage_capacity = 100.0 * (1.0 + index * 0.25)
        clarity_target = 0.40 + 0.015 * index
        purity_target = 0.45 + 0.015 * index
        comprehension_floor = mind_comprehension(index)
        lines = [
            f'id = &"{realm_id}"',
            f'breakthrough_item = &"{pill}"',
            f'training_item = &"{elixir}"',
        ]
        if spec["prefix"] == "mind":
            # Only the mind cultivates a sea of consciousness, so only the mind
            # carries a sea catalyst. QiRealmSeed has no such field; writing one
            # would invent a property the resource does not have.
            lines.append(f'sea_catalyst = &"{sea_catalyst}"')
        # Both systems author a recovery item: a failed attempt must stay
        # repairable through content (ADR 0031).
        lines.append(f'recovery_item = &"{recovery}"')
        if spec["prefix"] == "qi":
            # qi's ladder is linear where the mind's is not. See the helpers
            # above for why the clamps are there.
            lines.append(f"progress_required = {qi_progress(index):.1f}")
            lines.append(f"comprehension_required = {qi_comprehension(index):.1f}")
            lines.append(f"dantian_quality_required = {qi_dantian_quality(index):.2f}")
            lines.append("dantian_fill_required = 1.0")
            lines.append(f'dantian_tier = &"{tier_for(index, tiers)}"')
            lines.append(f"required_meridians = {data._array_literal(required)}")
            lines.append(f'required_channel_state = &"{spec["channel_state"]}"')
            lines.append(f"channel_refinement_cap = {index + 1}")
            lines.append(f"dantian_capacity = {storage_capacity:.1f}")
            lines.append(f"rewards = {data._dict_literal([(spec['reward'], 2.0)])}")
        else:
            # The mind keeps the accelerating ladders: work grows at i^1.45, and
            # comprehension is the quadratic 10 + 6i + 2i^2 whose insight floor is
            # exactly half of it.
            cultivation_work = round(100.0 * max(1, index) ** 1.45)
            sea_work = round(20.0 * (index + 1) ** 1.4)
            meridian_work = round(15.0 * (index + 1) ** 1.4)
            lines.extend(
                [
                    f"progress_required = {cultivation_work}.0",
                    f"comprehension_required = {comprehension_floor:.1f}",
                    f"clarity_required = {clarity_target:.2f}",
                    f"purity_required = {purity_target:.2f}",
                    "sea_fill_required = 1.0",
                    f'sea_tier = &"{tier_for(index, tiers)}"',
                    f"required_meridians = {data._array_literal(required)}",
                    f'required_channel_state = &"{spec["channel_state"]}"',
                    f"channel_refinement_cap = {index + 1}",
                    f"sea_capacity = {storage_capacity:.1f}",
                    f"sea_milestone_work = {sea_work}.0",
                    f"meridian_milestone_work = {meridian_work}.0",
                    f"insight_required = {comprehension_floor * 0.5:.1f}",
                    f"resonance_required = {max(0, index - 17)}",
                    f"rewards = {data._dict_literal([(spec['reward'], 2.0)])}",
                ]
            )
        files[f"{spec['dir']}/realms/{realm_id}.tres"] = resource(
            spec["class"], spec["script"], lines
        )
        for item_id, category, subtype, source, name, description in (
            (
                pill,
                "consumable",
                "pill",
                f"craft:{prefix}_pill_recipe",
                f"{stage} {spec['pill_noun']}",
                f"Consumed by the {spec['prefix'].title()} Cultivation attempt "
                f"entering {stage}; no equipment modifier.",
            ),
            (
                elixir,
                "consumable",
                "elixir",
                f"craft:{prefix}_elixir_recipe",
                f"{stage} {spec['elixir_noun']}",
                "Advances one meridian a step, or deepens a strengthened channel.",
            ),
            (
                sea_catalyst,
                "consumable",
                "tonic",
                f"craft:{prefix}_sea_recipe",
                f"{stage} Sea Catalyst",
                "Strengthens the sea of consciousness toward the realm's targets.",
            ),
            (
                herb,
                "material",
                "herb",
                "gather",
                f"{stage} {spec['herb_noun']}",
                "Gathered reagent for the realm's elixir.",
            ),
            (
                core,
                "material",
                "beast_core",
                f"boss:{boss}",
                f"{stage} {spec['core_noun']}",
                "Boss-only catalyst for the realm's pill.",
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
        for suffix, output in (("pill", pill), ("elixir", elixir), ("sea", sea_catalyst)):
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
                f'display_name = "{stage} Warden"',
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
