"""Author the rapid (right-click) art family: one art per element, plus its manual.

DEF-0385's ruling: share 1.0 (pure elemental), magnitude =
`BARE_SWING_MAGNITUDE * ANCHOR_BLOW_SCALE / 12`, cooldown 0.2 (the fight loop's own
5 hits/s clamp), a small stamina cost per hit (nothing is free, AGENTS.md), and each
manual reachable at the realm its element itself opens at (the tier's trial domain).

Deterministic and idempotent: an existing file is never overwritten, so a hand edit to an
art or a manual survives a re-run. Prints what it wrote and what it kept.

Mirrors `tools/generate_qi_items.py`, the sibling one-shot that authored the qi item
family the same way: content generation is a Python decision recorded in a script, never
a hand-typed wave. Run with `uv run python tools/generate_rapid_arts.py`.
"""

import re
from pathlib import Path

ROOT = Path(__file__).parent.parent
TECHNIQUES = ROOT / "game" / "data" / "techniques"
ITEMS = ROOT / "game" / "data" / "items" / "technique"

# `BARE_SWING_MAGNITUDE * ANCHOR_BLOW_SCALE / 12` from `app/combat_boot.gd` and
# `app/fight_loop.gd`, evaluated once and kept as the formula next to it so a retune of
# either constant is a one-line edit here rather than a scattered 13-file sweep.
BARE_SWING_MAGNITUDE = 2.0
ANCHOR_BLOW_SCALE = 1.0 / 5.6
RAPID_TO_HEAVY = 12.0
MAGNITUDE = round(BARE_SWING_MAGNITUDE * ANCHOR_BLOW_SCALE / RAPID_TO_HEAVY, 6)

#: `(element id, ElementDefaults display name, tier)` for all thirteen, in the order
#: `ElementDefaults.all()` builds them: the five base, the five advanced, the triad.
ELEMENTS: tuple[tuple[str, str, int], ...] = (
    ("metal", "Metal", 1),
    ("wood", "Wood", 1),
    ("water", "Water", 1),
    ("fire", "Fire", 1),
    ("earth", "Earth", 1),
    ("lightning", "Lightning", 2),
    ("ice", "Ice", 2),
    ("wind", "Wind", 2),
    ("light", "Light", 2),
    ("dark", "Dark", 2),
    ("void", "Void", 3),
    ("chaos", "Chaos", 3),
    ("time", "Time", 3),
)

#: Where a tier's manual sits: the realm the tier's elements open at, that realm's own
#: trial domain (the source every manual in this family declares), and the LEARN gate.
#:
#: `min_path_realm` is a 1-BASED ladder realm number — the content contract enforces
#: `1..29` — so `1` is Qi Refining itself and the gate compares it against the actor's
#: realm number (the ordinal plus one; the first generation shipped 0/9/18 and the
#: content contract refused the zero).
TIER_PLACEMENT: dict[int, tuple[str, str, int]] = {
    1: ("foundation", "qi_foundation_trial", 1),
    2: ("core_formation", "qi_core_formation_trial", 10),
    3: ("earth_immortal", "qi_earth_immortal_trial", 19),
}


def art_id(element: str) -> str:
    return f"qi_{element}_rapid"


def manual_id(element: str) -> str:
    return f"manual_{element}_rapid"


def art_tres(element: str, name: str, tier: int) -> str:
    realm, _domain, min_realm = TIER_PLACEMENT[tier]
    display = f"LOC_TECHNIQUES_QI_{element.upper()}_RAPID_DISPLAY_NAME"
    description = f"LOC_TECHNIQUES_QI_{element.upper()}_RAPID_DESCRIPTION"
    return (
        '[gd_resource type="Resource" script_class="TechniqueDef" format=3]\n'
        "\n"
        '[ext_resource type="Script" path="res://src/modules/techniques/technique_def.gd"'
        ' id="1_def"]\n'
        "\n"
        "[resource]\n"
        'script = ExtResource("1_def")\n'
        f'id = &"{art_id(element)}"\n'
        f'delivered_by = &"{manual_id(element)}"\n'
        f'display_name = "{display}"\n'
        f'description = "{description}"\n'
        f'tags = Array[StringName]([&"technique", &"{element}"])\n'
        'grade = &"mortal"\n'
        'rarity = &"common"\n'
        f'element = &"{element}"\n'
        'schools = Array[StringName]([&"emitting", &"elemental"])\n'
        "active = true\n"
        "rapid = true\n"
        'path = &"qi_cultivation"\n'
        f'min_path_realm = {{&"qi_cultivation": {min_realm}}}\n'
        "qi_cost = 0\n"
        "stamina_cost = 2.0\n"
        "cooldown = 0.2\n"
        "mastery_rungs = 5\n"
        f"magnitude = {MAGNITUDE}\n"
        "element_share = 1.0\n"
    )


