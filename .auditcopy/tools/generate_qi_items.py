"""Generate 90 Qi cultivation items (3 per realm) with recipes, materials, bosses, and domains."""

from pathlib import Path

REALM_DIR = Path(__file__).parent.parent / "game" / "data" / "qi_cultivation" / "realms"
ITEMS_DIR = Path(__file__).parent.parent / "game" / "data" / "items"
RECIPES_DIR = Path(__file__).parent.parent / "game" / "data" / "recipes"
BOSSES_DIR = Path(__file__).parent.parent / "game" / "data" / "bosses"
DOMAINS_DIR = Path(__file__).parent.parent / "game" / "data" / "domains"

TIER_GRADE = {
    "MORTAL": "mortal",
    "SPIRIT": "spirit",
    "IMMORTAL": "immortal",
    "TRANSCENDENT": "divine",
}

REALMS = [
    ("qi_refining", "Qi Refining", "MORTAL"),
    ("foundation", "Foundation Establishment", "MORTAL"),
    ("core_formation", "Core Formation", "MORTAL"),
    ("nascent_soul", "Nascent Soul", "MORTAL"),
    ("spirit_transformation", "Spirit Transformation", "MORTAL"),
    ("void_refinement", "Void Refinement", "MORTAL"),
    ("body_integration", "Body Integration", "MORTAL"),
    ("great_ascension", "Great Ascension", "MORTAL"),
    ("tribulation", "Tribulation Crossing", "MORTAL"),
    ("spirit_condensation", "Spirit Condensation", "SPIRIT"),
    ("spirit_sea", "Spirit Sea", "SPIRIT"),
    ("spirit_palace", "Spirit Palace", "SPIRIT"),
    ("spirit_manifestation", "Spirit Manifestation", "SPIRIT"),
    ("spirit_severing", "Spirit Severing", "SPIRIT"),
    ("spirit_unity", "Spirit Unity", "SPIRIT"),
    ("spirit_domain", "Spirit Domain", "SPIRIT"),
    ("spirit_sovereign", "Spirit Sovereign", "SPIRIT"),
    ("spirit_ascension", "Spirit Ascension", "SPIRIT"),
    ("earth_immortal", "Earth Immortal", "IMMORTAL"),
    ("heaven_immortal", "Heaven Immortal", "IMMORTAL"),
    ("golden_immortal", "Golden Immortal", "IMMORTAL"),
    ("mystic_immortal", "Mystic Immortal", "IMMORTAL"),
    ("true_immortal", "True Immortal", "IMMORTAL"),
    ("primordial_immortal", "Primordial Immortal", "IMMORTAL"),
    ("great_luo", "Great Luo Immortal", "IMMORTAL"),
    ("dao_fruit", "Dao Fruit", "IMMORTAL"),
    ("immortal_sovereign", "Immortal Sovereign", "IMMORTAL"),
    ("transcendent", "Transcendent", "TRANSCENDENT"),
    ("dao_ancestor", "Dao Ancestor", "TRANSCENDENT"),
    ("primordial_origin", "Primordial Origin", "TRANSCENDENT"),
]

PILL_NAMES = {
    "qi_refining": "First Breath Initiation Pill",
    "foundation": "Root Stabilization Pill",
    "core_formation": "Golden Core Condensation Pill",
    "nascent_soul": "Soul Embryo Elixir",
    "spirit_transformation": "Spirit Transformation Pill",
    "void_refinement": "Void Seam Refinement Pill",
    "body_integration": "Integrated Vessel Pill",
    "great_ascension": "Ascendant Compression Elixir",
    "tribulation": "Ninefold Crossing Pill",
    "spirit_condensation": "Refined Spirit Condensation Pill",
    "spirit_sea": "Spirit Tide Elixir",
    "spirit_palace": "Palace Keystone Pill",
    "spirit_manifestation": "Spirit Image Elixir",
    "spirit_severing": "Severance Purification Pill",
    "spirit_unity": "Harmonic Unity Pill",
    "spirit_domain": "Domain Boundary Elixir",
    "spirit_sovereign": "Sovereign Seal Pill",
    "spirit_ascension": "Spirit Ascension Elixir",
    "earth_immortal": "Earth Immortal Foundation Pill",
    "heaven_immortal": "Heaven Pattern Elixir",
    "golden_immortal": "Golden Immortal Tempering Pill",
    "mystic_immortal": "Mystic Law Elixir",
    "true_immortal": "True Immortal Restoration Pill",
    "primordial_immortal": "Primordial Source Elixir",
    "great_luo": "Great Luo Convergence Pill",
    "dao_fruit": "Dao Fruit Ripening Elixir",
    "immortal_sovereign": "Immortal Crown Pill",
    "transcendent": "Transcendent Origin Elixir",
    "dao_ancestor": "Dao Ancestor Fusion Pill",
    "primordial_origin": "Primordial Genesis Elixir",
}

