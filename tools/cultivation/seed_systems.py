"""Seed the qi_cultivation and mind_cultivation realm contracts.

Mirrors the body-cultivation seed contract (ADR 0023) for the other two major
systems: one `.tres` per realm plus the two consumables, two materials, recipe,
boss, and domain each realm's contract references. Existing authored resources
are never overwritten.
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
        herb = f"{prefix}_{spec['prefix']}_herb"
        core = f"{prefix}_warden_core"
        boss = f"{prefix}_warden"
        domain = f"{prefix}_trial"
        # Channel requirements use the *previous* realm's unlock set: never demand
        # a channel that only unlocks later. Storage tier, by contrast, follows the
        # realm being entered, because that is the vessel cultivated afterwards.
        source_index = max(0, index - 1)
        required = [channel for channel, unlock in CHANNELS if unlock <= source_index]
        storage_capacity = 100.0 * (1.0 + index * 0.25)
        quality = 0.5 + 0.01 * source_index
        files[f"{spec['dir']}/realms/{realm_id}.tres"] = resource(
            spec["class"],
            spec["script"],
            [
                f'id = &"{realm_id}"',
                f'breakthrough_item = &"{pill}"',
                f'training_item = &"{elixir}"',
                f"progress_required = {100.0 * max(1, index)}",
                f"comprehension_required = {10.0 + 2.0 * max(0, index - 1)}",
                f"{_quality_field(spec)} = {quality:.2f}",
                f"{_fill_field(spec)} = 1.0",
                f'{_tier_field(spec)} = &"{tier_for(index, tiers)}"',
                f"required_meridians = {data._array_literal(required)}",
                f'required_channel_state = &"{spec["channel_state"]}"',
                f"channel_refinement_cap = {index + 1}",
                f"{_capacity_field(spec)} = {storage_capacity:.1f}",
                f"rewards = {data._dict_literal([(spec['reward'], 2.0)])}",
            ],
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


def _quality_field(spec: dict) -> str:
    return "dantian_quality_required" if spec["prefix"] == "qi" else "clarity_required"


def _fill_field(spec: dict) -> str:
    return "dantian_fill_required" if spec["prefix"] == "qi" else "sea_fill_required"


def _tier_field(spec: dict) -> str:
    return "dantian_tier" if spec["prefix"] == "qi" else "sea_tier"


def _capacity_field(spec: dict) -> str:
    return "dantian_capacity" if spec["prefix"] == "qi" else "sea_capacity"