def manual_tres(element: str, name: str, tier: int) -> str:
    realm, domain, _min_realm = TIER_PLACEMENT[tier]
    display = f"LOC_ITEMS_MANUAL_{element.upper()}_RAPID_DISPLAY_NAME"
    return (
        '[gd_resource type="Resource" script_class="ItemDef" load_steps=2 format=3]\n'
        "\n"
        '[ext_resource type="Script" path="res://src/modules/items/item_def.gd"'
        ' id="1_item"]\n'
        "\n"
        "[resource]\n"
        'script = ExtResource("1_item")\n'
        f'id = &"{manual_id(element)}"\n'
        f'display_name = "{display}"\n'
        'category = &"technique"\n'
        'subcategory = &"jade_slip"\n'
        'rarity = &"common"\n'
        f'realm = &"{realm}"\n'
        'grade = &"mortal"\n'
        f'sources = Array[StringName]([&"domain:{domain}"])\n'
    )


def _write(path: Path, text: str, wrote: list[str], kept: list[str]) -> None:
    if path.exists():
        kept.append(path.name)
        return
    path.write_text(text, encoding="utf-8", newline="\n")
    wrote.append(path.name)


#: Where each tier's manuals are PAID: the trial's own warden table. The encounter
#: (`game/data/loot/encounters/loot_<domain>.tres`) binds this table per boss per tier,
#: and `test_domain_route_acquisition` walks exactly that path — a `domain:` source
#: with no entry in the domain's boss tables is an orphan the player can never hold,
#: however deliverable the reachability graph calls it.
WARDEN_TABLE: dict[int, str] = {
    1: "loot_qi_foundation_warden",
    2: "loot_qi_core_formation_warden",
    3: "loot_qi_earth_immortal_warden",
}

TABLE_DIR = ROOT / "game" / "data" / "loot" / "tables"


def _entry_block(entry_id: str, item_id: str) -> str:
    return (
        f'[sub_resource type="Resource" id="{entry_id}"]\n'
        'script = ExtResource("2_entry")\n'
        f'id = &"{entry_id}"\n'
        'kind = &"item"\n'
        f'item_id = &"{item_id}"\n'
        'table_id = &""\n'
        "weight = 1.\n"
        "chance = -1.0\n"
        "guaranteed = false\n"
        "quantity = 1\n"
        'rarity_floor = &"common"\n'
        "\n"
    )


def wire_loot_tables() -> tuple[list[str], list[str]]:
    """Insert one weighted entry per manual into its trial's warden table.

    Idempotent: a table that already pays the manual is left alone, so a re-run is a
    no-op and a hand retune of an entry survives. Only the `entries` array and the
    sub_resources above `[resource]` are touched; `load_steps` counts ext + sub + 1,
    so each added entry bumps it by one.
    """
    wired: list[str] = []
    kept: list[str] = []
    for tier, table_id in sorted(WARDEN_TABLE.items()):
        path = TABLE_DIR / f"{table_id}.tres"
        text = path.read_text(encoding="utf-8")
        added: list[tuple[str, str]] = []
        for element, _name, element_tier in ELEMENTS:
            if element_tier != tier:
                continue
            manual = manual_id(element)
            if f'item_id = &"{manual}"' in text:
                continue
            added.append((f"{table_id.removeprefix('loot_')}_manual_{element}_rapid", manual))
        if not added:
            kept.append(path.name)
            continue
        blocks = "".join(_entry_block(entry_id, item_id) for entry_id, item_id in added)
        text = text.replace("\n[resource]\n", "\n" + blocks + "[resource]\n", 1)
        refs = "".join(f'\tSubResource("{entry_id}"),\n' for entry_id, _item_id in added)
        close = text.rindex("\n])")
        text = text[: close + 1] + refs + text[close + 1 :]
        match = re.search(r"load_steps=(\d+)", text)
        if match:
            text = text.replace(
                f"load_steps={match.group(1)}",
                f"load_steps={int(match.group(1)) + len(added)}",
                1,
            )
        path.write_text(text, encoding="utf-8", newline="\n")
        wired.append(path.name)
    return wired, kept


def main() -> int:
    wrote: list[str] = []
    kept: list[str] = []
    for element, name, tier in ELEMENTS:
        _write(TECHNIQUES / f"{art_id(element)}.tres", art_tres(element, name, tier), wrote, kept)
        _write(ITEMS / f"{manual_id(element)}.tres", manual_tres(element, name, tier), wrote, kept)
    wired, tables_kept = wire_loot_tables()
    print(f"wrote {len(wrote)} file(s), kept {len(kept)} existing")
    for row in wrote:
        print(f"  + {row}")
    print(f"wired {len(wired)} loot table(s), kept {len(tables_kept)} already-paying")
    for row in wired:
        print(f"  ~ {row}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
