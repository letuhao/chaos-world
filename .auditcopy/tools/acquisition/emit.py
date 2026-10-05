"""Text for the loot tables and encounters a body trial is made of.

`.tres` is editor-owned and order-sensitive, so this writes the same shape the
shipped content already uses rather than inventing one: a header, the scripts it
needs, one `sub_resource` per entry, then the `[resource]` block. Nothing here
reads content; it is a formatter for the shapes `design.py` decides.
"""

from __future__ import annotations

from . import design

TABLE_SCRIPT = "res://src/modules/loot/loot_table_def.gd"
ENTRY_SCRIPT = "res://src/modules/loot/loot_entry.gd"
ENCOUNTER_SCRIPT = "res://src/modules/loot/loot_encounter_def.gd"
TIER_SCRIPT = "res://src/modules/loot/loot_tier.gd"


def name(value: str) -> str:
    return f'&"{value}"'


def string_array(values: tuple[str, ...] | list[str]) -> str:
    return "Array[StringName]([" + ", ".join(name(value) for value in values) + "])"


def dictionary_array(entries: list[dict]) -> str:
    """One inline `{key: value}` per binding, on its own line.

    A trailing comma on the last binding is what the shipped content writes, and
    Godot's variant parser accepts it, so the generated shape matches by reading
    rather than by luck.
    """
    lines = [
        "\t{"
        + ", ".join(
            f'"{key}": {name(value) if isinstance(value, str) else value}'
            for key, value in entry.items()
        )
        + "},"
        for entry in entries
    ]
    return "Array[Dictionary]([\n" + "\n".join(lines) + "\n])"


def float_text(value: float) -> str:
    """A float literal that stays a float when read back.

    `40` would load as an int, and the shipped content writes `100.0`, so a
    generated `vitality` that reads back as an int is a shape difference a reader
    would trip over.

    **NOT `%g`.** `%g` switches to scientific notation at 1e6 and trims to six
    significant digits, and ADR 0197's vitality runs to `25 * 75 * 551.46` = 1033987.5
    at R30 -- so `%g` emitted `1.03399e+06`, which is a DIFFERENT number AND a shape
    no shipped `.tres` uses. A boss's pool is read by a parser and a test, not by
    eyeball, so losing four significant digits of it is silent corruption.
    """
    text = f"{value:.10f}".rstrip("0")
    return text if "." in text else f"{text}.0"


class Entry:
    """One authored `LootEntry`, in the two shapes the format allows.

    A weighted item entry carries `chance = -1.0`, which is `LootEntry.NO_CHANCE`:
    the sentinel that keeps an entry out of the independent Bernoulli pass. A
    guaranteed entry must declare no chance at all, which the loot validator
    rejects, and the sentinel is the only value that is not a probability.
    """

    def __init__(  # noqa: PLR0913  the entry format has seven independent fields
        self,
        entry_id: str,
        *,
        item_id: str = "",
        table_id: str = "",
        guaranteed: bool = False,
        weight: float = 1.0,
        quantity: int = 1,
        quantity_max: int = 0,
        rarity_floor: str = "",
    ) -> None:
        self.id = entry_id
        self.item_id = item_id
        self.table_id = table_id
        self.guaranteed = guaranteed
        self.weight = weight
        self.quantity = quantity
        self.quantity_max = quantity_max
        self.rarity_floor = rarity_floor

    def body(self, resource_id: str) -> str:
        fields = [
            'script = ExtResource("2_entry")',
            f"id = {name(self.id)}",
            f'kind = &"{"table" if self.table_id else "item"}"',
            f"item_id = {name(self.item_id)}",
            f"table_id = {name(self.table_id)}",
            f"weight = {float_text(self.weight)}",
            "chance = -1.0",
            f"guaranteed = {str(self.guaranteed).lower()}",
            f"quantity = {self.quantity}",
        ]
        if self.quantity_max:
            fields.append(f"quantity_max = {self.quantity_max}")
        fields.append(f"rarity_floor = {name(self.rarity_floor)}")
        joined = "\n".join(fields)
        # A blank line after each sub_resource, because that is the shape the
        # shipped tables read with. Generated content nobody can diff against the
        # authored content is content nobody reviews.
        return f'[sub_resource type="Resource" id="{resource_id}"]\n{joined}\n\n'


