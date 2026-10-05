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

    A guaranteed entry inside a pool counts **only when the pool itself is
    reached unconditionally**: see [method guaranteed_quantities], which is where
    the enclosing step is checked.
    """
    return set(guaranteed_quantities(graph, table_id, depth))


def guaranteed_quantities(graph: Graph, table_id: str, depth: int = 0) -> dict[str, int]:
    """item id -> the units one resolve of `table_id` yields of it, guaranteed only.

    A resolve pays a guaranteed entry once, at its exact authored quantity, and the
    draw count does not multiply it, so this is a supply figure and not a per-draw
    one.

    **Every enclosing step has to be unconditional, and that is the whole rule.** A
    guaranteed entry inside a pool is unconditional *only if the entry that nests
    that pool is itself guaranteed*. A pool is one weighted candidate among many on
    its parent's table, so a rolled parent leaves the whole subtree to a draw — and
    a cleared band grants no second run (rule E2), so that draw is a permanent miss.
    Walking the nesting edge unconditionally (which this function used to do)
    reported the pool's contents as guaranteed whatever the parent was, which is how
    26 `qi_<realm>_guardian_core` reagents read as safe while their pool usually did
    not drop: the third incident of this class, one level below the two `ddc9229d`
    fixed. It is a narrowing, never a widening: an item already counted is still
    counted whenever every step above it is guaranteed, and one that was only
    reachable through a rolled parent now correctly reads as a roll.

    Descending only through guaranteed nesting entries is also what the runtime does.
    `LootResolver._resolve` pays `guaranteed_entries()` first and unconditionally,
    and `weighted_pool` (which excludes guaranteed entries) is what the draw range
    chooses from — so a guaranteed nested entry resolves on every resolve, exactly
    as this walk now reports, and `LootValidator` permits it: the only rule on the
    flag is that a guaranteed entry must not declare a chance, and a nested entry
    carries the `NO_CHANCE` sentinel.
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
            # The enclosing step. A rolled nesting entry is a draw, so nothing the
            # pool holds is unconditional — however the pool's own entries read.
            if "guaranteed = true" not in chunk:
                continue
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