CATALYST_NAMES = {
    "qi_refining": "Ember Vessel Grit",
    "foundation": "Root Binding Sand",
    "core_formation": "Core Lattice Jade",
    "nascent_soul": "Soul Cradle Dew",
    "spirit_transformation": "Transforming Spirit Amber",
    "void_refinement": "Void Suture Silk",
    "body_integration": "Vessel Fusion Ore",
    "great_ascension": "Ascendant Compression Crystal",
    "tribulation": "Crossing Stabilizer",
    "spirit_condensation": "Refined Sea Pearl",
    "spirit_sea": "Tidewall Coral",
    "spirit_palace": "Palace Foundation Jade",
    "spirit_manifestation": "Manifestation Prism",
    "spirit_severing": "Severance Purity Salt",
    "spirit_unity": "Harmonic Vessel Crystal",
    "spirit_domain": "Domain Boundary Ore",
    "spirit_sovereign": "Sovereign Vessel Jade",
    "spirit_ascension": "Ascension Anchor Pearl",
    "earth_immortal": "World Seed Kernel",
    "heaven_immortal": "Celestial Axis Stone",
    "golden_immortal": "Golden Law Matrix",
    "mystic_immortal": "Mystic Spatial Thread",
    "true_immortal": "True Law Heart",
    "primordial_immortal": "Primordial Source Sand",
    "great_luo": "Great Luo Lattice",
    "dao_fruit": "Dao Fruit Pith",
    "immortal_sovereign": "Immortal Sovereign Keystone",
    "transcendent": "Origin World Kernel",
    "dao_ancestor": "Ancestral Law Keystone",
    "primordial_origin": "Genesis Anchor Crystal",
}

ELIXIR_NAMES = {
    "qi_refining": "First Channel Dew",
    "foundation": "Root Circuit Resin",
    "core_formation": "Core Circuit Dew",
    "nascent_soul": "Heart Circuit Resin",
    "spirit_transformation": "Spirit Flow Dew",
    "void_refinement": "Void Channel Resin",
    "body_integration": "Integrated Circuit Dew",
    "great_ascension": "Ascendant Channel Resin",
    "tribulation": "Twelvefold Circuit Dew",
    "spirit_condensation": "Extraordinary Channel Dew",
    "spirit_sea": "Spirit Tide Resin",
    "spirit_palace": "Palace Circuit Dew",
    "spirit_manifestation": "Qiao Channel Dew",
    "spirit_severing": "Qiao Expansion Resin",
    "spirit_unity": "Qiao Tempering Dew",
    "spirit_domain": "Wei Channel Dew",
    "spirit_sovereign": "Wei Expansion Resin",
    "spirit_ascension": "Wei Tempering Dew",
    "earth_immortal": "Earth Resonance Dew",
    "heaven_immortal": "Heaven Resonance Resin",
    "golden_immortal": "Golden Resonance Dew",
    "mystic_immortal": "Mystic Resonance Resin",
    "true_immortal": "True Resonance Dew",
    "primordial_immortal": "Primordial Resonance Resin",
    "great_luo": "Great Luo Resonance Dew",
    "dao_fruit": "Dao Fruit Resonance Resin",
    "immortal_sovereign": "Sovereign Resonance Dew",
    "transcendent": "Origin Circuit Resin",
    "dao_ancestor": "Ancestral Circuit Dew",
    "primordial_origin": "Genesis Circuit Resin",
}


def make_item_tres(item_id, display_name, category, subcategory, grade, sources, desc=""):
    lines = [
        '[gd_resource type="Resource" script_class="ItemDef" load_steps=2 format=3]',
        "",
        '[ext_resource type="Script" path="res://src/modules/items/item_def.gd" id="1_item"]',
        "",
        "[resource]",
        'script = ExtResource("1_item")',
        f'id = &"{item_id}"',
        f'display_name = "{display_name}"',
        f'category = &"{category}"',
        f'subcategory = &"{subcategory}"',
        f'grade = &"{grade}"',
        f"sources = Array[StringName]({sources})",
    ]
    if desc:
        lines.append(f'description = "{desc}"')
    return "\n".join(lines) + "\n"