def table(
    table_id: str,
    display_name: str,
    entries: list[Entry],
    *,
    realm: str = "",
    rarity: str = "",
    draws: int = design.DRAWS,
    allow_empty: bool = design.ALLOW_EMPTY,
) -> str:
    """A `LootTableDef` whose entries keep the order they were given.

    `realm` and `rarity` are left empty on a boss's own table so the drop context
    stays the band's, and declared on a realm pool so its items roll at their own
    realm instead of the trial's.

    **`rolls` is derived, never assumed.** A table with no weighted entry draws
    nothing it could pick, and `LootValidator` rejects exactly that: `rolls > 0`
    with a total weighted weight of zero is "draws 1 roll(s) but its weighted
    weights sum to 0.0000". A catalyst-only pool is the case that reaches it —
    every entry guaranteed, so `weighted_entries()` is empty — and it is the same
    content the shipped pools already carry as `rolls = 0`. Writing `design.DRAWS`
    unconditionally would make the generator emit a table the validator refuses,
    which is the one direction a generator must never be wrong in. Guaranteed and
    independent entries are unaffected: they resolve on their own pass.
    """
    # `LootEntry.is_weighted()` is `not guaranteed and chance < 0.0`, and every
    # entry this module writes carries the `NO_CHANCE` sentinel, so a weighted entry
    # is exactly a non-guaranteed one.
    has_weighted = any(not entry.guaranteed for entry in entries)
    effective_draws = draws if has_weighted else 0
    sub_resources = "".join(entry.body(f"entry_{index}") for index, entry in enumerate(entries))
    refs = ",\n".join(f'\tSubResource("entry_{index}")' for index in range(len(entries)))
    listed = f"Array[LootEntry]([\n{refs}\n])" if entries else "Array[LootEntry]([])"
    return (
        '[gd_resource type="Resource" script_class="LootTableDef" '
        f"load_steps={3 + len(entries)} format=3]\n"
        "\n"
        f'[ext_resource type="Script" path="{TABLE_SCRIPT}" id="1_table"]\n'
        f'[ext_resource type="Script" path="{ENTRY_SCRIPT}" id="2_entry"]\n'
        "\n"
        f"{sub_resources}"
        "[resource]\n"
        'script = ExtResource("1_table")\n'
        f"id = {name(table_id)}\n"
        f'display_name = "{display_name}"\n'
        f"realm = {name(realm)}\n"
        f"rarity = {name(rarity)}\n"
        f"rolls = {effective_draws}\n"
        f"allow_empty = {str(allow_empty).lower()}\n"
        f"entries = {listed}\n"
    )


def _tier(resource_id: str, tier: int, realm_id: str, vitality: float, bindings: list[dict]) -> str:
    return (
        f'[sub_resource type="Resource" id="{resource_id}"]\n'
        'script = ExtResource("2_tier")\n'
        f"tier = {tier}\n"
        f'label = "{design.TIER_LABELS[tier]}"\n'
        f"realm = {name(realm_id)}\n"
        f"rarity = {name(design.TIER_RARITY[tier])}\n"
        f"vitality = {float_text(vitality)}\n"
        f"boss_tables = {dictionary_array(bindings)}\n\n"
    )


def encounter(
    encounter: str,
    display_name: str,
    domain_id: str,
    boss_ids: tuple[str, ...],
    realm_id: str,
    ladder: bool,
    bindings: list[dict],
) -> str:
    """A `LootEncounterDef` with one authored band per `design.TIERS` entry.

    Every band binds every boss, because the loot validator reports a band that
    leaves a boss unbound as content that cannot be fought.

    ## `ladder`, not `realm_index`
    `ladder=True` is a LADDER trial, whose `realm_id` is a canonical realm and a claim
    about the fight. `ladder=False` is a WORLD domain, whose `realm_id` is
    `Graph.band_realm`'s derived drop-context LABEL -- the lowest realm any of its drops
    belongs to, which says nothing about the creature's strength (see
    [constant design.WORLD_DOMAIN_FLOOR]). The two must not be priced identically.

    This argument REPLACES the `realm_index` the old signature took, and that is the
    point of ADR 0197: an index is not a ladder position the runtime can resolve, so
    pricing a fight off one mis-scales a retuned ladder and cannot see that a band's
    label under-reports. `RealmPowerTable` is keyed by realm ID.
    """
    tiers = "".join(
        _tier(
            f"tier_{index}",
            tier,
            realm_id,
            design.vitality(realm_id, tier, ladder=ladder),
            bindings,
        )
        for index, tier in enumerate(design.TIERS)
    )
    refs = ",\n".join(f'\tSubResource("tier_{index}")' for index in range(len(design.TIERS)))
    return (
        '[gd_resource type="Resource" script_class="LootEncounterDef" '
        f"load_steps={4 + len(design.TIERS)} format=3]\n"
        "\n"
        f'[ext_resource type="Script" path="{ENCOUNTER_SCRIPT}" id="1_encounter"]\n'
        f'[ext_resource type="Script" path="{TIER_SCRIPT}" id="2_tier"]\n'
        "\n"
        f"{tiers}"
        "[resource]\n"
        'script = ExtResource("1_encounter")\n'
        f"id = {name(encounter)}\n"
        f'display_name = "{display_name}"\n'
        f"domain_id = {name(domain_id)}\n"
        f"boss_ids = {string_array(boss_ids)}\n"
        "key_reach = 0\n"
        f"tiers = Array[LootTier]([\n{refs}\n])\n"
    )
