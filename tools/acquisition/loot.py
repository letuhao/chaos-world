"""Read the two facts a generated loot table has to get right.

`tools/data.py`'s loot-table schema records what a table can *produce* (its item
ids and the tables it nests), which is exactly what the content gate checks. It
does not record which entry is `guaranteed`, because nothing in `data audit`
needs that; the acquisition contract does, so it is read here from the authored
text rather than by widening another tool's schema for one caller.
"""

from __future__ import annotations

from .chain import Graph, scalar, sub_resources

# `LootContent.MAX_NESTING_DEPTH`, mirrored so a reader of this module sees the
# same ceiling the resolver enforces. It bounds the walks below, so a cyclic
# table terminates instead of recursing until the guard gives up.
MAX_NESTING_DEPTH = 4


def reachable_items(graph: Graph, table_id: str, depth: int = 0) -> set[str]:
    """Every item `table_id` can produce, nested tables included."""
    if depth > MAX_NESTING_DEPTH:
        return set()
    table = graph.loot_tables.get(table_id)
    if table is None:
        return set()
    found = set(table.get("entries", ()))
    for nested in table.get("nested", ()):
        found |= reachable_items(graph, nested, depth + 1)
    return found


def guaranteed_items(graph: Graph, table_id: str, depth: int = 0) -> set[str]:
    """Items `table_id` resolves unconditionally, nested tables included.

    A guaranteed entry inside a pool counts: the pool resolves it once whenever it
    is reached, so it is as unconditional as a direct entry.
    """
    return set(guaranteed_quantities(graph, table_id, depth))


def guaranteed_quantities(graph: Graph, table_id: str, depth: int = 0) -> dict[str, int]:
    """item id -> the units one resolve of `table_id` yields of it, guaranteed only.

    A resolve pays a guaranteed entry once, at its exact authored quantity, and the
    draw count does not multiply it, so this is a supply figure and not a per-draw
    one. Nested tables count under the same reading as [method guaranteed_items].

    A nested entry is followed whether or not **it** is flagged `guaranteed`, and
    that distinction is the whole fix: a nested entry cannot meaningfully be one —
    `LootValidator` rejects a guaranteed entry that declares a chance, and a nested
    table is resolved by its own resolver rather than by the parent's — so every
    pool entry in a generated boss table reads `guaranteed = false` while the
    *guaranteed items inside that pool* are what the trial depends on. Skipping
    non-guaranteed entries before asking whether they are nested therefore reported
    every pooled catalyst as a roll, and a qi realm's breakthrough reagent with it.
    """
    if depth > MAX_NESTING_DEPTH:
        return {}
    record = graph.loot_tables.get(table_id)
    if record is None:
        return {}
    out: dict[str, int] = {}
    for chunk in sub_resources(graph.read(record)):
        nested = scalar(chunk, "table_id")
        if nested:
            for item_id, count in guaranteed_quantities(graph, nested, depth + 1).items():
                out[item_id] = out.get(item_id, 0) + count
            continue
        if "guaranteed = true" not in chunk:
            continue
        item = scalar(chunk, "item_id")
        if item:
            out[item] = out.get(item, 0) + _quantity(chunk)
    return out


def _quantity(chunk: str) -> int:
    """A `LootEntry.quantity`, defaulting to 1 the way the entry itself does."""
    raw = scalar(chunk, "quantity")
    if not raw:
        return 1
    return max(1, int(float(raw)))