def make_recipe_tres(recipe_id, display_name, station, inputs, outputs):
    inputs_str = ", ".join(f'&"{i}"' for i in inputs)
    outputs_str = ", ".join(f'&"{o}"' for o in outputs)
    return f"""[gd_resource type="Resource" script_class="RecipeDef" load_steps=2 format=3]

[ext_resource type="Script" path="res://src/modules/items/recipe_def.gd" id="1_recipe"]

[resource]
script = ExtResource("1_recipe")
id = &"{recipe_id}"
display_name = "{display_name}"
station = &"{station}"
inputs = Array[StringName]([{inputs_str}])
outputs = Array[StringName]([{outputs_str}])
"""


def make_boss_tres(boss_id, display_name, domain_id, loot):
    loot_str = ", ".join(f'&"{item}"' for item in loot)
    return f"""[gd_resource type="Resource" script_class="BossDef" load_steps=2 format=3]

[ext_resource type="Script" path="res://src/modules/world/boss_def.gd" id="1_boss"]

[resource]
script = ExtResource("1_boss")
id = &"{boss_id}"
display_name = "{display_name}"
domain_id = &"{domain_id}"
loot = Array[StringName]([{loot_str}])
"""


def make_domain_tres(domain_id, display_name, boss_ids):
    bosses_str = ", ".join(f'&"{b}"' for b in boss_ids)
    return f"""[gd_resource type="Resource" script_class="DomainDef" load_steps=2 format=3]

[ext_resource type="Script" path="res://src/modules/world/domain_def.gd" id="1_domain"]

[resource]
script = ExtResource("1_domain")
id = &"{domain_id}"
display_name = "{display_name}"
boss_ids = Array[StringName]([{bosses_str}])
"""


def main():
    """Emit the qi corpus: five items and three recipes per realm.

    Every write is `if not exists`, so a run is additive only. Measured, not
    assumed: the boss (`qi_<realm>_guardian`) and domain (`qi_<realm>_domain`)
    families this script also writes are ALREADY on disk, so a full run creates
    nothing there. ADR 0096 suspected this script had drifted from the corpus; it
    has not — both families ship.
    """
    # Create directories if needed
    for d in ["consumable", "material"]:
        (ITEMS_DIR / d).mkdir(parents=True, exist_ok=True)
    RECIPES_DIR.mkdir(parents=True, exist_ok=True)
    BOSSES_DIR.mkdir(parents=True, exist_ok=True)
    DOMAINS_DIR.mkdir(parents=True, exist_ok=True)

    # Group realms into 10 domains (3 realms each)
    domains = []
    for i in range(0, 30, 3):
        group = REALMS[i : i + 3]
        domain_id = f"qi_{group[0][0]}_domain"
        domain_name = f"Qi {group[0][1]} Domain"
        domains.append((domain_id, domain_name, group))

    for realm_id, realm_name, tier in REALMS:
        grade = TIER_GRADE[tier]
        domain_idx = (REALMS.index((realm_id, realm_name, tier))) // 3
        domain_id = domains[domain_idx][0]

        # Item IDs
        pill_id = f"qi_{realm_id}_breakthrough_pill"
        catalyst_id = f"qi_{realm_id}_dantian_catalyst"
        elixir_id = f"qi_{realm_id}_meridian_catalyst"
        herb_id = f"qi_{realm_id}_cultivation_herb"
        core_id = f"qi_{realm_id}_guardian_core"
        boss_id = f"qi_{realm_id}_guardian"

        # 1. Breakthrough pill
        pill_path = ITEMS_DIR / "consumable" / f"{pill_id}.tres"
        if not pill_path.exists():
            pill_path.write_text(
                make_item_tres(
                    pill_id,
                    PILL_NAMES[realm_id],
                    "consumable",
                    "pill",
                    grade,
                    f'[&"craft:{pill_id}_recipe"]',
                    f"Breakthrough pill for {realm_name}. Consumed when a valid attempt starts.",
                ),
                encoding="utf-8",
            )
            print(f"  Created {pill_id}")

        # 2. Dantian catalyst: the PRICE of a `cultivate` sitting whose circulation
        # overflows a reservoir the gate already demands be full. It converts the
        # refused qi into dantian quality PAST the next realm's floor, which is roll
        # certainty `cultivate` cannot reach — it stops refining at that floor
        # (ADR 0195). No gate reads it, which is what ADR 0096 required and what
        # `tools/cultivation/audit.py` now enforces.
        cat_path = ITEMS_DIR / "consumable" / f"{catalyst_id}.tres"
        if not cat_path.exists():
            cat_path.write_text(
                make_item_tres(
                    catalyst_id,
                    CATALYST_NAMES[realm_id],
                    "consumable",
                    "tonic",
                    grade,
                    f'[&"craft:{catalyst_id}_recipe"]',
                    (
                        f"Spent on a {realm_name} sitting that overflows a full dantian. The"
                        " overflow becomes dantian quality past the next realm's floor, and"
                        " every gate is met without one."
                    ),
                ),
                encoding="utf-8",
            )
            print(f"  Created {catalyst_id}")

        # 3. Meridian catalyst: pays for one step on a channel the next realm's
        # gate does NOT name, so the channel elixir stays the gate's own price
        # (ADR 0194).
        elixir_path = ITEMS_DIR / "consumable" / f"{elixir_id}.tres"
        if not elixir_path.exists():
            elixir_path.write_text(
                make_item_tres(
                    elixir_id,
                    ELIXIR_NAMES[realm_id],
                    "consumable",
                    "elixir",
                    grade,
                    f'[&"craft:{elixir_id}_recipe"]',
                    (
                        f"Spent to train one {realm_name} meridian the next gate never names,"
                        " for the flow and reservoir width it grants. No gate asks for it."
                    ),
                ),
                encoding="utf-8",
            )
            print(f"  Created {elixir_id}")

        # 4. Cultivation herb (material)
        herb_path = ITEMS_DIR / "material" / f"{herb_id}.tres"
        if not herb_path.exists():
            herb_path.write_text(
                make_item_tres(
                    herb_id,
                    f"{realm_name} Herb",
                    "material",
                    "herb",
                    grade,
                    '[&"gather"]',
                    f"Cultivation herb for {realm_name}. Gathered from the wild.",
                ),
                encoding="utf-8",
            )
            print(f"  Created {herb_id}")

        # 5. Guardian core (material)
        core_path = ITEMS_DIR / "material" / f"{core_id}.tres"
        if not core_path.exists():
            core_path.write_text(
                make_item_tres(
                    core_id,
                    f"{realm_name} Guardian Core",
                    "material",
                    "core",
                    grade,
                    f'[&"boss:{boss_id}"]',
                    f"Guardian core dropped by {realm_name} guardian.",
                ),
                encoding="utf-8",
            )
            print(f"  Created {core_id}")

        # 6. Recipes (3 per realm)
        for recipe_id, inputs, output in [
            (f"{pill_id}_recipe", [core_id, herb_id], pill_id),
            (f"{catalyst_id}_recipe", [core_id, herb_id], catalyst_id),
            (f"{elixir_id}_recipe", [core_id, herb_id], elixir_id),
        ]:
            rpath = RECIPES_DIR / f"{recipe_id}.tres"
            if not rpath.exists():
                rpath.write_text(
                    make_recipe_tres(
                        recipe_id,
                        f"{output.replace('_', ' ').title()} Recipe",
                        "alchemy",
                        inputs,
                        [output],
                    ),
                    encoding="utf-8",
                )
                print(f"  Created {recipe_id}")

        # 7. Boss
        boss_path = BOSSES_DIR / f"{boss_id}.tres"
        if not boss_path.exists():
            boss_path.write_text(
                make_boss_tres(boss_id, f"{realm_name} Guardian", domain_id, [core_id]),
                encoding="utf-8",
            )
            print(f"  Created {boss_id}")

    # 8. Domains
    for domain_id, domain_name, group in domains:
        boss_ids = [f"qi_{r[0]}_guardian" for r in group]
        dpath = DOMAINS_DIR / f"{domain_id}.tres"
        if not dpath.exists():
            dpath.write_text(make_domain_tres(domain_id, domain_name, boss_ids), encoding="utf-8")
            print(f"  Created {domain_id}")

    print("\nDone! Generated all Qi cultivation items.")


if __name__ == "__main__":
    main()
